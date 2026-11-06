using Estris.Core;
using Estris.Ui;
using Estris.Utilities.ClipboardManager.Overlay;
using Estris.Utilities.ClipboardManager.Settings;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using static Estris.Core.Loc;

namespace Estris.Utilities.ClipboardManager;

/// The clipboard utility: records what's copied and shows the overlay on its shortcuts.
public sealed class ClipboardManagerUtility : IUtility
{
    private static readonly TimeSpan ExpiryCheck = TimeSpan.FromMinutes(1);

    private readonly AppLog log;
    private readonly ClipboardSettings settings = new();
    private readonly AppearanceSettings appearance = new();
    private readonly ClipboardHistory history;
    private readonly ClipboardMonitor monitor;
    private readonly ForegroundTracker foreground = new();
    private readonly List<object> shortcutOwners = [];
    private OverlayController? overlay;
    private DispatcherQueueTimer? expiryTimer;
    private bool hasRecorded;
    private bool isActive;

    public ClipboardManagerUtility(AppLog log)
    {
        this.log = log;
        history = new ClipboardHistory(log) { Limit = settings.MaxEntries.Value };
        monitor = new ClipboardMonitor(history, settings, log);
    }

    public string Id => "clipboard";
    public string Title => "Clipboard";
    public string Glyph => "";
    public UtilityGroup Group => UtilityGroup.Tools;
    public string[] Keywords => ["clipboard", "history", "paste", "copy"];
    public Setting<bool> Enabled { get; } = SettingsStore.Shared.Get("clipboardEnabled", false);

    public void Start()
    {
        overlay = new OverlayController(history, monitor, settings, appearance, log);
        settings.MaxEntries.Changed += () => history.Limit = settings.MaxEntries.Value;
        settings.Expiry.Changed += RemoveExpired;
        settings.MainShortcut.Changed += OnShortcutsChanged;
        foreach (var slot in settings.AlternativeShortcuts) slot.Changed += OnShortcutsChanged;
        Enabled.Changed += ApplyEnabled;
        ApplyEnabled();
        if (Environment.GetEnvironmentVariable("ESTRIS_DBG") != null) Hotkeys.Register(this, new Shortcut(true, false, true, false, 0x78), () => { var w = new FrostWindow(true); var ok = new StackPanel { Padding = new Thickness(12), Width = 360 }; w.Content = ok; ok.Children.Add(BuildTrayGroup(() => w.Hide())!); w.ShowAt(1000, 300, 540, 500); });
    }

    public void Stop()
    {
        Enabled.Changed -= ApplyEnabled;
        Deactivate();
        history.Save();
    }

    /// Turning the utility off stops recording, removes its shortcuts and closes the overlay.
    private void ApplyEnabled()
    {
        if (Enabled.Value) Activate();
        else Deactivate();
    }

    private void Activate()
    {
        if (isActive) return;
        isActive = true;
        monitor.Start(recordingCurrent: !hasRecorded);
        hasRecorded = true;
        foreground.Start();
        RegisterShortcuts();
        overlay?.Start();
        RemoveExpired();
        expiryTimer = App.Ui.CreateTimer();
        expiryTimer.Interval = ExpiryCheck;
        expiryTimer.Tick += (_, _) => RemoveExpired();
        expiryTimer.Start();
    }

    private void Deactivate()
    {
        if (!isActive) return;
        isActive = false;
        expiryTimer?.Stop();
        expiryTimer = null;
        monitor.Stop();
        foreground.Stop();
        UnregisterShortcuts();
        overlay?.Stop();
    }

    private void OnShortcutsChanged()
    {
        if (!isActive) return;
        UnregisterShortcuts();
        RegisterShortcuts();
    }

    private void RegisterShortcuts()
    {
        foreach (var shortcut in settings.Shortcuts.Distinct())
        {
            var owner = new object();
            shortcutOwners.Add(owner);
            Hotkeys.Register(owner, shortcut, () => overlay?.Cycle(shortcut));
        }
    }

    private void UnregisterShortcuts()
    {
        shortcutOwners.ForEach(Hotkeys.Unregister);
        shortcutOwners.Clear();
    }

    private void RemoveExpired()
    {
        if (ClipboardSettings.Interval(settings.Expiry.Value) is { } interval)
            history.RemoveEntries(DateTime.Now - interval);
    }

    public UIElement BuildPane() => ClipboardPane.Build(this, settings, appearance, history);

    /// The latest entries and Clear History, as chosen in Settings > System Tray.
    public UIElement? BuildTrayGroup(Action closeMenu)
    {
        var tray = App.Shared.TraySettings;
        var entries = tray.ShowsClipboardHistory.Value ? history.Items.Take((int)tray.ClipboardEntries.Value).ToList() : [];
        if (entries.Count == 0 && !tray.ShowsClearHistory.Value) return null;

        var group = new StackPanel { Spacing = 2 };
        foreach (var item in entries) group.Children.Add(TrayEntry(item, closeMenu));
        if (tray.ShowsClearHistory.Value)
        {
            var clear = new Button { Content = T("Clear History"), HorizontalAlignment = HorizontalAlignment.Stretch, IsEnabled = history.Items.Count > 0, Margin = new Thickness(0, entries.Count > 0 ? 6 : 0, 0, 0) };
            clear.Click += (_, _) =>
            {
                history.Clear();
                closeMenu();
            };
            group.Children.Add(clear);
        }
        return group;
    }

    private Button TrayEntry(ClipItem item, Action closeMenu)
    {
        var row = new Grid { ColumnSpacing = 8 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        const double iconSize = 20;
        FrameworkElement icon = AppIcons.Bitmap(item.SourcePath) is { } bitmap
            ? new Image { Source = bitmap, Width = iconSize, Height = iconSize }
            : new FontIcon { Glyph = ClipText.AppGlyph, FontSize = iconSize * 0.75 };
        var text = item.Kind == ClipKind.Image ? ClipText.ImageLabel(item) : ClipText.SingleLine(ClipText.Shown(item));
        var label = new TextBlock { Text = text, TextTrimming = TextTrimming.CharacterEllipsis, TextWrapping = TextWrapping.NoWrap, VerticalAlignment = VerticalAlignment.Center };
        Grid.SetColumn(label, 1);
        row.Children.Add(icon);
        row.Children.Add(label);

        var button = new Button
        {
            Content = row,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Transparent),
            BorderThickness = new Thickness(0),
        };
        ToolTipService.SetToolTip(button, ClipText.SourceName(item));
        button.Click += (_, _) =>
        {
            foreground.Restore();
            closeMenu();
            overlay?.Paste(item);
        };
        return button;
    }
}
