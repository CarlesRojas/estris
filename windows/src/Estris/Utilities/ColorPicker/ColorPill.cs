using System.Runtime.InteropServices;
using Estris.Ui;
using Microsoft.UI;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using static Estris.Core.Loc;
using static Estris.Core.Native;

namespace Estris.Utilities.ColorPicker;

/// A frosted pill with the color in a circle at the left and its value to the right: live under
/// the loupe, then saying "Copied" for a moment before it fades out. Lets clicks through. Its
/// height is fixed and both lines fit in it, so nothing moves when "Copied" appears.
internal sealed partial class ColorPill : FrostWindow
{
    private const double SwatchSize = 30, PillPadding = 7, MinimumTextWidth = 80;
    private const double PillHeight = SwatchSize + 2 * PillPadding;
    /// The value and "Copied" lines, with the gap between them, fill the swatch's height.
    private const double ValueSize = 12, ValueLine = 16, CopiedSize = 11, CopiedLine = 13, LineGap = 1;
    private const uint LWA_ALPHA = 2;
    private const byte Opaque = 255;
    private static readonly TimeSpan VisibleFor = TimeSpan.FromSeconds(1.6);
    private static readonly TimeSpan FadeStep = TimeSpan.FromMilliseconds(16);
    private static readonly TimeSpan FadeDuration = TimeSpan.FromSeconds(0.3);
    /// Alpha lost each step, so it fades out in FadeDuration.
    private static readonly int FadeAmount = (int)Math.Ceiling(Opaque * FadeStep / FadeDuration);

    private readonly Grid root = new() { Padding = new Thickness(PillPadding), Height = PillHeight, ColumnSpacing = 10, RequestedTheme = ElementTheme.Dark };
    private readonly Ellipse swatch = new()
    {
        Width = SwatchSize,
        Height = SwatchSize,
        Stroke = new SolidColorBrush(Windows.UI.Color.FromArgb(89, 255, 255, 255)),
        StrokeThickness = 1,
        VerticalAlignment = VerticalAlignment.Center,
    };
    private readonly TextBlock value = new()
    {
        FontFamily = new FontFamily("Cascadia Mono, Consolas"),
        FontWeight = Microsoft.UI.Text.FontWeights.Medium,
        FontSize = ValueSize,
        LineHeight = ValueLine,
        LineStackingStrategy = LineStackingStrategy.BlockLineHeight,
        TextAlignment = TextAlignment.Center,
        HorizontalAlignment = HorizontalAlignment.Center,
    };
    private readonly TextBlock copied = new()
    {
        Text = T("Copied"),
        FontSize = CopiedSize,
        LineHeight = CopiedLine,
        LineStackingStrategy = LineStackingStrategy.BlockLineHeight,
        HorizontalAlignment = HorizontalAlignment.Center,
        // Fluent's secondary text on dark, as the pill is always dark.
        Foreground = new SolidColorBrush(Windows.UI.Color.FromArgb(197, 255, 255, 255)),
        Visibility = Visibility.Collapsed,
    };
    private readonly DispatcherQueueTimer hideTimer = App.Ui.CreateTimer();
    private readonly DispatcherQueueTimer fadeTimer = App.Ui.CreateTimer();
    private bool isVisible;
    private int alpha = Opaque;
    private int anchorX, anchorY, aboveAnchorY;

    public ColorPill() : base(takesFocus: false)
    {
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        root.Children.Add(swatch);
        var text = new StackPanel { Spacing = LineGap, VerticalAlignment = VerticalAlignment.Center, MinWidth = MinimumTextWidth, Margin = new Thickness(0, 0, SwatchSize / 2, 0) };
        text.Children.Add(value);
        text.Children.Add(copied);
        Grid.SetColumn(text, 1);
        root.Children.Add(text);
        Content = root;

        SetWindowLongPtr(Hwnd, GWL_EXSTYLE, GetWindowLongPtr(Hwnd, GWL_EXSTYLE) | WS_EX_LAYERED | WS_EX_TRANSPARENT);
        SetLayeredWindowAttributes(Hwnd, 0, Opaque, LWA_ALPHA);

        hideTimer.IsRepeating = false;
        hideTimer.Interval = VisibleFor;
        hideTimer.Tick += (_, _) => fadeTimer.Start();
        fadeTimer.Interval = FadeStep;
        fadeTimer.Tick += (_, _) => Fade();
    }

    /// Shows it centred under a point, or over it when there's no room below.
    public void Show(Rgb color, string text, bool isCopied, int x, int y, int aboveY)
    {
        hideTimer.Stop();
        fadeTimer.Stop();
        SetAlpha(Opaque);
        swatch.Fill = new SolidColorBrush(Windows.UI.Color.FromArgb(255, color.R, color.G, color.B));
        value.Text = text;
        copied.Visibility = isCopied ? Visibility.Visible : Visibility.Collapsed;
        anchorX = x;
        anchorY = y;
        aboveAnchorY = aboveY;
        Place();
        if (isCopied) hideTimer.Start();
    }

    /// The live pill turns into the Copied one where it is.
    public void ShowCopied(Rgb color, string text) => Show(color, text, isCopied: true, anchorX, anchorY, aboveAnchorY);

    private void Place()
    {
        root.Measure(new Windows.Foundation.Size(double.PositiveInfinity, double.PositiveInfinity));
        var scale = Scale;
        var (frameWidth, frameHeight) = Frame();
        var width = (int)Math.Ceiling(Math.Max(root.DesiredSize.Width, 2 * SwatchSize) * scale) + frameWidth;
        var height = (int)Math.Ceiling(PillHeight * scale) + frameHeight;
        var work = WorkAreaAt(anchorX, anchorY);
        var top = anchorY + height > work.Bottom ? aboveAnchorY - height : anchorY;
        var left = Math.Clamp(anchorX - width / 2, work.Left, Math.Max(work.Left, work.Right - width));
        if (!isVisible)
        {
            isVisible = true;
            ShowAt(left, top, width, height);
            // A window that hasn't shown yet can't measure its content: place it again once it can.
            App.Ui.TryEnqueue(DispatcherQueuePriority.Low, Place);
            return;
        }
        SetWindowPos(Hwnd, HWND_TOPMOST, left, top, width, height, SWP_NOACTIVATE);
    }

    /// The invisible border around the content, which the window's size must leave room for.
    private (int Width, int Height) Frame()
    {
        if (!GetWindowRect(Hwnd, out var window) || !GetClientRect(Hwnd, out var client) || window.Width == 0) return (0, 0);
        return (window.Width - client.Width, window.Height - client.Height);
    }

    private static RECT WorkAreaAt(int x, int y)
    {
        var info = new MONITORINFO { cbSize = Marshal.SizeOf<MONITORINFO>() };
        GetMonitorInfo(MonitorFromPoint(new POINT { X = x, Y = y }, MONITOR_DEFAULTTONEAREST), ref info);
        return info.rcWork;
    }

    private void Fade()
    {
        SetAlpha(alpha - FadeAmount);
        if (alpha > 0) return;
        fadeTimer.Stop();
        Dismiss();
    }

    /// Takes it away at once, without fading.
    public void Dismiss()
    {
        hideTimer.Stop();
        fadeTimer.Stop();
        isVisible = false;
        Hide();
        SetAlpha(Opaque);
    }

    private void SetAlpha(int value)
    {
        alpha = Math.Max(value, 0);
        SetLayeredWindowAttributes(Hwnd, 0, (byte)alpha, LWA_ALPHA);
    }

    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool GetClientRect(nint hwnd, out RECT rect);
}
