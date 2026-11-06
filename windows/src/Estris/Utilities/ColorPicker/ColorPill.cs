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

/// A pill of glass, as Window Snapping's preview, with the color in a circle at the left and its
/// value to the right: live under the loupe, then saying "Copied" for a moment before it fades out.
/// Lets clicks through. Its height is fixed and both lines fit in it, so nothing moves when
/// "Copied" appears.
internal sealed class ColorPill
{
    private const double SwatchSize = 30, PillPadding = 7, MinimumTextWidth = 80;
    private const double PillHeight = SwatchSize + 2 * PillPadding;
    /// The value and "Copied" lines, with the gap between them, fill the swatch's height.
    private const double ValueSize = 12, ValueLine = 16, CopiedSize = 11, CopiedLine = 13, LineGap = 1;
    private const double ShadowBlur = 16;
    private static readonly TimeSpan VisibleFor = TimeSpan.FromSeconds(1.6);
    private static readonly TimeSpan FadeStep = TimeSpan.FromMilliseconds(16);
    private static readonly TimeSpan FadeDuration = TimeSpan.FromSeconds(0.3);
    /// Opacity lost each step, so it fades out in FadeDuration.
    private static readonly double FadeAmount = FadeStep / FadeDuration;

    private readonly Grid root = new() { Padding = new Thickness(PillPadding), Height = PillHeight, ColumnSpacing = 10 };
    private readonly GlassPanel panel;
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
        Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
        Visibility = Visibility.Collapsed,
    };
    private readonly DispatcherQueueTimer hideTimer = App.Ui.CreateTimer();
    private readonly DispatcherQueueTimer fadeTimer = App.Ui.CreateTimer();
    private bool isVisible;
    private double opacity = 1;
    private int anchorX, anchorY, aboveAnchorY;

    public ColorPill()
    {
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        root.Children.Add(swatch);
        var text = new StackPanel { Spacing = LineGap, VerticalAlignment = VerticalAlignment.Center, MinWidth = MinimumTextWidth, Margin = new Thickness(0, 0, SwatchSize / 2, 0) };
        text.Children.Add(value);
        text.Children.Add(copied);
        Grid.SetColumn(text, 1);
        root.Children.Add(text);
        panel = new GlassPanel(root, PillHeight / 2, ShadowBlur, clickThrough: true);

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
        SetOpacity(1);
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
        var scale = panel.Scale;
        var width = (int)Math.Ceiling(Math.Max(root.DesiredSize.Width, 2 * SwatchSize) * scale);
        var height = (int)Math.Ceiling(PillHeight * scale);
        var work = WorkAreaAt(anchorX, anchorY);
        var top = anchorY + height > work.Bottom ? aboveAnchorY - height : anchorY;
        var left = Math.Clamp(anchorX - width / 2, work.Left, Math.Max(work.Left, work.Right - width));
        panel.Place(left, top, width, height);
        if (isVisible) return;
        isVisible = true;
        panel.RefreshLook();
        panel.Show();
        // A window that hasn't shown yet can't measure its content: place it again once it can.
        App.Ui.TryEnqueue(DispatcherQueuePriority.Low, Place);
    }

    private static RECT WorkAreaAt(int x, int y)
    {
        var info = new MONITORINFO { cbSize = Marshal.SizeOf<MONITORINFO>() };
        GetMonitorInfo(MonitorFromPoint(new POINT { X = x, Y = y }, MONITOR_DEFAULTTONEAREST), ref info);
        return info.rcWork;
    }

    private void Fade()
    {
        SetOpacity(opacity - FadeAmount);
        if (opacity > 0) return;
        fadeTimer.Stop();
        Dismiss();
    }

    /// Takes it away at once, without fading.
    public void Dismiss()
    {
        hideTimer.Stop();
        fadeTimer.Stop();
        isVisible = false;
        panel.Hide();
        SetOpacity(1);
    }

    private void SetOpacity(double value)
    {
        opacity = Math.Max(value, 0);
        panel.SetOpacity(opacity);
    }
}
