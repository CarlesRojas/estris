using static Estris.Core.Native;

namespace Estris.Utilities.WindowSnapping;

/// Fits a snap to the windows already tiled on the screen: the snap's sides that aren't on a
/// screen edge move to the nearest edge of a neighbouring window, so the window fills the
/// space left instead of covering others or leaving a gap.
///
/// Only windows that look tiled count: on the same screen, touching a screen edge, and mostly
/// visible (not hidden behind others). The result never overlaps them; where the free space
/// isn't a rectangle it leaves the gap. Each direction may only grow or shrink so far from the
/// usual size (a third doesn't become two thirds), or it keeps the usual size.
public static class SpaceFiller
{
    /// How close edges must be to count as touching, in logical pixels.
    private const double Tolerance = 8;
    /// How far, as a share of the screen, a side may move to line up with another window's.
    private const double AlignmentReach = 0.25;
    /// Share of a window that must be uncovered for it to count.
    private const double MinimumVisibleShare = 0.5;
    private const int VisibilitySteps = 6;

    /// How far, relative to the usual size, a direction may shrink or grow. Halves and corners
    /// may fill nearly the whole screen; thirds stay close to a third, so a lone third doesn't
    /// become two thirds.
    private static (double Min, double Max) SizeRange(SnapAction action) =>
        action.Group() is SnapGroup.Halves or SnapGroup.Corners ? (0.1, 1.95) : (0.5, 1.6);

    /// The smallest size each app's windows took, learned when one refused to fit, so a later
    /// fill (and its preview) that would be smaller keeps the usual size.
    private static readonly Dictionary<uint, (int Width, int Height)> MinimumSizes = [];

    /// The windows that count, leaving out window.
    public static List<RECT> TiledWindows(Screen screen, TopWindow window)
    {
        var inFront = new List<RECT>();
        var tiled = new List<RECT>();
        var tolerance = (int)(Tolerance * screen.Scale);
        foreach (var other in TopWindow.All())
        {
            if (other == window || !other.IsNormal || other.Frame is not { } frame) continue;
            if (Rects.IsMostlyOn(frame, screen) && TouchesEdge(frame, screen.Work, tolerance)
                && VisibleShare(frame, inFront) >= MinimumVisibleShare)
                tiled.Add(frame);
            inFront.Add(frame);
        }
        return tiled;
    }

    /// The snap's frame fitted to the tiled windows, or usual when nothing applies.
    public static RECT Fit(RECT usual, SnapAction action, Screen screen, List<RECT> tiled, uint process)
    {
        if (action is SnapAction.Maximize or SnapAction.Restore || tiled.Count == 0) return usual;
        var area = screen.Work;
        var tolerance = (int)(Tolerance * screen.Scale);
        var range = SizeRange(action);
        var rect = usual;
        // Twice, as moving the sides of one direction changes which windows the other meets.
        for (var pass = 0; pass < 2; pass++)
        {
            var beside = tiled.Where(t => Overlap(t.Top, t.Bottom, rect.Top, rect.Bottom) > tolerance).Select(t => (t.Left, t.Right)).ToList();
            var (left, right) = FitSpan(rect.Left, rect.Right, usual.Left, usual.Right, area.Left, area.Right, beside,
                tiled.SelectMany(t => new[] { t.Left, t.Right }), area.Width, range, tolerance);
            rect = rect with { Left = left, Right = right };

            var above = tiled.Where(t => Overlap(t.Left, t.Right, rect.Left, rect.Right) > tolerance).Select(t => (t.Top, t.Bottom)).ToList();
            var (top, bottom) = FitSpan(rect.Top, rect.Bottom, usual.Top, usual.Bottom, area.Top, area.Bottom, above,
                tiled.SelectMany(t => new[] { t.Top, t.Bottom }), area.Height, range, tolerance);
            rect = rect with { Top = top, Bottom = bottom };
        }
        if (MinimumSizes.TryGetValue(process, out var minimum) && (rect.Width < minimum.Width || rect.Height < minimum.Height))
            return usual;
        return rect;
    }

    /// Whether a window refused the size it was asked for, ending up bigger; if so, its app's
    /// minimum is remembered.
    public static bool Refused(RECT asked, RECT? got, uint process)
    {
        if (got is not { } frame || (frame.Width <= asked.Width + 1 && frame.Height <= asked.Height + 1)) return false;
        var known = MinimumSizes.GetValueOrDefault(process);
        MinimumSizes[process] = (
            Math.Max(known.Width, frame.Width > asked.Width + 1 ? frame.Width : 0),
            Math.Max(known.Height, frame.Height > asked.Height + 1 ? frame.Height : 0));
        return true;
    }

    /// One direction of the fit: start and end are a side each, with lower and upper the
    /// screen's edges that way. A side with a window directly beside it goes to that window's
    /// edge; one with nothing beside it lines up with the nearest side of another tiled window.
    private static (int Start, int End) FitSpan(int start, int end, int usualStart, int usualEnd, int lower, int upper,
        List<(int Start, int End)> beside, IEnumerable<int> allSides, int length, (double Min, double Max) range, int tolerance)
    {
        var lines = allSides.Where(side => side > lower + tolerance && side < upper - tolerance).ToList();
        var reach = length * AlignmentReach;
        if (usualStart > lower + 1)
        {
            var edges = beside.Where(b => b.End < usualEnd - tolerance && b.Start < usualStart + tolerance).ToList();
            if (edges.Count > 0) start = edges.Max(b => b.End);
            else if (Nearest(usualStart, lines.Where(line => line < end - tolerance), reach) is { } line) start = line;
        }
        if (usualEnd < upper - 1)
        {
            var edges = beside.Where(b => b.Start > usualStart + tolerance && b.End > usualEnd - tolerance).ToList();
            var from = start;
            if (edges.Count > 0) end = edges.Min(b => b.Start);
            else if (Nearest(usualEnd, lines.Where(line => line > from + tolerance), reach) is { } line) end = line;
        }
        var ratio = (end - start) / (double)(usualEnd - usualStart);
        return ratio >= range.Min && ratio <= range.Max ? (start, end) : (usualStart, usualEnd);
    }

    private static int? Nearest(int value, IEnumerable<int> lines, double reach)
    {
        int? best = null;
        foreach (var line in lines)
            if (Math.Abs(line - value) <= reach && (best is null || Math.Abs(line - value) < Math.Abs(best.Value - value))) best = line;
        return best;
    }

    private static int Overlap(int a1, int a2, int b1, int b2) => Math.Min(a2, b2) - Math.Max(a1, b1);

    private static bool TouchesEdge(RECT frame, RECT area, int tolerance) =>
        Math.Abs(frame.Left - area.Left) <= tolerance || Math.Abs(frame.Right - area.Right) <= tolerance
        || Math.Abs(frame.Top - area.Top) <= tolerance || Math.Abs(frame.Bottom - area.Bottom) <= tolerance;

    /// The share of a window not covered by the windows in front of it, sampled on a grid.
    private static double VisibleShare(RECT frame, List<RECT> inFront)
    {
        if (inFront.Count == 0) return 1;
        var visible = 0;
        for (var column = 0; column < VisibilitySteps; column++)
        {
            for (var row = 0; row < VisibilitySteps; row++)
            {
                var x = frame.Left + frame.Width * (column + 0.5) / VisibilitySteps;
                var y = frame.Top + frame.Height * (row + 0.5) / VisibilitySteps;
                if (!inFront.Any(rect => Rects.Contains(rect, x, y))) visible++;
            }
        }
        return visible / (double)(VisibilitySteps * VisibilitySteps);
    }
}
