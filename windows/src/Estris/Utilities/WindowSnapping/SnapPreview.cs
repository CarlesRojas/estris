using System.Numerics;
using System.Runtime.InteropServices;
using Microsoft.Win32;
using Windows.UI;
using Windows.UI.Composition;
using Windows.UI.Composition.Desktop;
using Windows.UI.ViewManagement;
using WinRT;
using static Estris.Core.Native;

namespace Estris.Utilities.WindowSnapping;

/// Where a dragged window will land, drawn like Windows 11's own Snap preview: frosted glass of
/// what's behind, light or dark with the system, rounded like a window, with a soft shadow and
/// no outline, a little in from the screen's edges. It grows out of the dragged window, glides
/// from area to area and shrinks back into the window when the pointer leaves, always just
/// behind it. The compositor runs the animations, in step with the display; with Animation
/// effects off in Windows, it just appears and goes.
public sealed partial class SnapPreview : IDisposable
{
    /// Room between the preview and the screen's edges, in logical pixels.
    private const double EdgeInset = 8;
    private const double CornerRadius = 8;
    private const uint SPI_GETCLIENTAREAANIMATION = 0x1042;

    /// One overlay per screen, kept for the next drag.
    private readonly Dictionary<RECT, Overlay> overlays = [];
    private Compositor? compositor;
    private Overlay? shown;
    private RECT target;

    /// Shows the preview over an area of a screen, just behind the dragged window.
    public void Show(RECT area, Screen screen, TopWindow window)
    {
        var frame = Inset(area, screen);
        if (shown is { } current && current.Work.Equals(screen.Work) && frame.Equals(target)) return;
        target = frame;
        if (shown is { } other && !other.Work.Equals(screen.Work)) other.Hide(window.Frame, Animates);
        compositor ??= new Compositor();
        if (!overlays.TryGetValue(screen.Work, out var overlay))
            overlay = overlays[screen.Work] = new Overlay(compositor, screen.Work);
        overlay.Show(frame, window, screen.Scale, Look.Current(), Animates);
        shown = overlay;
    }

    /// Shrinks the preview back into the dragged window.
    public void Hide(TopWindow window)
    {
        shown?.Hide(window.Frame, Animates);
        shown = null;
    }

    /// Takes the preview away at once, as when the window lands in it.
    public void Close()
    {
        shown?.Hide(null, false);
        shown = null;
    }

    public void Dispose()
    {
        foreach (var overlay in overlays.Values) overlay.Dispose();
        overlays.Clear();
        shown = null;
        compositor?.Dispose();
        compositor = null;
    }

    /// Windows' Animation effects switch: off means no animations.
    private static bool Animates => SystemParametersInfo(SPI_GETCLIENTAREAANIMATION, 0, out var isOn, 0) && isOn;

    /// The area, in from the screen edges it touches; sides next to other areas stay put.
    private static RECT Inset(RECT area, Screen screen)
    {
        var inset = (int)Math.Round(EdgeInset * screen.Scale);
        var work = screen.Work;
        return new RECT
        {
            Left = area.Left + (area.Left <= work.Left ? inset : 0),
            Top = area.Top + (area.Top <= work.Top ? inset : 0),
            Right = area.Right - (area.Right >= work.Right ? inset : 0),
            Bottom = area.Bottom - (area.Bottom >= work.Bottom ? inset : 0),
        };
    }

    /// The colors of Windows' preview in the system's theme, measured from it: a grey over the
    /// blurred backdrop, or solid with transparency effects off.
    private readonly record struct Look(Color Tint, float ShadowOpacity)
    {
        private const string ThemeKey = @"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";
        private static readonly Color LightTint = Color.FromArgb(184, 249, 249, 249), DarkTint = Color.FromArgb(199, 73, 73, 73);
        private static readonly Color LightSolid = Color.FromArgb(255, 237, 237, 237), DarkSolid = Color.FromArgb(255, 64, 64, 64);
        private const float LightShadowOpacity = 0.4f, DarkShadowOpacity = 0.75f;

        public static Look Current()
        {
            var isLight = Registry.GetValue(ThemeKey, "SystemUsesLightTheme", 0) is int value && value != 0;
            var isFrosted = new UISettings().AdvancedEffectsEnabled;
            var tint = isFrosted ? (isLight ? LightTint : DarkTint) : (isLight ? LightSolid : DarkSolid);
            return new Look(tint, isLight ? LightShadowOpacity : DarkShadowOpacity);
        }
    }

    /// A see-through, click-through window over one screen's work area, with the preview drawn
    /// in it by the compositor: a shadow, the blurred backdrop and the tint over it, clipped to
    /// a rounded rectangle whose place and size are animated as one.
    private sealed partial class Overlay : IDisposable
    {
        private const string ClassName = "EstrisSnapPreview";
        private const uint WS_POPUP = 0x80000000, WM_DPICHANGED = 0x2E0, LWA_ALPHA = 2;
        private const long WS_EX_NOREDIRECTIONBITMAP = 0x200000;
        private const int DWMWA_USE_HOSTBACKDROPBRUSH = 17;
        private const uint ShowFlags = SWP_NOACTIVATE | SWP_SHOWWINDOW;
        private const uint SWP_HIDEWINDOW = 0x80;
        private const double ShadowBlur = 60, ShadowDrop = 16;
        /// How far a rounded corner's curve comes in from the edges, as a share of its radius.
        private const float CasterInset = 0.3f;
        private static readonly TimeSpan GrowDuration = TimeSpan.FromMilliseconds(250);
        private static readonly TimeSpan ShrinkDuration = TimeSpan.FromMilliseconds(150);
        private static readonly Guid CompositorDesktopInterop = new("29E691FA-4567-4DCA-B319-D0F207EB6807");

        private static readonly WindowProc Proc = Dispatch;
        private static bool isRegistered;

        private readonly Compositor compositor;
        private readonly nint hwnd;
        private readonly DesktopWindowTarget target;
        private readonly ContainerVisual card;
        private readonly CompositionColorBrush tint;
        private readonly CompositionRoundedRectangleGeometry clipShape;
        private readonly SpriteVisual caster;
        private readonly DropShadow shadow;
        private readonly CompositionEasingFunction grow, shrink;
        /// Counts shows and hides, so a hide that finishes after a new show leaves it alone.
        private int generation;
        private bool isShown;
        /// The window is on screen, possibly still shrinking the preview away.
        private bool isVisible;

        public RECT Work { get; }

        public Overlay(Compositor compositor, RECT work)
        {
            this.compositor = compositor;
            Work = work;
            Register();
            var style = WS_EX_NOREDIRECTIONBITMAP | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED | WS_EX_TRANSPARENT;
            hwnd = CreateWindowEx((uint)style, ClassName, "", WS_POPUP, work.Left, work.Top, work.Width, work.Height, 0, 0, GetModuleHandle(null), 0);
            if (hwnd == 0) throw new InvalidOperationException($"CreateWindowEx failed: {Marshal.GetLastPInvokeError()}");
            SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA);
            // A plain window gets the blurred backdrop only when it asks for it.
            var useBackdrop = 1;
            DwmSetWindowAttribute(hwnd, DWMWA_USE_HOSTBACKDROPBRUSH, ref useBackdrop, sizeof(int));
            target = CreateTarget(compositor, hwnd);

            grow = compositor.CreateCubicBezierEasingFunction(new Vector2(0, 0), new Vector2(0, 1));
            shrink = compositor.CreateCubicBezierEasingFunction(new Vector2(0.7f, 0), new Vector2(1, 0.5f));
            card = compositor.CreateContainerVisual();
            target.Root = card;

            // The shadow comes from a plain rectangle under the glass, in from the edges just
            // enough to stay inside the rounded corners.
            shadow = compositor.CreateDropShadow();
            shadow.Color = Color.FromArgb(255, 0, 0, 0);
            caster = compositor.CreateSpriteVisual();
            caster.Brush = compositor.CreateColorBrush(Color.FromArgb(255, 0, 0, 0));
            caster.RelativeSizeAdjustment = Vector2.One;
            caster.Shadow = shadow;
            card.Children.InsertAtTop(caster);

            clipShape = compositor.CreateRoundedRectangleGeometry();
            var frost = compositor.CreateSpriteVisual();
            frost.RelativeSizeAdjustment = Vector2.One;
            frost.Brush = compositor.CreateHostBackdropBrush();
            frost.Clip = compositor.CreateGeometricClip(clipShape);
            tint = compositor.CreateColorBrush();
            var tinted = compositor.CreateSpriteVisual();
            tinted.RelativeSizeAdjustment = Vector2.One;
            tinted.Brush = tint;
            frost.Children.InsertAtTop(tinted);
            card.Children.InsertAtTop(frost);

            var follow = compositor.CreateExpressionAnimation("card.Size");
            follow.SetReferenceParameter("card", card);
            clipShape.StartAnimation("Size", follow);
        }

        /// Shows the preview at a frame in screen pixels, just behind the window: grown out of
        /// the window if it wasn't showing, glided there if it was.
        public void Show(RECT frame, TopWindow window, double scale, Look look, bool animates)
        {
            generation++;
            var radius = (float)(CornerRadius * scale);
            clipShape.CornerRadius = new Vector2(radius);
            var inset = radius * CasterInset;
            caster.Offset = new Vector3(inset, inset, 0);
            caster.Size = new Vector2(-2 * inset);
            shadow.BlurRadius = (float)(ShadowBlur * scale);
            shadow.Offset = new Vector3(0, (float)(ShadowDrop * scale), 0);
            shadow.Opacity = look.ShadowOpacity;
            tint.Color = look.Tint;
            // Shown again while shrinking away, it glides back from where it is.
            if (!isVisible) Place(animates && window.Frame is { } from ? from : frame);
            isShown = isVisible = true;
            if (animates) Animate(frame, GrowDuration, grow);
            else Place(frame);
            SetWindowPos(hwnd, window.Hwnd, Work.Left, Work.Top, Work.Width, Work.Height, ShowFlags);
        }

        /// Shrinks the preview into a frame (the dragged window's) and hides it, or hides it at
        /// once.
        public void Hide(RECT? into, bool animates)
        {
            if (!isShown) return;
            isShown = false;
            var hiding = ++generation;
            if (!animates || into is not { } frame)
            {
                HideWindow();
                return;
            }
            var batch = compositor.CreateScopedBatch(CompositionBatchTypes.Animation);
            Animate(frame, ShrinkDuration, shrink);
            batch.End();
            batch.Completed += (_, _) =>
            {
                if (hiding == generation) HideWindow();
            };
        }

        private void HideWindow()
        {
            SetWindowPos(hwnd, 0, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_HIDEWINDOW);
            isVisible = false;
            // Nothing left to flash from the last place when it shows again.
            Place(new RECT());
        }

        private void Place(RECT frame)
        {
            card.StopAnimation("Offset");
            card.StopAnimation("Size");
            card.Offset = new Vector3(frame.Left - Work.Left, frame.Top - Work.Top, 0);
            card.Size = new Vector2(frame.Width, frame.Height);
        }

        /// Moves and sizes the preview to a frame from wherever it is now, even mid-animation.
        private void Animate(RECT frame, TimeSpan duration, CompositionEasingFunction easing)
        {
            var move = compositor.CreateVector3KeyFrameAnimation();
            move.InsertKeyFrame(1, new Vector3(frame.Left - Work.Left, frame.Top - Work.Top, 0), easing);
            move.Duration = duration;
            var size = compositor.CreateVector2KeyFrameAnimation();
            size.InsertKeyFrame(1, new Vector2(frame.Width, frame.Height), easing);
            size.Duration = duration;
            card.StartAnimation("Offset", move);
            card.StartAnimation("Size", size);
        }

        public void Dispose()
        {
            target.Dispose();
            DestroyWindow(hwnd);
        }

        /// The compositor's visuals hosted in a plain window, through its desktop interop.
        private static unsafe DesktopWindowTarget CreateTarget(Compositor compositor, nint hwnd)
        {
            var unknown = ((IWinRTObject)compositor).NativeObject.ThisPtr;
            Marshal.ThrowExceptionForHR(Marshal.QueryInterface(unknown, in CompositorDesktopInterop, out var interop));
            try
            {
                nint result;
                var create = (delegate* unmanaged[Stdcall]<nint, nint, int, nint*, int>)(*(nint**)interop)[3];
                Marshal.ThrowExceptionForHR(create(interop, hwnd, 0, &result));
                try { return DesktopWindowTarget.FromAbi(result); }
                finally { Marshal.Release(result); }
            }
            finally { Marshal.Release(interop); }
        }

        private static void Register()
        {
            if (isRegistered) return;
            isRegistered = true;
            var windowClass = new WNDCLASSEX
            {
                cbSize = Marshal.SizeOf<WNDCLASSEX>(),
                lpfnWndProc = Marshal.GetFunctionPointerForDelegate(Proc),
                hInstance = GetModuleHandle(null),
                lpszClassName = ClassName,
            };
            RegisterClassEx(ref windowClass);
        }

        /// Stays the size of its screen when Windows suggests another for a new scale.
        private static nint Dispatch(nint hwnd, uint message, nint wParam, nint lParam) =>
            message == WM_DPICHANGED ? 0 : DefWindowProc(hwnd, message, wParam, lParam);

        private delegate nint WindowProc(nint hwnd, uint message, nint wParam, nint lParam);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct WNDCLASSEX
        {
            public int cbSize;
            public uint style;
            public nint lpfnWndProc;
            public int cbClsExtra, cbWndExtra;
            public nint hInstance, hIcon, hCursor, hbrBackground;
            public string? lpszMenuName;
            public string lpszClassName;
            public nint hIconSm;
        }

        [DllImport("user32", CharSet = CharSet.Unicode, EntryPoint = "RegisterClassExW")] private static extern ushort RegisterClassEx(ref WNDCLASSEX windowClass);
        [LibraryImport("user32", EntryPoint = "CreateWindowExW", StringMarshalling = StringMarshalling.Utf16, SetLastError = true)]
        private static partial nint CreateWindowEx(uint exStyle, string className, string title, uint style, int x, int y, int width, int height, nint parent, nint menu, nint instance, nint param);
        [LibraryImport("user32", EntryPoint = "DefWindowProcW")] private static partial nint DefWindowProc(nint hwnd, uint message, nint wParam, nint lParam);
        [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool DestroyWindow(nint hwnd);
        [LibraryImport("dwmapi")] private static partial int DwmSetWindowAttribute(nint hwnd, int attribute, ref int value, int size);
        [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool SetLayeredWindowAttributes(nint hwnd, uint key, byte alpha, uint flags);
    }

    [LibraryImport("user32", EntryPoint = "SystemParametersInfoW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool SystemParametersInfo(uint action, uint size, [MarshalAs(UnmanagedType.Bool)] out bool value, uint flags);
}
