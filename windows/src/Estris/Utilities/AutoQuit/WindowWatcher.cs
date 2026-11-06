using System.Diagnostics;
using Estris.Core;
using Estris.Utilities.WindowSnapping;
using static Estris.Core.Native;
using static Estris.Utilities.WindowSnapping.WindowNative;

namespace Estris.Utilities.AutoQuit;

/// Quits an app once its last window has closed, reacting to window events instead of polling.
///
/// Every app's top-level windows are tracked, per process, as they are shown. When a tracked
/// window is destroyed, the app's other windows are looked at right away; if none are left, the
/// app is asked to quit after the chosen delay. A polite quit: it is sent WM_CLOSE on its
/// hidden windows, then WM_QUIT on its window threads, and never terminated, as it may have
/// work to save. One that won't go is left running and logged.
///
/// Apps also close windows on their own to open another, so the chosen delay applies only when
/// the person closed the window: its close button, a menu's Close, Alt+F4, Ctrl+W, or the
/// taskbar. Any other close waits longer for a new window first. A window that is hidden rather
/// than destroyed counts as closed only when the person closed it (apps that keep running in
/// the tray); apps hide windows for all sorts of reasons of their own.
///
/// Left alone: apps never seen with a window, the shell, Windows's own programs and excluded
/// apps. Minimized windows and windows on other virtual desktops still count as windows.
public sealed class WindowWatcher(AutoQuitSettings settings, AppLog log)
{
    private const string LogSource = "Auto Quit";
    /// How long an app that closed its last window on its own is given to open another.
    private const double AppCloseDelay = 10;
    /// How long before (or a little after) a window closes the person's request to close it
    /// counts; a dialog asking to save can stand in between.
    private const double CloseRequestBefore = 0.5, CloseRequestAfter = 3;
    /// How long an app gets to leave after WM_CLOSE, then after WM_QUIT.
    private const double CloseGrace = 1.5, QuitGrace = 5;
    /// Longest a window may take to say what's under a click.
    private const uint HitTestTimeout = 100;
    /// Where the close button is on windows drawing their own title bar, which often don't
    /// tell, from the top right corner, in logical pixels.
    private const int CloseButtonWidth = 56, CloseButtonHeight = 44;
    /// Smaller windows (helpers) don't count as an app's window.
    private const int MinimumWindowSide = 80;
    private const int VK_F4 = 0x73, VK_W = 0x57, VK_LCONTROL = 0xA2, VK_RCONTROL = 0xA3, VK_LMENU = 0xA4, VK_RMENU = 0xA5;

    /// A running app seen with a window. Path tells it from a later process with the same id.
    private sealed class TrackedApp(string path)
    {
        public string Path { get; } = path;
        public string Name => System.IO.Path.GetFileName(Path);
        /// Last time one of its windows closed, and whether by hiding.
        public DateTime LastClose { get; set; }
    }

    private WinEventHook? hook;
    /// Windows being watched, with their process. The hook thread reads it too.
    private readonly Dictionary<nint, uint> windows = [];
    private readonly Dictionary<uint, TrackedApp> apps = [];
    /// Last time the person asked each app to close a window.
    private readonly Dictionary<uint, DateTime> closeRequests = [];
    /// Last click on the shell, where a window of any app can be closed.
    private DateTime lastShellClick;
    private bool isRunning;

    public void Start()
    {
        if (isRunning) return;
        isRunning = true;
        foreach (var window in TopWindow.All()) Track(window);
        hook = new WinEventHook(EVENT_OBJECT_DESTROY, EVENT_OBJECT_HIDE, OnEvent, LogSource);
        InputHooks.Subscribe(OnKey);
        InputHooks.Subscribe(OnMouse);
        log.Add(LogSource, $"started, watching {apps.Count} apps");
    }

    public void Stop()
    {
        if (!isRunning) return;
        isRunning = false;
        log.Add(LogSource, "stopped");
        hook?.Dispose();
        hook = null;
        InputHooks.Unsubscribe(OnKey);
        InputHooks.Unsubscribe(OnMouse);
        lock (windows)
        {
            windows.Clear();
            closeRequests.Clear();
        }
        apps.Clear();
    }

    // Close requests

    /// Notes Alt+F4, Ctrl+F4 and Ctrl+W in the app in front. On the hook thread.
    private void OnKey(KeyEvent e)
    {
        if (!e.IsDown || e.IsOwn || e.Vk is not (VK_F4 or VK_W)) return;
        var ctrl = Hotkeys.IsHeld(VK_LCONTROL) || Hotkeys.IsHeld(VK_RCONTROL);
        var alt = Hotkeys.IsHeld(VK_LMENU) || Hotkeys.IsHeld(VK_RMENU);
        if (e.Vk == VK_F4 ? ctrl || alt : ctrl && !alt) NoteCloseRequest(TopWindow.Foreground.ProcessId, DateTime.Now);
    }

    /// Notes clicks, looked at off the hook thread as asking a window what's there can block.
    private void OnMouse(MouseEvent e)
    {
        if (e.Action != MouseAction.LeftDown || e.IsOwn) return;
        var (point, time) = (new POINT { X = e.X, Y = e.Y }, DateTime.Now);
        ThreadPool.QueueUserWorkItem(_ => NoteClick(point, time));
    }

    /// A click on a close button, in a menu (it may be a Close item) or on the shell (the
    /// taskbar's Close window, its thumbnails' close button, Alt+Tab's).
    private void NoteClick(POINT point, DateTime time)
    {
        var window = TopWindow.At(point);
        if (window.Hwnd == 0) return;
        if (window.ClassName == "#32768")
        {
            NoteCloseRequest(window.ProcessId, time);
            return;
        }
        if (window.IsShell)
        {
            lock (windows) lastShellClick = time;
            return;
        }
        var isCloseButton = HitTest(window.Hwnd, point.X, point.Y, HitTestTimeout) == HTCLOSE || IsInCloseCorner(window, point);
        if (isCloseButton) NoteCloseRequest(window.ProcessId, time);
    }

    private static bool IsInCloseCorner(TopWindow window, POINT point)
    {
        if (window.Frame is not { } frame) return false;
        var scale = Screen.ScaleOf(MonitorFromWindow(window.Hwnd, MONITOR_DEFAULTTONEAREST));
        return point.X >= frame.Right - CloseButtonWidth * scale && point.X < frame.Right
            && point.Y >= frame.Top && point.Y < frame.Top + CloseButtonHeight * scale;
    }

    private void NoteCloseRequest(uint process, DateTime time)
    {
        lock (windows) closeRequests[process] = time;
    }

    /// Whether the app's window closed because the person asked it to.
    private bool ClosedByPerson(uint process, DateTime closed)
    {
        bool Counts(DateTime request)
        {
            var after = (closed - request).TotalSeconds;
            return after >= -CloseRequestBefore && after <= CloseRequestAfter;
        }
        lock (windows)
            return Counts(lastShellClick) || (closeRequests.TryGetValue(process, out var request) && Counts(request));
    }

    // Windows

    private void OnEvent(uint type, nint hwnd, int idObject, int idChild)
    {
        if (idObject != OBJID_WINDOW || idChild != 0) return;
        if (type == EVENT_OBJECT_SHOW)
        {
            if (GetAncestor(hwnd, GA_PARENT) != GetDesktopWindow()) return;
            App.Ui.TryEnqueue(() => { if (isRunning) Track(new TopWindow(hwnd)); });
            return;
        }
        lock (windows)
            if (!windows.ContainsKey(hwnd)) return;
        App.Ui.TryEnqueue(() => { if (isRunning) WindowGone(hwnd, type == EVENT_OBJECT_HIDE); });
    }

    /// Starts watching a window if it is an app's, which notes the app has had windows.
    private void Track(TopWindow window)
    {
        if (!CountsAsWindow(window)) return;
        var process = window.ProcessId;
        lock (windows)
            if (windows.ContainsKey(window.Hwnd)) return;
        if (process == (uint)Environment.ProcessId || ProcessPath(process) is not { } path || AutoQuitSettings.IsAlwaysKept(path)) return;
        lock (windows) windows[window.Hwnd] = process;
        if (apps.TryGetValue(process, out var known) && known.Path == path) return;
        apps[process] = new TrackedApp(path);
        log.Add(LogSource, $"{apps[process].Name}: has a window");
    }

    /// An app's window, minimized and on other virtual desktops too.
    private static bool CountsAsWindow(TopWindow window)
    {
        if (!window.Exists || !window.IsVisible || window.IsOwned || !window.IsAppWindow) return false;
        if ((window.Cloak & DWM_CLOAKED_APP) != 0) return false;
        if (window.IsMinimized) return true;
        if (window.Frame is not { } frame) return false;
        var scale = Screen.ScaleOf(MonitorFromWindow(window.Hwnd, MONITOR_DEFAULTTONEAREST));
        return frame.Width >= MinimumWindowSide * scale && frame.Height >= MinimumWindowSide * scale;
    }

    private static int WindowCount(uint process) =>
        TopWindow.All().Count(window => window.ProcessId == process && CountsAsWindow(window));

    private void WindowGone(nint hwnd, bool wasHidden)
    {
        uint process;
        lock (windows)
        {
            if (!windows.Remove(hwnd, out process)) return;
        }
        if (!apps.TryGetValue(process, out var app)) return;
        var closed = DateTime.Now;
        app.LastClose = closed;
        log.Add(LogSource, $"{app.Name}: a window {(wasHidden ? "was hidden" : "closed")}");
        if (settings.KeepsRunning(app.Path))
        {
            log.Add(LogSource, $"{app.Name}: excluded");
            return;
        }
        var count = WindowCount(process);
        if (count > 0)
        {
            log.Add(LogSource, $"{app.Name}: still has {count} window(s)");
            return;
        }
        After(settings.DelaySeconds, () => Confirm(process, app, closed, wasHidden));
    }

    /// With the chosen delay over, quits when the person closed the window; otherwise gives
    /// the app time to open another one first, looking once more before quitting.
    private void Confirm(uint process, TrackedApp app, DateTime closed, bool wasHidden)
    {
        if (!IsStillDue(process, app, closed)) return;
        if (WindowCount(process) > 0)
        {
            log.Add(LogSource, $"{app.Name}: a window came back, left running");
            return;
        }
        if (ClosedByPerson(process, closed))
        {
            Quit(process, app);
            return;
        }
        if (wasHidden)
        {
            log.Add(LogSource, $"{app.Name}: hid its window on its own, left running");
            return;
        }
        var wait = AppCloseDelay - (DateTime.Now - closed).TotalSeconds;
        log.Add(LogSource, $"{app.Name}: closed its window on its own, waiting for another one");
        After(wait, () =>
        {
            if (!IsStillDue(process, app, closed)) return;
            if (WindowCount(process) > 0) log.Add(LogSource, $"{app.Name}: opened another window, left running");
            else Quit(process, app);
        });
    }

    /// Whether this close is still the app's latest and the app is still there. A newer close
    /// starts its own wait.
    private bool IsStillDue(uint process, TrackedApp app, DateTime closed) =>
        isRunning && apps.GetValueOrDefault(process) == app && app.LastClose == closed && ProcessPath(process) == app.Path;

    // Quitting

    private void Quit(uint process, TrackedApp app)
    {
        apps.Remove(process);
        log.Add(LogSource, $"{app.Name}: no windows left, quitting");
        foreach (var window in OwnWindows(process))
            PostMessage(window.Hwnd, WM_CLOSE, 0, 0);
        After(CloseGrace, () => QuitThreads(process, app));
    }

    /// Hidden top-level windows of the process, without those Windows gives every thread.
    private static List<TopWindow> OwnWindows(uint process) => TopWindow.All()
        .Where(window => window.ProcessId == process && window.ClassName is not ("IME" or "MSCTFIME UI"))
        .ToList();

    private void QuitThreads(uint process, TrackedApp app)
    {
        if (ProcessPath(process) != app.Path) return;
        if (WindowCount(process) > 0)
        {
            log.Add(LogSource, $"{app.Name}: showed a window instead of quitting, left running");
            return;
        }
        var threads = TopWindow.All().Where(window => window.ProcessId == process).Select(window => window.ThreadId).ToHashSet();
        var sent = threads.Count(thread => PostThreadMessage(thread, WM_QUIT, 0, 0));
        if (sent == 0)
        {
            log.Add(LogSource, $"{app.Name}: can't be asked to quit, left running");
            return;
        }
        After(QuitGrace, () =>
        {
            if (ProcessPath(process) == app.Path) log.Add(LogSource, $"{app.Name}: declined to quit, left running");
            else log.Add(LogSource, $"{app.Name}: quit");
        });
    }

    /// Runs an action on the UI thread later.
    private static void After(double seconds, Action action)
    {
        if (seconds <= 0) App.Ui.TryEnqueue(() => action());
        else _ = Task.Delay(TimeSpan.FromSeconds(seconds)).ContinueWith(_ => App.Ui.TryEnqueue(() => action()), TaskScheduler.Default);
    }
}
