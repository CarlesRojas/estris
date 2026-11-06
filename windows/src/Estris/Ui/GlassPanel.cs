using System.Numerics;
using System.Runtime.InteropServices;
using Estris.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Microsoft.Win32;
using Windows.UI;
using Windows.UI.Composition;
using Windows.UI.Composition.Desktop;
using Windows.UI.ViewManagement;
using WinRT;
using static Estris.Core.Native;

namespace Estris.Ui;

/// The glass everything floating is made of, as Windows 11 draws its Snap preview, measured from
/// it: a grey over the blurred backdrop, or solid with transparency effects off.
public readonly record struct GlassLook(Color Tint, float ShadowOpacity)
{
    private const string ThemeKey = @"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";
    private static readonly Color LightTint = Color.FromArgb(184, 249, 249, 249), DarkTint = Color.FromArgb(199, 73, 73, 73);
    private static readonly Color LightSolid = Color.FromArgb(255, 237, 237, 237), DarkSolid = Color.FromArgb(255, 64, 64, 64);
    private const float LightShadowOpacity = 0.4f, DarkShadowOpacity = 0.75f;

    public static GlassLook Current()
    {
        var isLight = Registry.GetValue(ThemeKey, "SystemUsesLightTheme", 0) is int value && value != 0;
        var isFrosted = new UISettings().AdvancedEffectsEnabled;
        var tint = isFrosted ? (isLight ? LightTint : DarkTint) : (isLight ? LightSolid : DarkSolid);
        return new GlassLook(tint, isLight ? LightShadowOpacity : DarkShadowOpacity);
    }
}

/// The system compositor, which is what can blur what's behind a plain window.
public static class GlassCompositor
{
    private static readonly Guid DesktopInterop = new("29E691FA-4567-4DCA-B319-D0F207EB6807");
    private static Windows.UI.Composition.Compositor? shared;

    public static Windows.UI.Composition.Compositor Shared
    {
        get
        {
            if (shared is not null) return shared;
            EnsureDispatcherQueue();
            return shared = new Windows.UI.Composition.Compositor();
        }
    }

    /// It needs the system's own kind of queue on its thread, which WinUI only makes once a window
    /// has opened, and the Clipboard's panels are made before that.
    private static void EnsureDispatcherQueue()
    {
        if (Windows.System.DispatcherQueue.GetForCurrentThread() is not null) return;
        var options = new DispatcherQueueOptions { Size = Marshal.SizeOf<DispatcherQueueOptions>(), ThreadType = DQTYPE_THREAD_CURRENT, ApartmentType = DQTAT_COM_NONE };
        Marshal.ThrowExceptionForHR(CreateDispatcherQueueController(options, out dispatcherQueueController));
    }

    private const int DQTYPE_THREAD_CURRENT = 2, DQTAT_COM_NONE = 0;
    private static nint dispatcherQueueController;

    [StructLayout(LayoutKind.Sequential)]
    private struct DispatcherQueueOptions { public int Size, ThreadType, ApartmentType; }

    [DllImport("CoreMessaging")]
    private static extern int CreateDispatcherQueueController(DispatcherQueueOptions options, out nint controller);

    /// The compositor's visuals hosted in a plain window, through its desktop interop.
    public static unsafe DesktopWindowTarget CreateTarget(Windows.UI.Composition.Compositor compositor, nint hwnd)
    {
        var unknown = ((IWinRTObject)compositor).NativeObject.ThisPtr;
        Marshal.ThrowExceptionForHR(Marshal.QueryInterface(unknown, in DesktopInterop, out var interop));
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
}

/// A shape of glass floating on screen: a see-through, click-through window with a shadow, the
/// blurred backdrop and the tint over it, clipped to a rounded rectangle.
internal sealed partial class GlassLayer
{
    private const string ClassName = "EstrisGlass";
    private const uint WS_POPUP = 0x80000000, LWA_ALPHA = 2, SWP_HIDEWINDOW = 0x80;
    private const long WS_EX_NOREDIRECTIONBITMAP = 0x200000;
    private const int DWMWA_USE_HOSTBACKDROPBRUSH = 17, SHADOW_DROP_SHARE = 3;
    /// How far a rounded corner's curve comes in from the edges, as a share of its radius.
    private const float CasterInset = 0.3f;
    private static readonly WindowProc Proc = DefWindowProc;
    private static bool isRegistered;

    private readonly nint hwnd;
    private readonly DesktopWindowTarget target;
    private readonly ContainerVisual card;
    private readonly CompositionColorBrush tint;
    private readonly CompositionRoundedRectangleGeometry clipShape;
    private readonly SpriteVisual caster;
    private readonly DropShadow shadow;
    private readonly double radius, shadowBlur;

    public GlassLayer(double radius, double shadowBlur)
    {
        this.radius = radius;
        this.shadowBlur = shadowBlur;
        Register();
        var style = WS_EX_NOREDIRECTIONBITMAP | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOPMOST;
        hwnd = CreateWindowEx((uint)style, ClassName, "", WS_POPUP, 0, 0, 0, 0, 0, 0, GetModuleHandle(null), 0);
        if (hwnd == 0) throw new InvalidOperationException($"CreateWindowEx failed: {Marshal.GetLastPInvokeError()}");
        SetLayeredWindowAttributes(hwnd, 0, 0, LWA_ALPHA);
        // A plain window gets the blurred backdrop only when it asks for it.
        var useBackdrop = 1;
        DwmSetWindowAttribute(hwnd, DWMWA_USE_HOSTBACKDROPBRUSH, ref useBackdrop, sizeof(int));

        var compositor = GlassCompositor.Shared;
        target = GlassCompositor.CreateTarget(compositor, hwnd);
        card = compositor.CreateContainerVisual();
        target.Root = card;

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
    }

    public nint Hwnd => hwnd;

    /// Places the glass at a frame in screen pixels, its window reaching out for the shadow.
    public void Place(int x, int y, int width, int height, double scale, GlassLook look)
    {
        var blur = shadowBlur * scale;
        var padding = (int)Math.Ceiling(blur * 1.5);
        var corner = (float)(radius * scale);
        clipShape.CornerRadius = new Vector2(corner);
        clipShape.Size = new Vector2(width, height);
        var inset = corner * CasterInset;
        caster.Offset = new Vector3(inset, inset, 0);
        caster.Size = new Vector2(-2 * inset);
        shadow.BlurRadius = (float)blur;
        shadow.Offset = new Vector3(0, (float)(blur / SHADOW_DROP_SHARE), 0);
        shadow.Opacity = look.ShadowOpacity;
        tint.Color = look.Tint;
        card.Offset = new Vector3(padding, padding, 0);
        card.Size = new Vector2(width, height);
        SetWindowPos(hwnd, HWND_TOPMOST, x - padding, y - padding, width + 2 * padding, height + 2 * padding, SWP_NOACTIVATE);
    }

    public void Show() => SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);

    public void Hide() => SetWindowPos(hwnd, 0, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_HIDEWINDOW);

    public void SetAlpha(byte alpha) => SetLayeredWindowAttributes(hwnd, 0, alpha, LWA_ALPHA);

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
    [LibraryImport("dwmapi")] private static partial int DwmSetWindowAttribute(nint hwnd, int attribute, ref int value, int size);
}

/// Makes a XAML window see-through wherever its content doesn't draw, which no stock backdrop does.
internal sealed partial class ClearBackdrop : SystemBackdrop
{
    private const uint DWM_BB_ENABLE = 1, DWM_BB_BLURREGION = 2, WM_ERASEBKGND = 0x14;

    [StructLayout(LayoutKind.Sequential)]
    private struct DWM_BLURBEHIND { public uint dwFlags; public int fEnable; public nint hRgnBlur; public int fTransitionOnMaximized; }

    [StructLayout(LayoutKind.Sequential)]
    private struct MARGINS { public int Left, Right, Top, Bottom; }

    private delegate nint SubclassProc(nint hwnd, uint message, nint wParam, nint lParam, nuint id, nuint data);

    private static readonly SubclassProc Erase = OnMessage;
    private static readonly nint Black = CreateSolidBrush(0);
    private Windows.UI.Composition.CompositionColorBrush? brush;

    protected override void OnTargetConnected(Microsoft.UI.Composition.ICompositionSupportsSystemBackdrop target, XamlRoot root)
    {
        base.OnTargetConnected(target, root);
        var hwnd = (nint)root.ContentIslandEnvironment.AppWindowId.Value;
        var margins = default(MARGINS);
        DwmExtendFrameIntoClientArea(hwnd, ref margins);
        // A region of nothing: DWM then blends the window with what's behind, blurring none of it.
        var nothing = new DWM_BLURBEHIND { dwFlags = DWM_BB_ENABLE | DWM_BB_BLURREGION, fEnable = 1, hRgnBlur = CreateRectRgn(-2, -2, -1, -1) };
        DwmEnableBlurBehindWindow(hwnd, ref nothing);
        SetWindowSubclass(hwnd, Marshal.GetFunctionPointerForDelegate(Erase), 1, 0);
        brush = GlassCompositor.Shared.CreateColorBrush(Color.FromArgb(0, 0, 0, 0));
        target.SystemBackdrop = brush;
    }

    protected override void OnTargetDisconnected(Microsoft.UI.Composition.ICompositionSupportsSystemBackdrop target)
    {
        base.OnTargetDisconnected(target);
        target.SystemBackdrop = null;
        brush?.Dispose();
        brush = null;
    }

    /// With this kind of window, black is what DWM treats as see-through.
    private static nint OnMessage(nint hwnd, uint message, nint wParam, nint lParam, nuint id, nuint data)
    {
        if (message != WM_ERASEBKGND) return DefSubclassProc(hwnd, message, wParam, lParam);
        if (GetClientRect(hwnd, out var rect)) FillRect(wParam, ref rect, Black);
        return 1;
    }

    [LibraryImport("dwmapi")] private static partial int DwmExtendFrameIntoClientArea(nint hwnd, ref MARGINS margins);
    [LibraryImport("dwmapi")] private static partial int DwmEnableBlurBehindWindow(nint hwnd, ref DWM_BLURBEHIND blur);
    [LibraryImport("gdi32")] private static partial nint CreateRectRgn(int left, int top, int right, int bottom);
    [LibraryImport("gdi32")] private static partial nint CreateSolidBrush(uint color);
    [LibraryImport("user32")] private static partial int FillRect(nint dc, ref RECT rect, nint brush);
    [DllImport("comctl32")] private static extern bool SetWindowSubclass(nint hwnd, nint proc, nuint id, nuint data);
    [LibraryImport("comctl32")] private static partial nint DefSubclassProc(nint hwnd, uint message, nint wParam, nint lParam);
}

/// Something floating on screen over glass: the glass in one window and the content, in XAML, in a
/// see-through one right on top, as glass can't hold XAML and a XAML window's own Acrylic has
/// Windows's corners and a border. Never activated.
public sealed partial class GlassPanel
{
    private const int DWMWA_WINDOW_CORNER_PREFERENCE = 33, DWMWA_BORDER_COLOR = 34;
    private const int DWMWCP_DONOTROUND = 1;
    private const long WS_POPUP = 0x80000000;
    private const uint DWMWA_COLOR_NONE = 0xFFFFFFFE, WDA_EXCLUDEFROMCAPTURE = 0x11;

    private readonly GlassLayer glass;
    private readonly Window window = new();
    private readonly FrameworkElement content;
    private (int X, int Y, int Width, int Height) placed;
    private GlassLook look = GlassLook.Current();

    public nint Hwnd { get; }
    public double Scale => GetDpiForWindow(Hwnd) / 96.0;

    /// A panel is created on the UI thread. clickThrough lets the pointer act on what's behind.
    public GlassPanel(FrameworkElement content, double radius, double shadowBlur, bool clickThrough = false)
    {
        this.content = content;
        glass = new GlassLayer(radius, shadowBlur);
        Hwnd = WinRT.Interop.WindowNative.GetWindowHandle(window);
        window.SystemBackdrop = new ClearBackdrop();
        window.Content = content;

        // Not a presenter's "no border": that keeps the resize frame, which shows as white around
        // the content and cuts into it. A popup has no frame at all.
        window.AppWindow.IsShownInSwitchers = false;
        SetWindowLongPtr(Hwnd, GWL_STYLE, WS_POPUP);
        SetWindowPos(Hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED);

        var noRounding = DWMWCP_DONOTROUND;
        DwmSetWindowAttribute(Hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, ref noRounding, sizeof(int));
        var noBorder = unchecked((int)DWMWA_COLOR_NONE);
        DwmSetWindowAttribute(Hwnd, DWMWA_BORDER_COLOR, ref noBorder, sizeof(int));
        var style = GetWindowLongPtr(Hwnd, GWL_EXSTYLE) | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE;
        if (clickThrough) style |= WS_EX_TRANSPARENT | WS_EX_LAYERED;
        SetWindowLongPtr(Hwnd, GWL_EXSTYLE, style);
        if (clickThrough) SetLayeredWindowAttributes(Hwnd, 0, 255, LWA_ALPHA);
    }

    private const uint LWA_ALPHA = 2;

    /// Keeps it out of screen captures, for when it floats over what's being captured.
    public void ExcludeFromCapture()
    {
        SetWindowDisplayAffinity(Hwnd, WDA_EXCLUDEFROMCAPTURE);
        SetWindowDisplayAffinity(glass.Hwnd, WDA_EXCLUDEFROMCAPTURE);
    }

    /// Picks up a change of Windows's theme or transparency effects.
    public void RefreshLook()
    {
        look = GlassLook.Current();
        placed = default;
    }

    /// Places it in screen pixels, the content exactly over the glass.
    public void Place(int x, int y, int width, int height)
    {
        if (placed == (x, y, width, height)) return;
        placed = (x, y, width, height);
        glass.Place(x, y, width, height, Scale, look);
        SetWindowPos(Hwnd, HWND_TOPMOST, x, y, width, height, SWP_NOACTIVATE);
    }

    public void Show()
    {
        glass.Show();
        window.AppWindow.Show(false);
        SetWindowPos(Hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    }

    public void Hide()
    {
        window.AppWindow.Hide();
        glass.Hide();
    }

    /// Fades the whole panel: the glass through its window, the content through XAML.
    public void SetOpacity(double value)
    {
        glass.SetAlpha((byte)Math.Round(255 * value));
        content.Opacity = value;
    }

    [LibraryImport("dwmapi")] private static partial int DwmSetWindowAttribute(nint hwnd, int attribute, ref int value, int size);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool SetWindowDisplayAffinity(nint hwnd, uint affinity);
}
