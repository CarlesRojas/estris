using System.Runtime.InteropServices;
using Estris.Core;
using static Estris.Core.Native;

namespace Estris.Utilities.HotCorners;

/// The buttons on a screen's taskbar, pressed through UI Automation. The shell's shortcuts (Win,
/// Win+S, Win+N) open Start, Search and Notification Center on the main screen whichever screen
/// the pointer is on, while each taskbar's own buttons open them on that screen. Slow enough
/// (tens of milliseconds) to keep off the UI thread.
internal static partial class TaskbarButtons
{
    public const string Start = "StartButton";
    /// Notification Center opens from the clock, which every taskbar has.
    public const string Clock = "SystemTray.OmniButtonLeft";

    private const int AutomationIdProperty = 30011, ClassNameProperty = 30012;
    private const int InvokePattern = 10000, TogglePattern = 10015;
    private const int TreeScopeDescendants = 4;
    private const uint MONITOR_DEFAULTTONEAREST = 2;

    private static readonly Lazy<IUIAutomation?> Automation = new(() =>
    {
        try { return (IUIAutomation)new CUIAutomation(); }
        catch (COMException) { return null; }
    });

    /// Presses the button with that automation id or class name on the taskbar of the screen
    /// holding that point. False when that screen has no taskbar or no such button.
    public static bool Press(POINT onScreen, string button)
    {
        var taskbar = TaskbarOn(MonitorFromPoint(onScreen, MONITOR_DEFAULTTONEAREST));
        if (taskbar == 0 || Automation.Value is not { } automation) return false;
        try
        {
            var root = automation.ElementFromHandle(taskbar);
            var property = button.Contains('.') ? ClassNameProperty : AutomationIdProperty;
            var element = root.FindFirst(TreeScopeDescendants, automation.CreatePropertyCondition(property, button));
            if (element is null) return false;
            if (element.GetCurrentPattern(TogglePattern) is IUIAutomationTogglePattern toggle) toggle.Toggle();
            else if (element.GetCurrentPattern(InvokePattern) is IUIAutomationInvokePattern invoke) invoke.Invoke();
            else return false;
            return true;
        }
        catch (COMException) { return false; }
    }

    /// The main taskbar or a secondary one, whichever is on that monitor.
    private static nint TaskbarOn(nint monitor)
    {
        var main = FindWindowEx(0, 0, "Shell_TrayWnd", null);
        if (main != 0 && MonitorFromWindow(main, MONITOR_DEFAULTTONEAREST) == monitor) return main;
        for (var bar = FindWindowEx(0, 0, "Shell_SecondaryTrayWnd", null); bar != 0; bar = FindWindowEx(0, bar, "Shell_SecondaryTrayWnd", null))
            if (MonitorFromWindow(bar, MONITOR_DEFAULTTONEAREST) == monitor) return bar;
        return 0;
    }

    [LibraryImport("user32", EntryPoint = "FindWindowExW", StringMarshalling = StringMarshalling.Utf16)]
    private static partial nint FindWindowEx(nint parent, nint after, string className, string? title);

    [LibraryImport("user32")] private static partial nint MonitorFromWindow(nint hwnd, uint flags);

    // UI Automation's COM interfaces, as far as needed here; the placeholders keep the vtable order.

    [ComImport, Guid("ff48dba4-60ef-4201-aa87-54103eef594e")]
    private class CUIAutomation;

    [ComImport, Guid("30cbe57d-d9d0-452a-ab13-7ac5ac4825ee"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IUIAutomation
    {
        void CompareElements();
        void CompareRuntimeIds();
        void GetRootElement();
        IUIAutomationElement ElementFromHandle(nint hwnd);
        void ElementFromPoint();
        void GetFocusedElement();
        void GetRootElementBuildCache();
        void ElementFromHandleBuildCache();
        void ElementFromPointBuildCache();
        void GetFocusedElementBuildCache();
        void CreateTreeWalker();
        void ControlViewWalker();
        void ContentViewWalker();
        void RawViewWalker();
        void RawViewCondition();
        void ControlViewCondition();
        void ContentViewCondition();
        void CreateCacheRequest();
        void CreateTrueCondition();
        void CreateFalseCondition();
        IUIAutomationCondition CreatePropertyCondition(int property, [MarshalAs(UnmanagedType.Struct)] object value);
    }

    [ComImport, Guid("352ffba8-0973-437c-a61f-f64cafd81df9"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IUIAutomationCondition;

    [ComImport, Guid("d22108aa-8ac5-49a5-837b-37bbb3d7591e"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IUIAutomationElement
    {
        void SetFocus();
        void GetRuntimeId();
        IUIAutomationElement? FindFirst(int scope, IUIAutomationCondition condition);
        void FindAll();
        void FindFirstBuildCache();
        void FindAllBuildCache();
        void BuildUpdatedCache();
        void GetCurrentPropertyValue();
        void GetCurrentPropertyValueEx();
        void GetCachedPropertyValue();
        void GetCachedPropertyValueEx();
        void GetCurrentPatternAs();
        void GetCachedPatternAs();
        [return: MarshalAs(UnmanagedType.IUnknown)] object? GetCurrentPattern(int pattern);
    }

    [ComImport, Guid("fb377fbe-8ea6-46d5-9c73-6499642d3059"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IUIAutomationInvokePattern
    {
        void Invoke();
    }

    [ComImport, Guid("94cf8058-9b8d-4ab9-8bfd-4cd0a33c8c70"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IUIAutomationTogglePattern
    {
        void Toggle();
    }
}
