using Estris.Core;
using static Estris.Core.Loc;

namespace Estris.Utilities.FocusFollowsMouse;

public sealed class FocusFollowsMouseSettings
{
    public const double MinimumPassThroughSpeed = 200, MaximumPassThroughSpeed = 3000, PassThroughSpeedStep = 100;
    public const double MinimumNewAppSeconds = 1, MaximumNewAppSeconds = 15;

    /// The delays to choose from, in milliseconds.
    public static readonly int[] Delays = [0, 100, 250, 500, 1000];

    private static readonly SettingsStore Store = SettingsStore.Shared;

    public Setting<bool> Enabled { get; } = Store.Get("focusFollowsMouseEnabled", false);
    /// How long the pointer stays over a window before it is focused, in milliseconds.
    public Setting<int> Delay { get; } = Store.Get("focusFollowsMouseDelay", 100);
    /// Moving faster than this, in logical pixels per second, is passing through: windows
    /// crossed aren't focused.
    public Setting<double> PassThroughSpeed { get; } = Store.Get("focusFollowsMousePassThroughSpeed", 800.0);
    /// Whether an app that just opened keeps the focus for a while, so the pointer can get
    /// there before hovering other windows takes it away.
    public Setting<bool> KeepsNewAppsInFront { get; } = Store.Get("focusFollowsMouseKeepsNewAppsInFront", true);
    /// For how long, in seconds.
    public Setting<double> NewAppSeconds { get; } = Store.Get("focusFollowsMouseNewAppSeconds", 2.0);
    /// Programs whose windows are never focused by hovering.
    public Setting<List<string>> ExcludedApps { get; } = Store.Get("focusFollowsMouseExcludedApps", new List<string>());

    public static string DelayTitle(int milliseconds) =>
        milliseconds == 0 ? T("Immediately") : T("%lld ms", (long)milliseconds);

    /// Back to the defaults; the on/off switch and excluded apps stay as they are.
    public void Reset()
    {
        foreach (var setting in new ISetting[] { Delay, PassThroughSpeed, KeepsNewAppsInFront, NewAppSeconds })
            setting.Reset();
    }
}
