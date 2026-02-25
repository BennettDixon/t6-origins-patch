#include maps\mp\gametypes_zm\_hud_util;
#include maps\mp\zombies\_zm_utility;
#include maps\mp\zombies\_zm_perks;
#include maps\mp\zombies\_zm;

init()
{
    level._stress_fill_ents = [];
    level._stress_fill_count = 0;
    level._stress_ramp_active = 0;
    level._st_elpkill_active = 0;

    setDvar("st_cmd", "");
    setDvar("st_arg", "");

    level thread st_command_listener();
}

// --- COMMAND LISTENER ---

// Polls the "st_cmd" dvar every 0.25s.
// Usage in Plutonium console:
//   set st_cmd kill
//   set st_cmd "skip 10"      (quotes for multi-word — or: set st_arg 10 && set st_cmd skip)
//   set st_cmd help
st_command_listener()
{
    level endon("end_game");

    for (;;)
    {
        wait 0.25;

        raw = getDvar("st_cmd");
        if (!isdefined(raw) || raw == "")
            continue;

        setDvar("st_cmd", "");

        args = strtok(raw, " ");
        if (args.size == 0)
            continue;

        cmd = args[0];
        arg1 = getDvar("st_arg");
        if (args.size > 1)
            arg1 = args[1];
        setDvar("st_arg", "");

        players = getplayers();
        if (players.size == 0)
            continue;
        player = players[0];

        if (cmd == "skip")
            player thread st_cmd_skip(arg1);
        else if (cmd == "kill")
            player thread st_cmd_kill();
        else if (cmd == "fill")
            player thread st_cmd_fill(arg1);
        else if (cmd == "drain")
            player thread st_cmd_drain();
        else if (cmd == "score")
            player thread st_cmd_score(arg1);
        else if (cmd == "nade")
            player thread st_cmd_nade(arg1);
        else if (cmd == "box")
            player thread st_cmd_box(arg1);
        else if (cmd == "dropinc")
            player thread st_cmd_dropinc(arg1);
        else if (cmd == "health")
            player thread st_cmd_health(arg1);
        else if (cmd == "god")
            player thread st_cmd_god();
        else if (cmd == "perks")
            player thread st_cmd_perks();
        else if (cmd == "openmap")
            player thread st_cmd_openmap();
        else if (cmd == "status")
            player thread st_cmd_status();
        else if (cmd == "ramp")
            level thread st_cmd_ramp(arg1);
        else if (cmd == "stop")
            st_cmd_stop();
        else if (cmd == "killrise")
            level thread st_cmd_killrise();
        else if (cmd == "elpramp")
            level thread st_cmd_elpramp(arg1);
        else if (cmd == "el01ramp")
            level thread st_cmd_el01ramp(arg1);
        else if (cmd == "lerptest")
            level thread st_cmd_lerptest(arg1);
        else if (cmd == "lerpramp")
            level thread st_cmd_lerpramp(arg1);
        else if (cmd == "lerpwatch")
            level thread st_cmd_lerpwatch();
        else if (cmd == "elpkill")
            level thread st_cmd_elpkill();
        else if (cmd == "elpsynth")
            level thread st_cmd_elpsynth();
        else if (cmd == "elp")
            level thread st_cmd_elp();
        else if (cmd == "givebasestaff")
            player thread st_cmd_givebasestaff();
        else if (cmd == "givestafffire")
            player thread st_cmd_givestafffire();
        else if (cmd == "givestaffair")
            player thread st_cmd_givestaffair();
        else if (cmd == "givestafflightning")
            player thread st_cmd_givestafflightning();
        else if (cmd == "givestaffwater")
            player thread st_cmd_givestaffwater();
        else if (cmd == "giveallstaffs")
            player thread st_cmd_giveallstaffs();
        else if (cmd == "stafflegit")
            player thread st_cmd_stafflegit();
        else if (cmd == "sa10test")
            player thread st_cmd_sa10test();
        else if (cmd == "sa10stat")
            player thread st_cmd_sa10stat();
        else if (cmd == "mi06test")
            player thread st_cmd_mi06test();
        else if (cmd == "mi06auto")
            player thread st_cmd_mi06auto();
        else if (cmd == "mi06stat")
            player thread st_cmd_mi06stat();
        else if (cmd == "mi07test")
            player thread st_cmd_mi07test();
        else if (cmd == "mi07stat")
            player thread st_cmd_mi07stat();
        else if (cmd == "mi08test")
            level thread st_cmd_mi08test();
        else if (cmd == "mi08stat")
            level thread st_cmd_mi08stat();
        else if (cmd == "mi09test")
            level thread st_cmd_mi09test();
        else if (cmd == "mi09stat")
            level thread st_cmd_mi09stat();
        else if (cmd == "mi12test")
            level thread st_cmd_mi12test();
        else if (cmd == "mi12stat")
            level thread st_cmd_mi12stat();
        else if (cmd == "mi11test")
            level thread st_cmd_mi11test();
        else if (cmd == "mi11stat")
            level thread st_cmd_mi11stat();
        else if (cmd == "weap")
            player thread st_cmd_weap(arg1);
        else if (cmd == "papweap")
            player thread st_cmd_papweap(arg1);
        else if (cmd == "weapstat")
            player thread st_cmd_weapstat();
        else if (cmd == "help")
            player thread st_cmd_help();
        else if (cmd == "gencap")
            level thread st_cmd_gencap(arg1);
        else if (cmd == "genstat")
            level thread st_cmd_genstat();
        else if (cmd == "aipop")
            level thread st_cmd_aipop(arg1);
        else if (cmd == "animstate")
            level thread st_cmd_animstate(arg1);
        else if (cmd == "animindex")
            level thread st_cmd_animindex(arg1);
        else if (cmd == "animleakrate")
            level thread st_cmd_animleakrate(arg1);
        else if (cmd == "animsat")
            level thread st_cmd_animsat(arg1);
        else if (cmd == "animstop")
            level thread st_cmd_animstop();
        else if (cmd == "animstat")
            level thread st_cmd_animstat();
        else if (cmd == "animasd")
            level thread st_cmd_animasd(arg1);
        else if (cmd == "roboforce")
            level thread st_cmd_roboforce();
        else if (cmd == "roboforce1")
            level thread st_cmd_roboforce1();
        else if (cmd == "robosoak")
            level thread st_cmd_robosoak(arg1);
        else if (cmd == "animrobotleak")
            level thread st_cmd_animrobotleak(arg1);
        else if (cmd == "animrobotwatch")
            level thread st_cmd_animrobotwatch();
        else if (cmd == "animrobotstat")
            level thread st_cmd_animrobotstat();
        else if (cmd == "animrobotstop")
            level notify("animrobotwatch_stop");
        else if (cmd == "animoverlap")
            level thread st_cmd_animoverlap();
        else if (cmd == "animcgsnap")
            level thread st_cmd_animcgsnap();
        else if (cmd == "animcgwatch")
            level thread st_cmd_animcgwatch(arg1);
        else if (cmd == "animcgstop")
            level thread st_cmd_animcgstop();
        else if (cmd == "animcgstat")
            level thread st_cmd_animcgstat();
        else if (cmd == "freezeround")
            level thread st_cmd_freezeround();
        else if (cmd == "thawround")
            level thread st_cmd_thawround();
        else
            iprintln("^1[ST] Unknown: " + cmd + "  |  set st_cmd help");
    }
}

// --- ROUND SKIP ---

st_cmd_skip(arg)
{
    if (arg == "")
    {
        iprintln("^1[ST] Usage: /st skip <round>");
        return;
    }

    target = int(arg);

    if (target < 1)
        target = 1;

    if (target > 255)
        target = 255;

    iprintln("^3[ST] Skipping to round " + target + "...");

    st_kill_all_zombies();
    wait 0.5;

    level.zombie_total = 0;
    level.zombie_total_subtract = 0;

    level.round_number = target;

    st_recalc_health(target);

    if (level.gamedifficulty == 0)
        level.zombie_move_speed = target * level.zombie_vars["zombie_move_speed_multiplier_easy"];
    else
        level.zombie_move_speed = target * level.zombie_vars["zombie_move_speed_multiplier"];

    delay = 2.0;
    for (i = 1; i < target; i++)
    {
        delay = delay * 0.95;
        if (delay < 0.08)
        {
            delay = 0.08;
            break;
        }
    }
    level.zombie_vars["zombie_spawn_delay"] = delay;

    setroundsplayed(target);

    wait 0.5;

    level notify("end_of_round");
    wait 0.1;
    level notify("between_round_over");

    iprintln("^2[ST] Now at round " + target + " | Health: " + level.zombie_health + " | Speed: " + level.zombie_move_speed);
}

// --- KILL ALL ---

st_cmd_kill()
{
    iprintln("^3[ST] Killing all zombies...");
    count = st_kill_all_zombies();
    iprintln("^2[ST] Killed " + count + " zombies");
}

st_kill_all_zombies()
{
    if (!isdefined(level.zombie_team))
        return 0;

    ai = getaiarray(level.zombie_team);
    count = 0;

    if (!isdefined(ai))
        return 0;

    for (i = 0; i < ai.size; i++)
    {
        if (isdefined(ai[i]) && isalive(ai[i]))
        {
            ai[i] dodamage(ai[i].health + 666, ai[i].origin);
            count++;

            if (count % 5 == 0)
                wait 0.05;
        }
    }

    return count;
}

// --- ENTITY FILL / DRAIN ---
// Safe cap so we never trigger "G_Spawn: no free entities" (engine crashes on next spawn).
// T6 spawn() is a hard engine crash — it does NOT return undefined when the
// entity pool is full.  Cap fill conservatively using the count-based estimate
// from zm_diagnostics (level.diag_ent_count), which is safe to compute because
// it uses getentarray() rather than spawning.
//
// diag_count_ents() undercounts entities whose classnames aren't enumerated
// (info_volume, script_brushmodel, zbarrier_*, etc.), so we use a large buffer
// (ST_FILL_UNDERCOUNT_BUFFER) to cover the gap.
//
// ST_ENT_LIMIT must match DIAG_ENT_LIMIT in zm_diagnostics.gsc.
#define ST_ENT_LIMIT 1024
#define ST_FILL_SAFE_CAP 150
#define ST_FILL_UNDERCOUNT_BUFFER 150

st_cmd_fill(arg)
{
    if (arg == "")
    {
        iprintln("^1[ST] Usage: /st fill <count>");
        return;
    }

    n = int(arg);

    if (n < 1 || n > 1000)
    {
        iprintln("^1[ST] Count must be 1-1000");
        return;
    }

    // Cap using count-based headroom.  level.diag_ent_count is updated every
    // 0.5s by the diagnostics HUD loop and is safe to read.  Fall back to
    // ST_FILL_SAFE_CAP if diagnostics haven't run yet.
    cap = ST_FILL_SAFE_CAP;
    if (isdefined(level.diag_ent_count) && level.diag_ent_count > 0)
    {
        free_est = ST_ENT_LIMIT - level.diag_ent_count - ST_FILL_UNDERCOUNT_BUFFER;
        if (free_est > 0)
            cap = free_est;
        else
            cap = 0;
    }
    if (n > cap)
    {
        if (cap <= 0)
        {
            iprintln("^1[ST] Refusing fill — entity headroom too low (Ent Tally: " + level.diag_ent_count + "/" + ST_ENT_LIMIT + ")");
            return;
        }
        iprintln("^3[ST] Capping at " + cap + " (Ent Tally: " + level.diag_ent_count + "/" + ST_ENT_LIMIT + ")");
        n = cap;
    }

    iprintln("^3[ST] Filling " + n + " entities...");
    spawned = 0;

    for (i = 0; i < n; i++)
    {
        ent = spawn("script_origin", (0, 0, -10000));

        if (!isdefined(ent))
        {
            iprintln("^1[ST] Spawn failed at " + spawned + " — entity limit reached!");
            break;
        }

        level._stress_fill_ents[level._stress_fill_count] = ent;
        level._stress_fill_count++;
        spawned++;

        if (spawned % 50 == 0)
            wait 0.05;
    }

    iprintln("^2[ST] Filled " + spawned + " entities (total held: " + level._stress_fill_count + ")");
}

st_cmd_drain()
{
    count = level._stress_fill_count;

    if (count == 0)
    {
        iprintln("^3[ST] No fill entities to drain");
        return;
    }

    iprintln("^3[ST] Draining " + count + " entities...");
    freed = 0;

    for (i = 0; i < count; i++)
    {
        if (isdefined(level._stress_fill_ents[i]))
        {
            level._stress_fill_ents[i] delete();
            freed++;
        }

        if (freed % 50 == 0)
            wait 0.05;
    }

    level._stress_fill_ents = [];
    level._stress_fill_count = 0;
    iprintln("^2[ST] Drained " + freed + " entities");
}

// --- SCORE MANIPULATION ---

// Sets both the displayed score (self.score) and the cumulative stat
// (self.score_total) so the on-screen points counter looks like a real run.
// No-arg default of 250000 is a plausible R50 Origins amount.
st_cmd_score(arg)
{
    val = 250000;
    if (arg != "")
        val = int(arg);

    self.score       = val;
    self.score_total = val;
    if (isdefined(self.pers))
        self.pers["score"] = val;

    iprintln("^2[ST] " + self.name + " score set to " + val);
}

// --- GRENADE COUNT ---

st_cmd_nade(arg)
{
    if (arg == "")
    {
        iprintln("^1[ST] Usage: /st nade <count>");
        return;
    }

    val = int(arg);
    self.grenade_multiattack_count = val;
    iprintln("^2[ST] " + self.name + " grenade_multiattack_count set to " + val);
}

// --- BOX HITS ---

st_cmd_box(arg)
{
    if (arg == "")
    {
        iprintln("^1[ST] Usage: /st box <count>");
        return;
    }

    val = int(arg);
    level.chest_accessed = val;
    iprintln("^2[ST] chest_accessed set to " + val);
}

// --- POWERUP DROP INCREMENT ---

st_cmd_dropinc(arg)
{
    if (arg == "")
    {
        iprintln("^1[ST] Usage: /st dropinc <value>");
        return;
    }

    val = int(arg);
    level.zombie_vars["zombie_powerup_drop_increment"] = val;
    iprintln("^2[ST] zombie_powerup_drop_increment set to " + val);
}

// --- ZOMBIE HEALTH ---

st_cmd_health(arg)
{
    if (arg == "")
    {
        iprintln("^1[ST] Usage: /st health <value>");
        return;
    }

    val = int(arg);
    level.zombie_health = val;
    iprintln("^2[ST] zombie_health set to " + val);
}

// --- GOD MODE ---

st_cmd_god()
{
    if (!isdefined(self._st_godmode))
        self._st_godmode = 0;

    if (self._st_godmode)
    {
        self._st_godmode = 0;
        self disableinvulnerability();
        iprintln("^2[ST] God mode OFF for " + self.name);
    }
    else
    {
        self._st_godmode = 1;
        self enableinvulnerability();
        iprintln("^2[ST] God mode ON for " + self.name);
    }
}

// --- PERKS ---

// Gives the four core Origins high-round perks directly, skipping the
// machines.  Silently skips any the player already has.
//
// Perk mapping:
//   specialty_armorvest    Juggernog      (250 HP)
//   specialty_quickrevive  Quick Revive   (faster self-revive)
//   specialty_fastreload   Speed Cola     (faster reload)
//   specialty_longersprint Stamin-Up      (unlimited sprint)
st_cmd_perks()
{
    perks = [];
    perks[0] = "specialty_armorvest";
    perks[1] = "specialty_quickrevive";
    perks[2] = "specialty_fastreload";
    perks[3] = "specialty_longersprint";

    given = 0;
    for (i = 0; i < perks.size; i++)
    {
        if (!self hasperk(perks[i]))
        {
            self give_perk(perks[i]);
            given++;
        }
    }

    if (given == 0)
        iprintln("^3[ST] " + self.name + " already has all four core perks");
    else
        iprintln("^2[ST] " + self.name + " +" + given + " perk(s): Jugger + QR + Speed Cola + Stamin-Up");

    logprint("[ST] perks: gave " + given + " perk(s) to " + self.name + "\n");
}

// --- OPEN MAP ---

// Force-opens all buyable doors and clears all debris on the map without
// spending any points.  Uses the same force-trigger path as the quantum bomb
// (notify "trigger" with force=1), which bypasses the point check in
// door_buy() and debris_think() identically to zombie_unlock_all.
//
// Safe to call multiple times — already-open doors ignore the notify.
st_cmd_openmap()
{
    player = self;
    opened = 0;

    doors = getentarray("zombie_door", "targetname");
    for (i = 0; i < doors.size; i++)
    {
        doors[i] notify("trigger", player, 1);
        opened++;
    }

    airlocks = getentarray("zombie_airlock_buy", "targetname");
    for (i = 0; i < airlocks.size; i++)
    {
        airlocks[i] notify("trigger", player, 1);
        opened++;
    }

    debris = getentarray("zombie_debris", "targetname");
    for (i = 0; i < debris.size; i++)
    {
        debris[i] notify("trigger", player, 1);
        opened++;
    }

    iprintln("^2[ST] openmap: triggered " + opened + " door/debris/airlock entities");
    logprint("[ST] openmap: triggered " + opened + " entities\n");
}

// --- HELP ---

st_cmd_help()
{
    iprintln("^3[ST] Console commands — no-arg:  ^2set st_cmd kill");
    wait 0.1;
    iprintln("^3[ST] With arg:  ^2set st_arg 10 ^3then^2 set st_cmd skip");
    wait 0.1;
    iprintln("^2kill^7/^2drain^7/^2god^7/^2perks^7/^2stop^7/^2status  ^7- no argument needed");
    wait 0.1;
    iprintln("^2perks       ^7- give Juggernog + Quick Revive + Speed Cola + Stamin-Up (Origins broll)");
    wait 0.1;
    iprintln("^2openmap     ^7- force-open all doors and clear all debris (no points spent)");
    wait 0.1;
    iprintln("^2skip <N>    ^7- instant jump to round N");
    wait 0.1;
    iprintln("^2ramp <N>    ^7- step to round N one-at-a-time (3s gap, shows leak curve)");
    wait 0.1;
    iprintln("^2fill <N>    ^7- spawn N filler entities (watch Ent Tally on HUD)");
    wait 0.1;
    iprintln("^2score [N]   ^7- set displayed+total score (default 250000)  |  ^2dropinc <N>  ^7- set drop increment");
    wait 0.1;
    iprintln("^2health <N>  ^7- set zombie health  |  ^2nade <N>  ^7- set grenade count");
    wait 0.1;
    iprintln("^2box <N>     ^7- set chest_accessed count");
    wait 0.1;
    iprintln("^2killrise    ^7- auto-kill mid-rise each round (ELP leak test, /st stop to disarm)");
    wait 0.1;
    iprintln("^2elpkill     ^7- kill each zombie within its ~50ms anchor window (precise ELP test)");
    wait 0.1;
    iprintln("^2elpsynth    ^7- place synthetic anchors then kill, A/B test ELP on vs off");
    wait 0.1;
    iprintln("^2elpramp <N> ^7- ramp to R N killing mid-rise each wave, log anchors freed/round");
    wait 0.1;
    iprintln("^2el01ramp <N>^7- ramp to R N applying lerp() synthetically, log lerp links freed/round");
    wait 0.1;
    iprintln("^2lerptest <N>^7- kill at t+5s per wave for N rounds, log probe HR (lerp() leak test)");
    wait 0.1;
    iprintln("^2lerpramp <N>^7- kill NON-lerp zombies each wave; fftest watcher handles mid-lerp (EL-01)");
    wait 0.1;
    iprintln("^2lerpwatch  ^7- continuous: kill non-lerp zombies every 0.5s, accumulate lerp detections");
    wait 0.1;
    iprintln("^2elp         ^7- one-shot: kill now, print ent-delta + anchors-freed");
    wait 0.1;
    iprintln("^2givebasestaff ^7- give base Fire Staff and print its ammo (diagnostic)");
    wait 0.1;
    iprintln("^2givestafffire     ^7- give upgraded Fire Staff with ammo (SA-10 test setup, zm_origins only)");
    wait 0.1;
    iprintln("^2givestaffair      ^7- give upgraded Wind Staff (MI-06 test: hold fire to charge, zm_origins only)");
    wait 0.1;
    iprintln("^2givestafflightning^7- give upgraded Lightning Staff with ammo (zm_origins only)");
    wait 0.1;
    iprintln("^2givestaffwater    ^7- give upgraded Water/Ice Staff with ammo (zm_origins only)");
    wait 0.1;
    iprintln("^2giveallstaffs     ^7- give all four upgraded staves at once (zm_origins only)");
    wait 0.1;
    iprintln("^2stafflegit        ^7- skip R50 + god + all staves + print expected behavior for each");
    wait 0.1;
    iprintln("^2sa10test    ^7- give fire staff + arm SA-10 dedup counter (zm_origins only)");
    wait 0.1;
    iprintln("^2sa10stat    ^7- print/reset SA-10 blocked-thread count");
    wait 0.1;
    iprintln("^2mi06test    ^7- give wind staff + arm MI-06 soft-lock detector (zm_origins only)");
    wait 0.1;
    iprintln("^2mi06auto    ^7- automated MI-06: kill-to-2, countdown, script-kills zombie[0] (zm_origins only)");
    wait 0.1;
    iprintln("^2mi06stat    ^7- print/reset MI-06 redirect-saved count");
    wait 0.1;
    iprintln("^2mi07test    ^7- arm MI-07 drag-escape counter (wind staff invisible zombie reproduction)");
    wait 0.1;
    iprintln("^2mi07stat    ^7- print/reset MI-07 undamaged-zombie count");
    wait 0.1;
    iprintln("^2mi08test    ^7- arm MI-08 spawn-contamination watcher (is_on_ice/staff_hit at birth)");
    wait 0.1;
    iprintln("^2mi08stat    ^7- print/reset MI-08 contaminated-spawn counts");
    wait 0.1;
    iprintln("^2mi09test    ^7- arm MI-09 do_damage_network_safe partial-path logger (float/int gap)");
    wait 0.1;
    iprintln("^2mi09stat    ^7- print/reset MI-09 partial vs kill branch counts");
    wait 0.1;
    iprintln("^2mi12test    ^7- arm MI-12 ice blizzard frozen-survivor watcher (validates float32 fix)");
    wait 0.1;
    iprintln("^2mi12stat    ^7- print/reset MI-12 blizzard audit counts — PASS = 0 frozen survivors");
    wait 0.1;
    iprintln("^2mi11test    ^7- arm MI-11 dispatch counter (zm_highrise only — stand on elevator roof)");
    wait 0.1;
    iprintln("^2mi11stat    ^7- print/reset MI-11 dispatched vs no-climber counts");
    wait 0.1;
    iprintln("^2weap <N>    ^7- add N fake hitsthismag entries (simulate box cycling, SA-08)");
    wait 0.1;
    iprintln("^2papweap <N> ^7- add N fake pap_weapon_options entries (simulate PaP cycling, SA-09)");
    wait 0.1;
    iprintln("^2weapstat    ^7- print hitsthismag and pap cache sizes for all players");
    wait 0.1;
    iprintln("^2gencap <N>  ^7- force-capture N generators at once (GEN-ZC-01 test, zm_origins only)");
    wait 0.1;
    iprintln("^2genstat     ^7- print per-zone capture_zombie_limit and live capture zombie counts");
}

// --- STATUS DUMP ---

st_cmd_status()
{
    r = 0;
    if (isdefined(level.round_number))
        r = level.round_number;

    h = 0;
    if (isdefined(level.zombie_health))
        h = level.zombie_health;

    di = 0;
    if (isdefined(level.zombie_vars) && isdefined(level.zombie_vars["zombie_powerup_drop_increment"]))
        di = int(level.zombie_vars["zombie_powerup_drop_increment"]);

    ch = 0;
    if (isdefined(level.chest_accessed))
        ch = level.chest_accessed;

    iprintln("^3[ST] --- Status ---");
    wait 0.05;
    iprintln("^7  Round: " + r + " | ZHealth: " + h);
    wait 0.05;
    iprintln("^7  Fill ents held: " + level._stress_fill_count);
    wait 0.05;
    iprintln("^7  Drop Inc: " + di + " | Box Hits: " + ch);
    wait 0.05;
    iprintln("^7  Ramp active: " + level._stress_ramp_active);

    logprint("ST_STATUS round=" + r + " health=" + h + " fill=" + level._stress_fill_count + " dropinc=" + di + " chest=" + ch + "\n");
}

// --- RAMP ---

// Slowly advances through rounds one at a time, killing zombies and calling
// the skip logic between each step.  The interval lets you watch the entity
// leak curve build in near-real time instead of jumping straight to a target.
//
// Usage: /st ramp <target>          -- default 3-second pause between rounds
//        /st stop                   -- abort an in-progress ramp
st_cmd_ramp(arg)
{
    if (arg == "")
    {
        iprintln("^1[ST] Usage: /st ramp <target_round>");
        return;
    }

    target = int(arg);
    if (target < 2)   target = 2;
    if (target > 255) target = 255;

    if (level._stress_ramp_active)
    {
        iprintln("^1[ST] Ramp already running. Use /st stop first.");
        return;
    }

    r = 1;
    if (isdefined(level.round_number))
        r = level.round_number;

    if (target <= r)
    {
        iprintln("^1[ST] Target must be greater than current round (" + r + ")");
        return;
    }

    level._stress_ramp_active = 1;
    iprintln("^3[ST] Ramping from R" + r + " to R" + target + " — use /st stop to abort");

    for (next = r + 1; next <= target; next++)
    {
        if (!level._stress_ramp_active)
        {
            iprintln("^3[ST] Ramp aborted at R" + (next - 1));
            return;
        }

        // Kill remaining zombies so end_of_round triggers cleanly.
        st_kill_all_zombies();
        wait 0.5;

        // Advance exactly one round using the same skip logic.
        level.zombie_total = 0;
        level.zombie_total_subtract = 0;
        level.round_number = next;
        st_recalc_health(next);

        if (level.gamedifficulty == 0)
            level.zombie_move_speed = next * level.zombie_vars["zombie_move_speed_multiplier_easy"];
        else
            level.zombie_move_speed = next * level.zombie_vars["zombie_move_speed_multiplier"];

        delay = 2.0;
        for (i = 1; i < next; i++)
        {
            delay = delay * 0.95;
            if (delay < 0.08) { delay = 0.08; break; }
        }
        level.zombie_vars["zombie_spawn_delay"] = delay;
        setroundsplayed(next);

        wait 0.5;
        level notify("end_of_round");
        wait 0.1;
        level notify("between_round_over");

        iprintln("^2[ST] Ramp: R" + next + "/" + target + " | ZHealth: " + level.zombie_health);

        // 3-second window so the entity probe loop can fire between rounds.
        wait 3.0;
    }

    level._stress_ramp_active = 0;
    iprintln("^2[ST] Ramp complete at R" + target);
}

// --- ELP: KILLRISE MODE ---
//
// Arms an auto-kill that fires every round ~2 seconds after the wave starts.
// That 2-second window is when most zombies are still mid-rise: anchor entities
// exist but the normal cleanup code hasn't run yet.  This creates the exact
// condition EL-01 describes.
//
// What to look for in the server log:
//   [ST] killrise R3: killed 12 mid-rise
//   [ELP] R3 — anchors freed: 9 (total: 9)
//   (per-round ELP log fires at start_of_round, so count appears at R4 header)
//
// Toggle off with: set st_cmd stop
//   (reuses the ramp stop flag to keep the interface simple)
//
// Usage: set st_cmd killrise
#define ST_KILLRISE_DELAY 1.0

st_cmd_killrise()
{
    if (level._stress_ramp_active)
    {
        iprintln("^1[ST] A ramp or killrise is already running. Use /st stop first.");
        return;
    }

    level._stress_ramp_active = 1;
    iprintln("^2[ST] killrise armed — killing mid-rise zombies each round (^3/st stop^2 to disarm)");
    logprint("[ST] killrise armed\n");

    level endon("end_game");

    for (;;)
    {
        if (!level._stress_ramp_active)
        {
            iprintln("^3[ST] killrise disarmed");
            logprint("[ST] killrise disarmed\n");
            return;
        }

        level waittill("start_of_round");

        if (!level._stress_ramp_active)
            return;

        // Wait for the rise window.  Spawn animations on Town start immediately
        // at wave start; ~2s covers roughly the full rise duration for most zombies
        // at normal round speeds.
        wait ST_KILLRISE_DELAY;

        r = 0;
        if (isdefined(level.round_number))
            r = level.round_number;

        count = st_kill_all_zombies();
        logprint("[ST] killrise R" + r + ": killed " + count + " mid-rise\n");
        iprintln("^3[ST] killrise R" + r + ": killed " + count + " mid-rise");
    }
}

// --- ELP: AUTOMATED RAMP TEST ---
//
// Advances through rounds start→target, killing zombies mid-rise on every wave.
// Unlike /st ramp (which skips waves entirely), this lets each wave actually
// spawn so zombies run do_zombie_rise() and acquire self.anchor before being
// killed.  That is the exact leak scenario EL-01 describes.
//
// Per-round log line (search for ELPRAMP):
//   [ST] ELPRAMP R3: killed=11 anchors_freed=8 ents_before=214 ents_after=212
//
// End-of-run summary:
//   [ST] ELPRAMP done R1→R10: total_killed=87 total_anchors_freed=61
//
// Usage:
//   set st_arg 10
//   set st_cmd elpramp
//
// Abort mid-run: set st_cmd stop
//
// Notes:
//   - The first iteration uses whatever wave is currently active (no waittill).
//   - Subsequent iterations wait for start_of_round so advancement is clean.
//   - After each kill the code waits 0.1s for ELP watchdogs + 0.6s for the
//     diagnostics loop to refresh level.diag_ent_count.
//   - If ELP patch is not loaded, anchors_freed will always be 0 and a warning
//     is printed at the end — useful as a control run.

st_cmd_elpramp(arg)
{
    if (arg == "")
    {
        iprintln("^1[ST] Usage: /st elpramp <target_round>");
        return;
    }

    target = int(arg);
    if (target < 2)   target = 2;
    if (target > 255) target = 255;

    start_r = 1;
    if (isdefined(level.round_number))
        start_r = level.round_number;

    if (target <= start_r)
    {
        iprintln("^1[ST] Target must be greater than current round (" + start_r + ")");
        return;
    }

    if (level._stress_ramp_active)
    {
        iprintln("^1[ST] A ramp or killrise is already running. Use /st stop first.");
        return;
    }

    elp_loaded = isdefined(level._elp_version);

    level._stress_ramp_active = 1;
    iprintln("^2[ST] elpramp R" + start_r + " → R" + target
        + (elp_loaded ? " ^2(ELP v" + level._elp_version + " active)" : " ^1(ELP not loaded — control run)"));
    logprint("[ST] ELPRAMP start R" + start_r + "→R" + target + " elp=" + elp_loaded + "\n");

    level endon("end_game");

    total_killed  = 0;
    total_freed   = 0;

    for (i = 0; start_r + i < target; i++)
    {
        if (!level._stress_ramp_active)
        {
            iprintln("^3[ST] elpramp aborted at R" + (start_r + i));
            logprint("[ST] ELPRAMP aborted at R" + (start_r + i) + "\n");
            return;
        }

        // Always wait for start_of_round so the kill timer is anchored to the
        // wave spawn, not to when the command was issued.
        level waittill("start_of_round");

        // Rise window: most zombies are mid-animation at this point.
        wait ST_KILLRISE_DELAY;

        r = start_r + i;

        freed_before = 0;
        if (isdefined(level._elp_anchors_freed))
            freed_before = level._elp_anchors_freed;

        ents_before = -1;
        if (isdefined(level.diag_ent_count))
            ents_before = int(level.diag_ent_count);

        count = st_kill_all_zombies();
        total_killed += count;

        // 0.1s for ELP watchdog threads to fire their death handlers.
        wait 0.1;

        // 0.6s so the diagnostics loop (0.5s cadence) refreshes diag_ent_count.
        wait 0.6;

        freed_after = 0;
        if (isdefined(level._elp_anchors_freed))
            freed_after = level._elp_anchors_freed;

        ents_after = -1;
        if (isdefined(level.diag_ent_count))
            ents_after = int(level.diag_ent_count);

        delta_freed = freed_after - freed_before;
        total_freed += delta_freed;

        logprint("[ST] ELPRAMP R" + r
            + ": killed=" + count
            + " anchors_freed=" + delta_freed
            + " ents_before=" + ents_before
            + " ents_after=" + ents_after
            + "\n");

        iprintln("^3[ST] ELPRAMP R" + r
            + ": killed=" + count
            + " freed=" + delta_freed
            + " ents=" + ents_before + "→" + ents_after);

        // Clear spawn queue and advance round, same as /st ramp.
        level.zombie_total          = 0;
        level.zombie_total_subtract = 0;

        next = r + 1;
        level.round_number = next;
        st_recalc_health(next);

        if (level.gamedifficulty == 0)
            level.zombie_move_speed = next * level.zombie_vars["zombie_move_speed_multiplier_easy"];
        else
            level.zombie_move_speed = next * level.zombie_vars["zombie_move_speed_multiplier"];

        delay = 2.0;
        for (j = 1; j < next; j++)
        {
            delay = delay * 0.95;
            if (delay < 0.08) { delay = 0.08; break; }
        }
        level.zombie_vars["zombie_spawn_delay"] = delay;
        setroundsplayed(next);

        wait 0.5;
        level notify("end_of_round");
        wait 0.1;
        level notify("between_round_over");

        // Brief pause before waittill("start_of_round") fires in the next loop.
        wait 0.5;
    }

    level._stress_ramp_active = 0;

    logprint("[ST] ELPRAMP done R" + start_r + "→R" + target
        + ": total_killed=" + total_killed
        + " total_anchors_freed=" + total_freed
        + " elp=" + elp_loaded
        + "\n");

    iprintln("^2[ST] elpramp done R" + start_r + "→R" + target
        + " | killed=" + total_killed
        + " freed=" + total_freed
        + (elp_loaded ? "" : " ^1(ELP not loaded)"));

    if (!elp_loaded)
        iprintln("^1[ST] Re-run with ELP loaded to compare freed count");
    else if (total_freed == 0 && total_killed > 0)
        iprintln("^3[ST] 0 anchors freed — zombies may have completed rise before " + ST_KILLRISE_DELAY + "s window; try lower ST_KILLRISE_DELAY");
}

// --- EL-01: SYNTHETIC LERP LEAK RAMP TEST ---
//
// Tests the EL-01 lerp() entity leak fix across multiple rounds by forcing
// every zombie into a mid-lerp death each round.
//
// For each round:
//   1. Waits for start_of_round, then ST_EL01RAMP_SPAWN_WAIT seconds.
//   2. Drains the spawn queue (no more zombies this wave).
//   3. For each live zombie: spawns a temp first_node, sets first_node +
//      attacking_spot, threads lerp() — zombie is now mid-lerp (_lerp_link set).
//   4. Waits 150ms (lerp() blocked at waittill_multiple on all zombies).
//   5. Kills all zombies — ELP watchdog fires, deletes _lerp_link, increments
//      level._elp_lerp_freed.
//   6. Logs per-round: lerp_applied, lerp_freed_delta, ent_delta.
//   7. Forces round advance.
//
// Key metric:
//   lerp_freed_delta == lerp_applied → EL-01 PASS (all links cleaned up)
//   lerp_freed_delta == 0            → EL-01 FAIL (ELP not loaded or FF not active)
//   lerp_freed_delta <  lerp_applied → PARTIAL (check log)
//
// Also works as a control run without ELP loaded: freed will always be 0
// and entity count will climb, demonstrating the baseline leak.
//
// Requires: zm_patch_entity_leaks.gsc (for _elp_lerp_freed counter).
// Also benefits from zm_test_ff.gsc (fftest watcher provides additional
// per-zombie detection log lines).
//
// Usage:
//   set st_cmd el01ramp 20     run for 20 rounds from current round
//   set st_cmd stop            abort
//
// Per-round log (search EL01RAMP):
//   [ST] EL01RAMP R5: applied=14 freed=14 ents=244->230
//
// End summary:
//   [ST] EL01RAMP done R1->R20: total_applied=210 total_freed=210

#define ST_EL01RAMP_SPAWN_WAIT 2.0

st_cmd_el01ramp(arg)
{
    if (arg == "")
    {
        iprintln("^1[ST] Usage: /st el01ramp <target_round>");
        return;
    }

    if (level._stress_ramp_active)
    {
        iprintln("^1[ST] Another automated mode is running. Use /st stop first.");
        return;
    }

    target = int(arg);
    if (target < 2)   target = 2;
    if (target > 255) target = 255;

    start_r = 1;
    if (isdefined(level.round_number))
        start_r = level.round_number;

    if (target <= start_r)
    {
        iprintln("^1[ST] Target must be greater than current round (" + start_r + ")");
        return;
    }

    elp_loaded = isdefined(level._elp_version);

    level._stress_ramp_active = 1;

    iprintln("^2[ST] el01ramp R" + start_r + "->R" + target
        + (elp_loaded ? " ^2(ELP v" + level._elp_version + " active)" : " ^1(ELP not loaded — control run, links will leak)"));
    logprint("[ST] EL01RAMP start R" + start_r + "->R" + target + " elp=" + elp_loaded + "\n");

    level endon("end_game");

    total_applied = 0;
    total_freed   = 0;

    for (i = 0; start_r + i < target; i++)
    {
        if (!level._stress_ramp_active)
        {
            iprintln("^3[ST] el01ramp aborted");
            logprint("[ST] EL01RAMP aborted\n");
            return;
        }

        level waittill("start_of_round");
        wait ST_EL01RAMP_SPAWN_WAIT;

        r = start_r + i;

        // Drain spawn queue — fix the population we're testing.
        level.zombie_total          = 0;
        level.zombie_total_subtract = 0;

        lerp_freed_before = 0;
        if (isdefined(level._elp_lerp_freed))
            lerp_freed_before = lerp_freed_before + level._elp_lerp_freed;
        if (isdefined(level._hrp_lerp_freed))
            lerp_freed_before = lerp_freed_before + level._hrp_lerp_freed;

        ents_before = -1;
        if (isdefined(level.diag_ent_count))
            ents_before = int(level.diag_ent_count);

        // Pass 1: synthetically apply lerp() to every live zombie.
        // Spawn a temp script_origin as first_node so lerp() can read .angles.
        // lerp() reads first_node.angles synchronously before waittill, so
        // the node only needs to survive until lerp() starts blocking (~1 frame).
        ai = getaiarray(level.zombie_team);
        nodes       = [];
        lerp_applied = 0;

        for (j = 0; j < ai.size; j++)
        {
            if (!isdefined(ai[j]) || !isalive(ai[j]))
                continue;

            node = spawn("script_origin", ai[j].origin + (50, 0, 0));
            node.angles = (0, 0, 0);
            nodes[nodes.size] = node;

            ai[j].first_node     = node;
            ai[j].attacking_spot = ai[j].origin + (50, 0, 0);
            ai[j] thread lerp(undefined);
            lerp_applied++;
        }

        total_applied += lerp_applied;

        // Pass 2: wait for all lerp() threads to set _lerp_link and block
        // at waittill_multiple — happens within one GSC frame (~50ms).
        wait 0.15;

        // Pass 3: kill all zombies mid-lerp.
        // ELP watchdog (elp_zombie_anchor_watchdog) fires on each "death":
        //   isdefined(self._lerp_link) → delete it → _elp_lerp_freed++
        st_kill_all_zombies();

        // Pass 4: wait for watchdog threads to complete.
        wait 0.5;

        // Clean up temp first_node entities.
        for (j = 0; j < nodes.size; j++)
        {
            if (isdefined(nodes[j]))
                nodes[j] delete();
        }

        // Diag loop refresh (0.5s cadence).
        wait 0.6;

        lerp_freed_after = 0;
        if (isdefined(level._elp_lerp_freed))
            lerp_freed_after = lerp_freed_after + level._elp_lerp_freed;
        if (isdefined(level._hrp_lerp_freed))
            lerp_freed_after = lerp_freed_after + level._hrp_lerp_freed;

        ents_after = -1;
        if (isdefined(level.diag_ent_count))
            ents_after = int(level.diag_ent_count);

        freed_delta = lerp_freed_after - lerp_freed_before;
        total_freed += freed_delta;

        logprint("[ST] EL01RAMP R" + r
            + ": applied=" + lerp_applied
            + " freed=" + freed_delta
            + " ents=" + ents_before + "->" + ents_after
            + "\n");

        if (freed_delta == lerp_applied && lerp_applied > 0)
            result_color = "^2";
        else if (freed_delta == 0)
            result_color = "^1";
        else
            result_color = "^3";

        iprintln(result_color + "[ST] EL01RAMP R" + r
            + ": applied=" + lerp_applied
            + " freed=" + freed_delta
            + " ^7ents=" + ents_before + "->" + ents_after);

        // Force round advance.
        next = r + 1;
        level.round_number = next;
        st_recalc_health(next);

        if (level.gamedifficulty == 0)
            level.zombie_move_speed = next * level.zombie_vars["zombie_move_speed_multiplier_easy"];
        else
            level.zombie_move_speed = next * level.zombie_vars["zombie_move_speed_multiplier"];

        delay = 2.0;
        for (j = 1; j < next; j++)
        {
            delay = delay * 0.95;
            if (delay < 0.08) { delay = 0.08; break; }
        }
        level.zombie_vars["zombie_spawn_delay"] = delay;
        setroundsplayed(next);

        wait 0.5;
        level notify("end_of_round");
        wait 0.1;
        level notify("between_round_over");
        wait 0.5;
    }

    level._stress_ramp_active = 0;

    logprint("[ST] EL01RAMP done R" + start_r + "->R" + target
        + ": total_applied=" + total_applied
        + " total_freed=" + total_freed
        + " elp=" + elp_loaded
        + "\n");

    iprintln("^2[ST] el01ramp done R" + start_r + "->R" + target);
    iprintln("^7  total lerp_applied: " + total_applied + "  lerp_freed: " + total_freed);

    if (!elp_loaded)
        iprintln("^1[ST] Control run: " + total_applied + " link entities leaked (ELP not loaded)");
    else if (total_applied == 0)
        iprintln("^3[ST] 0 zombies encountered — run during an active wave");
    else if (total_freed == total_applied)
        iprintln("^2[ST] EL-01 PASS: all " + total_applied + " lerp link entities freed");
    else if (total_freed == 0)
        iprintln("^1[ST] EL-01 FAIL: 0 freed — FF not active or ELP watchdog not cleaning lerp links");
    else
        iprintln("^3[ST] EL-01 PARTIAL: " + total_freed + "/" + total_applied + " freed — check log");
}

// --- LERP() ENTITY LEAK TEST ---
//
// Tests whether lerp()'s local 'link' entity leaks when a zombie is killed
// mid-animation.  lerp() has NO self endon("death"), so its thread is
// force-terminated rather than exiting cleanly.  If force-terminated threads
// do NOT trigger engine auto-cleanup, 'link' persists in the pool permanently.
//
// Unlike the anchor leak test (elpkill/elpramp), this must use the spawn-based
// probe as its metric — getentarray() won't see leaked 'link' entities any more
// than it saw leaked anchors.  Watch for probe_hr to drop below 128.
//
// Strategy: kill all zombies at t+5s per wave.  By then most zombies have
// walked to a barrier and entered their lerp() attack animation.  Force the
// round to end and advance, repeat for N rounds.  If probe_hr stays >128 after
// 50+ rounds, lerp() likely does NOT leak (engine handles force-terminated
// threads the same as endon() exits).
//
// Per-round log (search for LERPTEST):
//   [ST] LERPTEST R5 killed=18 probe_hr=128 ent=207
//
// Usage:
//   set st_cmd lerptest 50   (run for 50 rounds from current round)
//   set st_cmd lerptest      (run indefinitely; use /st stop to abort)
//
// Abort: set st_cmd stop
//
// NOTE: the probe is only updated every 10s by the diagnostics loop.  The
// probe_hr value logged each round is the most recent sample — it may lag
// by up to 10s.  Degradation will appear as a trend across rounds, not
// as a sudden drop.

#define ST_LERPKILL_DELAY 5.0

st_cmd_lerptest(arg)
{
    if (level._stress_ramp_active)
    {
        iprintln("^1[ST] Another automated mode is running. Use /st stop first.");
        return;
    }

    target = 0;
    if (isdefined(arg) && arg != "")
        target = int(arg);

    start_r = 1;
    if (isdefined(level.round_number))
        start_r = level.round_number;

    level._stress_ramp_active = 1;

    run_str = (target > 0 ? target + " rounds" : "indefinitely");
    logprint("[ST] LERPTEST start R" + start_r + " target=" + target + "\n");
    iprintln("^2[ST] lerptest armed — killing at t+" + ST_LERPKILL_DELAY + "s, running " + run_str);
    iprintln("^3[ST] Watch log: [ST] LERPTEST RN probe_hr=X — degrade below 128 = real lerp() leak");

    level endon("end_game");

    total_killed = 0;
    rounds_run   = 0;

    for (;;)
    {
        if (!level._stress_ramp_active) break;
        if (target > 0 && rounds_run >= target) break;

        level waittill("start_of_round");

        if (!level._stress_ramp_active) break;
        if (target > 0 && rounds_run >= target) break;

        // Give zombies time to walk to barriers and enter lerp() animation.
        wait ST_LERPKILL_DELAY;

        r = level.round_number;

        // Sample probe HR before killing — captures any accumulation so far.
        // The probe loop (10s cadence) may have run during this round's wait.
        probe_hr = -1;
        if (isdefined(level.diag_entity_headroom))
            probe_hr = level.diag_entity_headroom;

        ent_count = -1;
        if (isdefined(level.diag_ent_count))
            ent_count = int(level.diag_ent_count);

        count = st_kill_all_zombies();
        total_killed += count;

        logprint("[ST] LERPTEST R" + r
            + " killed=" + count
            + " probe_hr=" + probe_hr
            + " ent=" + ent_count
            + "\n");

        iprintln("^3[ST] LERPTEST R" + r
            + " killed=" + count
            + " probe=" + probe_hr);

        // Drain spawn queue and advance round.
        level.zombie_total          = 0;
        level.zombie_total_subtract = 0;

        next = r + 1;
        level.round_number = next;
        st_recalc_health(next);

        if (level.gamedifficulty == 0)
            level.zombie_move_speed = next * level.zombie_vars["zombie_move_speed_multiplier_easy"];
        else
            level.zombie_move_speed = next * level.zombie_vars["zombie_move_speed_multiplier"];

        delay = 2.0;
        for (j = 1; j < next; j++)
        {
            delay = delay * 0.95;
            if (delay < 0.08) { delay = 0.08; break; }
        }
        level.zombie_vars["zombie_spawn_delay"] = delay;
        setroundsplayed(next);

        wait 0.5;
        level notify("end_of_round");
        wait 0.1;
        level notify("between_round_over");
        wait 0.5;

        rounds_run++;
    }

    level._stress_ramp_active = 0;

    final_hr = -1;
    if (isdefined(level.diag_entity_headroom))
        final_hr = level.diag_entity_headroom;

    logprint("[ST] LERPTEST done R" + start_r + "→R" + level.round_number
        + " total_killed=" + total_killed
        + " rounds_run=" + rounds_run
        + " final_probe_hr=" + final_hr
        + "\n");

    iprintln("^2[ST] lerptest done — " + rounds_run + " rounds, " + total_killed + " kills");
    if (final_hr >= 128)
        iprintln("^2[ST] Probe HR stable at >" + final_hr + " — no detected lerp() leak after " + rounds_run + " rounds");
    else if (final_hr >= 0)
        iprintln("^1[ST] Probe HR degraded to " + final_hr + " — lerp() LEAK CONFIRMED");
    else
        iprintln("^3[ST] Probe HR unknown (diagnostics not loaded?)");
}

// --- ELP: SYNTHETIC ANCHOR LEAK TEST ---
//
// The natural anchor window (~50ms) is unreachable from addon hooks due to
// GSC thread scheduling order.  This command sidesteps the timing problem by
// synthetically creating the exact leak condition:
//
//   1. Wait for zombies to be active mid-wave.
//   2. For each live zombie that has no anchor, spawn a script_origin and assign
//      it as self.anchor — exactly what do_zombie_rise() does.
//   3. Kill all zombies immediately.
//   4. Wait for ELP watchdog threads to fire (0.5s).
//   5. Measure: how many anchors were freed vs placed?
//
// Run twice for a clean A/B comparison:
//
//   WITH ELP loaded:
//     anchors_freed == anchors_placed  → watchdog caught every leak
//     ent_delta < 0                    → pool smaller (zombie slots + anchors freed)
//
//   WITHOUT ELP loaded (remove zm_patch_entity_leaks.gsc from Plutonium storage):
//     anchors_freed == 0               → nothing freed, expected
//     ent_delta ≈ 0                    → zombie entity removal offset by leaked anchors
//
// The difference in ent_delta between the two runs equals the number of anchors
// that would have leaked permanently without the patch.
//
// Usage (wait until zombies are active, then):
//   set st_cmd elpsynth

st_cmd_elpsynth()
{
    if (!isdefined(level.zombie_team))
    {
        iprintln("^1[ST] elpsynth: no zombie_team — start a game first");
        return;
    }

    ai = getaiarray(level.zombie_team);

    if (!isdefined(ai) || ai.size == 0)
    {
        iprintln("^1[ST] elpsynth: no active zombies — run during a wave");
        return;
    }

    elp_loaded = isdefined(level._elp_version);

    // Snapshot before.
    freed_before = 0;
    if (isdefined(level._elp_anchors_freed))
        freed_before = level._elp_anchors_freed;

    ents_before = -1;
    if (isdefined(level.diag_ent_count))
        ents_before = int(level.diag_ent_count);

    // Place a synthetic anchor on every live zombie that doesn't already have one.
    // This replicates exactly what do_zombie_rise() does at line 2784 in _zm_spawner.gsc.
    anchors_placed = 0;
    for (i = 0; i < ai.size; i++)
    {
        if (!isdefined(ai[i]) || !isalive(ai[i]))
            continue;
        if (isdefined(ai[i].anchor))
            continue;

        ai[i].anchor = spawn("script_origin", ai[i].origin);
        anchors_placed++;
    }

    logprint("[ST] ELPSYNTH placed " + anchors_placed + " synthetic anchors"
        + " (elp=" + elp_loaded + ")\n");

    // Kill immediately — without ELP every anchor now leaks permanently.
    count = st_kill_all_zombies();

    // Give ELP watchdog threads time to fire.
    wait 0.5;

    // Snapshot after — wait another 0.1s for diag loop to refresh.
    wait 0.6;

    freed_after = 0;
    if (isdefined(level._elp_anchors_freed))
        freed_after = level._elp_anchors_freed;

    ents_after = -1;
    if (isdefined(level.diag_ent_count))
        ents_after = int(level.diag_ent_count);

    delta_freed = freed_after - freed_before;
    ent_delta   = ents_after - ents_before;

    logprint("[ST] ELPSYNTH result"
        + " anchors_placed=" + anchors_placed
        + " killed=" + count
        + " anchors_freed=" + delta_freed
        + " ent_delta=" + ent_delta
        + " elp=" + elp_loaded
        + "\n");

    iprintln("^3[ST] elpsynth: placed=" + anchors_placed
        + " freed=" + delta_freed
        + " ent_delta=" + ent_delta
        + (elp_loaded ? " ^2(ELP on)" : " ^1(ELP off — control)"));

    if (!elp_loaded)
    {
        iprintln("^1[ST] Control run: " + anchors_placed + " anchors now leaked");
        iprintln("^3[ST] Re-run with ELP loaded to compare freed count");
    }
    else if (delta_freed == anchors_placed)
        iprintln("^2[ST] ELP PASS: all " + anchors_placed + " synthetic anchors freed");
    else if (delta_freed < anchors_placed)
        iprintln("^1[ST] ELP PARTIAL: " + delta_freed + "/" + anchors_placed + " freed");
    else
        iprintln("^1[ST] ELP ANOMALY: freed more than placed — check log");
}

// --- ELP: PER-ZOMBIE ANCHOR-WINDOW KILL ---
//
// The anchor in do_zombie_rise()/do_zombie_spawn() exists for only ~50-100ms
// (a moveto(0.05) + optional rotateto(0.05) to position the zombie at its spot).
// The visual rise animation begins AFTER the anchor is deleted.
//
// This mode injects a per-zombie watchdog that fires one GSC frame (~50ms) after
// each zombie spawns and kills it if self.anchor is still set.  That is the only
// timing that can reliably catch the anchor window.
//
// How it works:
//   Appends a kill-on-next-frame thread to level._zombie_custom_spawn_logic.
//   The spawner calls that hook right before threading do_zombie_rise().
//   One frame later our thread runs, catches self.anchor mid-moveto, and kills.
//   The ELP watchdog (already on the zombie) fires, frees the anchor, increments
//   level._elp_anchors_freed.
//
// What to look for:
//   [ELP] R2 — anchors freed this round: 6 (total: 6)
//
// Disarm: set st_cmd stop  (clears _stress_ramp_active)
//
// NOTE: this will kill every zombie as it spawns, making normal play impossible.
// It is purely a diagnostic mode to confirm ELP is functional.
//
// Usage: set st_cmd elpkill

st_cmd_elpkill()
{
    if (level._stress_ramp_active)
    {
        iprintln("^1[ST] Another automated mode is running. Use /st stop first.");
        return;
    }

    // ELP patch is optional — elpkill works without it as a control/leak run.
    // Without ELP: anchors killed mid-window are never freed, entity count climbs.
    // With ELP:    watchdog frees every anchor, entity count stays flat.
    elp_loaded = isdefined(level._elp_version);
    if (!elp_loaded)
    {
        iprintln("^1[ST] ELP not loaded — running as CONTROL (leaks will accumulate)");
        iprintln("^3[ST] Watch Ent Tally grow each round vs ELP-on baseline");
        logprint("[ST] elpkill armed (CONTROL — no ELP loaded)\n");
    }
    else
    {
        logprint("[ST] elpkill armed\n");
    }

    // Append our per-zombie kill thread to the spawn hook.
    // Safe to add on top of whatever ELP already installed.
    if (!isdefined(level._zombie_custom_spawn_logic))
    {
        level._zombie_custom_spawn_logic = ::st_elp_kill_in_anchor_window;
    }
    else if (isarray(level._zombie_custom_spawn_logic))
    {
        level._zombie_custom_spawn_logic[level._zombie_custom_spawn_logic.size] = ::st_elp_kill_in_anchor_window;
    }
    else
    {
        prior = level._zombie_custom_spawn_logic;
        level._zombie_custom_spawn_logic    = [];
        level._zombie_custom_spawn_logic[0] = prior;
        level._zombie_custom_spawn_logic[1] = ::st_elp_kill_in_anchor_window;
    }

    level._stress_ramp_active   = 1;
    level._st_elpkill_active    = 1;

    if (elp_loaded)
        iprintln("^2[ST] elpkill armed (ELP ON) — watch [ELP] RN anchors freed");
    else
        iprintln("^1[ST] elpkill armed (ELP OFF) — anchor leaks accumulate in pool");

    // Log per-round entity count so control and patched runs can be compared.
    level thread st_elpkill_round_log();
}

// Logs entity count and mid-anchor kill count at every round boundary while
// elpkill is active.  Works with or without ELP loaded — the freed count is
// taken from level._elp_anchors_freed if defined, otherwise shown as "--".
// This gives a per-round entity tally to compare control vs patched runs.
st_elpkill_round_log()
{
    level endon("end_game");

    prev_freed  = 0;
    if (isdefined(level._elp_anchors_freed))
        prev_freed = level._elp_anchors_freed;

    for (;;)
    {
        level waittill("start_of_round");

        if (!level._st_elpkill_active)
            break;

        ent_count = "--";
        if (isdefined(level.diag_ent_count))
            ent_count = int(level.diag_ent_count);

        freed_str = "--";
        freed_delta = "--";
        if (isdefined(level._elp_anchors_freed))
        {
            freed_delta = level._elp_anchors_freed - prev_freed;
            freed_str   = level._elp_anchors_freed;
            prev_freed  = level._elp_anchors_freed;
        }

        elp_tag = "ELP=off";
        if (isdefined(level._elp_version))
            elp_tag = "ELP=on";

        logprint("[ST] elpkill R" + level.round_number
            + " ent=" + ent_count
            + " anchors_freed_this_round=" + freed_delta
            + " total_freed=" + freed_str
            + " " + elp_tag + "\n");
    }
}

// Threaded on each zombie via _zombie_custom_spawn_logic.
// The spawner calls us just before threading do_zombie_rise(), so
// self.anchor is not yet set.  Yield one frame — that is when
// do_zombie_rise sets the anchor and begins the 0.05s moveto.
//
// We kill regardless of whether the anchor is still set.  This means:
//   - Zombie with anchor (caught in the ~50ms window): ELP watchdog fires,
//     freed counter increments.  Log line includes "mid-anchor".
//   - Zombie without anchor (already past window): killed cleanly, no hoard
//     builds up, godmode stay bearable.
//
// The ELP per-round log will tell us how many of each round's kills had
// anchors at death time.
st_elp_kill_in_anchor_window()
{
    if (!isdefined(level._st_elpkill_active) || !level._st_elpkill_active)
        return;

    // One GSC frame: do_zombie_rise has now set self.anchor and started moveto.
    wait 0.05;

    if (!isdefined(self) || !isalive(self))
        return;

    had_anchor = isdefined(self.anchor);

    self dodamage(self.health + 666, self.origin);

    if (had_anchor)
        logprint("[ST] elpkill: killed mid-anchor\n");
}

// --- ELP: SINGLE-SHOT MEASUREMENT ---
//
// Immediately kills all active zombies and prints a before/after comparison:
//   - entity count delta (should be ≤ 0 if ELP is working; orphaned anchors would
//     show as positive growth without the patch)
//   - anchors freed this run (from level._elp_anchors_freed set by ELP patch)
//
// Run from the console any time zombies are active mid-animation.  Best used right
// after /st killrise fires automatically, or manually when you see zombies rising.
//
// Usage: set st_cmd elp
st_cmd_elp()
{
    r = 0;
    if (isdefined(level.round_number))
        r = level.round_number;

    // Snapshot before.
    ents_before = -1;
    if (isdefined(level.diag_ent_count))
        ents_before = int(level.diag_ent_count);

    freed_before = 0;
    if (isdefined(level._elp_anchors_freed))
        freed_before = level._elp_anchors_freed;
    elp_loaded = isdefined(level._elp_version);

    // Kill everyone and wait one GSC frame for ELP watchdogs to fire.
    count = st_kill_all_zombies();
    wait 0.1;

    // Snapshot after — diag loop updates every 0.5s so wait for a fresh sample.
    wait 0.6;

    ents_after = -1;
    if (isdefined(level.diag_ent_count))
        ents_after = int(level.diag_ent_count);

    freed_after = 0;
    if (isdefined(level._elp_anchors_freed))
        freed_after = level._elp_anchors_freed;

    delta_ents   = ents_after - ents_before;
    delta_freed  = freed_after - freed_before;

    logprint("[ST] ELP_TEST R" + r
        + " killed=" + count
        + " ents_before=" + ents_before
        + " ents_after=" + ents_after
        + " ent_delta=" + delta_ents
        + " anchors_freed=" + delta_freed
        + " elp_loaded=" + elp_loaded
        + "\n");

    iprintln("^3[ST] ELP test R" + r + ": killed " + count
        + " | ent delta: " + delta_ents
        + " | anchors freed: " + delta_freed);

    if (!elp_loaded)
        iprintln("^1[ST] WARNING: zm_patch_entity_leaks not loaded — no watchdog active");
    else if (count > 0 && delta_freed == 0)
        iprintln("^3[ST] No anchors freed — zombies may have completed animation already");
}

// --- EL-01: LERP RAMP TEST ---
//
// Automated multi-round test for the EL-01 lerp() entity leak fix.
//
// Each round:
//   1. Waits ST_LERPRAMP_WAIT seconds after start_of_round (zombies walk to barriers).
//   2. Drains the spawn queue (zombie_total=0) so no further zombies spawn this wave.
//   3. Kills all zombies WITHOUT self._lerp_link (roaming, chasing, post-lerp).
//   4. The fftest lerp watcher (zm_test_ff.gsc) detects _lerp_link on surviving
//      zombies, kills them mid-lerp, and increments level._fftest_lerp_detected.
//   5. Logs per-round metrics, then waits for the game to naturally end the round.
//      Round advancement (health, speed, timing) is handled by the normal game loop.
//
// Requires zm_test_ff.gsc (for _fftest_lerp_detected + per-zombie watcher).
// Without it, lerp_detected is unavailable — falls back to probe_hr only.
//
// Per-round log (search LERPRAMP):
//   [ST] LERPRAMP R5: nonlerp_killed=14 lerp_detected=6 probe_hr=128 ents=244->238
//
// End summary:
//   [ST] LERPRAMP done R1->R20: total_lerp_detected=91 total_nonlerp_killed=240
//
// Usage:
//   set st_cmd god                     -- recommended: god mode so non-lerp zombies can't down you
//   set st_cmd lerpramp 20             -- stop after 20 rounds (/st stop to abort early)
//   set st_cmd lerpramp                -- run indefinitely (/st stop to abort)
//
// Pass/fail:
//   PASS: lerp_detected > 0 each round  — FF patch active, _lerp_link being set
//   FAIL: lerp_detected == 0 after 3+ rounds — unpatched _zm_utility in FF

#define ST_LERPRAMP_WAIT 5.0

st_cmd_lerpramp(arg)
{
    if (level._stress_ramp_active)
    {
        iprintln("^1[ST] Another automated mode is running. Use /st stop first.");
        return;
    }

    target = 0;
    if (isdefined(arg) && arg != "")
        target = int(arg);

    start_r = 1;
    if (isdefined(level.round_number))
        start_r = level.round_number;

    if (target > 0 && target <= start_r)
    {
        iprintln("^1[ST] Target must be greater than current round (" + start_r + ")");
        return;
    }

    // Arm the EL-01 lerp watcher if zm_test_ff is loaded.
    fftest_loaded = isdefined(level._fftest_lerp_detected);
    if (fftest_loaded)
    {
        level._fftest_el01_armed    = 1;
        level._fftest_lerp_detected = 0;
        level._fftest_lerp_kills    = 0;
        iprintln("^2[ST] fftest EL-01 watcher armed");
    }
    else
    {
        iprintln("^3[ST] zm_test_ff not loaded — lerp_detected unavailable, using probe_hr only");
    }

    level._stress_ramp_active = 1;

    run_str = (target > 0 ? "R" + start_r + "->R" + target : "R" + start_r + " indefinitely");
    logprint("[ST] LERPRAMP start " + run_str + " fftest=" + fftest_loaded + "\n");
    iprintln("^2[ST] lerpramp " + run_str + " — non-lerp zombies auto-killed, watcher handles mid-lerp");
    iprintln("^3[ST] Tip: run ^2set st_cmd god ^3first so non-lerp zombies can't down you");

    level endon("end_game");

    total_nonlerp_killed = 0;
    total_lerp_detected  = 0;
    rounds_run           = 0;

    for (;;)
    {
        if (!level._stress_ramp_active) break;
        if (target > 0 && rounds_run >= target) break;

        level waittill("start_of_round");

        if (!level._stress_ramp_active) break;
        if (target > 0 && rounds_run >= target) break;

        // Give zombies time to walk to barriers and enter lerp().
        wait ST_LERPRAMP_WAIT;

        r = level.round_number;

        lerp_before = 0;
        if (fftest_loaded && isdefined(level._fftest_lerp_detected))
            lerp_before = level._fftest_lerp_detected;

        ents_before = -1;
        if (isdefined(level.diag_ent_count))
            ents_before = int(level.diag_ent_count);

        probe_hr = -1;
        if (isdefined(level.diag_entity_headroom))
            probe_hr = level.diag_entity_headroom;

        // Drain spawn queue — no more zombies will spawn this wave.
        // The game ends the round naturally once the last zombie dies;
        // health, speed, and round number are set by the normal game loop.
        level.zombie_total          = 0;
        level.zombie_total_subtract = 0;

        // Kill zombies NOT in lerp; lerp watcher handles the mid-lerp ones.
        nonlerp_killed = st_kill_nonlerp_zombies();
        total_nonlerp_killed += nonlerp_killed;

        // Wait for per-zombie lerp watcher threads to detect _lerp_link,
        // kill remaining mid-lerp zombies, and let the EL-01 watchdog clean up.
        // Watcher polls every 50ms; allow several cycles + watchdog cleanup.
        wait 1.5;

        lerp_after = 0;
        if (fftest_loaded && isdefined(level._fftest_lerp_detected))
            lerp_after = level._fftest_lerp_detected;

        // Diag loop refresh (0.5s cadence).
        wait 0.6;

        ents_after = -1;
        if (isdefined(level.diag_ent_count))
            ents_after = int(level.diag_ent_count);

        lerp_this_round = lerp_after - lerp_before;
        total_lerp_detected += lerp_this_round;

        logprint("[ST] LERPRAMP R" + r
            + ": nonlerp_killed=" + nonlerp_killed
            + " lerp_detected=" + lerp_this_round
            + " probe_hr=" + probe_hr
            + " ents=" + ents_before + "->" + ents_after
            + "\n");

        result_color = (lerp_this_round > 0 ? "^2" : "^3");
        iprintln(result_color + "[ST] LERPRAMP R" + r
            + ": nonlerp=" + nonlerp_killed
            + " lerp_detected=" + lerp_this_round
            + " ^7probe=" + probe_hr
            + " ents=" + ents_before + "->" + ents_after);

        if (fftest_loaded && lerp_this_round == 0 && rounds_run >= 3)
            iprintln("^1[ST] LERPRAMP WARNING: 0 lerp detections at R" + r + " — FF may be inactive");

        // Round ends naturally when the last zombie dies.
        // waittill("start_of_round") at the top of the loop picks it up.
        rounds_run++;
    }

    level._stress_ramp_active = 0;

    final_hr = -1;
    if (isdefined(level.diag_entity_headroom))
        final_hr = level.diag_entity_headroom;

    logprint("[ST] LERPRAMP done R" + start_r + "->R" + level.round_number
        + ": total_lerp_detected=" + total_lerp_detected
        + " total_nonlerp_killed=" + total_nonlerp_killed
        + " rounds_run=" + rounds_run
        + " final_probe_hr=" + final_hr
        + " fftest=" + fftest_loaded
        + "\n");

    iprintln("^2[ST] lerpramp done — " + rounds_run + " rounds");
    iprintln("^7  total lerp_detected: " + total_lerp_detected
        + "  nonlerp_killed: " + total_nonlerp_killed
        + "  final probe_hr: " + final_hr);

    if (!fftest_loaded)
        iprintln("^3[ST] Load zm_test_ff.gsc for lerp_detected metric next run");
    else if (total_lerp_detected == 0)
        iprintln("^1[ST] LERPRAMP FAIL: 0 lerp detections — _zm_utility FF replacement NOT active");
    else
        iprintln("^2[ST] LERPRAMP PASS: _lerp_link detected in " + total_lerp_detected + " zombies across " + rounds_run + " rounds");
}

// --- EL-01: CONTINUOUS LERP WATCH ---
//
// Kills non-lerp zombies on a tight loop so the player isn't overwhelmed,
// while the fftest lerp watcher (zm_test_ff.gsc) handles barrier zombies.
// No round management — waves proceed naturally, new zombies keep spawning,
// and lerp_detected accumulates across the whole session.
//
// This is the simplest EL-01 test: stand near barrier windows, arm this mode,
// and let the session run.  Every 10s the current lerp_detected count is logged.
//
// Usage:
//   set st_cmd god        -- recommended
//   set st_cmd lerpwatch  -- arm; zombies at barriers get detected, rest auto-killed
//   set st_cmd stop       -- disarm and print final count
//
// Pass/fail (check final summary or log for "lerpwatch"):
//   PASS: lerp_detected > 0           — FF active, _lerp_link being set
//   FAIL: lerp_detected == 0 after ~30s near barriers — FF not active

#define ST_LERPWATCH_POLL    0.5   // seconds between non-lerp kill sweeps
#define ST_LERPWATCH_LOG_INT 20    // log every N poll ticks (~10s)

st_cmd_lerpwatch()
{
    if (level._stress_ramp_active)
    {
        iprintln("^1[ST] Another automated mode is running. Use /st stop first.");
        return;
    }

    fftest_loaded = isdefined(level._fftest_lerp_detected);
    if (fftest_loaded)
    {
        level._fftest_el01_armed    = 1;
        level._fftest_lerp_detected = 0;
        level._fftest_lerp_kills    = 0;
        iprintln("^2[ST] fftest EL-01 watcher armed");
    }
    else
    {
        iprintln("^3[ST] zm_test_ff not loaded — lerp_detected unavailable");
    }

    level._stress_ramp_active = 1;
    logprint("[ST] lerpwatch armed\n");
    iprintln("^2[ST] lerpwatch armed — non-lerp zombies killed every " + ST_LERPWATCH_POLL + "s");
    iprintln("^3[ST] Stand near barrier windows. /st stop to disarm and print summary.");

    level endon("end_game");

    ticks = 0;

    for (;;)
    {
        if (!level._stress_ramp_active) break;

        wait ST_LERPWATCH_POLL;

        if (!level._stress_ramp_active) break;

        if (isdefined(level.zombie_team))
            st_kill_nonlerp_zombies();

        ticks++;

        if (ticks % ST_LERPWATCH_LOG_INT == 0)
        {
            detected = 0;
            if (isdefined(level._fftest_lerp_detected))
                detected = level._fftest_lerp_detected;

            r = 0;
            if (isdefined(level.round_number))
                r = level.round_number;

            logprint("[ST] lerpwatch R" + r + " lerp_detected=" + detected + "\n");
            iprintln("^3[ST] lerpwatch R" + r + " — lerp_detected so far: ^2" + detected);
        }
    }

    level._stress_ramp_active = 0;

    detected = 0;
    if (isdefined(level._fftest_lerp_detected))
        detected = level._fftest_lerp_detected;

    logprint("[ST] lerpwatch disarmed lerp_detected=" + detected + "\n");
    iprintln("^3[ST] lerpwatch disarmed — total lerp_detected: ^2" + detected);

    if (fftest_loaded)
    {
        if (detected == 0)
            iprintln("^1[ST] FAIL: 0 lerp detections — FF not active or no barrier zombies seen");
        else
            iprintln("^2[ST] PASS: _lerp_link seen on " + detected + " zombies");
    }
}

// Kill all zombies that are NOT currently in their lerp() barrier-attack animation.
// Zombies with self._lerp_link set are mid-animation — skip them so the
// fftest lerp watcher can detect them, log them, and kill them cleanly.
// Everything else (spawning, roaming, chasing, post-lerp) is killed here.
st_kill_nonlerp_zombies()
{
    if (!isdefined(level.zombie_team))
        return 0;

    ai = getaiarray(level.zombie_team);
    killed = 0;

    if (!isdefined(ai))
        return 0;

    for (i = 0; i < ai.size; i++)
    {
        if (!isdefined(ai[i]) || !isalive(ai[i]))
            continue;

        if (isdefined(ai[i]._lerp_link))
            continue;  // mid-lerp — watcher will detect, kill, and log this one

        ai[i] dodamage(ai[i].health + 666, ai[i].origin);
        killed++;

        if (killed % 5 == 0)
            wait 0.05;
    }

    return killed;
}

st_cmd_stop()
{
    if (!level._stress_ramp_active)
    {
        iprintln("^3[ST] No ramp is running");
        return;
    }
    level._stress_ramp_active = 0;
    if (isdefined(level._st_elpkill_active))
        level._st_elpkill_active = 0;
    iprintln("^3[ST] Stop signal sent — ramp will halt after current step");
}

// --- MAP-SPECIFIC TEST WEAPON HELPERS ---

// Give the fully upgraded Fire Staff for SA-10 testing (zm_origins only).
// staff_fire_upgraded3_zm is the max-upgraded form that triggers the AoE
// dedup logic in _zm_weap_staff_fire.gsc::staff_fire_aoe_damage().
// Give an upgraded Origins staff with working ammo.
// giveweapon must be called with PaP options for upgraded weapons, otherwise
// Give the base (un-upgraded) Fire Staff to check whether it has ammo by default.
// Use this to find the right base→upgrade path before testing SA-10.
st_cmd_givebasestaff()
{
    weap = "staff_fire_zm";
    self giveweapon(weap);
    if (!self hasweapon(weap))
    {
        iprintln("^1[ST] giveweapon failed for " + weap);
        return;
    }
    self switchtoweapon(weap);
    clip  = self getweaponammoclip(weap);
    stock = self getweaponammostock(weap);
    iprintln("^2[ST] Given " + weap + " — ammo: " + clip + "/" + stock);
    logprint("[ST] givebasestaff: " + weap + " clip=" + clip + " stock=" + stock + "\n");
}

// Shared helper for all four upgraded Origins staves (zm_origins only).
//
// All charger-station upgrades share the same give sequence:
//   1. Give staff_revive_zm first — watch_staff_usage() in zm_tomb_utility.gsc
//      enforces that an upgraded staff can only be held alongside the Zombie
//      Shield; without it the weapon is revoked on the next weapon_change event.
//   2. Plain giveweapon (no get_pack_a_punch_weapon_options — staves are not PaP
//      weapons and that call crashes on them).
//   3. Ammo via weaponclipsize/weaponmaxammo, mirroring zm_tomb_craftables.gsc
//      lines 1149-1152. Falls back to 9/81 if the weapon table says 0.
st_cmd_give_upgraded_staff(weap, hint)
{
    self giveweapon("staff_revive_zm");
    self giveweapon(weap);
    if (!self hasweapon(weap))
    {
        iprintln("^1[ST] giveweapon failed for " + weap + " — zm_origins only");
        return;
    }
    n_clip  = weaponclipsize(weap);
    n_stock = weaponmaxammo(weap);
    if (n_clip  <= 0) n_clip  = 9;
    if (n_stock <= 0) n_stock = 81;
    self setweaponammoclip(weap, n_clip);
    self setweaponammostock(weap, n_stock);
    self switchtoweapon(weap);
    iprintln("^2[ST] Given " + weap + " + staff_revive_zm — " + n_clip + "/" + n_stock);
    if (isdefined(hint))
        iprintln("^3[ST] " + hint);
    logprint("[ST] give_upgraded_staff: gave " + weap + " clip=" + n_clip + " stock=" + n_stock + "\n");
}

st_cmd_givestafffire()
{
    self st_cmd_give_upgraded_staff("staff_fire_upgraded_zm",
        "SA-10 test: fire into 5+ zombies. Run 'sa10stat' after to check dedup counter.");
}

st_cmd_givestaffair()
{
    self st_cmd_give_upgraded_staff("staff_air_upgraded_zm",
        "MI-06 test: HOLD fire to charge, release for whirlwind. Run 'mi06test' for auto-check.");
}

st_cmd_givestafflightning()
{
    self st_cmd_give_upgraded_staff("staff_lightning_upgraded_zm",
        "HOLD fire to charge, release for chain-lightning AoE (upgraded2/3 projectile).");
}

st_cmd_givestaffwater()
{
    self st_cmd_give_upgraded_staff("staff_water_upgraded_zm",
        "HOLD fire to charge, release for ice-prison AoE.");
}

// Give all four upgraded staves + zombie shield at once.
// Only one staff can be the active weapon, but all four sit in the primary
// weapon slots so you can cycle between them with the weapon switch bind.
// Note: plain giveweapon does not enforce the normal 2-primary slot limit,
// so all four staves coexist in inventory.
st_cmd_giveallstaffs()
{
    self giveweapon("staff_revive_zm");
    self st_cmd_give_upgraded_staff("staff_fire_upgraded_zm", undefined);
    self st_cmd_give_upgraded_staff("staff_air_upgraded_zm", undefined);
    self st_cmd_give_upgraded_staff("staff_lightning_upgraded_zm", undefined);
    self st_cmd_give_upgraded_staff("staff_water_upgraded_zm", undefined);
    iprintln("^2[ST] All four upgraded staves given.");
    iprintln("^7[ST] Cycle with weapon switch. HOLD fire on each to charge.");
    logprint("[ST] giveallstaffs: all four upgraded staves given\n");
}

// Legitimacy check: skip to R50, enable god mode, give all four staves, and
// print what to fire and what to expect for each one. All staff behavior is
// registered at onplayerconnect — not during weapon pickup — so staves given
// via giveweapon are functionally identical to naturally crafted ones.
//
// Expected behavior at R50+:
//   Fire   — AoE fireball: zombies ignite and burn. Single-target instant kill
//             on direct hit. With SA-10 patched, each zombie gets exactly one
//             burn thread — no stacked ticks, normal kill speed.
//   Wind   — Charged shot: whirlwind anchors to nearest alive zombie and pulls
//             the horde inward. With MI-06 patched, anchors correctly even when
//             zombie[0] in the sorted array is dead.
//   Lightning — Charged shot: bolt chains between zombies, killing whole groups
//             in one discharge at R50+.
//   Water  — Charged shot: ice-prison encases nearby zombies, then shatters.
//             Reliable crowd-freeze + mass kill at high rounds.
st_cmd_stafflegit()
{
    iprintln("^3[ST] stafflegit: skipping to R50, enabling god mode, giving all staves...");
    level thread st_cmd_skip(50);
    self thread st_cmd_god();
    wait 0.5; // let skip arm before giving weapons
    self st_cmd_giveallstaffs();

    wait 0.2;
    iprintln("^7[ST] --- STAFF LEGITIMACY GUIDE ---");
    iprintln("^2[ST] Fire  ^7CHARGE shot → ignites horde. Deals fixed ~24k dmg (20k impact + DOT).");
    iprintln("^7[ST]        NOT a high-round killer — fire staff has fixed damage by design.");
    iprintln("^7[ST]        Unpatched SA-10 stacked 25 impact hits (500k) making it appear to scale.");
    iprintln("^2[ST] Wind  ^7CHARGE shot → whirlwind anchors to nearest alive zombie, pulls horde.");
    iprintln("^2[ST] Elec  ^7CHARGE shot → chain bolt, high fixed damage, good to ~R80.");
    iprintln("^2[ST] Water ^7CHARGE shot → blizzard deals self.health damage (true insta-kill any round).");
    iprintln("^7[ST] Only Water scales infinitely. Fire/Wind/Elec are mid-game weapons by design.");
    logprint("[ST] stafflegit: skip=50 god=1 all staves given\n");
}

// --- SA-10 / MI-06 AUTOMATED TESTS ---
//
// sa10test  — arms the SA-10 dedup counter, then fires after each blast and
//             reports how many redundant flame_damage_fx calls were blocked.
//             Patched + working: counter climbs per fire blast (every already-
//             burning zombie's re-check is blocked).  Counter = 0 means the
//             dedup never fired — something is wrong.
//
// sa10stat  — print and reset the SA-10 counter without re-arming.
//
// mi06test  — arms the MI-06 round-completion monitor. Fire a charged wind
//             shot (hold fire, release), then kill the remaining zombies.
//             The monitor checks: (a) the patch redirect counter (how many
//             times the fix chose zombie[i] over dead zombie[0]) and (b)
//             whether level.zombie_total reaches 0 after all visible zombies
//             die (soft-lock detection).
//
// mi06stat  — print and reset MI-06 counters without re-arming.

// Enable SA-10 diagnostic counter and arm per-blast reporter.
st_cmd_sa10test()
{
    st_cmd_givestafffire();
    level._hrp_sa10_diag    = 1;
    level._hrp_sa10_blocked = 0;
    iprintln("^2[ST] SA-10 diagnostic ARMED — counter reset to 0.");
    iprintln("^3[ST] Fire into 3+ zombies. Each tick where the dedup blocks");
    iprintln("^3[ST] a redundant flame thread increments the counter.");
    iprintln("^3[ST] Run 'sa10stat' after firing to see results.");
    logprint("[ST] sa10test: diagnostic armed\n");
}

// Print current SA-10 blocked count and reset it.
st_cmd_sa10stat()
{
    if (!isdefined(level._hrp_sa10_blocked))
        level._hrp_sa10_blocked = 0;

    n = level._hrp_sa10_blocked;
    level._hrp_sa10_blocked = 0;

    if (n > 0)
        iprintln("^2[ST] SA-10 PASS: " + n + " redundant flame threads blocked since last reset.");
    else
        iprintln("^1[ST] SA-10 WARN: counter is 0 — either no zombies were already burning");
    iprintln("^7[ST]   when the next AoE tick fired, or the dedup is not working.");
    logprint("[ST] sa10stat: blocked=" + n + "\n");
}

// Arm MI-06 monitoring: enable the redirect counter and start round-end watcher.
st_cmd_mi06test()
{
    st_cmd_givestaffair();
    level._hrp_mi06_diag  = 1;
    level._hrp_mi06_saved = 0;
    iprintln("^2[ST] MI-06 diagnostic ARMED — counter reset to 0.");
    iprintln("^3[ST] Kill all but 2 zombies. Kill the one CLOSER to where you");
    iprintln("^3[ST] will aim. Hold fire to charge, release for whirlwind shot.");
    iprintln("^3[ST] Then kill the remaining zombie. Monitor auto-reports.");
    self thread st_mi06_monitor();
    logprint("[ST] mi06test: diagnostic armed\n");
}

// Background watcher: once all visible zombies die, check whether the round
// system also sees zero. A mismatch means a phantom zombie (soft-lock).
st_mi06_monitor()
{
    self endon("disconnect");

    // Wait until the player fires a charged wind shot (projectile impact).
    iprintln("^7[ST] MI-06 monitor: waiting for charged wind shot...");
    while (true)
    {
        self waittill("projectile_impact", str_weap);
        if (str_weap == "staff_air_upgraded2_zm" || str_weap == "staff_air_upgraded3_zm")
            break;
    }
    iprintln("^7[ST] MI-06 monitor: charged shot detected — waiting for zombies to die...");

    // Wait until no alive zombies remain (with 60s safety timeout).
    t_start = gettime();
    while (true)
    {
        n_alive = 0;
        a_all = getaiarray(level.zombie_team);
        foreach (z in a_all)
        {
            if (isalive(z))
                n_alive++;
        }
        if (n_alive == 0)
            break;
        if ((gettime() - t_start) > 60000)
        {
            iprintln("^3[ST] MI-06 monitor: timed out waiting for all zombies to die.");
            return;
        }
        wait 0.5;
    }

    // Give the round system a moment to process deaths.
    wait 1.0;

    n_saved  = isdefined(level._hrp_mi06_saved) ? level._hrp_mi06_saved : 0;
    n_total  = level.zombie_total;

    // SA-10 PASS: round system should agree (zombie_total == 0).
    if (n_total <= 0)
    {
        iprintln("^2[ST] MI-06 PASS: round ended cleanly (zombie_total=0).");
        if (n_saved > 0)
            iprintln("^2[ST]   Fix redirected " + n_saved + " shot(s) away from dead zombie[0].");
        else
            iprintln("^3[ST]   Redirect counter=0: zombie[0] may have been alive — try again with zombie[0] dead.");
    }
    else
    {
        iprintln("^1[ST] MI-06 FAIL: soft-lock! zombie_total=" + n_total + " but 0 alive zombies.");
        iprintln("^1[ST]   Whirlwind anchored to a dead/recycled entity — round cannot complete.");
    }
    logprint("[ST] mi06monitor: zombie_total=" + n_total + " mi06_saved=" + n_saved + "\n");
}

// Print and reset MI-06 counters manually.
st_cmd_mi06stat()
{
    n_saved = isdefined(level._hrp_mi06_saved) ? level._hrp_mi06_saved : 0;
    level._hrp_mi06_saved = 0;
    iprintln("^2[ST] MI-06 stat: redirect_saved=" + n_saved);
    iprintln("^7[ST]   (times fix chose zombie[i] over dead zombie[0] since last reset)");
    logprint("[ST] mi06stat: saved=" + n_saved + "\n");
}

// --- MI-11: ELEVATOR ROOF WATCHER DISPATCH COUNTER ---
//
// MI-11 was `continue` instead of `break` in elevator_roof_watcher().
// The loop iterated every zombie and overwrote `climber` on each pass,
// so only the LAST zombie in getaiarray() could trigger a climb.
// Fixed: `break` exits on the first valid climber found.
//
// mi11test  — arms _hrp_mi11_diag and resets both counters.
//             Stand on an elevator roof in zm_highrise with the power on.
//             The patch's `elevator_roof_watcher` will increment:
//               _hrp_mi11_dispatched  — a valid climber was found and climb fired
//               _hrp_mi11_no_climber  — loop found no unseen zombie (poll returned nothing)
//             With the fix: dispatched >> no_climber (climb fires on first unseen zombie).
//             Bug mode (no fix): no_climber dominates because the loop's result
//             depended on whether the very last array entry happened to be unseen.
//
// mi11stat  — print and reset both counters.
//
// Note: counters live in the compiled elevator source (zm_highrise_elevators.gsc →
// mod.ff). If _hrp_mi11_dispatched is never defined after arming, the elevator code
// is running from the unpatched zm_highrise.ff instead of mod.ff.

// Arm MI-11 dispatch counters.
st_cmd_mi11test()
{
    level._hrp_mi11_diag       = 1;
    level._hrp_mi11_dispatched = 0;
    level._hrp_mi11_no_climber = 0;
    iprintln("^2[ST] MI-11 diagnostic ARMED — counters reset to 0.");
    iprintln("^3[ST] Map: zm_highrise only. Turn on power, go to an upper");
    iprintln("^3[ST] floor and stand on an elevator roof trigger for 2+ min.");
    iprintln("^3[ST] Run 'mi11stat' to see dispatched vs no-climber ratio.");
    logprint("[ST] mi11test: diagnostic armed\n");
}

// Print and reset MI-11 counters.
st_cmd_mi11stat()
{
    n_disp  = isdefined(level._hrp_mi11_dispatched) ? level._hrp_mi11_dispatched : 0;
    n_none  = isdefined(level._hrp_mi11_no_climber)  ? level._hrp_mi11_no_climber  : 0;
    level._hrp_mi11_dispatched = 0;
    level._hrp_mi11_no_climber  = 0;

    if (!isdefined(level._hrp_mi11_diag))
    {
        iprintln("^3[ST] MI-11 diagnostic not armed — run 'mi11test' first.");
        return;
    }

    total = n_disp + n_none;
    iprintln("^2[ST] MI-11 stat: dispatched=" + n_disp + "  no_climber=" + n_none
           + "  total_polls=" + total);

    if (total == 0)
        iprintln("^3[ST]   No polls recorded yet — stand on elevator roof longer.");
    else if (n_disp > n_none)
        iprintln("^2[ST]   PASS: climb dispatch firing reliably (fix is working).");
    else
        iprintln("^1[ST]   WARN: no_climber >= dispatched — climbs rarely firing.");

    logprint("[ST] mi11stat: dispatched=" + n_disp + " no_climber=" + n_none
           + " total=" + total + "\n");
}

// Insertion sort of an AI array by distance-squared from v_origin.
// Replaces get_array_of_closest, which is only available inside map scripts.
st_sort_by_distance(v_origin, a_in)
{
    a_out = [];
    for (i = 0; i < a_in.size; i++)
        a_out[i] = a_in[i];

    for (i = 1; i < a_out.size; i++)
    {
        cur = a_out[i];
        d_cur = distancesquared(v_origin, cur.origin);
        j = i - 1;
        while (j >= 0 && distancesquared(v_origin, a_out[j].origin) > d_cur)
        {
            a_out[j + 1] = a_out[j];
            j--;
        }
        a_out[j + 1] = cur;
    }

    return a_out;
}

// Automated MI-06 test: no timing skill required.
//
// Gives the wind staff, kills all but the 2 zombies closest to the player,
// then counts down 5 seconds so you can pre-charge the whirlwind shot.  On
// zero the script kills zombie[0] (the closer zombie) — just release the
// charge button when it drops.  The MI-06 monitor auto-reports the result.
//
// Sorting is by distance from the player's position, which matches the
// distance-from-detonation order that _zm_weap_staff_air uses when the player
// aims toward the zombies.  Stand between the two remaining zombies and aim
// at the farther one to ensure the detonation point is equidistant from both.
st_cmd_mi06auto()
{
    self endon("disconnect");

    // Arm the staff and diagnostic (gives wind staff, resets counter, starts monitor).
    st_cmd_mi06test();

    // Kill down to the 2 alive zombies closest to the player.
    ai = getaiarray(level.zombie_team);
    if (!isdefined(ai))
    {
        iprintln("^1[ST] mi06auto: no zombies alive.");
        return;
    }

    ai = st_sort_by_distance(self.origin, ai);

    kept = 0;
    for (i = 0; i < ai.size; i++)
    {
        if (!isdefined(ai[i]) || !isalive(ai[i]))
            continue;
        kept++;
        if (kept > 2)
            ai[i] dodamage(ai[i].health + 666, ai[i].origin);
    }

    // Wait for the kill-flood to process.
    wait 1.0;

    // Re-fetch and re-sort — grab the closer of the two survivors.
    ai = getaiarray(level.zombie_team);
    ai = st_sort_by_distance(self.origin, ai);

    z0 = undefined;
    for (i = 0; i < ai.size; i++)
    {
        if (isdefined(ai[i]) && isalive(ai[i]))
        {
            z0 = ai[i];
            break;
        }
    }

    if (!isdefined(z0))
    {
        iprintln("^1[ST] mi06auto: could not find zombie[0] after trim.");
        return;
    }

    iprintln("^2[ST] mi06auto: 2 zombies remain. AIM at the farther one.");
    iprintln("^2[ST] PRE-CHARGE the wind staff NOW (hold fire).");
    iprintln("^3[ST] Script kills zombie[0] (closer zombie) in 5...");
    wait 1.0;
    iprintln("^3[ST] 4...");
    wait 1.0;
    iprintln("^3[ST] 3...");
    wait 1.0;
    iprintln("^3[ST] 2...");
    wait 1.0;
    iprintln("^3[ST] 1...");
    wait 1.0;

    if (!isdefined(z0) || !isalive(z0))
    {
        iprintln("^1[ST] mi06auto: zombie[0] already dead before countdown ended — re-run.");
        return;
    }

    z0 dodamage(z0.health + 666, z0.origin);
    iprintln("^2[ST] FIRE — release the charge NOW!");
    logprint("[ST] mi06auto: zombie[0] script-killed, awaiting player release\n");
}

// --- MI-07: WIND STAFF INVISIBLE ZOMBIE (WHIRLWIND INTERRUPT) ---
//
// Hypothesis: firing a second charged wind shot while the first whirlwind is
// still dragging zombies sends "whirlwind_stopped", which expires the first
// whirlwind mid-drag.  Zombies that were mid-move have their while loop broken
// and are never damaged — they survive at an intermediate (off-screen) position
// with full health, invisible to the player.
//
// Reproduction: arm mi07test, then fire a charged shot into a large group and
// immediately fire a second charged shot before the first whirlwind expires.
// The _hrp_mi07_undamaged counter increments each time a zombie survives a
// drag because the whirlwind was interrupted.  Run mi07stat to read the count.

// Arm the MI-07 drag-escape diagnostic and give the wind staff.
st_cmd_mi07test()
{
    st_cmd_givestaffair();
    level._hrp_mi07_diag      = 1;
    level._hrp_mi07_undamaged = 0;
    iprintln("^2[ST] MI-07 diagnostic ARMED — counter reset to 0.");
    iprintln("^3[ST] Fire a charged shot into a group of zombies.");
    iprintln("^3[ST] Then IMMEDIATELY fire a second charged shot before");
    iprintln("^3[ST] the first whirlwind finishes. Run 'mi07stat' after.");
    logprint("[ST] mi07test: diagnostic armed\n");
}

// Print and reset the MI-07 undamaged-zombie counter.
st_cmd_mi07stat()
{
    n = isdefined(level._hrp_mi07_undamaged) ? level._hrp_mi07_undamaged : 0;
    level._hrp_mi07_undamaged = 0;

    if (n > 0)
    {
        iprintln("^1[ST] MI-07: " + n + " zombie(s) survived whirlwind drag (check log for origins).");
        iprintln("^1[ST]   These are your invisible zombies.");
    }
    else
        iprintln("^2[ST] MI-07: 0 drag-escaped zombies — whirlwind was not interrupted mid-drag.");

    logprint("[ST] mi07stat: undamaged=" + n + "\n");
}

// --- MI-08: STAFF FLAG CONTAMINATION AT SPAWN ---
//
// Hypothesis: is_on_ice (ice staff) and staff_hit (wind staff) are set on
// zombie entities during staff kills but never cleared before the entity is
// recycled for the next zombie spawn.  New zombies inherit the flag from a
// prior use of the same entity, causing them to appear frozen or to be
// excluded from staff targeting before they are ever hit.
//
// This watcher inserts a _zombie_custom_spawn_logic hook that runs on every
// new zombie just before do_zombie_rise().  At that point the zombie has not
// been touched by any staff, so any flag present is contamination from the
// recycled entity.
//
// Reproduction: arm mi08test, fire the ice staff blizzard (charge level 3)
// into a full horde to mass-contaminate entities, then watch the next horde
// spawn.  mi08stat prints how many fresh zombies arrived pre-contaminated.

st_cmd_mi08test()
{
    level._hrp_mi08_diag         = 1;
    level._hrp_mi08_ice_spawns   = 0;
    level._hrp_mi08_hit_spawns   = 0;
    level._hrp_mi08_total_spawns = 0;

    // Register the spawn hook (safe to call multiple times — guards against dup).
    if (!isdefined(level._hrp_mi08_hook_armed))
    {
        level._hrp_mi08_hook_armed = 1;
        st_append_custom_spawn_logic(::st_mi08_spawn_check);
    }

    iprintln("^2[ST] MI-08 diagnostic ARMED — counters reset to 0.");
    iprintln("^3[ST] Fire the ice staff (charge 3) into a full horde to contaminate entities.");
    iprintln("^3[ST] Then wait for the next horde. Run 'mi08stat' to read contaminated-spawn count.");
    logprint("[ST] mi08test: spawn contamination watcher armed\n");
}

// Append a function pointer to _zombie_custom_spawn_logic regardless of its
// current type (undefined, single funcref, or array).
st_append_custom_spawn_logic(fn)
{
    if (!isdefined(level._zombie_custom_spawn_logic))
    {
        level._zombie_custom_spawn_logic = fn;
    }
    else if (isarray(level._zombie_custom_spawn_logic))
    {
        level._zombie_custom_spawn_logic[level._zombie_custom_spawn_logic.size] = fn;
    }
    else
    {
        prior = level._zombie_custom_spawn_logic;
        level._zombie_custom_spawn_logic    = [];
        level._zombie_custom_spawn_logic[0] = prior;
        level._zombie_custom_spawn_logic[1] = fn;
    }
}

// Called on each zombie by _zombie_custom_spawn_logic, before do_zombie_rise().
// self is the fresh zombie entity.
st_mi08_spawn_check()
{
    if (!isdefined(level._hrp_mi08_diag))
        return;

    level._hrp_mi08_total_spawns++;

    if (isdefined(self.is_on_ice) && self.is_on_ice)
    {
        level._hrp_mi08_ice_spawns++;
        logprint("[ST MI-08] is_on_ice=1 at spawn — entity contaminated. health=" + self.health + "\n");
    }

    if (isdefined(self.staff_hit) && self.staff_hit)
    {
        level._hrp_mi08_hit_spawns++;
        logprint("[ST MI-08] staff_hit=1 at spawn — entity contaminated. health=" + self.health + "\n");
    }
}

// Print and reset MI-08 contamination counters.
st_cmd_mi08stat()
{
    total = isdefined(level._hrp_mi08_total_spawns) ? level._hrp_mi08_total_spawns : 0;
    ice   = isdefined(level._hrp_mi08_ice_spawns)   ? level._hrp_mi08_ice_spawns   : 0;
    hit   = isdefined(level._hrp_mi08_hit_spawns)   ? level._hrp_mi08_hit_spawns   : 0;

    level._hrp_mi08_total_spawns = 0;
    level._hrp_mi08_ice_spawns   = 0;
    level._hrp_mi08_hit_spawns   = 0;

    iprintln("^3[ST] MI-08 contamination over " + total + " spawns:");

    if (ice > 0)
        iprintln("^1[ST]   is_on_ice=1 at birth: " + ice + " zombie(s) — ice staff entity leak CONFIRMED.");
    else
        iprintln("^2[ST]   is_on_ice at birth: 0 — no ice staff contamination detected.");

    if (hit > 0)
        iprintln("^1[ST]   staff_hit=1 at birth: " + hit + " zombie(s) — wind staff entity leak CONFIRMED.");
    else
        iprintln("^2[ST]   staff_hit at birth: 0 — no wind staff contamination detected.");

    logprint("[ST] mi08stat: total=" + total + " ice=" + ice + " hit=" + hit + "\n");
}

// --- MI-09: do_damage_network_safe BRANCH LOGGER ---
//
// Arms the diagnostic flag that makes do_damage_network_safe log whenever a
// call with n_amount == self.health (intended kill) ends up in the
// partial-damage branch instead.  If that happens, the log shows the exact
// gap between n_amount and self.health at the moment of the comparison.
//
// A gap > 0 confirms the float/int mismatch hypothesis: self.health was read
// as float32 (losing precision) for n_amount, but the comparison re-reads it
// at a slightly higher value, routing into partial damage and leaving the
// zombie alive with residual HP.
//
// Workflow:
//   1. set st_cmd mi09test
//   2. set st_cmd skip 110   (or whatever round where the bug appears)
//   3. Fire charged ice/wind staff shots at zombies
//   4. set st_cmd mi09stat   — check partial vs kill counts and gap values in log

st_cmd_mi09test()
{
    level._hrp_mi09_diag    = 1;
    level._hrp_mi09_partial = 0;
    level._hrp_mi09_kill    = 0;
    iprintln("^2[ST] MI-09 diagnostic ARMED — branch counters reset.");
    iprintln("^3[ST] Fire charged ice or wind staff shots at zombies.");
    iprintln("^3[ST] Run 'mi09stat' after to see partial vs kill branch counts.");
    iprintln("^3[ST] Check the log file for exact n_amount / self.health gap values.");
    logprint("[ST] mi09test: do_damage_network_safe branch logger armed\n");
}

st_cmd_mi09stat()
{
    partial = isdefined(level._hrp_mi09_partial) ? level._hrp_mi09_partial : 0;
    kill    = isdefined(level._hrp_mi09_kill)    ? level._hrp_mi09_kill    : 0;

    level._hrp_mi09_partial = 0;
    level._hrp_mi09_kill    = 0;

    iprintln("^3[ST] MI-09 do_damage_network_safe branches:");
    iprintln("^7[ST]   Kill path  (n_amount >= health): " + kill);

    if (partial > 0)
    {
        iprintln("^1[ST]   Partial path (n_amount <  health): " + partial + " — float/int gap CONFIRMED.");
        iprintln("^1[ST]   Check log for exact gap values per zombie.");
    }
    else
        iprintln("^2[ST]   Partial path (n_amount <  health): 0 — no mismatch detected.");

    logprint("[ST] mi09stat: kill=" + kill + " partial=" + partial + "\n");
}

// --- MI-12: ICE STAFF FROZEN-SURVIVOR CHECKER ---
//
// Validates the float32 kill fix (+128 in _kill_zombie_network_safe_internal).
//
// The ice staff blizzard calls staff_water_kill_zombie on every zombie in range with
// always_kill = 1.  That function reads self.health (float32) and passes it to
// do_damage_network_safe.  At R127+ (health > 2^26 = ~67M), float32 can only
// represent multiples of 8, so up to 7 HP are silently dropped.  The zombie
// survives with self.health mod 8 remaining HP, still carrying is_on_ice = 1.
//
// This diagnostic hooks on two level notifications from the ice staff:
// "blizzard_shot" fires when the charged projectile lands.
// "blizzard_ended" fires immediately after flag_clear("blizzard_active") —
// this is an [HRP] hook added to staff_water_position_source in zm_tomb.ff.
// After "blizzard_ended", a 3s buffer lets all kill threads drain, then the
// scan runs on alive zombies still holding is_on_ice = 1.
//
// Expected result with fix   : 0 frozen survivors at any round.
// Expected result without fix: non-zero survivors from R127+ (7 in 8 zombies
//                              have non-multiples-of-8 health at that point).
//
// mi12test — arm the watcher and reset counters.
//            Prerequisite: Origins map, upgraded Ice Staff (givestaffwater).
//            1. set st_cmd mi12test
//            2. set st_cmd "skip 127"   (or any round >= 127)
//            3. set st_cmd god
//            4. Fire a fully-charged blizzard into a horde
//            5. Wait ~12s for the blizzard to end and threads to drain
//            6. set st_cmd mi12stat
//
// mi12stat — print and reset. PASS = 0 survivors. FAIL = any survivor.
//            Each blizzard also prints a live result on-screen immediately.

st_cmd_mi12test()
{
    if (isdefined(level._hrp_mi12_diag))
    {
        iprintln("^3[ST] MI-12 already armed — resetting counters.");
    }
    else
    {
        level._hrp_mi12_diag = 1;
        level thread st_mi12_blizzard_watch();
    }
    level._hrp_mi12_blizzards = 0;
    level._hrp_mi12_survivors = 0;
    iprintln("^2[ST] MI-12 ARMED — watching for ice staff blizzard shots.");
    iprintln("^3[ST] givestaffwater, skip to R127+, god, fire full-charge blizzard.");
    iprintln("^3[ST] Each blizzard auto-reports live. Run mi12stat for totals.");
    logprint("[ST] mi12test: ice frozen-survivor watcher armed\n");
}

// Level thread — loops watching for each blizzard_shot notification.
st_mi12_blizzard_watch()
{
    level endon("end_game");
    while (isdefined(level._hrp_mi12_diag))
    {
        level waittill("blizzard_shot");
        level thread st_mi12_scan_after_blizzard();
    }
}

// Threaded per-blizzard: wait for blizzard to finish, then audit survivors.
st_mi12_scan_after_blizzard()
{
    // Wait for the blizzard to end.
    // "blizzard_ended" is notified by staff_water_position_source immediately after
    // flag_clear("blizzard_active") — added as an [HRP] diagnostic hook.
    // This avoids calling flag() which is not in the addon script include chain.
    level waittill("blizzard_ended");

    // Give ice_affect_zombie kill threads time to complete:
    // up to 0.1s (last poll) + 0.7s (wait in ice_affect_zombie) +
    // 0.05s (wait_network_frame) + ~0.5s (network_choke_action queue drain) = ~1.4s.
    // Use 3s for a comfortable margin.
    wait 3.0;

    if (!isdefined(level._hrp_mi12_diag))
        return;

    n_frozen = 0;
    a_zombies = getaiarray(level.zombie_team);
    foreach (zombie in a_zombies)
    {
        if (!isalive(zombie))
            continue;
        if (isdefined(zombie.is_on_ice) && zombie.is_on_ice)
            n_frozen++;
    }

    level._hrp_mi12_blizzards++;
    level._hrp_mi12_survivors += n_frozen;

    r = level.round_number;
    if (n_frozen > 0)
    {
        logprint("[HRP MI-12] R" + r + ": " + n_frozen + " frozen zombie(s) survived blizzard\n");
        iprintln("^1[ST] MI-12 R" + r + ": " + n_frozen + " frozen survivor(s) — fix NOT active.");
    }
    else
    {
        logprint("[HRP MI-12] R" + r + ": 0 frozen survivors (OK)\n");
        iprintln("^2[ST] MI-12 R" + r + ": blizzard clean — 0 frozen survivors.");
    }
}

st_cmd_mi12stat()
{
    if (!isdefined(level._hrp_mi12_diag))
    {
        iprintln("^3[ST] MI-12 not armed — run mi12test first.");
        return;
    }

    n_b = isdefined(level._hrp_mi12_blizzards) ? level._hrp_mi12_blizzards : 0;
    n_s = isdefined(level._hrp_mi12_survivors) ? level._hrp_mi12_survivors : 0;
    level._hrp_mi12_blizzards = 0;
    level._hrp_mi12_survivors = 0;

    iprintln("^3[ST] MI-12: ice staff frozen-survivor check:");
    iprintln("^7[ST]   Blizzards audited : " + n_b);
    iprintln("^7[ST]   Frozen survivors  : " + n_s);

    if (n_b == 0)
        iprintln("^3[ST]   No blizzards captured yet — fire a charged Ice Staff shot first.");
    else if (n_s == 0)
        iprintln("^2[ST]   PASS: 0 frozen survivors across all blizzards. Float32 fix confirmed.");
    else
        iprintln("^1[ST]   FAIL: " + n_s + " survivor(s) detected. zm_tomb.ff may not be rebuilt.");

    logprint("[ST] mi12stat: blizzards=" + n_b + " survivors=" + n_s + "\n");
}

// --- SCRVAR STRESS: weap / papweap / weapstat ---
//
// These commands artificially inflate the two arrays identified in SA-08 and
// SA-09 to simulate a session with heavy box cycling and PaP usage.
//
// Usage workflow:
//   1. Load zm_patch_scrvar.gsc and this script together.
//   2. set st_cmd "weap 100"     — inflates self.hitsthismag with 100 fakes
//   3. set st_cmd "papweap 50"   — inflates pap_weapon_options with 50 fakes
//   4. set st_cmd weapstat       — confirm sizes are inflated
//   5. set st_cmd "skip 2"       — advance to next round (triggers svp pruner)
//   6. set st_cmd weapstat       — confirm fake entries were pruned
//
// Without zm_patch_scrvar: entries survive round skip, sizes stay inflated.
// With zm_patch_scrvar:    pruner fires at start_of_round, removes all fakes,
//                          log shows "[SVP] hitsthismag: pruned N stale entries".

// SA-08 inflator: adds N synthetic weapon strings to self.hitsthismag.
// Uses a _fake_sv_weap_ prefix so the SVP pruner correctly identifies them
// as stale (they won't appear in getweaponslist()).
st_cmd_weap(arg)
{
    if (arg == "")
    {
        iprintln("^1[ST] Usage: /st weap <N>  — inflate hitsthismag with N fake entries");
        return;
    }

    n = int(arg);
    if (n < 1)   n = 1;
    if (n > 500) n = 500;

    if (!isdefined(self.hitsthismag))
        self.hitsthismag = [];

    before = self.hitsthismag.size;

    for (i = 0; i < n; i++)
        self.hitsthismag["_fake_sv_weap_" + i] = 30;   // 30 = arbitrary clip size

    after = self.hitsthismag.size;

    iprintln("^3[ST] SA-08 inflated: hitsthismag " + before + " -> " + after
             + " entries for " + self.name);
    logprint("[ST] weap: hitsthismag inflated " + before + " -> " + after
             + " for " + self.name + "\n");
}

// SA-09 inflator: adds N synthetic entries to self.pack_a_punch_weapon_options.
st_cmd_papweap(arg)
{
    if (arg == "")
    {
        iprintln("^1[ST] Usage: /st papweap <N>  — inflate pap_weapon_options with N fake entries");
        return;
    }

    n = int(arg);
    if (n < 1)   n = 1;
    if (n > 500) n = 500;

    if (!isdefined(self.pack_a_punch_weapon_options))
        self.pack_a_punch_weapon_options = [];

    before = self.pack_a_punch_weapon_options.size;

    for (i = 0; i < n; i++)
        self.pack_a_punch_weapon_options["_fake_pap_weap_" + i] = 0;

    after = self.pack_a_punch_weapon_options.size;

    iprintln("^3[ST] SA-09 inflated: pap_weapon_options " + before + " -> " + after
             + " entries for " + self.name);
    logprint("[ST] papweap: pap_weapon_options inflated " + before + " -> " + after
             + " for " + self.name + "\n");
}

// Print current array sizes for all connected players.
// Shows: hitsthismag size, pap_weapon_options size, total pruned/cleared by SVP.
st_cmd_weapstat()
{
    players = getplayers();

    if (players.size == 0)
    {
        iprintln("^1[ST] No players connected");
        return;
    }

    for (i = 0; i < players.size; i++)
    {
        p = players[i];

        mag_size = 0;
        if (isdefined(p.hitsthismag))
            mag_size = p.hitsthismag.size;

        pap_size = 0;
        if (isdefined(p.pack_a_punch_weapon_options))
            pap_size = p.pack_a_punch_weapon_options.size;

        iprintln("^3[ST] " + p.name
                 + "  ^2hitsthismag=^7" + mag_size
                 + "  ^2pap_opts=^7" + pap_size);
    }

    // Show SVP totals if the patch is loaded.
    pruned = 0;
    cleared = 0;
    if (isdefined(level._svp_pruned_total)) pruned  = level._svp_pruned_total;
    if (isdefined(level._svp_pap_cleared))  cleared = level._svp_pap_cleared;

    if (isdefined(level._svp_version))
        iprintln("^3[ST] SVP v" + level._svp_version
                 + "  cumulative pruned=" + pruned + "  pap_cleared=" + cleared);
    else
        iprintln("^1[ST] zm_patch_scrvar not loaded — no pruning active");
}

// --- GENERATOR TESTS (GEN-ZC-01, zm_origins only) ---

// Force-capture N generators simultaneously and print their capture_zombie_limit values.
// With GEN-ZC-01 unpatched: each zone in a 2-zone contest shows limit=6 instead of limit=3.
// Usage: set st_cmd gencap 2   (or 3, 4)
st_cmd_gencap(arg)
{
    if (!isdefined(level.zone_capture) || !isdefined(level.zone_capture.zones))
    {
        iprintln("^1[ST] gencap: zone_capture not initialized — load zm_origins first");
        return;
    }

    n_zones = int(arg);
    if (n_zones < 1 || n_zones > 6)
        n_zones = 2;

    // Notify each generator struct to start a capture (simulates player activation)
    n_queued = 0;
    foreach (str_key, s_zone in level.zone_capture.zones)
    {
        if (n_queued >= n_zones)
            break;

        if (!s_zone ent_flag("player_controlled") && !s_zone ent_flag("zone_contested"))
        {
            s_zone notify("start_generator_capture", getplayers()[0]);
            n_queued++;
            wait 0.05;
        }
    }

    iprintln("^3[ST] gencap: notified " + n_queued + " generators — watch SV and HR during contest");
    wait 2;
    level thread st_cmd_genstat();
}

// Print each zone's capture_zombie_limit and current live capture zombie count.
// Run during an active capture event to observe GEN-ZC-01's inflated limit.
st_cmd_genstat()
{
    if (!isdefined(level.zone_capture) || !isdefined(level.zone_capture.zones))
    {
        iprintln("^1[ST] genstat: zone_capture not initialized — load zm_origins first");
        return;
    }

    foreach (str_key, s_zone in level.zone_capture.zones)
    {
        n_limit = 0;
        n_live  = 0;

        if (isdefined(s_zone.capture_zombie_limit))
            n_limit = s_zone.capture_zombie_limit;

        if (isdefined(s_zone.capture_zombies))
        {
            s_zone.capture_zombies = array_removedead(s_zone.capture_zombies);
            n_live = s_zone.capture_zombies.size;
        }

        str_contested = s_zone ent_flag("zone_contested") ? "CONTESTED" : "inactive";
        iprintln("^3[ST] " + str_key + "  limit=" + n_limit + "  live=" + n_live + "  " + str_contested);
        wait 0.05;
    }

    // Also print recapture zombie count
    n_recap = 0;
    if (isdefined(level.zone_capture.recapture_zombies))
    {
        level.zone_capture.recapture_zombies = array_removedead(level.zone_capture.recapture_zombies);
        n_recap = level.zone_capture.recapture_zombies.size;
    }

    iprintln("^3[ST] recapture zombies: " + n_recap);
}

// Raise the simultaneous zombie AI cap and refill the spawn queue so the
// spawner keeps pushing zombies up to N alive at once.
//
// level.zombie_ai_limit   — max concurrent live AI (default 24)
// level.zombie_vars["zombie_max_ai"] — secondary cap read by get_current_zombie_count
// level.zombie_total      — remaining spawn budget; refilled to N so the queue
//                           never runs dry while animsat is holding entries alive
//
// Usage: set st_cmd aipop 64
st_cmd_aipop(arg)
{
    n = int(arg);
    if (n <= 0)
    {
        iprintln("^1[ST] Usage: set st_cmd aipop <N>  (default is 24)");
        return;
    }

    level.zombie_ai_limit = n;
    level.zombie_actor_limit = n + 16;  // actors include robots, corpses, etc.
    level.zombie_vars["zombie_max_ai"] = n;
    level.zombie_total = n;

    iprintln("^3[ST] aipop: ai_limit=" + n + "  actor_limit=" + (n+16) + "  spawn_queue=" + n);
}

// --- ANIM INFO TESTS (GR-AI-01 through GR-AI-05, zm_origins) ---

// GR-06 hypothesis test: call animscripted N times on one zombie using DIFFERENT
// state names each time (no stopanimscripted between calls), then stopanimscripted.
// Mirrors the mechz_tank_hit_callback pattern:
//   animscripted("zm_tank_hit_in")  → donotetracks → (no stop)
//   animscripted("zm_tank_hit_loop") → donotetracks → (no stop)
//   animscripted("zm_tank_hit_out") → donotetracks → function returns with no stop
//
// If calling animscripted with a new STATE NAME while the previous entry is still
// active allocates a second entry (rather than replacing it), each state transition
// leaks one slot permanently. The mechz robot-stomp and tank-hit paths would then
// leak 2 entries per event.
//
// Uses two confirmed Origins zombie ASD states for the test:
//   cycle[0] = "zm_generator_melee"
//   cycle[1] = "zm_dug_rise"
//
// Test procedure:
//   1. animsat 15              -- establish baseline
//   2. animstop
//   3. animstate 6             -- call animscripted with alternating states 6x, then stop
//   4. animsat 15              -- if this crashes or holds less: state transitions accumulate
//
// Usage: set st_cmd animstate 6
st_cmd_animstate(arg)
{
    n = int(arg);
    if (n <= 0)
    {
        iprintln("^1[ST] Usage: set st_cmd animstate <N>  (try 6 to match tank/stomp pattern)");
        return;
    }

    states = [];
    states[0] = "zm_generator_melee";
    states[1] = "zm_dug_rise";

    zombies = getaiarray(level.zombie_team);
    if (!isdefined(zombies) || zombies.size == 0)
    {
        iprintln("^1[ST] animstate: no live zombies");
        return;
    }

    z = zombies[0];

    for (i = 0; i < n; i++)
    {
        z animscripted(z.origin, z.angles, states[i % 2]);
        wait 0.05;
    }

    z stopanimscripted();

    iprintln("^3[ST] animstate: called animscripted " + n + "x with alternating state names then stopanimscripted");
    iprintln("^3[ST] animstate: now run animsat at your previous baseline to check for leaks");
}

// GR-05 hypothesis test: call animscripted N times on one zombie with sequential
// integer indices (0, 1, 2, ...) then stopanimscripted. If each call with a new
// index allocates its own anim info entry rather than replacing the previous one,
// the anim info table will be (N-1) entries lower after this call than before.
//
// Test procedure:
//   1. animsat 20              -- establish baseline (holds 20 entries fine)
//   2. animstop
//   3. animindex 3             -- call animscripted(state,0), (state,1), (state,2), then stop
//   4. animsat 20              -- if this now crashes, N-1=2 entries leaked; if OK, no leak
//
// Usage: set st_cmd animindex 3
st_cmd_animindex(arg)
{
    n = int(arg);
    if (n <= 0)
    {
        iprintln("^1[ST] Usage: set st_cmd animindex <N>  (try 3 to match robot walk)");
        return;
    }

    state = getDvar("st_anim_state");
    if (!isdefined(state) || state == "")
        state = "zm_generator_melee";

    zombies = getaiarray(level.zombie_team);
    if (!isdefined(zombies) || zombies.size == 0)
    {
        iprintln("^1[ST] animindex: no live zombies");
        return;
    }

    z = zombies[0];
    o = z.origin;
    a = z.angles;

    for (i = 0; i < n; i++)
    {
        z animscripted(o, a, state, i);
        wait 0.05;
    }

    z stopanimscripted();

    iprintln("^3[ST] animindex: called animscripted " + n + "x with indices 0.." + (n-1) + " then stopanimscripted");
    iprintln("^3[ST] animindex: now run animsat at your previous baseline — if it holds less, entries leaked");
}

// GR-05 leak rate test: repeat the animindex 3 pattern R times and measure how
// many anim info slots are consumed overall. Approximates one robot walk cycle
// (3 segment-indexed animscripted calls followed by stopanimscripted).
//
// After R repetitions, run animsat at your pre-test baseline. If it fails, the
// count of failures (how many fewer entries you can hold) gives entries leaked per
// cycle. Then:  entries_leaked / R = leak_per_walk_cycle.
//
// Usage: set st_cmd animleakrate 20
st_cmd_animleakrate(arg)
{
    r = int(arg);
    if (r <= 0)
    {
        iprintln("^1[ST] Usage: set st_cmd animleakrate <R>  (R = number of simulated walk cycles)");
        return;
    }

    state = getDvar("st_anim_state");
    if (!isdefined(state) || state == "")
        state = "zm_generator_melee";

    zombies = getaiarray(level.zombie_team);
    if (!isdefined(zombies) || zombies.size == 0)
    {
        iprintln("^1[ST] animleakrate: no live zombies");
        return;
    }

    z = zombies[0];

    iprintln("^3[ST] animleakrate: running " + r + " simulated walk cycles (animscripted 0,1,2 + stop each)...");

    for (j = 0; j < r; j++)
    {
        o = z.origin;
        a = z.angles;

        z animscripted(o, a, state, 0);
        wait 0.05;
        z animscripted(o, a, state, 1);
        wait 0.05;
        z animscripted(o, a, state, 2);
        wait 0.05;
        z stopanimscripted();
        wait 0.05;
    }

    iprintln("^3[ST] animleakrate: done — " + r + " cycles complete");
    iprintln("^3[ST] animleakrate: now run animsat at your pre-test baseline to measure how many slots were consumed");
}



// Force N live Origins zombies into animscripted state and hold them there.
// Each zombie gets a thread that re-issues animscripted every 0.05s, keeping
// the entry alive even though zm_generator_melee is a one-shot animation.
// Uses "zm_generator_melee" — confirmed valid for zm_tomb_basic.
// Override via: set st_anim_state <state>  then re-run animsat.
// Usage:
//   set st_cmd animsat 4     hold 4 zombies
//   set st_cmd animstop      release all held entries
//   set st_cmd animstat      print current held count
st_cmd_animsat(arg)
{
    n = int(arg);
    if (n <= 0)
    {
        iprintln("^1[ST] Usage: set st_cmd animsat <N>");
        return;
    }

    state = getDvar("st_anim_state");
    if (!isdefined(state) || state == "")
        state = "zm_generator_melee";

    if (!isdefined(level._animsat_zombies))
        level._animsat_zombies = [];

    // Release any existing hold before re-saturating.
    if (level._animsat_zombies.size > 0)
    {
        foreach (z in level._animsat_zombies)
        {
            if (isdefined(z) && isalive(z))
            {
                z notify("animsat_release");
                z stopanimscripted();
            }
        }
        level._animsat_zombies = [];
    }

    zombies = getaiarray(level.zombie_team);
    if (!isdefined(zombies) || zombies.size == 0)
    {
        iprintln("^1[ST] animsat: no live zombies — skip to a later round first");
        return;
    }

    held = 0;
    foreach (z in zombies)
    {
        if (held >= n)
            break;
        if (!isalive(z))
            continue;

        z thread animsat_hold(state);
        level._animsat_zombies[held] = z;

        o = z.origin;
        iprintln("^3[ST] animsat[" + held + "]: frozen at ("
            + int(o[0]) + ", " + int(o[1]) + ", " + int(o[2]) + ")");

        held++;
    }

    if (held < n)
        iprintln("^3[ST] animsat: WARNING — only " + held + " of " + n + " zombies available");

    iprintln("^3[ST] animsat: holding " + held + " / " + n + " (state=" + state + ")");
}

// Per-zombie thread: re-issues animscripted every 0.05s so the entry persists
// even though the animation is a one-shot cycle. Exits on animsat_release or death.
animsat_hold(state)
{
    self endon("animsat_release");
    self endon("death");

    while (true)
    {
        self animscripted(self.origin, self.angles, state);
        wait 0.05;
    }
}

// Release all animscripted entries held by animsat.
st_cmd_animstop()
{
    if (!isdefined(level._animsat_zombies) || level._animsat_zombies.size == 0)
    {
        iprintln("^3[ST] animstop: nothing held");
        return;
    }

    freed = 0;
    foreach (z in level._animsat_zombies)
    {
        if (isdefined(z) && isalive(z))
        {
            z notify("animsat_release");
            z stopanimscripted();
            freed++;
        }
    }

    level._animsat_zombies = [];
    iprintln("^3[ST] animstop: released " + freed + " animscripted entries");
}

// Print the current animsat held count.
st_cmd_animstat()
{
    held = 0;
    if (isdefined(level._animsat_zombies))
    {
        foreach (z in level._animsat_zombies)
        {
            if (isdefined(z) && isalive(z))
                held++;
        }
    }
    iprintln("^3[ST] animstat: animsat holding " + held + " live entries");
}

// Call getanimfromasd N times on one zombie without consuming the result.
// Probes whether the function allocates an anim info entry at runtime.
// After the calls, follow up with animsat 1 to check available table headroom.
// Usage: set st_cmd animasd 5
st_cmd_animasd(arg)
{
    n = int(arg);
    if (n <= 0)
    {
        iprintln("^1[ST] Usage: set st_cmd animasd <N>");
        return;
    }

    state = getDvar("st_anim_state");
    if (!isdefined(state) || state == "")
        state = "zm_generator_melee";

    zombies = getaiarray(level.zombie_team);
    if (!isdefined(zombies) || zombies.size == 0)
    {
        iprintln("^1[ST] animasd: no live zombies");
        return;
    }

    z = zombies[0];
    for (i = 0; i < n; i++)
        z getanimfromasd(state, 0);

    iprintln("^3[ST] animasd: called getanimfromasd " + n + "x (result discarded each time)");
    iprintln("^3[ST] animasd: now run animsat 1 to probe whether table headroom shrank");
}

// Force a three-robot round on Origins by advancing level.round_number to the
// NEXT multiple of 4 beyond the current value. Always increments, so robot_cycling()'s
// internal three_robot_round tracker (which equals the last multiple-of-4 it already
// processed) will be less than the new value and the condition will fire.
// zm_origins only.
st_cmd_roboforce()
{
    if (!isdefined(level.zone_capture) || !isdefined(level.zone_capture.zones))
    {
        iprintln("^1[ST] roboforce: not on zm_origins — aborted");
        return;
    }

    r = level.round_number;
    // Always advance to the next multiple of 4, never stay at current.
    r = r + (4 - (r % 4));

    level.round_number = r;
    iprintln("^3[ST] roboforce: round_number -> " + r + " — robot_cycling() will send all 3 robots on next poll");
}

// ---------------------------------------------------------------------------
// robosoak N — run N sequential single-robot walks and report each one.
//
// Designed for long-period leak measurement when per-walk noise is too high.
// Run 20-50 walks and compare cg_drawAnimInfo floor before vs after:
//   leak_per_walk = (floor_after - floor_before) / N
//
// The floor (minimum value between peaks) is more stable than instantaneous
// readings. With ambient noise of ±10-20 and a leak of 1-2/walk, 20 walks
// gives a +20-40 shift that rises above the noise band.
//
// Workflow:
//   set st_cmd freezeround          (kill zombies, stable baseline)
//   wait ~10s, note cg_drawAnimInfo floor  ← RECORD THIS
//   set st_cmd robosoak 20
//   ... watch walks fire, each logs [ST] soak walk N/20 ...
//   [ST] robosoak DONE — note cg_drawAnimInfo floor  ← RECORD THIS
//   leak_per_walk = (after - before) / 20
//
// Usage: set st_cmd robosoak 20
// ---------------------------------------------------------------------------
st_cmd_robosoak(arg)
{
    if (!isdefined(level.zone_capture) || !isdefined(level.zone_capture.zones))
    {
        iprintln("^1[ST] robosoak: not on zm_origins — aborted");
        return;
    }

    n_walks = int(arg);
    if (n_walks <= 0)
        n_walks = 10;

    iprintln("^5[ST] robosoak START: " + n_walks + " single-robot walks queued");
    iprintln("^5[ST] Note cg_drawAnimInfo floor NOW as your baseline.");

    for (i = 0; i < n_walks; i++)
    {
        // Set round to a non-multiple-of-4 so robot_cycling sends 1 robot.
        r = level.round_number;
        if (r % 4 == 0)
            r++;
        level.round_number = r;

        iprintln("^3[ST] robosoak walk " + (i + 1) + "/" + n_walks + " queued (r=" + r + ")");

        // Wait for this walk to complete before queuing the next.
        level waittill("giant_robot_walk_cycle_complete");

        // Small gap so robot_cycling finishes its 5s post-walk wait and
        // robot entity state fully resets before the next walk fires.
        wait 7;
    }

    iprintln("^5[ST] robosoak DONE — all " + n_walks + " walks complete.");
    iprintln("^5[ST] Note cg_drawAnimInfo floor NOW and compute: (after - before) / " + n_walks);
}

// Trigger a SINGLE robot walk on the next robot_cycling pass.
//
// robot_cycling() sends all 3 robots when round_number % 4 == 0.
// This command sets round_number to a non-multiple-of-4, so robot_cycling
// takes the single-robot branch on its next loop iteration.
//
// Use AFTER any current walk cycle has finished. robot_cycling will send one
// randomly chosen robot on its next poll (after its 5s inter-cycle delay).
//
// For a clean cg_drawAnimInfo measurement:
//   set st_cmd freezeround       (kill zombies, lock spawning)
//   set st_cmd roboforce1        (queue a single-robot walk)
//   wait for [HRP] r* START then [HRP] r* final stopanimscripted
//   compare cg_drawAnimInfo before START vs after final stop
//
// Usage: set st_cmd roboforce1
st_cmd_roboforce1()
{
    if (!isdefined(level.zone_capture) || !isdefined(level.zone_capture.zones))
    {
        iprintln("^1[ST] roboforce1: not on zm_origins — aborted");
        return;
    }

    r = level.round_number;

    // Step off the triple-round multiple so robot_cycling sends only 1 robot.
    if (r % 4 == 0)
        r++;

    level.round_number = r;
    iprintln("^3[ST] roboforce1: round_number -> " + r + " (not R%4==0) — next robot_cycling pass sends 1 robot");
    iprintln("^3[ST] If a walk is currently in progress, the single walk fires after it completes (+5s).");
}

// Measure anim info entries leaked by a robot walk cycle.
//
// Protocol:
//   1. Probe table headroom: animsat PROBE_N, record count_before, animstop.
//   2. Trigger one robot round via roboforce.
//   3. Wait for giant_robot_walk_cycle_complete + 5s margin (for triple rounds all
//      three complete before we re-probe).
//   4. Probe again: animsat PROBE_N, record count_after, animstop.
//   5. leaked = count_before - count_after.
//
// With the unpatched robot each walk leaks 2 entries (segments 0 and 1 are never
// freed). A triple-giant round leaks 6. With GR-05 applied, leaked == 0.
//
// Requires: zm_origins with enough live zombies (use aipop 30+ first).
// Usage: set st_cmd animrobotleak         — one robot cycle
//        set st_cmd animrobotleak 5       — five robot cycles, cumulative
st_cmd_animrobotleak(arg)
{
    if (!isdefined(level.zone_capture) || !isdefined(level.zone_capture.zones))
    {
        iprintln("^1[ST] animrobotleak: not on zm_origins — aborted");
        return;
    }

    n_cycles = int(arg);
    if (n_cycles <= 0)
        n_cycles = 1;

    probe_n = 30;

    zombies = getaiarray(level.zombie_team);
    if (!isdefined(zombies) || zombies.size < 10)
    {
        iprintln("^1[ST] animrobotleak: need 10+ live zombies — run aipop 30 first");
        return;
    }

    iprintln("^5[ST] animrobotleak: starting " + n_cycles + " cycle(s), probe_n=" + probe_n);

    total_leaked = 0;

    for (cycle = 0; cycle < n_cycles; cycle++)
    {
        // --- Probe BEFORE ---
        count_before = animrobotleak_probe(probe_n);
        iprintln("^3[ST] robotleak[" + cycle + "] PRE : " + count_before + " slots available");

        // --- Trigger robot round ---
        r = level.round_number;
        r = r + (4 - (r % 4));
        level.round_number = r;
        iprintln("^3[ST] robotleak[" + cycle + "] round_number -> " + r + ", waiting for walk...");

        // Wait for the first completion, then 5s margin for triple-round stragglers.
        level waittill("giant_robot_walk_cycle_complete");
        wait 5;

        // --- Probe AFTER ---
        count_after = animrobotleak_probe(probe_n);
        iprintln("^3[ST] robotleak[" + cycle + "] POST: " + count_after + " slots available");

        leaked = count_before - count_after;
        total_leaked += leaked;

        if (leaked > 0)
            iprintln("^1[ST] robotleak[" + cycle + "] LEAKED " + leaked + " entries  (cumulative: " + total_leaked + ")");
        else
            iprintln("^2[ST] robotleak[" + cycle + "] NO LEAK — patch confirmed for this cycle");

        wait 1;
    }

    iprintln("^5[ST] animrobotleak DONE: total_leaked=" + total_leaked + " over " + n_cycles + " cycle(s)");
    if (total_leaked == 0)
        iprintln("^2[ST] RESULT: PATCH WORKING — zero leaked entries");
    else
        iprintln("^1[ST] RESULT: LEAK CONFIRMED — " + total_leaked + " entries unfreed");
}

// Sub: fill the table with probe_n animscripted entries, record how many
// actually took (= available headroom), then release them all.
// Returns the count of entries successfully held.
animrobotleak_probe(probe_n)
{
    // Release any leftover animsat state.
    if (isdefined(level._animsat_zombies) && level._animsat_zombies.size > 0)
    {
        foreach (z in level._animsat_zombies)
        {
            if (isdefined(z) && isalive(z))
            {
                z notify("animsat_release");
                z stopanimscripted();
            }
        }
        level._animsat_zombies = [];
    }

    zombies = getaiarray(level.zombie_team);
    held = 0;

    foreach (z in zombies)
    {
        if (held >= probe_n)
            break;
        if (!isalive(z))
            continue;
        z thread animsat_hold("zm_generator_melee");
        level._animsat_zombies[held] = z;
        held++;
    }

    // Give the hold threads one frame to issue their first animscripted call.
    wait 0.1;

    // Count how many are actually live (the engine may have silently rejected
    // some if the table was full).
    live = 0;
    foreach (z in level._animsat_zombies)
    {
        if (isdefined(z) && isalive(z))
            live++;
    }

    // Release immediately.
    foreach (z in level._animsat_zombies)
    {
        if (isdefined(z) && isalive(z))
        {
            z notify("animsat_release");
            z stopanimscripted();
        }
    }
    level._animsat_zombies = [];

    wait 0.1;
    return live;
}

// Passive background watcher: probes the anim info table automatically every
// time a robot completes a walk cycle. No manual triggering needed — just run
// the game normally in god mode and watch the console.
//
// After each giant_robot_walk_cycle_complete the watcher:
//   1. Waits 3s for any concurrent robots on the same round to also finish.
//   2. Probes table headroom with animrobotleak_probe(20).
//   3. Prints: walk #N  headroom=X  delta_from_baseline=Y  leaked_this_walk=Z
//
// Expected output WITHOUT GR-05 patch:
//   walk #1  headroom=20  delta=0  this_walk=0    <- no robot yet (first notify is baseline)
//   walk #2  headroom=18  delta=2  this_walk=2    <- 2 entries leaked by walk 1
//   walk #3  headroom=16  delta=4  this_walk=2    <- another 2 leaked
//   (triple-giant round: each of 3 robots fires the notify → delta +2 per robot)
//
// Expected output WITH GR-05 patch:
//   walk #N  headroom=20  delta=0  this_walk=0    <- flat forever
//
// Stop with: set st_cmd animrobotstop
// Usage:     set st_cmd animrobotwatch
st_cmd_animrobotwatch()
{
    level endon("animrobotwatch_stop");
    level endon("game_ended");

    if (!isdefined(level.zone_capture) || !isdefined(level.zone_capture.zones))
    {
        iprintln("^1[ST] animrobotwatch: not on zm_origins — aborted");
        return;
    }

    probe_n = 20;

    zombies = getaiarray(level.zombie_team);
    if (!isdefined(zombies) || zombies.size < 5)
    {
        iprintln("^1[ST] animrobotwatch: need live zombies — wait for a round to start");
        return;
    }

    // Take the initial baseline before any robot has walked.
    baseline = animrobotleak_probe(probe_n);
    level._arw_baseline     = baseline;
    level._arw_walk_count   = 0;
    level._arw_total_leaked = 0;
    level._arw_headroom     = baseline;
    iprintln("^5[ST] animrobotwatch STARTED  baseline=" + baseline + "  (stat: set st_cmd animrobotstat  stop: set st_cmd animrobotstop)");

    while (true)
    {
        level waittill("giant_robot_walk_cycle_complete");

        // Wait a few seconds so concurrent robots on the same triple-giant
        // round also finish before we probe.
        wait 3;

        level._arw_walk_count++;
        headroom = animrobotleak_probe(probe_n);
        delta_total = level._arw_baseline - headroom;
        delta_this  = level._arw_headroom - headroom;
        level._arw_headroom     = headroom;
        level._arw_total_leaked = delta_total;

        if (delta_this > 0)
            color = "^1";
        else
            color = "^2";

        iprintln(color + "[ST] walk #" + level._arw_walk_count
            + "  headroom=" + headroom
            + "  total_leaked=" + delta_total
            + "  this_walk=" + delta_this);
    }
}

// Print the current watcher state without waiting for the next walk.
st_cmd_animrobotstat()
{
    if (!isdefined(level._arw_baseline))
    {
        iprintln("^1[ST] animrobotstat: watcher not running — start with set st_cmd animrobotwatch");
        return;
    }

    probe_n = 20;
    headroom = animrobotleak_probe(probe_n);
    delta_total = level._arw_baseline - headroom;

    iprintln("^5[ST] animrobotstat:"
        + "  walks=" + level._arw_walk_count
        + "  baseline=" + level._arw_baseline
        + "  headroom_now=" + headroom
        + "  total_leaked=" + delta_total);
}

// Force the worst-case concurrent anim info scenario:
//   1. Advance to next R%4==0 so robot_cycling sends all 3 robots walking
//   2. Wait 4s for robots to start their walk animation (robot_cycling polls ~every few seconds)
//   3. Trigger all 6 generators — capture zombies take ~10-20s to navigate to the generator
//   4. Wait 10s then print genstat so you can confirm capture zombies are active
//
// zm_origins only. Skip to R12+ with god mode first.
st_cmd_animoverlap()
{
    if (!isdefined(level.zone_capture) || !isdefined(level.zone_capture.zones))
    {
        iprintln("^1[ST] animoverlap: not on zm_origins — aborted");
        return;
    }

    iprintln("^3[ST] animoverlap: step 1 — roboforce (robots walk on next cycle)");
    level thread st_cmd_roboforce();

    iprintln("^3[ST] animoverlap: waiting 4s for robots to start walking...");
    wait 4;

    iprintln("^3[ST] animoverlap: step 2 — triggering all 6 generators");
    level thread st_cmd_gencap("6");

    iprintln("^3[ST] animoverlap: waiting 15s for capture zombies to navigate and enter melee...");
    wait 15;

    iprintln("^3[ST] animoverlap: step 3 — status check:");
    level thread st_cmd_genstat();
}

// ---------------------------------------------------------------------------
// animcgsnap — confirms that cg_drawAnimInfo is NOT readable server-side.
//
// cg_drawAnimInfo is a Plutonium client-side variable. Server-side GSC cannot
// read it with getdvarint(). This command exists as a diagnostic to confirm
// that finding. It will always print 0.
//
// To track cg_drawAnimInfo:
//   - Enable the HUD overlay:  cg_drawAnimInfo 1  (Plutonium console)
//   - Read the displayed value manually after each robot walk.
//   - Correlate with [HRP] walk markers in games_mp.log.
//
// Usage: set st_cmd animcgsnap
// ---------------------------------------------------------------------------
st_cmd_animcgsnap()
{
    iprintln( "^3[ST] animcgsnap: cg_drawAnimInfo is a Plutonium CLIENT-side dvar." );
    iprintln( "^3[ST] Server GSC cannot read it. Enable via console: cg_drawAnimInfo 1" );
    iprintln( "^3[ST] Correlate HUD values with [HRP] lines in games_mp.log manually." );
}

// ---------------------------------------------------------------------------
// animcgwatch / animcgstop / animcgstat — NOT AVAILABLE
//
// cg_drawAnimInfo is confirmed client-side only (getdvarint returns 0).
// These stubs exist so the commands fail gracefully rather than silently.
// ---------------------------------------------------------------------------
st_cmd_animcgwatch( arg )
{
    iprintln( "^1[ST] animcgwatch: not available — cg_drawAnimInfo is client-side only." );
    iprintln( "^1[ST] Use: cg_drawAnimInfo 1 in console, note values after each walk." );
    iprintln( "^1[ST] Correlate with [HRP] r* walk lines in games_mp.log." );
}

st_cmd_animcgstop()
{
    iprintln( "^3[ST] animcgstop: animcgwatch was never running (client-side dvar)." );
}

st_cmd_animcgstat()
{
    iprintln( "^3[ST] animcgstat: not available — cg_drawAnimInfo is client-side only." );
}

// ---------------------------------------------------------------------------
// freezeround — kill all live zombies, lock spawning, hold round open.
//
// Creates a 0-zombie stable state ideal for clean cg_drawAnimInfo measurement.
// With no live zombies, the 300-400 unit oscillation from zombie animscripted
// calls collapses to a stable ambient floor, making per-walk deltas readable.
//
// After freezeround:
//   1. All live zombies are instantly killed.
//   2. zombie_ai_limit=0 prevents any new zombie from becoming alive.
//   3. zombie_total=9999 keeps the round-end check from firing.
//   4. spawn_delay=99s prevents the spawner from queuing new zombies.
//
// Workflow for clean walk measurement:
//   set st_cmd freezeround
//   (wait for cg_drawAnimInfo to plateau — ~5s)
//   note baseline value
//   set st_cmd roboforce           (triggers robot walk)
//   watch for [HRP] r* final stopanimscripted in console
//   (wait ~5s for cleanup transient to clear)
//   note post-walk value
//   delta = post - pre = permanent cost of 1 walk cycle
//
// Restore normal gameplay: set st_cmd thawround
// ---------------------------------------------------------------------------
st_cmd_freezeround()
{
    level._freeze_saved_ai_limit     = level.zombie_ai_limit;
    level._freeze_saved_spawn_delay  = level.zombie_vars["zombie_spawn_delay"];
    level._freeze_active             = 1;

    n_killed = 0;
    zombies = getaiarray( level.zombie_team );
    foreach ( z in zombies )
    {
        if ( isdefined( z ) && isalive( z ) )
        {
            z dodamage( z.health + 100, z.origin );
            n_killed++;
        }
    }

    level.zombie_ai_limit                    = 0;
    level.zombie_actor_limit                 = 16;
    level.zombie_vars["zombie_max_ai"]       = 0;
    level.zombie_total                       = 9999;
    level.zombie_total_subtract              = 9999;
    level.zombie_vars["zombie_spawn_delay"]  = 99;

    iprintln( "^5[ST] freezeround: killed=" + n_killed + "  spawning locked  round held" );
    iprintln( "^5[ST] Wait ~5s for cg_drawAnimInfo to plateau, then note baseline." );
    iprintln( "^5[ST] Restore: set st_cmd thawround" );
}

// ---------------------------------------------------------------------------
// thawround — restore normal spawning and let the round end naturally.
// ---------------------------------------------------------------------------
st_cmd_thawround()
{
    if ( !isdefined( level._freeze_active ) || !level._freeze_active )
    {
        iprintln( "^3[ST] thawround: freezeround is not active" );
        return;
    }

    level.zombie_ai_limit                   = level._freeze_saved_ai_limit;
    level.zombie_actor_limit                = level._freeze_saved_ai_limit + 16;
    level.zombie_vars["zombie_max_ai"]      = level._freeze_saved_ai_limit;
    level.zombie_total                      = 0;
    level.zombie_total_subtract             = 0;
    level.zombie_vars["zombie_spawn_delay"] = level._freeze_saved_spawn_delay;
    level._freeze_active                    = 0;

    iprintln( "^5[ST] thawround: spawning restored — round will end when zombie_total hits 0" );
}

// --- HELPERS ---

st_recalc_health(round_number)
{
    level.zombie_health = level.zombie_vars["zombie_health_start"];

    for (i = 2; i <= round_number; i++)
    {
        if (i >= 10)
        {
            old_health = level.zombie_health;
            level.zombie_health = level.zombie_health + int(level.zombie_health * level.zombie_vars["zombie_health_increase_multiplier"]);

            if (level.zombie_health < old_health)
            {
                level.zombie_health = old_health;
                return;
            }
        }
        else
            level.zombie_health = int(level.zombie_health + level.zombie_vars["zombie_health_increase"]);
    }
}
