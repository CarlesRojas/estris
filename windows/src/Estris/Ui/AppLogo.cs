using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Foundation;
using Windows.UI;

namespace Estris.Ui;

/// Estris's icon for the app's own pages, drawn rather than loaded: WinUI scales pictures down
/// roughly, so a bitmap goes soft at the small sizes these show at, and this stays sharp at any.
public static class AppLogo
{
    private const double GridSize = 16;
    private const double TileRadius = 2.6;
    private const double BoxRadius = 0.9;

    /// The white bento on its dark tile, as on the icon file (`scripts/make-icon.py`).
    public static FrameworkElement Tile(double size)
    {
        var tile = new Grid
        {
            Width = size,
            Height = size,
            CornerRadius = new CornerRadius(TileRadius * size / GridSize),
            Background = new LinearGradientBrush
            {
                StartPoint = new Point(0, 0),
                EndPoint = new Point(0, 1),
                GradientStops =
                {
                    new GradientStop { Color = Color.FromArgb(255, 0x2C, 0x2C, 0x2E), Offset = 0 },
                    new GradientStop { Color = Color.FromArgb(255, 0x14, 0x14, 0x16), Offset = 1 },
                },
            },
        };
        var white = new SolidColorBrush(Colors.White);
        foreach (var (left, top, right, bottom) in new[] { (3.0, 3.0, 7.5, 13.0), (8.5, 3.0, 13.0, 7.5), (8.5, 8.5, 13.0, 13.0) })
            tile.Children.Add(Box(left, top, right, bottom, size, white));
        return tile;
    }

    /// The bento alone in one color: how the tray draws it.
    public static FrameworkElement Mark(double size, Brush fill)
    {
        var mark = new Grid { Width = size, Height = size };
        foreach (var (left, top, right, bottom) in new[] { (2.0, 2.0, 7.0, 14.0), (9.0, 2.0, 14.0, 7.0), (9.0, 9.0, 14.0, 14.0) })
            mark.Children.Add(Box(left, top, right, bottom, size, fill));
        return mark;
    }

    private static Border Box(double left, double top, double right, double bottom, double size, Brush fill)
    {
        var unit = size / GridSize;
        return new Border
        {
            Width = (right - left) * unit,
            Height = (bottom - top) * unit,
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(left * unit, top * unit, 0, 0),
            CornerRadius = new CornerRadius(BoxRadius * unit),
            Background = fill,
        };
    }
}
