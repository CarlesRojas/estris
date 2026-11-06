using System.Runtime.InteropServices;
using System.Text;
using Estris.Core;
using static Estris.Core.Native;

namespace Estris.Utilities.WindowSnapping;

/// The keys a Window Snapping shortcut can use with Ctrl and Alt, and which shortcut has which.
public static partial class SnapKeys
{
    /// Arrange All's id among the shortcuts, next to the snap actions' ids.
    public const string ArrangeAllId = "arrangeAll";

    private const int VK_LCONTROL = 0xA2, VK_RCONTROL = 0xA3, VK_LMENU = 0xA4, VK_RMENU = 0xA5, VK_MENU = 0x12, VK_CONTROL = 0x11;
    private const int VK_LSHIFT = 0xA0, VK_RSHIFT = 0xA1, VK_LWIN = 0x5B, VK_RWIN = 0x5C;
    private const uint MOD_ALT = 1, MOD_CONTROL = 2;
    /// A probe that isn't kept: only asks whether the combination is taken.
    private const int ProbeHotkeyId = 0xE571;
    /// ToUnicodeEx leaves the keyboard's dead-key state alone with this.
    private const uint KeepKeyboardState = 4;

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

    [LibraryImport("user32")] private static partial nint GetKeyboardLayout(uint thread);
    [LibraryImport("user32")] private static partial uint MapVirtualKeyExW(uint code, uint type, nint layout);
    [LibraryImport("user32", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool RegisterHotKey(nint hwnd, int id, uint modifiers, uint vk);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool UnregisterHotKey(nint hwnd, int id);

    [DllImport("user32", CharSet = CharSet.Unicode)]
    private static extern int ToUnicodeEx(uint vk, uint scan, byte[] keyState, StringBuilder text, int size, uint flags, nint layout);

    /// What Ctrl+Alt plus a key types on the keyboard in use, which is the same as AltGr plus
    /// it, or null when it types nothing: only then does a shortcut take a character away.
    public static string? TypedWithAltGr(int vk)
    {
        var layout = GetKeyboardLayout(TopWindow.Foreground.ThreadId);
        var state = new byte[256];
        state[VK_CONTROL] = state[VK_LCONTROL] = state[VK_MENU] = state[VK_RMENU] = 0x80;
        var text = new StringBuilder(8);
        var length = ToUnicodeEx((uint)vk, MapVirtualKeyExW((uint)vk, 0, layout), state, text, text.Capacity, KeepKeyboardState, layout);
        // Negative for a dead key, which does type something, once followed by a letter.
        if (length == 0) return null;
        var typed = length < 0 ? text.ToString(0, 1) : text.ToString(0, length);
        return typed.Any(c => !char.IsControl(c) && !char.IsWhiteSpace(c)) ? typed : null;
    }

    /// Whether another app claimed Ctrl+Alt plus this key for itself.
    public static bool IsTakenByAnotherApp(int vk)
    {
        if (RegisterHotKey(0, ProbeHotkeyId, MOD_CONTROL | MOD_ALT, (uint)vk))
        {
            UnregisterHotKey(0, ProbeHotkeyId);
            return false;
        }
        return Marshal.GetLastPInvokeError() == WindowNative.ERROR_HOTKEY_ALREADY_REGISTERED;
    }

    public static bool IsAltGrHeld => Hotkeys.IsHeld(VK_RMENU) && !Hotkeys.IsHeld(VK_LMENU);
    public static bool AreCtrlAltHeld => (Hotkeys.IsHeld(VK_LCONTROL) || Hotkeys.IsHeld(VK_RCONTROL)) && (Hotkeys.IsHeld(VK_LMENU) || Hotkeys.IsHeld(VK_RMENU));
    public static bool AreOtherModifiersHeld => Hotkeys.IsHeld(VK_LSHIFT) || Hotkeys.IsHeld(VK_RSHIFT) || Hotkeys.IsHeld(VK_LWIN) || Hotkeys.IsHeld(VK_RWIN);
}

/// The Ctrl+Alt shortcuts, through the keyboard hook like Core's Hotkeys so they win over apps'
/// own, with one difference: AltGr, which Windows reports as Ctrl+Alt, keeps typing. Pressing
/// the right Alt on a key that types something with it is left alone.
public sealed class SnapHotkeys
{
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
        if (action is null || !SnapKeys.AreCtrlAltHeld || SnapKeys.AreOtherModifiersHeld) return;
        if (SnapKeys.IsAltGrHeld && SnapKeys.TypedWithAltGr(e.Vk) is not null) return;
        e.Handled = true;
        if (held.Add(e.Vk)) App.Ui.TryEnqueue(() => action());
    }
}
