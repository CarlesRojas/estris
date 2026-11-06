using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Documents;
using Microsoft.UI.Xaml.Media;
using static Estris.Core.Loc;

namespace Estris.Utilities.Remap;

/// Every key and button pressed and released, newest at the bottom, with the device it came
/// from. Follows new events while scrolled to the bottom; logs only while on screen.
internal sealed class EventViewer : StackPanel
{
    private const double RowHeight = 32, MinimumListHeight = 260, BottomMargin = 56, AtBottomSlack = 8;
    private const string TimeFormat = "HH:mm:ss.fff";
    private const string ArrowGlyph = "";

    private readonly RemapUtility remap;
    private readonly Action<InputDevice, RemapInput> map;
    private readonly TextBlock count = new() { VerticalAlignment = VerticalAlignment.Center, Foreground = Brush("TextFillColorSecondaryBrush") };
    private readonly Button clear = new() { Content = T("Clear"), HorizontalAlignment = HorizontalAlignment.Right };
    private readonly StackPanel rows = new();
    private readonly ScrollViewer scroller = new() { Padding = new Thickness(8, 4, 16, 4) };
    private readonly Border frame = new()
    {
        BorderThickness = new Thickness(1),
        CornerRadius = (CornerRadius)Application.Current.Resources["OverlayCornerRadius"],
        Background = Brush("CardBackgroundFillColorDefaultBrush"),
        BorderBrush = Brush("CardStrokeColorDefaultBrush"),
    };
    private bool isAtBottom = true;

    public EventViewer(RemapUtility remap, Action<InputDevice, RemapInput> map)
    {
        this.remap = remap;
        this.map = map;
        Spacing = 8;
        Margin = new Thickness(0, 8, 0, 0);

        var top = new Grid();
        top.Children.Add(count);
        top.Children.Add(clear);
        clear.Click += (_, _) => remap.EventLog.Clear();
        Children.Add(top);

        scroller.Content = rows;
        scroller.ViewChanged += (_, e) =>
        {
            if (!e.IsIntermediate) isAtBottom = scroller.VerticalOffset >= scroller.ScrollableHeight - AtBottomSlack;
        };
        frame.Child = scroller;
        Children.Add(frame);

        Loaded += (_, _) => Open();
        Unloaded += (_, _) => Close();
    }

    private static Brush Brush(string name) => (Brush)Application.Current.Resources[name];

    private void Open()
    {
        var log = remap.EventLog;
        log.Added += OnAdded;
        log.Removed += OnRemoved;
        XamlRoot.Changed += OnRootChanged;
        SizeList();
        rows.Children.Clear();
        foreach (var row in log.Events) rows.Children.Add(Row(row));
        UpdateCount();
        remap.IsViewing = true;
        ScrollToBottom();
    }

    private void Close()
    {
        remap.IsViewing = false;
        var log = remap.EventLog;
        log.Added -= OnAdded;
        log.Removed -= OnRemoved;
        XamlRoot.Changed -= OnRootChanged;
    }

    private void OnRootChanged(XamlRoot sender, XamlRootChangedEventArgs e) => SizeList();

    /// Fills what's left of the window, as the page around it doesn't limit its height.
    private void SizeList()
    {
        var top = frame.TransformToVisual(null).TransformPoint(default).Y;
        frame.Height = Math.Max(MinimumListHeight, XamlRoot.Size.Height - top - BottomMargin);
    }

    private void OnAdded(InputEventRow row)
    {
        var follows = isAtBottom;
        rows.Children.Add(Row(row));
        UpdateCount();
        if (follows) ScrollToBottom();
    }

    private void OnRemoved()
    {
        if (rows.Children.Count > 0) rows.Children.RemoveAt(0);
        UpdateCount();
    }

    private void ScrollToBottom()
    {
        rows.UpdateLayout();
        scroller.UpdateLayout();
        scroller.ChangeView(null, scroller.ScrollableHeight, null, true);
        isAtBottom = true;
    }

    private void UpdateCount()
    {
        var total = remap.EventLog.Events.Count;
        count.Text = total == 0 ? T("No events yet") : T("%lld events", total);
        clear.IsEnabled = total > 0;
    }

    private Grid Row(InputEventRow row)
    {
        var grid = new Grid { Height = RowHeight, ColumnSpacing = 12, Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent), CornerRadius = new CornerRadius(4), Padding = new Thickness(6, 0, 6, 0) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(92) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(44) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto, MaxWidth = 200 });

        var time = Cell(row.Time.ToString(TimeFormat), 0, "TextFillColorSecondaryBrush");
        Microsoft.UI.Xaml.Documents.Typography.SetNumeralAlignment(time, Microsoft.UI.Xaml.FontNumeralAlignment.Tabular);
        grid.Children.Add(time);
        var phase = Cell(row.IsDown ? T("Down") : T("Up"), 1, row.IsDown ? "AccentTextFillColorPrimaryBrush" : "TextFillColorSecondaryBrush");
        phase.Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"];
        phase.FontWeight = Microsoft.UI.Text.FontWeights.SemiBold;
        phase.VerticalAlignment = VerticalAlignment.Center;
        grid.Children.Add(phase);

        var line = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, VerticalAlignment = VerticalAlignment.Center };
        Grid.SetColumn(line, 2);
        line.Children.Add(new TextBlock { Text = row.Name, VerticalAlignment = VerticalAlignment.Center });
        line.Children.Add(new TextBlock { Text = $"({row.Detail})", Foreground = Brush("TextFillColorSecondaryBrush"), VerticalAlignment = VerticalAlignment.Center });
        if (row.Result is { } result)
        {
            line.Children.Add(new FontIcon { Glyph = ArrowGlyph, FontSize = 12, Foreground = Brush("AccentTextFillColorPrimaryBrush") });
            line.Children.Add(new TextBlock { Text = result, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, Foreground = Brush("AccentTextFillColorPrimaryBrush"), VerticalAlignment = VerticalAlignment.Center });
        }
        if (row.Source is { } source && row.Input != RemapInput.LeftButton) AddCreateMapping(grid, line, source, row.Input);
        grid.Children.Add(line);

        var device = Cell(row.Device, 3, "TextFillColorSecondaryBrush");
        device.TextTrimming = TextTrimming.CharacterEllipsis;
        grid.Children.Add(device);

        grid.PointerEntered += (_, _) => grid.Background = Brush("SubtleFillColorSecondaryBrush");
        grid.PointerExited += (_, _) => grid.Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
        return grid;
    }

    private void AddCreateMapping(Grid grid, StackPanel line, InputDevice source, RemapInput input)
    {
        var button = new Button { Content = T("Create Mapping"), Visibility = Visibility.Collapsed, Padding = new Thickness(8, 1, 8, 2), FontSize = 12 };
        button.PointerEntered += (_, _) => remap.IsOverViewerLink = true;
        button.PointerExited += (_, _) => remap.IsOverViewerLink = false;
        button.Click += (_, _) =>
        {
            remap.IsOverViewerLink = false;
            map(source, input);
        };
        grid.PointerEntered += (_, _) => button.Visibility = Visibility.Visible;
        grid.PointerExited += (_, _) => button.Visibility = Visibility.Collapsed;
        line.Children.Add(button);
    }

    private static TextBlock Cell(string text, int column, string brush)
    {
        var cell = new TextBlock { Text = text, Foreground = Brush(brush), VerticalAlignment = VerticalAlignment.Center };
        Grid.SetColumn(cell, column);
        return cell;
    }
}
