using Estris.Core;
using static Estris.Core.Loc;

namespace Estris.Utilities.KeepAwake;

/// How long the PC may be idle before Keep Awake lets it sleep. Saved by number: keep the order.
public enum KeepAwakeDuration { Off, FifteenMinutes, ThirtyMinutes, OneHour, TwoHours, FourHours, EightHours, Indefinitely }

public static class KeepAwakeDurations
{
    public static string Title(KeepAwakeDuration duration) => duration switch
    {
        KeepAwakeDuration.Off => T("Don't keep awake"),
        KeepAwakeDuration.FifteenMinutes => T("15 minutes"),
        KeepAwakeDuration.ThirtyMinutes => T("30 minutes"),
        KeepAwakeDuration.OneHour => T("1 hour"),
        KeepAwakeDuration.TwoHours => T("2 hours"),
        KeepAwakeDuration.FourHours => T("4 hours"),
        KeepAwakeDuration.EightHours => T("8 hours"),
        _ => T("Indefinitely"),
    };

    /// Null for no limit; zero for not at all.
    public static TimeSpan? Limit(KeepAwakeDuration duration) => duration switch
    {
        KeepAwakeDuration.Off => TimeSpan.Zero,
        KeepAwakeDuration.FifteenMinutes => Environment.GetEnvironmentVariable("ESTRIS_SHOW") is null ? TimeSpan.FromMinutes(15) : TimeSpan.FromSeconds(20), // TESTONLY
        KeepAwakeDuration.ThirtyMinutes => TimeSpan.FromMinutes(30),
        KeepAwakeDuration.OneHour => TimeSpan.FromHours(1),
        KeepAwakeDuration.TwoHours => TimeSpan.FromHours(2),
        KeepAwakeDuration.FourHours => TimeSpan.FromHours(4),
        KeepAwakeDuration.EightHours => TimeSpan.FromHours(8),
        _ => null,
    };
}

/// Keep Awake preferences.
public sealed class KeepAwakeSettings
{
    private static readonly SettingsStore Store = SettingsStore.Shared;

    /// How long while plugged in.
    public Setting<KeepAwakeDuration> OnPower { get; } = Store.Get("keepAwakeOnPower", KeepAwakeDuration.Indefinitely);
    /// How long while on battery.
    public Setting<KeepAwakeDuration> OnBattery { get; } = Store.Get("keepAwakeOnBattery", KeepAwakeDuration.OneHour);
    /// When the idle time runs out, start the screen saver instead of sleeping.
    public Setting<bool> StartsScreenSaver { get; } = Store.Get("keepAwakeStartsScreenSaver", true);

    /// Back to the default durations and the screen saver; the on/off switch stays.
    public void Reset()
    {
        OnPower.Reset();
        OnBattery.Reset();
        StartsScreenSaver.Reset();
    }
}
