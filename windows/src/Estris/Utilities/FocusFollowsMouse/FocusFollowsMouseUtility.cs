using Estris.Core;
using Estris.Ui;
using Microsoft.UI.Xaml;
using static Estris.Core.Loc;

namespace Estris.Utilities.FocusFollowsMouse;

/// The Focus Follows Mouse utility: when the pointer rests on another app's window for the
/// chosen delay, with no mouse button or modifier key held, that window comes to the front and
/// gets the focus. Menus, the taskbar, the desktop, Estris's panels and excluded apps are left
/// alone.
public sealed class FocusFollowsMouseUtility : IUtility
{
    private readonly FocusFollowsMouseSettings settings = new();
    private readonly HoverFocus hover;

    public FocusFollowsMouseUtility(AppLog log) => hover = new HoverFocus(settings, log);

    public string Id => "focusFollowsMouse";
    public string Title => "Focus Follows Mouse";
    public string Glyph => "";
    public UtilityGroup Group => UtilityGroup.WindowsAndApps;
    public string[] Keywords => ["focus", "hover", "mouse", "pointer", "raise"];
    public Setting<bool> Enabled => settings.Enabled;

    public void Start()
    {
        settings.Enabled.Changed += Apply;
        Apply();
    }

    public void Stop() => hover.Stop();

    private void Apply()
    {
        if (settings.Enabled.Value) hover.Start();
        else hover.Stop();
    }

    public UIElement BuildPane()
    {
        var pane = new Pane();
        pane.UtilityHeader(this, T("The window under the pointer comes to the front and gets the focus."));
        pane.Tabs(
            (T("Settings"), BuildSettings),
            (T("Excluded Apps"), page => page.Add(new ExcludedAppsList(settings.ExcludedApps))));
        return pane.Root;
    }

    private void BuildSettings(Pane pane)
    {
        pane.Section(T("General"));
        pane.Choice(T("Focus after hovering for"), settings.Delay,
            FocusFollowsMouseSettings.Delays.Select(d => (d, FocusFollowsMouseSettings.DelayTitle(d))).ToArray());
        pane.Slider(T("Skip windows when moving faster than"), settings.PassThroughSpeed,
            FocusFollowsMouseSettings.MinimumPassThroughSpeed, FocusFollowsMouseSettings.MaximumPassThroughSpeed,
            FocusFollowsMouseSettings.PassThroughSpeedStep, v => T("%lld px/s", (long)v));

        pane.Section(T("Switching Apps"));
        pane.Toggle(T("Keep new windows and apps you switch to in front"), settings.KeepsNewAppsInFront,
            T("New windows and popups, and apps opened, clicked or picked with Alt+Tab or the taskbar, are often away from the pointer; this leaves time to get there."));
        var seconds = pane.Slider(T("Keep them in front for"), settings.NewAppSeconds,
            FocusFollowsMouseSettings.MinimumNewAppSeconds, FocusFollowsMouseSettings.MaximumNewAppSeconds, 1, v => T("%lld s", (long)v));
        void Sync() => seconds.IsEnabled = settings.KeepsNewAppsInFront.Value;
        Sync();
        settings.KeepsNewAppsInFront.Changed += Sync;
        pane.ResetButton(settings.Reset);
    }
}
