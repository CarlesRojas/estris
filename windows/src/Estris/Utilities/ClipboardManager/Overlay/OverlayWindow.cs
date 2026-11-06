using System.Runtime.InteropServices;
using Estris.Core;
using Estris.Ui;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using static Estris.Core.Loc;
using static Estris.Core.Native;

namespace Estris.Utilities.ClipboardManager.Overlay;

/// What's under a point of the overlay.
internal enum OverlayHit { Nothing, Card, Trash }

/// One borderless window over the whole screen with the pointer, never activated: a picture of
/// the screen taken just before it opens, the dim on top, and the frosted card over both, whose
/// blur reads that picture. The dim and the card fade in and out together, on the compositor.
internal sealed partial class OverlayWindow : FrostWindow
{
    private const double PillGap = 12;
    /// A window shows what it last drew until it draws again: stay cloaked for this many frames.
    private const int FramesToDraw = 2;
    private const int DWMWA_WINDOW_CORNER_PREFERENCE = 33, DWMWA_BORDER_COLOR = 34, DWMWA_CLOAK = 13;
    private const int DWMWCP_DONOTROUND = 1;
    private const uint DWMWA_COLOR_NONE = 0xFFFFFFFE;

    private readonly AppearanceSettings appearance;
    private readonly ScreenCapture capture = new();
    private readonly Image backdrop = new() { Stretch = Stretch.Fill, IsHitTestVisible = false };
    private readonly Microsoft.UI.Xaml.Shapes.Rectangle dim = new() { Fill = new SolidColorBrush(Colors.Black), IsHitTestVisible = false };
    private readonly Canvas stage = new() { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
    /// The dim and the stage, which fade as one.
    private readonly Grid layer = new() { Opacity = 0 };
    private readonly Grid pillRow = new();
    private readonly Grid root = new();
    private readonly SurfaceLook look;
    private readonly ClipCard card;
    private readonly PositionPill pill;
    private readonly Microsoft.UI.Dispatching.DispatcherQueueTimer hideTimer;
    private RECT bounds;
    private int framesLeft;
    private bool isRendering, isWarming, isOnScreen;

    public OverlayWindow(AppearanceSettings appearance) : base(takesFocus: false)
    {
        this.appearance = appearance;
        SystemBackdrop = null;
        ((OverlappedPresenter)AppWindow.Presenter).SetBorderAndTitleBar(false, false);
        var noRounding = DWMWCP_DONOTROUND;
        DwmSetWindowAttribute(Hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, ref noRounding, sizeof(int));
        var noBorder = unchecked((int)DWMWA_COLOR_NONE);
        DwmSetWindowAttribute(Hwnd, DWMWA_BORDER_COLOR, ref noBorder, sizeof(int));

        look = new SurfaceLook(appearance);
        card = new ClipCard(look, CardMetrics.Entry, fitsImageInside: false);
        pill = new PositionPill(look);
        pillRow.Children.Add(pill);
        stage.Children.Add(pillRow);
        stage.Children.Add(card);
        dim.Opacity = appearance.BackdropDim.Value;
        appearance.BackdropDim.Changed += () => dim.Opacity = appearance.BackdropDim.Value;
        layer.Children.Add(dim);
        layer.Children.Add(stage);
        root.Children.Add(backdrop);
        root.Children.Add(layer);
        Content = root;

        // Once faded out, it leaves the screen; a show in the meantime stops it.
        hideTimer = App.Ui.CreateTimer();
        hideTimer.IsRepeating = false;
        hideTimer.Tick += (_, _) =>
        {
            isOnScreen = false;
            Hide();
        };
    }

    /// Draws once while cloaked, so the first real open doesn't pay for setting everything up.
    public void Warm()
    {
        if (isOnScreen) return;
        isWarming = true;
        var (screen, _) = ScreenUnderPointer();
        Reveal(screen);
    }

    /// Shows the entry under the pill's "2 of 12". position is null when there's nothing to show.
    public void ShowEntry(ClipItem? item, string? position, double width, double height, bool showsDate, bool showsDelete)
    {
        card.ShowCorner(showsDate, showsDelete);
        card.Show(item, width, height);
        pill.Visibility = position is null ? Visibility.Collapsed : Visibility.Visible;
        if (position is not null) pill.Text = position;
        stage.Width = width;
        stage.Height = PositionPill.PillHeight + PillGap + height;
        pillRow.Width = width;
        // Laid out at the usual height with the top pinned: a card that grows for an image grows
        // downward only.
        Canvas.SetTop(card, PositionPill.PillHeight + PillGap);
    }

    /// Takes the picture of the screen and opens over it. While it is still fading out, the
    /// screen is already showing this window, so it just fades back in.
    public void Present()
    {
        isWarming = false;
        if (isOnScreen && !isRendering)
        {
            FadeTo(1);
            return;
        }
        var (screen, _) = ScreenUnderPointer();
        look.ApplyTheme();
        capture.Take(screen);
        backdrop.Source = capture.Bitmap;
        Reveal(screen);
    }

    private void Reveal(RECT screen)
    {
        bounds = screen;
        SetCloaked(true);
        isOnScreen = true;
        ShowAt(screen.Left, screen.Top, screen.Width, screen.Height);
        framesLeft = FramesToDraw;
        Render(true);
    }

    public void Dismiss()
    {
        if (isOnScreen) FadeTo(0);
    }

    /// Lets go of the screen's picture while nothing shows.
    public void ReleaseCapture()
    {
        if (isOnScreen) return;
        backdrop.Source = null;
        capture.Dispose();
    }

    /// What's at a point in screen pixels. Null when it isn't on the overlay's screen.
    public OverlayHit? HitTest(int x, int y)
    {
        if (x < bounds.Left || x >= bounds.Right || y < bounds.Top || y >= bounds.Bottom) return null;
        var point = new Windows.Foundation.Point((x - bounds.Left) / Scale, (y - bounds.Top) / Scale);
        var result = OverlayHit.Nothing;
        foreach (var element in Microsoft.UI.Xaml.Media.VisualTreeHelper.FindElementsInHostCoordinates(point, root))
        {
            if (element == card.Trash) return OverlayHit.Trash;
            if (element == card) result = OverlayHit.Card;
        }
        return result;
    }

    /// Highlights what the pointer is over.
    public void ShowHover(OverlayHit? hit)
    {
        card.State = hit is OverlayHit.Card or OverlayHit.Trash ? SurfaceState.Hovered : SurfaceState.Normal;
        card.IsTrashHovered = hit == OverlayHit.Trash;
    }

    private void FadeTo(double target)
    {
        hideTimer.Stop();
        layer.OpacityTransition = Motion.OpacityTransition(Motion.Fade);
        layer.Opacity = target;
        if (target > 0) return;
        hideTimer.Interval = layer.OpacityTransition?.Duration ?? TimeSpan.Zero;
        hideTimer.Start();
    }

    private void Render(bool isOn)
    {
        if (isOn == isRendering) return;
        isRendering = isOn;
        if (isOn) CompositionTarget.Rendering += OnRendering;
        else CompositionTarget.Rendering -= OnRendering;
    }

    /// Waits for the window to have drawn, then uncloaks it and fades in; a warm-up just leaves.
    private void OnRendering(object? sender, object e)
    {
        if (--framesLeft > 0) return;
        Render(false);
        if (isWarming)
        {
            isOnScreen = false;
            Hide();
            return;
        }
        SetCloaked(false);
        FadeTo(1);
    }

    private void SetCloaked(bool isCloaked)
    {
        var value = isCloaked ? 1 : 0;
        DwmSetWindowAttribute(Hwnd, DWMWA_CLOAK, ref value, sizeof(int));
    }

    [LibraryImport("dwmapi")]
    private static partial int DwmSetWindowAttribute(nint hwnd, int attribute, ref int value, int size);
}
