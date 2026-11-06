using Estris.Core;
using static Estris.Core.Loc;

namespace Estris.Utilities.AutoQuit;

public sealed class AutoQuitSettings
{
    /// How long an app may sit with no windows before it is quit, by the id it is saved under.
    public static readonly (string Id, double Seconds)[] Delays =
    [
        ("immediately", 0), ("oneSecond", 1), ("fiveSeconds", 5), ("thirtySeconds", 30),
    ];

    /// What must keep running without windows: the shell and what Windows runs apps' windows
    /// in, as program names; anything in the Windows folder counts too.
    private static readonly HashSet<string> AlwaysKept =
    [
        "explorer.exe", "estris.exe", "applicationframehost.exe", "conhost.exe", "openconsole.exe", "windowsterminal.exe",
        "cmd.exe", "powershell.exe", "pwsh.exe", "wsl.exe", "wslhost.exe", "msedgewebview2.exe",
    ];

    private static readonly SettingsStore Store = SettingsStore.Shared;
    private static readonly string WindowsFolder = Environment.GetFolderPath(Environment.SpecialFolder.Windows) + Path.DirectorySeparatorChar;

    public Setting<bool> Enabled { get; } = Store.Get("autoQuitEnabled", false);
    public Setting<string> Delay { get; } = Store.Get("autoQuitDelay", "oneSecond");
    /// Programs that are never quit.
    public Setting<List<string>> ExcludedApps { get; } = Store.Get("autoQuitExcludedApps", new List<string>());

    public double DelaySeconds => Array.Find(Delays, d => d.Id == Delay.Value).Seconds;

    public static string DelayTitle(string id) => id switch
    {
        "immediately" => T("Immediately"),
        "oneSecond" => T("After 1 second"),
        "fiveSeconds" => T("After 5 seconds"),
        _ => T("After 30 seconds"),
    };

    /// Whether a program is the shell or part of Windows, which is never quit.
    public static bool IsAlwaysKept(string path) =>
        AlwaysKept.Contains(Path.GetFileName(path).ToLowerInvariant())
        || path.StartsWith(WindowsFolder, StringComparison.OrdinalIgnoreCase);

    public bool KeepsRunning(string path) =>
        IsAlwaysKept(path) || ExcludedApps.Value.Contains(Path.GetFileName(path).ToLowerInvariant());

    /// Back to the default delay; the on/off switch and excluded apps stay as they are.
    public void Reset() => Delay.Reset();
}
