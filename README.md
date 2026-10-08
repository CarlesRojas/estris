# Paste Ring

A native macOS menu bar app that keeps a history of copied text and lets you pick which one to paste.

## Usage

- Copy text as usual. Paste Ring records every new text entry, most recent first.
- Hold `⌘⇧` and press `V` to open the overlay in the middle of the screen. The highlighted entry is what will be pasted.
- Keep holding `⌘⇧` and press `V`, the arrow keys (`↑`/`←` previous, `↓`/`→` next), or scroll to move through entries.
- Release `⌘` or `⇧` to paste the selected entry into the frontmost app.
- `⌘⇧Esc` closes the overlay without pasting.

## Settings

Open **Settings…** from the menu bar icon to choose:

- **Style**: *Stack* (vertical list, selected entry in the middle) or *Ring menu* (entries on a rotating circle, selected one at the top, full text in the centre).
- **History size**: how many entries to keep (5 to 500, default 50).

Entries marked as concealed or transient (password managers) are ignored. History lives in memory only.

## Build

Requires macOS 13+ and the Swift toolchain (Xcode or Command Line Tools).

```sh
./scripts/build-app.sh
open build/PasteRing.app
```

On first launch macOS asks for **Accessibility** access (System Settings > Privacy & Security > Accessibility). It is needed to send `⌘V` to the frontmost app. Without it the selected entry is still placed on the clipboard.

The build is ad-hoc signed by default, so macOS may forget the permission after a rebuild. Remove and re-add the app in the Accessibility list, or sign with a stable identity:

```sh
SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/build-app.sh
```

## Notes

`⌘⇧V` is also "Paste and Match Style" in some apps. Paste Ring takes over that shortcut while running.
