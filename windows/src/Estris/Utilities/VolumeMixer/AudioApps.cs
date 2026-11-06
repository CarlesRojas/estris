using System.Diagnostics;
using System.Runtime.InteropServices;
using Estris.Core;
using static Estris.Core.Native;

namespace Estris.Utilities.VolumeMixer;

/// The app a process plays for: helpers that play on an app's behalf (a browser's audio process)
/// count as the app, as the first process up its parents that has a window.
internal static partial class AudioApps
{
    /// What a process's sound is saved and listed under: its lowercase program name, as Excluded
    /// Apps use, its name for people, and the program, for its icon.
    public sealed record Identity(string Key, string Name, string? Path);

    private const int MaxParents = 6;
    private const string Shell = "explorer.exe";

    public static Identity Find(uint process)
    {
        var parents = ParentsByProcess();
        var withWindows = ProcessesWithWindows();
        var current = process;
        for (var depth = 0; depth < MaxParents && current != 0; depth++)
        {
            if (withWindows.Contains(current) && Describe(current) is { } owner && owner.Key != Shell) return owner;
            if (!parents.TryGetValue(current, out current)) break;
        }
        return Describe(process) ?? new Identity(process.ToString(), process.ToString(), null);
    }

    private static Identity? Describe(uint process)
    {
        var path = ProcessPath(process);
        if (path is null)
        {
            // Elevated: its path can't be read, its name can.
            try
            {
                var name = Process.GetProcessById((int)process).ProcessName;
                return new Identity(name.ToLowerInvariant() + ".exe", name, null);
            }
            catch (Exception) { return null; }
        }
        var key = Path.GetFileName(path).ToLowerInvariant();
        return new Identity(key, DisplayName(key, path), path);
    }

    /// The Start menu's name, else the program's own description, else its file name.
    private static string DisplayName(string key, string path)
    {
        if (InstalledApps.All.FirstOrDefault(app => app.Program == key) is { } installed) return installed.Name;
        var description = FileVersionInfo.GetVersionInfo(path).FileDescription;
        return string.IsNullOrWhiteSpace(description) ? Path.GetFileNameWithoutExtension(path) : description;
    }

    private static HashSet<uint> ProcessesWithWindows()
    {
        var found = new HashSet<uint>();
        EnumWindows((hwnd, _) =>
        {
            if (IsWindowVisible(hwnd))
            {
                GetWindowThreadProcessId(hwnd, out var process);
                found.Add(process);
            }
            return true;
        }, 0);
        return found;
    }

    private static Dictionary<uint, uint> ParentsByProcess()
    {
        var parents = new Dictionary<uint, uint>();
        var snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if (snapshot == InvalidHandle) return parents;
        try
        {
            var entry = new PROCESSENTRY32 { dwSize = (uint)Marshal.SizeOf<PROCESSENTRY32>() };
            for (var more = Process32First(snapshot, ref entry); more; more = Process32Next(snapshot, ref entry))
                parents[entry.th32ProcessID] = entry.th32ParentProcessID;
        }
        finally { CloseHandle(snapshot); }
        return parents;
    }

    private const uint TH32CS_SNAPPROCESS = 2;
    private static readonly nint InvalidHandle = -1;

    private delegate bool WindowCallback(nint hwnd, nint data);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct PROCESSENTRY32
    {
        public uint dwSize, cntUsage, th32ProcessID;
        public nuint th32DefaultHeapID;
        public uint th32ModuleID, cntThreads, th32ParentProcessID;
        public int pcPriClassBase;
        public uint dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szExeFile;
    }

    [DllImport("user32")] private static extern bool EnumWindows(WindowCallback callback, nint data);
    [DllImport("kernel32", SetLastError = true)] private static extern nint CreateToolhelp32Snapshot(uint flags, uint process);
    [DllImport("kernel32", CharSet = CharSet.Unicode, EntryPoint = "Process32FirstW")] private static extern bool Process32First(nint snapshot, ref PROCESSENTRY32 entry);
    [DllImport("kernel32", CharSet = CharSet.Unicode, EntryPoint = "Process32NextW")] private static extern bool Process32Next(nint snapshot, ref PROCESSENTRY32 entry);
}
