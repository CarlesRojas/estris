#!/usr/bin/env bash
# Builds Estris.app into ./build.
# Signs with SIGN_IDENTITY, else your Apple Development certificate, else ad hoc.
# RELEASE=1 builds for both Apple silicon and Intel and, with a Developer ID identity, signs
# for notarization (hardened runtime, secure timestamp). SPARKLE_PUBLIC_KEY, when set, is the
# key updates are checked against; without it the app doesn't look for updates.
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
if [[ -n "${SPARKLE_PUBLIC_KEY:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $SPARKLE_PUBLIC_KEY" "$APP/Contents/Info.plist"
fi

# Sparkle, for updates: SwiftPM leaves its framework next to the binary.
SPARKLE="$BIN_DIR/Sparkle.framework"
if [[ ! -d "$SPARKLE" ]]; then
    SPARKLE="$(find .build/artifacts -type d -path "*macos*/Sparkle.framework" | head -1)"
fi
mkdir -p "$APP/Contents/Frameworks"
cp -R "$SPARKLE" "$APP/Contents/Frameworks/"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Estris" 2> /dev/null || true

IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    # By its hash: an expired or revoked certificate can share the same name.
    IDENTITY="$(security find-identity -v -p codesigning | grep "Apple Development" | grep -v CSSMERR | head -1 | awk '{print $2}' || true)"
fi
if [[ -z "$IDENTITY" ]]; then
    IDENTITY="-"
    echo "No Apple Development certificate: signing ad hoc, so Accessibility must be granted again after each build."
fi
HARDENED=()
if [[ "${RELEASE:-}" == 1 && "$IDENTITY" != "-" ]]; then
    HARDENED=(--options runtime --timestamp)
fi
# Inside out: Sparkle's helpers, then the framework, then the app.
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for item in "$FRAMEWORK"/XPCServices/*.xpc; do
    if [[ -e "$item" ]]; then
        codesign --force ${HARDENED[@]+"${HARDENED[@]}"} --preserve-metadata=entitlements --sign "$IDENTITY" "$item"
    fi
done
for item in "$FRAMEWORK/Autoupdate" "$FRAMEWORK/Updater.app" "$APP/Contents/Frameworks/Sparkle.framework"; do
    if [[ -e "$item" ]]; then
        codesign --force ${HARDENED[@]+"${HARDENED[@]}"} --sign "$IDENTITY" "$item"
    fi
done
if [[ "${#HARDENED[@]}" -gt 0 ]]; then
    codesign --force "${HARDENED[@]}" --entitlements Resources/Estris.entitlements --sign "$IDENTITY" "$APP"
else
    codesign --force --sign "$IDENTITY" "$APP"
fi
SIGNATURE="$(codesign -dvv "$APP" 2>&1)"
AUTHORITY="$(grep '^Authority=' <<<"$SIGNATURE" | head -1 | cut -d= -f2- || true)"
echo "Signed with: ${AUTHORITY:-ad hoc}"

echo "Built $APP"
