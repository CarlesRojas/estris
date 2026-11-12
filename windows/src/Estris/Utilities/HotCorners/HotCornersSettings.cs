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

/// Hot Corners preferences: an action for each corner, the delay, and full-screen apps.
public sealed class HotCornersSettings
{
    private static SettingsStore Store => SettingsStore.Shared;

    public const double DefaultDelay = 0, MaximumDelay = 1000, DelayStep = 50;
    public const bool DefaultIgnoresFullScreen = true;

    public Setting<HotCornerAction> TopLeft { get; } = Store.Get("hotCornersTopLeft", HotCornerAction.Nothing);
    public Setting<HotCornerAction> TopRight { get; } = Store.Get("hotCornersTopRight", HotCornerAction.TaskView);
    public Setting<HotCornerAction> BottomLeft { get; } = Store.Get("hotCornersBottomLeft", HotCornerAction.Nothing);
    public Setting<HotCornerAction> BottomRight { get; } = Store.Get("hotCornersBottomRight", HotCornerAction.ShowDesktop);
    /// How long the pointer rests in a corner before the action runs, in milliseconds.
    public Setting<double> Delay { get; } = Store.Get("hotCornersDelay", DefaultDelay);
    public Setting<bool> IgnoresFullScreen { get; } = Store.Get("hotCornersIgnoreFullScreen", DefaultIgnoresFullScreen);

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
    }
}
