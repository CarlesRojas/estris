using System.Runtime.InteropServices;
using Estris.Core;
using static Estris.Core.Loc;

namespace Estris.Utilities.Remap;

/// Turning what the hook and Raw Input report into one key code, and that code into what to send.
public static partial class KeyCodes
{
    private const int Extended = 0x100;
    private const int VirtualOnly = 0x10000;
    private const int PauseCode = 0x245;
    private const int PrintScreenCode = 0x137;
    private const int NumLockCode = 0x45;
    private const int RightShiftCode = 0x36;
    private const int VkPause = 0x13, VkPrintScreen = 0x2C, VkNumLock = 0x90, VkRightShift = 0xA1;
    private const int VkLeftControl = 0xA2, LeftControlCode = 0x1D;
    private const uint MAPVK_VK_TO_VSC_EX = 4, MAPVK_VSC_TO_VK_EX = 3, MAPVK_VK_TO_CHAR = 2;
    /// A key no layout uses: tapping it makes Windows forget a Win or Alt press was alone.
    private const int MaskKey = 0xE8;
    /// The Ctrl that AltGr adds in front of itself on some layouts.
    public const int AltGrControlScan = 0x21D;
    public const int RightAlt = 0x138;
    public const int FakeShiftVk = 0xFF;

    [LibraryImport("user32", EntryPoint = "MapVirtualKeyW")]
    private static partial uint MapVirtualKey(uint code, uint type);

    [LibraryImport("user32", EntryPoint = "MapVirtualKeyExW")]
    private static partial uint MapVirtualKeyEx(uint code, uint type, nint layout);

    [LibraryImport("user32")]
    private static partial nint GetKeyboardLayout(uint thread);

    public static int FromHook(int vk, int scan, bool extended)
    {
        if (Special(vk) is { } special) return special;
        if (scan != 0) return (scan & 0xFF) | (extended ? Extended : 0);
        // Sent by a program with no scan code, or by a key without one.
        var mapped = MapVirtualKey((uint)vk, MAPVK_VK_TO_VSC_EX);
        if (mapped == 0) return VirtualOnly | vk;
        return (int)(mapped & 0xFF) | ((mapped & 0xFF00) != 0 ? Extended : 0);
    }

    /// Null for the bytes that aren't a key, such as the fake Shift around Print Screen.
    public static int? FromRaw(int vk, int makeCode, bool isE0)
    {
        if (vk == FakeShiftVk) return null;
        if (Special(vk) is { } special) return special;
        return makeCode | (isE0 ? Extended : 0);
    }

    /// Keys the two report differently: Right Shift and Num Lock have the hook's extended flag
    /// the wrong way round, and Pause shares its scan code with Num Lock.
    private static int? Special(int vk) => vk switch
    {
        VkPause => PauseCode,
        VkNumLock => NumLockCode,
        VkPrintScreen => PrintScreenCode,
        VkRightShift => RightShiftCode,
        _ => null,
    };

    /// Sends a key: as the virtual key given or, for a result, what the layout in use gives that
    /// physical key, with its scan code in either case.
    public static void Send(int code, bool isDown, int vk = 0)
    {
        if ((code & VirtualOnly) != 0) { InputSender.Key(code & 0xFF, isDown); return; }
        if (code == PauseCode) { InputSender.Key(VkPause, isDown, 0x45); return; }
        if (vk == 0) vk = VirtualKey(code);
        InputSender.Key(vk, isDown, code & 0xFF, (code & Extended) != 0);
    }

    /// The Ctrl that Right Alt brings on layouts with AltGr.
    public static void SendAltGrControl(bool isDown) => InputSender.Key(VkLeftControl, isDown, LeftControlCode);

    public static void TapMaskKey()
    {
        InputSender.Key(MaskKey, true);
        InputSender.Key(MaskKey, false);
    }

    private static int VirtualKey(int code)
    {
        if (KeyCatalog.FixedVk(code) is { } vk) return vk;
        var thread = Native.GetWindowThreadProcessId(Native.GetForegroundWindow(), out _);
        var scan = (uint)(code & 0xFF) | ((code & Extended) != 0 ? 0xE000u : 0);
        return (int)MapVirtualKeyEx(scan, MAPVK_VSC_TO_VK_EX, GetKeyboardLayout(thread));
    }

    /// The character a typing key has on this layout, or null for one with none.
    public static char? LayoutCharacter(int code)
    {
        var vk = MapVirtualKey((uint)code, MAPVK_VSC_TO_VK_EX);
        var mapped = vk == 0 ? 0 : MapVirtualKey(vk, MAPVK_VK_TO_CHAR) & 0x7FFFFFFF;
        return mapped == 0 ? null : (char)mapped;
    }

    public static string CodeText(int code) => $"0x{code & 0xFFF:X2}";
}

public enum KeySection { Letters, Numbers, Modifiers, Editing, Navigation, Function, Symbols, Keypad, Other }

/// A key: its code, and the virtual key where the layout can't say (the keypad's digits depend on
/// Num Lock).
public sealed record KeyInfo(int Code, string Name, KeySection Section, int? Vk = null);

/// Every key Estris lists to remap from or to. The typing keys go by the layout in use, so each
/// shows what it types here; any other key can still be recorded.
public static class KeyCatalog
{
    private const string Letters = "1234567890";

    private static readonly IReadOnlyList<KeyInfo> Cache = Build();
    private static readonly Dictionary<int, KeyInfo> ByCode = Cache.GroupBy(k => k.Code).ToDictionary(g => g.Key, g => g.First());

    public static IReadOnlyList<KeyInfo> All => Cache;

    public static int? FixedVk(int code) => ByCode.GetValueOrDefault(code)?.Vk;

    public static string SectionTitle(KeySection section) => section switch
    {
        KeySection.Letters => T("Letters"),
        KeySection.Numbers => T("Numbers"),
        KeySection.Modifiers => T("Modifiers"),
        KeySection.Editing => T("Editing"),
        KeySection.Navigation => T("Navigation"),
        KeySection.Function => T("Function Keys"),
        KeySection.Symbols => T("Symbols"),
        KeySection.Keypad => T("Keypad"),
        _ => T("Other"),
    };

    /// A readable name for any key, listed or not.
    public static string Name(int code) =>
        ByCode.GetValueOrDefault(code)?.Name ?? T("Key %@", KeyCodes.CodeText(code));

    private static List<KeyInfo> Build()
    {
        var keys = new List<KeyInfo>();
        void Add(int code, string name, KeySection section, int? vk = null) => keys.Add(new KeyInfo(code, name, section, vk));

        int[] typing =
        [
            0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D,
            0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B,
            0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28,
            0x29, 0x2B,
            0x2C, 0x2D, 0x2E, 0x2F, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35,
            0x56,
        ];
        foreach (var code in typing)
        {
            if (KeyCodes.LayoutCharacter(code) is not { } character) continue;
            var section = char.IsLetter(character) ? KeySection.Letters : char.IsDigit(character) ? KeySection.Numbers : KeySection.Symbols;
            Add(code, section == KeySection.Symbols ? SymbolName(character) : character.ToString(), section);
        }
        keys = keys.OrderBy(k => k.Section).ThenBy(k => Letters.IndexOf(k.Name, StringComparison.Ordinal)).ThenBy(k => k.Name, StringComparer.CurrentCultureIgnoreCase).ToList();

        Add(0x15B, T("Left Windows"), KeySection.Modifiers);
        Add(0x15C, T("Right Windows"), KeySection.Modifiers);
        Add(0x38, T("Left Alt"), KeySection.Modifiers);
        Add(0x138, T("Right Alt"), KeySection.Modifiers);
        Add(0x1D, T("Left Control"), KeySection.Modifiers);
        Add(0x11D, T("Right Control"), KeySection.Modifiers);
        Add(0x2A, T("Left Shift"), KeySection.Modifiers);
        Add(0x36, T("Right Shift"), KeySection.Modifiers);
        Add(0x3A, T("Caps Lock"), KeySection.Modifiers);

        Add(0x1C, T("Enter"), KeySection.Editing);
        Add(0x0F, T("Tab"), KeySection.Editing);
        Add(0x39, T("Space"), KeySection.Editing);
        Add(0x0E, T("Backspace"), KeySection.Editing);
        Add(0x153, T("Delete"), KeySection.Editing);
        Add(0x01, T("Escape"), KeySection.Editing);
        Add(0x152, T("Insert"), KeySection.Editing);

        Add(0x148, T("Up Arrow"), KeySection.Navigation);
        Add(0x150, T("Down Arrow"), KeySection.Navigation);
        Add(0x14B, T("Left Arrow"), KeySection.Navigation);
        Add(0x14D, T("Right Arrow"), KeySection.Navigation);
        Add(0x147, T("Home"), KeySection.Navigation);
        Add(0x14F, T("End"), KeySection.Navigation);
        Add(0x149, T("Page Up"), KeySection.Navigation);
        Add(0x151, T("Page Down"), KeySection.Navigation);

        for (var i = 0; i < 10; i++) Add(0x3B + i, $"F{i + 1}", KeySection.Function);
        Add(0x57, "F11", KeySection.Function);
        Add(0x58, "F12", KeySection.Function);
        for (var i = 0; i < 11; i++) Add(0x64 + i, $"F{i + 13}", KeySection.Function);
        Add(0x76, "F24", KeySection.Function);

        (int Code, string Label, int Vk)[] keypad =
        [
            (0x4F, "1", 0x61), (0x50, "2", 0x62), (0x51, "3", 0x63), (0x4B, "4", 0x64), (0x4C, "5", 0x65),
            (0x4D, "6", 0x66), (0x47, "7", 0x67), (0x48, "8", 0x68), (0x49, "9", 0x69), (0x52, "0", 0x60),
            (0x53, ".", 0x6E), (0x4E, "+", 0x6B), (0x4A, "-", 0x6D), (0x37, "*", 0x6A), (0x135, "/", 0x6F),
        ];
        foreach (var (code, label, vk) in keypad) Add(code, T("Keypad %@", label), KeySection.Keypad, vk);
        Add(0x11C, T("Keypad Enter"), KeySection.Keypad, 0x0D);
        Add(0x45, T("Num Lock"), KeySection.Keypad, 0x90);

        Add(0x137, T("Print Screen"), KeySection.Other, 0x2C);
        Add(0x46, T("Scroll Lock"), KeySection.Other, 0x91);
        Add(0x245, T("Pause"), KeySection.Other, 0x13);
        Add(0x15D, T("Menu"), KeySection.Other);
        Add(0x120, T("Mute"), KeySection.Other, 0xAD);
        Add(0x130, T("Volume Up"), KeySection.Other, 0xAF);
        Add(0x12E, T("Volume Down"), KeySection.Other, 0xAE);
        Add(0x122, T("Play or Pause"), KeySection.Other, 0xB3);
        Add(0x119, T("Next Track"), KeySection.Other, 0xB0);
        Add(0x110, T("Previous Track"), KeySection.Other, 0xB1);
        return keys;
    }

    private static string SymbolName(char character) => character switch
    {
        '-' => T("- (Minus)"),
        '=' => T("= (Equals)"),
        '[' => T("[ (Left Bracket)"),
        ']' => T("] (Right Bracket)"),
        '\\' => T("\\ (Backslash)"),
        ';' => T("; (Semicolon)"),
        '\'' => T("' (Quote)"),
        '`' => T("` (Grave Accent)"),
        ',' => T(", (Comma)"),
        '.' => T(". (Period)"),
        '/' => T("/ (Slash)"),
        '§' => T("§ (Section)"),
        _ => character.ToString(),
    };
}

/// Names for mouse buttons, by number. 0 is the left one, then right, middle, back and forward.
public static class MouseButtons
{
    /// Everything but the left button, so the mouse can always click. Windows has only these.
    public static readonly int[] Remappable = [1, 2, 3, 4];
    public static readonly int[] All = [0, 1, 2, 3, 4];

    private const uint LeftDown = 0x02, LeftUp = 0x04, RightDown = 0x08, RightUp = 0x10, MiddleDown = 0x20, MiddleUp = 0x40, XDown = 0x80, XUp = 0x100;

    public static string Name(int number) => number switch
    {
        0 => T("Left Button"),
        1 => T("Right Button"),
        2 => T("Middle Button"),
        3 => T("Button 4 (Back)"),
        4 => T("Button 5 (Forward)"),
        _ => T("Button %lld", number + 1),
    };

    public static void Send(int number, bool isDown)
    {
        switch (number)
        {
            case 0: InputSender.Mouse(isDown ? LeftDown : LeftUp); break;
            case 1: InputSender.Mouse(isDown ? RightDown : RightUp); break;
            case 2: InputSender.Mouse(isDown ? MiddleDown : MiddleUp); break;
            case 3 or 4: InputSender.Mouse(isDown ? XDown : XUp, (uint)number - 2); break;
        }
    }

    /// The button number a hook action stands for, or null for moves and the wheel.
    public static int? From(MouseEvent e) => e.Action switch
    {
        MouseAction.LeftDown or MouseAction.LeftUp => 0,
        MouseAction.RightDown or MouseAction.RightUp => 1,
        MouseAction.MiddleDown or MouseAction.MiddleUp => 2,
        MouseAction.XDown or MouseAction.XUp => 2 + e.Data,
        _ => null,
    };

    public static bool IsDown(MouseEvent e) => e.Action is MouseAction.LeftDown or MouseAction.RightDown or MouseAction.MiddleDown or MouseAction.XDown;
}
