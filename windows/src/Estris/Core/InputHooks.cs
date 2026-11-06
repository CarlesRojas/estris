using System.Runtime.InteropServices;
using static Estris.Core.Native;

namespace Estris.Core;

public sealed class KeyEvent
{
    public required int Vk { get; init; }
    public required int Scan { get; init; }
    public required bool IsDown { get; init; }
    public required bool IsExtended { get; init; }
    /// Sent by a program rather than a keyboard.
    public required bool IsInjected { get; init; }
    /// Sent by Estris itself: every handler ignores these unless it wants them.
    public required bool IsOwn { get; init; }
    /// Set to swallow the event.
    public bool Handled { get; set; }
}

public enum MouseAction { Move, LeftDown, LeftUp, RightDown, RightUp, MiddleDown, MiddleUp, XDown, XUp, Wheel, HorizontalWheel }

public sealed class MouseEvent
{
    public required MouseAction Action { get; init; }
    public required int X { get; init; }
    public required int Y { get; init; }
    /// For X buttons: 1 or 2. For wheels: the signed delta.
    public required int Data { get; init; }
    public required bool IsInjected { get; init; }
    public required bool IsOwn { get; init; }
    public bool Handled { get; set; }
}

/// The low-level keyboard and mouse hooks, one thread shared by every utility. Each hook is
/// only installed while something listens. Handlers run on the hook thread, in the order they
/// subscribed, and must be quick: Windows drops a hook that takes too long (about 300 ms), without
/// saying so, so one that went quiet is put back within seconds. Marshal anything slow to another
/// thread, and never touch UI from them. While Estris is in front and listens to Raw Input,
/// Windows gives its keys to that and skips these hooks: see RawInputListener.
public static class InputHooks
{
    private static readonly object Gate = new();
    private static readonly List<Action<KeyEvent>> KeyHandlers = [];
    private static readonly List<Action<MouseEvent>> MouseHandlers = [];
    private static readonly HookProc KeyProc = OnKey;
    private static readonly HookProc MouseProc = OnMouse;
    private static Thread? thread;
    private static uint threadId;
    private static nint keyHook, mouseHook;
    private const uint WM_APP_UPDATE = 0x8001, WM_APP_REINSTALL = 0x8004, WM_TIMER = 0x113;
    private const uint HookCheckMilliseconds = 3000;
    /// Input newer than the last hook call by this much didn't pass through the hooks.
    private const int MissedInputMilliseconds = 500;
    private static int lastHookCall = Environment.TickCount;

    public static void Subscribe(Action<KeyEvent> handler)
    {
        lock (Gate) KeyHandlers.Add(handler);
        Update();
    }

    public static void Unsubscribe(Action<KeyEvent> handler)
    {
        lock (Gate) KeyHandlers.Remove(handler);
        Update();
    }

    public static void Subscribe(Action<MouseEvent> handler)
    {
        lock (Gate) MouseHandlers.Add(handler);
        Update();
    }

    public static void Unsubscribe(Action<MouseEvent> handler)
    {
        lock (Gate) MouseHandlers.Remove(handler);
        Update();
    }

    private static void Update()
    {
        lock (Gate)
        {
            if (thread is null)
            {
                using var ready = new ManualResetEventSlim();
                thread = new Thread(() =>
                {
                    threadId = GetCurrentThreadId();
                    // Makes the message queue, so the first post isn't lost.
                    PeekMessage(out _, 0, 0, 0, 0);
                    ready.Set();
                    Run();
                }) { IsBackground = true, Name = "Input hooks" };
                thread.SetApartmentState(ApartmentState.STA);
                thread.Priority = ThreadPriority.Highest;
                thread.Start();
                ready.Wait();
            }
        }
        PostThreadMessage(threadId, WM_APP_UPDATE, 0, 0);
    }

    private static void Run()
    {
        SetThreadTimer(0, 0, HookCheckMilliseconds, 0);
        while (GetMessage(out var message, 0, 0, 0) > 0)
        {
            if (message.message == WM_APP_UPDATE) Apply();
            if (message.message == WM_APP_REINSTALL) Reinstall();
            if (message.message == WM_TIMER) ReinstallIfMissingInput();
            TranslateMessage(ref message);
            DispatchMessage(ref message);
        }
        if (keyHook != 0) UnhookWindowsHookEx(keyHook);
        if (mouseHook != 0) UnhookWindowsHookEx(mouseHook);
    }

    private static void Apply()
    {
        bool wantsKeys, wantsMouse;
        lock (Gate)
        {
            wantsKeys = KeyHandlers.Count > 0;
            wantsMouse = MouseHandlers.Count > 0;
        }
        if (wantsKeys && keyHook == 0) keyHook = SetWindowsHookEx(WH_KEYBOARD_LL, KeyProc, GetModuleHandle(null), 0);
        if (!wantsKeys && keyHook != 0) { UnhookWindowsHookEx(keyHook); keyHook = 0; }
        if (wantsMouse && mouseHook == 0) mouseHook = SetWindowsHookEx(WH_MOUSE_LL, MouseProc, GetModuleHandle(null), 0);
        if (!wantsMouse && mouseHook != 0) { UnhookWindowsHookEx(mouseHook); mouseHook = 0; }
    }

    /// Installs the hooks again, first in line: Windows can stop calling a hook, or another
    /// program's hook can keep events from it, and a utility that notices (Remap, through Raw
    /// Input) asks for this.
    public static void RequestReinstall()
    {
        if (thread is not null) PostThreadMessage(threadId, WM_APP_REINSTALL, 0, 0);
    }

    /// New hooks first, so no input slips through between the old going and the new arriving.
    private static void Reinstall()
    {
        var (oldKey, oldMouse) = (keyHook, mouseHook);
        (keyHook, mouseHook) = (0, 0);
        Apply();
        if (oldKey != 0) UnhookWindowsHookEx(oldKey);
        if (oldMouse != 0) UnhookWindowsHookEx(oldMouse);
        lastHookCall = Environment.TickCount;
    }

    /// Windows knows of input the hooks never saw: they were dropped. With the keyboard hook alone,
    /// moving the mouse also looks like this, which is why it only costs a harmless reinstall.
    private static void ReinstallIfMissingInput()
    {
        if ((keyHook == 0 && mouseHook == 0) || IsOwnWindowInFront) return;
        var input = new LASTINPUTINFO { cbSize = (uint)Marshal.SizeOf<LASTINPUTINFO>() };
        if (!GetLastInputInfo(ref input) || unchecked((int)input.dwTime - lastHookCall) < MissedInputMilliseconds) return;
        if (keyHook != 0 && mouseHook != 0) App.Shared.Log.Add("Input", "Hooks missed input: installing them again");
        Reinstall();
    }

    public static bool IsOwnWindowInFront
    {
        get
        {
            GetWindowThreadProcessId(GetForegroundWindow(), out var process);
            return process == Environment.ProcessId;
        }
    }

    public static void Shutdown()
    {
        if (thread is not null) PostThreadMessage(threadId, WM_QUIT, 0, 0);
    }

    private static nint OnKey(int code, nint message, nint data)
    {
        lastHookCall = Environment.TickCount;
        if (code < 0) return CallNextHookEx(0, code, message, data);
        var raw = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(data);
        var e = new KeyEvent
        {
            Vk = (int)raw.vkCode,
            Scan = (int)raw.scanCode,
            IsDown = message is WM_KEYDOWN or WM_SYSKEYDOWN,
            IsExtended = (raw.flags & LLKHF_EXTENDED) != 0,
            IsInjected = (raw.flags & LLKHF_INJECTED) != 0,
            IsOwn = raw.dwExtraInfo == InputSender.Tag,
        };
        Action<KeyEvent>[] handlers;
        lock (Gate) handlers = KeyHandlers.ToArray();
        foreach (var handler in handlers)
        {
            try { handler(e); }
            catch (Exception error) { App.Shared.Log.Add("Input", $"Key handler failed: {error.Message}"); }
            if (e.Handled) return 1;
        }
        return CallNextHookEx(0, code, message, data);
    }

    private static nint OnMouse(int code, nint message, nint data)
    {
        lastHookCall = Environment.TickCount;
        if (code < 0) return CallNextHookEx(0, code, message, data);
        var raw = Marshal.PtrToStructure<MSLLHOOKSTRUCT>(data);
        var high = (short)(raw.mouseData >> 16);
        MouseAction? action = (int)message switch
        {
            WM_MOUSEMOVE => MouseAction.Move,
            WM_LBUTTONDOWN => MouseAction.LeftDown,
            WM_LBUTTONUP => MouseAction.LeftUp,
            WM_RBUTTONDOWN => MouseAction.RightDown,
            WM_RBUTTONUP => MouseAction.RightUp,
            WM_MBUTTONDOWN => MouseAction.MiddleDown,
            WM_MBUTTONUP => MouseAction.MiddleUp,
            WM_XBUTTONDOWN => MouseAction.XDown,
            WM_XBUTTONUP => MouseAction.XUp,
            WM_MOUSEWHEEL => MouseAction.Wheel,
            WM_MOUSEHWHEEL => MouseAction.HorizontalWheel,
            _ => null,
        };
        if (action is null) return CallNextHookEx(0, code, message, data);
        var e = new MouseEvent
        {
            Action = action.Value,
            X = raw.pt.X,
            Y = raw.pt.Y,
            Data = high,
            IsInjected = (raw.flags & LLMHF_INJECTED) != 0,
            IsOwn = raw.dwExtraInfo == InputSender.Tag,
        };
        Action<MouseEvent>[] handlers;
        lock (Gate) handlers = MouseHandlers.ToArray();
        foreach (var handler in handlers)
        {
            try { handler(e); }
            catch (Exception error) { App.Shared.Log.Add("Input", $"Mouse handler failed: {error.Message}"); }
            if (e.Handled) return 1;
        }
        return CallNextHookEx(0, code, message, data);
    }
}
