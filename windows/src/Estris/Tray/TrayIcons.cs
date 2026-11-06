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

    /// One tall compartment and two small ones, square as on the Mac. Every edge lands on a whole
    /// pixel, mirrored around the middle, so nothing blurs and the two columns stay equal.
    private static void DrawBento(Graphics g, Color color, int size)
    {
        using var brush = new SolidBrush(color);
        var radius = 1.25f * size / GridSize;
        int Edge(float position) => (int)MathF.Floor(position * size / GridSize + 0.49f);
        int Mirrored(float position) => size - Edge(GridSize - position);
        Fill(g, brush, Edge(2), Edge(2), Edge(7), Mirrored(14), radius);
        Fill(g, brush, Mirrored(9), Edge(2), Mirrored(14), Edge(7), radius);
        Fill(g, brush, Mirrored(9), Mirrored(9), Mirrored(14), Mirrored(14), radius);
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
