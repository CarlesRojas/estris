# Estris: project context

Estris is a set of small utilities in one app, for Mac and Windows. Each app is native and has its own code: there is nothing shared to build, but they are one product, so a feature, change or fix goes into both.

- `macos/`: the Mac app, in Swift. Its features, settings and structure are in `macos/PROJECT.md`.
- `windows/`: the Windows app, in C# with WinUI 3. Same: `windows/PROJECT.md`.
- `web/`: the download site, below.

The Mac app is the reference for how a utility behaves. The Windows one matches it, in Windows's own look: it shouldn't look like a Mac app.

## What each app has

| Utility | Mac | Windows |
| --- | --- | --- |
| Clipboard | yes | yes |
| Color Picker | yes | yes |
| Volume Mixer | yes | yes, per-app volume up to 100% (more needs an audio driver) |
| Keep Awake | yes | yes |
| Rounded Corners | yes | yes |
| Window Snapping | yes | yes |
| Focus Follows Mouse | yes | yes |
| Auto Quit | yes | yes |
| Remap | yes | yes |
| Dock Preview | yes | no: the taskbar already shows previews |
| Middle Click | yes | no: three-finger tap is a Windows setting |
| Delete to Trash | yes | no: Delete already works this way |

Only what makes sense on a platform goes in: what the system already does well, or what can't really be done there, stays out, and this table says so.

## Releases

Each app releases on its own, from Actions, with its own version and changelog: **Release macOS** and **Release Windows**. GitHub's "latest release" belongs to the Mac app, whose updates and download button read it, so Windows releases are never marked as latest; installed Windows copies and the website read the rolling `windows-latest` release instead.

## Website

`web/` is the download site, built with Astro as a static site (for Vercel, with `web` as the project's root directory). Everything is centred. On a desktop it fits one screen: a top bar with the icon and the name, and a **GitHub** link on the right (with the star count once there are at least `MIN_STARS_SHOWN`, 25, asked of GitHub's API once per visit); the app icon, larger, right above the headline, and under it **Download for Mac** and **Download for Windows** side by side (with a download icon, as in the footer), with lots of room around them; the visitor's own system goes first and solid, the other is quieter; the features as pills with their icons, in rows as even as they can be (the narrowest list that keeps the same number of rows), the playing one tinted with its colour and filling up as its animation plays (fully filled once picked); and a large panel tinted with the playing feature's colour, with its animation, title, one-line pitch and up to three lines on how it works (when the panel is wide, at least 8:5, the animation, larger, on the left and the words on the right, centred together with the glow behind the animation). Scrolling only reveals a small footer: the download buttons, the system versions needed and the copyright. Visitors on Windows (`data-os` on the page, set before it paints) get the wording of `windowsTagline` and `windowsDetails`; features Windows has built in (`macOnly`) say **Mac only**. The features play one after another, each for its animation's length (a short line under the playing one shows its progress), back to the first after the last, until one is picked: it then keeps replaying. Every animation ends exactly as it starts, so replaying is seamless. Keep Awake and Remap are still pictures. Rounded Corners shows a square-cornered screen filled by a light, square-cornered window, so the black corners stand out (the menu bar's items kept clear of the corners) and its switch in the middle: clicked on, the screen's corners round off in black, as round as the menu bar is tall; clicked off, they square up again. The panel spans the page's width, up to 1440 px. On narrow or short screens the page scrolls, with the features as a grid of icons (five to a row, all in view) above the panel, smaller text and a smaller top bar. Only plays while on screen; with Reduce Motion each animation shows how it ends.

- `src/data/features.ts`: the features' texts (and their Windows wording), order, animation lengths, colours and icons.
- `src/lib/motion.ts`: the animations' motion language, after LottieFiles' motion-design skill (the "Playful" personality): fast starts with soft landings, a small overshoot when things arrive (ease-out-back), a squash and spring on every click and keypress, a pointer that travels in arcs (x and y on different curves) and holds down while dragging, and a soft light drifting over each screen. Helpers return the keyframes, so every spot moves the same way. Colours are a softer palette than the system's pure ones (`--blue`, `--pink`… in `spot.css`).
- `src/components/spots/`: one animation per feature, in HTML and CSS on a square, transparent stage (`src/styles/spot.css` holds the shared pieces: screen, windows, pointer, keycaps, labels). Each runs its keyframes once over `--d` while its root has `.playing`.
- `src/pages/spots/[id].astro`: each animation alone, for recording; `scripts/render-spots.mjs` records them as 1080 px transparent WebM into `public/spots` (and ProRes 4444 with `--mov`), for social posts or elsewhere. `--sheet` writes a few frames side by side to check one.
- `src/config.ts`: where Download points (`Estris.dmg` of this repo's latest GitHub release, and the installer on the rolling `windows-latest` release), the site's address, the repo and the star threshold.
- Shared links show `public/og.png` (1200 × 630: the icon, the headline and Window Snapping's animation, paused while a window is dragged to the left edge), recorded from `src/pages/og.astro` by `scripts/render-og.mjs` (`npm run render-og` after a build).
