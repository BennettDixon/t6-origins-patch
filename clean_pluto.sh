#!/usr/bin/env bash
# clean_pluto.sh — remove all zm_hrp mod files from the Plutonium storage dir
#
# Removes:
#   mods/zm_hrp/mod.ff
#   scripts/zm/zm_diagnostics.gsc
#   scripts/zm/zm_highround_patch.gsc
#   scripts/zm/zm_patch_entity_leaks.gsc
#   scripts/zm/zm_patch_loops.gsc
#   scripts/zm/zm_patch_overflow.gsc
#   scripts/zm/zm_patch_scrvar.gsc
#   scripts/zm/zm_stress_test.gsc
#   scripts/zm/zm_test.gsc
#   scripts/zm/zm_test_ff.gsc
#   scripts/zm/zm_test_il01.gsc
#
# After recording, rebuild and redeploy with:
#   ./build_ff.sh
set -euo pipefail

PLUTO_T6="/mnt/c/Users/benne/AppData/Local/Plutonium/storage/t6"
PLUTO_MOD="$PLUTO_T6/mods/zm_hrp"
PLUTO_SCRIPTS="$PLUTO_T6/scripts/zm"

if [[ ! -d "$PLUTO_T6" ]]; then
    echo "error: Plutonium storage not found at $PLUTO_T6"
    exit 1
fi

# Collect what's actually present so we can report honestly
declare -a TO_REMOVE

add_if_exists() {
    [[ -e "$1" ]] && TO_REMOVE+=("$1")
}

add_if_exists "$PLUTO_MOD/mod.ff"
add_if_exists "$PLUTO_SCRIPTS/zm_diagnostics.gsc"
add_if_exists "$PLUTO_SCRIPTS/zm_highround_patch.gsc"
add_if_exists "$PLUTO_SCRIPTS/zm_patch_entity_leaks.gsc"
add_if_exists "$PLUTO_SCRIPTS/zm_patch_loops.gsc"
add_if_exists "$PLUTO_SCRIPTS/zm_patch_overflow.gsc"
add_if_exists "$PLUTO_SCRIPTS/zm_patch_scrvar.gsc"
add_if_exists "$PLUTO_SCRIPTS/zm_stress_test.gsc"
add_if_exists "$PLUTO_SCRIPTS/zm_test.gsc"
add_if_exists "$PLUTO_SCRIPTS/zm_test_ff.gsc"
add_if_exists "$PLUTO_SCRIPTS/zm_test_il01.gsc"

if [[ ${#TO_REMOVE[@]} -eq 0 ]]; then
    echo "nothing to remove — Plutonium directory is already clean"
    exit 0
fi

echo "Files to remove:"
for f in "${TO_REMOVE[@]}"; do
    echo "  $f"
done
echo ""

# Skip confirmation if -y flag passed
if [[ "${1:-}" != "-y" ]]; then
    read -r -p "Remove ${#TO_REMOVE[@]} file(s)? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "aborted"; exit 0; }
fi

for f in "${TO_REMOVE[@]}"; do
    rm "$f"
    echo "removed  $f"
done

# Remove the mod folder itself if now empty (except for logs)
if [[ -d "$PLUTO_MOD" ]]; then
    remaining=$(find "$PLUTO_MOD" -not -name "*.log" -not -type d | wc -l)
    if [[ "$remaining" -eq 0 ]]; then
        rmdir "$PLUTO_MOD" 2>/dev/null && echo "removed  $PLUTO_MOD (empty)"
    fi
fi

echo ""
echo "Plutonium directory cleaned. To rebuild and redeploy:"
echo "  ./build_ff.sh"
