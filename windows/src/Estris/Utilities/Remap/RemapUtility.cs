using Estris.Core;
using Estris.Ui;
using Microsoft.UI.Xaml;
using static Estris.Core.Loc;

namespace Estris.Utilities.Remap;

public sealed class RemapUtility(AppLog log) : IUtility
{
    public string Id => "remap";
    public string Title => "Remap";
    public string Glyph => "";
    public UtilityGroup Group => UtilityGroup.KeyboardAndMouse;
    public string[] Keywords => ["keyboard", "mouse", "keys", "buttons", "remap", "shortcut"];
    public Setting<bool> Enabled { get; } = SettingsStore.Shared.Get("remapEnabled", false);

    public void Start() { }
    public void Stop() { }

    public UIElement BuildPane()
    {
        var pane = new Pane();
        pane.UtilityHeader(this, T("Change what keys and mouse buttons do, per device."));
        return pane.Root;
    }
}
