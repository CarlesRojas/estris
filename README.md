# PasteRing

A native macOS menu bar app with a set of utilities. Requires macOS 13+ and the Swift toolchain (Xcode or Command Line Tools).

## Develop

```sh
./scripts/create-dev-certificate.sh
```
Run once. Creates a local signing certificate so macOS keeps the Accessibility permission across rebuilds. Asks for your password to trust it.

```sh
./scripts/run.sh
```
Quits the running app, builds it and opens the new build. Use it after every change.

```sh
./scripts/build-app.sh
```
Only builds `build/PasteRing.app`, without opening it.

The first time the signed build opens, grant Accessibility in System Settings > Privacy & Security > Accessibility (remove any old PasteRing entry first). Later builds keep it.

Click the version in Settings > General > About six times to show the Developer pane, with the logs.
