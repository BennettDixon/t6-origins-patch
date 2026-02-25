#!/usr/bin/env bash
# deploy.sh — deploy compiled addon scripts to Plutonium T6 scripts dir (WSL)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPILED_DIR="$SCRIPT_DIR/compiled/t6"

if [[ ! -d "$COMPILED_DIR" ]]; then
    echo "error: compiled/t6/ not found. Run build.sh first."
    exit 1
fi

DEST="/mnt/c/Users/$(cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r')/AppData/Local/Plutonium/storage/t6/scripts/zm"

if [[ ! -d "/mnt/c/Users" ]]; then
    echo "error: Windows filesystem not found at /mnt/c. Run this from WSL."
    exit 1
fi

mkdir -p "$DEST"
cp "$COMPILED_DIR"/zm_*.gsc "$DEST/"

echo "Deployed to $DEST"
ls -la "$DEST/"
