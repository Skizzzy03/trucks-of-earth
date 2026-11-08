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
-- Meeting the truck: oncoming cars close to the player's truck move over to the right edge of their lane (instead of
--   braking: the stock AI brakes for anything whose line comes within half the two widths of its own).
-- Gaps: on a busy road nobody would get past. Every GAP_EVERY_S, when cars are queued behind the player, the
--   oncoming cars far ahead (out of sight) are held back for GAP_LEN_S, and a few of them are moved to the road behind
--   the player, driving its way (more cars behind, fewer coming): a gap, then the rest come as a bunch.
-- Drivers: each car has a temper (mostly calm, some normal, a few sporty): how hard it accelerates and brakes, how
--   long it waits behind a truck, how bold its passes are.
-- Zones: before and inside roadworks, speed cameras, police checks and accident scenes traffic slows down.
-- Diagnosis: M.debug = true (default) logs every pass and, every few seconds, why the cars behind the player do not
--   pass (beamng.log, tag fernfahrer.tai).
-- career.lua: M.update(ctx, dt); ctx: playerVeh(), trailerId(), roadLimit(), zones() -> list, protect(id), enabled()

local M = {}
M.debug = true
local accidents = require('fernfahrer/accidents')

M.C = {
  TICK_S = 0.5,
  NEAR_M = 450,
  LOOK_M = 55,              -- an obstacle this close ahead in the same lane
  LANE_W = 2.4,             -- lateral offset that still counts as "the same lane"
  SLOW_KMH = 10,            -- the obstacle at least this much slower than the limit
  MOVING_MS = 2.0,          -- slower obstacles count as standing
  STOP_WAIT_S = 6,          -- behind a standing one this long: round it slowly
  ROUND_MS = 7,             -- (25 km/h)
  FOLLOW_GAP_M = 10,
  MIN_GAIN_MS = 3.5,
  PASS_EXTRA_KMH = 40,      -- the pass speed: obstacle + this (capped by the limit + 9 km/h)
  MERGE_M = 14,
  GUARD_S = 0.12,           -- (the look at the truck's rear: often, it is about the last second)
  GUARD_LOOK_M = 95,
  GUARD_LAT_M = 2.0,
  GUARD_DECEL = 3.0,        -- needing to brake harder than this to stay clear of the truck: brakes applied
  ONCOMING_LAT_M = 7,
  SLOW_SHARE = 0.65,        -- only vehicles slower than this share of the limit are passed (a truck, a tractor)
  QUEUE_M = 40,             -- an obstacle that itself follows a slower one this close: a queue, nobody jumps it
  MEET_M = 70,              -- meeting: an oncoming vehicle this close ahead
  MEET_ROOM = 0.35,         -- ... with this much room between them (plus their half widths): no braking for it
  MEET_S = 5,
  JUMP_M = 80,              -- a car this much farther than half a second ago was respawned
  AHEAD_CLEAR_M = 700,      -- no car respawned this close ahead in the player's lane (it starts from standstill)
  SCAN_M = 1500,
  MAX_BEND_DEG = 35,
  SIDE_ROAD_DRV = 0.75,     -- a junction counts when a road of at least this drivability joins
  ABORT_TTC_S = 3.4,
  PASS_TIMEOUT_S = 24,
  COOLDOWN_S = 8,
  MAX_PASSING = 3,
  ZONE_BEFORE_M = 220,
  DODGE_M = { 15, 140 },    -- oncoming cars this far ahead of the player's truck move over
  DODGE_EXTRA = 0.55,       -- m right of their lane centre
  GAP_EVERY_S = { 30, 50 },
  GAP_LEN_S = { 30, 40 },
  GAP_RESPAWN_MOVE = 8,     -- during a gap, cars respawned ahead of the player go behind it instead (at most)
  GAP_FROM_M = 420,         -- oncoming cars farther ahead than this are held
  GAP_HOLD_MS = 2.0,
  GAP_MOVE = 3,             -- of the held ones, this many go to the road behind the player
  GAP_MOVE_FROM_M = 650,    -- (only ones this far ahead: out of sight)
  BEHIND_M = { 170, 260 },
  LOG_S = 4,
}
local C = M.C

M.TEMPERS = {
  { share = 0.55, aggr = { 0.16, 0.30 }, wait = { 5, 11 }, risk = { 0.82, 0.98 } },   -- calm
  { share = 0.33, aggr = { 0.30, 0.45 }, wait = { 2.5, 6 }, risk = { 0.68, 0.85 } },  -- normal
  { share = 0.12, aggr = { 0.45, 0.62 }, wait = { 1, 3 }, risk = { 0.56, 0.70 } },    -- sporty
}

local cars = {}
local tickT, logT = 0, 0
local gap = { nextAt = nil, untilT = 0, held = {}, moved = 0, respawnMoved = 0 }
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
    behindT = 0, aggrAt = 0 }
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
  local link = a.links and a.links[n2]
  local half = (link and (link.inRadius or link.outRadius)) or ((a.radius or 3) + (b.radius or 3)) * 0.5
  return centre, d, half, back, fwd, nodes
end

local function lateralOf(pos, dir)
  local centre, d, half = roadAt(pos, dir)
  if not centre or not d then return nil end
  return (pos - centre):dot(vec3(d.y, -d.x, 0)), half
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
  if not centre or not heading then return 0, nil end
  local start, maxBend, junctionAt = heading, 0, nil
  walk(nodes, back, fwd, heading, nodes[fwd].pos:distance(pos), dist, function(n, travelled, h, nextNode)
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
  return maxBend, junctionAt
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
      out[id] = { pos = vec3(o.pos), vel = vel, dir = dir, speed = vel:length() }
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
        local sp = gap.held[oid] and C.GAP_HOLD_MS or o.speed
        -- the closing distance during the pass is a must; the driver's risk only adds a small margin on top
        -- (bold ~15 m, careful ~95 m). risk == nil: no margin at all (the abort check while beside the obstacle –
        -- with the careful margin there every oncoming car within ~400 m stopped the pass, beamng.log 2026-11-03)
        local margin = risk and (20 + math.max(0, risk - 0.5) * 160) or 0
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
      if along > 6 and along < C.MEET_M and lat < 6 and (not bd or along < bd) then best, bd, blat = oid, along, lat end
    end
  end
  return best, bd, blat
end

-- the moves ---------------------------------------------------------------------------------------------------

local function capSpeed(id, st, ms)
  ms = math.max(1.0, ms)
  if st.capMs and math.abs(st.capMs - ms) < 0.6 then return end
  st.capMs = ms
  send(id, string.format('ai.setSpeedMode("limit") ai.setSpeed(%.2f)', ms))
end

local function freeSpeed(id, st)
  if not st.capMs then return end
  st.capMs = nil
  send(id, 'ai.setSpeedMode("legal")')
end

-- move the car's plan sideways so that it ends up `target` m right of the centre line (negative: left of it)
local function steerTo(id, c, target, over)
  local lat = lateralOf(c.pos, c.dir)
  if not lat then return end
  local err = target - lat
  if math.abs(err) < 0.3 then return end
  send(id, string.format('ai.laneChange(nil, %.1f, %.2f)', over or math.max(18, c.speed * 2.2), err))
end

local function startPass(id, st, c, passMs)
  local _, half = lateralOf(c.pos, c.dir)
  st.phase, st.t0, st.passMs, st.steerT, st.pushed = 'pass', now(), passMs, now(), nil
  st.half = half or 3.2
  st.capMs = passMs
  send(id, string.format('electrics.set_left_signal(true) ai.driveInLane("off") ai.setAggression(%.2f) ai.setSpeedMode("limit") ai.setSpeed(%.2f)',
    math.min(0.7, st.aggr + 0.15), passMs))
  steerTo(id, c, -st.half * 0.5, math.max(22, c.speed * 2.5))
end

local function endPass(id, st, c, aborted, obstacleMs)
  st.phase = nil
  st.cool = now() + (aborted and C.COOLDOWN_S * 0.7 or C.COOLDOWN_S)
  st.behindT = 0
  if c then steerTo(id, c, (st.half or 3.2) * 0.5, math.max(20, c.speed * 2)) end
  send(id, string.format('ai.driveInLane("on") ai.setAggression(%.2f) electrics.set_left_signal(false)', st.aggr))
  st.capMs = nil
  -- (aborted: just below the obstacle's speed, no full stop – the following logic then keeps the gap)
  if aborted then capSpeed(id, st, (obstacleMs or 8) * 0.85) else send(id, 'ai.setSpeedMode("legal")') end
  dlog('%s pass car %d (%.0f s)', aborted and 'ABORT' or 'done', id, now() - (st.t0 or now()))
end

-- gaps ------------------------------------------------------------------------------------------------------------

local function updateGap(t, pv, all, queued)
  if not gap.nextAt then gap.nextAt = t + rnd(C.GAP_EVERY_S[1], C.GAP_EVERY_S[2]) * 0.4 end
  local p = all[pv:getID()]
  if t < gap.untilT and p and p.dir then
    local right = vec3(p.dir.y, -p.dir.x, 0)
    for oid, o in pairs(all) do
      if not gap.held[oid] and o.dir and o.dir:dot(p.dir) < -0.5 and oid ~= pv:getID() then
        local rel = o.pos - p.pos
        local along = rel:dot(p.dir)
        if along > C.GAP_FROM_M and math.abs(rel:dot(right)) < 20 then
          local moved = false
          if gap.moved < C.GAP_MOVE and along > C.GAP_MOVE_FROM_M then
            -- out of sight far ahead: to the road behind the player, driving its way
            local spot, sdir = placeBehind(p.pos, p.dir, rnd(C.BEHIND_M[1], C.BEHIND_M[2]))
            local gt = rawget(_G, 'gameplay_traffic')
            if spot and gt and gt.respawnVehicle then
              -- (the traffic system's own respawn: its bookkeeping follows, the car starts afresh)
              local ok = pcall(gt.respawnVehicle, oid, spot, quatFromDir(sdir, vec3(0, 0, 1)))
              if ok then
                gap.moved, moved = gap.moved + 1, true
                cars[oid] = nil
                dlog('gap: car %d moved %.0f m ahead -> behind the player', oid, along)
              end
            end
          end
          if not moved then
            gap.held[oid] = true
            send(oid, string.format('ai.setSpeedMode("limit") ai.setSpeed(%.2f)', C.GAP_HOLD_MS))
          end
        end
      end
    end
  elseif next(gap.held) then
    for oid in pairs(gap.held) do send(oid, 'ai.setSpeedMode("legal")') end
    dlog('gap over: %d oncoming cars released', (function() local n = 0 for _ in pairs(gap.held) do n = n + 1 end return n end)())
    gap.held = {}
  end
  if t >= gap.untilT and t - (gap.respawnResetT or 0) > 60 then gap.respawnMoved, gap.respawnResetT = 0, t end
  if t >= gap.untilT and t > gap.nextAt and queued then
    gap.untilT = t + rnd(C.GAP_LEN_S[1], C.GAP_LEN_S[2])
    gap.nextAt = gap.untilT + rnd(C.GAP_EVERY_S[1], C.GAP_EVERY_S[2])
    gap.moved, gap.respawnMoved = 0, 0
    dlog('gap: oncoming traffic held for %.0f s', gap.untilT - t)
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
              local closing = sp - vec3(x[1].vel):dot(dir)
              local gap = along - lengthOf(x[2]) * 0.5 - lengthOf(id) * 0.5
              if closing > 0.5 then
                local need = closing * closing / (2 * math.max(0.5, gap - 2))
                if need > C.GUARD_DECEL then want = math.max(want, math.min(1, need / 5)) end
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
  local playerIsTruck = trailerId ~= nil or lengthOf(playerId) > 7
  local passing, queued = 0, false
  for _, st in pairs(cars) do if st.phase == 'pass' then passing = passing + 1 end end
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
    st.lastPos = c and c.pos or nil
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
    if (jumped or fresh) and p and p.dir and c and c.dir and c.dir:dot(p.dir) > 0.5 and c.speed < 4
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
    if c and c.dir and c.pos:distance(center) < C.NEAR_M and not gap.held[id] then
      if t - st.aggrAt > 20 and not st.phase then
        st.aggrAt = t
        send(id, string.format('ai.setAggression(%.2f)', st.aggr))
      end
      local cap
      for _, z in ipairs(zones) do
        local rel = c.pos - z.pos
        local along = rel:dot(z.dir)
        if c.dir:dot(z.dir) > 0.5 and math.abs(rel:dot(vec3(z.dir.y, -z.dir.x, 0))) < 12
           and along > -C.ZONE_BEFORE_M and along < (z.len or 40) then
          cap = math.min(cap or 999, z.limit / 3.6)
        end
      end

      -- meeting the truck: an oncoming car near it moves over to the right edge of its lane
      if p and p.dir and playerIsTruck and not st.phase and c.dir:dot(p.dir) < -0.6 then
        local rel = c.pos - p.pos
        local along = rel:dot(p.dir)
        if along > C.DODGE_M[1] and along < C.DODGE_M[2] and math.abs(rel:dot(vec3(p.dir.y, -p.dir.x, 0))) < 9 then
          if not st.dodged or t - st.dodged > 6 then
            st.dodged = t
            local _, half = lateralOf(c.pos, c.dir)
            steerTo(id, c, (half or 3) * 0.5 + C.DODGE_EXTRA, math.max(12, math.min(along * 0.5, 40)))
          end
        end
      end

      -- meeting anyone (the player's truck, another car): the stock AI brakes – down to standing, and then it
      -- reverses – for an oncoming vehicle whose line comes within half their two widths of its own, though their
      -- real paths pass each other. With room between them as they are (their actual positions) and nobody ahead in
      -- its lane, it stops minding oncoming vehicles for the moment of meeting.
      if not st.phase then
        local mid, md, mlat = meeting(id, c, all)
        local room = mid and (lengthOf(mid) > 7 and 1.3 or 0.95) + 0.95 + C.MEET_ROOM
        if mid and mlat >= room and not obstacleAhead(id, c, all, 40 + c.speed * 5.5) then
          if not st.meetUntil then send(id, 'ai.setAvoidCars("off")') end
          st.meetUntil = t + math.min(C.MEET_S, md / math.max(5, c.speed + all[mid].speed) + 1.5)
        end
      end
      -- (2026-11-08: and it ends the moment someone is ahead in its lane – with its eyes off the cars for up to 5 s, and a
      -- line of oncoming cars renewing that, it ran into the back of the truck)
      if st.meetUntil and (t > st.meetUntil or st.phase or obstacleAhead(id, c, all, 30 + c.speed * 3.5)) then
        st.meetUntil = nil
        send(id, 'ai.setAvoidCars("on")')
      end

      if st.phase == 'pass' then
        local tgt = all[st.target]
        if not tgt then endPass(id, st, c, false); goto next end
        local ahead = (c.pos - tgt.pos):dot(tgt.dir or c.dir)
        if ahead > C.MERGE_M then endPass(id, st, c, false); goto next end
        if t - st.t0 > C.PASS_TIMEOUT_S then endPass(id, st, c, true, tgt.speed); goto next end
        -- an oncoming car turns up (often one just respawned ahead): still behind the obstacle's middle -> abort,
        -- drop back; already level with it or past -> pull through (a bit faster), unless it is really close
        local olen = st.targetLen or 5
        local need = math.max(0, olen * 0.5 - ahead) + C.MERGE_M
        local closeT = need / math.max(1, c.speed - tgt.speed)
        local onc = oncomingBlock(id, c, all, c.speed, math.min(C.ABORT_TTC_S, closeT + 1), nil)
        if onc then
          if ahead < -olen * 0.25 then
            endPass(id, st, c, true, tgt.speed)
            goto next
          elseif not st.pushed then
            st.pushed = true
            send(id, string.format('ai.setSpeed(%.2f) ai.setAggression(%.2f)', (st.passMs or c.speed) + 3, math.min(0.8, st.aggr + 0.3)))
            dlog('car %d pulls through (oncoming %.0f m)', id, onc)
          end
        end
        -- (the plan keeps the offset; only when the car has drifted back right for a while, a gentle correction –
        -- every laneChange adds to the planned offset, so they are not repeated each tick)
        do
          local lat = lateralOf(c.pos, c.dir)
          local target = -(st.half or 3.2) * 0.5
          if lat and lat > target + 0.9 and t - (st.steerT or 0) > 2.5 then
            st.steerT = t
            send(id, string.format('ai.laneChange(nil, 30, %.2f)', (target - lat) * 0.5))
          end
        end
        goto next
      end

      do
        local oid, gapM = obstacleAhead(id, c, all, math.max(C.LOOK_M, 30 + c.speed * 3.5))
        local obLen = oid and lengthOf(oid) or 0
        if oid and trailerId and oid == trailerId and all[playerId] then oid = playerId end
        local o = oid and all[oid]
        local moving = o and o.speed >= C.MOVING_MS
        -- following a moving vehicle: never faster than it once the room left is what slowing down to its speed takes
        -- (a stopped one: the stock AI stops and passes). (2026-11-08: bumper to bumper, and the speed difference counts)
        local bumper = o and (gapM - obLen * 0.5 - 2.3) or 0
        local closing = o and math.max(0, c.speed - o.speed) or 0
        if moving and bumper < C.FOLLOW_GAP_M * 0.8 + c.speed * 0.9 + closing * closing / 5 and o.speed < c.speed + 1 then
          capSpeed(id, st, math.min(cap or 99, o.speed * (bumper < C.FOLLOW_GAP_M * 0.8 and 0.9 or 1.0)))
        elseif cap then
          capSpeed(id, st, cap)
        else
          freeSpeed(id, st)
        end
        local why
        -- (the look far ahead was for the speed only: overtaking is decided close behind, as before)
        if not o or gapM >= C.LOOK_M then st.behindT, st.stopT = 0, 0; goto next end
        if oid == playerId then queued = true end
        -- a standing obstacle (the player stopped at the roadside, a breakdown): the stock AI waits behind it for
        -- ever when it does not fit past in its lane (two cars stood a minute behind the player, 2026-11-03) –
        -- after STOP_WAIT_S it goes round slowly, with the same checks as a pass
        if not moving then st.stopT = (st.stopT or 0) + stepS else st.stopT = 0 end
        local roundStopped = not moving and st.stopT >= C.STOP_WAIT_S and gapM >= 5
        if not moving and not roundStopped then why = string.format('Hindernis steht (%.0f/%d s)', st.stopT, C.STOP_WAIT_S)
        elseif cap and not roundStopped then why = 'Zone'   -- (round a standing one even at an accident scene)
        elseif not limit then why = 'kein Limit bekannt'
        elseif limit >= 110 then why = 'Autobahn'
        elseif st.cool and t < st.cool then why = 'Pause nach Überholen'
        elseif not roundStopped and o.speed * 3.6 > math.min(limit - C.SLOW_KMH, limit * C.SLOW_SHARE) then
          why = string.format('Vordermann nicht langsam genug (%.0f von %d)', o.speed * 3.6, limit)
        elseif oid ~= playerId then
          -- a queue: the car ahead follows a slower one itself – wait (only the one behind the slow vehicle passes)
          local qid, qgap = obstacleAhead(oid, o, all)
          if qid and qgap < C.QUEUE_M then why = 'Kolonne' end
        end
        if why then
          st.behindT = 0
        else
          st.behindT = st.behindT + stepS
          if st.behindT < st.wait and not roundStopped then why = string.format('wartet %.0f/%.0f s', st.behindT, st.wait)
          elseif passing >= C.MAX_PASSING then why = 'schon 3 überholen'
          elseif gapM < 5 then why = 'zu dicht dran'
          end
        end
        if not why then
          local olen = lengthOf(oid)
          if oid == playerId and trailerId then olen = olen + lengthOf(trailerId) + 1 end
          local passMs = roundStopped and C.ROUND_MS or math.min(limit / 3.6 + 2.5, o.speed + C.PASS_EXTRA_KMH / 3.6)
          if passMs - o.speed < C.MIN_GAIN_MS then why = 'kein Tempoüberschuss'
          else
            local passDist = gapM + olen + C.MERGE_M + 6
            local tp = passDist / (passMs - o.speed) + 2
            local need = passMs * tp + 30
            local bend, junctionAt = roadAhead(c.pos, c.dir, need)
            local block = oncomingBlock(id, c, all, passMs, tp, st.risk)
            if bend > C.MAX_BEND_DEG then why = string.format('Kurve %.0f°', bend); st.behindT = st.wait * 0.7
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
    ::next::
  end
  pcall(updateGap, t, pv, all, queued)
  for id in pairs(cars) do if not seen[id] then cars[id] = nil end end
end

function M.stats()
  local n, p = 0, 0
  for _, st in pairs(cars) do n = n + 1; if st.phase == 'pass' then p = p + 1 end end
  local held = 0
  for _ in pairs(gap.held) do held = held + 1 end
  return { cars = n, passing = p, held = held }
end

function M.reset()
  for id in pairs(braking) do letGo(id) end
  for id, st in pairs(cars) do
    if st.phase or st.capMs then send(id, 'ai.driveInLane("on") ai.setSpeedMode("legal") electrics.set_left_signal(false)') end
  end
  for id in pairs(gap.held) do send(id, 'ai.setSpeedMode("legal")') end
  cars, gap = {}, { nextAt = nil, untilT = 0, held = {}, moved = 0, respawnMoved = 0 }
end

return M
