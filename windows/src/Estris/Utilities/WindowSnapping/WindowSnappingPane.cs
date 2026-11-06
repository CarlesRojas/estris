using CommunityToolkit.WinUI.Controls;
using Estris.Core;
using Estris.Ui;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Markup;
using Microsoft.UI.Xaml.Media;
using System.Runtime.InteropServices;
using static Estris.Core.Loc;

namespace Estris.Utilities.WindowSnapping;

/// The Window Snapping pane: the on/off switch, then dragging, Arrange All, gestures and the
/// shortcuts on one page.
public static partial class WindowSnappingPane
{
    private const uint SPI_GETWINARRANGING = 0x82;
    private const double IconWidth = 18, IconHeight = 14, IconRadius = 2, IconStroke = 1.25;
    private static readonly TimeSpan SnapCheckInterval = TimeSpan.FromSeconds(2);

    [LibraryImport("user32", EntryPoint = "SystemParametersInfoW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool SystemParametersInfo(uint action, uint param, out int value, uint update);

    /// Whether Windows's own Snap is on, which reacts to the same drags.
    private static bool IsWindowsSnapOn => SystemParametersInfo(SPI_GETWINARRANGING, 0, out var on, 0) && on != 0;

    public static UIElement Build(IUtility utility, WindowSnappingSettings settings)
    {
        var pane = new Pane();
        pane.UtilityHeader(utility, T("Snap windows to halves, corners and thirds with shortcuts or by dragging them to a screen edge."));
        AddWindowsSnapWarning(pane);
        AddDragging(pane, settings);
        AddArrangeAll(pane, settings);
        AddGestures(pane, settings);
        pane.Section(T("Shortcuts"));
        foreach (var action in SnapActions.All)
            AddShortcut(pane, settings, action.Id(), action.Title(), ActionIcon(action));
        pane.ResetButton(settings.Reset);
        return pane.Root;
    }

    /// Shown while Windows's own Snap is on, read again every few seconds while the pane shows,
    /// so it goes away once it is turned off in Windows Settings.
    private static void AddWindowsSnapWarning(Pane pane)
    {
        var open = new Button { Content = T("Open Multitasking Settings") };
        open.Click += async (_, _) => await Windows.System.Launcher.LaunchUriAsync(new Uri("ms-settings:multitasking"));
        var bar = pane.Warning(T("Windows's own Snap reacts to the same drags. Turn off “Snap windows” in Settings > System > Multitasking so they don't both act."));
        bar.Margin = new Thickness(0, 8, 0, 0);
        bar.ActionButton = open;
        bar.IsOpen = IsWindowsSnapOn;
        var timer = App.Ui.CreateTimer();
        timer.Interval = SnapCheckInterval;
        timer.Tick += (_, _) => bar.IsOpen = IsWindowsSnapOn;
        pane.Root.Loaded += (_, _) =>
        {
            bar.IsOpen = IsWindowsSnapOn;
            timer.Start();
        };
        pane.Root.Unloaded += (_, _) => timer.Stop();
    }

    private static void AddDragging(Pane pane, WindowSnappingSettings settings)
    {
        pane.Section(T("Dragging"));
        pane.Toggle(T("Snap by dragging a window to a screen edge"), settings.SnapsByDragging);
        var edge = pane.Slider(T("Edge area"), settings.EdgeArea, WindowSnappingSettings.MinimumEdgeArea, WindowSnappingSettings.MaximumEdgeArea, 1, v => T("%lld px", (long)v));
        EnableWith(settings.SnapsByDragging, edge);
        pane.Toggle(T("Resize side-by-side windows together"), settings.ResizesTogether);
        pane.Toggle(T("Fill the space next to other windows"), settings.FillsSpace, T("Press a shortcut again for the exact size, or hold Ctrl while dragging."));
    }

    private static void AddArrangeAll(Pane pane, WindowSnappingSettings settings)
    {
        pane.Section(T("Auto Arrange All Windows"));
        pane.Toggle(T("Place all windows side by side"), settings.ArrangesAll, T("One shortcut fits every window on the screen without overlaps, each near where it was."));
        var row = AddShortcut(pane, settings, SnapKeys.ArrangeAllId, T("Arrange All Windows"), new FontIcon { Glyph = "" });
        EnableWith(settings.ArrangesAll, row);
    }

    private static void AddGestures(Pane pane, WindowSnappingSettings settings)
    {
        pane.Section(T("Gestures"));
        foreach (var gesture in SnapGestures.All)
        {
            var toggle = new ToggleSwitch { IsOn = settings.Has(gesture), OnContent = T("On"), OffContent = T("Off") };
            toggle.Toggled += (_, _) => { if (toggle.IsOn != settings.Has(gesture)) settings.Set(gesture, toggle.IsOn); };
            settings.Gestures.Changed += () => { if (toggle.IsOn != settings.Has(gesture)) toggle.IsOn = settings.Has(gesture); };
            var card = pane.Card(gesture.Title(), toggle, resets: new SnapGestureSetting(settings, gesture));
            EnableWith(settings.SnapsByDragging, card);
        }
    }

    private static void EnableWith(Setting<bool> setting, params Control[] rows)
    {
        void Sync()
        {
            foreach (var row in rows) row.IsEnabled = setting.Value;
        }
        Sync();
        setting.Changed += Sync;
    }

    /// A shortcut: Ctrl + Alt and a menu to pick its key, with what else uses it right below.
    private static SettingsCard AddShortcut(Pane pane, WindowSnappingSettings settings, string id, string title, IconElement icon)
    {
        var keys = new ComboBox { MinWidth = 110 };
        foreach (var vk in SnapKeys.All) keys.Items.Add(KeyNames.Name(vk));
        void SyncKey() => keys.SelectedIndex = Array.IndexOf(SnapKeys.All, settings.Key(id));
        SyncKey();
        keys.SelectionChanged += (_, _) =>
        {
            if (keys.SelectedIndex >= 0 && SnapKeys.All[keys.SelectedIndex] != settings.Key(id))
                settings.SetKey(id, SnapKeys.All[keys.SelectedIndex]);
        };
        var content = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        content.Children.Add(new TextBlock
        {
            Text = "Ctrl + Alt +",
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
        });
        content.Children.Add(keys);
        var card = pane.Card(title, content, resets: new SnapKeySetting(settings, id));
        card.HeaderIcon = icon;

        var warnings = new StackPanel { Spacing = Pane.RowSpacing };
        pane.Add(warnings);
        void SyncConflicts()
        {
            warnings.Children.Clear();
            foreach (var text in Conflicts(settings, id))
                warnings.Children.Add(new InfoBar { IsOpen = true, IsClosable = false, Severity = InfoBarSeverity.Warning, Message = text });
        }
        SyncConflicts();
        settings.KeyCodes.Changed += () =>
        {
            SyncKey();
            SyncConflicts();
        };
        settings.ArrangesAll.Changed += SyncConflicts;
        return card;
    }

    /// The other Window Snapping shortcuts on the same key, and what else the key does.
    private static IEnumerable<string> Conflicts(WindowSnappingSettings settings, string id)
    {
        if (id == SnapKeys.ArrangeAllId && !settings.ArrangesAll.Value) yield break;
        var key = settings.Key(id);
        // In priority order: the first one with a key gets it.
        var sharing = SnapKeys.Ids.Where(other => settings.Key(other) == key && (other != SnapKeys.ArrangeAllId || settings.ArrangesAll.Value)).ToList();
        if (sharing.Count > 1)
        {
            if (sharing[0] == id)
                yield return T("Also set for %@. This one takes priority.", string.Join(", ", sharing.Skip(1).Select(TitleOf)));
            else
                yield return T("Also set for %@, which takes priority, so this one won't work.", TitleOf(sharing[0]));
        }
        if (SnapKeys.TypedWithAltGr(key) is { } typed)
            yield return T("On this keyboard Ctrl + Alt + %@ types “%@”. Pressing Ctrl and Alt runs this shortcut instead; the AltGr key keeps typing it.", KeyNames.Name(key), typed);
        if (SnapKeys.IsTakenByAnotherApp(key))
            yield return T("Another app uses this shortcut. Estris takes it while Window Snapping is on, or pick another key.");
    }

    private static string TitleOf(string id) => SnapActions.FromId(id)?.Title() ?? T("Arrange All Windows");

    /// A small screen with the part the action takes filled in, like Windows's snap layouts.
    private static IconElement ActionIcon(SnapAction action)
    {
        if (action.Shape() is not { } shape) return new FontIcon { Glyph = "" };
        var x = 0.0;
        var y = 1.0;
        var (width, height) = (IconWidth, IconHeight);
        string Outline(double inset)
        {
            var radius = Math.Max(IconRadius - inset, 0.5);
            var (left, top, right, bottom) = (x + inset, y + inset, x + width - inset, y + height - inset);
            return FormattableString.Invariant($"M{left + radius},{top} L{right - radius},{top} A{radius},{radius} 0 0 1 {right},{top + radius} L{right},{bottom - radius} A{radius},{radius} 0 0 1 {right - radius},{bottom} L{left + radius},{bottom} A{radius},{radius} 0 0 1 {left},{bottom - radius} L{left},{top + radius} A{radius},{radius} 0 0 1 {left + radius},{top} Z ");
        }
        var (insideLeft, insideTop) = (x + IconStroke * 2, y + IconStroke * 2);
        var (insideWidth, insideHeight) = (width - IconStroke * 4, height - IconStroke * 4);
        var fill = FormattableString.Invariant($"M{insideLeft + shape.Left * insideWidth},{insideTop + shape.Top * insideHeight} L{insideLeft + shape.Right * insideWidth},{insideTop + shape.Top * insideHeight} L{insideLeft + shape.Right * insideWidth},{insideTop + shape.Bottom * insideHeight} L{insideLeft + shape.Left * insideWidth},{insideTop + shape.Bottom * insideHeight} Z");
        var data = "F0 " + Outline(0) + Outline(IconStroke) + fill;
        return new PathIcon { Data = (Geometry)XamlBindingHelper.ConvertValue(typeof(Geometry), data) };
    }
}
