#!/usr/bin/env bash
# build_ff.sh — build mod.ff containing Origins + core FF-layer patches
#
# 9 scripts: 2 core + 7 Origins-specific (no Die Rise)
#
# Prerequisites:
#   OAT compiled at ~/projects/OpenAssetTools (or set OAT env var)
#   Base game .ff files (set BO2 env var to game install path)
#
# Usage:
#   ./build_ff.sh
#   OAT=~/tools/OpenAssetTools ./build_ff.sh
#   BO2="/path/to/BO2" ./build_ff.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
OAT_DIR="${OAT:-$HOME/projects/OpenAssetTools}"
LINKER="$OAT_DIR/build/bin/Release_x64/Linker"
BO2="${BO2:-/mnt/c/Program Files (x86)/Steam/steamapps/common/Call of Duty Black Ops II}"

PLUTO_MOD="/mnt/c/Users/$(cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r')/AppData/Local/Plutonium/storage/t6/mods/zm_origins_fix"
BUILD_DIR="/tmp/oat_origins_build"

PATCHED_DIR="$REPO_DIR/patched"

# ---------------------------------------------------------------------------

if [[ ! -x "$LINKER" ]]; then
    echo "error: OAT Linker not found at $LINKER"
    echo "Build OAT: cd ~/projects/OpenAssetTools && build/premake5 --arch=x86_64 gmake && make -C build config=release_x64 -j\$(nproc)"
    exit 1
fi

if [[ ! -d "$PATCHED_DIR" ]]; then
    echo "error: patched/ directory not found"
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 1: Staging area
# ---------------------------------------------------------------------------
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/zone_source"
mkdir -p "$BUILD_DIR/raw/t6/maps/mp/zombies"
mkdir -p "$BUILD_DIR/raw/t6/maps/mp"

cp "$REPO_DIR/zone_source/zm_origins_fix.zone" "$BUILD_DIR/zone_source/"

# ---------------------------------------------------------------------------
# Step 2: Stage patched source files (9 scripts)
# ---------------------------------------------------------------------------

# Core
cp "$PATCHED_DIR/maps/mp/zombies/_zm_weapons.gsc"          "$BUILD_DIR/raw/t6/maps/mp/zombies/"
cp "$PATCHED_DIR/maps/mp/zombies/_zm_utility.gsc"           "$BUILD_DIR/raw/t6/maps/mp/zombies/"

# Origins staff weapons
cp "$PATCHED_DIR/maps/mp/zombies/_zm_weap_staff_fire.gsc"   "$BUILD_DIR/raw/t6/maps/mp/zombies/"
cp "$PATCHED_DIR/maps/mp/zombies/_zm_weap_staff_air.gsc"    "$BUILD_DIR/raw/t6/maps/mp/zombies/"
cp "$PATCHED_DIR/maps/mp/zombies/_zm_weap_staff_water.gsc"  "$BUILD_DIR/raw/t6/maps/mp/zombies/"

# Origins map scripts
cp "$PATCHED_DIR/maps/mp/zm_tomb_capture_zones.gsc"         "$BUILD_DIR/raw/t6/maps/mp/"
cp "$PATCHED_DIR/maps/mp/zm_tomb_giant_robot.gsc"           "$BUILD_DIR/raw/t6/maps/mp/"
cp "$PATCHED_DIR/maps/mp/zm_tomb_tank.gsc"                  "$BUILD_DIR/raw/t6/maps/mp/"
cp "$PATCHED_DIR/maps/mp/zm_tomb_utility.gsc"               "$BUILD_DIR/raw/t6/maps/mp/"

echo "staged 9 patched source files (2 core + 7 Origins)"

# ---------------------------------------------------------------------------
# Step 3: Link
# ---------------------------------------------------------------------------
echo "linking (OAT compiles sources)..."
"$LINKER" \
    --base-folder "$BUILD_DIR" \
    --load "$BO2/zone/all/patch_zm.ff" \
    --load "$BO2/zone/all/common_zm.ff" \
    --load "$BO2/zone/all/zm_tomb.ff" \
    zm_origins_fix

FF_PATH="$BUILD_DIR/zone_out/zm_origins_fix/mod.ff"
if [[ ! -f "$FF_PATH" ]]; then
    echo "error: Linker did not produce $FF_PATH"
    exit 1
fi

SIZE=$(du -h "$FF_PATH" | cut -f1)
echo "built  mod.ff  ($SIZE)  — 9 OAT-compiled scripts"

cp "$FF_PATH" "$REPO_DIR/zone/mod.ff"
echo "updated zone/mod.ff"

# ---------------------------------------------------------------------------
# Step 4: Deploy
# ---------------------------------------------------------------------------
if [[ -d "$(dirname "$PLUTO_MOD")" ]]; then
    mkdir -p "$PLUTO_MOD"
    cp "$FF_PATH" "$PLUTO_MOD/mod.ff"
    echo "deployed → $PLUTO_MOD/mod.ff"
    echo ""
    echo "Enable 'zm_origins_fix' mod in Plutonium, then load Origins."
else
    echo ""
    echo "Plutonium not found. Copy manually:"
    echo "  cp $FF_PATH"
    echo "  to: %LOCALAPPDATA%\\Plutonium\\storage\\t6\\mods\\zm_origins_fix\\mod.ff"
fi
