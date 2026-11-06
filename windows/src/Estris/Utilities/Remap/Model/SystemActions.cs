using System.Diagnostics;
using System.Management;
using System.Runtime.InteropServices;
using Estris.Core;
using static Estris.Core.Loc;

namespace Estris.Utilities.Remap;

/// What each system action is called and does on Windows.
public static partial class SystemActions
{
    private const int Ctrl = 0xA2, Shift = 0xA0, Win = 0x5B, Tab = 0x09, Period = 0xBE, Escape = 0x1B, Left = 0x25, Right = 0x27, PrintScreen = 0x2C;
    private const int VkD = 0x44, VkS = 0x53;
    private const int VolumeUpKey = 0xAF, VolumeDownKey = 0xAE, MuteKey = 0xAD, PlayPauseKey = 0xB3, NextKey = 0xB0, PreviousKey = 0xB1;
    private const uint WM_SYSCOMMAND = 0x112;
    private const nint SC_MONITORPOWER = 0xF170, MonitorOff = 2, HWND_BROADCAST = 0xFFFF;
    /// A press right after asking would wake the display at once, its release included.
    private static readonly TimeSpan SleepDelay = TimeSpan.FromMilliseconds(500);

    public static readonly (string Title, SystemAction[] Actions)[] Sections =
    [
        (T("Task View and Desktops"), [SystemAction.TaskView, SystemAction.ShowDesktop, SystemAction.StartMenu, SystemAction.NextDesktop, SystemAction.PreviousDesktop]),
        (T("Media"), [SystemAction.VolumeUp, SystemAction.VolumeDown, SystemAction.Mute, SystemAction.PlayPause, SystemAction.NextTrack, SystemAction.PreviousTrack]),
        (T("Display"), [SystemAction.BrightnessUp, SystemAction.BrightnessDown, SystemAction.SleepDisplay]),
        (T("System"), [SystemAction.LockScreen, SystemAction.Search, SystemAction.Screenshot, SystemAction.ScreenshotScreen, SystemAction.EmojiPanel, SystemAction.TaskManager]),
    ];

    public static string Title(SystemAction action) => action switch
    {
        SystemAction.TaskView => T("Task View"),
        SystemAction.ShowDesktop => T("Show Desktop"),
        SystemAction.StartMenu => T("Start Menu"),
        SystemAction.NextDesktop => T("Next Desktop"),
        SystemAction.PreviousDesktop => T("Previous Desktop"),
        SystemAction.VolumeUp => T("Volume Up"),
        SystemAction.VolumeDown => T("Volume Down"),
        SystemAction.Mute => T("Mute"),
        SystemAction.PlayPause => T("Play or Pause"),
        SystemAction.NextTrack => T("Next Track"),
        SystemAction.PreviousTrack => T("Previous Track"),
        SystemAction.BrightnessUp => T("Brightness Up"),
        SystemAction.BrightnessDown => T("Brightness Down"),
        SystemAction.SleepDisplay => T("Sleep Display"),
        SystemAction.LockScreen => T("Lock Screen"),
        SystemAction.Search => T("Search"),
        SystemAction.Screenshot => T("Screenshot Tools"),
        SystemAction.ScreenshotScreen => T("Screenshot of Screen"),
        SystemAction.EmojiPanel => T("Emoji and Symbols"),
        _ => T("Task Manager"),
    };

    [LibraryImport("user32", EntryPoint = "PostMessageW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool PostMessage(nint hwnd, uint message, nint wParam, nint lParam);

    [LibraryImport("user32")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool LockWorkStation();

    /// Runs it. Quick actions happen right here, so they keep their place among the keys sent.
    public static void Perform(SystemAction action, AppLog log)
    {
        switch (action)
        {
            case SystemAction.TaskView: InputSender.Chord(Win, Tab); break;
            case SystemAction.ShowDesktop: InputSender.Chord(Win, VkD); break;
            case SystemAction.StartMenu: InputSender.Chord(Win); break;
            case SystemAction.NextDesktop: InputSender.Chord(Ctrl, Win, Right); break;
            case SystemAction.PreviousDesktop: InputSender.Chord(Ctrl, Win, Left); break;
            case SystemAction.VolumeUp: InputSender.Chord(VolumeUpKey); break;
            case SystemAction.VolumeDown: InputSender.Chord(VolumeDownKey); break;
            case SystemAction.Mute: InputSender.Chord(MuteKey); break;
            case SystemAction.PlayPause: InputSender.Chord(PlayPauseKey); break;
            case SystemAction.NextTrack: InputSender.Chord(NextKey); break;
            case SystemAction.PreviousTrack: InputSender.Chord(PreviousKey); break;
            case SystemAction.BrightnessUp: _ = Task.Run(() => Brightness.Change(Brightness.Step, log)); break;
            case SystemAction.BrightnessDown: _ = Task.Run(() => Brightness.Change(-Brightness.Step, log)); break;
            case SystemAction.SleepDisplay: _ = SleepDisplay(); break;
            case SystemAction.LockScreen: LockWorkStation(); break;
            case SystemAction.Search: InputSender.Chord(Win, VkS); break;
            case SystemAction.Screenshot: InputSender.Chord(Win, Shift, VkS); break;
            case SystemAction.ScreenshotScreen: InputSender.Chord(Win, PrintScreen); break;
            case SystemAction.EmojiPanel: InputSender.Chord(Win, Period); break;
            case SystemAction.TaskManager: InputSender.Chord(Ctrl, Shift, Escape); break;
        }
    }

    private static async Task SleepDisplay()
    {
        await Task.Delay(SleepDelay);
        PostMessage(HWND_BROADCAST, WM_SYSCOMMAND, SC_MONITORPOWER, MonitorOff);
    }
}

/// Display brightness: WMI for built-in screens, DDC/CI for monitors that take it.
public static partial class Brightness
{
    public const int Step = 10;
    private const string WmiScope = @"root\wmi";
    private const int MonitorNameLength = 128;
    private static int isChanging;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct PHYSICAL_MONITOR
    {
        public nint Handle;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = MonitorNameLength)] public string Description;
    }

    private delegate bool MonitorEnum(nint monitor, nint dc, nint rect, nint data);

    [DllImport("user32")]
    private static extern bool EnumDisplayMonitors(nint dc, nint clip, MonitorEnum callback, nint data);

    [DllImport("dxva2", SetLastError = true)]
    private static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(nint monitor, out uint count);

    [DllImport("dxva2", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool GetPhysicalMonitorsFromHMONITOR(nint monitor, uint count, [Out] PHYSICAL_MONITOR[] monitors);

    [DllImport("dxva2")]
    private static extern bool DestroyPhysicalMonitors(uint count, PHYSICAL_MONITOR[] monitors);

    [DllImport("dxva2", SetLastError = true)]
    private static extern bool GetMonitorBrightness(nint monitor, out uint minimum, out uint current, out uint maximum);

    [DllImport("dxva2", SetLastError = true)]
    private static extern bool SetMonitorBrightness(nint monitor, uint brightness);

    /// Whether at least one display here can change its brightness. Slow: not for the UI thread.
    public static bool IsSupported()
    {
        try
        {
            using var search = new ManagementObjectSearcher(WmiScope, "SELECT * FROM WmiMonitorBrightnessMethods");
            using var found = search.Get();
            if (found.Count > 0) return true;
        }
        catch (ManagementException) { /* No such class on PCs without a built-in screen. */ }

        var isSupported = false;
        ForEachMonitor(monitor => isSupported |= GetMonitorBrightness(monitor, out _, out _, out _));
        return isSupported;
    }

    /// Changes every display that can by that many percent. Presses while one is under way are
    /// dropped: DDC/CI is slow, and they would pile up when held.
    public static void Change(int percent, AppLog log)
    {
        if (Interlocked.Exchange(ref isChanging, 1) == 1) return;
        try
        {
            var changed = ChangeBuiltIn(percent, log);
            ForEachMonitor(monitor =>
            {
                if (!GetMonitorBrightness(monitor, out var minimum, out var current, out var maximum) || maximum <= minimum) return;
                var step = (int)(maximum - minimum) * percent / 100;
                changed |= SetMonitorBrightness(monitor, (uint)Math.Clamp((int)current + step, (int)minimum, (int)maximum));
            });
            if (!changed) log.Add("Remap", "brightness: no display here supports changing it");
        }
        finally { Interlocked.Exchange(ref isChanging, 0); }
    }

    private static bool ChangeBuiltIn(int percent, AppLog log)
    {
        try
        {
            using var levels = new ManagementObjectSearcher(WmiScope, "SELECT CurrentBrightness FROM WmiMonitorBrightness");
            using var current = levels.Get();
            var level = current.Cast<ManagementObject>().Select(o => Convert.ToInt32(o["CurrentBrightness"])).DefaultIfEmpty(-1).First();
            if (level < 0) return false;

            using var search = new ManagementObjectSearcher(WmiScope, "SELECT * FROM WmiMonitorBrightnessMethods");
            using var found = search.Get();
            foreach (var display in found.Cast<ManagementObject>())
                display.InvokeMethod("WmiSetBrightness", [1u, (byte)Math.Clamp(level + percent, 0, 100)]);
            return found.Count > 0;
        }
        catch (ManagementException e)
        {
            log.Add("Remap", $"brightness: {e.Message}");
            return false;
        }
    }

    private static void ForEachMonitor(Action<nint> action)
    {
        var monitors = new List<nint>();
        EnumDisplayMonitors(0, 0, (monitor, _, _, _) => { monitors.Add(monitor); return true; }, 0);
        foreach (var monitor in monitors)
        {
            if (!GetNumberOfPhysicalMonitorsFromHMONITOR(monitor, out var count) || count == 0) continue;
            var physical = new PHYSICAL_MONITOR[count];
            if (!GetPhysicalMonitorsFromHMONITOR(monitor, count, physical)) continue;
            foreach (var one in physical) action(one.Handle);
            DestroyPhysicalMonitors(count, physical);
        }
    }
}
