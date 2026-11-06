using Estris.Core;
using Estris.Utilities.ClipboardManager.Overlay;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using static Estris.Core.Loc;

namespace Estris.Utilities.ClipboardManager.Settings;

/// The History tab: every saved entry, searchable, with delete and Clear All.
internal sealed class HistoryList : StackPanel
{
    private const double IconSize = 22, ImageHeight = 140;
    private const int TextLines = 2;

    private readonly ClipboardHistory history;
    private readonly AutoSuggestBox search = new() { PlaceholderText = T("Search"), QueryIcon = new SymbolIcon(Symbol.Find), Margin = new Thickness(0, 8, 0, 8) };
    private readonly TextBlock count = new() { VerticalAlignment = VerticalAlignment.Center, Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"] };
    private readonly Button clearAll = new() { Content = T("Clear All"), HorizontalAlignment = HorizontalAlignment.Right };
    private readonly StackPanel rows = new() { Spacing = 4 };

    public HistoryList(ClipboardHistory history)
    {
        this.history = history;
        Spacing = 4;
        var header = new Grid { Margin = new Thickness(1, 0, 0, 6) };
        header.Children.Add(count);
        header.Children.Add(clearAll);
        Children.Add(search);
        Children.Add(header);
        Children.Add(rows);

        search.TextChanged += (_, _) => Rebuild();
        clearAll.Click += async (_, _) => await ConfirmClear();
        // Only while showing: the history changes on every copy.
        Loaded += (_, _) =>
        {
            history.Changed += Rebuild;
            Rebuild();
        };
        Unloaded += (_, _) => history.Changed -= Rebuild;
    }

    private async Task ConfirmClear()
    {
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = T("Delete all clipboard entries?"),
            PrimaryButtonText = T("Clear All"),
            CloseButtonText = T("Cancel"),
            DefaultButton = ContentDialogButton.Close,
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary) history.Clear();
    }

    private void Rebuild()
    {
        var query = search.Text.Trim();
        var results = query.Length == 0
            ? history.Items
            : history.Items.Where(i => i.Text.Contains(query, StringComparison.CurrentCultureIgnoreCase)
                || ClipText.SourceName(i).Contains(query, StringComparison.CurrentCultureIgnoreCase)).ToList();

        var total = history.Items.Count == 1 ? T("1 entry") : T("%lld entries", history.Items.Count);
        count.Text = query.Length == 0 ? total : T("%lld of %@", results.Count, total);
        clearAll.IsEnabled = history.Items.Count > 0;

        rows.Children.Clear();
        if (history.Items.Count == 0) rows.Children.Add(Placeholder(T("No clipboard entries yet")));
        else if (results.Count == 0) rows.Children.Add(Placeholder(T("No entries match “%@”", search.Text)));
        foreach (var item in results) rows.Children.Add(Row(item));
    }

    private static TextBlock Placeholder(string text) => new()
    {
        Text = text,
        HorizontalAlignment = HorizontalAlignment.Center,
        Margin = new Thickness(0, 12, 0, 12),
        Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
    };

    /// Laid out like the overlay's card: app and date on top, the content below.
    private Border Row(ClipItem item)
    {
        var secondary = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"];
        var header = new Grid { ColumnSpacing = 8 };
        foreach (var width in new[] { GridLength.Auto, new GridLength(1, GridUnitType.Star), GridLength.Auto, GridLength.Auto })
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = width });

        FrameworkElement icon = AppIcons.Bitmap(item.SourcePath) is { } bitmap
            ? new Image { Source = bitmap, Width = IconSize, Height = IconSize }
            : new FontIcon { Glyph = ClipText.AppGlyph, FontSize = IconSize * 0.75 };
        var name = new TextBlock { Text = ClipText.SourceName(item), FontSize = 12, Foreground = secondary, VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis };
        var date = new TextBlock { Text = DateFormat.Show(item.Date), FontSize = 12, Foreground = secondary, VerticalAlignment = VerticalAlignment.Center };
        var delete = new Button { Content = new FontIcon { Glyph = ClipText.TrashGlyph, FontSize = 14 }, Padding = new Thickness(6), Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent), BorderThickness = new Thickness(0) };
        ToolTipService.SetToolTip(delete, T("Delete this entry"));
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(delete, T("Delete this entry"));
        delete.Click += (_, _) => history.Remove(item);
        Grid.SetColumn(name, 1);
        Grid.SetColumn(date, 2);
        Grid.SetColumn(delete, 3);
        header.Children.Add(icon);
        header.Children.Add(name);
        header.Children.Add(date);
        header.Children.Add(delete);

        var content = new StackPanel { Spacing = 8 };
        content.Children.Add(header);
        content.Children.Add(Content(item));
        return new Border
        {
            Child = content,
            Padding = new Thickness(14, 8, 8, 10),
            CornerRadius = new CornerRadius(4),
            Background = (Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"],
            BorderBrush = (Brush)Application.Current.Resources["CardStrokeColorDefaultBrush"],
            BorderThickness = new Thickness(1),
        };
    }

    private static FrameworkElement Content(ClipItem item)
    {
        if (ClipThumbnails.Bitmap(item) is WriteableBitmap image)
            return new Image { Source = image, Height = ImageHeight, HorizontalAlignment = HorizontalAlignment.Left, Stretch = Stretch.Uniform };

        var text = new TextBlock
        {
            Text = item.Kind == ClipKind.Image ? ClipText.ImageLabel(item) : ClipText.Shown(item).Trim(),
            TextWrapping = TextWrapping.Wrap,
            TextTrimming = TextTrimming.CharacterEllipsis,
            MaxLines = TextLines,
        };
        if (item.Kind == ClipKind.Text) return text;
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
        row.Children.Add(new FontIcon { Glyph = ClipText.Glyph(item), FontSize = 14 });
        row.Children.Add(text);
        return row;
    }
}
