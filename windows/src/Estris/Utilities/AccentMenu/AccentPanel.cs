using System.Runtime.InteropServices;
using Estris.Ui;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using static Estris.Core.Native;

namespace Estris.Utilities.AccentMenu;

/// The accents of a held letter in a row of glass over the caret, each with its number under it,
/// the chosen one filled with the accent colour. Lets the pointer through: the utility follows the
/// pointer itself, from the mouse hook, so the window never takes a click or the focus.
internal sealed class AccentPanel
{
    /// The items' corners sit inside the panel's, as the Clipboard's card: its radius is theirs plus the padding.
    private const double ItemWidth = 32, ItemHeight = 42, Padding = 5, Spacing = 2, ItemRadius = 8, Radius = ItemRadius + Padding, ShadowBlur = 24;
    private const double LetterSize = 18, LetterLine = 22, NumberSize = 10, NumberLine = 12;
    /// The text over the glass, as the Clipboard's: white or black, the numbers fainter.
    private static readonly Windows.UI.Color DarkLetter = Windows.UI.Color.FromArgb(0xFF, 255, 255, 255), LightLetter = Windows.UI.Color.FromArgb(0xE4, 0, 0, 0);
    private static readonly Windows.UI.Color DarkNumber = Windows.UI.Color.FromArgb(0x8C, 255, 255, 255), LightNumber = Windows.UI.Color.FromArgb(0x80, 0, 0, 0);
    /// The number on the chosen accent: the accent's own text colour, fainter.
    private const double OnAccentNumberOpacity = 0.7;
    /// The gap between the caret and the panel, in logical pixels.
    private const double CaretGap = 6;

    private readonly StackPanel row = new() { Orientation = Orientation.Horizontal, Spacing = Spacing, Padding = new Thickness(Padding) };
    private readonly GlassPanel panel;
    private readonly List<(Border Item, TextBlock Letter, TextBlock Number)> items = [];
    private readonly SolidColorBrush letterBrush = new(), numberBrush = new();
    private (int X, int Y) origin;
    private double scale = 1;

    public AccentPanel()
    {
        panel = new GlassPanel(row, Radius, ShadowBlur, clickThrough: true);
    }

    public bool IsVisible { get; private set; }

    /// Shows the accents over the caret, or under it when there's no room above.
    public void Show(string accents, RECT caret)
    {
        row.Children.Clear();
        items.Clear();
        for (var i = 0; i < accents.Length; i++)
        {
            var letter = new TextBlock
            {
                Text = accents[i].ToString(), FontSize = LetterSize, LineHeight = LetterLine,
                LineStackingStrategy = LineStackingStrategy.BlockLineHeight, HorizontalAlignment = HorizontalAlignment.Center,
            };
            var number = new TextBlock
            {
                Text = (i + 1).ToString(), FontSize = NumberSize, LineHeight = NumberLine,
                LineStackingStrategy = LineStackingStrategy.BlockLineHeight, HorizontalAlignment = HorizontalAlignment.Center,
            };
            var stack = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            stack.Children.Add(letter);
            stack.Children.Add(number);
            var item = new Border { Width = ItemWidth, Height = ItemHeight, CornerRadius = new CornerRadius(ItemRadius), Child = stack };
            items.Add((item, letter, number));
            row.Children.Add(item);
        }
        // Light or dark text as the glass is, which follows Windows's own theme rather than the app's.
        var isLightGlass = GlassLook.Current().Tint.R > 128;
        letterBrush.Color = isLightGlass ? LightLetter : DarkLetter;
        numberBrush.Color = isLightGlass ? LightNumber : DarkNumber;
        Select(-1);

        var monitor = MonitorFromPoint(new POINT { X = caret.Left, Y = caret.Top }, MONITOR_DEFAULTTONEAREST);
        GetDpiForMonitor(monitor, 0, out var dpi, out _);
        scale = dpi / 96.0;
        var width = (int)Math.Ceiling((accents.Length * ItemWidth + (accents.Length - 1) * Spacing + 2 * Padding) * scale);
        var height = (int)Math.Ceiling((ItemHeight + 2 * Padding) * scale);
        var gap = (int)Math.Round(CaretGap * scale);
        var info = new MONITORINFO { cbSize = Marshal.SizeOf<MONITORINFO>() };
        GetMonitorInfo(monitor, ref info);
        var work = info.rcWork;
        var top = caret.Top - gap - height >= work.Top ? caret.Top - gap - height : caret.Bottom + gap;
        var left = Math.Clamp(caret.Left - width / 2, work.Left, Math.Max(work.Left, work.Right - width));
        origin = (left, top);
        panel.RefreshLook();
        panel.Place(left, top, width, height);
        // The glass starts out see-through.
        panel.SetOpacity(1);
        panel.Show();
        IsVisible = true;
    }

    public void Hide()
    {
        if (!IsVisible) return;
        IsVisible = false;
        panel.Hide();
    }

    /// Fills that accent with the accent colour, or none with -1.
    public void Select(int index)
    {
        var resources = Application.Current.Resources;
        for (var i = 0; i < items.Count; i++)
        {
            var (item, letter, number) = items[i];
            var isSelected = i == index;
            item.Background = isSelected ? (Brush)resources["AccentFillColorDefaultBrush"] : null;
            var onAccent = (Brush)resources["TextOnAccentFillColorPrimaryBrush"];
            letter.Foreground = isSelected ? onAccent : letterBrush;
            number.Foreground = isSelected ? onAccent : numberBrush;
            number.Opacity = isSelected ? OnAccentNumberOpacity : 1;
        }
    }

    /// Each accent's frame on screen, in pixels, and the whole panel's, for following the pointer.
    public (RECT[] Items, RECT Panel) Frames()
    {
        int Px(double logical) => (int)Math.Round(logical * scale);
        var frames = new RECT[items.Count];
        for (var i = 0; i < items.Count; i++)
        {
            var left = origin.X + Px(Padding + i * (ItemWidth + Spacing));
            var top = origin.Y + Px(Padding);
            frames[i] = new RECT { Left = left, Top = top, Right = left + Px(ItemWidth), Bottom = top + Px(ItemHeight) };
        }
        var whole = new RECT
        {
            Left = origin.X,
            Top = origin.Y,
            Right = origin.X + Px(items.Count * ItemWidth + (items.Count - 1) * Spacing + 2 * Padding),
            Bottom = origin.Y + Px(ItemHeight + 2 * Padding),
        };
        return (frames, whole);
    }

    [DllImport("shcore")] private static extern int GetDpiForMonitor(nint monitor, int type, out uint dpiX, out uint dpiY);
}
