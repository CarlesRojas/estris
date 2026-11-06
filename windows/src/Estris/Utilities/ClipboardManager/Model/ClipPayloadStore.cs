using System.Security.Cryptography;
using System.Text;

namespace Estris.Utilities.ClipboardManager;

/// Saves entry contents, thumbnails and copies of files next to the history in
/// %LOCALAPPDATA%\Estris\history, and removes them with their entry.
public static class ClipPayloadStore
{
    /// Larger copies (a huge image, say) are not kept.
    public const long MaxPayloadBytes = 25 * 1024 * 1024;

    public static string Directory { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Estris", "history");

    private static string PayloadPath(Guid id) => Path.Combine(Directory, $"{id}.payload");
    public static string ThumbnailPath(Guid id) => Path.Combine(Directory, $"{id}-thumbnail.png");
    private static string FilesPath(Guid id) => Path.Combine(Directory, id.ToString());

    /// Clipboard formats by name, each with its bytes.
    public static void Save(Guid id, Dictionary<string, byte[]> formats, byte[]? thumbnail)
    {
        System.IO.Directory.CreateDirectory(Directory);
        using (var writer = new BinaryWriter(File.Create(PayloadPath(id))))
        {
            writer.Write(formats.Count);
            foreach (var (name, data) in formats)
            {
                writer.Write(name);
                writer.Write(data.Length);
                writer.Write(data);
            }
        }
        if (thumbnail is not null) File.WriteAllBytes(ThumbnailPath(id), thumbnail);
    }

    public static Dictionary<string, byte[]>? Load(Guid id)
    {
        try
        {
            using var reader = new BinaryReader(File.OpenRead(PayloadPath(id)));
            var formats = new Dictionary<string, byte[]>();
            for (var count = reader.ReadInt32(); count > 0; count--)
            {
                var name = reader.ReadString();
                formats[name] = reader.ReadBytes(reader.ReadInt32());
            }
            return formats;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return null; }
    }

    /// Keeps a copy of copied files when they fit, so an entry still pastes after the originals
    /// are gone. Folders and anything that can't be read stay as paths only.
    public static void KeepFiles(Guid id, IReadOnlyList<string> paths)
    {
        try
        {
            var files = paths.Where(File.Exists).ToList();
            if (files.Count == 0 || files.Sum(f => new FileInfo(f).Length) > MaxPayloadBytes) return;
            for (var index = 0; index < files.Count; index++)
            {
                var folder = Path.Combine(FilesPath(id), index.ToString());
                System.IO.Directory.CreateDirectory(folder);
                File.Copy(files[index], Path.Combine(folder, Path.GetFileName(files[index])));
            }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }

    /// The kept copy of a file, or null.
    public static string? KeptFile(Guid id, string original)
    {
        var folder = FilesPath(id);
        if (!System.IO.Directory.Exists(folder)) return null;
        return System.IO.Directory.EnumerateFiles(folder, Path.GetFileName(original), SearchOption.AllDirectories).FirstOrDefault();
    }

    public static void Delete(Guid id)
    {
        try
        {
            File.Delete(PayloadPath(id));
            File.Delete(ThumbnailPath(id));
            if (System.IO.Directory.Exists(FilesPath(id))) System.IO.Directory.Delete(FilesPath(id), recursive: true);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }

    /// Removes what no entry owns any more, such as after a crash.
    public static void DeleteAll(ISet<Guid> except)
    {
        if (!System.IO.Directory.Exists(Directory)) return;
        foreach (var path in System.IO.Directory.EnumerateFileSystemEntries(Directory))
        {
            var name = Path.GetFileNameWithoutExtension(path).Replace("-thumbnail", "");
            if (Guid.TryParse(name, out var id) && !except.Contains(id)) Delete(id);
        }
    }

    public static string Fingerprint(params IEnumerable<byte[]>[] parts)
    {
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        foreach (var part in parts)
            foreach (var data in part) hash.AppendData(data);
        return Convert.ToHexString(hash.GetHashAndReset());
    }

    public static string Fingerprint(IEnumerable<string> paths) =>
        Fingerprint(paths.Select(path => Encoding.UTF8.GetBytes(path + "\n")));
}
