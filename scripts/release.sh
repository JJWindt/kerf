#!/bin/bash
# Builds a Kerf release for Homebrew: archives, signs with Developer ID, has Apple notarize it
# (through the account in Xcode), staples the ticket and zips the app.
#
#   scripts/release.sh             build/release/Kerf-<version>.zip and its sha256
#   scripts/release.sh --publish   also the GitHub release and the cask in paultje1900/homebrew-tap
#
# The version is MARKETING_VERSION in the project; raise it first.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(xcodebuild -project Kerf.xcodeproj -scheme Kerf -configuration Release -showBuildSettings 2>/dev/null | awk '$1 == "MARKETING_VERSION" { print $3 }')
OUT=build/release
ARCHIVE="$OUT/Kerf.xcarchive"
rm -rf "$OUT"
mkdir -p "$OUT"

echo "Kerf $VERSION: archiving"
xcodebuild -project Kerf.xcodeproj -scheme Kerf -configuration Release -derivedDataPath build/DerivedData \
    -archivePath "$ARCHIVE" archive | grep -E "error:|ARCHIVE (SUCCEEDED|FAILED)"

echo "Signing with Developer ID and sending to Apple's notary service"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist scripts/ExportOptions.plist \
    -exportPath "$OUT/upload" -allowProvisioningUpdates | grep -E "error:|EXPORT (SUCCEEDED|FAILED)"

echo "Waiting for Apple (usually a few minutes)"
for _ in $(seq 1 90); do
    xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$OUT/app" >/dev/null 2>&1 && break
    sleep 20
done
APP="$OUT/app/Kerf.app"
[ -d "$APP" ] || { echo "Not notarized after 30 minutes; see Window > Organizer in Xcode."; exit 1; }
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

ZIP="$OUT/Kerf-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | awk '{ print $1 }')
echo "$ZIP"
echo "sha256 $SHA"

[ "${1:-}" = "--publish" ] || exit 0

echo "Publishing v$VERSION"
gh release create "v$VERSION" "$ZIP" --repo paultje1900/kerf --title "Kerf $VERSION" \
    --notes "Install or update: \`brew install --cask paultje1900/tap/kerf\` or \`brew upgrade --cask kerf\`."
TAP=$(mktemp -d)
gh repo clone paultje1900/homebrew-tap "$TAP" -- --quiet
sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$TAP/Casks/kerf.rb"
git -C "$TAP" commit --quiet -am "kerf $VERSION"
git -C "$TAP" push --quiet
rm -rf "$TAP"
echo "Done: brew upgrade --cask kerf"
