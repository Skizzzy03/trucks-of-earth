-- Trucks of Earth: the traffic lab (2026-11-11).
-- A test drive that measures the traffic: the truck drives itself (BeamNG.Earth's autodrive, a destination 25-70 km away is set when
-- there is none, a new one when it arrives), and for as long as the test runs (25 minutes unless told otherwise) every traffic car
-- near the player is watched once a second. Written to /settings/fernfahrer/lab/<date>.json (every five minutes and at the end) and
-- read by tools/lab_report.js, which turns it into a report with a score – the same route again after a change shows what it did.
--
-- What is measured (all of it about what the player would see):
--   flow       free cars (nobody in front of them in their lane): their speed as a share of the limit; free and slow for no reason
--   distance   time gaps under TAILGATE_S; hard braking (deceleration over HARD_BRAKE), emergency braking (over PANIC_BRAKE)
--   standing   cars standing longer than STUCK_S with nobody standing in front of them (at a junction or out on the road)
--   road       cars beside the road (OFF_M over the edge) or left of the centre line on a two-way road (WRONG_M) for a few seconds
--   crashes    a car's damage going up by more than CRASH_DMG
--   lanes      roads with several lanes one way: which lane the cars use, lane changes; wide carriageways without lane data
--   pop-in     a car appearing out of nowhere (respawned) closer than POPIN_M to the player
--   load       frames per second, ms per frame of the traffic AI and of the whole mod, how many cars drive
-- Also kept, for the simulator at home: the cars' tracks every TRACK_S (near the player) and the piece of road graph driven through.
-- trafficai.lua reports every line it logs (M.tap) – counted by kind. Started and stopped by fernfahrer_career.labStart / labStop
-- (Strg+Umschalt+V, or the console).
--
-- (2026-11-11) The full-automatic test (Strg+Umschalt+V, fernfahrer_career.labAuto): AUTO_MIN minutes in SCENES - each with its hour of
-- the day (the career's clock is set to it, the traffic follows the hour as always) and its kind of route (over the country roads from
-- village to village, or the fast one over the motorway), one of them with a jam asked for (trafficflow.requestJam). The scene is in every
-- window, the report splits by it. The route kind and the clock are put back at the end.
-- More sensors from then on, for what the score does not show:
--   black box    every BOX_S the vehicles near the truck (position, height, speed, vertical speed, heading, our driver or not, why);
--                a crash keeps the BOX_KEEP_S that led up to it - the simulator at home replays it
--   jolts        a vehicle's vertical speed jumping at speed (a step in the road surface, a seam on a bridge): an event, and hazards.bump
--   near misses  closing on the one in front with under NEAR_TTC_S to go
--   junctions    cars through a node of three roads or more: how many, ours or BeamNG's, stopped there; two crossing in one at once
--   gaps, pace   the time gaps behind the one in front and the free cars' pace / limit, as histograms by kind of road
--   the truck    tailgated (under a second behind it), overtaken

local M = {}
M.C = {
  SAMPLE_S = 1,
  WINDOW_S = 10,
  TRACK_S = 2,
  NEAR_M = 600,
  TRACK_M = 400,
  GRAPH_S = 15,
  GRAPH_M = 1500,
  GRAPH_PER_FRAME = 4000,
  SAVE_S = 120,             -- (2026-11-11: the game crashed at minute 28, the last five minutes were lost)
  PROGRESS_S = 300,
  DEFAULT_MIN = 25,
  ROUTE_KM = { 25, 70 },
  ROUTE_FAST_KM = { 45, 100 },  -- (2026-11-11: a motorway scene - the route for 30 km went over country roads all the way; farther: more likely the motorway)
  LEADER_M = 90,
  LANE_SIDE_M = 1.8,
  FREE_S = 3.5,             -- nobody in the lane ahead within this many seconds (at least 40 m): free
  SLOW_FREE = 0.7,          -- free and slower than this share of the limit, out on the road: hesitating
  JUNCTION_M = 35,
  TAILGATE_S = 0.8,
  HARD_BRAKE = 4.5,
  PANIC_BRAKE = 7.0,
  STOP_MS = 0.5,
  STUCK_S = 25,
  OFF_M = 1.0,
  WRONG_M = -0.8,
  ROAD_HOLD_S = 3,
  CRASH_DMG = 80,
  JUMP_M = 60,
  POPIN_M = 220,
  PLAYER_STUCK_S = 90,
  -- (2026-11-11, after the first test: the cars of the start counted as popping up; one pile-up was 13 crashes; 86 % of the "free" cars had just
  -- been put down and were still speeding up – flow is now judged on cars that have been driving for a while)
  WARMUP_S = 60,
  CRASH_MERGE_S = 15,
  YOUNG_S = 20,
  SETTLE_S = 1.5,           -- a car just put down: no hard brake counted for this long
  -- (2026-11-11) the full-automatic test
  AUTO_MIN = 36,
  -- (2026-11-12, for the virtual traffic: what a car costs. The last scene raises the number of cars driving step by step, PERF_STEP_S each,
  -- whatever the frame rate; the windows keep the frame rate, the worst frame and how many were put down)
  PERF_STEP_S = 50,
  -- (2026-11-12) the full-automatic test drives with the virtual traffic (virtual.lua) - to try it out
  VIRTUAL = true,
  SCENES = {
    { at = 0, key = 'land_morning', hour = 7.5, route = 'land', text = 'Landstraße am Morgen, Berufsverkehr' },
    { at = 8, key = 'land_noon', hour = 12.5, route = 'land', text = 'Landstraße zur Mittagszeit' },
    { at = 15, key = 'motorway_evening', hour = 17.25, route = 'fast', jam = 3, needs = 'motorway', text = 'Autobahn im Feierabendverkehr, mit Stau' },
    { at = 23, key = 'motorway_night', hour = 23.5, route = 'fast', needs = 'motorway', text = 'Autobahn bei Nacht' },
    { at = 30, key = 'perf', hour = 12.5, route = 'fast', perf = { 4, 8, 12, 16, 20, 99 }, text = 'Leistungsmessung: Schritt für Schritt mehr Autos' },
  },
  -- (2026-11-11, ninth Verkehrstest: "kaum Autobahn gefahren" - the motorway scenes began by the clock, the truck still on country roads, and
  -- from there it took longer than both scenes to reach one. A motorway scene begins once the truck is on a motorway (a limit of
  -- MOTORWAY_KMH or more for MOTORWAY_S); until then it is on its way there with the fast route, at most APPROACH_MAX_S, and the test
  -- runs that much longer)
  MOTORWAY_KMH = 105,
  MOTORWAY_S = 10,
  APPROACH_MAX_S = 720,
  SWITCH_S = 40,            -- after a new destination in the middle of a drive: the autodrive going off is ours, not the player taking over
  -- the black box
  BOX_S = 0.25,
  BOX_M = 250,
  BOX_KEEP_S = 8,
  BOX_AFTER_S = 1.5,
  BOX_MAX = 30,
  BOX_AROUND_M = 80,
  -- jolts
  BUMP_DVZ = 2.0,
  BUMP_MS = 15,
  BUMP_REPEAT_S = 3,
  BUMP_QUIET_S = 5,         -- (after a jump - put elsewhere, dropped onto the road - a while without)
  -- near misses
  NEAR_TTC_S = 1.5,
  NEAR_CLOSE_MS = 3,
  NEAR_REPEAT_S = 10,
  -- junctions
  JPASS_M = 15,
  JCONFLICT_COS = 0.7,
  JCONFLICT_REPEAT_S = 10,
  TAIL_TRUCK_S = 1.0,
  HEADWAY_S = { 0.5, 1, 1.5, 2, 3 },
  SHARE_BINS = { 0.5, 0.7, 0.85, 0.95, 1.05, 1.15 },
}
local C = M.C
M.on = false

local api
local run

local function now() return os.clock() end
local function r1(x) return math.floor(x * 10 + 0.5) / 10 end
local function r2(x) return math.floor(x * 100 + 0.5) / 100 end
local function flat(v) local l = math.sqrt(v.x * v.x + v.y * v.y); if l < 1e-3 then return nil end return vec3(v.x / l, v.y / l, 0) end
local atan2 = math.atan2 or math.atan
-- the kind of road by its limit (as trafficflow.roadKind)
local function kindOf(lim)
  local kmh = (lim or 0) * 3.6
  if kmh >= 105 then return 'motorway' elseif kmh > 55 then return 'rural' end
  return 'town'
end
local function bin(edges, x)
  for i, e in ipairs(edges) do if x < e then return i end end
  return #edges + 1
end
local function count(tbl, kind, edges, x)
  local h = tbl[kind]
  if not h then h = {}; for i = 1, #edges + 1 do h[i] = 0 end; tbl[kind] = h end
  local i = bin(edges, x)
  h[i] = h[i] + 1
end

function M.attach(a) api = a end

local function path()
  if FS and FS.directoryExists and FS.directoryCreate and not FS:directoryExists('/settings/fernfahrer/lab/') then
    pcall(function() FS:directoryCreate('/settings/fernfahrer/lab/', true) end)
  end
  return string.format('/settings/fernfahrer/lab/%s.json', os.date('%Y-%m-%d_%H-%M'))
end

local function newWindow()
  return { frames = 0, real = 0, ai = 0, mod = 0, near = 0, samples = 0, freeSum = 0, freeN = 0, slowFree = 0, tailgate = 0,
    hard = 0, stopped = 0, multi = 0, own = 0, passing = 0, pKmh = 0, pLim = 0, pN = 0, lanesUnknown = 0, wide = 0, jam = 0,
    nearMiss = 0, tailTruck = 0, inJunction = 0, conflicts = 0, bumps = 0, blockHits = 0, fell = 0, worst = 0, puts = 0 }
end

M.WINDOW_COLS = { 't', 'near', 'active', 'fps', 'aiMs', 'modMs', 'free', 'freeN', 'slowFree', 'tailgate', 'hardBrake', 'stopped',
  'playerKmh', 'playerLimitKmh', 'multiLane', 'own', 'passing', 'wideNoLanes', 'jam',
  'scene', 'hour', 'roadF', 'nearMiss', 'tailTruck', 'inJunction', 'conflicts', 'bumps', 'blockHits', 'fell', 'worstMs', 'puts', 'virt' }
M.BOX_COLS = { 't', 'id', 'x', 'y', 'z', 'v', 'vz', 'hdg', 'own', 'why' }
M.TRACK_COLS = { 't', 'id', 'x', 'y', 'v', 'lim', 'lat', 'lane', 'own', 'phase', 'lorry', 'cap', 'age', 'why', 'dvt', 'thr', 'gap', 'dwhy' }

local function event(kind, id, pos, extra)
  if not run then return end
  local e = { t = r1(run.simT), kind = kind, id = id or 0 }
  if pos then e.x, e.y = r1(pos.x), r1(pos.y) end
  if extra then for k, v in pairs(extra) do e[k] = v end end
  run.events[#run.events + 1] = e
  run.counts[kind] = (run.counts[kind] or 0) + 1
end

-- trafficai.lua's log lines, counted by kind (the format string itself is the kind)
local function tap(fmt)
  if not run or type(fmt) ~= 'string' then return end
  local k = fmt:gsub('%%[%-%d%.]*[dsf]', '#'):sub(1, 60)
  run.tai[k] = (run.tai[k] or 0) + 1
end

function M.mark(name, d)
  if not run then return end
  local w = run.win
  w.mod = w.mod + d
  if name == 'trafficAI' then w.ai = w.ai + d end
end

local function trafficIds()
  local gt = rawget(_G, 'gameplay_traffic')
  if not gt or not gt.getTrafficList then return {} end
  local ok, list = pcall(gt.getTrafficList)
  local set = {}
  if ok and type(list) == 'table' then for _, id in pairs(list) do set[id] = true end end
  return set
end

local function nearJunction(nodes, back, fwd, pos)
  if not nodes then return false end
  for _, n in ipairs({ back, fwd }) do
    local nd = n and nodes[n]
    if nd and nd.pos then
      local deg = 0
      for _ in pairs(nd.links or {}) do deg = deg + 1 end
      if deg > 2 and nd.pos:distance(pos) <= C.JUNCTION_M then return true, tostring(n), nd.pos end
    end
  end
  return false
end

-- the piece of road graph around the player, a few thousand nodes a frame
local function graphStep(ppos)
  local g = run.graph
  -- (Earth moves the world's origin now and then: a new part of the graph from there on, the coordinates do not fit together)
  local anchor = api.anchor and api.anchor()
  if anchor ~= g.anchor then
    g.anchor = anchor
    g.part = { t = r1(run.simT), anchor = tostring(anchor), nodes = {}, edges = {} }
    g.parts[#g.parts + 1] = g.part
    g.seen, g.active = {}, false
    if #g.parts > 1 then event('rebase', 0, nil, { part = #g.parts }) end
  end
  local m = map and map.getMap and map.getMap()
  local nodes = m and m.nodes
  if not nodes then return end
  if not g.active then
    if run.simT - g.lastAt < C.GRAPH_S then return end
    g.active, g.of, g.cursor, g.center = true, nodes, nil, ppos
  elseif g.of ~= nodes then
    g.of, g.cursor = nodes, nil                     -- (Earth sent a new graph: from the start again)
  end
  local r2m = C.GRAPH_M * C.GRAPH_M
  local cx, cy = g.center.x, g.center.y
  local k, nd = g.cursor, nil
  for _ = 1, C.GRAPH_PER_FRAME do
    k, nd = next(nodes, k)
    if k == nil then g.active, g.lastAt = false, run.simT; return end
    local p = nd.pos
    if p then
      local dx, dy = p.x - cx, p.y - cy
      if dx * dx + dy * dy < r2m then
        local name = tostring(k)
        if not g.part.nodes[name] then g.part.nodes[name] = { r1(p.x), r1(p.y), r1(p.z), r1(nd.radius or 0) }; g.nNodes = g.nNodes + 1 end
        for other, l in pairs(nd.links or {}) do
          local o = tostring(other)
          local key = name < o and (name .. '|' .. o) or (o .. '|' .. name)
          if not g.seen[key] then
            g.seen[key] = true
            g.part.edges[#g.part.edges + 1] = { name, o, r2(l.inRadius or l.outRadius or 0), r1(l.speedLimit or 0), l.oneWay and 1 or 0,
              type(l.lanes) == 'string' and l.lanes or '', r2(l.drivability or 0), tostring(l.inNode or '') }
          end
        end
      end
    end
  end
  g.cursor = k
end

local function save(final)
  if not run then return end
  local w = run.windows
  local s = { minutes = r1(run.simT / 60), windows = #w, cars = run.carsSeen, events = run.counts }
  local fps, ai, free, fn = 0, 0, 0, 0
  for _, row in ipairs(w) do fps = fps + row[4]; ai = ai + row[5]; free = free + row[7] * row[8]; fn = fn + row[8] end
  if #w > 0 then s.fps, s.aiMs = r1(fps / #w), r2(ai / #w) end
  if fn > 0 then s.freeFlow = r2(free / fn) end
  s.km = r1(run.odo / 1000)
  local d = { lab = 1, started = run.started, final = final or false, plannedMin = run.minutes, meta = run.meta, summary = s,
    windowCols = M.WINDOW_COLS, windows = w, events = run.events, tai = run.tai, laneUse = run.laneUse,
    trackCols = M.TRACK_COLS, tracks = run.tracks,
    graph = { parts = run.graph.parts }, put = api.tai() and api.tai().put or nil, hazards = api.hazards and api.hazards() or nil,
    boxCols = M.BOX_COLS, boxes = run.boxes, junctions = run.junctions, headway = run.headway, share = run.share,
    headwayBins = C.HEADWAY_S, shareBins = C.SHARE_BINS, passTruck = run.passTruck,
    avoid = api.tai() and api.tai().avoid or nil,
    virtual = api.tai() and api.tai().virt and api.tai().virt.stats or nil,
    own = api.tai() and api.tai().ownTotal or nil, slowVehicles = api.tai() and api.tai().slowVehicle and api.tai().slowVehicle.count or 0, gasse = api.tai() and api.tai().laneStats and api.tai().laneStats.gasse or 0 }
  local ok, err = pcall(jsonWriteFile, run.file, d, false)
  if not ok then log('W', 'fernfahrer', 'lab: could not write ' .. run.file .. ': ' .. tostring(err)) end
  return s
end

-- a destination 25-70 km away (the cities the jobs go to), for the autodrive
local function pickDestination()
  local h = api.here()
  if not h then return nil end
  local list, far, fd = {}, nil, nil
  for _, c in ipairs(api.cities() or {}) do
    local d = api.haversine(h.lat, h.lon, c[2], c[3]) / 1000
    local span = (run and run.auto and api.routeMode and api.routeMode() == 'fast') and C.ROUTE_FAST_KM or C.ROUTE_KM
    if d >= span[1] and d <= span[2] then list[#list + 1] = c end
    if d > 5 and d < 150 and (not fd or d > fd) then far, fd = c, d end
  end
  local c = #list > 0 and list[math.random(#list)] or far
  if not c then return nil end
  return { lat = c[2], lon = c[3] }, c[1]
end

local function drive(t)
  local r = run.route
  local on = api.autodriveOn()
  local pv = api.playerVeh()
  local speed = pv and vec3(pv:getVelocity()):length() or 0
  -- (a new scene with another kind of route: a new destination now, while driving)
  if r.reroute and (on or not r.wasOn) then
    r.reroute = nil
    local place, name = pickDestination()
    if place then
      r.pickedAt, r.switchAt = t, t
      api.navTo(place, name)
      run.meta.destinations[#run.meta.destinations + 1] = name
      event('destination', 0, nil, { name = name, scene = run.auto and run.auto.idx or 0 })
    end
    return
  end
  if on then
    if r.manual then r.manual = nil; run.meta.manualBack = r1(run.simT) end   -- (it was only off for a moment: "put right on the spot")
    r.wasOn, r.offT = true, nil
    if speed < C.STOP_MS then
      r.stillT = (r.stillT or 0) + C.SAMPLE_S
      if r.stillT >= C.PLAYER_STUCK_S and not r.stuckSaid then r.stuckSaid = true; event('playerStuck', 0, pv and vec3(pv:getPosition())) end
    else r.stillT, r.stuckSaid = 0, nil end
    return
  end
  if r.manual then return end
  if r.manualAt and run.simT - r.manualAt < 10 then return end
  -- (the autodrive went off on the new route: put on again)
  if r.switchAt and t - r.switchAt < C.SWITCH_S and api.hasRoute() then
    if t - (r.toggledAt or -1e9) > 6 then r.toggledAt = t; api.autodriveToggle() end
    return
  end
  -- (taken over while moving: the player drives, the lab only watches)
  if r.wasOn and speed > 3 then r.manual, r.manualAt = true, run.simT; run.meta.manual = r1(run.simT); api.notify('Verkehrstest: Du fährst selbst – gemessen wird weiter.', 5); return end
  r.offT = (r.offT or 0) + C.SAMPLE_S
  if r.offT < 3 then return end
  if not api.hasRoute() or r.wasOn then
    if t - (r.pickedAt or -1e9) < 25 then return end
    local place, name = pickDestination()
    if not place then if not r.noDest then r.noDest = true; api.notify('Verkehrstest: kein Ziel gefunden – bitte ein Navi-Ziel setzen.', 8) end return end
    r.pickedAt, r.wasOn, r.reroute = t, false, nil
    api.navTo(place, name)
    run.meta.destinations[#run.meta.destinations + 1] = name
    event('destination', 0, nil, { name = name })
    return
  end
  if t - (r.toggledAt or -1e9) > 6 then r.toggledAt = t; api.autodriveToggle() end
end

-- the full-automatic test: the next scene when its time has come
local function sceneTick()
  local a = run.auto
  if not a then return end
  local nx = C.SCENES[a.idx + 1]
  -- (on a motorway now?)
  if (api.limitKmh() or 0) >= C.MOTORWAY_KMH then a.mwT = (a.mwT or 0) + C.SAMPLE_S else a.mwT = 0 end
  if nx and nx.needs == 'motorway' and run.simT >= nx.at * 60 + (a.shift or 0) and a.mwT < C.MOTORWAY_S then
    if not a.approach then
      a.approach = run.simT
      if api.setRouteMode then pcall(api.setRouteMode, 'fast') end
      run.route.reroute = true
      event('approach', 0, nil, { key = nx.key })
      api.notify('🧪 Verkehrstest: auf dem Weg zur Autobahn – die nächste Szene beginnt dort.', 6)
    end
    if run.simT - a.approach < C.APPROACH_MAX_S then return end
  end
  if a.approach and nx and nx.needs == 'motorway' and run.simT >= nx.at * 60 + (a.shift or 0) then
    local waited = run.simT - a.approach
    a.shift, a.approach = (a.shift or 0) + waited, nil
    run.minutes = run.minutes + waited / 60
    run.meta.approachS = r1((run.meta.approachS or 0) + waited)
  end
  if nx and run.simT >= nx.at * 60 + (a.shift or 0) then
    a.idx = a.idx + 1
    local before = api.routeMode and api.routeMode() or nil
    if api.setHours then pcall(api.setHours, nx.hour) end
    if api.setRouteMode then pcall(api.setRouteMode, nx.route) end
    run.meta.scenes[#run.meta.scenes + 1] = { key = nx.key, t = r1(run.simT), hour = nx.hour, route = nx.route, text = nx.text }
    event('scene', 0, nil, { key = nx.key, hour = nx.hour, route = nx.route })
    api.notify(string.format('🧪 Szene %d von %d: %s (%02d:%02d Uhr)', a.idx, #C.SCENES, nx.text, math.floor(nx.hour), math.floor((nx.hour % 1) * 60 + 0.5)), 6)
    if a.idx == 1 or before ~= nx.route then run.route.reroute = true end
    a.jamAt = nx.jam and (run.simT + nx.jam * 60) or nil
    a.perf = nx.perf and { steps = nx.perf, i = 0, nextAt = run.simT } or nil
  end
  if a.perf and run.simT >= a.perf.nextAt then
    a.perf.i = a.perf.i + 1
    a.perf.nextAt = run.simT + C.PERF_STEP_S
    local n = a.perf.steps[a.perf.i]
    if n and api.setTrafficAmount then
      local got = api.setTrafficAmount(n)
      event('perfStep', 0, nil, { want = n, n = got or n })
      api.notify(string.format('🧪 Leistungsmessung: %d Autos', got or n), 4)
    elseif not n then
      if api.setTrafficAmount then api.setTrafficAmount(nil) end
      a.perf = nil
    end
  end
  if a.jamAt and run.simT >= a.jamAt then
    a.jamAt = nil
    local fl = api.flow and api.flow()
    if fl and fl.requestJam then fl.requestJam(); event('jamAsked', 0) end
  end
end

-- the black box, the jolts (every BOX_S)
local function dumpBox(q)
  if #run.boxes >= C.BOX_MAX then return end
  local rows = {}
  for _, f in ipairs(run.box) do
    for _, r in ipairs(f.rows) do
      if r[1] == q.id or (math.abs(r[2] - q.x) < C.BOX_AROUND_M and math.abs(r[3] - q.y) < C.BOX_AROUND_M) then
        rows[#rows + 1] = { f.t, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9] }
      end
    end
  end
  run.boxes[#run.boxes + 1] = { t = q.t, id = q.id, rows = rows }
end
local function boxTick(t)
  local pv = api.playerVeh()
  if not pv or not map or not map.objects then return end
  local pid, tid = pv:getID(), api.trailerId()
  local ppos = vec3(pv:getPosition())
  local ids = run.ids or {}
  local tai = api.tai()
  local lab = tai and tai.labApi
  local frame = { t = r1(t), rows = {} }
  for id, o in pairs(map.objects) do
    if (ids[id] or id == pid) and id ~= tid and o.pos and o.vel then
      local pos = vec3(o.pos)
      if pos:distance(ppos) <= C.BOX_M then
        local vel = vec3(o.vel)
        local sp = vel:length()
        local dv = o.dirVec
        local st = id ~= pid and lab and lab.car and lab.car(id) or nil
        frame.rows[#frame.rows + 1] = { id == pid and 0 or id, r1(pos.x), r1(pos.y), r1(pos.z), r1(sp), r1(vel.z),
          dv and r2(atan2(dv.x, dv.y)) or 0, st and st.own and 1 or 0, st and st.why or '' }
        -- (a jolt: the vertical speed jumping, at speed, without the damage going up)
        local b = run.bumpK[id]
        local dmg = tonumber(o.damage) or 0
        if b then
          local gap = t - b.t
          if b.pos:distance(pos) > sp * gap + 10 then b.quiet = t + C.BUMP_QUIET_S end
          if sp > C.BUMP_MS and gap < C.BOX_S * 2.5 and t > (b.quiet or 0) and math.abs(vel.z - b.vz) > C.BUMP_DVZ and dmg - b.dmg < 50
             and t - (b.at or -1e9) > C.BUMP_REPEAT_S then
            b.at = t
            run.win.bumps = run.win.bumps + 1
            event('bump', id == pid and 0 or id, pos, { kmh = math.floor(sp * 3.6), dvz = r1(vel.z - b.vz), z = r1(pos.z), own = st and st.own and 1 or 0 })
            local dir = flat(vel)
            if api.bump and dir then pcall(api.bump, pos, dir, sp * 3.6) end
          end
          b.vz, b.dmg, b.t, b.pos = vel.z, dmg, t, pos
        else
          run.bumpK[id] = { vz = vel.z, dmg = dmg, t = t, pos = pos }
        end
      end
    end
  end
  run.box[#run.box + 1] = frame
  while #run.box > 0 and t - run.box[1].t > C.BOX_KEEP_S + C.BOX_AFTER_S do table.remove(run.box, 1) end
  for i = #run.boxDue, 1, -1 do
    local q = run.boxDue[i]
    if t >= q.at then table.remove(run.boxDue, i); dumpBox(q) end
  end
end

local function sample(dt)
  local pv = api.playerVeh()
  if not pv or not map or not map.objects then return end
  local tai = api.tai()
  local lab = tai and tai.labApi
  local pid, tid = pv:getID(), api.trailerId()
  local ppos = vec3(pv:getPosition())
  local w = run.win
  local ids = trafficIds()
  run.ids = ids
  local cars = {}
  local jHere = {}
  local parked = tai and tai.virt and tai.virt.parked or {}
  for id, o in pairs(map.objects) do
    if ids[id] and id ~= pid and id ~= tid and o.pos and o.vel and not parked[id] then
      local pos = vec3(o.pos)
      local d = pos:distance(ppos)
      if d <= C.NEAR_M then
        local vel = vec3(o.vel)
        cars[#cars + 1] = { id = id, o = o, pos = pos, vel = vel, speed = vel:length(), dir = flat(o.dirVec and vec3(o.dirVec) or vel), d = d }
      end
    end
  end
  -- (the player's truck is in the way of everybody too)
  local pvel = vec3(pv:getVelocity())
  local pdir = flat(vec3(pv:getDirectionVector()))
  local others = { { pos = ppos, speed = pvel:length(), dir = pdir } }
  for _, c in ipairs(cars) do others[#others + 1] = c end
  w.samples = w.samples + 1
  w.near = w.near + #cars
  do local fl = api.flow and api.flow(); if fl and fl.active() then local n = 0; for _ in pairs(fl.member) do n = n + 1 end; w.jam = w.jam + n end end
  for _, c in ipairs(cars) do
    local k = run.car[c.id]
    if not k then
      k = { stopT = 0, offT = 0, wrongT = 0 }
      run.car[c.id] = k
      run.carsSeen = run.carsSeen + 1
      k.born = run.simT
      if c.d < C.POPIN_M and run.simT > C.WARMUP_S then event('popin', c.id, c.pos, { d = math.floor(c.d) }) end
    elseif k.pos and k.pos:distance(c.pos) > C.JUMP_M + c.speed * dt then
      k.speed, k.stopT, k.offT, k.wrongT, k.lane, k.dmg, k.stuckSaid = nil, 0, 0, 0, nil, nil, nil
      k.born = run.simT
      event('respawn', c.id, c.pos, { kmh = math.floor(c.speed * 3.6) })
      run.win.puts = run.win.puts + 1
      if c.d < C.POPIN_M and run.simT > C.WARMUP_S then event('popin', c.id, c.pos, { d = math.floor(c.d) }) end
    end
    local st = lab and lab.car(c.id)
    if st and st.own then w.own = w.own + 1 end
    if st and st.phase then w.passing = w.passing + 1 end
    -- the road under it
    local lim, lat, half, atJ, laneIdx = 0, nil, nil, false, 0
    local jName, jPos
    if c.dir and lab then
      local centre, rd, hf, back, fwd, nodes, link = lab.roadAt(c.pos, c.dir)
      if centre and rd then
        half = hf
        lat = (c.pos - centre):dot(vec3(rd.y, -rd.x, 0))
        lim = type(link) == 'table' and link.speedLimit or 0
        atJ, jName, jPos = nearJunction(nodes, back, fwd, c.pos)
        if type(link) == 'table' and link.oneWay and hf and hf > 4.6 then
          w.wide = w.wide + 1
          if type(link.lanes) ~= 'string' then w.lanesUnknown = w.lanesUnknown + 1 end
        end
      end
      local li = lab.lanesHere(c.pos, c.dir)
      if li then
        w.multi = w.multi + 1
        laneIdx = li.idx
        local key = li.n .. ':' .. li.idx
        run.laneUse[key] = (run.laneUse[key] or 0) + 1
        if k.lane and k.lane ~= li.idx and k.laneN == li.n then event('laneChange', c.id, c.pos, { from = k.lane, to = li.idx, n = li.n }) end
        k.lane, k.laneN = li.idx, li.n
      else k.lane = nil end
    end
    -- the one in front of it in its lane
    local lead, gap = nil, nil
    if c.dir then
      local right = vec3(c.dir.y, -c.dir.x, 0)
      for _, o in ipairs(others) do
        if o ~= c and o.dir and o.dir:dot(c.dir) > 0.5 then
          local rel = o.pos - c.pos
          local ahead, side = rel:dot(c.dir), rel:dot(right)
          if ahead > 2 and ahead < C.LEADER_M and math.abs(side) < C.LANE_SIDE_M and math.abs(rel.z) < 3.5 and (not gap or ahead < gap) then lead, gap = o, ahead end
        end
      end
    end
    -- (2026-11-11) through a junction: counted when it has left it
    local kind = kindOf(lim)
    if jName and jPos and jPos:distance(c.pos) <= C.JPASS_M then
      w.inJunction = w.inJunction + 1
      if k.jn ~= jName then k.jn, k.jIn, k.jMin, k.jOwn = jName, run.simT, c.speed, st and st.own and 1 or 0 else k.jMin = math.min(k.jMin, c.speed) end
      local l = jHere[jName]
      if not l then l = {}; jHere[jName] = l end
      l[#l + 1] = { c = c, own = st and st.own and 1 or 0 }
    elseif k.jn then
      local J = run.junctions
      J.passes, J.secs = J.passes + 1, J.secs + (run.simT - k.jIn)
      if k.jOwn == 1 then J.own = J.own + 1 end
      if k.jMin < C.STOP_MS then J.stopped = J.stopped + 1; if k.jOwn == 1 then J.ownStopped = J.ownStopped + 1 end end
      k.jn = nil
    end
    -- (2026-11-11) through something shut (roadworks, lost cargo, a wreck): the traffic is to go round it, never through
    do
      local zs = tai and tai.zonesNow
      -- (not one just put down there: BeamNG's respawn sets cars anywhere; going round from there is the AI's part)
      if zs and c.dir and lab and c.speed > 3 and run.simT - (k.born or 0) >= 4 then
        for _, z in ipairs(zs) do
          local B = z.block
          if B and z.dir and c.dir:dot(z.dir) > 0.5 then
            local along = (c.pos - z.pos):dot(z.dir)
            if along > B.s0 + 2 and along < B.s1 - 2 then
              local centre, rd = lab.roadAt(c.pos, c.dir)
              local zl = centre and rd and (c.pos - centre):dot(vec3(rd.y, -rd.x, 0))
              if zl and zl + 0.8 > B.l0 and zl - 0.8 < B.l1 then
                local key = tostring(z.kind) .. math.floor(z.pos.x / 25) .. ':' .. math.floor(z.pos.y / 25)
                k.blockHits = k.blockHits or {}
                if not k.blockHits[key] then
                  k.blockHits[key] = true
                  w.blockHits = (w.blockHits or 0) + 1
                  event('blockHit', c.id, c.pos, { what = tostring(z.kind), kmh = math.floor(c.speed * 3.6), own = st and st.own and 1 or 0, lat = r1(zl), l0 = r1(B.l0) })
                end
              end
            end
          end
        end
      end
    end
    -- near misses, gaps, the truck
    if lead and gap and c.speed > 5 then
      local itsWay = lead.dir and math.max(0, lead.dir:dot(c.dir)) * (lead.speed or 0) or 0
      local closing = c.speed - itsWay
      if closing > C.NEAR_CLOSE_MS then
        local ttc = (gap - 5) / closing
        if ttc < C.NEAR_TTC_S and run.simT - (k.nearAt or -1e9) > C.NEAR_REPEAT_S then
          k.nearAt = run.simT
          w.nearMiss = w.nearMiss + 1
          event('nearMiss', c.id, c.pos, { ttc = r1(math.max(0, ttc)), kmh = math.floor(c.speed * 3.6), lead = lead.id or 'player', own = st and st.own and 1 or 0, j = atJ and 1 or 0, road = kind })
        end
      end
      if c.speed > 8 and lim > 3 then count(run.headway, kind, C.HEADWAY_S, (gap - 5) / c.speed) end
      if lead == others[1] and (gap - 5) / c.speed < C.TAIL_TRUCK_S then w.tailTruck = w.tailTruck + 1 end
    end
    do
      local rel = c.pos - ppos
      if c.dir and pdir and c.dir:dot(pdir) > 0.7 and math.abs(rel:dot(vec3(pdir.y, -pdir.x, 0))) < 8 and math.abs(rel:dot(pdir)) < 60 then
        local side = rel:dot(pdir) > 0 and 1 or -1
        if k.truckSide == -1 and side == 1 then run.passTruck = run.passTruck + 1; event('passTruck', c.id, c.pos, { kmh = math.floor(c.speed * 3.6), own = st and st.own and 1 or 0 }) end
        k.truckSide = side
      else k.truckSide = nil end
    end
    -- flow
    local freeM = math.max(40, c.speed * C.FREE_S)
    local age = run.simT - (k.born or 0)
    -- (2026-11-11: a lorry at 80 on a road for 120 is keeping the rules, not dawdling: judged by the lorry's limit, as trafficai.lua paceOf)
    local fair = lim
    if lab and lab.lengthOf and lab.lengthOf(c.id) > 7 and lim > 0 then
      local kmh = math.floor(lim * 3.6 + 0.5)
      fair = (kmh >= 110 and 80 or (kmh > 50 and math.min(kmh, 60) or kmh)) / 3.6
    end
    if lim > 3 and (not gap or gap > freeM) and c.speed > C.STOP_MS and not atJ and age >= C.YOUNG_S then
      local share = math.min(1.5, c.speed / fair)
      w.freeSum, w.freeN = w.freeSum + share, w.freeN + 1
      count(run.share, kind, C.SHARE_BINS, share)
      if share < C.SLOW_FREE then w.slowFree = w.slowFree + 1 end
    end
    if gap and c.speed > 5 and (gap - 5) / c.speed < C.TAILGATE_S then w.tailgate = w.tailgate + 1 end
    -- (2026-11-13: not in the first moments after it was put down - the game's speed of a car just teleported is not its own)
    if k.speed and age >= C.SETTLE_S then
      local acc = (c.speed - k.speed) / dt
      if acc < -C.HARD_BRAKE then
        w.hard = w.hard + 1
        if acc < -C.PANIC_BRAKE then event('panicBrake', c.id, c.pos, { kmh = math.floor(k.speed * 3.6), lead = lead and (lead.id or 'player') or '', gap = gap and math.floor(gap) or -1 }) end
      end
    end
    -- standing
    if c.speed < C.STOP_MS then
      w.stopped = w.stopped + 1
      local queued = lead and gap and gap < 25 and lead.speed < 1.5
      -- (2026-11-12) in a jam (asleep far from the player too) or one of its accident: standing is what it is to do
      do local fl = tai and tai.flow; if fl and ((fl.member and fl.member[c.id]) or (fl.cause and fl.cause[c.id])) then queued = true end end
      if queued then k.stopT = 0 else k.stopT = k.stopT + dt end
      if k.stopT >= C.STUCK_S and not k.stuckSaid then
        k.stuckSaid = true
        event('stuck', c.id, c.pos, { where = atJ and 'junction' or 'road', own = st and st.own and 1 or 0, d = math.floor(c.d) })
      end
    else k.stopT, k.stuckSaid = 0, nil end
    -- beside the road / on the wrong side
    if lat and half then
      if math.abs(lat) > half + C.OFF_M then k.offT = k.offT + dt else k.offT, k.offSaid = 0, nil end
      if k.offT >= C.ROAD_HOLD_S and not k.offSaid then k.offSaid = true; event('offRoad', c.id, c.pos, { over = r1(math.abs(lat) - half), kmh = math.floor(c.speed * 3.6) }) end
      local drift = lab and c.dir and lab.laneDrift(c.pos, c.dir)
      if drift and drift < C.WRONG_M and c.speed > 3 and not (st and (st.phase or st.avoid)) then k.wrongT = k.wrongT + dt else k.wrongT, k.wrongSaid = 0, nil end
      if k.wrongT >= C.ROAD_HOLD_S and not k.wrongSaid then k.wrongSaid = true; event('wrongSide', c.id, c.pos, { lat = r1(drift or 0), kmh = math.floor(c.speed * 3.6) }) end
    end
    -- crashes
    local dmg = tonumber(c.o.damage) or 0
    -- (2026-11-12) falling through the world: counted apart (the Earth ground missing, not the driving), and its landing is no crash
    local vzF = c.o.vel and c.o.vel.z
    if vzF and vzF < -9 then
      if not k.fellT or run.simT - k.fellT > 10 then event('fell', c.id, c.pos, { vz = r1(vzF), z = r1(c.pos.z) }); w.fell = (w.fell or 0) + 1 end
      k.fellT = run.simT
    end
    if k.fellT and run.simT - k.fellT < 8 then k.dmg = dmg end
    if k.dmg and dmg - k.dmg > C.CRASH_DMG and k.crash and run.simT - k.crash.t < C.CRASH_MERGE_S then
      k.crash.dmg = k.crash.dmg + math.floor(dmg - k.dmg)            -- (the same crash still going on: one)
      if c.pos:distance(ppos) < 14 then k.crash.player = 1 end
    elseif k.dmg and dmg - k.dmg > C.CRASH_DMG then
      local withPlayer = c.pos:distance(ppos) < 14
      event('crash', c.id, c.pos, { dmg = math.floor(dmg - k.dmg), kmh = math.floor((k.speed or c.speed) * 3.6), player = withPlayer and 1 or 0, own = st and st.own and 1 or 0, age = math.floor(age),
        j = atJ and 1 or 0, road = kind, why = st and st.why or '' })
      k.crash = run.events[#run.events]
      run.boxDue[#run.boxDue + 1] = { at = run.simT + C.BOX_AFTER_S, id = c.id, x = c.pos.x, y = c.pos.y, t = r1(run.simT) }
    end
    k.dmg, k.speed, k.pos = dmg, c.speed, c.pos
    -- tracks
    if run.trackDue and c.d <= C.TRACK_M then
      run.tracks[#run.tracks + 1] = { r1(run.simT), c.id, r1(c.pos.x), r1(c.pos.y), r1(c.speed), r1(lim), lat and r2(lat) or 0, laneIdx,
        st and st.own and 1 or 0, st and st.phase or '', lab.lengthOf and lab.lengthOf(c.id) > 7 and 1 or 0, st and st.capMs and r1(st.capMs) or 0, math.floor(age), st and st.why or '',
        st and st.own and st.dvt and r1(st.dvt) or 0, st and st.own and st.dthr and r2(st.dthr) or 0, st and st.own and st.dgap or -1, st and st.own and st.dwhy or '' }
    end
  end
  -- two cars in one junction at once, crossing each other's way
  for name, l in pairs(jHere) do
    if #l > 1 then
      for i = 1, #l - 1 do
        for j = i + 1, #l do
          local a, b = l[i].c, l[j].c
          if a.speed > 2 and b.speed > 2 and a.dir and b.dir and math.abs(a.dir:dot(b.dir)) < C.JCONFLICT_COS and a.pos:distance(b.pos) < 2 * C.JPASS_M then
            local key = math.min(a.id, b.id) .. ':' .. math.max(a.id, b.id)
            if run.simT - (run.jSeen[key] or -1e9) > C.JCONFLICT_REPEAT_S then
              run.jSeen[key] = run.simT
              w.conflicts = w.conflicts + 1
              run.junctions.conflicts = run.junctions.conflicts + 1
              event('junctionConflict', a.id, a.pos, { other = b.id, own = l[i].own + l[j].own, kmh = math.floor(math.max(a.speed, b.speed) * 3.6), d = math.floor(a.pos:distance(b.pos)) })
            end
          end
        end
      end
    end
  end
  -- the player
  local plim = (api.limitKmh() or 0) / 3.6
  -- (2026-11-11: Earth moving the world, a reset of the truck: a jump, not driving - 436 km in 25 minutes in the fourth test)
  local psp = pvel:length()
  if psp > 70 then psp = 0 end
  w.pKmh, w.pLim, w.pN = w.pKmh + psp * 3.6, w.pLim + plim * 3.6, w.pN + 1
  run.odo = run.odo + psp * dt
  if run.trackDue then
    run.tracks[#run.tracks + 1] = { r1(run.simT), 0, r1(ppos.x), r1(ppos.y), r1(pvel:length()), r1(plim), 0, 0, 0, api.autodriveOn() and 'auto' or 'man', 1, 0, 0, '', 0, 0, -1, '' }
    run.trackDue = false
  end
end

local function closeWindow()
  local w = run.win
  local n = math.max(1, w.samples)
  local active = api.trafficActive()
  local fl = api.flow and api.flow()
  local tai0 = api.tai and api.tai()
  run.windows[#run.windows + 1] = { r1(run.simT), r1(w.near / n), active or 0, r1(w.frames / math.max(0.01, w.real)),
    r2(w.ai / math.max(1, w.frames) * 1000), r2(w.mod / math.max(1, w.frames) * 1000), w.freeN > 0 and r2(w.freeSum / w.freeN) or 0, w.freeN,
    w.slowFree, w.tailgate, w.hard, r2(w.stopped / math.max(1, w.near)), r1(w.pKmh / math.max(1, w.pN)), r1(w.pLim / math.max(1, w.pN)),
    w.multi, w.own, w.passing, w.wide > 0 and r2(w.lanesUnknown / w.wide) or 0, r1(w.jam / math.max(1, w.samples)),
    run.auto and run.auto.idx or 0, r1(api.hours() or 0), r2(fl and fl.roadF or 1), w.nearMiss, w.tailTruck, w.inJunction, w.conflicts, w.bumps, w.blockHits, w.fell, r1(w.worst * 1000), w.puts, (tai0 and tai0.virt and tai0.virt.stats.n) or 0 }
  run.win = newWindow()
end

function M.update(dtReal, dtSim)
  if not run then return end
  local w = run.win
  w.frames, w.real = w.frames + 1, w.real + dtReal
  if dtReal > w.worst then w.worst = dtReal end
  if dtSim <= 0 then return end                     -- (paused)
  run.simT = run.simT + dtSim
  local t = run.simT
  local pv = api.playerVeh()
  if pv then pcall(graphStep, vec3(pv:getPosition())) end
  if t - run.boxAt >= C.BOX_S then
    run.boxAt = t
    local okB, errB = pcall(boxTick, t)
    if not okB and not run.boxErr then run.boxErr = true; log('W', 'fernfahrer', 'lab box: ' .. tostring(errB)) end
  end
  if t - run.sampleAt >= C.SAMPLE_S then
    local dt = t - run.sampleAt
    run.sampleAt = t
    if t - run.trackAt >= C.TRACK_S then run.trackAt, run.trackDue = t, true end
    local ok, err = pcall(sample, dt)
    if not ok then log('W', 'fernfahrer', 'lab sample: ' .. tostring(err)) end
    local okS, errS = pcall(sceneTick)
    if not okS then log('W', 'fernfahrer', 'lab scene: ' .. tostring(errS)) end
    local okD, errD = pcall(drive, now())
    if not okD then log('W', 'fernfahrer', 'lab drive: ' .. tostring(errD)) end
  end
  if t - run.windowAt >= C.WINDOW_S then run.windowAt = t; closeWindow() end
  if t - run.savedAt >= C.SAVE_S then run.savedAt = t; save(false) end
  if t - run.toldAt >= C.PROGRESS_S then
    run.toldAt = t
    api.notify(string.format('🧪 Verkehrstest: %d von %d Minuten.', math.floor(t / 60), run.minutes), 4)
  end
  if t >= run.minutes * 60 then M.stop('done') end
end

function M.start(minutes, auto)
  if run then api.notify('Der Verkehrstest läuft schon (Strg+Umschalt+V beendet ihn).', 4); return false end
  if not api or not api.playerVeh() then return false end
  minutes = tonumber(minutes) or (auto and C.AUTO_MIN or C.DEFAULT_MIN)
  local tai = api.tai()
  local set = api.settings() or {}
  run = { minutes = minutes, file = path(), started = os.date('%Y-%m-%d %H:%M:%S'), simT = 0, sampleAt = 0, trackAt = -1e9, windowAt = 0,
    savedAt = 0, toldAt = 0, odo = 0, win = newWindow(), windows = {}, events = {}, counts = {}, tai = {}, laneUse = {}, tracks = {},
    car = {}, carsSeen = 0, route = {},
    box = {}, boxAt = -1e9, boxDue = {}, boxes = {}, bumpK = {}, jSeen = {}, headway = {}, share = {}, passTruck = 0,
    junctions = { passes = 0, own = 0, stopped = 0, ownStopped = 0, secs = 0, conflicts = 0 },
    auto = auto and { idx = 0 } or nil,
    restore = auto and { route = api.routeMode and api.routeMode() or nil, hour = api.hours and api.hours() or nil } or nil,
    graph = { parts = {}, seen = {}, nNodes = 0, lastAt = -1e9, anchor = false },
    meta = { mod = api.version(), ownDriver = set.ownDriver == true, smartTraffic = set.smartTraffic ~= false, traffic = set.traffic or 'auto',
      routeMode = set.routeMode or 'fast', hour = r1(api.hours() or 0), destinations = {}, auto = auto and true or false, scenes = {} } }
  if tai then tai.tap = tap; tai.ownTotal = {} end
  if auto and C.VIRTUAL and api.setVirtual then pcall(api.setVirtual, true); run.meta.virtual = true end
  M.on = true
  api.notify(auto and string.format('🧪 Vollautomatischer Verkehrstest: %d Minuten, %d Szenen (Landstraße und Autobahn, morgens bis nachts). Der LKW fährt selbst, Strg+Umschalt+V beendet ihn.', minutes, #C.SCENES)
    or string.format('🧪 Verkehrstest gestartet: %d Minuten, der LKW fährt selbst. Strg+Umschalt+V beendet ihn.', minutes), 6)
  log('I', 'fernfahrer', string.format('lab: started, %d min, writing %s', minutes, run.file))
  return true
end

function M.stop(why)
  if not run then return nil end
  closeWindow()
  local s = save(true)
  local file = run.file
  local tai = api.tai()
  if tai then tai.tap = nil end
  if run.route.wasOn and api.autodriveOn() and not run.route.manual then api.autodriveToggle() end
  -- (the full-automatic test: the route kind and the clock as they were)
  if api.setTrafficAmount then pcall(api.setTrafficAmount, nil) end
  if api.setVirtual then pcall(api.setVirtual, false) end
  if run.restore then
    if run.restore.route and api.setRouteMode then pcall(api.setRouteMode, run.restore.route) end
    if run.restore.hour and api.setHours then pcall(api.setHours, run.restore.hour) end
  end
  run, M.on = nil, false
  local ev = s and s.events or {}
  api.notify(string.format('🧪 Verkehrstest %s: %.0f min, %d Autos gesehen, %d Unfälle, %d stehen geblieben. Datei: %s',
    why == 'done' and 'fertig' or 'beendet', s and s.minutes or 0, s and s.cars or 0, ev.crash or 0, ev.stuck or 0, file), 12)
  log('I', 'fernfahrer', 'lab: ' .. tostring(why) .. ', written to ' .. file)
  return file
end

function M.running() return run ~= nil end

return M
