-- Trucks of Earth: the traffic's memory of dangerous places (2026-11-11).
-- Second Verkehrstest: cars at 100 km/h stopped dead with nothing around them (something on Earth's road that is not on its graph: a
-- seam, a kerb, a pillar), and whoever came next ran into the wreck. So:
--   wrecks   a traffic car whose damage jumps is a wreck: for WRECK_S (or until it drives off / is put elsewhere) the traffic coming up
--            behind it slows down for it, as at an accident scene (a zone, as accidents.lua and events.lua make them).
--   learned  a car that crashed alone (nobody within ALONE_M) at speed adds to the spot (lat / lon, cells of CELL_M, and its heading).
--            Once a spot has SCORE_ZONE, the traffic going that way eases off to LIMIT_KMH there, every time, in every session:
--            kept in /settings/fernfahrer/hazards.json. A spot that has been driven through ZONE_OK times since its last crash is
--            trusted again a little (the score goes down), so a slowdown does not stay for ever where the cause has gone.
-- trafficai.lua calls M.crash and M.passed; career.lua M.zones (the traffic's zones), M.anchor (BeamNG.Earth's geodetic anchor).

local M = {}
M.C = {
  CELL_M = 40,
  KEEP = 400,
  WRECK_S = 90,
  WRECK_GONE_M = 25,        -- the wreck has moved this far: gone
  WRECK_BEFORE_M = 15,
  WRECK_LEN_M = 30,
  WRECK_KMH = 30,
  ALONE_M = 10,
  FAST_KMH = 70,            -- alone at this speed or more: 1 point; from SLOW_KMH: half a point
  SLOW_KMH = 40,
  -- (2026-11-12, Verkehrstest 22-57: in a town 23 crashes in one spot, 11 of them alone at 16 to 28 km/h - something of Earth's in the
  -- road. Slow crashes alone were never learned. OBST_N of them in a spot: an obstacle - a block the traffic goes round, trafficai avoidZones)
  OBST_N = 3,
  OBST_MIN_KMH = 8,
  OBST_KMH = 30,
  SCORE_ZONE = 1,
  ZONE_BEFORE_M = 20,
  ZONE_LEN_M = 45,
  LIMIT_KMH = 60,
  NEAR_M = 1500,
  ZONE_OK = 25,             -- cars through without a crash: the score goes down by OK_DROP
  OK_DROP = 0.25,
  FILE = '/settings/fernfahrer/hazards.json',
  -- (2026-11-11, fifth Verkehrstest: the crash at 103 km/h on the motorway was where the one of the fourth test was - and there Earth's
  -- road graph climbs 4.7 m in 22 m, 22 %: a bridge seam the road surface has as a step. A slope like that on a fast road is next to never
  -- real (motorways stay under 8 %); in all the tests' graphs there were 2 to 4 such links, and the cars crashed on them. Found in the
  -- graph itself now, before anybody crashes: the traffic eases off to STEP_KMH over it)
  STEP_GRADE = 0.12,
  STEP_MIN_MS = 20,         -- (only links posted at 72 km/h or more: in town a steep ramp is a ramp)
  STEP_KMH = 70,
  STEP_BEFORE_M = 60,
  STEP_AFTER_M = 20,
  STEP_PER_CALL = 2500,     -- the graph is gone through a piece at a time
  -- (and what the cars feel: a jolt up or down at speed - trafficlab.lua's sensor - is a third of a crash at the spot)
  BUMP_SCORE = 0.34,
  SAVE_S = 30,
}
local C = M.C
M.stats = { wrecks = 0, learned = 0, zonesNow = 0 }

local spots, loaded, dirty, savedAt = {}, false, false, -1e9
local wrecks = {}
local steps, scan = {}, nil

local function now() return os.clock() end
local function geo(pos)
  local a = M.anchor and M.anchor()
  if a and a.worldToGeodetic and pos then return a:worldToGeodetic(pos.x, pos.y, pos.z or 0) end
end
local function world(lat, lon)
  local a = M.anchor and M.anchor()
  if a and a.geodeticToWorld and lat and lon then local x, y, z = a:geodeticToWorld(lat, lon, 0); return vec3(x, y, z or 0) end
end
local function key(lat, lon)
  local k = C.CELL_M / 111320
  return math.floor(lat / k) .. ':' .. math.floor(lon / (k * 1.6))
end
local atan2 = math.atan2 or math.atan   -- (LuaJIT in the game; 5.3 in the simulations)
local function hdgOf(dir) return dir and atan2(dir.x, dir.y) or nil end
local function dirOf(h) return vec3(math.sin(h), math.cos(h), 0) end

local function load()
  if loaded then return end
  loaded = true
  local ok, d = pcall(jsonReadFile, C.FILE)
  if ok and type(d) == 'table' and type(d.spots) == 'table' then
    for _, s in pairs(d.spots) do
      if type(s) == 'table' and tonumber(s.lat) and tonumber(s.lon) and tonumber(s.hdg) then spots[key(s.lat, s.lon) .. ':' .. math.floor((s.hdg % (2 * math.pi)) / (math.pi / 2))] = s end
    end
  end
end
M.load = load

local function save(force)
  if not dirty or (not force and now() - savedAt < C.SAVE_S) then return end
  dirty, savedAt = false, now()
  local list, n = {}, 0
  for _, s in pairs(spots) do n = n + 1; list[n] = s end
  table.sort(list, function(a, b) return (a.last or 0) > (b.last or 0) end)
  for i = C.KEEP + 1, #list do list[i] = nil end
  pcall(jsonWriteFile, C.FILE, { v = 1, spots = list }, false)
end

-- a traffic car's damage jumped (trafficai.lua): kmh before, alone (nobody within ALONE_M)
function M.crash(id, pos, dir, kmh, alone)
  load()
  wrecks[id] = { pos = vec3(pos), dir = dir and vec3(dir) or nil, untilT = now() + C.WRECK_S }
  M.stats.wrecks = M.stats.wrecks + 1
  if not alone or not dir then return nil end
  local slow = (kmh or 0) < C.SLOW_KMH
  if slow and (kmh or 0) < C.OBST_MIN_KMH then return nil end
  local lat, lon = geo(pos)
  if not lat then return nil end
  local h = hdgOf(dir)
  local k = key(lat, lon) .. ':' .. math.floor((h % (2 * math.pi)) / (math.pi / 2))
  local s = spots[k]
  if not s then s = { lat = lat, lon = lon, hdg = h, score = 0, n = 0, ok = 0 }; spots[k] = s end
  if slow then
    s.obst = (s.obst or 0) + 1
    if s.obst == C.OBST_N then M.stats.obstacles = (M.stats.obstacles or 0) + 1 end
  else
    s.score = s.score + ((kmh or 0) >= C.FAST_KMH and 1 or 0.5)
  end
  s.n, s.ok, s.last = s.n + 1, 0, os.time()
  s.kmh = math.max(s.kmh or 0, math.floor(kmh or 0))
  M.stats.learned = M.stats.learned + 1
  dirty = true
  save(false)
  return s
end

-- a car went through a learned spot without a crash
local function passedSpot(s)
  s.ok = (s.ok or 0) + 1
  if s.ok >= C.ZONE_OK then s.ok, s.score = 0, math.max(0, s.score - C.OK_DROP); dirty = true end
end

-- the zones for the traffic near center: wrecks, and the learned spots with score enough. zone = { pos, dir, len, limit, kind, spot }
function M.zones(center)
  load()
  local out, t = {}, now()
  for id, w in pairs(wrecks) do
    local o = map and map.objects and map.objects[id]
    local gone = t > w.untilT or not o or not o.pos or vec3(o.pos):distance(w.pos) > C.WRECK_GONE_M
    if gone then wrecks[id] = nil
    elseif w.dir then
      out[#out + 1] = { pos = w.pos - w.dir * C.WRECK_BEFORE_M, dir = w.dir, len = C.WRECK_LEN_M, limit = C.WRECK_KMH, kind = 'wreck' }
    end
  end
  if center then
    for _, s in pairs(spots) do
      if (s.obst or 0) >= C.OBST_N then
        local p = world(s.lat, s.lon)
        if p and p:distance(center) < C.NEAR_M then
          local d = dirOf(s.hdg)
          -- (the place itself: trafficai blockFor finds its lane from it)
          out[#out + 1] = { pos = vec3(p.x, p.y, center.z) - d * C.ZONE_BEFORE_M, dir = d, len = C.ZONE_LEN_M, limit = C.OBST_KMH, kind = 'obstacle',
            at = vec3(p.x, p.y, center.z) }
        end
      end
      if s.score >= C.SCORE_ZONE then
        local p = world(s.lat, s.lon)
        if p and p:distance(center) < C.NEAR_M then
          local d = dirOf(s.hdg)
          out[#out + 1] = { pos = vec3(p.x, p.y, center.z) - d * C.ZONE_BEFORE_M, dir = d, len = C.ZONE_LEN_M, limit = C.LIMIT_KMH, kind = 'hazard', spot = s }
        end
      end
    end
  end
  if center then
    pcall(M.scanSteps, map and map.getMap and map.getMap() and map.getMap().nodes)
    for _, z in ipairs(steps) do
      if z.at:distance(center) < C.NEAR_M then out[#out + 1] = z end
    end
  end
  local n = 0
  for _, z in ipairs(out) do if z.kind == 'hazard' then n = n + 1 end end
  M.stats.zonesNow = n
  save(false)
  return out
end

-- trafficai.lua: a car has been through zone z (a learned one) without crashing
function M.passed(z) if z and z.spot then passedSpot(z.spot) end end

-- the road graph (map.getMap().nodes), gone through STEP_PER_CALL nodes at a call; a new graph (Earth loaded more, moved the world): again
function M.scanSteps(nodes)
  if not nodes then return end
  if not scan or scan.of ~= nodes then scan = { of = nodes, cursor = nil, found = {}, done = false } end
  if scan.done then return end
  local k, nd = scan.cursor, nil
  for _ = 1, C.STEP_PER_CALL do
    k, nd = next(nodes, k)
    if k == nil then
      scan.done, steps = true, scan.found
      M.stats.steps = #steps
      return
    end
    local a = nd.pos
    if a then
      for other, l in pairs(nd.links or {}) do
        local o = nodes[other]
        if o and o.pos and (l.speedLimit or 0) >= C.STEP_MIN_MS and tostring(k) < tostring(other) then
          local b = o.pos
          local dx, dy = b.x - a.x, b.y - a.y
          local len = math.sqrt(dx * dx + dy * dy)
          if len > 3 and math.abs(b.z - a.z) / len > C.STEP_GRADE then
            local function add(p, q)
              local d = vec3((q.x - p.x) / len, (q.y - p.y) / len, 0)
              scan.found[#scan.found + 1] = { pos = vec3(p.x, p.y, p.z) - d * C.STEP_BEFORE_M, dir = d, len = len + C.STEP_BEFORE_M + C.STEP_AFTER_M,
                limit = C.STEP_KMH, kind = 'step', grade = math.abs(b.z - a.z) / len, at = vec3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2) }
            end
            -- (a one-way link: in its direction only, from inNode; the other carriageway is a road of its own)
            if l.oneWay then
              if tostring(l.inNode) == tostring(other) then add(b, a) else add(a, b) end
            else add(a, b); add(b, a) end
          end
        end
      end
    end
  end
  scan.cursor = k
end
function M.steps() return steps end

-- trafficlab.lua's sensor: a car (or the truck) jolted up or down at speed here
function M.bump(pos, dir, kmh)
  load()
  if not dir or (kmh or 0) < C.SLOW_KMH then return nil end
  local lat, lon = geo(pos)
  if not lat then return nil end
  local h = hdgOf(dir)
  local k = key(lat, lon) .. ':' .. math.floor((h % (2 * math.pi)) / (math.pi / 2))
  local s = spots[k]
  if not s then s = { lat = lat, lon = lon, hdg = h, score = 0, n = 0, ok = 0 }; spots[k] = s end
  s.score = s.score + C.BUMP_SCORE
  s.bumps, s.ok, s.last = (s.bumps or 0) + 1, 0, os.time()
  M.stats.bumps = (M.stats.bumps or 0) + 1
  dirty = true
  save(false)
  return s
end

function M.count() local n, z = 0, 0; for _, s in pairs(spots) do n = n + 1; if s.score >= C.SCORE_ZONE then z = z + 1 end end return n, z end
function M.flush() save(true) end
function M.reset() wrecks = {} end
-- (for the simulations)
function M._clear() spots, wrecks, loaded, dirty, steps, scan = {}, {}, true, false, {}, nil end

return M
