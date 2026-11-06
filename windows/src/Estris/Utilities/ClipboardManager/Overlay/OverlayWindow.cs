using System.Runtime.InteropServices;
using Estris.Core;
using Estris.Ui;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using static Estris.Core.Native;

namespace Estris.Utilities.ClipboardManager.Overlay;

/// What's under a point of the overlay.
internal enum OverlayHit { Nothing, Card, Trash }

/// The dim over a whole screen: a plain black window at a set transparency that clicks go through.
/// The system composes it over what's on screen in every frame, so a video keeps playing under it.
internal sealed partial class DimWindow
{
    private const uint WS_POPUP = 0x80000000, LWA_ALPHA = 2;
    private const int BLACK_BRUSH = 4, SW_HIDE = 0;
    private const string ClassName = "EstrisDim";

    private delegate nint WndProc(nint hwnd, uint message, nint wParam, nint lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WNDCLASS
    {
        public uint style;
        public WndProc lpfnWndProc;
        public int cbClsExtra, cbWndExtra;
        public nint hInstance, hIcon, hCursor, hbrBackground;
        public string? lpszMenuName;
        public string lpszClassName;
    }

    private readonly WndProc proc = DefWindowProc;
    private readonly nint window;

    public DimWindow()
    {
        var instance = GetModuleHandle(null);
        var cls = new WNDCLASS { lpfnWndProc = proc, hInstance = instance, hbrBackground = GetStockObject(BLACK_BRUSH), lpszClassName = ClassName };
        RegisterClass(ref cls);
        window = CreateWindowEx((uint)(WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE), ClassName, "", WS_POPUP, 0, 0, 0, 0, 0, 0, instance, 0);
    }

    public void Show(RECT screen)
    {
        SetAlpha(0);
        SetWindowPos(window, HWND_TOPMOST, screen.Left, screen.Top, screen.Width, screen.Height, SWP_NOACTIVATE | SWP_SHOWWINDOW);
    }

    public void SetAlpha(byte alpha) => SetLayeredWindowAttributes(window, 0, alpha, LWA_ALPHA);

    public void Hide() => ShowWindow(window, SW_HIDE);

    [DllImport("user32", CharSet = CharSet.Unicode)] private static extern ushort RegisterClass(ref WNDCLASS wc);
    [DllImport("user32", CharSet = CharSet.Unicode)] private static extern nint CreateWindowEx(uint ex, string cls, string title, uint style, int x, int y, int w, int h, nint parent, nint menu, nint instance, nint param);
    [DllImport("user32", CharSet = CharSet.Unicode)] private static extern nint DefWindowProc(nint hwnd, uint message, nint wParam, nint lParam);
    [DllImport("gdi32")] private static extern nint GetStockObject(int item);
    [DllImport("user32")] private static extern bool ShowWindow(nint hwnd, int command);
}

/// A window of real Acrylic holding one surface, blurring what's behind it live. It fades through
/// the window's own transparency, as the blur belongs to the window and not to what's in it.
internal sealed class OverlayPanel : FrostWindow
{
    private const uint LWA_ALPHA = 2;
    /// Windows's own minimum would otherwise widen a small panel.
    private const int SmallestSize = 1;

    public FrostBackdrop Backdrop { get; }
    private (int X, int Y, int Width, int Height) placed;

    public OverlayPanel(UIElement content) : this(content, new FrostBackdrop()) { }

    private OverlayPanel(UIElement content, FrostBackdrop backdrop) : base(takesFocus: false, backdrop)
    {
        Backdrop = backdrop;
        Content = content;
        var presenter = (OverlappedPresenter)AppWindow.Presenter;
        presenter.PreferredMinimumWidth = SmallestSize;
        presenter.PreferredMinimumHeight = SmallestSize;
        SetWindowLongPtr(Hwnd, GWL_EXSTYLE, GetWindowLongPtr(Hwnd, GWL_EXSTYLE) | WS_EX_LAYERED);
        SetAlpha(0);
    }

    public void SetAlpha(byte alpha) => SetLayeredWindowAttributes(Hwnd, 0, alpha, LWA_ALPHA);

    /// Only when something changed, as stepping through entries calls this for each one.
    public void Place(int x, int y, int width, int height)
    {
        if (placed == (x, y, width, height)) return;
        placed = (x, y, width, height);
        PlaceContentAt(x, y, width, height);
    }

    public void Forget() => placed = default;
}

/// The overlay, on the screen with the pointer and never activated: the dim, then the card and the
/// "2 of 12" over it as windows of their own. All of it is live, nothing is a picture of the screen.
internal sealed class OverlayWindow
{
    private const double PillGap = 12;
    /// A window shows what it last drew until it draws again: wait this many frames.
    private const int FramesToDraw = 2;
    private const float FrostOpacity = 0.45f;
    private const byte Opaque = 255;
    private static readonly TimeSpan FadeStep = TimeSpan.FromMilliseconds(16);

    private readonly AppearanceSettings appearance;
    private readonly SurfaceLook look;
    private readonly ClipCard card;
    private readonly PositionPill pill;
    private readonly OverlayPanel cardPanel, pillPanel;
    private readonly DimWindow dim = new();
    private readonly DispatcherQueueTimer fadeTimer;
    private RECT bounds;
    private double usualHeight, opacity, target;
    private int framesLeft;
    private bool isRendering, isWarming, isOnScreen, showsPill;

    public OverlayWindow(AppearanceSettings appearance)
    {
        this.appearance = appearance;
        look = new SurfaceLook(appearance, isOverAcrylic: true);
        card = new ClipCard(look, CardMetrics.Entry, fitsImageInside: false);
        pill = new PositionPill(look);
        cardPanel = new OverlayPanel(card);
        pillPanel = new OverlayPanel(pill);

        fadeTimer = App.Ui.CreateTimer();
        fadeTimer.Interval = FadeStep;
        fadeTimer.Tick += (_, _) => StepFade();
        appearance.BackdropDim.Changed += () => { if (isOnScreen) ApplyOpacity(); };
    }

    /// Draws once, unseen, so the first real open doesn't pay for setting everything up.
    public void Warm()
    {
        if (isOnScreen) return;
        isWarming = true;
        Reveal();
    }

    /// Shows the entry under the pill's "2 of 12". position is null when there's nothing to show.
    public void ShowEntry(ClipItem? item, string? position, double width, double height, bool showsDate, bool showsDelete)
    {
        card.ShowCorner(showsDate, showsDelete);
        card.Show(item, width, height);
        usualHeight = height;
        showsPill = position is not null;
        if (position is not null) pill.Text = position;
        if (isOnScreen) Place();
    }

    /// Opens on the pointer's screen. While it is still fading out, it just fades back in.
    public void Present()
    {
        isWarming = false;
        if (isOnScreen && !isRendering)
        {
            FadeTo(1);
            return;
        }
        Reveal();
    }

    private void Reveal()
    {
        (bounds, _) = FrostWindow.ScreenUnderPointer();
        look.ApplyTheme();
        cardPanel.Backdrop.Update(look.BaseColor, FrostOpacity);
        pillPanel.Backdrop.Update(look.BaseColor, FrostOpacity);
        opacity = 0;
        isOnScreen = true;
        if (!isWarming) dim.Show(bounds);
        ApplyOpacity();
        Place();
        cardPanel.AppWindow.Show(false);
        if (showsPill) pillPanel.AppWindow.Show(false);
        framesLeft = FramesToDraw;
        Render(true);
    }

    /// The card centred with the pill above it. Measured at the usual height: a card that grows
    /// for an image grows downward only.
    private void Place()
    {
        var scale = cardPanel.Scale;
        var width = (int)Math.Ceiling(card.Width * scale);
        var height = (int)Math.Ceiling(card.Height * scale);
        var pillHeight = (int)Math.Ceiling(PositionPill.PillHeight * scale);
        var gap = (int)Math.Ceiling(PillGap * scale);
        var left = bounds.Left + (bounds.Width - width) / 2;
        var top = bounds.Top + (bounds.Height - pillHeight - gap - (int)Math.Ceiling(usualHeight * scale)) / 2;
        cardPanel.Place(left, top + pillHeight + gap, width, height);

        pill.Measure(new Windows.Foundation.Size(double.PositiveInfinity, double.PositiveInfinity));
        var pillWidth = (int)Math.Ceiling(Math.Max(pill.DesiredSize.Width, PositionPill.PillHeight) * scale);
        pillPanel.Place(left + (width - pillWidth) / 2, top, pillWidth, pillHeight);
        if (showsPill) pillPanel.AppWindow.Show(false);
        else pillPanel.Hide();
    }

    public void Dismiss()
    {
        if (isOnScreen) FadeTo(0);
    }

    /// What's at a point in screen pixels. Null when it isn't on the overlay's screen.
    public OverlayHit? HitTest(int x, int y)
    {
        if (x < bounds.Left || x >= bounds.Right || y < bounds.Top || y >= bounds.Bottom) return null;
        var origin = new POINT();
        ClientToScreen(cardPanel.Hwnd, ref origin);
        var scale = cardPanel.Scale;
        var point = new Windows.Foundation.Point((x - origin.X) / scale, (y - origin.Y) / scale);
        if (point.X < 0 || point.Y < 0 || point.X >= card.ActualWidth || point.Y >= card.ActualHeight) return OverlayHit.Nothing;
        return VisualTreeHelper.FindElementsInHostCoordinates(point, card).Contains(card.Trash) ? OverlayHit.Trash : OverlayHit.Card;
    }

    /// Highlights what the pointer is over.
    public void ShowHover(OverlayHit? hit)
    {
        card.State = hit is OverlayHit.Card or OverlayHit.Trash ? SurfaceState.Hovered : SurfaceState.Normal;
        card.IsTrashHovered = hit == OverlayHit.Trash;
    }

    private void FadeTo(double value)
    {
        target = value;
        if (Motion.IsReduced) opacity = value;
        fadeTimer.Start();
        StepFade();
    }

    private void StepFade()
    {
        var step = FadeStep / Motion.Fade;
        opacity = opacity < target ? Math.Min(opacity + step, target) : Math.Max(opacity - step, target);
        ApplyOpacity();
        if (opacity != target) return;
        fadeTimer.Stop();
        if (target == 0) LeaveScreen();
    }

    private void ApplyOpacity()
    {
        var alpha = (byte)Math.Round(Opaque * opacity);
        cardPanel.SetAlpha(alpha);
        pillPanel.SetAlpha(alpha);
        dim.SetAlpha((byte)Math.Round(Opaque * opacity * appearance.BackdropDim.Value));
    }

    private void LeaveScreen()
    {
        isOnScreen = false;
        cardPanel.Hide();
        pillPanel.Hide();
        dim.Hide();
    }

    private void Render(bool isOn)
    {
        if (isOn == isRendering) return;
        isRendering = isOn;
        if (isOn) CompositionTarget.Rendering += OnRendering;
        else CompositionTarget.Rendering -= OnRendering;
    }

    /// Waits for the panels to have drawn, then fades in; a warm-up just leaves. They are placed
    /// again here, as a panel can only measure itself once it has shown.
    private void OnRendering(object? sender, object e)
    {
        if (--framesLeft > 0) return;
        Render(false);
        Place();
        if (isWarming) LeaveScreen();
        else FadeTo(1);
    }
}
