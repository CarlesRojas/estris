namespace Estris.Core;

/// What the utilities noticed and decided, for Developer > Logs. Keeps the latest 2,000 lines.
public sealed class AppLog
{
    public sealed record Entry(DateTime Time, string Source, string Message);

    private const int Limit = 2000;
    private readonly List<Entry> entries = [];

    public event Action? Changed;

    public IReadOnlyList<Entry> Entries
    {
        get { lock (entries) return entries.ToArray(); }
    }

    public void Add(string source, string message)
    {
        lock (entries)
        {
            entries.Add(new Entry(DateTime.Now, source, message));
            if (entries.Count > Limit) entries.RemoveAt(0);
        }
        System.Diagnostics.Debug.WriteLine($"[{source}] {message}");
        Changed?.Invoke();
    }

    public void Clear()
    {
        lock (entries) entries.Clear();
        Changed?.Invoke();
    }
}
