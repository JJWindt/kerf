#!/bin/bash
# Builds Kerf in Release, installs it in /Applications and starts it. Waits for a running copy
# to quit first, so the old one can't take the new one's socket with it.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project Kerf.xcodeproj -scheme Kerf -configuration Release -derivedDataPath build/DerivedData build | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
osascript -e 'quit app "Kerf"' 2>/dev/null || true
for _ in $(seq 1 50); do
    pgrep -f "/Applications/Kerf.app/Contents/MacOS/Kerf$" >/dev/null || break
    sleep 0.2
done
pkill -f "/Applications/Kerf.app/Contents/MacOS/Kerf$" 2>/dev/null || true
rm -rf /Applications/Kerf.app
cp -R build/DerivedData/Build/Products/Release/Kerf.app /Applications/Kerf.app
open /Applications/Kerf.app
echo "Installed and started /Applications/Kerf.app."
