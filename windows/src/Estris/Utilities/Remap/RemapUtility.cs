using Estris.Core;
using Estris.Ui;
using Microsoft.UI.Xaml;
using Microsoft.Win32;
using static Estris.Core.Loc;

namespace Estris.Utilities.Remap;

/// The Remap utility: changes what keys and mouse buttons do, per device. The hooks and Raw Input
/// feed RemapEngine, which decides; this owns them and carries out what it decides. Nothing runs
/// while there's nothing to map, watch or record.
public sealed class RemapUtility : IUtility
{
    public string Id => "remap";
    public string Title => "Remap";
    public string Glyph => "";
    public UtilityGroup Group => UtilityGroup.KeyboardAndMouse;
    public string[] Keywords => ["keyboard", "mouse", "keys", "buttons", "remap", "shortcut"];
    public Setting<bool> Enabled => Settings.Enabled;

    private static readonly double[] LookAgainSeconds = [5, 20];
    private const long UnknownDeviceLookInterval = 2000;

    public RemapSettings Settings { get; } = new();
    public InputDevices Devices { get; }
    public EventLog EventLog { get; } = new();

    private readonly AppLog log;
    private readonly RemapEngine engine;
    private readonly RawInputListener listener;
    private bool isHookingKeys, isHookingMouse, isListening, isRecording, wasEnabled;
    private bool isViewing, isOnMappings;
    private Action<RemapInput, bool>? recordingDone;
    private volatile bool swallowsAltGrControl;
    private int isSending;
    private long lastUnknownLook;

    public RemapUtility(AppLog log)
    {
        this.log = log;
        Devices = new InputDevices(log);
        engine = new RemapEngine(() => Environment.TickCount64);
        listener = new RawInputListener(DeviceOf, OnRaw, RefreshDevicesLater, engine.NextDeadline, OnDeadline);
    }

    public void Start()
    {
        Enabled.Changed += Apply;
        Settings.Devices.Changed += Apply;
        Devices.Changed += () => App.Ui.TryEnqueue(Apply);
        AppDomain.CurrentDomain.ProcessExit += (_, _) => ReleaseEverything();
        wasEnabled = Enabled.Value;
        Apply();
    }

    /// Lets go of everything held, since nothing would after this.
    public void Stop()
    {
        Enabled.Changed -= Apply;
        Settings.Devices.Changed -= Apply;
        engine.SetTable(MappingTable.Empty);
        Wire(false, false, false);
    }

    public UIElement BuildPane() => RemapPane.Build(this);

    /// Whether the Event Viewer is on screen, so events are logged.
    public bool IsViewing
    {
        set
        {
            isViewing = value;
            engine.SetViewing(value);
            engine.MutesLeftClicks = false;
            Apply();
        }
    }

    /// Whether the pointer is on a Create Mapping button in the Event Viewer.
    public bool IsOverViewerLink { set => engine.MutesLeftClicks = value; }

    /// Whether Mappings is on screen, so devices coming and going show up.
    public bool IsOnMappings
    {
        set
        {
            isOnMappings = value;
            Apply();
            if (value) RefreshDevicesLater();
        }
    }

    /// Calls done on the UI thread with the next key or button pressed on the device, which isn't
    /// passed on, and whether it had no device.
    public void Record(string deviceId, Action<RemapInput, bool> done)
    {
        recordingDone = done;
        isRecording = true;
        log.Add("Remap", $"recording: waiting for a key or button on {deviceId}");
        Apply();
        engine.Record(deviceId);
    }

    public void CancelRecording()
    {
        recordingDone = null;
        isRecording = false;
        engine.CancelRecording();
        Apply();
    }

    private void Apply()
    {
        var isOn = Enabled.Value;
        var table = isOn ? Settings.BuildTable(Devices.Connected) : MappingTable.Empty;
        engine.SetTable(table);
        swallowsAltGrControl = table.IsMapped(RemapInput.Key(KeyCodes.RightAlt));
        if (wasEnabled && !isOn) ReleaseEverything();
        wasEnabled = isOn;
        var isWatching = isViewing || isRecording;
        Wire(table.HasKeys || isWatching, table.HasButtons || isWatching, isOnMappings);
    }

    /// Holds only what's needed. Raw Input comes first, so nothing waits for it in vain.
    private void Wire(bool wantsKeys, bool wantsMouse, bool wantsDevices)
    {
        var wantsListener = wantsKeys || wantsMouse || wantsDevices;
        if (wantsListener && !isListening)
        {
            isListening = true;
            listener.Start(log);
            SystemEvents.SessionSwitch += OnSessionSwitch;
            SystemEvents.PowerModeChanged += OnPowerChange;
            RefreshDevicesLater();
            foreach (var delay in LookAgainSeconds) _ = LookAgain(delay);
        }
        if (isListening) listener.ListenToMouse(wantsMouse);

        if (wantsKeys != isHookingKeys)
        {
            isHookingKeys = wantsKeys;
            if (wantsKeys) InputHooks.Subscribe((Action<KeyEvent>)OnKey);
            else InputHooks.Unsubscribe((Action<KeyEvent>)OnKey);
        }
        if (wantsMouse != isHookingMouse)
        {
            isHookingMouse = wantsMouse;
            if (wantsMouse) InputHooks.Subscribe((Action<MouseEvent>)OnMouse);
            else InputHooks.Unsubscribe((Action<MouseEvent>)OnMouse);
        }

        if (!wantsKeys && !wantsMouse) ReleaseEverything();
        if (!wantsListener && isListening)
        {
            isListening = false;
            SystemEvents.SessionSwitch -= OnSessionSwitch;
            SystemEvents.PowerModeChanged -= OnPowerChange;
            listener.Stop();
        }
    }

    /// Wireless keyboards can finish appearing a while after Windows starts.
    private async Task LookAgain(double seconds)
    {
        await Task.Delay(TimeSpan.FromSeconds(seconds));
        if (isListening) RefreshDevicesLater();
    }

    private void RefreshDevicesLater()
    {
        var known = Settings.Devices.Value.ToDictionary(d => d.Key, d => d.Value.Name);
        _ = Task.Run(() =>
        {
            try { Devices.Refresh(known); }
            catch (Exception e) { log.Add("Remap", $"can't list devices: {e.Message}"); }
        });
    }

    /// The name of a device by its handle. A press from one not listed yet looks again, as it
    /// may have just connected; at most every 2 seconds.
    private string? DeviceOf(nint handle)
    {
        if (handle == 0) return null;
        if (Devices.Device(handle) is { } device) return device.Id;
        var now = Environment.TickCount64;
        if (now - lastUnknownLook > UnknownDeviceLookInterval)
        {
            lastUnknownLook = now;
            log.Add("Remap", $"press from an interface not listed, handle 0x{handle:X}");
            RefreshDevicesLater();
        }
        return null;
    }

    private void OnKey(KeyEvent e)
    {
        if (e.IsOwn) return;
        // Right Alt on such a layout: it brings its Ctrl again if it's sent on.
        if (e.Scan == KeyCodes.AltGrControlScan)
        {
            e.Handled = swallowsAltGrControl;
            return;
        }
        var input = RemapInput.Key(KeyCodes.FromHook(e.Vk, e.Scan, e.IsExtended));
        e.Handled = engine.OnHook(new HookEvent(input, e.IsDown, e.Vk, e.IsInjected));
        Sent();
    }

    private void OnMouse(MouseEvent e)
    {
        if (e.IsOwn || MouseButtons.From(e) is not { } button) return;
        e.Handled = engine.OnHook(new HookEvent(RemapInput.Button(button), MouseButtons.IsDown(e), 0, e.IsInjected));
        Sent();
    }

    private void OnRaw(RawEvent raw)
    {
        engine.OnRaw(raw);
        Drain();
    }

    private void OnDeadline()
    {
        engine.Tick();
        Drain();
    }

    /// Keys go right from the hook thread, to stay ahead of the next key through the hook.
    private void Sent()
    {
        if (!engine.SendsButton()) Drain();
        if (engine.SendsButton() || engine.NextDeadline() >= 0) listener.Wake();
    }

    private void OnSessionSwitch(object sender, SessionSwitchEventArgs e) => ReleaseEverything();

    private void OnPowerChange(object sender, PowerModeChangedEventArgs e)
    {
        if (e.Mode == PowerModes.Suspend) ReleaseEverything();
    }

    private void ReleaseEverything()
    {
        engine.ReleaseAll();
        Drain();
    }

    /// Carries out what the engine decided, oldest first. One thread at a time, and the others
    /// never wait: a hook thread that did would hold up the keys being sent, which pass through it.
    private void Drain()
    {
        while (Interlocked.CompareExchange(ref isSending, 1, 0) == 0)
        {
            var effects = engine.TakeEffects();
            foreach (var effect in effects)
            {
                try { Run(effect); }
                catch (Exception e) { log.Add("Remap", $"failed: {e.Message}"); }
            }
            Interlocked.Exchange(ref isSending, 0);
            if (effects.Count == 0) return;
        }
    }

    private void Run(Effect effect)
    {
        switch (effect)
        {
            case Press { Input.IsMouse: true } press:
                MouseButtons.Send(press.Input.Code, press.IsDown);
                break;
            case Press press:
                KeyCodes.Send(press.Input.Code, press.IsDown, press.Vk);
                break;
            case RunAction action:
                SystemActions.Perform(action.Action, log);
                break;
            case MaskMenu:
                KeyCodes.TapMaskKey();
                break;
            case Note note:
                log.Add("Remap", note.Message);
                break;
            case Recorded recorded:
                App.Ui.TryEnqueue(() => FinishRecording(recorded));
                break;
            case LogRow row:
                App.Ui.TryEnqueue(() => AddRow(row));
                break;
        }
    }

    private void FinishRecording(Recorded recorded)
    {
        var done = recordingDone;
        recordingDone = null;
        isRecording = false;
        Apply();
        done?.Invoke(recorded.Input, recorded.IsDeviceLess);
    }

    private void AddRow(LogRow row)
    {
        var source = row.Handle != 0 ? Devices.Device(row.Handle) : Devices.Connected.FirstOrDefault(d => d.Id == row.DeviceId);
        var device = source is not null ? Settings.Name(source)
            : row.IsPosted ? T("Posted by another app")
            : row.Handle != 0 ? T("Unknown device %@", $"0x{row.Handle:X}")
            : T("Other source");
        var (name, detail) = row.Input.IsMouse
            ? (MouseButtons.Name(row.Input.Code), T("button %lld", row.Input.Code))
            : (KeyCatalog.Name(row.Input.Code), T("scan code %@, virtual key %@", KeyCodes.CodeText(row.Input.Code), $"0x{row.Vk:X2}"));
        EventLog.Add(new InputEventRow(DateTime.Now, device, source, row.Input, row.IsDown, name, detail, row.Output is null ? null : Choices.Title(row.Output)));
    }
}
