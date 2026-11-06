# Estris

Small utilities for Mac and Windows. `macos/` and `windows/` are the two apps, `web/` the site.

## Mac (`macos/`)

Needs an Apple Development certificate (Xcode > Settings > Accounts > Manage Certificates). The build signs with it, so macOS keeps the Accessibility permission across builds.

```sh
cd macos && ./scripts/run.sh
```
Quits the running app, builds it and opens the new build. Use it after every change.

```sh
cd macos && ./scripts/build-app.sh
```
Only builds `build/Estris.app`, without opening it.

```sh
tccutil reset Accessibility com.carlesrojas.Estris
```
Run once after the signing certificate changes, then grant Accessibility again.

```sh
python3 macos/scripts/check-localization.py
```
Checks every visible string is translated in every language.

## Windows (`windows/`)

Needs the [.NET 10 SDK](https://dotnet.microsoft.com/download). Visual Studio isn't needed.

```sh
bash windows/scripts/build.sh run
```
Quits the running app, builds it and opens the new build.

```sh
python windows/scripts/check-localization.py
```
Checks every visible string is translated in every language. `--from-mac` first copies the translations the Mac app already has.

```sh
dotnet tool install -g vpk && VERSION=1.2.3 bash windows/scripts/make-installer.sh
```
Builds the installers into `windows/build/releases`.

## Releases

Actions > Release macOS or Release Windows > Run workflow, on main, choosing patch, minor or major: bumps that app's version, turns its changelog's Unreleased entries into the release notes, and publishes it.

## Website (`web/`)

```sh
cd web && npm install && npm run dev
```
Runs the site locally at http://localhost:4321.

```sh
cd web && npm run build && npm run render-spots
```
Re-records the feature animations as transparent videos in `web/public/spots` (add `-- --mov` for ProRes too).

```sh
cd web && npm run build && npm run render-og
```
Re-records `web/public/og.png`, the picture shown when the site is shared.

Vercel: Add New > Project > import this repo > Root Directory `web` > Deploy.
