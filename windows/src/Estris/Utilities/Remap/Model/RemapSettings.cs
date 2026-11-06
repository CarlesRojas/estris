using Estris.Core;
using static Estris.Core.Loc;

namespace Estris.Utilities.Remap;

/// A key or button and what it does instead. Either side is empty until chosen; an incomplete
/// mapping does nothing.
public sealed record Mapping
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public RemapInput? Input { get; init; }
    public RemapOutput? Output { get; init; }
    /// When it was added; the oldest wins when mappings on several devices compete.
    public DateTime? Created { get; init; } = DateTime.UtcNow;
    /// Recorded from a press with no device. Only these can compete with mappings on other
    /// devices; a key picked from the list belongs to its device.
    public bool? IsDeviceLess { get; init; }
}

/// A device's mappings, with its name kept so it still shows while disconnected.
public sealed record DeviceMappings(string Name, DeviceKind Kind, List<Mapping> Mappings);

public enum ConflictKind { Above, OtherDevice }

public sealed record MappingConflict(ConflictKind Kind, string Device = "")
{
    public string Message => Kind == ConflictKind.Above ? T("Already mapped above") : T("Already mapped on %@", Device);

    public string Explanation => Kind == ConflictKind.Above
        ? T("Only the first mapping for a key or button applies.")
        : T("This press reaches Windows without saying which device sent it, so only the mapping on %@ applies.", Device);
}

/// Remap's settings. Mappings per device, keyed by InputDevice.Id, and the names given to devices.
public sealed class RemapSettings
{
    public Setting<bool> Enabled { get; } = SettingsStore.Shared.Get("remapEnabled", false);
    public Setting<Dictionary<string, DeviceMappings>> Devices { get; } = SettingsStore.Shared.Get("remapDevices", new Dictionary<string, DeviceMappings>());
    public Setting<Dictionary<string, string>> CustomNames { get; } = SettingsStore.Shared.Get("remapDeviceNames", new Dictionary<string, string>());
    /// Devices the user said are of another kind than Windows's reports suggest.
    public Setting<Dictionary<string, DeviceKind>> CustomKinds { get; } = SettingsStore.Shared.Get("remapDeviceKinds", new Dictionary<string, DeviceKind>());

    public RemapSettings() => RemoveEmptyMappings();

    /// The device's name, as renamed by the user if it was.
    public string Name(InputDevice device) => CustomNames.Value.GetValueOrDefault(device.Id) ?? device.Name;

    /// The device's kind, as set by the user if it was.
    public DeviceKind Kind(InputDevice device) => CustomKinds.Value.GetValueOrDefault(device.Id, device.Kind);

    /// Sets a device's kind; the one it was detected as just forgets the choice.
    public void SetKind(string deviceId, DeviceKind kind, DeviceKind? detected)
    {
        var kinds = new Dictionary<string, DeviceKind>(CustomKinds.Value);
        if (kind == detected) kinds.Remove(deviceId);
        else kinds[deviceId] = kind;
        CustomKinds.Value = kinds;
    }

    /// Renames a device; an empty name goes back to the one it reports.
    public void Rename(string deviceId, string name)
    {
        var names = new Dictionary<string, string>(CustomNames.Value);
        if (name.Trim() == "") names.Remove(deviceId);
        else names[deviceId] = name.Trim();
        CustomNames.Value = names;
    }

    public IReadOnlyList<Mapping> Mappings(string deviceId) =>
        Devices.Value.GetValueOrDefault(deviceId)?.Mappings ?? [];

    private (string Id, DeviceMappings Entry)? ActiveDevice(RemapInput input)
    {
        var candidates =
            from pair in Devices.Value
            let first = pair.Value.Mappings.FirstOrDefault(m => m.Input == input)
            where first is { IsDeviceLess: true, Output: not null }
            orderby first.Created ?? DateTime.MinValue, pair.Key
            select (pair.Key, pair.Value);
        var found = candidates.ToList();
        return found.Count > 0 ? found[0] : null;
    }

    /// Why a mapping doesn't apply, or null when it does: an earlier row on the same device has
    /// the same key or button, or, for a device-less one, another device's device-less mapping
    /// wins. Mappings on different devices never compete otherwise.
    public MappingConflict? Conflict(Mapping mapping, string deviceId)
    {
        if (mapping.Input is not { } input) return null;
        var first = Mappings(deviceId).FirstOrDefault(m => m.Input == input);
        if (first is not null && first.Id != mapping.Id) return new MappingConflict(ConflictKind.Above);
        if (mapping.IsDeviceLess != true || ActiveDevice(input) is not { } active || active.Id == deviceId) return null;
        return new MappingConflict(ConflictKind.OtherDevice, CustomNames.Value.GetValueOrDefault(active.Id) ?? active.Entry.Name);
    }

    /// Adds an empty mapping at the end of the device's list.
    public void AddMapping(InputDevice device) => Change(device, list => list.Add(new Mapping()));

    /// Adds a mapping from a key or button, unless the device already has one for it.
    public void AddMapping(RemapInput input, InputDevice device)
    {
        if (!Mappings(device.Id).Any(m => m.Input == input))
            Change(device, list => list.Add(new Mapping { Input = input }));
    }

    /// Changes a mapping. Another one for the same key or button stays; only the first applies.
    public void Update(Mapping mapping, string deviceId)
    {
        if (!Devices.Value.TryGetValue(deviceId, out var entry)) return;
        var list = entry.Mappings.Select(m => m.Id == mapping.Id ? mapping : m).ToList();
        Store(deviceId, entry with { Mappings = list });
    }

    public void Remove(Mapping mapping, string deviceId)
    {
        if (!Devices.Value.TryGetValue(deviceId, out var entry)) return;
        Store(deviceId, entry with { Mappings = entry.Mappings.Where(m => m.Id != mapping.Id).ToList() });
    }

    /// Drops mappings with neither side chosen.
    public void RemoveEmptyMappings()
    {
        var empty = Devices.Value.Where(d => d.Value.Mappings.Any(IsEmpty)).ToList();
        foreach (var (id, entry) in empty)
            Store(id, entry with { Mappings = entry.Mappings.Where(m => !IsEmpty(m)).ToList() });
    }

    private static bool IsEmpty(Mapping mapping) => mapping.Input is null && mapping.Output is null;

    private void Change(InputDevice device, Action<List<Mapping>> change)
    {
        var entry = Devices.Value.GetValueOrDefault(device.Id);
        var list = entry?.Mappings.ToList() ?? [];
        change(list);
        Store(device.Id, new DeviceMappings(device.Name, device.Kind, list));
    }

    private void Store(string deviceId, DeviceMappings entry) =>
        Devices.Value = new Dictionary<string, DeviceMappings>(Devices.Value) { [deviceId] = entry };

    /// What applies now: the mappings of the devices plugged in, and the device-less ones of any
    /// device. Mappings of the same device are read in order; only the first for an input counts,
    /// and a row still missing its result leaves that input unmapped.
    public MappingTable BuildTable(IReadOnlyList<InputDevice> connected)
    {
        var isConnected = connected.Select(d => d.Id).ToHashSet();
        var devices = new Dictionary<string, Dictionary<RemapInput, RemapOutput>>();
        var deviceLess = new Dictionary<RemapInput, RemapOutput>();
        foreach (var (id, entry) in Devices.Value.OrderBy(d => d.Value.Mappings.Min(m => m.Created) ?? DateTime.MinValue))
        {
            var mappings = new Dictionary<RemapInput, RemapOutput>();
            var seen = new HashSet<RemapInput>();
            foreach (var mapping in entry.Mappings)
            {
                if (mapping.Input is not { } input || !seen.Add(input) || mapping.Output is not { } output) continue;
                if (input == RemapInput.LeftButton) continue;
                mappings[input] = output;
                if (mapping.IsDeviceLess == true && ActiveDevice(input)?.Id == id) deviceLess[input] = output;
            }
            if (isConnected.Contains(id)) devices[id] = mappings;
        }
        foreach (var device in connected) devices.TryAdd(device.Id, []);
        return new MappingTable(devices, deviceLess, connected.Where(d => Kind(d) == DeviceKind.Keyboard).Select(d => d.Id).ToList());
    }
}
