using Estris.Core;
using static Estris.Core.Loc;

namespace Estris.Utilities.WindowSnapping;

/// A drag-to-snap area, switched on or off on its own.
public enum SnapGesture
{
    TopLeft, TopRight, BottomLeft, BottomRight, Maximize,
    LeftHalf, RightHalf, TopHalf, BottomHalf, Thirds, TwoThirds,
}

public static class SnapGestures
{
    public static readonly SnapGesture[] All = Enum.GetValues<SnapGesture>();

    public static string Title(this SnapGesture gesture) => gesture switch
    {
        SnapGesture.TopLeft => T("Top left corner"),
        SnapGesture.TopRight => T("Top right corner"),
        SnapGesture.BottomLeft => T("Bottom left corner"),
        SnapGesture.BottomRight => T("Bottom right corner"),
        SnapGesture.Maximize => T("Top edge: maximize"),
        SnapGesture.LeftHalf => T("Left edge: left half"),
        SnapGesture.RightHalf => T("Right edge: right half"),
        SnapGesture.TopHalf => T("Side edges near the top: top half"),
        SnapGesture.BottomHalf => T("Side edges near the bottom: bottom half"),
        SnapGesture.Thirds => T("Bottom edge: thirds"),
        _ => T("Bottom edge: two thirds when sliding to the middle"),
    };

    /// On unless it splits the screen into top and bottom.
    public static bool IsOnByDefault(this SnapGesture gesture) => gesture is not (SnapGesture.TopHalf or SnapGesture.BottomHalf);
}

public sealed class WindowSnappingSettings
{
    public const double MinimumEdgeArea = 8, MaximumEdgeArea = 150;

    private static readonly SettingsStore Store = SettingsStore.Shared;

    public Setting<bool> Enabled { get; } = Store.Get("windowSnappingEnabled", false);
    /// Snap a window by dragging it to a screen edge or corner.
    public Setting<bool> SnapsByDragging { get; } = Store.Get("windowSnappingByDragging", true);
    /// Resizing a window also resizes the windows sharing the edge being dragged.
    public Setting<bool> ResizesTogether { get; } = Store.Get("windowSnappingResizesTogether", true);
    /// Fit snaps to the space left by windows already tiled on the screen.
    public Setting<bool> FillsSpace { get; } = Store.Get("windowSnappingFillsSpace", true);
    /// How far into the screen, in logical pixels, the edges reach for dragging.
    public Setting<double> EdgeArea { get; } = Store.Get("windowSnappingEdgeArea", 64.0);
    /// A shortcut shares the screen evenly among all its windows.
    public Setting<bool> ArrangesAll { get; } = Store.Get("windowSnappingArrangesAll", true);
    /// Keys chosen for the shortcuts, by id; missing ones keep their default.
    public Setting<Dictionary<string, int>> KeyCodes { get; } = Store.Get("windowSnappingKeyCodes", new Dictionary<string, int>());
    /// The drag areas that snap.
    public Setting<List<string>> Gestures { get; } = Store.Get("windowSnappingGestures",
        SnapGestures.All.Where(g => g.IsOnByDefault()).Select(g => g.ToString()).ToList());

    public int Key(string id) => KeyCodes.Value.TryGetValue(id, out var vk) ? vk : SnapKeys.DefaultKey(id);

    public void SetKey(string id, int? vk)
    {
        var keys = new Dictionary<string, int>(KeyCodes.Value);
        if (vk is null || vk == SnapKeys.DefaultKey(id)) keys.Remove(id);
        else keys[id] = vk.Value;
        KeyCodes.Value = keys;
    }

    public bool Has(SnapGesture gesture) => Gestures.Value.Contains(gesture.ToString());

    public void Set(SnapGesture gesture, bool isOn)
    {
        var gestures = Gestures.Value.Where(g => g != gesture.ToString()).ToList();
        if (isOn) gestures.Add(gesture.ToString());
        Gestures.Value = gestures;
    }

    /// Back to how dragging, resizing, gestures, Arrange All and the shortcut keys start out;
    /// the on/off switch stays.
    public void Reset()
    {
        foreach (var setting in new ISetting[] { ArrangesAll, KeyCodes, SnapsByDragging, ResizesTogether, FillsSpace, EdgeArea, Gestures })
            setting.Reset();
    }
}

/// One shortcut's key as a setting of its own, for its row's Reset to Default.
public sealed class SnapKeySetting : ISetting
{
    private readonly WindowSnappingSettings settings;
    private readonly string id;

    public SnapKeySetting(WindowSnappingSettings settings, string id)
    {
        this.settings = settings;
        this.id = id;
        settings.KeyCodes.Changed += () => Changed?.Invoke();
    }

    public bool IsDefault => !settings.KeyCodes.Value.ContainsKey(id);
    public void Reset() => settings.SetKey(id, null);
    public event Action? Changed;
}

/// One gesture's switch as a setting of its own, for its row's Reset to Default.
public sealed class SnapGestureSetting : ISetting
{
    private readonly WindowSnappingSettings settings;
    private readonly SnapGesture gesture;

    public SnapGestureSetting(WindowSnappingSettings settings, SnapGesture gesture)
    {
        this.settings = settings;
        this.gesture = gesture;
        settings.Gestures.Changed += () => Changed?.Invoke();
    }

    public bool IsDefault => settings.Has(gesture) == gesture.IsOnByDefault();
    public void Reset() => settings.Set(gesture, gesture.IsOnByDefault());
    public event Action? Changed;
}
