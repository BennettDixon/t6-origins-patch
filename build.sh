#!/usr/bin/env bash
# build.sh — compile addon GSC scripts (diagnostics, patches, stress test)
#
# These are loaded by Plutonium's script injection (scripts/zm/ directory),
# separate from the FF-layer overrides built by build_ff.sh.
#
# Prerequisites:
#   gsc-tool binary in tools/ (download from https://github.com/xensik/gsc-tool/releases)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GSC_TOOL="$SCRIPT_DIR/tools/gsc-tool"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
COMPILED_DIR="$SCRIPT_DIR/compiled"

if [[ ! -x "$GSC_TOOL" ]]; then
    echo "error: gsc-tool not found at $GSC_TOOL"
    echo "download from https://github.com/xensik/gsc-tool/releases"
    exit 1
fi

echo "gsc-tool: $($GSC_TOOL --version 2>&1 | head -1)"
echo ""

FAIL=0
PASS=0

for gsc_file in "$SCRIPTS_DIR"/*.gsc; do
    [[ -f "$gsc_file" ]] || continue
    name="$(basename "$gsc_file")"

    echo -n "compiling $name ... "
    if "$GSC_TOOL" -m comp -g t6 -s pc "$gsc_file" 2>&1 | grep -q "compiled"; then
        echo "ok"
        PASS=$((PASS + 1))
    else
        echo "FAILED"
        "$GSC_TOOL" -m comp -g t6 -s pc "$gsc_file" 2>&1
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "results: $PASS passed, $FAIL failed"

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi

echo ""
echo "compiled scripts in: $COMPILED_DIR/t6/"
ls -la "$COMPILED_DIR/t6/"
