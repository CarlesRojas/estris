using System.Runtime.InteropServices;
using Estris.Utilities.RoundedCorners;
using static Estris.Core.Loc;
using static Estris.Core.Native;

namespace Estris.Utilities.HotCorners;

/// A screen, with an ID that stays the same across restarts and reconnects: its monitor's device
/// path, which names the monitor model and the port it is plugged into.
public readonly record struct Display(string Id, string Name, RECT Bounds, uint Dpi, bool IsMain);

/// The screens, with their monitors' names and lasting IDs from the display configuration. The
/// configuration is asked again only when the screens change, as the mouse hook lists them often.
public static class Displays
{
    private const uint QDC_ONLY_ACTIVE_PATHS = 2, MONITORINFOF_PRIMARY = 1;
    private const int ERROR_INSUFFICIENT_BUFFER = 122;
    private const uint GET_SOURCE_NAME = 1, GET_TARGET_NAME = 2;
    /// Output technologies of screens built into the PC: internal, embedded DisplayPort and UDI.
    private const uint TechInternal = 0x80000000, TechDisplayPortEmbedded = 11, TechUdiEmbedded = 13;

    private static readonly object Gate = new();
    private static string signature = "";
    private static Dictionary<string, (string Path, string Name, bool IsBuiltIn)> targets = [];

    /// Every screen, left to right. With refresh, the monitors are asked again even if the screens
    /// look the same (one monitor swapped for another of the same size).
    public static List<Display> All(bool refresh = false)
    {
        var monitors = new List<(string Device, RECT Bounds, uint Dpi, bool IsMain)>();
        EnumDisplayMonitors(0, 0, (monitor, _, _, _) =>
        {
            var info = new MONITORINFOEX { cbSize = Marshal.SizeOf<MONITORINFOEX>() };
            if (GetMonitorInfo(monitor, ref info))
                monitors.Add((info.szDevice, info.rcMonitor, LayeredWindow.Dpi(monitor), (info.dwFlags & MONITORINFOF_PRIMARY) != 0));
            return true;
        }, 0);
        monitors.Sort((a, b) => a.Bounds.Left != b.Bounds.Left ? a.Bounds.Left.CompareTo(b.Bounds.Left) : a.Bounds.Top.CompareTo(b.Bounds.Top));

        Dictionary<string, (string Path, string Name, bool IsBuiltIn)> known;
        lock (Gate)
        {
            var now = string.Join(";", monitors.Select(m => $"{m.Device}@{m.Bounds.Left},{m.Bounds.Top},{m.Bounds.Right},{m.Bounds.Bottom}"));
            if (refresh || now != signature)
            {
                targets = Targets();
                signature = now;
            }
            known = targets;
        }

        var named = monitors.Select(m => known.TryGetValue(m.Device, out var t)
            ? (m, Id: t.Path.Length > 0 ? t.Path : m.Device, Name: t.Name.Length > 0 ? t.Name : t.IsBuiltIn ? T("Built-in Display") : T("Display"))
            : (m, Id: m.Device, Name: T("Display"))).ToList();
        // Two of the same monitor get numbers, left to right.
        var displays = new List<Display>();
        foreach (var (m, id, name) in named)
        {
            var same = named.Where(n => n.Name == name).ToList();
            var label = same.Count > 1 ? $"{name} ({same.FindIndex(n => n.Id == id) + 1})" : name;
            displays.Add(new Display(id, label, m.Bounds, m.Dpi, m.IsMain));
        }
        return displays;
    }

    /// Each active screen's GDI name (\\.\DISPLAY1) with its monitor's device path and name.
    private static Dictionary<string, (string Path, string Name, bool IsBuiltIn)> Targets()
    {
        var result = new Dictionary<string, (string, string, bool)>();
        DISPLAYCONFIG_PATH_INFO[] paths;
        uint pathCount, modeCount;
        int status;
        do
        {
            if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out pathCount, out modeCount) != 0) return result;
            paths = new DISPLAYCONFIG_PATH_INFO[pathCount];
            var modes = new DISPLAYCONFIG_MODE_INFO[modeCount];
            status = QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref pathCount, paths, ref modeCount, modes, 0);
        } while (status == ERROR_INSUFFICIENT_BUFFER);
        if (status != 0) return result;

        for (var i = 0; i < pathCount; i++)
        {
            var path = paths[i];
            var source = new DISPLAYCONFIG_SOURCE_DEVICE_NAME();
            source.header = new DISPLAYCONFIG_DEVICE_INFO_HEADER
            {
                type = GET_SOURCE_NAME, size = (uint)Marshal.SizeOf<DISPLAYCONFIG_SOURCE_DEVICE_NAME>(),
                adapterId = path.sourceInfo.adapterId, id = path.sourceInfo.id,
            };
            if (DisplayConfigGetDeviceInfo(ref source) != 0) continue;
            // A screen mirrored onto two monitors keeps the first.
            if (result.ContainsKey(source.viewGdiDeviceName)) continue;
            var target = new DISPLAYCONFIG_TARGET_DEVICE_NAME();
            target.header = new DISPLAYCONFIG_DEVICE_INFO_HEADER
            {
                type = GET_TARGET_NAME, size = (uint)Marshal.SizeOf<DISPLAYCONFIG_TARGET_DEVICE_NAME>(),
                adapterId = path.targetInfo.adapterId, id = path.targetInfo.id,
            };
            if (DisplayConfigGetDeviceInfo(ref target) != 0) continue;
            var tech = target.outputTechnology;
            var isBuiltIn = tech is TechInternal or TechDisplayPortEmbedded or TechUdiEmbedded;
            result[source.viewGdiDeviceName] = (target.monitorDevicePath ?? "", target.monitorFriendlyDeviceName ?? "", isBuiltIn);
        }
        return result;
    }

    private delegate bool MonitorCallback(nint monitor, nint dc, nint rect, nint data);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct MONITORINFOEX
    {
        public int cbSize;
        public RECT rcMonitor, rcWork;
        public uint dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string szDevice;
    }

    [StructLayout(LayoutKind.Sequential)] private struct LUID { public uint LowPart; public int HighPart; }
    [StructLayout(LayoutKind.Sequential)] private struct DISPLAYCONFIG_RATIONAL { public uint Numerator, Denominator; }

    [StructLayout(LayoutKind.Sequential)]
    private struct DISPLAYCONFIG_PATH_SOURCE_INFO { public LUID adapterId; public uint id, modeInfoIdx, statusFlags; }

    [StructLayout(LayoutKind.Sequential)]
    private struct DISPLAYCONFIG_PATH_TARGET_INFO
    {
        public LUID adapterId;
        public uint id, modeInfoIdx, outputTechnology, rotation, scaling;
        public DISPLAYCONFIG_RATIONAL refreshRate;
        public uint scanLineOrdering;
        public int targetAvailable;
        public uint statusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DISPLAYCONFIG_PATH_INFO { public DISPLAYCONFIG_PATH_SOURCE_INFO sourceInfo; public DISPLAYCONFIG_PATH_TARGET_INFO targetInfo; public uint flags; }

    /// Only its size matters: the modes aren't read.
    [StructLayout(LayoutKind.Sequential, Size = 64)] private struct DISPLAYCONFIG_MODE_INFO { public uint infoType; }

    [StructLayout(LayoutKind.Sequential)]
    private struct DISPLAYCONFIG_DEVICE_INFO_HEADER { public uint type, size; public LUID adapterId; public uint id; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct DISPLAYCONFIG_SOURCE_DEVICE_NAME
    {
        public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string viewGdiDeviceName;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct DISPLAYCONFIG_TARGET_DEVICE_NAME
    {
        public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
        public uint flags, outputTechnology;
        public ushort edidManufactureId, edidProductCodeId;
        public uint connectorInstance;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string monitorFriendlyDeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string monitorDevicePath;
    }

    [DllImport("user32")] private static extern bool EnumDisplayMonitors(nint dc, nint clip, MonitorCallback callback, nint data);
    [DllImport("user32", CharSet = CharSet.Unicode, EntryPoint = "GetMonitorInfoW")] private static extern bool GetMonitorInfo(nint monitor, ref MONITORINFOEX info);
    [DllImport("user32")] private static extern int GetDisplayConfigBufferSizes(uint flags, out uint pathCount, out uint modeCount);
    [DllImport("user32")]
    private static extern int QueryDisplayConfig(uint flags, ref uint pathCount, [Out] DISPLAYCONFIG_PATH_INFO[] paths, ref uint modeCount, [Out] DISPLAYCONFIG_MODE_INFO[] modes, nint topology);
    [DllImport("user32")] private static extern int DisplayConfigGetDeviceInfo(ref DISPLAYCONFIG_SOURCE_DEVICE_NAME request);
    [DllImport("user32")] private static extern int DisplayConfigGetDeviceInfo(ref DISPLAYCONFIG_TARGET_DEVICE_NAME request);
}
