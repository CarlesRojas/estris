using System.Collections.Concurrent;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml.Media.Imaging;

namespace Estris.Utilities.ClipboardManager.Overlay;

/// Decoded premultiplied BGRA, ready to show. Any thread can make one; bitmaps are UI-thread only.
internal sealed record Pixels(int Width, int Height, byte[] Bgra)
{
    public WriteableBitmap ToBitmap()
    {
        var bitmap = new WriteableBitmap(Width, Height);
        using (var stream = bitmap.PixelBuffer.AsStream()) stream.Write(Bgra);
        bitmap.Invalidate();
        return bitmap;
    }

    public static Pixels From(Bitmap image)
    {
        var locked = image.LockBits(new Rectangle(0, 0, image.Width, image.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppPArgb);
        try
        {
            var stride = image.Width * 4;
            var bgra = new byte[stride * image.Height];
            for (var row = 0; row < image.Height; row++)
                Marshal.Copy(locked.Scan0 + row * locked.Stride, bgra, row * stride, stride);
            return new Pixels(image.Width, image.Height, bgra);
        }
        finally { image.UnlockBits(locked); }
    }
}

/// Programs' names and icons, each looked up once.
internal static partial class AppIcons
{
    private const int IconSize = 64;
    private const int SIIGBF_ICONONLY = 4;
    private static readonly ConcurrentDictionary<string, string> Names = new(StringComparer.OrdinalIgnoreCase);
    private static readonly ConcurrentDictionary<string, Pixels?> Decoded = new(StringComparer.OrdinalIgnoreCase);
    private static readonly Dictionary<string, WriteableBitmap?> Bitmaps = new(StringComparer.OrdinalIgnoreCase);

    /// What the program calls itself, or its file name.
    public static string Name(string path) => Names.GetOrAdd(path, static path =>
    {
        try
        {
            var description = FileVersionInfo.GetVersionInfo(path).FileDescription;
            if (!string.IsNullOrWhiteSpace(description)) return description.Trim();
        }
        catch (FileNotFoundException) { }
        return Path.GetFileNameWithoutExtension(path);
    });

    /// Slow the first time, so the warmer calls it ahead on a background thread.
    public static Pixels? Load(string path) => Decoded.GetOrAdd(path, LoadIcon);

    /// The icon as an image. On the UI thread.
    public static WriteableBitmap? Bitmap(string? path)
    {
        if (path is null) return null;
        if (!Bitmaps.TryGetValue(path, out var bitmap)) Bitmaps[path] = bitmap = Load(path)?.ToBitmap();
        return bitmap;
    }

    private static Pixels? LoadIcon(string path)
    {
        var factoryId = typeof(IShellItemImageFactory).GUID;
        if (SHCreateItemFromParsingName(path, 0, ref factoryId, out var factory) != 0) return null;
        try
        {
            if (factory.GetImage(new NativeSize { Width = IconSize, Height = IconSize }, SIIGBF_ICONONLY, out var bitmap) != 0) return null;
            try { return Gdi.Read(bitmap, IconSize, IconSize); }
            finally { Gdi.DeleteObject(bitmap); }
        }
        finally { Marshal.FinalReleaseComObject(factory); }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeSize { public int Width, Height; }

    [ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellItemImageFactory
    {
        [PreserveSig] int GetImage(NativeSize size, int flags, out nint bitmap);
    }

    [DllImport("shell32", CharSet = CharSet.Unicode)]
    private static extern int SHCreateItemFromParsingName(string path, nint context, ref Guid id, [MarshalAs(UnmanagedType.Interface)] out IShellItemImageFactory item);
}

/// Thumbnails of the entries, kept for the most recently used ones.
internal static class ClipThumbnails
{
    private const int CachedImages = 32;
    private static readonly ConcurrentDictionary<Guid, Pixels> Decoded = new();
    private static readonly Dictionary<Guid, WriteableBitmap> Bitmaps = [];
    private static readonly LinkedList<Guid> Recent = new();

    /// Reads and decodes the file. Slow, so the warmer calls it on a background thread.
    public static void Decode(ClipItem item)
    {
        if (item.Kind == ClipKind.Image && !Decoded.ContainsKey(item.Id)) Load(item);
    }

    private static Pixels? Load(ClipItem item)
    {
        try
        {
            using var image = new Bitmap(ClipPayloadStore.ThumbnailPath(item.Id));
            return Decoded[item.Id] = Pixels.From(image);
        }
        catch (Exception e) when (e is ArgumentException or IOException) { return null; }
    }

    /// The entry's thumbnail, or null if it has none. On the UI thread.
    public static WriteableBitmap? Bitmap(ClipItem item)
    {
        if (item.Kind != ClipKind.Image) return null;
        Recent.Remove(item.Id);
        if (!Bitmaps.TryGetValue(item.Id, out var bitmap))
        {
            var pixels = Decoded.TryRemove(item.Id, out var ready) ? ready : Load(item);
            if (pixels is null) return null;
            Decoded.TryRemove(item.Id, out _);
            Bitmaps[item.Id] = bitmap = pixels.ToBitmap();
        }
        Recent.AddFirst(item.Id);
        while (Recent.Count > CachedImages)
        {
            Bitmaps.Remove(Recent.Last!.Value);
            Recent.RemoveLast();
        }
        return bitmap;
    }
}

/// Gets entries ready to draw before they are shown: the app's icon and name, the image read and
/// decoded. Each is slow the first time, and done on the spot it made the first steps through
/// the history lag. The slow part runs on a background thread, the rest between key presses.
internal sealed class ClipPreviewWarmer
{
    private CancellationTokenSource? running;

    /// Replaces whatever was waiting: the latest order is the one that matters.
    public void Warm(IReadOnlyList<ClipItem> items)
    {
        running?.Cancel();
        var cancel = (running = new CancellationTokenSource()).Token;
        Task.Run(() =>
        {
            foreach (var item in items)
            {
                if (cancel.IsCancellationRequested) return;
                if (item.SourcePath is { } path)
                {
                    AppIcons.Name(path);
                    AppIcons.Load(path);
                }
                ClipThumbnails.Decode(item);
                App.Ui.TryEnqueue(DispatcherQueuePriority.Low, () =>
                {
                    if (cancel.IsCancellationRequested) return;
                    AppIcons.Bitmap(item.SourcePath);
                    ClipThumbnails.Bitmap(item);
                });
            }
        }, cancel);
    }
}
