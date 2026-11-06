using System.Runtime.InteropServices;
using System.Text;
using Estris.Core;
using static Estris.Core.Native;
using static Estris.Utilities.ClipboardManager.ClipboardNative;

namespace Estris.Utilities.ClipboardManager;

/// Listens for clipboard changes on its own thread and message-only window, and records what is
/// copied: text (always plain), images and files. Reading can wait on the copying app, so it
/// stays away from the UI thread.
public sealed class ClipboardMonitor(ClipboardHistory history, ClipboardSettings settings, AppLog log)
{
    private const string WindowClass = "EstrisClipboardListener";
    /// Marks what Estris itself puts on the clipboard.
    private static readonly uint OwnFormat = RegisterClipboardFormat("Estris Clipboard Item");
    /// Formats password managers and the like put on what must not be kept, and the
    /// "don't add to Windows' clipboard history" flag, which is a DWORD of 0.
    private static readonly uint[] ConcealedFormats =
    [
        RegisterClipboardFormat("ExcludeClipboardContentFromMonitorProcessing"),
        RegisterClipboardFormat("Clipboard Viewer Ignore"),
    ];
    private static readonly uint HistoryFlagFormat = RegisterClipboardFormat("CanIncludeInClipboardHistory");
    private static readonly uint PngFormat = RegisterClipboardFormat("PNG");
    private static readonly uint MimePngFormat = RegisterClipboardFormat("image/png");
    private const string PngName = "PNG";
    /// Formats tied to the copying app's running objects, useless once saved.
    private static readonly HashSet<string> TransientFormats =
        ["DataObject", "Ole Private Data", "OlePrivateData", "Object Descriptor", "Link Source Descriptor", "Link Source", "Embed Source", "Embedded Object", "Native", "OwnerLink", "ObjectLink", "Shell IDList Array"];

    private const int OpenAttempts = 20, OpenRetryDelay = 10;
    /// Apps often set the clipboard several times for one copy: wait for them to finish.
    private const uint SettleDelay = 40;
    private const nuint SettleTimer = 1;

    private readonly WindowProc windowProc = StaticProc;
    private static ClipboardMonitor? current;
    private Thread? thread;
    private nint hwnd;
    private uint lastSequence;

    /// Starts watching. recordingCurrent also records what is on the clipboard now; when turning
    /// back on it is skipped, since that was copied while switched off.
    public void Start(bool recordingCurrent)
    {
        if (thread is not null) return;
        current = this;
        using var ready = new ManualResetEventSlim();
        thread = new Thread(() => Run(ready, recordingCurrent)) { IsBackground = true, Name = "Clipboard" };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        ready.Wait();
    }

    public void Stop()
    {
        if (thread is null) return;
        PostMessage(hwnd, WM_CLOSE, 0, 0);
        thread.Join();
        thread = null;
        hwnd = 0;
    }

    private void Run(ManualResetEventSlim ready, bool recordingCurrent)
    {
        var className = Marshal.StringToHGlobalUni(WindowClass);
        var windowClass = new WNDCLASSEX
        {
            cbSize = Marshal.SizeOf<WNDCLASSEX>(),
            lpfnWndProc = Marshal.GetFunctionPointerForDelegate(windowProc),
            hInstance = GetModuleHandle(null),
            lpszClassName = className,
        };
        RegisterClassEx(ref windowClass);
        hwnd = CreateWindowEx(0, WindowClass, null, 0, 0, 0, 0, 0, HWND_MESSAGE, 0, GetModuleHandle(null), 0);
        lastSequence = GetClipboardSequenceNumber();
        AddClipboardFormatListener(hwnd);
        ready.Set();
        if (recordingCurrent) Capture();

        while (GetMessage(out var message, 0, 0, 0) > 0)
        {
            TranslateMessage(ref message);
            DispatchMessage(ref message);
        }
    }

    private static nint StaticProc(nint hwnd, uint message, nint wParam, nint lParam)
    {
        switch (message)
        {
            case WM_CLIPBOARDUPDATE:
                SetTimer(hwnd, SettleTimer, SettleDelay, 0);
                return 0;
            case WM_TIMER:
                KillTimer(hwnd, SettleTimer);
                current?.OnChanged();
                return 0;
            case WM_CLOSE:
                RemoveClipboardFormatListener(hwnd);
                DestroyWindow(hwnd);
                return 0;
            case WM_DESTROY:
                PostQuitMessage(0);
                return 0;
            default:
                return DefWindowProc(hwnd, message, wParam, lParam);
        }
    }

    private void OnChanged()
    {
        var sequence = GetClipboardSequenceNumber();
        if (sequence == lastSequence) return;
        lastSequence = sequence;
        Capture();
    }

    private bool Open()
    {
        for (var attempt = 0; attempt < OpenAttempts; attempt++)
        {
            if (OpenClipboard(hwnd)) return true;
            Thread.Sleep(OpenRetryDelay);
        }
        return false;
    }

    /// What was read while the clipboard was open, to finish after closing it.
    private sealed record Copied(ClipKind Kind, string? SourcePath, string? Text = null, List<string>? Files = null, byte[]? Png = null, byte[]? Dib = null, Dictionary<string, byte[]>? Others = null);

    private void Capture()
    {
        if (!Open())
        {
            log.Add("Clipboard", "Couldn't open the clipboard to read it");
            return;
        }
        Copied? copied;
        try { copied = Read(); }
        catch (Exception e) when (e is ExternalException or OutOfMemoryException)
        {
            log.Add("Clipboard", $"Failed to read the clipboard: {e.Message}");
            return;
        }
        finally { CloseClipboard(); }
        if (copied is null) return;

        var item = Finish(copied);
        if (item is null) return;
        App.Ui.TryEnqueue(() => history.Add(item, settings.RemoveDuplicates.Value));
        if (item.Kind == ClipKind.Files) ClipPayloadStore.KeepFiles(item.Id, item.Files);
    }

    private Copied? Read()
    {
        if (IsClipboardFormatAvailable(OwnFormat)) return null;
        if (settings.IgnorePasswords.Value && IsConcealed()) return null;

        var source = SourcePath();
        if (source is not null && settings.ExcludedApps.Value.Contains(Path.GetFileName(source).ToLowerInvariant())) return null;

        if (ReadFormat(CF_HDROP) is { } drop && ParseDrop(drop) is { Count: > 0 } files)
            return new Copied(ClipKind.Files, source, Files: files);

        if (ReadFormat(CF_UNICODETEXT) is { } text)
        {
            var value = Encoding.Unicode.GetString(text).TrimEnd('\0');
            if (!string.IsNullOrWhiteSpace(value)) return new Copied(ClipKind.Text, source, Text: value);
        }

        var png = ReadFormat(PngFormat) ?? ReadFormat(MimePngFormat);
        var dib = png is null ? ReadFormat(CF_DIB) : null;
        if (png is null && dib is null || !settings.RecordImages.Value) return null;
        return new Copied(ClipKind.Image, source, Png: png, Dib: dib, Others: ReadOtherFormats());
    }

    private static bool IsConcealed()
    {
        if (ConcealedFormats.Any(IsClipboardFormatAvailable)) return true;
        return ReadFormat(HistoryFlagFormat) is { Length: >= 4 } flag && BitConverter.ToInt32(flag) == 0;
    }

    /// The app holding the clipboard, else the one in front, which almost always just copied.
    private static string? SourcePath()
    {
        var window = GetClipboardOwner();
        if (window == 0) window = GetForegroundWindow();
        GetWindowThreadProcessId(window, out var process);
        return ProcessPath(process);
    }

    private static byte[]? ReadFormat(uint format)
    {
        if (!IsClipboardFormatAvailable(format)) return null;
        var data = GetClipboardData(format);
        return data == 0 ? null : ReadBytes(data);
    }

    /// Whatever else the image came with, so pasting gives it all back. Handles to GDI objects
    /// and the like can't be saved; the image's own formats are kept as PNG.
    private static Dictionary<string, byte[]> ReadOtherFormats()
    {
        const uint firstRegistered = 0xC000;
        const uint unicodeText = CF_UNICODETEXT, oemText = 7, ansiText = 1, locale = 16;
        var others = new Dictionary<string, byte[]>();
        long total = 0;
        for (var format = EnumClipboardFormats(0); format != 0; format = EnumClipboardFormats(format))
        {
            var isPlainData = format >= firstRegistered || format is unicodeText or oemText or ansiText or locale;
            if (!isPlainData || format == PngFormat || format == MimePngFormat) continue;
            var name = FormatName(format);
            if (TransientFormats.Contains(name) || ReadFormat(format) is not { } data) continue;
            if (total + data.Length > ClipPayloadStore.MaxPayloadBytes) continue;
            total += data.Length;
            others[name] = data;
        }
        return others;
    }

    /// DROPFILES: an offset to the paths, a wide-characters flag, then null-separated paths.
    private static List<string> ParseDrop(byte[] drop)
    {
        const int isWideOffset = 16;
        var start = BitConverter.ToInt32(drop, 0);
        var encoding = BitConverter.ToInt32(drop, isWideOffset) != 0 ? Encoding.Unicode : Encoding.Default;
        return encoding.GetString(drop, start, drop.Length - start)
            .Split('\0', StringSplitOptions.RemoveEmptyEntries).ToList();
    }

    private ClipItem? Finish(Copied copied)
    {
        switch (copied.Kind)
        {
            case ClipKind.Files:
                return new ClipItem
                {
                    Text = string.Join("\n", copied.Files!.Select(Path.GetFileName)),
                    SourcePath = copied.SourcePath,
                    Kind = ClipKind.Files,
                    Files = copied.Files!,
                    Fingerprint = ClipPayloadStore.Fingerprint(copied.Files!),
                };
            case ClipKind.Image:
                return FinishImage(copied);
            default:
                return new ClipItem { Text = copied.Text!, SourcePath = copied.SourcePath };
        }
    }

    private ClipItem? FinishImage(Copied copied)
    {
        using var image = copied.Png is not null ? ClipImageCodec.FromPng(copied.Png) : ClipImageCodec.FromDib(copied.Dib!);
        if (image is null)
        {
            log.Add("Clipboard", "Skipped an image it couldn't read");
            return null;
        }
        var png = copied.Png ?? ClipImageCodec.Png(image);
        if (png.Length > ClipPayloadStore.MaxPayloadBytes) return null;

        var formats = new Dictionary<string, byte[]>(copied.Others!) { [PngName] = png };
        var item = new ClipItem
        {
            Text = $"{image.Width} × {image.Height}",
            SourcePath = copied.SourcePath,
            Kind = ClipKind.Image,
            PixelWidth = image.Width,
            PixelHeight = image.Height,
            Fingerprint = ClipPayloadStore.Fingerprint([png]),
            HasPayload = true,
        };
        ClipPayloadStore.Save(item.Id, formats, ClipImageCodec.Thumbnail(image));
        return item;
    }

    /// Puts an entry back on the clipboard without recording it as a new entry. Text goes back
    /// plain, images with their saved formats plus a CF_DIB, files as a CF_HDROP of real files.
    public void Write(ClipItem item)
    {
        var data = new List<(uint Format, byte[] Bytes)>();
        if (item.Kind == ClipKind.Files && DropOf(item) is { } drop) data.Add((CF_HDROP, drop));
        if (item.Kind == ClipKind.Image && item.HasPayload && ClipPayloadStore.Load(item.Id) is { } formats)
        {
            foreach (var (name, bytes) in formats) data.Add((FormatId(name), bytes));
            if (formats.TryGetValue(PngName, out var png) && ClipImageCodec.ToDib(png) is { } dib) data.Add((CF_DIB, dib));
        }
        if (data.Count == 0) data.Add((CF_UNICODETEXT, Encoding.Unicode.GetBytes(item.Text + "\0")));
        data.Add((OwnFormat, [1]));

        if (!Open())
        {
            log.Add("Clipboard", "Couldn't open the clipboard to write to it");
            return;
        }
        try
        {
            EmptyClipboard();
            foreach (var (format, bytes) in data)
            {
                var memory = Allocate(bytes);
                if (memory != 0 && SetClipboardData(format, memory) == 0) GlobalFree(memory);
            }
        }
        finally { CloseClipboard(); }
    }

    /// A DROPFILES of the paths that still exist, or of the kept copies of those that don't.
    private static byte[]? DropOf(ClipItem item)
    {
        const int headerSize = 20, isWideOffset = 16;
        var paths = item.Files
            .Select(path => File.Exists(path) || Directory.Exists(path) ? path : ClipPayloadStore.KeptFile(item.Id, path))
            .OfType<string>().ToList();
        if (paths.Count == 0) return null;
        var names = Encoding.Unicode.GetBytes(string.Concat(paths.Select(p => p + "\0")) + "\0");
        var drop = new byte[headerSize + names.Length];
        BitConverter.TryWriteBytes(drop.AsSpan(0), headerSize);
        BitConverter.TryWriteBytes(drop.AsSpan(isWideOffset), 1);
        names.CopyTo(drop, headerSize);
        return drop;
    }
}
