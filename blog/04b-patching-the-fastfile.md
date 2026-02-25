# Patching a Compiled Game Function in Black Ops 2

*An addendum to Part 4. The previous post ended with "The distribution mechanism
doesn't yet exist." It now does. This is the story of how.*

---

At the end of Part 4, `has_attachment()` was the one bug we confirmed, fixed, and
couldn't ship. The fix was one line — `idx++` — but the function lives inside a
compiled `.ff` archive that ships with the game, and our addon scripts load into a
completely separate namespace. Every attempt to intercept the base game's calls had
failed.

Then we figured it out.

---

## What We Were Up Against

To understand why this was hard, a quick primer on how BO2's scripts work.

When Treyarch shipped BO2, they compiled their 2,000+ GSC source files into bytecode
and packed them into `.ff` (fast-file) archives. The file we cared about —
`_zm_weapons.gsc` — ended up in `patch_zm.ff`, which loads at game startup.

The compiled bytecode for each script includes a function table. Cross-script calls
are resolved at load time using a combination of the script path hash and a function
name hash. When `_zm.gsc` calls `has_attachment()`, it does so via a compile-time
reference baked into the bytecode — not a runtime lookup through a string table you
could intercept.

This is why the addon script approaches all failed:

**Attempt 1: Function shadowing.** Define our own `has_attachment()` in an addon
script with the same name. The engine would find it, right? Wrong. T6 resolves
function calls by script path hash + function hash. Our addon has a different path
hash. The base game's call to `_zm_weapons::has_attachment` goes to `_zm_weapons`,
not to our script. We got:

```
**** Unresolved external: "has_attachment" with 2 parameters in "" at lines [,1,1] ****
```

**Attempt 2: Function pointer override.** Swap out `level.weaponUpgrade_func` or
similar. There is no such pointer. The `_zm_weapons.gsc` PaP system is
self-contained. No externally accessible hooks anywhere near `has_attachment`.

**Attempt 3: Raw script placement.** Put a compiled `_zm_weapons.gsc` in the
Plutonium scripts directory. The engine loaded it without complaint, but it didn't
replace anything. The FF-compiled version was already loaded and its symbols were
already in the table. Our script ran in parallel.

The only path forward was to get our version of `_zm_weapons.gsc` inside the FF
itself — replacing the original at load time, before `_zm.gsc` resolves its
references.

---

## BO2 Has No Mod Tools

The first thing we looked for was an official route. Treyarch shipped mod tools for
Black Ops 1 and Black Ops 3 on Steam. These include a tool called ZoneBuilder that
takes a `.zone` spec file and outputs a `.ff` archive with any assets you specify.

BO2 never got them. It ships on Steam as a single executable with no tools package.
The documentation we'd seen for FF construction assumed either BO1 or BO3. The BO2
path required something else.

---

## Finding OpenAssetTools

The community-built equivalent is
[OpenAssetTools](https://github.com/Laupetin/OpenAssetTools) — an open source tool
for reading and writing CoD asset archives, with BO2 (T6) support. Its `Linker`
binary takes a zone spec and produces a `.ff`. Its `Unlinker` can extract one.

The zone spec format is straightforward:

```
>game,T6
>name,mod

script,maps/mp/zombies/_zm_weapons.gsc
script,maps/mp/zombies/_zm_utility.gsc
```

And the resulting `mod.ff` goes in Plutonium's `mods/zm_hrp/` folder rather than
the base game's `zone/` folder. (That distinction matters — `zone/` adds new
content; only `mods/` can override existing assets from base-game zones.)

We had a build script. We had the tool. We thought we were close.

---

## The First Compiler Mistake

The obvious approach: compile our patched source with
[gsc-tool](https://github.com/xensik/gsc-tool), pack the output into the FF.
`gsc-tool` is the standard decompiler/compiler for T6 GSC — it had produced our
source files from the original binaries in the first place.

Recompile, pack, deploy. Game crash:

```
**** Unresolved external : "init" with 0 parameters in "maps/mp/zombies/_zm.gsc" at line 1 ****
```

We spent time diagnosing this. The crash message is misleading — it sounds like
`_zm.gsc` is missing its `init` function, but `_zm.gsc` is unmodified. What it
actually means is that `_zm.gsc` failed to resolve one of its *own* cross-script
calls during the link phase.

We diff'd the compiled output against the original binary. Two differences:

1. The script name hash at bytes 8–11 was `0x00000000` in gsc-tool's output.
   The original had a CRC — `1db784f2` for `_zm_weapons.gsc`. T6 uses this field
   to identify scripts for cross-script linking. A zero hash means the linker can't
   find the script.

2. Beyond the hash, gsc-tool's section layout was different from the original T6
   compiler's output — different section offsets, different structure at 0x40.

We patched the hash in post (a Python script that wrote the correct bytes at offset
8). The crash continued. The section layout mismatch was a deeper problem — gsc-tool
and the original T6 compiler produce structurally different bytecode, and T6's
runtime linker couldn't reconcile them.

---

## The Key Insight from Jbleezy

Stuck, we looked at
[Jbleezy/BO2-Reimagined](https://github.com/Jbleezy/BO2-Reimagined) — a working BO2
Zombies overhaul mod that demonstrably modifies game behavior. If anyone had solved
this problem, it was this repo.

His `build.bat` doesn't use gsc-tool at all.

Instead, he passes **source `.gsc` files** directly to the OAT Linker via
`--add-asset-search-path`, and OAT compiles them internally. The compiled output goes
straight into the FF. No intermediate bytecode, no separate compiler step.

This is the detail that unlocked everything. OAT's Linker doesn't just pack
pre-compiled assets — it *has its own T6 GSC compiler* built in. When you hand it a
source file and list it as a `script` asset in the zone spec, it compiles it with
its own T6-targeted compiler and emits bytecode that is format-compatible with what
the original Treyarch compiler produced.

T6's load log confirms it:

```
Script source "maps/mp/zombies/_zm_weapons.gsc" loaded successfully from fastfile
```

"Script source" is T6's internal terminology for a loaded `scriptparsetree` asset —
compiled bytecode — not raw text. The scripts were loading. The cross-script linker
was happy with the format.

```
./build_ff.sh
[deploy mod.ff]
set fftest_cmd il01
[FFTEST] IL-01 PASS — returned true, no freeze
```

The loop that had been spinning since 2012 finally terminated.

---

## What the Working Pipeline Looks Like

The whole build is one script:

```bash
./build_ff.sh
```

Under the hood:

1. Write a zone spec listing `script` assets.
2. Copy the patched `.gsc` source files into OAT's asset search path.
3. Run `OAT Linker` with `--load` flags for each base-game FF needed. The `--load`
   flags give OAT access to base-game assets for `#include` resolution without
   bundling them in the output. OAT compiles the source files with its internal T6
   compiler.
4. Deploy the resulting `mod.ff` to
   `%LOCALAPPDATA%\Plutonium\storage\t6\mods\zm_hrp\mod.ff`.
5. Enable the mod in-game via the Private Match lobby.

The output is a single file containing all compiled script overrides. The rest of
each base-game FF loads normally from the originals. The mod is purely additive
except for the specific functions it replaces.

> *This post was written when the pipeline was first proven with two scripts from
> `patch_zm.ff`. The same pipeline now covers six scripts from three FFs
> (`patch_zm.ff`, `zm_tomb.ff`, `zm_highrise.ff`) in one build step — see the
> completed patch list in [Part 9](09-the-full-patch.md) and [Part 10](10-generators-patched.md).*

---

## The Current State

Both infinite-loop fixes and the entity-leak fix are now delivered via `mod.ff`:

| Bug | Fix | Status |
|---|---|---|
| IL-01: `has_attachment()` infinite loop | `idx++` inside while loop | ✅ Verified via `fftest_cmd il01` |
| IL-02: `random_attachment()` infinite loop | Bounded retry loop (max 30) | Deployed, pending explicit test |
| EL-01: `lerp()` entity leak | `_lerp_link` cleanup in `_zm_utility.gsc` | Deployed, pending extended soak |

The addon script patch (EL-02/03 anchor leaks, OF-01/02/03 overflow caps, SA-08/09
scrVar pruning) runs alongside the FF mod. Together they address all six root causes
we identified.

Part 5 covers what the numbers look like with everything running.

*All scripts, tests, and research are at [github.com/banq/t6-high-round-fix](#).*
