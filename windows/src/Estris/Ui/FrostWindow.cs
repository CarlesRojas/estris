using Estris.Core;
using Microsoft.UI;
using Microsoft.UI.Composition;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Windows.Graphics;
using Windows.UI;
using WinRT;
using static Estris.Core.Native;

namespace Estris.Ui;

/// The frosted look: real Acrylic of what's behind the window, with its tint under our control
/// and kept on while the window has no focus, which the stock backdrop doesn't do.
public sealed class FrostBackdrop : Microsoft.UI.Xaml.Media.SystemBackdrop
{
    public Color Tint { get; set; } = Color.FromArgb(255, 32, 32, 32);
    public float TintOpacity { get; set; } = 0.55f;
    public float LuminosityOpacity { get; set; } = 0.85f;
    public DesktopAcrylicKind Kind { get; set; } = DesktopAcrylicKind.Thin;

    private DesktopAcrylicController? controller;

    protected override void OnTargetConnected(ICompositionSupportsSystemBackdrop target, Microsoft.UI.Xaml.XamlRoot root)
    {
        base.OnTargetConnected(target, root);
        controller = new DesktopAcrylicController
        {
            Kind = Kind,
            TintColor = Tint,
            TintOpacity = TintOpacity,
            LuminosityOpacity = LuminosityOpacity,
            FallbackColor = Tint,
        };
        controller.AddSystemBackdropTarget(target);
        controller.SetSystemBackdropConfiguration(new SystemBackdropConfiguration { IsInputActive = true, Theme = SystemBackdropTheme.Default });
    }

    protected override void OnTargetDisconnected(ICompositionSupportsSystemBackdrop target)
    {
        base.OnTargetDisconnected(target);
        controller?.RemoveSystemBackdropTarget(target);
        controller?.Dispose();
        controller = null;
    }

    /// Applies a changed tint to what's showing.
    public void Update(Color tint, float opacity)
    {
        Tint = tint;
        TintOpacity = opacity;
        if (controller is null) return;
        controller.TintColor = tint;
        controller.TintOpacity = opacity;
        controller.FallbackColor = tint;
    }
}

/// A borderless window for floating things: the tray menu, pills, the overlay's panels. It has
/// no title bar, stays out of the taskbar and Alt-Tab, and keeps Windows 11's rounded corners.
public class FrostWindow : Window
{
    public nint Hwnd { get; }
    public double Scale => GetDpiForWindow(Hwnd) / 96.0;
    private readonly bool takesFocus;

    public FrostWindow(bool takesFocus, FrostBackdrop? backdrop = null, bool isAlwaysOnTop = true)
    {
        this.takesFocus = takesFocus;
        Hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        SystemBackdrop = backdrop ?? new FrostBackdrop();

        var presenter = OverlappedPresenter.Create();
        presenter.IsResizable = false;
        presenter.IsMaximizable = false;
        presenter.IsMinimizable = false;
        presenter.IsAlwaysOnTop = isAlwaysOnTop;
        presenter.SetBorderAndTitleBar(true, false);
        AppWindow.SetPresenter(presenter);
        AppWindow.IsShownInSwitchers = false;

        var style = GetWindowLongPtr(Hwnd, GWL_EXSTYLE) | WS_EX_TOOLWINDOW;
        if (!takesFocus) style |= WS_EX_NOACTIVATE;
        SetWindowLongPtr(Hwnd, GWL_EXSTYLE, style);
    }

    /// Shows it at a place in physical pixels.
    public void ShowAt(int x, int y, int width, int height)
    {
        AppWindow.MoveAndResize(new RectInt32(x, y, width, height));
        AppWindow.Show(takesFocus);
        if (takesFocus) SetForegroundWindow(Hwnd);
    }

    /// Shows it with its content at exactly this place and size, in physical pixels. The frame that
    /// keeps the rounded corners has invisible borders, which ShowAt counts in the size it is given.
    /// They are measured, as AppWindow.ResizeClient adds a title bar this window doesn't have.
    public void ShowContentAt(int x, int y, int width, int height)
    {
        PlaceContentAt(x, y, width, height);
        AppWindow.Show(takesFocus);
        if (takesFocus) SetForegroundWindow(Hwnd);
    }

    /// The same without showing it.
    public void PlaceContentAt(int x, int y, int width, int height)
    {
        GetWindowRect(Hwnd, out var frame);
        GetClientRect(Hwnd, out var client);
        var origin = new POINT();
        ClientToScreen(Hwnd, ref origin);
        AppWindow.MoveAndResize(new RectInt32(
            x - (origin.X - frame.Left),
            y - (origin.Y - frame.Top),
            width + frame.Width - client.Width,
            height + frame.Height - client.Height));
    }

    public void Hide() => AppWindow.Hide();

    /// The screen the pointer is on, as (whole screen, the part outside the taskbar).
    public static (RECT Bounds, RECT WorkArea) ScreenUnderPointer()
    {
        GetCursorPos(out var point);
        var info = new MONITORINFO { cbSize = System.Runtime.InteropServices.Marshal.SizeOf<MONITORINFO>() };
        GetMonitorInfo(MonitorFromPoint(point, MONITOR_DEFAULTTONEAREST), ref info);
        return (info.rcMonitor, info.rcWork);
    }
}
