# GEN-ZC-01 / GEN-ZC-02 / GEN-ZC-03 Test Results: Origins Generator System

**Date:** _pending_  
**Status:** _pending_

---

## Bugs Found

### GEN-ZC-01 — `get_capture_zombies_needed(b_per_zone)` dead-variable assignment
`zm_tomb_capture_zones.gsc` line 779

Original: `b_capture_zombies_needed = n_capture_zombies_needed_per_zone`

`b_capture_zombies_needed` is never read anywhere in the file. `n_capture_zombies_needed` (the return variable) is not modified. The function always returns the total count regardless of `b_per_zone`. The correct line is `n_capture_zombies_needed = n_capture_zombies_needed_per_zone`.

Consequence: `set_capture_zombies_needed_per_zone()` always sets each contested zone's `capture_zombie_limit` to the TOTAL zombie quota, not the per-zone allocation. During multi-zone captures:

| Active contests | Intended limit/zone | Actual limit/zone (buggy) |
|---|---|---|
| 1 | 4 | 4 (same — no difference) |
| 2 | 3 | 6 (2×) |
| 3 | 2 | 6 (3×) |
| 4 | 2 | 8 (4×) |

Each generator's `monitor_capture_zombies` loop calls `spawn_zombie` every 0.5 seconds until its inflated limit is reached. After the 6-slot AI budget is filled by the combined spawns, subsequent calls hit the limit but the loop continues polling.

### GEN-ZC-02 — `ignore_player[]` never cleared on recapture zombie reassignment
`zm_tomb_capture_zones.gsc` lines 1216–1240

Recapture zombies maintain `self.ignore_player[]` — a list of players too close to the current target generator to merit the zombie attacking the generator. When `set_recapture_zombie_attack_target()` redirects zombies to a new generator between recapture phases, `ignore_player` is not cleared. Disconnected players leave permanent entries.

### GEN-ZC-03 — Off-by-one in attack point index range
`zm_tomb_capture_zones.gsc` lines 1124–1135, 1137–1148

`get_unclaimed_attack_points_between_indicies(n_start, n_end)` uses `i < n_end`. With the 12-point layout (0–3, 4–7, 8–11), callers passing `(0,3)`, `(4,7)`, `(8,11)`, and `(0,11)` never see index 11. Attack point 11 is permanently unused.

---

## Prerequisites

- Map: `zm_origins`
- Mod: `zm_hrp` enabled (Private Match → Select Mod)
- Scripts loaded: `zm_diagnostics.gsc`, `zm_stress_test.gsc`
- Note: all three bugs are in `zm_tomb.ff` and cannot be patched from an addon script. These tests establish baseline behavior only; no patched control is available unless `zm_tomb.ff` is replaced.

---

## GEN-ZC-01 Test Procedure

**Goal:** Confirm that multi-zone captures cause inflated `capture_zombie_limit` values and sustained spawn polling after the AI budget is exhausted.

**Observable metric:** The `SV` counter in the HRP HUD (top right) and the entity headroom counter (HR). During a two-zone simultaneous capture, both should show elevated pressure compared to a single-zone capture.

**Baseline (single-zone capture):**

1. Load `zm_origins`. Skip to R5: `set st_cmd skip 5`
2. Activate only one generator. Observe `SV` and `HR` values.
3. Note: single-zone captures call `get_capture_zombies_needed(1)` and get the right answer for 1 zone (both total and per-zone = 4) — so GEN-ZC-01 has no effect with 1 active zone.
4. Record `SV` and `HR` at start of capture, peak during capture, and after capture completes.

**Multi-zone capture (bug active):**

1. Skip to R10: `set st_cmd skip 10`
2. Enable god mode: `set st_cmd god`
3. Simultaneously activate two generators (requires 2 players, or use `set st_cmd skipgencap 2` if available)
4. Observe `SV` and `HR` values. With 2 zones, each zone's `capture_zombie_limit` = 6 instead of 3.

**Expected (unpatched — bug present):**
- Peak SV during 2-zone capture is noticeably higher than single-zone
- `HR` shows more entity churn (entities allocated and freed in rapid succession)
- After captures complete, SV and HR return to baseline (entries are cleaned up; no permanent leak)

**Pass criteria:**
- 2-zone capture shows higher SV than single-zone proportionally (>1.5× spike duration)
- Spawn attempts visible in `zm_diagnostics.gsc` output (if spawn call logging is enabled) exceed 6 total during the combined capture event

---

## GEN-ZC-02 Test Procedure

**Goal:** Confirm that `ignore_player[]` entries from generator A persist on recapture zombies after they are redirected to generator B.

**Observable behavior:** During a recapture event that moves from generator A to generator B:
- Unpatched: zombies redirected from A to B still have A's player-proximity context; they may immediately attack B's generator even when players are standing at B (because those players were ignored near A)
- Patched: zombies start fresh at B, correctly deferring to players if they're nearby

Since this is a behavioral/gameplay test and the fix isn't available from addon, this is a qualitative observation.

1. Load `zm_origins`. Skip to R12: `set st_cmd skip 12` (recapture events start at R10)
2. Enable god mode: `set st_cmd god`
3. Capture 4+ generators to trigger recapture events
4. Wait for a recapture event to start
5. Stand near generator A while recapture zombies attack it
6. Observe when recapture zombies transition to generator B — do they immediately attack B's pillar even with you standing next to it?

**Expected (unpatched):**
- Recapture zombies that "ignored" you near A continue doing so near B for up to 0.5 seconds until the next `should_capture_zombie_attack_generator()` poll

---

## GEN-ZC-03 Test Procedure

**Goal:** Confirm that attack point index 11 is never claimed by any recapture zombie.

**Observation:** Add temporary instrumentation to log `attacking_point` indices. Requires modifying `init_recapture_zombie` or `get_unclaimed_attack_point` in an FF replacement build.

Without instrumentation, this is a static analysis finding only — the off-by-one is deterministic from code inspection.

---

## Results

### GEN-ZC-01 — Inflated capture zombie spawn limit

| Condition | Active zones | SV peak | HR drop | Duration of elevated pressure |
|---|---|---|---|---|
| Single-zone capture | 1 | _ | _ | _ |
| Multi-zone capture | 2 | _ | _ | _ |
| Multi-zone capture | 3 | _ | _ | _ |

Notes: _

**GEN-ZC-01 verdict:** _PASS / FAIL_

---

### GEN-ZC-02 — `ignore_player[]` stale entries

| Condition | Behavior at redirect | `ignore_player` cleared? |
|---|---|---|
| Unpatched (baseline) | _ | _ |

Notes: _

**GEN-ZC-02 verdict:** _BEHAVIORAL OBSERVATION ONLY_

---

### GEN-ZC-03 — Off-by-one in attack point range

| Condition | Attack point 11 ever claimed? |
|---|---|
| Static analysis | No — index excluded by `i < n_end` |
| Runtime (instrumented) | _ |

Notes: _

**GEN-ZC-03 verdict:** _STATIC ANALYSIS CONFIRMED — runtime instrumentation pending_

---

**Overall:** _PENDING_
