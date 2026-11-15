using Estris.Core;

namespace Estris.Utilities.RoundedCorners;

/// Rounded Corners preferences. The radius is in logical pixels, scaled per screen.
public sealed class RoundedCornersSettings
{
    /// Windows 11's own window corners, so a maximized window is concentric with the screen's.
    public const double DefaultRadius = 8, MinimumRadius = 2, MaximumRadius = 40;

    public const string EnabledKey = "roundedCornersEnabled", RadiusKey = "roundedCornersRadius";

    public Setting<double> Radius { get; } = SettingsStore.Shared.Get(RadiusKey, DefaultRadius);

    /// How round the screens' corners are right now, in physical pixels at that DPI: 0 while
    /// Rounded Corners is off. Read from what is saved, for others drawing along the corners.
    public static double ScreenRadius(uint dpi)
    {
        var store = SettingsStore.Shared;
        return store.Get(EnabledKey, false).Value ? store.Get(RadiusKey, DefaultRadius).Value * dpi / 96 : 0;
    }

    /// Back to the default radius; the on/off switch stays.
    public void Reset() => Radius.Reset();
}
