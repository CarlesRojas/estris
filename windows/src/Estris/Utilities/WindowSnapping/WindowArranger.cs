using static Estris.Core.Native;

namespace Estris.Utilities.WindowSnapping;

/// Arrange All: every window on a screen shares it evenly. Two side by side, three in thirds,
/// four in quarters; from five on, columns (about the square root of the count) with the
/// windows spread over them, the fewer per column on the left. Five is a left third plus four
/// quarters of the rest, six is three columns of two, seven is 2 + 2 + 3, and so on. Each
/// window goes to the space nearest where it is, so what is on the left stays on the left.
/// An app that can't get as wide or tall as its share takes what it can, and the others
/// share the rest.
public static class WindowArranger
{
    /// The windows mostly on the screen: not minimized, cloaked or kept in front of everything.
    public static List<TopWindow> Windows(Screen screen) =>
        TopWindow.All().Where(w => w.IsMain && w.Frame is { } frame && Rects.IsMostlyOn(frame, screen)).ToList();

    /// Which space each window gets: the pairing that moves them least in all, measuring
    /// between centres in proportion to the area, so a window further left ends up on the left,
    /// a higher one higher. result[i] is the index in frames for windows[i].
    public static int[] Assign(IReadOnlyList<RECT> windows, IReadOnlyList<RECT> frames, RECT area)
    {
        var count = Math.Min(windows.Count, frames.Count);
        if (count == 0) return [];
        (double X, double Y) Center(RECT rect) => (
            (rect.Left + rect.Width / 2.0 - area.Left) / Math.Max(area.Width, 1),
            (rect.Top + rect.Height / 2.0 - area.Top) / Math.Max(area.Height, 1));
        var cost = new double[count, count];
        for (var row = 0; row < count; row++)
        {
            for (var column = 0; column < count; column++)
            {
                var (wx, wy) = Center(windows[row]);
                var (fx, fy) = Center(frames[column]);
                cost[row, column] = (wx - fx) * (wx - fx) + (wy - fy) * (wy - fy);
            }
        }
        return Hungarian(cost, count);
    }

    /// The cheapest pairing of rows with columns of a square cost matrix (Kuhn and Munkres):
    /// the column for each row.
    private static int[] Hungarian(double[,] cost, int n)
    {
        var u = new double[n + 1];
        var v = new double[n + 1];
        var match = new int[n + 1]; // column -> row, 1-based
        var way = new int[n + 1];
        for (var row = 1; row <= n; row++)
        {
            match[0] = row;
            var column0 = 0;
            var minimum = Enumerable.Repeat(double.PositiveInfinity, n + 1).ToArray();
            var used = new bool[n + 1];
            do
            {
                used[column0] = true;
                var row0 = match[column0];
                var delta = double.PositiveInfinity;
                var column1 = 0;
                for (var column = 1; column <= n; column++)
                {
                    if (used[column]) continue;
                    var current = cost[row0 - 1, column - 1] - u[row0] - v[column];
                    if (current < minimum[column])
                    {
                        minimum[column] = current;
                        way[column] = column0;
                    }
                    if (minimum[column] < delta)
                    {
                        delta = minimum[column];
                        column1 = column;
                    }
                }
                for (var column = 0; column <= n; column++)
                {
                    if (used[column])
                    {
                        u[match[column]] += delta;
                        v[column] -= delta;
                    }
                    else
                    {
                        minimum[column] -= delta;
                    }
                }
                column0 = column1;
            } while (match[column0] != 0);
            do
            {
                var column1 = way[column0];
                match[column0] = match[column1];
                column0 = column1;
            } while (column0 != 0);
        }
        var result = new int[n];
        for (var column = 1; column <= n; column++)
            if (match[column] > 0) result[match[column] - 1] = column - 1;
        return result;
    }

    /// How many windows each column gets, left to right; the extra ones go to the right-hand
    /// columns.
    public static int[] Columns(int count)
    {
        if (count <= 0) return [];
        var columns = count <= 3 ? count : (int)Math.Ceiling(Math.Sqrt(count));
        var extra = count % columns;
        return Enumerable.Range(0, columns).Select(i => count / columns + (i >= columns - extra ? 1 : 0)).ToArray();
    }

    /// One frame per window, column by column, each from the top down. Space is shared
    /// evenly, except that a window that can't get as wide or as tall as its share (an app
    /// with a maximum size) takes only what it can, and the others share the rest. A column is
    /// as wide as its widest window can be. maxWidths and maxHeights are per window, in the
    /// same order; infinity when there is no limit.
    public static RECT[][] Frames(int[] columns, RECT area, double[][]? maxWidths = null, double[][]? maxHeights = null)
    {
        var widths = Share(area.Width, columns.Select((_, i) => maxWidths?[i].Max() ?? double.PositiveInfinity).ToArray());
        double x = area.Left;
        return columns.Select((rows, column) =>
        {
            var heights = Share(area.Height, maxHeights?[column] ?? Enumerable.Repeat(double.PositiveInfinity, rows).ToArray());
            var left = (int)Math.Round(x);
            x += widths[column];
            var right = (int)Math.Round(x);
            double y = area.Top;
            return Enumerable.Range(0, rows).Select(row =>
            {
                var top = (int)Math.Round(y);
                y += heights[row];
                return new RECT { Left = left, Top = top, Right = right, Bottom = (int)Math.Round(y) };
            }).ToArray();
        }).ToArray();
    }

    /// Splits a length as evenly as the parts' maximums allow: a part whose maximum is under
    /// an even share gets its maximum, and the others share what is left. When every part has
    /// reached its maximum, the rest stays empty, at the end.
    public static double[] Share(double length, double[] maximums)
    {
        var sizes = new double[maximums.Length];
        var open = Enumerable.Range(0, maximums.Length).ToList();
        var left = length;
        while (open.Count > 0)
        {
            var even = left / open.Count;
            var capped = open.Where(i => maximums[i] < even).ToList();
            if (capped.Count == 0)
            {
                foreach (var i in open) sizes[i] = even;
                break;
            }
            foreach (var i in capped)
            {
                sizes[i] = maximums[i];
                left -= maximums[i];
            }
            open.RemoveAll(capped.Contains);
        }
        return sizes;
    }
}
