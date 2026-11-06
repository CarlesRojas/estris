using System.Diagnostics;
using System.Runtime.InteropServices;
using Estris.Core;
using Estris.Utilities.WindowSnapping;
using Microsoft.Win32;
using static Estris.Core.Native;
using static Estris.Utilities.WindowSnapping.WindowNative;

namespace Estris.Utilities.FocusFollowsMouse;

/// Counts how long the pointer stays over the same window while moving slowly (or resting), and
/// focuses it once that reaches the delay; moving fast or entering another window starts the
/// count again, so windows crossed on the way aren't brought forward. The mouse hook only
/// notes the pointer: all the work is on a thread of its own, which also does the raising.
public sealed partial class HoverFocus(FocusFollowsMouseSettings settings, AppLog log)
{
    private const string LogSource = "Focus Follows Mouse";
    /// Pause between looks at the pointer, however often it reports moving.
    private const int MoveInterval = 8;
    /// Gap between lists of the windows on screen, while the pointer moves.
    private const double WindowCheckInterval = 0.2;
    /// How much of the smoothed speed is the last move's.
    private const double SpeedSmoothing = 0.4;
    /// How long after hovering focused an app its activation still counts as caused by that.
    private const double HoverActivationGrace = 1;
    /// Windows coming on screen for this long after switching desktops aren't new.
    private const double DesktopSwitchGrace = 1;
    /// Windows of the app in front floating above others, smaller than this in logical pixels,
    /// aren't panels; nor, for popups, these.
    private const int PanelWidth = 100, PanelHeight = 60, PopupSide = 40;
    private const int VK_LBUTTON = 1, VK_RBUTTON = 2, VK_MBUTTON = 4, VK_XBUTTON1 = 5, VK_XBUTTON2 = 6;
    private const string VirtualDesktopKey = @"Software\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops";

    /// Modifier keys, either side, and the Windows keys.
    private static readonly int[] HeldKeys = [0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0x5B, 0x5C, VK_LBUTTON, VK_RBUTTON, VK_MBUTTON, VK_XBUTTON1, VK_XBUTTON2];

    private static readonly uint OwnProcess = (uint)Environment.ProcessId;
    private readonly Stopwatch clock = Stopwatch.StartNew();
    private WinEventHook? foregroundHook;
    private Thread? thread;
    private volatile bool isRunning;
    private readonly AutoResetEvent moved = new(false);
    private long latestPoint;

    /// The app last brought forward by hovering, and when, so its activation isn't taken for
    /// the user switching to it.
    private (uint Process, double Time)? focusedByHover;
    /// The app the user last switched to (clicking it, Alt+Tab, the taskbar), and when.
    private (uint Process, double Time)? switchedTo;
    private uint lastFrontProcess;
    private readonly object activationGate = new();

    /// Windows on screen, and when each was first seen: a new one (a dialog, a popup like a
    /// browser's screen sharing picker) is kept in front for a while, like a new app.
    private Dictionary<nint, double> windowsSeen = [];
    private double windowsCheckedAt;
    /// Until when windows appearing count as already there: after switching desktops, the
    /// windows coming on screen aren't new.
    private double windowsOldUntil;
    private string? currentDesktop;

    private POINT? lastPoint;
    private double lastTime;
    /// The pointer's speed in logical pixels a second, smoothed over the last few moves.
    private double speed;
    /// The window under the pointer, and since when it has been there moving slowly.
    private TopWindow candidate;
    private double dwellStart;
    /// Whether the candidate was already handled, so slow moves over it don't repeat the work.
    private bool isHandled;
    /// When the count finishes if the pointer stops before then, as no more moves arrive.
    private double? pendingAt;

    private double Now => clock.Elapsed.TotalSeconds;

    public void Start()
    {
        if (isRunning) return;
        isRunning = true;
        windowsSeen = [];
        windowsOldUntil = Now;
        pendingAt = null;
        candidate = default;
        lastPoint = null;
        speed = 0;
        lastFrontProcess = TopWindow.Foreground.ProcessId;
        CheckWindows(Now);
        foregroundHook = new WinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, OnForeground, LogSource);
        InputHooks.Subscribe(OnMouse);
        thread = new Thread(Run) { IsBackground = true, Name = LogSource };
        thread.Start();
    }

    public void Stop()
    {
        if (!isRunning) return;
        isRunning = false;
        InputHooks.Unsubscribe(OnMouse);
        foregroundHook?.Dispose();
        foregroundHook = null;
        moved.Set();
    }

    /// On the hook thread: only notes where the pointer is.
    private void OnMouse(MouseEvent e)
    {
        if (e.Action != MouseAction.Move || e.IsOwn) return;
        Interlocked.Exchange(ref latestPoint, ((long)e.X << 32) | (uint)e.Y);
        moved.Set();
    }

    /// An app coming to the front that hovering didn't bring forward: the user switched to it.
    private void OnForeground(uint type, nint hwnd, int idObject, int idChild)
    {
        var process = new TopWindow(hwnd).ProcessId;
        lock (activationGate)
        {
            if (process == lastFrontProcess) return;
            lastFrontProcess = process;
            if (focusedByHover is { } hover && hover.Process == process && Now - hover.Time < HoverActivationGrace) return;
            switchedTo = (process, Now);
        }
    }

    private void Run()
    {
        while (true)
        {
            var wait = pendingAt is { } at ? Math.Max((int)Math.Ceiling((at - Now) * 1000), 0) : Timeout.Infinite;
            var hasMoved = moved.WaitOne(wait);
            if (!isRunning) return;
            try
            {
                if (hasMoved)
                {
                    var point = Interlocked.Read(ref latestPoint);
                    PointerMoved(new POINT { X = (int)(point >> 32), Y = (int)point }, Now);
                    Thread.Sleep(MoveInterval);
                }
                else if (pendingAt is not null)
                {
                    pendingAt = null;
                    speed = 0;
                    if (!isHandled) FocusWindowUnderPointer();
                }
            }
            catch (Exception error) { log.Add(LogSource, $"Failed: {error.Message}"); }
        }
    }

    private void PointerMoved(POINT point, double time)
    {
        if (lastPoint is { } last && time > lastTime)
        {
            var scale = Screen.At(point).Scale;
            var distance = Math.Sqrt(Math.Pow(point.X - last.X, 2) + Math.Pow(point.Y - last.Y, 2)) / scale;
            speed = speed * (1 - SpeedSmoothing) + distance / (time - lastTime) * SpeedSmoothing;
        }
        lastPoint = point;
        lastTime = time;
        if (time - windowsCheckedAt >= WindowCheckInterval) CheckWindows(time);

        var window = TopWindow.At(point);
        if (window != candidate)
        {
            candidate = window;
            dwellStart = time;
            isHandled = false;
        }
        if (speed > settings.PassThroughSpeed.Value) dwellStart = time;
        pendingAt = null;
        if (isHandled) return;

        var delay = settings.Delay.Value / 1000.0;
        var waited = time - dwellStart;
        if (waited >= delay) FocusWindowUnderPointer();
        else pendingAt = time + delay - waited;
    }

    private void FocusWindowUnderPointer()
    {
        // Dragging, clicking, or holding a modifier for a shortcut; tried again on the next move.
        if (HeldKeys.Any(Hotkeys.IsHeld)) return;
        GetCursorPos(out var point);
        var target = TopWindow.At(point);
        var targetProcess = target.ProcessId;
        var front = TopWindow.Foreground;
        var frontProcess = front.ProcessId;

        // A menu or the shell's panels are open; going to another window would close them.
        if (IsBusy(front)) return;
        if (settings.KeepsNewAppsInFront.Value)
        {
            var keep = settings.NewAppSeconds.Value;
            // An app that just opened, or that the user just switched to, is often away from
            // the pointer: it keeps the focus for a while. Tried again on the next move.
            lock (activationGate)
            {
                if (targetProcess != frontProcess && switchedTo is { } switched && switched.Process == frontProcess && Now - switched.Time < keep) return;
            }
            // A window that just appeared, when the pointer isn't on it.
            CheckWindows(Now);
            var recent = Now - keep;
            foreach (var (hwnd, seen) in windowsSeen)
                if (seen > recent && hwnd != target.Hwnd) return;
        }
        isHandled = true;

        // The window a click would reach; nothing to do over the taskbar, the desktop or
        // anything else that isn't a normal window, or over one a dialog is blocking.
        if (!target.IsNormal || !IsWindowEnabled(target.Hwnd) || target == front) return;
        if (WindowApp(target.Hwnd) is { } app && settings.ExcludedApps.Value.Contains(app)) return;
        // A dialog or a panel keeps the focus until it is closed.
        if (frontProcess == targetProcess && IsPanel(front)) return;
        // Another app in front with a panel open (one that doesn't cover the screen, so the
        // windows behind are easy to cross): it keeps the focus, or the panel would end up
        // behind the window raised.
        if (frontProcess != targetProcess && frontProcess != OwnProcess && ShowsPanel(front)) return;
        if (IsHungAppWindow(target.Hwnd)) return;

        lock (activationGate) focusedByHover = (targetProcess, Now);
        if (Raise(target)) log.Add(LogSource, $"focused {WindowApp(target.Hwnd) ?? target.ClassName}: {target.Title}");
        else log.Add(LogSource, $"couldn't focus {WindowApp(target.Hwnd) ?? target.ClassName}");
    }

    /// Brings a window forward. Windows refuses a process that didn't get the last input, so
    /// if a plain request isn't enough, an input of its own that does nothing makes that Estris.
    private static bool Raise(TopWindow window)
    {
        if (SetForegroundWindow(window.Hwnd) && GetForegroundWindow() == window.Hwnd) { App.Shared.Log.Add("DBG", "plain worked"); return true; }
        App.Shared.Log.Add("DBG", "plain refused");
        InputSender.Mouse(0);
        SetForegroundWindow(window.Hwnd);
        App.Shared.Log.Add("DBG", $"after input fg ok={GetForegroundWindow() == window.Hwnd}");
        return GetForegroundWindow() == window.Hwnd;
    }

    // Windows

    /// Notes the normal windows on screen that weren't there before, and forgets those gone.
    private void CheckWindows(double time)
    {
        windowsCheckedAt = time;
        var desktop = CurrentDesktop();
        if (desktop != currentDesktop)
        {
            // Switching desktops moves windows under a still pointer; that isn't the user
            // picking one.
            if (currentDesktop is not null)
            {
                pendingAt = null;
                candidate = default;
                windowsOldUntil = time + DesktopSwitchGrace;
            }
            currentDesktop = desktop;
        }
        var isOld = time <= windowsOldUntil;
        var seen = new Dictionary<nint, double>();
        foreach (var window in TopWindow.All())
        {
            if (!window.IsNormal || window.ProcessId == OwnProcess) continue;
            seen[window.Hwnd] = windowsSeen.TryGetValue(window.Hwnd, out var first) ? first : isOld ? double.NegativeInfinity : time;
        }
        windowsSeen = seen;
    }

    /// Which virtual desktop is showing, as Windows keeps it for Task View.
    private static string? CurrentDesktop()
    {
        using var key = Registry.CurrentUser.OpenSubKey(VirtualDesktopKey);
        return key?.GetValue("CurrentVirtualDesktop") is byte[] id ? Convert.ToHexString(id) : null;
    }

    /// Whether something that closes when focus moves is open: a menu in the app in front, or a
    /// part of the shell such as Start, Alt+Tab or the taskbar's panels.
    private static bool IsBusy(TopWindow front)
    {
        var info = new GUITHREADINFO { cbSize = Marshal.SizeOf<GUITHREADINFO>() };
        if (GetGUIThreadInfo(front.ThreadId, ref info) && (info.flags & (GUI_INMENUMODE | GUI_POPUPMENUMODE | GUI_SYSTEMMENUMODE | GUI_INMOVESIZE)) != 0) return true;
        var className = front.ClassName;
        if (front.IsShell && className is not ("Progman" or "WorkerW" or "Shell_TrayWnd" or "Shell_SecondaryTrayWnd")) return true;
        return HasOpenPopup(front);
    }

    /// Menus and flyouts apps draw themselves are borderless windows, owned or of the same
    /// thread as the window in front.
    private static bool HasOpenPopup(TopWindow front)
    {
        var (process, scale) = (front.ProcessId, Screen.ScaleOf(MonitorFromWindow(front.Hwnd, MONITOR_DEFAULTTONEAREST)));
        foreach (var window in TopWindow.All())
        {
            if (window == front || window.ProcessId != process || !window.IsVisible || window.Cloak != 0) continue;
            var style = window.Style;
            if ((style & WS_POPUP) == 0 || (style & (WS_THICKFRAME | WS_CAPTION)) != 0 || !window.IsOwned) continue;
            if ((window.ExStyle & WS_EX_TRANSPARENT) != 0 || window.ClassName.Contains("tooltip", StringComparison.OrdinalIgnoreCase)) continue;
            if (window.Frame is { } frame && frame.Width >= PopupSide * scale && frame.Height >= PopupSide * scale) return true;
        }
        return false;
    }

    /// Dialogs and floating windows: owned by another window, or dialogs by class or frame.
    private static bool IsPanel(TopWindow window) =>
        window.IsOwned || window.ClassName == "#32770" || (window.ExStyle & WS_EX_DLGMODALFRAME) != 0;

    /// Whether the window in front is a panel, or its app has a window on screen floating above
    /// normal ones.
    private static bool ShowsPanel(TopWindow front)
    {
        if (IsPanel(front)) return true;
        var (process, scale) = (front.ProcessId, Screen.ScaleOf(MonitorFromWindow(front.Hwnd, MONITOR_DEFAULTTONEAREST)));
        foreach (var window in TopWindow.All())
        {
            if (window.ProcessId != process || !window.IsTopmost || !window.IsVisible || window.Cloak != 0 || window.IsMinimized) continue;
            if ((window.ExStyle & WS_EX_TRANSPARENT) != 0) continue;
            if (window.Frame is { } frame && frame.Width >= PanelWidth * scale && frame.Height >= PanelHeight * scale) return true;
        }
        return false;
    }
}
