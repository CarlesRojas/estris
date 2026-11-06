using System.Runtime.InteropServices;
using System.Text;

namespace Estris.Utilities.WindowSnapping;

/// The Win32 and DWM calls that listing, moving and watching other apps' windows needs.
internal static partial class WindowNative
{
    public const int DWMWA_EXTENDED_FRAME_BOUNDS = 9, DWMWA_CLOAKED = 14;
    public const uint GW_OWNER = 4;
    public const long WS_CHILD = 0x40000000, WS_CAPTION = 0xC00000, WS_THICKFRAME = 0x40000;
    public const uint SWP_NOOWNERZORDER = 0x200, SWP_ASYNCWINDOWPOS = 0x4000;
    public const int SW_SHOWNOACTIVATE = 4, SW_MAXIMIZE = 3;
    public const int ERROR_ACCESS_DENIED = 5, ERROR_HOTKEY_ALREADY_REGISTERED = 1409;

    public const int OBJID_WINDOW = 0;
    public const uint EVENT_SYSTEM_MOVESIZESTART = 0xA, EVENT_SYSTEM_MOVESIZEEND = 0xB;
    private const uint WINEVENT_OUTOFCONTEXT = 0;

    public delegate bool EnumProc(nint hwnd, nint data);
    public delegate bool MonitorProc(nint monitor, nint dc, nint rect, nint data);
    public delegate void WinEventProc(nint hook, uint type, nint hwnd, int idObject, int idChild, uint thread, uint time);

    [StructLayout(LayoutKind.Sequential)]
    public struct WINDOWPLACEMENT
    {
        public int length;
        public uint flags, showCmd;
        public Core.Native.POINT ptMinPosition, ptMaxPosition;
        public Core.Native.RECT rcNormalPosition;
    }

    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool EnumWindows(EnumProc callback, nint data);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool EnumDisplayMonitors(nint dc, nint clip, MonitorProc callback, nint data);
    [LibraryImport("user32")] public static partial nint GetWindow(nint hwnd, uint command);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool IsWindow(nint hwnd);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool IsZoomed(nint hwnd);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool IsHungAppWindow(nint hwnd);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool ShowWindow(nint hwnd, int command);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool GetWindowPlacement(nint hwnd, ref WINDOWPLACEMENT placement);
    [LibraryImport("user32", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool SetWindowPlacement(nint hwnd, ref WINDOWPLACEMENT placement);
    [LibraryImport("user32", SetLastError = true, EntryPoint = "SetWindowPos")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool SetWindowPosChecked(nint hwnd, nint after, int x, int y, int width, int height, uint flags);
    [LibraryImport("user32")] public static partial nint MonitorFromWindow(nint hwnd, uint flags);
    [LibraryImport("shcore")] public static partial int GetDpiForMonitor(nint monitor, int type, out uint dpiX, out uint dpiY);
    [LibraryImport("dwmapi")] public static partial int DwmGetWindowAttribute(nint hwnd, int attribute, out Core.Native.RECT value, int size);
    [LibraryImport("dwmapi")] public static partial int DwmGetWindowAttribute(nint hwnd, int attribute, out int value, int size);
    [LibraryImport("user32")] private static partial nint SetWinEventHook(uint min, uint max, nint module, WinEventProc callback, uint process, uint thread, uint flags);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool UnhookWinEvent(nint hook);

    [DllImport("user32", CharSet = CharSet.Unicode, EntryPoint = "GetClassNameW")]
    private static extern int GetClassName(nint hwnd, StringBuilder name, int size);

    public static string ClassName(nint hwnd)
    {
        var name = new StringBuilder(256);
        return GetClassName(hwnd, name, name.Capacity) > 0 ? name.ToString() : "";
    }

    /// Listens to system window events on a thread of its own with a message loop, as they
    /// need one. The handler runs on that thread: keep it quick.
    public sealed class WinEventHook : IDisposable
    {
        public delegate void Handler(uint type, nint hwnd, int idObject, int idChild);

        private readonly WinEventProc callback;
        private uint threadId;

        public WinEventHook(uint min, uint max, Handler handler, string name)
        {
            callback = (_, type, hwnd, idObject, idChild, _, _) =>
            {
                try { handler(type, hwnd, idObject, idChild); }
                catch (Exception error) { App.Shared.Log.Add(name, $"Window event failed: {error.Message}"); }
            };
            using var ready = new ManualResetEventSlim();
            var thread = new Thread(() =>
            {
                threadId = Core.Native.GetCurrentThreadId();
                var hook = SetWinEventHook(min, max, 0, callback, 0, 0, WINEVENT_OUTOFCONTEXT);
                ready.Set();
                while (Core.Native.GetMessage(out var message, 0, 0, 0) > 0)
                {
                    Core.Native.TranslateMessage(ref message);
                    Core.Native.DispatchMessage(ref message);
                }
                UnhookWinEvent(hook);
            }) { IsBackground = true, Name = name };
            thread.Start();
            ready.Wait();
        }

        public void Dispose() => Core.Native.PostThreadMessage(threadId, Core.Native.WM_QUIT, 0, 0);
    }
}
