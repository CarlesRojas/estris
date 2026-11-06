using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;

namespace Estris.Utilities.ClipboardManager.Overlay;

/// The overlay's animations, and Windows' Animation effects switch (Accessibility > Visual
/// effects), which is its Reduce Motion: with it off, things change at once.
internal static partial class Motion
{
    public static readonly TimeSpan Fade = TimeSpan.FromSeconds(0.15);
    public static readonly TimeSpan Hover = TimeSpan.FromSeconds(0.12);
    private const uint SPI_GETCLIENTAREAANIMATION = 0x1042;

    public static bool IsReduced => SystemParametersInfo(SPI_GETCLIENTAREAANIMATION, 0, out var isOn, 0) && !isOn;

    /// A fade of this length for an element's opacity, or none with Reduce Motion.
    public static ScalarTransition? OpacityTransition(TimeSpan duration) =>
        IsReduced ? null : new ScalarTransition { Duration = duration };

    [LibraryImport("user32", EntryPoint = "SystemParametersInfoW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool SystemParametersInfo(uint action, uint size, [MarshalAs(UnmanagedType.Bool)] out bool value, uint flags);
}
