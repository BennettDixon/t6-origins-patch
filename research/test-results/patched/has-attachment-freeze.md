# Test IL-01 (Patched): has_attachment() Infinite Loop

**Patch:** `zm_patch_loops.gsc v1.1` — function pointer override approach + `safe_has_attachment()` helper.

**Baseline result (unpatched):** `has_attachment("an94_zm+reflex+grip", "grip")` froze the server — 1300ms + 766ms hitch warnings, Plutonium process became "Not Responding", "Connection Interrupted" screen.

## Run Metadata

| Field           | Value |
|-----------------|-------|
| Date            | 2026-02-19 |
| Map             | zm_transit / Town (gump_town) |
| Player count    | Solo |
| Plutonium build | r5246 |
| Script versions | zm_test_il01.gsc v1.0, zm_patch_loops.gsc v1.1 |
| Patch scripts   | zm_patch_loops.gsc |

---

## Critical Discovery: GSC Function Resolution in Plutonium T6

This test revealed a fundamental architectural constraint that changes how we can approach all GSC-level fixes.

### Attempt 1 — Function shadowing (v1.0, FAILED)

**Hypothesis:** Define `has_attachment()` in `zm_patch_loops.gsc`. Plutonium loads all scripts into a shared global namespace, so our definition would shadow the buggy one in `_zm_weapons.gsc`.

**Test result with `#include _zm_weapons` in test script:**
- Plutonium process did NOT crash (improved over baseline)
- "Connection Lost" screen appeared (non-fatal server disconnect)
- Player could still move around after disconnect

This partial success suggested the shadow was interfering but not cleanly overriding.

**Test result after removing `#include _zm_weapons` from test script:**

![Unresolved external error](il01-unresolved-external.png)

```
**** 1 script error(s):
**** Unresolved external: "has_attachment" with 2 parameters in "" at lines [,1,1] ****
```

The engine couldn't find `has_attachment()` at all — even though `zm_patch_loops.gsc` defines it.

### What the error proves

**Plutonium T6 GSC uses compile-time, namespace-scoped function resolution. There is no global function table.**

| Resolution method | Works? | Notes |
|------------------|--------|-------|
| `#include file` | ✅ | Links to that file's functions at compile time |
| `scriptfile::function()` | ✅ | Explicit qualified call |
| Same-name definition in custom script | ❌ | Only available to scripts that include YOUR file |
| Global function override | ❌ | Does not exist in this engine |

When a script includes `_zm_weapons`, the compiled bytecode contains a hard reference to `_zm_weapons::has_attachment`. No external definition can intercept that reference. Our `zm_patch_loops::has_attachment` exists in a separate namespace that the engine doesn't expose globally.

**Base game scripts that call `has_attachment()` do so via `_zm_weapons` includes baked in at compile time. We cannot intercept those calls from a standalone add-on script.**

### Attempt 2 — Function pointer override (v1.1, CURRENT)

The only hooks available to add-on scripts are:
1. **`level.` function pointers** — set during init, callable via `[[ level.func_ptr ]]()`, overridable in our `init()`
2. **Level notification events** — `waittill("event")` to react after the fact

`zm_patch_loops.gsc v1.1` hooks `level.weaponUpgrade_func` (if defined) to wrap the PaP upgrade call chain. However, without decompiled source confirming the exact pointer name used by `_zm_weapons.gsc`'s upgrade path, this hook may not intercept the specific code path that calls `has_attachment()`.

**Additionally, `safe_has_attachment()` and `safe_random_attachment()` are provided as correct implementations for use by custom scripts that `#include zm_patch_loops`.**

---

## Test Results (v1.1)

| Check | Expected | Actual |
|-------|----------|--------|
| `[LLP]` banner on load | `[LLP] Loop patch v1.1 loaded` | **CONFIRMED — no unresolved external error** |
| `weaponUpgrade_func` hook | `[LLP] weaponUpgrade_func hook installed` | **`weaponUpgrade_func not defined at init time`** — pointer does not exist |
| `/il01 freeze` — server freeze | N/A — see note below | "Connection Interrupted" (still freezes) |

**Server log confirms:**
```
0:00 [LLP] Loop patch v1.1 init
0:00 [LLP] weaponUpgrade_func not defined at init time
```

`level.weaponUpgrade_func` does not exist in `_zm_weapons.gsc`. The guessed pointer name was wrong. The PaP upgrade system has **no externally-accessible function pointer** — it is entirely self-contained within `_zm_weapons.gsc`. There is no hook point for add-on scripts.

**Why the test still freezes:** `zm_test_il01.gsc` calls `has_attachment()` directly via its compile-time `#include _zm_weapons` link. Even if a pointer existed, the test hits the bug head-on and cannot be used to validate any pointer-based fix.

---

## Summary: What Can vs Cannot Be Fixed from Add-On GSC

| Approach | Intercepts base game calls? | Result |
|---------|----------------------------|--------|
| Function shadowing (same name) | ❌ No — namespace-scoped, not global | **Ruled out — confirmed by "Unresolved external" error** |
| Function pointer override (`level.X`) | ✅ Yes — but only if a pointer exists | **Ruled out — `weaponUpgrade_func` does not exist** |
| `safe_has_attachment()` helper | ✅ Yes — for custom scripts that include our file | **Implemented and available** |
| Direct `_zm_weapons.gsc` replacement | ✅ Yes — full guaranteed fix | **Required for complete fix** |

## Conclusion (Attempts 1 + 2)

**IL-01 cannot be fixed from a standalone add-on GSC script.** Two approaches were exhausted:

1. **Function shadowing (v1.0):** Plutonium T6 resolves function calls at compile time per namespace. A same-name definition in a custom script is not globally visible — confirmed by `Unresolved external: "has_attachment"` error when the include was removed.

2. **Function pointer override (v1.1):** The PaP upgrade system in `_zm_weapons.gsc` is entirely self-contained with no externally-accessible `level.` function pointers — confirmed by `weaponUpgrade_func not defined at init time` in server log.

**The only complete fix is a modified `_zm_weapons.gsc`** with a single `idx++` added to the `has_attachment()` while-loop. This requires distributing the modified base file alongside the add-on scripts.

`zm_patch_loops.gsc` is retained and provides `safe_has_attachment()` / `safe_random_attachment()` for any future custom scripts that need safe attachment checking.

**Practical risk note:** In standard BO2 zombies, weapon names with multiple "+" tokens are uncommon (most zombie weapons are `weaponname_zm` or `weaponname_zm_upgraded`). The crash is a hard-freeze when triggered, but the trigger conditions may be rarer than initial static analysis suggested. The health cap (OF-01 fix) also reduces PaP usage pressure at high rounds.

---

## Attempt 3 — Direct `_zm_weapons.gsc` replacement (PENDING TEST)

**Source:** `ZM/Core/maps/mp/zombies/_zm_weapons.gsc` — the full decompiled base game script is in the repo source tree.

**Fixes applied:**

### IL-01: `has_attachment()` — added `idx++`

```gsc
// BEFORE (line ~1735 in source):
while ( split.size > idx )
{
    if ( att == split[idx] )
        return true;
    // ← idx never incremented: infinite loop when att != split[1]
}

// AFTER:
while ( split.size > idx )
{
    if ( att == split[idx] )
        return true;
    idx++;
}
```

### IL-02: `random_attachment()` — bounded loop guard

```gsc
// BEFORE:
while ( true )
{
    idx = randomint( attachments.size - lo ) + lo;
    if ( !isdefined( exclude ) || attachments[idx] != exclude )
        return attachments[idx];
}

// AFTER:
tries = 0;
while ( tries < 30 )
{
    idx = randomint( attachments.size - lo ) + lo;
    if ( !isdefined( exclude ) || attachments[idx] != exclude )
        return attachments[idx];
    tries++;
}
```

**Build:** `build.sh` compiles `_zm_weapons.gsc` as a game override; output goes to `compiled/t6/_zm_weapons.gsc` (45 KB).

**Deploy:** `deploy.sh` / `deploy.ps1` now copy all `_*.gsc` files alongside `zm_*.gsc` to `%LOCALAPPDATA%\Plutonium\storage\t6\scripts\zm\`.

**Expected behavior if Plutonium supports same-name script replacement:**
- No "Connection Interrupted" screen on `/il01 freeze`
- Server stays responsive, no hitch warnings
- `has_attachment("an94_zm+reflex+grip", "grip")` returns `true` without freezing

**Expected behavior if Plutonium does NOT support replacement (loads both):**
- Possible function redefinition error at startup visible in console
- Or existing behavior unchanged (base version wins)

### Test results (2026-02-19)

| Check | Expected | Actual |
|-------|----------|--------|
| Game loads without script errors | No console errors | **CONFIRMED — no duplicate ClientField error** |
| `safe_has_attachment()` variants | Instant result, correct bool | **CONFIRMED — result=1 and result=0 both correct, no freeze** |
| `/il01 freeze` — no server freeze | No hitch warning | **FAILED — Connection Interrupted, same as baseline** |

**Server log:**
```
0:43 IL01 variant_a START
0:43 IL01 variant_a DONE result=1    ← safe_has_attachment() correct
0:43 IL01 variant_b START
0:43 IL01 variant_b DONE result=0    ← safe_has_attachment() correct
0:43 IL01 safe_variants_complete
[freeze variant → Connection Interrupted, no DONE log entry]
```

### Why Attempt 3 also fails

Removing `init()` from the raw file prevents the duplicate ClientField error (the game loads), but does not make the raw `has_attachment()` override the FF version.

Scripts compiled against FF `_zm_weapons` (via `#include maps\mp\zombies\_zm_weapons`) have a **compile-time hardcoded reference** to `_zm_weapons::has_attachment` in the FF namespace. Plutonium's raw loader adds our compiled script to the namespace **alongside** the FF version — it does not replace it. The FF version's function remains the one that all FF-compiled code calls.

This means:
- Our raw `has_attachment()` is **never called by any FF-compiled script** — including the PaP upgrade system in `_zm_weapons.gsc` itself
- `zm_test_il01.gsc` uses `#include _zm_weapons` (FF link) so the freeze variant still calls the FF buggy function
- Only custom scripts that `#include zm_patch_loops` can call our safe version

---

## Final Verdict: IL-01 is Unfixable from an Add-on Script

All four approaches have been exhausted:

| Attempt | Approach | Result |
|---------|----------|--------|
| v1.0 | Function shadowing (same function name in addon) | ❌ Namespace-scoped — FF calls never reach it |
| v1.1 | `level.weaponUpgrade_func` pointer override | ❌ Pointer does not exist in `_zm_weapons.gsc` |
| v3a | Raw `_zm_weapons.gsc` with full `init()` | ❌ Duplicate ClientField registration crash |
| v3b | Raw `_zm_weapons.gsc` without `init()` | ❌ FF version wins all compile-time linked calls |

**The fix (`idx++` in `has_attachment()`) is correct and exists in source** at `ZM/Core/maps/mp/zombies/_zm_weapons.gsc`. It is ready to apply. But distributing it requires a method that replaces the compiled bytecode in the game's fast file (`.ff`), which is outside Plutonium's addon script mechanism.

**Practical risk in vanilla gameplay:** IL-01 triggers when the PaP upgrade system calls `has_attachment()` on a weapon with 3+ `+`-separated tokens (e.g. `an94_zm+reflex+grip`) and checks for an attachment that is NOT the first one. In standard BO2 zombies, most weapons are `weaponname_zm` or `weaponname_zm_upgraded`. PaP'd weapons with multiple inherited attachments are the trigger condition. The bug exists but the specific trigger conditions are less common at low-to-mid rounds.

**For end users:** `safe_has_attachment()` in `zm_patch_loops.gsc` is available for any custom map scripts that need correct attachment checking.
