#!/usr/bin/env bash
# Packs build/Estris.app into build/Estris.dmg: a window with the app, a link to Applications
# and a background saying to drag one onto the other (scripts/dmg-settings.py). Needs dmgbuild
# (`python3 -m pip install dmgbuild`). Signs the disk image too when SIGN_IDENTITY is a real identity.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! python3 -c "import dmgbuild" 2> /dev/null; then
    echo "dmgbuild is missing: python3 -m pip install dmgbuild" >&2
    exit 1
fi

DMG="build/Estris.dmg"
BACKGROUND="build/dmg-background.tiff"
rm -f "$DMG" "$BACKGROUND"
# One image with both resolutions, so the background is sharp on Retina screens.
tiffutil -cathidpicheck Resources/DMG/background.png Resources/DMG/background@2x.png -out "$BACKGROUND"
python3 -m dmgbuild -s scripts/dmg-settings.py -D app=build/Estris.app -D background="$BACKGROUND" Estris "$DMG"

if [[ -n "${SIGN_IDENTITY:-}" && "${SIGN_IDENTITY}" != "-" ]]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi
echo "Built $DMG"
