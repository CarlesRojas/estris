using System.Text.Json.Serialization;

namespace Estris.Utilities.Remap;

/// What a mapping is triggered by: a key, by its scan code (0x100 added for the E0 ones, so it
/// doesn't change with the keyboard layout), or a mouse button by number (0 is the left one).
public readonly record struct RemapInput(bool IsMouse, int Code)
{
    public static readonly RemapInput LeftButton = Button(0);
    public static RemapInput Key(int code) => new(false, code);
    public static RemapInput Button(int number) => new(true, number);

    /// Win and Alt: releasing one alone opens Start or the menu bar.
    [JsonIgnore]
    public bool OpensMenu => !IsMouse && Code is 0x15B or 0x15C or 0x38 or 0x138;
}

public enum OutputKind { Key, MouseButton, Action, Nothing }

/// Things a remapped key or button can do besides typing a key.
[JsonConverter(typeof(JsonStringEnumConverter<SystemAction>))]
public enum SystemAction
{
    TaskView, ShowDesktop, StartMenu, NextDesktop, PreviousDesktop,
    VolumeUp, VolumeDown, Mute, PlayPause, NextTrack, PreviousTrack,
    BrightnessUp, BrightnessDown, SleepDisplay,
    LockScreen, Search, Screenshot, ScreenshotScreen, EmojiPanel, TaskManager,
}

/// What a mapping does instead. Code is the key's or the button's.
public sealed record RemapOutput(OutputKind Kind, int Code = 0, SystemAction? Action = null)
{
    public static readonly RemapOutput Nothing = new(OutputKind.Nothing);
    public static RemapOutput Key(int code) => new(OutputKind.Key, code);
    public static RemapOutput Button(int number) => new(OutputKind.MouseButton, number);
    public static RemapOutput Run(SystemAction action) => new(OutputKind.Action, 0, action);

    /// Whether holding the key repeats it, like the real volume and brightness keys.
    [JsonIgnore]
    public bool Repeats => Action is SystemAction.VolumeUp or SystemAction.VolumeDown or SystemAction.BrightnessUp or SystemAction.BrightnessDown;
}

/// The mappings that apply right now, read on the hook thread, so never changed once made: those
/// of the devices plugged in, and what a press with no device takes. Only the first mapping for
/// an input on a device counts.
public sealed class MappingTable
{
    public static readonly MappingTable Empty = new(new Dictionary<string, Dictionary<RemapInput, RemapOutput>>(), new Dictionary<RemapInput, RemapOutput>(), []);

    private readonly IReadOnlyDictionary<string, Dictionary<RemapInput, RemapOutput>> devices;
    private readonly IReadOnlyDictionary<RemapInput, RemapOutput> deviceLess;
    private readonly IReadOnlyList<string> keyboards;
    private readonly HashSet<RemapInput> mapped = [];

    /// devices: each connected one's mappings, oldest first, including those with none.
    /// deviceLess: what a press with no device takes. keyboards: the connected devices that look
    /// like keyboards.
    public MappingTable(
        IReadOnlyDictionary<string, Dictionary<RemapInput, RemapOutput>> devices,
        IReadOnlyDictionary<RemapInput, RemapOutput> deviceLess,
        IReadOnlyList<string> keyboards)
    {
        this.devices = devices;
        this.deviceLess = deviceLess;
        this.keyboards = keyboards;
        foreach (var mappings in devices.Values) mapped.UnionWith(mappings.Keys);
        mapped.UnionWith(deviceLess.Keys);
    }

    public bool HasKeys => mapped.Any(i => !i.IsMouse);
    public bool HasButtons => mapped.Any(i => i.IsMouse);
    public bool IsMapped(RemapInput input) => mapped.Contains(input);
    public IReadOnlyList<string> Keyboards => keyboards;

    public RemapOutput? Output(string? deviceId, RemapInput input) => deviceId is null
        ? deviceLess.GetValueOrDefault(input)
        : devices.GetValueOrDefault(deviceId)?.GetValueOrDefault(input);

    /// The first device that maps this input, for when nothing says which one sent it.
    public string? DeviceMapping(RemapInput input) =>
        devices.FirstOrDefault(d => d.Value.ContainsKey(input)).Key;

    /// The connected devices that map this input.
    public IEnumerable<string> Mappers(RemapInput input) =>
        devices.Where(d => d.Value.ContainsKey(input)).Select(d => d.Key);

    /// One of these devices, the preferred one if it is among them, when every one of them that is
    /// connected does the same with the input, so it doesn't matter which sent it. Null when they
    /// differ or none is connected.
    public string? Agreed(IEnumerable<string> candidates, RemapInput input, string? preferred)
    {
        var connected = candidates.Where(devices.ContainsKey).Distinct().ToList();
        if (connected.Count == 0) return null;
        var first = Output(connected[0], input);
        if (connected.Any(d => Output(d, input) != first)) return null;
        return preferred is not null && connected.Contains(preferred) ? preferred : connected[0];
    }
}
