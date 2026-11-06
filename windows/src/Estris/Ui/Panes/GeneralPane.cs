using System.Diagnostics;
using Estris.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Storage;
using Windows.Storage.Pickers;
using WinRT.Interop;
using static Estris.Core.DateFormat;
using static Estris.Core.Loc;

namespace Estris.Ui.Panes;

/// Language, date and time formats, Open at login, About, and Export & Import.
public static class GeneralPane
{
    private const string WebsiteUrl = "https://estris.pro";
    private const string IssuesUrl = "https://github.com/CarlesRojas/estris/issues/new";
    private const int ClicksToUnlockDeveloper = 6;

    public static UIElement Build(Window window)
    {
        var pane = new Pane();
        var requested = SettingsStore.Shared.Get("language", "");

        pane.Section(T("Language & Region"));
        var options = new List<(string, string)> { ("", T("System")) };
        options.AddRange(Languages.Select(l => (l.Code, l.Name)));
        var languageBox = new ComboBox { MinWidth = 180 };
        foreach (var (_, name) in options) languageBox.Items.Add(name);
        languageBox.SelectedIndex = options.FindIndex(o => o.Item1 == requested.Value);
        languageBox.SelectionChanged += async (_, _) =>
        {
            var code = options[languageBox.SelectedIndex].Item1;
            if (code == requested.Value) return;
            var dialog = new ContentDialog
            {
                XamlRoot = window.Content.XamlRoot,
                Title = T("Relaunch Estris?"),
                Content = T("The language changes after relaunching."),
                PrimaryButtonText = T("Relaunch"),
                CloseButtonText = T("Cancel"),
                DefaultButton = ContentDialogButton.Primary,
            };
            if (await dialog.ShowAsync() == ContentDialogResult.Primary)
            {
                requested.Value = code;
                SettingsStore.Shared.Flush();
                SingleInstance.Relaunch();
            }
            else languageBox.SelectedIndex = options.FindIndex(o => o.Item1 == requested.Value);
        };
        pane.Card(T("Language"), languageBox);
        pane.Choice(T("Date format"), Date, [
            (DateStyle.MonthDay, "Oct 9"), (DateStyle.DayMonth, "9 Oct"),
            (DateStyle.NumericMonthDay, "10/9"), (DateStyle.NumericDayMonth, "9/10")]);
        pane.Choice(T("Time format"), DateFormat.Time, [
            (TimeStyle.System, T("System")), (TimeStyle.TwentyFour, T("24-hour")), (TimeStyle.Twelve, T("12-hour"))]);

        pane.Section(T("Startup"));
        var login = new ToggleSwitch { IsOn = LoginItem.IsEnabled, OnContent = T("On"), OffContent = T("Off") };
        login.Toggled += (_, _) => LoginItem.IsEnabled = login.IsOn;
        pane.Card(T("Open at login"), login, T("Estris starts with Windows, in the system tray."));

        pane.Section(T("About"));
        pane.Add(About());

        pane.Section(T("Export & Import"));
        var export = new Button { Content = T("Export Settings…") };
        export.Click += async (_, _) => await Export(window);
        pane.Card(T("Export Settings…"), export, T("Saves every Estris setting to a file. Clipboard history stays out."));
        var import = new Button { Content = T("Import Settings…") };
        import.Click += async (_, _) => await Import(window);
        pane.Card(T("Import Settings…"), import, T("Replaces your settings with a saved file, then Estris opens again."));
        return pane.Root;
    }

    private static UIElement About()
    {
        var version = new HyperlinkButton { Content = T("Version %@", Updates.Shared.Version), Padding = new Thickness(0) };
        var clicks = 0;
        version.Click += (_, _) =>
        {
            if (++clicks >= ClicksToUnlockDeveloper) SettingsWindow.ShowsDeveloper.Value = true;
        };

        var details = new StackPanel { Spacing = 2, VerticalAlignment = VerticalAlignment.Center };
        details.Children.Add(new TextBlock { Text = "Estris", Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"] });
        details.Children.Add(version);

        var links = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center };
        if (Updates.Shared.IsInstalled)
        {
            var check = new Button { Content = T("Check for Updates…") };
            check.Click += async (_, _) =>
            {
                check.IsEnabled = false;
                if (await Updates.Shared.Check()) await Updates.Shared.Install();
                check.IsEnabled = true;
            };
            links.Children.Add(check);
        }
        links.Children.Add(new HyperlinkButton { Content = T("Website"), NavigateUri = new Uri(WebsiteUrl) });
        links.Children.Add(new HyperlinkButton { Content = T("Report an Issue"), NavigateUri = new Uri(IssuesUrl) });

        var row = new Grid { Padding = new Thickness(16), ColumnSpacing = 16, CornerRadius = new CornerRadius(4), Background = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"], BorderBrush = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["CardStrokeColorDefaultBrush"], BorderThickness = new Thickness(1) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var icon = new Image { Source = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri(Path.Combine(AppContext.BaseDirectory, "Assets", "Estris.ico"))), Width = 40, Height = 40 };
        row.Children.Add(icon);
        Grid.SetColumn(details, 1);
        row.Children.Add(details);
        Grid.SetColumn(links, 2);
        row.Children.Add(links);
        return row;
    }

    private static async Task Export(Window window)
    {
        var picker = new FileSavePicker { SuggestedFileName = "Estris Settings" };
        picker.FileTypeChoices.Add("JSON", [".json"]);
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(window));
        var file = await picker.PickSaveFileAsync();
        if (file is not null) await FileIO.WriteTextAsync(file, SettingsStore.Shared.Export());
    }

    private static async Task Import(Window window)
    {
        var picker = new FileOpenPicker();
        picker.FileTypeFilter.Add(".json");
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(window));
        var file = await picker.PickSingleFileAsync();
        if (file is null) return;
        var dialog = new ContentDialog
        {
            XamlRoot = window.Content.XamlRoot,
            Title = T("Replace your settings?"),
            Content = T("Your current settings are replaced by the ones in this file, and Estris opens again."),
            PrimaryButtonText = T("Replace"),
            CloseButtonText = T("Cancel"),
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        try
        {
            SettingsStore.Shared.Import(await FileIO.ReadTextAsync(file));
            SingleInstance.Relaunch();
        }
        catch (Exception)
        {
            await new ContentDialog { XamlRoot = window.Content.XamlRoot, Title = T("This file can't be read."), CloseButtonText = T("OK") }.ShowAsync();
        }
    }
}
