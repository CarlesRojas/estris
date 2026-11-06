namespace Estris.Utilities.Remap;

/// One key or button press or release, as shown in the Event Viewer.
public sealed record InputEventRow(
    DateTime Time,
    string Device,
    /// The device and input it came from, when it can be remapped.
    InputDevice? Source,
    RemapInput Input,
    bool IsDown,
    string Name,
    string Detail,
    /// What it was remapped to, if it was.
    string? Result);

/// The latest events, oldest first, while the Event Viewer is open. UI thread only.
public sealed class EventLog
{
    private const int Limit = 300;
    private readonly List<InputEventRow> events = [];

    public IReadOnlyList<InputEventRow> Events => events;
    public event Action<InputEventRow>? Added;
    public event Action? Removed;

    public void Add(InputEventRow row)
    {
        events.Add(row);
        Added?.Invoke(row);
        if (events.Count <= Limit) return;
        events.RemoveAt(0);
        Removed?.Invoke();
    }

    public void Clear()
    {
        var count = events.Count;
        events.Clear();
        for (var i = 0; i < count; i++) Removed?.Invoke();
    }
}
