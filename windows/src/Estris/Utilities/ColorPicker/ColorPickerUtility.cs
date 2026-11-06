using Estris.Core;
using Estris.Ui;
using Microsoft.UI.Xaml;
using static Estris.Core.Loc;

namespace Estris.Utilities.ColorPicker;

public sealed class ColorPickerUtility(AppLog log) : IUtility
{
    public string Id => "colorPicker";
    public string Title => "Color Picker";
    public string Glyph => "";
    public UtilityGroup Group => UtilityGroup.Tools;
    public string[] Keywords => ["color", "colour", "eyedropper", "hex", "rgb", "hsl"];
    public Setting<bool> Enabled { get; } = SettingsStore.Shared.Get("colorPickerEnabled", false);

    public void Start() { }
    public void Stop() { }

    public UIElement BuildPane()
    {
        var pane = new Pane();
        pane.UtilityHeader(this, T("Pick a color anywhere on screen and copy it."));
        return pane.Root;
    }
}
