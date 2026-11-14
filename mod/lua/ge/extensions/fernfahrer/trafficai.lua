-- Trucks of Earth: a smarter layer over BeamNG's traffic AI.
--
-- Why it is needed: the stock traffic AI keeps to its lane, and on a road with one lane each way it never steers
-- round a moving vehicle ahead (its sideways avoidance needs more than ~5.2 m of usable width, ai.lua
-- inMultipleLanes) – it queues behind a slow truck for ever. (Stopped vehicles it does pass on its own: those are
-- left to it.)
--
-- Overtaking, twice a second for every traffic car near the player:
--   following  behind a slower moving vehicle: never faster than it when close (no ramming). After a wait that
--              depends on the driver, the pass is checked: the oncoming cars up to 1.5 km against the time the pass
--              takes (with the driver's appetite for risk), no real junction (a side road, not a field track or a
--              drive) and no sharp bend on the road graph ahead, no roadworks / camera / check / accident.
--   pullout    left indicator, lane binding off, the plan moved onto the oncoming lane (ai.laneChange, by the car's
--              measured offset from the road's centre line), the pass speed.
--   passing    kept over there until MERGE_M in front, then back into its lane. An oncoming car that would be there
--              within ABORT_TTC_S while it is still beside the obstacle: abort – back right, brake below the
--              obstacle's speed, drop in behind it. The stock AI still brakes for anything in its way; when it is
--              too late, it crashes.
-- Meeting: with room between two oncoming vehicles the stock AI's braking for them is switched off for the moment of
--   meeting (it brakes for anything whose line comes within half the two widths of its own). Nobody is steered for it.
-- Gaps: on a busy road nobody would get past. Every GAP_EVERY_S, when cars are queued behind the player, a few of the
--   oncoming cars far ahead (out of sight) are moved to the road behind the player, and for GAP_LEN_S those that respawn
--   ahead go there too. Nobody is slowed down for it.
-- Several lanes one way (motorways, big roads): the car looks at the lane beside it (who is there, how fast they come), indicates
--   and changes lane when a slower one holds it up, keeps right again when it is free, and moves over for the truck joining from
--   a slip road. The stock AI's plan stays in whichever lane the car is put.
-- Talking to each other (every car here knows what the others are doing, as all of it runs in one place):
--   a lane change books its place in the new lane, so that nobody takes the same one; a car held up and blocked at the side asks for
--   a gap and the one beside it lets it in (and for the truck when it indicates); what is happening at the head of a queue is passed
--   back car by car; oncoming cars ease off for one overtaking towards them.
-- Staying on the road: wheels at the edge of the asphalt are brought back early; a car that ended up stuck off the road is put back
--   where the player does not see it.
-- Drivers: each car has a temper (mostly calm, some normal, a few sporty): how hard it accelerates and brakes, how
--   long it waits behind a truck, how bold its passes are, and its own pace (not everybody at exactly the limit). Lorries keep
--   to lorry speed and to the right.
-- Zones: before and inside roadworks, speed cameras, police checks and accident scenes traffic slows down.
-- Diagnosis: M.debug = true (default) logs every pass and, every few seconds, why the cars behind the player do not
--   pass (beamng.log, tag fernfahrer.tai).
-- Our own driver (Beta, settings): lua/vehicle/extensions/fernfahrer/driver.lua does the steering and the pedals on plain roads; what is
--   decided here reaches it instead of BeamNG's AI. It hands a car back by itself where a decision at a junction is needed.
-- career.lua: M.update(ctx, dt); ctx: playerVeh(), trailerId(), roadLimit(), zones() -> list, protect(id), enabled(), ownDriver()

local M = {}
M.debug = true
M.watch = { at = 0, looks = 0, known = 0, left = 0 }
local accidents = require('fernfahrer/accidents')
local priority = require('fernfahrer/priority')
local junctions = require('fernfahrer/junctions')
local flow = require('fernfahrer/trafficflow')
local virt = require('fernfahrer/virtual')
local proxySeq = 0
local parkHeld = {}           -- id -> when a parked car moving was last held again
local parkHow = {}            -- id -> 'dormant' (asleep in BeamNG's pool) or 'hidden' (invisible, hand brake: where the pool is not to be had)
local shapeCfg = {}
local hazards = require('fernfahrer/hazards')

M.C = {
  TICK_S = 0.5,
  NEAR_M = 450,
  LOOK_M = 55,              -- an obstacle this close ahead in the same lane
  LANE_W = 2.4,             -- lateral offset that still counts as "the same lane"
  SLOW_KMH = 10,            -- the obstacle at least this much slower than the limit
  MOVING_MS = 2.0,          -- slower obstacles count as standing
  STOP_WAIT_S = 12,         -- behind the player standing this long: round it slowly
  STOP_WAIT_OTHER_S = 50,   -- behind any other standing one: longer than a red light (they drove round the queue at the lights)
  OTHER_WAIT_S = 15,        -- behind a slow car (not the player) this long before thinking of passing: it is mostly just turning off or starting
  ROUND_MS = 7,             -- (25 km/h)
  FOLLOW_GAP_M = 10,
  FOLLOW_RELEASE_M = 20,    -- following: let go only this much farther back than it started (on and off at one distance was gas, brake, gas)
  MIN_GAIN_MS = 3.5,
  PASS_EXTRA_KMH = 40,      -- the pass speed: obstacle + this (capped by the limit + 9 km/h)
  MERGE_M = 14,
  GUARD_S = 0.12,           -- (the look at the truck's rear: often, it is about the last second)
  GUARD_LOOK_M = 120,       -- (2026-11-11: 95 -> 120; at 100 km/h a standing car needs ~100 m at 4 m/s2)
  GUARD_LAT_M = 2.0,
  GUARD_ALL_M = 260,
  LEVEL_M = 3.5,
  STANDING_MS = 3,          -- (slower: in the way whichever way it points – a wreck at an angle)
  STANDING_WIDER_M = 1.2,            -- (another vehicle this much higher or lower: on a bridge or below it, never in the way)
  CRASH_DMG = 400,
  STRUCT_SHARE = 0.25,
  CHAIN_S = 12,
  WRECK_BLOCK_S = 15,       -- the truck standing behind a wreck in its lane this long (after WRECK_CLEAR_S): towed away, seen or not
  BAD_CRASHES = 3,          -- crashed this often ...
  BAD_S = 120,              -- ... within this: off the road with it, once out of sight
  HAZARD_SHARE = 0.7,             -- a wreck crashing again this soon: not learned as a spot
  -- (2026-11-11, fifth Verkehrstest: one of ours at 49 km/h into a car turning left across its way at a junction - slow, from the oncoming
  -- side, so the guard did not count it: moving towards the car, not in its lane yet. Now a car crossing is judged where it will be)
  -- (the twin: judged anywhere, the straight line ahead in a bend took the cars round it for crossing - the brake three times as often,
  -- more rear-end crashes. Only at a junction, and only across: 60 to 120 degrees)
  -- (and even so: in the twin, three versions of it, all clearly worse - 36 to 37 points against 42, the brake on twice as often, more cars
  -- standing. Off until a drive in the game says otherwise; the slow one turning across from the oncoming side is braked for all the same)
  CROSS = false,
  -- (2026-11-11, ninth Verkehrstest: BeamNG put three cars down at once on a country road - one at 6 km/h, the next 14 m behind it at 77.
  -- No brake stops that; they crashed a second later, twice. A car just put down (JUST_PUT_S) that could not stop in time any more
  -- (MATCH_DECEL) is given the speed of the one in front, there and then - it has only just appeared, away from the truck)
  JUST_PUT_S = 2.5,
  -- (2026-11-12, Verkehrstest 12-16: BeamNG put cars down where the Earth ground was not there yet - they fell 20 to 100 m, and the
  -- traffic coming on found them as wrecks; 50 crashes in five minutes. Falling faster than FALL_MS twice running: taken away at once,
  -- no wreck, nothing learned. And one just put down before a zone at its own speed: the zone's speed there and then)
  FALL_MS = 9,
  -- (2026-11-12, Verkehrstest 21-03: 143 "falls", 70 of them in the very second a virtual car was made real, at 87 to 408 m/s down. A car
  -- moved a few hundred metres has that speed for a moment - no fall. Falling only when it really goes down between two looks)
  FALL_CONFIRM_S = 0.3,     -- two looks at least this far apart ...
  FALL_DROP_M = 3,          -- ... and this much lower at the second
  FALL_FAST_MS = 15,        -- (2026-11-12, Verkehrstest 16-52: falling at 65 to 128 m/s a car moved further between two looks than a jump -
                            -- it counted as put down and was never taken away; 9 fell, several onto the motorway below. Faster than this: at once, in the guard)
  -- (one put down where another already is - 1 s old and 20000 of damage, inside a wreck - or inside a wreck's zone: away at once)
  GUARD_MARGIN_MIN_M = 0.6,  -- the brake keeps this much in hand at walking pace, up to 2 m at speed
  GAP_T = { 0.9, 2.4 },     -- (2026-11-12) the time gaps a driver keeps, from the keen to the calm
  PROXY_Z_LIFT = 0.0,       -- (a placeholder's height over the ground: the models stand on z = 0)
  OVERLAP_M = 3.0,          -- (side by side in two lanes is 3.5 m)
  -- (2026-11-12, Verkehrstest 18-08: 108 falls, the same car up to 32 times. forceTeleport put it 300 to 800 m ahead - into the jam there,
  -- where the Earth ground was missing again. Away now means behind the truck first, on road it has just driven over, with ground under it)
  AWAY_BEHIND_M = { 300, 400, 520 },
  GROUND_UP_M = 3,          -- a car just put down: a ray from this far above it ...
  GROUND_DOWN_M = 4,        -- ... finds ground within this far below it, or it is moved at once
  -- (2026-11-12, Verkehrstest 21-03, the player: "die Autos sind in der Luft gespawnt, ich habe sie über mir gesehen, dann fallen". The height
  -- came from the road network's nodes, in Earth at times well above the road. Every car this file, trafficflow.lua or virtual.lua puts
  -- down goes onto the ground under it: a ray from GROUND_UP_M above down SNAP_DOWN_M; no ground within that: not put down there)
  SNAP_DOWN_M = 14,
  SNAP_LIFT_M = 0.3,
  -- (2026-11-12, the twin: queue cars crept at 4 to 10 km/h into the accident at a jam's head - a cap never goes below 1 m/s, and before
  -- a lane shut it kept 2 m/s on top. At the stop line before what is shut the brakes hold it, as long as it has to wait)
  HOLD_BRAKE = 0.5,
  -- (2026-11-12) hazard lights at the end of a queue, as drivers do here: braking hard from TAIL_WARN_MS for one standing ahead,
  -- for TAIL_WARN_S (longer while it still stands behind it)
  TAIL_WARN_MS = 16,
  TAIL_WARN_S = 6,
  ZONE_MATCH_SIDE_M = 15,
  -- (2026-11-11: "wenn es einen Unfall gibt, drumherum fahren; eine Baustelle erkennen und drumherum fahren, nicht einfach durch".
  -- A zone can say what of the road is shut (block: s0..s1 along it, l0..l1 metres right of the centre line - events.lua works it out
  -- from its props; a wreck and the player's accident: round the car). Who would drive into it: on several lanes over in good time, as
  -- where a lane ends (laneBrain); on one lane each way past it on the other side once the oncoming lane allows, else waiting before it)
  AVOID_LOOK_M = 160,
  AVOID_LOOK_S = 8,
  AVOID_MARGIN_M = 0.5,     -- room kept to the shut strip (on top of half the car's width)
  AVOID_DECEL = 2.0,        -- waiting: slowing as for a stop line ...
  AVOID_STOP_M = 12,        -- ... this far before it (2026-11-11: from 6 m away, at walking pace, there was no room left to swing out)
  AVOID_START_M = 40,       -- out round it this far before it (or AVOID_START_S at its speed) - over by the time it is there
  AVOID_START_S = 3.5,
  AVOID_AFTER_M = 8,        -- back in this far past it
  AVOID_MAX_S = 45,
  AVOID_WRECK_HL = 3.5, AVOID_WRECK_HW = 1.4,     -- a wreck: half its length and width as shut
  AVOID_ACC_HL = 9, AVOID_ACC_HW = 2.6,           -- the player's accident: the truck, the trailer, the other car
  MATCH_DECEL = 7,
  MATCH_AWAY_M = 110,
  CROSS_COS = 0.5,          -- more than 60 degrees off our heading (either way): crossing
  CROSS_JUNCTION_M = 30,
  CROSS_FIRST_S = 0.7,      -- there this much sooner than the other: it is the other's to wait    -- ... and within this of a node of three roads or more
  CROSS_MS = 1.0,
  CROSS_LOOK_S = 3,      -- a crash with another car close by is the road's doing when that one took less than this share of the damage
  WRECK_CLEAR_S = 25,       -- a wreck standing this long ...
  WRECK_UNSEEN_M = 170,     -- ... this far from the player (or well behind it) is cleared away
  WRECK_AWAY_M = { 300, 800 },          -- a traffic car's damage up this much in half a second: a crash (hazards.lua)        -- (the other cars within this of the player are looked at too)
  GUARD_DECEL = 3.2,        -- (twin, learnt twice 2026-11-12: 3.2 better than 4.0 and 3.0) needing to brake harder than this to stay clear of the truck: brakes applied
  GUARD_RELEASE = 2.5,      -- ... and held until it needs less than this (one threshold: the brakes came on and off every look)
  -- (2026-11-13, the player: "nicht immer Vollbremsungen - qualmt hinten, dadurch sieht man schlechter. Ganz smooth anfahren und bremsen,
  -- ein realistischer Rhythmus." Brakes went straight from nothing to the full pedal in one look (GUARD_S): a real emergency reaction, but
  -- the same for every routine close call too - locking the wheels and smoking them even at ordinary traffic density. Now eased in and
  -- out, except a need clearly beyond saving (GUARD_PANIC_WANT): that one still snaps on at once)
  GUARD_RAMP_UP = 3.0,      -- the brake pedal itself rises by this much (0-1) per second ...
  GUARD_RAMP_DOWN = 3.5,    -- ... and falls by this much, once let off
  GUARD_PANIC_WANT = 0.85,  -- a want this high (need near or past GUARD_DECEL * 2) skips the ramp: truly no time left
  -- (2026-11-13, the player: "Gas geben, Vollbremse, Gas geben, Vollbremse ... bis sie irgendwann drumherum sind" - round a wreck, the
  -- smooth cap from avoidZones (BeamNG's own ai.setSpeed) already slows the car in good time, but the guard watched the same wreck as a
  -- standing "target" and kept slamming the full brake on top of it every look, undoing the smooth approach; once let go, BeamNG's AI
  -- throttled straight back up to the (still reduced) cap and closed in again - a loop. While the avoidance is already on this exact
  -- obstacle, the guard now only steps in for something that cap could not have caught in time)
  GUARD_DECEL_AVOID = 6.5,
  GUARD_RELEASE_AVOID = 5.0,
  AVOID_GUARD_GRACE_S = 2.5,  -- how long after the last look at that block the higher threshold still applies
  ONCOMING_LAT_M = 7,
  SLOW_SHARE = 0.6,         -- only vehicles slower than this share of the limit are passed
  SLOW_SHARE_TRUCK = 0.85,  -- ... a lorry a good deal less slow: everybody passes a lorry doing 80 on a road for 100
  TRUCK_LEN_M = 7,
  TOWN_KMH = 60,            -- this limit or less: in town, nobody overtakes (only round something standing)
  QUEUE_M = 40,             -- an obstacle that itself follows a slower one this close: a queue, nobody jumps it
  MEET_M = 70,              -- meeting: an oncoming vehicle this close ahead
  MEET_ROOM = 0.12,         -- ... with this much room between them (plus their half widths): no braking for it
  MEET_S = 5,
  JUMP_M = 80,              -- a car this much farther than half a second ago was respawned
  AHEAD_CLEAR_M = 700,      -- no car respawned this close ahead in the player's lane (it starts from standstill)
  SCAN_M = 1500,
  -- (2026-11-12, Verkehrstest 19-46) with the virtual traffic BeamNG's respawning is off - but no real car within STARVE_M of the player
  -- for STARVE_S: on again until there is one (a safety net, whatever went wrong)
  STARVE_M = 450,
  PARK_HOLD_MS = 1.5,       -- a parked (invisible) car faster than this is held again ...
  PARK_HOLD_S = 1,          -- ... at most this often
  PUT_SETTLE_S = 0.35,      -- a car just moved: its speed is not trusted for this long
  STILL_MS = 0.8,           -- (2026-11-14) slower than this a held car is held by the hand brake (the pedal at a stand means reverse)
  SPEED_HOLD_S = 2.5, SPEED_HOLD_DV = 2.5,   -- (2026-11-14) made real: held at the placeholder's speed this long, while off by more than this
  -- (2026-11-14, Verkehrstest 23-53: "nach einer gewissen Zeit werden die Autos unsichtbar". BeamNG fades a car out to respawn it and
  -- in again where it puts it down - on Earth's short road map that place is often not found, and it stays faded, driving on, solid)
  INVIS_NEAR_M = 220,       -- a faded car this near the player: seen again at once
  INVIS_MAX_S = 4,          -- ... and any faded one waiting longer than this for BeamNG's respawn
  INVIS_HOLD_M = 120,       -- ... and BeamNG's respawn radius for it set this far past the player, so that it does not fade again at once
  -- (2026-11-14, Verkehrstest 23-53: "auf schmalen Straßen weicht sich der Gegenverkehr nicht aus, sondern bleibt voreinander stehen",
  -- and cars reversing out of nowhere: the stock AI brakes to standing for an oncoming car whose line comes within their two half widths
  -- and then backs up. On a narrow road both slow early to a crawl - the stock AI makes room past one going slowly (its pass margin), our
  -- own driver moves over to the edge (driver.lua) - and nobody brakes hard for, or queues behind, one standing there facing it)
  -- (2026-11-14, Verkehrstest 14-30: "sie fahren immer noch aus dem Nichts rückwärts auf schmalen Straßen" - BeamNG's AI, stuck before an
  -- oncoming car, backs up. A car of ours going backwards for REV_S: out of the player's sight it is taken away, in sight it is held and our
  -- own driver (who meets and passes) asked for at once)
  REV_MS = 1.0, REV_S = 1.0, REV_AWAY_M = 140, REV_HOLD_S = 3,
  TRUCK_AVOID_MAX_S = 25,   -- (2026-11-14) the autodrive's way round a block: never longer than this ...
  TRUCK_AVOID_STEER_N = 2,  -- ... and held out there by at most this many nudges (more fought Earth's own path: the wheel to and fro)
  NARROW_HALF_M = 2.7,      -- a two-way road this narrow (half its width): one lane's width each way at most
  NARROW_LOOK_M = 45,       -- an oncoming vehicle in the way this far ahead (or NARROW_LOOK_S at its speed) ...
  NARROW_LOOK_S = 4.5,
  NARROW_LAT_M = 2.6,       -- ... this close to its line (at most: and closer than their two half widths and NARROW_ROOM_M)
  NARROW_ROOM_M = 0.3,
  -- (2026-11-14, Verkehrstest 18-43: "die Autos weichen mir aus und bremsen, viel zu früh" - BeamNG's AI pushes its line aside for any vehicle
  -- within 0.8 of their two widths (3.5 m for a car and the lorry), the push AWARE_COEF of its own 0.25; sent with its aggression)
  AWARE_COEF = 0.08,
  NARROW_MS = 2.5,          -- ... and it meets it at walking pace
  NARROW_DECEL = 1.5,
  NARROW_SLOW_M = 8,
  NARROW_GUARD_LAT_M = 1.7, -- one standing there facing it: in the way for the emergency brake only this close to its line
  -- (2026-11-13, Verkehrstest 13-42: 129 emergency brakes above 80 km/h, nearly all with "the end of a queue ahead" - the stock AI and our
  -- look ahead (LOOK_M, 55 m) saw a standing queue too late: at 100 km/h it takes 100 m at 4 m/s2. Now a driver's look ahead: a queue or a
  -- standing car in its lane up to QAHEAD_MAX_M away, and the speed eased down on a gentle curve towards it)
  QAHEAD_S = 7,             -- looked ahead this many seconds of its speed ...
  QAHEAD_MIN_M = 60, QAHEAD_MAX_M = 220,
  QAHEAD_LAT_M = 1.9,       -- ... in its lane
  QAHEAD_DV = 4,            -- only for one clearly slower (m/s): ordinary slower traffic is the overtaking's business
  QAHEAD_DECEL = 1.8,       -- the gentle braking towards it (the emergency brake comes on at GUARD_DECEL 3.2)
  QAHEAD_S0 = 7,            -- standing this far behind it
  -- (2026-11-13, the same test: 824 of the 1070 emergency brakes below 20 km/h, most at 1 or 2 km/h - one held before a block crept off as
  -- soon as it stood (the stock AI wants to go), was braked again, let go once it stood: a jerk every second, for minutes. Held, it stays held)
  STARVE_S = 20,
  MAX_BEND_DEG = 20,
  SIDE_ROAD_DRV = 0.5,      -- a junction counts when a road of at least this drivability joins (priority.lua rates side roads at 0.65 of the main road)
  ABORT_TTC_S = 3.4,
  PASS_TIMEOUT_S = 14,
  PASS_MIN_HALF = 2.7,      -- a road narrower than twice this (a car beside a truck does not fit): nobody overtakes on it
  DRIFT_LAT = -0.2,         -- the lane watch: the car's middle this far right of the centre line (negative: left of it) is wrong
  DRIFT_HOLD_S = 1.0,       -- ... for this long
  DRIFT_EVERY_S = 2.5,      -- ... and at most one correction this often (each adds to the planned offset)
  DRIFT_ALIGN = 0.9,        -- only with the car along the road (about 25 degrees): not while it turns
  DRIFT_JUNCTION_M = 18,    -- only this far from a junction: "the nearest road" is any of them there
  -- (2026-11-09: 34 passes in 10 minutes, 20 of them given up half way: cars kept swinging out and back. Rare and with room to spare)
  COOLDOWN_S = 40,
  MAX_PASSING = 1,
  RAMP_FAST_MS = 22, RAMP_LOOK_M = 600, RAMP_ACC = 1.6,   -- (2026-11-14) on-ramps: up to the motorway's pace by the merge
  OWN_TRY_S = 1.5,          -- our own driver: asks to take a car over this often (2026-11-14: 3)
  OWN_AFTER_PUT_S = 0.5,    -- (2026-11-14) ... and this soon after the car was moved or made real out of a placeholder: ours from the start
  LANE_MAX_BEND = 12,       -- several lanes: no lane change with more of a bend than this ahead
  YIELD_M = 70,             -- lets in one asking for a gap this far ahead of it
  PASSER_M = 320,           -- oncoming cars ease off for one overtaking towards them, this far away
  EDGE_MARGIN = 0.2,        -- a car's side this far over the real edge of the asphalt: back in
  EDGE_HOLD_S = 0.5,
  EDGE_EVERY_S = 1.5,
  RESCUE_S = 7,             -- standing off the road this long: put back on it, when the player does not see it
  LANE_COOL_S = 14,         -- several lanes: at least this long between two lane changes of one car (no weaving)
  LANE_GAIN_MS = 3,
  SLOW_ROAD_KMH = { 70, 100 },  -- a slow vehicle: on a country road with a limit like this ...
  SLOW_AHEAD_M = { 250, 900 },  -- ... a car this far ahead of the player, going its way ...
  SLOW_MS = { 9.5, 12.5 },      -- ... at 34-45 km/h ...
  SLOW_FOR_S = { 150, 300 },    -- ... for so long ...
  SLOW_EVERY_S = { 480, 900 },  -- ... and the next one after this
  -- (2026-11-11, sixth Verkehrstest: "auf Landstraßen sollen die Autos nicht 40 fahren für eine gewisse Zeit, sondern normal - wenn 100
  -- erlaubt ist, sollen die schon 100 fahren. Fließender Verkehr, normaler Rhythmus". Off)
  SLOW_ON = false,
  SLOW_FIRST_S = { 240, 480 },
  GASSE_M = 0.8,            -- the Rettungsgasse: this far to the side of its lane
  GASSE_MS = 4,             -- (only once slower than this: standing, creeping)
  GASSE_OVER_M = 12,
  LANE_END_LOOK_M = 250,    -- a lane ending: looked for this far ahead, or this many seconds
  LANE_END_LOOK_S = 10,
  LANE_END_DECEL = 1.5,     -- still not over: slowing so as to be at walking pace this far before its end
  LANE_END_STOP_M = 15,         -- changes lane for one at least this much slower than it wants to go
  LANE_JUNCTION_M = 70,     -- on a town road, not this close before a junction
  BEHIND_EVERY_S = 6,       -- a look whether there is any traffic behind the player
  BEHIND_WANT = 3,          -- ... this many going its way within
  BEHIND_SCAN_M = 450,
  DONOR_M = 520,            -- a car this far away (nobody sees it) goes there
  PACE_MAX_MS = 41,         -- (148 km/h)
  ZONE_BEFORE_M = 220,
  GAP_EVERY_S = { 30, 50 },
  GAP_LEN_S = { 30, 40 },
  GAP_RESPAWN_MOVE = 8,     -- during a gap, cars respawned ahead of the player go behind it instead (at most)
  GAP_MOVE = 3,             -- this many oncoming cars go to the road behind the player
  GAP_MOVE_FROM_M = 650,    -- (only ones this far ahead: out of sight)
  BEHIND_M = { 170, 260 },
  -- (2026-11-11, Verkehrstest: 25 crashes in 25 minutes, most of them 1-9 s after a car had been put down – standing, in the truck's lane,
  -- 200 m behind it on the motorway, and whatever came up at 120 ran into it. And with BeamNG's respawn value 1 a car counted as gone 80 m
  -- away: 131 respawns in 20 minutes with five cars, each starting again at 50 km/h at most)
  PUT_CLEAR_M = 40,         -- nobody this close to the spot
  PUT_CLEAR_BEHIND_M = 160, -- ... and nobody coming up the same way this far behind it
  PUT_SPEED_SHARE = 0.9,    -- put down at the player's speed, at most this share of the limit there
  SPAWN_VALUE = 0.5,        -- BeamNG's respawn value for all traffic (1: gone at 80 m, 0.5: at 120 m, and half as quick)
  BOOST_MIN_KMH = 70,       -- the game's own respawns on roads this fast: brought up to the pace there
  BOOST_SHARE = 0.8,
  BOOST_DECEL = 2.0,        -- (a comfortable stop, m/s2)
  BOOST_LOOK_MAX_M = 260,
  LOG_S = 4,
}
local C = M.C

M.TEMPERS = {
  -- (the AI's limit for cornering and braking is aggression * g. Stock traffic is 0.35, never under 0.25: at 0.16 a car slowed down
  -- for every kink of the road graph. 0.62 was too much the other way: they swung over the middle)
  -- (pace: share of the limit it drives at; everybody at exactly the limit never catches up with anybody)
  { share = 0.51, aggr = { 0.32, 0.38 }, wait = { 5, 11 }, risk = { 0.82, 0.98 }, pace = { 0.93, 1.00 } },   -- calm
  { share = 0.33, aggr = { 0.36, 0.42 }, wait = { 2.5, 6 }, risk = { 0.68, 0.85 }, pace = { 1.00, 1.06 } },  -- normal
  { share = 0.12, aggr = { 0.42, 0.48 }, wait = { 1, 3 }, risk = { 0.56, 0.70 }, pace = { 1.06, 1.14 } },    -- sporty
  -- (2026-11-10: the speeder, on purpose and now and then: goes in close in front after a pass, waits for nobody. Everybody else keeps
  -- a proper distance – an overtaker that cut in and braked was a fault, not a character)
  { share = 0.04, aggr = { 0.46, 0.52 }, wait = { 0.5, 1.5 }, risk = { 0.42, 0.55 }, pace = { 1.12, 1.2 }, rash = true },
}

local cars = {}
local tickT, logT, spawnVarsT = 0, 0, -1e9
M.slowVehicle = {}
local gap = { nextAt = nil, untilT = 0, moved = 0, respawnMoved = 0 }
local function now() return os.clock() end
-- (2026-11-11) its own random numbers (Park-Miller, exact in doubles): the rest of the game drawing from math.random does not change what
-- happens here, nor this the rest - in the digital twin one change no longer reshuffles every drive, so an A/B test compares like with like.
-- A driver's temper comes from its vehicle id, whenever it turns up. Seeded once from math.random: in the game as random as before
local SEED0 = math.floor(math.random() * 2147483645) + 1
local seed = SEED0
local function rand() seed = (seed * 16807) % 2147483647; return seed / 2147483647 end
local function rnd(a, b) return a + rand() * (b - a) end
M.reseed = function(s) SEED0 = math.floor(s) % 2147483646 + 1; seed = SEED0 end
local function flat(v) local w = vec3(v.x, v.y, 0); local l = w:length(); return l > 1e-3 and w * (1 / l) or nil end
local function obj(id) return getObjectByID(id) end
-- (2026-11-11, the digital twin: at a motorway over a town road a car on the motorway took the car in the underpass, 4 m below, for one
-- standing in its lane – emergency brake, and the traffic behind ran into it. Who is ahead / beside / in the way: on the same level only)
local FAR = vec3(1e6, 1e6, 0)
local function relOf(a, b)
  local r = a - b
  if math.abs(r.z) > M.C.LEVEL_M then return FAR end
  return r
end
local function send(id, cmd) local v = obj(id); if v then v:queueLuaCommand(cmd) end end
local function dlog(fmt, ...)
  if M.tap then pcall(M.tap, fmt) end            -- (the traffic lab counts what happens, trafficlab.lua)
  if M.debug then log('I', 'fernfahrer.tai', string.format(fmt, ...)) end
end
-- (2026-11-13, Verkehrstest 10-23: cars parked out of sight drove on, invisible, at up to 100 km/h into the traffic. BeamNG, after every
-- respawnVehicle, resets a traffic car the frame after (vehicle.lua onRefresh -> role:resetAction -> setAiMode(traffic), resetElectrics):
-- our ai.setMode("disabled") and the hand brake were undone. Its mode set on BeamNG's own traffic object: isAi false, no refresh, no
-- respawning of it by BeamNG; and back again)
local function beamMode(id, mode)
  local gt = rawget(_G, 'gameplay_traffic')
  if gt and gt.getTrafficData then
    local okD, data = pcall(gt.getTrafficData)
    local v = okD and type(data) == 'table' and data[id] or nil
    if v and v.setAiMode and pcall(v.setAiMode, v, mode) then return true end
  end
  send(id, string.format('ai.setMode("%s")', mode))
  return false
end
M.beamMode = beamMode

-- (2026-11-13, Verkehrstest 13-42: "ganz viele Autos sind unsichtbar", "die Autos bremsen immer noch abrupt". A car parked out of sight
-- (a placeholder in its place) was only made invisible and held with the hand brake - and every one of them was sent to the same spot,
-- 450 m behind the truck: in one another, flung apart, then about at 35 to 55 km/h, invisible but solid, in the traffic's way (nine cars
-- at exactly the same speed in the log). Now it is put to sleep where it is by BeamNG's own pool, as BeamNG keeps its reserve vehicles
-- dormant (gameplay/traffic.lua setVehToDormant): inactive - no physics, no collision, not drawn, no Lua, nothing to pay for it)
local dormantKeep = {}        -- id -> the traffic flags it had before
local function trafficPool()
  local vp = rawget(_G, 'core_vehicleActivePooling')
  return vp and vp.getPool and vp.getPool('autoTraffic') or nil
end
local function trafficVeh(id)
  local gt = rawget(_G, 'gameplay_traffic')
  if not gt or not gt.getTrafficData then return nil end
  local okD, data = pcall(gt.getTrafficData)
  return okD and type(data) == 'table' and data[id] or nil
end
local function canDormant(id)
  local pool = trafficPool()
  return pool ~= nil and pool.allVehs ~= nil and pool.allVehs[id] == 1 and trafficVeh(id) ~= nil
end
local function toDormant(id)
  -- (out of the pool already, woken all the same: just inactive again)
  local k0 = dormantKeep[id]
  if k0 and k0.outPool then
    local o = getObjectByID(id)
    if o and o.setActive then pcall(function() o:setActive(0) end) end
    return true
  end
  if not canDormant(id) then return false end
  local v, pool = trafficVeh(id), trafficPool()
  -- (asleep again after BeamNG woke it: the values from before the first sleep are kept, not the parked ones)
  local again = dormantKeep[id] ~= nil
  if not again then
    dormantKeep[id] = { enableRespawn = v.enableRespawn, enableAutoPooling = v.enableAutoPooling, activeProbability = v.activeProbability,
      ignoreForceTeleport = v.ignoreForceTeleport, reserved = v.reserved }
  end
  -- (a reserve, not claimed, not to respawn: BeamNG's pool keeps it asleep even when it fills the active ones up again)
  v.reserved, v.enableRespawn, v.enableAutoPooling, v.activeProbability, v.ignoreForceTeleport, v.respawnSpeed = 'fernfahrer_park', false, false, 0, true, nil
  -- (2026-11-14, Verkehrstest 16-46: 2060 times "woken by BeamNG while parked", up to 30 cars in one second every quarter minute - each
  -- change of the number of cars makes BeamNG's pool wake every inactive car (setAllVehs) and put the reserves back at once, but it books
  -- a car as awake only a frame later, so the putting back is taken for done already: the cars stood there, real, where they fell asleep.
  -- Now a sleeping car leaves BeamNG's pool altogether (as Earth itself keeps an occupied car out of it): nothing of BeamNG's wakes it)
  local okS, done
  local o = getObjectByID(id)
  if pool.removeVeh and pool.insertVeh and o and o.setActive then
    okS, done = pcall(pool.removeVeh, pool, id)
    if okS and done then
      dormantKeep[id].outPool = true
      pcall(function() o:setActive(0) end)
      M.put.outPool = (M.put.outPool or 0) + 1
    end
  else
    okS, done = pcall(pool.setVeh, pool, id, false)
  end
  if not okS or not done or (o and o.getActive and o:getActive()) then
    if dormantKeep[id] and dormantKeep[id].outPool then pcall(pool.insertVeh, pool, id, true); dormantKeep[id].outPool = nil end
    local k = dormantKeep[id]
    v.reserved, v.enableRespawn, v.enableAutoPooling, v.activeProbability, v.ignoreForceTeleport = k.reserved, k.enableRespawn, k.enableAutoPooling, k.activeProbability, k.ignoreForceTeleport
    if not again then dormantKeep[id] = nil end
    return false
  end
  return true
end
local function fromDormant(id)
  local v, k = trafficVeh(id), dormantKeep[id] or {}
  dormantKeep[id] = nil
  if v then
    v.reserved = k.reserved
    v.enableRespawn = k.enableRespawn ~= false
    v.enableAutoPooling = k.enableAutoPooling ~= false
    v.activeProbability = k.activeProbability or 1
    v.ignoreForceTeleport = k.ignoreForceTeleport
    v._teleport, v.respawnSpeed, v.alpha = nil, nil, 1    -- (no teleport of BeamNG's own on waking, and seen at once: no fade)
  end
  local pool = trafficPool()
  local o = getObjectByID(id)
  if k.outPool and pool and pool.insertVeh and o then
    -- (back into the pool, awake: forced in, as BeamNG's own reserves are)
    pcall(function() o:setActive(1) end)
    pcall(pool.insertVeh, pool, id, true)
  elseif pool then pcall(pool.setVeh, pool, id, true, true)
  elseif o then pcall(function() o:setActive(1) end) end
  pcall(function() getObjectByID(id):setMeshAlpha(1, '') end)
end
-- room among the active ones for a sleeping car to wake (else one of the active far away is taken instead: no count over BeamNG's limit,
-- which it would put right by sending an arbitrary active car - perhaps one in sight - to sleep)
local function poolRoom()
  local pool = trafficPool()
  if not pool or not pool.activeVehs or not pool.maxActiveAmount then return true end
  return #pool.activeVehs < pool.maxActiveAmount
end
M._dormant = { to = toDormant, from = fromDormant, can = canDormant, room = poolRoom, keep = dormantKeep }

local function newDriver(id)
  -- (its own little stream, from its id: the same car the same temper)
  local s = ((tonumber(id) or 1) * 48271 + SEED0) % 2147483647
  if s == 0 then s = 1 end
  local function r1() s = (s * 16807) % 2147483647; return s / 2147483647 end
  local function rr(a, b) return a + r1() * (b - a) end
  r1(); r1()
  local r, acc = r1(), 0
  local t = M.TEMPERS[1]
  for _, x in ipairs(M.TEMPERS) do acc = acc + x.share; if r <= acc then t = x; break end end
  local d = { aggr = rr(t.aggr[1], t.aggr[2]), wait = rr(t.wait[1], t.wait[2]), risk = rr(t.risk[1], t.risk[2]),
    pace = rr(t.pace[1], t.pace[2]), rash = t.rash or nil, behindT = 0, aggrAt = 0 }
  -- (2026-11-12, the player: "die Abstände müssen variabel sein, mal ein bisschen mehr, mal weniger, nicht alle gleich". Its own time gap
  -- to the one in front: the calm ones keep more, the keen ones less, and no two alike - the mod's own driver keeps it, driver.lua setFollowT)
  local keen = math.max(0, math.min(1, (d.aggr - 0.32) / 0.16))
  d.gapT = math.max(C.GAP_T[1], math.min(C.GAP_T[2], 2.0 - keen * 0.9 + rr(-0.35, 0.35)))
  return d
end

-- (2026-11-11, eighth Verkehrstest: "only 12 m of road ahead" on a motorway with kilometres of it loaded. BeamNG's graph has edges kept on
-- one of their two nodes only (map.lua: "single sided"), and a walk along nodes[n].links ended where the way on was kept on the next
-- node. All the links of a node, its own and those kept on the other side; the other sides gathered once for every new graph)
local revOf, revFor = nil, nil
local function reverseLinks(nodes)
  if revFor == nodes then return revOf end
  local rev = {}
  for k, nd in pairs(nodes) do
    for m, l in pairs(nd.links or {}) do
      local o = nodes[m]
      if o and not (o.links and o.links[k]) then
        local r = rev[m]
        if not r then r = {}; rev[m] = r end
        r[k] = l
      end
    end
  end
  revOf, revFor = rev, nodes
  return rev
end
local NO_LINKS = {}
local function linksOf(nodes, n)
  if not nodes then return NO_LINKS end
  local nd = nodes[n]
  local own = nd and nd.links or NO_LINKS
  local r = reverseLinks(nodes)[n]
  if not r then return own end
  local all = {}
  for k, l in pairs(own) do all[k] = l end
  for k, l in pairs(r) do if all[k] == nil then all[k] = l end end
  return all
end
M.linksOf = linksOf

-- the road under pos (stock road graph): centre line point, direction (along dir), half width, the edge's nodes
local function roadAt(pos, dir)
  if not (map and map.findClosestRoad and map.getMap) then return nil end
  local n1, n2 = map.findClosestRoad(pos)
  local g = map.getMap()
  local nodes = g and g.nodes
  if not n1 or not n2 or not nodes or not nodes[n1] or not nodes[n2] then return nil end
  local a, b = nodes[n1], nodes[n2]
  local ab = b.pos - a.pos
  local len2 = ab:squaredLength()
  if len2 < 0.01 then return nil end
  local tt = math.max(0, math.min(1, (pos - a.pos):dot(ab) / len2))
  local centre = a.pos + ab * tt
  local d = flat(ab)
  local fwd, back = n2, n1
  if d and dir and d:dot(dir) < 0 then d = -d; fwd, back = n1, n2 end
  -- (2026-11-09: an edge can be kept on one of its two nodes only - the game's own code asks both, this did not: "which road" was unknown for good)
  local link = (a.links and a.links[n2]) or (b.links and b.links[n1])
  local half = (link and (link.inRadius or link.outRadius)) or ((a.radius or 3) + (b.radius or 3)) * 0.5
  return centre, d, half, back, fwd, nodes, link
end

-- a node of three roads or more within m of pos (the crossing check of the guard)
local function atJunction(pos, dir, m)
  local centre, _, _, back, fwd, nodes = roadAt(pos, dir)
  if not centre or not nodes then return false end
  for _, n in ipairs({ back, fwd }) do
    local nd = n and nodes[n]
    if nd and nd.pos and nd.pos:distance(pos) <= m then
      local deg = 0
      for _ in pairs(nd.links or {}) do deg = deg + 1 end
      if deg > 2 then return true end
    end
  end
  return false
end

local function lateralOf(pos, dir)
  local centre, d, half, _, _, _, link = roadAt(pos, dir)
  if not centre or not d then return nil end
  return (pos - centre):dot(vec3(d.y, -d.x, 0)), half, link
end

-- is b in another lane than a car at a, going dir? (a straight line ahead runs through the next lane in any bend: the road knows
-- better. false when it can't tell: off its road, the nearest edge is another one)
local function otherLane(a, dir, b)
  local la, ha = lateralOf(a, dir)
  local lb, hb = lateralOf(b, dir)
  if not la or not lb or not ha or not hb then return false end
  if math.abs(la) > ha + 1.5 or math.abs(lb) > hb + 1.5 then return false end
  return math.abs(la - lb) > M.C.LANE_W
end

-- (2026-11-09) a carriageway of its own (one-way, a divided road): "left of the centre" is the central barrier there, not an
-- oncoming lane – the passes went into it
local function oneWayRoad(pos, dir)
  local _, _, link = lateralOf(pos, dir)
  return type(link) == 'table' and link.oneWay == true
end

-- (2026-11-09) how far right of the centre line a car is, only where that means something: a two-way road with as many lanes each
-- way, the car along it, no junction near. nil and why: can't tell here (turning, a junction, the nearest edge is another road).
local function laneDrift(pos, dir)
  local centre, d, half, back, fwd, nodes, link = roadAt(pos, dir)
  if not centre or not d then return nil, 'no road' end
  if type(link) == 'table' and link.oneWay then return nil, 'one-way' end
  if d:dot(dir) < C.DRIFT_ALIGN then return nil, 'turning' end
  if type(link) == 'table' and type(link.lanes) == 'string' then
    local _, plus = link.lanes:gsub('%+', '')
    local _, minus = link.lanes:gsub('%-', '')
    if plus ~= minus then return nil, 'uneven lanes' end
  end
  for _, n in ipairs({ back, fwd }) do
    local degree = 0
    for _ in pairs(linksOf(nodes, n)) do degree = degree + 1 end
    if degree > 2 and nodes[n].pos:distance(pos) <= C.DRIFT_JUNCTION_M then return nil, 'junction' end
  end
  local lat = (pos - centre):dot(vec3(d.y, -d.x, 0))
  if lat < -half - 1.5 then return nil, 'another road' end
  return lat, half
end

-- walk the graph from edge (prev -> cur) along the straightest links; calls fn(node, travelled, heading) per node,
-- stops when fn returns true or after dist
local function walk(nodes, prevNode, cur, heading, startDist, dist, fn)
  local travelled = startDist
  for _ = 1, 60 do
    if travelled > dist then return end
    local best, bestDot = nil, -2
    for m in pairs(linksOf(nodes, cur)) do
      if m ~= prevNode and nodes[m] then
        local d = flat(nodes[m].pos - nodes[cur].pos)
        if d and d:dot(heading) > bestDot then best, bestDot = m, d:dot(heading) end
      end
    end
    if fn(cur, travelled, heading, best) then return end
    if not best then return end
    local d = flat(nodes[best].pos - nodes[cur].pos)
    travelled = travelled + nodes[cur].pos:distance(nodes[best].pos)
    heading, prevNode, cur = d, cur, best
  end
end

-- the road ahead: the largest heading change, and the distance to the first real junction (a side road joining)
local function roadAhead(pos, dir, dist)
  local centre, heading, _, back, fwd, nodes = roadAt(pos, dir)
  if not centre or not heading then return 0, nil, false end
  local start, maxBend, junctionAt = heading, 0, nil
  local top, crest = pos.z, false                 -- (2026-11-09: over a crest nobody sees the oncoming lane)
  walk(nodes, back, fwd, heading, nodes[fwd].pos:distance(pos), dist, function(n, travelled, h, nextNode)
    local z = nodes[n].pos.z
    if z > top then top = z elseif top - z > 1.2 and top - pos.z > 1.8 then crest = true end
    local bend = math.deg(math.acos(math.max(-1, math.min(1, h:dot(start)))))
    if bend > maxBend then maxBend = bend end
    for m, link in pairs(linksOf(nodes, n)) do
      if m ~= nextNode and nodes[m] and (link.drivability or 1) >= C.SIDE_ROAD_DRV then
        local d = flat(nodes[m].pos - nodes[n].pos)
        -- a road leaving to the side (not the one we came from)
        if d and d:dot(h) > -0.8 and d:dot(h) < 0.8 then junctionAt = junctionAt or travelled end
      end
    end
    return false
  end)
  return maxBend, junctionAt, crest
end

-- a place on the road dist m behind pos (against dir), in the right lane, facing dir
local function placeBehind(pos, dir, dist)
  -- (2026-11-08: on the way the truck came, when it has come that far: on the motorway the graph's nearest road may be
  -- the other carriageway)
  local tp, td = accidents.behind(dist)
  if tp then return tp + vec3(0, 0, 0.4), td end
  local centre, heading, half, back, fwd, nodes = roadAt(pos, dir)
  if not centre or not heading then return nil end
  local spot, spotDir
  walk(nodes, fwd, back, -heading, nodes[back].pos:distance(pos), dist + 40, function(n, travelled, h)
    if travelled >= dist then spot, spotDir = vec3(nodes[n].pos), -h; return true end
    return false
  end)
  if not spot then return nil end
  local right = vec3(spotDir.y, -spotDir.x, 0)
  return spot + right * ((half or 3) * 0.5) + vec3(0, 0, 0.4), spotDir
end

local lenCache = {}
-- (2026-11-10) how wide: a lorry's middle can be right of the centre line with its left side well over it
local widCache = {}
local function widthOf(id)
  if widCache[id] then return widCache[id] end
  local v = obj(id)
  if not v then return 1.9 end
  local ok, w = pcall(function() return v:getSpawnWorldOOBB():getHalfExtents().x * 2 end)
  w = ok and tonumber(w) or 1.9
  if w < 1.2 or w > 3.2 then w = 1.9 end
  widCache[id] = w
  return w
end

local function lengthOf(id)
  if lenCache[id] then return lenCache[id] end
  local v = obj(id)
  if not v then return 5 end
  local ok, bb = pcall(function() return v:getSpawnWorldOOBB() end)
  local l = ok and bb and bb:getHalfExtents().y * 2 or 5
  lenCache[id] = l
  return l
end

-- (pedestrians of the Pedestrians mod are vehicles too: left out – walkers on the pavement made passes wait)
local pedCache = {}
local function isPed(id)
  local v = pedCache[id]
  if v == nil then
    local o = getObjectByID(id)
    v = o and (o.JBeam == 'pedestrian') or false
    pedCache[id] = v
  end
  return v
end

local function snapshot(center, radius)
  local out = {}
  for id, o in pairs(map and map.objects or {}) do
    if o.pos and center:distance(o.pos) < radius and not isPed(id) then
      local vel = o.vel and vec3(o.vel) or vec3(0, 0, 0)
      local dir = (o.dirVec and flat(vec3(o.dirVec))) or flat(vel)
      out[id] = { pos = vec3(o.pos), vel = vel, dir = dir, speed = vel:length(), signal = type(o.states) == 'table' and tonumber(o.states.turnsignal) or 0 }
    end
  end
  return out
end

-- (2026-11-11) a car put on the road by this file: only where nobody is about to run into it, and at speed (the game gives its own
-- respawns a start speed, a car moved with respawnVehicle stood still)
M.put = { done = 0, refused = 0 }
M.flow = flow
M.put.eco = flow.ecoStats
local function snapGround(q)
  if not q or not castRayStatic then return q end
  local okR, hit = pcall(castRayStatic, vec3(q.x, q.y, q.z + C.GROUND_UP_M), vec3(0, 0, -1), C.SNAP_DOWN_M)
  if not okR or type(hit) ~= 'number' then return q end
  if hit >= C.SNAP_DOWN_M - 0.05 then M.put.noSnap = (M.put.noSnap or 0) + 1; return nil end
  local z = q.z + C.GROUND_UP_M - hit + C.SNAP_LIFT_M
  if math.abs(z - q.z) > 1.5 then M.put.snapped = (M.put.snapped or 0) + 1 end
  return vec3(q.x, q.y, z)
end
M.snapGround = snapGround

local function putBehind(id, spot, sdir, p)
  if not spot or not sdir then return false end
  spot = snapGround(spot)
  if not spot then M.put.refused = M.put.refused + 1; return false end
  local gt = rawget(_G, 'gameplay_traffic')
  if not (gt and gt.respawnVehicle) then return false end
  local right = vec3(sdir.y, -sdir.x, 0)
  for oid, o in pairs(snapshot(spot, C.PUT_CLEAR_BEHIND_M + 20)) do
    if oid ~= id then
      local rel = relOf(o.pos, spot)
      local along = rel:dot(sdir)
      if rel:length() < C.PUT_CLEAR_M
         or (o.dir and o.dir:dot(sdir) > 0.5 and along < 0 and along > -C.PUT_CLEAR_BEHIND_M and math.abs(rel:dot(right)) < 8) then
        M.put.refused = M.put.refused + 1
        return false
      end
    end
  end
  local _, _, _, _, _, _, link = roadAt(spot, sdir)
  local lim = type(link) == 'table' and tonumber(link.speedLimit) or 14
  local v = math.max(4, math.min(lim * C.PUT_SPEED_SHARE, (p and p.speed or lim) + 2, C.PACE_MAX_MS))
  if not pcall(gt.respawnVehicle, id, spot, quatFromDir(sdir, vec3(0, 0, 1))) then return false end
  local okD, data = pcall(gt.getTrafficData)
  if okD and type(data) == 'table' and data[id] then data[id].respawnSpeed = v
  else send(id, string.format('thrusters.applyVelocity(obj:getDirectionVector() * %.1f, 0.25)', v)) end
  M.put.done = M.put.done + 1
  return true
end
M.putBehind = putBehind

-- ground under a place? (no answer: as before, yes)
local function groundOk(q)
  if not q or not castRayStatic then return true end
  local reach = C.GROUND_UP_M + C.GROUND_DOWN_M
  local okR, hit = pcall(castRayStatic, vec3(q.x, q.y, q.z + C.GROUND_UP_M), vec3(0, 0, -1), reach)
  if not okR or type(hit) ~= 'number' then return true end
  return hit < reach - 0.05
end
M.groundOk = groundOk

-- (2026-11-12) a car taken away (falling, put down into another, a wreck cleared): behind the truck if there is room, else where the game likes
local function sendAway(id, pos, dir, speed)
  -- (2026-11-14, Verkehrstest 18-43: 71 crashes in the jam scene, most a car put down at 83 to 100 km/h into the queue or right before a wreck -
  -- one taken away (fallen, backing up, a wreck cleared) and given to BeamNG's forceTeleport, which puts it ahead at the road's respawn speed.
  -- With the virtual traffic it needs no new place: it goes to sleep where it is, and comes back as a placeholder's real car, repaired)
  if M.virtOnNow and not virt.parked[id] and canDormant(id) then
    send(id, 'if fernfahrer_driver then fernfahrer_driver.release("parked") end electrics.set_warn_signal(false)')
    if toDormant(id) then
      parkHow[id], parkHeld[id] = 'dormant', nil
      virt.parked[id] = now()
      M.put.awaySleep = (M.put.awaySleep or 0) + 1
      return true
    end
  end
  if pos and dir then
    for _, dist in ipairs(C.AWAY_BEHIND_M) do
      local spot, sdir = placeBehind(pos, dir, dist)
      if spot and groundOk(spot) and putBehind(id, spot, sdir, { speed = speed or 0 }) then
        M.put.awayBehind = (M.put.awayBehind or 0) + 1
        return true
      end
    end
  end
  local gt = rawget(_G, 'gameplay_traffic')
  if gt and gt.forceTeleport and pos and dir and pcall(gt.forceTeleport, id, pos, dir, C.WRECK_AWAY_M[1], C.WRECK_AWAY_M[2]) then
    M.put.awayAhead = (M.put.awayAhead or 0) + 1
    return true
  end
  return false
end
M.sendAway = sendAway

-- a queue or a standing car ahead in its lane: the speed to have now to come up to it gently (nil: none)
local function queueAhead(id, c, all)
  if not c or not c.pos or not c.dir or (c.speed or 0) < 3 then return nil end
  local look = math.min(C.QAHEAD_MAX_M, math.max(C.QAHEAD_MIN_M, c.speed * C.QAHEAD_S))
  local right = vec3(c.dir.y, -c.dir.x, 0)
  local best
  for oid, o in pairs(all) do
    -- (2026-11-13, the twin: a wreck is no queue - going round it is the avoiding's business, which has its own speed; slowed to a crawl
    -- for it here, the cars came to grief at blocks more often, 1.35 against 0.93 per run)
    local ost = cars[oid]
    if oid ~= id and o.pos and not virt.parked[oid] and not (ost and ost.wreckAt) then
      local rel = relOf(o.pos, c.pos)
      local along = rel:dot(c.dir)
      if along > 2 and along < look and math.abs(rel:dot(right)) < C.QAHEAD_LAT_M then
        local sp = o.speed or 0
        local its = (o.dir and o.dir:dot(c.dir) or 1) * sp
        -- (going its way, or standing whichever way it points; not one coming the other way)
        local st0 = cars[id]
        local facing = o.dir and o.dir:dot(c.dir) < -0.5 and st0 and st0.narrowAt and now() - st0.narrowAt < 1.5
        if (its > -1 or sp < 1.5) and its < c.speed - C.QAHEAD_DV and not facing then
          local gap = along - 0.5 * (lengthOf(oid) + lengthOf(id)) - C.QAHEAD_S0
          local v = math.sqrt(math.max(0, its) ^ 2 + 2 * C.QAHEAD_DECEL * math.max(0, gap))
          if not best or v < best then best = v end
        end
      end
    end
  end
  return best
end
M._queueAhead = queueAhead

local function obstacleAhead(id, c, all, look)
  look = look or C.LOOK_M
  local best, bd
  local right = vec3(c.dir.y, -c.dir.x, 0)
  for oid, o in pairs(all) do
    -- (2026-11-11, fourth Verkehrstest: a car crawling at an angle on the edge of the lane after a knock was nobody's car in front - it
    -- did not point the same way. Standing, it is in the way whichever way it points, and a little wider)
    local standing = o.speed and o.speed < C.STANDING_MS
    if oid ~= id and o.dir and (o.dir:dot(c.dir) > 0.8 or standing) then
      local rel = relOf(o.pos, c.pos)
      local along = rel:dot(c.dir)
      if along > 2 and along < look and math.abs(rel:dot(right)) < C.LANE_W + (standing and C.STANDING_WIDER_M or 0) and (not bd or along < bd) then
        best, bd = oid, along
      end
    end
  end
  return best, bd
end

-- the nearest oncoming car that would meet a pass of tp s at passMs, or nil when the way is clear. Moving ones
-- coming this way only; a standing one only when it stands on the oncoming lane itself (cars parked at the kerb on
-- the other side are not in the way – they made every pass abort, in game 2026-11-03)
local function oncomingBlock(id, c, all, passMs, tp, risk)
  local right = vec3(c.dir.y, -c.dir.x, 0)
  for oid, o in pairs(all) do
    local rel = relOf(o.pos, c.pos)
    local along = rel:dot(c.dir)
    local lat = rel:dot(right)                      -- (negative: left of the car)
    if oid ~= id and along > 0 and along < C.SCAN_M then
      local moving = o.speed > 2 and o.dir and o.dir:dot(c.dir) < -0.5 and math.abs(lat) < C.ONCOMING_LAT_M
      local standing = o.speed <= 2 and along < 300 and lat < -1.2 and lat > -4.6   -- (on the lane the pass uses)
      if standing then return along end
      if moving then
        local sp = o.speed
        -- the closing distance during the pass is a must; the driver's risk only adds a small margin on top
        -- (bold ~15 m, careful ~95 m). risk == nil: no margin at all (the abort check while beside the obstacle –
        -- with the careful margin there every oncoming car within ~400 m stopped the pass, beamng.log 2026-11-03)
        local margin = risk and (90 + math.max(0, risk - 0.5) * 160) or 0
        if along < (passMs + sp) * tp + margin then return along end
      end
    end
  end
  return nil
end

-- the vehicle the car is about to meet (oncoming, 12..MEET_M ahead) and the room between their lines
local function meeting(id, c, all)
  local right = vec3(c.dir.y, -c.dir.x, 0)
  local best, bd, blat
  for oid, o in pairs(all) do
    if oid ~= id and o.dir and o.dir:dot(c.dir) < -0.6 and o.speed > 1 then
      local rel = relOf(o.pos, c.pos)
      local along = rel:dot(c.dir)
      local lat = math.abs(rel:dot(right))
      -- (2026-11-09: the stock AI starts braking long before 70 m when both are fast: looked at as far ahead as they will need a few seconds for. A line of sight along a bend is wider too.)
      local reach = math.max(C.MEET_M, math.min(280, (c.speed + o.speed) * 7))
      if along > 6 and along < reach and lat < 6 + along * 0.02 and (not bd or along < bd) then best, bd, blat = oid, along, lat end
    end
  end
  return best, bd, blat
end

-- the moves ---------------------------------------------------------------------------------------------------

local function driverCall(id, st, code)
  if st.own then send(id, 'if fernfahrer_driver then fernfahrer_driver.' .. code .. ' end') end
end

-- sideways by disp metres (to the right) over so many metres: to whichever is driving
local function shiftCmd(st, over, disp)
  if st.own then return string.format('if fernfahrer_driver then fernfahrer_driver.shift(%.2f, %.1f) end', disp, over) end
  return string.format('ai.laneChange(nil, %.1f, %.2f)', over, disp)
end

local function capSpeed(id, st, ms)
  ms = math.max(1.0, ms)
  if st.capMs and math.abs(st.capMs - ms) < 0.6 then return end
  st.capMs = ms
  send(id, string.format('ai.setSpeedMode("limit") ai.setSpeed(%.2f)', ms))
  driverCall(id, st, string.format('setCap(%.2f)', ms))
end

local function freeSpeed(id, st)
  if not st.capMs then return end
  st.capMs = nil
  send(id, 'ai.setSpeedMode("legal")')
  driverCall(id, st, 'setCap(0)')
end

-- move the car's plan sideways so that it ends up `target` m right of the centre line (negative: left of it)
local function steerTo(id, st, c, target, over)
  local lat, half = lateralOf(c.pos, c.dir)
  if not lat then return end
  -- (2026-11-09: off its road by more than a lane: the nearest graph edge is another road, the other carriageway – the "error"
  -- was then 15 m and the car steered off the road)
  if math.abs(lat) > (half or 3) + 1.5 then return end
  local err = math.max(-4, math.min(4, target - lat))
  if math.abs(err) < 0.3 then return end
  send(id, shiftCmd(st, over or math.max(18, c.speed * 2.2), err))
end

local function startPass(id, st, c, passMs)
  local _, half = lateralOf(c.pos, c.dir)
  st.phase, st.t0, st.passMs, st.steerT, st.pushed = 'pass', now(), passMs, now(), nil
  -- back in only with a gap a driver leaves: about a second at the pass speed (the speeder: right in front)
  st.mergeM = st.rash and C.MERGE_M or math.max(C.MERGE_M, passMs * 1.1 + 4)
  st.half = half or 3.2
  st.capMs = passMs
  send(id, string.format('electrics.set_left_signal(true) ai.driveInLane("off") ai.setAggression(%.2f) ai.setSpeedMode("limit") ai.setSpeed(%.2f)',
    math.min(0.7, st.aggr + 0.15), passMs))
  driverCall(id, st, string.format('setPassing(true) fernfahrer_driver.setCap(%.2f)', passMs))
  steerTo(id, st, c, -st.half * 0.5, math.max(22, c.speed * 2.5))
end

local function endPass(id, st, c, aborted, obstacleMs)
  st.phase = nil
  st.cool = now() + (aborted and C.COOLDOWN_S * 0.7 or C.COOLDOWN_S)
  st.behindT = 0
  send(id, string.format('ai.driveInLane("on") ai.setAggression(%.2f) electrics.set_left_signal(false)', st.aggr))
  driverCall(id, st, 'setPassing(false)')
  if c then steerTo(id, st, c, (st.half or 3.2) * 0.5, math.max(20, c.speed * 2)) end
  -- (2026-11-09: back in as anybody does it: the right indicator for a moment)
  send(id, 'electrics.set_right_signal(true)')
  st.blinkOffAt = now() + 2.2
  st.capMs = nil
  -- (aborted: just below the obstacle's speed, no full stop – the following logic then keeps the gap)
  if aborted then capSpeed(id, st, (obstacleMs or 8) * 0.85) else send(id, 'ai.setSpeedMode("legal")'); driverCall(id, st, 'setCap(0)') end
  dlog('%s pass car %d (%.0f s)', aborted and 'ABORT' or 'done', id, now() - (st.t0 or now()))
end

-- several lanes ---------------------------------------------------------------------------------------------------

-- the speed this driver wants on a road with this limit (m/s). Lorries by the rules the player's truck goes by (career.lua L.ruleLimit):
-- posted 110 or more 80, posted over 50 up to 100 60, in town the sign
local function paceOf(st, limitMs, len)
  local p = st.pace
  if len > C.TRUCK_LEN_M then
    local kmh = math.floor(limitMs * 3.6 + 0.5)        -- (rounded: 50 is 50, not 50.5 - a lorry in town went 52)
    local rule = kmh >= 110 and 80 or (kmh > 50 and math.min(kmh, 60) or kmh)
    return rule / 3.6 * math.max(0.97, math.min(1.03, p))
  end
  if limitMs * 3.6 <= C.TOWN_KMH then p = math.min(p, 1.03) end
  return math.min(limitMs * p, C.PACE_MAX_MS)
end

-- ... and with a lower limit coming up: already slowing for it, gently. (The stock "legal" speed mode reads the limits along its plan,
-- a set speed does not: into town at 100, then the brakes.)
-- (2026-11-14, Verkehrstest 13-13: "auf Autobahnauffahrten ist oft 30 oder 40, und sie fahren lange Stücke nur 30") on an on-ramp - one-way,
-- slower, into a one-way fast road ahead - the speed to be at the fast road's pace by the merge (nil: no ramp here)
local function rampBoost(st, c, len)
  local centre, heading, _, back, fwd, nodes, link0 = roadAt(c.pos, c.dir)
  if not centre or not heading or type(link0) ~= 'table' or not link0.oneWay then return nil end
  local lim0 = tonumber(link0.speedLimit) or 0
  if lim0 >= C.RAMP_FAST_MS then return nil end
  local best
  walk(nodes, back, fwd, heading, nodes[fwd].pos:distance(c.pos), C.RAMP_LOOK_M, function(n, travelled, h, nextNode)
    local link = nextNode and linksOf(nodes, n)[nextNode]
    if type(link) ~= 'table' then return true end
    if not link.oneWay then return true end                     -- (a two-way road: no ramp)
    local lim = tonumber(link.speedLimit) or 0
    if lim >= C.RAMP_FAST_MS and lim > lim0 + 4 then
      local v = paceOf(st, lim, len)
      best = math.sqrt(math.max(0, v * v - 2 * C.RAMP_ACC * travelled))
      return true
    end
    return false
  end)
  return best and best > lim0 and best or nil
end
M._rampBoost = rampBoost

local function paceAhead(st, c, wanted, len)
  local centre, heading, _, back, fwd, nodes = roadAt(c.pos, c.dir)
  if not centre or not heading then return wanted end
  local best = wanted
  walk(nodes, back, fwd, heading, nodes[fwd].pos:distance(c.pos), math.max(80, c.speed * 6), function(n, travelled, h, nextNode)
    local link = nextNode and (nodes[n].links[nextNode] or nodes[nextNode].links[n])
    local lim = type(link) == 'table' and tonumber(link.speedLimit) or nil
    -- (2026-11-10: at a fork - an exit - the fastest of the ways on that go about straight: the slip road's 60 is not the motorway's)
    if lim and h then
      local deg = 0
      for _ in pairs(linksOf(nodes, n)) do deg = deg + 1 end
      if deg > 2 then
        for m, l2 in pairs(linksOf(nodes, n)) do
          if m ~= nextNode and nodes[m] and type(l2) == 'table' and not (l2.oneWay and l2.inNode ~= n) then
            local dd = flat(nodes[m].pos - nodes[n].pos)
            local lm = tonumber(l2.speedLimit)
            if dd and lm and dd:dot(h) > 0.9 and lm > lim then lim = lm end
          end
        end
      end
    end
    if lim and lim > 3 then
      local v = paceOf(st, lim, len)
      best = math.min(best, math.sqrt(v * v + 2 * 1.6 * math.max(0, travelled)))
    end
    return false
  end)
  return best
end

-- the lanes of the car's own direction, when there are at least two: { n, idx (1: the left one), w, left (their left edge), lat }
local function lanesHere(pos, dir)
  local centre, d, half, back, _, _, link = roadAt(pos, dir)
  if not centre or not d or not half or type(link) ~= 'table' or type(link.lanes) ~= 'string' then return nil end
  if d:dot(dir) < 0.9 then return nil end
  local _, plus = link.lanes:gsub('%+', '')
  local _, minus = link.lanes:gsub('%-', '')
  local total = plus + minus
  local mine, against = plus, 0
  if not link.oneWay then
    local along = link.inNode == back
    mine, against = along and plus or minus, along and minus or plus
  end
  if mine < 2 or total < 2 then return nil end
  local w = 2 * half / total
  local left = -half + against * w
  local lat = (pos - centre):dot(vec3(d.y, -d.x, 0))
  if lat < left - w * 0.5 or lat > half + 1.5 then return nil end   -- (the nearest edge is another road, or it is over the middle)
  return { n = mine, idx = math.max(1, math.min(mine, math.floor((lat - left) / w) + 1)), w = w, left = left, lat = lat }
end

-- room in the lane beside the car (side: -1 left, 1 right)? Time gaps, as a driver judges them: whoever comes up from behind counts
-- by how fast it comes, whoever is ahead by how fast the car closes on it. extra: more clear road wanted ahead
local function laneFree(id, c, li, side, all, extra)
  local centre = li.left + (li.idx + side - 0.5) * li.w
  local right = vec3(c.dir.y, -c.dir.x, 0)
  local me = lengthOf(id) * 0.5
  for oid, o in pairs(all) do
    local standing = o.speed and o.speed < C.STANDING_MS
    if oid ~= id and o.dir and (o.dir:dot(c.dir) > 0.6 or standing) then
      local rel = relOf(o.pos, c.pos)
      local along = rel:dot(c.dir)
      local side2 = rel:dot(right)
      if math.abs(along) < 260 and math.abs(side2) < 14 then
        local lo = lateralOf(o.pos, c.dir) or (li.lat + side2)
        -- (a wreck in the next lane: 100 km/h into it after a lane change, fourth Verkehrstest)
        if math.abs(lo - centre) < li.w * 0.62 + (standing and C.STANDING_WIDER_M or 0) then
          local room = math.abs(along) - me - lengthOf(oid) * 0.5
          local need
          if along >= 0 then need = 8 + c.speed * 0.35 + math.max(0, c.speed - o.speed) * 3 + (extra or 0)
          else need = 7 + c.speed * 0.2 + math.max(0, o.speed - c.speed) * 3.5 end
          if room < need then return false end
        end
      end
    end
  end
  -- (a place another car has just booked is taken, wherever that car still is)
  local clock = now()
  for cid, cst in pairs(cars) do
    local o = all[cid]
    if cid ~= id and o and cst.laneUntil and cst.laneUntil > clock and math.abs(cst.laneTo - centre) < li.w * 0.62 then
      if math.abs((o.pos - c.pos):dot(c.dir)) < 15 + c.speed * 0.5 then return false end
    end
  end
  return true
end

-- (2026-11-11, the digital twin: three lanes became one and the cars in the lanes that ended drove into the ones in the lane that went on.
-- Where does the road ahead have fewer lanes its way? nil when it has not, or a fork comes first (there the right-hand lane may be an exit))
local function lanesAhead(c, li)
  local centre, heading, _, back, fwd, nodes = roadAt(c.pos, c.dir)
  if not centre or not heading or not nodes or not nodes[fwd] then return nil end
  local found, at
  walk(nodes, back, fwd, heading, nodes[fwd].pos:distance(c.pos), math.max(C.LANE_END_LOOK_M, c.speed * C.LANE_END_LOOK_S), function(n, travelled, h, nextNode)
    local deg = 0
    for _ in pairs(linksOf(nodes, n)) do deg = deg + 1 end
    if deg > 2 then return true end
    local link = nextNode and (nodes[n].links[nextNode] or nodes[nextNode].links[n])
    if type(link) ~= 'table' or type(link.lanes) ~= 'string' then return false end
    local _, plus = link.lanes:gsub('%+', '')
    local _, minus = link.lanes:gsub('%-', '')
    local mine = link.oneWay and plus or ((link.inNode == n) and plus or minus)
    if mine >= 1 and mine < li.n then found, at = mine, travelled; return true end
    return false
  end)
  return found, at
end
M.lanesAhead = lanesAhead

local laneTick = -1                   -- (one lane change per look over all cars: the traffic does not all jump at once)
M.laneStats = { multi = 0, left = 0, right = 0, room = 0 }

local function changeLane(id, st, c, li, side, t, why)
  if side > 0 and st.noRightUntil and t < st.noRightUntil then return end
  if side < 0 and st.noLeftUntil and t < st.noLeftUntil then return end
  -- (never with a bend coming: the car would still be between the lanes in it)
  if roadAhead(c.pos, c.dir, math.max(60, c.speed * 4)) > C.LANE_MAX_BEND then return end
  laneTick, st.laneT, st.laneWait, st.rightT = t, t, 0, 0
  local target = li.left + (li.idx + side - 0.5) * li.w
  st.laneTo, st.laneUntil = target, t + 5
  send(id, string.format('electrics.set_%s_signal(true) ', side < 0 and 'left' or 'right') .. shiftCmd(st, math.max(45, c.speed * 3), target - li.lat))
  st.blinkOffAt = t + 3.4
  local s = M.laneStats
  if why == 'room' then s.room = s.room + 1 elseif side < 0 then s.left = s.left + 1 else s.right = s.right + 1 end
  dlog('car %d lane %d/%d -> %s (%s, %.0f km/h)', id, li.idx, li.n, side < 0 and 'left' or 'right', why, c.speed * 3.6)
end

-- what a driver does on a road with several lanes, every look. o, gapM: the one ahead in its lane; wanted: its own speed (m/s)
local function laneBrain(id, st, c, all, t, stepS, li, o, gapM, wanted, ownLimitKmh, p, playerLone)
  M.laneStats.multi = M.laneStats.multi + 1
  -- (2026-11-11) the lane shut ahead (roadworks, a wreck): over to the free side in good time, asking for a gap; else it stops before it
  if st.blockEnd then
    local side = st.blockSide or -1
    st.laneEnd = st.blockEnd
    if laneTick ~= t and t - (st.laneT or -1e9) > 3 and laneFree(id, c, li, side, all) then
      M.avoid.lanes = (M.avoid.lanes or 0) + 1
      return changeLane(id, st, c, li, side, t, 'shut ahead')
    end
    st.wantGapT = t
    return
  end
  -- its lane ends ahead: over in good time, asking for a gap when the lane beside it is full (those there let it in, yieldSpeed: a zip)
  do
    local nA, dA = nil, nil
    if li.idx > 1 then nA, dA = lanesAhead(c, li) end
    if nA and li.idx > nA then
      st.laneEnd = dA
      if laneTick ~= t and t - (st.laneT or -1e9) > 3 and laneFree(id, c, li, -1, all) then
        M.laneStats.ends = (M.laneStats.ends or 0) + 1
        return changeLane(id, st, c, li, -1, t, 'lane ends')
      end
      st.wantGapT = t
      return
    end
    st.laneEnd = nil
  end
  if laneTick == t or t - (st.laneT or -1e9) < C.LANE_COOL_S then return end
  -- the truck joining from a slip road beside the right-hand lane: room for it
  if p and p.dir and playerLone and li.idx == li.n and p.dir:dot(c.dir) > 0.85 then
    local rel = p.pos - c.pos
    local along, beside = rel:dot(c.dir), rel:dot(vec3(c.dir.y, -c.dir.x, 0))
    if along > -20 and along < 90 and beside > 3 and beside < 11 and laneFree(id, c, li, -1, all) then
      return changeLane(id, st, c, li, -1, t, 'room')
    end
  end
  local held = o and wanted and o.speed < wanted - C.LANE_GAIN_MS and gapM < math.max(40, c.speed * 5)
  -- (a lorry goes left only round something standing)
  if held and lengthOf(id) > C.TRUCK_LEN_M and o.speed >= C.MOVING_MS then held = false end
  if held and li.idx > 1 then
    st.laneWait = (st.laneWait or 0) + stepS
    if st.laneWait >= st.wait * 0.35 then
      if laneFree(id, c, li, -1, all) then
        local _, junctionAt = roadAhead(c.pos, c.dir, C.LANE_JUNCTION_M + 30)
        if not (ownLimitKmh <= C.TOWN_KMH + 10 and junctionAt and junctionAt < C.LANE_JUNCTION_M) then
          return changeLane(id, st, c, li, -1, t, 'overtake')
        end
      else
        st.wantGapT = t             -- (blocked at the side: it asks)
      end
    end
  else
    st.laneWait = 0
  end
  -- keeps right: once the lane there is free for a good stretch (nobody it would have to pull out for again straight away)
  if li.idx < li.n and not held and laneFree(id, c, li, 1, all, c.speed * 3 + 25) then
    st.rightT = (st.rightT or 0) + stepS
    if st.rightT >= math.max(4, st.wait) then return changeLane(id, st, c, li, 1, t, 'keep right') end
  else
    st.rightT = 0
  end
end

-- talking to each other, staying on the road --------------------------------------------------------------------------

-- the speed to let in one that asks for a gap in this car's lane (or the truck indicating left there), nil when nobody does
local function yieldSpeed(id, st, c, all, t, p)
  if st.wait < 2.5 then return nil end            -- (the sporty ones do not)
  local right = vec3(c.dir.y, -c.dir.x, 0)
  local function asks(o)
    if not o or not o.dir or o.dir:dot(c.dir) < 0.8 then return false end
    local rel = relOf(o.pos, c.pos)
    local along, side = rel:dot(c.dir), rel:dot(right)
    return along > -5 and along < C.YIELD_M and side > 2.2 and side < 5.5
  end
  for cid, cst in pairs(cars) do
    if cid ~= id and cst.wantGapT and t - cst.wantGapT < 1.1 and asks(all[cid]) then
      return math.max(8, math.min(all[cid].speed - 1.5, (st.yieldRef or c.speed) - 2.5))
    end
  end
  if p and p.signal < 0 and asks(p) then return math.max(8, math.min(p.speed - 1.5, (st.yieldRef or c.speed) - 2.5)) end
  return nil
end

-- is someone overtaking towards this car, on its side of the road?
local function passerAhead(id, c, passers)
  local right = vec3(c.dir.y, -c.dir.x, 0)
  for _, x in ipairs(passers) do
    if x.id ~= id and x.o.dir and x.o.dir:dot(c.dir) < -0.6 then
      local rel = relOf(x.o.pos, c.pos)
      local along = rel:dot(c.dir)
      if along > 20 and along < C.PASSER_M and math.abs(rel:dot(right)) < 4.5 then return true end
    end
  end
  return false
end

M.safety = { edge = 0, rescued = 0 }
-- wheels over the edge of the real asphalt: back in early. Stuck off the road: back on it, out of the player's sight. True: it was moved
local function keepOnRoad(id, st, c, t, stepS, p, len)
  local centre, d, half, back, fwd, nodes = roadAt(c.pos, c.dir)
  if not centre or not d then return false end
  local real = priority.realHalf(back, fwd) or half
  local lat = (c.pos - centre):dot(vec3(d.y, -d.x, 0))
  local atJunction = false
  for _, n in ipairs({ back, fwd }) do
    local degree = 0
    for _ in pairs(linksOf(nodes, n)) do degree = degree + 1 end
    if degree > 2 and nodes[n].pos:distance(c.pos) <= C.DRIFT_JUNCTION_M + 8 then atJunction = true end
  end
  local along = math.abs(d:dot(c.dir))
  -- (2026-11-10: a car more than a little beside this road is on another one running along it, and a correction that has not helped three
  -- times is not going to. It was pushing cars about, every 1.5 s, for 40 s on end)
  if t - (st.edgeFix or -1e9) > 12 then st.edgeN = 0 end
  if not st.phase and not st.avoid and real and real >= 2.4 and (st.edgeN or 0) < 3 and along >= C.DRIFT_ALIGN and not atJunction and math.abs(lat) <= real + 0.6 and c.speed > 6 then
    local over = math.abs(lat) + (len > C.TRUCK_LEN_M and 1.25 or 0.95) - real
    -- (2026-11-10: only on a straight piece. In a town's bends the line between two nodes cuts the corner, and a car in its lane looked
    -- half off the road: 120 corrections in 20 minutes, nearly all of them for nothing)
    if over > C.EDGE_MARGIN and roadAhead(c.pos, c.dir, 40) < 10 then
      st.edgeT = (st.edgeT or 0) + stepS
      if st.edgeT >= C.EDGE_HOLD_S and t - (st.edgeFix or -1e9) >= C.EDGE_EVERY_S then
        st.edgeFix, st.edgeSlow, st.edgeN = t, t + 3, (st.edgeN or 0) + 1
        M.safety.edge = M.safety.edge + 1
        send(id, 'ai.driveInLane("on") ' .. shiftCmd(st, math.max(14, c.speed * 1.3), (lat > 0 and -1 or 1) * math.min(1.5, over + 0.25)))
        dlog('car %d at the edge of the road: %.2f m over, back in (%.0f km/h)', id, over, c.speed * 3.6)
      end
    else
      st.edgeT = 0
    end
  else
    st.edgeT = 0
  end
  st.stillT = c.speed < 1.2 and (st.stillT or 0) + stepS or 0
  local off = not atJunction and ((real and math.abs(lat) > real + 1) or along < 0.5)
  if st.stillT >= C.RESCUE_S and off and p and p.dir then
    local rel = c.pos - p.pos
    if rel:length() > 220 or rel:dot(p.dir) < -40 then
      local spot, sdir = placeBehind(p.pos, p.dir, rnd(C.BEHIND_M[1], C.BEHIND_M[2]))
      local gt = rawget(_G, 'gameplay_traffic')
      if putBehind(id, spot, sdir, p) then
        st.stillT, st.lastPos, st.capMs, st.limMs, st.limC = 0, spot, nil, nil, nil
        M.safety.rescued = M.safety.rescued + 1
        dlog('car %d was stuck off the road: back on it, behind the player', id)
        return true
      end
    end
  end
  return false
end

-- (2026-11-10) the game puts its cars ahead of the player and nobody ever came up from behind: when there are too few behind it, one from
-- far away, out of sight, is put on the road behind the player, going its way
local behindT = 0
local function fillBehind(t, p, pid, all, list)
  if t - behindT < C.BEHIND_EVERY_S or not p or not p.dir or p.speed < 4 or flow.active() then return end
  behindT = t
  local right = vec3(p.dir.y, -p.dir.x, 0)
  local count = 0
  for oid, o in pairs(all) do
    if oid ~= pid and cars[oid] and o.dir and o.dir:dot(p.dir) > 0.5 then
      local rel = o.pos - p.pos
      local along = rel:dot(p.dir)
      if along < -10 and along > -C.BEHIND_SCAN_M and math.abs(rel:dot(right)) < 25 then count = count + 1 end
    end
  end
  if count >= C.BEHIND_WANT then return end
  local donor, far = nil, C.DONOR_M
  for _, id in pairs(list) do
    local mo = map.objects[id]
    local st = cars[id]
    if mo and mo.pos and not (st and st.phase) and not virt.parked[id] then   -- (2026-11-13: a parked one is invisible and asleep)
      local d = p.pos:distance(vec3(mo.pos))
      if d > far then donor, far = id, d end
    end
  end
  if not donor then return end
  local spot, sdir = placeBehind(p.pos, p.dir, rnd(C.BEHIND_M[1], C.BEHIND_M[2]))
  if not spot then return end
  for _, o in pairs(all) do if o.pos:distance(spot) < 35 then return end end
  local gt = rawget(_G, 'gameplay_traffic')
  if putBehind(donor, spot, sdir, p) then
    cars[donor] = nil
    dlog('car %d from %.0f m away -> behind the player (%d there)', donor, far, count)
  end
end

-- gaps ------------------------------------------------------------------------------------------------------------

local function updateGap(t, pv, all, queued)
  -- (2026-11-09: on a carriageway of its own nobody needs a gap in the other direction: Earth 1.9 fills that one on purpose)
  local p = all[pv:getID()]
  if t >= gap.untilT and p and p.dir and oneWayRoad(p.pos, p.dir) then return end
  if not gap.nextAt then gap.nextAt = t + rnd(C.GAP_EVERY_S[1], C.GAP_EVERY_S[2]) * 0.4 end
  -- (2026-11-09: the oncoming cars used to be held at 7 km/h as well, for up to 40 s out of every 80. The player reached them within
  -- seconds, and everything behind them braked: a queue crawling towards the truck for no reason. Only moved now, out of sight.)
  if t < gap.untilT and p and p.dir and gap.moved < C.GAP_MOVE then
    local right = vec3(p.dir.y, -p.dir.x, 0)
    for oid, o in pairs(all) do
      if gap.moved >= C.GAP_MOVE then break end
      if cars[oid] and o.dir and o.dir:dot(p.dir) < -0.5 and oid ~= pv:getID() then
        local rel = o.pos - p.pos
        local along = rel:dot(p.dir)
        if along > C.GAP_MOVE_FROM_M and math.abs(rel:dot(right)) < 20 then
          -- out of sight far ahead: to the road behind the player, driving its way
          local spot, sdir = placeBehind(p.pos, p.dir, rnd(C.BEHIND_M[1], C.BEHIND_M[2]))
          local gt = rawget(_G, 'gameplay_traffic')
          -- (the traffic system's own respawn: its bookkeeping follows, the car starts afresh)
          if putBehind(oid, spot, sdir, p) then
            gap.moved = gap.moved + 1
            if cars[oid].phase then send(oid, 'ai.driveInLane("on") electrics.set_left_signal(false)') end
            cars[oid] = nil
            dlog('gap: car %d moved %.0f m ahead -> behind the player', oid, along)
          end
        end
      end
    end
  end
  if t >= gap.untilT and t - (gap.respawnResetT or 0) > 60 then gap.respawnMoved, gap.respawnResetT = 0, t end
  if t >= gap.untilT and t > gap.nextAt and queued then
    gap.untilT = t + rnd(C.GAP_LEN_S[1], C.GAP_LEN_S[2])
    gap.nextAt = gap.untilT + rnd(C.GAP_EVERY_S[1], C.GAP_EVERY_S[2])
    gap.moved, gap.respawnMoved = 0, 0
    dlog('gap: for %.0f s', gap.untilT - t)
  end
end

-- the last resort (2026-11-08): a traffic car about to run into the back of the truck. The AI looks at the road; the
-- truck stopping hard in front of it is often seen too late. Brakes applied straight in the car (as the cruise control
-- does), for as long as it takes.
local guardT = 0
local braking = {}
local guardSeen = {}          -- id -> { pos, t }: a jump between two looks is a car put down
local matched = {}
-- (2026-11-14: a car standing is held by the hand brake, not the pedal - BeamNG's automatic gearbox takes the brake pedal of a standing car
-- for the way into reverse, and once in reverse the brake pedal is its throttle (vehicleController.lua: isArcadeSwitched). Held at a block
-- or in a queue with the pedal, cars crept off backwards "out of nowhere")
local pbHeld = {}
local function letGo(id)
  braking[id] = nil
  if pbHeld[id] then
    pbHeld[id] = nil
    send(id, 'electrics.values.throttleOverride = nil electrics.values.brakeOverride = nil input.event("parkingbrake", 0, 1)')
  else
    send(id, 'electrics.values.throttleOverride = nil electrics.values.brakeOverride = nil')
  end
end
M._pbHeld = pbHeld
local function guard(ctx, t)
  if t - guardT < C.GUARD_S then return end
  guardT = t
  local pv = ctx.enabled() and ctx.playerVeh()
  local objs = map and map.objects
  local P = pv and objs and objs[pv:getID()]
  if not P or not P.pos then
    for id in pairs(braking) do letGo(id) end
    return
  end
  local pid, tid = pv:getID(), ctx.trailerId()
  local T = objs[tid or -1]
  local ppos = vec3(P.pos)
  -- (2026-11-11, second Verkehrstest: 35 crashes, nearly all of them a car at 50-100 km/h into one standing or crawling in its lane – a car
  -- turning off, one just put down, the wreck of the crash before. The look ahead is for every vehicle now, not only the truck and its trailer)
  local targets = { { P, pid } }
  if T and T.pos and T.vel then targets[#targets + 1] = { T, tid } end
  for oid in pairs(cars) do
    local q = objs[oid]
    if q and q.pos and q.vel and oid ~= pid and oid ~= tid and ppos:squaredDistance(vec3(q.pos)) < C.GUARD_ALL_M * C.GUARD_ALL_M then targets[#targets + 1] = { q, oid } end
  end
  for id, st in pairs(cars) do
    local o = objs[id]
    if virt.parked[id] then goto guardNext end
    local want = 0
    local forStanding = false
    local fresh = false
    local fastFall = false
    if o and o.pos and o.vel and o.vel.z and o.vel.z < -C.FALL_FAST_MS then
      local ff, z = st.ffall, o.pos.z
      if not ff or t - ff.t > 2 then st.ffall = { t = t, z = z }
      elseif t - ff.t >= C.FALL_CONFIRM_S then
        if ff.z - z > C.FALL_DROP_M then fastFall = true else st.ffall = { t = t, z = z } end
      end
    else
      st.ffall = nil
    end
    if fastFall then
      st.ffall = nil
      local pdv = P.dirVec and flat(vec3(P.dirVec)) or flat(vec3(P.vel or vec3(1, 0, 0))) or vec3(1, 0, 0)
      if sendAway(id, ppos, pdv, P.vel and vec3(P.vel):length() or 0) then
        M.put.fell = (M.put.fell or 0) + 1
        dlog('car %d: falling (%.0f m/s down) - taken away', id, -o.vel.z)
        st.wreckAt, st.dmg, st.badCar, st.crashTs, st.blockPlT, st.fallN, st.lastPos = nil, nil, nil, nil, nil, nil, nil
        guardSeen[id] = nil
        goto guardNext
      end
    end
    if o and o.pos then
      local gs = guardSeen[id]
      local here = vec3(o.pos)
      if gs and here:distance(gs.pos) > 20 + vec3(o.vel or vec3(0, 0, 0)):length() * (t - gs.t) * 1.5 then st.putAt, st.jumpAt = t, t end
      -- (seen for the first time already this close to the truck: it has just been put down too - BeamNG brings them from far away)
      if not gs and here:distance(ppos) < C.GUARD_ALL_M - 60 then st.putAt = t end
      if gs then gs.pos, gs.t = here, t else guardSeen[id] = { pos = here, t = t } end
      fresh = st.putAt and t - st.putAt < C.JUST_PUT_S
      -- (2026-11-12) put down into another car, or into a wreck's zone: away at once, before anything moves
      if fresh and not st.overlapDone and here:distance(ppos) > 25 then
        local bad = nil
        for oid, q in pairs(objs) do
          if oid ~= id and q.pos and vec3(q.pos):distance(here) < C.OVERLAP_M then bad = 'another car'; break end
        end
        if not bad and not groundOk(here) then bad = 'no ground' end
        if not bad and M.zonesNow and not flow.member[id] then
          for _, z in ipairs(M.zonesNow) do
            if (z.kind == 'wreck' or z.kind == 'accident') and z.pos and z.dir then
              local rel = here - z.pos
              local along = rel:dot(z.dir)
              if along > -10 and along < (z.len or 40) + 5 and math.abs(rel:dot(vec3(z.dir.y, -z.dir.x, 0))) < 8 then bad = z.kind; break end
            end
          end
        end
        if bad then
          st.overlapDone = true
          local pdv = P.dirVec and flat(vec3(P.dirVec)) or flat(vec3(P.vel or vec3(1, 0, 0))) or vec3(1, 0, 0)
          if sendAway(id, ppos, pdv, P.vel and vec3(P.vel):length() or 0) then
            if bad == 'no ground' then M.put.noGround = (M.put.noGround or 0) + 1 else M.put.overlap = (M.put.overlap or 0) + 1 end
            dlog('car %d: put down in %s - moved away', id, bad)
            guardSeen[id] = nil
            st.putAt = t
            goto guardNext
          end
        end
      elseif not fresh then
        st.overlapDone = nil
      end
      -- (2026-11-13, Verkehrstest 13-42: three cars moved into a jam, standing there 2 s later and 7 m on, read at 93 to 100 km/h in the
      -- look right after - the speed the game gives in the frames after a teleport is not the car's. "Given its speed", "emergency brake
      -- (100 km/h)" and the lab's hard brakes were answers to that. Its speed is looked at once it has settled)
      if st.jumpAt and t - st.jumpAt < C.PUT_SETTLE_S then goto guardNext end
      -- (2026-11-14, Verkehrstest 23-53: "emergency brake (9377 km/h)" for a car just made real out of a placeholder - woken from the pool,
      -- its last place long ago: no jump to see, and the speed of the first frames is nonsense. Settled first, as after any jump)
      if virt.just and virt.just[id] and t - virt.just[id] < C.PUT_SETTLE_S + 0.15 then goto guardNext end
      -- (2026-11-14, Verkehrstest 15-35: "made real (0 km/h)" - and half a second later at 34 km/h into the queue in front. A car that slept in
      -- the pool wakes with the speed it fell asleep with; the one push to the placeholder's speed was not always enough. For the first
      -- SPEED_HOLD_S it is pushed to that speed again while it is off by more than SPEED_HOLD_DV)
      do
        local vj, vv = virt.just and virt.just[id], virt.justV and virt.justV[id]
        if vj and vv and t - vj < C.SPEED_HOLD_S and o.vel then
          local sp = vec3(o.vel):length()
          if math.abs(sp - vv) > C.SPEED_HOLD_DV and (st.speedFixN or 0) < 6 then
            st.speedFixN = (st.speedFixN or 0) + 1
            send(id, string.format('thrusters.applyVelocity(obj:getDirectionVector() * %.1f, 0.2)', vv))
            M.put.speedFix = (M.put.speedFix or 0) + 1
          end
        elseif st.speedFixN and not vj then st.speedFixN = nil end
      end
      -- (2026-11-12) just put down at speed before a zone (a wreck, an accident, roadworks, a jam): at the zone's speed straight away
      if fresh and not matched[id] and o.vel and M.zonesNow and here:distance(ppos) > C.MATCH_AWAY_M then
        local vel = vec3(o.vel)
        local sp = vel:length()
        local dir = flat(vel)
        if sp > 8 and dir then
          for _, z in ipairs(M.zonesNow) do
            if z.pos and z.dir and z.limit and dir:dot(z.dir) > 0.5 then
              local rel = here - z.pos
              local along = rel:dot(z.dir)
              local vz = math.max(5, z.limit / 3.6)
              local stop = (sp * sp - vz * vz) / (2 * C.GUARD_DECEL)
              if sp > vz + 2 and math.abs(rel:dot(vec3(z.dir.y, -z.dir.x, 0))) < C.ZONE_MATCH_SIDE_M and along > -stop - 20 and along < (z.len or 60) then
                matched[id] = t
                send(id, string.format('thrusters.applyVelocity(obj:getDirectionVector() * %.1f, 0.25)', vz))
                M.put.zoneMatched = (M.put.zoneMatched or 0) + 1
                dlog('car %d: just put down %.0f m before a %s at %.0f km/h - given its speed (%.0f km/h)', id, -along, tostring(z.kind), sp * 3.6, vz * 3.6)
                break
              end
            end
          end
          -- (2026-11-12, Verkehrstest 15-23: of 20 crashes in the last scene most were one put down by BeamNG at 92 to 100 km/h into a jam,
          -- a second later into a car standing in it. A jam is no zone: its speed there, the approach to its end included, from trafficflow)
          if not matched[id] and flow.active() then
            local okJ, jc = pcall(flow.capFor, id, { pos = here, dir = dir }, t)
            if okJ and jc and sp > jc + 2 then
              matched[id] = t
              send(id, string.format('thrusters.applyVelocity(obj:getDirectionVector() * %.1f, 0.25)', jc))
              M.put.jamMatched = (M.put.jamMatched or 0) + 1
              dlog('car %d: just put down in a jam at %.0f km/h - given its speed (%.0f km/h)', id, sp * 3.6, jc * 3.6)
            end
          end
        end
      end
    end
    if o and o.pos and o.vel and id ~= pid and id ~= tid and not st.phase and ppos:squaredDistance(vec3(o.pos)) < C.GUARD_ALL_M * C.GUARD_ALL_M then
      local vel = vec3(o.vel)
      local sp = vel:length()
      local dir = flat(vel)
      if sp > 3 and dir then
        local cpos = vec3(o.pos)
        local right = vec3(dir.y, -dir.x, 0)
        for _, x in ipairs(targets) do
          if x[2] ~= id then
            local rel = relOf(vec3(x[1].pos), cpos)
            local along = rel:dot(dir)
            local tv = vec3(x[1].vel)
            local tStanding = tv:length() < C.STANDING_MS
            local ls = rel:dot(right)
            local lat = math.abs(ls)
            -- (2026-11-11, seventh Verkehrstest: the truck pulling out onto the road at an angle, its middle 5.6 m beside the lane - and one of
            -- ours at 73 km/h into its side. What sticks into the lane is half its length times how much it stands across)
            -- (the twin: for everything at an angle - the cars round a bend - the brake came on three times as often. Only for one standing or
            -- crawling, more than 30 degrees across)
            if tStanding then
              local tdv = (x[1].dirVec and flat(vec3(x[1].dirVec))) or flat(tv)
              local across = tdv and math.abs(tdv:dot(right)) or 0
              if across > 0.5 then lat = math.max(0, lat - 0.5 * lengthOf(x[2]) * across) end
            end
            -- (crossing our way: where it will be by the time we are there)
            local crossing = false
            if C.CROSS and along > 0 and along < C.GUARD_LOOK_M and lat >= C.GUARD_LAT_M then
              local tdir = flat(tv)
              local cross = tv:dot(right)
              if tdir and math.abs(tdir:dot(dir)) < C.CROSS_COS and math.abs(cross) > C.CROSS_MS and ls * cross < 0 then
                local lsF = ls + cross * math.min(C.CROSS_LOOK_S, along / math.max(1, sp))
                -- (the twin: two crossing each other both braked for the other - and stood. The one there clearly first goes; at the same
                -- time the rule of the road: the one coming from the right goes first)
                local tMe, tIt = along / math.max(1, sp), math.abs(ls) / math.abs(cross)
                local yields = tIt < tMe - C.CROSS_FIRST_S or (tIt <= tMe + C.CROSS_FIRST_S and ls > 0)
                if yields and math.abs(lsF) < C.GUARD_LAT_M + 1 and atJunction(vec3(x[1].pos), tdir, C.CROSS_JUNCTION_M) then crossing, lat = true, math.min(lat, math.abs(lsF)) end
              end
            end
            -- (2026-11-14) on a narrow road one standing there facing it is the oncoming car waiting to be passed, slowly: in the way only
            -- right in its line
            if tStanding and st.narrowAt and t - st.narrowAt < 1.5 then
              local tdv2 = (x[1].dirVec and flat(vec3(x[1].dirVec))) or nil
              if tdv2 and tdv2:dot(dir) < -0.5 then lat = lat + (C.GUARD_LAT_M + C.STANDING_WIDER_M - C.NARROW_GUARD_LAT_M) end
            end
            if along > 0 and along < C.GUARD_LOOK_M and lat < C.GUARD_LAT_M + ((tStanding or crossing) and C.STANDING_WIDER_M or 0) then
              local itsWay = vec3(x[1].vel):dot(dir)
              local closing = sp - itsWay
              local room = along - lengthOf(x[2]) * 0.5 - lengthOf(id) * 0.5
              -- (2026-11-09: the truck coming towards the car counted as well. In a bend its straight line ahead runs through the truck:
              -- closing 50 m/s, full brakes on an oncoming car out of nowhere)
              -- (one standing or crossing counts whichever way it faces: the car turning left across from the oncoming side, 2026-11-11)
              if (itsWay > -1 or tStanding or crossing) and closing > 0.5 then
                -- (2026-11-12, Verkehrstest 21-03: 1642 of 1888 emergency brakes below 20 km/h, one car 301 times - the jam a car's length and
                -- 1.6 to 2.8 m apart now, and 2 m kept in hand made every creeping car an emergency. The margin with the speed)
                local margin = math.min(2, C.GUARD_MARGIN_MIN_M + sp * 0.25)
                local need = closing * closing / (2 * math.max(0.3, room - margin))
                -- (just put down, and too fast to stop behind it: the speed of the one in front, at once)
                if fresh and need > C.MATCH_DECEL and not matched[id] and ppos:distance(cpos) > C.MATCH_AWAY_M then
                  matched[id] = t
                  local v = math.max(0, itsWay - 1)
                  send(id, string.format('thrusters.applyVelocity(obj:getDirectionVector() * %.1f, 0.25)', v))
                  M.put.matched = (M.put.matched or 0) + 1
                  dlog('car %d: just put down %.0f m behind %d at %.0f km/h - given its speed (%.0f km/h)', id, room, x[2], sp * 3.6, v * 3.6)
                end
                local avoiding = tStanding and (st.avoid ~= nil or (st.blockNear and t - st.blockNear < C.AVOID_GUARD_GRACE_S))
                local decelThresh = avoiding and (braking[id] and C.GUARD_RELEASE_AVOID or C.GUARD_DECEL_AVOID) or (braking[id] and C.GUARD_RELEASE or C.GUARD_DECEL)
                if need > decelThresh and (crossing or (tStanding and lat < C.GUARD_LAT_M + C.STANDING_WIDER_M) or not otherLane(cpos, dir, vec3(x[1].pos))) then
                  want = math.max(want, math.min(1, need / 7))
                  if tStanding then forStanding = true end
                  if crossing and not braking[id] then M.put.cross = (M.put.cross or 0) + 1; dlog('car %d: braking for %d crossing (%.0f m, %.0f deg)', id, x[2], along, math.deg(math.acos(math.max(-1, math.min(1, (flat(tv) or dir):dot(dir)))))) end
                end
              end
            end
          end
        end
      end
    end
    local wantBeforeHold = want
    -- (2026-11-13, the twin: held on for up to a second after the avoiding had decided to go - let go the moment it goes round)
    if st.holdBlock and not st.avoid and t - st.holdBlock < 1.0 and o and o.vel and (vec3(o.vel):length() > 0.2 or braking[id]) then
      want = math.max(want, C.HOLD_BRAKE)
      if not st.holdSaid then st.holdSaid = true; M.avoid.held = (M.avoid.held or 0) + 1 end
    elseif st.holdSaid and not (st.holdBlock and t - st.holdBlock < 1.0) then st.holdSaid = nil end
    local was = braking[id]
    local raw = want
    if raw >= C.GUARD_PANIC_WANT then
      -- (a real emergency: at once, no smoke to spare anyone)
    elseif raw > (was or 0) then
      want = math.min(raw, (was or 0) + C.GUARD_RAMP_UP * C.GUARD_S)
    elseif raw < (was or 0) then
      want = math.max(raw, (was or 0) - C.GUARD_RAMP_DOWN * C.GUARD_S)
      if want < 0.03 then want = 0 end
    end
    if want > 0 then
      if not was or math.abs(was - want) > 0.03 then
        -- (held before a block, nothing else: not an emergency - counted on its own)
        if not was and wantBeforeHold > 0 then dlog('car %d: emergency brake (%.0f km/h)', id, vec3(objs[id].vel):length() * 3.6); M.put.guard = (M.put.guard or 0) + 1
        elseif not was then M.put.holdBrake = (M.put.holdBrake or 0) + 1 end
        -- (the end of a queue: hazard lights for those behind)
        if not was and forStanding and not st.wreckAt and vec3(objs[id].vel):length() > C.TAIL_WARN_MS then
          if not st.tailWarnAt then send(id, 'electrics.set_warn_signal(true)') end
          st.tailWarnAt = t
          M.put.tailWarn = (M.put.tailWarn or 0) + 1
          dlog('car %d: hazard lights, the end of a queue ahead', id)
        end
        braking[id] = want
        local spNow = objs[id] and objs[id].vel and vec3(objs[id].vel):length() or 0
        if spNow < C.STILL_MS then
          pbHeld[id] = true
          send(id, 'electrics.values.throttleOverride = 0 electrics.values.brakeOverride = 0 input.event("parkingbrake", 1, 1)')
        else
          send(id, string.format('electrics.values.throttleOverride = 0 electrics.values.brakeOverride = %.2f', want))
        end
      elseif not pbHeld[id] and objs[id] and objs[id].vel and vec3(objs[id].vel):length() < C.STILL_MS then
        -- (come to a stand under the brake: over to the hand brake now, before the gearbox reads the pedal as reverse)
        pbHeld[id] = true
        send(id, 'electrics.values.throttleOverride = 0 electrics.values.brakeOverride = 0 input.event("parkingbrake", 1, 1)')
        M.put.toHandbrake = (M.put.toHandbrake or 0) + 1
      end
    elseif was then
      letGo(id)
    end
    if st.tailWarnAt and want > 0 then st.tailWarnAt = math.max(st.tailWarnAt, t - C.TAIL_WARN_S + 2) end   -- (on while it brakes, then TAIL_WARN_S more at most)
    if st.tailWarnAt and t - st.tailWarnAt > C.TAIL_WARN_S then
      st.tailWarnAt = nil
      if not st.wreckAt then send(id, 'electrics.set_warn_signal(false)') end
    end
    ::guardNext::
  end
  for id in pairs(braking) do if not cars[id] then letGo(id) end end
  for id, at in pairs(matched) do if t - at > C.JUST_PUT_S * 2 then matched[id] = nil end end
  for id in pairs(guardSeen) do if not cars[id] then guardSeen[id] = nil end end
end

-- (2026-11-11) going round what is shut ------------------------------------------------------------------------
M.avoid = {}
local function blockFor(z)
  if z.block then return z.block end
  -- (2026-11-12) an obstacle learned from slow crashes alone (hazards.lua): its lane shut there, as for a wreck
  if z.kind == 'obstacle' and z.at then
    local at = (z.at - z.pos):dot(z.dir)
    local lat = lateralOf(z.at, z.dir)
    if not lat then return nil end
    z.block = { s0 = at - C.AVOID_WRECK_HL, s1 = at + C.AVOID_WRECK_HL, l0 = lat - C.AVOID_WRECK_HW, l1 = lat + C.AVOID_WRECK_HW }
    return z.block
  end
  if z.kind == 'wreck' or z.kind == 'accident' then
    local at = z.kind == 'wreck' and hazards.C.WRECK_BEFORE_M or 25
    local wp = z.pos + z.dir * at
    local lat = lateralOf(wp, z.dir)
    if not lat then return nil end
    local hl = z.kind == 'wreck' and C.AVOID_WRECK_HL or C.AVOID_ACC_HL
    local hw = z.kind == 'wreck' and C.AVOID_WRECK_HW or C.AVOID_ACC_HW
    z.block = { s0 = at - hl, s1 = at + hl, l0 = lat - hw, l1 = lat + hw }
    return z.block
  end
  return nil
end
M._blockFor = blockFor

-- every look, for one car: a cap to wait before it (or nil), and whether it is on its way round
local function avoidZones(id, st, c, zones, all, t)
  local myHw = (lengthOf(id) > C.TRUCK_LEN_M and 1.3 or 1.0) + C.AVOID_MARGIN_M
  local a = st.avoid
  if a then
    local along = (c.pos - a.z.pos):dot(a.z.dir)
    if along > a.s1 + C.AVOID_AFTER_M or t - a.t0 > C.AVOID_MAX_S then
      st.avoid = nil
      send(id, 'ai.driveInLane("on") electrics.set_left_signal(false) electrics.set_right_signal(true)')
      st.blinkOffAt = t + 2
      driverCall(id, st, 'setPassing(false)')
      local _, half = lateralOf(c.pos, c.dir)
      steerTo(id, st, c, (half or 3.2) * 0.5, math.max(20, c.speed * 2))
      dlog('car %d: past the %s, back in', id, a.z.kind)
      return nil
    end
    -- (held out there: without its lane the AI's plan runs back to the middle of the road within 100 m, as when passing. Only once it
    -- is over, and only when it drifts back towards the shut side - never pushed further out: the twin, 2026-11-11)
    local lat = lateralOf(c.pos, c.dir)
    local drifting = lat and ((a.side < 0 and lat > a.target + 0.5) or (a.side > 0 and lat < a.target - 0.5))
    if drifting and t > (a.holdFrom or 0) and t - (a.steerT or 0) > 1.2 then
      a.steerT = t
      send(id, shiftCmd(st, 30, (a.target - lat) * 0.8))
    end
    return nil
  end
  for _, z in ipairs(zones) do
    local B = blockFor(z)
    if B and c.dir:dot(z.dir) > 0.5 then
      local rel = c.pos - z.pos
      local along = rel:dot(z.dir)
      local look = math.max(C.AVOID_LOOK_M, c.speed * C.AVOID_LOOK_S)
      if along < B.s1 and along > B.s0 - look and math.abs(rel:dot(vec3(z.dir.y, -z.dir.x, 0))) < 20 then
        local lat, half = lateralOf(c.pos, c.dir)
        if lat and half then
          local leftRoom, rightRoom = B.l0 + half, half - B.l1
          local side = leftRoom >= rightRoom and -1 or 1
          local li = lanesHere(c.pos, c.dir)
          local passT = t + (B.s1 - along) / math.max(5, c.speed) + 3
          if li and li.n >= 2 then
            -- (never into the shut lane while it is ahead)
            if B.l1 > lat then st.noRightUntil = passT end
            if B.l0 < lat then st.noLeftUntil = passT end
          end
          if lat + myHw > B.l0 and lat - myHw < B.l1 then
            local toGo = B.s0 - along
            M.avoid.seen = (M.avoid.seen or 0) + 1
            st.blockNear = t
            if li and li.n >= 2 then
              -- (2026-11-12, Verkehrstest 12-16: "lane 2/2 -> right (shut ahead)" every three seconds - the right-hand side had the more room,
              -- but the car was in the right-hand lane already. The side with a lane that is there and clear of the block; none: it stops)
              local pick
              for _, s2 in ipairs({ side, -side }) do
                local k = li.idx + s2
                if k >= 1 and k <= li.n then
                  local cl = li.left + (k - 0.5) * li.w
                  if cl + myHw < B.l0 or cl - myHw > B.l1 then pick = s2; break end
                end
              end
              if not pick then
                st.why = 'shut'
                M.avoid.allShut = (M.avoid.allShut or 0) + 1
                if toGo < C.AVOID_STOP_M + 1 then st.holdBlock = t end
                return math.sqrt(2 * C.AVOID_DECEL * math.max(0, toGo - C.AVOID_STOP_M))
              end
              side = pick
              st.blockEnd, st.blockSide = math.max(0, toGo), side
              if side < 0 then st.noLeftUntil = nil else st.noRightUntil = nil end
              -- (no gap beside it yet: slowing as before a lane's end - inside the zone its cap rules, the lane end's braking does not)
              if st.laneUntil and t < st.laneUntil then return nil end
              if toGo < C.AVOID_STOP_M + 1 then st.holdBlock = t end
              return math.sqrt(2 * C.LANE_END_DECEL * math.max(0, toGo - C.LANE_END_STOP_M)) + math.min(2, math.max(0, toGo - C.AVOID_STOP_M) * 0.15)
            end
            -- (2026-11-12, Verkehrstest 12-16: of the cars on our own driver none went round the roadworks - it had taken a car over right
            -- at them, or its sideways shift was gone again. The way round on a road with one lane each way is BeamNG's, as for the one that
            -- did go round: our driver gives the car back first)
            -- (2026-11-14, Verkehrstest 15-35: "an einem Unfall musste ich selbst ausweichen, nichts ist drumherum gefahren" - handed to BeamNG, whose
            -- AI keeps to its lane and only gets round a stopped vehicle slowly, if at all. Our driver goes round it itself now: the shift to
            -- the other side held (setPassing), its speed by the cap, the wait for the oncoming side as before)
            if st.own then M.avoid.ownRound = (M.avoid.ownRound or 0) + 1 end
            local target = side < 0 and (B.l0 - myHw) or (B.l1 + myHw)
            local stopCap = math.sqrt(2 * C.AVOID_DECEL * math.max(0, toGo - C.AVOID_STOP_M))
            if target < -half - 0.3 or target > half + 0.3 then st.why = 'shut'; if toGo < C.AVOID_STOP_M + 1 then st.holdBlock = t end; return stopCap end
            local vPass = math.max(4, math.min(c.speed, (z.limit or 30) / 3.6))
            local needOncoming = side < 0 and target - myHw < 0
            local tp = (B.s1 - along + 10) / vPass + 1
            local blocked = needOncoming and oncomingBlock(id, c, all, vPass, tp, st.risk or 0.8)
            if blocked then
              st.why = 'wait ' .. tostring(z.kind)
              if not st.avoidWaitSaid then st.avoidWaitSaid = true; M.avoid.waited = (M.avoid.waited or 0) + 1; dlog('car %d: waits before the %s (oncoming %.0f m)', id, z.kind, blocked) end
              if toGo < C.AVOID_STOP_M + 1 then st.holdBlock = t end
              return stopCap
            end
            if toGo < math.max(C.AVOID_START_M, c.speed * C.AVOID_START_S) then
              local over = math.max(12, math.min(toGo - 4, c.speed * 2.2))
              st.avoid, st.avoidWaitSaid = { z = z, s1 = B.s1, t0 = t, target = target, side = side, steerT = t, holdFrom = t + over / math.max(3, c.speed) + 1 }, nil
              send(id, string.format('ai.driveInLane("off") electrics.set_%s_signal(true)', side < 0 and 'left' or 'right'))
              st.blinkOffAt = t + 3
              driverCall(id, st, 'setPassing(true)')
              steerTo(id, st, c, target, over)
              M.avoid.done = (M.avoid.done or 0) + 1
              dlog('car %d: round the %s, %.1f m to the %s (%.0f km/h)', id, z.kind, math.abs(target - lat), side < 0 and 'left' or 'right', c.speed * 3.6)
              return vPass
            end
          end
        end
      end
    end
  end
  return nil
end

-- (2026-11-14) two meeting on a narrow road: the speed to meet the oncoming one at (nil: none in the way), and whether the road is narrow
local function narrowMeet(id, st, c, all, t)
  if not c or not c.pos or not c.dir then return nil end
  local lat, half, link = lateralOf(c.pos, c.dir)
  if not lat or not half or half >= C.NARROW_HALF_M or math.abs(lat) > half + 1.5 or (type(link) == 'table' and link.oneWay) then st.narrowAt = nil; return nil end
  st.narrowAt = t
  local right = vec3(c.dir.y, -c.dir.x, 0)
  local look = math.max(C.NARROW_LOOK_M, (c.speed or 0) * C.NARROW_LOOK_S)
  local best
  for oid, o in pairs(all) do
    if oid ~= id and o.pos and o.dir and not virt.parked[oid] and o.dir:dot(c.dir) < -0.5 then
      local rel = relOf(o.pos, c.pos)
      local along = rel:dot(c.dir)
      local need = 0.5 * (widthOf(id) + widthOf(oid)) + C.NARROW_ROOM_M
      if along > 0 and along < look + (o.speed or 0) * C.NARROW_LOOK_S and math.abs(rel:dot(right)) < math.min(C.NARROW_LAT_M, need) then
        local gap = along - 0.5 * (lengthOf(oid) + lengthOf(id))
        -- (the other comes nearer too: half the room is ours)
        local share = (o.speed or 0) > 1 and (c.speed or 0) / math.max(0.5, (c.speed or 0) + o.speed) or 1
        local v = math.sqrt(C.NARROW_MS * C.NARROW_MS + 2 * C.NARROW_DECEL * math.max(0, gap * share - C.NARROW_SLOW_M))
        if not best or v < best then best = v end
      end
    end
  end
  return best
end
M._narrowMeet = narrowMeet

-- (2026-11-14, Verkehrstest 23-53: "Eigener LKW umfährt im Autodrive-Modus nicht die Baustellen oder Hindernisse". The autodrive is
-- BeamNG.Earth's - the truck's own stock AI on a path (ai.driveUsingPath, in its lane). It knows vehicles, not cones, lost cargo or the
-- shut strip round a wreck. The same look as for the traffic's cars: a block in its lane ahead - round it where there is room (room on
-- its own side, a free lane beside, or the oncoming side when nobody comes), else slowed to wait before it; back in once past)
M.truckAv = nil
local function truckSend(pv, code) pcall(function() pv:queueLuaCommand(code) end) end
local TRUCK_BACK = 'ai.driveInLane("on") ai.setSpeedMode("legal") electrics.set_left_signal(false) electrics.set_right_signal(false)'
function M._truckAvoid(ctx, t, pv, p, zones, all, pid)
  local s = M.truckAv
  local on = ctx.autodriveOn and ctx.autodriveOn() or false
  if not on or not pv or not p or not p.pos or not p.dir then
    if s then
      M.truckAv = nil
      if on and pv then truckSend(pv, TRUCK_BACK) end
    end
    return
  end
  local myHw = 1.3 + C.AVOID_MARGIN_M
  if s then
    local along = (p.pos - s.z.pos):dot(s.z.dir)
    -- (2026-11-14, Verkehrstest 14-30: the truck long on the oncoming side of a country road, the wheel to and fro - a way round that ended
    -- only past the block, and the route had turned off before it; meanwhile nudged back out against Earth's path, again and again.
    -- Now it ends once the truck no longer goes the block's way, or after TRUCK_AVOID_MAX_S)
    local offWay = p.dir:dot(s.z.dir) < 0.6 or math.abs((p.pos - s.z.pos):dot(vec3(s.z.dir.y, -s.z.dir.x, 0))) > 25
    if along > s.B.s1 + C.AVOID_AFTER_M + 8 or t - s.t0 > C.TRUCK_AVOID_MAX_S or offWay or (not s.out and along < s.B.s0 - 400) then
      M.truckAv = nil
      truckSend(pv, TRUCK_BACK)
      if s.out then
        local lat = lateralOf(p.pos, p.dir)
        if lat then truckSend(pv, string.format('ai.laneChange(nil, %.1f, %.2f)', math.max(25, p.speed * 2.5), s.home - lat)) end
      end
      dlog('autodrive: past the %s, back in', tostring(s.z.kind))
      return
    end
    local toGo = s.B.s0 - along
    if not s.out then
      local free = s.mode ~= 'oncoming' or not oncomingBlock(pid, p, all, math.max(5, s.passMs), (s.B.s1 - along + 20) / math.max(4, s.passMs), nil)
      if free and toGo < math.max(C.AVOID_START_M + 10, p.speed * (C.AVOID_START_S + 1)) then
        s.out, s.steerT = true, t
        local lat = lateralOf(p.pos, p.dir) or s.home
        local over = math.max(18, math.min(toGo - 2, p.speed * 2.6))
        truckSend(pv, string.format('ai.driveInLane("off") electrics.set_%s_signal(true) ai.laneChange(nil, %.1f, %.2f) ai.setSpeedMode("limit") ai.setSpeed(%.2f)',
          s.target < lat and 'left' or 'right', over, s.target - lat, s.passMs))
        M.avoid.truck = (M.avoid.truck or 0) + 1
        dlog('autodrive: round the %s, %.1f m to the %s (%.0f km/h)', tostring(s.z.kind), math.abs(s.target - lat), s.target < lat and 'left' or 'right', p.speed * 3.6)
      elseif not free then
        local v = math.sqrt(2 * C.AVOID_DECEL * math.max(0, toGo - C.AVOID_STOP_M - 4))
        if not s.waitMs or math.abs(s.waitMs - v) > 0.7 then
          s.waitMs = v
          truckSend(pv, string.format('ai.setSpeedMode("limit") ai.setSpeed(%.2f)', v))
        end
        if not s.waitSaid then s.waitSaid = true; M.avoid.truckWait = (M.avoid.truckWait or 0) + 1; dlog('autodrive: waits before the %s for the oncoming traffic', tostring(s.z.kind)) end
      end
    else
      -- (held out there: a new path from Earth, or the plan running back to the lane, puts it back in)
      local lat = lateralOf(p.pos, p.dir)
      if lat and math.abs(lat - s.target) > 1.0 and t - (s.steerT or 0) > 2 and along < s.B.s1 and (s.steerN or 0) < C.TRUCK_AVOID_STEER_N then
        s.steerT, s.steerN = t, (s.steerN or 0) + 1
        truckSend(pv, string.format('ai.driveInLane("off") ai.laneChange(nil, %.1f, %.2f)', math.max(15, p.speed * 1.8), (s.target - lat) * 0.9))
      end
    end
    return
  end
  for _, z in ipairs(zones) do
    local B = blockFor(z)
    if B and z.dir and p.dir:dot(z.dir) > 0.5 then
      local rel = p.pos - z.pos
      local along = rel:dot(z.dir)
      local look = math.max(C.AVOID_LOOK_M, p.speed * C.AVOID_LOOK_S)
      if along < B.s0 and along > B.s0 - look and math.abs(rel:dot(vec3(z.dir.y, -z.dir.x, 0))) < 20 then
        local lat, half, link = lateralOf(p.pos, p.dir)
        if lat and half and B.l0 < lat + myHw and B.l1 > lat - myHw then
          local oneWay = type(link) == 'table' and link.oneWay
          local leftT, rightT = B.l0 - myHw, B.l1 + myHw
          local target, mode
          if rightT <= half - 1.3 + 0.4 then target, mode = rightT, 'lane'             -- (room on its own side, or the lane to the right)
          elseif leftT >= -half + 1.3 - 0.3 then target, mode = leftT, oneWay and 'lane' or 'oncoming' end
          if target then
            local passMs = math.max(4, math.min(math.max(p.speed, 6), (tonumber(z.limit) or 30) / 3.6))
            M.truckAv = { z = z, B = B, target = target, mode = mode, t0 = t, home = lat, passMs = passMs }
            dlog('autodrive: a %s ahead in the lane (%.0f m) - round it %s', tostring(z.kind), B.s0 - along, mode == 'oncoming' and 'over the oncoming side' or 'beside it')
          else
            M.avoid.truckNoRoom = (M.avoid.truckNoRoom or 0) + 1
          end
          return
        end
      end
    end
  end
end

-- the loop ----------------------------------------------------------------------------------------------------

function M.update(ctx, dt)
  local t = now()
  pcall(guard, ctx, t)
  -- (2026-11-13) the placeholders, every frame
  if ctx.virtualOn and ctx.virtualOn() or next(virt.cars) then
    local pveh0 = ctx.playerVeh()
    local okR, errR = pcall(virt.render, t, pveh0 and vec3(pveh0:getPosition()) or nil)
    if not okR and not M.proxyErr then M.proxyErr = tostring(errR); log('W', 'fernfahrer.tai', 'placeholders: ' .. tostring(errR)) end
  end
  do
    local pveh = ctx.playerVeh()
    if map and map.objects then
      pcall(junctions.tick, t, map.objects, pveh and pveh:getID(), ctx.trailerId(), function(id, node) send(id, string.format('if fernfahrer_driver then fernfahrer_driver.junctionGo(%q) end', node)) end)
    end
  end
  if t - tickT < C.TICK_S then return end
  local stepS = math.min(1, t - tickT)            -- (the real time since the last look)
  tickT = t
  if not ctx.enabled() then return end
  local gt = rawget(_G, 'gameplay_traffic')
  local pv = ctx.playerVeh()
  if not gt or not gt.getTrafficList or not pv then return end
  local okL, list = pcall(gt.getTrafficList)
  if not okL or type(list) ~= 'table' then return end
  if t - spawnVarsT > 20 and gt.getTrafficVars and gt.setTrafficVars then
    spawnVarsT = t
    local okV, vars = pcall(gt.getTrafficVars)
    -- (2026-11-12) with the virtual traffic it brings the cars where they are seen: BeamNG's own respawning is off
    local wantSV = (ctx.virtualOn and ctx.virtualOn() and t - (M.nearT or t) < C.STARVE_S) and 0 or C.SPAWN_VALUE
    if okV and type(vars) == 'table' and tonumber(vars.spawnValue) and math.abs(vars.spawnValue - wantSV) > 0.01 then
      dlog('traffic: respawn value %.2f -> %.2f', vars.spawnValue, wantSV)
      pcall(gt.setTrafficVars, { spawnValue = wantSV })
    end
  end
  local center = vec3(pv:getPosition())
  local tdataNow
  do local okD, d = pcall(gt.getTrafficData); if okD and type(d) == 'table' then tdataNow = d end end
  local virtOnNow = ctx.virtualOn and ctx.virtualOn() or false
  M.virtOnNow = virtOnNow
  local all = snapshot(center, C.SCAN_M + 200)
  if not M.nearT then M.nearT = t end
  for _, oid in pairs(list) do
    local o = all[oid]
    if o and o.pos and center:distance(o.pos) < C.STARVE_M then M.nearT = t; break end
  end
  if ctx.virtualOn and ctx.virtualOn() and t - M.nearT >= C.STARVE_S and not M.starving then
    M.starving = true
    M.put.starved = (M.put.starved or 0) + 1
    dlog('traffic: no car within %.0f m for %.0f s - BeamNG respawning on again', C.STARVE_M, t - M.nearT)
    spawnVarsT = -1e9
  elseif M.starving and t - M.nearT < C.STARVE_S then
    M.starving = nil
    spawnVarsT = -1e9
  end
  local limit = ctx.roadLimit()
  local zones = ctx.zones() or {}
  -- (2026-11-12) the accident at the head of a jam
  do local cz = flow.causeZone and flow.causeZone(); if cz then local z2 = {}; for i, z in ipairs(zones) do z2[i] = z end; z2[#z2 + 1] = cz; zones = z2 end end
  M.zonesNow = zones
  local trailerId = ctx.trailerId()
  local playerId = pv:getID()
  local p = all[playerId]
  pcall(M._truckAvoid, ctx, t, pv, p, zones, all, playerId)
  local passing, queued = 0, false
  for _, st in pairs(cars) do if st.phase == 'pass' then passing = passing + 1 end end
  -- (who is overtaking right now: the traffic's own, and the player over the middle of a road)
  local passers = {}
  for cid, cst in pairs(cars) do if (cst.phase == 'pass' or cst.phase == 'back') and all[cid] then passers[#passers + 1] = { id = cid, o = all[cid] } end end
  if p and p.dir and p.speed > 5 then
    local plat = laneDrift(p.pos, p.dir)
    if plat and plat < -0.8 then passers[#passers + 1] = { id = playerId, o = p } end
  end
  local logIt = M.debug and t - logT > C.LOG_S
  if logIt then logT = t end

  -- (2026-11-11) a slow vehicle now and then on a country road – a tractor, a harvester going to the next field: a car ahead of the player,
  -- out of its sight, goes at 34-45 km/h for a few minutes. The queue behind it forms by itself, and they get past it as they get past
  -- anything slow (the passing above: when the oncoming lane allows)
  do
    local sv = M.slowVehicle
    if sv.id and (not cars[sv.id] or not all[sv.id] or t > sv.untilT) then
      if cars[sv.id] then cars[sv.id].slowMs = nil end
      dlog('slow vehicle %d: back to its pace', sv.id)
      sv.id = nil
    end
    if not sv.nextAt then sv.nextAt = t + rnd(C.SLOW_FIRST_S[1], C.SLOW_FIRST_S[2]) end
    local lim = ctx.roadLimit and ctx.roadLimit() or 0
    if C.SLOW_ON and not sv.id and t >= sv.nextAt and p and p.dir and p.speed > 10 and lim >= C.SLOW_ROAD_KMH[1] and lim <= C.SLOW_ROAD_KMH[2] and not oneWayRoad(p.pos, p.dir) then
      sv.nextAt = t + 30                      -- (nobody suitable: a look again in a while)
      local right = vec3(p.dir.y, -p.dir.x, 0)
      local best, bestAlong
      for _, id in pairs(list) do
        local o, st = all[id], cars[id]
        if o and o.dir and st and not st.phase and o.dir:dot(p.dir) > 0.8 and not flow.member[id] then
          local rel = relOf(o.pos, p.pos)
          local along = rel:dot(p.dir)
          if along > C.SLOW_AHEAD_M[1] and along < C.SLOW_AHEAD_M[2] and math.abs(rel:dot(right)) < 6 and (not bestAlong or along < bestAlong) then best, bestAlong = id, along end
        end
      end
      if best then
        cars[best].slowMs = rnd(C.SLOW_MS[1], C.SLOW_MS[2])
        sv.id, sv.untilT = best, t + rnd(C.SLOW_FOR_S[1], C.SLOW_FOR_S[2])
        sv.nextAt = t + rnd(C.SLOW_EVERY_S[1], C.SLOW_EVERY_S[2])
        M.slowVehicle.count = (M.slowVehicle.count or 0) + 1
        dlog('slow vehicle %d: %.0f km/h for %.0f s, %.0f m ahead of the player', best, cars[best].slowMs * 3.6, sv.untilT - t, bestAlong)
      end
    end
  end
  local dmgBefore = {}
  for cid, cst in pairs(cars) do dmgBefore[cid] = cst.dmg end
  local seen = {}
  for _, id in pairs(list) do
    seen[id] = true
    local c = all[id]
    local st = cars[id]
    if not st then st = newDriver(id); cars[id] = st end
    if flow.cause and flow.cause[id] then st.lastPos = c and c.pos or nil; goto next end   -- (a car of the accident at a jam's head: it stands)
    if virt.parked[id] then
      -- (2026-11-13: parked out of sight, a placeholder took its place. Moving all the same, over and over ("held again" 972 times in
      -- one test) - input.event is a one-off, not a held key: nothing kept the handbrake down between our checks, a second apart, and
      -- idle creep (or a slope) crept the car back up to 6-8 km/h each time before the next one. Now the handbrake (and disabled AI)
      -- is renewed every look, not only once it has already got away again)
      st.lastPos = nil
      if parkHow[id] == 'dormant' then
        -- (2026-11-14, Verkehrstest 23-53: "Instability detected" for a car asleep in the pool since minute 5. Woken by BeamNG itself
        -- (its pool filling the active ones up again) where it slept, perhaps long since under newly loaded ground: asleep again at once)
        local ob = getObjectByID(id)
        local okA, act = pcall(function() return ob and ob.getActive and ob:getActive() end)
        -- (2026-11-14, Verkehrstest 01-42: 2870 times - BeamNG's pool wakes every reserve for a moment whenever the number of cars changes,
        -- and puts the dormant ones back itself, updateTrafficPool. Only one still awake a second later is ours to put back)
        if okA and act then st.dormantAwakeT = st.dormantAwakeT or t else st.dormantAwakeT = nil end
        if okA and act and t - st.dormantAwakeT >= 1 and t - (st.dormantChk or -1e9) > 1 then
          st.dormantChk, st.dormantAwakeT = t, nil
          if toDormant(id) then
            M.put.reslept = (M.put.reslept or 0) + 1
            dlog('car %d: woken by BeamNG while parked - asleep again', id)
          end
        end
        goto next
      end
      beamMode(id, 'disabled')
      send(id, 'ai.setMode("disabled") electrics.values.throttleOverride = 0 input.event("parkingbrake", 1, 1)')
      if c and (c.speed or 0) > C.PARK_HOLD_MS and t - (parkHeld[id] or -1e9) > C.PARK_HOLD_S then
        parkHeld[id] = t
        send(id, 'thrusters.applyVelocity(obj:getDirectionVector() * 0, 0.2)')
        pcall(function() getObjectByID(id):setMeshAlpha(0, '') end)
        M.put.parkHeld = (M.put.parkHeld or 0) + 1
        dlog('car %d: parked, but moving (%.0f km/h) - held again', id, (c.speed or 0) * 3.6)
      end
      goto next
    end
    if flow.eco and flow.eco[id] then st.lastPos = c and c.pos or nil; goto next end       -- (a jam's car asleep, out of the player's way)
    -- (2026-11-14, Verkehrstest 23-53: "nach einer gewissen Zeit werden die Autos unsichtbar". BeamNG fades a traffic car out once it is
    -- far enough to be respawned (traffic/vehicle.lua tryRespawn: 'fadeOut', alpha to 0, 'queued') and in again where it puts it down.
    -- On Earth's short road map that new place is often not to be had: the car stays queued - invisible, driving on, solid - and with the
    -- virtual traffic BeamNG's respawning is switched off again meanwhile, so for good. Seen again at once when it is not to be respawned
    -- or is near, else when the respawn has not come within INVIS_MAX_S)
    do
      local tv = tdataNow and tdataNow[id]
      if tv and type(tv.alpha) == 'number' and tv.alpha < 0.99 and tv.state ~= 'fadeIn' then
        st.invisT = st.invisT or t
        local dP = c and c.pos and center:distance(c.pos) or 1e9
        if (virtOnNow and not M.starving) or dP < C.INVIS_NEAR_M or t - st.invisT > C.INVIS_MAX_S then
          local was = tv.state
          tv.state, tv.alpha = 'active', 1
          if type(tv.respawn) == 'table' and tonumber(tv.respawn.activeRadius) then tv.respawn.activeRadius = math.max(tv.respawn.activeRadius, math.min(dP, 2000) + C.INVIS_HOLD_M) end
          pcall(function() getObjectByID(id):setMeshAlpha(1, '') end)
          st.invisT = nil
          M.put.unhid = (M.put.unhid or 0) + 1
          dlog('car %d: faded out by BeamNG (%s), %.0f m away - seen again', id, tostring(was), math.min(dP, 99999))
        end
      else
        st.invisT = nil
      end
    end
    -- respawned (a jump): during a gap one that came back ahead of the player, on the way towards it, goes
    -- behind the player instead (the traffic spawns elsewhere while the gap lasts)
    local jumped = c and st.lastPos and c.pos:distance(st.lastPos) > C.JUMP_M
    -- (one out of the traffic pool is new to us – no jump to see: standing there is the sign it was just put down)
    local fresh = c and not st.seen and c.speed < 3
    if c then st.seen = true end
    -- (2026-11-14) moved, or just made real: our own driver asks for it at once (it waited up to 15 s after a reset before)
    -- (2026-11-14) going backwards
    if c and c.dir and c.vel and not st.wreckAt and not (flow.member and flow.member[id]) then
      if c.vel:dot(c.dir) < -C.REV_MS and not st.revHoldUntil then st.revT = (st.revT or 0) + stepS else st.revT = 0 end
      if st.revT >= C.REV_S then
        st.revT = 0
        local dP = center:distance(c.pos)
        local behindP = p and p.dir and (c.pos - p.pos):dot(p.dir) < -30
        if p and p.dir and (dP > C.REV_AWAY_M or behindP) and sendAway(id, p.pos, p.dir, p.speed or 0) then
          M.put.revAway = (M.put.revAway or 0) + 1
          dlog('car %d: going backwards %.0f m from the player - taken away', id, dP)
        else
          -- (stopped dead and held by the hand brake - the brake pedal would be its throttle in reverse)
          send(id, 'thrusters.applyVelocity(obj:getDirectionVector() * 0, 0.3) electrics.values.throttleOverride = 0 electrics.values.brakeOverride = 0 input.event("parkingbrake", 1, 1)')
          st.revHoldUntil, st.ownTry = t + C.REV_HOLD_S, -1e9
          M.put.revHeld = (M.put.revHeld or 0) + 1
          dlog('car %d: going backwards %.0f m from the player - held, our driver asked', id, dP)
        end
      end
    end
    if st.revHoldUntil and t > st.revHoldUntil then
      st.revHoldUntil = nil
      if not braking[id] then send(id, 'electrics.values.brakeOverride = nil electrics.values.throttleOverride = nil input.event("parkingbrake", 0, 1)') end
    end
    if jumped or (virt.just and virt.just[id] and virt.just[id] ~= st.ownPutSeen) then
      st.ownPutSeen = virt.just and virt.just[id] or st.ownPutSeen
      st.ownTry = t - C.OWN_TRY_S + C.OWN_AFTER_PUT_S
    end
    if jumped then st.limMs, st.limC, st.capMs, st.following, st.gasse, st.slowMs, st.avoid, st.blockEnd = nil, nil, nil, nil, nil, nil, nil, nil end   -- (a car from the pool starts afresh)
    -- (2026-11-12) falling through the world (FALL_MS): away with it before it lands as a wreck
    do
      local mo = map.objects[id]
      local vz = mo and mo.vel and mo.vel.z
      if c and vz and vz < -C.FALL_MS then
        st.fallN = (st.fallN or 0) + 1
        -- (and lower than at the first look: a car just moved has a speed like that for a moment)
        if st.fallN == 1 then st.fallZ = c.pos and c.pos.z or (mo.pos and mo.pos.z) end
        local zNow = c.pos and c.pos.z or (mo.pos and mo.pos.z)
        local dropped = st.fallZ and zNow and st.fallZ - zNow > C.FALL_DROP_M
        if st.fallN >= 2 and not dropped and zNow then st.fallN, st.fallZ = 1, zNow end
        if st.fallN >= 2 and dropped and p and p.pos and p.dir then
          if sendAway(id, p.pos, p.dir, p.speed) then
            M.put.fell = (M.put.fell or 0) + 1
            dlog('car %d: falling (%.0f m/s down) - taken away', id, -vz)
            send(id, 'electrics.set_warn_signal(false)')
            st.wreckAt, st.dmg, st.badCar, st.crashTs, st.blockPlT, st.fallN, st.lastPos = nil, nil, nil, nil, nil, nil, nil
            goto next
          end
        end
      elseif c then
        st.fallN = 0
      end
    end
    -- (2026-11-11) a crash: its wreck slows the traffic behind it; a crash alone at speed is remembered at the spot (hazards.lua)
    do
      local mo = map.objects[id]
      local dmg = mo and tonumber(mo.damage) or nil
      if dmg and c and st.dmg and not jumped and dmg - st.dmg > C.CRASH_DMG then
        -- (2026-11-11, Verkehrstest: 101 km/h into a bridge, 19000 of damage - and the car beside it, brushed in passing, 1500: not "alone",
        -- so the place was not remembered. Another vehicle close by counts only when it took a good share of the blow itself: then they
        -- hit each other; otherwise the road did it. The player's truck close by: never the road's fault)
        local alone = true
        local mine = dmg - st.dmg
        for oid, o in pairs(all) do
          if oid ~= id and o.pos:distance(c.pos) < hazards.C.ALONE_M then
            local omo = map.objects[oid]
            local before = dmgBefore[oid]
            local theirs = (omo and before) and ((tonumber(omo.damage) or 0) - before) or math.huge
            if oid == playerId or theirs > mine * C.STRUCT_SHARE then alone = false; break end
          end
        end
        local kmh = (st.lastSpeed or c.speed) * 3.6
        -- (2026-11-11, fifth Verkehrstest: two cars touched at 103 km/h - and the one spinning off into the barrier half a second later
        -- counted as crashed "alone" there, the spot learned. A car that is a wreck already crashes as a result, not because of the road)
        if st.wreckAt and t - st.wreckAt < C.CHAIN_S then alone = false end
        local s = hazards.crash(id, c.pos, st.lastDir or c.dir, kmh, alone)
        dlog('car %d crashed (%.0f km/h, damage +%.0f%s)%s', id, kmh, dmg - st.dmg, alone and ', alone' or '', s and string.format(': spot remembered, score %.1f', s.score) or '')
        -- (the breakdown service of the traffic: hazard lights at once; cleared away once it has stood a while out of the player's sight)
        if not st.wreckAt then send(id, 'electrics.set_warn_signal(true)') end
        st.wreckAt = t
        -- (2026-11-11, eleventh Verkehrstest: one car crashed 12 times in 6 minutes - damaged, it drove on, bumping along the kerbs and into
        -- others. BAD_CRASHES within BAD_S: the breakdown service takes it off the road as soon as the truck does not see it, moving or not)
        st.crashTs = st.crashTs or {}
        st.crashTs[#st.crashTs + 1] = t
        while #st.crashTs > 0 and t - st.crashTs[1] > C.BAD_S do table.remove(st.crashTs, 1) end
        if #st.crashTs >= C.BAD_CRASHES and not st.badCar then st.badCar = t; dlog('car %d: crashed %d times in %.0f s - to be taken off the road', id, #st.crashTs, C.BAD_S) end
      end
      if st.wreckAt and c then
        if jumped then st.badCar, st.crashTs = nil, nil end
        if jumped or (c.speed > 4 and t - st.wreckAt > 6 and not st.badCar) then
          st.wreckAt = nil
          send(id, 'electrics.set_warn_signal(false)')
        elseif (t - st.wreckAt > C.WRECK_CLEAR_S or st.badCar) and p and p.dir then
          local rel = c.pos - p.pos
          local d = rel:length()
          -- (2026-11-11, twelfth Verkehrstest: a car crashed right in front of the truck, in its lane, and the autodrive stood behind it for a
          -- minute - the wreck was in sight, so it was never cleared. Standing behind it for WRECK_BLOCK_S: the breakdown service tows it)
          local ahead, beside = rel:dot(p.dir), math.abs(rel:dot(vec3(p.dir.y, -p.dir.x, 0)))
          if p.speed < 1 and ahead > 3 and ahead < 60 and beside < 2.8 then st.blockPlT = (st.blockPlT or 0) + stepS else st.blockPlT = 0 end
          if (d > C.WRECK_UNSEEN_M or (rel:dot(p.dir) < -40 and d > 60) or st.blockPlT >= C.WRECK_BLOCK_S) then
            if sendAway(id, p.pos, p.dir, p.speed) then
              send(id, 'electrics.set_warn_signal(false)')
              dlog('car %d: the wreck cleared away (%.0f s, %.0f m from the player)', id, t - st.wreckAt, d)
              st.wreckAt, st.dmg, st.badCar, st.crashTs, st.blockPlT = nil, nil, nil, nil, nil
              M.put.cleared = (M.put.cleared or 0) + 1
            end
          end
        end
      end
      st.dmg = dmg
      if c then st.lastSpeed, st.lastDir = c.speed, c.dir end
    end
    st.lastPos = c and c.pos or nil
    -- (2026-11-09) a pass is only looked after near the player: one that fell out of that – far away, respawned, held back – stayed
    -- without its lane for good (a 49 s "pass" in the log) and drove down the middle of the road
    if st.phase == 'pass' and (jumped or not c or c.pos:distance(center) >= C.NEAR_M or t - st.t0 > C.PASS_TIMEOUT_S + 4) then
      endPass(id, st, c, false)
    end
    -- (also while a car is passing: a car popping up ahead is what made them brake hard, in game 2026-11-03)
    if jumped and not virt.isNew(id, t) and p and p.dir and (t < gap.untilT or passing > 0) and gap.respawnMoved < C.GAP_RESPAWN_MOVE
       and c.dir and c.dir:dot(p.dir) < -0.5 then
      local along = (c.pos - p.pos):dot(p.dir)
      if along > 60 and along < 1400 then
        local spot, sdir = placeBehind(p.pos, p.dir, rnd(C.BEHIND_M[1], C.BEHIND_M[2]))
        local gt2 = rawget(_G, 'gameplay_traffic')
        if putBehind(id, spot, sdir, p) then
          gap.respawnMoved = gap.respawnMoved + 1
          st.lastPos = spot
          dlog('gap: car %d respawned %.0f m ahead -> moved behind the player', id, along)
          goto next
        end
      end
    end
    -- respawned ahead of the player on its own way, in its lane: it would start there from standstill and brake
    -- everyone (the player too) – it goes behind the player instead (to catch up from there)
    if (jumped or fresh) and not flow.member[id] and not virt.isNew(id, t) and p and p.dir and c and c.dir and c.dir:dot(p.dir) > 0.5 and c.speed < 4
       and t - (st.movedAt or -1e9) > 30 then
      local rel = c.pos - p.pos
      local along = rel:dot(p.dir)
      if along > 0 and along < C.AHEAD_CLEAR_M and math.abs(rel:dot(vec3(p.dir.y, -p.dir.x, 0))) < 7 then
        local spot, sdir = placeBehind(p.pos, p.dir, rnd(C.BEHIND_M[1], C.BEHIND_M[2]))
        local gt2 = rawget(_G, 'gameplay_traffic')
        if putBehind(id, spot, sdir, p) then
          st.movedAt, st.lastPos = t, spot
          dlog('car %d respawned %.0f m ahead in the player\'s lane -> moved behind the player', id, along)
          goto next
        end
      end
    end
    -- (2026-11-11) the game's own respawn starts a car at 50 km/h at most, on the motorway too: brought up to the pace of the road
    if jumped and c and c.dir and not flow.member[id] and not st.phase then
      local _, rd, _, _, _, _, link = roadAt(c.pos, c.dir)
      local lim = type(link) == 'table' and tonumber(link.speedLimit) or 0
      if rd and rd:dot(c.dir) > 0.95 and lim * 3.6 >= C.BOOST_MIN_KMH then
        local want = math.min(paceOf(st, lim, lengthOf(id)), C.PACE_MAX_MS) * C.BOOST_SHARE
        -- (2026-11-11, fourth Verkehrstest: put down 100 m behind the truck standing in a queue and sent off at 95 km/h, an emergency brake every
        -- time. It looks as far as it needs to stop, and gets no more speed than it can lose before what is there)
        local q, qd = obstacleAhead(id, c, all, math.min(C.BOOST_LOOK_MAX_M, want * want / (2 * C.BOOST_DECEL) + 40))
        if q and all[q] then want = qd < 60 and 0 or math.min(want, all[q].speed + math.sqrt(2 * C.BOOST_DECEL * math.max(0, qd - 25))) end
        if want - c.speed > 4 then
          send(id, string.format('thrusters.applyVelocity(obj:getDirectionVector() * %.1f, 0.25)', want))   -- (the velocity itself, not a difference: thrusters.lua)
          M.put.boosted = (M.put.boosted or 0) + 1
        end
      end
    end
    if st.blinkOffAt and t >= st.blinkOffAt then st.blinkOffAt = nil; send(id, 'electrics.set_left_signal(false) electrics.set_right_signal(false)') end
    if c and c.dir and (c.pos:distance(center) < C.NEAR_M or flow.member[id]) then
      if t - st.aggrAt > 8 and not st.phase and not st.avoid then
        st.aggrAt = t
        -- (in its lane, every time: a respawned car keeps what the AI was last told)
        send(id, string.format('ai.setAggression(%.2f) ai.driveInLane("on") ai.setParameters({awarenessForceCoef = %.2f})', st.aggr, C.AWARE_COEF))
      end
      if keepOnRoad(id, st, c, t, stepS, p, lengthOf(id)) then goto next end
      -- (2026-11-11) the Rettungsgasse: standing or creeping in a jam on a road with several lanes, the left-hand lane keeps to the left,
      -- every other lane to the right; once the jam is over for it, back to the middle of its lane
      do
        local inJam = flow.member[id] and flow.active() and c.speed < C.GASSE_MS
        if inJam and not st.gasse then
          local gl = lanesHere(c.pos, c.dir)
          if gl and gl.n >= 2 then
            st.gasse = gl.idx == 1 and -C.GASSE_M or C.GASSE_M
            send(id, shiftCmd(st, C.GASSE_OVER_M, st.gasse))
            M.laneStats.gasse = (M.laneStats.gasse or 0) + 1
          end
        elseif st.gasse and not (flow.member[id] and flow.active()) then
          send(id, shiftCmd(st, math.max(C.GASSE_OVER_M, c.speed * 2), -st.gasse))
          st.gasse = nil
        end
      end
      -- our own driver: on when the setting is, for the ordinary traffic only (no police, no chase)
      do
        local own = ctx.ownDriver and ctx.ownDriver()
        if own and not st.own and not st.phase and not st.avoid and not (st.blockNear and t - st.blockNear < 6) and t - (st.ownTry or -1e9) >= C.OWN_TRY_S then
          st.ownTry = t
          local okD, data = pcall(gt.getTrafficData)
          local d = okD and type(data) == 'table' and data[id]
          if not d or d.roleName == nil or d.roleName == 'standard' then
            send(id, string.format('extensions.load("fernfahrer_driver") if fernfahrer_driver then fernfahrer_driver.acquire(%.2f) if fernfahrer_driver.setFollowT then fernfahrer_driver.setFollowT(%.2f, true) end end', st.capMs or 0, st.gapT or 1.5))
          end
        elseif st.own and not own then
          send(id, 'if fernfahrer_driver then fernfahrer_driver.release("control room") end')
        end
      end
      -- (2026-11-10: not on a carriageway of its own - the cars over the central barrier, in their own left lane, were taken for overtakers
      -- coming at it, and it slowed down to 85 % over and over: "bremsen random auf der Autobahn")
      local warned = not st.phase and #passers > 0 and not oneWayRoad(c.pos, c.dir) and passerAhead(id, c, passers)
      local cap
      for _, z in ipairs(zones) do
        local rel = c.pos - z.pos
        local along = rel:dot(z.dir)
        if c.dir:dot(z.dir) > 0.5 and math.abs(rel:dot(vec3(z.dir.y, -z.dir.x, 0))) < 12
           and along > -C.ZONE_BEFORE_M and along < (z.len or 40) then
          -- (2026-11-11, sixth Verkehrstest: "Autos auf der Autobahn langsam unterwegs, aber kein Stau davor" - a learned spot took a car
          -- on a road for 120 down to 60, with nothing to be seen. A spot is a reason to ease off, not to crawl: 70 % of the limit, 60 at
          -- the least. A wreck (to be seen) and a step in the road (a jolt at speed) keep theirs)
          local zl = z.limit / 3.6
          if z.kind == 'hazard' and st.limMs then zl = math.max(zl, st.limMs * C.HAZARD_SHARE) end
          cap = math.min(cap or 999, zl)
          if z.spot and along > 0 and st.hzSpot ~= z.spot then st.hzSpot = z.spot; hazards.passed(z) end
        end
      end
      -- (2026-11-11) round what is shut ahead
      st.blockEnd = nil
      do
        local okA, aCap = pcall(avoidZones, id, st, c, zones, all, t)
        if okA and aCap then cap = math.min(cap or 999, aCap) end
        if not okA and not M.avoid.err then M.avoid.err = tostring(aCap); log('W', 'fernfahrer.tai', 'avoid: ' .. tostring(aCap)) end
      end
      do
        local jc = flow.capFor(id, c, t, st.own and st.dgap or nil)
        if jc then cap = math.min(cap or 999, jc) end
      end

      -- (2026-11-09) the lane watch: a car that is not overtaking and not going round an accident (a zone) has no business left of
      -- the centre line. Whatever put it there, its plan goes back into its own lane (the stock AI clamps this to the lanes of its
      -- direction, so it cannot push a car off the road).
      -- (2026-11-10) the wrong way on a carriageway of its own ("zumindest auf der passenden Straßenseite"): the lane watch above does not judge one-way roads, and the own
      -- driver turned down such cars ("wrong way" in the log). Along a one-way link against its direction for 2 s, not near a junction: put back on the road behind
      -- the player, the right way round (where it is seen, as well: a car coming at the truck on the motorway is worse than one that is gone)
      if c.speed > 2 and t - (st.wwT or 0) > 0.9 then
        st.wwT = t
        local okW, centre, d, half, back, fwd, nodes, link = pcall(roadAt, c.pos, c.dir)
        local wrong = okW and centre and type(link) == 'table' and link.oneWay and link.inNode ~= nil and link.inNode == fwd
        if wrong then
          for _, n in ipairs({ back, fwd }) do
            local degree = 0
            for _ in pairs(linksOf(nodes, n)) do degree = degree + 1 end
            if degree > 2 and nodes[n].pos:distance(c.pos) <= 25 then wrong = false end
          end
          if wrong and math.abs((c.pos - centre):dot(vec3(d.y, -d.x, 0))) > (half or 3) + 2 then wrong = false end
        end
        st.wwN = wrong and (st.wwN or 0) + 1 or 0
        if st.wwN >= 2 and p and p.dir then
          st.wwN = 0
          local spot, sdir = placeBehind(p.pos, p.dir, rnd(C.BEHIND_M[1], C.BEHIND_M[2]))
          local gt = rawget(_G, 'gameplay_traffic')
          if putBehind(id, spot, sdir, p) then
            st.capMs, st.limMs, st.limC, st.phase = nil, nil, nil, nil
            M.safety.wrong = (M.safety.wrong or 0) + 1
            dlog('car %d the wrong way on a carriageway (%s, %.0f km/h, %.0f m from the player): put back behind the player', id, st.own and 'own driver' or 'BeamNG AI', c.speed * 3.6, p.pos:distance(c.pos))
            goto next
          end
        end
      end
      if not st.phase and not cap and not st.avoid and c.speed > 3 then
        local lat, half = laneDrift(c.pos, c.dir)
        if not lat then M.watch[half or '?'] = (M.watch[half or '?'] or 0) + 1 end
        -- (the log's proof that the watch runs: how many looks, how many could tell, how many found a car on the wrong side)
        local w = M.watch
        -- (2026-11-10: and a lorry by its left side: its middle right of the line, its mirror half a metre over it - "a green lorry quite in the middle of the B67")
        local lorry = lengthOf(id) > C.TRUCK_LEN_M
        local wide = lorry and lat and half and half >= widthOf(id) + 0.5 and (lat - widthOf(id) * 0.5) < -0.15
        w.looks, w.known, w.left = w.looks + 1, w.known + (lat and 1 or 0), w.left + ((lat and (lat < C.DRIFT_LAT or wide)) and 1 or 0)
        if wide then w.lorry = (w.lorry or 0) + 1 end
        if t - w.at > 60 then
          dlog('lane watch: %d looks, %d on a plain road, %d left of the centre line, %d of them lorries over it with their left side (not judged: %d turning, %d junction, %d one-way, %d other road)', w.looks, w.known, w.left, w.lorry or 0,
            w.turning or 0, w.junction or 0, w['one-way'] or 0, (w['another road'] or 0) + (w['no road'] or 0))
          local ls = M.laneStats
          dlog('several lanes: %d looks, %d to the left, %d back right, %d made room; on the road: %d brought back from the edge, %d rescued, %d wrong way', ls.multi, ls.left, ls.right, ls.room, M.safety.edge, M.safety.rescued, M.safety.wrong or 0)
          M.safety = { edge = 0, rescued = 0, wrong = 0 }
          do
            local parts, on = {}, 0
            for why, count in pairs(M.ownStats) do parts[#parts + 1] = why .. ': ' .. count end
            for _, s2 in pairs(cars) do if s2.own then on = on + 1 end end
            if on > 0 or #parts > 0 then
              local jn, jw = junctions.count()
              dlog('own driver: %d cars now; %s; junctions: %d goes, now %d in use, %d cars waiting', on, table.concat(parts, ', '), junctions.stats.go, jn, jw)
              junctions.stats.go = 0
            end
            M.ownStats = {}
          end
          M.laneStats = { multi = 0, left = 0, right = 0, room = 0 }
          M.watch = { at = t, looks = 0, known = 0, left = 0 }
        end
        if lat and (lat < C.DRIFT_LAT or wide) then
          st.driftT = (st.driftT or 0) + stepS
          if st.driftT >= C.DRIFT_HOLD_S and t - (st.driftFix or 0) > C.DRIFT_EVERY_S then
            st.driftFix = t
            -- (a lorry: just far enough that its left side is a little right of the line, not into the verge)
            local disp = wide and lat >= C.DRIFT_LAT and math.min(0.9, widthOf(id) * 0.5 + 0.2 - lat) or math.min(4, half * 0.5 - lat)
            send(id, 'ai.driveInLane("on") ' .. shiftCmd(st, math.max(15, c.speed * 1.8), disp))
            dlog('%s %d back into its lane: %.1f m %s the centre line for %.1f s (half width %.1f, %.0f km/h, %s)', lorry and 'lorry' or 'car', id,
              wide and lat >= C.DRIFT_LAT and (widthOf(id) * 0.5 - lat) or -lat, wide and lat >= C.DRIFT_LAT and 'with its left side over' or 'left of', st.driftT, half, c.speed * 3.6, st.own and 'own driver' or 'BeamNG AI')
          end
        else
          st.driftT = 0
        end
      end

      -- (2026-11-09: oncoming cars used to be steered to the right edge of their lane here, up to 230 m ahead of the truck and every
      -- 6 s. The AI's plan runs back to the lane centre by itself, so each one swung right, back, right. The meeting below needs no steering.)
      -- meeting anyone (the player's truck, another car): the stock AI brakes – down to standing, and then it
      -- reverses – for an oncoming vehicle whose line comes within half their two widths of its own, though their
      -- real paths pass each other. With room between them as they are (their actual positions) and nobody ahead in
      -- its lane, it stops minding oncoming vehicles for the moment of meeting.
      -- (not with one overtaking towards it: its eyes stay on that one)
      if not st.phase and not warned then
        local mid, md, mlat = meeting(id, c, all)
        local room = mid and (lengthOf(mid) > 7 and 1.3 or 0.95) + 0.95 + C.MEET_ROOM
        if mid and mlat >= room and not obstacleAhead(id, c, all, 40 + c.speed * 5.5) then
          if not st.meetUntil then send(id, 'ai.setAvoidCars("off")') end
          st.meetUntil = t + math.min(C.MEET_S, md / math.max(5, c.speed + all[mid].speed) + 1.5)
        end
      end
      -- (2026-11-08: and it ends the moment someone is ahead in its lane – with its eyes off the cars for up to 5 s, and a
      -- line of oncoming cars renewing that, it ran into the back of the truck)
      if st.meetUntil and (t > st.meetUntil or st.phase or warned or obstacleAhead(id, c, all, 30 + c.speed * 3.5)) then
        st.meetUntil = nil
        send(id, 'ai.setAvoidCars("on")')
      end

      if st.phase == 'back' then
        local tgt = all[st.target]
        local behind = tgt and (c.pos - tgt.pos):dot(tgt.dir or c.dir) or -1e9
        if not tgt or behind < -((st.targetLen or 5) * 0.5 + lengthOf(id) * 0.5 + 6) or t - (st.backT or t) > 9 then
          endPass(id, st, c, true, tgt and tgt.speed or c.speed)
        else
          capSpeed(id, st, math.max(2, tgt.speed * 0.75))
        end
        goto next
      end
      if st.phase == 'pass' then
        local tgt = all[st.target]
        if not tgt then endPass(id, st, c, false); goto next end
        local ahead = (c.pos - tgt.pos):dot(tgt.dir or c.dir)
        if ahead > (st.mergeM or C.MERGE_M) then endPass(id, st, c, false); goto next end
        if t - st.t0 > C.PASS_TIMEOUT_S then st.phase, st.backT = 'back', t; goto next end
        -- an oncoming car turns up (often one just respawned ahead): still behind the obstacle's middle -> abort,
        -- drop back; already level with it or past -> pull through (a bit faster), unless it is really close
        local olen = st.targetLen or 5
        local need = math.max(0, olen * 0.5 - ahead) + C.MERGE_M
        local closeT = need / math.max(1, c.speed - tgt.speed)
        local onc = oncomingBlock(id, c, all, c.speed, math.min(C.ABORT_TTC_S, closeT + 1), nil)
        if onc then
          if ahead < -olen * (st.rash and 0.6 or 0.25) then
            -- (2026-11-10: given up – but back in only once behind it again. It used to steer right at once, beside the truck, and brake)
            st.phase, st.backT = 'back', t
            capSpeed(id, st, tgt.speed * 0.75)
            dlog('car %d gives the pass up, drops back', id)
            goto next
          elseif not st.pushed then
            st.pushed = true
            send(id, string.format('ai.setSpeed(%.2f) ai.setAggression(%.2f)', (st.passMs or c.speed) + 3, math.min(0.8, st.aggr + 0.3)))
            driverCall(id, st, string.format('setCap(%.2f)', (st.passMs or c.speed) + 3))
            dlog('car %d pulls through (oncoming %.0f m)', id, onc)
          end
        end
        -- (the plan keeps the offset; only when the car has drifted back right for a while, a gentle correction –
        -- every laneChange adds to the planned offset, so they are not repeated each tick)
        do
          local lat = lateralOf(c.pos, c.dir)
          local target = -(st.half or 3.2) * 0.5
          -- (2026-11-09: without its lane the AI's plan runs back to the middle of the road within 100 m: held on the other lane more firmly)
          if lat and lat > target + 0.4 and t - (st.steerT or 0) > 1.2 then
            st.steerT = t
            send(id, shiftCmd(st, 30, (target - lat) * 0.8))
          end
        end
        goto next
      end

      do
        local oid, gapM = obstacleAhead(id, c, all, math.max(C.LOOK_M, 30 + c.speed * 3.5))
        -- (2026-11-09: on a multi-lane road in a bend the "car ahead" was the slow one in the next lane: braked for nothing)
        if oid and gapM > 12 and otherLane(c.pos, c.dir, all[oid].pos) then oid, gapM = nil, nil end
        local obLen = oid and lengthOf(oid) or 0
        if oid and trailerId and oid == trailerId and all[playerId] then oid = playerId end
        local o = oid and all[oid]
        local moving = o and o.speed >= C.MOVING_MS
        -- following a moving vehicle: never faster than it once the room left is what slowing down to its speed takes
        -- (a stopped one: the stock AI stops and passes). (2026-11-08: bumper to bumper, and the speed difference counts)
        local bumper = o and (gapM - obLen * 0.5 - 2.3) or 0
        -- (looks past the one ahead as well: when the one in front of it is braking or slower, it eases off early, as a driver does)
        local leadMs = o and o.speed or 0
        if o and moving then
          local q = obstacleAhead(oid, o, all, 70)
          if q and all[q] and all[q].speed < leadMs then leadMs = all[q].speed end
          -- (and what the one ahead has been told: the news from the head of a queue comes back car by car)
          local net = cars[oid] and cars[oid].netMs
          if net and net < leadMs then leadMs = net end
        end
        st.netMs = (o and moving and bumper < 90) and leadMs or nil
        local closing = o and math.max(0, c.speed - leadMs) or 0
        local keep = C.FOLLOW_GAP_M * 0.8 + c.speed * 0.9 + closing * closing / 5
        -- its own pace, from the limit of the road it is on (the same new limit twice in a row: one wrong "nearest road" changes nothing)
        local _, _, ownLink = lateralOf(c.pos, c.dir)
        local linkMs = type(ownLink) == 'table' and tonumber(ownLink.speedLimit) or nil
        if linkMs and linkMs > 3 then
          if st.limC ~= linkMs then st.limC, st.limN = linkMs, 0 else st.limN = st.limN + 1 end
          -- (2026-11-10: a lower one only after 3 looks and along the car's way: beside a motorway the "nearest road" was the slip road at 60 for a
          -- few hundred metres, and the cars on the motorway braked for it)
          local need = (st.limMs and linkMs < st.limMs) and 3 or 1
          local _, ld = roadAt(c.pos, c.dir)
          if need > 1 and ld and ld:dot(c.dir) < 0.97 then need = 6 end
          if st.limN >= need or not st.limMs then st.limMs = linkMs end
        end
        local wanted = st.limMs and paceAhead(st, c, paceOf(st, st.limMs, lengthOf(id)), lengthOf(id)) or nil
        if wanted then
          local rb = rampBoost(st, c, lengthOf(id))
          if rb and rb > wanted then wanted = rb; M.put.ramp = (M.put.ramp or 0) + 1 end
        end
        local li = lanesHere(c.pos, c.dir)
        -- (2026-11-11, third Verkehrstest: free cars held at a steady 29 km/h on the motorway. These three each took a share of the speed
        -- the car had at that moment, every half second – 0.92 for 3 s is 0.6, 0.85 for 4 s is 0.27 – down to the floor of 8 m/s. Now a
        -- share of the speed it had when it began, for as long as it lasts)
        st.why = nil
        if wanted then
          local y = li and li.idx < li.n and yieldSpeed(id, st, c, all, t, p)
          if y then
            st.yieldRef = st.yieldRef or c.speed            -- (yieldSpeed: below the one joining, and from the speed it had when it began)
            if y < wanted then wanted, st.why = y, 'yield' end
          else st.yieldRef = nil end
          if warned then
            st.warnRef = st.warnRef or c.speed
            local w = math.max(8, st.warnRef * 0.85)
            if w < wanted then wanted, st.why = w, 'passer' end
          else st.warnRef = nil end
          if st.edgeSlow and t < st.edgeSlow then
            st.edgeRef = st.edgeRef or c.speed
            local e = math.max(8, st.edgeRef * 0.92)
            if e < wanted then wanted, st.why = e, 'edge' end
          else st.edgeRef = nil end
        end
        if wanted and st.slowMs and st.slowMs < wanted then wanted, st.why = st.slowMs, 'slow vehicle' end
        if wanted and st.laneEnd then
          local e = math.sqrt(2 * C.LANE_END_DECEL * math.max(0, st.laneEnd - C.LANE_END_STOP_M)) + 2
          if e < wanted then wanted, st.why = e, 'lane ends' end
        end
        -- (not while it goes round something, nor before a block the avoiding has taken on)
        if not st.avoid and not (st.blockNear and t - st.blockNear < 2) then
          local q = queueAhead(id, c, all)
          if q then
            if wanted and q < wanted then wanted, st.why = math.max(1, q), 'queue' end
            if cap and q < cap then cap = math.max(1, q) end
            M.put.queueEase = (M.put.queueEase or 0) + 1
          end
        end
        do
          local nm = narrowMeet(id, st, c, all, t)
          if nm then
            if not wanted or nm < wanted then wanted, st.why = nm, 'narrow' end
            if cap and nm < cap then cap = nm end
            if not st.meetNarrowAt or t - st.meetNarrowAt > 4 then M.put.narrow = (M.put.narrow or 0) + 1 end
            st.meetNarrowAt = t
          end
        end
        if cap and (not wanted or cap < wanted) and st.why ~= 'narrow' then st.why = 'zone' end
        if moving and (bumper < keep and o.speed < c.speed + 1 or (st.following and bumper < keep + C.FOLLOW_RELEASE_M)) then
          -- (2026-11-09: a little faster than the car ahead the farther back it is, and held until well clear: it was free or capped
          -- at one distance, so the car surged up to it and braked, over and over)
          st.following, st.why = true, 'follow'
          local tight = bumper < C.FOLLOW_GAP_M * 0.8
          capSpeed(id, st, math.min(cap or 99, wanted or 99, tight and o.speed * 0.9 or math.max(leadMs, o.speed - 3) + math.min(3, math.max(0, bumper - keep) * 0.12)))
        else
          st.following = nil
          if cap then capSpeed(id, st, cap) elseif wanted then capSpeed(id, st, wanted) else freeSpeed(id, st) end
        end
        -- (2026-11-09: on a road with several lanes each way nobody ever overtook: "Richtungsfahrbahn" and "Autobahn" all over the log)
        if li then
          if not cap or st.blockEnd then laneBrain(id, st, c, all, t, stepS, li, o, gapM, wanted, (st.limMs or 27) * 3.6, p, p and p.dir and not lanesHere(p.pos, p.dir))
          else st.laneEnd = nil end
          st.behindT, st.stopT = 0, 0
          goto next
        end
        st.laneEnd = nil
        local why
        -- (the look far ahead was for the speed only: overtaking is decided close behind, as before)
        if not o or gapM >= C.LOOK_M then st.behindT, st.stopT = 0, 0; goto next end
        -- (2026-11-09: the limit of the road the car is on, not of the player's)
        local ownLimit = type(ownLink) == 'table' and tonumber(ownLink.speedLimit) and ownLink.speedLimit * 3.6 or limit
        if oid == playerId then queued = true end
        -- a standing obstacle (the player stopped at the roadside, a breakdown): the stock AI waits behind it for
        -- ever when it does not fit past in its lane (two cars stood a minute behind the player, 2026-11-03) –
        -- after STOP_WAIT_S it goes round slowly, with the same checks as a pass
        if not moving then st.stopT = (st.stopT or 0) + stepS else st.stopT = 0 end
        local roundStopped = not moving and st.stopT >= (oid == playerId and C.STOP_WAIT_S or C.STOP_WAIT_OTHER_S) and gapM >= 5
        -- (2026-11-10: "an der Ampel ist mir einer hinten reingefahren" - the truck waiting at the lights was a breakdown after 12 s, the car behind went round it,
        -- into the junction, and back in. Not round the player where a junction or the lights are just ahead of the truck, or a queue stands in front of it)
        if roundStopped and oid == playerId then
          if not st.waitAt or t - st.waitAt > 3 then
            st.waitAt = t
            local okJ, _, jd = pcall(roadAhead, o.pos, o.dir or c.dir, 70)
            local q = obstacleAhead(oid, o, all, 35)
            st.waitWhy = (okJ and jd and jd < 70 and 'Kreuzung oder Ampel vor dem Lkw') or (q and 'Stau vor dem Lkw') or nil
          end
          if st.waitWhy then roundStopped = false end
        end
        if not moving and not roundStopped then why = (oid == playerId and st.waitWhy) and ('wartet: ' .. st.waitWhy) or string.format('Hindernis steht (%.0f s)', st.stopT)
        elseif cap and not roundStopped then why = 'Zone'   -- (round a standing one even at an accident scene)
        elseif not ownLimit then why = 'kein Limit bekannt'
        elseif ownLimit >= 110 then why = 'Autobahn'
        elseif not roundStopped and ownLimit <= C.TOWN_KMH then why = 'innerorts'
        elseif oneWayRoad(c.pos, c.dir) then why = 'Richtungsfahrbahn'
        elseif not roundStopped and (select(2, lateralOf(c.pos, c.dir)) or 0) < C.PASS_MIN_HALF then why = 'Straße zu schmal'
        elseif st.cool and t < st.cool then why = 'Pause nach Überholen'
        -- (2026-11-11, ninth Verkehrstest: the truck at 60 on a road for 100 was "not slow enough" - its tractor alone is under TRUCK_LEN_M, the
        -- trailer was not counted, so the share for a car (60 %) was asked of it. The player drives a lorry, always)
        elseif not roundStopped and o.speed * 3.6 > math.min(ownLimit - C.SLOW_KMH, ownLimit * ((oid == playerId or obLen > C.TRUCK_LEN_M) and C.SLOW_SHARE_TRUCK or C.SLOW_SHARE)) then
          why = string.format('Vordermann nicht langsam genug (%.0f von %d)', o.speed * 3.6, ownLimit)
        elseif oid ~= playerId then
          -- a queue: the car ahead follows a slower one itself – wait (only the one behind the slow vehicle passes)
          local qid, qgap = obstacleAhead(oid, o, all)
          if qid and qgap < C.QUEUE_M then why = 'Kolonne' end
        elseif not st.rash then
          -- (2026-11-10) room in front of the truck to go back in: nobody slow there
          local qid, qgap = obstacleAhead(oid, o, all, 60)
          if qid and qgap < 45 then why = 'kein Platz vor dem Lkw' end
        end
        if why then
          st.behindT = 0
        else
          st.behindT = st.behindT + stepS
          local waitFor = oid == playerId and st.wait or math.max(st.wait, C.OTHER_WAIT_S)
          if st.behindT < waitFor and not roundStopped then why = string.format('wartet %.0f/%.0f s', st.behindT, waitFor)
          elseif passing >= C.MAX_PASSING then why = 'ein anderer überholt schon'
          elseif gapM < 5 then why = 'zu dicht dran'
          end
        end
        if not why then
          local olen = lengthOf(oid)
          if oid == playerId and trailerId then olen = olen + lengthOf(trailerId) + 1 end
          local passMs = roundStopped and C.ROUND_MS or math.min(ownLimit / 3.6 + 2.5, o.speed + C.PASS_EXTRA_KMH / 3.6)
          if passMs - o.speed < C.MIN_GAIN_MS then why = 'kein Tempoüberschuss'
          else
            local passDist = gapM + olen + C.MERGE_M + 6
            local tp = passDist / (passMs - o.speed) + 2
            local need = passMs * tp + 30
            local bend, junctionAt, crest = roadAhead(c.pos, c.dir, need)
            local block = oncomingBlock(id, c, all, passMs, tp, st.risk)
            if bend > C.MAX_BEND_DEG then why = string.format('Kurve %.0f°', bend); st.behindT = st.wait * 0.7
            elseif crest and not roundStopped then why = 'Kuppe'; st.behindT = st.wait * 0.7
            -- (a side road matters only where the car is beside the obstacle – not one far ahead on the way)
            elseif junctionAt and junctionAt < gapM + olen + 35 then why = string.format('Einmündung in %.0f m', junctionAt); st.behindT = st.wait * 0.7
            elseif block then why = string.format('Gegenverkehr in %.0f m (Überholweg %.0f m)', block, need)
            else
              ctx.protect(id)
              st.target, st.targetLen = oid, olen
              startPass(id, st, c, passMs)
              passing = passing + 1
              dlog('PASS car %d: %.0f -> %.0f km/h over %.0f m, risk %.2f', id, o.speed * 3.6, passMs * 3.6, passDist, st.risk)
            end
          end
        end
        -- (only when the reason changes: the same line every 4 s filled the log, 2026-11-04)
        local whyKey = why and why:gsub('%d+', '#')
        if why and logIt and oid == playerId and st.lastWhy ~= whyKey then
          st.lastWhy = whyKey
          dlog('car %d behind the player (%.0f m): %s', id, gapM, why)
        end
      end
    end
    -- (out of the player's sight: back to the road's own limit, nobody is watching over its pace there)
    if c and c.dir and c.pos:distance(center) >= C.NEAR_M and not st.phase and not flow.member[id] then
      if st.own then send(id, 'if fernfahrer_driver then fernfahrer_driver.release("control room") end'); st.own = nil end
      if st.capMs then freeSpeed(id, st) end
    end
    ::next::
  end
  pcall(flow.update, t, p, playerId, all, list, ctx)
  do
    local okVt, errVt = pcall(virt.update, t, p, playerId, trailerId, all, list, ctx)
    if not okVt and not M.virtErr then M.virtErr = tostring(errVt); log('W', 'fernfahrer.tai', 'virtual: ' .. tostring(errVt)) end
  end
  pcall(fillBehind, t, p, playerId, all, list)
  pcall(updateGap, t, pv, all, queued)
  for id, st in pairs(cars) do
    if not seen[id] then
      if st.phase then send(id, 'ai.driveInLane("on") ai.setSpeedMode("legal") electrics.set_left_signal(false)') end
      if st.own then send(id, 'if fernfahrer_driver then fernfahrer_driver.release("control room") end') end
      cars[id] = nil
    end
  end
end

-- the car's own driver reports: it has the car, or it gave it back (and why)
M.ownStats = {}
M.ownTotal = {}
-- what the jams need from here
-- what the virtual traffic needs from here
virt.init({ roadAt = roadAt, linksOf = linksOf, send = send, dlog = dlog, rnd = rnd, flow = flow, lengthOf = lengthOf,
  nodes = function() local okM, m = pcall(function() return map.getMap() end); return okM and m and m.nodes or nil end,
  respawn = function(id, pos, dir)
    local gt = rawget(_G, 'gameplay_traffic')
    if not gt or not gt.respawnVehicle then return false end
    local at = snapGround(pos)
    if not at then return false end
    local v = trafficVeh(id)
    if v then v.respawnSpeed = nil end
    return (pcall(gt.respawnVehicle, id, at, quatFromDir(dir, vec3(0, 0, 1))))
  end,
  busy = function(id) local st = cars[id]; return st and (st.phase ~= nil or st.wreckAt ~= nil or st.avoid ~= nil) end,
  zones = function() return M.zonesNow end,
  -- (2026-11-13) the placeholders (virtual.lua): the car models alone, no physics
  shapes = function(dirs)
    local out = {}
    for _, dir in ipairs(dirs or {}) do
      local okF, files = pcall(function() return FS:findFiles(dir, '*.dae', 0, false, false) end)
      if okF and type(files) == 'table' then for _, f in ipairs(files) do out[#out + 1] = f end end
    end
    return out
  end,
  proxyNew = function(shape)
    local o = createObject('TSStatic')
    if not o then return nil end
    o.useInstanceRenderData = false
    o:setField('dynamic', 0, 'true')
    o:setField('shapeName', 0, shape)
    o:setField('collisionType', 0, 'None')
    o:setField('decalType', 0, 'None')
    pcall(function() o:setField('instanceColor', 0, string.format('%.2f %.2f %.2f 1', rnd(0.05, 0.9), rnd(0.05, 0.9), rnd(0.05, 0.9))) end)
    o.canSave = false
    proxySeq = proxySeq + 1
    o:registerObject('ff_proxy_' .. proxySeq)
    return o
  end,
  proxyMove = function(o, pos, dir)
    -- (a vehicle's model faces -y: turned round)
    local rot = quatFromDir(-dir, vec3(0, 0, 1))
    o:setPosRot(pos.x, pos.y, pos.z + C.PROXY_Z_LIFT, rot.x, rot.y, rot.z, rot.w)
  end,
  proxyHide = function(o) pcall(function() o:setPosRot(0, 0, -5000, 0, 0, 0, 1) end) end,
  -- (the models' materials: loaded for a vehicle only when one of the folder is spawned, and then not for a bare model - all of the
  -- folders' material files and the common ones, once, as the game does for a vehicle, core/vehicle/manager.lua)
  loadMaterials = function(dirs)
    local n = 0
    for _, dir in ipairs(dirs or {}) do
      local okF, files = pcall(function() return FS:findFiles(dir, '*materials.json', -1, true, false) end)
      if okF and type(files) == 'table' then for _, f in ipairs(files) do if pcall(loadJsonMaterialsFile, f) then n = n + 1 end end end
    end
    dlog('placeholders: %d material files loaded', n)
  end,
  -- (2026-11-13, Verkehrstest 01-11: never one parked - this asked a P that is the guard's own, here nil. The player as virtual.lua has it)
  parkSpot = function(dist, ppos, pdir)
    if not ppos or not pdir then return nil end
    local spot, sdir = placeBehind(vec3(ppos), pdir, dist)
    if not spot then return nil end
    spot = snapGround(spot)
    return spot, sdir
  end,
  park = function(id, spot, sdir)
    -- (first choice: asleep where it is - no teleport, nothing on the road)
    if canDormant(id) then
      send(id, 'if fernfahrer_driver then fernfahrer_driver.release("parked") end electrics.set_warn_signal(false)')
      if toDormant(id) then
        parkHow[id], parkHeld[id] = 'dormant', nil
        M.put.dormant = (M.put.dormant or 0) + 1
        return true
      end
    end
    if not spot or not sdir then return false end
    local gt = rawget(_G, 'gameplay_traffic')
    if not gt or not gt.respawnVehicle then return false end
    beamMode(id, 'disabled')
    if not pcall(gt.respawnVehicle, id, spot, quatFromDir(sdir, vec3(0, 0, 1))) then beamMode(id, 'traffic'); return false end
    send(id, 'if fernfahrer_driver then fernfahrer_driver.release("parked") end ai.setMode("disabled") electrics.values.throttleOverride = 0 input.event("parkingbrake", 1, 1)')
    pcall(function() getObjectByID(id):setMeshAlpha(0, '') end)
    parkHeld[id] = nil
    parkHow[id] = 'hidden'
    return true
  end,
  unpark = function(id)
    parkHeld[id] = nil
    if parkHow[id] == 'dormant' then
      parkHow[id] = nil
      fromDormant(id)
      local st = cars[id]
      if st then st.lastPos, st.capMs, st.limMs, st.limC, st.following = nil, nil, nil, nil, nil end
      return
    end
    parkHow[id] = nil
    pcall(function() getObjectByID(id):setMeshAlpha(1, '') end)
    beamMode(id, 'traffic')
    send(id, 'electrics.values.throttleOverride = nil input.event("parkingbrake", 0, 1) ai.setMode("traffic")')
    local st = cars[id]
    if st then st.lastPos, st.capMs, st.limMs, st.limC, st.following = nil, nil, nil, nil, nil end
  end,
  alive = function(id) return getObjectByID(id) ~= nil end,
  -- (2026-11-14) a real car's paint, for its placeholder: "r g b a"
  colorOf = function(id)
    local o = getObjectByID(id)
    local okC, c = pcall(function() return o and o.color end)
    if not okC or not c then return nil end
    local okS, s = pcall(function() return string.format('%.3f %.3f %.3f 1', c.x or c.r or c[1], c.y or c.g or c[2], c.z or c.b or c[3]) end)
    return okS and s or nil
  end,
  proxyColor = function(o, col) if o and col then o:setField('instanceColor', 0, col) end end,
  canDormant = canDormant,
  poolRoom = poolRoom,
  -- (2026-11-13) a real car's model as a placeholder file: its configuration names the model part (agent_traffic_eunew1_model_fmibiza), the
  -- model's file has that name in the vehicle's folder (fmibiza.dae)
  shapeOf = function(id)
    local o = getObjectByID(id)
    if not o then return nil end
    local pc = o.partConfig
    if type(pc) ~= 'string' or pc == '' then return nil end
    local data
    if pc:sub(1, 1) == '{' then
      local okJ, d = pcall(function() return jsonDecode(pc) end)
      data = okJ and d or nil
    else
      data = shapeCfg[pc]
      if data == nil then local okR, d = pcall(jsonReadFile, pc); data = okR and d or false; shapeCfg[pc] = data end
    end
    if type(data) ~= 'table' or type(data.parts) ~= 'table' then return nil end
    local model = nil
    for k, v in pairs(data.parts) do
      if type(k) == 'string' and k:sub(-6) == '_model' and type(v) == 'string' then model = v:match('_model_(.+)$'); break end
    end
    local folder = (data.model or (o.JBeam ~= '' and o.JBeam) or nil)
    if not model or not folder then return nil end
    local dae = '/vehicles/' .. folder .. '/' .. model .. '.dae'
    if FS and FS.fileExists and not FS:fileExists(dae) then return nil end
    return dae
  end,
  isActive = function(id) local o = getObjectByID(id); if not o or not o.getActive then return true end local okA, a = pcall(function() return o:getActive() end); return not okA or a ~= false end,
  groundOk = groundOk })
M.virt = virt
flow.init({ beamMode = beamMode, roadAt = roadAt, linksOf = linksOf, lanesHere = lanesHere, lengthOf = lengthOf, send = send, dlog = dlog, rnd = rnd, oneWay = oneWayRoad,
  forget = function(id) local st = cars[id]; if st then st.lastPos, st.capMs, st.limMs, st.limC, st.following = nil, nil, nil, nil, nil end end,
  busy = function(id) local st = cars[id]; return (st and st.phase ~= nil) or virt.parked[id] ~= nil end, snapGround = snapGround,
  -- (2026-11-14) the jam takes sleeping cars of the pool too, woken for it
  parked = function() return virt.parked end,
  holdSpeed = function(id, v) if virt.just and virt.justV then virt.just[id], virt.justV[id] = now(), v or 0 end end,
  poolRoom = function() return poolRoom() end,
  wake = function(id)
    if not virt.parked[id] then return end
    virt.parked[id] = nil
    if virt.reserved then virt.reserved[id] = nil end
    local a = virt._api()
    if a and a.unpark then a.unpark(id) end
  end })

function M.onJunctionAsk(id, node, x, y, inB, outB, rank, eq, mainA, mainB, eta)
  if cars[id] then junctions.ask(id, node, x, y, inB, outB, rank, eq, mainA, mainB, eta, now()) end
end
function M.onJunctionDone(id, node) junctions.done(id, node) end

-- (2026-11-11) driver.lua's report every 2 s: planned speed, throttle, gap to the one in front, what sets the speed (for the lab)
function M.onOwnState(id, vt, thr, gap, why)
  local st = cars[id]
  if st then st.dvt, st.dthr, st.dgap, st.dwhy = tonumber(vt), tonumber(thr), tonumber(gap), why end
end

function M.onOwnDriver(id, on, why)
  local st = cars[id]
  why = tostring(why or '?')
  M.ownStats[why] = (M.ownStats[why] or 0) + 1
  M.ownTotal[why] = (M.ownTotal[why] or 0) + 1        -- (the whole drive, for the traffic lab: ownStats is emptied with every log line)
  if not st then return end
  if on then
    st.own = true
    -- (2026-11-14, Verkehrstest 01-42: ours at 38 km/h on the motorway, the control room's cap long since 130 - the driver took over with the
    -- cap of the moment it was asked, and a cap lifted before its answer came never reached it. Now what holds now, always, a lifted one too)
    send(id, string.format('if fernfahrer_driver then fernfahrer_driver.setCap(%.2f) end', st.capMs or 0))
  elseif st.own or not why:find('refused') then
    -- (BeamNG's AI has started afresh: everything it was told is to be told again)
    st.own, st.capMs, st.aggrAt = nil, nil, 0
  end
end

function M.stats()
  local n, p = 0, 0
  for _, st in pairs(cars) do n = n + 1; if st.phase == 'pass' then p = p + 1 end end
  return { cars = n, passing = p }
end

-- (2026-11-11) for the traffic lab (trafficlab.lua): the same look at the road as here, and what a car is doing
M.labApi = { roadAt = roadAt, lanesHere = lanesHere, laneDrift = laneDrift, lengthOf = lengthOf, car = function(id) return cars[id] end }

function M.reset()
  for id in pairs(braking) do letGo(id) end
  for id, st in pairs(cars) do
    if st.phase or st.capMs then send(id, 'ai.driveInLane("on") ai.setSpeedMode("legal") electrics.set_left_signal(false)') end
    if st.own then send(id, 'if fernfahrer_driver then fernfahrer_driver.release("control room") end') end
  end
  cars, gap = {}, { nextAt = nil, untilT = 0, moved = 0, respawnMoved = 0 }
  M.slowVehicle = {}
  junctions.reset()
  flow.reset()
end

return M
