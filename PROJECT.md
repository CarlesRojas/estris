# Estris: project context

The app was called PasteRing. On the first launch as Estris (new bundle identifier `com.carlesrojas.Estris`), its settings and its history in Application Support carry over (`App/RenameMigration.swift`); macOS permissions are tied to the identifier and must be granted again, and Estris adds itself to the login items as on a first install.

What the app does and how the code is organized. For building and running, see README.md.

A native macOS menu bar app with a set of utilities: Clipboard (a history of copied items to pick from when pasting), Auto Quit, Middle Click, Delete to Trash, Remap, Window Snapping, Focus Follows Mouse, Dock Preview, Keep Awake, Rounded Corners, Seasons, Color Picker and Volume Mixer.

## Usage

- Copy as usual. Estris records text, images and files, most recent first, along with the app they were copied from (shown as its icon). Text is always kept, shown and pasted as plain text, without its styling (entries saved styled by older versions too). Pasting an image or files gives back exactly what was copied. The overlay shows images at the card's full width. Copies that arrive from your other Apple devices through Universal Clipboard are recorded too, marked as coming from another device.
- Hold `⌘⇧` and press `V` to open the overlay in the middle of the screen. The highlighted entry is what will be pasted.
- Stepping through the history stays quick from the first press: the latest 30 entries are prepared ahead (app icon and name, image decoded; `ClipPreviewWarmer`), one per turn of the run loop so key presses go first, shortly after each copy and again in order when the overlay opens. Cards lay out only the first 3,000 characters of a text, and date formatters are reused.
- Keep holding `⌘⇧` and press `V`, the arrow keys (`↑`/`←` previous, `↓`/`→` next), or scroll to move through entries.
- Release `⌘` or `⇧` to paste the selected entry into the frontmost app.
- `⌘⇧Esc` closes the overlay without pasting. `⌘⇧Delete` removes the selected entry from the history.
- While holding `⌘⇧`, click any entry to paste it, click its trash icon to delete it, or click outside to close. Releasing always pastes the selected entry, not the one under the mouse.

History is saved in `~/Library/Application Support/Estris` (readable by your user only), so it survives restarts. Images and files are kept in full, up to 25 MB per entry.

## Settings

Every utility is off at first, so nothing asks for a permission until one that needs it is turned on. Settings opens whenever Estris is opened by hand (double-clicking it in Applications, also while it's running), not when it opens at login (`keyAELaunchedAsLogInItem` in the launch event). While Accessibility isn't allowed, Estris checks every 2 seconds; once it is, Estris opens again (Settings too, if it was open) so the utilities that set themselves up at launch get it.

Open **Settings** from the menu bar menu, or by opening Estris again. The sidebar (with search) has **General**, **Menu Bar** (and **Developer**, when unlocked) right under the search field, then the utilities in three groups, each under a small faint title: **Tools** (Clipboard, Color Picker, Volume Mixer, Keep Awake, Rounded Corners, Seasons), **Windows & Apps** (Window Snapping, Focus Follows Mouse, Dock Preview, Auto Quit) and **Keyboard & Mouse** (Remap, Middle Click, Delete to Trash). A search hides groups with no match; each utility shows whether it is **On** or **Off** at the right of its row (in English in every language), and its pane starts with a switch to turn it on or off.

Look and accessibility, kept the same everywhere: sidebar icons stay in the label color (the accent color clashes with the selected row); the switches inside a pane are the mini size (`RowSwitchStyle`, as System Settings), the utility's own switch in its header stays large; warnings under a row are an orange triangle with secondary text (`WarningLabel`), never orange text; icon-only buttons carry a VoiceOver label matching their tooltip; section headers use title case; the window shows the app's name, **Estris**, as its title at the top of the right column. With Reduce Motion, the clipboard overlay's styles move the selection without springs or slides, and the snap preview only fades.

Every utility that needs permissions starts its pane (below its on/off switch) with a **Permissions** section: each permission it needs with, in plain words, the one thing it is used for (for example Screen Recording: only to show a thumbnail of what each window shows), whether it is allowed (System Audio Recording read through the private `TCCAccessPreflight`, macOS having no public way; it often can't tell even once allowed, so sound coming through a Volume Mixer tap is remembered as proof it is), and a button to its System Settings page when it isn't or can't be told. While one is known not to be allowed, an orange line says what still works without it, and the utility works that way: Clipboard records and copies the picked entry (no paste), Remap keeps key-to-key mappings, Volume Mixer keeps the output and microphone (each app's row is disabled and no app is tapped, which would only silence it), Color Picker uses macOS's loupe, Dock Preview shows app icons instead of thumbnails; Auto Quit, Middle Click, Delete to Trash, Window Snapping and Focus Follows Mouse can't do anything without Accessibility. Once allowed, the full behavior applies without changing any setting. Turning a utility on while one of its permissions isn't allowed opens an alert, "Allow what <utility> needs?", listing each missing permission and what it is for; **Allow** asks macOS for them (its own prompt for Accessibility, and for Screen Recording the first time; the System Settings page after that and for System Audio Recording, which has no public way to ask), **Not Now** leaves the utility on, working without them. Utilities that need none (Keep Awake, Rounded Corners, Seasons) have no such section; an optional one (Color Picker's Screen Recording) says so.

Every pane but General, Remap and Developer ends with **Reset to Defaults**, which puts that pane's settings back to how they start out. It leaves the utility's on/off switch, excluded apps, the clipboard history and Open at login as they are.

Every row with a setting (switch, slider, stepper, picker, color, shortcut key), the utilities' on/off switches, each Excluded Apps row and each Volume Mixer app also has a right-click menu (anywhere on the row, its background included) with **Reset to Default**, which puts back just that one (`resetMenu` in `Settings/ResetMenu.swift`); no menu shows while it already has its default. Each settings class keeps its defaults as constants, used by `reset()` and these menus alike. Not covered, as they have no default: Remap's mappings, the Clipboard's alternative shortcuts, the Volume Mixer's output and microphone (the Mac's own), and history.

**General** (applies to every utility)
- **Permissions**: whether Accessibility is allowed, with a button to its page in System Settings when it isn't. It isn't asked for at launch, only when turning on a utility that needs it.
- **Language** (see Languages below), **Date format** (Oct 9, 9 Oct, 10/9 or 9/10; never the year) and **Time format** (system setting, 24-hour or 12-hour).
- **Open at login**: on by default, so Estris is running after a restart.
- **About**: app icon, name and version, with links to the website and to open an issue on GitHub.
- **Export & Import** (at the bottom): **Export Settings…** saves every Estris setting to a JSON file; **Import Settings…** reads one back after a confirmation, replacing the current settings, and Estris opens again to apply them. Everything Estris keeps in UserDefaults goes in (the app's language too), except state tied to the Mac (login item setup, permission hints, migrations); the clipboard history and Open at login don't. Data stored as JSON stays readable in the file (`$json`), other data and dates are wrapped (`$data`, `$date`) (`Shared/SettingsTransfer.swift`).

**Clipboard** (off by default) starts with its on/off switch (off stops recording and frees its shortcuts), then three tabs:
- **Settings**:
  - *General*: how many entries to keep (5 to 100, default 50), when to delete old entries (never by default, or after an hour, a day, a week or 30 days), and these switches:
    - **Ignore passwords**: skips text copied from password fields and password managers.
    - **Record images** (on): keeps copied images in the history.
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

## Menu bar

Clicking the menu bar icon opens a menu below it in the clipboard overlay's default frosted look (always the defaults, whatever its Appearance settings). It shows, for each of these utilities while it is on and with the parts chosen in Settings > Menu Bar:

- **Volume Mixer**: the same rows as its pane, titled **System Volume** and **Apps Volume**.
- **Clipboard**: the most recent entries (off by default), each with its source app and one line of it; a click pastes it into the app in front, as the overlay does. A **Clear History** button (on by default) empties the history.
- **Color Picker**: the recent colors (off by default), a click copies one; a **Pick a Color** button (on by default) that starts picking.

Then **Settings** and **Quit** side by side at the bottom, as capsules, set apart from the groups above by three times the gap between groups. The menu hangs a little below the menu bar; its corners are concentric with the capsule buttons, and each part (System Volume, Apps Volume, Clipboard, Color Picker) sits in its own rounded box. In dark mode the menu is a shade darker than the overlay's surface and the boxes a lighter grey; in light mode the menu is almost white and the boxes a light grey, concentric with the menu; no separator lines. A click outside, Esc or another click on the icon closes it.

**Menu Bar** in Settings (no on/off switch) picks the icon: 52 in a 13 by 4 grid, all in view, a click applies it at once. Estris's own icon comes first and is the default: the bento box (one tall compartment and two small ones), as on the app icon. Then Estris's other drawings (a chest of drawers, a ring of six dots, three sliders), drawn in code on a 24-point grid (`MenuBarIcon.swift`), the clipboard (the icon before Estris had its own), and common monochrome symbols (star, heart, flame, leaf, sun, moon, cloud, bolt...). All are template images, so macOS draws them in the menu bar's colour. Then a section per utility picks what the menu shows of it: Under the grid, **Custom color** (off) draws the icon in a chosen colour instead of the menu bar's own (it starts from white), with a colour well to pick it; the grid shows the icons in it too.

- **Volume Mixer**: **Show System Volume**, with **Show Output** and **Show Microphone** under it (they do nothing while it is off), **Show Apps Volume**, **Show device pickers** (all on) and **Show volume percentages** (off).
- **Clipboard**: **Show recent entries** (off) and how many (**Entries**, 1 to 10, default 5), **Show Clear History button** (on).
- **Color Picker**: **Show Pick a Color button** (on) and **Show recent colors** (off).

**Reset to Defaults** puts the icon and all of these back.

Device pickers look the same everywhere (Settings and the menu): the device's name with up-down arrows and no background until the pointer is over them, aligned to the right edge whatever the name's length, long names cut short. The System rows show a coloured tile where an app row has the app's icon (blue for Output, orange for Microphone), so it doesn't look like the mute button below it.

## Developer settings

Click the version in **Settings > General > About** six times to add a **Developer** pane to the sidebar:

- **Logs**: what the utilities noticed and decided (newest first, searchable, and filtered to one utility with the menu next to the search), with **Copy All** (what is shown) for bug reports and **Clear**. A click on an entry copies that line alone (time, utility and message), and it shows "Copied" for a moment.
  - **Permissions** entries: what macOS says about Accessibility, Screen Recording, Input Monitoring, Post Events and System Audio Recording (the last through the private `TCCAccessPreflight`, for the log only), at launch and whenever it changes.
- **Settings**: status details and settings regular users don't need: **Show Dock Preview's hover area** (draws, while the panel shows, the panel and icon in blue and the triangle that keeps it open in orange (faded while it is being ignored), over everything and letting clicks through), and **Hide Developer Settings**.

## Auto Quit

Quits an app when you close its last window, the way apps on iPad and many Windows apps behave. Off by default; turn it on in **Settings > Auto Quit**.

- **Quit**: immediately, or after 1, 5 or 30 seconds (default 1 second) with no windows.
- **Excluded Apps**: every installed app with a switch, all off. Switch an app on to exclude it: it is never quit. The Finder is always excluded.
- It reacts to windows closing (no polling): when an app's window is destroyed, its other windows are checked right away, leaving out the one that closed, and the app quits after the chosen delay if none are left. Closing a full-screen window always waits about a second, since leaving full screen briefly leaves an app with no windows.
- The chosen delay applies when you close the window (its close button, a menu item with ⌘W, ⌘W itself, or Dock Preview's close button). When the app closes its last window on its own, often to open another (Android Studio closes its project picker, then opens the project), it gets 10 seconds to show a new one before it is quit.
- Apps opened without a window, menu bar and background apps, and hidden apps are left alone: an app is only quit after it was seen with a window. Windows on other desktops are only noticed with the Screen Recording permission (macOS hides other apps' window titles without it), so without it closing the last window on this desktop can quit an app that still has one elsewhere. Windows an app keeps hidden on no desktop, as Safari does with closed windows so it can reopen them, don't count.
- Decisions are logged under **Developer > Logs** (and in Console, as "Estris Auto Quit") to see why an app was or wasn't quit.
- Needs the Accessibility permission to see each app's windows.

## Middle Click

Middle click from the trackpad, which macOS doesn't offer. Off by default; turn it on in **Settings > Middle Click**.

- **Tap with**: three fingers (default) or four. A quick tap with the fingers held still clicks the middle button where the pointer is.
- **Excluded Apps**: every installed app with a switch, all off. Switch an app on to exclude it: tapping while it is in front does nothing.
- It reads the trackpad's raw touches through the private MultitouchSupport framework and posts the click, so it needs the Accessibility permission.
- To use three fingers, turn off Look Up's three-finger tap in System Settings > Trackpad.

## Delete to Trash

Delete deletes what is selected, as on Windows, where macOS wants ⌘⌫. Off by default; turn it on in **Settings > Delete to Trash**.

- In any app whose menus have a command on ⌘⌫ (Move to Trash in Finder, Delete in Photos, Notes, Music and many others), Delete with no modifier is sent on as ⌘⌫. The commands are found by their shortcut, read from the items of each menu in the app's menu bar through Accessibility (submenus left out), so it doesn't matter what they're called or in which language. They are read when an app comes to the front and kept for 5 seconds.
- **Delete (⌫)** (the Mac keyboard's delete key, Backspace on others) and **Forward Delete (⌦)** (Delete on keyboards made for Windows, fn-Delete on a Mac keyboard) each have a switch, both on by default.
- **Shift-Delete deletes immediately** (on by default): Shift with either key is sent on as ⌥⌘⌫ where the app has that (Delete Immediately in Finder, which asks first). Off, Shift-Delete is left as it is.
- Finder always counts as having both (its Delete Immediately is a hidden alternate menu item). In Finder's Trash, where ⌘⌫ is Put Back, Delete is sent on as ⌥⌘⌫ instead, found by the front window's title being the Trash's name.
- Left as it is while the focus is on something that takes text (a text field, a text area, a search field, renaming a file), or when that can't be told; with ⌘, ⌃ or ⌥ held; in Estris itself; in apps without such a command; and in excluded apps.
- **Excluded Apps**: every installed app with a switch, all off. Switch an app on to leave the keys alone in it.
- Holding the key down deletes once: repeats are dropped.
- Uses an event tap on key presses and reads what has the focus and the apps' menus, so it needs the Accessibility permission.

## Remap

Changes what keys and mouse buttons do, per device. Off by default; turn it on in **Settings > Remap**.

- **Mappings**: every device (connected keyboards, mice and trackpads, and disconnected ones that still have mappings) is its own group, "<name> Mappings", all on one page; the pencil next to the title renames it. One group per physical device. Any key or button a device sends can be remapped on its entry; whether it looks like a keyboard or a mouse only picks its icon and which inputs the picker lists first. **Add Mapping** (the button at the right under each group) adds an empty row to it; rows with both sides still empty are dropped when the page is left or the app relaunches; each row's source and result are buttons that open a picker, so adding and editing work the same. A row missing either side does nothing.
  - Source: any key or mouse button except the left one. **Record** captures the next key or button pressed on that device; or pick from a searchable, sectioned list.
  - Result: another key, a mouse button, a system action (Mission Control, App Windows, Show Desktop, Launchpad, next or previous desktop, volume, mute, media, display and keyboard brightness, sleep display, lock screen, Spotlight, screenshots, emoji picker, Force Quit) or nothing.
  - Only the first mapping for a source applies: a later row for the same key or button on the same device shows "Already mapped above", with its result disabled. Nothing is deleted.
  - The swap button turns a mapping around (result becomes source); off when the result can't be a source, such as a system action.
- **Event Viewer**: every key and button pressed and released (Down and Up), newest at the bottom (the list follows new events unless scrolled up): the readable name, then the raw codes in parentheses (macOS key code and HID usage, or the button number macOS uses, counted from 0), and the device. A remapped event shows the key or button pressed, then an arrow and what it was remapped to, in blue. A key changed on the keyboard itself reaches macOS as the new key and can't be told apart from pressing that key, so both show as the new key, with no arrow. Media keys are shown too. Hovering a row that can be remapped shows **Create Mapping**, which opens Mappings on that device with a mapping from it (or its existing one). Left clicks on that button aren't logged, so clicking it doesn't move the list; every other click is. Events posted by other apps (for example a mouse utility re-sending side buttons) have no device and show "Posted by" and the app; events from an interface Estris doesn't know show "Unknown device" and its ID. Logs only while the tab is open.
- How it works:
  - Key to key: set on the keyboard itself through the system's per-device `UserKeyMapping` property, so modifiers and Caps Lock work like real keys. Set again when a device connects or the Mac wakes; cleared when Remap is turned off or the app quits.
  - Except when the resulting key has a mapping of its own on that device (to a button, an action or nothing): the keyboard would report both presses as that key, so the event tap does that key to key instead and sees the key actually pressed. This repeats for chains.
  - Everything else: an event tap that reads the sending device from the HID event inside each event (private `CGEventCopyIOHIDEvent` and `IOHIDEventGetSenderID`), swallows the original and posts the result.
  - Every interface of a device (keyboard, pointer, media keys, vendor extras) maps to it, since a mouse can send side buttons through any of them; only devices with a keyboard or pointer interface are listed.
  - Devices are identified by vendor, product and name, so mappings survive reconnects; identical devices share mappings.
  - The input services are read through a new event system client each time: a client keeps the list it started with, so a keyboard that reconnected later (a Bluetooth one after the Mac starts, with a new id) never showed up and its presses came from an unknown device. Developer > Logs lists the keyboard, pointer and media key services when they change, and a press from a service not listed.
  - A wireless keyboard just after the Mac starts can show up without its product name: an unnamed interface with the vendor and product of a device that has mappings counts as that device. The devices are listed again 5 and 20 seconds after launch, and when a press comes from an interface not listed yet (at most every 2 seconds); each time, key-to-key mappings are set again on the keyboards found.
  - Devices can be renamed (pencil next to the group title); an empty name goes back to the original.
  - A key picked from the list belongs to its device and never conflicts with other devices. Two mappings for the same key on one device do: the later shows "Already mapped above".
  - A mapping recorded from a press that reached macOS without its device is device-less (events posted by apps, Estris included, never count). Such presses take the oldest complete device-less mapping for them on any device; newer device-less mappings of the same key on other devices show "Already mapped on" that device, with their result disabled. Picking the key from the list again, or swapping, makes it belong to its device.
  - Next and previous desktop use the Control-arrow shortcuts, which must be on in System Settings > Keyboard > Keyboard Shortcuts > Mission Control.
- Needs the Accessibility permission.

## Window Snapping

Moves the front window to halves, corners, thirds or the whole screen, or arranges all the screen's windows. Off by default; turn it on in **Settings > Window Snapping**.

- The pane is one page: Dragging, Auto Arrange All Windows, Gestures and Shortcuts sections, and **Reset to Defaults** (dragging, edge area, frosted preview, resizing together, filling space, gestures, Arrange All and the shortcut keys; not the on/off switch).
- **Shortcuts** (all ⌃⌥, listed in the Shortcuts section; each row's key is a menu to pick another, saved by id in `windowSnappingKeyCodes`): ← → ↑ ↓ halves; U, I, J, K top left, top right, bottom left, bottom right; ↩ maximize; D, F, G left, center, right third; E, R, T left, center and right two thirds; ⌫ restore (the frame before the window was first snapped, or before it was last moved by hand and snapped again).
- Windows kept in front of everything (floating video players, picture in picture, overlays: any window above the normal window level) are left out of everything: they aren't snapped by shortcut or dragging, arranged, or resized together with their neighbours, and resizing one doesn't move others.
- **Arrange All Windows** (⌃⌥Space unless changed, a switch and its key in the Auto Arrange All Windows section, on by default): every window on the screen the pointer is on shares it evenly, each going to the space nearest where it is (the pairing that moves them least in all, between centres measured in proportion to the screen, so what is further left ends up on the left and what is higher, higher): two side by side, three in thirds, four in quarters; from five on, about √n columns with the windows spread over them, fewer per column on the left (five is a left third plus four quarters of the rest, six is three columns of two, seven 2 + 2 + 3, and so on). Normal windows of regular apps (and Estris's own) mostly on that screen; minimized and hidden ones stay. Each window is found by its window server number, since Accessibility's window list can miss one just brought over from another desktop; then by frame; then among the app's elements one by one (`AXWindow.of(pid:number:frame:)`). An app with a maximum size that can't fill its space takes what it can, and the others share the rest (columns as wide as their widest window can be, rows within a column the same way); the layout is worked out again with the sizes windows actually took, up to three rounds, as a window given more room may have a maximum too. Each window's frame before is kept, so Restore (⌃⌥⌫) puts the front one back. ⌃⌥Space is also macOS's shortcut for the next input source (on by default).
- **Conflicts**: right below a shortcut's row, a warning when another Window Snapping shortcut has the same key (Arrange All only while on), naming which one takes priority: the first in the pane's order (Arrange All, then the snap actions top to bottom), the only one registered, or when a turned-on macOS shortcut is ⌃⌥ and that key (macOS keeps the keys), with **Open Keyboard Shortcuts**; the input source one is named. macOS's shortcuts are read through the window server's symbolic hot keys (`Shared/SystemShortcuts.swift`, shared with Dock Preview), again each time Estris comes back to the front.
- The center third's icon is drawn (`SnapActionIcon`): a frame with a bar in its middle third, as SF Symbols has none.
- **Dragging** (on by default): drag a window by its title bar to an edge of the screen the pointer is on, see an outline of where it will go, and release:
  - Corners: quarters. Top edge: maximize.
  - Left or right edge: that half; near the top or bottom end of the edge, the top or bottom half.
  - Bottom edge: left, center or right third by where the pointer is; sliding along the bottom from a side third into the middle makes it two thirds on that side.
  - **Edge area** (8 to 150 points, default 64): how far into the screen edges reach, so a drag can stop on an edge shared with another display. Corners reach that far, and at least 64 points, along each edge; the top and bottom halves 145 points from the ends of a side edge.
  - **Gestures**: each area can be switched off (all on by default except the top and bottom halves). An area that is off leaves its place to the next one that applies, such as the side half instead of a corner.
  - The outline is rounded like a window's corners, dark and see-through, with a faint white border; it sits just behind the dragged window (in front of every other one), grows out of the edge or corner and glides between areas.
  - **Frosted preview** (off by default): the outline is an empty Clipboard Manager card instead, in its default look (grey tint and shadow, no border) with a lighter blur (30 points instead of 60).
- **Resize side-by-side windows together** (on by default): a dragged edge is treated as a line across the whole screen. Every other window mostly on the same screen with an edge on that line (within 4 points), on either side and anywhere along it, has that edge moved with it, live and once more on release; so with a window in each corner, dragging any part of the middle line moves all four. A window with edges on two moved lines (dragging a corner) follows both. Windows don't shrink below 120 points.
- **Fill the space next to other windows** (on by default; shortcuts and dragging, preview included): a snap's sides that aren't on a screen edge move to the nearest edge of a tiled window, growing into a gap or shrinking away from a window.
  - Tiled windows: on the same screen, touching a screen edge (within 8 points), and at least half visible (sampled on a grid, against the windows in front). The moved window doesn't count.
  - Never overlaps them: where the free space isn't a rectangle, it leaves the gap.
  - A free side with no window directly beside it lines up with the nearest side of another tiled window (not a screen edge, and within a quarter of the screen of where it would be), so a new bottom-left quarter meets the line two moved top quarters share.
  - Each direction stays within a range of the usual size, or keeps the usual size: halves and corners 0.1 to 1.95 times (nearly the whole screen), thirds and two thirds 0.5 to 1.6 times (a third next to a single third doesn't become two thirds).
  - Maximize and Restore never fill.
  - Exact area instead: pressing the same shortcut again on the same, unmoved window switches between the filled and the exact area (only when they differ); holding ⌘ while dragging previews and snaps the exact area, switching as ⌘ is pressed or released. The setting's subtitle says so.
  - If the app won't get as small as the space, the window gets the usual snap and the app's minimum is remembered, so later previews for it show the usual snap.
- A window whose app can't get as big as a snap (a maximum size) keeps to the screen edges the snap touches (centred where it touches neither or both), so the space left is beside the others, where a filled snap or Arrange All can use it.
- Works through the Accessibility permission (frames of other apps' windows) and a listen-only event tap, which also sees drags of Estris's own windows; those are moved directly. macOS's own "Drag windows to screen edges to tile" (System Settings > Desktop & Dock) does something similar and should be off to avoid both acting.

## Focus Follows Mouse

The window under the pointer comes to the front and its app becomes active, without clicking. Off by default; turn it on in **Settings > Focus Follows Mouse**.

- **Focus after hovering for**: **Immediately**, or 100 (default), 250, 500 or 1000 ms. The delay counts while the pointer stays over the same window moving slowly or resting, without having to stop; moving fast (over **Skip windows when moving faster than**, 200 to 3000 points per second, default 800, smoothed over the last moves) or entering another window starts it again, so windows crossed on the way stay where they are. Immediately focuses a window as soon as the pointer is over it moving slowly.
- Nothing happens while a mouse button or a modifier key is held (dragging, clicking, a shortcut), over menus, the Dock, the menu bar, the desktop or anything else that isn't a normal window (window layer 0), over Estris's panels (menu, overlay, pills), while a sheet or modal dialog of the app in front is open, while the app in front has a panel open (its focused window is a dialog or floating window, or it has a window on screen floating above normal ones, window layers 1 to 20; panels don't cover the screen, so the windows behind them are easy to cross, and raising one would hide the panel), or when switching desktops.
- The window is raised (Accessibility `AXRaise` and `AXMain`) and its app activated. Estris's own titled windows (Settings) are brought forward too. The pointer is read with a listen-only event tap, which unlike a global event monitor also sees moves over Estris's windows. Focusing without raising would need private window server calls, so it always raises.
- **Switching Apps**: **Keep new windows and apps you switch to in front** (on by default) leaves an app in front for **Keep them in front for** (1 to 15 seconds, default 2) after it opened or the user switched to it (clicking it, ⌘Tab, Mission Control, the Dock: any activation hovering didn't cause, from `NSWorkspace.didActivateApplicationNotification`): hovering other apps' windows doesn't focus them meanwhile. The same goes for any new window of any app (a dialog, a popup like a browser's screen sharing picker): for that time, hovering any other window doesn't focus it. New windows are found by listing the normal windows on screen (layer 0, at least 100 by 60 points, not Estris's) at most every 0.2 s while the pointer moves and before each focus; windows coming on screen in the second after switching desktops don't count, and a window that closes stops counting. Such apps and windows are often away from the pointer, and moving to them would otherwise send them behind; with Mission Control the pointer can rest on another app as it closes.
- **Excluded Apps** tab: apps whose windows are never focused by hovering.
- Each focus is logged under **Developer > Logs**.

## Dock Preview

Rest the pointer on a running app's icon in the Dock to see its windows as thumbnails, in a panel next to the icon (above a bottom Dock, beside a left or right one) in the clipboard overlay's default frosted look. Off by default; turn it on in **Settings > Dock Preview**. Needs macOS 14 or later; on older versions its pane is hidden and it never starts.

- Each window's card has the app's icon and the window's name at the top left and, at the same height on the right, a × (**Show a button to close each window**, on) that closes the window: just the symbol, faint, darker on hover and while pressed. Below, the thumbnail.
- A click on a card brings its window to the front (un-minimizing it) and activates the app. A window on another desktop: Estris goes there first, activating the app (macOS travels by itself when the app has no window on the desktop showing) and otherwise pressing the user's own "Move left/right a space" shortcut (Mission Control shortcuts, read from the system) one desktop at a time until the window's desktop shows, then raises it. Desktop membership and the shortcuts come from private window server calls looked up at run time; without them, it only activates the app.
- While the panel shows (and **Switch windows with the scroll wheel** is on; off by default), the scroll wheel (or a trackpad swipe) moves a highlight through the windows and brings each one forward, going to its desktop if needed, with the panel still open to keep going (a fast spin acts where it pauses, after 0.12 s; desktop changes from it don't close the panel). Return opens the highlighted one and closes the panel, Esc closes it; the scroll doesn't reach the app underneath. An active event tap does this, enabled only while the panel shows.
- An automatically hidden Dock stays showing while the panel is open: autohide is turned off for that time (private CoreDock call), with a marker saved first so it is turned back on at the next launch if Estris quits before it could, and also on quitting.
- **Size** (slider, 80 to 320 pt, default 200): the thumbnails' height; their width follows each window's shape.
- **Open after hovering for**: Immediately (default), 100, 250, 500 or 1000 ms. Sliding along the Dock to another app switches the panel after at most 100 ms.
- **Show only windows on the current desktop** (off): when off, windows on other desktops and minimized ones are listed too. At most 10 windows.
- The panel stays while the pointer is on the icon, on the panel or on the way between them (a triangle from where the pointer last was on the icon to the panel's corners on the Dock's side: heading for any window, even diagonally across other icons, stays in it, while sliding along the Dock leaves it at once, so the next app's preview still follows). The triangle is ignored over another Dock icon when the pointer is slow there (under 150 points per second, smoothed) or rests on it for 0.15 s: that app's preview comes instead; and when the pointer stops in it for 0.15 s off the panel and every icon, after which the panel closes as usual, and closes 0.3 s after it leaves (time to cut a corner on the way up to the panel), on a click outside it (including on the Dock) or when switching desktops. After a click on a Dock icon (opening the app, or its right-click menu), that icon's preview waits until the pointer leaves it and comes back, and none opens while one of the Dock's menus is on screen (a Dock window at the pop-up menu level).
- How: a listen-only event tap follows the pointer; only near the Dock's edge (from the Dock's own preferences: position, icon size, magnification) does it ask Accessibility for the Dock icon under it. Windows come from the window server's list; thumbnails from ScreenCaptureKit (**Screen Recording**, asked for by the alert when the utility is turned on), cached so they show at once next time. A window's thumbnail is captured at the size it can show at most (twice the height, in the screen's pixels), all the app's windows at once. ScreenCaptureKit's list of capturable windows, the slowest part, is asked for as soon as the pointer rests on an icon and kept for 30 seconds (asked again for a window it doesn't have yet; sizes always come from the window server's list), so moving between icons reuses it. Without Screen Recording it still works: each card keeps its size with the app's icon in the middle instead of a thumbnail, titles come from Accessibility (the window list hides them then), and ScreenCaptureKit isn't asked at all. Raising and closing go through Accessibility, matching windows by number.

## Keep Awake

Keeps the Mac and its display awake until it has been idle for a chosen time, then starts the screen saver or puts it to sleep. Turn it on with the switch in **Settings > Keep Awake**; it stays on until turned off.

- **Idle Time Before Sleep**, separately **On power adapter** (default Indefinitely) and **On battery** (default 1 hour): Don't keep awake, 15 or 30 minutes, 1, 2, 4 or 8 hours, or Indefinitely.
- Idle means no mouse, keyboard or trackpad input (the system's HID idle time) and no other app keeping the display on (as video players do while playing). Any of those starts the count again.
- While not idle for that long it holds a `PreventUserIdleDisplaySleep` power assertion; once idle for that long it releases it and starts the screen saver (**Start the screen saver instead of sleeping**, on by default) or puts the Mac to sleep (`pmset sleepnow`); a global input monitor or the screen or Mac waking holds it again. Waking counts as activity, so the count starts over instead of sleeping again straight away.
- It looks again exactly when the idle time would run out, and whenever macOS posts that power assertions changed (an app starts or stops keeping the Mac awake); while another app keeps the display on it also looks every 5 seconds, in case that notice doesn't come. Which apps keep the display on is logged under Developer > Logs as it changes.
- Plugging in or out (IOKit power source notifications) applies the other choice at once. "Don't keep awake" pauses it; "Indefinitely" always holds.
- **Status** (while on): the power source; the state, refreshed every second while the pane is open (Active while the Mac is used, meaning input within the last second, or while another app keeps the display on; Inactive while counting down; Inactive, macOS sleep settings apply once the time is up; Always on; Not keeping awake); and, while counting, **Sleeps in** with a countdown of whole seconds left (full while the Mac is used, 0:00 during the last second) that ticks while the pane is open.

## Rounded Corners

Paints the corners of every screen black, as if the screens themselves had rounded corners. Turn it on with the switch in **Settings > Rounded Corners** (off by default).

- **Radius** (2 to 40 points): how round the corners are. By default as round as macOS's window corners (16 points from macOS 26, 10 before), so a window filling the screen, which touches its edges, is concentric with them. The corners follow the slider as it moves.
- Each corner is a small borderless window (twice the radius on each side) that lets clicks through, at the screen saver level so it covers the menu bar, the Dock and full screen apps, on every Space. A shape layer fills what lies outside the screen's continuous rounded outline (the same curve as SwiftUI's `RoundedRectangle(style: .continuous)`). The windows are kept and moved rather than made again, and redone when screens are added, removed or rearranged.
- Left out of screenshots and screen recordings (`sharingType = .none`), where real screen corners wouldn't show.

## Seasons

The season's particles fall over every screen and pile up: snow in winter, pink petals in spring, beach sand in summer, autumn-coloured leaves in autumn. Turn it on with the switch in **Settings > Seasons** (off by default).

- **Season**: Automatic (by default) or one of the four. Automatic follows the date in whole months (winter is December to February), flipped for Macs set to a region south of the equator; checked once a minute.
- **Falls**: in front of windows (by default) or behind them, over the desktop only.
- **Density** (10% to 400%): how much falls, on top of each season's own rate (sand falls thick and fast, leaves few and slow).
- **On each window** (0 to 2,000, 500 by default) and **At the bottom** (0 to 10,000, 3,000 by default): how many particles a window's top edge, or the bottom of a screen, holds; past that, the oldest melts away. At 0, nothing lands on windows, or what reaches the bottom melts at once.
- **Wind** (strongest to the left to strongest to the right, blowing what falls and, past a light breeze, the piles: the loose top of snow and sand moves downwind, some of it lifted into the air, blowing off a window's downwind end and drifting against the screen's edge; strong wind picks the top leaves and petals off their piles; calm by default, up to 140 points per second) and **Falling** (on by default: off, nothing new falls and what is there stays). Both are also on the weather widget; Reset to Defaults calms the wind and leaves Falling alone.
- **Pause** on battery or in Low Power Mode, and on a screen showing a full screen app (both on by default). It also stops while the screens sleep. Paused, its windows hide and piles keep where they were.
- Physics: particles fall at their own speed, sway and turn, and take the speed of the air around them (a `wind` that is still for now, meant to be set later). Leaves and petals tumble, turning edge-on and back faster the quicker they move. They land on the bottom of the screen (behind the Dock, which hides that part) and on the top edges of windows; each pile is a row of 3-point columns, lying on the edge's real shape: flat, then dropping down a window's rounded corners (10 points before macOS 26, 16 from it, 22 for the weather widget) so what lands there slides off as it would. Each column (its slope taken from the curve itself) of a drift holds only what its slope allows: sand nothing past about 30°, snow a little more, to about 50°; the rest slides outward and falls off the side. Leaves and petals stay themselves, stacked in their column and lying on their side, and what lands on a column standing too far above its neighbour rolls down, and off a window's edge. Snow and sand merge into a drift instead (`DriftLayer`): each column only a depth, settling every frame. Sand flows down to about 23°, eases into any hollow beside it (dig some out and the rest runs in) and pours off a window's edge as a stream of grains; Snow lands spread a little wider, sticks, rounds off over a window's edge and keeps smoothing until its surface is even, into soft mounds without peaks. A drift is drawn as a picture rendered pixel by pixel from its heights, at most 20 times a second: lit from the upper left by its slope near the surface, darker where it meets what it lies on, over a texture fixed to the screen so it doesn't shimmer. Sand has grains of a few tones with dark and bright specks; snow a fine, faintly blue grain, bluish deeper in, a soft uneven top and single pure white pixels scattered through it that fade slowly in and out, as snow catches the light. A window that just moved collects nothing until it has been still for 0.3 seconds, so a dragged or shaken window stays clear. Dug or shaken off, snow falls in clumps and sand scatters as many fine grains (`SeasonStyle.debris`), which join a drift again where they land. The pointer pushes and carries what it passes through; a quick sweep scatters leaves and petals and digs through snow, throwing up clumps, while sand gives way even to a slow hand. A drift's limit is its volume as that many particles: a window's drift that is full stops catching, and what falls carries on past it to the bottom; the bottom of the screen's drift settles lower instead.
- A window that moves, resizes, closes, minimizes or goes to another Space drops its pile, which falls with the window's speed (a drift breaking up into grains or clumps), so shaking a window flings it off. Parts of a top edge hidden by a window in front take nothing and hide what is there.
- One click-through window per screen, on every Space, with a layer per particle (sprites drawn once per season), stepped 60 times a second; resting particles are left alone. Windows are read about 12 times a second from the window list, which needs no permission. In front, the window sits just below the Dock and the menu bar; behind, just above the desktop's icons.

### Weather Widget

An optional panel to change the weather from the desktop, set up in the **Weather Widget** section of **Settings > Seasons** (**Show the weather widget**, off by default), and shown while Seasons is on. Made to look like a macOS desktop widget: 330 points wide, 22-point continuous corners, frosted glass blurring what lies behind it (masked so the glass itself is rounded). On top, the season's symbol in its colour, the season large, and under it what it is doing ("Automatic · Snowing", "Paused"), which opens a menu to pick the season; a round glass start/stop button on the right. Then **Intensity** (the same setting as Density, the system slider) and **Wind**, which settles on calm when let go near the middle, each with its value. Wind is the system slider (`NSSlider`) with only its bar redrawn: it fills from calm in the middle toward the knob, with a small mark at calm, as the wind blows either way. What it changes is saved with the Seasons settings, so it is kept when Estris quits.

- **Show season**, **Show intensity** and **Show wind** (all on by default); the start/stop button is always there. The section's other settings are dimmed while the widget is off; Reset to Defaults resets them with the rest of Seasons.
- **Sits** on the desktop (by default, behind every window, above the desktop's icons) or above windows. **Snow and the rest pile up on it** (on by default): the widget counts as one more window to Seasons, at the back or the front. Particles start upwind beyond the screen's edge when there is wind, so the screen fills evenly.
- Dragging it anywhere but its controls moves it, on every Space, always 16 points clear of the screen's edges, the menu bar and the Dock. Where it is left is remembered (not exported with the settings, as it depends on the screens). When Estris opens or the screens change, it goes back there, or to the nearest place on a screen with that room if it no longer fits; at first, the top right of the main screen. **Move Back to the Corner** puts it there.
- A borderless non-activating panel (`Widget/WeatherWidget.swift`), so using it doesn't bring Estris forward; it follows the size of its SwiftUI view as controls are shown or hidden.

## Color Picker

Picks a color anywhere on screen with a shortcut and copies it. Off by default; turn it on in **Settings > Color Picker**.

- **Shortcut** (default ⇧⌘C, which browsers also use for Inspect Element) shows a loupe by the pointer. Click picks, Esc (or a right click) cancels.
  - Without Screen Recording (the default): macOS's color sampler (`NSColorSampler`), which needs no permission; the pill below only shows once copied.
  - With Screen Recording allowed (optional, offered in the pane's Permissions section, never asked for by picking): Estris's own loupe, a magnified circle centred on the pointer with the centre pixel outlined, and under it the same pill as when copying (the color in a concentric circle and its value in the chosen format, without "Copied"), following the pointer live. A nearly clear window over each screen takes the pointer, clicks and Esc; each move captures a small square below it (`CGWindowListCreateImage`, looked up at run time since newer SDKs mark it unavailable) and reads the centre pixel in sRGB. Once picked, the pill says "Copied" and fades out.
- **Copy as**: Hex (`#FF8000`, with **Include # prefix**, on by default), RGB (`rgb(255, 128, 0)`), HSL (`hsl(30, 100%, 50%)`) or SwiftUI (`Color(red: 1.000, green: 0.502, blue: 0.000)`), in sRGB. An example shows the chosen format.
- After picking, a pill by the pointer shows the color and the copied value with "Copied", and fades out after a moment. It uses the clipboard overlay's default frosted look (always the defaults, whatever its Appearance settings): a capsule with the color in a circle at the left, concentric with its end, and the text centred to its right.
- **Recent Colors**: the last 16 colors picked, most recent first, as swatches (hover shows the value). A click copies one in the chosen format, with the same pill. **Clear** empties them; Reset to Defaults keeps them. The menu bar menu can show the first 8.

## Volume Mixer

Sets the volume and device of the Mac's sound and microphone, and of each app. Needs macOS 14.4 or later; on older versions its pane is hidden and it never starts. Off by default; turn it on in **Settings > Volume Mixer**. Everything follows changes made elsewhere (menu bar, System Settings, keyboard) live, through CoreAudio listeners. Every audio process is followed for starting and stopping output (running output, running, and its output devices: some macOS versions change the first without notifying), with bursts of notifications handled in one refresh.

Its pane has two tabs: **Mixer** (below) and **Excluded Apps**, every installed app with a switch; an excluded app is ignored entirely: never listed (in the pane or the menu bar menu) and never changed, playing as macOS plays it.

- **System**: two rows, **Output** and **Microphone**, each with an icon and its title where an app row has the app's icon and name: the device in use (sets the system default, which every app uses unless it picked its own device) at the top right, and below it a mute button, the volume across the width and its percentage, laid out like an app row. Each control is disabled when the device doesn't support it.
- **Apps**: only the apps making sound right now (helper processes, like a browser's audio process, count as their app); pausing one takes it off the list at once. Its settings stay and apply again as soon as it plays. Each has an output device (**Same as System** by default; a device that isn't connected shows "(not connected)" and the app falls back to the system output until it is), a mute button and a volume slider from 0% to 200%. The slider starts in the middle, 100%, where the app plays as it is, and snaps there when close.
- Settings are remembered per app (bundle identifier, else name), also after it quits. **Reset to Defaults** puts every app back to 100%, unmuted, on the system output.
- How: an app with changed settings gets a process tap that mutes its own output, and a private aggregate device of the tap and the chosen output plays it again scaled (clipped above full scale). Untouched apps aren't tapped. macOS asks once for **System Audio Recording** permission (Info.plist `NSAudioCaptureUsageDescription`, translated in `InfoPlist.strings`), the first time an app's sound is changed. If a tap fails, the pane names the app with **Open System Settings** and **Try Again**, and Developer > Logs says why.

## Languages

English, Spanish, French, Portuguese (Brazil), German, Italian and Catalan. **General > Language** picks one or follows the system; a change applies after relaunching, so choosing a language opens a dialog in the middle of the window: **Relaunch** now (Settings opens again on General), or **Cancel** to keep the current language. Dates follow the chosen language.

- App icon: `Resources/Icon/AppIcon.svg` (the bento box in white on a near-black squircle, on macOS's 1024 grid) is the source; `Resources/AppIcon.icns`, made from it, is what `build-app.sh` copies into the app (`CFBundleIconFile` in `Info.plist`). Change the SVG, then remake the .icns from a 1024 px render of it (for example with `iconutil` from an iconset, or Pillow).
- Translations: `Resources/Localization/<language>.lproj/Localizable.strings`, keyed by the English text (the permission prompt is in `InfoPlist.strings`); `build-app.sh` copies them into the app and `Info.plist` lists the languages.
- `scripts/check-localization.py` finds the text the app shows and reports anything missing in a language.

## Website

`web/` is the download site, built with Astro as a static site (for Vercel, with `web` as the project's root directory). Everything is centred. On a desktop it fits one screen: a top bar with the icon and the name, and a **GitHub** link on the right (with the star count once there are at least `MIN_STARS_SHOWN`, 25, asked of GitHub's API once per visit); the app icon, larger, right above the headline, and under it the main **Download for Mac** button (with a download icon, as in the footer), with lots of room around them; the features as pills with their icons, in rows as even as they can be (the narrowest list that keeps the same number of rows), the playing one tinted with its colour and filling up as its animation plays (fully filled once picked); and a large panel tinted with the playing feature's colour, with its animation, title, one-line pitch and up to three lines on how it works (when the panel is wide, at least 8:5, the animation, larger, on the left and the words on the right, centred together with the glow behind the animation). Scrolling only reveals a small footer: the download button, the macOS version needed and the copyright. The features play one after another, each for its animation's length (a short line under the playing one shows its progress), back to the first after the last, until one is picked: it then keeps replaying. Every animation ends exactly as it starts, so replaying is seamless. Keep Awake and Remap are still pictures. Rounded Corners shows a square-cornered screen filled by a light, square-cornered window, so the black corners stand out (the menu bar's items kept clear of the corners) and its switch in the middle: clicked on, the screen's corners round off in black, as round as the menu bar is tall; clicked off, they square up again. The panel spans the page's width, up to 1440 px. On narrow or short screens the page scrolls, with the features as a grid of icons (five to a row, all in view) above the panel, smaller text and a smaller top bar. Only plays while on screen; with Reduce Motion each animation shows how it ends.

- `src/data/features.ts`: the features' texts, order, animation lengths, colours and icons, and how many there are as a word (`toolCount`), which the page's description, its footer ("All twelve tools, free.") and the shared picture use.
- `src/lib/motion.ts`: the animations' motion language, after LottieFiles' motion-design skill (the "Playful" personality): fast starts with soft landings, a small overshoot when things arrive (ease-out-back), a squash and spring on every click and keypress, a pointer that travels in arcs (x and y on different curves) and holds down while dragging, and a soft light drifting over each screen. Helpers return the keyframes, so every spot moves the same way. Colours are a softer palette than the system's pure ones (`--blue`, `--pink`… in `spot.css`).
- `src/components/spots/`: one animation per feature, in HTML and CSS on a square, transparent stage (`src/styles/spot.css` holds the shared pieces: screen, windows, pointer, keycaps, labels). Each runs its keyframes once over `--d` while its root has `.playing`.
- `src/pages/spots/[id].astro`: each animation alone, for recording; `scripts/render-spots.mjs` records them as 1080 px transparent WebM into `public/spots` (and ProRes 4444 with `--mov`), for social posts or elsewhere. `--sheet` writes a few frames side by side to check one.
- `src/config.ts`: where Download points (`Estris.dmg` of this repo's latest GitHub release), the site's address, the repo and the star threshold.
- Shared links show `public/og.png` (1200 × 630: the icon, the headline and Window Snapping's animation, paused while a window is dragged to the left edge), recorded from `src/pages/og.astro` by `scripts/render-og.mjs` (`npm run render-og` after a build).

## Project structure

Estris is meant to grow into a set of macOS utilities, so code is grouped by area:

```
Sources/Estris/
  App/                    entry point, app delegate (creates the utilities, Settings window)
  MenuBar/                the menu bar item: settings, icon choices, the frosted menu and its panel
  General/                settings shared by every utility (language, date and time format)
  Settings/               the Settings window: sidebar, search, General and Menu Bar panes, the Permissions section
  Shared/                 helpers any utility can use (hotkeys, pasting, login item, app icons, device watcher, localization, relaunch, hover delays, size reader, settings export, updates)
  Utilities/
    AutoQuit/
      AutoQuit.swift           owns the utility
      Model/                   settings and the window watcher
      Settings/                the Auto Quit settings pane
    MiddleClick/
      MiddleClick.swift        owns the utility
      Model/                   settings and the tap listener
      Settings/                the Middle Click settings pane
    DeleteToTrash/
      DeleteToTrash.swift      owns the utility: key event tap, menu commands, typing check
      Model/                   settings
      Settings/                the Delete to Trash settings pane
    WindowSnapping/
      WindowSnapping.swift     owns the utility: shortcuts, snapping, restore frames
      Model/                   settings, snap actions, Accessibility windows, drag snapper, space filler, preview
      Settings/                the Window Snapping pane
    ColorPicker/
      ScreenColorPicker.swift  owns the utility (named so it doesn't hide SwiftUI's ColorPicker)
      Model/                   settings and formats, the Copied pill
      Settings/                the Color Picker pane
    VolumeMixer/
      VolumeMixer.swift        owns the utility: devices, app list, one tap engine per changed app
      Model/                   settings, CoreAudio helpers and listeners, app list, tap engine
      Settings/                the Volume Mixer pane
    FocusFollowsMouse/
      FocusFollowsMouse.swift  owns the utility: pointer monitor, speed-aware delay, raising the window under it
      Model/                   settings
      Settings/                the Focus Follows Mouse pane
    DockPreview/
      DockPreview.swift        owns the utility: event tap, open and hide timing, the panel
      Model/                   settings, Dock icons, app windows and thumbnails, the panel's view
      Settings/                the Dock Preview pane
    KeepAwake/
      KeepAwake.swift          owns the utility: power assertion and timer
      Model/                   settings, status, power source
      Settings/                the Keep Awake pane
    RoundedCorners/
      RoundedCorners.swift     owns the utility: a black corner window per screen corner
      Model/                   settings (on/off, radius)
      Settings/                the Rounded Corners pane
    Seasons/
      Seasons.swift            owns the utility: a scene per screen, the frame timer, pausing
      Model/                   settings, each season's look, the window list, the scene and its physics, drifts
      Settings/                the Seasons pane
      Widget/                  the weather widget: its panel and view, and settings
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

To add a utility: create `Utilities/<Name>/` with a class like `ClipboardManager` (a `start()`, an on/off setting and a `settingsPane()` that begins with `UtilityHeader`, then, if it needs any, a `PermissionsSection` listing them and why), create and start it in `AppDelegate`, and add a case for it to `SettingsPane` in `Settings/SettingsView.swift`, put it in a `SettingsGroup`, and report its state in `isOn(_:)`.

## Installing

Opened from the disk image or Downloads (the real location, through App Translocation's original path), Estris first asks **Move Estris to Applications?** (`App/ApplicationsMover.swift`). **Move to Applications** copies it there (an older copy goes to the Trash), clears the download quarantine, quits, opens the moved copy and ejects the disk image, which closes its window; if the copy fails, an alert says to drag it there instead. **Not Now** carries on from where it is, without adding it to the login items until it runs from elsewhere. Dragged to Applications instead, the disk image stays mounted (its icon on the desktop) until Estris opens from Applications: at each launch it ejects any read-only volume holding an Estris.app with its bundle identifier.

## Updates

Through Sparkle (`Shared/Updates.swift`): Estris reads `appcast.xml` from the latest GitHub release at launch and every 6 hours (`SUFeedURL`, `SUScheduledCheckInterval` in Info.plist; checking is on without asking). A newer version shows at the top of the menu bar menu as **Update Available**, with its version and an **Update** button, instead of Sparkle's own window (gentle scheduled update reminders). **Update**, or **Check for Updates…** in General > About, opens Sparkle's window with the release notes and **Install Update**, which downloads the disk image, checks its signature, replaces the app and opens it again. Sparkle's windows open on the screen with the pointer: until the update session ends, each new one moves there once it becomes key. Updates are signed with an EdDSA key: the public half is put in Info.plist (`SUPublicEDKey`) at build time from `SPARKLE_PUBLIC_KEY`; builds without it (local ones) don't check and hide **Check for Updates…**. `build-app.sh` copies `Sparkle.framework` into `Contents/Frameworks` and signs its helpers, the framework and then the app.

## Releases

- `CHANGELOG.md`: what changed for people using Estris. Every user-facing change adds a line under **Unreleased** in the same change.
- The **Release** workflow (`.github/workflows/release.yml`, run by hand from Actions on main, choosing patch, minor or major):
  1. `scripts/release.py` bumps `CFBundleShortVersionString` (and `CFBundleVersion` by one) in `Resources/Info.plist` and turns Unreleased into the new version's section, dated; those entries, then "Performance improvements and bug fixes." (in every release, the only line when Unreleased is empty), are the release notes.
  2. On the newest macOS runner with the latest stable Xcode (an app built with an older SDK gets the older look on new macOS), builds for Apple silicon and Intel (`RELEASE=1 scripts/build-app.sh`), signed with the Developer ID certificate from the secrets (hardened runtime, `Resources/Estris.entitlements`), packs `Estris.dmg` with a link to Applications (`scripts/make-dmg.sh`), and notarizes and staples it.
  3. Signs `Estris.dmg` for Sparkle (`sign_update` with the `SPARKLE_PRIVATE_KEY` secret) and writes `appcast.xml` (`scripts/make-appcast.py`: the version, build number, minimum macOS, the notes as HTML and the disk image's link and signature); skipped with a warning without the key.
  4. Commits "Release X.Y.Z" to main, tags it `vX.Y.Z` and creates the GitHub release with `Estris.dmg` (which the website's Download points to) and `appcast.xml` (which installed copies check).
  - `Estris.dmg` opens to a window with the app, a link to Applications and a background (`Resources/DMG/background.svg`, rendered to `background.png` and `@2x`) titled "Drag Estris to Applications", with an arrow between them and the line "Then open Estris from Applications. This window closes by itself." Laid out by `dmgbuild` (`scripts/dmg-settings.py`).
  - Without the signing secrets it still releases, signed ad hoc and not notarized, with a warning; macOS then makes people allow the app by hand. Secrets: `DEVELOPER_ID_CERTIFICATE` (base64 .p12), `DEVELOPER_ID_CERTIFICATE_PASSWORD`, `APPLE_ID`, `APPLE_APP_PASSWORD`, `APPLE_TEAM_ID`.

## Notes

The app needs Accessibility. Builds are signed with an Apple Development certificate (see README.md) so the permission survives rebuilds. An ad-hoc signature changes every build and macOS then forgets it; a self-signed certificate was tried and macOS still kept asking.


`⌘⇧V` is also "Paste and Match Style" in some apps. Estris takes over that shortcut while running.
