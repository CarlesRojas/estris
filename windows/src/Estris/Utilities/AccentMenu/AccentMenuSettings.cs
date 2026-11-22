using Estris.Core;

namespace Estris.Utilities.AccentMenu;

/// Accent Menu preferences: how long a key is held before its accents show.
public sealed class AccentMenuSettings
{
    private static SettingsStore Store => SettingsStore.Shared;

    /// Windows's own key repeat delay, at its default, as the Mac shows the menu when a key would repeat.
    public const double DefaultDelay = 500, MinimumDelay = 200, MaximumDelay = 1500, DelayStep = 50;

    /// In milliseconds.
    public Setting<double> Delay { get; } = Store.Get("accentMenuDelay", DefaultDelay);

    /// Back to the defaults; the on/off switch stays.
    public void Reset() => Delay.Reset();
}
