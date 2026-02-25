# How BO2 Zombies Slowly Runs Out of World

*Part 3 of the BO2 High-Round Crash Fix series. [Part 1 — The Archaeology](#) | [Part 2 — Building the Instrument Panel](#)*

---

For over a decade, Black Ops 2 zombies players have reported the same pattern: games that run for a long time eventually crash, but not at any predictable round. Some people crash at round 80. Others reach round 200. The crash seems random, except it isn't — experienced players noticed it correlates with **how aggressively you play**, not how long you survive.

Grenade launchers, traps, splash weapons near barriers. Long games with those strategies crash earlier. Long games with headshots-only, careful play crash later or not at all. And there's a third variant the community talks about less: the box cyclist. Someone who rolls the magic box hundreds of times across a very long session, chasing the right weapon. They crash too, but later, and sometimes with a different error.

Those three patterns are fingerprints of **two separate resource exhaustion bugs** — one in the entity pool, one in the script variable pool. This post is about finding both of them, testing them, being surprised by how wrong we were about the first one, and building patches for both anyway.

---

## What Is an Entity Leak?

The BO2 engine has a hard limit of **1024 game entities**. Every zombie, weapon, pickup, trigger, physics prop, and sound emitter consumes an entity slot. The game allocates a pool at startup and that pool never grows.

Most entities are transient: a zombie spawns (allocates), dies (frees), new zombie spawns. The pool breathes in and out. As long as frees keep up with allocations, you never hit the ceiling.

An entity **leak** happens when something allocates an entity but never frees it. The pool fills up one slot at a time, invisibly, until there's nowhere left for a new zombie to spawn and the engine crashes.

The question was: where?

---

## Finding the Leaks: Static Analysis

We decompiled the full BO2 zombies GSC source using [gsc-tool](https://github.com/xensik/gsc-tool) and ran a systematic audit: find every `spawn()` call and trace whether its corresponding `delete()` is guaranteed to execute.

Most were fine. But three functions stood out.

### Leak 1: `lerp()` in `_zm_utility.gsc`

```gsc
lerp( chunk )
{
    link = spawn( "script_origin", self getorigin() );
    link linkto( self );
    link moveto( ... );
    link waittill_multiple( "rotatedone", "movedone" );
    self unlink();
    link delete();
}
```

`lerp()` is called when zombies move from their spawn door to the playspace — the walk-in animation. It creates a `script_origin` entity called `link`, uses it to drive the zombie's movement, then deletes it.

The problem: **no `self endon("death")`**.

GSC uses cooperative multitasking. When a zombie dies, the engine cleans up that entity's threads. But `link` is a *different* entity. If the zombie is killed while `link waittill_multiple(...)` is sleeping, the zombie's thread terminates — but `link` is still alive, still in the entity pool, and now unreachable. `link delete()` never runs.

This is pure resource leak. One `script_origin` abandoned per zombie killed during their walk-in. At high rounds, with Insta-Kill active and dozens of zombies walking in at once, this is a very common event. Especially during the 'insta-kill' round phenomena that is a result of zombie health overflow at high round intervals.

**The catch:** `link` is a function-local variable. There's no `self.link`, no way for any outside code to find it. Any fix requires modifying the base game function itself — not something an addon script can do.

### Leaks 2 & 3: `do_zombie_rise()` and `do_zombie_spawn()` in `_zm_spawner.gsc`

These two functions have the same pattern with a cruel irony:

```gsc
do_zombie_rise()
{
    self endon( "death" );           // ← "safety" mechanism
    self.anchor = spawn( "script_origin", ... );
    self linkto( self.anchor );
    self.anchor moveto( anim_org, 0.05 );
    self.anchor waittill( "movedone" );
    // ...
    self.anchor delete();            // ← NEVER REACHED if endon fires
}
```

The `self endon("death")` guard is there specifically to handle the "zombie dies early" case. But it backfires: when the zombie dies, `endon` exits the thread immediately — before `self.anchor delete()` can run. The anchor entity is left behind.

Unlike `lerp()`'s `link`, this one *is* stored on `self` as `self.anchor`. It's reachable. A watchdog on the zombie can find it and clean it up.

Together, we called these three the **entity leak trifecta**:
- `lerp()` link — zombie walk-in, unfixable from addon
- `do_zombie_rise()` anchor — zombie spawn rise, fixable
- `do_zombie_spawn()` anchor — zombie spawn placement, fixable

Our initial severity estimate: these could leak 3–6 entities per round at high rounds. Over 200 rounds, that's 600–1200 leaked entities against a ~910-entity gameplay budget. **Enough to crash any long run.**

We were half right and half very wrong.

---

## Building the Diagnostic Infrastructure

Before writing any fix, we needed proof. We built two tools:

**`zm_diagnostics.gsc`** — a live HUD overlay showing entity count, zombie health, queue depth, kills, recycles, and powerup state. It probes entity headroom by attempting to spawn 128 `script_origin` entities: if it succeeds, there's at least 128 slots free (reported as `Probe HR: >128`).

**`zm_stress_test.gsc`** — a console-driven testing framework. Key commands:
- `set st_cmd ramp <N>` — skip to round N instantly
- `set st_cmd killall` — kill all active zombies
- `set st_cmd elpramp <N>` — advance from current round to N, killing zombies at t+1s each wave, logging entity metrics

The ELP patch (`zm_patch_entity_leaks.gsc`) hooks into `level._zombie_custom_spawn_logic`, an official mod hook in `_zm_spawner.gsc` that threads a function on every new zombie. Our watchdog sleeps on `waittill("death")` and runs `self.anchor delete()` if it finds the anchor still defined.

---

## The First Test: Zero Freed Anchors

With everything deployed, we ran `elpramp R1→R10`: advance through rounds 1–10, kill all zombies at 1 second into each wave, log the ELP patch's `anchors_freed` count.

```
[ST] ELPRAMP done R1→R10: total_killed=17 total_anchors_freed=0 elp=1
```

Zero.

The entity deltas were clean: killing zombies *removed* entities (−2 per kill), confirming the game wasn't leaking anything. But the ELP watchdog never triggered.

We thought the delay might be wrong. Reduced from 2 seconds to 1 second. Still zero. Tried 0.5 seconds. Still zero.

Something was fundamentally off about our mental model of the anchor lifecycle.

---

## The Key Discovery: The Anchor Window Is 50ms

We went back to `do_zombie_rise()` in `_zm_spawner.gsc` and read it more carefully. Specifically, the execution order:

```
Line 2784: self.anchor = spawn(...)          ← anchor created
Line 2795: self.anchor moveto(anim_org, 0.05) ← moves zombie to spawn spot in 50ms
Line 2796: self.anchor waittill("movedone")  ← yields one GSC frame (~50ms)
Line 2802: self.anchor rotateto(..., 0.05)   ← optional 50ms rotate
Line 2803: self.anchor waittill("rotatedone")
Line 2806: self unlink()
Line 2808: self.anchor delete()              ← ANCHOR GONE after ~50-100ms total

Line 2811: self thread hide_pop()            ← VISUAL ANIMATION STARTS HERE
Line 2812: level thread zombie_rise_death()
```

The anchor is not the rise animation. **The anchor is a teleport.** It moves the zombie entity to its exact spawn spot in 50ms — essentially snapping it into position with a tiny eased movement. The visual "zombie crawling out of the ground" that players see begins *after* `self.anchor delete()` already ran.

**The anchor window is ~50-100ms per zombie, not several seconds.**

This changes the entire severity picture:

| What we assumed | Reality |
|----------------|---------|
| Anchor spans the full visible rise animation (~3-5s) | Anchor is a 50-100ms positioning utility |
| Any kill of a rising zombie leaks an anchor | Only a kill within the first 100ms of existence leaks |
| Common trigger: players shooting rising zombies | Rare trigger: grenades landing exactly at spawn point |

Our 1-second delay in `elpramp` fired long after every anchor was gone. That's why we got zero.

---

## GSC Thread Scheduling: Why Even 50ms Isn't Enough

We added a new command, `elpkill`, that hooks `level._zombie_custom_spawn_logic` with a per-zombie kill: one GSC frame (50ms) after spawn, kill the zombie.

This should be exactly in the anchor window. Frame 0: zombie spawned, anchor created by `do_zombie_rise()`. Frame 1: our kill fires, anchor still present, ELP watchdog catches it.

Except it still got zero in early testing.

The reason is GSC's cooperative scheduler, which uses **creation-order FIFO**: threads run in the order they were created within a frame. Our `elpkill` hook runs *before* `do_zombie_rise()` is threaded (the spawner calls our hook first, then threads `do_zombie_rise()`). So our kill thread runs in frame 1 *before* `do_zombie_rise()` gets its turn. The anchor was never set. We killed a clean zombie.

The only way to catch anchors consistently is concurrent spawn density — multiple zombies spawning within the same frame creates timing overlap where our kill in frame 1 lands *after* another zombie's `do_zombie_rise()` set its anchor in an interleaved thread. This is why the `elpkill` data shows zero at low rounds and climbs as round number (and spawn density) increases:

```
R3:  8 anchors freed
R4: 13 anchors freed
R5: 18 anchors freed
...
R11: 33 anchors freed
```

More zombies per round = more concurrent spawn events = more timing overlap = more catches.

---

## The Definitive Proof: `elpsynth` A/B Test

Thread scheduling made it impossible to cleanly reproduce the natural anchor leak via gameplay timing. So we bypassed it entirely with a new command: `elpsynth`.

The approach: instead of racing the natural 50ms window, *synthetically construct the exact leak condition*. Walk all live zombies, spawn a `script_origin` on each one and assign it as `self.anchor` — exactly what `do_zombie_rise()` does. Then kill them all. Measure how many anchors were freed vs placed.

**Run 1 — ELP removed from storage (control):**

```
[ST] ELPSYNTH placed 4 synthetic anchors (elp=0)
[ST] elpsynth: placed=4 freed=0 ent_delta=-4 (ELP off — control)
[ST] Control run: 4 anchors now leaked
```

![Control run: 4 anchors leaked with no patch](../research/test-results/patched/elpsynth-control-no-elp.png)

Four `script_origin` entities created, four zombies killed, zero anchors freed. The four entities are now permanently resident in the pool with no owner. `ent_delta=-4` — only the zombie AI entities were removed; the anchor entities remain, invisible to the entity audit (the `getentarray()` approach misses bare `script_origin` entities, which is itself an interesting finding).

**Run 2 — ELP v1.1 loaded (patched):**

```
[ST] ELPSYNTH placed 6 synthetic anchors (elp=1)
[ST] ELPSYNTH result anchors_placed=6 killed=6 anchors_freed=6 ent_delta=-5 elp=1
[ELP] R2 — anchors freed this round: 6 (total: 6)
```

Six placed, six freed. 100% catch rate.

| Condition | anchors_placed | anchors_freed | Permanently leaked |
|-----------|---------------|---------------|--------------------|
| ELP OFF   | 4             | 0             | **4** |
| ELP ON    | 6             | 6             | **0** |

The watchdog works exactly as designed — it finds and frees every externally-assigned `self.anchor` at death time. But running it prompted a question: does the same leak happen under natural gameplay conditions?

---

## The Twist: Natural Anchors Don't Actually Leak

We ran `elpkill` without ELP for 32 rounds and 1600 kills. The spawn-based probe stayed at `HR=128` the entire time.

```
DIAG_SNAP [AUTO R30]
  Ent Tally:    207/1024
  Probe HR:     >128
  Kills:        1396
[ST] elpkill R30 ent=206 ELP=off
[ST] elpkill R31 ent=206 ELP=off
[ST] elpkill R32 ent=206 ELP=off
```

Hundreds of "killed mid-anchor" events. Probe completely flat. No pool pressure at all.

**The anchor entities from `do_zombie_rise()` are not real persistent leaks.**

The most consistent explanation is **thread-scoped entity ownership**. Look at `do_zombie_rise()` again:

```gsc
do_zombie_rise( spot )
{
    self endon( "death" );          // ← thread exits HERE when zombie dies
    ...
    self.anchor = spawn( "script_origin", ... );  // ← created in self's thread
    ...
    self.anchor delete();           // ← never reached on death
}
```

The anchor is spawned *within a thread running on `self`*. When the zombie dies, `endon("death")` fires and the thread exits cleanly. The T6 engine appears to reclaim entities spawned by a thread when that thread exits via `endon` — an implicit cleanup that isn't documented anywhere but is consistent with every test result.

So the `delete()` on line 2808 that we thought was the entire problem... the engine was running its own version of it all along.

### Why `elpsynth` Showed a Real Leak

`elpsynth` spawns entities from `level`'s thread context:

```gsc
// Running on level, not on self
ai[i].anchor = spawn( "script_origin", ai[i].origin );
```

This entity has no ownership link to the zombie's thread. When the zombie dies and its thread exits, there's nothing for the engine to auto-clean. The `script_origin` genuinely persists. ELP finds it and frees it correctly.

`elpsynth` was inadvertently testing a *different* scenario — external-thread entity assignment — which is a real leak, but not one that `do_zombie_rise()` actually produces. This is why ELP showed `freed=6` with synthetic anchors but the probe never moved after 1600 natural kills.

### What This Means

| Leak source | Static finding | Runtime verdict |
|-------------|---------------|-----------------|
| `do_zombie_rise()` anchor | Code path misses `delete()` | **Not a real leak** — engine auto-cleans on `endon` exit |
| `do_zombie_spawn()` anchor | Same | **Not a real leak** |
| `lerp()` local `link` | No `endon`, force-terminated | **Unknown — open question** |

The ELP patch is correct code. It frees anchors that would otherwise leak in external-thread scenarios (which `elpsynth` confirms are real). But it is not preventing a natural gameplay leak from the normal zombie spawn path.

---

## The Remaining Open Question: `lerp()`

`lerp()` is categorically different from the anchor functions:

```gsc
lerp( chunk )
{
    // NO self endon("death") here
    link = spawn( "script_origin", self getorigin() );
    link linkto( self );
    link moveto( ... );
    link waittill_multiple( "rotatedone", "movedone" );
    self unlink();
    link delete();
}
```

There is no `endon("death")`. When the zombie dies mid-`lerp()`, the thread is **force-terminated** by the engine (not a clean exit via `endon`). Whether force-terminated threads trigger the same implicit cleanup as `endon`-exited threads is unknown. It may be a genuinely different code path in the engine's thread manager.

If force-terminated threads do NOT trigger auto-cleanup, then `link` — a function-local variable with no `self.link` reference anywhere — genuinely persists in the engine pool with no way to reach or free it from addon scripts. The only fix would be modifying `_zm_utility.gsc` directly to add `self endon("death")` followed by a cleanup path.

Confirming this requires a long natural gameplay run with no `elpkill` automation: just play normally with zombies walking in, monitor probe headroom over 50+ rounds. If the probe degrades, `lerp()` leaks. If it doesn't, the engine cleans force-terminated threads too and there may be no entity leak at all.

---

## The Patch

`zm_patch_entity_leaks.gsc` is a single-file addon:

```gsc
init()
{
    // Hook into the official mod spawn hook — threads our watchdog on every zombie.
    level._zombie_custom_spawn_logic = ::elp_zombie_anchor_watchdog;
    logprint("[ELP] Entity leak patch v1.1 loaded — anchor watchdog installed\n");
    level thread elp_per_round_log();
}

elp_zombie_anchor_watchdog()
{
    self waittill( "death" );

    if ( isdefined( self.anchor ) )
    {
        self.anchor delete();
        self.anchor = undefined;
        level._elp_anchors_freed++;
    }
}
```

That's it. 8 lines of logic. Drop `zm_patch_entity_leaks.gsc` into your Plutonium scripts folder, compile with gsc-tool, and the watchdog installs itself on every zombie via the existing mod hook.

The per-round log line tells you exactly what it caught:

```
[ELP] R11 — anchors freed this round: 33 (total: 208)
```

---

## The Other Crash: Script Variables

While building the entity leak test infrastructure, we encountered a second distinct crash type in the community bug reports:

```
Userver script runtime error
exceeded maximum number of child server script variables
Terminal script error
maps/mp/zombies/_zm_utility.gsc:1
```

This is **not** the entity pool. The T6 engine has a second fixed-size pool — the GSC VM's "child scrVar" pool — that holds all live script variable values simultaneously. Every `entity.field = value` assignment, every array element, every local variable in a running thread, all share a single global bucket. When it's gone, the VM panics.

The `_zm_utility.gsc:1` location is a red herring. It's the entry-point module of the zombies script system, not the actual bug site — the engine reports where it's currently executing when the allocation fails.

### What fills it

Two patterns in `_zm_weapons.gsc` that we found during the investigation:

**`self.hitsthismag[weapon]`** — set inside `watchweaponchangezm()`, which runs once per player for the entire session. Every unique weapon string the player ever switches to adds a permanent entry. In BO2, weapon names encode all active attachments: `"an94_zm"`, `"an94_zm+reflex"`, `"an94_zm+reflex+grip"`, and the PaP variant `"an94_upgraded_zm"` are four distinct keys. The array is never pruned. With 50+ box cycles across a long session, one player can hold 40–80+ permanent scrVar slots in this single array.

```gsc
watchweaponchangezm()
{
    self.hitsthismag = [];    // initialized once, never cleared

    while ( true )
    {
        self waittill( "weapon_change", newweapon );
        if ( !isdefined( self.hitsthismag[newweapon] ) )
            self.hitsthismag[newweapon] = weaponclipsize( newweapon );  // grows forever
    }
}
```

**`self.pack_a_punch_weapon_options[weapon]`** — set inside `get_pack_a_punch_weapon_options()`, which caches the visual customization (camo, scope, reticle) for each upgraded weapon. Never cleared. Every unique PaP'd weapon string is a new key.

Neither of these causes an immediate crash. But four players at high rounds with aggressive box cycling can collectively accumulate hundreds of permanently-occupied scrVar slots per session. Add the path node arrays that never get freed, the kill counter accumulation, and any orphaned thread frames from entity leaks, and eventually you hit the pool ceiling.

### Why this one hits box-heavy players later

The entity ceiling crash tends to hit earlier because the entity pool is smaller and entity leaks accumulate with every explosive kill of a rising or walking zombie. The scrVar crash requires more game time: you only gain one entry per *unique* weapon string, so you need 50+ box rolls before the per-player count becomes significant.

The crucial insight: **the two crashes come from the same playstyle but at different depths**. Heavy box cycling accelerates both. Explosive weapons accelerate only the entity crash. This is why the community pattern — "grenade spammers crash early, box spammers crash late" — is actually two separate bugs expressing at different timescales.

### The fix

Unlike `lerp()` and unlike `has_attachment`, this one is fully patchable from an addon script. The arrays are plain player entity fields. At each `start_of_round`:

```gsc
svp_prune_player()
{
    // SA-08: rebuild hitsthismag keeping only weapons currently carried
    current_weapons = self getweaponslist();
    keep = [];
    for (i = 0; i < current_weapons.size; i++)
    {
        w = current_weapons[i];
        if (isdefined(self.hitsthismag[w]))
            keep[w] = self.hitsthismag[w];
    }
    self.hitsthismag = keep;    // stale entries from dropped weapons are gone

    // SA-09: clear PaP cache entirely — base code regenerates lazily on next call
    self.pack_a_punch_weapon_options = undefined;
}
```

All read sites for both arrays are guarded by `isdefined()`, so missing entries are simply re-added on first use. The base code at `_zm_weapons.gsc:398-412` re-initialises missing `hitsthismag` entries on weapon switch. `get_pack_a_punch_weapon_options()` re-initialises the PaP cache lazily. The only observable effect is that PaP weapon cosmetics re-randomise once per round — purely aesthetic.

### Confirmed

Using the new `weap` and `papweap` stress test commands to inflate the arrays to simulated-high-round sizes, then advancing rounds:

```
0:12 [ST] weap: hitsthismag inflated 1 -> 101 for banq
0:15 [SVP] banq hitsthismag: pruned 100 stale entries (was 101, now 1)

0:30 [ST] papweap: pap_weapon_options inflated 0 -> 50 for banq
1:45 [SVP] banq pap_weapon_options: cleared 50 cached entries
```

100 stale entries pruned at round 1 start. 50 PaP entries cleared at round 3 start. The arrays stay at current-weapon-count (2–3 entries) for the rest of the session regardless of how much box cycling happens.

---

## The Broader Lessons

**Static analysis is a starting point, not a conclusion.** We identified the right functions but got the mechanics wrong. The anchor was a 50ms positioning utility, not a multi-second animation prop. Without runtime testing, we would have written a patch for a problem that rarely occurs and called it done.

**GSC's cooperative scheduler has observable, exploitable behavior.** The FIFO thread ordering is documented nowhere in the community but is directly responsible for why `elpkill` gets zero at round 3 but 33 at round 11. Understanding it was key to designing a test that actually caught the leak.

**`elpsynth` is the right pattern for testing leak patches.** When the natural timing window is too narrow to catch reliably, bypass it entirely: synthetically construct the exact memory state the patch is supposed to handle, run the patch, verify the state was cleaned up. Cleaner than any race-based test.

**The diag counter misses certain entity types.** `getentarray()` doesn't enumerate bare `script_origin` entities without specific targeting. The leaked anchors in the control run are invisible to the audit but present in the pool. This is worth knowing when debugging entity issues generally — you can have more entities than your diagnostics show.

**"Running out of world" can mean two different pools.** The entity ceiling crash and the scrVar pool crash have different symptoms, different error messages, different triggers, and different fixes — but they both kill long sessions and they're both invisible to the player until the game terminates. Assuming there is only one resource pool is the kind of assumption that sends you in the wrong direction for a long time.

---

## Next

Two resource pools addressed. One open question remains: `lerp()`. The next post covers what it means that a function-local variable is unfixable from an addon script, how Plutonium T6's compile-time namespace resolution works, and why `idx++` is one of the most consequential missing lines of code in BO2 history.

*All scripts, test data, and raw logs are at [github.com/banq/t6-high-round-fix](#).*
