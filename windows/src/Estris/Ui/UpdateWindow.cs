using Estris.Core;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Graphics;
using static Estris.Core.Loc;

namespace Estris.Ui;

/// The update window, as Sparkle's on the Mac: it looks for a new version and says so when
/// Estris is up to date, or shows the new version's notes with Install Update, which downloads
/// it and opens Estris again. Opens on the screen with the pointer.
public sealed class UpdateWindow : Window
{
    /// Tall with release notes, short for every other step.
    private const int WidthDips = 540, TallHeightDips = 460, ShortHeightDips = 250, IconSize = 64;

    private static UpdateWindow? shown;

    private readonly TextBlock title = new() { Style = Style("SubtitleTextBlockStyle"), TextWrapping = TextWrapping.Wrap };
    private readonly TextBlock message = new() { TextWrapping = TextWrapping.Wrap, Foreground = Brush("TextFillColorSecondaryBrush") };
    private readonly ContentControl middle = new() { HorizontalContentAlignment = HorizontalAlignment.Stretch, VerticalContentAlignment = VerticalAlignment.Stretch };
    private readonly StackPanel buttons = new() { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Right };

    /// Shows the window, looking for a new version first unless one is already known.
    public static void Open(bool checkFirst)
    {
        if (shown is not null)
        {
            shown.Activate();
            return;
        }
        shown = new UpdateWindow();
        shown.Closed += (_, _) => shown = null;
        shown.Activate();
        if (checkFirst || Updates.Shared.AvailableVersion is null) shown.Check();
        else shown.ShowAvailable();
    }

    private UpdateWindow()
    {
        Title = T("Software Update");
        SystemBackdrop = new MicaBackdrop();
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "Estris.ico"));
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.IsResizable = false;
            presenter.IsMaximizable = false;
            presenter.IsMinimizable = false;
        }
        Place();

        var icon = new Image { Source = new BitmapImage(new Uri(Path.Combine(AppContext.BaseDirectory, "Assets", "Estris.png"))), Width = IconSize, Height = IconSize, VerticalAlignment = VerticalAlignment.Top };
        var text = new StackPanel { Spacing = 6, VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(title);
        text.Children.Add(message);
        var header = new Grid { ColumnSpacing = 20 };
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        header.Children.Add(icon);
        Grid.SetColumn(text, 1);
        header.Children.Add(text);

        var root = new Grid { Padding = new Thickness(28, 24, 28, 24), RowSpacing = 20 };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.Children.Add(header);
        Grid.SetRow(middle, 1);
        root.Children.Add(middle);
        Grid.SetRow(buttons, 2);
        root.Children.Add(buttons);
        Content = root;
    }

    /// Centred on the work area of the screen with the pointer, sized for that screen's scaling.
    private void Place()
    {
        var (_, work) = FrostWindow.ScreenUnderPointer();
        var (width, height) = Size(ShortHeightDips);
        AppWindow.MoveAndResize(new RectInt32(work.Left + (work.Width - width) / 2, work.Top + (work.Height - height) / 2, width, height));
    }

    /// Grows or shrinks around the window's current centre.
    private void Resize(int heightDips)
    {
        var (width, height) = Size(heightDips);
        if (AppWindow.Size.Height == height) return;
        var centreY = AppWindow.Position.Y + AppWindow.Size.Height / 2;
        AppWindow.MoveAndResize(new RectInt32(AppWindow.Position.X, centreY - height / 2, width, height));
    }

    private (int Width, int Height) Size(int heightDips)
    {
        var scale = Native.GetDpiForWindow(WinRT.Interop.WindowNative.GetWindowHandle(this)) / 96.0;
        return ((int)(WidthDips * scale), (int)(heightDips * scale));
    }

    private async void Check()
    {
        Show(T("Checking for updates…"), "", new ProgressBar { IsIndeterminate = true, VerticalAlignment = VerticalAlignment.Top });
        SetButtons(Button(T("Cancel"), Close));
        switch (await Updates.Shared.Check())
        {
            case UpdateCheck.Available:
                ShowAvailable();
                break;
            case UpdateCheck.UpToDate:
                Show(T("You're up to date!"), T("Estris %@ is the newest version available.", Updates.Shared.Version), null);
                SetButtons(Button(T("OK"), Close, accent: true));
                break;
            default:
                Show(T("Couldn't check for updates"), T("Check your internet connection and try again."), null);
                SetButtons(Button(T("OK"), Close, accent: true));
                break;
        }
    }

    private void ShowAvailable()
    {
        Show(T("A new version of Estris is available!"),
            T("Estris %@ is now available. You have %@. Would you like to install it now?", Updates.Shared.AvailableVersion ?? "", Updates.Shared.Version),
            Notes(Updates.Shared.AvailableNotes));
        SetButtons(Button(T("Remind Me Later"), Close), Button(T("Install Update"), Install, accent: true));
    }

    private async void Install()
    {
        var bar = new ProgressBar { Maximum = 100, VerticalAlignment = VerticalAlignment.Top };
        Show(T("Downloading update…"), T("Estris opens again by itself when it's done."), bar);
        SetButtons();
        var installed = await Updates.Shared.Install(percent => App.Ui.TryEnqueue(() => bar.Value = percent));
        if (installed) return;
        Show(T("Couldn't install the update"), T("Check your internet connection and try again."), null);
        SetButtons(Button(T("OK"), Close, accent: true));
    }

    private void Show(string heading, string text, UIElement? content)
    {
        Resize(content is Border ? TallHeightDips : ShortHeightDips);
        title.Text = heading;
        message.Text = text;
        message.Visibility = text.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        middle.Content = content;
    }

    private void SetButtons(params Button[] list)
    {
        buttons.Children.Clear();
        foreach (var button in list) buttons.Children.Add(button);
    }

    private static Button Button(string text, Action action, bool accent = false)
    {
        var button = new Button { Content = text, MinWidth = 120 };
        if (accent) button.Style = Style("AccentButtonStyle");
        button.Click += (_, _) => action();
        return button;
    }

    /// The release notes on a card, with the Markdown's headings and bullets turned into plain text.
    private static UIElement? Notes(string? markdown)
    {
        if (string.IsNullOrWhiteSpace(markdown)) return null;
        var lines = markdown.Replace("\r", "").Split('\n')
            .Select(line => line.TrimEnd())
            .Where(line => !line.StartsWith('#'))
            .Select(line => line.StartsWith("- ") || line.StartsWith("* ") ? "•  " + line[2..] : line);
        var text = new TextBlock { Text = string.Join('\n', lines).Trim(), TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true };
        var stack = new StackPanel { Spacing = 8 };
        stack.Children.Add(new TextBlock { Text = T("Release Notes:"), Style = Style("BodyStrongTextBlockStyle") });
        stack.Children.Add(text);
        return new Border
        {
            Background = Brush("CardBackgroundFillColorDefaultBrush"),
            BorderBrush = Brush("CardStrokeColorDefaultBrush"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Child = new ScrollViewer { Content = stack, Padding = new Thickness(16, 12, 16, 12) },
        };
    }

    private static Style Style(string key) => (Style)Application.Current.Resources[key];
    private static Brush Brush(string key) => (Brush)Application.Current.Resources[key];
}
