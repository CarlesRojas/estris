# Changelog

## Unreleased

- Clipboard keeps text plain: it is recorded, shown and pasted without its styling, so the **Paste as plain text** setting is gone. This also fixes Estris freezing for up to half a minute when it opens, while the history held text copied from some web pages.

## 0.1.13 - 2026-10-19

- Focus Follows Mouse also keeps new windows and popups in front for a moment (like a browser's screen sharing picker), so they no longer go behind as soon as you move the pointer. The time it keeps them in front now defaults to 2 seconds instead of 5.
- Auto Quit no longer quits apps that close a window to open another, like Android Studio after you pick a project. When an app closes its last window on its own, it gets 10 seconds to open a new one.
- Performance improvements and bug fixes.

## 0.1.12 - 2026-10-17

- Auto Quit now quits Safari when you close its last window.
- Performance improvements and bug fixes.

## 0.1.11 - 2026-10-15

- New utility, Rounded Corners: paints the corners of your screens black so they look rounded, as round as macOS windows by default, with a slider to change it. Off by default.
- Performance improvements and bug fixes.

## 0.1.10 - 2026-10-14

- Window Snapping can show the drag preview frosted instead of dark: turn on **Frosted preview** in its Dragging settings. The preview now also stays behind the window you're dragging.
- Performance improvements and bug fixes.

## 0.1.9 - 2026-10-12

- Focus Follows Mouse also keeps an app in front for a few seconds after you switch to it (clicking it, ⌘Tab, Mission Control), not only after it opens. The setting is now **Keep apps you open or switch to in front**.
- Performance improvements and bug fixes.

## 0.1.8 - 2026-10-12

- Focus Follows Mouse leaves the app in front alone while it has a panel or dialog open, so passing over the windows behind it no longer hides the panel.
- Performance improvements and bug fixes.

## 0.1.7 - 2026-10-12

- Remap: keyboards that reconnect while Estris is running, such as Bluetooth keyboards after starting the Mac, are recognized again, so their mappings keep working.
- Performance improvements and bug fixes.

## 0.1.6 - 2026-10-12

- Remap: wireless keyboards that showed as an unknown device after starting the Mac, with their mappings not working until turned off and on, are now recognized.
- Performance improvements and bug fixes.

## 0.1.5 - 2026-10-11

- Dock Preview shows window previews faster, especially when the Mac is busy.
- Performance improvements and bug fixes.

## 0.1.4 - 2026-10-11

- Performance improvements and bug fixes.

## 0.1.3 - 2026-10-11

- The menu bar menu no longer shows recent colors unless turned on in Settings > Menu Bar.

## 0.1.2 - 2026-10-11

- Updates: when a new version is out, the menu bar menu shows **Update Available** with a button that installs it. **Check for Updates…** is in General.
- Settings look as they should on the latest macOS: releases are built with the newest Xcode.

## 0.1.1 - 2026-10-11

- **Export & Import** in General: save all your settings to a file and load them again, on this Mac or another.
- The disk image shows how to install Estris: drag it to Applications. Opened from the disk image, Estris offers to move itself there, opens again from Applications and ejects the disk image.
- Every utility starts off, and nothing asks for a permission until you turn on one that needs it.
- Opening Estris (from Applications, also while it's running) shows Settings.
- Once Accessibility is allowed, Estris opens again by itself so every utility can use it.

## 0.1.0 - 2026-10-11

- First release, with ten utilities in the menu bar:
  - **Clipboard**: a history of what you copy, to pick from when pasting.
  - **Window Snapping**: drag windows to edges or use shortcuts; one shortcut arranges every window on the screen.
  - **Focus Follows Mouse**: the window under the pointer comes to the front.
  - **Dock Preview**: hover an app in the Dock to see its windows.
  - **Volume Mixer**: a volume and output device for each app.
  - **Color Picker**: pick any color on screen and copy it.
  - **Remap**: change what keys and mouse buttons do, per device.
  - **Middle Click**: a three-finger tap as a middle click.
  - **Keep Awake**: keep the Mac from sleeping.
  - **Auto Quit**: quit apps when their last window closes.
