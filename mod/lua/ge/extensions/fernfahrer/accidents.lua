-- Trucks of Earth: accidents. A sudden jump in the player vehicle's damage is a crash; a moment later the scene is
-- read (the other vehicles that took damage close by, the speed before the impact, the road's limit) and, unless it
-- was a mere scrape, the police are called – and an ambulance when it was a bad one. They drive there with their
-- lights on (BeamNG's AI on the road graph), stop at the scene, and the police write the accident report (a company
-- document in the office: place, vehicles, speed estimate, who is to blame, injuries). Then they leave.
-- career.lua calls M.update(ctx, dt) every frame; ctx: playerVeh(), damageOf(id), speedKmh(), roadLimit(), here(),
--   placeOf(lat, lon) -> {road, near}, trailerId(), clockText(), addDocument(doc), fine(amount, reason),
--   notify(text, ttl), message(text, from), protect(id), busy() (travelling: no detection), vehicleName()

local M = {}
local pool = require('fernfahrer/pool')

M.C = {
  SAMPLE_S = 0.25,
  CRASH_DMG = 700,          -- damage gained within one sample: a crash
  IMPACT_DMG = 250,         -- the dashcam saves: this much damage at once ...
  IMPACT_KMH = 15,          -- ... going at least this fast just before
  IMPACT_GAP_S = 10,        -- (not again within this: one crash, one recording)
  SETTLE_S = 2.5,           -- then the scene is read
  MIN_REPORT_DMG = 2500,    -- below that (and nobody else hit): no police
  OTHER_DMG = 80,           -- another vehicle that took this much: involved
  COOLDOWN_S = 30,
  NEAR_M = 25,              -- other vehicles this close that took damage are involved
  SCAN_M = 70,
  SPAWN_M = { 220, 450 },   -- the responders start this far away on the road graph
  ARRIVE_M = 3.5,           -- parked this close to its own spot at the scene
  MIN_RUN_M = 5,            -- moved this far from where it stood: its order has arrived
  NEAR_SCENE_M = 40,        -- stopped within this of the scene: it stays where it is, no jump
  SLOW_M = 70,              -- from here on a slow approach
  STUCK_S = 6,              -- standing this long on the approach: parked where it is
  DRIVE_TIMEOUT_S = 110,    -- then they are put at the scene
  NO_PROGRESS_S = 12,       -- (2026-11-09) on the way and not a metre nearer for this long: stuck, crashed: it starts again nearer the scene
  NO_START_S = 22,          -- ... the same for one that never got going
  MAX_RECOVERS = 2,         -- ... and after that it is put at the scene: it always arrives
  REPORT_S = 8,             -- the police at the scene this long: the report
  LEAVE_S = 18,             -- after the report they leave
  GONE_M = 400,             -- the player this far away: the responders go
  MAX_AGE_S = 360,
}
local C = M.C

local acc = nil
local lastAt = -math.huge
local lastImpact, impactId = -math.huge, nil
local sampleT = 0
local prev = { id = nil, dmg = 0 }
local speeds = {}            -- the last 2 s of player speed (km/h)
local others = {}            -- id -> { dmg, speed } around the player at the last sample
local function now() return os.clock() end

local OFFICERS = { 'POK Schneider', 'PK Wagner', 'POM Becker', 'PHK Schulz', 'POK Hoffmann', 'PK Yilmaz', 'POM Krüger',
  'PHK Neumann', 'POK Lehmann', 'PK Schäfer' }

local function round5(x) return math.floor(x / 5 + 0.5) * 5 end
local function vehPos(v) return vec3(v:getPosition()) end
local function flatDist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end
local function flatDir(v) local l = math.sqrt(v.x * v.x + v.y * v.y); return l > 0.01 and vec3(v.x / l, v.y / l, 0) or nil end

-- (2026-11-08) the way the truck came: a point every few metres. A place on it is on the right carriageway and faces the
-- right way by definition – on the motorway the nearest road of the graph can be the other carriageway, or a road beside
-- it from which there is no way up. Whoever has to come from behind starts here.
local trail = {}
M.TRAIL_STEP, M.TRAIL_MAX = 6, 130
local function trailAdd(p)
  local last = trail[#trail]
  if last then
    local d = flatDist(p, last)
    if d > 90 then trail = {}                       -- (a teleport: that way nobody can come)
    elseif d < M.TRAIL_STEP then return end
  end
  trail[#trail + 1] = vec3(p)
  if #trail > M.TRAIL_MAX then table.remove(trail, 1) end
end
-- the point dist m back along a trail, and the direction of travel there
local function trailPoint(tr, dist)
  local s = 0
  for i = #tr, 2, -1 do
    local a, b = tr[i - 1], tr[i]
    local l = flatDist(a, b)
    if l > 0.01 then
      if s + l >= dist then
        local k = (dist - s) / l
        return b + (a - b) * k, flatDir(b - a)
      end
      s = s + l
    end
  end
  return nil
end
local function groundAt(p)
  local top = vec3(p.x, p.y, p.z + 3)               -- (just above the road: not the bridge over it)
  local hit = castRayStatic(top, vec3(0, 0, -1), 14)
  return (hit and hit < 14) and vec3(p.x, p.y, top.z - hit) or vec3(p)
end
-- for the others who come from behind (a siren, traffic moved behind the truck): the road surface dist m back, direction
function M.behind(dist)
  local p, d = trailPoint(trail, dist)
  if p and d then return groundAt(p), d end
  return nil
end
local function canDrive(nodes, a, b)
  local l = nodes[a] and nodes[a].links and nodes[a].links[b]
  return not (l and l.oneWay and l.inNode ~= a)
end
-- the graph's node about `ahead` m along the road the vehicle is on, in its direction of travel and by the road's
-- direction (never against a one-way carriageway); and the node right ahead
function M.nodeAlong(pos, dir, ahead)
  if not (map and map.findClosestRoad and map.getMap) then return nil end
  local g = map.getMap()
  local nodes = g and g.nodes
  if not nodes then return nil end
  local function edgeAt(p)
    local ok, n1, n2 = pcall(map.findClosestRoad, p)
    if not ok or not n1 or not n2 or not nodes[n1] or not nodes[n2] then return nil end
    local back, fwd = n1, n2
    if (nodes[fwd].pos - nodes[back].pos):dot(dir) < 0 then back, fwd = n2, n1 end
    if canDrive(nodes, back, fwd) then return back, fwd end
    return nil
  end
  local right = vec3(dir.y, -dir.x, 0)
  local back, fwd = edgeAt(pos)
  if not back then
    for _, k in ipairs({ 7, -7, 14, -14 }) do
      back, fwd = edgeAt(pos + right * k)
      if back then break end
    end
  end
  if not back then return nil end
  local prev, cur = back, fwd
  local heading = flatDir(nodes[fwd].pos - nodes[back].pos) or dir
  local run = flatDist(nodes[fwd].pos, pos)
  for _ = 1, 80 do
    if run >= ahead then break end
    local best, bestDot = nil, 0.35
    for m in pairs(nodes[cur].links or {}) do
      if m ~= prev and nodes[m] and canDrive(nodes, cur, m) then
        local d = flatDir(nodes[m].pos - nodes[cur].pos)
        if d and d:dot(heading) > bestDot then best, bestDot = m, d:dot(heading) end
      end
    end
    if not best then break end
    heading = flatDir(nodes[best].pos - nodes[cur].pos) or heading
    run = run + flatDist(nodes[best].pos, nodes[cur].pos)
    prev, cur = cur, best
  end
  return cur, fwd
end

local function scanOthers(ctx, v)
  local p = vehPos(v)
  local out = {}
  local objs = map and map.objects or {}
  local pid, tid = v:getID(), ctx.trailerId()
  for id, o in pairs(objs) do
    if id ~= pid and o.pos and p:distance(vec3(o.pos)) < C.SCAN_M then
      local sp = 0
      local ov = getObjectByID(id)
      if ov then sp = vec3(ov:getVelocity()):length() * 3.6 end
      -- (a walker of the Pedestrians mod is a vehicle too: counted apart)
      out[id] = { dmg = o.damage or 0, speed = sp, trailer = id == tid or nil, ped = ov and ov.JBeam == 'pedestrian' or nil,
        pos = vec3(o.pos) }
    end
  end
  return out
end

-- responders ------------------------------------------------------------------------------------------------

-- where a responder starts: on the scene's own road, back the way the player came (dist m along the road graph,
-- the straightest way at every node), facing the scene; and the node at the scene to drive to. (A node anywhere
-- within 450 m picked side roads with no good way to the scene: the ambulance stood about, in game 2026-11-03.)
local function spawnNode(pos, dir, dist)
  if not (map and map.findClosestRoad and map.getMap) then return nil end
  local n1, n2 = map.findClosestRoad(pos)
  local g = map.getMap()
  local nodes = g and g.nodes
  if not n1 or not n2 or not nodes or not nodes[n1] or not nodes[n2] then return nil end
  -- the edge oriented with the travel direction: `back` is the node behind the scene
  local back, fwd = n1, n2
  if (nodes[fwd].pos - nodes[back].pos):dot(dir) < 0 then back, fwd = n2, n1 end
  local prev, cur = fwd, back
  local travelled = nodes[back].pos:distance(pos)
  local heading = nodes[back].pos - nodes[fwd].pos
  heading.z = 0
  heading = heading:length() > 0.1 and heading:normalized() or -dir
  for _ = 1, 60 do
    if travelled >= dist then break end
    local best, bestDot = nil, 0.2
    for m in pairs(nodes[cur].links or {}) do
      if m ~= prev and nodes[m] and canDrive(nodes, m, cur) then
        local d = nodes[m].pos - nodes[cur].pos
        d.z = 0
        if d:length() > 0.1 then
          d = d:normalized()
          if d:dot(heading) > bestDot then best, bestDot = m, d:dot(heading) end
        end
      end
    end
    if not best then break end
    local d = nodes[best].pos - nodes[cur].pos
    d.z = 0
    travelled = travelled + d:length()
    heading = d:normalized()
    prev, cur = cur, best
  end
  if travelled < 60 then return nil, back end
  -- the start node, the scene's node to drive to, the node after the start (towards the scene)
  return cur, back, prev, nodes
end

-- (2026-11-08) where a responder stops: the nearest free place around the scene – behind it, then beside it – clear of
-- the truck, its trailer, the other vehicles and the spot of the other responder. Never far from the accident.
local function freeSpot(ctx, a, kind)
  local d = a.dir or vec3(0, 1, 0)
  d = vec3(d.x, d.y, 0)
  d = d:length() > 0.1 and d:normalized() or vec3(0, 1, 0)
  local right = vec3(d.y, -d.x, 0)
  -- (behind the scene: on the way the truck came, so round a bend too)
  local function base(s)
    if s < 0 and a.trail then
      local p, td = trailPoint(a.trail, -s)
      if p and td then return p, td end
    end
    return a.pos + d * s, d
  end
  local tid = ctx.trailerId and ctx.trailerId()
  local pv = ctx.playerVeh and ctx.playerVeh()
  local pid = pv and pv:getID()
  local blocks = {}
  for id, o in pairs(map and map.objects or {}) do
    if o.pos then blocks[#blocks + 1] = { p = vec3(o.pos), r = id == tid and 10.5 or (id == pid and 7 or 6) } end
  end
  for _, u in ipairs(a.units or {}) do if u.dest then blocks[#blocks + 1] = { p = u.dest, r = 7.5 } end end
  -- the responder itself is not in the way of its own spot: it is far off when this is asked
  local tries = {}
  for _, s in ipairs({ -10, -14, -18, -22, -26, -30, -34 }) do
    for _, l in ipairs({ 0.8, 3.6, -3.0 }) do tries[#tries + 1] = { s = s, l = l } end
  end
  table.sort(tries, function(x, y) return x.s ^ 2 + x.l ^ 2 < y.s ^ 2 + y.l ^ 2 end)
  -- (beside the truck only when there is no room behind it: beside the road is often a ditch)
  for _, s in ipairs({ -6, 0, 8 }) do tries[#tries + 1] = { s = s, l = 4.6 } end
  for _, c in ipairs(tries) do
    local bp, bd = base(c.s)
    local q = bp + vec3(bd.y, -bd.x, 0) * c.l
    local free = true
    for _, b in ipairs(blocks) do
      local dx, dy = b.p.x - q.x, b.p.y - q.y
      if dx * dx + dy * dy < b.r * b.r then free = false; break end
    end
    if free then
      local top = vec3(q.x, q.y, q.z + 4)
      local hit = castRayStatic(top, vec3(0, 0, -1), 16)
      if hit and hit < 16 and math.abs((top.z - hit) - q.z) < 4 then
        return vec3(q.x, q.y, top.z - hit), bd
      end
    end
  end
  local bp, bd = base(-24)
  return bp + vec3(bd.y, -bd.x, 0) * 3.6, bd
end

-- the last metres: the speed comes down with the distance left, and the car moves over to the side its spot is on
local function brakeCmd(dd)
  return string.format('ai.setSpeedMode("limit") ai.setSpeed(%.2f)', math.max(1.2, math.sqrt(2 * 2.4 * math.max(0, dd - 2)) ))
end
local function sidewaysCmd(uv, up, dest)
  local h = flatDir(vec3(uv:getDirectionVector())) or vec3(0, 1, 0)
  local rel = dest - up
  local along = math.max(10, rel:dot(h))
  local lateral = rel:dot(vec3(h.y, -h.x, 0))
  if math.abs(lateral) < 0.5 then return '' end
  return string.format('ai.driveInLane("off") ai.laneChange(nil, %.1f, %.2f)', along * 0.85, math.max(-5, math.min(5, lateral)))
end

-- where a responder starts when the truck has come a way: on the truck's own way back there, not on top of another car
-- (2026-11-09: and where the game has a road to drive on: Earth's road graph and its solid ground only reach some hundred metres round the
-- truck. From beyond that the AI had no way to plan: it drove off straight on into whatever stood there.)
local function hasRoad(p, d)
  local ok, n1, _, off = pcall(map.findClosestRoad, p)
  if not ok or not n1 or (off and off > 14) then return false end
  return M.nodeAlong(p, d, 40) ~= nil
end
local function startOnTrail(a, dist)
  if not a.trail then return nil end
  for _, m in ipairs({ dist, dist * 0.8, dist * 0.6, dist * 0.4, dist * 0.25 }) do
    local p, d = trailPoint(a.trail, m)
    if p and d and hasRoad(p, d) then
      local free = true
      for _, o in pairs(map and map.objects or {}) do
        if o.pos and flatDist(vec3(o.pos), p) < 9 then free = false; break end
      end
      if free then return groundAt(p), d end
    end
  end
  return nil
end

-- what a responder is told: a road and a lane to keep, at a speed it can take the bends at (blue lights: somewhat over the limit)
local function responderCmd(kind, a, target)
  local start = kind == 'service' and 'controller.setFreeze(0) electrics.set_warn_signal(1) ' or 'controller.setFreeze(0) electrics.set_lightbar_signal(2) '
  if not target then return start end
  local limit = (a.limit or 80) / 3.6
  local vmax = kind == 'service' and math.max(12, math.min(22, limit)) or math.max(14, math.min(27, limit * 1.2))
  return start .. string.format('ai.setMode("manual") ai.setTarget(%q) ai.setSpeedMode("limit") ai.setSpeed(%.1f) ai.setAggression(%.2f) ai.setAvoidCars("on") ai.driveInLane("on")',
    target, vmax, kind == 'service' and 0.35 or 0.45)
end

local function spawnResponder(ctx, kind, scene)
  local a = scene or acc
  -- (the ambulance a little farther back: it comes in behind the patrol car; the breakdown service from farther still)
  local dist = kind == 'service' and 340 or (kind == 'ambulance' and 300 or 240)
  local pos, dir = startOnTrail(a, dist)
  local sNode, target, nextNode, nodes
  if pos then
    -- (the road on, past the scene: seen from just before the crash – the truck may have ended up off the road. It is
    -- braked at its own spot long before it would get there)
    local before = trailPoint(a.trail, 18) or a.pos
    target = M.nodeAlong(before, a.dir or dir, 180)
    if not target then
      local _, b = spawnNode(a.pos, a.dir or dir, 80)
      target = b
    end
  else
    sNode, target, nextNode, nodes = spawnNode(a.pos, a.dir or vec3(0, 1, 0), dist)
  end
  if pos then
    log('I', 'fernfahrer', string.format('responder %s: starts on the truck\'s way, target node %s', kind, tostring(target)))
  elseif sNode and nextNode then
    pos = vec3(nodes[sNode].pos)
    dir = (vec3(nodes[nextNode].pos) - pos)
    dir.z = 0
    dir = dir:length() > 0.1 and dir:normalized() or vec3(0, 1, 0)
  else
    -- no road graph: behind the scene, along the player's heading
    local v = ctx.playerVeh()
    local d = v and vec3(v:getDirectionVector()) or vec3(0, 1, 0)
    d.z = 0
    dir = d:length() > 0.1 and d:normalized() or vec3(0, 1, 0)
    pos = a.pos - dir * 120
  end
  -- (from the pool: spawned in advance, no hitch now)
  local id = pool.take(kind, pos + vec3(0, 0, 0.4), dir)
  local veh = id and getObjectByID(id)
  if not veh then log('W', 'fernfahrer', 'responder ' .. kind .. ': none'); return end
  ctx.protect(id)
  local cmd = responderCmd(kind, a, target)
  veh:queueLuaCommand(cmd)
  local dest, ddir = freeSpot(ctx, a, kind)
  -- (cmd is given again until it moves: an order to a vehicle just spawned or woken up gets lost – it stood where it had
  -- come into the world and was put at the scene after the time-out, 2026-11-08)
  table.insert(a.units, { a = a, id = id, kind = kind, t0 = now(), kickT0 = now(), arrived = false, driving = target ~= nil, cmd = cmd, kickAt = now() + 0.4, dest = dest, ddir = ddir, from = vec3(pos) })
end

local function park(u, ctx, teleport)
  local v = getObjectByID(u.id)
  if not v then return end
  local a = u.a or acc
  if teleport then
    -- did not make it in time: put it just behind the scene
    local d = u.ddir or a.dir or vec3(0, 1, 0)
    local dest = u.dest or (a.pos - d * 20)
    if spawn and spawn.safeTeleport then pcall(spawn.safeTeleport, v, dest, quatFromDir(d, vec3(0, 0, 1))) end
  end
  v:queueLuaCommand('ai.setMode("disabled") controller.setFreeze(1) ' .. (u.kind == 'service' and '' or 'electrics.set_lightbar_signal(1) ') .. 'electrics.set_warn_signal(1)')
  u.arrived = true
  u.at = now()
end

-- (2026-11-08) off again: its walking-pace limit from parking goes (it stood there for good with it), and it first pulls
-- out round whatever stands ahead of it – the truck, as a rule – before it is ordinary traffic again
local function release(u, a)
  local v = getObjectByID(u.id)
  if not v then return end
  local d = flatDir(vec3(v:getDirectionVector())) or (a and a.dir) or vec3(0, 1, 0)
  local target = M.nodeAlong(vehPos(v), d, 350)
  local off = 'controller.setFreeze(0) electrics.set_lightbar_signal(0) electrics.set_warn_signal(0) '
  u.relTraffic = off .. 'ai.setMode("traffic") ai.setSpeedMode("legal") ai.setAggression(0.3) ai.setAvoidCars("on") ai.driveInLane("on")'
  u.relCmd = target and (off .. string.format('ai.setMode("manual") ai.setTarget(%q) ai.setSpeedMode("limit") ai.setSpeed(13) ai.setAggression(0.4) ai.setAvoidCars("on") ai.driveInLane("off")', target)) or u.relTraffic
  v:queueLuaCommand(u.relCmd)
  local t = now()
  u.relAgain, u.relNormal = t + 1.5, t + 16
end
local function releaseTick(u, t)
  local v = u.relCmd and getObjectByID(u.id)
  if not v then return end
  if u.relAgain and t >= u.relAgain then u.relAgain = nil; v:queueLuaCommand(u.relCmd) end
  if u.relNormal and t >= u.relNormal then u.relNormal = nil; v:queueLuaCommand(u.relTraffic) end
end

local function clearUnits(a)
  for _, u in ipairs(a and a.units or {}) do pool.give(u.id) end
  if a then a.units = {} end
end

-- the report --------------------------------------------------------------------------------------------------

local function buildReport(ctx, a)
  local place = ctx.placeOf(a.lat, a.lon) or {}
  local n = #a.involved
  local sevName = ({ leicht = 'leichter Sachschaden', mittel = 'erheblicher Sachschaden', schwer = 'schwerer Unfall' })[a.severity]
  -- the speed: what it was before the impact, as an officer would guess it from the marks (± a little)
  local est = math.max(5, round5(a.preSpeed + (math.random() * 12 - 6)))
  local estText = est <= 10 and 'Schrittgeschwindigkeit' or string.format('ca. %d km/h', est)
  -- who is to blame
  local fault, why
  local over = a.limit and (a.preSpeed - a.limit) or 0
  local main = a.involved[1]
  local peds = a.peds or 0
  if peds > 0 and n == 0 then
    -- a walker: the driver, unless slow and the walker stepped out (then shared)
    if a.preSpeed < 25 and over <= 0 and math.random() < 0.35 then
      fault, why = 'Teilschuld (50 / 50)', 'Fußgänger trat unvermittelt auf die Fahrbahn'
    else
      fault, why = 'Fahrer (du)', over > 5 and string.format('Fußgänger erfasst – zu schnell (%d km/h über dem Limit)', math.floor(over))
        or 'Fußgänger erfasst – nicht rechtzeitig gebremst / Unaufmerksamkeit'
    end
  elseif n == 0 then
    fault, why = 'Fahrer (du)', 'Alleinunfall – kein anderes Fahrzeug beteiligt'
  elseif over > 10 then
    fault, why = 'Fahrer (du)', string.format('nicht angepasste Geschwindigkeit (%d km/h über dem Limit)', math.floor(over))
  elseif main and main.rel == 'behind' and main.speed > a.preSpeed + 5 then
    fault, why = 'Unfallgegner', 'Auffahrunfall – der Unfallgegner ist von hinten aufgefahren'
  elseif main and main.rel == 'ahead' and a.preSpeed > (main.speed or 0) + 5 then
    fault, why = 'Fahrer (du)', 'Auffahrunfall – zu geringer Sicherheitsabstand'
  elseif main and main.rel == 'side' then
    local r = math.random()
    if r < 0.4 then fault, why = 'Unfallgegner', 'Vorfahrt missachtet / Spurwechsel ohne Schulterblick'
    elseif r < 0.7 then fault, why = 'Fahrer (du)', 'Fehler beim Spurwechsel oder Abbiegen'
    else fault, why = 'Teilschuld (50 / 50)', 'Unfallhergang nicht eindeutig zu klären' end
  else
    fault, why = 'Teilschuld (50 / 50)', 'Unfallhergang nicht eindeutig zu klären'
  end
  local injured
  local hurt = 0                                   -- (people hurt in the vehicles)
  if a.severity == 'schwer' and n > 0 then hurt = 2 elseif a.severity == 'schwer' then hurt = 1
  elseif a.severity == 'mittel' and math.random() < 0.5 then hurt = 1 end
  if n == 0 and peds > 0 then hurt = 0 end         -- (a walker hit: nobody in the truck is hurt by that)
  local pedState
  if peds > 0 then
    pedState = a.preSpeed > 60 and 'lebensgefährlich verletzt' or (a.preSpeed > 30 and 'schwer verletzt' or 'leicht verletzt')
  end
  local parts = {}
  if peds > 0 then parts[#parts + 1] = string.format('%d Fußgänger %s', peds, pedState) end
  if hurt > 0 then parts[#parts + 1] = hurt == 1 and '1 Fahrzeuginsasse verletzt' or (hurt .. ' Fahrzeuginsassen verletzt') end
  if #parts == 0 then injured = 'keine Verletzten'
  else
    local hospital = (peds > 0 and a.preSpeed > 30) or hurt > 1
    local care = ''
    if a.ambulance then care = ' – vom Rettungsdienst versorgt' .. (hospital and ' und ins Krankenhaus gebracht' or '') end
    injured = table.concat(parts, ', ') .. care
  end
  if a.fled then fault, why = 'Fahrer (du)', 'Unfallort vor Eintreffen der Polizei verlassen (Unfallflucht)' end
  -- alcohol / cannabis (the cab's beer and joint, vices.lua): the police test at the scene. From 0,3 ‰ (or THC over
  -- the limit) with an accident the driver counts as unfit to drive – the share of the blame goes to him.
  local imp = ctx.impairment and ctx.impairment() or nil
  local bac, thc = imp and imp.bac or 0, imp and imp.thc or 0
  local drunk, high = bac >= 0.3, thc >= 3.5
  if (drunk or high) and not a.fled then
    if fault ~= 'Unfallgegner' or bac >= 1.1 then fault = 'Fahrer (du)' end
    why = why .. (drunk and string.format(' – unter Alkoholeinfluss (%s ‰)', (string.format('%.2f', bac):gsub('%.', ','))) or '')
      .. (high and ' – unter Cannabiseinfluss' or '')
  end

  -- the criminal law side, as a theory (German law, roughly): what a court would look at
  local legal, points, prison = {}, 0, false
  local bacText = (string.format('%.2f', bac):gsub('%.', ','))
  if bac >= 1.1 then
    legal[#legal + 1] = string.format('Absolute Fahruntüchtigkeit (%s ‰): Gefährdung des Straßenverkehrs (§ 315c StGB) bzw. Trunkenheit im Verkehr (§ 316 StGB) – Freiheitsstrafe bis zu 5 Jahren, Entzug der Fahrerlaubnis (§ 69 StGB)', bacText)
    points = 3
  elseif drunk and fault == 'Fahrer (du)' then
    legal[#legal + 1] = string.format('Relative Fahruntüchtigkeit (%s ‰ und ein Unfall): § 315c StGB – Freiheitsstrafe bis zu 5 Jahren, Entzug der Fahrerlaubnis', bacText)
    points = 3
  elseif bac >= 0.5 then
    legal[#legal + 1] = string.format('Fahren mit %s ‰ (§ 24a Abs. 1 StVG) – 500 €, 2 Punkte, 1 Monat Fahrverbot', bacText)
    points = math.max(points, 2)
  end
  if high then
    if fault == 'Fahrer (du)' then
      legal[#legal + 1] = 'Fahren unter Cannabiseinfluss mit Unfall: drogenbedingte Fahruntüchtigkeit (§ 315c StGB) – Entzug der Fahrerlaubnis, MPU'
      points = 3
    else
      legal[#legal + 1] = string.format('THC über dem Grenzwert (%.1f ng/ml, Grenzwert 3,5 – § 24a Abs. 1a StVG)%s – 2 Punkte, 1 Monat Fahrverbot',
        thc, bac >= 0.5 and ', zusammen mit Alkohol: 1000 €' or ': 500 €'):gsub('(%d)%.(%d)', '%1,%2')
      points = math.max(points, 2)
    end
  end
  local driverFault = fault == 'Fahrer (du)'
  local inTown = a.limit and a.limit <= 60
  if (peds > 0 or hurt > 0) and (driverFault or fault:find('Teilschuld')) then
    legal[#legal + 1] = 'Fahrlässige Körperverletzung (§ 229 StGB) – Geldstrafe oder Freiheitsstrafe bis zu 3 Jahren'
    points = math.max(points, 2)
    if peds > 0 and a.preSpeed > 60 then
      legal[#legal + 1] = 'Bei tödlichem Ausgang: fahrlässige Tötung (§ 222 StGB) – Freiheitsstrafe bis zu 5 Jahren'
    end
  end
  if a.fled then
    legal[#legal + 1] = 'Unerlaubtes Entfernen vom Unfallort (§ 142 StGB) – Geldstrafe oder Freiheitsstrafe bis zu 3 Jahren, Entzug der Fahrerlaubnis'
    points = 3
  end
  if over >= (inTown and 31 or 41) then
    if peds > 0 or hurt > 0 then
      legal[#legal + 1] = 'Grob verkehrswidrig und rücksichtslos zu schnell: Gefährdung des Straßenverkehrs (§ 315c StGB) – bis zu 5 Jahren'
      points = 3
    else
      legal[#legal + 1] = string.format('Geschwindigkeitsüberschreitung um %d km/h – Fahrverbot (1–3 Monate) und 2 Punkte in Flensburg', math.floor(over))
      points = math.max(points, 2)
    end
  elseif over > 20 then
    points = math.max(points, 1)
  end
  if driverFault and #legal == 0 and n > 0 then legal[#legal + 1] = 'Ordnungswidrigkeit (Verwarnungs- bzw. Bußgeld)'; points = math.max(points, 1) end
  if (peds > 0 and driverFault and a.preSpeed > 50) or (a.fled and (peds > 0 or hurt > 0)) or (over >= 41 and (peds > 0 or hurt > 0))
     or ((bac >= 1.1 or (drunk and high)) and driverFault and (peds > 0 or hurt > 0)) then
    prison = true
  end
  local verdict
  if prison then
    verdict = 'Theorie: Bei dieser Lage wäre im echten Leben eine Freiheitsstrafe realistisch – du würdest wohl ins Gefängnis kommen.'
  elseif #legal > 0 and (peds > 0 or hurt > 0 or a.fled) then
    verdict = 'Theorie: Geldstrafe, Punkte und Fahrverbot; eine Freiheitsstrafe auf Bewährung wäre möglich.'
  elseif #legal > 0 then
    verdict = 'Theorie: eine Ordnungswidrigkeit – Bußgeld, unter Umständen Punkte.'
  end
  local doc = {
    kind = 'accident', title = 'Polizeilicher Unfallbericht', t = os.time(), clock = ctx.clockText(),
    case = string.format('VU-%s-%05d', os.date('%Y'), math.random(10000, 99999)),
    officer = OFFICERS[math.random(#OFFICERS)],
    road = place.road or 'Straße', near = place.near, lat = a.lat, lon = a.lon, limit = a.limit,
    vehicles = n + 1, others = n, trailerHit = a.trailerHit or nil, vehicle = a.vehicle,
    severity = sevName, speed = estText, speedValue = est, fault = fault, reason = why, injured = injured,
    ambulance = a.ambulance or nil, fled = a.fled or nil, damagePct = math.min(100, math.floor(a.dmg / 600)),
    pedestrians = peds > 0 and peds or nil, pedState = pedState, legal = #legal > 0 and legal or nil,
    points = points > 0 and points or nil, prison = prison or nil, verdict = verdict, street = place.street, town = place.town,
    bac = bac >= 0.1 and math.floor(bac * 100 + 0.5) / 100 or nil, thc = thc >= 1 and math.floor(thc * 10 + 0.5) / 10 or nil,
  }
  doc.text = string.format('Am %s um %s Uhr kam es %s%s zu einem Verkehrsunfall (%s) mit %d beteiligten Fahrzeug%s%s%s. '
      .. 'Geschwindigkeit des Fahrzeugs der Spedition vor dem Aufprall: %s%s. Verletzte: %s. Unfallursache: %s.',
    os.date('%d.%m.%Y'), doc.clock, doc.road, doc.near and (' ' .. doc.near) or '', sevName, doc.vehicles,
    doc.vehicles == 1 and '' or 'en', peds > 0 and string.format(', dabei wurde%s %d Fußgänger erfasst', peds > 1 and 'n' or '', peds) or '',
    a.trailerHit and ', der Auflieger wurde beschädigt' or '', estText,
    doc.limit and string.format(' (zulässig: %d km/h)', doc.limit) or '', injured, why)
  if doc.bac or doc.thc then
    doc.text = doc.text .. ' Test vor Ort: ' .. table.concat((function()
      local t = {}
      if doc.bac then t[#t + 1] = 'Atemalkohol ' .. bacText .. ' ‰ (Blutprobe angeordnet)' end
      if doc.thc then t[#t + 1] = (string.format('Drogenvortest positiv auf THC (ca. %.1f ng/ml)', doc.thc):gsub('%.', ',')) end
      return t
    end)(), ', ') .. '.'
  end
  -- the fine when the driver is to blame (a walker hit: a lot more)
  if fault == 'Fahrer (du)' and (n > 0 or a.fled or peds > 0) then
    doc.fine = (a.fled and 600 or (over > 10 and 160 or 100) + 60 * n) + peds * (a.preSpeed > 30 and 1500 or 600)
  elseif fault:find('Teilschuld') and (n > 0 or peds > 0) then
    doc.fine = 55 + peds * 200
  end
  if bac >= 1.1 or (drunk and driverFault) or high then doc.fine = (doc.fine or 0) + (bac >= 1.1 and 2500 or 1000)
  elseif bac >= 0.5 then doc.fine = (doc.fine or 0) + 500 end
  return doc
end

-- the loop ----------------------------------------------------------------------------------------------------

local function relOf(v, ov)
  local d = vec3(v:getDirectionVector())
  d.z = 0
  if d:length() < 0.1 then return 'side' end
  d = d:normalized()
  local rel = vec3(ov:getPosition()) - vehPos(v)
  rel.z = 0
  local along = rel:dot(d)
  local side = math.abs(rel:dot(vec3(d.y, -d.x, 0)))
  if along > 2 and side < 3 then return 'ahead' end
  if along < -2 and side < 3 then return 'behind' end
  return 'side'
end

local function detect(ctx, v, t)
  local id = v:getID()
  if not ctx.busy() then trailAdd(vehPos(v)) end
  -- (2026-11-09: being chased is no accident to report; the way behind goes on being noted, the chasers come along it)
  if M.muted then prev.id = nil; return end
  local dmg = ctx.damageOf(id)
  local sp = ctx.speedKmh()
  if prev.id ~= id then
    prev.id, prev.dmg = id, dmg
    speeds, others = {}, {}
    return
  end
  local jump = dmg - prev.dmg
  -- a walker hit: the truck hardly takes damage from it, the walker does (and is thrown) – a crash as well
  local scan = not acc and scanOthers(ctx, v) or nil
  local pedHit = false
  if scan then
    local here = vehPos(v)
    for oid, o in pairs(scan) do
      local b = others[oid]
      if o.ped and b and (o.dmg - b.dmg > 10 or o.speed > b.speed + 12) and o.pos:distance(here) < 14 then pedHit = true; break end
    end
  end
  -- the dashcam saves its recording on any real knock (from 15 km/h, a noticeable bump) – a police report or not
  local pre = 0
  for _, s in ipairs(speeds) do pre = math.max(pre, s) end
  if (jump > C.IMPACT_DMG or pedHit) and pre >= C.IMPACT_KMH and t - lastImpact > C.IMPACT_GAP_S and not ctx.busy() then
    lastImpact = t
    impactId = string.format('acc%d_%03d', os.time(), math.random(0, 999))
    if ctx.onImpact then pcall(ctx.onImpact, impactId, pre) end
  end
  if not acc and (jump > C.CRASH_DMG or pedHit) and t - lastAt > C.COOLDOWN_S and not ctx.busy() then
    local p = ctx.here()
    local d = vec3(v:getDirectionVector())
    d.z = 0
    -- (the way it came, and the direction of the road: not where the wreck happens to point)
    local atr = {}
    for i, q in ipairs(trail) do atr[i] = q end
    atr[#atr + 1] = vehPos(v)
    if #atr >= 4 then d = flatDir(atr[#atr] - atr[#atr - 3]) or d end
    acc = { t0 = t, pos = vehPos(v), trail = #atr >= 8 and atr or nil, dir = d:length() > 0.1 and d:normalized() or vec3(0, 1, 0),
      lat = p and p.lat, lon = p and p.lon, dmg0 = prev.dmg, preSpeed = pre, limit = ctx.ruleLimit and ctx.ruleLimit() or ctx.roadLimit(),
      base = others, units = {}, vehicle = ctx.vehicleName(), stage = 'settle' }
    -- (the dashcam's recording of this crash: the one just saved, else one now – a slow walker hit, say)
    if impactId and t - lastImpact < 1.5 then acc.id = impactId
    else
      acc.id = string.format('acc%d_%03d', os.time(), math.random(0, 999))
      if ctx.onImpact then pcall(ctx.onImpact, acc.id, pre) end
    end
    lastAt = t
  end
  prev.dmg = dmg
  table.insert(speeds, sp)
  if #speeds > 8 then table.remove(speeds, 1) end
  if not acc then others = scan or scanOthers(ctx, v) end
end

-- the police called: by the scene's rules (others hit), or by the driver from the HUD's phone (M.callPolice)
M.ASK_S = 45
function M.call(ctx, a, t)
  a.stage = 'called'
  ctx.notify(a.ambulance and '⚠ Unfall gemeldet – Polizei und Rettungsdienst sind unterwegs' or '⚠ Unfall gemeldet – die Polizei ist unterwegs', 8)
  ctx.message('Unfall gemeldet. Bleib am Unfallort, bis die Polizei den Bericht aufgenommen hat.', 'Leitstelle')
  pcall(spawnResponder, ctx, 'police', a)
  if a.ambulance then a.ambAt = t + 6 end
end
-- (the HUD's phone: the driver calls; the next update sends them)
function M.callPolice()
  if acc and acc.stage == 'ask' then acc.callNow = true; return true end
  return false
end
-- (the HUD's phone hung up: no police)
function M.dismissCall() if acc and acc.stage == 'ask' then acc = nil end end

-- (2026-11-09) got stuck, crashed, on its roof: it comes back whole on the truck's way, nearer the scene, and drives on from there. The
-- second time it does not work out it is simply put at the scene: whoever was called arrives.
local function recoverUnit(u, a, ctx, t, uv, dd, why)
  u.recovers = (u.recovers or 0) + 1
  local pos, dir
  if u.recovers <= C.MAX_RECOVERS then pos, dir = startOnTrail(a, math.max(70, math.min(dd * 0.55, 200))) end
  if not pos then
    log('I', 'fernfahrer', string.format('responder %s: %s, %.0f m off: put at the scene', u.kind, why, dd))
    park(u, ctx, true)
    return
  end
  pcall(function() uv:requestReset(RESET_PHYSICS) end)
  local rot = quatFromDir(dir, vec3(0, 0, 1))
  local sp = rawget(_G, 'spawn')
  if sp and sp.safeTeleport then pcall(sp.safeTeleport, uv, pos + vec3(0, 0, 0.4), rot, true, nil, false)
  else uv:setPositionRotation(pos.x, pos.y, pos.z + 0.4, rot.x, rot.y, rot.z, rot.w) end
  local before = (a.trail and trailPoint(a.trail, 18)) or a.pos
  u.cmd = responderCmd(u.kind, a, M.nodeAlong(before, a.dir or dir, 180) or M.nodeAlong(pos, dir, 150))
  u.kickT0, u.kickAt, u.p0, u.bestDd, u.bestAt, u.stillT = t, t + 0.4, nil, nil, t, 0
  log('I', 'fernfahrer', string.format('responder %s: %s, %.0f m off: on its way again from nearer (%d)', u.kind, why, dd, u.recovers))
end

-- one responder on its way, one frame
local function driveUnit(u, a, ctx, t, dt, uv)
  local up = vehPos(uv)
  local dest = u.dest or a.pos
  local dd = up:distance(dest)
  local sp = vec3(uv:getVelocity()):length()
  -- (its first order, again until it has really moved: a vehicle just put down has a speed too – that counted as
  -- "on its way" after 0.0 s, the order was lost, it stood there and was put at the scene, in game 2026-11-08)
  if u.cmd then
    local gone = u.p0 and flatDist(up, u.p0) > C.MIN_RUN_M and sp > 1
    if gone or t - (u.kickT0 or u.t0) > 45 then
      log('I', 'fernfahrer', string.format('responder %s: %s after %.1f s', u.kind, gone and 'on its way' or 'did not start', t - (u.kickT0 or u.t0)))
      u.cmd = nil
    elseif t >= (u.kickAt or 0) then
      u.kickAt = t + 1.5
      u.p0 = u.p0 or up
      uv:queueLuaCommand(u.cmd)
    end
  end
  -- is it getting anywhere? (not in the last stretch: there it is meant to crawl; a car on its roof at once)
  if dd >= C.SLOW_M and u.driving then
    if not u.bestDd or dd < u.bestDd - 4 then u.bestDd, u.bestAt = dd, t end
    local okU, upv = pcall(function() return uv:getDirectionVectorUp() end)
    local rolled = okU and upv and upv.z < 0.3
    if rolled or t - (u.bestAt or t) > (u.cmd and C.NO_START_S or C.NO_PROGRESS_S) then
      recoverUnit(u, a, ctx, t, uv, dd, rolled and 'on its side' or 'not getting nearer')
      return
    end
  end
  if dd < C.ARRIVE_M then park(u, ctx, false)
  elseif t - u.t0 > C.DRIVE_TIMEOUT_S or not u.driving then park(u, ctx, up:distance(a.pos) > C.NEAR_SCENE_M)
  elseif dd < C.SLOW_M then
    -- the last metres: to its own free spot, slowing to walking pace
    if not u.cmd and t >= (u.capAt or 0) then
      u.capAt = t + 0.3
      uv:queueLuaCommand(brakeCmd(dd))
    end
    if not u.cmd and not u.slow and dd < 42 then
      u.slow, u.slowAt = true, t
      uv:queueLuaCommand(sidewaysCmd(uv, up, dest))
    end
    -- (past its spot – the road did not lead right over it: it stops here)
    if u.slow and (dest - up):dot(u.ddir or a.dir) < -1 then park(u, ctx, false)
    elseif sp < 0.5 then
      u.stillT = (u.stillT or 0) + dt
      -- stopped short: near enough stays where it is; else once more, and only then it is put there
      if u.stillT > C.STUCK_S then
        if up:distance(a.pos) <= C.NEAR_SCENE_M then park(u, ctx, false)
        elseif not u.retried then u.retried, u.stillT = true, 0; uv:queueLuaCommand(sidewaysCmd(uv, up, dest))
        else park(u, ctx, true) end
      end
    else
      u.stillT = 0
    end
  end
end

-- (2026-11-08) the breakdown service: on the responders' way – it starts back along the road the truck came and drives up
local svc = nil
function M.serviceStart(ctx)
  local v = ctx.playerVeh()
  if not v or svc then return false end
  local atr = {}
  for i, q in ipairs(trail) do atr[i] = q end
  atr[#atr + 1] = vehPos(v)
  local d = vec3(v:getDirectionVector())
  d.z = 0
  if #atr >= 4 then d = flatDir(atr[#atr] - atr[#atr - 3]) or d end
  local s = { pos = vehPos(v), dir = d:length() > 0.1 and d:normalized() or vec3(0, 1, 0), trail = #atr >= 8 and atr or nil,
    limit = ctx.ruleLimit and ctx.ruleLimit() or ctx.roadLimit(), units = {} }
  local ok, err = pcall(spawnResponder, ctx, 'service', s)
  if not ok then log('W', 'fernfahrer', 'service: ' .. tostring(err)) end
  if #s.units == 0 then return false end
  svc = s
  return true
end
function M.serviceTick(ctx, dt)
  if not svc then return end
  local u = svc.units[1]
  local uv = u and getObjectByID(u.id)
  if not uv then svc = nil; return end
  local t = now()
  if svc.leftAt then
    releaseTick(u, t)
    local v = ctx.playerVeh()
    if t - svc.leftAt > 40 or (v and vehPos(v):distance(vehPos(uv)) > C.GONE_M) then clearUnits(svc); svc = nil end
    return
  end
  if not u.arrived then driveUnit(u, svc, ctx, t, dt, uv) end
end
-- 'coming' or 'there', and how far off; nil: nobody on the way
function M.serviceState()
  local u = svc and svc.units[1]
  local uv = u and getObjectByID(u.id)
  if not uv then return nil end
  if u.arrived then return 'there', 0 end
  return 'coming', vehPos(uv):distance(svc.pos)
end
-- (2026-11-10) the service car, for its mechanic to get out of
function M.serviceCar()
  local u = svc and svc.units[1]
  return u and u.id or nil
end
function M.serviceLeave()
  local u = svc and svc.units[1]
  if not u then return end
  svc.leftAt = now()
  release(u, svc)
end
function M.serviceCancel()
  if svc then clearUnits(svc); svc = nil end
end

function M.update(ctx, dt)
  local t = now()
  if t - sampleT < C.SAMPLE_S then
    if not acc then return end
  else
    sampleT = t
    local v = ctx.playerVeh()
    if v then detect(ctx, v, t) end
  end
  if not acc then return end
  local a = acc
  local v = ctx.playerVeh()
  local here = v and vehPos(v)
  local away = here and here:distance(a.pos) or 0

  if a.stage == 'settle' and t - a.t0 >= C.SETTLE_S then
    a.dmg = v and math.max(0, ctx.damageOf(v:getID()) - a.dmg0) or 0
    a.involved = {}
    a.peds = 0
    local tid = ctx.trailerId()
    for id, b in pairs(a.base) do
      local o = map and map.objects and map.objects[id]
      local ov = getObjectByID(id)
      if o and ov then
        local gained, dd = (o.damage or 0) - b.dmg, vec3(o.pos):distance(a.pos)
        if b.ped then
          -- a walker hit: damage taken, or thrown far from where it stood
          if (gained > 10 and dd < C.NEAR_M + 15) or (b.pos and vec3(o.pos):distance(b.pos) > 6 and dd < C.NEAR_M + 25) then a.peds = a.peds + 1 end
        elseif gained > C.OTHER_DMG and dd < C.NEAR_M + 10 then
          if id == tid then a.trailerHit = true
          else table.insert(a.involved, { id = id, speed = b.speed or 0, rel = v and relOf(v, ov) or 'side' }) end
        end
      end
    end
    if a.dmg < C.MIN_REPORT_DMG and #a.involved == 0 and a.peds == 0 then acc = nil; return end   -- (a scrape)
    local score = a.dmg + #a.involved * 9000 + a.peds * 20000
    a.severity = score > 30000 and 'schwer' or (score > 10000 and 'mittel' or 'leicht')
    if a.peds > 0 and a.preSpeed > 25 then a.severity = 'schwer' end
    a.ambulance = a.severity ~= 'leicht' or a.peds > 0
    -- (2026-11-05: alone into something – nobody else hit: the driver is asked (the HUD's phone) whether to call the
    -- police; not called, nobody comes and there is no fine. Others hit: they come as before.)
    if #a.involved == 0 and a.peds == 0 then
      a.stage, a.askAt = 'ask', t
      return
    end
    M.call(ctx, a, t)
    return
  end
  if a.stage == 'ask' then
    if a.callNow then a.callNow = nil; M.call(ctx, a, t); return end
    -- (not called: forgotten after ASK_S, or once the driver drives on)
    if t - a.askAt > M.ASK_S or away > 150 then acc = nil end
    return
  end
  if a.stage == 'settle' then return end

  if a.ambAt and t > a.ambAt then a.ambAt = nil; pcall(spawnResponder, ctx, 'ambulance', a) end

  -- on the way / at the scene
  local police
  for _, u in ipairs(a.units) do
    local uv = getObjectByID(u.id)
    if uv and not u.arrived then driveUnit(u, a, ctx, t, dt, uv) end
    if u.kind == 'police' then police = u end
  end
  -- leaving the scene before the police are there
  if a.stage == 'called' and away > 300 and not a.fled then a.fled = true end

  -- the scene photographed once the police stand there (their lights in the pictures)
  -- (when the ambulance is there too – or 12 s after the police, whichever first: all of the scene in the pictures)
  local ambThere = not a.ambulance
  for _, u in ipairs(a.units) do if u.kind == 'ambulance' and u.arrived then ambThere = true end end
  if a.stage == 'called' and police and police.arrived and not a.photographed and ctx.photos
     and t - police.at > 2 and (ambThere or t - police.at > 12) then
    a.photographed = true
    -- everything that belongs to the scene: the crash, the truck, its trailer, the others hit, the responders
    local pts = { a.pos }
    if v then pts[#pts + 1] = vehPos(v) end
    local tv = ctx.trailerId() and getObjectByID(ctx.trailerId())
    if tv and vehPos(tv):distance(a.pos) < 80 then pts[#pts + 1] = vehPos(tv) end
    for _, inv in ipairs(a.involved or {}) do
      local ov = getObjectByID(inv.id)
      if ov and vehPos(ov):distance(a.pos) < 80 then pts[#pts + 1] = vehPos(ov) end
    end
    for _, u in ipairs(a.units) do
      local uv = getObjectByID(u.id)
      if uv and u.arrived and vehPos(uv):distance(a.pos) < 80 then pts[#pts + 1] = vehPos(uv) end
    end
    local okP, list = pcall(ctx.photos, a.id, pts, a.dir)
    a.photos = okP and list or nil
  end
  if a.stage == 'called' and police and police.arrived and t - police.at > C.REPORT_S and (a.photographed or not ctx.photos) then
    local okR, doc = pcall(buildReport, ctx, a)
    if okR and doc then
      doc.photos, doc.camId = a.photos, a.id
      if ctx.attachClip then pcall(ctx.attachClip, a.id, doc) end
      ctx.addDocument(doc)
      if ctx.onReport then pcall(ctx.onReport, doc) end
      ctx.notify('📄 Unfallbericht aufgenommen (' .. doc.case .. ') – im Büro unter Dokumente', 8)
      ctx.message(string.format('%s: Bericht %s aufgenommen. Schuld: %s.', doc.officer, doc.case, doc.fault), 'Polizei')
      if doc.fine then ctx.fine(doc.fine, 'Verkehrsunfall: ' .. doc.reason) end
    else
      log('W', 'fernfahrer', 'accident report: ' .. tostring(doc))
    end
    a.stage, a.reportedAt = 'reported', t
  elseif a.stage == 'called' and a.fled and (not police or not police.arrived) and t - a.t0 > 25 then
    -- gone: the report is written without the driver
    local okR, doc = pcall(buildReport, ctx, a)
    if okR and doc then
      doc.camId = a.id
      if ctx.attachClip then pcall(ctx.attachClip, a.id, doc) end
      ctx.addDocument(doc)
      if ctx.onReport then pcall(ctx.onReport, doc) end
      if doc.fine then ctx.fine(doc.fine, 'Unfallflucht') end
      ctx.message('Unfallflucht wird verfolgt – Bericht ' .. doc.case .. ' liegt im Büro.', 'Polizei')
    end
    a.stage, a.reportedAt = 'reported', t
  end

  if a.stage == 'reported' and t - a.reportedAt > C.LEAVE_S and not a.left then
    a.left = true
    for _, u in ipairs(a.units) do release(u, a) end
  end
  if a.left then for _, u in ipairs(a.units) do releaseTick(u, t) end end
  if (a.left and (away > C.GONE_M or t - a.reportedAt > C.LEAVE_S + 60)) or t - a.t0 > C.MAX_AGE_S
     or (a.stage == 'reported' and away > C.GONE_M) then
    clearUnits(a)
    acc = nil
  end
end

M._buildReport = function(ctx, a) return buildReport(ctx, a) end   -- (for the offline check)

-- for trafficai.lua: traffic slows down past the scene, both ways
function M.zones()
  if not acc or acc.stage == 'settle' or not acc.dir then return nil end
  local d = acc.dir
  return {
    { pos = acc.pos - d * 25, dir = d, len = 55, limit = 30, kind = 'accident' },
    { pos = acc.pos + d * 25, dir = -d, len = 55, limit = 30, kind = 'accident' },
  }
end

-- the HUD's line: what is going on at the scene
function M.hud()
  if not acc or acc.stage == 'settle' then return nil end
  if acc.stage == 'ask' then
    return { ask = true, left = math.max(0, math.ceil(M.ASK_S - (now() - acc.askAt))), severity = acc.severity }
  end
  local arrived, total = 0, #acc.units
  for _, u in ipairs(acc.units) do if u.arrived then arrived = arrived + 1 end end
  if acc.stage == 'called' then
    return { text = arrived > 0 and 'Polizei am Unfallort – Bericht wird aufgenommen' or
      ('Unfall gemeldet – ' .. (acc.ambulance and 'Polizei und Rettungsdienst' or 'Polizei') .. ' unterwegs'), arrived = arrived, total = total }
  end
  return nil
end

-- Earth's origin shift: everything kept in world coordinates moves with the world
function M.transform(xf)
  local function mv(p) local x, y, z = xf:apply(p.x, p.y, p.z); return vec3(x, y, z) end
  for i, p in ipairs(trail) do trail[i] = mv(p) end
  if svc then
    svc.pos = mv(svc.pos)
    if svc.trail then for i, p in ipairs(svc.trail) do svc.trail[i] = mv(p) end end
    for _, u in ipairs(svc.units) do
      if u.dest then u.dest = mv(u.dest) end
      if u.p0 then u.p0 = mv(u.p0) end
    end
  end
  if acc then
    acc.pos = mv(acc.pos)
    if acc.trail then for i, p in ipairs(acc.trail) do acc.trail[i] = mv(p) end end
    for _, u in ipairs(acc.units or {}) do
      if u.dest then u.dest = mv(u.dest) end
      if u.p0 then u.p0 = mv(u.p0) end
    end
  end
end

function M.reset()
  if acc then clearUnits(acc) end
  if svc then clearUnits(svc); svc = nil end
  trail = {}
  acc = nil
  prev = { id = nil, dmg = 0 }
end

return M
