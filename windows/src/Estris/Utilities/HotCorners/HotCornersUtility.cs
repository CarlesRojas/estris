using System.Runtime.InteropServices;
using Estris.Core;
using Estris.Ui;
using Estris.Utilities.Remap;
using Estris.Utilities.RoundedCorners;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Markup;
using static Estris.Core.Loc;
using static Estris.Core.Native;

namespace Estris.Utilities.HotCorners;

/// Pushing the pointer into a corner of a screen runs that corner's action, as macOS's Hot
/// Corners. The actions toggle (Win+D, Win+Tab…), so a second push undoes the first. A corner
/// counts only where the pointer stops: one shared with the screen next to it doesn't.
public sealed partial class HotCornersUtility(AppLog log) : IUtility
{
    private const int Win = 0x5B, VkA = 0x41, VkN = 0x4E, VkW = 0x57;
    private const int VK_LBUTTON = 1, VK_RBUTTON = 2, VK_MBUTTON = 4;
    private const int QUNS_BUSY = 2, QUNS_RUNNING_D3D_FULL_SCREEN = 3, QUNS_PRESENTATION_MODE = 4;
    /// How near a corner, in pixels, counts as in it.
    private const int Tolerance = 1;
    /// How far the pointer must go from a corner, in logical pixels, before it can fire again, so
    /// a nudge at the corner doesn't undo what the push did.
    private const int ReArmDistance = 24;
    /// Screens are listed again this often, from the pointer's own moves.
    private const long ScreensRefreshMilliseconds = 2000;
    /// The shell's own windows cover the screen too (the desktop, Task View, Start), and a second
    /// push must still undo them.
    private static readonly HashSet<string> ShellApps =
        ["explorer.exe", "startmenuexperiencehost.exe", "searchhost.exe", "searchapp.exe", "shellexperiencehost.exe", "widgets.exe"];

    public string Id => "hotCorners";
    public string Title => "Hot Corners";
    public string Glyph => "";
    public UtilityGroup Group => UtilityGroup.WindowsAndApps;
    public string[] Keywords => ["corners", "hot", "screen", "desktop", "task view", "pointer", "mouse", "edge"];
    public Setting<bool> Enabled { get; } = SettingsStore.Shared.Get("hotCornersEnabled", false);

    private readonly HotCornersSettings settings = new();
    private DispatcherQueueTimer? delayTimer;
    private bool isListening;

    // Hook thread only.
    private List<(RECT Bounds, uint Dpi)> screens = [];
    private long screensAt;
    private Corner? latched;
    private RECT latchedBounds;

    // Shared: each push gets a number, and only the latest may still fire.
    private int generation;
    private int pendingGeneration;

    // UI thread only.
    private HotCornerAction pendingAction;

    public void Start()
    {
        delayTimer = App.Ui.CreateTimer();
        delayTimer.IsRepeating = false;
        delayTimer.Tick += (_, _) => Fire(pendingGeneration, pendingAction);
        Enabled.Changed += Apply;
        foreach (var corner in Enum.GetValues<Corner>()) settings.For(corner).Changed += Apply;
        Apply();
    }

    public void Stop() => Listen(false);

    /// Listens to the pointer only while on with something in a corner.
    private void Apply() =>
        Listen(Enabled.Value && Enum.GetValues<Corner>().Any(c => settings.For(c).Value != HotCornerAction.Nothing));

    private void Listen(bool listens)
    {
        if (listens == isListening) return;
        isListening = listens;
        if (listens) InputHooks.Subscribe(OnMouse);
        else
        {
            InputHooks.Unsubscribe(OnMouse);
            Interlocked.Increment(ref generation);
            delayTimer?.Stop();
        }
        log.Add(Title, listens ? "watching the corners" : "stopped watching the corners");
    }

    /// On the hook thread: keep it quick. Anything that acts goes to the UI thread.
    private void OnMouse(MouseEvent e)
    {
        if (e.Action != MouseAction.Move || e.IsOwn) return;
        if (screens.Count == 0 || Environment.TickCount64 - screensAt > ScreensRefreshMilliseconds)
        {
            screens = LayeredWindow.Screens();
            screensAt = Environment.TickCount64;
        }
        if (screens.Count == 0) return;

        // The hook can report the pointer past the edge it is pushed against.
        var (screen, x, y) = Nearest(e.X, e.Y);
        var hit = HitCorner(screen.Bounds, x, y);

        if (latched is { } held)
        {
            var (cornerX, cornerY) = CornerPoint(latchedBounds, held);
            var reArm = ReArmDistance * (int)screen.Dpi / 96;
            var isWaiting = Volatile.Read(ref pendingGeneration) == Volatile.Read(ref generation);
            // Gone far enough, or left before the delay was up: the next push counts.
            if (Math.Abs(x - cornerX) > reArm || Math.Abs(y - cornerY) > reArm || (isWaiting && hit != held))
            {
                latched = null;
                Interlocked.Increment(ref generation);
            }
            return;
        }
        if (hit is not { } corner) return;
        latched = corner;
        latchedBounds = screen.Bounds;
        var action = settings.For(corner).Value;
        if (action == HotCornerAction.Nothing) return;
        var push = Interlocked.Increment(ref generation);
        var delay = settings.Delay.Value;
        if (delay > 0) Volatile.Write(ref pendingGeneration, push);
        App.Ui.TryEnqueue(() =>
        {
            if (delay <= 0) Fire(push, action);
            else if (delayTimer is not null)
            {
                pendingAction = action;
                delayTimer.Stop();
                delayTimer.Interval = TimeSpan.FromMilliseconds(delay);
                delayTimer.Start();
            }
        });
    }

    /// The screen the point is on, or the nearest one, with the point moved onto it.
    private ((RECT Bounds, uint Dpi) Screen, int X, int Y) Nearest(int x, int y)
    {
        var best = screens[0];
        var (bestX, bestY, bestDistance) = (0, 0, long.MaxValue);
        foreach (var screen in screens)
        {
            var b = screen.Bounds;
            var cx = Math.Clamp(x, b.Left, b.Right - 1);
            var cy = Math.Clamp(y, b.Top, b.Bottom - 1);
            var distance = (long)(cx - x) * (cx - x) + (long)(cy - y) * (cy - y);
            if (distance >= bestDistance) continue;
            (best, bestX, bestY, bestDistance) = (screen, cx, cy, distance);
        }
        return (best, bestX, bestY);
    }

    /// The corner of that screen the point is in, if the pointer stops there: past either of its
    /// edges is no other screen.
    private Corner? HitCorner(RECT b, int x, int y)
    {
        var isLeft = x <= b.Left + Tolerance;
        var isRight = x >= b.Right - 1 - Tolerance;
        var isTop = y <= b.Top + Tolerance;
        var isBottom = y >= b.Bottom - 1 - Tolerance;
        if (!(isLeft || isRight) || !(isTop || isBottom)) return null;
        var corner = (isTop, isLeft) switch
        {
            (true, true) => Corner.TopLeft,
            (true, false) => Corner.TopRight,
            (false, true) => Corner.BottomLeft,
            _ => Corner.BottomRight,
        };
        var (cornerX, cornerY) = CornerPoint(b, corner);
        var outX = isLeft ? b.Left - 1 : b.Right;
        var outY = isTop ? b.Top - 1 : b.Bottom;
        return IsOnScreen(outX, cornerY) || IsOnScreen(cornerX, outY) ? null : corner;
    }

    private static (int X, int Y) CornerPoint(RECT b, Corner corner) => corner switch
    {
        Corner.TopLeft => (b.Left, b.Top),
        Corner.TopRight => (b.Right - 1, b.Top),
        Corner.BottomLeft => (b.Left, b.Bottom - 1),
        _ => (b.Right - 1, b.Bottom - 1),
    };

    private bool IsOnScreen(int x, int y) =>
        screens.Any(s => x >= s.Bounds.Left && x < s.Bounds.Right && y >= s.Bounds.Top && y < s.Bounds.Bottom);

    /// On the UI thread, if this push is still the latest.
    private void Fire(int push, HotCornerAction action)
    {
        if (push == 0 || Volatile.Read(ref generation) != push) return;
        Volatile.Write(ref pendingGeneration, 0);
        // Dragging into a corner, as Window Snapping does, isn't a push.
        if (IsButtonHeld()) return;
        if (settings.IgnoresFullScreen.Value && IsFullScreenAppInFront())
        {
            log.Add(Title, "a full-screen app is in front: not acting");
            return;
        }
        log.Add(Title, $"{action}");
        Perform(action);
    }

    private static bool IsButtonHeld() =>
        new[] { VK_LBUTTON, VK_RBUTTON, VK_MBUTTON }.Any(vk => (InputSender.GetAsyncKeyState(vk) & 0x8000) != 0);

    private static bool IsFullScreenAppInFront()
    {
        if (SHQueryUserNotificationState(out var state) != 0) return false;
        if (state is not (QUNS_BUSY or QUNS_RUNNING_D3D_FULL_SCREEN or QUNS_PRESENTATION_MODE)) return false;
        var app = ForegroundApp();
        return app is null || !ShellApps.Contains(app);
    }

    private void Perform(HotCornerAction action)
    {
        switch (action)
        {
            case HotCornerAction.ShowDesktop: SystemActions.Perform(SystemAction.ShowDesktop, log); break;
            case HotCornerAction.TaskView: SystemActions.Perform(SystemAction.TaskView, log); break;
            case HotCornerAction.StartMenu: SystemActions.Perform(SystemAction.StartMenu, log); break;
            case HotCornerAction.Search: SystemActions.Perform(SystemAction.Search, log); break;
            case HotCornerAction.NotificationCenter: InputSender.Chord(Win, VkN); break;
            case HotCornerAction.QuickSettings: InputSender.Chord(Win, VkA); break;
            case HotCornerAction.Widgets: InputSender.Chord(Win, VkW); break;
            case HotCornerAction.SleepDisplay: SystemActions.Perform(SystemAction.SleepDisplay, log); break;
            case HotCornerAction.LockScreen: SystemActions.Perform(SystemAction.LockScreen, log); break;
        }
    }

    private static string ActionTitle(HotCornerAction action) => action switch
    {
        HotCornerAction.ShowDesktop => SystemActions.Title(SystemAction.ShowDesktop),
        HotCornerAction.TaskView => SystemActions.Title(SystemAction.TaskView),
        HotCornerAction.StartMenu => SystemActions.Title(SystemAction.StartMenu),
        HotCornerAction.Search => SystemActions.Title(SystemAction.Search),
        HotCornerAction.NotificationCenter => T("Notification Center"),
        HotCornerAction.QuickSettings => T("Quick Settings"),
        HotCornerAction.Widgets => T("Widgets"),
        HotCornerAction.SleepDisplay => SystemActions.Title(SystemAction.SleepDisplay),
        HotCornerAction.LockScreen => SystemActions.Title(SystemAction.LockScreen),
        _ => T("Nothing"),
    };

    public UIElement BuildPane()
    {
        var pane = new Pane();
        pane.UtilityHeader(this, T("Push the pointer into a corner of the screen to show the desktop, open Task View and more. Push it again to go back."));

        pane.Section(T("Corners"));
        var options = Enum.GetValues<HotCornerAction>().Select(a => (a, ActionTitle(a))).ToArray();
        foreach (var (corner, title) in new[]
        {
            (Corner.TopLeft, T("Top Left")),
            (Corner.TopRight, T("Top Right")),
            (Corner.BottomLeft, T("Bottom Left")),
            (Corner.BottomRight, T("Bottom Right")),
        })
            pane.Choice(title, settings.For(corner), options).HeaderIcon = CornerIcon(corner);
        pane.Note(T("Only corners where the pointer stops count: one shared with another screen doesn't. Dragging into a corner does nothing, so Window Snapping's corners keep working."));

        pane.Section(T("Behavior"));
        pane.Slider(T("Delay"), settings.Delay, 0, HotCornersSettings.MaximumDelay, HotCornersSettings.DelayStep,
            value => value <= 0 ? T("None") : T("%lld ms", (long)Math.Round(value)),
            T("How long the pointer rests in a corner before the action runs. A short delay keeps a quick move to a maximized window's close button from opening Task View."));
        pane.Toggle(T("Off in full-screen apps"), settings.IgnoresFullScreen, T("Games, videos and presentations shown full screen ignore the corners."));

        pane.ResetButton(settings.Reset);
        return pane.Root;
    }

    /// A screen with its corner marked, as a vector icon in the text colour.
    private static PathIcon CornerIcon(Corner corner)
    {
        var mark = corner switch
        {
            Corner.TopLeft => "M1.5,3.5h6l-6,4.5z",
            Corner.TopRight => "M14.5,3.5h-6l6,4.5z",
            Corner.BottomLeft => "M1.5,12.5h6l-6,-4.5z",
            _ => "M14.5,12.5h-6l6,-4.5z",
        };
        return (PathIcon)XamlReader.Load(
            "<PathIcon xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' "
            + $"Data='F0 M0,2H16V14H0Z M1.5,3.5V12.5H14.5V3.5Z {mark}'/>");
    }

    [LibraryImport("shell32")] private static partial int SHQueryUserNotificationState(out int state);
}
