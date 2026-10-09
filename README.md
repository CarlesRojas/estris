# PasteRing

A native macOS menu bar app that keeps a history of copied text and lets you pick which one to paste.

## Usage

- Copy text as usual. PasteRing records every new text entry, most recent first, along with the app it was copied from (shown as its icon).
- Hold `⌘⇧` and press `V` to open the overlay in the middle of the screen. The highlighted entry is what will be pasted.
- Keep holding `⌘⇧` and press `V`, the arrow keys (`↑`/`←` previous, `↓`/`→` next), or scroll to move through entries.
- Release `⌘` or `⇧` to paste the selected entry into the frontmost app.
- `⌘⇧Esc` closes the overlay without pasting. `⌘⇧Delete` removes the selected entry from the history.
- While holding `⌘⇧`, click any entry to paste it, click its trash icon to delete it, or click outside to close. Releasing always pastes the selected entry, not the one under the mouse.

## Settings

Open **Settings…** from the menu bar icon.

**General**
- **History size**: how many entries to keep (5 to 500, default 50).
- **Open at login**: on by default, so PasteRing is running after a restart.
- **Accessibility**: shows whether the permission is granted, with a link to its page in System Settings.

**Appearance** (with a live preview over your wallpaper)
- **Style**:
  - *Default*: one card with the source app and the entry that will be pasted; cycling only swaps the content. Width and height are adjustable.
  - *Grid*: the most recent 8 to 24 entries (default 12) as tiles, all on screen at once. Tile width is adjustable (default 256).
  - *Carousel*: Cover Flow style, neighbours tilted away on either side. Card width and height are adjustable (default 260 by 260).
  - *Stack*: a pile of cards like the Default one; the next few peek out above the front card, smaller the further back. Cycling drops the front card down behind the pile and brings the next one forward.
  - *Ring menu*: the most recent entries (3 to 12, default 8) spread around a circle that turns to bring the selected one to the top.
- Surfaces use the system's frosted material.
- **Tint** (default mid grey), **Tint strength** (20%), **Selected highlight** (30%), **Shadow** (16), **Dim screen** (0%, fades in and out with the overlay).
- **Reset to Defaults** resets everything in this tab, including the style and its options.

**History** lists every saved entry. The trash button deletes one, **Clear All** deletes everything.

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

## Notes

`⌘⇧V` is also "Paste and Match Style" in some apps. PasteRing takes over that shortcut while running.
