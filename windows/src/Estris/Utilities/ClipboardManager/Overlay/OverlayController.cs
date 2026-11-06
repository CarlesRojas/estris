using Estris.Core;
using Microsoft.UI.Dispatching;
using static Estris.Core.Loc;

namespace Estris.Utilities.ClipboardManager.Overlay;

/// Shows the overlay while the shortcut's modifiers are held (Ctrl+Shift for the default
/// Ctrl+Shift+V). Pressing the shortcut again, the arrows or the wheel moves the selection;
/// releasing pastes the selected entry; Esc cancels; Delete removes the selected entry; clicking
/// an entry pastes it. Input goes through the hooks, which swallow what the overlay handles, as
/// the overlay never takes the focus away from the app being pasted into.
internal sealed class OverlayController
{
    private const int VkBackspace = 0x08, VkEsc = 0x1B, VkLeft = 0x25, VkUp = 0x26, VkRight = 0x27, VkDown = 0x28, VkDelete = 0x2E;
    private const int VkLShift = 0xA0, VkRShift = 0xA1, VkLCtrl = 0xA2, VkRCtrl = 0xA3, VkLAlt = 0xA4, VkRAlt = 0xA5, VkLWin = 0x5B, VkRWin = 0x5C;
    private const int VkControl = 0x11, VkV = 0x56;
    /// A key no keyboard has. Sent while the modifiers are down, so Alt or Win alone being
    /// released afterwards doesn't open a menu or Start.
    private const int VkUnassigned = 0xE8;
    /// How many of the latest entries are kept ready before the overlay opens.
    private const int WarmedEntries = 30;
    private const int WarmDelay = 300, PasteDelay = 50, RestoreDelay = 400;
    /// Fastest the wheel may cycle.
    private static readonly TimeSpan WheelStepInterval = TimeSpan.FromMilliseconds(90);
    private const int WheelNotch = 120;
    private static readonly TimeSpan ModifierPoll = TimeSpan.FromMilliseconds(15);

    private readonly ClipboardHistory history;
    private readonly ClipboardMonitor monitor;
    private readonly ClipboardSettings settings;
    private readonly AppearanceSettings appearance;
    private readonly AppLog log;
    private readonly ClipPreviewWarmer warmer = new();
    private readonly DispatcherQueueTimer modifierTimer;
    private readonly DispatcherQueueTimer warmTimer;
    private readonly HashSet<int> keysDown = [];
    private OverlayWindow? window;
    private List<ClipItem> items = [];
    /// Steps taken since opening.
    private int position;
    private Shortcut activeShortcut = ClipboardSettings.DefaultShortcut;
    private volatile bool isVisible;
    private int wheelAccumulator;
    private DateTime lastWheelStep = DateTime.MinValue;
    private bool swallowsLeftUp;
    private int hoverQueued;

    public OverlayController(ClipboardHistory history, ClipboardMonitor monitor, ClipboardSettings settings, AppearanceSettings appearance, AppLog log)
    {
        this.history = history;
        this.monitor = monitor;
        this.settings = settings;
        this.appearance = appearance;
        this.log = log;
        modifierTimer = App.Ui.CreateTimer();
        modifierTimer.Interval = ModifierPoll;
        modifierTimer.Tick += (_, _) => CheckModifiers();
        // New entries get ready while nothing is shown, so the first open is quick too.
        warmTimer = App.Ui.CreateTimer();
        warmTimer.Interval = TimeSpan.FromMilliseconds(WarmDelay);
        warmTimer.IsRepeating = false;
        warmTimer.Tick += (_, _) => { if (!isVisible) warmer.Warm(history.Items.Take(WarmedEntries).ToList()); };
    }

    /// Readies the window and the latest entries ahead of the first open.
    public void Start()
    {
        history.Changed += QueueWarm;
        QueueWarm();
        window ??= new OverlayWindow(appearance);
        window.ShowEntry(history.Items.FirstOrDefault(), null, settings.CardWidth.Value, settings.CardHeight.Value, true, true);
        window.Warm();
    }

    public void Stop()
    {
        history.Changed -= QueueWarm;
        warmTimer.Stop();
        Dismiss();
    }

    private void QueueWarm()
    {
        warmTimer.Stop();
        warmTimer.Start();
    }

    /// Opens the overlay, or moves to the next entry if it is already open. shortcut is the one
    /// that was pressed: the overlay stays open while its modifiers are held.
    public void Cycle(Shortcut shortcut)
    {
        if (isVisible) Move(1);
        else
        {
            activeShortcut = shortcut;
            Show();
        }
    }

    /// Closes the overlay without pasting.
    public void Dismiss() => Hide();

    /// Pastes an entry picked outside the overlay (the tray menu).
    public void Paste(ClipItem item) => Commit(item);

    private ClipItem? SelectedItem => items.Count == 0 ? null : items[Selected];

    private int Selected => items.Count == 0 ? 0 : (position % items.Count + items.Count) % items.Count;

    private void Show()
    {
        items = history.Items.ToList();
        position = 0;
        // Already let go: a quick tap pastes the latest entry with nothing to show for it.
        if (!AreModifiersHeld())
        {
            Commit();
            return;
        }

        wheelAccumulator = 0;
        lastWheelStep = DateTime.MinValue;
        swallowsLeftUp = false;
        keysDown.Clear();
        isVisible = true;
        window ??= new OverlayWindow(appearance);
        ShowSelected();
        window.Present();
        // The entries after the first, in the order the shortcut steps through them.
        warmer.Warm(items.Skip(1).Take(WarmedEntries).ToList());

        InputHooks.Subscribe(OnKey);
        InputHooks.Subscribe(OnMouse);
        InputSender.Chord(VkUnassigned);
        modifierTimer.Start();
    }

    private void ShowSelected() => window?.ShowEntry(
        SelectedItem,
        items.Count == 0 ? null : T("%lld of %lld", Selected + 1, items.Count),
        settings.CardWidth.Value,
        settings.CardHeight.Value,
        settings.ShowCopyDate.Value,
        settings.ShowDeleteButton.Value);

    private void Move(int step)
    {
        if (items.Count == 0) return;
        position += step;
        ShowSelected();
    }

    private void Hide()
    {
        if (!isVisible) return;
        isVisible = false;
        modifierTimer.Stop();
        InputHooks.Unsubscribe(OnKey);
        InputHooks.Unsubscribe(OnMouse);
        window?.Dismiss();
        window?.ShowHover(null);
    }

    private void DeleteSelected()
    {
        if (SelectedItem is { } item) Delete(item);
    }

    private void Delete(ClipItem item)
    {
        var index = items.IndexOf(item);
        if (index < 0) return;
        var selected = Selected;
        history.Remove(item);
        items.RemoveAt(index);
        // Keep the same entry selected, or the one that took the deleted entry's place.
        position = items.Count == 0 ? 0 : index < selected ? selected - 1 : Math.Min(selected, items.Count - 1);
        ShowSelected();
    }

    /// Releasing any of the shortcut's modifiers pastes.
    private void CheckModifiers()
    {
        if (isVisible && !AreModifiersHeld()) Commit();
    }

    private bool AreModifiersHeld() =>
        (!activeShortcut.Ctrl || Hotkeys.IsHeld(VkLCtrl) || Hotkeys.IsHeld(VkRCtrl))
        && (!activeShortcut.Shift || Hotkeys.IsHeld(VkLShift) || Hotkeys.IsHeld(VkRShift))
        && (!activeShortcut.Alt || Hotkeys.IsHeld(VkLAlt) || Hotkeys.IsHeld(VkRAlt))
        && (!activeShortcut.Win || Hotkeys.IsHeld(VkLWin) || Hotkeys.IsHeld(VkRWin));

    /// Pastes item, or the selected entry when null.
    private void Commit(ClipItem? item = null)
    {
        item ??= SelectedItem;
        Hide();
        if (item is null) return;
        if (settings.MoveToTopOnPaste.Value) history.Promote(item);

        // Without moving to the top, put the last copied entry back once the paste has gone
        // through, so the next Ctrl+V pastes what was copied last, not what was picked.
        var latest = settings.MoveToTopOnPaste.Value ? null : history.Items.FirstOrDefault();
        var restores = latest is not null && latest.Id != item.Id;
        _ = Task.Run(async () =>
        {
            try
            {
                monitor.Write(item);
                await Task.Delay(PasteDelay);
                InputSender.ReleaseHeldModifiers();
                InputSender.Chord(VkControl, VkV);
                if (!restores) return;
                await Task.Delay(RestoreDelay);
                monitor.Write(latest!);
            }
            catch (Exception e) when (e is IOException or System.Runtime.InteropServices.ExternalException)
            {
                log.Add("Clipboard", $"Failed to paste: {e.Message}");
            }
        });
    }

    /// On the hook thread: everything here only passes the work to the UI thread.
    private void OnKey(KeyEvent e)
    {
        if (e.IsOwn || !isVisible) return;
        Action? action = e.Vk switch
        {
            VkEsc => Dismiss,
            VkUp or VkLeft => () => Move(-1),
            VkDown or VkRight => () => Move(1),
            VkDelete or VkBackspace => DeleteSelected,
            _ => null,
        };
        if (action is null) return;
        e.Handled = true;
        if (!e.IsDown)
        {
            keysDown.Remove(e.Vk);
            return;
        }
        // Holding an arrow keeps moving; holding Delete must not empty the history.
        var isRepeat = !keysDown.Add(e.Vk);
        if (isRepeat && e.Vk is VkEsc or VkDelete or VkBackspace) return;
        App.Ui.TryEnqueue(DispatcherQueuePriority.High, () => { if (isVisible) action(); });
    }

    /// On the hook thread, like OnKey.
    private void OnMouse(MouseEvent e)
    {
        if (e.IsOwn || !isVisible) return;
        switch (e.Action)
        {
            case MouseAction.Move:
                if (Interlocked.Exchange(ref hoverQueued, 1) == 0)
                    App.Ui.TryEnqueue(DispatcherQueuePriority.Low, UpdateHover);
                break;
            case MouseAction.LeftDown:
                swallowsLeftUp = e.Handled = true;
                App.Ui.TryEnqueue(DispatcherQueuePriority.High, () => Click(e.X, e.Y));
                break;
            case MouseAction.LeftUp:
                e.Handled = swallowsLeftUp;
                swallowsLeftUp = false;
                break;
            case MouseAction.Wheel or MouseAction.HorizontalWheel:
                e.Handled = true;
                App.Ui.TryEnqueue(DispatcherQueuePriority.High, () => Wheel(e.Data));
                break;
        }
    }

    private void UpdateHover()
    {
        Interlocked.Exchange(ref hoverQueued, 0);
        if (!isVisible || window is null) return;
        Native.GetCursorPos(out var point);
        window.ShowHover(window.HitTest(point.X, point.Y));
    }

    /// Releasing always pastes the selected entry, not the one under the pointer; a click pastes
    /// the card, deletes through its trash, and closes anywhere else, other screens included.
    private void Click(int x, int y)
    {
        if (!isVisible || window is null) return;
        switch (window.HitTest(x, y))
        {
            case OverlayHit.Trash:
                DeleteSelected();
                break;
            case OverlayHit.Card:
                Commit();
                break;
            case OverlayHit.Nothing or null:
                Dismiss();
                break;
        }
    }

    /// A notch moves one entry and touchpads add up to one; a fast flick doesn't queue up steps.
    private void Wheel(int delta)
    {
        if (!isVisible) return;
        wheelAccumulator = Math.Clamp(wheelAccumulator + delta, -WheelNotch, WheelNotch);
        if (Math.Abs(wheelAccumulator) < WheelNotch || DateTime.Now - lastWheelStep < WheelStepInterval) return;
        Move(wheelAccumulator < 0 ? 1 : -1);
        wheelAccumulator = 0;
        lastWheelStep = DateTime.Now;
    }
}
