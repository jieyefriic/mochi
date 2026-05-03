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
    "$SRC_DIR/Onboarding.swift" \
    "$SRC_DIR/Persistence.swift" \
    "$SRC_DIR/Evolution.swift" \
    "$SRC_DIR/Bubbles.swift" \
    "$SRC_DIR/Species.swift" \
    "$SRC_DIR/Traits.swift"

# ───────── sprite bundling ─────────────────────────────────
# All assets land flat in Resources/ with prefix-encoded names so they're
# resolvable via NSImage(named:). Naming scheme (matches Evolution.swift):
#   egg_common.png                              S0
#   egg_idle.png                                S1 red (Magma) — historic name
#   egg_<blue|green|purple|gold>.png            S1 other colors
#   cracking_<color>.png                        S2
#   <color>_<stagename>.png                     S3..S6 species static
#   anim_<color>_<N>.png                        S1 idle anim frames
#   anim_cracking_<color>_<N>.png               S2 idle anim frames
#   anim_<color>_<stagename>_<N>.png            S3..S6 idle anim frames
#   anim_wobble_red_<N>.png                     red wobble (legacy)

echo "→ copying static sprites"
# Top-level eggs (egg_common, egg_idle, egg_blue, egg_green, egg_purple, egg_gold).
if compgen -G "$SRC_DIR/assets/*.png" > /dev/null; then
    cp "$SRC_DIR/assets/"*.png "$RESOURCES/" 2>/dev/null || true
fi

# Cracking statics  (assets/cracking/<color>.png → cracking_<color>.png)
if [ -d "$SRC_DIR/assets/cracking" ]; then
    for f in "$SRC_DIR/assets/cracking"/*.png; do
        [ -f "$f" ] || continue
        base=$(basename "$f" .png)
        cp "$f" "$RESOURCES/cracking_${base}.png"
    done
fi

# Per-color species statics  (assets/<color>/<stagename>.png → <color>_<stagename>.png)
for color in red blue green purple gold; do
    [ -d "$SRC_DIR/assets/$color" ] || continue
    for f in "$SRC_DIR/assets/$color"/*.png; do
        [ -f "$f" ] || continue
        base=$(basename "$f" .png)
        cp "$f" "$RESOURCES/${color}_${base}.png"
    done
done

echo "→ copying animation frames"
copy_anim() {
    local src_dir="$1"
    local prefix="$2"
    [ -d "$src_dir" ] || return 0
    for f in "$src_dir"/frame_*.png; do
        [ -f "$f" ] || continue
        n=$(basename "$f" .png | sed 's/frame_//')
        cp "$f" "$RESOURCES/${prefix}_${n}.png"
    done
}

# S1 elemental egg idle anims  (assets/anim/<color>/ → anim_<color>_N)
for color in red blue green purple gold; do
    copy_anim "$SRC_DIR/assets/anim/$color" "anim_${color}"
done

# S2 cracking idle anims  (assets/cracking_anim/<color>/ → anim_cracking_<color>_N)
for color in red blue green purple gold; do
    copy_anim "$SRC_DIR/assets/cracking_anim/$color" "anim_cracking_${color}"
done

# S3-S6 species idle anims  (assets/<color>/<stagename>/idle/ → anim_<color>_<stagename>_N)
for color in red blue green purple gold; do
    [ -d "$SRC_DIR/assets/$color" ] || continue
    for stage_dir in "$SRC_DIR/assets/$color"/*/idle; do
        [ -d "$stage_dir" ] || continue
        stage_name=$(basename "$(dirname "$stage_dir")")
        copy_anim "$stage_dir" "anim_${color}_${stage_name}"
    done
done

# Red wobble (legacy, only red has it from Phase A)
if [ -d "$SRC_DIR/assets/anim_wobble" ]; then
    for color in red blue green purple gold; do
        copy_anim "$SRC_DIR/assets/anim_wobble/$color" "anim_wobble_${color}"
    done
fi

# ── Feed animations (one-shot reaction overlay) ────────────────
# Naming mirrors the idle anims but with prefix `feed_` instead of `anim_`.
#   common/feed/                     → feed_common_N
#   anim_feed/<color>/               → feed_<color>_N            (S1)
#   anim_feed_cracking/<color>/      → feed_cracking_<color>_N   (S2)
#   anim_feed/<color>_<species>/     → feed_<color>_<species>_N  (S3-S6)
copy_anim "$SRC_DIR/assets/common/feed" "feed_common"
for color in red blue green purple gold; do
    copy_anim "$SRC_DIR/assets/anim_feed/$color" "feed_${color}"
    copy_anim "$SRC_DIR/assets/anim_feed_cracking/$color" "feed_cracking_${color}"
done
if [ -d "$SRC_DIR/assets/anim_feed" ]; then
    for d in "$SRC_DIR/assets/anim_feed"/*_*; do
        [ -d "$d" ] || continue
        slug=$(basename "$d")        # e.g. blue_mochilet
        copy_anim "$d" "feed_${slug}"
    done
fi

# Per-stage red wobble  (assets/red/<stage>/wobble/ → anim_wobble_red_<stage>_N)
if [ -d "$SRC_DIR/assets/red" ]; then
    for stage_dir in "$SRC_DIR/assets/red"/*/wobble; do
        [ -d "$stage_dir" ] || continue
        stage_name=$(basename "$(dirname "$stage_dir")")
        copy_anim "$stage_dir" "anim_wobble_red_${stage_name}"
    done
fi

echo "    bundled $(ls "$RESOURCES"/*.png 2>/dev/null | wc -l | tr -d ' ') png(s)"

echo "→ copying bubbles.json"
if [ -f "$SRC_DIR/bubbles.json" ]; then
    cp "$SRC_DIR/bubbles.json" "$RESOURCES/"
fi

echo "→ copying app icon"
if [ -f "$SRC_DIR/assets/Mochi.icns" ]; then
    cp "$SRC_DIR/assets/Mochi.icns" "$RESOURCES/Mochi.icns"
fi

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
