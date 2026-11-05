#!/bin/zsh
# Renders the promo video into build/promo: records the island with `Kerf --lab promo`, then
# composes the tilted plane, type, wipes and sound with compose.swift. Takes a few minutes.
# Keep the display awake while it records: the recorder only gets frames while it is on.
set -euo pipefail
cd "$(dirname "$0")/../.."
out=build/promo
xcodebuild -project Kerf.xcodeproj -scheme Kerf -configuration Release -derivedDataPath build/DerivedData build -quiet
rm -rf "$out/frames"
mkdir -p "$out"
build/DerivedData/Build/Products/Release/Kerf.app/Contents/MacOS/Kerf --lab promo "$out/frames"
swiftc -O -swift-version 5 scripts/promo/compose.swift -o "$out/compose"
"$out/compose" "$out/frames" "$out" "$@"
