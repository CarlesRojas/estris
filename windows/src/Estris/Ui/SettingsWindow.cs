using Estris.Core;
using Estris.Tray;
using Estris.Ui.Panes;
using Estris.Utilities;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Graphics;
using static Estris.Core.Loc;

namespace Estris.Ui;

/// Settings, laid out as Windows 11's own: a Mica window drawn into its title bar, a navigation
/// list with search on the left, and the page's title over its cards on the right. Each list
/// entry for a utility says On or Off at its right.
public sealed class SettingsWindow : Window
{
    private readonly IReadOnlyList<IUtility> utilities;
    private readonly AppLog log;
    private readonly NavigationView navigation = new()
    {
        IsBackButtonVisible = NavigationViewBackButtonVisible.Collapsed,
        IsSettingsVisible = false,
        IsPaneToggleButtonVisible = false,
        PaneDisplayMode = NavigationViewPaneDisplayMode.Left,
        OpenPaneLength = 300,
        AlwaysShowHeader = false,
    };
    private readonly ContentControl page = new() { HorizontalContentAlignment = HorizontalAlignment.Stretch };
    private readonly TextBlock pageTitle = new();
    private readonly ScrollViewer scroller = new();
    private readonly Dictionary<string, UIElement> built = [];
    private readonly Dictionary<string, NavigationViewItem> items = [];
    private readonly List<(NavigationViewItemHeader Header, UtilityGroup Group)> headers = [];
    private readonly AutoSuggestBox search = new() { PlaceholderText = T("Find a setting"), QueryIcon = new SymbolIcon(Symbol.Find) };

    public static Setting<bool> ShowsDeveloper { get; } = SettingsStore.Shared.Get("local.showsDeveloper", false);

    public SettingsWindow(IReadOnlyList<IUtility> utilities, AppLog log)
    {
        this.utilities = utilities;
        this.log = log;
        Title = "Estris";
        SystemBackdrop = new MicaBackdrop();
        ExtendsContentIntoTitleBar = true;
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "Estris.ico"));
        AppWindow.TitleBar.PreferredHeightOption = TitleBarHeightOption.Tall;

        var scale = Native.GetDpiForWindow(WinRT.Interop.WindowNative.GetWindowHandle(this)) / 96.0;
        AppWindow.Resize(new SizeInt32((int)(1120 * scale), (int)(780 * scale)));

        Content = BuildLayout();
        BuildList();
        ShowsDeveloper.Changed += BuildList;
        Closed += (_, _) => ShowsDeveloper.Changed -= BuildList;
        Select("general");
    }

    private Grid BuildLayout()
    {
        var root = new Grid();
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(48) });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

        var titleBar = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12, Margin = new Thickness(16, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
        titleBar.Children.Add(new Image { Source = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri(Path.Combine(AppContext.BaseDirectory, "Assets", "Estris.png"))), Width = 16, Height = 16 });
        titleBar.Children.Add(new TextBlock { Text = "Estris", Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"], VerticalAlignment = VerticalAlignment.Center });
        root.Children.Add(titleBar);
        SetTitleBar(titleBar);

        pageTitle.Style = (Style)Application.Current.Resources["TitleTextBlockStyle"];
        pageTitle.Margin = new Thickness(0, 0, 0, 16);
        var column = new StackPanel { MaxWidth = 960, Margin = new Thickness(40, 8, 40, 0) };
        column.Children.Add(pageTitle);
        column.Children.Add(page);
        scroller.Content = column;
        scroller.Padding = new Thickness(0, 0, 8, 0);
        navigation.Content = scroller;
        navigation.AutoSuggestBox = search;
        navigation.SelectionChanged += (_, e) =>
        {
            if (e.SelectedItem is NavigationViewItem { Tag: string id }) Show(id);
        };
        search.TextChanged += (_, _) => ApplySearch();
        Grid.SetRow(navigation, 1);
        root.Children.Add(navigation);
        return root;
    }

    private NavigationViewItem Item(string id, string title, string glyph, Setting<bool>? state = null)
    {
        var item = new NavigationViewItem { Tag = id, Icon = new FontIcon { Glyph = glyph } };
        if (state is null) item.Content = title;
        else
        {
            // On in the accent colour, so the utilities at work stand out; Off stays quiet.
            var status = new TextBlock { Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"], VerticalAlignment = VerticalAlignment.Center };
            void Sync()
            {
                status.Text = state.Value ? T("On") : T("Off");
                status.Foreground = (Brush)Application.Current.Resources[state.Value ? "AccentTextFillColorPrimaryBrush" : "TextFillColorTertiaryBrush"];
            }
            Sync();
            state.Changed += Sync;
            Closed += (_, _) => state.Changed -= Sync;
            var row = new Grid { Width = 214 };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.Children.Add(new TextBlock { Text = title, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center });
            Grid.SetColumn(status, 1);
            row.Children.Add(status);
            item.Content = row;
        }
        items[id] = item;
        return item;
    }

    private void BuildList()
    {
        navigation.MenuItems.Clear();
        items.Clear();
        headers.Clear();
        navigation.MenuItems.Add(Item("general", T("General"), ""));
        navigation.MenuItems.Add(Item("tray", T("System Tray"), ""));
        if (ShowsDeveloper.Value) navigation.MenuItems.Add(Item("developer", T("Developer"), ""));

        foreach (var (group, title) in new[]
        {
            (UtilityGroup.Tools, T("Tools")),
            (UtilityGroup.WindowsAndApps, T("Windows & Apps")),
            (UtilityGroup.KeyboardAndMouse, T("Keyboard & Mouse")),
        })
        {
            var header = new NavigationViewItemHeader { Content = title };
            headers.Add((header, group));
            navigation.MenuItems.Add(header);
            foreach (var utility in utilities.Where(u => u.Group == group))
                navigation.MenuItems.Add(Item(utility.Id, T(utility.Title), utility.Glyph, utility.Enabled));
        }
        ApplySearch();
    }

    /// Hides what doesn't match, and groups left with nothing.
    private void ApplySearch()
    {
        var query = search.Text.Trim();
        bool Matches(IUtility u) => query == "" || T(u.Title).Contains(query, StringComparison.CurrentCultureIgnoreCase)
            || u.Keywords.Any(k => k.Contains(query, StringComparison.OrdinalIgnoreCase));
        foreach (var utility in utilities)
            if (items.TryGetValue(utility.Id, out var item))
                item.Visibility = Matches(utility) ? Visibility.Visible : Visibility.Collapsed;
        foreach (var (header, group) in headers)
            header.Visibility = utilities.Any(u => u.Group == group && Matches(u)) ? Visibility.Visible : Visibility.Collapsed;
    }

    private void Select(string id)
    {
        if (items.TryGetValue(id, out var item)) navigation.SelectedItem = item;
    }

    private void Show(string id)
    {
        if (!built.TryGetValue(id, out var content))
        {
            content = id switch
            {
                "general" => GeneralPane.Build(this),
                "tray" => TrayPane.Build(App.Shared.TraySettings),
                "developer" => DeveloperPane.Build(log),
                _ => utilities.First(u => u.Id == id).BuildPane(),
            };
            built[id] = content;
        }
        pageTitle.Text = id switch
        {
            "general" => T("General"),
            "tray" => T("System Tray"),
            "developer" => T("Developer"),
            _ => T(utilities.First(u => u.Id == id).Title),
        };
        page.Content = content;
        scroller.ChangeView(null, 0, null, true);
    }

    public void Open(string? pane)
    {
        if (pane is not null) Select(pane);
        Activate();
    }
}
