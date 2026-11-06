using CommunityToolkit.WinUI.Controls;
using Estris.Core;
using Estris.Utilities;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using Windows.UI;
using static Estris.Core.Loc;

namespace Estris.Ui;

/// Builds a settings page the way Windows 11's Settings looks: section titles over cards. Every
/// row built from a Setting gets its right-click Reset to Default here, and pane.ResetButton
/// ends the page, so a pane only says what it has.
public sealed class Pane
{
    public const double RowSpacing = 4;
    public StackPanel Root { get; } = new() { Spacing = RowSpacing, Margin = new Thickness(0, 0, 0, 32) };

    /// Where rows go; tabs point this at their own page while they are built.
    private Panel target;

    public Pane() => target = Root;

    /// The utility's description and big on/off switch, first in every utility's pane.
    public void UtilityHeader(IUtility utility, string description)
    {
        var toggle = new ToggleSwitch { IsOn = utility.Enabled.Value };
        Bind(toggle, utility.Enabled);
        var card = new SettingsCard
        {
            Header = T(utility.Title),
            Description = description,
            HeaderIcon = new FontIcon { Glyph = utility.Glyph },
            Content = toggle,
        };
        WithReset(card, utility.Enabled);
        target.Children.Add(card);
    }

    public void Section(string title)
    {
        target.Children.Add(new TextBlock
        {
            Text = title,
            Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"],
            Margin = new Thickness(1, 24, 0, 6),
        });
    }

    /// A line of help under the section title or between rows.
    public void Note(string text) => target.Children.Add(new TextBlock
    {
        Text = text,
        TextWrapping = TextWrapping.Wrap,
        Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
        Margin = new Thickness(1, 2, 1, 6),
    });

    /// A warning under a row: the triangle in the caution colour, the text in the usual one.
    public InfoBar Warning(string text)
    {
        var bar = new InfoBar { IsOpen = true, IsClosable = false, Severity = InfoBarSeverity.Warning, Message = text };
        target.Children.Add(bar);
        return bar;
    }

    public void Add(UIElement element) => target.Children.Add(element);

    /// Any control on a card, for what the rows below don't cover.
    public SettingsCard Card(string title, FrameworkElement? control, string? description = null, ISetting? resets = null)
    {
        var card = new SettingsCard { Header = title, Description = description, Content = control };
        if (resets is not null) WithReset(card, resets);
        target.Children.Add(card);
        return card;
    }

    public SettingsCard Toggle(string title, Setting<bool> setting, string? description = null)
    {
        var toggle = new ToggleSwitch();
        toggle.IsOn = setting.Value;
        Bind(toggle, setting);
        return Card(title, toggle, description, setting);
    }

    public SettingsCard Slider(string title, Setting<double> setting, double minimum, double maximum, double step, Func<double, string> format, string? description = null)
    {
        var slider = new Slider { Minimum = minimum, Maximum = maximum, StepFrequency = step, SmallChange = step, Value = setting.Value, Width = 220 };
        var value = new TextBlock { VerticalAlignment = VerticalAlignment.Center, MinWidth = 52, TextAlignment = TextAlignment.Right, Text = format(setting.Value) };
        slider.IsThumbToolTipEnabled = false;
        slider.ValueChanged += (_, e) => setting.Value = e.NewValue;
        setting.Changed += () =>
        {
            if (slider.Value != setting.Value) slider.Value = setting.Value;
            value.Text = format(setting.Value);
        };
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        row.Children.Add(value);
        row.Children.Add(slider);
        return Card(title, row, description, setting);
    }

    public SettingsCard Choice<T1>(string title, Setting<T1> setting, (T1 Value, string Label)[] options, string? description = null) where T1 : notnull
    {
        var box = new ComboBox { MinWidth = 180 };
        foreach (var (_, label) in options) box.Items.Add(label);
        void Sync() => box.SelectedIndex = Array.FindIndex(options, o => o.Value.Equals(setting.Value));
        Sync();
        box.SelectionChanged += (_, _) => { if (box.SelectedIndex >= 0) setting.Value = options[box.SelectedIndex].Value; };
        setting.Changed += Sync;
        return Card(title, box, description, setting);
    }

    /// A color, saved as #RRGGBB.
    public SettingsCard ColorChoice(string title, Setting<string> setting, string? description = null)
    {
        var swatch = new Microsoft.UI.Xaml.Shapes.Rectangle { Width = 40, Height = 20, RadiusX = 4, RadiusY = 4 };
        void Sync() => swatch.Fill = new SolidColorBrush(ParseColor(setting.Value));
        Sync();
        setting.Changed += Sync;
        var picker = new Microsoft.UI.Xaml.Controls.ColorPicker { Color = ParseColor(setting.Value), IsAlphaEnabled = false, IsMoreButtonVisible = false };
        picker.ColorChanged += (_, e) => setting.Value = $"#{e.NewColor.R:X2}{e.NewColor.G:X2}{e.NewColor.B:X2}";
        var button = new Button { Content = swatch, Flyout = new Flyout { Content = picker } };
        return Card(title, button, description, setting);
    }

    public SettingsCard ShortcutRow(string title, Setting<Shortcut> setting, string? description = null) =>
        Card(title, new ShortcutBox(setting), description, setting);

    /// A page of tabs under the header. Each tab's content is built the first time it is shown.
    public void Tabs(params (string Title, Action<Pane> Build)[] tabs)
    {
        var bar = new SelectorBar { Margin = new Thickness(-8, 12, 0, 4) };
        var page = new ContentPresenter();
        var built = new Dictionary<int, UIElement>();
        foreach (var (title, _) in tabs) bar.Items.Add(new SelectorBarItem { Text = title });
        bar.SelectionChanged += (_, _) =>
        {
            var index = bar.Items.IndexOf(bar.SelectedItem);
            if (!built.TryGetValue(index, out var content))
            {
                var pane = new Pane();
                tabs[index].Build(pane);
                content = built[index] = pane.Root;
            }
            page.Content = content;
        };
        bar.SelectedItem = bar.Items[0];
        target.Children.Add(bar);
        target.Children.Add(page);
    }

    /// Ends the page. Resets what's listed; on/off switches, excluded apps and history stay.
    public void ResetButton(Action reset, string? title = null)
    {
        var button = new Button { Content = title ?? T("Reset to Defaults"), Margin = new Thickness(0, 24, 0, 0) };
        button.Click += (_, _) => reset();
        target.Children.Add(button);
    }

    /// Reset to Default on a row's right click, only while it isn't at its default.
    public static void WithReset(FrameworkElement row, ISetting setting)
    {
        row.RightTapped += (_, e) =>
        {
            if (setting.IsDefault) return;
            var item = new MenuFlyoutItem { Text = T("Reset to Default"), Icon = new FontIcon { Glyph = "" } };
            item.Click += (_, _) => setting.Reset();
            var menu = new MenuFlyout();
            menu.Items.Add(item);
            menu.ShowAt(row, e.GetPosition(row));
            e.Handled = true;
        };
    }

    private static void Bind(ToggleSwitch toggle, Setting<bool> setting)
    {
        toggle.OnContent = T("On");
        toggle.OffContent = T("Off");
        toggle.Toggled += (_, _) => setting.Value = toggle.IsOn;
        setting.Changed += () => { if (toggle.IsOn != setting.Value) toggle.IsOn = setting.Value; };
    }

    public static Color ParseColor(string hex)
    {
        var value = Convert.ToInt32(hex.TrimStart('#'), 16);
        return Color.FromArgb(255, (byte)(value >> 16), (byte)(value >> 8), (byte)value);
    }
}
