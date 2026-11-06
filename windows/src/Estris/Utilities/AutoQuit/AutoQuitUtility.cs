using Estris.Core;
using Estris.Ui;
using Microsoft.UI.Xaml;
using static Estris.Core.Loc;

namespace Estris.Utilities.AutoQuit;

/// The Auto Quit utility: quits an app when its last window closes.
public sealed class AutoQuitUtility : IUtility
{
    private readonly AutoQuitSettings settings = new();
    private readonly WindowWatcher watcher;

    public AutoQuitUtility(AppLog log) => watcher = new WindowWatcher(settings, log);

    public string Id => "autoQuit";
    public string Title => "Auto Quit";
    public string Glyph => "";
    public UtilityGroup Group => UtilityGroup.WindowsAndApps;
    public string[] Keywords => ["quit", "close", "window", "exit", "background"];
    public Setting<bool> Enabled => settings.Enabled;

    public void Start()
    {
        settings.Enabled.Changed += Apply;
        Apply();
    }

    public void Stop() => watcher.Stop();

    private void Apply()
    {
        if (settings.Enabled.Value) watcher.Start();
        else watcher.Stop();
    }

    public UIElement BuildPane()
    {
        var pane = new Pane();
        pane.UtilityHeader(this, T("Quits an app when you close its last window."));
        pane.Tabs(
            (T("Settings"), BuildSettings),
            (T("Excluded Apps"), page => page.Add(new ExcludedAppsList(settings.ExcludedApps, T("File Explorer and Windows's own programs always keep running.")))));
        return pane.Root;
    }

    private void BuildSettings(Pane pane)
    {
        pane.Section(T("General"));
        pane.Choice(T("Quit"), settings.Delay, AutoQuitSettings.Delays.Select(d => (d.Id, AutoQuitSettings.DelayTitle(d.Id))).ToArray());
        pane.ResetButton(settings.Reset);
    }
}
