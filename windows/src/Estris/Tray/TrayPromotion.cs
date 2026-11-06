using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace Estris.Tray;

/// Windows 11 tucks a new tray icon into the hidden icons menu until the person moves it out.
/// Estris shows itself in the taskbar instead, once per copy, and then leaves the choice to them.
public static class TrayPromotion
{
    private const string Key = @"Control Panel\NotifyIconSettings";
    private const int Attempts = 10;
    private static readonly TimeSpan Interval = TimeSpan.FromMilliseconds(500);

    [DllImport("shell32")]
    private static extern int SHGetKnownFolderPath(ref Guid id, uint flags, nint token, out nint path);

    /// Windows writes the icon's entry shortly after it's added, so this looks for it a few times.
    public static async void PromoteWhenListed()
    {
        for (var attempt = 0; attempt < Attempts; attempt++)
        {
            if (TryPromote()) return;
            await Task.Delay(Interval);
        }
    }

    /// True once this copy's entry is found. Only an entry the person never changed is promoted.
    private static bool TryPromote()
    {
        using var icons = Registry.CurrentUser.OpenSubKey(Key);
        if (icons is null) return false;
        foreach (var name in icons.GetSubKeyNames())
        {
            using var entry = icons.OpenSubKey(name, writable: true);
            if (entry?.GetValue("ExecutablePath") is not string path || !IsThisCopy(path)) continue;
            if (entry.GetValue("IsPromoted") is null) entry.SetValue("IsPromoted", 1, RegistryValueKind.DWord);
            return true;
        }
        return false;
    }

    /// Windows stores paths inside known folders as "{folder id}\rest", so those are expanded first.
    private static bool IsThisCopy(string path)
    {
        if (path.StartsWith('{') && path.IndexOf('}') is var end and > 0 && Guid.TryParse(path[..(end + 1)], out var folder)
            && SHGetKnownFolderPath(ref folder, 0, 0, out var folderPath) == 0)
        {
            try { path = Path.Join(Marshal.PtrToStringUni(folderPath), path[(end + 1)..]); }
            finally { Marshal.FreeCoTaskMem(folderPath); }
        }
        return string.Equals(Path.GetFullPath(path), Environment.ProcessPath, StringComparison.OrdinalIgnoreCase);
    }
}
