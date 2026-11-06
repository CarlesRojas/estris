using System.Runtime.InteropServices;
using System.Text;

namespace Estris.Core;

/// The Win32 calls more than one area uses. Anything only one utility needs stays in its folder.
public static partial class Native
{
    public const int WH_KEYBOARD_LL = 13, WH_MOUSE_LL = 14;
    public const nint WM_KEYDOWN = 0x100, WM_KEYUP = 0x101, WM_SYSKEYDOWN = 0x104, WM_SYSKEYUP = 0x105;
    public const uint WM_QUIT = 0x12;
    public const int WM_MOUSEMOVE = 0x200, WM_LBUTTONDOWN = 0x201, WM_LBUTTONUP = 0x202, WM_RBUTTONDOWN = 0x204, WM_RBUTTONUP = 0x205,
        WM_MBUTTONDOWN = 0x207, WM_MBUTTONUP = 0x208, WM_MOUSEWHEEL = 0x20A, WM_XBUTTONDOWN = 0x20B, WM_XBUTTONUP = 0x20C, WM_MOUSEHWHEEL = 0x20E;
    public const uint LLKHF_EXTENDED = 0x01, LLKHF_INJECTED = 0x10, LLMHF_INJECTED = 0x01;
    public const int GWL_STYLE = -16, GWL_EXSTYLE = -20;
    public const long WS_EX_TOPMOST = 0x8, WS_EX_TRANSPARENT = 0x20, WS_EX_TOOLWINDOW = 0x80, WS_EX_LAYERED = 0x80000, WS_EX_NOACTIVATE = 0x8000000, WS_EX_APPWINDOW = 0x40000;
    public const uint SWP_NOSIZE = 1, SWP_NOMOVE = 2, SWP_NOZORDER = 4, SWP_NOACTIVATE = 0x10, SWP_FRAMECHANGED = 0x20, SWP_SHOWWINDOW = 0x40;
    public const uint MONITOR_DEFAULTTONEAREST = 2;

    public delegate nint HookProc(int code, nint wParam, nint lParam);

    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; public readonly int Width => Right - Left; public readonly int Height => Bottom - Top; }
    [StructLayout(LayoutKind.Sequential)] public struct MSG { public nint hwnd; public uint message; public nint wParam, lParam; public uint time; public POINT pt; }
    [StructLayout(LayoutKind.Sequential)] public struct KBDLLHOOKSTRUCT { public uint vkCode, scanCode, flags, time; public nuint dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] public struct MSLLHOOKSTRUCT { public POINT pt; public uint mouseData, flags, time; public nuint dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] public struct LASTINPUTINFO { public uint cbSize, dwTime; }
    [StructLayout(LayoutKind.Sequential)] public struct MONITORINFO { public int cbSize; public RECT rcMonitor, rcWork; public uint dwFlags; }

    [LibraryImport("user32", EntryPoint = "SetWindowsHookExW")] public static partial nint SetWindowsHookEx(int id, HookProc proc, nint module, uint thread);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool UnhookWindowsHookEx(nint hook);
    [LibraryImport("user32")] public static partial nint CallNextHookEx(nint hook, int code, nint wParam, nint lParam);
    [LibraryImport("kernel32", EntryPoint = "GetModuleHandleW", StringMarshalling = StringMarshalling.Utf16)] public static partial nint GetModuleHandle(string? name);
    [LibraryImport("kernel32")] public static partial uint GetCurrentThreadId();
    [LibraryImport("user32", EntryPoint = "GetMessageW")] public static partial int GetMessage(out MSG message, nint hwnd, uint min, uint max);
    [LibraryImport("user32", EntryPoint = "PeekMessageW")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool PeekMessage(out MSG message, nint hwnd, uint min, uint max, uint remove);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool TranslateMessage(ref MSG message);
    [LibraryImport("user32", EntryPoint = "DispatchMessageW")] public static partial nint DispatchMessage(ref MSG message);
    [LibraryImport("user32", EntryPoint = "PostThreadMessageW")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool PostThreadMessage(uint thread, uint message, nint wParam, nint lParam);

    [LibraryImport("user32")] public static partial nint GetForegroundWindow();
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool SetForegroundWindow(nint hwnd);
    [LibraryImport("user32")] public static partial uint GetWindowThreadProcessId(nint hwnd, out uint process);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool IsWindowVisible(nint hwnd);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool IsIconic(nint hwnd);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool GetCursorPos(out POINT point);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool GetWindowRect(nint hwnd, out RECT rect);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool GetClientRect(nint hwnd, out RECT rect);
    [LibraryImport("user32", EntryPoint = "SetTimer")] public static partial nuint SetThreadTimer(nint hwnd, nuint id, uint milliseconds, nint callback);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool GetLastInputInfo(ref LASTINPUTINFO info);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool ClientToScreen(nint hwnd, ref POINT point);
    [LibraryImport("user32", EntryPoint = "GetWindowLongPtrW")] public static partial long GetWindowLongPtr(nint hwnd, int index);
    [LibraryImport("user32", EntryPoint = "SetWindowLongPtrW")] public static partial long SetWindowLongPtr(nint hwnd, int index, long value);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool SetWindowPos(nint hwnd, nint after, int x, int y, int width, int height, uint flags);
    [LibraryImport("user32")] public static partial nint MonitorFromPoint(POINT point, uint flags);
    [LibraryImport("user32", EntryPoint = "GetMonitorInfoW")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool GetMonitorInfo(nint monitor, ref MONITORINFO info);
    [LibraryImport("user32")] public static partial uint GetDpiForWindow(nint hwnd);
    [LibraryImport("user32")] public static partial uint GetDpiForSystem();
    [LibraryImport("kernel32", SetLastError = true)] public static partial nint OpenProcess(uint access, [MarshalAs(UnmanagedType.Bool)] bool inherit, uint id);
    [LibraryImport("kernel32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool CloseHandle(nint handle);

    [DllImport("kernel32", CharSet = CharSet.Unicode, EntryPoint = "QueryFullProcessImageNameW")]
    private static extern bool QueryFullProcessImageName(nint process, uint flags, StringBuilder name, ref uint size);

    public const nint HWND_TOPMOST = -1, HWND_NOTOPMOST = -2;
    private const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;

    /// The full path of a process's program, or null for one it can't read (most elevated ones).
    public static string? ProcessPath(uint process)
    {
        var handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, process);
        if (handle == 0) return null;
        try
        {
            var name = new StringBuilder(1024);
            var size = (uint)name.Capacity;
            return QueryFullProcessImageName(handle, 0, name, ref size) ? name.ToString() : null;
        }
        finally { CloseHandle(handle); }
    }

    /// The lowercase program name ("chrome.exe") owning a window: how excluded apps are matched.
    public static string? WindowApp(nint hwnd)
    {
        GetWindowThreadProcessId(hwnd, out var process);
        var path = ProcessPath(process);
        return path is null ? null : Path.GetFileName(path).ToLowerInvariant();
    }

    public static string? ForegroundApp() => WindowApp(GetForegroundWindow());
}
