using System.Runtime.InteropServices;
using Estris.Utilities.ClipboardManager.Overlay;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Foundation;
using Windows.UI;
using static Estris.Core.Loc;

namespace Estris.Utilities.ClipboardManager.Settings;

/// Overlay elements at real size over the desktop wallpaper, drawn with the current settings.
internal sealed partial class AppearancePreview : Grid
{
    private const double PreviewHeight = 300, CardWidth = 200, CardHeight = 120, Spacing14 = 14;
    private const int WallpaperWidth = 1200, PreviewLines = 3, PreviewEntries = 2;
    private const uint SPI_GETDESKWALLPAPER = 0x73;
    private const int MaxPath = 260;
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
            card.State = index == 0 ? SurfaceState.Selected : SurfaceState.Normal;
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

    private static Brush WallpaperBrush()
    {
        foreach (var path in WallpaperPaths())
        {
            if (!File.Exists(path)) continue;
            var image = new BitmapImage { DecodePixelWidth = WallpaperWidth };
            _ = LoadWallpaper(image, path);
            return new ImageBrush { ImageSource = image, Stretch = Stretch.UniformToFill };
        }
        return new LinearGradientBrush
        {
            StartPoint = new Point(0, 0),
            EndPoint = new Point(1, 1),
            GradientStops =
            {
                new GradientStop { Color = Color.FromArgb(255, 75, 0, 130), Offset = 0 },
                new GradientStop { Color = Color.FromArgb(255, 128, 0, 128), Offset = 0.5 },
                new GradientStop { Color = Color.FromArgb(255, 255, 140, 0), Offset = 1 },
            },
        };
    }

    /// The chosen picture, then the copy Windows keeps of it for slideshows and Spotlight.
    private static IEnumerable<string> WallpaperPaths()
    {
        if (ChosenWallpaper() is { } chosen) yield return chosen;
        yield return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Microsoft", "Windows", "Themes", "TranscodedWallpaper");
    }

    private static unsafe string? ChosenWallpaper()
    {
        var name = stackalloc char[MaxPath];
        return SystemParametersInfo(SPI_GETDESKWALLPAPER, MaxPath, name, 0) ? new string(name) : null;
    }

    private static async Task LoadWallpaper(BitmapImage image, string path)
    {
        var file = await Windows.Storage.StorageFile.GetFileFromPathAsync(path);
        using var stream = await file.OpenReadAsync();
        await image.SetSourceAsync(stream);
    }

    [LibraryImport("user32", EntryPoint = "SystemParametersInfoW", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static unsafe partial bool SystemParametersInfo(uint action, uint size, char* value, uint flags);
}
