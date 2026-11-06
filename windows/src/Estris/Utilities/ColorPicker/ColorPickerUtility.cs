using CommunityToolkit.WinUI.Controls;
using Estris.Core;
using Estris.Tray;
using Estris.Ui;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.ApplicationModel.DataTransfer;
using static Estris.Core.Loc;
using static Estris.Core.Native;

namespace Estris.Utilities.ColorPicker;

/// A shortcut shows a loupe by the pointer with the color under it in a pill; a click copies that
/// color in the chosen format and the pill says so for a moment. Windows needs no permission to
/// read the screen, so this is the only way of picking.
public sealed class ColorPickerUtility(AppLog log) : IUtility
{
    private const int TrayColumns = 8;
    private const int TrayRows = 1;
    private const double SwatchSize = 26, SwatchCell = 32;
    /// Room between the pointer and the pill, when no loupe is in between.
    private const int PointerOffset = 18;
    private const int ClipboardTries = 3;

    public string Id => "colorPicker";
    public string Title => "Color Picker";
    public string Glyph => "";
    public UtilityGroup Group => UtilityGroup.Tools;
    public string[] Keywords => ["color", "colour", "eyedropper", "hex", "rgb", "hsl"];
    public Setting<bool> Enabled { get; } = SettingsStore.Shared.Get("colorPickerEnabled", false);

    private readonly ColorPickerSettings settings = new();
    private ColorPill? pill;
    private PickerSession? session;

    public void Start()
    {
        Enabled.Changed += Apply;
        settings.Shortcut.Changed += Apply;
        Apply();
    }

    public void Stop()
    {
        Hotkeys.Unregister(this);
        session?.Cancel();
    }

    private void Apply()
    {
        Hotkeys.Unregister(this);
        if (Enabled.Value) Hotkeys.Register(this, settings.Shortcut.Value, Pick);
        else session?.Cancel();
    }

    /// Shows the loupe; on its shortcut, or from the tray menu.
    private void Pick()
    {
        if (session is not null) return;
        pill ??= new ColorPill();
        try
        {
            session = new PickerSession(pill, settings.Text, Picked);
            session.Begin();
        }
        catch (Exception e)
        {
            log.Add(Title, $"Can't start picking: {e.Message}");
            EndSession();
        }
    }

    private void Picked(Rgb? color)
    {
        EndSession();
        if (color is not { } picked)
        {
            pill?.Dismiss();
            return;
        }
        pill?.ShowCopied(picked, Write(picked));
    }

    private void EndSession()
    {
        session?.Dispose();
        session = null;
    }

    /// Copies one of the recent colors, from Settings or the tray menu, in the chosen format.
    private void Copy(string hex)
    {
        if (Rgb.FromHex(hex) is not { } color) return;
        pill ??= new ColorPill();
        GetCursorPos(out var point);
        pill.Show(color, Write(color), isCopied: true, point.X, point.Y + PointerOffset, point.Y - PointerOffset);
    }

    /// Puts the color on the clipboard in the chosen format, and among the recent ones.
    private string Write(Rgb color)
    {
        settings.Remember(color);
        var text = settings.Text(color);
        var package = new DataPackage();
        package.SetText(text);
        // Another app may hold the clipboard for a moment.
        for (var attempt = 1; attempt <= ClipboardTries; attempt++)
        {
            try
            {
                Clipboard.SetContent(package);
                Clipboard.Flush();
                break;
            }
            catch (Exception e) when (attempt < ClipboardTries)
            {
                log.Add(Title, $"Clipboard busy: {e.Message}");
                Thread.Sleep(20);
            }
            catch (Exception e)
            {
                log.Add(Title, $"Can't copy: {e.Message}");
            }
        }
        return text;
    }

    public UIElement BuildPane()
    {
        var pane = new Pane();
        pane.UtilityHeader(this, T("Pick a color anywhere on screen and copy it."));

        pane.Section(T("Shortcut"));
        pane.ShortcutRow(T("Pick a color"), settings.Shortcut);

        pane.Section(T("Copy As"));
        pane.Choice(T("Format"), settings.Format, ColorFormats.All);
        var hash = pane.Toggle(T("Include # prefix"), settings.HashPrefix);
        var example = new TextBlock
        {
            FontFamily = new FontFamily("Cascadia Mono, Consolas"),
            IsTextSelectionEnabled = true,
            Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
        };
        pane.Card(T("Example"), example);
        void SyncFormat()
        {
            hash.Visibility = settings.Format.Value == ColorFormat.Hex ? Visibility.Visible : Visibility.Collapsed;
            example.Text = settings.Text(new Rgb(255, 128, 0));
        }
        settings.Format.Changed += SyncFormat;
        settings.HashPrefix.Changed += SyncFormat;
        SyncFormat();

        var clear = new HyperlinkButton { Content = T("Clear"), HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center, Padding = new Thickness(6, 2, 6, 2) };
        clear.Click += (_, _) => settings.RecentColors.Value = [];
        var header = new Grid { Margin = new Thickness(1, 24, 0, 6) };
        header.Children.Add(new TextBlock { Text = T("Recent Colors"), Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"], VerticalAlignment = VerticalAlignment.Center });
        header.Children.Add(clear);
        pane.Add(header);
        var card = new Border
        {
            Padding = new Thickness(16, 12, 16, 12),
            CornerRadius = new CornerRadius(4),
            Background = (Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"],
            BorderBrush = (Brush)Application.Current.Resources["CardStrokeColorDefaultBrush"],
            BorderThickness = new Thickness(1),
            Child = RecentColors(ColorPickerSettings.MaxRecentColors),
        };
        pane.Add(card);
        void SyncClear() => clear.Visibility = settings.RecentColors.Value.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        settings.RecentColors.Changed += SyncClear;
        SyncClear();

        pane.ResetButton(settings.Reset);
        return pane.Root;
    }

    public UIElement? BuildTrayGroup(Action closeMenu)
    {
        var tray = App.Shared.TraySettings;
        if (!tray.ShowsColorPicker.Value && !tray.ShowsRecentColors.Value) return null;
        var group = new StackPanel { Spacing = 8 };
        if (tray.ShowsRecentColors.Value) group.Children.Add(RecentColors(TrayColumns * TrayRows, TrayColumns, closeMenu));
        if (tray.ShowsColorPicker.Value)
        {
            var button = new Button { Content = T("Pick a Color"), HorizontalAlignment = HorizontalAlignment.Stretch };
            button.Click += (_, _) =>
            {
                closeMenu();
                Pick();
            };
            group.Children.Add(button);
        }
        return group;
    }

    /// The colors picked lately as round swatches, most recent first; a click copies one in the
    /// chosen format.
    private ContentControl RecentColors(int limit, int columns = ColorPickerSettings.MaxRecentColors, Action? beforeCopying = null)
    {
        var host = new ContentControl { HorizontalContentAlignment = HorizontalAlignment.Stretch };
        void Sync()
        {
            var colors = settings.RecentColors.Value.Take(limit).ToList();
            if (colors.Count == 0)
            {
                host.Content = new TextBlock { Text = T("No colors picked yet."), Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"] };
                return;
            }
            var grid = new VariableSizedWrapGrid { Orientation = Orientation.Horizontal, MaximumRowsOrColumns = columns, ItemWidth = SwatchCell, ItemHeight = SwatchCell };
            foreach (var hex in colors) grid.Children.Add(Swatch(hex, beforeCopying));
            host.Content = grid;
        }
        host.Loaded += (_, _) =>
        {
            settings.RecentColors.Changed += Sync;
            settings.Format.Changed += Sync;
            settings.HashPrefix.Changed += Sync;
            Sync();
        };
        host.Unloaded += (_, _) =>
        {
            settings.RecentColors.Changed -= Sync;
            settings.Format.Changed -= Sync;
            settings.HashPrefix.Changed -= Sync;
        };
        Sync();
        return host;
    }

    private Button Swatch(string hex, Action? beforeCopying)
    {
        var color = Rgb.FromHex(hex) ?? new Rgb(0, 0, 0);
        var outline = (Brush)Application.Current.Resources["ControlStrongStrokeColorDefaultBrush"];
        var circle = new Ellipse
        {
            Width = SwatchSize,
            Height = SwatchSize,
            Fill = new SolidColorBrush(Windows.UI.Color.FromArgb(255, color.R, color.G, color.B)),
            Stroke = outline,
            StrokeThickness = 1,
        };
        var button = new Button
        {
            Content = circle,
            Padding = new Thickness(0),
            BorderThickness = new Thickness(0),
            Background = new SolidColorBrush(Colors.Transparent),
            CornerRadius = new CornerRadius(SwatchSize / 2),
            Width = SwatchSize,
            Height = SwatchSize,
        };
        // The value it copies, in the chosen format.
        var value = settings.Text(color);
        ToolTipService.SetToolTip(button, value);
        AutomationProperties.SetName(button, value);
        button.PointerEntered += (_, _) => circle.StrokeThickness = 2;
        button.PointerExited += (_, _) => circle.StrokeThickness = 1;
        button.Click += (_, _) =>
        {
            beforeCopying?.Invoke();
            Copy(hex);
        };
        return button;
    }
}
