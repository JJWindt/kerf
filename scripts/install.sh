#!/bin/bash
# Builds Kerf in Release, installs it in ~/Applications (no admin rights needed) and starts it.
# Waits for a running copy to quit first, so the old one can't take the new one's socket with it.
set -euo pipefail
cd "$(dirname "$0")/.."
target="$HOME/Applications/Kerf.app"
xcodebuild -project Kerf.xcodeproj -scheme Kerf -configuration Release -derivedDataPath build/DerivedData build | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
osascript -e 'quit app id "nl.jjwindt.kerf"' 2>/dev/null || true
for _ in $(seq 1 50); do
    pgrep -f "Kerf.app/Contents/MacOS/Kerf$" >/dev/null || break
    sleep 0.2
done
pkill -f "Kerf.app/Contents/MacOS/Kerf$" 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$target"
cp -R build/DerivedData/Build/Products/Release/Kerf.app "$target"
open "$target"
echo "Installed and started $target."
