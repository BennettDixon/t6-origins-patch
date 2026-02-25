# IL-01 Test Result: `has_attachment()` Infinite Loop Fix

**Date:** 2026-02-20  
**Status: PASS**

---

## Bug

`has_attachment(weaponname, att)` in `_zm_weapons.gsc` had a `while` loop that never
incremented its index variable `idx`. If the weapon had more than one attachment
segment and the target attachment wasn't the first, the loop spun forever, hanging
the GSC VM (single-threaded, no preemption). The server reported "Connection
Interrupted" to all clients.

```gsc
// Original (broken)
while ( split.size > idx )
{
    if ( att == split[idx] )
        return true;
    // idx never incremented — hangs if att != split[1]
}
```

---

## Fix

Added `idx++` inside the loop body:

```gsc
while ( split.size > idx )
{
    if ( att == split[idx] )
        return true;
    idx++;  // IL-01 fix
}
```

**Delivery:** `mod.ff` built by OAT Linker from patched source, deployed to
`%LOCALAPPDATA%\Plutonium\storage\t6\mods\zm_hrp\mod.ff`.

---

## Test

In-game console command:

```
set fftest_cmd il01
```

The test script calls `has_attachment("m16_zm+acog+fmj", "acog")` — a weapon
string with two attachments where the loop must iterate past the first segment.
On the original code this hangs. On the patched code it returns `true` and
the test continues.

---

## Result

```
[FFTEST] IL-01 PASS — returned true, no freeze
```

Confirmed in-game on Plutonium T6, map `zm_transit`, 2026-02-20.

---

## Toolchain lessons learned during development

Getting the FF working required several iterations. Key findings:

1. **`gsc-tool` produces incompatible bytecode.** Its compiled output has wrong
   section offsets and a zero script name hash (bytes 8–11). T6 loads the bytes
   but cannot perform cross-script linking, causing "Unresolved external" errors.
   Binary-patching the hash was not sufficient because the section layout also
   differed.

2. **OAT's internal GSC compiler is the correct tool.** OAT's Linker compiles
   `.gsc` source files with its own T6-targeted compiler, producing native-format
   bytecode. This is confirmed by T6's load log: `Script source "..." loaded
   successfully from fastfile` ("Script source" is T6's term for a compiled
   `scriptparsetree` asset, not raw text).

3. **Every function in the original must be present in the override.** When
   `mod.ff` contains a script, it *completely replaces* the base-game version.
   `init()` was accidentally removed from our `_zm_weapons.gsc` override during
   development. Since `_zm.gsc::init()` calls `_zm_weapons::init()`, this produced
   `**** Unresolved external : "init" in "maps/mp/zombies/_zm.gsc" ****` — even
   though our scripts themselves loaded cleanly. Restoring `init()` resolved the
   crash immediately.

4. **Deploy to `mods/`, not `zone/`.** `zone/` adds new zones but cannot override
   existing assets from core zones like `patch_zm`. `mods/zm_hrp/mod.ff` is the
   correct path. Plutonium's asset override mechanism only applies from the mods
   folder.
