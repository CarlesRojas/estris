namespace Estris.Utilities.Remap;

/// A key or button as the hook saw it. IsPosted: sent by another program, so no device has it.
public readonly record struct HookEvent(RemapInput Input, bool IsDown, int Vk, bool IsPosted = false);

/// A key or button as Raw Input saw it. A null DeviceId is a device not listed, or, with no
/// Handle either, none at all.
public readonly record struct RawEvent(RemapInput Input, bool IsDown, string? DeviceId, nint Handle, int Vk = 0);

/// What the engine decided should happen, in order.
public abstract record Effect;
public sealed record Press(RemapInput Input, bool IsDown, int Vk = 0) : Effect;
public sealed record RunAction(SystemAction Action) : Effect;
/// Keeps Start or the menu bar from opening on the release of Win or Alt that follows.
public sealed record MaskMenu : Effect;
public sealed record LogRow(RemapInput Input, int Vk, bool IsDown, string? DeviceId, nint Handle, bool IsPosted, RemapOutput? Output) : Effect;
public sealed record Recorded(RemapInput Input, bool IsDeviceLess) : Effect;
public sealed record Note(string Message) : Effect;
/// Raw Input saw a key or button that the hook never did: Windows stopped calling it, or another
/// program's hook keeps events from it.
public sealed record HookMissed(RemapInput Input) : Effect;

/// Decides what happens to each key and button: the mapping of the device that sent it, or the
/// original. It has no Windows calls and takes the time as a function, so it can be tested.
///
/// The hook can swallow but doesn't say the device; Raw Input says the device but comes from
/// another step inside Windows, and the two don't behave alike:
/// - A mouse button reaches Raw Input even when swallowed, usually before the hook. So a mapped
///   button waits for it (or takes it if it came first), and the original is sent again if its
///   device has no mapping; after a short wait it goes as if it had no device.
/// - A key reaches Raw Input only if nothing swallowed it, and only after the hook, so a press
///   can't wait for its device. When the keyboards plugged in all do the same with a key, it
///   doesn't matter. Otherwise it goes by what Raw Input said before: the keyboard being typed
///   on, unless only another kind of device (a mouse sending keys) has sent that key; when nobody
///   is typing, the devices that have sent it. Such a guess lets the release through, so Raw
///   Input says the device for next time (a lone release does nothing). With no guess, the key
///   waits for its release, which says the device; another key or holding it stops the wait,
///   going with the last keyboard.
/// Keys with no mapping are never held back, and a key or button goes up the way it went down.
public sealed class RemapEngine(Func<long> clock)
{
    /// How long a mouse button or a release waits for Raw Input, in milliseconds.
    public const long RawWait = 25;
    /// How long a Raw Input event stays usable for a hook event coming after it.
    public const long RawMemory = 60;
    /// How long a keyboard counts as the one being typed on.
    public const long ActiveKeyboardTime = 1500;
    /// How long a held key waits for its release before going with the last keyboard.
    public const long HoldWait = 200;
    /// How long after Raw Input's release the hook has to see it, or it never will.
    public const long MissedUpWait = 250;
    /// How many different keys a device must send to count as a keyboard: a receiver doesn't look
    /// like one, and a mouse may send a few keys.
    public const int KeyboardKeys = 8;
    private const long Forever = long.MaxValue;
    /// The Ctrl that AltGr adds is made by Windows, so the hook may see it without Raw Input
    /// agreeing on it; it doesn't count when checking the hook.
    private static readonly RemapInput LeftControl = RemapInput.Key(0x1D);

    private enum Route { Waiting, Untouched, Original, Mapped }

    private sealed class Held(RemapInput input, int vk, bool isPosted)
    {
        public RemapInput Input { get; } = input;
        public int Vk { get; } = vk;
        public bool IsPosted { get; } = isPosted;
        public Route Route { get; set; } = Route.Waiting;
        public RemapOutput? Output { get; set; }
        public string? DeviceId { get; set; }
        public nint Handle { get; set; }
        /// Windows and apps never saw it go down.
        public bool IsSwallowed { get; set; }
        /// Its release goes on, so Raw Input says the keyboard.
        public bool PassesRelease { get; set; }
        public long Deadline { get; set; }
        /// What the hook saw while waiting: true for a repeat, false for the release.
        public List<bool> Queued { get; } = [];
        public long? RawUpAt { get; set; }
    }

    private readonly object gate = new();
    private readonly Dictionary<RemapInput, Held> held = [];
    private readonly List<Held> waiting = [];
    private readonly List<(RawEvent Raw, long At)> recent = [];
    /// The devices Raw Input has seen sending each key, and how many keys each sent.
    private readonly Dictionary<RemapInput, HashSet<string>> senders = [];
    private readonly Dictionary<string, int> keyCounts = [];
    private List<Effect> effects = [];
    private MappingTable table = MappingTable.Empty;
    private bool isViewing;
    private bool areHooksSkipped;
    private string? recording;
    private bool isRecording;
    private string? lastKeyboard;
    private long lastKeyboardAt = long.MinValue / 2;

    /// Left clicks aren't logged, for the one on the Event Viewer's own button.
    public volatile bool MutesLeftClicks;

    public void SetTable(MappingTable value)
    {
        lock (gate) table = value;
    }

    public void SetViewing(bool value)
    {
        lock (gate) isViewing = value;
    }

    /// Windows is skipping the hooks: Raw Input is all there is, for logging and recording keys.
    public bool AreHooksSkipped
    {
        set { lock (gate) areHooksSkipped = value; }
    }

    /// The next press on the device, or from software with no device, is reported as Recorded.
    public void Record(string deviceId)
    {
        lock (gate)
        {
            recording = deviceId;
            isRecording = true;
        }
    }

    public void CancelRecording()
    {
        lock (gate) isRecording = false;
    }

    /// What to do next, oldest first, and forgets it.
    public List<Effect> TakeEffects()
    {
        lock (gate)
        {
            var taken = effects;
            effects = [];
            return taken;
        }
    }

    /// Whether a mouse button is about to be sent. Sending one from the hook thread would wait
    /// for that same thread, up to Windows's hook timeout.
    public bool SendsButton()
    {
        lock (gate) return effects.Any(e => e is Press { Input.IsMouse: true });
    }

    /// Milliseconds until Tick has something to do, or -1 for nothing.
    public int NextDeadline()
    {
        lock (gate)
        {
            var next = Forever;
            foreach (var press in waiting) next = Math.Min(next, press.Deadline);
            foreach (var press in held.Values)
                if (press.RawUpAt is { } at) next = Math.Min(next, at + MissedUpWait);
            return next == Forever ? -1 : (int)Math.Clamp(next - clock(), 0, int.MaxValue);
        }
    }

    /// Runs on the hook thread for every key and button not sent by Estris. Returns whether to
    /// swallow it.
    public bool OnHook(HookEvent e)
    {
        lock (gate)
        {
            var now = clock();
            ForgetOldRaw(now);
            if (held.TryGetValue(e.Input, out var press))
            {
                if (e.IsDown) return Repeat(press);
                held.Remove(e.Input);
                return Release(press, now);
            }
            return e.IsDown && NewPress(e, now);
        }
    }

    public void OnRaw(RawEvent raw)
    {
        lock (gate)
        {
            var now = clock();
            ForgetOldRaw(now);
            if (!raw.Input.IsMouse && raw.DeviceId is { } id)
            {
                lastKeyboard = id;
                lastKeyboardAt = now;
                if (!senders.TryGetValue(raw.Input, out var known)) senders[raw.Input] = known = [];
                if (known.Add(id)) keyCounts[id] = keyCounts.GetValueOrDefault(id) + 1;
            }
            if (areHooksSkipped && !raw.Input.IsMouse)
            {
                OnRawAlone(raw);
                return;
            }
            // A key reaches Raw Input after the hook, so one going down unseen got past it.
            if (!raw.Input.IsMouse && raw.IsDown && raw.Input != LeftControl && !held.ContainsKey(raw.Input))
                effects.Add(new HookMissed(raw.Input));

            var pending = waiting.FirstOrDefault(p => p.Input == raw.Input);
            if (pending is not null)
            {
                waiting.Remove(pending);
                Decide(pending, raw.DeviceId, raw.Handle, false);
                Replay(pending);
                return;
            }

            if (held.TryGetValue(raw.Input, out var press))
            {
                if (!raw.IsDown) press.RawUpAt ??= now;
                else if (press.RawUpAt is not null) recent.Add((raw, now));
            }
            else if (raw.IsDown && (table.IsMapped(raw.Input) || isViewing || isRecording)) recent.Add((raw, now));
        }
    }

    /// A key while the hooks are skipped: it can't be swallowed or mapped, only seen.
    private void OnRawAlone(RawEvent raw)
    {
        if (isRecording && raw.IsDown && (raw.DeviceId is null || raw.DeviceId == recording))
        {
            isRecording = false;
            effects.Add(new Recorded(raw.Input, raw.DeviceId is null));
        }
        else if (isViewing) effects.Add(new LogRow(raw.Input, raw.Vk, raw.IsDown, raw.DeviceId, raw.Handle, raw.Handle == 0, null));
    }

    /// Runs when NextDeadline says so: gives up waiting for Raw Input, so nothing is lost.
    public void Tick()
    {
        lock (gate)
        {
            var now = clock();
            ForgetOldRaw(now);
            foreach (var press in waiting.Where(p => p.Deadline <= now).ToList())
            {
                waiting.Remove(press);
                if (press.IsSwallowed && press.Input.IsMouse)
                    effects.Add(new Note($"no device reported for button {press.Input.Code} after {RawWait} ms"));
                Guess(press);
                Replay(press);
            }
            foreach (var press in held.Values.Where(p => p.RawUpAt + MissedUpWait <= now).ToList())
            {
                effects.Add(new Note($"released 0x{press.Input.Code:X}: the hook missed its release"));
                held.Remove(press.Input);
                Finish(press, false);
            }
        }
    }

    /// Lets go of everything held, for turning off, quitting or anything that can hide a release.
    /// A press still waiting is sent as it was.
    public void ReleaseAll()
    {
        lock (gate)
        {
            isRecording = false;
            foreach (var press in waiting.Where(p => p.IsSwallowed))
            {
                MaskIfMenu(press.Input);
                effects.Add(new Press(press.Input, true, press.Vk));
                effects.Add(new Press(press.Input, false, press.Vk));
            }
            waiting.Clear();
            foreach (var press in held.Values)
            {
                if (press.Route == Route.Original) effects.Add(new Press(press.Input, false, press.Vk));
                if (press.Route == Route.Mapped) ReleaseOutput(press, true);
            }
            held.Clear();
            recent.Clear();
        }
    }

    private bool NewPress(HookEvent e, long now)
    {
        var press = new Held(e.Input, e.Vk, e.IsPosted);
        held[e.Input] = press;
        if (e.IsPosted)
        {
            // Programs have no device. A button's Raw Input, which came first, says nothing more.
            TakeRecentRaw(e.Input);
            Decide(press, null, 0, true);
            return press.IsSwallowed;
        }
        if (!e.Input.IsMouse && !isRecording) DecideWaitingKeys();

        var wantsIt = e.Input != RemapInput.LeftButton && (table.IsMapped(e.Input) || isRecording);
        if (!wantsIt && !isViewing)
        {
            press.Route = Route.Untouched;
        }
        else if (TakeRecentRaw(e.Input) is { } raw)
        {
            Decide(press, raw.DeviceId, raw.Handle, true);
        }
        else if (e.Input.IsMouse || !wantsIt)
        {
            // Its Raw Input is on the way; only a mapped button is held back for it.
            press.IsSwallowed = wantsIt;
            Wait(press, now + RawWait);
        }
        else if (isRecording)
        {
            press.IsSwallowed = press.PassesRelease = true;
            Wait(press, Forever);
        }
        else if (LikelyKeyboard(e.Input, now, out var isSure) is { } keyboard)
        {
            press.PassesRelease = !isSure;
            Decide(press, keyboard, 0, true);
        }
        else
        {
            press.IsSwallowed = press.PassesRelease = true;
            Wait(press, now + HoldWait);
        }
        return press.IsSwallowed;
    }

    /// Which device a mapped key most likely came from, or null when nothing says. isSure: the
    /// devices that may have sent it (keyboards, and those that map it or sent it) all do the same
    /// with it.
    private string? LikelyKeyboard(RemapInput input, long now, out bool isSure)
    {
        var known = senders.GetValueOrDefault(input) ?? [];
        var keyboards = table.Keyboards.Concat(keyCounts.Where(c => c.Value >= KeyboardKeys).Select(c => c.Key)).ToList();
        var any = table.Agreed(keyboards.Concat(table.Mappers(input)).Concat(known), input, lastKeyboard);
        isSure = any is not null;
        if (isSure) return any;
        // A key a keyboard sends may come from the one being typed on; one that only another kind
        // of device has sent, such as a mouse sending keys, comes from that device.
        var isTyping = lastKeyboard is not null && now - lastKeyboardAt < ActiveKeyboardTime;
        if (isTyping && (known.Count == 0 || known.Contains(lastKeyboard!) || known.Any(keyboards.Contains))) return lastKeyboard;
        return table.Agreed(known, input, null) ?? (isTyping ? lastKeyboard : null);
    }

    private void Wait(Held press, long deadline)
    {
        press.Deadline = deadline;
        waiting.Add(press);
    }

    /// Another key is going through: keys waiting go first, so they stay in order.
    private void DecideWaitingKeys()
    {
        foreach (var press in waiting.Where(p => !p.Input.IsMouse && p.IsSwallowed).ToList())
        {
            waiting.Remove(press);
            Guess(press);
            Replay(press);
        }
    }

    /// Nothing said the device: a key goes with the last keyboard, a button has none.
    private void Guess(Held press)
    {
        var isKey = !press.Input.IsMouse && !isRecording;
        Decide(press, isKey ? lastKeyboard ?? table.DeviceMapping(press.Input) : null, 0, false);
    }

    /// Settles a press whose device is now known. hookOpen: the hook hasn't answered yet, so an
    /// original can simply go on rather than be sent again.
    private void Decide(Held press, string? deviceId, nint handle, bool hookOpen)
    {
        press.DeviceId = deviceId;
        press.Handle = handle;
        RemapOutput? output = null;
        if (isRecording && press.Input != RemapInput.LeftButton)
        {
            if (deviceId is null || deviceId == recording)
            {
                isRecording = false;
                effects.Add(new Note($"recording: 0x{press.Input.Code:X} from {deviceId ?? (handle == 0 ? "no device" : "an unlisted device")}"));
                effects.Add(new Recorded(press.Input, handle == 0));
                output = RemapOutput.Nothing;
            }
            else effects.Add(new Note($"recording: ignored 0x{press.Input.Code:X} from {deviceId}, another device"));
        }
        output ??= press.IsSwallowed || hookOpen ? table.Output(deviceId, press.Input) : null;
        press.Output = output;

        if (output is not null)
        {
            press.Route = Route.Mapped;
            press.IsSwallowed = true;
            Log(press, true);
            Perform(output, true, false);
        }
        else if (press.IsSwallowed)
        {
            press.Route = Route.Original;
            Log(press, true);
            effects.Add(new Press(press.Input, true, press.Vk));
        }
        else
        {
            press.Route = Route.Untouched;
            Log(press, true);
        }
    }

    /// What the hook saw of a press while it waited.
    private void Replay(Held press)
    {
        foreach (var isRepeat in press.Queued)
        {
            if (isRepeat) Repeat(press);
            else Finish(press, false);
        }
        press.Queued.Clear();
    }

    private bool Repeat(Held press)
    {
        switch (press.Route)
        {
            case Route.Waiting: press.Queued.Add(true); break;
            case Route.Original: effects.Add(new Press(press.Input, true, press.Vk)); break;
            case Route.Mapped: Perform(press.Output!, true, true); break;
        }
        return press.IsSwallowed;
    }

    private bool Release(Held press, long now)
    {
        if (press.Route != Route.Waiting) return Finish(press, true);
        press.Queued.Add(false);
        if (!press.IsSwallowed) return false;
        if (!press.PassesRelease) return true;
        // Goes on alone, for Raw Input to say the keyboard.
        press.Deadline = now + RawWait;
        MaskIfMenu(press.Input);
        return false;
    }

    /// The press is over. hookOpen: the hook is holding its release, so it can go on instead of
    /// one being sent. Returns whether to swallow that release.
    private bool Finish(Held press, bool hookOpen)
    {
        Log(press, false);
        switch (press.Route)
        {
            case Route.Original:
                if (hookOpen) return false;
                effects.Add(new Press(press.Input, false, press.Vk));
                return true;
            case Route.Mapped:
                ReleaseOutput(press, false);
                if (!press.PassesRelease) return true;
                // Windows never saw it go down.
                if (hookOpen) MaskIfMenu(press.Input);
                return false;
            default:
                return false;
        }
    }

    private void Perform(RemapOutput output, bool isDown, bool isRepeat)
    {
        switch (output.Kind)
        {
            case OutputKind.Action:
                if (isDown && (!isRepeat || output.Repeats)) effects.Add(new RunAction(output.Action!.Value));
                break;
            case OutputKind.Key:
                effects.Add(new Press(RemapInput.Key(output.Code), isDown));
                break;
            case OutputKind.MouseButton:
                if (!isRepeat) effects.Add(new Press(RemapInput.Button(output.Code), isDown));
                break;
        }
    }

    /// Lets go of what a press holds, unless another press still holds the same.
    private void ReleaseOutput(Held press, bool mask)
    {
        var output = press.Output!;
        if (output.Kind is not (OutputKind.Key or OutputKind.MouseButton)) return;
        if (held.Values.Any(p => p != press && p.Route == Route.Mapped && p.Output == output)) return;
        if (mask && output.Kind == OutputKind.Key) MaskIfMenu(RemapInput.Key(output.Code));
        Perform(output, false, false);
    }

    private void MaskIfMenu(RemapInput input)
    {
        if (input.OpensMenu) effects.Add(new MaskMenu());
    }

    private void Log(Held press, bool isDown)
    {
        if (!isViewing || (press.Input == RemapInput.LeftButton && MutesLeftClicks)) return;
        effects.Add(new LogRow(press.Input, press.Vk, isDown, press.DeviceId, press.Handle, press.IsPosted, press.Output));
    }

    private RawEvent? TakeRecentRaw(RemapInput input)
    {
        var index = recent.FindIndex(r => r.Raw.Input == input && r.Raw.IsDown);
        if (index < 0) return null;
        var raw = recent[index].Raw;
        recent.RemoveAt(index);
        return raw;
    }

    /// A button's Raw Input comes first; one no hook event claimed in time got past the hook.
    private void ForgetOldRaw(long now)
    {
        foreach (var (raw, _) in recent.Where(r => now - r.At > RawMemory)) effects.Add(new HookMissed(raw.Input));
        recent.RemoveAll(r => now - r.At > RawMemory);
    }
}
