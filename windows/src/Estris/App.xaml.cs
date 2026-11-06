using Estris.Core;
using Estris.Tray;
using Estris.Ui;
using Estris.Utilities;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;

namespace Estris;

/// Creates the utilities, the tray icon and, when asked for, the Settings window.
public partial class App : Application
{
    public static App Shared => (App)Current;
    public static DispatcherQueue Ui { get; private set; } = null!;

    public AppLog Log { get; } = new();
    public IReadOnlyList<IUtility> Utilities { get; private set; } = [];
    public TraySettings TraySettings { get; } = new();

    private readonly bool openedAtLogin;
    private TrayIcon? tray;
    private SettingsWindow? settingsWindow;

    public App(bool openedAtLogin)
    {
        this.openedAtLogin = openedAtLogin;
        InitializeComponent();
        UnhandledException += (_, e) =>
        {
            Log.Add("App", $"Unhandled: {e.Exception}");
            File.AppendAllText(Path.Combine(SettingsStore.Folder, "crash.log"), $"{DateTime.Now:s} {e.Exception}{Environment.NewLine}");
        };
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        try { Launch(); }
        catch (Exception e)
        {
            File.AppendAllText(Path.Combine(SettingsStore.Folder, "crash.log"), $"{DateTime.Now:s} {e}{Environment.NewLine}");
            throw;
        }
    }

    private void Launch()
    {
        Ui = DispatcherQueue.GetForCurrentThread();
        Utilities = UtilityList.Create(Log);
        foreach (var utility in Utilities)
        {
            try { utility.Start(); }
            catch (Exception e) { Log.Add(utility.Title, $"Failed to start: {e}"); }
        }

        tray = new TrayIcon(TraySettings, Utilities);
        tray.Show();
        SingleInstance.ListenForSecondCopy(() => Ui.TryEnqueue(() => OpenSettings()));
        Updates.Shared.Start();
        LoginItem.ApplyOnFirstLaunch();

        if (!openedAtLogin) OpenSettings();
    }

    public void OpenSettings(string? pane = null)
    {
        settingsWindow ??= new SettingsWindow(Utilities, Log);
        settingsWindow.Closed += (_, _) => settingsWindow = null;
        settingsWindow.Open(pane);
    }

    public void Quit()
    {
        foreach (var utility in Utilities)
        {
            try { utility.Stop(); }
            catch (Exception e) { Log.Add(utility.Title, $"Failed to stop: {e}"); }
        }
        tray?.Dispose();
        InputHooks.Shutdown();
        SettingsStore.Shared.Flush();
        Exit();
    }
}
