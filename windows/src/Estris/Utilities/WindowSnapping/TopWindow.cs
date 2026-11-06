using System.Runtime.InteropServices;
using static Estris.Core.Native;
using static Estris.Utilities.WindowSnapping.WindowNative;

namespace Estris.Utilities.WindowSnapping;

/// A screen, in physical pixels like everything here. Scale is how many pixels a logical pixel
/// (the Mac's point) takes on it.
public sealed record Screen(RECT Bounds, RECT Work, double Scale)
{
    private const int MDT_EFFECTIVE_DPI = 0;

    public static List<Screen> All()
    {
        var screens = new List<Screen>();
        EnumDisplayMonitors(0, 0, (monitor, _, _, _) =>
        {
            screens.Add(From(monitor));
            return true;
        }, 0);
        return screens;
    }

    /// The screen a point is on, or the nearest one.
    public static Screen At(POINT point) => From(MonitorFromPoint(point, MONITOR_DEFAULTTONEAREST));

    /// The screen showing most of a frame.
    public static Screen Of(RECT frame) =>
        All().MaxBy(screen => Rects.Area(Rects.Intersection(screen.Bounds, frame))) ?? At(new POINT { X = frame.Left, Y = frame.Top });

    private static Screen From(nint monitor)
    {
        var info = new MONITORINFO { cbSize = Marshal.SizeOf<MONITORINFO>() };
        GetMonitorInfo(monitor, ref info);
        return new Screen(info.rcMonitor, info.rcWork, ScaleOf(monitor));
    }

    public static double ScaleOf(nint monitor) =>
        GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, out var dpi, out _) == 0 ? dpi / 96.0 : 1;
}

/// Sums on frames, which are RECTs in screen pixels.
public static class Rects
{
    public static RECT Rect(int x, int y, int width, int height) => new() { Left = x, Top = y, Right = x + width, Bottom = y + height };

    public static RECT Intersection(RECT a, RECT b)
    {
        var left = Math.Max(a.Left, b.Left);
        var top = Math.Max(a.Top, b.Top);
        return new RECT { Left = left, Top = top, Right = Math.Max(left, Math.Min(a.Right, b.Right)), Bottom = Math.Max(top, Math.Min(a.Bottom, b.Bottom)) };
    }

    public static long Area(RECT rect) => (long)rect.Width * rect.Height;

    public static bool Contains(RECT rect, double x, double y) => x >= rect.Left && x < rect.Right && y >= rect.Top && y < rect.Bottom;

    public static bool Near(RECT a, RECT b, int tolerance = 2) =>
        Math.Abs(a.Left - b.Left) < tolerance && Math.Abs(a.Top - b.Top) < tolerance
        && Math.Abs(a.Right - b.Right) < tolerance && Math.Abs(a.Bottom - b.Bottom) < tolerance;

    /// Whether more than half of a frame is on a screen.
    public static bool IsMostlyOn(RECT frame, Screen screen) =>
        Area(Intersection(frame, screen.Bounds)) * 2 > Area(frame);
}

/// A top-level window of any app. Frames are the visible ones from the DWM, so they leave out
/// the invisible resize borders and snapped windows truly touch; all in physical pixels.
public readonly record struct TopWindow(nint Hwnd)
{
    /// Smallest size, in logical pixels, of a window that counts.
    private const int MinimumWidth = 100, MinimumHeight = 60;
    /// A busy app's window can answer later; a window moved to a screen with another DPI
    /// resizes itself, and needs asking again.
    private const int SetFrameAttempts = 3;
    private const uint MoveFlags = SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOOWNERZORDER;

    /// The surfaces of the shell: never windows to act on.
    private static readonly HashSet<string> ShellClasses =
    [
        "Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd", "Windows.UI.Core.CoreWindow",
        "XamlExplorerHostIslandWindow", "TaskListThumbnailWnd", "TopLevelWindowForOverflowXamlIsland",
        "NotifyIconOverflowWindow", "Shell_InputSwitchTopLevelWindow", "ForegroundStaging", "MultitaskingViewFrame",
    ];

    public static TopWindow Foreground => new(GetForegroundWindow());

    /// Every top-level window, front to back.
    public static List<TopWindow> All()
    {
        var windows = new List<TopWindow>();
        EnumWindows((hwnd, _) =>
        {
            windows.Add(new TopWindow(hwnd));
            return true;
        }, 0);
        return windows;
    }

    public bool Exists => Hwnd != 0 && IsWindow(Hwnd);
    public long Style => GetWindowLongPtr(Hwnd, GWL_STYLE);
    public long ExStyle => GetWindowLongPtr(Hwnd, GWL_EXSTYLE);
    public bool IsVisible => IsWindowVisible(Hwnd);
    public bool IsMinimized => IsIconic(Hwnd);
    public bool IsMaximized => IsZoomed(Hwnd);
    public bool IsTopmost => (ExStyle & WS_EX_TOPMOST) != 0;
    public bool IsResizable => (Style & WS_THICKFRAME) != 0;
    public bool IsOwned => GetWindow(Hwnd, GW_OWNER) != 0;
    public string ClassName => WindowNative.ClassName(Hwnd);

    public uint ProcessId
    {
        get
        {
            GetWindowThreadProcessId(Hwnd, out var process);
            return process;
        }
    }

    public uint ThreadId => GetWindowThreadProcessId(Hwnd, out _);

    /// Why the DWM doesn't draw it: 0 when it does; not 0 on another virtual desktop, or for a
    /// suspended app's frame.
    public int Cloak => DwmGetWindowAttribute(Hwnd, DWMWA_CLOAKED, out int value, sizeof(int)) == 0 ? value : 0;

    public bool IsShell => ShellClasses.Contains(ClassName);

    /// Its app runs as administrator and Estris doesn't, so Windows won't let Estris move it.
    public bool IsOutOfReach => !Environment.IsPrivilegedProcess && IsElevated(ProcessId);

    /// An app's own window: not a floating tool or a part of the shell. Has a frame, so
    /// splash screens, overlays and borderless things don't count.
    public bool IsAppWindow
    {
        get
        {
            var exStyle = ExStyle;
            if ((exStyle & WS_EX_TOOLWINDOW) != 0 && (exStyle & WS_EX_APPWINDOW) == 0) return false;
            if ((exStyle & (WS_EX_NOACTIVATE | WS_EX_TRANSPARENT)) != 0) return false;
            var style = Style;
            if ((style & WS_CHILD) != 0) return false;
            if ((style & WS_THICKFRAME) == 0 && (style & WS_CAPTION) != WS_CAPTION) return false;
            return !IsShell;
        }
    }

    /// A normal window on screen, on this desktop, that can be acted on: the Mac's window level
    /// 0. Windows kept in front of everything don't count.
    public bool IsNormal
    {
        get
        {
            if (!Exists || !IsVisible || IsMinimized || IsTopmost || !IsAppWindow || Cloak != 0) return false;
            if (Frame is not { } frame) return false;
            var scale = Screen.ScaleOf(MonitorFromWindow(Hwnd, MONITOR_DEFAULTTONEAREST));
            return frame.Width >= MinimumWidth * scale && frame.Height >= MinimumHeight * scale;
        }
    }

    /// The normal windows that are a window of their own, not a dialog over another.
    public bool IsMain => IsNormal && !IsOwned;

    /// The visible frame.
    public RECT? Frame
    {
        get
        {
            if (DwmGetWindowAttribute(Hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, out RECT frame, Marshal.SizeOf<RECT>()) == 0) return frame;
            return GetWindowRect(Hwnd, out frame) ? frame : null;
        }
    }

    /// How far each side of the window's real rectangle reaches past its visible frame.
    public RECT Borders()
    {
        GetWindowRect(Hwnd, out var outer);
        var visible = Frame ?? outer;
        return new RECT { Left = visible.Left - outer.Left, Top = visible.Top - outer.Top, Right = outer.Right - visible.Right, Bottom = outer.Bottom - visible.Bottom };
    }

    /// Moves it so its visible frame is this one, restoring it first if maximized. Returns
    /// false when it couldn't: elevated windows refuse a normal process, hung ones don't answer.
    /// A window going to a screen with another scale resizes itself for it once there, so it
    /// is always sized a second time then.
    public bool SetFrame(RECT frame, Core.AppLog? log = null, string source = "")
    {
        if (IsHungAppWindow(Hwnd))
        {
            log?.Add(source, $"{ClassName}: not responding, left where it is");
            return false;
        }
        if (IsMinimized || IsMaximized) Restore(frame);
        var flags = MoveFlags | (IsResizable ? 0 : SWP_NOSIZE);
        var changesScale = GetDpiForWindow(Hwnd) != DpiAt(frame);
        var last = Frame;
        for (var attempt = 0; attempt < SetFrameAttempts; attempt++)
        {
            var borders = Borders();
            var moved = SetWindowPosChecked(Hwnd, 0, frame.Left - borders.Left, frame.Top - borders.Top,
                frame.Width + borders.Left + borders.Right, frame.Height + borders.Top + borders.Bottom, flags);
            if (!moved)
            {
                var error = Marshal.GetLastPInvokeError();
                log?.Add(source, error == ERROR_ACCESS_DENIED
                    ? $"{ClassName}: elevated window, left where it is"
                    : $"{ClassName}: can't be moved (error {error})");
                return false;
            }
            var now = Frame;
            if (changesScale && attempt == 0) continue;
            if (now is { } got && (Rects.Near(got, frame) || (last is { } before && Rects.Near(got, before, 1)))) break;
            last = now;
        }
        return true;
    }

    /// For following a drag live: doesn't wait for the window, whose app may be slow.
    public void SetFrameWithoutWaiting(RECT frame, RECT borders) =>
        SetWindowPos(Hwnd, 0, frame.Left - borders.Left, frame.Top - borders.Top,
            frame.Width + borders.Left + borders.Right, frame.Height + borders.Top + borders.Bottom, MoveFlags | SWP_ASYNCWINDOWPOS);

    /// Back to a normal window without activating it, ending up about where it's going next,
    /// and no longer going back to maximized when restored from the taskbar.
    private void Restore(RECT frame)
    {
        var placement = new WINDOWPLACEMENT { length = Marshal.SizeOf<WINDOWPLACEMENT>() };
        if (!GetWindowPlacement(Hwnd, ref placement)) return;
        var borders = Borders();
        var outer = new RECT { Left = frame.Left - borders.Left, Top = frame.Top - borders.Top, Right = frame.Right + borders.Right, Bottom = frame.Bottom + borders.Bottom };
        placement.showCmd = SW_SHOWNOACTIVATE;
        placement.flags &= ~WPF_RESTORETOMAXIMIZED;
        placement.rcNormalPosition = ToWorkspace(outer);
        SetWindowPlacement(Hwnd, ref placement);
    }

    /// A placement's normal frame is in workspace coordinates: from the corner of its screen's
    /// work area, not of the screen, which differ when the taskbar is at the top or left.
    private static RECT ToWorkspace(RECT rect)
    {
        var info = new MONITORINFO { cbSize = Marshal.SizeOf<MONITORINFO>() };
        GetMonitorInfo(MonitorFromRect(rect, MONITOR_DEFAULTTONEAREST), ref info);
        var x = info.rcWork.Left - info.rcMonitor.Left;
        var y = info.rcWork.Top - info.rcMonitor.Top;
        return new RECT { Left = rect.Left - x, Top = rect.Top - y, Right = rect.Right - x, Bottom = rect.Bottom - y };
    }

    private static uint DpiAt(RECT frame) =>
        GetDpiForMonitor(MonitorFromRect(frame, MONITOR_DEFAULTTONEAREST), 0, out var dpi, out _) == 0 ? dpi : 96;

    public void Maximize() => ShowWindow(Hwnd, SW_MAXIMIZE);
}
