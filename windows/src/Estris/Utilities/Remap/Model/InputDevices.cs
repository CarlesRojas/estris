using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using Estris.Core;
using Microsoft.Win32;

namespace Estris.Utilities.Remap;

public enum DeviceKind { Keyboard, Mouse }

/// A keyboard or pointing device, made of one or more interfaces. HasKeyboard: one of them is a
/// keyboard, as on receivers and many mice.
public sealed record InputDevice(string Id, string Name, DeviceKind Kind, bool IsConnected = true, bool HasKeyboard = false)
{
    private const string KeyboardGlyph = "", MouseGlyph = "", TouchpadGlyph = "";

    public string Glyph => Kind == DeviceKind.Keyboard ? KeyboardGlyph
        : Name.Contains("touchpad", StringComparison.OrdinalIgnoreCase) || Name.Contains("trackpad", StringComparison.OrdinalIgnoreCase) ? TouchpadGlyph
        : MouseGlyph;

    /// Vendor, product and name, so a device keeps its mappings across reconnects, and identical
    /// devices share them.
    public static string MakeId(int vendor, int product, string name) => $"{vendor}-{product}-{name}";

    /// The vendor and product an id was made from.
    public static (int Vendor, int Product)? VendorAndProduct(string id)
    {
        var parts = id.Split('-', 3);
        return parts.Length == 3 && int.TryParse(parts[0], out var vendor) && int.TryParse(parts[1], out var product) ? (vendor, product) : null;
    }
}

/// The connected keyboards and mice from Raw Input, and which device each handle belongs to.
/// Every interface of a physical device counts as that device. Safe to read from any thread.
public sealed partial class InputDevices(AppLog log)
{
    private const uint RIM_TYPEMOUSE = 0, RIM_TYPEKEYBOARD = 1;
    private const uint RIDI_DEVICENAME = 0x20000007;
    private const uint OPEN_EXISTING = 3, FILE_SHARE_READ_WRITE = 3;
    private const int HidStringBytes = 512;
    private static readonly nint InvalidHandle = -1;
    private const string RemoteDesktopInterface = "RDP_";

    [StructLayout(LayoutKind.Sequential)]
    private struct RAWINPUTDEVICELIST { public nint Device; public uint Type; }

    [StructLayout(LayoutKind.Sequential)]
    private struct HIDD_ATTRIBUTES { public int Size; public ushort VendorID, ProductID, VersionNumber; }

    [DllImport("user32", SetLastError = true)]
    private static extern uint GetRawInputDeviceList([Out] RAWINPUTDEVICELIST[]? list, ref uint count, uint size);

    [DllImport("user32", SetLastError = true, CharSet = CharSet.Unicode, EntryPoint = "GetRawInputDeviceInfoW")]
    private static extern uint GetRawInputDeviceInfo(nint device, uint command, StringBuilder? data, ref uint size);

    [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode, EntryPoint = "CreateFileW")]
    private static extern nint CreateFile(string path, uint access, uint share, nint security, uint disposition, uint flags, nint template);

    [DllImport("hid")]
    private static extern bool HidD_GetAttributes(nint device, ref HIDD_ATTRIBUTES attributes);

    [DllImport("hid", CharSet = CharSet.Unicode)]
    private static extern bool HidD_GetProductString(nint device, StringBuilder buffer, uint length);

    [DllImport("hid", CharSet = CharSet.Unicode)]
    private static extern bool HidD_GetManufacturerString(nint device, StringBuilder buffer, uint length);

    private sealed record Interface(nint Handle, bool IsKeyboard, string Path, int Vendor, int Product, string Name);

    private readonly object refreshGate = new();
    private volatile IReadOnlyList<InputDevice> connected = [];
    private volatile IReadOnlyDictionary<nint, InputDevice> byHandle = new Dictionary<nint, InputDevice>();
    private string logged = "";

    public IReadOnlyList<InputDevice> Connected => connected;

    /// Runs on whichever thread refreshed, when the list changed.
    public event Action? Changed;

    public InputDevice? Device(nint handle) => byHandle.GetValueOrDefault(handle);

    /// Lists the devices again. known holds those with mappings, by id and name: an interface
    /// with no product name (a wireless keyboard just after Windows starts) is taken as the known
    /// device with its vendor and product, so its mappings still apply.
    public void Refresh(IReadOnlyDictionary<string, string> known)
    {
        lock (refreshGate)
        {
            var interfaces = ReadInterfaces();
            var knownByModel = new Dictionary<(int, int), (string Id, string Name)>();
            foreach (var (id, name) in known)
                if (InputDevice.VendorAndProduct(id) is { } model) knownByModel.TryAdd(model, (id, name));

            var groups = new Dictionary<string, (string Name, List<Interface> Parts)>();
            foreach (var part in interfaces)
            {
                var (id, name) = part.Name != ""
                    ? (InputDevice.MakeId(part.Vendor, part.Product, part.Name), part.Name)
                    : part.Vendor != 0 && knownByModel.TryGetValue((part.Vendor, part.Product), out var match) ? (match.Id, match.Name)
                    : (null, "");
                if (id is null)
                {
                    var fallback = RegistryDescription(part.Path);
                    if (fallback == "") continue;
                    (id, name) = (InputDevice.MakeId(part.Vendor, part.Product, fallback), fallback);
                }
                if (!groups.TryGetValue(id, out var group)) groups[id] = group = (name, []);
                group.Parts.Add(part);
            }

            var devices = new List<InputDevice>();
            var handles = new Dictionary<nint, InputDevice>();
            foreach (var (id, (name, parts)) in groups)
            {
                var hasKeyboard = parts.Any(p => p.IsKeyboard);
                var hasPointer = parts.Any(p => !p.IsKeyboard);
                var isKeyboard = hasKeyboard && (!hasPointer || name.Contains("keyboard", StringComparison.OrdinalIgnoreCase) || parts.MinBy(InterfaceNumber)!.IsKeyboard);
                var device = new InputDevice(id, name, isKeyboard ? DeviceKind.Keyboard : DeviceKind.Mouse, HasKeyboard: hasKeyboard);
                devices.Add(device);
                foreach (var part in parts) handles[part.Handle] = device;
            }
            devices.Sort((a, b) => string.Compare(a.Name, b.Name, StringComparison.CurrentCultureIgnoreCase));

            byHandle = handles;
            var hasChanged = !devices.SequenceEqual(connected);
            connected = devices;
            LogInterfaces(interfaces, handles);
            if (hasChanged) Changed?.Invoke();
        }
    }

    /// Says what Windows reports, so a missing or unexpected device can be traced. Only when it
    /// changed since the last time.
    private void LogInterfaces(List<Interface> interfaces, Dictionary<nint, InputDevice> handles)
    {
        var text = string.Join("\n", interfaces.Select(p => $"{(p.IsKeyboard ? "keyboard" : "pointer")} {p.Vendor:X4}:{p.Product:X4} \"{p.Name}\" -> {handles.GetValueOrDefault(p.Handle)?.Name ?? "not listed"} ({p.Path})"));
        if (text == logged) return;
        logged = text;
        log.Add("Remap", $"input interfaces ({interfaces.Count}):\n{text}");
    }

    private static List<Interface> ReadInterfaces()
    {
        var size = (uint)Marshal.SizeOf<RAWINPUTDEVICELIST>();
        uint count = 0;
        GetRawInputDeviceList(null, ref count, size);
        var list = new RAWINPUTDEVICELIST[count];
        count = GetRawInputDeviceList(list, ref count, size);
        var result = new List<Interface>();
        if (count == uint.MaxValue) return result;
        for (var i = 0; i < count; i++)
        {
            if (list[i].Type is not (RIM_TYPEKEYBOARD or RIM_TYPEMOUSE)) continue;
            var path = DevicePath(list[i].Device);
            if (path == "" || path.Contains(RemoteDesktopInterface, StringComparison.OrdinalIgnoreCase)) continue;
            var (vendor, product, name) = ReadHid(path);
            result.Add(new Interface(list[i].Device, list[i].Type == RIM_TYPEKEYBOARD, path, vendor, product, name));
        }
        return result;
    }

    private static string DevicePath(nint device)
    {
        uint size = 0;
        GetRawInputDeviceInfo(device, RIDI_DEVICENAME, null, ref size);
        if (size == 0) return "";
        var path = new StringBuilder((int)size);
        return GetRawInputDeviceInfo(device, RIDI_DEVICENAME, path, ref size) == uint.MaxValue ? "" : path.ToString();
    }

    /// Vendor, product and product name from the HID driver, with the IDs from the path when it
    /// won't open (a PS/2 keyboard isn't HID).
    private static (int Vendor, int Product, string Name) ReadHid(string path)
    {
        var (vendor, product) = IdsInPath(path);
        var handle = CreateFile(path, 0, FILE_SHARE_READ_WRITE, 0, OPEN_EXISTING, 0, 0);
        if (handle == InvalidHandle) return (vendor, product, "");
        try
        {
            var attributes = new HIDD_ATTRIBUTES { Size = Marshal.SizeOf<HIDD_ATTRIBUTES>() };
            if (HidD_GetAttributes(handle, ref attributes)) (vendor, product) = (attributes.VendorID, attributes.ProductID);
            var maker = HidString(handle, HidD_GetManufacturerString);
            var name = HidString(handle, HidD_GetProductString);
            if (maker != "" && name != "" && !name.Contains(maker.Split(' ')[0], StringComparison.OrdinalIgnoreCase)) name = $"{maker} {name}";
            return (vendor, product, name);
        }
        finally { Native.CloseHandle(handle); }
    }

    private static string HidString(nint device, Func<nint, StringBuilder, uint, bool> read)
    {
        var text = new StringBuilder(HidStringBytes / 2);
        return read(device, text, HidStringBytes) ? text.ToString().Trim() : "";
    }

    /// A USB device's main function comes first: a wireless keyboard's receiver and a mouse's both
    /// offer a keyboard and a pointer, but only the first has the keyboard as its interface 0.
    private static int InterfaceNumber(Interface part)
    {
        var match = InterfaceNumberPattern().Match(part.Path);
        return match.Success ? Convert.ToInt32(match.Groups[1].Value, 16) : int.MaxValue;
    }

    private static (int Vendor, int Product) IdsInPath(string path)
    {
        var match = VendorProductPattern().Match(path);
        return match.Success ? (Convert.ToInt32(match.Groups[1].Value, 16), Convert.ToInt32(match.Groups[2].Value, 16)) : (0, 0);
    }

    /// What Device Manager calls it, for interfaces that don't name themselves.
    private static string RegistryDescription(string path)
    {
        var parts = path.TrimStart('\\', '?').Split('#');
        if (parts.Length < 3) return "";
        using var key = Registry.LocalMachine.OpenSubKey($@"SYSTEM\CurrentControlSet\Enum\{parts[0]}\{parts[1]}\{parts[2]}");
        var text = (key?.GetValue("FriendlyName") ?? key?.GetValue("DeviceDesc")) as string ?? "";
        return text[(text.LastIndexOf(';') + 1)..].Trim();
    }

    [GeneratedRegex("VID[_&](?:[0-9A-Fa-f]{4})?([0-9A-Fa-f]{4}).*?PID[_&]([0-9A-Fa-f]{4})", RegexOptions.IgnoreCase)]
    private static partial Regex VendorProductPattern();

    [GeneratedRegex("MI_([0-9A-Fa-f]{2})", RegexOptions.IgnoreCase)]
    private static partial Regex InterfaceNumberPattern();
}
