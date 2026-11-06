using System.Runtime.InteropServices;
using Estris.Utilities.ClipboardManager.Overlay;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.UI;
using static Estris.Core.Loc;

namespace Estris.Utilities.ClipboardManager.Settings;

/// Overlay elements at real size over the desktop wallpaper, drawn with the current settings.
internal sealed partial class AppearancePreview : Grid
{
    private const double PreviewHeight = 300, CardWidth = 200, CardHeight = 120, Spacing14 = 14;
    private const int WallpaperWidth = 1200, PreviewLines = 3, PreviewEntries = 2;
    private const int COLOR_DESKTOP = 1;
    private static readonly CornerRadius Corners = new(SurfaceLook.CardRadius);

    public AppearancePreview(AppearanceSettings appearance, ClipboardHistory history)
    {
        Height = PreviewHeight;
        Margin = new Thickness(0, 0, 0, 8);

        var dim = new Border { CornerRadius = Corners, Background = new SolidColorBrush(Colors.Black), Opacity = appearance.BackdropDim.Value };
        appearance.BackdropDim.Changed += () => dim.Opacity = appearance.BackdropDim.Value;
        Children.Add(new Border { CornerRadius = Corners, Background = WallpaperBrush() });
        Children.Add(dim);

        var look = new SurfaceLook(appearance);
        var items = PreviewItems(history);
        var cards = new StackPanel { Orientation = Orientation.Horizontal, Spacing = Spacing14, HorizontalAlignment = HorizontalAlignment.Center };
        for (var index = 0; index < PreviewEntries; index++)
        {
            var card = new ClipCard(look, CardMetrics.Compact, fitsImageInside: true) { MaxLines = PreviewLines };
            card.Show(items[index], CardWidth, CardHeight);
            cards.Children.Add(card);
        }
        var stack = new StackPanel { Spacing = Spacing14, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        stack.Children.Add(cards);
        stack.Children.Add(new PositionPill(look) { Text = T("%lld of %lld", 2, 12) });
        Children.Add(stack);
    }

    /// Real entries when there are enough, so the preview shows familiar text and icons.
    private static List<ClipItem> PreviewItems(ClipboardHistory history)
    {
        var windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        ClipItem[] samples =
        [
            new() { Text = T("Meeting notes for Thursday"), SourcePath = Path.Combine(windows, "notepad.exe") },
            new() { Text = "https://learn.microsoft.com/windows", SourcePath = Path.Combine(windows, "explorer.exe") },
        ];
        return history.Items.Concat(samples).Take(PreviewEntries).ToList();
    }

    /// The desktop as it really is: its picture, or the solid color people can choose instead.
    private static Brush WallpaperBrush()
    {
        foreach (var path in WallpaperPaths())
        {
            if (!File.Exists(path)) continue;
            var image = new BitmapImage { DecodePixelWidth = WallpaperWidth };
            _ = LoadWallpaper(image, path);
            return new ImageBrush { ImageSource = image, Stretch = Stretch.UniformToFill };
        }
        var color = GetSysColor(COLOR_DESKTOP);
        return new SolidColorBrush(Color.FromArgb(255, (byte)color, (byte)(color >> 8), (byte)(color >> 16)));
    }

    /// Each screen's picture, then the copy Windows keeps of it for slideshows and Spotlight.
    private static IEnumerable<string> WallpaperPaths()
    {
        var desktop = (IDesktopWallpaper)new DesktopWallpaper();
        for (uint index = 0; index < desktop.GetMonitorDevicePathCount(); index++)
        {
            var path = desktop.GetWallpaper(desktop.GetMonitorDevicePathAt(index));
            if (!string.IsNullOrEmpty(path)) yield return path;
        }
        yield return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Microsoft", "Windows", "Themes", "TranscodedWallpaper");
    }

    private static async Task LoadWallpaper(BitmapImage image, string path)
    {
        var file = await Windows.Storage.StorageFile.GetFileFromPathAsync(path);
        using var stream = await file.OpenReadAsync();
        await image.SetSourceAsync(stream);
    }

    [LibraryImport("user32")]
    private static partial uint GetSysColor(int index);

    [ComImport, Guid("C2CF3110-460E-4fc1-B9D0-8A1C0C9CC4BD")]
    private class DesktopWallpaper;

    /// Only as far as what's used: the order is the interface's.
    [ComImport, Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IDesktopWallpaper
    {
        void SetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string? monitor, [MarshalAs(UnmanagedType.LPWStr)] string wallpaper);
        [return: MarshalAs(UnmanagedType.LPWStr)] string GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string? monitor);
        [return: MarshalAs(UnmanagedType.LPWStr)] string GetMonitorDevicePathAt(uint index);
        uint GetMonitorDevicePathCount();
    }
}
