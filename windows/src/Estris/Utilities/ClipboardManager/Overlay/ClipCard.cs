using Estris.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using static Estris.Core.Loc;

namespace Estris.Utilities.ClipboardManager.Overlay;

/// A card's proportions: the overlay's own, and a compact one for the settings preview.
internal sealed record CardMetrics(double Padding, double IconSize, double IconGap, double RowGap, double BodySize)
{
    public const double NameSize = 12;
    public static readonly CardMetrics Entry = new(20, 28, 10, 12, 16);
    public static readonly CardMetrics Compact = new(16, 24, 8, 10, 14);

    /// Padding plus the app row and the gap below it.
    public double Chrome => Padding * 2 + IconSize + RowGap;
}

internal static class ClipText
{
    /// More than the largest card shows; laying out a whole long text on every step through the
    /// history would only slow it down.
    public const int MaxCharacters = 3000;

    public const string ImageGlyph = "", FileGlyph = "", FilesGlyph = "", AppGlyph = "", TrashGlyph = "";

    /// Where the entry came from.
    public static string SourceName(ClipItem item) =>
        item.SourcePath is { } path ? AppIcons.Name(path) : T("Unknown app");

    /// The start of the text, as much as can show.
    public static string Shown(ClipItem item) =>
        item.Text.Length > MaxCharacters ? item.Text[..MaxCharacters] : item.Text;

    /// One line with line breaks shown as ⏎, for small rows.
    public static string SingleLine(string text) =>
        string.Join(" ⏎ ", text.Trim().Split(['\n', '\r'], StringSplitOptions.RemoveEmptyEntries));

    /// An image entry's name, for when its picture can't show.
    public static string ImageLabel(ClipItem item) => T("Image %@", item.Text);

    public static string Glyph(ClipItem item) => item.Kind switch
    {
        ClipKind.Image => ImageGlyph,
        _ => item.Files.Count > 1 ? FilesGlyph : FileGlyph,
    };
}

/// App icon and name on top with the date and delete button at the right, the copied content
/// below, filling the card and truncating where it ends. Its parts stay in place and only change
/// their content, so stepping through the history does no more than set a text.
internal sealed class ClipCard : Surface
{
    /// Tallest a card may grow to fit an image.
    private const double MaxImageCardHeight = 600;
    private const double ImageRadius = 4, TrashSize = 24, TrashGlyphSize = 13, DateSize = 12;

    private readonly SurfaceLook look;
    private readonly CardMetrics metrics;
    private readonly Image icon = new();
    private readonly FontIcon iconFallback;
    private readonly TextBlock name;
    private readonly TextBlock date;
    private readonly FontIcon trashIcon;
    private readonly TextBlock body;
    private readonly FontIcon labelIcon;
    private readonly Border picture = new() { CornerRadius = new CornerRadius(ImageRadius), HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Top };
    private readonly ImageBrush pictureBrush = new() { Stretch = Stretch.UniformToFill, AlignmentY = AlignmentY.Top, AlignmentX = AlignmentX.Left };
    private readonly Grid header = new();
    private readonly TextBlock empty;
    private readonly bool fitsImageInside;
    private ClipItem? shown;

    /// The delete button, for telling a click on it from a click on the card.
    public Border Trash { get; } = new() { Width = TrashSize, Height = TrashSize, Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent), Visibility = Visibility.Collapsed };

    /// fitsImageInside keeps the card's height and shows an image whole within it; otherwise the
    /// card grows to show the image at its full width.
    public ClipCard(SurfaceLook look, CardMetrics metrics, bool fitsImageInside) : base(look, SurfaceLook.CardRadius)
    {
        this.look = look;
        this.metrics = metrics;
        this.fitsImageInside = fitsImageInside;
        icon.Width = icon.Height = metrics.IconSize;
        iconFallback = new FontIcon { Glyph = ClipText.AppGlyph, FontSize = metrics.IconSize * 0.75, Foreground = look.Secondary, Visibility = Visibility.Collapsed };
        name = new TextBlock { FontSize = CardMetrics.NameSize, Foreground = look.Secondary, TextTrimming = TextTrimming.CharacterEllipsis, TextWrapping = TextWrapping.NoWrap, VerticalAlignment = VerticalAlignment.Center };
        date = new TextBlock { FontSize = DateSize, Foreground = look.Secondary, VerticalAlignment = VerticalAlignment.Center, Visibility = Visibility.Collapsed };
        trashIcon = new FontIcon { Glyph = ClipText.TrashGlyph, FontSize = TrashGlyphSize, Foreground = look.Secondary };
        Trash.Child = trashIcon;
        ToolTipService.SetToolTip(Trash, T("Delete from history"));
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(Trash, T("Delete from history"));
        body = new TextBlock { FontSize = metrics.BodySize, Foreground = look.Primary, TextWrapping = TextWrapping.Wrap, TextTrimming = TextTrimming.CharacterEllipsis };
        labelIcon = new FontIcon { FontSize = metrics.BodySize, Foreground = look.Secondary, Margin = new Thickness(0, 2, 6, 0), VerticalAlignment = VerticalAlignment.Top, Visibility = Visibility.Collapsed };
        empty = new TextBlock { Text = T("Clipboard history is empty"), FontSize = metrics.BodySize, Foreground = look.Primary, Visibility = Visibility.Collapsed };
        picture.Background = pictureBrush;

        header.ColumnSpacing = metrics.IconGap;
        header.Height = metrics.IconSize;
        foreach (var width in new[] { GridLength.Auto, new GridLength(1, GridUnitType.Star), GridLength.Auto, GridLength.Auto })
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = width });
        var iconBox = new Grid { Width = metrics.IconSize, Height = metrics.IconSize };
        iconBox.Children.Add(icon);
        iconBox.Children.Add(iconFallback);
        header.Children.Add(iconBox);
        SetColumn(name, 1);
        SetColumn(date, 2);
        SetColumn(Trash, 3);
        header.Children.Add(name);
        header.Children.Add(date);
        header.Children.Add(Trash);

        var content = new Grid { Margin = new Thickness(metrics.Padding), RowSpacing = metrics.RowGap };
        content.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        content.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        var bodyRow = new Grid();
        bodyRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        bodyRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        SetColumn(body, 1);
        bodyRow.Children.Add(labelIcon);
        bodyRow.Children.Add(body);
        SetColumnSpan(picture, 2);
        bodyRow.Children.Add(picture);
        SetRow(bodyRow, 1);
        SetRowSpan(empty, 2);
        content.Children.Add(header);
        content.Children.Add(bodyRow);
        content.Children.Add(empty);
        Children.Add(content);
    }

    /// At most this many lines of text, as the preview's small cards do. 0 fills the card.
    public int MaxLines { set => body.MaxLines = value; }

    /// Which of the corner's parts show. The settings preview leaves them off.
    public void ShowCorner(bool showsDate, bool showsDelete)
    {
        date.Visibility = showsDate ? Visibility.Visible : Visibility.Collapsed;
        Trash.Visibility = showsDelete ? Visibility.Visible : Visibility.Collapsed;
    }

    public bool IsTrashHovered
    {
        set => trashIcon.Foreground = value ? look.Primary : look.Secondary;
    }

    /// Shows an entry, or that the history is empty, at the card's width and usual height.
    public void Show(ClipItem? item, double width, double height)
    {
        Width = width;
        Height = FittedHeight(item, width, height);
        if (ReferenceEquals(item, shown) && item is not null) { ShowDate(item); FitPicture(item); return; }
        shown = item;

        var hasItem = item is not null;
        header.Visibility = hasItem ? Visibility.Visible : Visibility.Collapsed;
        empty.Visibility = hasItem ? Visibility.Collapsed : Visibility.Visible;
        if (item is null)
        {
            picture.Visibility = body.Visibility = labelIcon.Visibility = Visibility.Collapsed;
            return;
        }

        var bitmap = AppIcons.Bitmap(item.SourcePath);
        icon.Source = bitmap;
        iconFallback.Visibility = bitmap is null ? Visibility.Visible : Visibility.Collapsed;
        name.Text = ClipText.SourceName(item);
        ShowDate(item);
        ShowContent(item);
        FitPicture(item);
    }

    private void ShowDate(ClipItem item) => date.Text = DateFormat.Show(item.Date);

    private void ShowContent(ClipItem item)
    {
        var image = ClipThumbnails.Bitmap(item);
        pictureBrush.ImageSource = image;
        picture.Visibility = image is null ? Visibility.Collapsed : Visibility.Visible;
        body.Visibility = image is null ? Visibility.Visible : Visibility.Collapsed;
        var isLabel = item.Kind != ClipKind.Text && image is null;
        labelIcon.Visibility = isLabel ? Visibility.Visible : Visibility.Collapsed;
        if (isLabel) labelIcon.Glyph = ClipText.Glyph(item);
        if (image is null) body.Text = item.Kind == ClipKind.Image ? ClipText.ImageLabel(item) : ClipText.Shown(item).Trim();
    }

    /// `height`, or taller for an image so it shows whole at the card's width. Never above the limit.
    private double FittedHeight(ClipItem? item, double width, double height)
    {
        if (fitsImageInside || item is not { Kind: ClipKind.Image, PixelWidth: > 0 }) return height;
        var needed = metrics.Chrome + (width - metrics.Padding * 2) * item.PixelHeight / item.PixelWidth;
        return Math.Min(Math.Max(height, needed), Math.Max(height, MaxImageCardHeight));
    }

    private void FitPicture(ClipItem item)
    {
        if (item is not { Kind: ClipKind.Image, PixelWidth: > 0 }) return;
        var available = (Width: Width - metrics.Padding * 2, Height: Height - metrics.Chrome);
        var scale = available.Width / item.PixelWidth;
        if (fitsImageInside) scale = Math.Min(scale, available.Height / item.PixelHeight);
        picture.Width = item.PixelWidth * scale;
        picture.Height = Math.Min(item.PixelHeight * scale, available.Height);
    }
}

/// "2 of 12", on the same material.
internal sealed class PositionPill : Surface
{
    public const double PillHeight = 30;
    private const double FontSize = 13, SidePadding = 14;

    private readonly TextBlock text;

    public PositionPill(SurfaceLook look) : base(look, PillHeight / 2)
    {
        text = new TextBlock { FontSize = FontSize, Foreground = look.Secondary, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(SidePadding, 0, SidePadding, 0) };
        Height = PillHeight;
        HorizontalAlignment = HorizontalAlignment.Center;
        IsHitTestVisible = false;
        Children.Add(text);
    }

    public string Text { set => text.Text = value; }
}
