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
        // Estris lives in the tray: closing its last window leaves it running, and only Quit ends it.
        DispatcherShutdownMode = DispatcherShutdownMode.OnExplicitShutdown;
        UnhandledException += (_, e) =>
        {
            Fail("App", "Unhandled", e.Exception);
        };
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        try { Launch(); }
        catch (Exception e)
        {
            Fail("App", "Failed to launch", e);
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
            catch (Exception e) { Fail(utility.Title, "Failed to start", e); }
        }

        tray = new TrayIcon(TraySettings, Utilities);
        tray.Show();
        SingleInstance.ListenForSecondCopy(() => Ui.TryEnqueue(() => OpenSettings()));
        Updates.Shared.Start();
        LoginItem.ApplyOnFirstLaunch();

        if (!openedAtLogin) OpenSettings();
    }

    /// To Developer > Logs and to a file, which outlives the app.
    private void Fail(string source, string what, Exception error)
    {
        Log.Add(source, $"{what}: {error}");
        File.AppendAllText(Path.Combine(SettingsStore.Folder, "crash.log"), $"{DateTime.Now:s} {source}: {what}: {error}{Environment.NewLine}");
    }

    public void OpenSettings(string? pane = null)
    {
        settingsWindow ??= new SettingsWindow(Utilities, Log);
        settingsWindow.Closed += (_, _) => settingsWindow = null;
        settingsWindow.Open(pane);
    }

    public void Quit()
    {
        ShutDown();
        Exit();
    }

    /// Stops the utilities, removes the tray icon and saves settings, before quitting or updating.
    public void ShutDown()
    {
        foreach (var utility in Utilities)
        {
            try { utility.Stop(); }
            catch (Exception e) { Log.Add(utility.Title, $"Failed to stop: {e}"); }
        }
        tray?.Dispose();
        tray = null;
        InputHooks.Shutdown();
        SettingsStore.Shared.Flush();
    }
}
