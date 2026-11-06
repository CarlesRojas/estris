using Estris.Core;
using Estris.Ui;
using Microsoft.UI.Xaml;
using static Estris.Core.Loc;

namespace Estris.Utilities.KeepAwake;

public sealed class KeepAwakeUtility(AppLog log) : IUtility
{
    public string Id => "keepAwake";
    public string Title => "Keep Awake";
    public string Glyph => "";
    public UtilityGroup Group => UtilityGroup.Tools;
    public string[] Keywords => ["awake", "sleep", "caffeinate", "display", "battery", "power", "timer"];
    public Setting<bool> Enabled { get; } = SettingsStore.Shared.Get("keepAwakeEnabled", false);

    public void Start() { }
    public void Stop() { }

    public UIElement BuildPane()
    {
        var pane = new Pane();
        pane.UtilityHeader(this, T("Keep your PC awake until it has been idle for a chosen time."));
        return pane.Root;
    }
}
