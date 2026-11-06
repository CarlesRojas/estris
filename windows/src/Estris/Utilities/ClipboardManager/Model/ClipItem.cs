namespace Estris.Utilities.ClipboardManager;

/// What an entry holds. Images keep their clipboard formats in a payload file and files their
/// paths, so pasting them gives back what was copied. Text is always plain.
public enum ClipKind { Text, Image, Files }

public sealed record ClipItem
{
    public Guid Id { get; init; } = Guid.NewGuid();
    /// Plain text to show and search: the text itself, or the file names for files.
    public required string Text { get; init; }
    public DateTime Date { get; init; } = DateTime.Now;
    /// The program the entry was copied from, as a full path. Null when Windows won't say.
    public string? SourcePath { get; init; }
    public ClipKind Kind { get; init; } = ClipKind.Text;
    /// Identifies the content, for spotting duplicates of non-text entries.
    public string? Fingerprint { get; init; }
    /// Whether full clipboard contents were saved next to the history.
    public bool HasPayload { get; init; }
    /// The image's size in pixels, for images.
    public int PixelWidth { get; init; }
    public int PixelHeight { get; init; }
    /// The copied paths, for files.
    public List<string> Files { get; init; } = [];

    /// Two entries hold the same content.
    public bool HasSameContent(ClipItem other) =>
        Fingerprint is not null && other.Fingerprint is not null
            ? Fingerprint == other.Fingerprint
            : Kind == other.Kind && Text == other.Text;
}
