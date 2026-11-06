using System.Runtime.InteropServices;

namespace Estris.Utilities.ClipboardManager;

/// The Win32 calls only the clipboard needs.
internal static partial class ClipboardNative
{
    public const uint CF_UNICODETEXT = 13, CF_HDROP = 15, CF_DIB = 8, CF_DIBV5 = 17;
    public const uint GMEM_MOVEABLE = 2;
    public const uint WM_DESTROY = 2, WM_CLOSE = 0x10, WM_TIMER = 0x113, WM_CLIPBOARDUPDATE = 0x31D;
    public static readonly nint HWND_MESSAGE = -3;

    public delegate nint WindowProc(nint hwnd, uint message, nint wParam, nint lParam);
    public delegate void WinEventProc(nint hook, uint eventType, nint hwnd, int objectId, int childId, uint thread, uint time);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct WNDCLASSEX
    {
        public int cbSize;
        public uint style;
        public nint lpfnWndProc;
        public int cbClsExtra, cbWndExtra;
        public nint hInstance, hIcon, hCursor, hbrBackground;
        public nint lpszMenuName;
        public nint lpszClassName;
        public nint hIconSm;
    }

    [DllImport("user32", EntryPoint = "RegisterClassExW", SetLastError = true)]
    public static extern ushort RegisterClassEx(ref WNDCLASSEX windowClass);

    [LibraryImport("user32", EntryPoint = "CreateWindowExW", StringMarshalling = StringMarshalling.Utf16, SetLastError = true)]
    public static partial nint CreateWindowEx(uint exStyle, string className, string? title, uint style, int x, int y, int width, int height, nint parent, nint menu, nint instance, nint parameter);

    [LibraryImport("user32", EntryPoint = "DefWindowProcW")] public static partial nint DefWindowProc(nint hwnd, uint message, nint wParam, nint lParam);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool DestroyWindow(nint hwnd);
    [LibraryImport("user32", EntryPoint = "PostMessageW")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool PostMessage(nint hwnd, uint message, nint wParam, nint lParam);
    [LibraryImport("user32")] public static partial void PostQuitMessage(int code);
    [LibraryImport("user32")] public static partial nuint SetTimer(nint hwnd, nuint id, uint milliseconds, nint callback);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool KillTimer(nint hwnd, nuint id);

    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool AddClipboardFormatListener(nint hwnd);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool RemoveClipboardFormatListener(nint hwnd);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool OpenClipboard(nint hwnd);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool CloseClipboard();
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool EmptyClipboard();
    [LibraryImport("user32")] public static partial nint GetClipboardData(uint format);
    [LibraryImport("user32")] public static partial nint SetClipboardData(uint format, nint data);
    [LibraryImport("user32")] public static partial nint GetClipboardOwner();
    [LibraryImport("user32")] public static partial uint EnumClipboardFormats(uint format);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool IsClipboardFormatAvailable(uint format);
    [LibraryImport("user32", EntryPoint = "RegisterClipboardFormatW", StringMarshalling = StringMarshalling.Utf16)] public static partial uint RegisterClipboardFormat(string name);
    [LibraryImport("user32", EntryPoint = "GetClipboardFormatNameW")] public static unsafe partial int GetClipboardFormatName(uint format, char* name, int size);
    [LibraryImport("user32")] public static partial uint GetClipboardSequenceNumber();

    [LibraryImport("kernel32")] public static partial nint GlobalAlloc(uint flags, nuint bytes);
    [LibraryImport("kernel32")] public static partial nint GlobalLock(nint memory);
    [LibraryImport("kernel32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool GlobalUnlock(nint memory);
    [LibraryImport("kernel32")] public static partial nuint GlobalSize(nint memory);
    [LibraryImport("kernel32")] public static partial nint GlobalFree(nint memory);

    [LibraryImport("user32")] public static partial nint SetWinEventHook(uint min, uint max, nint module, WinEventProc proc, uint process, uint thread, uint flags);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool UnhookWinEvent(nint hook);
    [LibraryImport("user32", EntryPoint = "GetClassNameW")] public static unsafe partial int GetClassName(nint hwnd, char* name, int size);

    /// A clipboard format's name; standard formats have none and go by their number.
    public static unsafe string FormatName(uint format)
    {
        var name = stackalloc char[256];
        var length = GetClipboardFormatName(format, name, 256);
        return length > 0 ? new string(name, 0, length) : $"#{format}";
    }

    public static uint FormatId(string name) =>
        name.StartsWith('#') && uint.TryParse(name[1..], out var id) ? id : RegisterClipboardFormat(name);

    /// The bytes of a memory block on the clipboard, or null if it isn't one.
    public static byte[]? ReadBytes(nint memory)
    {
        var size = (long)GlobalSize(memory);
        if (size == 0) return null;
        var pointer = GlobalLock(memory);
        if (pointer == 0) return null;
        try
        {
            var data = new byte[size];
            Marshal.Copy(pointer, data, 0, data.Length);
            return data;
        }
        finally { GlobalUnlock(memory); }
    }

    /// A new memory block holding data, for SetClipboardData.
    public static nint Allocate(ReadOnlySpan<byte> data)
    {
        var memory = GlobalAlloc(GMEM_MOVEABLE, (nuint)data.Length);
        if (memory == 0) return 0;
        var pointer = GlobalLock(memory);
        unsafe { data.CopyTo(new Span<byte>((void*)pointer, data.Length)); }
        GlobalUnlock(memory);
        return memory;
    }
}
