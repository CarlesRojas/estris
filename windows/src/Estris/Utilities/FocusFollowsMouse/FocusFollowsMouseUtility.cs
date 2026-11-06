using Estris.Core;
using Estris.Ui;
using Microsoft.UI.Xaml;
using static Estris.Core.Loc;

namespace Estris.Utilities.FocusFollowsMouse;

public sealed class FocusFollowsMouseUtility(AppLog log) : IUtility
{
    public string Id => "focusFollowsMouse";
    public string Title => "Focus Follows Mouse";
    public string Glyph => "";
    public UtilityGroup Group => UtilityGroup.WindowsAndApps;
    public string[] Keywords => ["focus", "hover", "mouse", "pointer", "raise"];
    public Setting<bool> Enabled { get; } = SettingsStore.Shared.Get("focusFollowsMouseEnabled", false);

    public void Start() { }
    public void Stop() { }

    public UIElement BuildPane()
    {
        var pane = new Pane();
        pane.UtilityHeader(this, T("The window under the pointer comes to the front, without clicking."));
        return pane.Root;
    }
}
