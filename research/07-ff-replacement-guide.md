# FF File Replacement Guide

How to build and deploy a patched `mod.ff` that overrides base-game scripts in
`patch_zm.ff`, applying the IL-01 (`has_attachment` infinite loop), IL-02
(`random_attachment` infinite loop), and EL-01 (`lerp` entity leak) fixes.

> **BO2 has no official Steam Mod Tools.** BO1 and BO3 shipped them; BO2 (T6) did not.
> The only supported route is the community-built
> [OpenAssetTools (OAT)](https://github.com/Laupetin/OpenAssetTools).

---

## How it works

`_zm_weapons.gsc` and `_zm_utility.gsc` live in **`patch_zm.ff`** as `script`-type
assets. Plutonium's `zone\` folder can only add *new* content — it cannot override
existing assets from `patch_zm.ff`. Script overrides require the **`mods\` folder**,
which Plutonium loads after all base-game zones, letting assets replace same-named ones.

We build a minimal `mod.ff` containing only two `script` assets:

| Asset path | Source file | Fixes |
|---|---|---|
| `maps/mp/zombies/_zm_weapons.gsc` | `ZM/Core/maps/mp/zombies/_zm_weapons.gsc` | IL-01, IL-02 |
| `maps/mp/zombies/_zm_utility.gsc` | `ZM/Core/maps/mp/zombies/_zm_utility.gsc` | EL-01 |

OAT's Linker **compiles these source files itself** using its own T6 GSC compiler,
producing native T6 bytecode with the correct script name hash and section format.
Everything else in `patch_zm.ff` (models, sounds, other scripts) loads normally from
the unmodified base-game file.

### Why OAT's own compiler (not gsc-tool)

`gsc-tool` compiles T6 GSC but its output bytecode differs from the original T6
compiler in ways that cause runtime failures:

- The script name hash (bytes 8–11) is left as `0x00000000` instead of the expected CRC
- Section layout and offsets differ from the original T6 compiler output

Even binary-patching the hash was not sufficient — the T6 runtime rejected the
decompile/recompile output entirely.

OAT's Linker has its own T6-targeted GSC compiler that produces byte-for-byte
compatible output. This is the same approach used by
[Jbleezy/BO2-Reimagined](https://github.com/Jbleezy/BO2-Reimagined).

When T6 loads an OAT-compiled script from `mod.ff`, the console log confirms:

```
Script source "maps/mp/zombies/_zm_weapons.gsc" loaded successfully from fastfile
```

("Script source" is T6's log term for a compiled `scriptparsetree` asset — it does
not mean raw text.)

---

## Critical rule: every function must be present

When `mod.ff` contains `_zm_weapons.gsc`, it **completely replaces** the base-game
version. Every function that other scripts call must exist in your override. If you
omit a function (e.g. `init()`), the T6 script linker will error on any caller:

```
**** Unresolved external : "init" with 0 parameters in "maps/mp/zombies/_zm.gsc" ****
```

**Never remove functions from an override script.** Only add or modify them.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| WSL / Linux terminal | Already set up if you're reading this |
| [OpenAssetTools](https://github.com/Laupetin/OpenAssetTools) | Compiled at `~/projects/OpenAssetTools` |
| Plutonium T6 | Installed on Windows |
| BO2 base game | Via Steam |

`gsc-tool` is **not required** for the FF build. OAT compiles the source directly.

### Compile OAT (one-time)

```bash
cd ~/projects/OpenAssetTools
build/premake5 --arch=x86_64 gmake
make -C build config=release_x64 -j$(nproc)
# binary lands at: build/bin/Release_x64/Linker
```

---

## Step 1 — Build and deploy the FF

```bash
cd ~/projects/t6-high-round-fix
./build_ff.sh
```

`build_ff.sh` does everything in one step:

1. Writes a temporary `zone_source/zm_hrp.zone` spec (two `script` entries)
2. Stages the patched `.gsc` source files into `$BUILD_DIR/raw/t6/maps/mp/zombies/`
3. Runs `OAT Linker` with `--load patch_zm.ff --load common_zm.ff` so OAT can
   resolve `#include` dependencies without bundling them in the output
4. Copies the resulting `mod.ff` to
   `%LOCALAPPDATA%\Plutonium\storage\t6\mods\zm_hrp\mod.ff`

Expected output:

```
staged patched source files for OAT compilation
linking (OAT compiles sources)...
built  mod.ff  (40K)  — OAT-native compiled scripts
deployed → /mnt/c/Users/<you>/AppData/Local/Plutonium/storage/t6/mods/zm_hrp/mod.ff
```

If your Plutonium path or username differs, edit `PLUTO_MOD` at the top of
`build_ff.sh`. If OAT is at a non-default path, set `OAT`:

```bash
OAT=~/tools/OpenAssetTools ./build_ff.sh
```

---

## Step 2 — Enable the mod in-game

1. Launch Plutonium T6 Zombies
2. Go to **Private Match → Select Mod** (in the lobby menu)
3. Choose `zm_hrp` and confirm

This only needs to be done once — Plutonium remembers the selection per game mode.

---

## Step 3 — Verify the fixes loaded

Drop the test scripts into your Plutonium scripts folder:

```
%LOCALAPPDATA%\Plutonium\storage\t6\scripts\zm\
  zm_diagnostics.gsc
  zm_test_il01.gsc
```

Start a solo zombies match, open the console (~), and run:

```
set fftest_cmd il01
```

**PASS:** `[FFTEST] IL-01 PASS — returned true, no freeze` in the console.  
**FAIL:** Server hangs ("Connection Interrupted") — the fix is not active.

For the entity-leak fix (EL-01):

```
set fftest_cmd el01
```

Then after some play near barrier windows:

```
set fftest_cmd status
```

**PASS:** `EL-01: ACTIVE (_lerp seen: N)` — patched `_zm_utility.gsc` is running.

---

## Repo files involved

```
ZM/Core/maps/mp/zombies/
  _zm_weapons.gsc        Patched source  (IL-01 idx++ fix, IL-02 loop bound)
  _zm_utility.gsc        Patched source  (EL-01 lerp link cleanup)
zone_source/zm_hrp.zone  OAT project spec (template; build_ff.sh writes a fresh copy)
build_ff.sh              Build + deploy automation (single command)
```

Build artifacts (gitignored):

```
/tmp/oat_hrp_build/
  zone_source/zm_hrp.zone    zone spec written by build_ff.sh
  raw/t6/maps/mp/zombies/    staged source files for OAT
  zone_out/zm_hrp/mod.ff     compiled output, copied to Plutonium mods folder
```

---

## How the zone spec works

`zm_hrp.zone`:

```
>game,T6
>name,mod

script,maps/mp/zombies/_zm_weapons.gsc
script,maps/mp/zombies/_zm_utility.gsc
```

- `>game,T6` — target is Black Ops 2.
- `>name,mod` — output file is named `mod.ff` (Plutonium's required filename for mods).
- `script,...` — T6 asset type for compiled GSC bytecode. OAT resolves the path
  under `--base-folder/raw/t6/`.
- `--load patch_zm.ff` — makes base-game assets available for `#include` resolution
  during compilation without bundling them in the output.

---

## Troubleshooting

**`error: OAT Linker not found`**  
OAT hasn't been compiled yet. See Prerequisites above.

**`**** Unresolved external : "init" ... in "_zm.gsc" ****`**  
Your override of `_zm_weapons.gsc` is missing the `init()` function. When you
override a script, it completely replaces the original — every function that other
scripts call must be present. Check that `init()` exists at the top of
`ZM/Core/maps/mp/zombies/_zm_weapons.gsc`.

**`Attempting to override asset ... from zone 'patch_zm' with zone 'mod'` (crash)**  
The zone spec includes a non-script asset (e.g. `soundbank,zmb_patch.all`). Remove it.
Only `script` and `rawfile` assets can be overridden via `mods/`.

**`A mod is required for custom maps` (crash)**  
A modified FF was placed in the `zone\` folder instead of `mods\`. Move
`mod.ff` to `%LOCALAPPDATA%\Plutonium\storage\t6\mods\zm_hrp\mod.ff`.

**FF built successfully but IL-01 test still hangs**  
1. Confirm `mod.ff` is in `mods\zm_hrp\`, **not** `zone\` or `scripts\zm\`.
2. Confirm the mod is **enabled** in-game (Private Match → Select Mod → zm_hrp).
3. Fully restart the game (not just `map_restart`).

**"Connection Interrupted" immediately on map load (not during IL-01 test)**  
A script in `mod.ff` has a compile-time error. Re-run `build_ff.sh` and watch
for errors in OAT's output. The game will connect normally once OAT reports
`Created zone "mod"` without errors.
