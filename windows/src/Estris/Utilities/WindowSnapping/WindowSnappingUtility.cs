using Estris.Core;
using Microsoft.UI.Xaml;
using static Estris.Core.Native;

namespace Estris.Utilities.WindowSnapping;

/// The Window Snapping utility: moves the front window to halves, corners, thirds or the
/// whole screen, with shortcuts or by dragging it to a screen edge, and arranges all of them.
public sealed class WindowSnappingUtility : IUtility
{
    private const string LogSource = "Window Snapping";
    private const int MaximumRestoreFrames = 100;
    private const int SnapTolerance = 2;

    /// A snapped window's frame before its first snap, for Restore, and the frame it was
    /// snapped to, to tell whether it was moved since.
    private sealed class RestoreFrame(TopWindow window, RECT original, RECT snapped, bool wasMaximized)
    {
        public TopWindow Window { get; } = window;
        public RECT Original { get; set; } = original;
        public RECT Snapped { get; set; } = snapped;
        public bool WasMaximized { get; set; } = wasMaximized;
    }

    private readonly AppLog log;
    private readonly WindowSnappingSettings settings = new();
    private readonly SnapHotkeys hotkeys = new();
    private readonly DragSnapper dragSnapper;
    private readonly List<RestoreFrame> restoreFrames = [];
    /// The last shortcut snap, so pressing it again on the same, unmoved window switches
    /// between the filled and the exact area.
    private (TopWindow Window, SnapAction Action, RECT Frame, bool Filled)? lastShortcut;

    public WindowSnappingUtility(AppLog log)
    {
        this.log = log;
        dragSnapper = new DragSnapper(settings, (window, action, screen, original, fills, wasMaximized) =>
            Snap(window, action, screen, original, fills, wasMaximized));
    }

    public string Id => "windowSnapping";
    public string Title => "Window Snapping";
    public string Glyph => "";
    public UtilityGroup Group => UtilityGroup.WindowsAndApps;
    public string[] Keywords => ["snap", "window", "tile", "halves", "thirds", "arrange", "layout"];
    public Setting<bool> Enabled => settings.Enabled;

    public void Start()
    {
        foreach (var setting in new ISetting[] { settings.Enabled, settings.ArrangesAll, settings.KeyCodes, settings.SnapsByDragging, settings.ResizesTogether })
            setting.Changed += Apply;
        Apply();
    }

    public void Stop()
    {
        hotkeys.Set([]);
        dragSnapper.Stop();
    }

    public UIElement BuildPane() => WindowSnappingPane.Build(this, settings);

    private void Apply()
    {
        var keys = new Dictionary<int, Action>();
        if (settings.Enabled.Value)
        {
            foreach (var id in SnapKeys.Ids)
            {
                if (id == SnapKeys.ArrangeAllId && !settings.ArrangesAll.Value) continue;
                // Only the first with a key gets it; the pane says which.
                var key = settings.Key(id);
                if (!keys.TryAdd(key, id == SnapKeys.ArrangeAllId ? ArrangeAll : () => SnapFocusedWindow(SnapActions.FromId(id)!.Value)))
                    log.Add(LogSource, $"{id}: {KeyNames.Name(key)} is already set for an earlier shortcut, which takes priority");
            }
        }
        hotkeys.Set(keys);
        if (settings.Enabled.Value && (settings.SnapsByDragging.Value || settings.ResizesTogether.Value)) dragSnapper.Start();
        else dragSnapper.Stop();
    }

    /// Shares the screen the pointer is on evenly among all its windows, each going to the space
    /// nearest where it is. Each window's frame before is kept for Restore.
    private void ArrangeAll()
    {
        GetCursorPos(out var point);
        var screen = Screen.At(point);
        var area = screen.Work;
        var windows = WindowArranger.Windows(screen);
        var current = windows.Select(w => (Window: w, Frame: w.Frame ?? default, w.IsMaximized)).ToList();
        if (current.Count == 0)
        {
            log.Add(LogSource, "arrange all: no windows on this screen");
            return;
        }
        var columns = WindowArranger.Columns(current.Count);
        // Each window's column and row, from the even layout.
        var slots = columns.SelectMany((rows, column) => Enumerable.Range(0, rows).Select(row => (Column: column, Row: row))).ToArray();
        var even = WindowArranger.Frames(columns, area).SelectMany(frames => frames).ToArray();
        var assigned = WindowArranger.Assign(current.Select(c => c.Frame).ToArray(), even, area).Select(i => slots[i]).ToArray();
        // Apps with a maximum size end up smaller than asked; the layout is worked out again
        // with what they took, so the others share the space left. A few rounds, as a window
        // given more room may turn out to have a maximum too.
        var maxWidths = columns.Select(rows => Enumerable.Repeat(double.PositiveInfinity, rows).ToArray()).ToArray();
        var maxHeights = columns.Select(rows => Enumerable.Repeat(double.PositiveInfinity, rows).ToArray()).ToArray();
        var asked = new RECT?[current.Count];
        for (var round = 0; round < 3; round++)
        {
            var layout = WindowArranger.Frames(columns, area, maxWidths, maxHeights);
            var learned = false;
            for (var index = 0; index < current.Count; index++)
            {
                var (column, row) = assigned[index];
                var frame = layout[column][row];
                if (asked[index] is { } before && before.Equals(frame)) continue;
                asked[index] = frame;
                current[index].Window.SetFrame(frame, log, LogSource);
                if (current[index].Window.Frame is not { } got) continue;
                if (got.Width < frame.Width - 1 && got.Width < maxWidths[column][row])
                {
                    maxWidths[column][row] = got.Width;
                    learned = true;
                }
                if (got.Height < frame.Height - 1 && got.Height < maxHeights[column][row])
                {
                    maxHeights[column][row] = got.Height;
                    learned = true;
                }
            }
            if (!learned) break;
        }
        for (var index = 0; index < current.Count; index++)
        {
            var (window, original, wasMaximized) = current[index];
            Remember(window, original, window.Frame ?? asked[index] ?? original, wasMaximized);
        }
        lastShortcut = null;
        log.Add(LogSource, $"arrange all: {windows.Count} window(s): {string.Join(", ", windows.Select(w => WindowApp(w.Hwnd) ?? w.ClassName))}");
    }

    private void SnapFocusedWindow(SnapAction action)
    {
        var window = TopWindow.Foreground;
        if (!window.Exists || !window.IsAppWindow || window.IsMinimized || window.Frame is not { } frame)
        {
            log.Add(LogSource, "no window to snap");
            return;
        }
        if (window.IsTopmost)
        {
            log.Add(LogSource, "not snapping a window kept in front of everything");
            return;
        }
        var fills = settings.FillsSpace.Value;
        if (fills && lastShortcut is { } last && last.Action == action && last.Window == window && Rects.Near(last.Frame, frame, SnapTolerance))
            fills = !last.Filled;
        var result = Snap(window, action, Screen.Of(frame), frame, fills, window.IsMaximized);
        lastShortcut = result is { } snapped ? (window, action, snapped.Frame, snapped.Filled) : null;
    }

    /// Moves a window; original is where it was before, kept for Restore. Returns where it
    /// ended up, and whether that is the filled area rather than the exact one.
    private (RECT Frame, bool Filled)? Snap(TopWindow window, SnapAction action, Screen screen, RECT original, bool fills, bool wasMaximized)
    {
        var saved = restoreFrames.Find(entry => entry.Window == window);
        if (action == SnapAction.Restore)
        {
            if (saved is null) return null;
            window.SetFrame(saved.Original, log, LogSource);
            if (saved.WasMaximized) window.Maximize();
            restoreFrames.Remove(saved);
            return null;
        }
        if (action.Frame(screen) is not { } usual) return null;
        var target = usual;
        if (fills) target = SpaceFiller.Fit(usual, action, screen, SpaceFiller.TiledWindows(screen, window), window.ProcessId);
        if (!window.SetFrame(target, log, LogSource)) return null;
        // An app that won't get as small as the space gets the usual snap instead.
        if (!target.Equals(usual) && SpaceFiller.Refused(target, window.Frame, window.ProcessId))
        {
            target = usual;
            window.SetFrame(target, log, LogSource);
        }
        // An app that can't get as big as the space keeps to the screen edge it was snapped to
        // (or the middle), so the space left is next to the others, where filling a snap or
        // Arrange All can use it.
        if (window.Frame is { } got && (got.Width < target.Width - 1 || got.Height < target.Height - 1))
        {
            var aligned = Align(got, target, screen.Work);
            if (aligned.Left != got.Left || aligned.Top != got.Top) window.SetFrame(aligned, log, LogSource);
        }
        // Apps can round the size, so what it ended up as is what a later move is compared to.
        var snapped = window.Frame ?? target;
        Remember(window, original, snapped, wasMaximized);
        // Asked to fill but nothing to fill counts as exact, so a second press does nothing new.
        return (snapped, fills && !target.Equals(usual));
    }

    private void Remember(TopWindow window, RECT original, RECT snapped, bool wasMaximized)
    {
        restoreFrames.RemoveAll(entry => !entry.Window.Exists);
        if (restoreFrames.Find(entry => entry.Window == window) is { } saved)
        {
            // Moved by hand since its last snap: that is the frame to go back to now.
            if (!Rects.Near(saved.Snapped, original, SnapTolerance))
            {
                saved.Original = original;
                saved.WasMaximized = wasMaximized;
            }
            saved.Snapped = snapped;
            return;
        }
        restoreFrames.Add(new RestoreFrame(window, original, snapped, wasMaximized));
        if (restoreFrames.Count > MaximumRestoreFrames) restoreFrames.RemoveAt(0);
    }

    /// A smaller size placed in a snap's frame: against the screen edges the frame touches,
    /// centred where it touches neither or both.
    private static RECT Align(RECT size, RECT frame, RECT area)
    {
        static int Place(int length, int start, int end, int lower, int upper)
        {
            var atLower = Math.Abs(start - lower) < SnapTolerance;
            var atUpper = Math.Abs(end - upper) < SnapTolerance;
            if (atLower && !atUpper) return start;
            if (atUpper && !atLower) return end - length;
            return (start + end - length) / 2;
        }
        var width = Math.Min(size.Width, frame.Width);
        var height = Math.Min(size.Height, frame.Height);
        return Rects.Rect(Place(width, frame.Left, frame.Right, area.Left, area.Right), Place(height, frame.Top, frame.Bottom, area.Top, area.Bottom), width, height);
    }
}
