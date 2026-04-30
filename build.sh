#!/bin/bash
# Build Mochi.app and install to ~/Applications.
# Builds in /tmp to avoid iCloud fileprovider xattrs that break codesign.

set -e
cd "$(dirname "$0")"
SRC_DIR="$(pwd)"

APP_NAME="Mochi"
BUILD_DIR="$(mktemp -d /tmp/mochi-XXXXXX)"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

INSTALL_DIR="$HOME/Applications"
INSTALL_APP="$INSTALL_DIR/$APP_NAME.app"

cleanup() { rm -rf "$BUILD_DIR"; }
trap cleanup EXIT

echo "→ build dir: $BUILD_DIR"
mkdir -p "$MACOS" "$RESOURCES"

echo "→ compiling"
xcrun swiftc \
    -O \
    -target arm64-apple-macos13.0 \
    -parse-as-library \
    -o "$MACOS/$APP_NAME" \
    "$SRC_DIR/Mochi.swift" \
    "$SRC_DIR/TrashWatcher.swift" \
    "$SRC_DIR/Onboarding.swift"

echo "→ installing Info.plist"
cp "$SRC_DIR/Info.plist" "$CONTENTS/"

echo "→ ad-hoc signing"
codesign --force --deep --sign - "$APP_DIR"

echo "→ verifying signature"
codesign --verify --verbose "$APP_DIR" 2>&1 | sed 's/^/    /'

mkdir -p "$INSTALL_DIR"
if [ -d "$INSTALL_APP" ]; then
    echo "→ stopping any running instance"
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 0.3
    rm -rf "$INSTALL_APP"
fi

echo "→ installing to $INSTALL_APP"
ditto --noextattr --noqtn "$APP_DIR" "$INSTALL_APP"

echo ""
echo "✓ installed $INSTALL_APP"
echo "  launch: open \"$INSTALL_APP\""
