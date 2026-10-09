#!/usr/bin/env bash
# Quits the running PasteRing, rebuilds it and opens the new build.
set -euo pipefail

cd "$(dirname "$0")/.."

pkill -x PasteRing || true
./scripts/build-app.sh
open build/PasteRing.app
