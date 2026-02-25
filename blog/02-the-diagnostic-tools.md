# Building the Instrument Panel

*Part 2 of the BO2 High-Round Crash Fix series. [Part 1 — The Archaeology](01-the-archaeology.md)*

---

Before writing a single patch, we needed to answer a harder question than "does this bug
exist?" We needed to answer: "does this bug actually cause the crash?"

Finding a function with a missing `delete()` is static analysis — pattern matching on
source code. A missing `delete()` that runs thousands of times per session in a game with
a fixed entity budget sounds catastrophic. But "sounds catastrophic" and "is the crash"
are different claims, and the testing would turn out to split them in ways nobody expected.

To test any hypothesis rigorously you need instrumentation: something that shows you the
game's internal state in real time and lets you create controlled experimental conditions.
We built two tools.

---

## Tool 1: `zm_diagnostics.gsc` — The Instrument Panel

`zm_diagnostics.gsc` is a HUD overlay that displays game internals the original game
never exposes. The core display:

```
BANQ DIAG v0.6
Round: 34
ZHealth: 4.8M
ZQueue: 24
AI Active: 20
Probe HR: >128
Probe Min: >128
Ent Tally: 207/1024
----------
Kills: 394
Recycles: 0
Timeouts: 0
Box Hits: 17
----------
Drop Inc: 21500
ScoreTotal: 142000
Grenade Ct: 0
----------
```

Each line is a `newclienthudelem()` element positioned in the top-left corner. The
display updates every 0.5 seconds. The numbers are formatted into bucketed short forms
(`21500` → `21K`) to minimise unique config string consumption — every unique string ever
passed to `settext()` permanently occupies a slot in the engine's config string table, and
running the same HUD for 50+ rounds would exhaust that table without bucketing.

The most important fields:

**`Probe HR: >128`** — This is the entity headroom probe, the most reliable leak detector
in the entire system. Every 10 seconds, the script attempts to spawn 128 `script_origin`
entities in rapid succession. If all 128 succeed, there are at least 128 free entity slots
and the display shows `>128`. The probe is capped at 128 to stay well within safe headroom
on a healthy game — if estimated free slots drop too low to probe safely, the probe skips
entirely rather than risk crashing the session. A falling headroom reading is the warning;
the probe's job is to surface the trend before the ceiling is reached.

The probe is immune to measurement blind spots. Even if an orphaned entity is invisible
to `getentarray()` because it has no script owner, it still occupies a pool slot. A
declining probe headroom confirms real pool pressure regardless of what the entity audit
shows. If the pool leaks, the probe catches it.

**`Ent Tally: 207/1024`** — A direct count of entities returned by broad `getentarray()`
queries. Supplements the probe but is less reliable: some entity types (bare `script_origin`
with no script owner) don't appear in these queries. The probe is ground truth;
the tally is context.

**`Recycles: 0`** and **`Timeouts: 0`** — Counters from the zombie failsafe system.
When zombies get stuck and the failsafe kills and re-queues them, these increment. At
round 200+ with zombies having infinite health (the overflow condition), these explode:
`Kills=Recycles=Timeouts`, the queue count oscillates, the round never ends. Watching
these flatline vs explode is how we confirmed the failsafe soft-lock (IL-03) in a
controlled test.

### Implementation Detail: The Probe

The probe is the most technically interesting piece:

```gsc
diag_entity_probe_loop()
{
    level endon("end_game");

    for (;;)
    {
        wait level.diag_probe_interval;  // 10 seconds between probes

        probe = [];
        for (i = 0; i < DIAG_PROBE_CAP; i++)  // DIAG_PROBE_CAP = 128
        {
            e = spawn("script_origin", (0, 0, 0));
            if (!isdefined(e))
                break;  // vestigial — T6 hard-crashes before spawn() returns undefined
            probe[probe.size] = e;
        }

        level.diag_entity_headroom = probe.size;

        // Clean up immediately — the probe should not itself consume slots
        for (i = 0; i < probe.size; i++)
            probe[i] delete();
    }
}
```

Every probe attempt consumes 0–128 entity slots for a few milliseconds then releases them
all. Net effect on pool: zero. But the count of how many succeed up to the cap is a direct
measurement of remaining headroom, independent of how those slots are occupied. The real
safety mechanism is the pre-check: before running the probe, the script estimates free
slots from a `getentarray()` tally and skips entirely if headroom looks too tight to probe
safely. T6 `spawn()` does not return `undefined` when the pool is exhausted — it hard-crashes
the session — so the cap and the pre-check are the only things that keep the probe itself
from triggering the crash.

---

## Tool 2: `zm_stress_test.gsc` — The Time Machine

The second problem with testing entity leaks in a live game is time. Real entity
accumulation from natural play takes hours or dozens of rounds. A round at round 30 takes
several minutes. Waiting for pool pressure to manifest naturally would make every
hypothesis test a day-long experiment.

`zm_stress_test.gsc` is a console-driven testing framework that compresses that time by
orders of magnitude. Commands are issued by setting the `st_cmd` dvar in the Plutonium
console:

```
set st_cmd kill         — kill all live zombies instantly
set st_cmd skip 100     — jump to round 100 (sets health, speed, and spawns)
set st_cmd fill 800     — pre-fill 800 entity slots with script_origin entities
set st_cmd score 2147000000  — set player score near int32 max
set st_cmd dropinc 44000     — set powerup drop increment near cap
set st_cmd god          — toggle invulnerability
set st_cmd status       — print full state snapshot to console
```

The `fill` and `drain` commands are essential for entity ceiling testing:

```gsc
st_cmd_fill(arg)
{
    n = int(arg);
    for (i = 0; i < n; i++)
    {
        e = spawn("script_origin", (0, 0, i * 10));
        if (!isdefined(e))
            break;  // vestigial — actual exhaustion causes COM_ERROR before this triggers
        level._stress_fill_ents[level._stress_fill_count] = e;
        level._stress_fill_count++;
    }
    logprint("[ST] fill complete: " + level._stress_fill_count + " entities held\n");
}
```

Running `fill 800` with a baseline pool of ~207 occupied slots leaves only ~17 free —
enough to test behavior at the edge of the entity ceiling in a controlled environment
instead of waiting for natural accumulation.

### The ELP Test Commands

Three commands were added specifically for entity leak patch testing:

**`elpramp`** — Kill zombies 1 second after each wave starts and advance rounds
automatically. The 1s delay was our initial (wrong) guess at the anchor window. This is
what gave us zero anchors freed and prompted the discovery that the anchor window is 50ms.

**`elpkill`** — Kill each zombie 50ms after spawn via a per-zombie hook in
`level._zombie_custom_spawn_logic`. This fires inside the anchor window and produces the
"killed mid-anchor" log lines. Without the patch loaded, anchors accumulate. With the
patch, they're freed.

**`elpsynth`** — The synthetic anchor test. Walk all live zombies, manually assign each
a new `script_origin` as `self.anchor` (from `level`'s thread context, not from the
zombie's thread), then kill them all. Measure anchors freed vs placed.

```gsc
st_cmd_elpsynth()
{
    ai = getaiarray(level.zombie_team);
    for (i = 0; i < ai.size; i++)
    {
        // Assign anchor from level's thread — not from self's thread.
        // This is the scenario where the auto-cleanup doesn't apply.
        anchor = spawn("script_origin", ai[i].origin);
        ai[i].anchor = anchor;
    }
    placed = ai.size;
    iprintln("[ST] ELPSYNTH placed " + placed + " synthetic anchors");

    wait 0.1;

    ai2 = getaiarray(level.zombie_team);
    for (i = 0; i < ai2.size; i++)
        ai2[i] dodamage(ai2[i].health + 666, ai2[i].origin);

    wait 0.2;
    freed = level._elp_anchors_freed;
    // ... report
}
```

This command was how we proved that ELP's mechanism is correct — it finds and frees every
externally-assigned anchor — while also discovering that naturally-spawned anchors are
cleaned up by the engine itself without help. (Post 3 covers why.)

### The Overflow Commands

**`score N`** — sets `player.score_total` to N, which allowed us to reproduce the OF-02
score overflow without playing to INT_MAX naturally (which would take months of real play).

**`dropinc N`** — sets `zombie_powerup_drop_increment` directly. Combined with lowering
the drop threshold via `dropinc 100`, this lets us trigger dozens of drops in a single
round to observe the increment compounding.

**`health N`** and **`skip N`** together let us reproduce the round-163 health overflow
in under a minute: skip to round 163, observe `level.zombie_health` spike to ~2B on the
HUD, confirm zombies stop dying, watch the recycling counters explode.

---

## How Plutonium's Script System Works (and What It Won't Let You Do)

Building these tools taught us the hard way where Plutonium's addon script system ends.

Custom scripts loaded from the Plutonium scripts directory each have their `init()`
function called after the base game completes its initialization chain. This means we
can:

- **Thread background watchers** — `level thread entity_probe_loop()` runs for the
  life of the match alongside everything else
- **Override level function pointers** — `level.round_spawn_func = ::our_func`
  intercepts the per-round spawn logic
- **Hook per-zombie spawn** — `level._zombie_custom_spawn_logic` is an official mod
  hook in `_zm_spawner.gsc` that calls our function on every new zombie
- **Read and write `level.` variables** — including `zombie_health`, `zombie_vars`,
  stat counters

What we cannot do:

- **Override functions that base game scripts call directly.** When a base game script
  is compiled with `#include maps\mp\zombies\_zm_weapons`, the compiled bytecode contains
  a hardcoded function pointer to `_zm_weapons::has_attachment`. No addon script can
  intercept that pointer. The compiler resolved it; the runtime sees a direct address.

This limitation is why `has_attachment()` — confirmed as an infinite-loop bomb for
three-attachment weapon names — cannot be fixed by any addon script. No matter what name
or file you define a replacement in, base game code will never call it. Understanding
this constraint took three failed approaches and one "Unresolved external" error message
before we documented it precisely:

```
**** 1 script error(s):
**** Unresolved external: "has_attachment" with 2 parameters in "" at lines [,1,1] ****
```

The engine couldn't find `has_attachment` at all — because without `#include _zm_weapons`
in our test script, it had no reference to the function anywhere (our definition was in
a different namespace, inaccessible without an include). This confirmed there is no
global function table. Each script's namespace is its own island.

---

## What the Early Data Showed

With both tools deployed and the first baseline runs complete, the data was immediately
interesting.

Entity count across rounds 1–50 using `ramp`: **completely flat at 207**. Not a leak in
sight. But `ramp` advances rounds by setting `level.round_number` directly and signaling
`end_of_round` — zombies never spawn, walk, or die. A different kind of test was needed.

ELP `elpramp` across rounds 1–10: **zero anchors freed**. The entity count stayed flat.
No evidence of the leak we had confidently described from the static analysis.

This was the point where the project could have concluded "the static analysis was wrong
and there's no entity leak." Instead, it raised the harder question: **was the 1-second
kill delay wrong, or was the entire mental model of the anchor lifecycle wrong?**

Part 3 has the answer — and it required reading `do_zombie_rise()` four times more
carefully than we had before.

---

## A Note on the Config String Limit

One surprising constraint we hit early: every unique string ever passed to `settext()` on
a HUD element permanently consumes a slot in the engine's config string table. The table
has 512 total slots, 195 are reserved by the base game, leaving 317 for custom scripts.

If the diagnostic HUD updated kill counts as raw numbers (`settext("Kills: 394")`), it
would burn a slot for "Kills: 394", another for "Kills: 395", and so on. Forty rounds
with 24 zombies each is ~960 unique strings just for the kill counter.

The fix: `diag_hud_fmt()` buckets values into ranges and returns a short form:
- 0–999: exact value ("394")
- 1,000–9,999: one decimal K ("1.4K")
- 10,000+: rounded K ("21K")
- 1,000,000+: one decimal M ("2.1M")

This limits the kill counter to ~10 unique strings for the entire session. The diagnostic
tool that we built to study resource leaks has to be designed carefully to avoid causing
its own resource leak.

---

## Next

Part 3 covers what the data actually showed about entity leaks — including a significant
correction to our static analysis findings — and introduces the second crash vector we
hadn't originally looked for: the script variable pool.

*All scripts, test data, and raw logs are at [github.com/banq/t6-high-round-fix](#).*
