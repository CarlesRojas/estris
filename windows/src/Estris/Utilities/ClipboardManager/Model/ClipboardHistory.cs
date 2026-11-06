using System.Text.Json;
using Estris.Core;

namespace Estris.Utilities.ClipboardManager;

/// Most recent entry first, saved next to its payloads so it survives restarts. Used from the
/// UI thread; saving happens shortly after a change, on its own.
public sealed class ClipboardHistory
{
    private const int SaveDelay = 200;
    private static readonly string FilePath = Path.Combine(ClipPayloadStore.Directory, "history.json");

    private readonly AppLog log;
    private readonly object fileGate = new();
    private readonly Timer saveTimer;
    private List<ClipItem> items;
    private int limit = 50;

    /// Runs on the UI thread after any change.
    public event Action? Changed;

    public ClipboardHistory(AppLog log)
    {
        this.log = log;
        items = Load();
        saveTimer = new Timer(_ => Save());
        var kept = items.Select(i => i.Id).ToHashSet();
        Task.Run(() => ClipPayloadStore.DeleteAll(kept));
    }

    public IReadOnlyList<ClipItem> Items => items;

    public int Limit
    {
        get => limit;
        set
        {
            limit = value;
            if (items.Count > limit) Replace(items.Take(limit).ToList());
        }
    }

    /// Adds item as the most recent entry. With removingDuplicates, an older entry with the same
    /// content is dropped, so it moves to the top instead of appearing twice.
    public void Add(ClipItem item, bool removingDuplicates)
    {
        var updated = removingDuplicates ? items.Where(i => !i.HasSameContent(item)).ToList() : items.ToList();
        updated.Insert(0, item);
        Replace(updated.Take(limit).ToList());
    }

    public void RemoveEntries(DateTime olderThan)
    {
        if (items.Any(i => i.Date < olderThan)) Replace(items.Where(i => i.Date >= olderThan).ToList());
    }

    public void Promote(ClipItem item)
    {
        var index = items.FindIndex(i => i.Id == item.Id);
        if (index <= 0) return;
        var updated = items.ToList();
        updated.RemoveAt(index);
        updated.Insert(0, item);
        Replace(updated);
    }

    public void Remove(ClipItem item) => Replace(items.Where(i => i.Id != item.Id).ToList());

    public void Clear() => Replace([]);

    private void Replace(List<ClipItem> updated)
    {
        var kept = updated.Select(i => i.Id).ToHashSet();
        var removed = items.Where(i => !kept.Contains(i.Id)).Select(i => i.Id).ToList();
        items = updated;
        if (removed.Count > 0) Task.Run(() => removed.ForEach(ClipPayloadStore.Delete));
        saveTimer.Change(SaveDelay, Timeout.Infinite);
        Changed?.Invoke();
    }

    private static List<ClipItem> Load()
    {
        try { return JsonSerializer.Deserialize<List<ClipItem>>(File.ReadAllText(FilePath)) ?? []; }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { return []; }
    }

    /// Writes the current entries now, as quitting does.
    public void Save()
    {
        var snapshot = items;
        lock (fileGate)
        {
            try
            {
                Directory.CreateDirectory(ClipPayloadStore.Directory);
                var temporary = FilePath + ".tmp";
                File.WriteAllText(temporary, JsonSerializer.Serialize(snapshot));
                File.Move(temporary, FilePath, overwrite: true);
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                log.Add("Clipboard", $"Failed to save history: {e.Message}");
            }
        }
    }
}
