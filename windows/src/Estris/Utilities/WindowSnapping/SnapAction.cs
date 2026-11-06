using Estris.Core;
using static Estris.Core.Loc;
using static Estris.Core.Native;

namespace Estris.Utilities.WindowSnapping;

/// Where a window can be snapped to, on the screen it is on.
public enum SnapAction
{
    LeftHalf, RightHalf, TopHalf, BottomHalf,
    TopLeft, TopRight, BottomLeft, BottomRight,
    Maximize,
    FirstThird, CenterThird, LastThird,
    FirstTwoThirds, CenterTwoThirds, LastTwoThirds,
    Restore,
}

public enum SnapGroup { Halves, Corners, Thirds, Other }

public static class SnapActions
{
    public static readonly SnapAction[] All = Enum.GetValues<SnapAction>();

    /// The id a shortcut is saved under: the Mac's, so "leftHalf".
    public static string Id(this SnapAction action)
    {
        var name = action.ToString();
        return char.ToLowerInvariant(name[0]) + name[1..];
    }

    public static SnapAction? FromId(string id)
    {
        foreach (var action in All)
            if (action.Id() == id) return action;
        return null;
    }

    public static SnapGroup Group(this SnapAction action) => action switch
    {
        SnapAction.LeftHalf or SnapAction.RightHalf or SnapAction.TopHalf or SnapAction.BottomHalf => SnapGroup.Halves,
        SnapAction.TopLeft or SnapAction.TopRight or SnapAction.BottomLeft or SnapAction.BottomRight => SnapGroup.Corners,
        SnapAction.Maximize or SnapAction.Restore => SnapGroup.Other,
        _ => SnapGroup.Thirds,
    };

    public static string Title(this SnapAction action) => action switch
    {
        SnapAction.LeftHalf => T("Left Half"),
        SnapAction.RightHalf => T("Right Half"),
        SnapAction.TopHalf => T("Top Half"),
        SnapAction.BottomHalf => T("Bottom Half"),
        SnapAction.TopLeft => T("Top Left"),
        SnapAction.TopRight => T("Top Right"),
        SnapAction.BottomLeft => T("Bottom Left"),
        SnapAction.BottomRight => T("Bottom Right"),
        SnapAction.Maximize => T("Maximize"),
        SnapAction.FirstThird => T("Left Third"),
        SnapAction.CenterThird => T("Center Third"),
        SnapAction.LastThird => T("Right Third"),
        SnapAction.FirstTwoThirds => T("Left Two Thirds"),
        SnapAction.CenterTwoThirds => T("Center Two Thirds"),
        SnapAction.LastTwoThirds => T("Right Two Thirds"),
        _ => T("Restore"),
    };

    /// The key each starts out with, used with Win and Alt: the same keys as the Mac's ⌃⌥.
    public static int DefaultKey(this SnapAction action) => action switch
    {
        SnapAction.LeftHalf => 0x25,
        SnapAction.RightHalf => 0x27,
        SnapAction.TopHalf => 0x26,
        SnapAction.BottomHalf => 0x28,
        SnapAction.TopLeft => 'U',
        SnapAction.TopRight => 'I',
        SnapAction.BottomLeft => 'J',
        SnapAction.BottomRight => 'K',
        SnapAction.Maximize => 0x0D,
        SnapAction.FirstThird => 'D',
        SnapAction.CenterThird => 'F',
        SnapAction.LastThird => 'G',
        SnapAction.FirstTwoThirds => 'E',
        SnapAction.CenterTwoThirds => 'R',
        SnapAction.LastTwoThirds => 'T',
        _ => 0x08,
    };

    /// The frame on a screen, or null for Restore, which goes back to a remembered frame.
    public static RECT? Frame(this SnapAction action, Screen screen)
    {
        var area = screen.Work;
        var (x, y, width, height) = (area.Left, area.Top, area.Width, area.Height);
        var halfWidth = width / 2;
        var halfHeight = height / 2;
        var third = width / 3;
        return action switch
        {
            SnapAction.LeftHalf => Rects.Rect(x, y, halfWidth, height),
            SnapAction.RightHalf => Rects.Rect(x + halfWidth, y, width - halfWidth, height),
            SnapAction.TopHalf => Rects.Rect(x, y, width, height - halfHeight),
            SnapAction.BottomHalf => Rects.Rect(x, y + height - halfHeight, width, halfHeight),
            SnapAction.TopLeft => Rects.Rect(x, y, halfWidth, height - halfHeight),
            SnapAction.TopRight => Rects.Rect(x + halfWidth, y, width - halfWidth, height - halfHeight),
            SnapAction.BottomLeft => Rects.Rect(x, y + height - halfHeight, halfWidth, halfHeight),
            SnapAction.BottomRight => Rects.Rect(x + halfWidth, y + height - halfHeight, width - halfWidth, halfHeight),
            SnapAction.Maximize => area,
            SnapAction.FirstThird => Rects.Rect(x, y, third, height),
            SnapAction.CenterThird => Rects.Rect(x + third, y, third, height),
            SnapAction.LastThird => Rects.Rect(x + 2 * third, y, width - 2 * third, height),
            SnapAction.FirstTwoThirds => Rects.Rect(x, y, 2 * third, height),
            SnapAction.CenterTwoThirds => Rects.Rect(x + third / 2, y, 2 * third, height),
            SnapAction.LastTwoThirds => Rects.Rect(x + third, y, width - third, height),
            _ => null,
        };
    }

    /// The part of the screen it takes as (left, top, right, bottom) shares, for its icon.
    public static (double Left, double Top, double Right, double Bottom)? Shape(this SnapAction action) => action switch
    {
        SnapAction.LeftHalf => (0, 0, 0.5, 1),
        SnapAction.RightHalf => (0.5, 0, 1, 1),
        SnapAction.TopHalf => (0, 0, 1, 0.5),
        SnapAction.BottomHalf => (0, 0.5, 1, 1),
        SnapAction.TopLeft => (0, 0, 0.5, 0.5),
        SnapAction.TopRight => (0.5, 0, 1, 0.5),
        SnapAction.BottomLeft => (0, 0.5, 0.5, 1),
        SnapAction.BottomRight => (0.5, 0.5, 1, 1),
        SnapAction.Maximize => (0, 0, 1, 1),
        SnapAction.FirstThird => (0, 0, 1 / 3.0, 1),
        SnapAction.CenterThird => (1 / 3.0, 0, 2 / 3.0, 1),
        SnapAction.LastThird => (2 / 3.0, 0, 1, 1),
        SnapAction.FirstTwoThirds => (0, 0, 2 / 3.0, 1),
        SnapAction.CenterTwoThirds => (1 / 6.0, 0, 5 / 6.0, 1),
        SnapAction.LastTwoThirds => (1 / 3.0, 0, 1, 1),
        _ => null,
    };
}
