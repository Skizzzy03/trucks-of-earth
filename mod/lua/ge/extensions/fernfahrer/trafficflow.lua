-- Trucks of Earth: the rhythm of the traffic (2026-11-10).
-- Rhythm: how much traffic there is follows the career's clock (rush hours, a quiet night) and comes in slow waves, not at one level.
-- The frame-rate governor in career.lua keeps the last word: this only sets the most it may bring out.
-- Jams: on a motorway (a carriageway of its own, two lanes or more), more often in the rush hours, the road ahead of the player fills up:
-- a radio message, then cars standing and creeping in both lanes, stop-and-go in waves running back up the queue, the hazard lights on at
-- the tail. There are never many cars (the machine has to carry them): the ones the player has passed are taken from behind and put on
-- the front of the queue, out of sight, so that it goes on for as long as the jam is long.
-- trafficai.lua calls M.update and M.capFor; api: roadAt, lanesHere, lengthOf, send, dlog, rnd, forget.

local M = {}
M.C = {
  TICK_S = 2,
  RHYTHM_S = 15,
  CHECK_S = 20,
  MAX_LINE_M = 2800,
  TAIL_M = { 780, 1100 },     -- the jam's end this far ahead of the player when it begins
  LEN_M = { 350, 1000 },
  MIN_LIMIT_KMH = 100,
  -- (2026-11-11, sixth Verkehrstest: the jam asked for never came - 1.1 to 1.4 km of road wanted ahead, and BeamNG.Earth had seldom loaded
  -- that much. With less: nearer, and shorter, down to these)
  TAIL_MIN_M = 380,
  LEN_MIN_M = 200,
  BUILD_M = 520,              -- cars are put there when the end of the jam is this close
  -- (2026-11-12, Verkehrstest: "da waren 2 Autos vor mir, auf der linken und auf der rechten Spur, die langsam gefahren sind - man
  -- konnte sich nicht erklären, wieso hier Stau ist". A standing queue is close: a car's length and a few metres)
  -- (2026-11-12, after Verkehrstest 18-08: "die Autos im Stau immer noch nicht dicht genug" - a car's length and 1.6 to 2.8 m)
  SPACING_M = { 6.2, 7.4 },
  PLACE_PER_LOOK = 3,
  MIN_FROM_PLAYER_M = 170,
  CONVEY_BEHIND_M = 40,       -- a car this far behind the player in the jam goes to the front (2026-11-12: 70 - only the ones right behind stay)
  CONVEY_S = 1.2,
  CONVEY_AHEAD_M = 120,       -- (into the first gap from there on, not behind the furthest one: the queue stays dense where the player is)
  CONVEY_TRIES = 10,
  -- (2026-11-12) why there is a jam: an accident at its head (two cars across the left-hand lane, hazard lights on, the traffic
  -- merging past them) or simply heavy traffic - and the radio says which
  CAUSE_SHARE = 0.6,
  CAUSE_GAP_M = 7.5,          -- the two cars of the accident this far apart (more than PLACE_STANDING_M)
  CAUSE_YAW = 0.35,           -- standing this much across (radians)
  CAUSE_ZONE_M = 40,          -- the zone before them (slow, the lane shut)
  CAUSE_LIMIT_KMH = 30,
  -- (2026-11-12: "so dass man eine große Anzahl an Autos haben kann, ohne dass sie so viel CPU-Leistung ziehen". What a car costs is its
  -- AI and its Lua each frame (the agent traffic cars have some 60 nodes, their physics is cheap) - and a car standing still with its AI
  -- switched off costs next to nothing: BeamNG lets its physics sleep. So the cars of a jam further than ECO_AHEAD_M ahead of the player
  -- or ECO_BEHIND_M behind stand, AI off, handbrake on; coming closer they wake and go on in the waves)
  ECO_ON = true,
  ECO_AHEAD_M = 100,          -- (2026-11-12: 140 / 115 / 60 - the queue denser, so more of it asleep)
  ECO_WAKE_M = 80,
  ECO_BEHIND_M = 35,
  APPROACH_M = 320,
  DECEL = 1.6,
  CREEP_MS = 1.0,
  WAVE_MS = 4,
  -- (2026-11-12, Verkehrstest 15-23: "die haben alle sehr viel Abstand gehalten" - our driver 15 to 40 m behind the next at walking pace.
  -- The wave was 350 m long and ran back at 140 km/h, so two cars 20 m apart had different speeds and the one behind fell back. Now a
  -- stop-and-go wave as on the road (WAVE_LEN_M long, running back at WAVE_BACK_MS), and the cap a little above it (CATCH_MS): the
  -- one behind closes up, the gap to the one in front keeps it back)
  WAVE_LEN_M = 600,
  WAVE_BACK_MS = 5,
  CATCH_MS = 2.5,
  CATCH_BEAMNG = 0.4,
  CATCH_FROM_M = 6,          -- (bumper to bumper: more than this ahead, and it closes up)
  HEAD_FREE_M = 70,
  COOLDOWN_S = { 240, 420 },
  MAX_S = 480,
  LOST_S = 6,
  ROAD_F = { motorway = 1.3, rural = 0.55, town = 0.75 },   -- (2026-11-14: 0.8 / 1.0 - "auf der Landstraße und auf kleinen Straßen zu viel los")
  ROAD_SMOOTH_S = 90,
  PLACE_LANE_M = 2.4,         -- a car put into the queue: nobody in its lane (this much to the side) ...
  PLACE_BEHIND_M = 12,        -- ... this far behind it, plus PLACE_BEHIND_S seconds of its speed ...
  PLACE_BEHIND_S = 3,
  PLACE_AHEAD_M = 5.8,        -- ... and this far in front (2026-11-12: 7, more than the spacing now)
  PLACE_STANDING_M = 5.5,     -- (behind it, one standing: this far is enough)
  PLACE_BUMPER_M = 1.4,       -- (and at least the two half lengths and this between them)
  -- (2026-11-12: "der Verkehr muss noch dichter werden, es müssen mehr Autos sein". With the virtual traffic the real cars are all where
  -- the player sees them - so more of them: the usual number times this)
  VIRTUAL_BASE_F = 2.0,
}
local C = M.C

local api
M.member = {}
local jam, nextJamAt, rhythmT, tickT, checkT = nil, nil, 0, 0, 0
local wantJam = false

function M.init(a) api = a end
function M.active() return jam ~= nil end
function M.jam() return jam end

-- how much traffic at this hour (1: the day's usual)
-- (2026-11-10: the evening fuller - "abends ist mehr los": the rush hour from 16 to 19 the busiest of the day, the evening only thinning out after 20)
local HOURS = { { 0, 0.3 }, { 5, 0.3 }, { 6.5, 0.7 }, { 7.5, 1.15 }, { 9, 0.95 }, { 11, 0.8 }, { 14.5, 0.95 }, { 16, 1.2 }, { 17.5, 1.3 }, { 18.5, 1.2 }, { 19.5, 1.0 }, { 20.5, 0.8 }, { 22, 0.5 }, { 24, 0.3 } }
function M.hourFactor(h)
  h = h % 24
  for i = 1, #HOURS - 1 do
    local a, b = HOURS[i], HOURS[i + 1]
    if h >= a[1] and h <= b[1] then return a[2] + (b[2] - a[2]) * (h - a[1]) / (b[1] - a[1]) end
  end
  return 0.5
end

-- the slow coming and going of traffic, within a few minutes
-- (2026-11-14, the player: "der Verkehr muss in Wellen kommen, nicht auf einmal auf einer Straße so viel los") slower, deeper waves: a few
-- minutes busier, a few quieter (about 0.5 to 1.5 of the hour's amount)
function M.pulse(t) return 1 + 0.32 * math.sin(t * 2 * math.pi / 330) + 0.14 * math.sin(t * 2 * math.pi / 113) end

-- (2026-11-11: "mehr Autos auf Autobahnen, auf Landstraßen angepasst") the kind of road the player is on: a motorway fuller, a country road
-- emptier, a town as it is - followed slowly (ROAD_SMOOTH_S), so that nobody sees the traffic change
M.roadF = 1
function M.roadKind(p, ctx)
  local limit = ctx.roadLimit and ctx.roadLimit() or 0
  if limit >= 100 and api.lanesHere(p.pos, p.dir) and api.oneWay(p.pos, p.dir) then return 'motorway' end
  if limit >= 70 then return 'rural' end
  return 'town'
end
function M.rhythmTarget(base, pool, hours, t, roadF)
  local n = math.floor(base * M.hourFactor(hours) * M.pulse(t) * (roadF or 1) + 0.5)
  return math.max(3, math.min(pool, n))
end

-- the road ahead, along the way the player is going: points with their distance, half width and lanes
-- (2026-11-11, seventh Verkehrstest: "only 12 m of road ahead", over and over, on a motorway with 2 km of it loaded. The nearest road to
-- the truck in the right-hand lane was the other carriageway - one-way the other way, so the line ended at its first node. Then the
-- road a few metres to the right, or to the left, the one that goes our way)
local function ourWay(link, back)
  return not (type(link) == 'table' and link.oneWay and tostring(link.inNode) ~= tostring(back))
end
local function roadOurWay(p)
  local right = vec3(p.dir.y, -p.dir.x, 0)
  for _, k in ipairs({ 0, 3.5, 7, -3.5, 10.5 }) do
    local centre, heading, half0, back, fwd, nodes = api.roadAt(p.pos + right * k, p.dir)
    if centre and heading and nodes and nodes[back] and nodes[fwd] then
      local link = (nodes[back].links and nodes[back].links[fwd]) or (nodes[fwd].links and nodes[fwd].links[back])
      if ourWay(link, back) then return centre, heading, half0, back, fwd, nodes end
    end
  end
end
M._roadOurWay = roadOurWay

local lineFromRoute
local function lineAhead(p, ctx)
  local centre, heading, half0, back, fwd, nodes = roadOurWay(p)
  if not centre or not heading then return lineFromRoute(ctx) end
  local pts = { { x = centre.x, y = centre.y, z = centre.z, s = 0, half = half0 or 3.5, n = 1 } }
  local prev, cur, s = back, fwd, 0
  local hx, hy = heading.x, heading.y
  for _ = 1, 500 do
    local q = nodes[cur]
    if not q then break end
    local last = pts[#pts]
    local dx, dy = q.pos.x - last.x, q.pos.y - last.y
    s = s + math.sqrt(dx * dx + dy * dy)
    local link = (nodes[prev] and nodes[prev].links and nodes[prev].links[cur]) or (q.links and q.links[prev])
    if type(link) == 'table' then
      last.half = link.inRadius or last.half
      local _, plus = (link.lanes or '+'):gsub('%+', '')
      last.n = math.max(1, plus)
      last.oneWay = link.oneWay
    end
    pts[#pts + 1] = { x = q.pos.x, y = q.pos.y, z = q.pos.z, s = s, half = last.half, n = last.n, oneWay = last.oneWay }
    if s > C.MAX_LINE_M then break end
    local best, bestDot = nil, 0.7
    for m, l in pairs(api.linksOf and api.linksOf(nodes, cur) or q.links or {}) do
      if m ~= prev and nodes[m] and not (type(l) == 'table' and l.oneWay and l.inNode ~= cur) then
        local ex, ey = nodes[m].pos.x - q.pos.x, nodes[m].pos.y - q.pos.y
        local len = math.sqrt(ex * ex + ey * ey) + 1e-9
        local dot = (ex * hx + ey * hy) / len
        if dot > bestDot then best, bestDot, hx, hy = m, dot, ex / len, ey / len end
      end
    end
    if not best then
      -- (2026-11-11, eleventh Verkehrstest: still "only 20 m of road ahead" on a motorway. What the node where it ended has, for the log)
      local why = {}
      for m, l in pairs(api.linksOf and api.linksOf(nodes, cur) or q.links or {}) do
        if m ~= prev and nodes[m] then
          local ex, ey = nodes[m].pos.x - q.pos.x, nodes[m].pos.y - q.pos.y
          local len = math.sqrt(ex * ex + ey * ey) + 1e-9
          why[#why + 1] = string.format('%.2f%s', (ex * hx + ey * hy) / len, (type(l) == 'table' and l.oneWay) and ((tostring(l.inNode) == tostring(cur)) and ' ow+' or (' ow- in=' .. tostring(l.inNode) .. ' cur=' .. tostring(cur))) or '')
        end
      end
      M.lineEnd = string.format('%d links at the end (prev %s): %s', #why, tostring(prev), table.concat(why, '; '))
      break
    end
    prev, cur = cur, best
  end
  return pts
end

-- the line along the truck's GPS route (ctx.routeAhead: positions every few metres), lanes and width from the road under each point
lineFromRoute = function(ctx)
  local rp = ctx and ctx.routeAhead and ctx.routeAhead()
  if type(rp) ~= 'table' or #rp < 10 then return nil end
  local out = {}
  for _, q in ipairs(rp) do
    local c2, _, half2, _, _, _, link2 = api.roadAt(q.pos, q.dir)
    local n = 1
    if type(link2) == 'table' and type(link2.lanes) == 'string' then
      local _, plus = link2.lanes:gsub('%+', '')
      n = link2.oneWay and math.max(1, plus) or 1
    end
    out[#out + 1] = { x = q.pos.x, y = q.pos.y, z = (c2 and c2.z) or q.pos.z, s = q.d, half = half2 or 3.5, n = n, oneWay = type(link2) == 'table' and link2.oneWay or nil }
  end
  return out
end

-- the point at distance s on the line, with direction and lanes
local function pointAt(j, s)
  local pts = j.pts
  for i = 1, #pts - 1 do
    local a, b = pts[i], pts[i + 1]
    if s <= b.s then
      local t = (s - a.s) / math.max(0.01, b.s - a.s)
      local dx, dy = b.x - a.x, b.y - a.y
      local l = math.sqrt(dx * dx + dy * dy) + 1e-9
      return a.x + dx * t, a.y + dy * t, a.z + (b.z - a.z) * t, dx / l, dy / l, a.half, a.n
    end
  end
  return nil
end

-- where on the line is this position? s, and how far beside it; nil: not on it
local function onLine(j, pos, dir)
  local pts, best, bestD, bestS, bestLat = j.pts, nil, 1e18, nil, nil
  for i = 1, #pts - 1 do
    local a, b = pts[i], pts[i + 1]
    local dx, dy = b.x - a.x, b.y - a.y
    local l2 = dx * dx + dy * dy + 1e-9
    local t = math.max(0, math.min(1, ((pos.x - a.x) * dx + (pos.y - a.y) * dy) / l2))
    local ex, ey = pos.x - (a.x + dx * t), pos.y - (a.y + dy * t)
    local d = ex * ex + ey * ey
    if d < bestD then
      bestD, best, bestS = d, i, a.s + t * (b.s - a.s)
      bestLat = math.sqrt(d)
    end
  end
  if not best then return nil end
  local a, b = pts[best], pts[best + 1]
  local dx, dy = b.x - a.x, b.y - a.y
  local l = math.sqrt(dx * dx + dy * dy) + 1e-9
  if dir and (dir.x * dx + dir.y * dy) / l < 0.7 then return nil end
  if bestLat > (a.half or 3.5) + 3 then return nil end
  return bestS, bestLat
end

M.cause = {}                  -- id -> true: a car of the accident at the head (trafficai.lua leaves it alone)
M.eco = {}                    -- id -> true: a car of the jam asleep (trafficai.lua leaves it alone too)
M.ecoStats = { slept = 0, woke = 0, max = 0, now = 0 }
local function sleepCar(id)
  if M.eco[id] then return end
  M.eco[id] = true
  M.ecoStats.slept = M.ecoStats.slept + 1
  if api.beamMode then api.beamMode(id, 'disabled') end   -- (2026-11-13: on BeamNG's own traffic object too, trafficai.beamMode)
  api.send(id, 'if fernfahrer_driver then fernfahrer_driver.release("control room") end ai.setMode("disabled") electrics.values.throttleOverride = 0 input.event("parkingbrake", 1, 1)')
end
local function wakeCar(id)
  if not M.eco[id] then return end
  M.eco[id] = nil
  M.ecoStats.woke = M.ecoStats.woke + 1
  if api.beamMode then api.beamMode(id, 'traffic') end
  api.send(id, 'electrics.values.throttleOverride = nil input.event("parkingbrake", 0, 1) ai.setMode("traffic")')
  api.forget(id)
end
-- (2026-11-13) a car of the accident released: BeamNG's traffic again
local function releaseCause(id)
  if api.beamMode then api.beamMode(id, 'traffic') end
  api.send(id, 'electrics.set_warn_signal(false) electrics.values.throttleOverride = nil input.event("parkingbrake", 0, 1) ai.setMode("traffic")')
end
local function wakeAll() for id in pairs(M.eco) do wakeCar(id) end; M.ecoStats.now = 0 end
M._wakeAll = wakeAll
function M.causeZone() return jam and jam.causeZone or nil end
local function wave(s, t)
  local k = 2 * math.pi / C.WAVE_LEN_M
  return C.CREEP_MS + C.WAVE_MS * math.max(0, math.sin(s * k + t * k * C.WAVE_BACK_MS))
end
M._wave = wave

-- the speed for this car because of the jam, nil: none. Marks who is in it
-- gap: our driver's gap to the one ahead (-1: nobody ahead; nil: BeamNG drives it). Only with room ahead does it catch up
function M.capFor(id, c, t, gap)
  if not jam or not c.dir then return nil end
  local s = onLine(jam, c.pos, c.dir)
  if not s or s > jam.head then M.member[id] = jam.placed[id] and M.member[id] or nil; return nil end
  if s < jam.tail then
    local d = jam.tail - s
    if d > C.APPROACH_M then return nil end
    return math.sqrt(C.CREEP_MS * C.CREEP_MS + 2 * C.DECEL * d)
  end
  M.member[id] = true
  local toHead = jam.head - s
  local catch = C.CATCH_MS * C.CATCH_BEAMNG      -- (BeamNG keeps its own distance, closer than it should at times: less for it)
  if gap then catch = gap < 0 and 0 or math.max(0, math.min(C.CATCH_MS, (gap - C.CATCH_FROM_M) * 0.25)) end
  if toHead < C.HEAD_FREE_M then return wave(s, t) + catch + (C.HEAD_FREE_M - toHead) * 0.4 end
  return wave(s, t) + catch
end

local function finish(ctx, why, t)
  if not jam then return end
  for id in pairs(jam.hazard) do api.send(id, 'electrics.set_warn_signal(false)') end
  for id in pairs(M.cause) do releaseCause(id); api.forget(id) end
  M.cause = {}
  wakeAll()
  M.member = {}
  api.dlog('jam over (%s): %d cars used, %d moved along', why, jam.count, jam.moved)
  if why == 'passed' and ctx.notify then ctx.notify('Verkehrsfunk: Stau zu Ende. Gute Fahrt!', 5) end
  jam = nil
  nextJamAt = t + api.rnd(C.COOLDOWN_S[1], C.COOLDOWN_S[2])
end

local function clearAt(all, x, y, r)
  for _, o in pairs(all) do
    local dx, dy = o.pos.x - x, o.pos.y - y
    if dx * dx + dy * dy < r * r then return false end
  end
  return true
end

-- a car into the jam at distance s, the given lane (0: the right-hand one). True when it went
local function place(id, s, lane, all, yaw)
  local x, y, z, tx, ty, half, n = pointAt(jam, s)
  if not x then return false end
  local w = 2 * half / math.max(1, n)
  local offset = half - w * (math.min(lane, n - 1) + 0.5)
  local px, py = x + ty * offset, y - tx * offset
  if not clearAt(all, px, py, 3) then return false end         -- (the next lane is 3.5 m away: it may be taken)
  -- (2026-11-11, the digital twin: put down standing 10 m in front of one rolling up at 30 km/h in the same lane. Room behind it in its lane,
  -- by the speed of whoever comes, and nobody right in front)
  do
    local rx, ry = ty, -tx
    -- (2026-11-12, Verkehrstest 00-15: 45 crashes in one jam, most at 0 km/h and 3 s old - put down 6 to 7 m middle to middle, enough for
    -- two cars, not for a van or a lorry. The lengths of both and a bumper gap)
    local myL = api.lengthOf and api.lengthOf(id) or 4.6
    for oid, o in pairs(all) do
      local dx, dy = o.pos.x - px, o.pos.y - py
      local along, lat = dx * tx + dy * ty, dx * rx + dy * ry
      if oid ~= id and math.abs(lat) < C.PLACE_LANE_M and math.abs((o.pos.z or z) - z) < 3.5 then
        local need = 0.5 * (myL + (api.lengthOf and api.lengthOf(oid) or 4.6)) + C.PLACE_BUMPER_M
        local rolling = (o.speed or 0) > 2
        local behind = rolling and (C.PLACE_BEHIND_M + o.speed * C.PLACE_BEHIND_S) or math.max(C.PLACE_STANDING_M, need)   -- (the queue standing behind it: its spacing is enough)
        if along > -behind and along < math.max(C.PLACE_AHEAD_M, need) then return false end
      end
    end
  end
  local gt = rawget(_G, 'gameplay_traffic')
  if not gt or not gt.respawnVehicle then return false end
  wakeCar(id)
  M.member[id] = true
  jam.placed[id] = true
  local dir = vec3(tx, ty, 0)
  if yaw then local cs, sn = math.cos(yaw), math.sin(yaw); dir = vec3(tx * cs - ty * sn, tx * sn + ty * cs, 0) end
  local at = vec3(px, py, z + 0.4)
  if api.snapGround then at = api.snapGround(vec3(px, py, z)); if not at then return false end end   -- (2026-11-12: onto the ground, not into the air)
  if not pcall(gt.respawnVehicle, id, at, quatFromDir(dir, vec3(0, 0, 1))) then
    M.member[id], jam.placed[id] = nil, nil
    return false
  end
  api.forget(id)
  -- (2026-11-14, Verkehrstest 19-53: "put down in a jam at 98 km/h" - moved by respawnVehicle, a car keeps the speed it had: one passed by the
  -- truck and brought to the front kept its 100 km/h, into the standing queue. Every car the jam puts down starts at walking pace)
  if api.holdSpeed then api.holdSpeed(id, 0) end
  return true
end

local function lanesAt(s) local _, _, _, _, _, _, n = pointAt(jam, s); return n or 2 end

-- a car of the traffic that nobody sees and that is not in the jam
local function donor(list, all, p, pid)
  -- (2026-11-14, Verkehrstest 15-35: "im Stau sind kaum Autos, eigentlich gar keine". With the virtual traffic nearly every spare real car
  -- sleeps in the pool - and those were busy to the jam. The sleeping ones first now, woken for it)
  if api.parked and api.wake and (not api.poolRoom or api.poolRoom()) then
    for id in pairs(api.parked() or {}) do
      if not M.member[id] and not M.cause[id] then return id, true end
    end
  end
  local best, far = nil, -1
  for _, id in pairs(list) do
    if id ~= pid and not M.member[id] and not M.cause[id] then
      local o = all[id]
      if o then
        local rel = o.pos - p.pos
        local d, along = rel:length(), rel:dot(p.dir)
        if (d > C.MIN_FROM_PLAYER_M or along < -40) and d > far and not api.busy(id) then best, far = id, d end
      else
        return id                              -- (out of the scan altogether)
      end
    end
  end
  return best
end

local function startJam(p, t, ctx)
  local pts = lineAhead(p, ctx)
  -- (the graph's line too short: the truck's route instead, where it is longer)
  if not pts or pts[#pts].s < C.TAIL_M[1] + 300 then
    local rp = lineFromRoute(ctx)
    if rp and (not pts or rp[#rp].s > pts[#pts].s) then pts = rp; M.fromRoute = (M.fromRoute or 0) + 1 end
  end
  if not pts then return false end
  local tail = api.rnd(C.TAIL_M[1], C.TAIL_M[2])
  local head = tail + api.rnd(C.LEN_M[1], C.LEN_M[2])
  local length = pts[#pts].s
  if length < tail + 300 then
    tail = math.max(C.TAIL_MIN_M, length - 300 - C.LEN_MIN_M)
    head = tail + math.max(C.LEN_MIN_M, math.min(head - tail, length - 20 - tail))
    if length < tail + C.LEN_MIN_M + 20 then
      if wantJam then api.dlog('jam wanted: only %.0f m of road ahead - ' .. tostring(M.lineEnd), length) end
      return false
    end
  end
  head = math.min(head, length - 20)
  jam = { pts = pts, tail = tail, head = head, born = t, built = false, nextS = tail + 8, lane = 0, placed = {}, hazard = {}, count = 0, moved = 0, convT = 0, lostT = 0 }
  M.member, M.cause = {}, {}
  local _, _, _, _, _, _, nHead = pointAt(jam, head)
  jam.why = ((nHead or 1) >= 2 and api.rnd(0, 1) < C.CAUSE_SHARE) and 'accident' or 'busy'
  api.dlog('jam: end in %.0f m, %.0f m long, %s', tail, head - tail, jam.why)
  if ctx.notify then
    local function km(m) return (string.format('%.1f', m / 1000):gsub('%.', ',')) end
    ctx.notify('Verkehrsfunk: Stau voraus in etwa ' .. km(tail) .. ' km, rund ' .. km(head - tail) .. ' km lang. '
      .. (jam.why == 'accident' and 'Grund ist ein Unfall auf dem linken Fahrstreifen.' or 'Grund ist hohes Verkehrsaufkommen.'), 10)
  end
  return true
end
M.startJam = startJam
-- (2026-11-11) the traffic lab's full-automatic test asks for one: the next time the truck is on a carriageway of several lanes, whatever the hour
function M.requestJam() wantJam = true; nextJamAt = 0 end
function M.jamWanted() return wantJam end

local function jamTick(t, p, pid, all, list, ctx)
  local ps = onLine(jam, p.pos, p.dir)
  if not ps then
    jam.lostT = jam.lostT + C.TICK_S
    if jam.lostT >= C.LOST_S then return finish(ctx, 'left the road', t) end
    return
  end
  jam.lostT = 0
  if ps > jam.head + 150 then return finish(ctx, 'passed', t) end
  if t - jam.born > C.MAX_S then return finish(ctx, 'too long', t) end
  local distance = jam.tail - ps
  if distance < C.BUILD_M then
    if not jam.built then
      jam.built = true
      if ctx.setTrafficTarget then ctx.setTrafficTarget(ctx.trafficPool and ctx.trafficPool() or 99) end
    end
    -- the accident at the head: two cars across the left-hand lane, before anything else
    if jam.why == 'accident' and not jam.causeDone then
      jam.causeTries = (jam.causeTries or 0) + 1
      local n = lanesAt(jam.head)
      local got = 0
      for k, s in ipairs({ jam.head - C.CAUSE_GAP_M, jam.head }) do
        local id = donor(list, all, p, pid)
        if id and place(id, s, n - 1, all, k == 1 and C.CAUSE_YAW or -C.CAUSE_YAW * 0.6) then
          M.member[id], jam.placed[id] = nil, nil
          M.cause[id] = true
          if api.beamMode then api.beamMode(id, 'disabled') end
          api.send(id, 'if fernfahrer_driver then fernfahrer_driver.release("control room") end ai.setMode("disabled") electrics.values.throttleOverride = 0 input.event("parkingbrake", 1, 1) electrics.set_warn_signal(true)')
          got = got + 1
        end
      end
      if got > 0 or jam.causeTries > 5 then
        jam.causeDone = true
        local x, y, _, tx, ty, half = pointAt(jam, jam.head - C.CAUSE_GAP_M - C.CAUSE_ZONE_M)
        if got > 0 and x then
          local w = 2 * half / math.max(1, n)
          jam.causeZone = { kind = 'accident', pos = vec3(x, y, 0), dir = vec3(tx, ty, 0), len = C.CAUSE_ZONE_M + C.CAUSE_GAP_M + 15,
            limit = C.CAUSE_LIMIT_KMH, block = { s0 = C.CAUSE_ZONE_M - 4, s1 = C.CAUSE_ZONE_M + C.CAUSE_GAP_M + 5, l0 = -half - 0.5, l1 = -half + w + 0.3 } }
        end
        api.dlog('jam: the accident at its head, %d cars', got)
      end
    end
    -- the cars into their places, from the end of the queue forwards
    for _ = 1, C.PLACE_PER_LOOK do
      if jam.nextS >= jam.head or jam.nextS <= ps + C.MIN_FROM_PLAYER_M then
        if jam.nextS <= ps + C.MIN_FROM_PLAYER_M then jam.nextS = ps + C.MIN_FROM_PLAYER_M + 10 else break end
      end
      local id, sleeping = donor(list, all, p, pid)
      if not id then break end
      if sleeping then api.wake(id); M.woken = (M.woken or 0) + 1 end
      if place(id, jam.nextS, jam.lane, all) then
        -- (2026-11-14, Verkehrstest 17-48: a car woken for the jam woke with the speed it fell asleep with - held at walking pace: place())
        jam.count = jam.count + 1
        if jam.nextS < jam.tail + 30 and not jam.hazard[id] then
          jam.hazard[id] = true
          api.send(id, 'electrics.set_warn_signal(true)')
        end
      end
      jam.lane = (jam.lane + 1) % math.max(1, lanesAt(jam.nextS))
      if jam.lane == 0 then jam.nextS = jam.nextS + api.rnd(C.SPACING_M[1], C.SPACING_M[2]) + math.max(0, (api.lengthOf and api.lengthOf(id) or 4.6) - 4.6) end
    end
  end
  -- (2026-11-12) asleep further off, awake near the player
  if C.ECO_ON then
    local n = 0
    for id in pairs(M.member) do
      local o = all[id]
      local s = o and o.dir and onLine(jam, o.pos, o.dir)
      if s then
        local d = s - ps
        if M.eco[id] then
          if d < C.ECO_WAKE_M and d > -C.ECO_BEHIND_M + 15 then wakeCar(id) end
        elseif (d > C.ECO_AHEAD_M or d < -C.ECO_BEHIND_M) and (o.speed or 0) < 3 then
          sleepCar(id)
        end
      end
    end
    for _ in pairs(M.eco) do n = n + 1 end
    M.ecoStats.now = n
    if n > M.ecoStats.max then M.ecoStats.max = n end
  end
  -- the player is in it: the cars it has passed go to the front
  if ps > jam.tail and t - jam.convT >= C.CONVEY_S then
    local front = ps + C.CONVEY_AHEAD_M
    for id in pairs(M.member) do
      local o = all[id]
      if o and o.dir then
        local s = onLine(jam, o.pos, o.dir)
        if s and s > front then front = s end
      end
    end
    for id in pairs(M.member) do
      local o = all[id]
      local s = o and o.dir and onLine(jam, o.pos, o.dir)
      if s and s < ps - C.CONVEY_BEHIND_M then
        jam.convT = t
        if jam.hazard[id] then api.send(id, 'electrics.set_warn_signal(false)'); jam.hazard[id] = nil end
        local at = ps + C.CONVEY_AHEAD_M
        local done = false
        for _ = 1, C.CONVEY_TRIES do
          if at >= jam.head - C.CAUSE_GAP_M - 4 then break end
          local n = lanesAt(at)
          for k = 0, n - 1 do
            local lane = (jam.lane + k) % math.max(1, n)
            if place(id, at, lane, all) then jam.moved = jam.moved + 1; jam.lane = (lane + 1) % math.max(1, n); done = true; break end
          end
          if done then break end
          at = at + api.rnd(C.SPACING_M[1], C.SPACING_M[2])
        end
        if not done and front + 8 < jam.head - C.CAUSE_GAP_M - 4 and place(id, front + 8, jam.lane, all) then jam.moved = jam.moved + 1 end
        break
      end
    end
  end
end

-- every look of trafficai.lua. p: the player's snapshot; list: the traffic's ids
function M.update(t, p, pid, all, list, ctx)
  if t - tickT < C.TICK_S then return end
  tickT = t
  if not ctx.hours then return end
  local hours = ctx.hours()
  if p and p.dir then
    local want = C.ROAD_F[M.roadKind(p, ctx)] or 1
    M.roadF = M.roadF + (want - M.roadF) * math.min(1, C.TICK_S / C.ROAD_SMOOTH_S)
  end
  if t - rhythmT >= C.RHYTHM_S and not jam and ctx.setTrafficTarget and ctx.trafficBase then
    rhythmT = t
    local base = ctx.trafficBase()
    if ctx.virtualOn and ctx.virtualOn() then base = base * C.VIRTUAL_BASE_F end
    ctx.setTrafficTarget(M.rhythmTarget(base, ctx.trafficPool and ctx.trafficPool() or 99, hours, t, M.roadF))
  end
  if not p or not p.dir then return end
  if jam then return jamTick(t, p, pid, all, list, ctx) end
  if not nextJamAt then nextJamAt = t + api.rnd(60, 150) end
  if t < nextJamAt or t - checkT < C.CHECK_S then return end
  checkT = t
  local f = M.hourFactor(hours)
  if (f < 0.6 and not wantJam) or p.speed < 15 then return end
  local limit = ctx.roadLimit and ctx.roadLimit() or 0
  if not limit or limit < C.MIN_LIMIT_KMH then return end
  local li = api.lanesHere(p.pos, p.dir)
  if not li or not api.oneWay(p.pos, p.dir) then
    if wantJam then api.dlog('jam wanted: %s', not li and 'one lane here' or 'not one-way here') end
    return
  end
  local chance = 0.03 + 0.5 * math.max(0, f - 0.7)
  if wantJam then
    if startJam(p, t, ctx) then wantJam = false end
  elseif api.rnd(0, 1) < chance then startJam(p, t, ctx) end
end

function M.reset(ctx)
  if jam then for id in pairs(jam.hazard) do api.send(id, 'electrics.set_warn_signal(false)') end end
  for id in pairs(M.cause) do releaseCause(id) end
  M.cause = {}
  wakeAll()
  jam, nextJamAt = nil, nil
  M.member = {}
end

return M
