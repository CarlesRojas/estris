using System.Runtime.InteropServices.WindowsRuntime;
using Estris.Ui;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.UI;
using Windows.UI.ViewManagement;

namespace Estris.Utilities.ClipboardManager.Overlay;

public enum SurfaceState { Normal, Hovered, Selected }

/// The frosted material and colors shared by one window's surfaces, following the Appearance
/// settings and the Windows theme. Brushes are changed in place, so surfaces pick it up live.
internal sealed class SurfaceLook
{
    /// Windows 11's own radius for cards and flyouts, and half the pill's height.
    public const double CardRadius = 8, PillRadius = 15;
    private const double SelectedShadowOpacity = 0.35, ShadowOpacity = 0.22;

    private static readonly Color DarkBase = Color.FromArgb(255, 32, 32, 32), LightBase = Color.FromArgb(255, 243, 243, 243);

    private readonly AppearanceSettings appearance;
    private readonly Dictionary<SurfaceState, SolidColorBrush> tints = new()
    {
        [SurfaceState.Normal] = new SolidColorBrush(),
        [SurfaceState.Hovered] = new SolidColorBrush(),
        [SurfaceState.Selected] = new SolidColorBrush(),
    };

    public AcrylicBrush Frost { get; } = new() { TintOpacity = 0.45, TintLuminosityOpacity = 0.7 };
    public SolidColorBrush Stroke { get; } = new();
    public SolidColorBrush Primary { get; } = new();
    public SolidColorBrush Secondary { get; } = new();

    /// Runs when the shadow changes.
    public event Action? ShadowChanged;

    public SurfaceLook(AppearanceSettings appearance)
    {
        this.appearance = appearance;
        foreach (var setting in new[] { appearance.TintOpacity, appearance.SelectedTintOpacity }) setting.Changed += ApplyTint;
        appearance.Tint.Changed += ApplyTint;
        appearance.ShadowRadius.Changed += () => ShadowChanged?.Invoke();
        ApplyTheme();
    }

    public double ShadowRadius => appearance.ShadowRadius.Value;

    public Brush Tint(SurfaceState state) => tints[state];

    public static double ShadowOpacityFor(SurfaceState state) => state == SurfaceState.Selected ? SelectedShadowOpacity : ShadowOpacity;

    /// Picks up a change of Windows' light or dark mode.
    public void ApplyTheme()
    {
        var background = new UISettings().GetColorValue(UIColorType.Background);
        var isDark = background.R < 128;
        Frost.TintColor = isDark ? DarkBase : LightBase;
        Frost.FallbackColor = Frost.TintColor;
        Primary.Color = isDark ? Colors.White : Color.FromArgb(0xE4, 0, 0, 0);
        Secondary.Color = isDark ? Color.FromArgb(0xC8, 255, 255, 255) : Color.FromArgb(0x9E, 0, 0, 0);
        Stroke.Color = isDark ? Color.FromArgb(0x18, 255, 255, 255) : Color.FromArgb(0x14, 0, 0, 0);
        ApplyTint();
    }

    private void ApplyTint()
    {
        var color = Pane.ParseColor(appearance.Tint.Value);
        foreach (var (state, brush) in tints)
        {
            color.A = (byte)Math.Round(appearance.SurfaceTintOpacity(state) * 255);
            brush.Color = color;
        }
    }
}

/// Frosted material behind an overlay element, tinted as configured, with a shadow drawn only
/// outside it. A shadow under the whole card would show through the frost and darken it.
internal class Surface : Grid
{
    private readonly BrushTransition hoverTransition = new() { Duration = Motion.Hover };
    private readonly SurfaceLook look;
    private readonly double radius;
    private readonly Image shadow = new() { Stretch = Stretch.Fill, IsHitTestVisible = false, HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Top };
    private readonly Border tint;
    private SurfaceState state;

    public Surface(SurfaceLook look, double radius)
    {
        this.look = look;
        this.radius = radius;
        var corners = new CornerRadius(radius);
        tint = new Border { CornerRadius = corners, BorderBrush = look.Stroke, BorderThickness = new Thickness(1), Background = look.Tint(state) };
        Children.Add(shadow);
        Children.Add(new Border { CornerRadius = corners, Background = look.Frost });
        Children.Add(tint);
        look.ShadowChanged += ApplyShadow;
        SizeChanged += (_, _) => ApplyShadow();
        ApplyShadow();
        shadow.Opacity = SurfaceLook.ShadowOpacityFor(state);
    }

    public SurfaceState State
    {
        get => state;
        set
        {
            if (state == value) return;
            state = value;
            tint.BackgroundTransition = Motion.IsReduced ? null : hoverTransition;
            tint.Background = look.Tint(state);
            shadow.Opacity = SurfaceLook.ShadowOpacityFor(state);
        }
    }

    private void ApplyShadow()
    {
        var tile = ShadowTile.For(radius, look.ShadowRadius);
        shadow.Visibility = tile is null ? Visibility.Collapsed : Visibility.Visible;
        if (tile is null) return;
        shadow.Source = tile.Bitmap;
        shadow.NineGrid = new Thickness(tile.Inset);
        // Given in full, as an image set to fill would take all the space it is offered.
        shadow.Width = ActualWidth + tile.Padding * 2;
        shadow.Height = ActualHeight + tile.Padding * 2;
        shadow.Margin = new Thickness(-tile.Padding);
    }
}

/// A small picture of a shadow with the shape cut out of it, stretched around any size of surface
/// as a nine-grid. Cheap to draw, so a surface can move without its shadow being redone.
internal sealed record ShadowTile(WriteableBitmap Bitmap, int Padding, int Inset)
{
    private const int BlurPasses = 3;
    private static readonly Dictionary<(double, double), ShadowTile> Cache = [];

    /// A tile for a shape with these corners, or null for no shadow.
    public static ShadowTile? For(double cornerRadius, double blurRadius)
    {
        if (blurRadius < 1) return null;
        var key = (cornerRadius, Math.Round(blurRadius));
        if (!Cache.TryGetValue(key, out var tile)) Cache[key] = tile = Draw(cornerRadius, key.Item2);
        return tile;
    }

    private static ShadowTile Draw(double cornerRadius, double blurRadius)
    {
        var sigma = blurRadius / 2;
        var drop = (int)Math.Round(blurRadius / 3);
        var padding = (int)Math.Ceiling(sigma * 3) + drop + 1;
        var inset = padding + (int)Math.Ceiling(cornerRadius) + 1;
        var size = inset * 2 + 1;

        var shape = new float[size * size];
        for (var y = 0; y < size; y++)
            for (var x = 0; x < size; x++)
                shape[y * size + x] = Coverage(x, y, size, padding, cornerRadius);

        var blurred = new float[size * size];
        for (var y = 0; y < size; y++)
            for (var x = 0; x < size; x++)
                blurred[y * size + x] = y >= drop ? shape[(y - drop) * size + x] : 0;
        var boxRadius = Math.Max(1, (int)Math.Round(sigma * 0.94));
        for (var pass = 0; pass < BlurPasses; pass++)
        {
            Box(blurred, size, 1, size, boxRadius);
            Box(blurred, size, size, 1, boxRadius);
        }

        var bitmap = new WriteableBitmap(size, size);
        var bgra = new byte[size * size * 4];
        for (var index = 0; index < shape.Length; index++)
            bgra[index * 4 + 3] = (byte)Math.Round(255 * blurred[index] * (1 - shape[index]));
        using (var stream = bitmap.PixelBuffer.AsStream()) stream.Write(bgra);
        bitmap.Invalidate();
        return new ShadowTile(bitmap, padding, inset);
    }

    /// How much of a pixel the rounded shape covers, from its distance to the edge.
    private static float Coverage(int x, int y, int size, int padding, double radius)
    {
        var half = size / 2.0 - padding;
        var offsetX = Math.Abs(x + 0.5 - size / 2.0) - (half - radius);
        var offsetY = Math.Abs(y + 0.5 - size / 2.0) - (half - radius);
        var outside = Math.Sqrt(Math.Pow(Math.Max(offsetX, 0), 2) + Math.Pow(Math.Max(offsetY, 0), 2));
        var distance = outside + Math.Min(Math.Max(offsetX, offsetY), 0) - radius;
        return (float)Math.Clamp(0.5 - distance, 0, 1);
    }

    /// One pass of a running average along every line: lines step by next, pixels by along.
    private static void Box(float[] values, int size, int along, int next, int radius)
    {
        var line = new float[size];
        var width = radius * 2 + 1;
        for (var row = 0; row < size; row++)
        {
            float sum = 0;
            for (var index = -radius; index <= radius; index++) sum += values[row * next + Math.Clamp(index, 0, size - 1) * along];
            for (var index = 0; index < size; index++)
            {
                line[index] = sum / width;
                sum += values[row * next + Math.Min(index + radius + 1, size - 1) * along] - values[row * next + Math.Max(index - radius, 0) * along];
            }
            for (var index = 0; index < size; index++) values[row * next + index * along] = line[index];
        }
    }
}
