using static Estris.Core.Native;
using static Estris.Utilities.ClipboardManager.ClipboardNative;

namespace Estris.Utilities.ClipboardManager;

/// Remembers the last real app in front. The tray menu takes the focus when it opens, and the
/// taskbar before that, so this is where a pick from the menu has to go back to.
public sealed class ForegroundTracker
{
    private const uint EVENT_SYSTEM_FOREGROUND = 3, WINEVENT_OUTOFCONTEXT = 0;
    private static readonly HashSet<string> ShellClasses =
        ["Shell_TrayWnd", "Shell_SecondaryTrayWnd", "NotifyIconOverflowWindow", "TopLevelWindowForOverflowXamlIsland"];

    private readonly WinEventProc onForeground;
    private nint hook, lastApp;

    public ForegroundTracker() => onForeground = (_, _, hwnd, _, _, _, _) => Note(hwnd);

    public void Start()
    {
        if (hook != 0) return;
        Note(GetForegroundWindow());
        hook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, 0, onForeground, 0, 0, WINEVENT_OUTOFCONTEXT);
    }

    public void Stop()
    {
        if (hook == 0) return;
        UnhookWinEvent(hook);
        hook = 0;
    }

    /// Brings the remembered app back to the front.
    public void Restore()
    {
        if (lastApp != 0 && GetForegroundWindow() != lastApp) SetForegroundWindow(lastApp);
    }

    private void Note(nint hwnd)
    {
        if (hwnd == 0) return;
        GetWindowThreadProcessId(hwnd, out var process);
        if (process != Environment.ProcessId && !ShellClasses.Contains(ClassOf(hwnd))) lastApp = hwnd;
    }

    private static unsafe string ClassOf(nint hwnd)
    {
        var name = stackalloc char[256];
        return new string(name, 0, GetClassName(hwnd, name, 256));
    }
}
