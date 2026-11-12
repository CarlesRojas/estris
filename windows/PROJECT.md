# Estris for Windows: project context

A native Windows app with a set of utilities: Clipboard, Color Picker, Rounded Corners, Window Snapping, Hot Corners and Remap. `PROJECT.md` at the root of the repo says why the Mac's other utilities stay out, and why Hot Corners is only here. For building and running, see `README.md` there.

The Mac app is the reference: `macos/PROJECT.md` describes how each utility behaves, and this file only says what is different here, plus how this app is built. ⌘ on the Mac is Ctrl here. Window Snapping's ⌃⌥ is Win+Alt.

It is written in C# on .NET 10 with WinUI 3 (Windows App SDK), unpackaged and self-contained: the installer carries .NET and WinUI, so there is nothing to install first. It runs on Windows 10 2004 or later; Mica needs Windows 11.

## Look

It should look like a Windows 11 app, not a Mac port: the Settings window is laid out as Windows's own Settings (Mica drawn into the title bar, a navigation list with search, cards), with Segoe UI, Segoe Fluent Icons and the system accent colour, in the system's light or dark theme. Everything floating that doesn't take the focus (the Clipboard's card, the color pill, Window Snapping's preview) is the same glass, Windows's own Snap preview measured (`GlassLook`): the system compositor's blur in a plain window, which allows any corner radius and no border. In `Ui/GlassPanel.cs`, the content sits on it in a see-through XAML window. The tray menu, which takes the focus, is real Acrylic (`Ui/FrostWindow.cs`); `FrostBackdrop` keeps the frost on when the window has no focus, which the stock backdrop doesn't. The icon is always the real one, `macos/Resources/Icon/AppIcon.svg`: `scripts/make-icon.py` reads the icon file's shapes and colours from it, keeping the squircle without the room macOS leaves around icons, and the app's own pages draw the same numbers as one vector shape (`Ui/AppLogo.cs`), as WinUI scales pictures down roughly and puts separate shapes' edges a fraction of a pixel apart. The tray draws the bento at the exact size the taskbar shows it, with every edge on a whole pixel, so the shell scales nothing.

## System tray

The tray icon is Estris's place on Windows, as the menu bar is on the Mac: closing Settings leaves it running there, and only **Quit** in the tray menu ends it. Either click opens the menu, frosted, in the corner where Quick Settings opens, with an update when one is out, each utility's group while it is on, then **Settings** and **Quit**.

Windows 11 hides a new tray icon by default and remembers it by program path, so Estris asks to be shown on the taskbar at launch (`Tray/TrayPromotion.cs`), and respects it if you hide it again.

**System Tray** in Settings picks the icon (Estris's bento, drawn in code, then glyphs from Windows's icon font), **Custom color** (otherwise white or black to suit the taskbar), and what the menu shows of the Clipboard and the Color Picker.

## Settings

As on the Mac: **General**, **System Tray** (and **Developer**, unlocked by clicking the version in About six times), then the utilities in groups, each showing On (in the accent colour) or Off. Every row has its right-click **Reset to Default** (`Ui/Pane.cs`), and each pane but General, Remap and Developer ends with **Reset to Defaults**. There are no Permissions sections: Windows has no such thing. What it does have is that a program can't touch windows or see keys of an elevated one while it isn't elevated itself, so those are left alone.

Settings are one JSON file, `%APPDATA%\Estris\settings.json`, kept there because an update replaces the app's own folder. **Export Settings…** writes it to a file, leaving out keys starting with `local.` (what is tied to this PC). The clipboard history is next to them, in `history`. Nothing goes in `%LOCALAPPDATA%\Estris`: that is where the app is installed, so its installer would take the app as installed already, and uninstalling would delete it. **Open at login** is the current user's Run key; only an installed copy turns it on by itself, at its first launch, so a development build doesn't add itself. Opened at login, it starts in the tray without opening Settings.

## Clipboard

As on the Mac, with these differences:

- The overlay has one style, **Default**: the Mac's Grid, Carousel, Stack and Ring menu aren't here.
- The shortcut is Ctrl+Shift+V. Windows keeps Ctrl+Shift+Esc for the Task Manager, so Esc while holding the keys closes the overlay without pasting.
- The overlay is live, with no picture of the screen: **Dim screen** is a plain click-through window of black at a set transparency, and the card and the "2 of 12" are `GlassPanel`s over it, so a video behind keeps playing, dimmed and blurred. There's no **Shadow** setting, as glass brings its own, and with one style nothing to select, so no **Selected highlight**. **Tint strength** adds to the glass and starts at none.
- **Ignore passwords** skips copies carrying the formats password managers set to stay out of clipboard history (`ExcludeClipboardContentFromMonitorProcessing`, `CanIncludeInClipboardHistory`, `Clipboard Viewer Ignore`).

## Color Picker

As on the Mac, with Estris's own loupe for everyone (it needs no permission here). **Copy as** has C# (`Color.FromArgb(255, 255, 128, 0)`) where the Mac has SwiftUI.

## Rounded Corners

As on the Mac. The radius defaults to 8, Windows 11's window corners, so a maximized window fits them. The corners are plain click-through Win32 layered windows, not WinUI, so they weigh nothing, kept above the taskbar and left out of screenshots.

## Window Snapping

As on the Mac, with Win+Alt for the shortcuts, on the Mac's keys. Windows and Game Bar use many Win+Alt combinations (the arrows, D, F, G, K, R and T among the defaults); as the keyboard hook comes first, Estris gets them, and each row says when a key is taken, by trying to register it. A key nothing uses is tapped after each shortcut, or Windows would open Start on letting go of Win. Windows's own Snap should be off (Settings > System > Multitasking), and the pane says so with a link. Frames are the visible ones (`DWMWA_EXTENDED_FRAME_BOUNDS`, not the window's invisible resize borders), so snapped windows truly touch each other and the screen's edges. Cloaked, tool and always-on-top windows are left out.

The preview is one style, not two: frosted like Windows's own Snap preview, with no border. The Mac's dark outline and its **Frosted preview** switch aren't here. Holding Ctrl while dragging previews and snaps the exact area, as ⌘ does on the Mac.

The preview matches Windows 11's own, measured from it: the system's blurred backdrop under a grey tint (light or dark with the system theme, solid with transparency effects off), 8 px rounded corners, a soft shadow, 8 px in from the screen's edges. It is drawn by the system compositor in a click-through window per screen, just behind the dragged window, so it grows out of the window, glides between areas and shrinks back into it in step with the display; Animation effects off makes it instant. The window landing in its area isn't animated: another app's window can only be moved by asking that app to lay itself out again for every frame, which takes it 6 to 13 ms a step and shows its content lagging behind its frame.

The drag is followed from the dragged window's own move events (as PowerToys' FancyZones does), with a timer for the pointer moving while the window can't; a drag that starts with a resize arrow is a resize. Windows of apps run as administrator are left alone, as Windows doesn't let Estris move them. A window moved to a screen with another scale is sized a second time, after it has resized itself for the new scale.

## Hot Corners

Only on Windows: the Mac has it in System Settings. Behaves as the Mac's: pushing the pointer into a corner of a screen runs the action chosen for that corner, at once, and pushing it again undoes it, as every action toggles (Show Desktop is Win+D, Task View Win+Tab). Any action goes in any corner: Nothing, Show Desktop, Task View, Start Menu, Search, Notification Center (Win+N), Quick Settings (Win+A), Widgets (Win+W), Sleep Display and Lock Screen, the ones shared with Remap run through its `SystemActions`. By default the top-right corner opens Task View and the bottom-right one shows the desktop.

- The pointer is followed from the shared mouse hook (only while on with something in a corner); the hook can report it past the edge it is pushed against, so the point is moved onto the nearest screen first. A corner counts within 1 px, and only where the pointer stops: a corner with another screen past either of its edges doesn't. Screens are listed again every 2 seconds, from the pointer's moves.
- After firing, a corner fires again only once the pointer has gone 24 logical px away, so a nudge doesn't undo it.
- Nothing happens while a mouse button is held, so dragging a window into a corner (Window Snapping) doesn't trigger it.
- **Delay** (none by default, up to 1 s): the pointer must rest in the corner that long; leaving earlier cancels. It's there for the top-right corner, where a maximized window's close button is.
- **Off in full-screen apps** (on by default): `SHQueryUserNotificationState` says a full-screen app or presentation is in front. The shell's own full-screen windows (the desktop, Task View, Start, Search) don't count, so a second push still undoes them.
- The actions are keys sent with `SendInput`, which Windows blocks while a window running as administrator is in front.

## Remap

As on the Mac (a group of mappings per device with rename, Add Mapping, source and result pickers with Record, swap, "Already mapped above", the Event Viewer), with a very different engine, since Windows has no per-device key mapping: the low-level hook can swallow input but doesn't say which device sent it, and Raw Input (on a thread of its own, with a message-only window) says the device but can't swallow anything. `Utilities/Remap/Model/RemapEngine.cs` matches the two up; it has no Windows calls and takes the clock as a function, so it can be tested.

- Windows doesn't say what a device is, and receivers offer both a keyboard and a pointer. A device counts as a keyboard from its first interface (`MI_00`), and the icon next to its name changes that (`remapDeviceKinds`). The kind picks the icon, what the pickers list first and whether it counts among the keyboards below.
- Mouse buttons reach Raw Input before the hook, even when swallowed. A button with a mapping on any device waits in the hook for its Raw Input event (or takes one that came first); then that device's mapping applies, or the original is sent again. After 25 ms with none, it goes as if it had no device.
- Keys reach Raw Input only after the hook, and only if nothing swallowed them, so a key can't wait for its device. When every device that may have sent it does the same with it, it doesn't matter (always the case with one keyboard). Otherwise it goes by what Raw Input said before: the keyboard being typed on (in the last 1.5 s), unless only another kind of device, such as a mouse sending keys, has sent that key; with nobody typing, the devices that have sent it. A guessed key lets its release through, so Raw Input says the device for next time; with no guess the key waits for its release, or 200 ms held. Receivers look like mice, so a device that has sent 8 different keys counts as a keyboard too. With more than one device that can send keys, Mappings says this in a note.
- Keys and buttons with no mapping anywhere aren't touched or delayed. A key or button goes up the way it went down, even if mappings changed meanwhile; turning Remap off, quitting, locking or sleeping lets go of everything held.
- Raw Input also checks the hook: when it sees a key or button the hook never did (Windows can stop calling a hook, or another program's hook can keep events from it), the hooks are installed again, at most every 3 seconds. The first missed one goes through unmapped.
- While a process in front listens to Raw Input, Windows gives it the keys and skips its low-level hooks, whatever the flags. So Estris stops listening while one of its windows is in front, and shortcuts and mappings keep working in them. The Event Viewer and Record need the device, so they keep listening: there, Raw Input alone logs or records the key, which can't be swallowed or mapped.
- Win and Alt as sources: when a release goes on alone, a key no layout uses is tapped first, so Start and the menu bar stay shut. On AltGr layouts, the Ctrl Windows sends before Right Alt is held back while Right Alt has a mapping, and given back to a Right Alt that goes on unmapped.
- A press sent by another program has no device and takes the device-less mappings; recording one makes a device-less mapping, as on the Mac. The Event Viewer shows it as "Posted by another app" (Windows doesn't say which).
- Results: another key (by scan code, with the virtual key of the layout in use), a mouse button, nothing, or a system action: Task View, Show Desktop, Start Menu (for the Mac's Launchpad), next or previous desktop, volume, mute, media, display brightness (WMI for built-in screens, DDC/CI for monitors; the row says when no display supports it), sleep display, lock screen, Search, Screenshot Tools (Win+Shift+S), Screenshot of Screen (Win+Print Screen), Emoji and Symbols (Win+.) and Task Manager. There's no App Windows or keyboard brightness: Windows has neither.
- Devices come from `GetRawInputDeviceList` with the HID vendor, product, maker and product name (Device Manager's name for those that give none); every interface of a device counts as it. Identified by vendor, product and name, so mappings survive reconnects and identical devices share them. Listed again when one connects or disconnects, 5 and 20 seconds after Remap starts listening, and when a press comes from an interface not listed yet (at most every 2 seconds).
- Event Viewer: Down and Up rows with the name, the scan code and virtual key (or button number) and the device; a remapped one shows an arrow and the result in the accent colour. Hovering a row shows Create Mapping. It follows new events unless scrolled up, and logs only while open.
- Keys and buttons can't be remapped while a window running as administrator is in front (Windows keeps its input from other programs); the pane says so.

## Updates

Through Velopack (`Core/AppServices.cs`, `Ui/UpdateWindow.cs`), reading the rolling `windows-latest` release at launch and every 6 hours. A newer version shows at the top of the tray menu and in General > About, under the version, with **Update**; that, or **Check for Updates…** in General > About, opens a window with the release notes and **Install Update**, as Sparkle's on the Mac. Development builds don't check.

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

Input hook handlers (`Core/InputHooks.cs`) run on one shared thread and must be quick: Windows silently drops a hook that takes too long. Every 3 seconds the hooks check against Windows's last input time and reinstall themselves if input went past them, so no utility stays deaf; a utility that notices (Remap does, through Raw Input) can ask for it with `InputHooks.RequestReinstall`. None of this applies while Estris is in front and listening to Raw Input, where the hooks are skipped on purpose (see Remap).

## Releases

**Release Windows** (`.github/workflows/release-windows.yml`, run by hand from Actions on main, choosing patch, minor or major):

1. `scripts/release.py` bumps `<Version>` in `Estris.csproj` and turns `CHANGELOG.md`'s Unreleased into the new version's section; those entries are the release notes.
2. `scripts/make-installer.sh` publishes for x64 and ARM64 and packs each with Velopack into `Estris-win-Setup.exe`, `Estris-win-arm64-Setup.exe` and what installed copies read to update.
3. Commits "Release Windows X.Y.Z", tags it `windows-vX.Y.Z` and creates that release, then replaces the files on the rolling `windows-latest` release. Neither is ever marked as the repo's latest: that one belongs to the Mac's updates and download button.

Installers are signed only with the `WINDOWS_CERTIFICATE` (base64 .pfx) and `WINDOWS_CERTIFICATE_PASSWORD` secrets; without them it still releases, and SmartScreen warns when opening the installer.
