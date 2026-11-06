#!/usr/bin/env bash
# Quits the running Estris, rebuilds it and opens the new build.
set -euo pipefail

cd "$(dirname "$0")/.."

pkill -x Estris || true
# The app's name before it was renamed: quit it and drop its old build, so the two don't
# compete for the same shortcuts.
pkill -x PasteRing || true
rm -rf build/PasteRing.app
./scripts/build-app.sh
open build/Estris.app
