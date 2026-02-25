# A Scripting Language Running Inside a Machine It Cannot See

*Part 2 of the BO2 High-Round Crash Fix series. [Part 1 — The Archaeology](01-the-archaeology.md)*

---

Everything in this series depends on a constraint that shapes every decision: the crashes
we are fixing live at the boundary between two layers that can't talk to each other.
Understanding where that boundary sits — and why it exists — is the foundation for
everything else.

---

## Two Layers, One Game

When you launch Black Ops 2, two things start running.

The first is the **engine**: a compiled C++ binary (`t6mp.exe`) that is the
evolutionary descendant of id Software's Quake III Arena (1999). IW adapted it for
*Call of Duty* in 2003. Treyarch carried it forward through World at War, Black Ops 1,
and Black Ops 2. It handles everything that requires direct hardware access or
performance-sensitive computation: entity physics, collision detection, AI pathfinding,
network replication, the renderer, the audio mixer, and the virtual machine that runs
game scripts. You cannot read its source. You cannot patch it. It shipped as a
precompiled binary and that is what it remains.

The second is the **scripts**: `.gsc` files compiled to bytecode and shipped inside
`.ff` (fast-file) archives bundled with the game. The VM in the engine reads this
bytecode and executes it. Scripts handle game logic: zombie behavior, weapon systems,
the magic box, round management, HUD, scoring, the Pack-a-Punch machine. This is code
we can read — thanks to gsc-tool decompiling the bytecode — and code we can, with
significant constraints, modify.

The crashes are in the scripts. The constraints are in the engine. That asymmetry
drives everything.

---

## What GSC Can Do

GSC is a weakly-typed, garbage-collected scripting language whose design is obviously
derived from C with some JavaScript-style array handling. It runs on the T6 engine's
embedded VM in a **cooperative multitasking** model: multiple threads appear to run
concurrently, but only one executes at a time. Threads yield control voluntarily via
`wait`, `waittill`, or blocking calls. The scheduler resumes the next waiting thread on
the next engine frame (50ms at 20 ticks/s).

From a script, you can:

- **Spawn and delete engine entities** — `spawn("script_origin", ...)`, `entity delete()`
- **Read and write entity fields** — `self.health = 100`, `level.round_number++`
- **Thread coroutines** — `entity thread my_function()` starts a new execution context
- **Signal and wait on named events** — `entity notify("death")`, `entity waittill("death")`
- **Call engine built-ins** — `getentarray()`, `spawn()`, `getaiarray()`, `iprintln()`,
  `weaponclipsize()`, hundreds more
- **Access dvar configuration** — `getDvar("sv_maxclients")`, `setDvar("r_brightness", 1)`

What you cannot do is reach anything the engine hasn't explicitly surfaced to the scripting
layer. You cannot read the current entity pool utilization from a script. You cannot read
the scrVar pool's available capacity. You cannot change the size of either pool. You cannot
hook into engine-level event dispatch. You cannot intercept a function call between two
compiled scripts if you weren't included at compile time. The engine's C++ internals are
simply not visible from GSC.

---

## Why Debugging Is Harder Than It Should Be

The engine's opacity has a direct consequence for debugging: when something goes wrong,
you get a location, not a cause.

The most common crash message in the community:

```
Userver script runtime error
exceeded maximum number of child server script variables
Terminal script error
maps/mp/zombies/_zm_utility.gsc:1
```

`_zm_utility.gsc:1` is not where the bug is. It is where execution happened to be at the
moment the allocation failed. That file is the root include for the zombies script system —
`line 1` is the first line of the entry module. The VM panics, reports its current position,
and exits. The actual cause could be anywhere in the script tree that ran before this
moment.

The entity ceiling crash is even less informative: the game freezes, audio loops for 3–5
seconds, then exits with `Exception Code 0xC0000005` (access violation). No script error.
No line number. The entity pool is a C++ data structure; when it overflows, the engine
segfaults directly. There is no scripting layer left to report anything.

This means debugging requires **inference from behavior**:

- "The entity pool is full" is not directly observable — pool exhaustion causes a hard engine crash (`COM_ERROR: G_Spawn: no free entities`), not a script-visible failure
- "The scrVar pool is under pressure" is inferred from watching which operations cause
  freezes as the session lengthens
- "This specific function is the cause" is inferred by isolating which code path changed
  the observable symptom

The diagnostic infrastructure we built (covered in Part 3) exists entirely because the
engine won't tell you its internal state. You have to build your own instruments.

There is a second layer of difficulty: **GSC's cooperative scheduler has observable but
undocumented ordering behavior**. Threads are resumed in creation order within a frame —
FIFO scheduling. If your test assumes a different ordering, your test measures nothing.
Several apparent "null results" in early testing turned out to be tests that were running
in the wrong frame relative to the code under observation. The scheduler is not documented
anywhere in the community; we had to infer its behavior from test results.

---

## Constraint 1: The Entity Pool

The engine allocates a fixed pool of entity slots at startup. For T6 zombies, that pool
is **1024 slots**. Every object that exists in the game world occupies one slot:

| Entity type | Examples |
|-------------|---------|
| AI actors | Zombies, Nova Crawlers, Napalm Zombies |
| Players | 1–4 player entities |
| Weapon pickups | Max Ammo, Insta-Kill, Nuke drops |
| Physics props | Barricade planks, debris |
| Script origins | Animation anchors, movement proxies, trigger volumes |
| Sound emitters | Positional audio sources |
| HUD proxies | Some HUD effects use entity attachments |

A normal game on Town / Survival at round 30 occupies roughly **207 slots** for the level's permanent
fixtures plus active gameplay state. The remaining ~817 are the working budget. That budget
breathes: a zombie spawns (slot allocated), is killed (slot freed), the next zombie
spawns into the freed slot. As long as frees keep up with allocations, the pool is stable.

An entity **leak** is when an allocation happens without a corresponding free. One leaked
entity per round might seem negligible — 200 rounds is only 200 slots, well within
budget. But entity leaks in BO2 don't accumulate at a rate of one per round. The functions
with missing cleanup run on **every zombie spawn and every zombie death**. At round 100
with 24 zombies per wave and 100-round sessions running for hours, even a small per-zombie
leak rate fills the pool.

When the pool is exhausted, the engine crashes directly with `COM_ERROR: G_Spawn: no free entities`. `spawn()` does not return `undefined` — the session terminates before that can happen. There is no script-layer signal to catch.

One important wrinkle: the approach of the ceiling is observable before you hit it. The
diagnostic probe we built spawns up to 128 `script_origin` entities every 10 seconds,
then frees them all and reports the count. If all 128 succeed, the pool has at least 128
free slots. If estimated free headroom drops too low to probe safely, the probe skips
entirely rather than risk pushing the session over the edge. A declining probe count over
successive rounds is the warning signal. The probe can't tell you *what* occupies those
slots, but it tells you the headroom is draining before it's gone.

---

## Constraint 2: The Script Variable Pool

The second pool is less understood and harder to observe.

The GSC virtual machine maintains a global pool of **script variable slots** (scrVars).
Every value that exists simultaneously in the running script system occupies one scrVar
slot: every array entry, every entity field, every local variable in every currently-
executing thread frame. There is one pool, shared across everything.

There is no equivalent of `spawn()` returning `undefined`. The pool depletes silently. You
continue reading entity fields and setting array entries and all of it works — until the
allocator reaches the ceiling, at which point the VM immediately panics with the "exceeded
maximum number of child server script variables" error and the session ends.

Two distinct accumulation patterns feed this pool:

**Permanent baseline accumulation:** Arrays that grow monotonically and are never pruned.
`self.hitsthismag` in `_zm_weapons.gsc` adds one entry per unique weapon string the player
ever switches to — and in BO2, weapon names encode every attachment as a `+`-delimited
string, so `"an94_zm"`, `"an94_zm+reflex"`, `"an94_zm+reflex+grip"`, and
`"an94_upgraded_zm"` are four distinct keys. After 50+ box cycles across a long session, a
single player might hold 80+ permanent scrVar slots in this array alone. With four players
at high rounds, that's 320+ permanently-occupied slots that will never be released until
the session ends. The only thing that grows faster is the Origins fire staff bug (SA-10),
which creates hundreds of thread frames per shot because a check was written on the wrong
entity.

**Burst pressure:** Operations that temporarily spike scrVar demand during execution.
Die Rise's `elevator_roof_watcher` (MI-11) calls `get_players()` and `player_can_see_me()`
for every zombie on every elevator poll — 672 player-array allocations per 0.5 seconds
when all elevator triggers are active. These are transient (freed after each poll), but
the concurrent peak during each window is significant. When the baseline is already
depleted by permanent accumulation, a burst spike tips the pool over the edge.

The interaction between these two patterns is what makes the crash feel random. The
permanent accumulation sets the floor; the burst provides the trigger. With a fresh
pool, no individual burst is dangerous. With a depleted pool, any burst can be the
final push.

---

## How Small Errors Become a Twelve-Year Bug

None of the individual issues in this codebase are catastrophic in isolation. Reading
the source code with fresh eyes, the mistakes look ordinary:

- `watchweaponchangezm()` initializes `self.hitsthismag = []` and adds entries for every
  weapon encountered but never prunes the array between rounds. A one-line fix.
- `elevator_roof_watcher()` uses `continue` where it should use `break`, causing it to
  scan all zombies instead of stopping at the first eligible one. A one-word fix.
- `fire_staff_area_of_effect()` checks `self.is_on_fire` instead of
  `e_target.is_on_fire`, because `self` is the projectile entity, not the zombie. A
  five-character fix.
- `lerp()` spawns a `script_origin` without an `endon("death")` guard, which means the
  entity outlives the zombie that was using it. A one-line fix.

These are not architectural failures. They are the kind of mistakes that appear in any
large, fast-moving codebase maintained across multiple teams with tight ship deadlines.
A developer writing `self.is_on_fire` instead of `e_target.is_on_fire` in a fire-staff
effect function in 2012 did not break the game for any player running a normal session.
The bug only matters when:

1. The function accumulates state over a very long session
2. Multiple instances compound simultaneously
3. Some other bug has already depleted a resource that this bug now exhausts completely

That combination of conditions doesn't occur in a casual game. It occurs after 50+ hours
of continuous play, in the hands of competitive players who specifically push the
strategies that trigger maximum accumulation — box cycling, elemental staves, trap-heavy
play. Those are exactly the players chasing round 100, round 200, round 255.

The bugs shipped in 2012. Treyarch issued updates through 2014. Nothing in the patch
notes addressed these specific issues — likely because the pool-exhaustion crashes require
sessions too long to reproduce reliably in a QA environment. After 2014, the game received
no more patches. The codebase is frozen exactly as-shipped.

---

## The Asymmetry of Fixes

This is the core constraint that shapes everything in this series.

**We can fix GSC bugs. We cannot fix engine bugs.**

The engine's entity pool is 1024 slots. If Treyarch were still shipping patches, they
could raise that ceiling by recompiling the engine. We cannot. The pool is defined in
compiled C++ and we have no access to it.

The GSC scrVar pool has a fixed capacity defined in the engine. Treyarch could have
enlarged it. We cannot.

What we *can* do is make the scripts more careful with the resources they have. We can
prune arrays that grow forever. We can add cleanup callbacks that free entities on zombie
death. We can fix the accumulation rate so the pools last longer. We can't raise the
ceilings, but we can slow the approach.

There's a further subdivision within GSC fixes. Not all GSC bugs are reachable from
addon scripts.

When a base game script is compiled, function calls inside it are resolved at compile
time to direct bytecode addresses. If `_zm_utility.gsc` calls `has_attachment()` — the
infinite-loop bug we confirmed causes hard freezes — that call is a hardcoded reference
to the `has_attachment` function in `_zm_weapons.gsc`. No external script can intercept
it. Plutonium's addon script system calls our `init()` after the base game initializes,
but compiled base game code never looks up function names at runtime. The address is
already baked in.

This is why `has_attachment()` (IL-01) and `lerp()`'s local `link` entity (EL-01) cannot
be fixed from an addon script. The code containing the bugs is compiled into fastfiles
and called by other compiled code that has no external hookpoint.

The only path to those fixes is replacing the fastfile itself — compiling a modified
version of `_zm_weapons.gsc` or `_zm_utility.gsc` and shipping it as a replacement
fastfile asset via the Plutonium `mods/` folder. This requires a separate tool
([OpenAssetTools](https://github.com/Laupetin/OpenAssetTools)) because gsc-tool's
compiled output is rejected by the T6 runtime due to mismatched script name hashes and
section layout. The fastfile replacement route works — and is how the IL-01 and EL-01
fixes are actually shipped — but it is substantially more complex than an addon script
drop.

Everything else — the scrVar accumulation bugs, the probe-reachable entity leaks, the
loop bugs in code threaded via official mod hooks — is fixable from an addon script by
the end of this series.

---

## What This Means for the Rest of the Series

The crashes are not random. They are not the engine "getting tired." They are
two fixed-size resource pools being depleted by accumulated errors in GSC code that
has been frozen since 2014. Understanding the pools — which bugs fill which pool, at
what rate, in which map and playstyle combinations — is the entire problem.

Part 3 covers the diagnostic infrastructure we built to make those pools visible: a
live HUD that probes entity headroom in real time, a stress-testing framework that
compresses 50 hours of gameplay into a controlled 20-minute test, and what the first
data revealed about which of our static analysis findings were real and which were
phantom.

*All scripts, test data, and raw logs are at [github.com/banq/t6-high-round-fix](#).*
