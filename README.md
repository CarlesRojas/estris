# PasteRing

Needs an Apple Development certificate (Xcode > Settings > Accounts > Manage Certificates). The build signs with it, so macOS keeps the Accessibility permission across builds.

```sh
./scripts/run.sh
```
Quits the running app, builds it and opens the new build. Use it after every change.

```sh
./scripts/build-app.sh
```
Only builds `build/PasteRing.app`, without opening it.

```sh
tccutil reset Accessibility com.carlesrojas.PasteRing
```
Run once after the signing certificate changes, then grant Accessibility again.
