# PasteRing: project context

What the app does and how the code is organized. For building and running, see README.md.

A native macOS menu bar app with a set of utilities: Clipboard (a history of copied items to pick from when pasting), Auto Quit, Middle Click, Remap and Window Snapping.

## Usage

- Copy as usual. PasteRing records text, rich text, images and files, most recent first, along with the app they were copied from (shown as its icon). Pasting an entry gives back exactly what was copied. The overlay shows images at the card's full width and rich text with its styling (fonts, bold and italic, colours, underline). Copies that arrive from your other Apple devices through Universal Clipboard are recorded too, marked as coming from another device.
- Hold `⌘⇧` and press `V` to open the overlay in the middle of the screen. The highlighted entry is what will be pasted.
- Keep holding `⌘⇧` and press `V`, the arrow keys (`↑`/`←` previous, `↓`/`→` next), or scroll to move through entries.
- Release `⌘` or `⇧` to paste the selected entry into the frontmost app.
- `⌘⇧Esc` closes the overlay without pasting. `⌘⇧Delete` removes the selected entry from the history.
- While holding `⌘⇧`, click any entry to paste it, click its trash icon to delete it, or click outside to close. Releasing always pastes the selected entry, not the one under the mouse.

History is saved in `~/Library/Application Support/PasteRing` (readable by your user only), so it survives restarts. Rich text, images and files are kept in full, up to 25 MB per entry.

## Settings

Open **Settings…** from the menu bar icon. The sidebar (with search) has one pane for the whole app and one per utility; each utility shows whether it is **On** or **Off** at the right of its row, and its pane starts with a switch to turn it on or off.

**General** (applies to every utility)
- **Accessibility**: when the permission is missing, a notice explains why it is needed, with a button to its page in System Settings.
- **Language** (see Languages below), **Date format** (Oct 9, 9 Oct, 10/9 or 9/10; never the year) and **Time format** (system setting, 24-hour or 12-hour).
- **Open at login**: on by default, so PasteRing is running after a restart.
- **About**: app icon, name and version.

**Clipboard** starts with its on/off switch (off stops recording and frees its shortcuts), then three tabs:
- **Settings**:
  - *General*: how many entries to keep (5 to 100, default 50), when to delete old entries (never by default, or after an hour, a day, a week or 30 days), and these switches:
    - **Ignore passwords**: skips text copied from password fields and password managers.
    - **Record images** (on): keeps copied images in the history.
    - **Paste as plain text** (off): pastes rich text without its formatting.
    - **Remove duplicates**: copying something already in the history moves it to the top instead of adding it again.
    - **Move pasted entry to the top**: when off, the history keeps copy order and `⌘V` keeps pasting the last copied text after you paste an older entry.
  - *Appearance*, with a live preview over your wallpaper:
    - **Style**:
      - *Default*: one card with the source app and the entry that will be pasted; cycling only swaps the content. Width and height are adjustable.
      - *Grid*: the most recent 8 to 24 entries (default 12) as tiles, all on screen at once. Tile width and height are adjustable (default 320 by 256). On a smaller screen it shows fewer rows, and narrower tiles, so everything fits.
      - *Carousel*: Cover Flow style, neighbours tilted away on either side. Card width and height are adjustable (default 260 by 260).
      - *Stack*: a pile of cards like the Default one; the next few peek out above the front card, smaller the further back. Cycling slides the front card down and fades it out while the next one comes forward; going back plays the same motion in reverse. Card width and height are adjustable (default 520 by 256).
      - *Ring menu*: the most recent entries (3 to 24, default 16) as cards laid out like grid tiles, spread around a fixed-size oval that turns to bring the selected one to the top (with more entries the cards overlap more; the oval and cards keep their size). Card width and height are adjustable (default 280 by 256); if the ring is bigger than the screen it is scaled down to fit.
    - **Show when entries were copied** and **Show delete button** (the History tab always has them).
    - Frosted material with **Tint** (default mid grey), **Tint strength** (20%), **Selected highlight** (30%), **Shadow** (16) and **Dim screen** (50%, fades in and out with the overlay). **Reset Appearance to Defaults** resets everything in this section.
  - *Shortcuts*: the shortcut that opens the overlay (default `⌘⇧V`) and any alternatives. Click one and press a new combination; it needs `⌘`, `⌥` or `⌃`.
- **History**: every saved entry with where and when it was copied, with a search field. The trash button deletes one, **Clear All** deletes everything.
- **Excluded Apps**: every installed app with a switch, all off. Switch an app on to exclude it: nothing copied in it is recorded.

Every entry in the overlay shows when it was copied next to its trash icon, in the date and time format chosen in General.

## Developer settings

Click the version in **Settings… > General > About** six times to add a **Developer** pane to the sidebar:

- **Logs**: what the utilities noticed and decided (newest first, searchable), with **Copy All** for bug reports and **Clear**.
- **Settings**: status details and settings regular users don't need, including **Hide Developer Settings**.

## Auto Quit

Quits an app when you close its last window, the way apps on iPad and many Windows apps behave. Off by default; turn it on in **Settings… > Auto Quit**.

- **Quit**: immediately, or after 1, 5 or 30 seconds (default 1 second) with no windows.
- **Excluded Apps**: every installed app with a switch, all off. Switch an app on to exclude it: it is never quit. The Finder is always excluded.
- It reacts to windows closing (no polling): when an app's window is destroyed, its other windows are checked right away, leaving out the one that closed, and the app quits after the chosen delay if none are left. Closing a full-screen window always waits about a second, since leaving full screen briefly leaves an app with no windows.
- Apps opened without a window, menu bar and background apps, and hidden apps are left alone: an app is only quit after it was seen with a window. Windows on other desktops are only noticed with the Screen Recording permission (macOS hides other apps' window titles without it), so without it closing the last window on this desktop can quit an app that still has one elsewhere.
- Decisions are logged under **Developer > Logs** (and in Console, as "PasteRing Auto Quit") to see why an app was or wasn't quit.
- Needs the Accessibility permission to see each app's windows.

## Middle Click

Middle click from the trackpad, which macOS doesn't offer. Off by default; turn it on in **Settings… > Middle Click**.

- **Tap with**: three fingers (default) or four. A quick tap with the fingers held still clicks the middle button where the pointer is.
- **Excluded Apps**: every installed app with a switch, all off. Switch an app on to exclude it: tapping while it is in front does nothing.
- It reads the trackpad's raw touches through the private MultitouchSupport framework and posts the click, so it needs the Accessibility permission.
- To use three fingers, turn off Look Up's three-finger tap in System Settings > Trackpad.

## Remap

Changes what keys and mouse buttons do, per device. Off by default; turn it on in **Settings… > Remap**.

- **Mappings**: every device (connected keyboards, mice and trackpads, and disconnected ones that still have mappings) is its own group, "<name> Mappings", all on one page; the pencil next to the title renames it. One group per physical device. Any key or button a device sends can be remapped on its entry; whether it looks like a keyboard or a mouse only picks its icon and which inputs the picker lists first. **Add Mapping** (the button at the right under each group) adds an empty row to it; rows with both sides still empty are dropped when the page is left or the app relaunches; each row's source and result are buttons that open a picker, so adding and editing work the same. A row missing either side does nothing.
  - Source: any key or mouse button except the left one. **Record** captures the next key or button pressed on that device; or pick from a searchable, sectioned list.
  - Result: another key, a mouse button, a system action (Mission Control, App Windows, Show Desktop, Launchpad, next or previous desktop, volume, mute, media, display and keyboard brightness, sleep display, lock screen, Spotlight, screenshots, emoji picker, Force Quit) or nothing.
  - Only the first mapping for a source applies: a later row for the same key or button on the same device shows "Already mapped above", with its result disabled. Nothing is deleted.
  - The swap button turns a mapping around (result becomes source); off when the result can't be a source, such as a system action.
- **Event Viewer**: every key and button pressed and released (Down and Up), newest at the bottom (the list follows new events unless scrolled up): the readable name, then the raw codes in parentheses (macOS key code and HID usage, or the button number macOS uses, counted from 0), and the device. A remapped event shows the key or button pressed, then an arrow and what it was remapped to, in blue. A key changed on the keyboard itself reaches macOS as the new key, so its original is worked out from the mappings: pressing the real target key can show as remapped too. Media keys are shown too. Hovering a row that can be remapped shows **Create Mapping**, which opens Mappings on that device with a mapping from it (or its existing one). Left clicks on that button aren't logged, so clicking it doesn't move the list; every other click is. Events posted by other apps (for example a mouse utility re-sending side buttons) have no device and show "Posted by" and the app; events from an interface PasteRing doesn't know show "Unknown device" and its ID. Logs only while the tab is open.
- How it works:
  - Key to key: set on the keyboard itself through the system's per-device `UserKeyMapping` property, so modifiers and Caps Lock work like real keys. Set again when a device connects or the Mac wakes; cleared when Remap is turned off or the app quits.
  - Everything else: an event tap that reads the sending device from the HID event inside each event (private `CGEventCopyIOHIDEvent` and `IOHIDEventGetSenderID`), swallows the original and posts the result.
  - Every interface of a device (keyboard, pointer, media keys, vendor extras) maps to it, since a mouse can send side buttons through any of them; only devices with a keyboard or pointer interface are listed.
  - Devices are identified by vendor, product and name, so mappings survive reconnects; identical devices share mappings.
  - Devices can be renamed (pencil next to the group title); an empty name goes back to the original.
  - A press that reaches macOS without its device (seen while recording or pressing) is remembered as device-less. It takes the oldest complete mapping for it on any device; newer mappings of it on other devices show "Already mapped on" that device, with their result disabled.
  - Next and previous desktop use the Control-arrow shortcuts, which must be on in System Settings > Keyboard > Keyboard Shortcuts > Mission Control.
- Needs the Accessibility permission.

## Window Snapping

Moves the front window to halves, corners, thirds or the whole screen. Off by default; turn it on in **Settings… > Window Snapping**.

- The pane is one page: Dragging, Gestures and Shortcuts sections, and **Reset to Defaults** (dragging, edge area, resizing together, filling space and gestures; not the on/off switch).
- **Shortcuts** (all ⌃⌥, fixed, listed in the Shortcuts section): ← → ↑ ↓ halves; U, I, J, K top left, top right, bottom left, bottom right; ↩ maximize; D, F, G left, center, right third; E, R, T left, center and right two thirds; C center; ⌫ restore (the frame before the window was first snapped, or before it was last moved by hand and snapped again).
- **Dragging** (on by default): drag a window by its title bar to an edge of the screen the pointer is on, see an outline of where it will go, and release:
  - Corners: quarters. Top edge: maximize.
  - Left or right edge: that half; near the top or bottom end of the edge, the top or bottom half.
  - Bottom edge: left, center or right third by where the pointer is; sliding along the bottom from a side third into the middle makes it two thirds on that side.
  - **Edge area** (8 to 150 points, default 64): how far into the screen edges reach, so a drag can stop on an edge shared with another display. Corners reach that far, and at least 64 points, along each edge; the top and bottom halves 145 points from the ends of a side edge.
  - **Gestures**: each area can be switched off (all on by default except the top and bottom halves). An area that is off leaves its place to the next one that applies, such as the side half instead of a corner.
  - The outline is rounded, dark and see-through, with a faint white border; it grows out of the edge or corner and glides between areas.
- **Resize side-by-side windows together** (on by default): a dragged edge is treated as a line across the whole screen. Every other window mostly on the same screen with an edge on that line (within 4 points), on either side and anywhere along it, has that edge moved with it, live and once more on release; so with a window in each corner, dragging any part of the middle line moves all four. A window with edges on two moved lines (dragging a corner) follows both. Windows don't shrink below 120 points.
- **Fill the space next to other windows** (on by default; shortcuts and dragging, preview included): a snap's sides that aren't on a screen edge move to the nearest edge of a tiled window, growing into a gap or shrinking away from a window.
  - Tiled windows: on the same screen, touching a screen edge (within 8 points), and at least half visible (sampled on a grid, against the windows in front). The moved window doesn't count.
  - Never overlaps them: where the free space isn't a rectangle, it leaves the gap.
  - A free side with no window directly beside it lines up with the nearest side of another tiled window (not a screen edge, and within a quarter of the screen of where it would be), so a new bottom-left quarter meets the line two moved top quarters share.
  - Each direction stays within a range of the usual size, or keeps the usual size: halves and corners 0.1 to 1.95 times (nearly the whole screen), thirds and two thirds 0.5 to 1.6 times (a third next to a single third doesn't become two thirds).
  - Maximize, Center and Restore never fill.
  - Exact area instead: pressing the same shortcut again on the same, unmoved window switches between the filled and the exact area (only when they differ); holding ⌘ while dragging previews and snaps the exact area, switching as ⌘ is pressed or released. The setting's subtitle says so.
  - If the app won't get as small as the space, the window gets the usual snap and the app's minimum is remembered, so later previews for it show the usual snap.
- Works through the Accessibility permission (frames of other apps' windows) and a listen-only event tap, which also sees drags of PasteRing's own windows; those are moved directly. macOS's own "Drag windows to screen edges to tile" (System Settings > Desktop & Dock) does something similar and should be off to avoid both acting.

## Languages

English, Spanish, French, Portuguese (Brazil), German, Italian and Catalan. **General > Language** picks one or follows the system; a change applies after relaunching (a **Relaunch** button appears). Dates follow the chosen language.

- Translations: `Resources/Localization/<language>.lproj/Localizable.strings`, keyed by the English text; `build-app.sh` copies them into the app and `Info.plist` lists the languages.
- `scripts/check-localization.py` finds the text the app shows and reports anything missing in a language.

## Project structure

PasteRing is meant to grow into a set of macOS utilities, so code is grouped by area:

```
Sources/PasteRing/
  App/                    entry point, app delegate (menu bar item, Settings window)
  General/                settings shared by every utility (language, date and time format)
  Settings/               the Settings window: sidebar, search, General pane
  Shared/                 helpers any utility can use (hotkeys, pasting, login item, app icons, device watcher, localization, relaunch)
  Utilities/
    AutoQuit/
      AutoQuit.swift           owns the utility
      Model/                   settings and the window watcher
      Settings/                the Auto Quit settings pane
    MiddleClick/
      MiddleClick.swift        owns the utility
      Model/                   settings and the tap listener
      Settings/                the Middle Click settings pane
    WindowSnapping/
      WindowSnapping.swift     owns the utility: shortcuts, snapping, restore frames
      Model/                   settings, snap actions, Accessibility windows, drag snapper, space filler, preview
      Settings/                the Window Snapping pane
    Remap/
      Remap.swift              owns the utility and its event tap
      Model/                   settings, devices, key catalog, system actions, key mapper, event log
      Settings/                the Remap pane: mappings, pickers, Event Viewer
    ClipboardManager/
      ClipboardManager.swift   owns the utility; created and started by the app delegate
      Model/                   history, clipboard monitor, settings
      Overlay/                 the ⌘⇧V overlay: controller, panel, state, surface
        Components/            cards and chips shared by the styles
        Styles/                one view per overlay style
      Settings/                the Clipboard Manager settings pane and its tabs
```

To add a utility: create `Utilities/<Name>/` with a class like `ClipboardManager` (a `start()`, an on/off setting, optional `menuItems()` and a `settingsPane()` that begins with `UtilityHeader`), create and start it in `AppDelegate`, and add a case for it to `SettingsPane` in `Settings/SettingsView.swift`, including its state in `isOn(_:)`.

## Notes

The app needs Accessibility. Builds are signed with an Apple Development certificate (see README.md) so the permission survives rebuilds. An ad-hoc signature changes every build and macOS then forgets it; a self-signed certificate was tried and macOS still kept asking.


`⌘⇧V` is also "Paste and Match Style" in some apps. PasteRing takes over that shortcut while running.
