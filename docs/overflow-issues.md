# Integer and Float Overflow Issues

GSC on the BO2 engine uses 32-bit signed integers (max 2,147,483,647) and 32-bit floats (precision degrades above ~16 million, max ~3.4e38). Several values in the zombies code grow without bound and eventually overflow these limits.

---

## OF-01: Zombie health overflow at round ~163 (HIGH)

**File:** `_zm.gsc:3572-3592`

```gsc
ai_calculate_health( round_number )
{
    level.zombie_health = level.zombie_vars["zombie_health_start"];

    for ( i = 2; i <= round_number; i++ )
    {
        if ( i >= 10 )
        {
            old_health = level.zombie_health;
            level.zombie_health = level.zombie_health + int( level.zombie_health * level.zombie_vars["zombie_health_increase_multiplier"] );

            if ( level.zombie_health < old_health )
            {
                level.zombie_health = old_health;
                return;
            }
        }
        else
            level.zombie_health = int( level.zombie_health + level.zombie_vars["zombie_health_increase"] );
    }
}
```

**Mechanism:** Health starts at 150, grows linearly (+100/round) for rounds 2-9, then compounds at +10% per round from round 10 onward. The 10% compound growth means health roughly doubles every 7 rounds. By round ~163, the value exceeds `2^31 - 1`.

**Mitigation present:** The check `if ( level.zombie_health < old_health )` catches the overflow (a wrapped value is negative/smaller) and caps health at the last valid value. So it doesn't crash — but zombies become effectively unkillable since their health is ~2.1 billion.

**Downstream effects:**
- Zombies can't be killed by normal weapons (damage is also 32-bit)
- Only instakill effects (traps, Insta-Kill powerup, headshot multipliers that overflow) can kill them
- Combined with the failsafe recycling loop (see [IL-03](./infinite-loops.md#il-03-failsafe-zombie-recycling-loop-high)), this creates soft-lock conditions

**Additional note:** This function recalculates from round 2 every time it's called (via a loop from `i = 2` to `round_number`). At round 255, that's 254 iterations. It's called once per round so it's not a performance issue, but it's inefficient — a cached previous value with a single multiplication would suffice.

---

## OF-02: `score_total` integer overflow breaks powerup drops (HIGH)

**File:** `_zm_powerups.gsc:395-412`

```gsc
watch_for_drop()
{
    // ...
    while ( true )
    {
        // ...
        for ( i = 0; i < players.size; i++ )
        {
            if ( isdefined( players[i].score_total ) )
                curr_total_score = curr_total_score + players[i].score_total;
        }

        if ( curr_total_score > score_to_drop )
        {
            level.zombie_vars["zombie_powerup_drop_increment"] *= 1.14;
            score_to_drop = curr_total_score + level.zombie_vars["zombie_powerup_drop_increment"];
            // ... drop powerup ...
        }
        wait 0.5;
    }
}
```

**Mechanism:** `score_total` is a running total of all points earned in the game (not current score — total earned). With 4 players at round 200+ earning points continuously (kills + Double Points), the sum can exceed 2,147,483,647. The overflow wraps `curr_total_score` negative, making `curr_total_score > score_to_drop` permanently false. Powerup drops stop entirely.

**When it happens:** Rough estimate — 4 players earning an average of 200 points/zombie, ~5000 zombies/round, hitting round ~50-60 could approach the limit. With Double Points active frequently, even sooner.

---

## OF-03: `zombie_powerup_drop_increment` exponential float growth (HIGH)

**File:** `_zm_powerups.gsc:405`

```gsc
level.zombie_vars["zombie_powerup_drop_increment"] = level.zombie_vars["zombie_powerup_drop_increment"] * 1.14;
```

**Mechanism:** Starting at 2000 (set during init), this value is multiplied by 1.14 every time a powerup drop threshold is hit. This is exponential growth: `2000 * 1.14^n`.

| Drops | Value |
|-------|-------|
| 10 | ~7,424 |
| 50 | ~1,580,312 |
| 100 | ~1.25 billion |
| 200 | ~7.8e17 |
| 300 | ~4.9e26 |
| 400 | ~3.1e35 |

32-bit float precision breaks down well before the max. By ~200 drops, the comparison `curr_total_score > score_to_drop` becomes unreliable. Eventually the value hits `inf`.

**Interaction with OF-02:** These two issues compound. The drop threshold grows exponentially while the score sum grows linearly, meaning drops become increasingly rare even before overflow. After overflow of either value, drops stop.

---

## OF-04: `get_stat_combined_rank_value` overflow (MEDIUM)

**File:** `_zm_stats.gsc:599-609`

```gsc
get_stat_combined_rank_value_survival_classic()
{
    rounds = get_stat_round_number();
    kills = self.pers["kills"];

    if ( rounds > 99 )
        rounds = 99;

    result = rounds * 10000000 + kills;
    return result;
}
```

**Mechanism:** With `rounds` capped at 99: `99 * 10,000,000 = 990,000,000`. Remaining headroom for `kills` is ~1.15 billion before int32 overflow. In extremely long games (round 200+, 4 players), a single player's kill count could potentially approach this.

**Impact:** Stat corruption. The rank value wraps negative, potentially affecting leaderboard placement or progression systems.

---

## OF-05: Distance traveled float precision loss (LOW)

**File:** `_zm.gsc:1643-1653`

```gsc
player_monitor_travel_dist()
{
    self endon( "disconnect" );
    // ...
    for ( prevpos = self.origin; 1; prevpos = self.origin )
    {
        wait 0.1;
        self.pers["distance_traveled"] = self.pers["distance_traveled"] + distance( self.origin, prevpos );
    }
}
```

**Mechanism:** Accumulates a float every 100ms. After hours of play, the accumulated value is large. 32-bit floats lose precision above ~16 million — small distance increments (a few units) are rounded to zero when added to a large accumulator.

Later, per-round distance is calculated by subtraction:
```gsc
distancethisround = int( players[i].pers["distance_traveled"] - players[i].pers["previous_distance_traveled"] );
```

Subtracting two large, nearly-equal floats amplifies precision error (catastrophic cancellation).

**Impact:** Inaccurate distance stats. Not a crash risk.
