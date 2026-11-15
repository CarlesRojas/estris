using System.Text.Json.Serialization;
using Estris.Core;

namespace Estris.Utilities.HotCorners;

public enum Corner { TopLeft, TopRight, BottomLeft, BottomRight }

/// What pushing the pointer into a corner does. Each one toggles, so a second push undoes it.
[JsonConverter(typeof(JsonStringEnumConverter<HotCornerAction>))]
public enum HotCornerAction
{
    Nothing, ShowDesktop, TaskView, StartMenu, Search, NotificationCenter, QuickSettings, Widgets, SleepDisplay, LockScreen,
}

/// What each corner of one screen does.
public sealed record CornerActions(HotCornerAction TopLeft, HotCornerAction TopRight, HotCornerAction BottomLeft, HotCornerAction BottomRight)
{
    public HotCornerAction this[Corner corner] => corner switch
    {
        Corner.TopLeft => TopLeft,
        Corner.TopRight => TopRight,
        Corner.BottomLeft => BottomLeft,
        _ => BottomRight,
    };

    public CornerActions With(Corner corner, HotCornerAction action) => corner switch
    {
        Corner.TopLeft => this with { TopLeft = action },
        Corner.TopRight => this with { TopRight = action },
        Corner.BottomLeft => this with { BottomLeft = action },
        _ => this with { BottomRight = action },
    };

    public bool HasAny => Enum.GetValues<Corner>().Any(c => this[c] != HotCornerAction.Nothing);
}

/// Hot Corners preferences: an action for each corner, or for each corner of each display, the
/// delay, and full-screen apps.
public sealed class HotCornersSettings
{
    private static SettingsStore Store => SettingsStore.Shared;

    public const double DefaultDelay = 0, MaximumDelay = 1000, DelayStep = 50;
    public const bool DefaultIgnoresFullScreen = true;
    public const bool DefaultSeparatesDisplays = false;

    public Setting<HotCornerAction> TopLeft { get; } = Store.Get("hotCornersTopLeft", HotCornerAction.Nothing);
    public Setting<HotCornerAction> TopRight { get; } = Store.Get("hotCornersTopRight", HotCornerAction.Nothing);
    public Setting<HotCornerAction> BottomLeft { get; } = Store.Get("hotCornersBottomLeft", HotCornerAction.Nothing);
    public Setting<HotCornerAction> BottomRight { get; } = Store.Get("hotCornersBottomRight", HotCornerAction.Nothing);
    /// How long the pointer rests in a corner before the action runs, in milliseconds.
    public Setting<double> Delay { get; } = Store.Get("hotCornersDelay", DefaultDelay);
    public Setting<bool> IgnoresFullScreen { get; } = Store.Get("hotCornersIgnoreFullScreen", DefaultIgnoresFullScreen);
    /// Each display has its own corners. Tied to this PC's monitors, so not exported.
    public Setting<bool> SeparatesDisplays { get; } = Store.Get("local.hotCornersSeparateDisplays", DefaultSeparatesDisplays);
    /// Each display's corners, by its ID (Displays). A display not in here uses the shared ones.
    /// Always replaced, never changed in place: the mouse hook reads it from its own thread.
    public Setting<Dictionary<string, CornerActions>> PerDisplay { get; } = Store.Get("local.hotCornersDisplays", new Dictionary<string, CornerActions>());

    /// The corners every display uses while they aren't separate.
    public CornerActions Shared => new(TopLeft.Value, TopRight.Value, BottomLeft.Value, BottomRight.Value);

    /// The corners of that display: its own while each display has its own, if it has any yet.
    public CornerActions CornersOf(string? display) =>
        SeparatesDisplays.Value && display is not null && PerDisplay.Value.TryGetValue(display, out var own) ? own : Shared;

    /// Sets a corner of one display, which takes the shared corners for the others the first time.
    public void Set(string display, Corner corner, HotCornerAction action)
    {
        var current = CornersOf(display);
        if (current[corner] == action) return;
        PerDisplay.Value = new Dictionary<string, CornerActions>(PerDisplay.Value) { [display] = current.With(corner, action) };
    }

    /// Whether any corner anywhere does something.
    public bool HasAny => Shared.HasAny || (SeparatesDisplays.Value && PerDisplay.Value.Values.Any(d => d.HasAny));

    public Setting<HotCornerAction> For(Corner corner) => corner switch
    {
        Corner.TopLeft => TopLeft,
        Corner.TopRight => TopRight,
        Corner.BottomLeft => BottomLeft,
        _ => BottomRight,
    };

    /// Back to the defaults; the on/off switch stays.
    public void Reset()
    {
        TopLeft.Reset();
        TopRight.Reset();
        BottomLeft.Reset();
        BottomRight.Reset();
        Delay.Reset();
        IgnoresFullScreen.Reset();
        SeparatesDisplays.Reset();
        PerDisplay.Reset();
    }
}
