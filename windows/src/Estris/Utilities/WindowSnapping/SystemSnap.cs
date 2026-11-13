using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace Estris.Utilities.WindowSnapping;

/// Windows's own Snap, which reacts to the same drags as Estris.
///
/// Its one switch in Settings ("Snap windows") also controls dragging a maximized window off
/// the top, so turning it off leaves maximized windows stuck. Instead Snap stays on, and while
/// Estris snaps dragged windows it turns off only Windows's snapping of a window dragged to an
/// edge. The change is for this session only, the saved setting isn't touched: Estris puts it
/// back when it stops, and if it doesn't get to, it comes back at the next sign-in.
internal static partial class SystemSnap
{
    private const uint SPI_GETWINARRANGING = 0x82, SPI_GETDOCKMOVING = 0x90, SPI_SETDOCKMOVING = 0x91, SPIF_SENDCHANGE = 2;
    private const string AdvancedKey = @"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced";

    private static readonly object Gate = new();
    /// Whether edge snapping was on before Estris turned it off; null while Estris leaves it be.
    private static bool? wasDocking;

    [LibraryImport("user32", EntryPoint = "SystemParametersInfoW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool SystemParametersInfo(uint action, uint param, out int value, uint update);

    [LibraryImport("user32", EntryPoint = "SystemParametersInfoW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool SystemParametersInfo(uint action, uint param, nint value, uint update);

    /// Whether "Snap windows" is on in Windows Settings.
    public static bool IsOn => Get(SPI_GETWINARRANGING);

    /// Whether Windows shows its snap layouts when a window is dragged to the top of the screen,
    /// which snaps it on top of Estris. On unless turned off.
    public static bool ShowsLayoutsOnDrag => IsOn && Registry.GetValue(AdvancedKey, "EnableSnapBar", 1) is not 0;

    /// Turns Windows's snapping of windows dragged to an edge off while Estris snaps them, and
    /// back to how it was when it no longer does.
    public static void SetEdgeSnappingSuppressed(bool suppressed)
    {
        lock (Gate)
        {
            if (suppressed && wasDocking is null)
            {
                wasDocking = Get(SPI_GETDOCKMOVING);
                if (wasDocking == true) SetDocking(false);
            }
            else if (!suppressed && wasDocking is { } was)
            {
                if (was) SetDocking(true);
                wasDocking = null;
            }
        }
    }

    /// Turns edge snapping off again if something put it back on (Windows Settings, while
    /// changing Snap), so the drag starting now isn't snapped twice.
    public static void KeepSuppressed()
    {
        lock (Gate)
        {
            if (wasDocking is not null && Get(SPI_GETDOCKMOVING)) SetDocking(false);
        }
    }

    private static bool Get(uint action) => SystemParametersInfo(action, 0, out int on, 0) && on != 0;

    /// The value goes in uiParam, not pvParam as the documentation says. Without
    /// SPIF_UPDATEINIFILE it isn't saved.
    private static void SetDocking(bool on) => SystemParametersInfo(SPI_SETDOCKMOVING, on ? 1u : 0u, 0, SPIF_SENDCHANGE);
}
