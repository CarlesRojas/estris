using System.Runtime.InteropServices;
using Estris.Core;
using Estris.Ui;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using static Estris.Core.Loc;
using static Estris.Core.Native;

namespace Estris.Utilities.RoundedCorners;

/// While on, paints the corners of every screen black, as if the screens themselves had rounded
/// corners. Each corner is a small click-through window above everything, in Win32 rather than
/// XAML so it weighs nothing; they are left out of screenshots, as real screen corners would be.
public sealed partial class RoundedCornersUtility(AppLog log) : IUtility
{
    private const uint WM_DISPLAYCHANGE = 0x7E, WM_DPICHANGED = 0x2E0;
    private const uint EVENT_SYSTEM_FOREGROUND = 3, WINEVENT_OUTOFCONTEXT = 0;
    /// How often to go back on top anyway: not everything that covers them takes the focus.
    private static readonly TimeSpan TopmostCheck = TimeSpan.FromSeconds(2);

    public string Id => "roundedCorners";
    public string Title => "Rounded Corners";
    public string Glyph => "\uE7F4";
    public UtilityGroup Group => UtilityGroup.Tools;
    public string[] Keywords => ["corners", "round", "radius", "screen", "display", "black"];
    public Setting<bool> Enabled { get; } = SettingsStore.Shared.Get("roundedCornersEnabled", false);

    private readonly RoundedCornersSettings settings = new();
    private readonly List<LayeredWindow> windows = [];
    private LayeredWindow? displayWatcher;
    private DispatcherQueueTimer? topmostTimer;
    private WinEventProc? foregroundProc;
    private nint foregroundHook;
    private bool isUpdateQueued;

    public void Start()
    {
        Enabled.Changed += Apply;
        settings.Radius.Changed += Update;
        Apply();
    }

    public void Stop() => TurnOff();

    private void Apply()
    {
        if (Enabled.Value) TurnOn();
        else TurnOff();
    }

    private void TurnOn()
    {
        if (displayWatcher is not null) return;
        // Stays when every screen is gone, to hear when one comes back.
        displayWatcher = new LayeredWindow(handler: OnDisplayMessage);
        foregroundProc = (_, _, _, _, _, _, _) => BringToTop();
        foregroundHook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, 0, foregroundProc, 0, 0, WINEVENT_OUTOFCONTEXT);
        topmostTimer = App.Ui.CreateTimer();
        topmostTimer.Interval = TopmostCheck;
        topmostTimer.Tick += (_, _) => BringToTop();
        topmostTimer.Start();
        Update();
    }

    private void TurnOff()
    {
        topmostTimer?.Stop();
        topmostTimer = null;
        if (foregroundHook != 0) UnhookWinEvent(foregroundHook);
        foregroundHook = 0;
        foregroundProc = null;
        displayWatcher?.Dispose();
        displayWatcher = null;
        foreach (var window in windows) window.Dispose();
        windows.Clear();
    }

    private void BringToTop()
    {
        foreach (var window in windows) window.BringToTop();
    }

    private bool OnDisplayMessage(uint message, nint wParam, nint lParam, out nint result)
    {
        result = 0;
        if (message is WM_DISPLAYCHANGE or WM_DPICHANGED && !isUpdateQueued)
        {
            // A change of screens comes as several messages, while they are still settling.
            isUpdateQueued = true;
            App.Ui.TryEnqueue(DispatcherQueuePriority.Low, () =>
            {
                isUpdateQueued = false;
                Update();
            });
        }
        return false;
    }

    /// One window per corner of every screen. Windows are kept and moved rather than made again,
    /// so dragging the radius slider stays smooth.
    private void Update()
    {
        if (displayWatcher is null) return;
        var screens = LayeredWindow.Screens();
        var count = screens.Count * 4;
        if (count != windows.Count) log.Add(Title, $"painting the corners of {screens.Count} screen(s)");
        while (windows.Count > count)
        {
            windows[^1].Dispose();
            windows.RemoveAt(windows.Count - 1);
        }
        while (windows.Count < count)
        {
            var window = new LayeredWindow(WS_EX_TRANSPARENT, OnDisplayMessage);
            window.ExcludeFromCapture();
            windows.Add(window);
        }
        var index = 0;
        foreach (var (bounds, dpi) in screens)
        {
            var radius = settings.Radius.Value * dpi / 96;
            var side = (int)Math.Ceiling(radius);
            foreach (var (isRight, isBottom) in new[] { (false, false), (true, false), (false, true), (true, true) })
            {
                var x = isRight ? bounds.Right - side : bounds.Left;
                var y = isBottom ? bounds.Bottom - side : bounds.Top;
                windows[index++].Present(x, y, side, side, (pixels, _, _) => PaintCorner(pixels, side, radius, isRight, isBottom));
            }
        }
    }

    /// Black outside a circular arc, with its edge antialiased from the distance to the arc.
    private static unsafe void PaintCorner(nint pixels, int side, double radius, bool isRight, bool isBottom)
    {
        var row = (uint*)pixels;
        for (var y = 0; y < side; y++)
        {
            var fromTop = isBottom ? side - 1 - y : y;
            for (var x = 0; x < side; x++)
            {
                var fromLeft = isRight ? side - 1 - x : x;
                var distance = Math.Sqrt(Square(radius - fromLeft - 0.5) + Square(radius - fromTop - 0.5)) - radius;
                var alpha = (uint)Math.Round(Math.Clamp(distance + 0.5, 0, 1) * 255);
                row[y * side + x] = alpha << 24;
            }
        }
    }

    private static double Square(double value) => Math.Max(value, 0) * Math.Max(value, 0);

    public UIElement BuildPane()
    {
        var pane = new Pane();
        pane.UtilityHeader(this, T("Rounds the corners of your screens by painting them black."));
        pane.Section(T("Corners"));
        pane.Slider(T("Radius"), settings.Radius, RoundedCornersSettings.MinimumRadius, RoundedCornersSettings.MaximumRadius, 1, value => T("%lld px", (long)Math.Round(value)));
        pane.Note(T("By default, as round as the corners of Windows 11 windows, so a maximized window fits them."));
        pane.ResetButton(settings.Reset);
        return pane.Root;
    }

    private delegate void WinEventProc(nint hook, uint eventType, nint hwnd, int objectId, int childId, uint thread, uint time);

    [DllImport("user32")] private static extern nint SetWinEventHook(uint first, uint last, nint module, WinEventProc proc, uint process, uint thread, uint flags);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool UnhookWinEvent(nint hook);
}
