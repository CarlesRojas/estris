using System.Runtime.InteropServices;

namespace Estris.Core;

/// Sends keys and mouse buttons. Everything sent carries Tag, so InputHooks marks it as own.
public static partial class InputSender
{
    public static readonly nuint Tag = 0x45535452; // "ESTR"

    private const uint INPUT_MOUSE = 0, INPUT_KEYBOARD = 1;
    private const uint KEYEVENTF_EXTENDEDKEY = 1, KEYEVENTF_KEYUP = 2, KEYEVENTF_SCANCODE = 8;

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public nuint dwExtraInfo; }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public nuint dwExtraInfo; }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public KEYBDINPUT Key;
        [FieldOffset(0)] public MOUSEINPUT Mouse;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT { public uint type; public InputUnion data; }

    [LibraryImport("user32", SetLastError = true)]
    private static partial uint SendInput(uint count, [In] INPUT[] inputs, int size);

    private static INPUT KeyInput(int vk, bool down, int scan, bool extended) => new()
    {
        type = INPUT_KEYBOARD,
        data = new InputUnion
        {
            Key = new KEYBDINPUT
            {
                wVk = (ushort)vk,
                wScan = (ushort)scan,
                dwFlags = (down ? 0 : KEYEVENTF_KEYUP) | (extended ? KEYEVENTF_EXTENDEDKEY : 0),
                dwExtraInfo = Tag,
            },
        },
    };

    public static void Key(int vk, bool down, int scan = 0, bool extended = false) =>
        SendInput(1, [KeyInput(vk, down, scan, extended)], Marshal.SizeOf<INPUT>());

    /// Presses the keys in order, then releases them in reverse: Chord(VK_CONTROL, 'V').
    public static void Chord(params int[] vks)
    {
        var inputs = new List<INPUT>(vks.Length * 2);
        foreach (var vk in vks) inputs.Add(KeyInput(vk, true, 0, IsExtendedKey(vk)));
        foreach (var vk in vks.Reverse()) inputs.Add(KeyInput(vk, false, 0, IsExtendedKey(vk)));
        SendInput((uint)inputs.Count, inputs.ToArray(), Marshal.SizeOf<INPUT>());
    }

    public static void Mouse(uint flags, uint data = 0) =>
        SendInput(1, [new INPUT { type = INPUT_MOUSE, data = new InputUnion { Mouse = new MOUSEINPUT { dwFlags = flags, mouseData = data, dwExtraInfo = Tag } } }], Marshal.SizeOf<INPUT>());

    /// Lets go of modifiers the user is holding, so a chord sent now isn't changed by them.
    public static void ReleaseHeldModifiers()
    {
        foreach (var vk in new[] { 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0x5B, 0x5C })
            if ((GetAsyncKeyState(vk) & 0x8000) != 0) Key(vk, false, 0, IsExtendedKey(vk));
    }

    [LibraryImport("user32")]
    public static partial short GetAsyncKeyState(int vk);

    private static bool IsExtendedKey(int vk) => vk is
        0x21 or 0x22 or 0x23 or 0x24 or 0x25 or 0x26 or 0x27 or 0x28 or 0x2D or 0x2E // navigation
        or 0x5B or 0x5C or 0x5D or 0xA3 or 0xA5 or 0x6F or 0x90;
}
