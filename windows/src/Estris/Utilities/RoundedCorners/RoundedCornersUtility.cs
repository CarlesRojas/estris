using Estris.Core;
using Estris.Ui;
using Microsoft.UI.Xaml;
using static Estris.Core.Loc;

namespace Estris.Utilities.RoundedCorners;

public sealed class RoundedCornersUtility(AppLog log) : IUtility
{
    public string Id => "roundedCorners";
    public string Title => "Rounded Corners";
    public string Glyph => "";
    public UtilityGroup Group => UtilityGroup.Tools;
    public string[] Keywords => ["corners", "round", "radius", "screen", "display", "black"];
    public Setting<bool> Enabled { get; } = SettingsStore.Shared.Get("roundedCornersEnabled", false);

    public void Start() { }
    public void Stop() { }

    public UIElement BuildPane()
    {
        var pane = new Pane();
        pane.UtilityHeader(this, T("Paint the corners of every screen black, as if the screens were rounded."));
        return pane.Root;
    }
}
