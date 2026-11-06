using Estris.Core;
using Microsoft.UI.Xaml;

namespace Estris.Utilities;

public enum UtilityGroup { Tools, WindowsAndApps, KeyboardAndMouse }

/// One utility. To add one: a folder in Utilities/ with a class deriving from this, added to
/// UtilityList, with its pane in BuildPane and, if it shows in the tray menu, BuildTrayGroup.
public interface IUtility
{
    /// Stable id, for Settings navigation.
    string Id { get; }
    /// The English name, which is also its translation key.
    string Title { get; }
    /// A Segoe Fluent Icons glyph for the sidebar.
    string Glyph { get; }
    UtilityGroup Group { get; }
    /// Extra words the Settings search finds it by.
    string[] Keywords { get; }
    Setting<bool> Enabled { get; }
    void Start();
    void Stop();
    UIElement BuildPane();
    /// What the tray menu shows of it, or null. closeMenu closes the menu.
    UIElement? BuildTrayGroup(Action closeMenu) => null;
}

public static class UtilityList
{
    /// In the order the sidebar lists them within each group.
    public static IReadOnlyList<IUtility> Create(AppLog log) =>
    [
        new ClipboardManager.ClipboardManagerUtility(log),
        new ColorPicker.ColorPickerUtility(log),
        new RoundedCorners.RoundedCornersUtility(log),
        new WindowSnapping.WindowSnappingUtility(log),
        new Remap.RemapUtility(log),
    ];
}
