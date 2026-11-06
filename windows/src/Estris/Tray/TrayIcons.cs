using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using Microsoft.Win32;

namespace Estris.Tray;

/// The icons to choose from: Estris's own bento box first, drawn here so it stays crisp at
/// any size, then glyphs from Windows's own icon font, so it sits well in the taskbar.
public static class TrayIcons
{
    public const string DefaultId = "bento";
    private const float GridSize = 16;

    public static readonly string[] Glyphs =
    [
        "", "", "", "", "", "", "", "",
        "", "", "", "", "", "", "", "",
        "", "", "", "", "", "", "", "",
        "", "", "", "", "", "", "", "",
        "", "", "", "", "", "", "", "",
        "", "", "", "", "", "", "", "",
        "", "", "",
    ];

    public static IEnumerable<string> AllIds => new[] { DefaultId }.Concat(Glyphs);

    /// White on a dark taskbar, black on a light one.
    public static bool TaskbarIsLight()
    {
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        return key?.GetValue("SystemUsesLightTheme") is 1;
    }

    /// Draws the icon, returning an HICON the caller owns.
    public static nint Render(string id, Color color, int size)
    {
        using var bitmap = new Bitmap(size, size);
        using (var g = Graphics.FromImage(bitmap))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            // Whole numbers are pixel edges, not pixel centres.
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            if (id == DefaultId) DrawBento(g, color, size);
            else DrawGlyph(g, id, color, size);
        }
        return bitmap.GetHicon();
    }

    /// One tall compartment and two small square ones, as on the Mac: the compartments three
    /// to four times the gap, filling more of the icon and with tighter corners, since at this
    /// size the same proportions read as dots. Every edge lands on a whole pixel.
    private static void DrawBento(Graphics g, Color color, int size)
    {
        using var brush = new SolidBrush(color);
        var inset = (int)MathF.Round(size / GridSize, MidpointRounding.AwayFromZero);
        var span = size - 2 * inset;
        var gap = Math.Max(2, 2 * (int)MathF.Round(span / 18f));
        gap += (span - gap) % 2;
        var column = (span - gap) / 2;
        var radius = column / 6f;
        var (near, far) = (inset + column, inset + column + gap);
        Fill(g, brush, inset, inset, near, size - inset, radius);
        Fill(g, brush, far, inset, size - inset, near, radius);
        Fill(g, brush, far, far, size - inset, size - inset, radius);
    }

    private static void Fill(Graphics g, Brush brush, int left, int top, int right, int bottom, float radius)
    {
        using var path = new GraphicsPath();
        var d = radius * 2;
        path.AddArc(left, top, d, d, 180, 90);
        path.AddArc(right - d, top, d, d, 270, 90);
        path.AddArc(right - d, bottom - d, d, d, 0, 90);
        path.AddArc(left, bottom - d, d, d, 90, 90);
        path.CloseFigure();
        g.FillPath(brush, path);
    }

    private static void DrawGlyph(Graphics g, string glyph, Color color, int size)
    {
        using var font = new Font(FontFamilyName(), size * 0.8f, GraphicsUnit.Pixel);
        using var brush = new SolidBrush(color);
        using var format = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
        g.DrawString(glyph, font, brush, new RectangleF(0, 0, size, size), format);
    }

    private static string FontFamilyName()
    {
        using var fonts = new InstalledFontCollection();
        return fonts.Families.Any(f => f.Name == "Segoe Fluent Icons") ? "Segoe Fluent Icons" : "Segoe MDL2 Assets";
    }
}
