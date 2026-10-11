#!/usr/bin/env bash
# Builds Estris.app into ./build.
# Signs with SIGN_IDENTITY, else your Apple Development certificate, else ad hoc.
# RELEASE=1 builds for both Apple silicon and Intel and, with a Developer ID identity, signs
# for notarization (hardened runtime, secure timestamp).
# Ad-hoc signatures change every build, so macOS forgets the Accessibility permission each
# time; an Apple Development certificate keeps it.
set -euo pipefail

cd "$(dirname "$0")/.."

ARCHS=()
if [[ "${RELEASE:-}" == 1 ]]; then
    ARCHS=(--arch arm64 --arch x86_64)
fi
swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
BIN_DIR="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)"

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
if [[ "${RELEASE:-}" == 1 && "$IDENTITY" != "-" ]]; then
    codesign --force --options runtime --timestamp --entitlements Resources/Estris.entitlements --sign "$IDENTITY" "$APP"
else
    codesign --force --sign "$IDENTITY" "$APP"
fi
SIGNATURE="$(codesign -dvv "$APP" 2>&1)"
AUTHORITY="$(grep '^Authority=' <<<"$SIGNATURE" | head -1 | cut -d= -f2- || true)"
echo "Signed with: ${AUTHORITY:-ad hoc}"

echo "Built $APP"
