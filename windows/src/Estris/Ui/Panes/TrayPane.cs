using Estris.Tray;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using static Estris.Core.Loc;

namespace Estris.Ui.Panes;

/// Picks the tray icon and what the tray menu shows of each utility.
public static class TrayPane
{
    public static UIElement Build(TraySettings settings)
    {
        var pane = new Pane();
        pane.Section(T("Icon"));
        pane.Add(IconGrid(settings));
        pane.Toggle(T("Custom color"), settings.UsesCustomColor, T("Draws the icon in a color of your choice instead of the taskbar's own."));
        pane.ColorChoice(T("Color"), settings.CustomColor);

        pane.Section(T("Clipboard"));
        pane.Toggle(T("Show recent entries"), settings.ShowsClipboardHistory);
        pane.Slider(T("Entries"), settings.ClipboardEntries, 1, TraySettings.MaxClipboardEntries, 1, v => ((int)v).ToString());
        pane.Toggle(T("Show Clear History button"), settings.ShowsClearHistory);

        pane.Section(T("Color Picker"));
        pane.Toggle(T("Show Pick a Color button"), settings.ShowsColorPicker);
        pane.Toggle(T("Show recent colors"), settings.ShowsRecentColors);

        pane.ResetButton(settings.Reset);
        return pane.Root;
    }

    private static UIElement IconGrid(TraySettings settings)
    {
        var grid = new VariableSizedWrapGrid { Orientation = Orientation.Horizontal, MaximumRowsOrColumns = 13, ItemWidth = 48, ItemHeight = 48 };
        var buttons = new List<(string Id, ToggleButton Button)>();
        void Sync()
        {
            foreach (var (id, button) in buttons) button.IsChecked = id == settings.Icon.Value;
        }
        foreach (var id in TrayIcons.AllIds)
        {
            var button = new ToggleButton
            {
                Width = 44,
                Height = 44,
                Padding = new Thickness(0),
                Content = id == TrayIcons.DefaultId ? new FontIcon { Glyph = "" } : new FontIcon { Glyph = id },
            };
            button.Click += (_, _) => settings.Icon.Value = id;
            buttons.Add((id, button));
            grid.Children.Add(button);
        }
        Sync();
        settings.Icon.Changed += Sync;
        return grid;
    }
}
