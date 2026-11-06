using Estris.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.ApplicationModel.DataTransfer;
using static Estris.Core.Loc;

namespace Estris.Ui.Panes;

/// Logs of what the utilities noticed and decided, for bug reports. Unlocked by clicking the
/// version in About six times.
public static class DeveloperPane
{
    public static UIElement Build(AppLog log)
    {
        var pane = new Pane();
        var search = new TextBox { PlaceholderText = T("Search logs"), Width = 260 };
        var source = new ComboBox { MinWidth = 160 };
        var list = new ListView { MaxHeight = 480, SelectionMode = ListViewSelectionMode.None, IsItemClickEnabled = true };
        var shown = new List<string>();

        void Refresh()
        {
            var entries = log.Entries.Reverse().ToList();
            var selected = source.SelectedItem as string;
            var sources = new[] { T("All") }.Concat(entries.Select(e => e.Source).Distinct().Order()).ToList();
            if (!sources.SequenceEqual(source.Items.Cast<string>()))
            {
                source.Items.Clear();
                foreach (var name in sources) source.Items.Add(name);
                source.SelectedItem = selected is not null && sources.Contains(selected) ? selected : sources[0];
            }
            shown = entries
                .Where(e => source.SelectedIndex <= 0 || e.Source == (string)source.SelectedItem)
                .Select(e => $"{e.Time:HH:mm:ss}  {e.Source}  {e.Message}")
                .Where(line => line.Contains(search.Text, StringComparison.CurrentCultureIgnoreCase))
                .ToList();
            list.Items.Clear();
            foreach (var line in shown.Take(500))
                list.Items.Add(new TextBlock { Text = line, TextWrapping = TextWrapping.Wrap, FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Cascadia Mono, Consolas") });
        }

        void Copy(string text)
        {
            var package = new DataPackage();
            package.SetText(text);
            Clipboard.SetContent(package);
        }

        search.TextChanged += (_, _) => Refresh();
        source.SelectionChanged += (_, _) => { if (source.SelectedIndex >= 0) Refresh(); };
        list.ItemClick += (_, e) => Copy(((TextBlock)e.ClickedItem).Text);
        void OnChanged() => App.Ui.TryEnqueue(Refresh);
        log.Changed += OnChanged;

        var copy = new Button { Content = T("Copy All") };
        copy.Click += (_, _) => Copy(string.Join("\n", shown));
        var clear = new Button { Content = T("Clear") };
        clear.Click += (_, _) => log.Clear();

        var bar = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, Margin = new Thickness(0, 0, 0, 8) };
        bar.Children.Add(search);
        bar.Children.Add(source);
        bar.Children.Add(copy);
        bar.Children.Add(clear);

        pane.Section(T("Logs"));
        pane.Add(bar);
        pane.Add(list);

        var hide = new Button { Content = T("Hide Developer Settings") };
        hide.Click += (_, _) => SettingsWindow.ShowsDeveloper.Value = false;
        pane.Section(T("Settings"));
        pane.Add(hide);
        Refresh();
        return pane.Root;
    }
}
