using System.Globalization;
using System.Text;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Markup;
using Microsoft.UI.Xaml.Media;
using Windows.Foundation;
using Windows.UI;

namespace Estris.Ui;

/// Estris's icon for the app's own pages, with the numbers of `macos/Resources/Icon/AppIcon.svg`,
/// the one source of the icon. The bento is one shape: WinUI draws separate shapes each on its own
/// terms, which puts edges meant to line up a fraction of a pixel apart, and scales pictures roughly.
public static class AppLogo
{
    /// The SVG's squircle, from its corner, without the room macOS leaves around icons.
    private const double BodySize = 824, BodyRadius = 185;
    /// The bento on the SVG's 24 grid, which it places 172 in from the squircle's corner at 20 to 1.
    private const double BoxInset = 172, GridScale = 20, GridSize = 24, BoxRadius = 2;
    private const double StrokeInset = 0.5, StrokeOpacity = 0.08;

    private static readonly (double Left, double Top, double Width, double Height)[] Boxes = [(3, 3, 8, 18), (13, 3, 8, 8), (13, 13, 8, 8)];

    /// The white bento on its dark tile.
    public static FrameworkElement Tile(double size)
    {
        var scale = size / BodySize;
        var drawing = new Canvas { Width = size, Height = size };
        drawing.Children.Add(Shape(Rounded(0, 0, BodySize, BodySize, BodyRadius, scale), new LinearGradientBrush
        {
            StartPoint = new Point(0, 0),
            EndPoint = new Point(0, 1),
            GradientStops =
            {
                new GradientStop { Color = Color.FromArgb(255, 0x2C, 0x2C, 0x2E), Offset = 0 },
                new GradientStop { Color = Color.FromArgb(255, 0x14, 0x14, 0x16), Offset = 1 },
            },
        }));
        var edge = Shape(Rounded(StrokeInset, StrokeInset, BodySize - 2 * StrokeInset, BodySize - 2 * StrokeInset, BodyRadius, scale), null);
        edge.Stroke = new SolidColorBrush(Colors.White) { Opacity = StrokeOpacity };
        edge.StrokeThickness = scale;
        drawing.Children.Add(edge);
        var bento = string.Concat(Boxes.Select(box => Rounded(BoxInset + box.Left * GridScale, BoxInset + box.Top * GridScale, box.Width * GridScale, box.Height * GridScale, BoxRadius * GridScale, scale)));
        drawing.Children.Add(Shape(bento, new SolidColorBrush(Colors.White)));
        return drawing;
    }

    /// The bento alone in one color, as the tray and the Mac's menu bar draw it.
    public static FrameworkElement Mark(double size, Brush fill)
    {
        var scale = size / GridSize;
        var drawing = new Canvas { Width = size, Height = size };
        drawing.Children.Add(Shape(string.Concat(Boxes.Select(box => Rounded(box.Left, box.Top, box.Width, box.Height, BoxRadius, scale))), fill));
        return drawing;
    }

    private static Microsoft.UI.Xaml.Shapes.Path Shape(string data, Brush? fill) => new()
    {
        Data = (Geometry)XamlBindingHelper.ConvertValue(typeof(Geometry), data),
        Fill = fill,
        UseLayoutRounding = false,
    };

    /// A rounded rectangle as path data, at the size it shows.
    private static string Rounded(double left, double top, double width, double height, double radius, double scale)
    {
        string N(double value) => (value * scale).ToString("0.####", CultureInfo.InvariantCulture);
        var (right, bottom) = (left + width, top + height);
        var corner = $"A{N(radius)},{N(radius)} 0 0 1 ";
        return new StringBuilder()
            .Append($"M{N(left + radius)},{N(top)} H{N(right - radius)} {corner}{N(right)},{N(top + radius)} ")
            .Append($"V{N(bottom - radius)} {corner}{N(right - radius)},{N(bottom)} ")
            .Append($"H{N(left + radius)} {corner}{N(left)},{N(bottom - radius)} ")
            .Append($"V{N(top + radius)} {corner}{N(left + radius)},{N(top)} Z ")
            .ToString();
    }
}
