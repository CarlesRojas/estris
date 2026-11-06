using System.Runtime.InteropServices;
using Estris.Core;
using static Estris.Core.Native;

namespace Estris.Utilities.Remap;

/// Raw Input on a thread of its own, apart from the hook thread: says which device sent each key
/// and button and when devices change. Also what wakes the engine at its deadlines.
public sealed class RawInputListener(Func<nint, string?> deviceOf, Action<RawEvent> onRaw, Action onDevicesChanged, Func<int> nextDeadline, Action onDeadline)
{
    private const ushort GenericDesktop = 1, MouseUsage = 2, KeyboardUsage = 6;
    private const uint RIDEV_REMOVE = 0x1, RIDEV_INPUTSINK = 0x100, RIDEV_DEVNOTIFY = 0x2000;
    private const uint WM_INPUT = 0xFF, WM_INPUT_DEVICE_CHANGE = 0xFE, WM_APP_WAKE = 0x8002, WM_APP_MOUSE = 0x8003;
    private const uint RID_INPUT = 0x10000003, RIM_TYPEMOUSE = 0, RIM_TYPEKEYBOARD = 1;
    private const ushort RI_KEY_BREAK = 1, RI_KEY_E0 = 2;
    private const uint QS_ALLINPUT = 0x4FF, MWMO_INPUTAVAILABLE = 4, PM_REMOVE = 1, INFINITE = 0xFFFFFFFF;
    private const int SM_SWAPBUTTON = 23;
    private static readonly nint HWND_MESSAGE = -3;

    /// Which button each pair of RAWMOUSE flag bits stands for: press, then release.
    private static readonly (ushort Down, ushort Up, int Button)[] ButtonFlags =
        [(0x001, 0x002, 0), (0x004, 0x008, 1), (0x010, 0x020, 2), (0x040, 0x080, 3), (0x100, 0x200, 4)];

    private delegate nint WindowProc(nint hwnd, uint message, nint wParam, nint lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WNDCLASSEX
    {
        public int Size;
        public uint Style;
        public WindowProc Proc;
        public int ClassExtra, WindowExtra;
        public nint Instance, Icon, Cursor, Background;
        public string? Menu;
        public string ClassName;
        public nint SmallIcon;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RAWINPUTDEVICE { public ushort UsagePage, Usage; public uint Flags; public nint Target; }

    [StructLayout(LayoutKind.Sequential)]
    private struct RAWINPUTHEADER { public uint Type, Size; public nint Device, WParam; }

    [StructLayout(LayoutKind.Sequential)]
    private struct RAWKEYBOARD { public ushort MakeCode, Flags, Reserved, VKey; public uint Message, ExtraInformation; }

    [StructLayout(LayoutKind.Sequential)]
    private struct RAWMOUSE { public ushort Flags, Padding, ButtonFlags, ButtonData; public uint RawButtons; public int LastX, LastY; public uint ExtraInformation; }

    [DllImport("user32", CharSet = CharSet.Unicode, EntryPoint = "RegisterClassExW")]
    private static extern ushort RegisterClassEx(ref WNDCLASSEX windowClass);

    [DllImport("user32", CharSet = CharSet.Unicode, EntryPoint = "CreateWindowExW", SetLastError = true)]
    private static extern nint CreateWindowEx(uint exStyle, string className, string name, uint style, int x, int y, int width, int height, nint parent, nint menu, nint instance, nint param);

    [DllImport("user32")]
    private static extern bool DestroyWindow(nint hwnd);

    [DllImport("user32", EntryPoint = "DefWindowProcW")]
    private static extern nint DefWindowProc(nint hwnd, uint message, nint wParam, nint lParam);

    [DllImport("user32", SetLastError = true)]
    private static extern bool RegisterRawInputDevices(RAWINPUTDEVICE[] devices, uint count, uint size);

    [DllImport("user32")]
    private static extern uint GetRawInputData(nint input, uint command, nint data, ref uint size, uint headerSize);

    [DllImport("user32", EntryPoint = "PostMessageW")]
    private static extern bool PostMessage(nint hwnd, uint message, nint wParam, nint lParam);

    [DllImport("user32")]
    private static extern uint MsgWaitForMultipleObjectsEx(uint count, nint handles, uint milliseconds, uint mask, uint flags);

    [DllImport("user32")]
    private static extern int GetSystemMetrics(int index);

    private const string ClassName = "EstrisRawInput";
    private static readonly int HeaderSize = Marshal.SizeOf<RAWINPUTHEADER>();
    private readonly byte[] buffer = new byte[256];
    /// Kept alive here: Windows holds on to it for as long as the process runs.
    private WindowProc? keptProc;
    private Thread? thread;
    private volatile nint window;
    private volatile bool isQuitting;
    private bool listensToMouse;

    public void Start(AppLog log)
    {
        if (thread is not null) return;
        using var ready = new ManualResetEventSlim();
        isQuitting = false;
        thread = new Thread(() => Run(ready, log)) { IsBackground = true, Name = "Raw input" };
        thread.Priority = ThreadPriority.Highest;
        thread.Start();
        ready.Wait();
    }

    public void Stop()
    {
        if (thread is null) return;
        isQuitting = true;
        Wake();
        thread.Join(TimeSpan.FromSeconds(1));
        thread = null;
    }

    /// Makes it look at the deadlines again.
    public void Wake() => PostMessage(window, WM_APP_WAKE, 0, 0);

    /// Whether to listen to mice, which send thousands of moves: only while something needs them.
    public void ListenToMouse(bool value) => PostMessage(window, WM_APP_MOUSE, value ? 1 : 0, 0);

    private void Run(ManualResetEventSlim ready, AppLog log)
    {
        keptProc ??= OnMessage;
        var instance = GetModuleHandle(null);
        var windowClass = new WNDCLASSEX { Size = Marshal.SizeOf<WNDCLASSEX>(), Proc = keptProc, Instance = instance, ClassName = ClassName };
        RegisterClassEx(ref windowClass);
        window = CreateWindowEx(0, ClassName, "", 0, 0, 0, 0, 0, HWND_MESSAGE, 0, instance, 0);
        if (window == 0 || !Register(KeyboardUsage, RIDEV_INPUTSINK | RIDEV_DEVNOTIFY, window))
            log.Add("Remap", $"can't listen to Raw Input (error {Marshal.GetLastWin32Error()})");
        ready.Set();

        while (!isQuitting)
        {
            var timeout = nextDeadline();
            MsgWaitForMultipleObjectsEx(0, 0, timeout < 0 ? INFINITE : (uint)timeout, QS_ALLINPUT, MWMO_INPUTAVAILABLE);
            while (PeekMessage(out var message, 0, 0, 0, PM_REMOVE))
            {
                TranslateMessage(ref message);
                DispatchMessage(ref message);
            }
            onDeadline();
        }

        Register(KeyboardUsage, RIDEV_REMOVE, 0);
        if (listensToMouse) Register(MouseUsage, RIDEV_REMOVE, 0);
        listensToMouse = false;
        DestroyWindow(window);
        window = 0;
    }

    private static bool Register(ushort usage, uint flags, nint target) =>
        RegisterRawInputDevices([new RAWINPUTDEVICE { UsagePage = GenericDesktop, Usage = usage, Flags = flags, Target = target }], 1, (uint)Marshal.SizeOf<RAWINPUTDEVICE>());

    private nint OnMessage(nint hwnd, uint message, nint wParam, nint lParam)
    {
        switch (message)
        {
            case WM_INPUT:
                Read(lParam);
                return 0;
            case WM_INPUT_DEVICE_CHANGE:
                onDevicesChanged();
                return 0;
            case WM_APP_MOUSE:
                var wants = wParam != 0;
                if (wants != listensToMouse && Register(MouseUsage, wants ? RIDEV_INPUTSINK : RIDEV_REMOVE, wants ? hwnd : 0)) listensToMouse = wants;
                return 0;
            case WM_APP_WAKE:
                return 0;
            default:
                return DefWindowProc(hwnd, message, wParam, lParam);
        }
    }

    private unsafe void Read(nint input)
    {
        fixed (byte* data = buffer)
        {
            var size = (uint)buffer.Length;
            if (GetRawInputData(input, RID_INPUT, (nint)data, ref size, (uint)HeaderSize) == uint.MaxValue) return;
            var header = *(RAWINPUTHEADER*)data;
            var payload = data + HeaderSize;
            if (header.Type == RIM_TYPEKEYBOARD) ReadKey(*(RAWKEYBOARD*)payload, header.Device);
            else if (header.Type == RIM_TYPEMOUSE) ReadMouse(*(RAWMOUSE*)payload, header.Device);
        }
    }

    private void ReadKey(RAWKEYBOARD key, nint device)
    {
        if (key.ExtraInformation == (uint)InputSender.Tag) return;
        if (KeyCodes.FromRaw(key.VKey, key.MakeCode, (key.Flags & RI_KEY_E0) != 0) is not { } code) return;
        onRaw(new RawEvent(RemapInput.Key(code), (key.Flags & RI_KEY_BREAK) == 0, deviceOf(device), device));
    }

    private void ReadMouse(RAWMOUSE mouse, nint device)
    {
        if (mouse.ButtonFlags == 0 || mouse.ExtraInformation == (uint)InputSender.Tag) return;
        foreach (var (down, up, button) in ButtonFlags)
        {
            if ((mouse.ButtonFlags & (down | up)) == 0) continue;
            var number = button < 2 && GetSystemMetrics(SM_SWAPBUTTON) != 0 ? 1 - button : button;
            onRaw(new RawEvent(RemapInput.Button(number), (mouse.ButtonFlags & down) != 0, deviceOf(device), device));
        }
    }
}
