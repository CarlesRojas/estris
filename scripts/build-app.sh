#!/usr/bin/env bash
# Builds PasteRing.app into ./build.
# Signs with SIGN_IDENTITY, else your Apple Development certificate, else the
# "PasteRing Development" certificate made by create-dev-certificate.sh, else ad hoc.
# Ad-hoc signatures change every build, so macOS forgets the Accessibility permission each
# time; a fixed certificate keeps it, and an Apple-issued one is the most reliable.
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
    # By its hash: an expired or revoked certificate can share the same name.
    IDENTITY="$(security find-identity -v -p codesigning | grep "Apple Development" | grep -v CSSMERR | head -1 | awk '{print $2}' || true)"
fi
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
echo "Signed with: $(codesign -dvv "$APP" 2>&1 | grep -m1 '^Authority=' | cut -d= -f2- || echo 'ad hoc')"

echo "Built $APP"
