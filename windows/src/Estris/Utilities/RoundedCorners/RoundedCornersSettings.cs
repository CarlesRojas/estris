using Estris.Core;

namespace Estris.Utilities.RoundedCorners;

/// Rounded Corners preferences. The radius is in logical pixels, scaled per screen.
public sealed class RoundedCornersSettings
{
    /// Windows 11's own window corners, so a maximized window is concentric with the screen's.
    public const double DefaultRadius = 8, MinimumRadius = 2, MaximumRadius = 40;

    public Setting<double> Radius { get; } = SettingsStore.Shared.Get("roundedCornersRadius", DefaultRadius);

    /// Back to the default radius; the on/off switch stays.
    public void Reset() => Radius.Reset();
}
