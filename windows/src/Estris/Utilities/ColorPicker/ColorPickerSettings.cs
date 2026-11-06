using System.Globalization;
using Estris.Core;

namespace Estris.Utilities.ColorPicker;

/// A color in sRGB.
public readonly record struct Rgb(byte R, byte G, byte B)
{
    /// As saved among the recent colors: "FF8000".
    public string Hex => $"{R:X2}{G:X2}{B:X2}";

    public static Rgb? FromHex(string hex) =>
        hex.Length == 6 && int.TryParse(hex, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var value)
            ? new Rgb((byte)(value >> 16), (byte)(value >> 8), (byte)value)
            : null;
}

/// How a picked color is copied. Saved by number: keep the order.
public enum ColorFormat { Hex, Rgb, Hsl, CSharp }

public static class ColorFormats
{
    public static readonly (ColorFormat Value, string Label)[] All =
    [
        (ColorFormat.Hex, "Hex"), (ColorFormat.Rgb, "RGB"), (ColorFormat.Hsl, "HSL"), (ColorFormat.CSharp, "C#"),
    ];

    /// The color as text in this format.
    public static string Text(this ColorFormat format, Rgb color, bool hashPrefix)
    {
        switch (format)
        {
            case ColorFormat.Hex:
                return (hashPrefix ? "#" : "") + color.Hex;
            case ColorFormat.Rgb:
                return $"rgb({color.R}, {color.G}, {color.B})";
            case ColorFormat.Hsl:
                var (hue, saturation, lightness) = Hsl(color);
                return $"hsl({Round(hue)}, {Round(saturation * 100)}%, {Round(lightness * 100)}%)";
            default:
                return $"Color.FromArgb(255, {color.R}, {color.G}, {color.B})";
        }
    }

    private static int Round(double value) => (int)Math.Round(value, MidpointRounding.AwayFromZero);

    /// Hue in degrees, saturation and lightness between 0 and 1.
    private static (double, double, double) Hsl(Rgb color)
    {
        double red = color.R / 255.0, green = color.G / 255.0, blue = color.B / 255.0;
        var maximum = Math.Max(red, Math.Max(green, blue));
        var minimum = Math.Min(red, Math.Min(green, blue));
        var lightness = (maximum + minimum) / 2;
        var delta = maximum - minimum;
        if (delta <= 0) return (0, 0, lightness);
        var saturation = delta / (1 - Math.Abs(2 * lightness - 1));
        double hue;
        if (maximum == red) hue = (green - blue) / delta % 6;
        else if (maximum == green) hue = (blue - red) / delta + 2;
        else hue = (red - green) / delta + 4;
        hue *= 60;
        if (hue < 0) hue += 360;
        return (hue, saturation, lightness);
    }
}

/// Color Picker preferences.
public sealed class ColorPickerSettings
{
    public const int MaxRecentColors = 16;
    private const int ShortcutKey = 0x43;
    private static readonly SettingsStore Store = SettingsStore.Shared;

    public Setting<ColorFormat> Format { get; } = Store.Get("colorPickerFormat", ColorFormat.Hex);
    /// Hex values start with "#".
    public Setting<bool> HashPrefix { get; } = Store.Get("colorPickerHashPrefix", true);
    public Setting<Shortcut> Shortcut { get; } = Store.Get("colorPickerShortcut", new Shortcut(true, true, false, false, ShortcutKey));
    /// The colors picked lately, most recent first, as "FF8000". Kept by Reset to Defaults, like
    /// other histories.
    public Setting<List<string>> RecentColors { get; } = Store.Get("colorPickerRecentColors", new List<string>());

    public string Text(Rgb color) => Format.Value.Text(color, HashPrefix.Value);

    /// Puts a color first among the recent ones; picking one again moves it up.
    public void Remember(Rgb color) =>
        RecentColors.Value = RecentColors.Value.Where(hex => hex != color.Hex).Prepend(color.Hex).Take(MaxRecentColors).ToList();

    /// Back to the default format and shortcut; the on/off switch and recent colors stay.
    public void Reset()
    {
        Format.Reset();
        HashPrefix.Reset();
        Shortcut.Reset();
    }
}
