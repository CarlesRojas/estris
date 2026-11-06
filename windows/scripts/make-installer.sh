#!/usr/bin/env bash
# Publishes the app for x64 and ARM64 and packs each with Velopack into build/releases: the
# installers (Estris-win-Setup.exe, Estris-win-arm64-Setup.exe) and what installed copies read
# to update themselves. VERSION is required; SIGN_PARAMS, if set, goes to signtool.
set -euo pipefail
cd "$(dirname "$0")/.."

rm -rf build/publish build/releases
mkdir -p build/releases

pack() {
    local platform="$1" runtime="$2" channel="$3"
    dotnet publish src/Estris/Estris.csproj -c Release -p:Platform="$platform" -r "$runtime" -p:Version="$VERSION" -o "build/publish/$runtime"
    vpk pack \
        --packId Estris \
        --packTitle Estris \
        --packAuthors "Carles Rojas" \
        --packVersion "$VERSION" \
        --packDir "build/publish/$runtime" \
        --mainExe Estris.exe \
        --icon src/Estris/Assets/Estris.ico \
        --channel "$channel" \
        --runtime "$runtime" \
        --delta none \
        --noPortable \
        --outputDir build/releases \
        ${SIGN_PARAMS:+--signParams "$SIGN_PARAMS"}
}

pack x64 win-x64 win
pack ARM64 win-arm64 win-arm64
ls build/releases
