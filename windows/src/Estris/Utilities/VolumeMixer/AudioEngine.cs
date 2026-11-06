using System.Collections.Concurrent;
using Estris.Core;
using NAudio.CoreAudioApi;
using NAudio.CoreAudioApi.Interfaces;

namespace Estris.Utilities.VolumeMixer;

public sealed record AudioDevice(string Id, string Name);

/// A system device kind, output or microphone. Volume and IsMuted are null with no device.
public sealed record EndpointState(IReadOnlyList<AudioDevice> Devices, string? CurrentId, double? Volume, bool? IsMuted)
{
    public static EndpointState Empty { get; } = new([], null, null, null);
}

/// An app making sound right now.
public sealed record AppState(string Key, string Name, string? IconPath, double Volume, bool IsMuted, string? OutputId, string? OutputName, bool CanChooseDevice)
{
    /// Plays as Windows would without Estris, so there's nothing to reset.
    public bool IsDefault => Volume >= 1 && !IsMuted && OutputId is null;
}

public sealed record MixerState(EndpointState Output, EndpointState Input, IReadOnlyList<AppState> Apps)
{
    public static MixerState Empty { get; } = new(EndpointState.Empty, EndpointState.Empty, []);
}

/// Everything that touches Windows's audio, on one thread of its own, which lives only while the
/// utility is on. Core Audio's notifications arrive on its threads, where nothing may call back
/// into it, so they only queue work here. The rest of the app reads what State last published.
internal sealed class AudioEngine : IDisposable
{
    /// A burst of notifications is handled in one refresh, right after it.
    private static readonly TimeSpan RefreshDelay = TimeSpan.FromMilliseconds(50);
    /// How often to look at who is making sound while something shows it.
    private static readonly TimeSpan PollInterval = TimeSpan.FromMilliseconds(400);
    /// An app stays listed through silence this short: the gaps within a song.
    private static readonly TimeSpan SilenceAllowed = TimeSpan.FromSeconds(1.5);
    /// A notice this soon after changing an app comes from that change.
    private static readonly TimeSpan OwnChange = TimeSpan.FromMilliseconds(500);
    private const float Silent = 0.0005f;

    private readonly VolumeMixerSettings settings;
    private readonly Action<string> log;
    private readonly Action<MixerState> publish;
    private readonly BlockingCollection<Action> work = new();
    private readonly Thread thread;
    private readonly Dictionary<string, Tracked> sessions = [];
    private readonly Dictionary<string, AudioSessionManager> managers = [];
    private readonly Dictionary<uint, AudioApps.Identity> identities = [];
    private readonly Dictionary<string, DateTime> lastChanged = [];
    /// Apps whose device can't be chosen: the picker hides for them.
    private readonly HashSet<string> unroutable = [];
    private readonly Timer refreshTimer;
    private readonly Timer pollTimer;
    private MMDeviceEnumerator? enumerator;
    private MMDeviceNotificationClient? deviceNotices;
    private MMDevice? output, input;
    private MixerState state = MixerState.Empty;
    private int isRefreshQueued;

    public AudioEngine(VolumeMixerSettings settings, Action<string> log, Action<MixerState> publish)
    {
        this.settings = settings;
        this.log = log;
        this.publish = publish;
        refreshTimer = new Timer(_ =>
        {
            Interlocked.Exchange(ref isRefreshQueued, 0);
            Post(Refresh);
        });
        pollTimer = new Timer(_ => Post(ListApps));
        thread = new Thread(Run) { IsBackground = true, Name = "Volume Mixer" };
        thread.SetApartmentState(ApartmentState.MTA);
        thread.Start();
        Post(Begin);
    }

    private void Post(Action action)
    {
        if (!work.IsAddingCompleted)
        {
            try { work.Add(action); }
            catch (InvalidOperationException) { /* Ending: nothing left to do. */ }
        }
    }

    private void Run()
    {
        foreach (var action in work.GetConsumingEnumerable())
        {
            try { action(); }
            catch (Exception e) { log($"failed: {e.Message}"); }
        }
    }

    private void QueueRefresh()
    {
        if (Interlocked.Exchange(ref isRefreshQueued, 1) == 0) refreshTimer.Change(RefreshDelay, Timeout.InfiniteTimeSpan);
    }

    private void Begin()
    {
        enumerator = new MMDeviceEnumerator();
        deviceNotices = enumerator.CreateNotificationClient(useSynchronizationContext: false);
        deviceNotices.DefaultDeviceChanged += (_, _) => QueueRefresh();
        deviceNotices.DeviceAdded += (_, _) => QueueRefresh();
        deviceNotices.DeviceRemoved += (_, _) => QueueRefresh();
        deviceNotices.DeviceStateChanged += (_, _) => QueueRefresh();
        log(AppAudioRouting.IsAvailable ? "per-app devices available" : "per-app devices aren't available on this Windows");
        Refresh();
    }

    /// While a pane or the tray shows the rows; only then does who's playing need looking at.
    public bool IsWatched
    {
        set => pollTimer.Change(value ? TimeSpan.Zero : Timeout.InfiniteTimeSpan, value ? PollInterval : Timeout.InfiniteTimeSpan);
    }

    // MARK: System output and input

    private void Refresh()
    {
        if (enumerator is null) return;
        var previousOutput = output?.ID;
        var previousInput = input?.ID;
        var outputs = Devices(DataFlow.Render);
        var inputs = Devices(DataFlow.Capture);
        output = Follow(output, DataFlow.Render);
        input = Follow(input, DataFlow.Capture);
        if (output?.ID != previousOutput || input?.ID != previousInput) log($"output: {output?.FriendlyName ?? "none"}, microphone: {input?.FriendlyName ?? "none"}");
        state = state with { Output = Read(outputs, output), Input = Read(inputs, input) };
        RefreshSessions();
        ListApps(force: true);
    }

    private List<AudioDevice> Devices(DataFlow flow)
    {
        var devices = new List<AudioDevice>();
        foreach (var device in enumerator!.EnumerateAudioEndPoints(flow, DeviceState.Active))
        {
            devices.Add(new AudioDevice(device.ID, device.FriendlyName));
            device.Dispose();
        }
        return devices;
    }

    /// The device in use now, listening to its volume; the one before stops being followed.
    private MMDevice? Follow(MMDevice? current, DataFlow flow)
    {
        var id = enumerator!.HasDefaultAudioEndpoint(flow, Role.Multimedia) ? enumerator.GetDefaultAudioEndpoint(flow, Role.Multimedia) : null;
        if (id?.ID == current?.ID)
        {
            id?.Dispose();
            return current;
        }
        current?.Dispose();
        if (id is not null) id.AudioEndpointVolume.OnVolumeNotification += _ => Post(RefreshVolumes);
        return id;
    }

    private void RefreshVolumes()
    {
        state = state with { Output = Read(state.Output.Devices, output), Input = Read(state.Input.Devices, input) };
        publish(state);
    }

    private static EndpointState Read(IReadOnlyList<AudioDevice> devices, MMDevice? device) =>
        device is null
            ? new EndpointState(devices, null, null, null)
            : new EndpointState(devices, device.ID, device.AudioEndpointVolume.MasterVolumeLevelScalar, device.AudioEndpointVolume.Mute);

    public void SetVolume(bool isInput, double volume) => Post(() =>
    {
        if ((isInput ? input : output) is { } device) device.AudioEndpointVolume.MasterVolumeLevelScalar = (float)Math.Clamp(volume, 0, 1);
    });

    public void ToggleMute(bool isInput) => Post(() =>
    {
        if ((isInput ? input : output) is { } device) device.AudioEndpointVolume.Mute = !device.AudioEndpointVolume.Mute;
    });

    public void SetDefaultDevice(string deviceId) => Post(() => DefaultDevice.Set(deviceId));

    // MARK: Apps

    /// Finds every device's sessions. Each is followed from then on, by its own events.
    private void RefreshSessions()
    {
        var active = new HashSet<string>();
        foreach (var device in enumerator!.EnumerateAudioEndPoints(DataFlow.Render, DeviceState.Active))
        {
            active.Add(device.ID);
            if (!managers.TryGetValue(device.ID, out var manager))
            {
                manager = managers[device.ID] = device.AudioSessionManager;
                manager.OnSessionCreated += (_, _) => QueueRefresh();
            }
            else device.Dispose();
            manager.RefreshSessions();
            var list = manager.Sessions;
            for (var index = 0; index < list.Count; index++) Add(list[index]);
        }
        foreach (var id in managers.Keys.Where(id => !active.Contains(id)).ToList())
        {
            managers[id].Dispose();
            managers.Remove(id);
        }
        foreach (var (id, session) in sessions.Where(s => s.Value.IsGone).ToList())
        {
            sessions.Remove(id);
            identities.Remove(session.Process);
            session.Dispose();
        }
    }

    private void Add(AudioSessionControl control)
    {
        var id = control.GetSessionInstanceIdentifier;
        if (control.IsSystemSoundsSession || sessions.ContainsKey(id) || control.GetProcessID == Environment.ProcessId)
        {
            control.Dispose();
            return;
        }
        var process = control.GetProcessID;
        if (!identities.TryGetValue(process, out var identity)) identity = identities[process] = AudioApps.Find(process);
        var session = new Tracked(control, process, identity, this);
        sessions[id] = session;
        if (settings.Apps.Value.TryGetValue(identity.Key, out var sound) && !IsExcluded(identity.Key)) ApplyRemembered(session, sound);
    }

    /// Applies what's remembered to a session that just appeared. Once that means playing as
    /// Windows would, as after a reset, there's nothing left to remember.
    private void ApplyRemembered(Tracked session, AppSound sound)
    {
        session.Set(sound.Volume, sound.IsMuted);
        Route(session, sound.OutputId);
        if (!sound.IsUntouched) return;
        var apps = new Dictionary<string, AppSound>(settings.Apps.Value);
        apps.Remove(session.App.Key);
        settings.Apps.Value = apps;
    }

    /// Sends a session's process to a device, unless it's already there or that isn't connected.
    private void Route(Tracked session, string? deviceId)
    {
        if (!AppAudioRouting.IsAvailable || unroutable.Contains(session.App.Key)) return;
        if (deviceId is not null && state.Output.Devices.All(d => d.Id != deviceId)) return;
        try
        {
            if (AppAudioRouting.Get(session.Process) != deviceId) AppAudioRouting.Set(session.Process, deviceId);
        }
        catch (Exception e)
        {
            unroutable.Add(session.App.Key);
            log($"{session.App.Name}: can't choose its device ({e.Message})");
        }
    }

    private bool IsExcluded(string key) => settings.ExcludedApps.Value.Contains(key);

    private void ListApps() => ListApps(force: false);

    /// The apps making sound right now: their sessions are active, and something comes out.
    /// Silence counts while muted, since the meter can't tell it from not playing.
    private void ListApps(bool force)
    {
        var now = DateTime.UtcNow;
        var apps = new Dictionary<string, AppState>();
        foreach (var session in sessions.Values)
        {
            if (!session.IsPlaying(now, SilenceAllowed, Silent)) continue;
            var key = session.App.Key;
            if (apps.ContainsKey(key) || IsExcluded(key)) continue;
            apps[key] = Describe(session);
        }
        var list = apps.Values.OrderBy(app => app.Name, StringComparer.CurrentCultureIgnoreCase).ToList();
        if (!force && list.SequenceEqual(state.Apps)) return;
        if (!list.Select(a => a.Key).SequenceEqual(state.Apps.Select(a => a.Key))) log($"playing: {string.Join(", ", list.Select(a => a.Name))}");
        state = state with { Apps = list };
        publish(state);
    }

    private AppState Describe(Tracked session)
    {
        var app = session.App;
        var canChoose = AppAudioRouting.IsAvailable && !unroutable.Contains(app.Key);
        if (settings.Apps.Value.TryGetValue(app.Key, out var sound))
            return new AppState(app.Key, app.Name, app.Path, sound.Volume, sound.IsMuted, sound.OutputId, sound.OutputName, canChoose);
        var (volume, isMuted) = session.Read();
        return new AppState(app.Key, app.Name, app.Path, volume, isMuted, AppAudioRouting.Get(session.Process), null, canChoose);
    }

    private AppSound Sound(string key)
    {
        if (settings.Apps.Value.TryGetValue(key, out var sound)) return sound;
        // Not changed here yet: it starts from how the app sounds now.
        var session = sessions.Values.FirstOrDefault(s => s.App.Key == key);
        if (session is null) return new AppSound();
        var (volume, isMuted) = session.Read();
        var deviceId = AppAudioRouting.Get(session.Process);
        return new AppSound(volume, isMuted, deviceId, state.Output.Devices.FirstOrDefault(d => d.Id == deviceId)?.Name);
    }

    private void Remember(string key, AppSound sound)
    {
        var apps = new Dictionary<string, AppSound>(settings.Apps.Value);
        if (sound.IsUntouched) apps.Remove(key);
        else apps[key] = sound;
        settings.Apps.Value = apps;
    }

    private void Change(string key, Func<AppSound, AppSound> change)
    {
        var sound = change(Sound(key));
        Remember(key, sound);
        lastChanged[key] = DateTime.UtcNow;
        foreach (var session in sessions.Values.Where(s => s.App.Key == key))
        {
            session.Set(sound.Volume, sound.IsMuted);
            Route(session, sound.OutputId);
        }
        ListApps(force: true);
    }

    public void SetAppVolume(string key, double volume) => Post(() => Change(key, sound => sound with { Volume = volume }));

    public void ToggleAppMute(string key) => Post(() => Change(key, sound => sound with { IsMuted = !sound.IsMuted }));

    /// Null plays the app on the system output.
    public void SetAppOutput(string key, string? deviceId) => Post(() =>
        Change(key, sound => sound with { OutputId = deviceId, OutputName = state.Output.Devices.FirstOrDefault(d => d.Id == deviceId)?.Name }));

    /// One app back to playing as it is: its volume, mute and device.
    public void ResetApp(string key) => Post(() => Change(key, _ => new AppSound()));

    /// Every app back to playing as it is. The ones not playing keep an entry, so they're put back
    /// when they next do: Windows keeps their volume until then.
    public void Reset() => Post(() =>
    {
        settings.Apps.Value = settings.Apps.Value.Keys.ToDictionary(key => key, _ => new AppSound());
        var playing = sessions.Values.Select(s => s.App.Key).ToHashSet();
        foreach (var key in playing.Where(key => !IsExcluded(key))) Change(key, _ => new AppSound());
    });

    /// An app just excluded goes back to its own sound; what's remembered stays for if it returns.
    public void ExcludedChanged() => Post(() =>
    {
        foreach (var session in sessions.Values.Where(s => IsExcluded(s.App.Key) && settings.Apps.Value.ContainsKey(s.App.Key)))
            Restore(session);
        foreach (var (key, sound) in settings.Apps.Value)
            foreach (var session in sessions.Values.Where(s => s.App.Key == key && !IsExcluded(key)))
            {
                session.Set(sound.Volume, sound.IsMuted);
                Route(session, sound.OutputId);
            }
        ListApps(force: true);
    });

    private void Restore(Tracked session)
    {
        session.Set(1, false);
        Route(session, null);
    }

    /// A session's volume changed: elsewhere, unless it's the echo of a change made here.
    private void OnSessionVolume(Tracked session, float volume, bool isMuted)
    {
        var key = session.App.Key;
        if (lastChanged.TryGetValue(key, out var time) && DateTime.UtcNow - time < OwnChange) return;
        if (settings.Apps.Value.TryGetValue(key, out var sound)) Remember(key, sound with { Volume = volume, IsMuted = isMuted });
        ListApps(force: true);
    }

    /// Ends everything. Switched off by hand, the apps changed go back to their own sound; quitting
    /// leaves them, as Windows remembers each app's volume and device anyway.
    public void Stop(bool restoresApps)
    {
        Post(() =>
        {
            if (restoresApps)
            {
                foreach (var session in sessions.Values.Where(s => settings.Apps.Value.ContainsKey(s.App.Key) && !IsExcluded(s.App.Key)))
                    Restore(session);
            }
            foreach (var session in sessions.Values) session.Dispose();
            sessions.Clear();
            foreach (var manager in managers.Values) manager.Dispose();
            managers.Clear();
            deviceNotices?.Dispose();
            output?.Dispose();
            input?.Dispose();
            enumerator?.Dispose();
            enumerator = null;
        });
        work.CompleteAdding();
    }

    public void Dispose()
    {
        refreshTimer.Dispose();
        pollTimer.Dispose();
    }

    /// One audio session, followed through its own events.
    private sealed class Tracked : IAudioSessionEventsHandler, IDisposable
    {
        private readonly AudioSessionControl control;
        private readonly AudioEngine engine;
        private DateTime lastHeard = DateTime.MinValue;
        private bool isDisconnected;

        public uint Process { get; }
        public AudioApps.Identity App { get; }

        public Tracked(AudioSessionControl control, uint process, AudioApps.Identity app, AudioEngine engine)
        {
            this.control = control;
            this.engine = engine;
            Process = process;
            App = app;
            control.RegisterEventClient(this);
        }

        public bool IsGone => isDisconnected || control.State == AudioSessionState.AudioSessionStateExpired;

        public bool IsPlaying(DateTime now, TimeSpan silenceAllowed, float silent)
        {
            if (isDisconnected) return false;
            try
            {
                if (control.State != AudioSessionState.AudioSessionStateActive) return false;
                var volume = control.SimpleAudioVolume;
                if (volume.Mute || volume.Volume <= 0) return true;
                if (control.AudioMeterInformation.MasterPeakValue > silent) lastHeard = now;
                return now - lastHeard < silenceAllowed;
            }
            catch (Exception) { return false; }
        }

        public (double Volume, bool IsMuted) Read() => (control.SimpleAudioVolume.Volume, control.SimpleAudioVolume.Mute);

        public void Set(double volume, bool isMuted)
        {
            var simple = control.SimpleAudioVolume;
            simple.Volume = (float)Math.Clamp(volume, 0, 1);
            simple.Mute = isMuted;
        }

        public void OnVolumeChanged(float volume, bool isMuted) => engine.Post(() => engine.OnSessionVolume(this, volume, isMuted));
        public void OnStateChanged(AudioSessionState state) => engine.QueueRefresh();

        public void OnSessionDisconnected(AudioSessionDisconnectReason reason)
        {
            isDisconnected = true;
            engine.QueueRefresh();
        }

        public void OnDisplayNameChanged(string displayName) { }
        public void OnIconPathChanged(string iconPath) { }
        public void OnChannelVolumeChanged(uint channelCount, nint newVolumes, uint channelIndex) { }
        public void OnGroupingParamChanged(ref Guid groupingId) { }

        public void Dispose() => control.Dispose();
    }
}
