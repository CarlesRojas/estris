using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace Estris.Utilities.ClipboardManager;

/// Turns the clipboard's image formats into PNG and back. Screenshots arrive as raw DIBs, far
/// larger than the same pixels as a PNG, which also keeps entries within the size limit.
internal static class ClipImageCodec
{
    private const int FileHeaderSize = 14, InfoHeaderSize = 40, BitFieldsCompression = 3;
    /// Large enough to fill the biggest card.
    private const int MaxThumbnailSide = 1200;

    /// Decodes a CF_DIB by giving it the file header it lacks.
    public static Bitmap? FromDib(byte[] dib)
    {
        if (dib.Length < InfoHeaderSize) return null;
        var headerSize = BitConverter.ToInt32(dib, 0);
        var bits = BitConverter.ToInt16(dib, 14);
        var compression = BitConverter.ToInt32(dib, 16);
        var usedColors = BitConverter.ToInt32(dib, 32);
        var colors = usedColors != 0 ? usedColors : bits <= 8 ? 1 << bits : 0;
        var masks = compression == BitFieldsCompression && headerSize == InfoHeaderSize ? 12 : 0;
        var file = new byte[FileHeaderSize + dib.Length];
        file[0] = (byte)'B';
        file[1] = (byte)'M';
        BitConverter.TryWriteBytes(file.AsSpan(2), file.Length);
        BitConverter.TryWriteBytes(file.AsSpan(10), FileHeaderSize + headerSize + masks + colors * 4);
        dib.CopyTo(file, FileHeaderSize);
        try { return new Bitmap(new MemoryStream(file)); }
        catch (ArgumentException) { return null; }
    }

    public static Bitmap? FromPng(byte[] png)
    {
        try { return new Bitmap(new MemoryStream(png)); }
        catch (ArgumentException) { return null; }
    }

    public static byte[] Png(Image image)
    {
        using var stream = new MemoryStream();
        image.Save(stream, ImageFormat.Png);
        return stream.ToArray();
    }

    /// A PNG scaled down to fit a card.
    public static byte[] Thumbnail(Bitmap image)
    {
        var scale = Math.Min(1, (double)MaxThumbnailSide / Math.Max(image.Width, image.Height));
        if (scale >= 1) return Png(image);
        using var scaled = new Bitmap(Math.Max(1, (int)(image.Width * scale)), Math.Max(1, (int)(image.Height * scale)), PixelFormat.Format32bppArgb);
        using var graphics = Graphics.FromImage(scaled);
        graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
        graphics.DrawImage(image, 0, 0, scaled.Width, scaled.Height);
        return Png(scaled);
    }

    /// A 32-bit CF_DIB of a PNG, for the apps that don't read PNG.
    public static byte[]? ToDib(byte[] png)
    {
        using var image = FromPng(png);
        if (image is null) return null;
        var rectangle = new Rectangle(0, 0, image.Width, image.Height);
        var locked = image.LockBits(rectangle, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try
        {
            var stride = image.Width * 4;
            var dib = new byte[InfoHeaderSize + stride * image.Height];
            BitConverter.TryWriteBytes(dib.AsSpan(0), InfoHeaderSize);
            BitConverter.TryWriteBytes(dib.AsSpan(4), image.Width);
            BitConverter.TryWriteBytes(dib.AsSpan(8), image.Height);
            BitConverter.TryWriteBytes(dib.AsSpan(12), (short)1);
            BitConverter.TryWriteBytes(dib.AsSpan(14), (short)32);
            BitConverter.TryWriteBytes(dib.AsSpan(20), stride * image.Height);
            // A DIB's rows run from the bottom up.
            for (var row = 0; row < image.Height; row++)
                Marshal.Copy(locked.Scan0 + row * locked.Stride, dib, InfoHeaderSize + (image.Height - 1 - row) * stride, stride);
            return dib;
        }
        finally { image.UnlockBits(locked); }
    }
}
