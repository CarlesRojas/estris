using Estris.Core;
using Estris.Ui;
using Estris.Utilities;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using static Estris.Core.Loc;

namespace Estris.Tray;

/// What clicking the tray icon opens, in the place and frosted look of Windows's Quick Settings:
/// an update when one is out, each utility's group while it is on, then Settings and Quit.
public sealed class TrayMenu : FrostWindow
{
    public const double MenuWidth = 360;
    private const double ScreenMargin = 12;
    /// A click on the icon closes the menu first; it mustn't then open it again.
    private static readonly TimeSpan ReopenGuard = TimeSpan.FromMilliseconds(250);

    private readonly TraySettings settings;
    private readonly IReadOnlyList<IUtility> utilities;
    private readonly StackPanel root = new() { Spacing = 8, Padding = new Thickness(12), Width = MenuWidth };
    private DateTime hiddenAt;
    private bool isOpen;

    public TrayMenu(TraySettings settings, IReadOnlyList<IUtility> utilities) : base(takesFocus: true)
    {
        this.settings = settings;
        this.utilities = utilities;
        Content = root;
        ((FrameworkElement)Content).RequestedTheme = ElementTheme.Default;
        Activated += (_, e) =>
        {
            if (e.WindowActivationState == WindowActivationState.Deactivated) CloseMenu();
        };
        root.KeyDown += (_, e) =>
        {
            if (e.Key == Windows.System.VirtualKey.Escape) CloseMenu();
        };
        Updates.Shared.Changed += () => { if (isOpen) Rebuild(); };
    }

    public void Toggle()
    {
        if (isOpen) CloseMenu();
        else if (DateTime.Now - hiddenAt > ReopenGuard) Open();
    }

    private void Open()
    {
        Rebuild();
        isOpen = true;
        Place();
        // A window that hasn't shown yet can't measure its content: place it again once it can.
        App.Ui.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, Place);
    }

    private void Place()
    {
        if (!isOpen) return;
        var (_, work) = ScreenUnderPointer();
        root.Measure(new Windows.Foundation.Size(MenuWidth, double.PositiveInfinity));
        var margin = (int)(ScreenMargin * Scale);
        var width = (int)Math.Ceiling(MenuWidth * Scale);
        var height = Math.Min((int)Math.Ceiling(Math.Max(root.DesiredSize.Height, 48) * Scale), work.Height - 2 * margin);
        ShowContentAt(work.Right - width - margin, work.Bottom - height - margin, width, height);
    }

    private void CloseMenu()
    {
        if (!isOpen) return;
        isOpen = false;
        hiddenAt = DateTime.Now;
        Hide();
    }

    private void Rebuild()
    {
        root.Children.Clear();
        if (Updates.Shared.AvailableVersion is { } version)
        {
            var install = new Button { Content = T("Update"), HorizontalAlignment = HorizontalAlignment.Right };
            install.Click += (_, _) => { CloseMenu(); UpdateWindow.Open(checkFirst: false); };
            var row = new Grid();
            row.Children.Add(new TextBlock { Text = T("Update Available: %@", version), VerticalAlignment = VerticalAlignment.Center });
            row.Children.Add(install);
            root.Children.Add(Group(row));
        }

        foreach (var utility in utilities)
        {
            if (!utility.Enabled.Value) continue;
            if (utility.BuildTrayGroup(CloseMenu) is { } group) root.Children.Add(Group(group));
        }

        var buttons = new Grid { ColumnSpacing = 8, Margin = new Thickness(0, root.Children.Count > 0 ? 8 : 0, 0, 0) };
        buttons.ColumnDefinitions.Add(new ColumnDefinition());
        buttons.ColumnDefinitions.Add(new ColumnDefinition());
        var open = Action(T("Settings"), "", () => { CloseMenu(); App.Shared.OpenSettings(); });
        var quit = Action(T("Quit"), "", () => App.Shared.Quit());
        Grid.SetColumn(quit, 1);
        buttons.Children.Add(open);
        buttons.Children.Add(quit);
        root.Children.Add(buttons);
    }

    /// A utility's part of the menu, on a card of the Quick Settings kind.
    private static Border Group(UIElement content) => new()
    {
        Child = content,
        Padding = new Thickness(12),
        CornerRadius = new CornerRadius(8),
        Background = (Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"],
        BorderBrush = (Brush)Application.Current.Resources["CardStrokeColorDefaultBrush"],
        BorderThickness = new Thickness(1),
    };

    private static Button Action(string title, string glyph, Action click)
    {
        var content = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        content.Children.Add(new FontIcon { Glyph = glyph, FontSize = 14 });
        content.Children.Add(new TextBlock { Text = title });
        var button = new Button { Content = content, HorizontalAlignment = HorizontalAlignment.Stretch };
        button.Click += (_, _) => click();
        return button;
    }
}
