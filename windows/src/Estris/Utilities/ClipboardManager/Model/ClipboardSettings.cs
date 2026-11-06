using Estris.Core;
using Estris.Utilities.ClipboardManager.Overlay;
using static Estris.Core.Loc;

namespace Estris.Utilities.ClipboardManager;

/// How long entries stay in the history.
public enum HistoryExpiry { Never, Hour, Day, Week, Month }

/// What the utility keeps, how the overlay is laid out and its shortcuts.
public sealed class ClipboardSettings
{
    private static readonly SettingsStore Store = SettingsStore.Shared;

    public const int MinItems = 5, MaxItems = 100, ItemsStep = 5;
    public const double MinCardWidth = 360, MaxCardWidth = 900, MinCardHeight = 120, MaxCardHeight = 420;

    /// A key no shortcut uses: a free slot among the alternatives.
    public static readonly Shortcut NoShortcut = new(false, false, false, false, 0);
    private const int VkV = 0x56, VkB = 0x42;
    public static readonly Shortcut DefaultShortcut = new(Ctrl: true, Shift: true, Alt: false, Win: false, VkV);
    /// Offered in turn by Add Alternative Shortcut; the user then records over it.
    private static readonly Shortcut[] AlternativeCandidates =
    [
        new(Ctrl: true, Shift: false, Alt: true, Win: false, VkV),
        new(Ctrl: true, Shift: true, Alt: true, Win: false, VkV),
        new(Ctrl: false, Shift: true, Alt: true, Win: false, VkV),
        new(Ctrl: true, Shift: true, Alt: false, Win: false, VkB),
    ];

    public Setting<int> MaxEntries { get; } = Store.Get("clipboardMaxItems", 50);
    public Setting<HistoryExpiry> Expiry { get; } = Store.Get("clipboardExpiry", HistoryExpiry.Never);
    /// Skip copies marked by password managers and the like as not to be kept.
    public Setting<bool> IgnorePasswords { get; } = Store.Get("clipboardIgnorePasswords", true);
    /// Record copied images. Text and files are always recorded.
    public Setting<bool> RecordImages { get; } = Store.Get("clipboardRecordImages", true);
    public Setting<bool> RemoveDuplicates { get; } = Store.Get("clipboardRemoveDuplicates", true);
    /// Pasting an entry from the overlay makes it the most recent one. When off, the history
    /// keeps copy order and Ctrl+V goes back to the last copied text after the paste.
    public Setting<bool> MoveToTopOnPaste { get; } = Store.Get("clipboardMoveToTopOnPaste", true);
    /// Program names ("chrome.exe") whose copies are not recorded.
    public Setting<List<string>> ExcludedApps { get; } = Store.Get<List<string>>("clipboardExcludedApps", []);

    public Setting<double> CardWidth { get; } = Store.Get("clipboardCardWidth", 560.0);
    public Setting<double> CardHeight { get; } = Store.Get("clipboardCardHeight", 256.0);
    public Setting<bool> ShowCopyDate { get; } = Store.Get("clipboardShowCopyDate", true);
    public Setting<bool> ShowDeleteButton { get; } = Store.Get("clipboardShowDeleteButton", true);

    /// Opens the overlay.
    public Setting<Shortcut> MainShortcut { get; } = Store.Get("clipboardShortcut", DefaultShortcut);
    /// Other shortcuts that open it; a slot set to NoShortcut is free.
    public Setting<Shortcut>[] AlternativeShortcuts { get; } = Enumerable.Range(0, AlternativeCandidates.Length)
        .Select(slot => Store.Get($"clipboardAlternativeShortcut{slot}", NoShortcut)).ToArray();

    public static IReadOnlyList<(HistoryExpiry Value, string Label)> ExpiryChoices =>
    [
        (HistoryExpiry.Never, T("Never")),
        (HistoryExpiry.Hour, T("After 1 hour")),
        (HistoryExpiry.Day, T("After 1 day")),
        (HistoryExpiry.Week, T("After 1 week")),
        (HistoryExpiry.Month, T("After 30 days")),
    ];

    /// How old entries may get, or null to keep them.
    public static TimeSpan? Interval(HistoryExpiry expiry) => expiry switch
    {
        HistoryExpiry.Hour => TimeSpan.FromHours(1),
        HistoryExpiry.Day => TimeSpan.FromDays(1),
        HistoryExpiry.Week => TimeSpan.FromDays(7),
        HistoryExpiry.Month => TimeSpan.FromDays(30),
        _ => null,
    };

    public IEnumerable<Shortcut> Shortcuts =>
        AlternativeShortcuts.Select(s => s.Value).Where(s => s != NoShortcut).Prepend(MainShortcut.Value);

    /// Takes the first free slot, starting from a shortcut not in use. False if all are taken.
    public bool AddAlternativeShortcut()
    {
        var slot = Array.Find(AlternativeShortcuts, s => s.Value == NoShortcut);
        var unused = AlternativeCandidates.FirstOrDefault(c => !Shortcuts.Contains(c));
        if (slot is null || unused is null) return false;
        slot.Value = unused;
        return true;
    }

    /// Back to the default settings, appearance and shortcut; the on/off switch, excluded apps
    /// and history stay as they are.
    public void Reset()
    {
        foreach (var setting in new ISetting[] { MaxEntries, Expiry, IgnorePasswords, RecordImages, RemoveDuplicates, MoveToTopOnPaste, MainShortcut })
            setting.Reset();
        foreach (var setting in AlternativeShortcuts) setting.Reset();
        ResetLayout();
    }

    /// The Appearance section's own settings; the look of the surfaces is AppearanceSettings'.
    public void ResetLayout()
    {
        foreach (var setting in new ISetting[] { CardWidth, CardHeight, ShowCopyDate, ShowDeleteButton }) setting.Reset();
    }
}

/// How the overlay's surfaces look.
public sealed class AppearanceSettings
{
    private static readonly SettingsStore Store = SettingsStore.Shared;

    public const double MaxTintOpacity = 0.6, MaxSelectedTintOpacity = 0.6, MaxShadowRadius = 30, MaxBackdropDim = 0.7;

    public Setting<string> Tint { get; } = Store.Get("clipboardTint", "#808080");
    public Setting<double> TintOpacity { get; } = Store.Get("clipboardTintOpacity", 0.2);
    public Setting<double> SelectedTintOpacity { get; } = Store.Get("clipboardSelectedTintOpacity", 0.3);
    public Setting<double> ShadowRadius { get; } = Store.Get("clipboardShadowRadius", 16.0);
    public Setting<double> BackdropDim { get; } = Store.Get("clipboardBackdropDim", 0.5);

    public IEnumerable<ISetting> All => [Tint, TintOpacity, SelectedTintOpacity, ShadowRadius, BackdropDim];

    public void Reset()
    {
        foreach (var setting in All) setting.Reset();
    }

    /// How much of the tint a surface shows. Hover adds a third of the selection highlight, so
    /// it never reads as selected.
    public double SurfaceTintOpacity(SurfaceState state) => Math.Min(1, TintOpacity.Value + state switch
    {
        SurfaceState.Selected => SelectedTintOpacity.Value,
        SurfaceState.Hovered => SelectedTintOpacity.Value / 3,
        _ => 0,
    });
}
