using System.Text.Json.Serialization;
using Estris.Core;

namespace Estris.Utilities.VolumeMixer;

/// How one app sounds: remembered for the next time it plays, also after quitting it.
/// Volume goes from 0 to 1, where 1 plays the app as it is. OutputId is the device it plays on,
/// null following the system; OutputName is shown while that device isn't connected.
public sealed record AppSound(double Volume = 1, bool IsMuted = false, string? OutputId = null, string? OutputName = null)
{
    /// Played as Windows would without Estris.
    [JsonIgnore] public bool IsUntouched => Volume >= 1 && !IsMuted && OutputId is null;
}

/// Volume Mixer preferences.
public sealed class VolumeMixerSettings
{
    private static readonly SettingsStore Store = SettingsStore.Shared;

    /// By program name.
    public Setting<Dictionary<string, AppSound>> Apps { get; } = Store.Get("volumeMixerApps", new Dictionary<string, AppSound>());
    /// Program names of apps the mixer ignores: never listed, never changed.
    public Setting<List<string>> ExcludedApps { get; } = Store.Get("volumeMixerExcludedApps", new List<string>());
}
