using System.Numerics;
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

/// A picture of one screen, taken just before the overlay covers it. The overlay shows it as its
/// background, so its frosted cards have something to blur. Buffers are kept between opens: a
/// new one for every open would take longer than the copy.
internal sealed class ScreenCapture : IDisposable
{
    private nint memoryDc, section, sectionBits, previous;
    private int width, height;

    public WriteableBitmap? Bitmap { get; private set; }

    public void Take(RECT bounds)
    {
        if (bounds.Width != width || bounds.Height != height) Allocate(bounds.Width, bounds.Height);
        var screen = Gdi.GetDC(0);
        Gdi.BitBlt(memoryDc, 0, 0, width, height, screen, bounds.Left, bounds.Top, Gdi.SRCCOPY);
        Gdi.ReleaseDC(0, screen);
        MakeOpaque();
        unsafe
        {
            using var stream = Bitmap!.PixelBuffer.AsStream();
            stream.Write(new ReadOnlySpan<byte>((void*)sectionBits, width * height * 4));
        }
        Bitmap.Invalidate();
    }

    private void Allocate(int newWidth, int newHeight)
    {
        Release();
        width = newWidth;
        height = newHeight;
        var info = Gdi.TopDownHeader(width, height);
        var screen = Gdi.GetDC(0);
        memoryDc = Gdi.CreateCompatibleDC(screen);
        section = Gdi.CreateDIBSection(memoryDc, ref info, 0, out sectionBits, 0, 0);
        Gdi.ReleaseDC(0, screen);
        previous = Gdi.SelectObject(memoryDc, section);
        Bitmap = new WriteableBitmap(width, height);
    }

    /// BitBlt leaves alpha at 0, which would show as nothing.
    private unsafe void MakeOpaque()
    {
        var pixels = new Span<uint>((void*)sectionBits, width * height);
        var opaque = new Vector<uint>(0xFF000000);
        var index = 0;
        for (; index <= pixels.Length - Vector<uint>.Count; index += Vector<uint>.Count)
            (new Vector<uint>(pixels[index..]) | opaque).CopyTo(pixels[index..]);
        for (; index < pixels.Length; index++) pixels[index] |= 0xFF000000;
    }

    private void Release()
    {
        if (memoryDc == 0) return;
        Gdi.SelectObject(memoryDc, previous);
        Gdi.DeleteObject(section);
        Gdi.DeleteDC(memoryDc);
        memoryDc = 0;
        Bitmap = null;
        width = height = 0;
    }

    public void Dispose() => Release();
}
