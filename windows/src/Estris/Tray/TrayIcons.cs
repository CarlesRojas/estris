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
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            if (id == DefaultId) DrawBento(g, color, size);
            else DrawGlyph(g, id, color, size);
        }
        return bitmap.GetHicon();
    }

    /// One tall compartment and two small ones, as on the app's icon.
    private static void DrawBento(Graphics g, Color color, int size)
    {
        using var brush = new SolidBrush(color);
        float unit = size / 16f;
        Fill(g, brush, 1.5f * unit, 2 * unit, 6 * unit, 12 * unit, 1.6f * unit);
        Fill(g, brush, 8.5f * unit, 2 * unit, 6 * unit, 5.5f * unit, 1.6f * unit);
        Fill(g, brush, 8.5f * unit, 8.5f * unit, 6 * unit, 5.5f * unit, 1.6f * unit);
    }

    private static void Fill(Graphics g, Brush brush, float x, float y, float width, float height, float radius)
    {
        using var path = new GraphicsPath();
        var d = radius * 2;
        path.AddArc(x, y, d, d, 180, 90);
        path.AddArc(x + width - d, y, d, d, 270, 90);
        path.AddArc(x + width - d, y + height - d, d, d, 0, 90);
        path.AddArc(x, y + height - d, d, d, 90, 90);
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
