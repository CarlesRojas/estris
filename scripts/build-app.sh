#!/usr/bin/env bash
# Builds Estris.app into ./build.
# Signs with SIGN_IDENTITY, else your Apple Development certificate, else ad hoc.
# Ad-hoc signatures change every build, so macOS forgets the Accessibility permission each
# time; an Apple Development certificate keeps it.
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/Estris.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/Estris" "$APP/Contents/MacOS/Estris"
cp Resources/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp -R Resources/Localization/*.lproj "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    # By its hash: an expired or revoked certificate can share the same name.
    IDENTITY="$(security find-identity -v -p codesigning | grep "Apple Development" | grep -v CSSMERR | head -1 | awk '{print $2}' || true)"
fi
if [[ -z "$IDENTITY" ]]; then
    IDENTITY="-"
    echo "No Apple Development certificate: signing ad hoc, so Accessibility must be granted again after each build."
fi
codesign --force --sign "$IDENTITY" "$APP"
SIGNATURE="$(codesign -dvv "$APP" 2>&1)"
AUTHORITY="$(grep '^Authority=' <<<"$SIGNATURE" | head -1 | cut -d= -f2- || true)"
echo "Signed with: ${AUTHORITY:-ad hoc}"

echo "Built $APP"
