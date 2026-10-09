#!/usr/bin/env bash
# Builds PasteRing.app into ./build.
# Signs with SIGN_IDENTITY, else the "PasteRing Development" certificate made by
# create-dev-certificate.sh, else ad hoc. Ad-hoc signatures change every build, so macOS
# forgets the Accessibility permission each time; a fixed certificate keeps it.
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/PasteRing.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/PasteRing" "$APP/Contents/MacOS/PasteRing"
cp Resources/Info.plist "$APP/Contents/Info.plist"

IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    if security find-certificate -c "PasteRing Development" >/dev/null 2>&1; then
        IDENTITY="PasteRing Development"
    else
        IDENTITY="-"
        echo "Signing ad hoc: Accessibility must be granted again after each build."
        echo "Run ./scripts/create-dev-certificate.sh once to keep it."
    fi
fi
codesign --force --sign "$IDENTITY" "$APP"

echo "Built $APP"
