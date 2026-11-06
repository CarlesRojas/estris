using Estris.Ui;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using static Estris.Core.Loc;

namespace Estris.Utilities.Remap;

/// The Remap settings pane: the on/off switch, then Mappings and Event Viewer tabs.
public static class RemapPane
{
    public static UIElement Build(RemapUtility remap)
    {
        var pane = new Pane();
        pane.UtilityHeader(remap, T("Change what keys and mouse buttons do, per device."));
        MappingsView? mappings = null;
        pane.Tabs(
            (T("Mappings"), tab => mappings = new MappingsView(remap, tab)),
            (T("Event Viewer"), tab => tab.Add(new EventViewer(remap, (device, input) =>
            {
                remap.Settings.AddMapping(input, device);
                mappings?.ScrollTo(device.Id);
                var bar = pane.Root.Children.OfType<SelectorBar>().First();
                bar.SelectedItem = bar.Items[0];
            }))));
        return pane.Root;
    }
}

/// Every device as its own group of mappings, all on one page.
internal sealed class MappingsView
{
    private const double RowMinWidth = 180;
    private const double FlyoutWidth = 340, OutputFlyoutHeight = 440, InputFlyoutHeight = 480;
    private const string EditGlyph = "", ArrowGlyph = "", SwapGlyph = "", DeleteGlyph = "", AddGlyph = "", RecordGlyph = "";

    private readonly RemapUtility remap;
    private readonly RemapSettings settings;
    private readonly StackPanel groups = new() { Spacing = Pane.RowSpacing };
    /// Only with more than one device that can send keys, when which one sent a key matters.
    private readonly TextBlock keyboardsNote = new()
    {
        Text = T("With more than one keyboard, keys go by the one you're typing on, as Windows only says which keyboard sent a key after apps get it. Right after switching keyboards, a key that differs between them may act as on the other one, or only when you let go of it. Mouse buttons always know their mouse."),
        TextWrapping = TextWrapping.Wrap,
        Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
        Margin = new Thickness(1, 2, 1, 6),
    };
    private readonly Dictionary<string, FrameworkElement> headers = [];
    private bool? isBrightnessSupported;
    private string? scrollTarget;

    public MappingsView(RemapUtility remap, Pane tab)
    {
        this.remap = remap;
        settings = remap.Settings;
        tab.Note(T("Keys and buttons can't be remapped while a window running as administrator is in front: Windows keeps them from other apps."));
        tab.Add(keyboardsNote);
        tab.Add(groups);

        void Rebuild() => App.Ui.TryEnqueue(this.Rebuild);
        groups.Loaded += (_, _) =>
        {
            settings.Devices.Changed += Rebuild;
            settings.CustomNames.Changed += Rebuild;
            settings.CustomKinds.Changed += Rebuild;
            remap.Devices.Changed += Rebuild;
            remap.IsOnMappings = true;
            this.Rebuild();
        };
        // Rows left with both sides empty are dropped once the page is left.
        groups.Unloaded += (_, _) =>
        {
            settings.Devices.Changed -= Rebuild;
            settings.CustomNames.Changed -= Rebuild;
            settings.CustomKinds.Changed -= Rebuild;
            remap.Devices.Changed -= Rebuild;
            remap.IsOnMappings = false;
            settings.RemoveEmptyMappings();
        };
    }

    public void ScrollTo(string deviceId) => scrollTarget = deviceId;

    /// Connected devices, then disconnected ones that still have mappings, with the names the
    /// user gave them.
    private List<InputDevice> Listed()
    {
        var connected = remap.Devices.Connected;
        var saved = settings.Devices.Value
            .Where(d => d.Value.Mappings.Count > 0 && connected.All(c => c.Id != d.Key))
            .Select(d => new InputDevice(d.Key, d.Value.Name, d.Value.Kind, false));
        return connected.Concat(saved)
            .Select(d => d with { Name = settings.Name(d), Kind = settings.Kind(d) })
            .OrderBy(d => d.Name, StringComparer.CurrentCultureIgnoreCase)
            .ToList();
    }

    private void Rebuild()
    {
        keyboardsNote.Visibility = remap.Devices.Connected.Count(d => d.HasKeyboard) > 1 ? Visibility.Visible : Visibility.Collapsed;
        groups.Children.Clear();
        headers.Clear();
        foreach (var device in Listed())
        {
            var header = Header(device);
            headers[device.Id] = header;
            groups.Children.Add(header);
            foreach (var mapping in settings.Mappings(device.Id)) groups.Children.Add(Row(mapping, device));
            groups.Children.Add(AddButton(device));
        }
        if (scrollTarget is { } target && headers.TryGetValue(target, out var element))
        {
            scrollTarget = null;
            element.Loaded += (_, _) => element.StartBringIntoView(new BringIntoViewOptions { VerticalAlignmentRatio = 0 });
        }
    }

    /// "&lt;name&gt; Mappings", after the device's icon, which changes its kind, with a pencil to rename it.
    private FrameworkElement Header(InputDevice device)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, Margin = new Thickness(1, 20, 0, 6) };
        row.Children.Add(KindButton(device));
        row.Children.Add(new TextBlock
        {
            Text = device.IsConnected ? T("%@ Mappings", device.Name) : T("%@ Mappings (not connected)", device.Name),
            Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"],
            VerticalAlignment = VerticalAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis,
        });
        var rename = IconButton(EditGlyph, T("Rename this device"));
        rename.Click += async (_, _) => await Rename(device, rename.XamlRoot);
        row.Children.Add(rename);
        return row;
    }

    /// Windows doesn't say what a device is, and receivers look like both, so it can be told here.
    /// It picks the icon and what the pickers list first, and whether it counts as a keyboard.
    private Button KindButton(InputDevice device)
    {
        var button = IconButton(device.Glyph, T("Change device type"));
        var detected = remap.Devices.Connected.FirstOrDefault(d => d.Id == device.Id)?.Kind;
        var menu = new MenuFlyout();
        foreach (var (kind, title) in new[] { (DeviceKind.Keyboard, T("Keyboard")), (DeviceKind.Mouse, T("Mouse")) })
        {
            var item = new RadioMenuFlyoutItem { Text = title, IsChecked = device.Kind == kind };
            item.Click += (_, _) => settings.SetKind(device.Id, kind, detected);
            menu.Items.Add(item);
        }
        button.Flyout = menu;
        return button;
    }

    private async Task Rename(InputDevice device, XamlRoot root)
    {
        var name = new TextBox { Text = device.Name, PlaceholderText = T("Name") };
        var dialog = new ContentDialog
        {
            XamlRoot = root,
            Title = T("Rename Device"),
            Content = name,
            PrimaryButtonText = T("Rename"),
            CloseButtonText = T("Cancel"),
            DefaultButton = ContentDialogButton.Primary,
        };
        if (settings.CustomNames.Value.ContainsKey(device.Id)) dialog.SecondaryButtonText = T("Use Original Name");
        var result = await dialog.ShowAsync();
        if (result == ContentDialogResult.Primary) settings.Rename(device.Id, name.Text);
        else if (result == ContentDialogResult.Secondary) settings.Rename(device.Id, "");
    }

    private FrameworkElement AddButton(InputDevice device)
    {
        var content = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        content.Children.Add(new FontIcon { Glyph = AddGlyph, FontSize = 12 });
        content.Children.Add(new TextBlock { Text = T("Add Mapping") });
        var button = new Button { Content = content, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 4, 0, 0) };
        AutomationProperties.SetName(button, T("Add Mapping"));
        button.Click += (_, _) => settings.AddMapping(device);
        return button;
    }

    /// The mapping turned around, or null when its result can't be a source (a system action,
    /// nothing, or the left button).
    private static Mapping? Swapped(Mapping mapping)
    {
        RemapInput? input = mapping.Output switch
        {
            null => null,
            { Kind: OutputKind.Key } output => RemapInput.Key(output.Code),
            { Kind: OutputKind.MouseButton, Code: > 0 } output => RemapInput.Button(output.Code),
            _ => (RemapInput?)RemapInput.LeftButton,
        };
        if (input == RemapInput.LeftButton) return null;
        RemapOutput? turned = mapping.Input switch
        {
            null => null,
            { IsMouse: true } source => RemapOutput.Button(source.Code),
            { } source => RemapOutput.Key(source.Code),
        };
        // The new input was picked from the list, so it belongs to this device.
        return mapping with { Input = input, Output = turned, IsDeviceLess = null };
    }

    private FrameworkElement Row(Mapping mapping, InputDevice device)
    {
        var conflict = settings.Conflict(mapping, device.Id);
        var grid = new Grid { ColumnSpacing = 10 };
        foreach (var width in new[] { GridLength.Auto, GridLength.Auto, GridLength.Auto, new GridLength(1, GridUnitType.Star), GridLength.Auto, GridLength.Auto })
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = width });

        var source = SideButton(mapping.Input is { } input ? Choices.Title(input) : T("Choose…"));
        source.Flyout = PickerFlyout(InputFlyoutHeight, close => InputPicker(device, (chosen, isDeviceLess) =>
        {
            close();
            settings.Update(mapping with { Input = chosen, IsDeviceLess = isDeviceLess ? true : null }, device.Id);
        }));
        var result = SideButton(mapping.Output is { } output ? Choices.Title(output) : T("Choose…"));
        result.Flyout = PickerFlyout(OutputFlyoutHeight, close => new ChoiceList<RemapOutput>(Choices.Outputs(), chosen =>
        {
            close();
            settings.Update(mapping with { Output = chosen }, device.Id);
        }));
        result.IsEnabled = conflict is null;

        var turned = Swapped(mapping);
        var swap = IconButton(SwapGlyph, T("Swap From and To"));
        swap.IsEnabled = turned is not null;
        swap.Click += (_, _) => { if (turned is not null) settings.Update(turned, device.Id); };
        var remove = IconButton(DeleteGlyph, T("Remove this mapping"));
        remove.Click += (_, _) => settings.Remove(mapping, device.Id);

        var arrow = new FontIcon { Glyph = ArrowGlyph, FontSize = 12, Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"] };
        Place(grid, source, 0);
        Place(grid, arrow, 1);
        Place(grid, result, 2);
        Place(grid, swap, 4);
        Place(grid, remove, 5);

        var content = new StackPanel { Spacing = 6 };
        content.Children.Add(grid);
        // On a line of its own under the mapping.
        if (conflict is not null) content.Children.Add(Warning(conflict.Message, conflict.Explanation));
        if (mapping.Output?.Action is SystemAction.BrightnessUp or SystemAction.BrightnessDown) AddBrightnessWarning(content);
        return Card(content);
    }

    /// Asked once, off the UI thread, since DDC/CI takes a moment.
    private void AddBrightnessWarning(StackPanel content)
    {
        var message = T("No display here lets Windows change its brightness.");
        if (isBrightnessSupported == false) content.Children.Add(Warning(message));
        if (isBrightnessSupported is not null) return;
        _ = Task.Run(() =>
        {
            var isSupported = Brightness.IsSupported();
            App.Ui.TryEnqueue(() =>
            {
                isBrightnessSupported = isSupported;
                if (!isSupported) Rebuild();
            });
        });
    }

    private static void Place(Grid grid, FrameworkElement element, int column)
    {
        Grid.SetColumn(element, column);
        element.VerticalAlignment = VerticalAlignment.Center;
        grid.Children.Add(element);
    }

    private static Border Card(UIElement content) => new()
    {
        Child = content,
        Padding = new Thickness(16, 8, 12, 8),
        MinHeight = 52,
        CornerRadius = (CornerRadius)Application.Current.Resources["ControlCornerRadius"],
        Background = (Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"],
        BorderBrush = (Brush)Application.Current.Resources["CardStrokeColorDefaultBrush"],
        BorderThickness = new Thickness(1),
    };

    private static Button SideButton(string title) => new()
    {
        Content = title,
        MinWidth = RowMinWidth,
        HorizontalContentAlignment = HorizontalAlignment.Left,
    };

    private static Button IconButton(string glyph, string help)
    {
        var button = new Button
        {
            Content = new FontIcon { Glyph = glyph, FontSize = 14 },
            Padding = new Thickness(8),
            Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
            BorderThickness = new Thickness(0),
        };
        ToolTipService.SetToolTip(button, help);
        AutomationProperties.SetName(button, help);
        return button;
    }

    private static FrameworkElement Warning(string message, string? explanation = null)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        row.Children.Add(new FontIcon { Glyph = "", FontSize = 14, Foreground = (Brush)Application.Current.Resources["SystemFillColorCautionBrush"] });
        row.Children.Add(new TextBlock { Text = message, Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"], VerticalAlignment = VerticalAlignment.Center });
        if (explanation is not null) ToolTipService.SetToolTip(row, explanation);
        return row;
    }

    /// A flyout built when opened, as the lists are long and most rows never open theirs. build
    /// is given a way to close it.
    private static Flyout PickerFlyout(double height, Func<Action, FrameworkElement> build)
    {
        // Free to reach past the window, so it opens under its button even low on the page.
        var flyout = new Flyout { Placement = FlyoutPlacementMode.BottomEdgeAlignedLeft, ShouldConstrainToRootBounds = false };
        var style = new Style(typeof(FlyoutPresenter));
        style.Setters.Add(new Setter(Control.PaddingProperty, new Thickness(0)));
        style.Setters.Add(new Setter(FrameworkElement.MaxWidthProperty, FlyoutWidth + 2));
        flyout.FlyoutPresenterStyle = style;
        flyout.Opening += (_, _) =>
        {
            var content = build(flyout.Hide);
            content.Width = FlyoutWidth;
            content.Height = height;
            flyout.Content = content;
        };
        flyout.Closed += (_, _) => flyout.Content = null;
        return flyout;
    }

    /// The list of keys and buttons, with a button to record one by pressing it on the device.
    private FrameworkElement InputPicker(InputDevice device, Action<RemapInput, bool> choose)
    {
        var root = new Grid();
        var isRecording = false;

        void ShowList()
        {
            root.Children.Clear();
            root.RowDefinitions.Clear();
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            var content = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Center };
            content.Children.Add(new FontIcon { Glyph = RecordGlyph, FontSize = 14 });
            content.Children.Add(new TextBlock { Text = T("Record from %@", device.Name), TextTrimming = TextTrimming.CharacterEllipsis });
            var record = new Button
            {
                Content = content,
                HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Stretch,
                Margin = new Thickness(12, 12, 12, 0),
                IsEnabled = device.IsConnected,
            };
            AutomationProperties.SetName(record, T("Record from %@", device.Name));
            record.Click += (_, _) =>
            {
                isRecording = true;
                ShowRecording();
                remap.Record(device.Id, (input, isDeviceLess) =>
                {
                    isRecording = false;
                    choose(input, isDeviceLess);
                });
            };
            var list = new ChoiceList<RemapInput>(Choices.Inputs(device), input => choose(input, false));
            Grid.SetRow(list, 1);
            root.Children.Add(record);
            root.Children.Add(list);
        }

        // Nothing that takes keys while waiting, so the press reaches the recorder.
        void ShowRecording()
        {
            root.Children.Clear();
            root.RowDefinitions.Clear();
            var column = new StackPanel { Spacing = 16, VerticalAlignment = VerticalAlignment.Center, Padding = new Thickness(24) };
            column.Children.Add(new FontIcon { Glyph = RecordGlyph, FontSize = 40, Foreground = (Brush)Application.Current.Resources["SystemFillColorCriticalBrush"] });
            column.Children.Add(new TextBlock
            {
                Text = T("Press a key or button on %@", device.Name),
                Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"],
                TextWrapping = TextWrapping.Wrap,
                TextAlignment = TextAlignment.Center,
            });
            var cancel = new Button { Content = T("Cancel"), HorizontalAlignment = HorizontalAlignment.Center, IsTabStop = false };
            cancel.Click += (_, _) =>
            {
                isRecording = false;
                remap.CancelRecording();
                ShowList();
            };
            column.Children.Add(cancel);
            root.Children.Add(column);
        }

        root.Unloaded += (_, _) =>
        {
            if (isRecording) remap.CancelRecording();
            isRecording = false;
        };
        ShowList();
        return root;
    }
}
