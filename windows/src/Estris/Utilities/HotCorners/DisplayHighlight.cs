using Estris.Utilities.RoundedCorners;
using Microsoft.UI.Dispatching;
using Windows.UI.ViewManagement;
using static Estris.Core.Native;

namespace Estris.Utilities.HotCorners;

/// Outlines a display in the accent colour for a moment, so picking one in Hot Corners shows
/// which screen it is. A click-through window over the whole display, fading in and out.
internal static class DisplayHighlight
{
    /// Border thickness, in logical pixels.
    private const int Thickness = 8;
    private const double FadeInMilliseconds = 150, HoldMilliseconds = 1200, FadeOutMilliseconds = 350;
    private static readonly TimeSpan FrameInterval = TimeSpan.FromMilliseconds(16);

    private static LayeredWindow? window;
    private static DispatcherQueueTimer? timer;
    private static long startedAt;

    /// Shows the outline on that display, replacing one still showing elsewhere.
    public static void Show(Display display)
    {
        Close();
        var accent = new UISettings().GetColorValue(UIColorType.Accent);
        var thickness = Math.Max(1, Thickness * (int)display.Dpi / 96);
        // Along the screen's rounded corners, when Rounded Corners paints them.
        var radius = RoundedCornersSettings.ScreenRadius(display.Dpi);
        var b = display.Bounds;
        window = new LayeredWindow(WS_EX_TRANSPARENT);
        window.Present(b.Left, b.Top, b.Width, b.Height, (pixels, width, height) => Paint(pixels, width, height, thickness, radius, accent), 0);

        startedAt = Environment.TickCount64;
        if (timer is null)
        {
            timer = App.Ui.CreateTimer();
            timer.Interval = FrameInterval;
            timer.Tick += (_, _) => Step();
        }
        timer.Start();
    }

    private static void Step()
    {
        if (window is null) return;
        var elapsed = (double)(Environment.TickCount64 - startedAt);
        double opacity;
        if (elapsed < FadeInMilliseconds) opacity = elapsed / FadeInMilliseconds;
        else if (elapsed < FadeInMilliseconds + HoldMilliseconds) opacity = 1;
        else
        {
            var fading = (elapsed - FadeInMilliseconds - HoldMilliseconds) / FadeOutMilliseconds;
            if (fading >= 1)
            {
                Close();
                return;
            }
            opacity = 1 - fading;
        }
        // Ease out: quick to arrive, soft to leave.
        window.SetOpacity((byte)Math.Round(255 * (1 - Math.Pow(1 - opacity, 2))));
    }

    private static void Close()
    {
        timer?.Stop();
        window?.Dispose();
        window = null;
    }

    /// The border's pixels in the accent colour, the rest clear. The four corners follow a
    /// rounded outline, antialiased; the straight edges are plain.
    private static unsafe void Paint(nint pixels, int width, int height, int thickness, double radius, Windows.UI.Color accent)
    {
        var solid = Premultiplied(accent, 255);
        var surface = new Span<uint>((void*)pixels, width * height);
        surface.Clear();
        for (var y = 0; y < height; y++)
        {
            var row = surface.Slice(y * width, width);
            if (y < thickness || y >= height - thickness) row.Fill(solid);
            else
            {
                row[..Math.Min(thickness, width)].Fill(solid);
                row[Math.Max(0, width - thickness)..].Fill(solid);
            }
        }
        if (radius <= 0) return;

        var inner = Math.Max(0, radius - thickness);
        var side = Math.Min((int)Math.Ceiling(Math.Max(radius, thickness)) + 1, Math.Min(width, height) / 2);
        for (var y = 0; y < side; y++)
            for (var x = 0; x < side; x++)
            {
                // The pixel's centre, measured from the corner, as if it were the top-left one.
                var (px, py) = (x + 0.5, y + 0.5);
                var outside = Coverage(px, py, 0, radius);
                var hole = Coverage(px, py, thickness, inner);
                var color = Premultiplied(accent, (byte)Math.Round(255 * Math.Clamp(outside * (1 - hole), 0, 1)));
                surface[y * width + x] = color;
                surface[y * width + width - 1 - x] = color;
                surface[(height - 1 - y) * width + x] = color;
                surface[(height - 1 - y) * width + width - 1 - x] = color;
            }
    }

    /// How much of a pixel at (x, y) from the top-left corner lies inside a rounded rectangle
    /// inset by that much, with a corner of that radius.
    private static double Coverage(double x, double y, double inset, double radius)
    {
        var centre = inset + radius;
        var (dx, dy) = (centre - x, centre - y);
        // Past the corner's curve, it's the straight edges that count.
        var distance = dx > 0 && dy > 0 ? Math.Sqrt(dx * dx + dy * dy) - radius : Math.Max(inset - x, inset - y);
        return Math.Clamp(0.5 - distance, 0, 1);
    }

    private static uint Premultiplied(Windows.UI.Color color, byte alpha) =>
        (uint)alpha << 24 | (uint)(color.R * alpha / 255) << 16 | (uint)(color.G * alpha / 255) << 8 | (uint)(color.B * alpha / 255);
}
