using Estris.Core;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using static Estris.Core.Loc;

namespace Estris.Utilities.VolumeMixer;

/// Picks a device: its name and up-down chevrons with no background until the pointer is over it,
/// hugging the right edge whatever the name's length. Choices come when it opens.
internal sealed class DeviceMenu : Button
{
    private const double MaxNameWidth = 200;
    private readonly TextBlock name = new() { TextTrimming = TextTrimming.CharacterEllipsis, TextWrapping = TextWrapping.NoWrap, MaxWidth = MaxNameWidth, FontSize = 12, VerticalAlignment = VerticalAlignment.Center };
    private IReadOnlyList<(string? Id, string Name)> options = [];
    private string? selection;
    private readonly Action<string?> select;

    public DeviceMenu(Action<string?> select)
    {
        this.select = select;
        var chevrons = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Spacing = -3 };
        chevrons.Children.Add(new FontIcon { Glyph = "", FontSize = 8 });
        chevrons.Children.Add(new FontIcon { Glyph = "", FontSize = 8 });
        var content = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
        content.Children.Add(name);
        content.Children.Add(chevrons);
        Content = content;
        Padding = new Thickness(6, 3, 6, 3);
        Background = new SolidColorBrush(Colors.Transparent);
        BorderBrush = new SolidColorBrush(Colors.Transparent);
        HorizontalAlignment = HorizontalAlignment.Right;
        Click += (_, _) => Open();
    }

    public void Sync(IReadOnlyList<(string? Id, string Name)> options, string? selection)
    {
        this.options = options;
        this.selection = selection;
        name.Text = options.FirstOrDefault(o => o.Id == selection).Name ?? "";
    }

    private void Open()
    {
        // A menu that may leave the window would take the focus, which closes the tray menu.
        var menu = new MenuFlyout { ShouldConstrainToRootBounds = true };
        foreach (var (id, title) in options)
        {
            var item = new ToggleMenuFlyoutItem { Text = title, IsChecked = id == selection };
            item.Click += (_, _) => select(id);
            menu.Items.Add(item);
        }
        menu.ShowAt(this);
    }
}

/// One sound: an icon and title at the top left, the device at the top right, then mute, the
/// volume across the width and its percentage. The same in the pane and the tray menu.
internal sealed class SoundRow : StackPanel
{
    /// While moving a slider, the notices of earlier moves mustn't pull it back.
    private static readonly TimeSpan UserChange = TimeSpan.FromMilliseconds(400);
    private const double IconSize = 28, PercentWidth = 40;

    private readonly TextBlock title = new() { VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis };
    private readonly Grid header = new() { ColumnSpacing = 8 };
    private readonly Button mute = new() { Width = 32, Height = 32, Padding = new Thickness(0), Background = new SolidColorBrush(Colors.Transparent), BorderBrush = new SolidColorBrush(Colors.Transparent) };
    private readonly FontIcon muteIcon = new() { FontSize = 16 };
    private readonly Slider slider = new() { Minimum = 0, Maximum = 100, StepFrequency = 1, SmallChange = 1, IsThumbToolTipEnabled = false, VerticalAlignment = VerticalAlignment.Center };
    private readonly TextBlock percent = new() { VerticalAlignment = VerticalAlignment.Center, TextAlignment = TextAlignment.Right, Width = PercentWidth, Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"] };
    private readonly string glyph, mutedGlyph;
    private DateTime lastUserChange;
    private bool isSyncing;

    public DeviceMenu Device { get; }

    public SoundRow(string glyph, string mutedGlyph, FrameworkElement icon, Action<double> setVolume, Action toggleMute, Action<string?> selectDevice)
    {
        this.glyph = glyph;
        this.mutedGlyph = mutedGlyph;
        Spacing = 2;
        Device = new DeviceMenu(selectDevice);

        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(IconSize) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.Children.Add(icon);
        Grid.SetColumn(title, 1);
        header.Children.Add(title);
        Grid.SetColumn(Device, 2);
        header.Children.Add(Device);
        Children.Add(header);

        mute.Content = muteIcon;
        mute.Click += (_, _) => toggleMute();
        slider.ValueChanged += (_, e) =>
        {
            percent.Text = $"{(int)e.NewValue}%";
            if (isSyncing) return;
            lastUserChange = DateTime.UtcNow;
            setVolume(e.NewValue / 100);
        };
        var controls = new Grid { ColumnSpacing = 8 };
        controls.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        controls.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        controls.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        controls.Children.Add(mute);
        Grid.SetColumn(slider, 1);
        controls.Children.Add(slider);
        Grid.SetColumn(percent, 2);
        controls.Children.Add(percent);
        Children.Add(controls);
    }

    public void Sync(string name, double? volume, bool? isMuted, bool showsDevice, bool showsPercent)
    {
        title.Text = name;
        Device.Visibility = showsDevice ? Visibility.Visible : Visibility.Collapsed;
        percent.Visibility = showsPercent ? Visibility.Visible : Visibility.Collapsed;
        muteIcon.Glyph = isMuted == true ? mutedGlyph : glyph;
        mute.IsEnabled = isMuted is not null;
        var label = isMuted == true ? T("Unmute") : T("Mute");
        ToolTipService.SetToolTip(mute, label);
        AutomationProperties.SetName(mute, label);
        slider.IsEnabled = volume is not null && isMuted != true;
        if (DateTime.UtcNow - lastUserChange < UserChange) return;
        isSyncing = true;
        slider.Value = Math.Round((volume ?? 0) * 100);
        isSyncing = false;
        percent.Text = volume is null ? "" : $"{(int)slider.Value}%";
    }
}

/// Live rows of the mixer, shown in the pane and the tray menu alike. Rows are kept and updated
/// rather than made again, so a slider being dragged stays under the pointer.
internal sealed class MixerRows
{
    private const double IconSize = 28, TileSize = 24, TileGlyphSize = 14;
    private const string OutputGlyph = "", MicrophoneGlyph = "", VolumeGlyph = "", MutedGlyph = "", MicrophoneMutedGlyph = "";
    private static readonly Dictionary<string, BitmapImage?> Icons = [];

    private readonly VolumeMixerUtility mixer;
    private readonly bool showsDevices, showsPercent;
    private readonly SoundRow outputRow, inputRow;
    private readonly Dictionary<string, (SoundRow Row, FrameworkElement Wrapper)> appRows = [];
    private readonly Func<FrameworkElement, AppState, FrameworkElement> wrapApp;

    public StackPanel SystemRows { get; } = new() { Spacing = 8 };
    public StackPanel AppRows { get; } = new() { Spacing = 8 };
    public TextBlock NoApps { get; } = new()
    {
        Text = T("No app is playing sound."),
        Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
    };

    /// wrapApp puts an app's row on what surrounds it, in the place it shows. Output and microphone
    /// come in SystemRows in that order, wrapped the same way by wrapSystem.
    public MixerRows(VolumeMixerUtility mixer, bool showsDevices, bool showsPercent, Func<FrameworkElement, FrameworkElement> wrapSystem, Func<FrameworkElement, AppState, FrameworkElement> wrapApp, bool showsOutput = true, bool showsInput = true)
    {
        this.mixer = mixer;
        this.showsDevices = showsDevices;
        this.showsPercent = showsPercent;
        this.wrapApp = wrapApp;
        outputRow = new SoundRow(VolumeGlyph, MutedGlyph, Tile(OutputGlyph, Windows.UI.Color.FromArgb(255, 0, 120, 212)), v => mixer.Engine?.SetVolume(false, v), () => mixer.Engine?.ToggleMute(false), id => { if (id is not null) mixer.Engine?.SetDefaultDevice(id); });
        inputRow = new SoundRow(MicrophoneGlyph, MicrophoneMutedGlyph, Tile(MicrophoneGlyph, Windows.UI.Color.FromArgb(255, 247, 99, 12)), v => mixer.Engine?.SetVolume(true, v), () => mixer.Engine?.ToggleMute(true), id => { if (id is not null) mixer.Engine?.SetDefaultDevice(id); });
        if (showsOutput) SystemRows.Children.Add(wrapSystem(outputRow));
        if (showsInput) SystemRows.Children.Add(wrapSystem(inputRow));
    }

    public void Sync(MixerState state)
    {
        SyncSystem(outputRow, T("Output"), state.Output);
        SyncSystem(inputRow, T("Microphone"), state.Input);
        var keys = state.Apps.Select(a => a.Key).ToHashSet();
        foreach (var (key, entry) in appRows.Where(r => !keys.Contains(r.Key)).ToList())
        {
            AppRows.Children.Remove(entry.Wrapper);
            appRows.Remove(key);
        }
        var index = 0;
        foreach (var app in state.Apps)
        {
            if (!appRows.TryGetValue(app.Key, out var entry))
            {
                var key = app.Key;
                var row = new SoundRow(VolumeGlyph, MutedGlyph, AppIcon(app.IconPath), v => mixer.Engine?.SetAppVolume(key, v), () => mixer.Engine?.ToggleAppMute(key), id => mixer.Engine?.SetAppOutput(key, id));
                entry = appRows[key] = (row, wrapApp(row, app));
                AppRows.Children.Insert(index, entry.Wrapper);
            }
            else if (AppRows.Children.IndexOf(entry.Wrapper) != index)
            {
                AppRows.Children.Remove(entry.Wrapper);
                AppRows.Children.Insert(index, entry.Wrapper);
            }
            index++;
            entry.Row.Sync(app.Name, app.Volume, app.IsMuted, showsDevices && app.CanChooseDevice, showsPercent);
            entry.Row.Device.Sync(OutputOptions(app, state.Output.Devices), app.OutputId);
        }
        NoApps.Visibility = state.Apps.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void SyncSystem(SoundRow row, string title, EndpointState endpoint)
    {
        row.Sync(title, endpoint.Volume, endpoint.IsMuted, showsDevices, showsPercent);
        row.Device.Sync(endpoint.Devices.Select(d => ((string?)d.Id, d.Name)).ToList(), endpoint.CurrentId);
    }

    /// The system output, each device, and the chosen one while it isn't connected.
    private static List<(string? Id, string Name)> OutputOptions(AppState app, IReadOnlyList<AudioDevice> devices)
    {
        var options = new List<(string?, string)> { (null, T("Same as System")) };
        options.AddRange(devices.Select(d => ((string?)d.Id, d.Name)));
        if (app.OutputId is { } id && devices.All(d => d.Id != id)) options.Add((id, T("%@ (not connected)", app.OutputName ?? id)));
        return options;
    }

    /// Where an app row has the app's icon: a coloured tile, so it doesn't read as the mute button
    /// below it.
    private static Border Tile(string glyph, Windows.UI.Color color) => new()
    {
        Width = TileSize,
        Height = TileSize,
        CornerRadius = new CornerRadius(4),
        Background = new SolidColorBrush(color),
        HorizontalAlignment = HorizontalAlignment.Left,
        Child = new FontIcon { Glyph = glyph, FontSize = TileGlyphSize, Foreground = new SolidColorBrush(Colors.White) },
    };

    private static Image AppIcon(string? path) => new() { Width = IconSize, Height = IconSize, Source = Icon(path) };

    private static BitmapImage? Icon(string? path)
    {
        if (path is null) return null;
        if (Icons.TryGetValue(path, out var known)) return known;
        BitmapImage? image = null;
        using (var bitmap = InstalledApps.Icon(path))
        {
            if (bitmap is not null)
            {
                using var stream = new MemoryStream();
                bitmap.Save(stream, System.Drawing.Imaging.ImageFormat.Png);
                stream.Position = 0;
                image = new BitmapImage();
                image.SetSource(stream.AsRandomAccessStream());
            }
        }
        return Icons[path] = image;
    }
}
