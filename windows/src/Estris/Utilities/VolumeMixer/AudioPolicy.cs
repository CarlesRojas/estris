using System.Runtime.InteropServices;

namespace Estris.Utilities.VolumeMixer;

/// Sets the system's default device, through the undocumented but long-stable IPolicyConfig that
/// Windows's own sound settings use.
internal static class DefaultDevice
{
    private const int RoleCount = 3;

    /// For every role, as Windows's settings do: console, multimedia and communications.
    public static void Set(string deviceId)
    {
        var policy = (IPolicyConfig)new PolicyConfigClient();
        try
        {
            for (var role = 0; role < RoleCount; role++) Marshal.ThrowExceptionForHR(policy.SetDefaultEndpoint(deviceId, role));
        }
        finally { Marshal.ReleaseComObject(policy); }
    }

    [ComImport, Guid("870af99c-171d-4f9e-af0d-e63df40c2bc9")]
    private class PolicyConfigClient;

    /// Only the one call is used; the slots before it keep it in its place in the vtable.
    [ComImport, Guid("f8679f50-850a-41cf-9c72-430f290290c8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IPolicyConfig
    {
        void GetMixFormat();
        void GetDeviceFormat();
        void ResetDeviceFormat();
        void SetDeviceFormat();
        void GetProcessingPeriod();
        void SetProcessingPeriod();
        void GetShareMode();
        void SetShareMode();
        void GetPropertyValue();
        void SetPropertyValue();
        [PreserveSig] int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string deviceId, int role);
    }
}

/// Which device each process plays on, through the undocumented IAudioPolicyConfigFactory behind
/// Windows's own Volume Mixer. Its id changed in Windows 11; everything here is looked up at run
/// time and IsAvailable says whether it worked, as a later Windows may change it again.
internal static unsafe partial class AppAudioRouting
{
    private const string ClassName = "Windows.Media.Internal.AudioPolicyConfig";
    private const string RenderPrefix = @"\\?\SWD#MMDEVAPI#";
    private const string RenderSuffix = "#{e6327cad-dcec-4949-ae8a-991e976a79d2}";
    private const int FlowRender = 0;
    private const int RoleConsole = 0, RoleMultimedia = 1;
    /// After IUnknown, IInspectable and 19 methods this has no use for.
    private const int SetSlot = 25, GetSlot = 26;
    private static readonly Guid[] FactoryIds =
    [
        new("ab3d4648-e242-459f-b02f-541c70306324"),
        new("2a59116d-6c4f-45e0-a74f-707e3fef9258"),
    ];

    private static readonly nint Factory = Activate();

    public static bool IsAvailable => Factory != 0;

    private static nint Activate()
    {
        nint text = 0;
        try
        {
            WindowsCreateString(ClassName, ClassName.Length, out text);
            foreach (var id in FactoryIds)
            {
                var iid = id;
                if (RoGetActivationFactory(text, ref iid, out var factory) == 0) return factory;
            }
            return 0;
        }
        catch (Exception) { return 0; }
        finally { if (text != 0) WindowsDeleteString(text); }
    }

    /// The device chosen for a process, or null when it follows the system.
    public static string? Get(uint process)
    {
        if (Factory == 0) return null;
        var get = (delegate* unmanaged[Stdcall]<nint, uint, int, int, nint*, int>)Slot(GetSlot);
        nint device = 0;
        if (get(Factory, process, FlowRender, RoleMultimedia, &device) != 0 || device == 0) return null;
        try { return ToDeviceId(Marshal.PtrToStringUni(WindowsGetStringRawBuffer(device, out _))); }
        finally { WindowsDeleteString(device); }
    }

    /// Plays a process on a device, or back on the system's with null. Throws if it can't.
    public static void Set(uint process, string? deviceId)
    {
        var set = (delegate* unmanaged[Stdcall]<nint, uint, int, int, nint, int>)Slot(SetSlot);
        nint device = 0;
        if (deviceId is not null)
        {
            var full = RenderPrefix + deviceId + RenderSuffix;
            Marshal.ThrowExceptionForHR(WindowsCreateString(full, full.Length, out device));
        }
        try
        {
            Marshal.ThrowExceptionForHR(set(Factory, process, FlowRender, RoleConsole, device));
            Marshal.ThrowExceptionForHR(set(Factory, process, FlowRender, RoleMultimedia, device));
        }
        finally { if (device != 0) WindowsDeleteString(device); }
    }

    private static nint Slot(int index) => (*(nint**)Factory)[index];

    private static string? ToDeviceId(string? full)
    {
        if (string.IsNullOrEmpty(full)) return null;
        var start = full.IndexOf("{0.", StringComparison.Ordinal);
        var end = full.LastIndexOf("#{", StringComparison.Ordinal);
        return start >= 0 && end > start ? full[start..end] : full;
    }

    [LibraryImport("combase", StringMarshalling = StringMarshalling.Utf16)] private static partial int WindowsCreateString(string text, int length, out nint result);
    [LibraryImport("combase")] private static partial int WindowsDeleteString(nint text);
    /// The buffer belongs to the string, so this stays a pointer: a string return would free it.
    [LibraryImport("combase")] private static partial nint WindowsGetStringRawBuffer(nint text, out uint length);
    [LibraryImport("combase")] private static partial int RoGetActivationFactory(nint className, ref Guid iid, out nint factory);
}
