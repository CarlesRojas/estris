using System.Drawing;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Text;

namespace Estris.Core;

/// The apps a person would recognise: everything in the Start menu, for Excluded Apps lists.
/// Each is keyed by its lowercase program name ("chrome.exe"), which is what utilities compare
/// with Native.WindowApp.
public static class InstalledApps
{
    public sealed record App(string Name, string Program, string Path);

    private static IReadOnlyList<App>? cache;

    public static IReadOnlyList<App> All => cache ??= Load();

    private static List<App> Load()
    {
        var folders = new[]
        {
            Environment.GetFolderPath(Environment.SpecialFolder.CommonStartMenu),
            Environment.GetFolderPath(Environment.SpecialFolder.StartMenu),
        };
        var apps = new Dictionary<string, App>();
        foreach (var folder in folders)
        {
            if (!Directory.Exists(folder)) continue;
            foreach (var link in Directory.EnumerateFiles(folder, "*.lnk", SearchOption.AllDirectories))
            {
                var target = LinkTarget(link);
                if (target is null || !target.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) continue;
                var name = System.IO.Path.GetFileNameWithoutExtension(link);
                if (name.Contains("uninstall", StringComparison.OrdinalIgnoreCase)) continue;
                var program = System.IO.Path.GetFileName(target).ToLowerInvariant();
                apps.TryAdd(program, new App(name, program, target));
            }
        }
        return apps.Values.OrderBy(a => a.Name, StringComparer.CurrentCultureIgnoreCase).ToList();
    }

    [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
    private class ShellLink;

    [ComImport, Guid("000214F9-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellLinkW
    {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder file, int size, nint data, uint flags);
    }

    private static string? LinkTarget(string link)
    {
        try
        {
            var shell = new ShellLink();
            ((IPersistFile)shell).Load(link, 0);
            var path = new StringBuilder(1024);
            ((IShellLinkW)shell).GetPath(path, path.Capacity, 0, 0);
            Marshal.FinalReleaseComObject(shell);
            return path.Length > 0 ? path.ToString() : null;
        }
        catch (Exception) { return null; }
    }

    /// A program's icon as a bitmap, or null.
    public static Bitmap? Icon(string path)
    {
        try { return System.Drawing.Icon.ExtractAssociatedIcon(path)?.ToBitmap(); }
        catch (Exception) { return null; }
    }
}
