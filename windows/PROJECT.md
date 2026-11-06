# Estris for Windows: project context

A native Windows app with a set of utilities: Clipboard, Color Picker, Rounded Corners, Window Snapping and Remap. `PROJECT.md` at the root of the repo says why the Mac's other utilities stay out. For building and running, see `README.md` there.

The Mac app is the reference: `macos/PROJECT.md` describes how each utility behaves, and this file only says what is different here, plus how this app is built. ⌘ on the Mac is Ctrl here, ⌃⌥ is Ctrl+Alt.

It is written in C# on .NET 10 with WinUI 3 (Windows App SDK), unpackaged and self-contained: the installer carries .NET and WinUI, so there is nothing to install first. It runs on Windows 10 2004 or later; Mica needs Windows 11.

## Look

It should look like a Windows 11 app, not a Mac port: the Settings window is laid out as Windows's own Settings (Mica drawn into the title bar, a navigation list with search, cards), with Segoe UI, Segoe Fluent Icons and the system accent colour, in the system's light or dark theme. The tray menu and floating pills are real Acrylic (`Ui/FrostWindow.cs`); `FrostBackdrop` keeps the frost on when the window has no focus, which the stock backdrop doesn't. The icon is the Mac's bento on its dark grey gradient, as a Windows tile (`scripts/make-icon.py`).

## System tray

The tray icon is Estris's place on Windows, as the menu bar is on the Mac: closing Settings leaves it running there, and only **Quit** in the tray menu ends it. Either click opens the menu, frosted, in the corner where Quick Settings opens, with an update when one is out, each utility's group while it is on, then **Settings** and **Quit**.

Windows 11 hides a new tray icon by default and remembers it by program path, so Estris asks to be shown on the taskbar at launch (`Tray/TrayPromotion.cs`), and respects it if you hide it again.

**System Tray** in Settings picks the icon (Estris's bento, drawn in code, then glyphs from Windows's icon font), **Custom color** (otherwise white or black to suit the taskbar), and what the menu shows of the Clipboard and the Color Picker.

## Settings

As on the Mac: **General**, **System Tray** (and **Developer**, unlocked by clicking the version in About six times), then the utilities in groups, each showing On (in the accent colour) or Off. Every row has its right-click **Reset to Default** (`Ui/Pane.cs`), and each pane but General, Remap and Developer ends with **Reset to Defaults**. There are no Permissions sections: Windows has no such thing. What it does have is that a program can't touch windows or see keys of an elevated one while it isn't elevated itself, so those are left alone.

Settings are one JSON file, `%APPDATA%\Estris\settings.json`, kept there because an update replaces the app's own folder. **Export Settings…** writes it to a file, leaving out keys starting with `local.` (what is tied to this PC). The clipboard history is in `%LOCALAPPDATA%\Estris\history`. **Open at login** is the current user's Run key; only an installed copy turns it on by itself, at its first launch, so a development build doesn't add itself. Opened at login, it starts in the tray without opening Settings.

## Clipboard

As on the Mac, with these differences:

- The overlay has one style, **Default**: the Mac's Grid, Carousel, Stack and Ring menu aren't here.
- The shortcut is Ctrl+Shift+V. Windows keeps Ctrl+Shift+Esc for the Task Manager, so Esc while holding the keys closes the overlay without pasting.
- The overlay is one full-screen window over a picture of the screen taken as it opens: that picture, dimmed and blurred behind each card, gives real frost wherever the card is.
- **Ignore passwords** skips copies carrying the formats password managers set to stay out of clipboard history (`ExcludeClipboardContentFromMonitorProcessing`, `CanIncludeInClipboardHistory`, `Clipboard Viewer Ignore`).

## Color Picker

As on the Mac, with Estris's own loupe for everyone (it needs no permission here). **Copy as** has C# (`Color.FromArgb(255, 255, 128, 0)`) where the Mac has SwiftUI.

## Rounded Corners

As on the Mac. The radius defaults to 8, Windows 11's window corners, so a maximized window fits them. The corners are plain click-through Win32 layered windows, not WinUI, so they weigh nothing, kept above the taskbar and left out of screenshots.

## Window Snapping

As on the Mac, with Ctrl+Alt for the shortcuts. Windows's own Snap should be off (Settings > System > Multitasking), and the pane says so with a link. Frames are the visible ones (`DWMWA_EXTENDED_FRAME_BOUNDS`, not the window's invisible resize borders), so snapped windows truly touch each other and the screen's edges. Cloaked, tool and always-on-top windows are left out.

The preview is one style, not two: frosted like Windows's own Snap preview, with no border. The Mac's dark outline and its **Frosted preview** switch aren't here. Holding Ctrl while dragging previews and snaps the exact area, as ⌘ does on the Mac.

## Remap

As on the Mac, with a very different engine, since Windows has no per-device key mapping: a low-level hook can swallow input but doesn't say which device sent it, and Raw Input says the device but can't swallow anything. So the two are matched up (`Utilities/Remap/`): a key or button with a mapping on any device is held back in the hook until its Raw Input event tells which device it came from, then that device's mapping applies, or it is sent on unchanged if that device has none. Input with no mapping anywhere isn't touched or delayed.

## Updates

Through Velopack (`Core/AppServices.cs`, `Ui/UpdateWindow.cs`), reading the rolling `windows-latest` release at launch and every 6 hours. A newer version shows at the top of the tray menu with **Update**; that, or **Check for Updates…** in General > About, opens a window with the release notes and **Install Update**, as Sparkle's on the Mac. Development builds don't check.

## Project structure

```
windows/
  src/Estris/
    Program.cs               starts the app: Velopack first, then one copy only
    App.xaml.cs              creates the utilities, the tray and the Settings window
    Core/                    settings, translations, logs, input hooks, sending input, shortcuts, services
    Ui/                      the Settings window, its page builder, frosted windows, shared controls, the update window
      Panes/                 General, System Tray, Developer
    Tray/                    the tray icon, its pictures, its menu and settings
    Utilities/
      Utility.cs             IUtility and the list of utilities
      <Name>/                one folder per utility
    Localization/<language>/ translations, one .strings file per area
    Assets/                  the icon
  scripts/                   build, installers, release, localization check, icon
```

To add a utility: a folder in `Utilities/` with a class implementing `IUtility`, added to `UtilityList`, with its pane in `BuildPane` and, if it shows in the tray menu, `BuildTrayGroup`.

Input hook handlers (`Core/InputHooks.cs`) run on one shared thread and must be quick: Windows silently drops a hook that takes too long.

## Releases

**Release Windows** (`.github/workflows/release-windows.yml`, run by hand from Actions on main, choosing patch, minor or major):

1. `scripts/release.py` bumps `<Version>` in `Estris.csproj` and turns `CHANGELOG.md`'s Unreleased into the new version's section; those entries are the release notes.
2. `scripts/make-installer.sh` publishes for x64 and ARM64 and packs each with Velopack into `Estris-win-Setup.exe`, `Estris-win-arm64-Setup.exe` and what installed copies read to update.
3. Commits "Release Windows X.Y.Z", tags it `windows-vX.Y.Z` and creates that release, then replaces the files on the rolling `windows-latest` release. Neither is ever marked as the repo's latest: that one belongs to the Mac's updates and download button.

Installers are signed only with the `WINDOWS_CERTIFICATE` (base64 .pfx) and `WINDOWS_CERTIFICATE_PASSWORD` secrets; without them it still releases, and SmartScreen warns when opening the installer.
