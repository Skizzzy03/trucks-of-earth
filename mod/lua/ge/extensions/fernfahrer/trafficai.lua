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
  GUARD_LOOK_M = 95,
  GUARD_LAT_M = 2.0,
  GUARD_DECEL = 4.0,        -- needing to brake harder than this to stay clear of the truck: brakes applied
  GUARD_RELEASE = 2.5,      -- ... and held until it needs less than this (one threshold: the brakes came on and off every look)
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
  OWN_TRY_S = 3,            -- our own driver: asks to take a car over this often
  LANE_MAX_BEND = 12,       -- several lanes: no lane change with more of a bend than this ahead
  YIELD_M = 70,             -- lets in one asking for a gap this far ahead of it
  PASSER_M = 320,           -- oncoming cars ease off for one overtaking towards them, this far away
  EDGE_MARGIN = 0.2,        -- a car's side this far over the real edge of the asphalt: back in
  EDGE_HOLD_S = 0.5,
  EDGE_EVERY_S = 1.5,
  RESCUE_S = 7,             -- standing off the road this long: put back on it, when the player does not see it
  LANE_COOL_S = 14,         -- several lanes: at least this long between two lane changes of one car (no weaving)
  LANE_GAIN_MS = 3,         -- changes lane for one at least this much slower than it wants to go
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
local tickT, logT = 0, 0
local gap = { nextAt = nil, untilT = 0, moved = 0, respawnMoved = 0 }
local function now() return os.clock() end
local function rnd(a, b) return a + math.random() * (b - a) end
local function flat(v) local w = vec3(v.x, v.y, 0); local l = w:length(); return l > 1e-3 and w * (1 / l) or nil end
local function obj(id) return getObjectByID(id) end
local function send(id, cmd) local v = obj(id); if v then v:queueLuaCommand(cmd) end end
local function dlog(fmt, ...) if M.debug then log('I', 'fernfahrer.tai', string.format(fmt, ...)) end end

local function newDriver()
  local r, acc = math.random(), 0
  local t = M.TEMPERS[1]
  for _, x in ipairs(M.TEMPERS) do acc = acc + x.share; if r <= acc then t = x; break end end
  return { aggr = rnd(t.aggr[1], t.aggr[2]), wait = rnd(t.wait[1], t.wait[2]), risk = rnd(t.risk[1], t.risk[2]),
    pace = rnd(t.pace[1], t.pace[2]), rash = t.rash or nil, behindT = 0, aggrAt = 0 }
end

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
    for _ in pairs(nodes[n].links or {}) do degree = degree + 1 end
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
    for m in pairs(nodes[cur].links or {}) do
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
    for m, link in pairs(nodes[n].links or {}) do
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

local function obstacleAhead(id, c, all, look)
  look = look or C.LOOK_M
  local best, bd
  local right = vec3(c.dir.y, -c.dir.x, 0)
  for oid, o in pairs(all) do
    if oid ~= id and o.dir and o.dir:dot(c.dir) > 0.8 then
      local rel = o.pos - c.pos
      local along = rel:dot(c.dir)
      if along > 2 and along < look and math.abs(rel:dot(right)) < C.LANE_W and (not bd or along < bd) then
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
    local rel = o.pos - c.pos
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
      local rel = o.pos - c.pos
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
    local kmh = limitMs * 3.6 + 0.5
    local rule = kmh >= 110 and 80 or (kmh > 50 and math.min(kmh, 60) or kmh)
    return rule / 3.6 * math.max(0.97, math.min(1.03, p))
  end
  if limitMs * 3.6 <= C.TOWN_KMH then p = math.min(p, 1.03) end
  return math.min(limitMs * p, C.PACE_MAX_MS)
end

-- ... and with a lower limit coming up: already slowing for it, gently. (The stock "legal" speed mode reads the limits along its plan,
-- a set speed does not: into town at 100, then the brakes.)
local function paceAhead(st, c, wanted, len)
  local centre, heading, _, back, fwd, nodes = roadAt(c.pos, c.dir)
  if not centre or not heading then return wanted end
  local best = wanted
  walk(nodes, back, fwd, heading, nodes[fwd].pos:distance(c.pos), math.max(80, c.speed * 6), function(n, travelled, _, nextNode)
    local link = nextNode and (nodes[n].links[nextNode] or nodes[nextNode].links[n])
    local lim = type(link) == 'table' and tonumber(link.speedLimit) or nil
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
    if oid ~= id and o.dir and o.dir:dot(c.dir) > 0.6 then
      local rel = o.pos - c.pos
      local along = rel:dot(c.dir)
      local side2 = rel:dot(right)
      if math.abs(along) < 260 and math.abs(side2) < 14 then
        local lo = lateralOf(o.pos, c.dir) or (li.lat + side2)
        if math.abs(lo - centre) < li.w * 0.62 then
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

local laneTick = -1                   -- (one lane change per look over all cars: the traffic does not all jump at once)
M.laneStats = { multi = 0, left = 0, right = 0, room = 0 }

local function changeLane(id, st, c, li, side, t, why)
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
    local rel = o.pos - c.pos
    local along, side = rel:dot(c.dir), rel:dot(right)
    return along > -5 and along < C.YIELD_M and side > 2.2 and side < 5.5
  end
  for cid, cst in pairs(cars) do
    if cid ~= id and cst.wantGapT and t - cst.wantGapT < 1.1 and asks(all[cid]) then
      return math.max(8, math.min(all[cid].speed - 1.5, c.speed - 2.5))
    end
  end
  if p and p.signal < 0 and asks(p) then return math.max(8, math.min(p.speed - 1.5, c.speed - 2.5)) end
  return nil
end

-- is someone overtaking towards this car, on its side of the road?
local function passerAhead(id, c, passers)
  local right = vec3(c.dir.y, -c.dir.x, 0)
  for _, x in ipairs(passers) do
    if x.id ~= id and x.o.dir and x.o.dir:dot(c.dir) < -0.6 then
      local rel = x.o.pos - c.pos
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
    for _ in pairs(nodes[n].links or {}) do degree = degree + 1 end
    if degree > 2 and nodes[n].pos:distance(c.pos) <= C.DRIFT_JUNCTION_M + 8 then atJunction = true end
  end
  local along = math.abs(d:dot(c.dir))
  -- (2026-11-10: a car more than a little beside this road is on another one running along it, and a correction that has not helped three
  -- times is not going to. It was pushing cars about, every 1.5 s, for 40 s on end)
  if t - (st.edgeFix or -1e9) > 12 then st.edgeN = 0 end
  if not st.phase and real and real >= 2.4 and (st.edgeN or 0) < 3 and along >= C.DRIFT_ALIGN and not atJunction and math.abs(lat) <= real + 0.6 and c.speed > 6 then
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
      if spot and gt and gt.respawnVehicle and pcall(gt.respawnVehicle, id, spot, quatFromDir(sdir, vec3(0, 0, 1))) then
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
    if mo and mo.pos and not (st and st.phase) then
      local d = p.pos:distance(vec3(mo.pos))
      if d > far then donor, far = id, d end
    end
  end
  if not donor then return end
  local spot, sdir = placeBehind(p.pos, p.dir, rnd(C.BEHIND_M[1], C.BEHIND_M[2]))
  if not spot then return end
  for _, o in pairs(all) do if o.pos:distance(spot) < 35 then return end end
  local gt = rawget(_G, 'gameplay_traffic')
  if gt and gt.respawnVehicle and pcall(gt.respawnVehicle, donor, spot, quatFromDir(sdir, vec3(0, 0, 1))) then
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
          if spot and gt and gt.respawnVehicle and pcall(gt.respawnVehicle, oid, spot, quatFromDir(sdir, vec3(0, 0, 1))) then
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
local function letGo(id)
  braking[id] = nil
  send(id, 'electrics.values.throttleOverride = nil electrics.values.brakeOverride = nil')
end
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
  for id, st in pairs(cars) do
    local o = objs[id]
    local want = 0
    if o and o.pos and o.vel and id ~= pid and id ~= tid and not st.phase and ppos:squaredDistance(vec3(o.pos)) < 22500 then
      local vel = vec3(o.vel)
      local sp = vel:length()
      local dir = flat(vel)
      if sp > 3 and dir then
        local cpos = vec3(o.pos)
        local right = vec3(dir.y, -dir.x, 0)
        for _, x in ipairs({ { P, pid }, T and T.pos and T.vel and { T, tid } or false }) do
          if x then
            local rel = vec3(x[1].pos) - cpos
            local along = rel:dot(dir)
            if along > 0 and along < C.GUARD_LOOK_M and math.abs(rel:dot(right)) < C.GUARD_LAT_M then
              local itsWay = vec3(x[1].vel):dot(dir)
              local closing = sp - itsWay
              local room = along - lengthOf(x[2]) * 0.5 - lengthOf(id) * 0.5
              -- (2026-11-09: the truck coming towards the car counted as well. In a bend its straight line ahead runs through the truck:
              -- closing 50 m/s, full brakes on an oncoming car out of nowhere)
              if itsWay > -1 and closing > 0.5 then
                local need = closing * closing / (2 * math.max(0.5, room - 2))
                if need > (braking[id] and C.GUARD_RELEASE or C.GUARD_DECEL) and not otherLane(cpos, dir, vec3(x[1].pos)) then
                  want = math.max(want, math.min(1, need / 7))
                end
              end
            end
          end
        end
      end
    end
    local was = braking[id]
    if want > 0 then
      if not was or math.abs(was - want) > 0.1 then
        if not was then dlog('car %d: emergency brake behind the truck', id) end
        braking[id] = want
        send(id, string.format('electrics.values.throttleOverride = 0 electrics.values.brakeOverride = %.2f', want))
      end
    elseif was then
      letGo(id)
    end
  end
  for id in pairs(braking) do if not cars[id] then letGo(id) end end
end

-- the loop ----------------------------------------------------------------------------------------------------

function M.update(ctx, dt)
  local t = now()
  pcall(guard, ctx, t)
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
  local center = vec3(pv:getPosition())
  local all = snapshot(center, C.SCAN_M + 200)
  local limit = ctx.roadLimit()
  local zones = ctx.zones() or {}
  local trailerId = ctx.trailerId()
  local playerId = pv:getID()
  local p = all[playerId]
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

  local seen = {}
  for _, id in pairs(list) do
    seen[id] = true
    local c = all[id]
    local st = cars[id]
    if not st then st = newDriver(); cars[id] = st end
    -- respawned (a jump): during a gap one that came back ahead of the player, on the way towards it, goes
    -- behind the player instead (the traffic spawns elsewhere while the gap lasts)
    local jumped = c and st.lastPos and c.pos:distance(st.lastPos) > C.JUMP_M
    -- (one out of the traffic pool is new to us – no jump to see: standing there is the sign it was just put down)
    local fresh = c and not st.seen and c.speed < 3
    if c then st.seen = true end
    if jumped then st.limMs, st.limC, st.capMs, st.following = nil, nil, nil, nil end   -- (a car from the pool starts afresh)
    st.lastPos = c and c.pos or nil
    -- (2026-11-09) a pass is only looked after near the player: one that fell out of that – far away, respawned, held back – stayed
    -- without its lane for good (a 49 s "pass" in the log) and drove down the middle of the road
    if st.phase == 'pass' and (jumped or not c or c.pos:distance(center) >= C.NEAR_M or t - st.t0 > C.PASS_TIMEOUT_S + 4) then
      endPass(id, st, c, false)
    end
    -- (also while a car is passing: a car popping up ahead is what made them brake hard, in game 2026-11-03)
    if jumped and p and p.dir and (t < gap.untilT or passing > 0) and gap.respawnMoved < C.GAP_RESPAWN_MOVE
       and c.dir and c.dir:dot(p.dir) < -0.5 then
      local along = (c.pos - p.pos):dot(p.dir)
      if along > 60 and along < 1400 then
        local spot, sdir = placeBehind(p.pos, p.dir, rnd(C.BEHIND_M[1], C.BEHIND_M[2]))
        local gt2 = rawget(_G, 'gameplay_traffic')
        if spot and gt2 and gt2.respawnVehicle and pcall(gt2.respawnVehicle, id, spot, quatFromDir(sdir, vec3(0, 0, 1))) then
          gap.respawnMoved = gap.respawnMoved + 1
          st.lastPos = spot
          dlog('gap: car %d respawned %.0f m ahead -> moved behind the player', id, along)
          goto next
        end
      end
    end
    -- respawned ahead of the player on its own way, in its lane: it would start there from standstill and brake
    -- everyone (the player too) – it goes behind the player instead (to catch up from there)
    if (jumped or fresh) and not flow.member[id] and p and p.dir and c and c.dir and c.dir:dot(p.dir) > 0.5 and c.speed < 4
       and t - (st.movedAt or -1e9) > 30 then
      local rel = c.pos - p.pos
      local along = rel:dot(p.dir)
      if along > 0 and along < C.AHEAD_CLEAR_M and math.abs(rel:dot(vec3(p.dir.y, -p.dir.x, 0))) < 7 then
        local spot, sdir = placeBehind(p.pos, p.dir, rnd(C.BEHIND_M[1], C.BEHIND_M[2]))
        local gt2 = rawget(_G, 'gameplay_traffic')
        if spot and gt2 and gt2.respawnVehicle and pcall(gt2.respawnVehicle, id, spot, quatFromDir(sdir, vec3(0, 0, 1))) then
          st.movedAt, st.lastPos = t, spot
          dlog('car %d respawned %.0f m ahead in the player\'s lane -> moved behind the player', id, along)
          goto next
        end
      end
    end
    if st.blinkOffAt and t >= st.blinkOffAt then st.blinkOffAt = nil; send(id, 'electrics.set_left_signal(false) electrics.set_right_signal(false)') end
    if c and c.dir and (c.pos:distance(center) < C.NEAR_M or flow.member[id]) then
      if t - st.aggrAt > 20 and not st.phase then
        st.aggrAt = t
        -- (in its lane, every time: a respawned car keeps what the AI was last told)
        send(id, string.format('ai.setAggression(%.2f) ai.driveInLane("on")', st.aggr))
      end
      if keepOnRoad(id, st, c, t, stepS, p, lengthOf(id)) then goto next end
      -- our own driver: on when the setting is, for the ordinary traffic only (no police, no chase)
      do
        local own = ctx.ownDriver and ctx.ownDriver()
        if own and not st.own and not st.phase and t - (st.ownTry or -1e9) >= C.OWN_TRY_S then
          st.ownTry = t
          local okD, data = pcall(gt.getTrafficData)
          local d = okD and type(data) == 'table' and data[id]
          if not d or d.roleName == nil or d.roleName == 'standard' then
            send(id, string.format('extensions.load("fernfahrer_driver") if fernfahrer_driver then fernfahrer_driver.acquire(%.2f) end', st.capMs or 0))
          end
        elseif st.own and not own then
          send(id, 'if fernfahrer_driver then fernfahrer_driver.release("control room") end')
        end
      end
      local warned = not st.phase and passerAhead(id, c, passers)
      local cap
      for _, z in ipairs(zones) do
        local rel = c.pos - z.pos
        local along = rel:dot(z.dir)
        if c.dir:dot(z.dir) > 0.5 and math.abs(rel:dot(vec3(z.dir.y, -z.dir.x, 0))) < 12
           and along > -C.ZONE_BEFORE_M and along < (z.len or 40) then
          cap = math.min(cap or 999, z.limit / 3.6)
        end
      end
      do
        local jc = flow.capFor(id, c, t)
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
            for _ in pairs(nodes[n].links or {}) do degree = degree + 1 end
            if degree > 2 and nodes[n].pos:distance(c.pos) <= 25 then wrong = false end
          end
          if wrong and math.abs((c.pos - centre):dot(vec3(d.y, -d.x, 0))) > (half or 3) + 2 then wrong = false end
        end
        st.wwN = wrong and (st.wwN or 0) + 1 or 0
        if st.wwN >= 2 and p and p.dir then
          st.wwN = 0
          local spot, sdir = placeBehind(p.pos, p.dir, rnd(C.BEHIND_M[1], C.BEHIND_M[2]))
          local gt = rawget(_G, 'gameplay_traffic')
          if spot and gt and gt.respawnVehicle and pcall(gt.respawnVehicle, id, spot, quatFromDir(sdir, vec3(0, 0, 1))) then
            st.capMs, st.limMs, st.limC, st.phase = nil, nil, nil, nil
            M.safety.wrong = (M.safety.wrong or 0) + 1
            dlog('car %d the wrong way on a carriageway (%s, %.0f km/h, %.0f m from the player): put back behind the player', id, st.own and 'own driver' or 'BeamNG AI', c.speed * 3.6, p.pos:distance(c.pos))
            goto next
          end
        end
      end
      if not st.phase and not cap and c.speed > 3 then
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
          if st.limN >= 1 or not st.limMs then st.limMs = linkMs end
        end
        local wanted = st.limMs and paceAhead(st, c, paceOf(st, st.limMs, lengthOf(id)), lengthOf(id)) or nil
        local li = lanesHere(c.pos, c.dir)
        if wanted then
          local y = li and li.idx < li.n and yieldSpeed(id, st, c, all, t, p)
          if y then wanted = math.min(wanted, y) end
          if warned then wanted = math.min(wanted, math.max(8, c.speed * 0.85)) end
          if st.edgeSlow and t < st.edgeSlow then wanted = math.min(wanted, math.max(8, c.speed * 0.92)) end
        end
        if moving and (bumper < keep and o.speed < c.speed + 1 or (st.following and bumper < keep + C.FOLLOW_RELEASE_M)) then
          -- (2026-11-09: a little faster than the car ahead the farther back it is, and held until well clear: it was free or capped
          -- at one distance, so the car surged up to it and braked, over and over)
          st.following = true
          local tight = bumper < C.FOLLOW_GAP_M * 0.8
          capSpeed(id, st, math.min(cap or 99, wanted or 99, tight and o.speed * 0.9 or math.max(leadMs, o.speed - 3) + math.min(3, math.max(0, bumper - keep) * 0.12)))
        else
          st.following = nil
          if cap then capSpeed(id, st, cap) elseif wanted then capSpeed(id, st, wanted) else freeSpeed(id, st) end
        end
        -- (2026-11-09: on a road with several lanes each way nobody ever overtook: "Richtungsfahrbahn" and "Autobahn" all over the log)
        if li then
          if not cap then laneBrain(id, st, c, all, t, stepS, li, o, gapM, wanted, (st.limMs or 27) * 3.6, p, p and p.dir and not lanesHere(p.pos, p.dir)) end
          st.behindT, st.stopT = 0, 0
          goto next
        end
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
        elseif not roundStopped and o.speed * 3.6 > math.min(ownLimit - C.SLOW_KMH, ownLimit * (obLen > C.TRUCK_LEN_M and C.SLOW_SHARE_TRUCK or C.SLOW_SHARE)) then
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
-- what the jams need from here
flow.init({ roadAt = roadAt, lanesHere = lanesHere, lengthOf = lengthOf, send = send, dlog = dlog, rnd = rnd, oneWay = oneWayRoad,
  forget = function(id) local st = cars[id]; if st then st.lastPos, st.capMs, st.limMs, st.limC, st.following = nil, nil, nil, nil, nil end end,
  busy = function(id) local st = cars[id]; return st and st.phase ~= nil end })

function M.onJunctionAsk(id, node, x, y, inB, outB, rank, eq, mainA, mainB, eta)
  if cars[id] then junctions.ask(id, node, x, y, inB, outB, rank, eq, mainA, mainB, eta, now()) end
end
function M.onJunctionDone(id, node) junctions.done(id, node) end

function M.onOwnDriver(id, on, why)
  local st = cars[id]
  why = tostring(why or '?')
  M.ownStats[why] = (M.ownStats[why] or 0) + 1
  if not st then return end
  if on then
    st.own = true
    if st.capMs then send(id, string.format('if fernfahrer_driver then fernfahrer_driver.setCap(%.2f) end', st.capMs)) end
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

function M.reset()
  for id in pairs(braking) do letGo(id) end
  for id, st in pairs(cars) do
    if st.phase or st.capMs then send(id, 'ai.driveInLane("on") ai.setSpeedMode("legal") electrics.set_left_signal(false)') end
    if st.own then send(id, 'if fernfahrer_driver then fernfahrer_driver.release("control room") end') end
  end
  cars, gap = {}, { nextAt = nil, untilT = 0, moved = 0, respawnMoved = 0 }
  junctions.reset()
  flow.reset()
end

return M
