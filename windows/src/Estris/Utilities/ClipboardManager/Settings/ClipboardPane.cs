using CommunityToolkit.WinUI.Controls;
using Estris.Core;
using Estris.Ui;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using static Estris.Core.Loc;

namespace Estris.Utilities.ClipboardManager.Settings;

/// The Clipboard pane: the on/off switch, then Settings, History and Excluded Apps tabs.
internal static class ClipboardPane
{
    public static UIElement Build(IUtility utility, ClipboardSettings settings, AppearanceSettings appearance, ClipboardHistory history)
    {
        var pane = new Pane();
        pane.UtilityHeader(utility, T("A history of what you copy, to pick from when pasting."));
        pane.Tabs(
            (T("Settings"), page => BuildSettings(page, settings, appearance, history)),
            (T("History"), page => page.Add(new HistoryList(history))),
            (T("Excluded Apps"), page => page.Add(new ExcludedAppsList(settings.ExcludedApps, T("Nothing copied in an app switched on here is recorded.")))));
        return pane.Root;
    }

    private static void BuildSettings(Pane pane, ClipboardSettings settings, AppearanceSettings appearance, ClipboardHistory history)
    {
        pane.Section(T("General"));
        pane.Add(EntriesRow(settings.MaxEntries));
        pane.Choice(T("Delete entries"), settings.Expiry, ClipboardSettings.ExpiryChoices.ToArray());
        pane.Toggle(T("Ignore passwords"), settings.IgnorePasswords, T("Skips what password managers and other apps mark as not to be kept."));
        pane.Toggle(T("Record images"), settings.RecordImages, T("Keeps copied images in the history alongside text and files."));
        pane.Toggle(T("Remove duplicates"), settings.RemoveDuplicates, T("Copying something already in the history moves it to the top instead of adding it again."));
        pane.Toggle(T("Move pasted entry to the top"), settings.MoveToTopOnPaste, T("When off, the history keeps the order things were copied in, and Ctrl+V keeps pasting the last copied text."));

        pane.Section(T("Appearance"));
        pane.Add(new AppearancePreview(appearance, history));
        static string Whole(double value) => ((int)Math.Round(value)).ToString();
        static string Percent(double value) => $"{(int)Math.Round(value * 100)}%";
        pane.Slider(T("Width"), settings.CardWidth, ClipboardSettings.MinCardWidth, ClipboardSettings.MaxCardWidth, 1, Whole);
        pane.Slider(T("Height"), settings.CardHeight, ClipboardSettings.MinCardHeight, ClipboardSettings.MaxCardHeight, 1, Whole);
        pane.Toggle(T("Show when entries were copied"), settings.ShowCopyDate);
        pane.Toggle(T("Show delete button"), settings.ShowDeleteButton);
        pane.ColorChoice(T("Tint"), appearance.Tint);
        pane.Slider(T("Tint strength"), appearance.TintOpacity, 0, AppearanceSettings.MaxTintOpacity, 0.01, Percent);
        pane.Slider(T("Dim screen"), appearance.BackdropDim, 0, AppearanceSettings.MaxBackdropDim, 0.01, Percent);
        pane.ResetButton(() =>
        {
            settings.ResetLayout();
            appearance.Reset();
        }, T("Reset Appearance to Defaults"));

        pane.Section(T("Shortcuts"));
        pane.Add(new ShortcutList(settings));

        pane.ResetButton(() =>
        {
            settings.Reset();
            appearance.Reset();
        });
    }

    private static SettingsCard EntriesRow(Setting<int> setting)
    {
        var box = new NumberBox
        {
            Minimum = ClipboardSettings.MinItems,
            Maximum = ClipboardSettings.MaxItems,
            SmallChange = ClipboardSettings.ItemsStep,
            LargeChange = ClipboardSettings.ItemsStep,
            SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Inline,
            Value = setting.Value,
        };
        box.ValueChanged += (_, e) => { if (!double.IsNaN(e.NewValue)) setting.Value = (int)e.NewValue; else box.Value = setting.Value; };
        setting.Changed += () => box.Value = setting.Value;
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        row.Children.Add(box);
        row.Children.Add(new TextBlock { Text = T("entries"), VerticalAlignment = VerticalAlignment.Center });
        var card = new SettingsCard { Header = T("Keep up to"), Content = row };
        Pane.WithReset(card, setting);
        return card;
    }
}

/// The overlay's shortcut and its alternatives, with a button to add one. Only the first has a
/// default; alternatives are added by hand, and a change that would repeat another is undone.
internal sealed class ShortcutList : StackPanel
{
    private readonly ClipboardSettings settings;

    public ShortcutList(ClipboardSettings settings)
    {
        this.settings = settings;
        Spacing = Pane.RowSpacing;
        Rebuild();
        foreach (var slot in settings.AlternativeShortcuts)
        {
            var previous = slot.Value;
            slot.Changed += () =>
            {
                var isRepeat = slot.Value != ClipboardSettings.NoShortcut && settings.Shortcuts.Count(s => s == slot.Value) > 1;
                if (isRepeat) { slot.Value = previous; return; }
                var wasAddedOrRemoved = (previous == ClipboardSettings.NoShortcut) != (slot.Value == ClipboardSettings.NoShortcut);
                previous = slot.Value;
                if (wasAddedOrRemoved) Rebuild();
            };
        }
    }

    private void Rebuild()
    {
        Children.Clear();
        var main = new SettingsCard { Header = T("Open overlay"), Content = new ShortcutBox(settings.MainShortcut) };
        Pane.WithReset(main, settings.MainShortcut);
        Children.Add(main);

        foreach (var slot in settings.AlternativeShortcuts.Where(s => s.Value != ClipboardSettings.NoShortcut))
        {
            var remove = new Button { Content = new FontIcon { Glyph = "", FontSize = 14 }, Padding = new Thickness(8) };
            ToolTipService.SetToolTip(remove, T("Remove this shortcut"));
            Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(remove, T("Remove this shortcut"));
            remove.Click += (_, _) => slot.Reset();
            var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            row.Children.Add(new ShortcutBox(slot));
            row.Children.Add(remove);
            Children.Add(new SettingsCard { Header = T("Alternative"), Content = row });
        }

        var add = new Button { Content = T("Add Alternative Shortcut"), Margin = new Thickness(0, 8, 0, 0) };
        add.Click += (_, _) => add.IsEnabled = settings.AddAlternativeShortcut();
        add.IsEnabled = settings.AlternativeShortcuts.Any(s => s.Value == ClipboardSettings.NoShortcut);
        Children.Add(add);
    }
}
