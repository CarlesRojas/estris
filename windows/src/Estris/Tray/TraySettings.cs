using Estris.Core;

namespace Estris.Tray;

/// The tray icon, and what the tray menu shows of each utility.
public sealed class TraySettings
{
    private static readonly SettingsStore Store = SettingsStore.Shared;

    public const int MaxClipboardEntries = 10;

    public Setting<string> Icon { get; } = Store.Get("trayIcon", TrayIcons.DefaultId);
    public Setting<bool> UsesCustomColor { get; } = Store.Get("trayUsesCustomColor", false);
    public Setting<string> CustomColor { get; } = Store.Get("trayCustomColor", "#FFFFFF");

    public Setting<bool> ShowsClipboardHistory { get; } = Store.Get("trayShowsClipboardHistory", false);
    public Setting<double> ClipboardEntries { get; } = Store.Get("trayClipboardEntries", 5.0);
    public Setting<bool> ShowsClearHistory { get; } = Store.Get("trayShowsClearHistory", true);

    public Setting<bool> ShowsColorPicker { get; } = Store.Get("trayShowsColorPicker", true);
    public Setting<bool> ShowsRecentColors { get; } = Store.Get("trayShowsRecentColors", false);

    public void Reset()
    {
        foreach (var setting in new ISetting[]
        {
            Icon, UsesCustomColor, CustomColor, ShowsClipboardHistory, ClipboardEntries, ShowsClearHistory, ShowsColorPicker,
            ShowsRecentColors,
        }) setting.Reset();
    }
}
