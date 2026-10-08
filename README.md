# PasteRing

A native macOS menu bar app that keeps a history of copied text and lets you pick which one to paste.

## Usage

- Copy text as usual. PasteRing records every new text entry, most recent first, along with the app it was copied from (shown as its icon).
- Hold `⌘⇧` and press `V` to open the overlay in the middle of the screen. The highlighted entry is what will be pasted.
- Keep holding `⌘⇧` and press `V`, the arrow keys (`↑`/`←` previous, `↓`/`→` next), or scroll to move through entries.
- Release `⌘` or `⇧` to paste the selected entry into the frontmost app.
- `⌘⇧Esc` closes the overlay without pasting.

## Settings

Open **Settings…** from the menu bar icon to choose:

- **Style**:
  - *Stack*: vertical list, selected entry in the middle.
  - *Ring menu*: the most recent entries (3 to 12, default 8) spread around a circle that turns to bring the selected one to the top.
  - *Carousel*: Cover Flow style, neighbours tilted away on either side.
  - *Simple*: one rectangle with the entry that will be pasted; cycling only swaps the text.
  - *Grid*: pages of 12 tiles, the page follows the selection.
- **Glass**: *Frosted* or *Clear*. Uses Liquid Glass on macOS 26 and blur materials on earlier versions.
- **History size**: how many entries to keep (5 to 500, default 50).
- **Open at login**: on by default, so PasteRing is running after a restart.

The **History** tab lists every saved entry. The trash button deletes one, **Clear All** deletes everything.

Entries marked as concealed or transient (password managers) are ignored. History is saved to `~/Library/Application Support/PasteRing/history.json` (readable by your user only), so it survives quitting and restarting the Mac.

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
