using System.Runtime.InteropServices;
using static Estris.Core.Native;

namespace Estris.Utilities.RoundedCorners;

/// A bare Win32 popup painted with per-pixel alpha, for what must weigh nothing and follow the
/// pointer or sit on every screen: no XAML, only a bitmap handed to Windows. Lives on the UI
/// thread, whose message loop serves it.
internal sealed partial class LayeredWindow : IDisposable
{
    /// Sees a window's messages; true means it was handled and result is the answer.
    public delegate bool MessageHandler(uint message, nint wParam, nint lParam, out nint result);
    /// Paints a surface of premultiplied BGRA pixels, top row first.
    public delegate void Painter(nint pixels, int width, int height);

    public const uint WDA_EXCLUDEFROMCAPTURE = 0x11;
    private const string ClassName = "EstrisLayeredWindow";
    private const uint WS_POPUP = 0x80000000, SW_SHOWNOACTIVATE = 4, ULW_ALPHA = 2, BI_RGB = 0, LWA_ALPHA = 2;
    private const uint SWP_TOPMOST_ONLY = SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE;
    private const int MDT_EFFECTIVE_DPI = 0;

    private static readonly WindowProc Proc = Dispatch;
    private static readonly Dictionary<nint, LayeredWindow> Windows = [];
    private static bool isRegistered;

    private readonly MessageHandler? handler;
    private nint memoryDc, bitmap, previousBitmap, pixels;
    private int surfaceWidth, surfaceHeight;
    private bool isShown;

    public nint Hwnd { get; }

    public LayeredWindow(long extraStyle = 0, MessageHandler? handler = null)
    {
        this.handler = handler;
        Register();
        var style = WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TOPMOST | extraStyle;
        Hwnd = CreateWindowEx((uint)style, ClassName, "", WS_POPUP, 0, 0, 0, 0, 0, 0, GetModuleHandle(null), 0);
        if (Hwnd == 0) throw new InvalidOperationException($"CreateWindowEx failed: {Marshal.GetLastPInvokeError()}");
        Windows[Hwnd] = this;
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

    private static nint Dispatch(nint hwnd, uint message, nint wParam, nint lParam)
    {
        if (Windows.TryGetValue(hwnd, out var window) && window.handler is { } handler && handler(message, wParam, lParam, out var result))
            return result;
        return DefWindowProc(hwnd, message, wParam, lParam);
    }

    /// Paints the window and puts it at a place in physical pixels, in one step.
    public void Present(int x, int y, int width, int height, Painter paint)
    {
        if (width != surfaceWidth || height != surfaceHeight) Allocate(width, height);
        paint(pixels, width, height);
        var position = new POINT { X = x, Y = y };
        var size = new SIZE { cx = width, cy = height };
        var source = new POINT();
        var blend = new BLENDFUNCTION { SourceConstantAlpha = 255, AlphaFormat = 1 };
        UpdateLayeredWindow(Hwnd, 0, ref position, ref size, memoryDc, ref source, 0, ref blend, ULW_ALPHA);
        Show();
    }

    /// For a window that only has to exist, not show anything: nearly clear over an area.
    public void Cover(RECT area, byte alpha)
    {
        SetLayeredWindowAttributes(Hwnd, 0, alpha, LWA_ALPHA);
        SetWindowPos(Hwnd, HWND_TOPMOST, area.Left, area.Top, area.Width, area.Height, SWP_NOACTIVATE);
        Show();
    }

    private void Show()
    {
        if (isShown) return;
        isShown = true;
        ShowWindow(Hwnd, SW_SHOWNOACTIVATE);
    }

    public void ExcludeFromCapture() { if (Environment.GetEnvironmentVariable("ESTRIS_SHOW") is null) SetWindowDisplayAffinity(Hwnd, WDA_EXCLUDEFROMCAPTURE); } // TESTONLY

    /// Back above other topmost windows, which the taskbar becomes as soon as it's used.
    public void BringToTop() => SetWindowPos(Hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_TOPMOST_ONLY);

    private void Allocate(int width, int height)
    {
        Release();
        memoryDc = CreateCompatibleDC(0);
        var info = new BITMAPINFOHEADER
        {
            biSize = Marshal.SizeOf<BITMAPINFOHEADER>(),
            biWidth = width,
            biHeight = -height,
            biPlanes = 1,
            biBitCount = 32,
            biCompression = BI_RGB,
        };
        bitmap = CreateDIBSection(0, ref info, 0, out pixels, 0, 0);
        previousBitmap = SelectObject(memoryDc, bitmap);
        surfaceWidth = width;
        surfaceHeight = height;
    }

    private void Release()
    {
        if (memoryDc == 0) return;
        SelectObject(memoryDc, previousBitmap);
        DeleteObject(bitmap);
        DeleteDC(memoryDc);
        memoryDc = 0;
    }

    public void Dispose()
    {
        Windows.Remove(Hwnd);
        DestroyWindow(Hwnd);
        Release();
    }

    /// A screen's dots per inch.
    public static uint Dpi(nint monitor) => GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, out var x, out _) == 0 ? x : 96;

    /// Every screen, as its bounds in physical pixels and dots per inch.
    public static List<(RECT Bounds, uint Dpi)> Screens()
    {
        var screens = new List<(RECT, uint)>();
        EnumDisplayMonitors(0, 0, (monitor, _, _, _) =>
        {
            var info = new MONITORINFO { cbSize = Marshal.SizeOf<MONITORINFO>() };
            if (GetMonitorInfo(monitor, ref info)) screens.Add((info.rcMonitor, Dpi(monitor)));
            return true;
        }, 0);
        return screens;
    }

    private delegate nint WindowProc(nint hwnd, uint message, nint wParam, nint lParam);
    private delegate bool MonitorCallback(nint monitor, nint dc, nint rect, nint data);

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

    [StructLayout(LayoutKind.Sequential)] private struct SIZE { public int cx, cy; }
    [StructLayout(LayoutKind.Sequential)] private struct BLENDFUNCTION { public byte BlendOp, BlendFlags, SourceConstantAlpha, AlphaFormat; }
    [StructLayout(LayoutKind.Sequential)]
    private struct BITMAPINFOHEADER
    {
        public int biSize, biWidth, biHeight;
        public short biPlanes, biBitCount;
        public uint biCompression, biSizeImage;
        public int biXPelsPerMeter, biYPelsPerMeter;
        public uint biClrUsed, biClrImportant;
    }

    [DllImport("user32", CharSet = CharSet.Unicode, EntryPoint = "RegisterClassExW")] private static extern ushort RegisterClassEx(ref WNDCLASSEX windowClass);
    [LibraryImport("user32", EntryPoint = "CreateWindowExW", StringMarshalling = StringMarshalling.Utf16, SetLastError = true)]
    private static partial nint CreateWindowEx(uint exStyle, string className, string title, uint style, int x, int y, int width, int height, nint parent, nint menu, nint instance, nint param);
    [LibraryImport("user32", EntryPoint = "DefWindowProcW")] private static partial nint DefWindowProc(nint hwnd, uint message, nint wParam, nint lParam);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool DestroyWindow(nint hwnd);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool ShowWindow(nint hwnd, uint command);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool SetWindowDisplayAffinity(nint hwnd, uint affinity);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool SetLayeredWindowAttributes(nint hwnd, uint key, byte alpha, uint flags);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool UpdateLayeredWindow(nint hwnd, nint screenDc, ref POINT position, ref SIZE size, nint sourceDc, ref POINT sourcePosition, uint key, ref BLENDFUNCTION blend, uint flags);
    [DllImport("user32")] private static extern bool EnumDisplayMonitors(nint dc, nint clip, MonitorCallback callback, nint data);
    [LibraryImport("shcore")] private static partial int GetDpiForMonitor(nint monitor, int type, out uint x, out uint y);
    [LibraryImport("gdi32")] private static partial nint CreateCompatibleDC(nint dc);
    [LibraryImport("gdi32")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool DeleteDC(nint dc);
    [LibraryImport("gdi32")] private static partial nint SelectObject(nint dc, nint item);
    [LibraryImport("gdi32")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool DeleteObject(nint item);
    [LibraryImport("gdi32")] private static partial nint CreateDIBSection(nint dc, ref BITMAPINFOHEADER info, uint usage, out nint bits, nint section, uint offset);
}
