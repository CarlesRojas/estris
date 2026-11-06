#!/usr/bin/env bash
# Builds the Windows app for this PC. Pass "run" to open it after, quitting the running copy first.
set -euo pipefail
cd "$(dirname "$0")/.."

# dotnet-install puts the SDK here when it can't be installed for the whole machine.
if [[ -x "${LOCALAPPDATA:-}/Microsoft/dotnet/dotnet.exe" ]]; then
    export DOTNET_ROOT="$LOCALAPPDATA/Microsoft/dotnet"
    export PATH="$DOTNET_ROOT:$PATH"
fi
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1

taskkill //F //IM Estris.exe > /dev/null 2>&1 || true
dotnet build src/Estris/Estris.csproj -c Debug -p:Platform=x64 -r win-x64 -v:q -nologo

if [[ "${1:-}" == "run" ]]; then
    src/Estris/bin/x64/Debug/net10.0-windows10.0.26100.0/win-x64/Estris.exe &
fi
