#!/bin/bash
# Builds the MediaRemote adapter (Vendor/mediaremote-adapter, BSD 3-Clause) into the app's
# resources. Since macOS 15.4 only Apple-signed processes may read Now Playing; the adapter's
# Perl script runs under /usr/bin/perl and loads this framework to do it for Kerf.
set -euo pipefail
SRC="$SRCROOT/Vendor/mediaremote-adapter"
OUT="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/MediaRemoteAdapter"
FRAMEWORK="$OUT/MediaRemoteAdapter.framework"
BINARY="$FRAMEWORK/MediaRemoteAdapter"
mkdir -p "$FRAMEWORK"
if [ ! -f "$BINARY" ] || [ -n "$(find "$SRC/src" "$SRC/include" -newer "$BINARY" -print -quit)" ]; then
    xcrun clang -dynamiclib -fobjc-arc -fvisibility=default -arch arm64 -arch x86_64 -mmacosx-version-min=26.0 \
        -I "$SRC/include" -I "$SRC/src" \
        $(find "$SRC/src/adapter" "$SRC/src/private" "$SRC/src/utility" -name '*.m') \
        -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
        -install_name @rpath/MediaRemoteAdapter.framework/MediaRemoteAdapter -o "$BINARY"
fi
# Signed like the app itself, with the hardened runtime; an archive (a release) also gets the
# timestamp notarization needs.
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
if [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - "$BINARY"
elif [ "${ACTION:-}" = "install" ]; then
    codesign --force --sign "$IDENTITY" --options runtime --timestamp "$BINARY"
else
    codesign --force --sign "$IDENTITY" --options runtime "$BINARY"
fi
cp "$SRC/bin/mediaremote-adapter.pl" "$OUT/mediaremote-adapter.pl"
