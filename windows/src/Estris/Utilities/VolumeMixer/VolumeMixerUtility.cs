using Estris.Core;
using Estris.Tray;
using Estris.Ui;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using static Estris.Core.Loc;

namespace Estris.Utilities.VolumeMixer;

/// The volume and device of the PC's output and microphone, and a volume, mute and output device
/// for each app making sound, remembered per app. Windows does the work: unlike on the Mac, apps'
/// sound needs nothing in between, and only goes up to 100%.
public sealed class VolumeMixerUtility(AppLog log) : IUtility
{
    public string Id => "volumeMixer";
    public string Title => "Volume Mixer";
    public string Glyph => "";
    public UtilityGroup Group => UtilityGroup.Tools;
    public string[] Keywords => ["volume", "sound", "audio", "mixer", "microphone", "output"];
    public Setting<bool> Enabled { get; } = SettingsStore.Shared.Get("volumeMixerEnabled", false);

    private readonly VolumeMixerSettings settings = new();
    private MixerState state = MixerState.Empty;
    private event Action? StateChanged;
    /// How many sets of rows are on screen; only then does the engine watch who's playing.
    private int viewers;

    /// Null while off.
    internal AudioEngine? Engine { get; private set; }

    public void Start()
    {
        Enabled.Changed += () => Apply(restoresApps: true);
        settings.ExcludedApps.Changed += () => Engine?.ExcludedChanged();
        Apply(restoresApps: true);
    }

    public void Stop() => EndEngine(restoresApps: false);

    private void Apply(bool restoresApps)
    {
        if (!Enabled.Value)
        {
            EndEngine(restoresApps);
            return;
        }
        Engine ??= new AudioEngine(settings, message => log.Add(Title, message), Publish);
        Engine.IsWatched = viewers > 0;
    }

    private void EndEngine(bool restoresApps)
    {
        Engine?.Stop(restoresApps);
        Engine?.Dispose();
        Engine = null;
        Publish(MixerState.Empty);
    }

    /// Called on the audio thread.
    private void Publish(MixerState newState) => App.Ui.TryEnqueue(() =>
    {
        state = newState;
        StateChanged?.Invoke();
    });

    /// Keeps rows up to date while they're on screen, and has the engine watch for them.
    private void Follow(FrameworkElement host, MixerRows rows)
    {
        void Sync() => rows.Sync(state);
        host.Loaded += (_, _) =>
        {
            StateChanged += Sync;
            viewers++;
            if (Engine is not null) Engine.IsWatched = true;
            Sync();
        };
        host.Unloaded += (_, _) =>
        {
            StateChanged -= Sync;
            viewers--;
            if (Engine is not null) Engine.IsWatched = viewers > 0;
        };
        Sync();
    }

    public UIElement BuildPane()
    {
        var pane = new Pane();
        pane.UtilityHeader(this, T("Set the volume and device of your PC and of each app."));
        pane.Tabs(
            (T("Mixer"), BuildMixer),
            (T("Excluded Apps"), page => page.Add(new ExcludedAppsList(settings.ExcludedApps))));
        return pane.Root;
    }

    private void BuildMixer(Pane pane)
    {
        var rows = new MixerRows(this, showsDevices: true, showsPercent: true, row => OnCard(row), (row, app) => OnAppCard(row, app.Key));
        var live = new Pane();
        live.Root.Margin = new Thickness(0);
        live.Root.Spacing = Pane.RowSpacing;
        rows.SystemRows.Spacing = Pane.RowSpacing;
        rows.AppRows.Spacing = Pane.RowSpacing;
        live.Section(T("System"));
        live.Add(rows.SystemRows);
        live.Section(T("Apps"));
        live.Add(rows.NoApps);
        live.Add(rows.AppRows);
        pane.Add(live.Root);
        pane.ResetButton(Reset);

        void SyncVisibility() => live.Root.Visibility = Enabled.Value ? Visibility.Visible : Visibility.Collapsed;
        Enabled.Changed += SyncVisibility;
        SyncVisibility();
        Follow(live.Root, rows);
    }

    /// Every app back to playing as it is, also while off: the next time they play.
    private void Reset()
    {
        if (Engine is { } engine) engine.Reset();
        else settings.Apps.Value = settings.Apps.Value.Keys.ToDictionary(key => key, _ => new AppSound());
    }

    private static Border OnCard(FrameworkElement row) => new()
    {
        Child = row,
        Padding = new Thickness(16, 10, 12, 8),
        CornerRadius = new CornerRadius(4),
        Background = (Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"],
        BorderBrush = (Brush)Application.Current.Resources["CardStrokeColorDefaultBrush"],
        BorderThickness = new Thickness(1),
    };

    private Border OnAppCard(FrameworkElement row, string key)
    {
        var card = OnCard(row);
        Pane.WithReset(card, new AppSoundReset(key, () => state, () => Engine?.ResetApp(key)));
        return card;
    }

    /// Lets an app's card offer Reset to Default like any setting's row.
    private sealed class AppSoundReset(string key, Func<MixerState> state, Action reset) : ISetting
    {
        public bool IsDefault => state().Apps.FirstOrDefault(a => a.Key == key)?.IsDefault ?? true;
        public void Reset() => reset();
        public event Action? Changed { add { } remove { } }
    }

    public UIElement? BuildTrayGroup(Action closeMenu)
    {
        var tray = App.Shared.TraySettings;
        var showsSystem = tray.ShowsSystem.Value && (tray.ShowsOutput.Value || tray.ShowsMicrophone.Value);
        if (!showsSystem && !tray.ShowsApps.Value) return null;
        var rows = new MixerRows(this, tray.ShowsDevicePickers.Value, tray.ShowsPercentages.Value, row => row, (row, _) => row, tray.ShowsOutput.Value, tray.ShowsMicrophone.Value);
        var group = new StackPanel { Spacing = 8 };
        if (showsSystem)
        {
            group.Children.Add(GroupTitle(T("System Volume")));
            group.Children.Add(rows.SystemRows);
        }
        if (tray.ShowsApps.Value)
        {
            group.Children.Add(GroupTitle(T("Apps Volume")));
            group.Children.Add(rows.NoApps);
            group.Children.Add(rows.AppRows);
        }
        Follow(group, rows);
        return group;
    }

    private static TextBlock GroupTitle(string text) => new()
    {
        Text = text,
        Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"],
        Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
    };
}
