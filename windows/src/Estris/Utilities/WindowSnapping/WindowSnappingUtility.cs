using Estris.Core;
using Estris.Ui;
using Microsoft.UI.Xaml;
using static Estris.Core.Loc;

namespace Estris.Utilities.WindowSnapping;

public sealed class WindowSnappingUtility(AppLog log) : IUtility
{
    public string Id => "windowSnapping";
    public string Title => "Window Snapping";
    public string Glyph => "";
    public UtilityGroup Group => UtilityGroup.WindowsAndApps;
    public string[] Keywords => ["snap", "window", "tile", "halves", "thirds", "arrange", "layout"];
    public Setting<bool> Enabled { get; } = SettingsStore.Shared.Get("windowSnappingEnabled", false);

    public void Start() { }
    public void Stop() { }

    public UIElement BuildPane()
    {
        var pane = new Pane();
        pane.UtilityHeader(this, T("Move windows to halves, corners or thirds, or arrange them all."));
        return pane.Root;
    }
}
