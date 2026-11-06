using Estris.Core;
using Estris.Ui;
using Microsoft.UI.Xaml;
using static Estris.Core.Loc;

namespace Estris.Utilities.AutoQuit;

public sealed class AutoQuitUtility(AppLog log) : IUtility
{
    public string Id => "autoQuit";
    public string Title => "Auto Quit";
    public string Glyph => "";
    public UtilityGroup Group => UtilityGroup.WindowsAndApps;
    public string[] Keywords => ["quit", "close", "window", "exit", "background"];
    public Setting<bool> Enabled { get; } = SettingsStore.Shared.Get("autoQuitEnabled", false);

    public void Start() { }
    public void Stop() { }

    public UIElement BuildPane()
    {
        var pane = new Pane();
        pane.UtilityHeader(this, T("Quit an app when you close its last window."));
        return pane.Root;
    }
}
