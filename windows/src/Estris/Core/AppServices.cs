using System.Diagnostics;
using System.IO.Pipes;
using Microsoft.Win32;
using Velopack;
using Velopack.Sources;

namespace Estris.Core;

/// One copy at a time: a second one tells the first to open Settings, as the Mac's reopen does.
public static class SingleInstance
{
    private const string Name = "Estris.SingleInstance";
    private static Mutex? mutex;

    public static bool TryBecomeFirst()
    {
        mutex = new Mutex(true, Name, out var isFirst);
        return isFirst;
    }

    public static void AskFirstToOpenSettings()
    {
        try
        {
            using var pipe = new NamedPipeClientStream(".", Name, PipeDirection.Out);
            pipe.Connect(1000);
        }
        catch (Exception) { /* It is quitting: nothing to tell. */ }
    }

    public static void ListenForSecondCopy(Action open) => _ = Task.Run(async () =>
    {
        while (true)
        {
            using var pipe = new NamedPipeServerStream(Name, PipeDirection.In, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous);
            await pipe.WaitForConnectionAsync();
            open();
        }
    });

    /// Opens Estris again: a language change or imported settings apply at launch.
    public static void Relaunch(string? argument = null)
    {
        mutex?.ReleaseMutex();
        mutex?.Dispose();
        mutex = null;
        Process.Start(new ProcessStartInfo(Environment.ProcessPath!, argument ?? "") { UseShellExecute = false });
        App.Shared.Quit();
    }
}

/// Open at login: the current user's Run key. On by default, set once on the first launch.
public static class LoginItem
{
    public const string Argument = "--login";
    private const string Key = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private static readonly Setting<bool> WasSetUp = SettingsStore.Shared.Get("local.loginItemSetUp", false);

    public static bool IsEnabled
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(Key);
            return key?.GetValue("Estris") is not null;
        }
        set
        {
            using var key = Registry.CurrentUser.CreateSubKey(Key);
            if (value) key.SetValue("Estris", $"\"{Environment.ProcessPath}\" {Argument}");
            else key.DeleteValue("Estris", false);
        }
    }

    /// When uninstalling: nothing left pointing at a program that's gone, and a later install
    /// starts with Windows again, as a first install does.
    public static void Forget()
    {
        IsEnabled = false;
        WasSetUp.Value = false;
        SettingsStore.Shared.Flush();
    }

    public static void ApplyOnFirstLaunch()
    {
        // Only for an installed copy, so a development build doesn't add itself.
        if (WasSetUp.Value || !Updates.Shared.IsInstalled) return;
        WasSetUp.Value = true;
        IsEnabled = true;
    }
}

/// What looking for a new version found.
public enum UpdateCheck { UpToDate, Available, Failed }

/// Updates through Velopack, from the rolling windows-latest release: the same idea as the
/// Mac's Sparkle. Looks at launch and every 6 hours; a new version shows at the top of the
/// tray menu and in General > About with an Update button, which opens the update window.
public sealed class Updates
{
    public static Updates Shared { get; } = new();

    private const string Feed = "https://github.com/CarlesRojas/estris/releases/download/windows-latest/";
    private readonly UpdateManager manager = new(new SimpleWebSource(Feed));
    private UpdateInfo? pending;
    private Timer? timer;

    public event Action? Changed;

    public bool IsInstalled => manager.IsInstalled;
    public string Version => manager.CurrentVersion?.ToString() ?? typeof(Updates).Assembly.GetName().Version?.ToString(3) ?? "0.0.0";
    public string? AvailableVersion => pending?.TargetFullRelease.Version.ToString();
    /// The new version's notes, in Markdown, as the release workflow wrote them.
    public string? AvailableNotes => pending?.TargetFullRelease.NotesMarkdown;

    public void Start()
    {
        if (IsInstalled) timer = new Timer(_ => _ = Check(), null, TimeSpan.FromSeconds(10), TimeSpan.FromHours(6));
    }

    public async Task<UpdateCheck> Check()
    {
        if (!IsInstalled) return UpdateCheck.UpToDate;
        try
        {
            pending = await manager.CheckForUpdatesAsync();
            App.Ui.TryEnqueue(() => Changed?.Invoke());
            return pending is null ? UpdateCheck.UpToDate : UpdateCheck.Available;
        }
        catch (Exception e)
        {
            App.Shared.Log.Add("Updates", $"Check failed: {e.Message}");
            return UpdateCheck.Failed;
        }
    }

    /// Downloads the new version, reporting 0 to 100, then installs it and opens Estris again.
    /// False if it couldn't.
    public async Task<bool> Install(Action<int> progress)
    {
        if (pending is null) return false;
        try
        {
            await manager.DownloadUpdatesAsync(pending, progress);
            App.Shared.ShutDown();
            manager.ApplyUpdatesAndRestart(pending);
            return true;
        }
        catch (Exception e)
        {
            App.Shared.Log.Add("Updates", $"Install failed: {e.Message}");
            return false;
        }
    }
}
