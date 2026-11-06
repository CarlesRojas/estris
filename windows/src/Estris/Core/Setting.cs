using System.ComponentModel;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Estris.Core;

/// One saved value and its default. Settings classes hold these: the default lives here, so
/// a pane's Reset to Defaults and each row's Reset to Default can never disagree.
public interface ISetting
{
    bool IsDefault { get; }
    void Reset();
    event Action? Changed;
}

public sealed class Setting<T> : ISetting, INotifyPropertyChanged
{
    private readonly SettingsStore store;
    private readonly string key;
    private T value;

    public T Default { get; }
    public event Action? Changed;
    public event PropertyChangedEventHandler? PropertyChanged;

    internal Setting(SettingsStore store, string key, T defaultValue)
    {
        this.store = store;
        this.key = key;
        Default = defaultValue;
        value = store.Read(key, defaultValue);
    }

    public T Value
    {
        get => value;
        set
        {
            if (EqualityComparer<T>.Default.Equals(this.value, value)) return;
            this.value = value;
            store.Write(key, value);
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Value)));
            Changed?.Invoke();
        }
    }

    public bool IsDefault => JsonSerializer.Serialize(value) == JsonSerializer.Serialize(Default);
    public void Reset() => Value = Default;
}

/// Everything saved, as one JSON file in %APPDATA%\Estris, written shortly after a change.
/// The installer replaces the app's own folder, so nothing is kept there.
public sealed class SettingsStore
{
    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };
    public static string Folder { get; } = @"C:\Users\carle\AppData\Local\Temp\estris-t\appdata";

    public static SettingsStore Shared { get; } = new();

    private readonly string path = Path.Combine(Folder, "settings.json");
    private readonly object gate = new();
    private readonly Timer saveTimer;
    private JsonObject values;

    private SettingsStore()
    {
        Directory.CreateDirectory(Folder);
        saveTimer = new Timer(_ => Flush());
        values = Load(path);
    }

    private static JsonObject Load(string path)
    {
        try { return JsonNode.Parse(File.ReadAllText(path))?.AsObject() ?? []; }
        catch { return []; }
    }

    public Setting<T> Get<T>(string key, T defaultValue) => new(this, key, defaultValue);

    internal T Read<T>(string key, T fallback)
    {
        lock (gate)
        {
            if (!values.TryGetPropertyValue(key, out var node) || node is null) return fallback;
            try { return node.Deserialize<T>() ?? fallback; }
            catch { return fallback; }
        }
    }

    internal void Write<T>(string key, T value)
    {
        lock (gate) values[key] = JsonSerializer.SerializeToNode(value);
        saveTimer.Change(300, Timeout.Infinite);
    }

    /// Whether this key was saved before, for one-time setup.
    public bool Has(string key)
    {
        lock (gate) return values.ContainsKey(key);
    }

    public void Flush()
    {
        lock (gate)
        {
            var temp = path + ".tmp";
            File.WriteAllText(temp, values.ToJsonString(Options));
            File.Move(temp, path, overwrite: true);
        }
    }

    /// Every setting, for Export Settings. Keys starting with "local." are tied to this PC.
    public string Export()
    {
        lock (gate)
        {
            var copy = new JsonObject();
            foreach (var (key, node) in values)
                if (!key.StartsWith("local.")) copy[key] = node?.DeepClone();
            return copy.ToJsonString(Options);
        }
    }

    /// Replaces the settings with an exported file. Estris relaunches right after to apply it.
    /// Throws if the file isn't one.
    public void Import(string json)
    {
        var imported = JsonNode.Parse(json)?.AsObject() ?? throw new InvalidDataException();
        lock (gate)
        {
            foreach (var (key, node) in values)
                if (key.StartsWith("local.")) imported[key] = node?.DeepClone();
            values = imported;
        }
        Flush();
    }
}
