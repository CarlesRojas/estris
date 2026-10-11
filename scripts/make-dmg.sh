#!/usr/bin/env bash
# Packs build/Estris.app into build/Estris.dmg, with a link to Applications to drag it to.
# Signs the disk image too when SIGN_IDENTITY is a real identity.
set -euo pipefail

cd "$(dirname "$0")/.."

STAGING="build/dmg"
DMG="build/Estris.dmg"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R build/Estris.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname Estris -srcfolder "$STAGING" -fs HFS+ -format UDZO "$DMG"
rm -rf "$STAGING"

if [[ -n "${SIGN_IDENTITY:-}" && "${SIGN_IDENTITY}" != "-" ]]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi
echo "Built $DMG"
