# Test Protocol

Exact steps for reproducing each test. Written so that blog readers and community members can independently verify every result.

## General Setup

1. Install Plutonium T6 (see [04-toolchain-setup.md](../04-toolchain-setup.md))
2. Compile and install the diagnostic script (`zm_diagnostics.gsc`) and stress test script (`zm_stress_test.gsc`)
3. Launch Plutonium, start a Solo zombies game on the target map
4. Diagnostic HUD should appear on screen

## Recording Data

For each test:
- Note the **date**, **map**, **player count**, and **exact script versions** loaded
- Screenshot the diagnostic HUD at key intervals (every 10 rounds, at crash, etc.)
- Copy any console output or error messages
- Record the **exact round and game time** when any anomaly occurs
- Save results to the appropriate file in `baseline/` or `patched/`

---

## Test 1: Entity Leak Curve (EL-01/02/03)

**Objective:** Prove that entity count increases monotonically over rounds, confirming entity leaks.

**Setup:** Solo game, Town (Tranzit Diner), diagnostics script only (no patches).

**Important:** The `/st ramp` command kills zombies artificially and skips round logic — it does NOT trigger entity leaks because zombies never complete their spawn/movement/death lifecycle. This test MUST be done with real gameplay.

**Steps:**
1. Start game, enable auto-logging: `set diag_arg 1` then `set diag_cmd log`
2. Play normally — kill zombies with weapons, let rounds end naturally
3. At round 5, take a manual snap: `set diag_cmd snap`
4. Continue playing through round 30+, snapping every 5 rounds
5. To maximise leak rate: kill zombies mid-movement (while they are walking/pathing) and mid-rise (as they emerge from the ground). Traps near barriers are ideal for this.
6. After session, pull `DIAG_SNAP AUTO R*` blocks from `games_mp.log`

**What to watch on the HUD:**
- `Ent Tally` — direct count of known classnames. May undercount, but any growth is meaningful.
- `Probe Min` — the floor of the entity headroom probe across all probes so far. This is the most sensitive leak indicator; a steadily decreasing `Probe Min` over rounds confirms leaks even if `Tally` looks stable.

**Note from initial testing:** Fast-forwarding through rounds with `st ramp` produces a flat entity count (confirmed R1→R50: tally stayed at 207). The leaks are lifecycle-dependent — they only accumulate with real zombie spawns, animations, and deaths.

**Expected result:** `Ent Tally` and/or `Probe Min` should show a positive slope over 30+ real gameplay rounds.

**Log file:** `baseline/entity-leak-curve.md`

---

## Test 2: Entity Ceiling Crash

**Objective:** Confirm that entity exhaustion causes the crash, and find the exact limit.

**Setup:** Solo game, Town, diagnostics + stress test scripts.

**Steps:**
1. Start game
2. Use stress test to spawn N `script_origin` entities (start with 800)
3. Play normally — the game starts with reduced entity headroom
4. Record the round at which the game crashes
5. Repeat with different starting entity counts (700, 900, 950) to triangulate the limit
6. Also try: spawn entities one at a time until `spawn()` returns undefined — log the count

**Expected result:** Game crashes earlier with more pre-filled entities. The ceiling should be near 1024.

**Log file:** `baseline/entity-ceiling-crash.md`

---

## Test 3: `has_attachment()` Infinite Loop (IL-01)

**Objective:** Confirm that `has_attachment()` freezes the server when called with a multi-attachment weapon where the target isn't the first attachment.

**Setup:** Solo game, any map, a test script that calls the function.

**Steps:**
1. Write a test script that calls `has_attachment("an94_zm+reflex+grip", "grip")` on game start (after a short delay)
2. Load the script and start a game
3. Observe whether the server freezes
4. Repeat with `has_attachment("an94_zm+reflex+grip", "reflex")` — should succeed (first attachment matches)
5. Repeat with `has_attachment("an94_zm", "grip")` — should succeed (no attachments, loop doesn't execute)

**Expected result:** Call with `"grip"` (second attachment) freezes the server. Other calls work fine.

**Log file:** `baseline/has-attachment-freeze.md`

---

## Test 4: Score Overflow (OF-02)

**Objective:** Confirm that `score_total` overflow breaks powerup drops.

**Setup:** Solo game, Town, diagnostics + stress test scripts.

**Steps:**
1. Start game, let diagnostics HUD load
2. Run `/st dropinc 100` — lowers the drop threshold so powerups trigger every ~100 points, making them frequent enough to visually confirm they stop after the overflow
3. Use `/st score 2147400000` to set near int32 max (only 83,647 points remain before overflow)
4. Monitor the diagnostic HUD's `ScoreTotal` and `Drop Inc` displays — both should reflect the new values immediately
5. Kill zombies normally (~83 kills at 1000 pts each) until `ScoreTotal` wraps to a large negative number on the HUD
6. Continue playing — verify whether any powerup drops occur in the 2–3 rounds after overflow

**Expected result:** Once `score_total` overflows, `curr_total_score > score_to_drop` is permanently false and no more powerups drop.

**Log file:** `baseline/score-overflow.md`

---

## Test 5: Powerup Increment Growth (OF-03)

**Objective:** Measure the exponential growth of `zombie_powerup_drop_increment` and confirm it reaches float precision limits.

**Setup:** Solo game, Town, diagnostics script.

**Steps:**
1. Start game, monitor `zombie_powerup_drop_increment` on diagnostic HUD
2. Record the value after every powerup drop
3. Plot the curve (should be exponential: value * 1.14 per drop)
4. Note when drops become noticeably less frequent
5. Continue until drops stop entirely (if reachable in reasonable playtime)

**Expected result:** The value grows at 1.14x per drop. After ~100+ drops, the spacing between drops becomes extreme.

**Log file:** `baseline/powerup-increment-growth.md`

---

## Test 6: Failsafe Recycling (IL-03)

**Objective:** Confirm that the failsafe zombie recycling creates an infinite loop at very high rounds where zombies are unkillable.

**Setup:** Solo game, Town, diagnostics + stress test scripts (no health cap patch).

**Steps:**
1. Start game
2. Use stress test to skip to round 200 (setting round number, health, and speed accordingly)
3. Let zombies spawn naturally
4. Observe the diagnostic HUD: watch `zombie_total`, `zombie_total_subtract`, and active zombie count
5. Do NOT kill zombies — let the failsafe timer (30s) trigger
6. Observe whether killed zombies are re-queued (zombie_total goes back up)
7. Time how long it takes for the pattern to become apparent

**Expected result:** Stuck zombies are killed by failsafe, re-queued, spawn again, get stuck again. The round never completes.

**Log file:** `baseline/failsafe-recycling.md`

---

## Patched Tests

After building the patches (Phase 3), re-run all 6 tests with the combined patch script loaded. Log results to `patched/` using the same filenames. The comparison between `baseline/` and `patched/` results is the core evidence for the blog's final post.

---

## Test 7: OF-03 Patched — Drop Increment Cap

**Objective:** Confirm that `zm_patch_overflow.gsc` successfully caps `zombie_powerup_drop_increment`
at 50,000 and that powerup drops continue working after the cap fires.

**Setup:** Solo game, Town, `zm_diagnostics.gsc` + `zm_patch_overflow.gsc` + `zm_stress_test.gsc`.
Do NOT load the entity leak patch — isolate OF-03 behavior.

**Steps:**
1. Start game; confirm `[OFP] Overflow patch v1.0 loaded` banner appears.
2. Run `set st_cmd dropinc 100` — lowers drop threshold so powerups fire frequently (visual confirmation they work pre-cap).
3. Collect one powerup to confirm drops are live.
4. Run `set st_cmd "dropinc 44000"` — sets increment near the 50k ceiling.
5. Collect the next powerup. Base game multiplies: 44000 × 1.14 ≈ 50,160 > cap.
6. Within 1s: confirm `[OFP] Drop increment clamped at 50000` fires on screen and in log.
7. Watch `Drop Inc` on diagnostic HUD — should read ≤50,000 after clamp.
8. Collect 2–3 more powerups over 2+ rounds. Confirm drops continue landing.

**Expected result:** Clamp fires, drops continue. `Drop Inc` stays ≤50k. No cessation of drops.

**Log file:** `patched/powerup-increment-growth.md`

---

## Test 8: EL-01 Extended Soak — Hypothesis A vs B

**Objective:** Determine whether `lerp()` anchor entities actually persist in the engine pool
(Hypothesis A — real leak) or are auto-cleaned when the zombie entity is freed
(Hypothesis B — engine GC handles it). This resolves whether the FF file replacement
is critical for stability or merely a belt-and-suspenders cleanup.

**Setup:** Solo game, Town, `zm_diagnostics.gsc` + `zm_stress_test.gsc` ONLY.
**Do NOT load `zm_patch_entity_leaks.gsc`** — this is a control run to observe unpatched behavior.

**Steps:**
1. Confirm `[ELP]` banner does NOT appear (patch absent).
2. Note R1 entity tally and `Probe HR` from the diagnostic HUD.
3. Enable god mode: `set st_cmd god`
4. Arm elpkill: `set st_cmd elpkill` — kills every zombie within 50ms of spawn (mid-anchor window).
5. Let the game run autonomously for 25+ rounds. Do not intervene.
6. After each round, the server log records:
   `[ST] elpkill RN ent=X anchors_freed_this_round=-- total_freed=-- ELP=off`
7. Diagnostics auto-snaps fire every 5 rounds and record `Probe HR` and `Probe Min`.
8. Collect all `[ST] elpkill RN` lines and all `DIAG_SNAP [AUTO RN]` blocks from `games_mp.log`.

**Interpreting results:**
- `Ent Tally` growing +10–20 per round → Hypothesis A confirmed (real persistent leak)
- `Ent Tally` flat at ~207 through R25 → Hypothesis B confirmed (engine auto-cleanup)
- `Probe HR` degrading below 100 by R25 → Hypothesis A (real pool pressure)
- `Probe HR` stable >128 through R25 → Hypothesis B (no pool pressure)

**Impact:** If A, the FF replacement (EL-01 fix) is the highest-priority remaining work.
If B, the combined addon patch is sufficient and the time limit ceiling is already
effectively resolved on all maps.

**Log file:** `patched/el01-extended-soak.md`

---

## Test 9: Anim Info Ceiling (GR-AI-01)

**Objective:** Find the engine's anim info table size — the maximum number of entities that can hold a concurrent `animscripted` entry before the `exceeded maximum number of anim info` error fires.

**New command:** `set st_cmd animsat <N>` — forces N live Origins zombies into `animscripted` state simultaneously and holds them there. `set st_cmd animstop` releases all held entries.

**Setup:** Solo game, `zm_origins`. `zm_diagnostics.gsc` + `zm_stress_test.gsc`. God mode enabled. Skip to a round where enough zombies exist (R5+, so at least 12 are alive).

**Calibration step (run once before the table tests):**
The `animsat` command uses `"zm_walk"` as the default ASD state for Origins basic zombies. Before running the fill sequence, run `set st_cmd animsat 1` and confirm the targeted zombie freezes in its walk animation. If it does not (no visible change), the state name needs updating. Valid fallbacks to try: `"zm_run"`, `"zm_sprint"`. Update the `ANIMSAT_STATE` define in `zm_stress_test.gsc` once the correct name is confirmed.

**Steps:**
1. Start game, skip to R5: `set st_cmd skip 5`
2. Enable god mode: `set st_cmd god`
3. Note baseline on diagnostic HUD (`Probe HR`, entity tally)
4. Run `set st_cmd animsat 4` — hold 4 zombies
5. Confirm on HUD: `AnimSat` row shows 4
6. Run `set st_cmd animstat` — prints current animsat count to console
7. Increment by 2 each step: `animsat 6`, `animsat 8`, `animsat 10`, ...
8. Between each step, run `animstat` and check for `[ST] animsat: ERROR` messages in console
9. Stop when the game crashes or the engine prints the anim info error
10. Record N-2 as the confirmed safe maximum and N as the crash threshold
11. Repeat from step 3 twice to confirm (crash threshold should be consistent)

**After each `animsat <N>` call:** Run `set st_cmd animstop` to release all entries before the next increment. Then reissue `animsat <N+2>` fresh.

**What to watch:**
- Game crash or freeze = table exhausted at N
- Console output `[ST] animsat: animscripted failed on zombie X` = engine silently rejected the call (if T6 behaves this way)
- HUD `AnimSat` counter must match the requested N for the test to be valid

**Expected result:** Crash at some N between 8 and 32. Exact value unknown.

**Log file:** `baseline/anim-info-ceiling.md`

---

## Test 10: `getanimfromasd` Allocation Probe (GR-AI-02)

**Objective:** Determine whether calling `getanimfromasd` at runtime — without passing the returned handle to `animscripted` or any other function — allocates an anim info entry. If yes, the dead variable in `robot_walk_animation` leaks one entry per call at runtime.

**New command:** `set st_cmd animasd <N>` — calls `getanimfromasd` N times on a single zombie without consuming the result. Then attempts one controlled `animscripted` call as a canary and reports whether it succeeded.

**Setup:** Same as Test 9. Run Test 9 first to know the ceiling K.

**Steps:**
1. Start game, skip to R5, enable god mode
2. Run Test 9 to confirm ceiling K (e.g., K = 16)
3. Run `set st_cmd animsat <K-2>` — fill table to 2 below ceiling
4. Confirm `AnimSat` = K-2 on HUD
5. Run `set st_cmd animasd 1` — calls `getanimfromasd` once and then attempts one canary `animscripted`
6. Watch console for `[ST] animasd: canary animscripted OK` or `[ST] animasd: canary animscripted FAILED`
7. If OK: run `animstop`, then `animsat <K-1>`, then `animasd 1` again (now only 1 slot free)
8. If still OK at K-1 filled: `getanimfromasd` does NOT allocate — GR-02 is dead code only, not a leak
9. If FAIL at step 7: `getanimfromasd` allocates 1 entry when called — GR-02 is a real leak

**Variant — cumulative test:**
Run `animasd 10` (calls `getanimfromasd` 10× without consuming), then try `animsat 1`. If crash or failure, multiple calls compound.

**Expected result (most likely):** Canary succeeds regardless — `getanimfromasd` is a pure read-only lookup returning an integer handle, not an allocating call.

**Log file:** `baseline/getanimfromasd-allocation.md`

---

## Test 11: Origins Worst-Case Concurrent Overlap (GR-AI-03)

**Objective:** Reproduce the crash by forcing a three-robot round and a multi-generator capture event simultaneously. Confirms whether the peak concurrent count from the real game code exceeds the ceiling found in Test 9.

**New commands:**
- `set st_cmd roboforce` — sets the `three_robot_round` flag, causing `robot_cycling()` to send all 3 robots on their walk immediately at the next cycle
- `set st_cmd animoverlap` — calls `roboforce` then immediately triggers all 6 generators for capture (combines roboforce + gencap 6)

**Setup:** Solo game, `zm_origins`. All scripts loaded. Skip to R12 (recapture events active, mechz rounds active). God mode on. **Run without the GEN-ZC-01 fix** (load `zm_hrp` but temporarily disable the capture zones override if possible, or use a build without it).

**Steps (unpatched — GEN-ZC-01 bug active):**
1. Skip to R12: `set st_cmd skip 12`
2. Enable god mode: `set st_cmd god`
3. Note HUD baseline
4. Run `set st_cmd animoverlap`
5. Watch for crash. If no crash within 30s, run `set st_cmd genstat` to confirm capture zombies are active and `set st_cmd animstat` to see current count
6. Record whether crash occurs, and if so, at approximately what concurrent count

**Steps (patched — GEN-ZC-01 fix active):**
7. Repeat steps 1–6 with the GEN-ZC-01 fix active
8. Record whether the fix alone prevents the crash in this scenario

**Interpreting results:**
- Crash unpatched + no crash patched → GEN-ZC-01 fix is sufficient mitigation; generator captures are the amplifier
- Crash in both states → ceiling is below the patched peak count (~10–14); additional fixes needed
- No crash in either state → ceiling is above 14; crash has a different trigger

**Log file:** `baseline/anim-info-concurrent-peak.md`

---

## Test 12: `play_melee_attack_animation` Accumulation (GR-AI-04)

**Objective:** Determine whether capture zombies that complete `play_melee_attack_animation` normally (animation ends, loop exits) release their anim info entry — or whether a persistent leak accumulates from missing `stopanimscripted()`.

**Setup:** Same as Test 11. Run Test 9 first to know ceiling K.

**Steps:**
1. Start game, skip to R12, god mode on
2. Run `set st_cmd animsat <K-4>` — reserve 4 slots below ceiling (enough buffer to detect accumulation without crashing immediately)
3. Run `set st_cmd gencap 1` — trigger one generator capture; wait for it to complete (watch `genstat`)
4. After capture completes and all capture zombies are dead, run `set st_cmd animsat <K-4>` again
5. If the second `animsat` crashes with fewer zombies than the first, entries have leaked from the completed capture
6. Specifically: if first `animsat K-4` held OK, then after one capture, `animsat K-5` crashes → 1 slot was consumed and not freed
7. Repeat: trigger `gencap 1`, wait for completion, retry `animsat` with progressively fewer targets
8. Track how many slots are consumed per capture event

**Interpreting results:**
- Each completed capture event permanently consumes N slots → `play_melee_attack_animation` leaks; fix is `stopanimscripted()` at end of function
- Slot count is stable across capture events → natural animation completion properly frees entries; no leak

**Note:** Dead capture zombies should not hold entries since the entity is deleted. The leak would only occur for capture zombies that finish their animation while alive, survive the event, and then are killed after — though in practice all capture zombies are killed at event end. The more likely scenario is that entity deletion automatically frees anim info entries, making this a peak-count problem rather than an accumulation problem. Test 12 confirms which it is.

**Log file:** `baseline/anim-info-accumulation.md`

---

## Test 13: Robot Walk Segment-Index Leak (GR-AI-05)

**Objective:** Determine whether calling `animscripted(entity, origin, angles, state, N)` with a new segment index N while a previous entry for index N-1 is still active allocates a second anim info entry. If yes, each robot walk cycle leaks 2 entries (3 calls, only last freed by `stopanimscripted`), explaining the 26–27 hour accumulation crash.

**New commands:**
- `set st_cmd animindex 3` — calls `animscripted` with indices 0, 1, 2 on one zombie then `stopanimscripted`. Mirrors one robot walk segment sequence.
- `set st_cmd animleakrate 20` — repeats the above 20 times. Used to measure accumulated leak after N simulated walk cycles.

**Setup:** Solo game, `zm_origins`. All scripts loaded. R5+, god mode on. At least 1 zombie alive.

**Part A — Single cycle probe:**

1. Skip to R5, god mode on
2. Run `set st_cmd animsat 20` — confirm 20 entries hold (baseline)
3. Run `set st_cmd animstop`
4. Run `set st_cmd animindex 3`
5. Immediately run `set st_cmd animsat 20`

**Interpreting Part A:**
- `animsat 20` succeeds → segment-indexed calls replace existing entry; **no leak per cycle**
- `animsat 20` crashes → entries were not replaced; **2 leaked entries from the 3-call sequence** (GR-05 confirmed)

**Part B — Accumulated rate (if Part A crashes):**

1. Reload map (clean table state)
2. `animsat 20`, `animstop` — confirm baseline
3. `animleakrate 5` — 5 simulated walk cycles
4. `animsat 18` — should succeed (20 - 2×5 = 10 leaked, so only 10 left... crash at 18?)
5. Probe down: try `animsat 15`, `animsat 12`, etc. until one succeeds
6. Leaked entries = 20 - largest N that succeeds
7. Divide by 5 = entries leaked per cycle

**Expected result (if GR-05 confirmed):** 2 leaked entries per 3-call sequence. After 5 simulated walks, only ~10 free slots remain in the table.

**Log file:** `baseline/robot-walk-segment-leak.md`
