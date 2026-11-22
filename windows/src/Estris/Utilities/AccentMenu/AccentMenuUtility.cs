using Estris.Core;
using Estris.Ui;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using static Estris.Core.Loc;
using static Estris.Core.Native;

namespace Estris.Utilities.AccentMenu;

/// Holding down a letter key while typing shows its accented versions over the caret, as the
/// Mac's accent menu does: a number, the arrow keys and Enter, or a click picks one, which takes
/// the place of the letter typed; Esc keeps the letter, and any other key goes on as typed. Only
/// in what takes text, so a game's held keys still repeat; there, as on the Mac, no held letter
/// repeats, with accents or not.
public sealed class AccentMenuUtility(AppLog log) : IUtility
{
    private const int VkBack = 0x08, VkTab = 0x09, VkReturn = 0x0D, VkEscape = 0x1B, VkSpace = 0x20, VkLeft = 0x25, VkRight = 0x27;
    private const int VkShift = 0x10, VkControl = 0x11, VkMenu = 0x12, VkCapital = 0x14, VkLWin = 0x5B, VkRWin = 0x5C;
    private const uint MAPVK_VK_TO_CHAR = 2;
    /// What is in front is checked this often while the menu shows: switching windows closes it.
    private static readonly TimeSpan FrontCheck = TimeSpan.FromMilliseconds(200);

    public string Id => "accentMenu";
    public string Title => "Accent Menu";
    public string Glyph => "";
    public UtilityGroup Group => UtilityGroup.KeyboardAndMouse;
    public string[] Keywords => ["accents", "accented", "letters", "characters", "diacritics", "press and hold", "keyboard", "typing"];
    public Setting<bool> Enabled { get; } = SettingsStore.Shared.Get("accentMenuEnabled", false);

    private readonly AccentMenuSettings settings = new();
    private AccentPanel? panel;
    private DispatcherQueueTimer? holdTimer, frontTimer;
    private bool isListening;

    // Hook thread only.
    private int heldVk;
    /// Keys whose press the menu took, so their release is taken too.
    private readonly HashSet<int> swallowed = [];
    private bool isClickSwallowed;

    // Shared: each held key gets a number, and only the latest may still show its menu.
    private int generation;
    /// Whether the held key is typing into text: Unknown until the check comes back.
    private int heldTakesText;
    private const int Unknown = 0, TakesText = 1, NoText = 2;
    /// How long after the press the caret is looked for, so the app has typed the letter by then.
    private const int CheckAfterMilliseconds = 100;
    /// The menu on screen, or null. Opened and closed on the UI thread, its choice moved on the hook thread.
    private volatile Menu? menu;

    // UI thread only.
    private Pending? pending;
    private nint frontAtOpen;

    /// A held key waiting for its delay and for the text check.
    private sealed class Pending(int push, string accents)
    {
        public int Push { get; } = push;
        public string Accents { get; } = accents;
        public bool IsDue { get; set; }
        public bool IsChecked { get; set; }
        public RECT? Caret { get; set; }
    }

    private sealed class Menu(string accents, RECT[] items, RECT frame)
    {
        public string Accents { get; } = accents;
        public RECT[] Items { get; } = items;
        public RECT Frame { get; } = frame;
        public int Selected = -1;
    }

    public void Start()
    {
        panel = new AccentPanel();
        holdTimer = App.Ui.CreateTimer();
        holdTimer.IsRepeating = false;
        holdTimer.Tick += (_, _) =>
        {
            if (pending is null) return;
            pending.IsDue = true;
            ShowIfReady();
        };
        frontTimer = App.Ui.CreateTimer();
        frontTimer.Interval = FrontCheck;
        frontTimer.Tick += (_, _) => { if (GetForegroundWindow() != frontAtOpen) Close(); };
        Enabled.Changed += Apply;
        Apply();
    }

    public void Stop() => Listen(false);

    private void Apply() => Listen(Enabled.Value);

    private void Listen(bool listens)
    {
        if (listens == isListening) return;
        isListening = listens;
        if (listens) InputHooks.Subscribe(OnKey);
        else
        {
            InputHooks.Unsubscribe(OnKey);
            Interlocked.Increment(ref generation);
            Close();
        }
        log.Add(Title, listens ? "watching held keys" : "stopped watching held keys");
    }

    /// On the hook thread: keep it quick. Anything slow or on screen goes to another thread.
    private void OnKey(KeyEvent e)
    {
        if (e.IsOwn) return;
        if (menu is { } open && OnMenuKey(e, open)) return;
        if (!e.IsDown)
        {
            if (swallowed.Remove(e.Vk)) e.Handled = true;
            if (e.Vk != heldVk) return;
            heldVk = 0;
            // Let go before its menu showed: no menu.
            if (menu is null) Interlocked.Increment(ref generation);
            return;
        }
        if (e.Vk == heldVk)
        {
            // Held: it doesn't repeat while it may be typing into text.
            if (Volatile.Read(ref heldTakesText) != NoText) e.Handled = true;
            return;
        }
        heldVk = 0;
        var push = Interlocked.Increment(ref generation);
        if (!Accents.IsLetter(e.Vk) || IsShortcutHeld() || !TypesItsLetter(e.Vk)) return;
        heldVk = e.Vk;
        Volatile.Write(ref heldTakesText, Unknown);
        var isUppercase = IsDown(VkShift) ^ ((InputSender.GetKeyState(VkCapital) & 1) != 0);
        var accents = Accents.For(e.Vk, isUppercase);
        var delay = settings.Delay.Value;
        // A letter without accents only stops repeating, as on the Mac.
        if (accents.Length > 0) App.Ui.TryEnqueue(() =>
        {
            if (holdTimer is null) return;
            pending = new Pending(push, accents);
            holdTimer.Stop();
            holdTimer.Interval = TimeSpan.FromMilliseconds(delay);
            holdTimer.Start();
        });
        _ = Task.Run(async () =>
        {
            await Task.Delay((int)Math.Min(CheckAfterMilliseconds, delay / 2));
            RECT? caret = null;
            try { caret = TextFocus.Caret(); }
            catch (Exception error) { log.Add(Title, $"couldn't find the caret: {error.Message}"); }
            if (Volatile.Read(ref generation) == push) Volatile.Write(ref heldTakesText, caret is null ? NoText : TakesText);
            App.Ui.TryEnqueue(() =>
            {
                if (pending is null || pending.Push != push) return;
                pending.IsChecked = true;
                pending.Caret = caret;
                ShowIfReady();
            });
        });
    }

    /// A key while the menu shows. True when it's dealt with; false lets it go on as usual.
    private bool OnMenuKey(KeyEvent e, Menu open)
    {
        if (!e.IsDown)
        {
            if (swallowed.Remove(e.Vk)) e.Handled = true;
            if (e.Vk == heldVk) heldVk = 0;
            return true;
        }
        if (e.Vk == heldVk)
        {
            e.Handled = true;
            return true;
        }
        if (IsModifier(e.Vk)) return true;
        var number = e.Vk switch
        {
            >= 0x31 and <= 0x39 => e.Vk - 0x30,
            >= 0x61 and <= 0x69 => e.Vk - 0x60,
            _ => 0,
        };
        var count = open.Accents.Length;
        if (number > 0 && number <= count) Take(e, () => Choose(open, number - 1));
        else if (e.Vk is VkLeft or VkRight)
        {
            var next = open.Selected < 0
                ? (e.Vk == VkRight ? 0 : count - 1)
                : Math.Clamp(open.Selected + (e.Vk == VkRight ? 1 : -1), 0, count - 1);
            open.Selected = next;
            Take(e, () => { if (menu == open) panel?.Select(next); });
        }
        else if (e.Vk is VkReturn && open.Selected >= 0) Take(e, () => Choose(open, open.Selected));
        else if (e.Vk is VkSpace && open.Selected >= 0) Take(e, () => Choose(open, open.Selected, " "));
        else if (e.Vk is VkEscape) Take(e, Close);
        else
        {
            // Any other key closes it and goes on as typed: Tab, Backspace, another letter…
            App.Ui.TryEnqueue(Close);
            return false;
        }
        return true;
    }

    /// Swallows the key, and its release, and acts on the UI thread.
    private void Take(KeyEvent e, Action action)
    {
        e.Handled = true;
        swallowed.Add(e.Vk);
        App.Ui.TryEnqueue(() => action());
    }

    /// While the menu shows: the pointer over an accent selects it, a click picks it, and a click
    /// anywhere else closes the menu.
    private void OnMouse(MouseEvent e)
    {
        if (e.IsOwn) return;
        if (e.Action == MouseAction.LeftUp && isClickSwallowed)
        {
            isClickSwallowed = false;
            e.Handled = true;
            return;
        }
        if (menu is not { } open) return;
        var index = Array.FindIndex(open.Items, r => Contains(r, e.X, e.Y));
        switch (e.Action)
        {
            case MouseAction.Move when index >= 0 && index != open.Selected:
                open.Selected = index;
                App.Ui.TryEnqueue(() => { if (menu == open) panel?.Select(index); });
                break;
            case MouseAction.LeftDown or MouseAction.RightDown or MouseAction.MiddleDown or MouseAction.XDown:
                if (Contains(open.Frame, e.X, e.Y))
                {
                    e.Handled = true;
                    isClickSwallowed = e.Action == MouseAction.LeftDown;
                    if (e.Action == MouseAction.LeftDown && index >= 0) App.Ui.TryEnqueue(() => Choose(open, index));
                }
                else App.Ui.TryEnqueue(Close);
                break;
        }
    }

    private static bool Contains(RECT r, int x, int y) => x >= r.Left && x < r.Right && y >= r.Top && y < r.Bottom;

    /// On the UI thread, once the key has been held long enough and the caret is known.
    private void ShowIfReady()
    {
        if (pending is not { IsDue: true, IsChecked: true } ready) return;
        pending = null;
        if (ready.Push != Volatile.Read(ref generation) || ready.Caret is not { } caret || panel is null) return;
        panel.Show(ready.Accents, caret);
        var (items, frame) = panel.Frames();
        frontAtOpen = GetForegroundWindow();
        menu = new Menu(ready.Accents, items, frame);
        InputHooks.Subscribe(OnMouse);
        frontTimer?.Start();
    }

    /// Puts that accent in place of the letter typed, and after it what the key picking it types.
    private void Choose(Menu open, int index, string then = "")
    {
        if (menu != open) return;
        Close();
        InputSender.Key(VkBack, true);
        InputSender.Key(VkBack, false);
        InputSender.Text(open.Accents[index] + then);
    }

    private void Close()
    {
        holdTimer?.Stop();
        pending = null;
        if (menu is null) return;
        menu = null;
        frontTimer?.Stop();
        InputHooks.Unsubscribe(OnMouse);
        panel?.Hide();
    }

    private static bool IsDown(int vk) => (InputSender.GetAsyncKeyState(vk) & 0x8000) != 0;

    /// Ctrl, Alt or Win held: the letter is a shortcut, not typing.
    private static bool IsShortcutHeld() => IsDown(VkControl) || IsDown(VkMenu) || IsDown(VkLWin) || IsDown(VkRWin);

    private static bool IsModifier(int vk) => vk is VkShift or VkControl or VkMenu or VkCapital or VkLWin or VkRWin or (>= 0xA0 and <= 0xA5);

    /// The key types its own letter in the layout of the app in front, so not on a Cyrillic or Greek one.
    private static bool TypesItsLetter(int vk)
    {
        var layout = GetKeyboardLayout(GetWindowThreadProcessId(GetForegroundWindow(), out _));
        return MapVirtualKeyEx((uint)vk, MAPVK_VK_TO_CHAR, layout) == vk;
    }

    public UIElement BuildPane()
    {
        var pane = new Pane();
        pane.UtilityHeader(this, T("Hold down a letter key while typing to choose an accented version of it, such as é, ñ or ç."));

        pane.Section(T("Behavior"));
        pane.Slider(T("Delay"), settings.Delay, AccentMenuSettings.MinimumDelay, AccentMenuSettings.MaximumDelay, AccentMenuSettings.DelayStep,
            value => T("%lld ms", (long)Math.Round(value)),
            T("How long a key is held before its accents show."));
        pane.Note(T("Pick an accent with its number, with the arrow keys and Enter, or with a click. Esc keeps the letter you typed. As on a Mac, letters don't repeat while held in a text field."));

        pane.ResetButton(settings.Reset);
        return pane.Root;
    }

    [System.Runtime.InteropServices.DllImport("user32")] private static extern nint GetKeyboardLayout(uint thread);
    [System.Runtime.InteropServices.DllImport("user32", EntryPoint = "MapVirtualKeyExW")] private static extern uint MapVirtualKeyEx(uint code, uint type, nint layout);
}
