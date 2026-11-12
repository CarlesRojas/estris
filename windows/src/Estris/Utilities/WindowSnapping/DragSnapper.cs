using Estris.Core;
using Microsoft.UI.Dispatching;
using static Estris.Core.Native;
using static Estris.Utilities.WindowSnapping.WindowNative;

namespace Estris.Utilities.WindowSnapping;

/// Watches windows being dragged, to snap one taken to a screen edge or corner and to resize
/// the windows next to one being resized.
///
/// Windows says when a drag starts and ends, and each time the window moves. A drag that starts
/// with a resize arrow, or changes the window's size, is a resize, and windows that shared the
/// edge being dragged follow it; otherwise the window is being moved, and the pointer's place on
/// the screen picks a snap area (previewed, applied on release). Each move of the window is
/// acted on as it comes, and a timer catches the pointer moving while the window can't.
public sealed class DragSnapper(WindowSnappingSettings settings, DragSnapper.Snapper snap)
{
    /// Snaps a window: the action, its screen, where the window started, whether to fill the
    /// space next to other windows, and whether it was maximized.
    public delegate void Snapper(TopWindow window, SnapAction action, Screen screen, RECT original, bool fills, bool wasMaximized);

    /// How far along an edge from a corner the corner reaches, at least, in logical pixels.
    private const double MinimumCornerLength = 64;
    /// How far along a side edge from its ends the top and bottom halves reach.
    private const double ShortEdgeLength = 145;
    /// How close edges must be to count as shared.
    private const double SharedEdgeTolerance = 4;
    /// Smallest size a neighbour is resized down to.
    private const double MinimumNeighbourSize = 120;
    /// Gap between looks at the dragged window.
    private static readonly TimeSpan ReadInterval = TimeSpan.FromMilliseconds(16);
    private const int VK_LBUTTON = 1, VK_RBUTTON = 2, VK_CONTROL = 0x11, VK_ESCAPE = 0x1B, SM_SWAPBUTTON = 23;

    private enum Mode { Undecided, Moving, Resizing }
    private enum Edge { Left, Right, Top, Bottom }

    /// A window that may follow the resize, as it was when the drag started.
    private sealed record Other(TopWindow Window, RECT Frame, RECT Borders);

    /// A window with edges on the lines being dragged: each edge with the edge of the dragged
    /// window on that line.
    private sealed record Neighbour(TopWindow Window, RECT Frame, RECT Borders, List<(Edge Edge, Edge Dragged)> Edges)
    {
        public RECT? Last { get; set; }
    }

    private readonly SnapPreview preview = new();
    private WinEventHook? hook;
    private DispatcherQueueTimer? timer;
    /// The dragged window, for the event thread to pick out its moves.
    private nint watched;
    /// 1 while a look at the window is waiting to run, so moves don't pile up.
    private int isTickQueued;

    private TopWindow window;
    private bool isDragging;
    private RECT startFrame;
    private bool wasMaximized;
    private Mode mode;
    private bool isCancelled;
    private (SnapAction Action, Screen Screen)? target;
    private List<Other>? others;
    private List<Neighbour> neighbours = [];
    private HashSet<Edge> movedEdges = [];
    /// The tiled windows on each screen the drag has passed over, for filling space.
    private readonly Dictionary<RECT, List<RECT>> tiled = [];

    public void Start() => hook ??= new WinEventHook(OnEvent, "Window Snapping",
        (EVENT_SYSTEM_MOVESIZESTART, EVENT_SYSTEM_MOVESIZEEND), (EVENT_OBJECT_LOCATIONCHANGE, EVENT_OBJECT_LOCATIONCHANGE));

    public void Stop()
    {
        hook?.Dispose();
        hook = null;
        Reset();
        preview.Dispose();
    }

    private void OnEvent(uint type, nint hwnd, int idObject, int idChild)
    {
        if (idObject != OBJID_WINDOW || idChild != 0) return;
        if (type == EVENT_OBJECT_LOCATIONCHANGE)
        {
            if (hwnd == Volatile.Read(ref watched) && Interlocked.Exchange(ref isTickQueued, 1) == 0)
                App.Ui.TryEnqueue(DispatcherQueuePriority.High, () =>
                {
                    Volatile.Write(ref isTickQueued, 0);
                    Tick();
                });
            return;
        }
        var moved = new TopWindow(hwnd);
        if (type == EVENT_SYSTEM_MOVESIZESTART)
        {
            // Read here, as close to the start as can be. A drag from the keyboard (Alt+Space)
            // has no pointer to follow.
            if (!IsLeftButtonHeld || moved.Frame is not { } frame) return;
            var maximized = moved.IsMaximized;
            var resizes = IsSizingCursor();
            App.Ui.TryEnqueue(DispatcherQueuePriority.High, () => Begin(moved, frame, maximized, resizes));
        }
        else
        {
            App.Ui.TryEnqueue(DispatcherQueuePriority.High, () => { if (moved == window) End(); });
        }
    }

    private void Begin(TopWindow dragged, RECT frame, bool maximized, bool resizes)
    {
        Reset();
        // Windows kept in front of everything are left alone, and don't drag others along.
        // Windows run as administrator can't be moved by Estris, so they get no preview.
        if (dragged.IsTopmost || !dragged.IsAppWindow || dragged.IsOwned || dragged.IsOutOfReach) return;
        window = dragged;
        isDragging = true;
        startFrame = frame;
        wasMaximized = maximized;
        if (resizes) mode = Mode.Resizing;
        Volatile.Write(ref watched, dragged.Hwnd);
        if (timer is null)
        {
            timer = App.Ui.CreateTimer();
            timer.Interval = ReadInterval;
            timer.Tick += (_, _) => Tick();
        }
        timer.Start();
    }

    private static bool IsLeftButtonHeld =>
        Hotkeys.IsHeld(GetSystemMetrics(SM_SWAPBUTTON) != 0 ? VK_RBUTTON : VK_LBUTTON);

    [System.Runtime.InteropServices.DllImport("user32")]
    private static extern int GetSystemMetrics(int index);

    /// Holding Ctrl snaps to the exact area, without filling space.
    private bool Fills => settings.FillsSpace.Value && !Hotkeys.IsHeld(VK_CONTROL);

    private void Tick()
    {
        if (!isDragging) return;
        if (!window.Exists)
        {
            Reset();
            return;
        }
        // Esc puts the window back; there's nothing to snap.
        if (Hotkeys.IsHeld(VK_ESCAPE)) isCancelled = true;
        if (window.Frame is not { } frame) return;
        if (mode == Mode.Undecided)
        {
            if (Rects.Near(frame, startFrame, 1)) return;
            // Dragging a maximized window restores it, which changes its size.
            mode = wasMaximized || (frame.Width == startFrame.Width && frame.Height == startFrame.Height) ? Mode.Moving : Mode.Resizing;
        }
        if (mode == Mode.Moving)
        {
            if (settings.SnapsByDragging.Value) UpdateTarget();
        }
        else if (settings.ResizesTogether.Value && !isCancelled)
        {
            ResizeNeighbours(frame);
        }
    }

    private void End()
    {
        var (dragged, finalMode) = (window, mode);
        // A window gone or hidden by the end (a browser tab dropped back into its window), or
        // maximized by Windows itself, isn't snapped.
        var isSnappable = dragged.Exists && dragged.IsVisible && !dragged.IsMaximized;
        if (finalMode == Mode.Moving && !isCancelled && isSnappable && target is { } found)
            snap(dragged, found.Action, found.Screen, startFrame, Fills, wasMaximized);
        // The last moves may have been missed; line the neighbours up once more.
        else if (finalMode == Mode.Resizing && !isCancelled && settings.ResizesTogether.Value && dragged.Frame is { } frame)
            ResizeNeighbours(frame);
        Reset();
    }

    private void Reset()
    {
        timer?.Stop();
        Volatile.Write(ref watched, 0);
        isDragging = false;
        window = default;
        mode = Mode.Undecided;
        isCancelled = false;
        target = null;
        others = null;
        neighbours = [];
        movedEdges = [];
        tiled.Clear();
        preview.Close();
    }

    // Snap areas

    private void UpdateTarget()
    {
        GetCursorPos(out var point);
        var screen = Screen.At(point);
        if (isCancelled || !Rects.Contains(screen.Bounds, point.X, point.Y)
            || SnapArea(point, screen) is not { } action || action.Frame(screen) is not { } usual)
        {
            if (target is not null) preview.Hide(window);
            target = null;
            return;
        }
        var area = usual;
        if (Fills)
        {
            if (!tiled.TryGetValue(screen.Bounds, out var windows))
                windows = tiled[screen.Bounds] = SpaceFiller.TiledWindows(screen, window);
            area = SpaceFiller.Fit(usual, action, screen, windows, window.ProcessId);
        }
        target = (action, screen);
        preview.Show(area, screen, window);
    }

    /// The snap area under the pointer: corners for quarters, the top for the whole screen,
    /// the sides for halves (top and bottom halves near their ends), and the bottom for
    /// thirds, which become two thirds when the drag slides from a side third to the middle.
    /// Gestures switched off in Settings leave their place to the next area that applies.
    /// The edges reach as far into the screen as Settings says, wider than the screen's very
    /// edge, so a drag can stop on an edge shared with another display.
    private SnapAction? SnapArea(POINT point, Screen screen)
    {
        var frame = screen.Bounds;
        var band = (int)(settings.EdgeArea.Value * screen.Scale);
        var corner = Math.Max((int)(MinimumCornerLength * screen.Scale), band);
        var shortEdge = (int)(ShortEdgeLength * screen.Scale);
        var left = point.X <= frame.Left + band;
        var right = point.X >= frame.Right - band;
        var top = point.Y <= frame.Top + band;
        var bottom = point.Y >= frame.Bottom - band;
        var nearLeft = point.X <= frame.Left + corner;
        var nearRight = point.X >= frame.Right - corner;
        var nearTop = point.Y <= frame.Top + corner;
        var nearBottom = point.Y >= frame.Bottom - corner;

        if (settings.Has(SnapGesture.TopLeft) && ((left && nearTop) || (top && nearLeft))) return SnapAction.TopLeft;
        if (settings.Has(SnapGesture.TopRight) && ((right && nearTop) || (top && nearRight))) return SnapAction.TopRight;
        if (settings.Has(SnapGesture.BottomLeft) && ((left && nearBottom) || (bottom && nearLeft))) return SnapAction.BottomLeft;
        if (settings.Has(SnapGesture.BottomRight) && ((right && nearBottom) || (bottom && nearRight))) return SnapAction.BottomRight;
        if (top && settings.Has(SnapGesture.Maximize)) return SnapAction.Maximize;
        if (left || right)
        {
            if (settings.Has(SnapGesture.TopHalf) && point.Y <= frame.Top + shortEdge) return SnapAction.TopHalf;
            if (settings.Has(SnapGesture.BottomHalf) && point.Y >= frame.Bottom - shortEdge) return SnapAction.BottomHalf;
            if (left && settings.Has(SnapGesture.LeftHalf)) return SnapAction.LeftHalf;
            if (right && settings.Has(SnapGesture.RightHalf)) return SnapAction.RightHalf;
        }
        if (bottom && settings.Has(SnapGesture.Thirds))
        {
            var third = frame.Width / 3;
            if (point.X < frame.Left + third) return SnapAction.FirstThird;
            if (point.X > frame.Right - third) return SnapAction.LastThird;
            if (!settings.Has(SnapGesture.TwoThirds)) return SnapAction.CenterThird;
            return target?.Action switch
            {
                SnapAction.FirstThird or SnapAction.FirstTwoThirds => SnapAction.FirstTwoThirds,
                SnapAction.LastThird or SnapAction.LastTwoThirds => SnapAction.LastTwoThirds,
                _ => SnapAction.CenterThird,
            };
        }
        return null;
    }

    // Resizing together

    /// Moves every window edge that lay on a line the resize moved, so windows tiled along
    /// that line, on either side and anywhere along it, keep meeting there. Windows overlapping
    /// the dragged one (behind or in front of it) never follow.
    private void ResizeNeighbours(RECT frame)
    {
        var screen = Screen.Of(startFrame);
        var moved = MovedEdges(frame);
        if (!moved.SetEquals(movedEdges))
        {
            movedEdges = moved;
            neighbours = FindNeighbours(screen);
        }
        var minimum = (int)(MinimumNeighbourSize * screen.Scale);
        foreach (var neighbour in neighbours)
        {
            var rect = neighbour.Frame;
            foreach (var (edge, dragged) in neighbour.Edges)
            {
                var position = Position(dragged, frame);
                rect = edge switch
                {
                    Edge.Left => rect with { Left = position },
                    Edge.Right => rect with { Right = position },
                    Edge.Top => rect with { Top = position },
                    _ => rect with { Bottom = position },
                };
            }
            if (rect.Width < minimum || rect.Height < minimum || neighbour.Last is { } last && last.Equals(rect)) continue;
            neighbour.Last = rect;
            neighbour.Window.SetFrameWithoutWaiting(rect, neighbour.Borders);
        }
    }

    private HashSet<Edge> MovedEdges(RECT frame)
    {
        var moved = new HashSet<Edge>(movedEdges);
        if (frame.Left != startFrame.Left) moved.Add(Edge.Left);
        if (frame.Right != startFrame.Right) moved.Add(Edge.Right);
        if (frame.Top != startFrame.Top) moved.Add(Edge.Top);
        if (frame.Bottom != startFrame.Bottom) moved.Add(Edge.Bottom);
        return moved;
    }

    private static int Position(Edge edge, RECT frame) => edge switch
    {
        Edge.Left => frame.Left,
        Edge.Right => frame.Right,
        Edge.Top => frame.Top,
        _ => frame.Bottom,
    };

    /// Every other window on the same screen with an edge on a line the resize moved. The
    /// windows are read once per drag, before any has followed.
    private List<Neighbour> FindNeighbours(Screen screen)
    {
        others ??= TopWindow.All()
            .Where(other => other != window && other.IsMain && other.Frame is { } frame && Rects.IsMostlyOn(frame, screen))
            .Select(other => new Other(other, other.Frame!.Value, other.Borders()))
            .ToList();
        var tolerance = (int)(SharedEdgeTolerance * screen.Scale);
        bool Near(int a, int b) => Math.Abs(a - b) <= tolerance;
        var found = new List<Neighbour>();
        foreach (var other in others)
        {
            // A window behind or in front of the dragged one (overlapping it) isn't tiled with it.
            var overlaps = Math.Min(other.Frame.Right, startFrame.Right) - Math.Max(other.Frame.Left, startFrame.Left) > tolerance
                && Math.Min(other.Frame.Bottom, startFrame.Bottom) - Math.Max(other.Frame.Top, startFrame.Top) > tolerance;
            if (overlaps) continue;
            var edges = new List<(Edge, Edge)>();
            foreach (var dragged in movedEdges)
            {
                var line = Position(dragged, startFrame);
                Edge[] candidates = dragged is Edge.Left or Edge.Right ? [Edge.Left, Edge.Right] : [Edge.Top, Edge.Bottom];
                foreach (var edge in candidates)
                    if (Near(Position(edge, other.Frame), line)) edges.Add((edge, dragged));
            }
            if (edges.Count > 0) found.Add(new Neighbour(other.Window, other.Frame, other.Borders, edges));
        }
        return found;
    }
}
