using CommunityToolkit.WinUI.Controls;
using Estris.Core;
using Estris.Ui;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using static Estris.Core.Loc;

namespace Estris.Utilities.KeepAwake;

/// While on, keeps the PC and its display awake until it has been idle for as long as chosen for
/// the current power source. Idle means no mouse or keyboard input. Once idle for that long it
/// starts the screen saver or puts the PC to sleep, and holds again when the PC wakes or is used.
public sealed class KeepAwakeUtility(AppLog log) : IUtility
{
    private enum State
    {
        Off,
        /// On, but the current power source is set to not keep awake.
        Paused,
        Indefinitely,
        /// Keeping awake, as the PC was used within the chosen time.
        Active,
        /// Idle for the chosen time: put to sleep, or Windows's own settings apply until it is used.
        Idle,
    }

    /// How often to look for input once idle, where a hook would run on every mouse move.
    private static readonly TimeSpan ActivityCheck = TimeSpan.FromSeconds(1);
    /// How recent input must be to count as being used right now.
    private static readonly TimeSpan ActiveWindow = TimeSpan.FromSeconds(1);

    public string Id => "keepAwake";
    public string Title => "Keep Awake";
    public string Glyph => "\uE708";
    public UtilityGroup Group => UtilityGroup.Tools;
    public string[] Keywords => ["awake", "sleep", "caffeinate", "display", "battery", "power", "timer"];
    public Setting<bool> Enabled { get; } = SettingsStore.Shared.Get("keepAwakeEnabled", false);

    private readonly KeepAwakeSettings settings = new();
    private ExecutionHold? hold;
    private PowerWatcher? power;
    private DispatcherQueueTimer? timer;
    private State state = State.Off;
    private bool isOnBattery;
    private TimeSpan? limit;
    /// When the PC or its screen last woke, which counts as activity.
    private DateTime lastWake = DateTime.MinValue;

    private TimeSpan IdleTime
    {
        get
        {
            var sinceWake = DateTime.Now - lastWake;
            var input = PowerSystem.InputIdleTime;
            return input < sinceWake ? input : sinceWake;
        }
    }

    /// Time left until the PC may sleep, while counting down.
    private TimeSpan? Remaining => state == State.Active && limit is { } value
        ? (value > IdleTime ? value - IdleTime : TimeSpan.Zero)
        : null;

    public void Start()
    {
        timer = App.Ui.CreateTimer();
        timer.IsRepeating = false;
        timer.Tick += (_, _) => Evaluate();
        Enabled.Changed += Evaluate;
        settings.OnPower.Changed += Evaluate;
        settings.OnBattery.Changed += Evaluate;
        Evaluate();
    }

    public void Stop()
    {
        timer?.Stop();
        Release();
        state = State.Off;
    }

    private void Release()
    {
        power?.Dispose();
        power = null;
        hold?.Dispose();
        hold = null;
    }

    /// Decides whether to hold the PC awake now, and when to look again.
    private void Evaluate()
    {
        timer?.Stop();
        if (!Enabled.Value)
        {
            Release();
            state = State.Off;
            return;
        }
        hold ??= new ExecutionHold();
        power ??= new PowerWatcher(
            () => App.Ui.TryEnqueue(Evaluate),
            () => App.Ui.TryEnqueue(() =>
            {
                // Waking counts as activity, so the count starts over instead of the PC being
                // put straight back to sleep.
                lastWake = DateTime.Now;
                Evaluate();
            }));

        isOnBattery = PowerSystem.IsOnBattery;
        limit = KeepAwakeDurations.Limit(isOnBattery ? settings.OnBattery.Value : settings.OnPower.Value);
        if (limit is not { } time)
        {
            hold.IsHolding = true;
            state = State.Indefinitely;
            return;
        }
        if (time == TimeSpan.Zero)
        {
            hold.IsHolding = false;
            state = State.Paused;
            return;
        }

        var idle = IdleTime;
        if (idle < time)
        {
            hold.IsHolding = true;
            state = State.Active;
            LookAgain(time - idle);
            return;
        }
        hold.IsHolding = false;
        var wasCounting = state == State.Active;
        state = State.Idle;
        LookAgain(ActivityCheck);
        if (wasCounting) TimeIsUp();
    }

    private void LookAgain(TimeSpan after)
    {
        if (timer is null) return;
        timer.Interval = after < ActivityCheck ? ActivityCheck : after;
        timer.Start();
    }

    /// The idle time ran out: start the screen saver or sleep, rather than waiting for Windows's
    /// own timers. Without a screen saver, the display goes off instead.
    private void TimeIsUp()
    {
        var startsScreenSaver = settings.StartsScreenSaver.Value;
        var hasScreenSaver = PowerSystem.HasScreenSaver;
        _ = Task.Run(() =>
        {
            if (startsScreenSaver && hasScreenSaver)
            {
                log.Add(Title, "idle for the chosen time, starting the screen saver");
                PowerSystem.StartScreenSaver();
            }
            else if (startsScreenSaver)
            {
                log.Add(Title, "idle for the chosen time, no screen saver is set up, turning the display off");
                PowerSystem.TurnDisplayOff();
            }
            else
            {
                log.Add(Title, "idle for the chosen time, sleeping");
                if (PowerSystem.Sleep()) return;
                log.Add(Title, "can't sleep this way, turning the display off");
                PowerSystem.TurnDisplayOff();
            }
        });
    }

    public UIElement BuildPane()
    {
        var pane = new Pane();
        pane.UtilityHeader(this, T("Keep your PC awake until it has been idle for a chosen time."));

        var durations = Enum.GetValues<KeepAwakeDuration>().Select(d => (d, KeepAwakeDurations.Title(d))).ToArray();
        pane.Section(T("Idle Time Before Sleep"));
        pane.Choice(T("On power adapter"), settings.OnPower, durations);
        pane.Choice(T("On battery"), settings.OnBattery, durations);
        pane.Toggle(T("Start the screen saver instead of sleeping"), settings.StartsScreenSaver);
        var noScreenSaver = pane.Warning(T("No screen saver is set up on this PC, so the display turns off instead."));

        var status = new Pane();
        status.Root.Margin = new Thickness(0);
        status.Section(T("Status"));
        var source = new TextBlock();
        var stateText = new TextBlock();
        var countdown = new TextBlock();
        status.Card(T("Power source"), source);
        status.Card(T("State"), stateText);
        var countdownCard = status.Card(T("Sleeps in"), countdown);
        pane.Add(status.Root);
        pane.ResetButton(settings.Reset);

        void Refresh()
        {
            noScreenSaver.Visibility = Visible(settings.StartsScreenSaver.Value && !PowerSystem.HasScreenSaver);
            status.Root.Visibility = Visible(Enabled.Value);
            source.Text = isOnBattery ? T("Battery") : T("Power adapter");
            stateText.Text = StateText();
            var remaining = Remaining;
            countdownCard.Visibility = Visible(remaining is not null);
            if (remaining is { } left) countdown.Text = CountdownText(left);
        }

        // Every second while the pane is open, so the state follows what the PC is doing and the
        // countdown ticks.
        var ticker = App.Ui.CreateTimer();
        ticker.Interval = TimeSpan.FromSeconds(1);
        ticker.Tick += (_, _) => Refresh();
        pane.Root.Loaded += (_, _) => { Refresh(); ticker.Start(); };
        pane.Root.Unloaded += (_, _) => ticker.Stop();
        Enabled.Changed += () => App.Ui.TryEnqueue(Refresh);
        settings.StartsScreenSaver.Changed += Refresh;
        Refresh();
        return pane.Root;
    }

    private static Visibility Visible(bool isVisible) => isVisible ? Visibility.Visible : Visibility.Collapsed;

    /// Active while the PC is being used, Inactive while counting down and once the time is up.
    private string StateText() => state switch
    {
        State.Off or State.Paused => T("Not keeping awake"),
        State.Indefinitely => T("Always on"),
        State.Idle => T("Inactive, Windows sleep settings apply"),
        _ => IdleTime < ActiveWindow ? T("Active") : T("Inactive"),
    };

    /// Whole seconds left, so it reads 0:00 during the last second; the full time while the PC
    /// is being used.
    private string CountdownText(TimeSpan remaining)
    {
        var shown = IdleTime < ActiveWindow && limit is { } full ? full : remaining;
        var total = (int)shown.TotalSeconds;
        var (hours, minutes, seconds) = (total / 3600, total / 60 % 60, total % 60);
        return hours > 0 ? $"{hours}:{minutes:00}:{seconds:00}" : $"{minutes}:{seconds:00}";
    }
}
