using System.Drawing;
using System.Runtime.InteropServices;
using Estris.Core;
using Estris.Ui;
using Estris.Utilities;

namespace Estris.Tray;

/// The notification area icon, Estris's place on Windows as the menu bar is on the Mac. Either
/// click opens the frosted menu.
public sealed partial class TrayIcon : IDisposable
{
    private const uint WM_APP_TRAY = 0x8010, NIM_ADD = 0, NIM_MODIFY = 1, NIM_DELETE = 2, NIM_SETVERSION = 4;
    private const uint NIF_MESSAGE = 1, NIF_ICON = 2, NIF_TIP = 4;
    private const uint NOTIFYICON_VERSION_4 = 4;
    private const uint NIN_SELECT = 0x400, NIN_KEYSELECT = 0x401, WM_CONTEXTMENU = 0x7B, WM_SETTINGCHANGE = 0x1A;
    private static readonly nint HWND_MESSAGE = -3;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NOTIFYICONDATA
    {
        public int cbSize;
        public nint hWnd;
        public uint uID, uFlags, uCallbackMessage;
        public nint hIcon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string szTip;
        public uint dwState, dwStateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string szInfo;
        public uint uVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string szInfoTitle;
        public uint dwInfoFlags;
        public Guid guidItem;
        public nint hBalloonIcon;
    }

    private delegate nint WndProc(nint hwnd, uint message, nint wParam, nint lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WNDCLASS
    {
        public uint style;
        public WndProc lpfnWndProc;
        public int cbClsExtra, cbWndExtra;
        public nint hInstance, hIcon, hCursor, hbrBackground;
        public string? lpszMenuName;
        public string lpszClassName;
    }

    [DllImport("shell32", CharSet = CharSet.Unicode)] private static extern bool Shell_NotifyIcon(uint message, ref NOTIFYICONDATA data);
    [DllImport("user32", CharSet = CharSet.Unicode)] private static extern ushort RegisterClass(ref WNDCLASS wc);
    [DllImport("user32", CharSet = CharSet.Unicode)] private static extern nint CreateWindowEx(uint ex, string cls, string title, uint style, int x, int y, int w, int h, nint parent, nint menu, nint instance, nint param);
    [DllImport("user32", CharSet = CharSet.Unicode)] private static extern nint DefWindowProc(nint hwnd, uint message, nint wParam, nint lParam);
    [DllImport("user32", CharSet = CharSet.Unicode)] private static extern uint RegisterWindowMessage(string name);
    [DllImport("user32")] private static extern bool DestroyWindow(nint hwnd);
    [DllImport("user32")] private static extern bool DestroyIcon(nint icon);

    private readonly TraySettings settings;
    private readonly IReadOnlyList<IUtility> utilities;
    private readonly WndProc proc;
    private readonly uint taskbarCreated = RegisterWindowMessage("TaskbarCreated");
    private readonly nint window;
    private nint icon;
    private TrayMenu? menu;

    public TrayIcon(TraySettings settings, IReadOnlyList<IUtility> utilities)
    {
        this.settings = settings;
        this.utilities = utilities;
        proc = OnMessage;
        var instance = Native.GetModuleHandle(null);
        var cls = new WNDCLASS { lpfnWndProc = proc, hInstance = instance, lpszClassName = "EstrisTray" };
        RegisterClass(ref cls);
        window = CreateWindowEx(0, cls.lpszClassName, "", 0, 0, 0, 0, 0, HWND_MESSAGE, 0, instance, 0);

        settings.Icon.Changed += Refresh;
        settings.UsesCustomColor.Changed += Refresh;
        settings.CustomColor.Changed += Refresh;
    }

    private NOTIFYICONDATA Data(uint flags) => new()
    {
        cbSize = Marshal.SizeOf<NOTIFYICONDATA>(),
        hWnd = window,
        uID = 1,
        uFlags = flags,
        uCallbackMessage = WM_APP_TRAY,
        hIcon = icon,
        szTip = "Estris",
        szInfo = "",
        szInfoTitle = "",
    };

    public void Show()
    {
        RenderIcon();
        var data = Data(NIF_MESSAGE | NIF_ICON | NIF_TIP);
        Shell_NotifyIcon(NIM_ADD, ref data);
        data.uVersion = NOTIFYICON_VERSION_4;
        Shell_NotifyIcon(NIM_SETVERSION, ref data);
        TrayPromotion.PromoteWhenListed();
    }

    private void RenderIcon()
    {
        if (icon != 0) DestroyIcon(icon);
        var color = settings.UsesCustomColor.Value
            ? ColorTranslator.FromHtml(settings.CustomColor.Value)
            : TrayIcons.TaskbarIsLight() ? Color.Black : Color.White;
        var size = (int)Math.Round(16 * Native.GetDpiForSystem() / 96.0);
        icon = TrayIcons.Render(settings.Icon.Value, color, size);
    }

    private void Refresh()
    {
        RenderIcon();
        var data = Data(NIF_ICON);
        Shell_NotifyIcon(NIM_MODIFY, ref data);
    }

    private nint OnMessage(nint hwnd, uint message, nint wParam, nint lParam)
    {
        if (message == WM_APP_TRAY)
        {
            // With version 4 the event is in the low word, and the pointer's place in wParam.
            var trayEvent = (uint)(lParam & 0xFFFF);
            if (trayEvent is NIN_SELECT or NIN_KEYSELECT or WM_CONTEXTMENU) ToggleMenu();
            return 0;
        }
        if (message == taskbarCreated) Show();
        else if (message == WM_SETTINGCHANGE && !settings.UsesCustomColor.Value) Refresh();
        return DefWindowProc(hwnd, message, wParam, lParam);
    }

    private void ToggleMenu()
    {
        menu ??= new TrayMenu(settings, utilities);
        menu.Toggle();
    }

    public void Dispose()
    {
        var data = Data(0);
        Shell_NotifyIcon(NIM_DELETE, ref data);
        if (icon != 0) DestroyIcon(icon);
        DestroyWindow(window);
    }
}
