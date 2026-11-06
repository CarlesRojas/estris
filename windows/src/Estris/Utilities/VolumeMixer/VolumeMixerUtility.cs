using Estris.Core;
using Estris.Ui;
using Microsoft.UI.Xaml;
using static Estris.Core.Loc;

namespace Estris.Utilities.VolumeMixer;

public sealed class VolumeMixerUtility(AppLog log) : IUtility
{
    public string Id => "volumeMixer";
    public string Title => "Volume Mixer";
    public string Glyph => "";
    public UtilityGroup Group => UtilityGroup.Tools;
    public string[] Keywords => ["volume", "sound", "audio", "mixer", "microphone", "output"];
    public Setting<bool> Enabled { get; } = SettingsStore.Shared.Get("volumeMixerEnabled", false);

    public void Start() { }
    public void Stop() { }

    public UIElement BuildPane()
    {
        var pane = new Pane();
        pane.UtilityHeader(this, T("Set the volume and device of your PC and of each app."));
        return pane.Root;
    }
}
