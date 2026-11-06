using System.Diagnostics;
using System.Runtime.InteropServices;
using Estris.Ui;
using Microsoft.UI;
using Microsoft.UI.Composition;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI;
using Windows.UI.ViewManagement;
using static Estris.Core.Native;
using static Estris.Utilities.WindowSnapping.WindowNative;

namespace Estris.Utilities.WindowSnapping;

/// The outline showing where a dragged window will snap: rounded like a window, with a dark
/// see-through fill, or frosted like the Clipboard's overlay when chosen in Settings. It sits
/// just behind the dragged window, grows out of the screen edge or corner being dragged to, and
/// glides between areas as the pointer moves; with animations off in Windows, it just appears.
public sealed partial class SnapPreview
{
    /// Room between the outline and the area, so it reads as a preview of it, in logical pixels.
    private const double Inset = 6;
    private const double Duration = 0.18;
    private static readonly TimeSpan FrameInterval = TimeSpan.FromMilliseconds(8);

    private OutlineWindow? window;
    private bool isFrosted;
    private DispatcherQueueTimer? timer;
    private readonly Stopwatch clock = new();
    private RECT from, to, current;
    private nint below;
    private bool isShown;

    /// Shows the outline over area, growing from edge if it isn't showing yet, just behind
    /// the dragged window.
    public void Show(RECT area, SnapEdge edge, TopWindow behind, bool frosted, double scale)
    {
        var inset = (int)(Inset * scale);
        var target = new RECT { Left = area.Left + inset, Top = area.Top + inset, Right = area.Right - inset, Bottom = area.Bottom - inset };
        if (isShown && target.Equals(to)) return;
        below = behind.Hwnd;
        var animates = new UISettings().AnimationsEnabled;
        if (!isShown)
        {
            if (window is null || isFrosted != frosted)
            {
                window?.Close();
                window = new OutlineWindow(frosted);
                isFrosted = frosted;
            }
            current = animates ? edge.StartRect(target) : target;
            isShown = true;
            window.ShowBehind(below, current);
        }
        from = current;
        to = target;
        clock.Restart();
        if (timer is null)
        {
            timer = App.Ui.CreateTimer();
            timer.Interval = FrameInterval;
            timer.Tick += (_, _) => Step();
        }
        if (animates) timer.Start();
        else
        {
            from = target;
            Step();
        }
    }

    public void Hide()
    {
        if (!isShown) return;
        isShown = false;
        timer?.Stop();
        window?.Hide();
    }

    private void Step()
    {
        var progress = Math.Min(clock.Elapsed.TotalSeconds / Duration, 1);
        var eased = 1 - Math.Pow(1 - progress, 3);
        int Mix(int a, int b) => (int)Math.Round(a + (b - a) * eased);
        current = new RECT { Left = Mix(from.Left, to.Left), Top = Mix(from.Top, to.Top), Right = Mix(from.Right, to.Right), Bottom = Mix(from.Bottom, to.Bottom) };
        window?.Place(below, current);
        if (progress >= 1) timer?.Stop();
    }

    /// The window itself. Dark, it is the window's own see-through pixels with a border drawn in
    /// them; frosted, it is the system's acrylic with its own rounded corners and shadow.
    private sealed partial class OutlineWindow : FrostWindow
    {
        [LibraryImport("dwmapi")] private static partial int DwmSetWindowAttribute(nint hwnd, int attribute, ref uint value, int size);

        private const uint PlaceFlags = SWP_NOACTIVATE | SWP_SHOWWINDOW;
        private const double WindowCornerRadius = 8;
        private const double BorderWidth = 2;
        private const int DWMWA_BORDER_COLOR = 34;
        private const long WS_DLGFRAME = 0x400000;
        private const uint DWMWA_COLOR_NONE = 0xFFFFFFFE;
        private static readonly Color DarkFill = Color.FromArgb(77, 0, 0, 0);
        private static readonly Color DarkBorder = Color.FromArgb(77, 255, 255, 255);

        private readonly bool isFrosted;

        public OutlineWindow(bool frosted) : base(takesFocus: false, frosted ? FrostedBackdrop() : null, isAlwaysOnTop: false)
        {
            isFrosted = frosted;
            if (frosted)
            {
                Content = new Grid();
                return;
            }
            ((OverlappedPresenter)AppWindow.Presenter).SetBorderAndTitleBar(false, false);
            var noColor = DWMWA_COLOR_NONE;
            DwmSetWindowAttribute(Hwnd, DWMWA_BORDER_COLOR, ref noColor, sizeof(uint));
            SystemBackdrop = new ClearBackdrop();
            Content = new Border
            {
                Background = new SolidColorBrush(DarkFill),
                BorderBrush = new SolidColorBrush(DarkBorder),
                BorderThickness = new Thickness(BorderWidth),
                CornerRadius = new CornerRadius(WindowCornerRadius),
            };
        }

        /// The Clipboard overlay's default look, in a lighter blur.
        private static FrostBackdrop FrostedBackdrop() => new()
        {
            Tint = Color.FromArgb(255, 128, 128, 128),
            TintOpacity = 0.2f,
            LuminosityOpacity = 0.5f,
            Kind = DesktopAcrylicKind.Thin,
        };

        public void ShowBehind(nint window, RECT frame)
        {
            Place(window, frame);
            AppWindow.Show(false);
            // WinUI gives a borderless window a thin dialog frame, which would show around the
            // drawn outline.
            if (!isFrosted) SetWindowLongPtr(Hwnd, GWL_STYLE, GetWindowLongPtr(Hwnd, GWL_STYLE) & ~WS_DLGFRAME);
            SetWindowPos(Hwnd, window, frame.Left, frame.Top, frame.Width, frame.Height, PlaceFlags | SWP_FRAMECHANGED);
        }

        public void Place(nint behind, RECT frame) =>
            SetWindowPos(Hwnd, behind, frame.Left, frame.Top, frame.Width, frame.Height, PlaceFlags);
    }

    /// Lets the desktop show through wherever the window's content draws nothing: XAML has no
    /// clear window background of its own, so the DWM is told the whole client area is glass and
    /// the system backdrop's place takes a clear brush.
    private sealed partial class ClearBackdrop : SystemBackdrop
    {
        private const uint DWM_BB_ENABLE = 1, DWM_BB_BLURREGION = 2;

        [StructLayout(LayoutKind.Sequential)]
        private struct DWM_BLURBEHIND
        {
            public uint dwFlags;
            public int fEnable;
            public nint hRgnBlur;
            public int fTransitionOnMaximized;
        }

        [LibraryImport("dwmapi")] private static partial int DwmEnableBlurBehindWindow(nint hwnd, ref DWM_BLURBEHIND blur);
        [LibraryImport("gdi32")] private static partial nint CreateRectRgn(int left, int top, int right, int bottom);
        [LibraryImport("gdi32")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool DeleteObject(nint handle);

        private Windows.UI.Composition.Compositor? compositor;

        protected override void OnTargetConnected(ICompositionSupportsSystemBackdrop target, XamlRoot root)
        {
            base.OnTargetConnected(target, root);
            var hwnd = Win32Interop.GetWindowFromWindowId(root.ContentIslandEnvironment.AppWindowId);
            var nothing = CreateRectRgn(-2, -2, -1, -1);
            var blur = new DWM_BLURBEHIND { dwFlags = DWM_BB_ENABLE | DWM_BB_BLURREGION, fEnable = 1, hRgnBlur = nothing };
            DwmEnableBlurBehindWindow(hwnd, ref blur);
            DeleteObject(nothing);
            compositor ??= new Windows.UI.Composition.Compositor();
            target.SystemBackdrop = compositor.CreateColorBrush(Color.FromArgb(0, 0, 0, 0));
        }

        protected override void OnTargetDisconnected(ICompositionSupportsSystemBackdrop target)
        {
            base.OnTargetDisconnected(target);
            target.SystemBackdrop = null;
            compositor?.Dispose();
            compositor = null;
        }
    }
}
