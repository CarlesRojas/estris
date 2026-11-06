using Estris.Core;
using Estris.Ui;
using Microsoft.UI.Xaml;
using static Estris.Core.Loc;

namespace Estris.Utilities.ClipboardManager;

public sealed class ClipboardManagerUtility(AppLog log) : IUtility
{
    public string Id => "clipboard";
    public string Title => "Clipboard";
    public string Glyph => "";
    public UtilityGroup Group => UtilityGroup.Tools;
    public string[] Keywords => ["clipboard", "history", "paste", "copy"];
    public Setting<bool> Enabled { get; } = SettingsStore.Shared.Get("clipboardEnabled", false);

    public void Start() { }
    public void Stop() { }

    public UIElement BuildPane()
    {
        var pane = new Pane();
        pane.UtilityHeader(this, T("A history of what you copy, to pick from when pasting."));
        return pane.Root;
    }
}
