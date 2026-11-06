using System.Runtime.InteropServices;
using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Xaml.Media.Imaging;
using static Estris.Core.Native;

namespace Estris.Utilities.ClipboardManager.Overlay;

internal static partial class Gdi
{
    public const uint SRCCOPY = 0x00CC0020;

    [StructLayout(LayoutKind.Sequential)]
    public struct BITMAPINFOHEADER
    {
        public uint biSize;
        public int biWidth, biHeight;
        public ushort biPlanes, biBitCount;
        public uint biCompression, biSizeImage;
        public int biXPelsPerMeter, biYPelsPerMeter;
        public uint biClrUsed, biClrImportant;
    }

    [LibraryImport("user32")] public static partial nint GetDC(nint hwnd);
    [LibraryImport("user32")] public static partial int ReleaseDC(nint hwnd, nint dc);
    [LibraryImport("gdi32")] public static partial nint CreateCompatibleDC(nint dc);
    [LibraryImport("gdi32")] public static partial nint CreateDIBSection(nint dc, ref BITMAPINFOHEADER info, uint usage, out nint bits, nint section, uint offset);
    [LibraryImport("gdi32")] public static partial nint SelectObject(nint dc, nint item);
    [LibraryImport("gdi32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool BitBlt(nint target, int x, int y, int width, int height, nint source, int sourceX, int sourceY, uint operation);
    [LibraryImport("gdi32")] public static partial int GetDIBits(nint dc, nint bitmap, uint start, uint lines, nint bits, ref BITMAPINFOHEADER info, uint usage);
    [LibraryImport("gdi32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool DeleteObject(nint item);
    [LibraryImport("gdi32")] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool DeleteDC(nint dc);

    public static BITMAPINFOHEADER TopDownHeader(int width, int height) => new()
    {
        biSize = (uint)Marshal.SizeOf<BITMAPINFOHEADER>(),
        biWidth = width,
        biHeight = -height,
        biPlanes = 1,
        biBitCount = 32,
    };

    /// The pixels of a 32-bit bitmap handle.
    public static Pixels? Read(nint bitmap, int width, int height)
    {
        var info = TopDownHeader(width, height);
        var bgra = new byte[width * height * 4];
        var dc = GetDC(0);
        try
        {
            unsafe
            {
                fixed (byte* bits = bgra)
                    return GetDIBits(dc, bitmap, 0, (uint)height, (nint)bits, ref info, 0) == height ? new Pixels(width, height, bgra) : null;
            }
        }
        finally { ReleaseDC(0, dc); }
    }
}
