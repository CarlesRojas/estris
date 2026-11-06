using System.Runtime.InteropServices;
using Estris.Core;
using static Estris.Core.Native;

namespace Estris.Utilities.WindowSnapping;

/// The keys a Window Snapping shortcut can use with Win and Alt, and which shortcut has which.
public static partial class SnapKeys
{
    /// Arrange All's id among the shortcuts, next to the snap actions' ids.
    public const string ArrangeAllId = "arrangeAll";

    private const int VK_LCONTROL = 0xA2, VK_RCONTROL = 0xA3, VK_LMENU = 0xA4, VK_RMENU = 0xA5;
    private const int VK_LSHIFT = 0xA0, VK_RSHIFT = 0xA1, VK_LWIN = 0x5B, VK_RWIN = 0x5C;
    private const uint MOD_ALT = 1, MOD_WIN = 8;
    /// A probe that isn't kept: only asks whether the combination is taken.
    private const int ProbeHotkeyId = 0xE571;
    /// Letters, digits, arrows, Enter, Backspace, Space, Tab and punctuation.
    public static readonly int[] All =
    [
        .. Enumerable.Range('A', 26), .. Enumerable.Range('1', 9), '0',
        0x25, 0x27, 0x26, 0x28, 0x0D, 0x08, 0x20, 0x09,
        0xBD, 0xBB, 0xDB, 0xDD, 0xBA, 0xDE, 0xBC, 0xBE, 0xBF, 0xDC, 0xC0,
    ];

    /// Every shortcut's id, in priority order, the order the pane shows them in: Arrange All,
    /// then the snap actions. When two share a key, the first one gets it.
    public static IEnumerable<string> Ids => SnapActions.All.Select(a => a.Id()).Prepend(ArrangeAllId);

    /// Each shortcut's key as it starts out.
    public static int DefaultKey(string id) =>
        id == ArrangeAllId ? 0x20 : SnapActions.FromId(id)?.DefaultKey() ?? 0;

    [LibraryImport("user32", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool RegisterHotKey(nint hwnd, int id, uint modifiers, uint vk);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool UnregisterHotKey(nint hwnd, int id);

    /// Whether Windows or an app claimed Win+Alt plus this key for itself.
    public static bool IsTaken(int vk)
    {
        if (RegisterHotKey(0, ProbeHotkeyId, MOD_WIN | MOD_ALT, (uint)vk))
        {
            UnregisterHotKey(0, ProbeHotkeyId);
            return false;
        }
        return Marshal.GetLastPInvokeError() == WindowNative.ERROR_HOTKEY_ALREADY_REGISTERED;
    }

    public static bool AreWinAltHeld => (Hotkeys.IsHeld(VK_LWIN) || Hotkeys.IsHeld(VK_RWIN)) && (Hotkeys.IsHeld(VK_LMENU) || Hotkeys.IsHeld(VK_RMENU));
    public static bool AreOtherModifiersHeld => Hotkeys.IsHeld(VK_LSHIFT) || Hotkeys.IsHeld(VK_RSHIFT) || Hotkeys.IsHeld(VK_LCONTROL) || Hotkeys.IsHeld(VK_RCONTROL);
}

/// The Win+Alt shortcuts, through the keyboard hook like Core's Hotkeys so they win over Windows's
/// and apps' own, with one difference: as the key is swallowed, Windows would take Win and Alt for
/// pressed alone and open Start or the menu bar on release, so a key nothing uses is tapped first.
public sealed class SnapHotkeys
{
    private const int VkUnassigned = 0xE8;

    private readonly Dictionary<int, Action> actions = [];
    private readonly HashSet<int> held = [];
    private bool isListening;

    /// Replaces the shortcuts. Each runs on the UI thread; none listens with an empty map.
    public void Set(Dictionary<int, Action> keys)
    {
        lock (actions)
        {
            actions.Clear();
            foreach (var (vk, action) in keys) actions[vk] = action;
        }
        if (keys.Count > 0 && !isListening) InputHooks.Subscribe(OnKey);
        if (keys.Count == 0 && isListening) InputHooks.Unsubscribe(OnKey);
        isListening = keys.Count > 0;
    }

    private void OnKey(KeyEvent e)
    {
        if (e.IsOwn || KeyNames.IsModifier(e.Vk)) return;
        if (!e.IsDown)
        {
            if (held.Remove(e.Vk)) e.Handled = true;
            return;
        }
        Action? action;
        lock (actions) actions.TryGetValue(e.Vk, out action);
        if (action is null || !SnapKeys.AreWinAltHeld || SnapKeys.AreOtherModifiersHeld) return;
        e.Handled = true;
        if (!held.Add(e.Vk)) return;
        App.Ui.TryEnqueue(() =>
        {
            InputSender.Chord(VkUnassigned);
            action();
        });
    }
}
