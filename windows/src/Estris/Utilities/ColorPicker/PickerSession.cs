using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using Estris.Core;
using Estris.Utilities.RoundedCorners;
using static Estris.Core.Native;

namespace Estris.Utilities.ColorPicker;

/// One color pick: a nearly clear window over all the screens takes the pointer and the clicks,
/// and Esc comes through the keyboard hook, since nothing here takes the focus. The loupe and the
/// pill follow the pointer. Picks on release. Both windows stay out of what's sampled.
internal sealed partial class PickerSession : IDisposable
{
    private const uint WM_SETCURSOR = 0x20, WM_MOUSEACTIVATE = 0x21, WM_MOUSEMOVE_ = 0x200, WM_LBUTTONUP_ = 0x202, WM_RBUTTONUP_ = 0x205;
    private const nint MA_NOACTIVATE = 3;
    private const int SM_XVIRTUALSCREEN = 76, SM_YVIRTUALSCREEN = 77, SM_CXVIRTUALSCREEN = 78, SM_CYVIRTUALSCREEN = 79;
    private const int EscapeKey = 0x1B;
    /// Enough for Windows to send the window the pointer, and too little to see.
    private const byte CoverAlpha = 1;
    /// Room between the loupe and the pill.
    private const int PillGap = 10;

    private readonly ColorPill pill;
    private readonly Func<Rgb, string> format;
    private readonly Action<Rgb?> done;
    private readonly LayeredWindow cover;
    private readonly Loupe loupe = new();
    private Rgb? color;
    private bool isDone;

    public PickerSession(ColorPill pill, Func<Rgb, string> format, Action<Rgb?> done)
    {
        this.pill = pill;
        this.format = format;
        this.done = done;
        cover = new LayeredWindow(handler: OnMessage);
    }

    public void Begin()
    {
        cover.ExcludeFromCapture();
        var left = GetSystemMetrics(SM_XVIRTUALSCREEN);
        var top = GetSystemMetrics(SM_YVIRTUALSCREEN);
        cover.Cover(new RECT
        {
            Left = left,
            Top = top,
            Right = left + GetSystemMetrics(SM_CXVIRTUALSCREEN),
            Bottom = top + GetSystemMetrics(SM_CYVIRTUALSCREEN),
        }, CoverAlpha);
        InputHooks.Subscribe(OnKey);
        Update();
    }

    private bool OnMessage(uint message, nint wParam, nint lParam, out nint result)
    {
        result = 0;
        switch (message)
        {
            case WM_SETCURSOR:
                // The outlined pixel in the loupe is the pointer: anything drawn over it hides it.
                SetCursor(0);
                result = 1;
                return true;
            case WM_MOUSEACTIVATE:
                result = MA_NOACTIVATE;
                return true;
            case WM_MOUSEMOVE_:
                Update();
                return true;
            case WM_LBUTTONUP_:
                Finish(cancelled: false);
                return true;
            case WM_RBUTTONUP_:
                Finish(cancelled: true);
                return true;
            default:
                return false;
        }
    }

    private void OnKey(KeyEvent e)
    {
        if (e.Vk != EscapeKey || !e.IsDown) return;
        e.Handled = true;
        App.Ui.TryEnqueue(() => Finish(cancelled: true));
    }

    private void Update()
    {
        if (isDone) return;
        GetCursorPos(out var point);
        var dpi = LayeredWindow.Dpi(MonitorFromPoint(point, MONITOR_DEFAULTTONEAREST));
        var picked = loupe.Show(point, dpi);
        color = picked;
        var below = point.Y + loupe.Radius + (int)(PillGap * dpi / 96.0);
        var above = point.Y - loupe.Radius - (int)(PillGap * dpi / 96.0);
        pill.Show(picked, format(picked), isCopied: false, point.X, below, above);
    }

    private void Finish(bool cancelled)
    {
        if (isDone) return;
        Update();
        isDone = true;
        done(cancelled ? null : color);
    }

    public void Cancel() => Finish(cancelled: true);

    public void Dispose()
    {
        InputHooks.Unsubscribe(OnKey);
        cover.Dispose();
        loupe.Dispose();
    }

    [LibraryImport("user32")] private static partial nint SetCursor(nint cursor);
    [LibraryImport("user32")] private static partial int GetSystemMetrics(int index);
}

/// The pixels under the pointer, magnified, in a circle centred on it with the centre one
/// outlined. The window keeps itself out of what it reads from the screen.
internal sealed partial class Loupe : IDisposable
{
    /// Screen pixels across; odd, so one sits in the middle.
    private const int Cells = 15;
    private const int LoupeSize = 128, ShadowRoom = 12, ShadowDrop = 3;
    private const double ShadowOpacity = 0.35;
    private const int RingWidth = 1;
    private const int RingAlpha = 46;
    private const uint SRCCOPY = 0xCC0020, CAPTUREBLT = 0x40000000;
    private const uint OpaqueAlpha = 0xFF000000;

    private readonly LayeredWindow window = new(WS_EX_TRANSPARENT);
    private readonly nint screenDc, captureDc, captureBitmap, previousBitmap;
    private readonly nint capturePixels;
    private uint dpi;
    private int cell, diameter, room;
    private uint[] backdrop = [];
    private byte[] mask = [];

    public int Radius => diameter / 2;

    public Loupe()
    {
        window.ExcludeFromCapture();
        screenDc = GetDC(0);
        captureDc = CreateCompatibleDC(screenDc);
        var info = new BITMAPINFOHEADER { biSize = 40, biWidth = Cells, biHeight = -Cells, biPlanes = 1, biBitCount = 32 };
        captureBitmap = CreateDIBSection(screenDc, ref info, 0, out capturePixels, 0, 0);
        previousBitmap = SelectObject(captureDc, captureBitmap);
    }

    /// Reads the screen around a point and shows it there. Returns the color of the middle pixel.
    public unsafe Rgb Show(POINT point, uint dpi)
    {
        if (dpi != this.dpi) Prepare(dpi);
        BitBlt(captureDc, 0, 0, Cells, Cells, screenDc, point.X - Cells / 2, point.Y - Cells / 2, SRCCOPY | CAPTUREBLT);
        var middle = ((uint*)capturePixels)[Cells / 2 * Cells + Cells / 2];
        var side = diameter + 2 * room;
        window.Present(point.X - side / 2, point.Y - side / 2, side, side, Paint);
        return new Rgb((byte)(middle >> 16), (byte)(middle >> 8), (byte)middle);
    }

    /// Works out what doesn't change between moves, for this screen's size of pixel.
    private void Prepare(uint newDpi)
    {
        dpi = newDpi;
        var scale = newDpi / 96.0;
        cell = (int)Math.Round(LoupeSize * scale / Cells);
        diameter = cell * Cells;
        room = (int)Math.Ceiling(ShadowRoom * scale);
        var side = diameter + 2 * room;
        var center = side / 2.0;
        var radius = diameter / 2.0;
        var drop = ShadowDrop * scale;
        var blur = room - drop;
        backdrop = new uint[side * side];
        mask = new byte[side * side];
        for (var y = 0; y < side; y++)
        {
            for (var x = 0; x < side; x++)
            {
                double dx = x + 0.5 - center, dy = y + 0.5 - center;
                var distance = Math.Sqrt(dx * dx + dy * dy);
                mask[y * side + x] = (byte)Math.Round(Math.Clamp(radius - distance + 0.5, 0, 1) * 255);
                var shadow = Math.Sqrt(dx * dx + (dy - drop) * (dy - drop)) - radius;
                var fade = Math.Clamp(1 - shadow / blur, 0, 1);
                backdrop[y * side + x] = (uint)Math.Round(fade * fade * ShadowOpacity * 255) << 24;
            }
        }
    }

    private unsafe void Paint(nint pixels, int width, int height)
    {
        var frame = (uint*)pixels;
        var capture = (uint*)capturePixels;
        for (var y = 0; y < height; y++)
        {
            var row = (y - room) / cell;
            for (var x = 0; x < width; x++)
            {
                var index = y * width + x;
                uint coverage = mask[index];
                if (coverage == 0)
                {
                    frame[index] = backdrop[index];
                    continue;
                }
                var source = capture[row * Cells + (x - room) / cell] | OpaqueAlpha;
                frame[index] = coverage == 255 ? source : Blend(source, backdrop[index], coverage);
            }
        }

        // Rings and outlines are few pixels, each thin enough to be worth GDI+'s antialiasing.
        var scale = dpi / 96f;
        using var bitmap = new Bitmap(width, height, width * 4, PixelFormat.Format32bppPArgb, pixels);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        graphics.PixelOffsetMode = PixelOffsetMode.Half;
        var ringWidth = RingWidth * scale;
        using var ring = new Pen(Color.FromArgb(RingAlpha, 255, 255, 255), ringWidth);
        graphics.DrawEllipse(ring, room + ringWidth / 2, room + ringWidth / 2, diameter - ringWidth, diameter - ringWidth);

        graphics.SmoothingMode = SmoothingMode.None;
        var pixel = room + Cells / 2 * cell;
        using var dark = new Pen(Color.FromArgb(153, 0, 0, 0)) { Alignment = PenAlignment.Inset };
        graphics.DrawRectangle(dark, pixel - 2, pixel - 2, cell + 3, cell + 3);
        using var light = new Pen(Color.White) { Alignment = PenAlignment.Inset };
        graphics.DrawRectangle(light, pixel - 1, pixel - 1, cell + 1, cell + 1);
    }

    /// One premultiplied pixel over another, with the first scaled by a coverage out of 255.
    private static uint Blend(uint over, uint under, uint coverage)
    {
        var alpha = ((over >> 24) * coverage + 127) / 255;
        var rest = 255 - alpha;
        var result = 0u;
        for (var shift = 0; shift < 32; shift += 8)
        {
            var top = ((over >> shift & 0xFF) * coverage + 127) / 255;
            result |= Math.Min(top + ((under >> shift & 0xFF) * rest + 127) / 255, 255) << shift;
        }
        return result;
    }

    public void Dispose()
    {
        window.Dispose();
        SelectObject(captureDc, previousBitmap);
        DeleteObject(captureBitmap);
        DeleteDC(captureDc);
        ReleaseDC(0, screenDc);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BITMAPINFOHEADER
    {
        public int biSize, biWidth, biHeight;
        public short biPlanes, biBitCount;
        public uint biCompression, biSizeImage;
        public int biXPelsPerMeter, biYPelsPerMeter;
        public uint biClrUsed, biClrImportant;
    }

    [LibraryImport("user32")] private static partial nint GetDC(nint hwnd);
    [LibraryImport("user32")] private static partial int ReleaseDC(nint hwnd, nint dc);
    [LibraryImport("gdi32")] private static partial nint CreateCompatibleDC(nint dc);
    [LibraryImport("gdi32")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool DeleteDC(nint dc);
    [LibraryImport("gdi32")] private static partial nint SelectObject(nint dc, nint item);
    [LibraryImport("gdi32")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool DeleteObject(nint item);
    [LibraryImport("gdi32")] private static partial nint CreateDIBSection(nint dc, ref BITMAPINFOHEADER info, uint usage, out nint bits, nint section, uint offset);
    [LibraryImport("gdi32")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool BitBlt(nint target, int x, int y, int width, int height, nint source, int sourceX, int sourceY, uint operation);
}
