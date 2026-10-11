# Estris

Needs an Apple Development certificate (Xcode > Settings > Accounts > Manage Certificates). The build signs with it, so macOS keeps the Accessibility permission across builds.

```sh
./scripts/run.sh
```
Quits the running app, builds it and opens the new build. Use it after every change.

```sh
./scripts/build-app.sh
```
Only builds `build/Estris.app`, without opening it.

```sh
tccutil reset Accessibility com.carlesrojas.Estris
```
Run once after the signing certificate changes, then grant Accessibility again.

```sh
python3 scripts/check-localization.py
```
Checks every visible string is translated in every language.

## Website (`web/`)

```sh
cd web && npm install && npm run dev
```
Runs the site locally at http://localhost:4321.

```sh
cd web && npm run build && npm run render-spots
```
Re-records the feature animations as transparent videos in `web/public/spots` (add `-- --mov` for ProRes too).

Vercel: Add New > Project > import this repo > Root Directory `web` > Deploy.
