using static Estris.Core.Loc;

namespace Estris.Core;

/// A key combination, saved as data. The Mac's ⌘ is Ctrl here, ⌃⌥ is Ctrl+Alt.
public sealed record Shortcut(bool Ctrl, bool Shift, bool Alt, bool Win, int Vk)
{
    public bool HasCommandModifier => Ctrl || Alt || Win;

    public string Display
    {
        get
        {
            var parts = new List<string>();
            if (Win) parts.Add("Win");
            if (Ctrl) parts.Add("Ctrl");
            if (Alt) parts.Add("Alt");
            if (Shift) parts.Add("Shift");
            parts.Add(KeyNames.Name(Vk));
            return string.Join(" + ", parts);
        }
    }
}

/// Global shortcuts. These go through the keyboard hook rather than RegisterHotKey, so they win
/// over apps' own shortcuts as on the Mac, and the key is swallowed only when it matches.
public static class Hotkeys
{
    private static readonly Dictionary<object, (Shortcut Shortcut, Action Action)> Registered = [];
    private static bool isListening;

    /// Runs the action on the UI thread when the shortcut is pressed. Registering the same
    /// owner again replaces its shortcut; repeats while held are swallowed but don't run it.
    public static void Register(object owner, Shortcut shortcut, Action action)
    {
        lock (Registered)
        {
            Registered[owner] = (shortcut, action);
            if (isListening) return;
            isListening = true;
        }
        InputHooks.Subscribe(OnKey);
    }

    public static void Unregister(object owner)
    {
        lock (Registered)
        {
            Registered.Remove(owner);
            if (Registered.Count > 0 || !isListening) return;
            isListening = false;
        }
        InputHooks.Unsubscribe(OnKey);
    }

    private static readonly HashSet<int> Held = [];

    private static void OnKey(KeyEvent e)
    {
        if (e.IsOwn || KeyNames.IsModifier(e.Vk)) return;
        if (!e.IsDown)
        {
            if (Held.Remove(e.Vk)) e.Handled = true;
            return;
        }
        var ctrl = IsHeld(0xA2) || IsHeld(0xA3);
        var shift = IsHeld(0xA0) || IsHeld(0xA1);
        var alt = IsHeld(0xA4) || IsHeld(0xA5);
        var win = IsHeld(0x5B) || IsHeld(0x5C);
        (Shortcut Shortcut, Action Action)[] all;
        lock (Registered) all = Registered.Values.ToArray();
        foreach (var (shortcut, action) in all)
        {
            if (shortcut.Vk != e.Vk || shortcut.Ctrl != ctrl || shortcut.Shift != shift || shortcut.Alt != alt || shortcut.Win != win) continue;
            e.Handled = true;
            if (Held.Add(e.Vk)) App.Ui.TryEnqueue(() => action());
            return;
        }
    }

    public static bool IsHeld(int vk) => (InputSender.GetAsyncKeyState(vk) & 0x8000) != 0;
}

/// Names of virtual keys, for showing shortcuts and pickers.
public static class KeyNames
{
    public static bool IsModifier(int vk) => vk is 0x10 or 0x11 or 0x12 or >= 0xA0 and <= 0xA5 or 0x5B or 0x5C;

    public static string Name(int vk) => vk switch
    {
        >= 0x30 and <= 0x39 or >= 0x41 and <= 0x5A => ((char)vk).ToString(),
        >= 0x70 and <= 0x87 => $"F{vk - 0x6F}",
        >= 0x60 and <= 0x69 => $"Num {vk - 0x60}",
        0x08 => T("Backspace"),
        0x09 => "Tab",
        0x0D => "Enter",
        0x1B => "Esc",
        0x20 => T("Space"),
        0x21 => "Page Up",
        0x22 => "Page Down",
        0x23 => T("End"),
        0x24 => T("Home"),
        0x25 => "←",
        0x26 => "↑",
        0x27 => "→",
        0x28 => "↓",
        0x2D => "Insert",
        0x2E => T("Delete"),
        0xBA => ";",
        0xBB => "=",
        0xBC => ",",
        0xBD => "-",
        0xBE => ".",
        0xBF => "/",
        0xC0 => "`",
        0xDB => "[",
        0xDC => "\\",
        0xDD => "]",
        0xDE => "'",
        _ => $"0x{vk:X2}",
    };
}
