using System.Runtime.InteropServices;
using static Estris.Core.Native;

namespace Estris.Utilities.AccentMenu;

/// Where the text being typed is: whether what has the focus takes text, and where its caret is,
/// in screen pixels. UI Automation answers for most apps (browsers, Office, WinUI, Electron);
/// classic Win32 apps show a system caret. Slow enough (a few to tens of milliseconds, more the
/// first time an app is asked) to keep off the hook thread.
internal static partial class TextFocus
{
    private const int UIA_BoundingRectanglePropertyId = 30001, UIA_ControlTypePropertyId = 30003, UIA_IsPasswordPropertyId = 30019;
    private const int UIA_ValuePatternId = 10002, UIA_TextPattern2Id = 10024;
    private const int UIA_EditControlTypeId = 50004, UIA_DocumentControlTypeId = 50030;
    private const int TextPatternRangeEndpoint_Start = 0, TextUnit_Character = 0;
    /// A field taller than this, in logical pixels, is a document: its top says nothing of the caret.
    private const int SingleLineHeight = 48;

    private static readonly Lazy<IUIAutomation?> Automation = new(() =>
    {
        try { return (IUIAutomation)new CUIAutomation(); }
        catch (COMException) { return null; }
    });

    /// The caret of the text field with the focus, as a thin rectangle, or null when what has the
    /// focus doesn't take text (or is a password field).
    public static RECT? Caret()
    {
        var front = GetForegroundWindow();
        if (front == 0) return null;
        var thread = GetWindowThreadProcessId(front, out _);
        var info = new GUITHREADINFO { cbSize = Marshal.SizeOf<GUITHREADINFO>() };
        var hasSystemCaret = GetGUIThreadInfo(thread, ref info) && info.hwndCaret != 0 && info.rcCaret.Height > 0;

        var (takesText, caret, field) = FromAutomation();
        if (takesText == false) return null;
        if (caret is { } found) return found;
        if (hasSystemCaret) return SystemCaret(info.hwndCaret, info.rcCaret);
        if (takesText != true) return null;
        // Takes text but says nowhere where its caret is: at a single line's start, or by the pointer.
        if (field is { } box && box.Height <= SingleLineHeight * GetDpiForWindow(front) / 96)
            return new RECT { Left = box.Left, Top = box.Top, Right = box.Left + 1, Bottom = box.Bottom };
        GetCursorPos(out var pointer);
        return new RECT { Left = pointer.X, Top = pointer.Y, Right = pointer.X + 1, Bottom = pointer.Y + 1 };
    }

    /// Whether the focused element takes text (null when UI Automation can't tell), its caret if
    /// it says, and its frame.
    private static (bool? TakesText, RECT? Caret, RECT? Field) FromAutomation()
    {
        if (Automation.Value is not { } automation) return (null, null, null);
        try
        {
            var element = automation.GetFocusedElement();
            if (element is null) return (null, null, null);
            if (element.GetCurrentPropertyValue(UIA_IsPasswordPropertyId) is true) return (false, null, null);
            var type = element.GetCurrentPropertyValue(UIA_ControlTypePropertyId) as int? ?? 0;
            var value = element.GetCurrentPattern(UIA_ValuePatternId) as IUIAutomationValuePattern;
            bool? takesText = type switch
            {
                UIA_EditControlTypeId => value is null || value.get_CurrentIsReadOnly() == 0,
                // A web page or a reader is a document too, but only an editable one has a value to set.
                UIA_DocumentControlTypeId => value is not null && value.get_CurrentIsReadOnly() == 0,
                _ => null,
            };
            if (takesText == false) return (false, null, null);
            RECT? field = element.GetCurrentPropertyValue(UIA_BoundingRectanglePropertyId) is double[] { Length: 4 } r && r[3] > 0
                ? new RECT { Left = (int)r[0], Top = (int)r[1], Right = (int)(r[0] + r[2]), Bottom = (int)(r[1] + r[3]) }
                : null;
            return (takesText, takesText == true ? CaretFrom(element) : null, field);
        }
        catch (COMException) { return (null, null, null); }
        catch (InvalidCastException) { return (null, null, null); }
    }

    /// The caret from the text pattern: the character before it, as it has just been typed.
    private static RECT? CaretFrom(IUIAutomationElement element)
    {
        if (element.GetCurrentPattern(UIA_TextPattern2Id) is not IUIAutomationTextPattern2 text) return null;
        var range = text.GetCaretRange(out _);
        if (range is null) return null;
        var before = range.Clone();
        before.MoveEndpointByUnit(TextPatternRangeEndpoint_Start, TextUnit_Character, -1);
        var rects = before.GetBoundingRectangles();
        if (rects is not { Length: >= 4 }) rects = range.GetBoundingRectangles();
        if (rects is not { Length: >= 4 } || rects[^1] <= 0) return null;
        // The last rectangle is the line the caret is on; the caret is at its end.
        var (left, top, width, height) = (rects[^4], rects[^3], rects[^2], rects[^1]);
        var x = (int)Math.Round(left + width);
        return new RECT { Left = x, Top = (int)top, Right = x + 1, Bottom = (int)Math.Round(top + height) };
    }

    /// The system caret in screen pixels. Its rectangle is in its window's own pixels, which for an
    /// app that isn't DPI aware are scaled.
    private static RECT SystemCaret(nint hwnd, RECT client)
    {
        var context = GetWindowDpiAwarenessContext(hwnd);
        var previous = SetThreadDpiAwarenessContext(context);
        var topLeft = new POINT { X = client.Left, Y = client.Top };
        var bottomRight = new POINT { X = client.Right, Y = client.Bottom };
        ClientToScreen(hwnd, ref topLeft);
        ClientToScreen(hwnd, ref bottomRight);
        SetThreadDpiAwarenessContext(previous);
        LogicalToPhysicalPointForPerMonitorDPI(hwnd, ref topLeft);
        LogicalToPhysicalPointForPerMonitorDPI(hwnd, ref bottomRight);
        return new RECT { Left = topLeft.X, Top = topLeft.Y, Right = Math.Max(bottomRight.X, topLeft.X + 1), Bottom = bottomRight.Y };
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct GUITHREADINFO
    {
        public int cbSize;
        public uint flags;
        public nint hwndActive, hwndFocus, hwndCapture, hwndMenuOwner, hwndMoveSize, hwndCaret;
        public RECT rcCaret;
    }

    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool GetGUIThreadInfo(uint thread, ref GUITHREADINFO info);
    [LibraryImport("user32")] private static partial nint GetWindowDpiAwarenessContext(nint hwnd);
    [LibraryImport("user32")] private static partial nint SetThreadDpiAwarenessContext(nint context);
    [LibraryImport("user32")] [return: MarshalAs(UnmanagedType.Bool)] private static partial bool LogicalToPhysicalPointForPerMonitorDPI(nint hwnd, ref POINT point);

    // UI Automation's COM interfaces, as far as needed here; the placeholders keep the vtable order.

    [ComImport, Guid("ff48dba4-60ef-4201-aa87-54103eef594e")]
    private class CUIAutomation;

    [ComImport, Guid("30cbe57d-d9d0-452a-ab13-7ac5ac4825ee"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IUIAutomation
    {
        void CompareElements();
        void CompareRuntimeIds();
        void GetRootElement();
        void ElementFromHandle();
        void ElementFromPoint();
        IUIAutomationElement? GetFocusedElement();
    }

    [ComImport, Guid("d22108aa-8ac5-49a5-837b-37bbb3d7591e"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IUIAutomationElement
    {
        void SetFocus();
        void GetRuntimeId();
        void FindFirst();
        void FindAll();
        void FindFirstBuildCache();
        void FindAllBuildCache();
        void BuildUpdatedCache();
        [return: MarshalAs(UnmanagedType.Struct)] object? GetCurrentPropertyValue(int property);
        void GetCurrentPropertyValueEx();
        void GetCachedPropertyValue();
        void GetCachedPropertyValueEx();
        void GetCurrentPatternAs();
        void GetCachedPatternAs();
        [return: MarshalAs(UnmanagedType.IUnknown)] object? GetCurrentPattern(int pattern);
    }

    [ComImport, Guid("a94cd8b1-0844-4cd6-9d2d-640537ab39e9"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IUIAutomationValuePattern
    {
        void SetValue();
        void get_CurrentValue();
        int get_CurrentIsReadOnly();
    }

    [ComImport, Guid("506a921a-fcc9-409f-b23b-37eb74106872"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IUIAutomationTextPattern2
    {
        void RangeFromPoint();
        void RangeFromChild();
        void GetSelection();
        void GetVisibleRanges();
        void get_DocumentRange();
        void get_SupportedTextSelection();
        void RangeFromAnnotation();
        IUIAutomationTextRange? GetCaretRange(out int isActive);
    }

    [ComImport, Guid("a543cc6a-f4ae-494b-8239-c814481187a8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IUIAutomationTextRange
    {
        IUIAutomationTextRange Clone();
        void Compare();
        void CompareEndpoints();
        void ExpandToEnclosingUnit();
        void FindAttribute();
        void FindText();
        void GetAttributeValue();
        [return: MarshalAs(UnmanagedType.SafeArray, SafeArraySubType = VarEnum.VT_R8)] double[]? GetBoundingRectangles();
        void GetEnclosingElement();
        void GetText();
        void Move();
        int MoveEndpointByUnit(int endpoint, int unit, int count);
    }
}
