# EL-01 Test Result: `lerp()` Entity Leak Fix

**Date:** 2026-02-20  
**Status: SYNTHETIC PASS — real-game soak pending**

---

## Bug

`lerp()` in `_zm_utility.gsc` spawns a `script_origin` into a local variable `link`
and moves the zombie to its barrier-attack position. The function has no
`self endon("death")`, so if the zombie is killed while blocked at
`waittill_multiple("rotatedone", "movedone")`, the engine force-terminates the
thread and `link` becomes permanently unreachable — never deleted, never freed
back to the entity pool.

```gsc
// Original (broken)
lerp( chunk )
{
    link = spawn( "script_origin", self getorigin() );
    // link is a LOCAL variable — if zombie dies mid-waittill, link leaks forever
    link.angles = self.first_node.angles;
    self linkto( link );
    link rotateto( ... );
    link moveto( ... );
    link waittill_multiple( "rotatedone", "movedone" );  // ← dies here → LEAK
    ...
    link delete();  // ← never reached
}
```

---

## Fix

Two-part fix:

1. **FF layer (`_zm_utility.gsc` override in `mod.ff`):** Store `link` on the entity
   as `self._lerp_link` before the blocking call, making it reachable from outside
   the thread:

```gsc
lerp( chunk )
{
    link = spawn( "script_origin", self getorigin() );
    self._lerp_link = link;  // EL-01 fix: expose link for death watchdog
    ...
    link waittill_multiple( "rotatedone", "movedone" );
    self unlink();
    self._lerp_link = undefined;
    link delete();
}
```

2. **Addon script (`zm_patch_entity_leaks.gsc`):** Per-zombie death watchdog checks
   `self._lerp_link` on zombie death and deletes it if still defined:

```gsc
elp_zombie_anchor_watchdog()
{
    self waittill( "death" );
    if ( isdefined( self._lerp_link ) )
    {
        self._lerp_link delete();
        self._lerp_link = undefined;
        level._elp_lerp_freed++;
    }
}
```

**Delivery:** `mod.ff` built by OAT Linker, deployed to
`%LOCALAPPDATA%\Plutonium\storage\t6\mods\zm_hrp\mod.ff`.

---

## Synthetic Tests (PASS)

Synthetic tests bypass the need for zombies to naturally reach barrier windows
by calling `lerp()` directly on live zombies with fabricated `first_node` and
`attacking_spot` fields.

### EL-01S: Single-zombie probe

```
set fftest_cmd el01s
```

Confirms two things independently:
- `_lerp_link` is set → patched `_zm_utility.gsc` FF override is active
- `_fftest_lerp_detected` increments → per-zombie watcher is installed and polling

**Result (2026-02-20, zm_transit):**
```
[FFTEST] EL-01S PASS — _lerp_link set AND watcher detected it
[FFTEST]   FF active + per-zombie watcher working correctly
```

### EL-01 Ramp: Multi-round automated leak test

```
set st_cmd el01ramp 20
```

Applies `lerp()` synthetically to every zombie each round, kills them mid-lerp,
and checks that `_elp_lerp_freed` increments by exactly the number of zombies
killed (`applied == freed`). Entity count should decrease each round (zombies
freed), never increase.

**Result (2026-02-20, zm_transit, R3 sample):**
```
[ST] EL01RAMP R3: applied=2 freed=2 ents=208->206
```

Green result (`applied == freed`) confirms the ELP watchdog is cleaning every
`_lerp_link` entity on mid-lerp zombie death.

---

## Outstanding: Real-Game Testing

The synthetic tests confirm the fix is mechanically correct. What they cannot
prove is long-session stability under real high-round gameplay conditions. The
following tests are still required.

### 1. EL-01 Ramp — Patched long run (20+ rounds)

**Goal:** Confirm `applied == freed` holds consistently, entity tally never
climbs, and the fix scales correctly to larger hordes at higher rounds.

**Method:**
```
set st_cmd god
set st_cmd el01ramp 20     ← or higher
```

**Pass criteria:**
- Every round: `freed == applied` (green output)
- `ents_before -> ents_after` decreasing or flat each round
- No `EL-01 PARTIAL` or `EL-01 FAIL` lines in log

**Blocking issue:** None — this test can be run today.

---

### 2. EL-01 Ramp — Control run (no ELP, no FF)

**Goal:** Confirm the leak is real and accumulates without the patch. Resolves
the open hypothesis in `el01-extended-soak.md` for the lerp-specific leak.

**Method:** Remove `zm_patch_entity_leaks.gsc` from Plutonium scripts folder.
Keep `mod.ff` loaded (or remove it for a fully unpatched baseline).

```
set st_cmd el01ramp 20
```

**Pass criteria (proving the leak exists):**
- Every round: `freed == 0` (ELP not loaded → nothing freed)
- `ents_before -> ents_after` increases by roughly `applied` each round
- After 20 rounds: entity tally ~`start + (avg_zombies_per_round × 20)`

**Note:** If entity tally stays flat even without ELP, the engine may
auto-clean thread-local entities on force-termination (Hypothesis B in
`el01-extended-soak.md`). This would mean EL-01 is a false positive.

---

### 3. Natural lerp detection at high rounds (R50+)

**Goal:** Confirm `lerp()` fires naturally in real gameplay at high rounds,
and that `_lerp_link` is detected and cleaned up without synthetic forcing.

**Method:**
```
set st_cmd god
set st_cmd lerpwatch       ← continuous: kills non-lerp zombies, watcher handles lerp ones
```

Stand near barrier windows (Town building windows, Origins sandbag barriers).
Run for 10+ minutes. Check `set fftest_cmd status` periodically.

**Pass criteria:**
- `_lerp_link seen: N` with N > 0 after ~10 minutes near barriers
- `lerp_freed` counter increments in the HUD (ELP watchdog firing naturally)

**Why high rounds:** At R50+, zombie density is high enough that several are
always approaching barriers simultaneously, making natural `lerp()` triggers
much more frequent than at early rounds.

**Blocking issue:** Requires a high-round session (~2–3 hours from R1, or use
`set st_cmd skip 50` to fast-forward).

---

### 4. Long-session stability soak (R100+)

**Goal:** Prove the entity pool stays flat over a long patched session where
`lerp()` fires naturally hundreds of times. This is the definitive validation
that EL-01 does not contribute to the entity exhaustion crashes seen at high rounds.

**Method:** Normal gameplay with all patches loaded. Run `zm_diagnostics.gsc`
alongside so entity tally and probe headroom are logged every 5 rounds.

**Pass criteria:**
- Probe headroom stays > 128 at R100+
- Entity tally trend flat (not growing)
- No `G_Spawn: no free entities` crash

**Blocking issue:** Requires a long session. This is the same soak described
in `el01-extended-soak.md` but with the patched FF active.

---

## Summary

| Test | Status | Date |
|------|--------|------|
| `el01s` — FF active + watcher installed | **PASS** | 2026-02-20 |
| `el01ramp` — `applied==freed` per round | **PASS (R3 sample)** | 2026-02-20 |
| `el01ramp` 20-round patched run | **PENDING** | — |
| `el01ramp` 20-round control (no ELP) | **PENDING** | — |
| Natural lerp detection R50+ via `lerpwatch` | **PENDING** | — |
| Long-session soak R100+ | **PENDING** | — |
