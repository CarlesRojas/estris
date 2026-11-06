using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace Estris.Utilities.KeepAwake;

/// Holds the PC and its display awake. The hold belongs to the thread that asks for it, so one
/// thread lives only to keep it, for as long as Keep Awake is on.
internal sealed class ExecutionHold : IDisposable
{
    private const uint ES_CONTINUOUS = 0x80000000, ES_SYSTEM_REQUIRED = 1, ES_DISPLAY_REQUIRED = 2;

    private readonly AutoResetEvent wake = new(false);
    private volatile bool wantsHold, isDisposed;

    public ExecutionHold() => new Thread(Run) { IsBackground = true, Name = "Keep Awake" }.Start();

    public bool IsHolding
    {
        get => wantsHold;
        set
        {
            if (wantsHold == value) return;
            wantsHold = value;
            wake.Set();
        }
    }

    private void Run()
    {
        while (!isDisposed)
        {
            SetThreadExecutionState(wantsHold ? ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED : ES_CONTINUOUS);
            wake.WaitOne();
        }
        SetThreadExecutionState(ES_CONTINUOUS);
        wake.Dispose();
    }

    public void Dispose()
    {
        isDisposed = true;
        wake.Set();
    }

    [DllImport("kernel32")] private static extern uint SetThreadExecutionState(uint flags);
}

/// Tells when the power source changes, and when the PC or its display wakes, without a window.
/// Windows calls these on a thread of its own.
internal sealed class PowerWatcher : IDisposable
{
    private const uint DEVICE_NOTIFY_CALLBACK = 2, PBT_APMRESUMESUSPEND = 7, PBT_APMRESUMEAUTOMATIC = 0x12, PBT_POWERSETTINGCHANGE = 0x8013;
    private static readonly Guid AcDcPowerSource = new("5d3e9a59-e9d5-4b00-a6bd-ff34ff516548");
    private static readonly Guid ConsoleDisplayState = new("6fe69556-704a-47a0-8f24-c28d936fda47");

    private readonly Action changed, woke;
    private readonly PowerCallback callback;
    private readonly GCHandle pin;
    private nint suspendHandle, sourceHandle, displayHandle;
    /// The first notice only says how it is now.
    private bool? isDisplayOn;

    public PowerWatcher(Action changed, Action woke)
    {
        this.changed = changed;
        this.woke = woke;
        callback = OnNotice;
        pin = GCHandle.Alloc(callback);
        var parameters = new SubscribeParameters { Callback = Marshal.GetFunctionPointerForDelegate(callback) };
        PowerRegisterSuspendResumeNotification(DEVICE_NOTIFY_CALLBACK, ref parameters, out suspendHandle);
        var source = AcDcPowerSource;
        PowerSettingRegisterNotification(ref source, DEVICE_NOTIFY_CALLBACK, ref parameters, out sourceHandle);
        var display = ConsoleDisplayState;
        PowerSettingRegisterNotification(ref display, DEVICE_NOTIFY_CALLBACK, ref parameters, out displayHandle);
    }

    private uint OnNotice(nint context, uint type, nint setting)
    {
        if (type is PBT_APMRESUMESUSPEND or PBT_APMRESUMEAUTOMATIC)
        {
            woke();
        }
        else if (type == PBT_POWERSETTINGCHANGE && setting != 0)
        {
            var notice = Marshal.PtrToStructure<PowerSettingNotice>(setting);
            if (notice.Setting == AcDcPowerSource) changed();
            if (notice.Setting == ConsoleDisplayState)
            {
                var isOn = notice.Data != 0;
                if (isDisplayOn == false && isOn) woke();
                isDisplayOn = isOn;
            }
        }
        return 0;
    }

    public void Dispose()
    {
        PowerUnregisterSuspendResumeNotification(suspendHandle);
        PowerSettingUnregisterNotification(sourceHandle);
        PowerSettingUnregisterNotification(displayHandle);
        pin.Free();
    }

    private delegate uint PowerCallback(nint context, uint type, nint setting);

    [StructLayout(LayoutKind.Sequential)] private struct SubscribeParameters { public nint Callback, Context; }
    [StructLayout(LayoutKind.Sequential)] private struct PowerSettingNotice { public Guid Setting; public uint Length; public uint Data; }

    [DllImport("powrprof")] private static extern uint PowerRegisterSuspendResumeNotification(uint flags, ref SubscribeParameters recipient, out nint handle);
    [DllImport("powrprof")] private static extern uint PowerUnregisterSuspendResumeNotification(nint handle);
    [DllImport("powrprof")] private static extern uint PowerSettingRegisterNotification(ref Guid setting, uint flags, ref SubscribeParameters recipient, out nint handle);
    [DllImport("powrprof")] private static extern uint PowerSettingUnregisterNotification(nint handle);
}

/// Reads and does what Keep Awake needs of the PC.
internal static class PowerSystem
{
    private const uint WM_SYSCOMMAND = 0x112, SMTO_ABORTIFHUNG = 2;
    private const nint SC_SCREENSAVE = 0xF140, SC_MONITORPOWER = 0xF170, MONITOR_OFF = 2;
    private const uint MessageTimeoutMs = 1000;
    private const byte AcOffline = 0;

    public static bool IsOnBattery => GetSystemPowerStatus(out var status) && status.ACLineStatus == AcOffline;

    /// Since the last mouse or keyboard input.
    public static TimeSpan InputIdleTime
    {
        get
        {
            var info = new LASTINPUTINFO { cbSize = (uint)Marshal.SizeOf<LASTINPUTINFO>() };
            if (!GetLastInputInfo(ref info)) return TimeSpan.Zero;
            // Both wrap around after 49 days; the difference doesn't care.
            return TimeSpan.FromMilliseconds(unchecked((uint)Environment.TickCount - info.dwTime));
        }
    }

    /// Whether a screen saver is chosen in Windows's settings.
    public static bool HasScreenSaver
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Control Panel\Desktop");
            return !string.IsNullOrWhiteSpace(key?.GetValue("SCRNSAVE.EXE") as string);
        }
    }

    public static void StartScreenSaver() => SystemCommand(SC_SCREENSAVE, 0);

    public static void TurnDisplayOff() => SystemCommand(SC_MONITORPOWER, MONITOR_OFF);

    /// False when it can't, as PCs with Modern Standby only sleep with the display off.
    public static bool Sleep() => SetSuspendState(false, false, false);

    private static void SystemCommand(nint command, nint argument) =>
        SendMessageTimeout(GetDesktopWindow(), WM_SYSCOMMAND, command, argument, SMTO_ABORTIFHUNG, MessageTimeoutMs, out _);

    [StructLayout(LayoutKind.Sequential)] private struct LASTINPUTINFO { public uint cbSize, dwTime; }
    [StructLayout(LayoutKind.Sequential)] private struct SYSTEM_POWER_STATUS { public byte ACLineStatus, BatteryFlag, BatteryLifePercent, SystemStatusFlag; public int BatteryLifeTime, BatteryFullLifeTime; }

    [DllImport("user32")] private static extern bool GetLastInputInfo(ref LASTINPUTINFO info);
    [DllImport("kernel32")] private static extern bool GetSystemPowerStatus(out SYSTEM_POWER_STATUS status);
    [DllImport("powrprof")] private static extern bool SetSuspendState(bool hibernate, bool force, bool wakeupEventsDisabled);
    [DllImport("user32")] private static extern nint GetDesktopWindow();
    [DllImport("user32", EntryPoint = "SendMessageTimeoutW")] private static extern nint SendMessageTimeout(nint hwnd, uint message, nint wParam, nint lParam, uint flags, uint timeout, out nint result);
}
