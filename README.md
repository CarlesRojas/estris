# PasteRing

A native macOS menu bar app that keeps a history of copied text and lets you pick which one to paste.

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
- **Language** (English for now), **Date format** (Oct 9, 9 Oct, 10/9 or 9/10; never the year) and **Time format** (system setting, 24-hour or 12-hour).
- **Open at login**: on by default, so PasteRing is running after a restart.
- **About**: app icon, name and version.

**Clipboard** starts with its on/off switch (off stops recording and frees its shortcuts), then three tabs:
- **Settings**:
  - *General*: how many entries to keep (5 to 500, default 50), when to delete old entries (never by default, or after an hour, a day, a week or 30 days), and these switches:
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
      - *Ring menu*: the most recent entries (3 to 12, default 12) as cards laid out like grid tiles, spread around a ring (an ellipse as tight as the cards allow) that turns to bring the selected one to the top. Card width and height are adjustable (default 280 by 256); if the ring is bigger than the screen it is scaled down to fit.
    - **Show when entries were copied** and **Show delete button** (the History tab always has them).
    - Frosted material with **Tint** (default mid grey), **Tint strength** (20%), **Selected highlight** (30%), **Shadow** (16) and **Dim screen** (50%, fades in and out with the overlay). **Reset Appearance to Defaults** resets everything in this section.
  - *Shortcuts*: the shortcut that opens the overlay (default `⌘⇧V`) and any alternatives. Click one and press a new combination; it needs `⌘`, `⌥` or `⌃`.
- **History**: every saved entry with where and when it was copied, with a search field. The trash button deletes one, **Clear All** deletes everything.
- **Excluded Apps**: every installed app with a switch, all on. Switch an app off and nothing copied in it is recorded.

Every entry in the overlay shows when it was copied next to its trash icon, in the date and time format chosen in General.

## Build

Requires macOS 13+ and the Swift toolchain (Xcode or Command Line Tools).

```sh
./scripts/build-app.sh
open build/PasteRing.app
```

Reinstall (quit the running app, reset its Accessibility permission, rebuild, open):

```sh
pkill -x PasteRing; tccutil reset Accessibility com.carlesrojas.PasteRing; rm -rf build/PasteRing.app && ./scripts/build-app.sh && open build/PasteRing.app
```

Resetting the permission avoids a stale entry: after an ad-hoc rebuild, System Settings can show PasteRing as allowed while macOS ignores it. You will be asked to grant it again on launch.

On first launch macOS asks for **Accessibility** access (System Settings > Privacy & Security > Accessibility). It is needed to send `⌘V` to the frontmost app. Without it the selected entry is still placed on the clipboard.

The build is ad-hoc signed by default, so macOS may forget the permission after a rebuild. Remove and re-add the app in the Accessibility list, or sign with a stable identity:

```sh
SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/build-app.sh
```

## Project structure

PasteRing is meant to grow into a set of macOS utilities, so code is grouped by area:

```
Sources/PasteRing/
  App/                    entry point, app delegate (menu bar item, Settings window)
  General/                settings shared by every utility (language, date and time format)
  Settings/               the Settings window: sidebar, search, General pane
  Shared/                 helpers any utility can use (hotkeys, pasting, login item, app icons)
  Utilities/
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

`⌘⇧V` is also "Paste and Match Style" in some apps. PasteRing takes over that shortcut while running.
