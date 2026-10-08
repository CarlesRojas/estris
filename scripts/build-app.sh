#!/usr/bin/env bash
# Builds PasteRing.app into ./build.
# Set SIGN_IDENTITY to a Developer ID / Apple Development identity to keep the
# Accessibility permission across rebuilds (ad-hoc signatures change every build).
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/PasteRing.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/PasteRing" "$APP/Contents/MacOS/PasteRing"
cp Resources/Info.plist "$APP/Contents/Info.plist"

codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"

echo "Built $APP"
