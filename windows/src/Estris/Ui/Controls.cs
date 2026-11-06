using CommunityToolkit.WinUI.Controls;
using Estris.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using static Estris.Core.Loc;

namespace Estris.Ui;

/// A button showing a shortcut: click it, then press the new combination. It needs Ctrl, Alt or
/// Win; Esc cancels.
public sealed class ShortcutBox : Button
{
    private readonly Setting<Shortcut> setting;
    private bool isRecording;

    public ShortcutBox(Setting<Shortcut> setting)
    {
        this.setting = setting;
        MinWidth = 140;
        Content = setting.Value.Display;
        setting.Changed += () => Content = setting.Value.Display;
        Click += (_, _) => Toggle();
    }

    private void Toggle()
    {
        if (isRecording) { Stop(); return; }
        isRecording = true;
        Content = T("Press a shortcut…");
        InputHooks.Subscribe(OnKey);
        LostFocus += OnLostFocus;
    }

    private void OnLostFocus(object sender, RoutedEventArgs e) => Stop();

    private void Stop()
    {
        if (!isRecording) return;
        isRecording = false;
        InputHooks.Unsubscribe(OnKey);
        LostFocus -= OnLostFocus;
        Content = setting.Value.Display;
    }

    private void OnKey(KeyEvent e)
    {
        if (e.IsOwn || !e.IsDown || KeyNames.IsModifier(e.Vk)) return;
        e.Handled = true;
        var shortcut = new Shortcut(
            Hotkeys.IsHeld(0xA2) || Hotkeys.IsHeld(0xA3),
            Hotkeys.IsHeld(0xA0) || Hotkeys.IsHeld(0xA1),
            Hotkeys.IsHeld(0xA4) || Hotkeys.IsHeld(0xA5),
            Hotkeys.IsHeld(0x5B) || Hotkeys.IsHeld(0x5C),
            e.Vk);
        App.Ui.TryEnqueue(() =>
        {
            if (e.Vk != 0x1B && shortcut.HasCommandModifier) setting.Value = shortcut;
            Stop();
        });
    }
}

/// Every installed app with a switch, all off: switch one on to exclude it. Saved as a list of
/// program names. Includes apps saved that are no longer in the Start menu.
public sealed class ExcludedAppsList : StackPanel
{
    public ExcludedAppsList(Setting<List<string>> excluded, string? description = null)
    {
        Spacing = Pane.RowSpacing;
        if (description is not null)
            Children.Add(new TextBlock { Text = description, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(1, 8, 1, 8), Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"] });

        var search = new AutoSuggestBox { PlaceholderText = T("Search apps"), QueryIcon = new SymbolIcon(Symbol.Find), Margin = new Thickness(0, 0, 0, 8) };
        var rows = new StackPanel { Spacing = Pane.RowSpacing };
        Children.Add(search);
        Children.Add(rows);

        var cards = new List<(string Name, SettingsCard Card)>();
        foreach (var app in InstalledApps.All)
        {
            var toggle = new ToggleSwitch { IsOn = excluded.Value.Contains(app.Program), OnContent = T("Excluded"), OffContent = "" };
            toggle.Toggled += (_, _) =>
            {
                var list = excluded.Value.Where(p => p != app.Program).ToList();
                if (toggle.IsOn) list.Add(app.Program);
                excluded.Value = list;
            };
            var card = new SettingsCard { Header = app.Name, Description = app.Program, Content = toggle };
            cards.Add((app.Name, card));
            rows.Children.Add(card);
        }
        search.TextChanged += (_, _) =>
        {
            foreach (var (name, card) in cards)
                card.Visibility = name.Contains(search.Text, StringComparison.CurrentCultureIgnoreCase) ? Visibility.Visible : Visibility.Collapsed;
        };
    }
}
