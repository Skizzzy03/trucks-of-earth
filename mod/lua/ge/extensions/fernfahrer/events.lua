-- Trucks of Earth: things that happen on the road, on the planned BeamNG.Earth route ahead of the player:
-- roadworks (warning signs, the limit, no overtaking, a taper of arrow boards, red/white barriers along the road's
-- edge, a work site with an excavator, heaps, floodlights, a fence; sometimes a speed camera), speed camera posts that
-- flash, police checks (a parked patrol car with its lights on, cones, a marked bay to stop in; the tachograph, the
-- vehicle and the cargo are checked).
-- Where: the route (lat / lon) decides where an event is; the scenery is laid out on the game's road graph there
-- (the road's centre line, direction and real width – priority.lua keeps the asphalt's width before it widens the
-- lanes for the AI), so it stands at the actual edge of the road and faces the traffic. Static meshes from the
-- game's own art (TSStatic, no collision, no physics), a few per frame. Only the patrol car is a vehicle (frozen).
-- career.lua calls M.update(ctx, dt) every frame and reads M.hud() / M.limitOverride() / M.zones(); ctx:
--   here() -> {lat, lon}; speedKmh(); roadLimit(); routePoints() -> {{lat, lon}...}; anchor(); hasJob(); playerPos();
--   fine(amount, reason); notify(text, ttl); message(text); story(key); controlCheck() -> list of {amount, reason}
-- Add-ons can add kinds: M.KINDS[key] = { weight, make(ev, ctx), spawn(ev, ctx), update(ev, ctx, dt, p) }.

local M = {}

M.C = {
  CHECK_S = 20,
  GAP_S = 150,              -- (more happens on the road: was 240 s / 0.4, roadworks were nearly all, 2026-11-04)
  CHANCE = 0.55,
  AHEAD_M = { 1200, 2000 },
  ANNOUNCE_M = 900,
  SPAWN_M = 700,
  PER_FRAME = 6,
  ZONE_M = 320,
  PRE_M = 300,              -- the warning signs stand up to this far before the start
  PASS_M = 35,
  CONTROL_STOP_S = 4,
  MAX_AGE_S = 600,
}
local C = M.C

local ev = nil
local lastAt = -math.huge
local lastRoll = 0
local function now() return os.clock() end
local function flat(v) local w = vec3(v.x, v.y, 0); local l = w:length(); return l > 1e-3 and w * (1 / l) or nil end

local function haversine(a, b)
  local p1, p2 = math.rad(a.lat), math.rad(b.lat)
  local dp, dl = p2 - p1, math.rad(b.lon - a.lon)
  local x = math.sin(dp / 2) ^ 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ^ 2
  return 2 * 6371000 * math.asin(math.min(1, math.sqrt(x)))
end

function M.speedFine(over)
  if over <= 10 then return 30 elseif over <= 15 then return 70 elseif over <= 20 then return 80
  elseif over <= 25 then return 95 elseif over <= 30 then return 140 elseif over <= 40 then return 200
  elseif over <= 50 then return 320 end
  return 480
end

-- the scenery ---------------------------------------------------------------------------------------------------
-- yaw: degrees added to the road's direction (0: the mesh's front faces the oncoming driver – for these meshes
-- their +y axis points along the road); long-x meshes are turned 90°. wcu: needs West Coast USA's object materials.

local WCU = '/levels/west_coast_usa/art/shapes/objects/'
local CLUTTER = '/art/shapes/garage_and_dealership/Clutter/'
M.SHAPES = {
  board      = { '/art/shapes/objects/constructionbarrier_arrows.dae' },   -- (2 m along its y: parallel to the road)
  barrierRed = { CLUTTER .. 'hr_plasticbarrier_red.DAE', yaw = 90 },
  barrier    = { CLUTTER .. 'hr_plasticbarrier.DAE', yaw = 90 },
  barrel     = { '/assets/meshes/props/race_event/equipment/s_trafficbarrel_01.dae' },
  cone       = { CLUTTER .. 'road_cone.DAE' },
  jersey     = { '/art/shapes/objects/jerseybarrier_3m.dae' },
  slab       = { CLUTTER .. 'concrete_road_barrier_a.dae', yaw = 90 },
  pile       = { CLUTTER .. 'big_pile.DAE', scale = 2.4 },
  pileSmall  = { CLUTTER .. 'medium_pile.DAE', scale = 2.0 },
  signWork   = { '/art/shapes/objects/construction_sign_big_a.DAE' },
  sign30     = { CLUTTER .. 'italy_traf_sign_speed_30.dae' },
  sign50     = { CLUTTER .. 'italy_traf_sign_speed_50.dae' },
  sign60     = { CLUTTER .. 'italy_traf_sign_speed_60.dae' },
  sign80     = { CLUTTER .. 'italy_traf_sign_speed_80.dae' },
  signNoPass = { CLUTTER .. 'italy_traf_sign_no_overtaking.dae' },
  signNarrow = { CLUTTER .. 'italy_traf_sign_warn_road_narrows.dae' },
  signDanger = { CLUTTER .. 'italy_traf_sign_warn_other_danger.dae' },
  signKeepL  = { CLUTTER .. 'italy_traf_sign_keep_left.dae' },
  fence      = { WCU .. 'constructionbarrier.dae', wcu = true },
  sandbarrel = { WCU .. 'sandbarrel.dae', wcu = true },
  flood      = { WCU .. 'floodlight_portable.dae', wcu = true, yaw = 180 },
  excavator  = { WCU .. 'excavator.dae', yaw = 70 },
  camPole    = { WCU .. 's_camera_pole.dae', wcu = true, scale = 0.72 },
  camBox     = { WCU .. 's_camera_speed1.dae', wcu = true, yaw = 180 },
  -- (the mod's own, tools/build_props.js)
  triangle   = { '/levels/beamng_earth/art/shapes/fernfahrer/props/ff_triangle.dae' },
  crate      = { '/levels/beamng_earth/art/shapes/fernfahrer/props/ff_crate.dae' },
  pallet     = { '/levels/beamng_earth/art/shapes/fernfahrer/props/ff_pallet.dae' },
}

local wcuLoaded = false
local function needWcu()
  if wcuLoaded then return end
  wcuLoaded = true
  local f = WCU .. 'main.materials.json'
  if FS:fileExists(f) and loadJsonMaterialsFile then pcall(loadJsonMaterialsFile, f) end
end

local function rotZ(v, deg)
  local a = math.rad(deg)
  local c, s = math.cos(a), math.sin(a)
  return vec3(v.x * c - v.y * s, v.x * s + v.y * c, 0)
end

local function ground(pos)
  local top = vec3(pos.x, pos.y, pos.z + 30)
  local hit = castRayStatic(top, vec3(0, 0, -1), 80)
  if not hit or hit >= 80 then return nil end
  return vec3(pos.x, pos.y, top.z - hit)
end

local propN = 0
local function makeStatic(key, pos, dir, extraYaw, lift)
  local s = M.SHAPES[key]
  if not s then return nil end
  if s.wcu then needWcu() end
  local o = createObject('TSStatic')
  if not o then return nil end
  o:setField('shapeName', 0, s[1])
  local sc = s.scale or 1
  o.scale = vec3(sc, sc, sc)
  o.useInstanceRenderData = true
  o:setField('instanceColor', 0, '1 1 1 1')
  o:setField('collisionType', 0, 'None')
  o:setField('decalType', 0, 'None')
  o.canSave = false
  propN = propN + 1
  o:registerObject('ff_ev_' .. propN)
  -- (+y along the travel direction: the signs' faces towards the driver coming along `dir` – with a turn of 180°
  -- they stood back to front, in game 2026-11-03)
  local d = rotZ(dir, (s.yaw or 0) + (extraYaw or 0))
  local rot = quatFromDir(d, vec3(0, 0, 1))
  o:setPosRot(pos.x, pos.y, pos.z + (lift or 0), rot.x, rot.y, rot.z, rot.w)
  return o:getID()
end

local function makeLight(pos, color, brightness, radius)
  local l = createObject('PointLight')
  if not l then return nil end
  l.canSave = false
  pcall(function()
    l.radius = radius or 30
    l:setField('color', 0, color or '1 0.97 0.92 1')
    l:setField('brightness', 0, tostring(brightness or 12))
    l:setField('castShadows', 0, '0')
    l.isEnabled = false
  end)
  propN = propN + 1
  l:registerObject('ff_ev_flash_' .. propN)
  l:setPosition(pos)
  return l:getID()
end

function M.protect(id)
  if not id then return end
  pcall(function()
    local own = require('realAITraffic/trafficAI/vehicleOwnership')
    if own and own.markPlayerOwned then own.markPlayerOwned(id) end
  end)
end

-- the patrol car: from the pool (spawned in advance: no hitch here), parked facing the traffic's way, lights on
local pool = require('fernfahrer/pool')
local accidents = require('fernfahrer/accidents')
local function spawnVehicle(kind, pos, dir)
  local id = pool.take(kind, pos + vec3(0, 0, 0.3), dir)
  local veh = id and getObjectByID(id)
  if not veh then log('W', 'fernfahrer', 'event vehicle ' .. tostring(kind) .. ': none'); return nil end
  veh:queueLuaCommand('ai.setMode("disabled") controller.setFreeze(1) electrics.set_lightbar_signal(1) electrics.set_warn_signal(1)')
  M.protect(id)
  return id
end

-- the route ------------------------------------------------------------------------------------------------------

-- the route point `meters` further along from the one nearest `from`; returns the point and its index
local function along(points, from, meters, startIdx)
  if not points or #points < 2 then return nil end
  local i0 = startIdx
  if not i0 then
    local bd
    for i, p in ipairs(points) do
      local d = haversine(from, { lat = p[1], lon = p[2] })
      if not bd or d < bd then i0, bd = i, d end
    end
    if bd > 200 then return nil end
  end
  local acc, a = 0, from
  for i = i0, #points - 1 do
    local b = { lat = points[i + 1][1], lon = points[i + 1][2] }
    local seg = haversine(a, b)
    if seg > 0.5 and acc + seg >= meters then
      local f = (meters - acc) / seg
      return { lat = a.lat + (b.lat - a.lat) * f, lon = a.lon + (b.lon - a.lon) * f }, i
    end
    acc = acc + seg
    a = b
  end
  return nil
end

-- the road at the event: the game's road graph from PRE_M before the start to past the zone, as a polyline of
-- { s (m from the start), pos (centre line), half (the asphalt's half width) }
local function realHalf(a, b, link)
  local ok, pr = pcall(require, 'fernfahrer/priority')
  local h = ok and pr.realHalf and pr.realHalf(a, b)
  return h or (link and (link.inRadius or link.outRadius)) or 2.75
end

local function nextNode(nodes, prev, cur, heading)
  local best, bestDot = nil, 0.3
  for m in pairs(nodes[cur].links or {}) do
    if m ~= prev and nodes[m] then
      local d = flat(nodes[m].pos - nodes[cur].pos)
      if d and d:dot(heading) > bestDot then best, bestDot = m, d:dot(heading) end
    end
  end
  return best
end

local function buildLine(e, ctx)
  local anchor = ctx.anchor()
  if not anchor or not anchor.geodeticToWorld or not (map and map.findClosestRoad and map.getMap) then return nil, 'no anchor / map' end
  local x, y, z = anchor:geodeticToWorld(e.start.lat, e.start.lon, 0)
  local q = along(e.points, e.start, 40, e.startIdx)
  if not q then return nil, 'route ends' end
  local x2, y2 = anchor:geodeticToWorld(q.lat, q.lon, 0)
  local hint = flat(vec3(x2 - x, y2 - y, 0))
  if not hint then return nil, 'no direction' end
  -- the height: geodeticToWorld(.., 0) is at sea level, the road at the ground's height (often 50-200 m up: the
  -- road search found nothing, 2026-11-03). From the player's height a ray down to the ground there.
  local pp = ctx.playerPos and ctx.playerPos()
  local zGuess = pp and pp.z or z
  local hit = castRayStatic(vec3(x, y, zGuess + 300), vec3(0, 0, -1), 800)
  local s0 = vec3(x, y, (hit and hit < 800) and (zGuess + 300 - hit) or zGuess)
  local nodes = map.getMap().nodes
  local okR, n1, n2, dist = pcall(map.findClosestRoad, s0)
  if not okR or not n1 or not n2 or not nodes[n1] or not nodes[n2] or (dist and dist > 40) then
    -- the nearest graph edge on the map (flat distance)
    n1, n2 = nil, nil
    local bd
    for a, na in pairs(nodes) do
      local dx, dy = na.pos.x - x, na.pos.y - y
      if dx * dx + dy * dy < 250000 then              -- (within 500 m)
        for b in pairs(na.links or {}) do
          local nb = nodes[b]
          if nb then
            local ab = vec3(nb.pos.x - na.pos.x, nb.pos.y - na.pos.y, 0)
            local l2 = ab:squaredLength()
            if l2 > 0.01 then
              local tt = math.max(0, math.min(1, ((x - na.pos.x) * ab.x + (y - na.pos.y) * ab.y) / l2))
              local px, py = na.pos.x + ab.x * tt - x, na.pos.y + ab.y * tt - y
              local d2 = px * px + py * py
              if not bd or d2 < bd then n1, n2, bd = a, b, d2 end
            end
          end
        end
      end
    end
    if not n1 or bd > 3600 then return nil, string.format('no road within 60 m (findClosestRoad %s m)', tostring(dist)) end
  end
  local a, b = n1, n2
  if (nodes[b].pos - nodes[a].pos):dot(hint) < 0 then a, b = b, a end
  -- s of the start on edge a -> b
  local ab = nodes[b].pos - nodes[a].pos
  local sOnEdge = math.max(0, math.min(ab:length(), (s0 - nodes[a].pos):dot(flat(ab) or hint)))
  local pts = {}
  -- backwards from a
  local back = { { s = -sOnEdge, node = a } }
  do
    local prev, cur, s = b, a, -sOnEdge
    while s > -(C.PRE_M + 30) do
      local h = flat(nodes[cur].pos - nodes[prev].pos)
      local nx = h and nextNode(nodes, prev, cur, h)
      if not nx then break end
      s = s - nodes[cur].pos:distance(nodes[nx].pos)
      table.insert(back, { s = s, node = nx, from = cur })
      prev, cur = cur, nx
    end
  end
  for i = #back, 1, -1 do table.insert(pts, back[i]) end
  -- forwards from b
  do
    local prev, cur, s = a, b, ab:length() - sOnEdge
    table.insert(pts, { s = s, node = b })
    while s < C.ZONE_M + 80 do
      local h = flat(nodes[cur].pos - nodes[prev].pos)
      local nx = h and nextNode(nodes, prev, cur, h)
      if not nx then break end
      s = s + nodes[cur].pos:distance(nodes[nx].pos)
      table.insert(pts, { s = s, node = nx })
      prev, cur = cur, nx
    end
  end
  local line = {}
  for i, pt in ipairs(pts) do
    local nb = pts[i + 1] or pts[i - 1]
    local link = nb and nodes[pt.node].links[nb.node]
    line[i] = { s = pt.s, pos = vec3(nodes[pt.node].pos), half = realHalf(pt.node, nb and nb.node, link) }
  end
  if #line < 2 then return nil end
  return line
end

-- the frame at s: centre line point, direction of travel, the asphalt's half width
local function frameAt(e, s)
  local line = e.line
  if not line then return nil end
  for i = 2, #line do
    if line[i].s >= s or i == #line then
      local A, B = line[i - 1], line[i]
      local d = flat(B.pos - A.pos)
      if not d then return nil end
      local f = (s - A.s) / math.max(0.01, B.s - A.s)
      if f < -0.5 or f > 1.5 then return nil end
      return A.pos + (B.pos - A.pos) * f, d, A.half + (B.half - A.half) * math.max(0, math.min(1, f))
    end
  end
end

-- one item: { at = s, edge = metres outward from the asphalt's right edge (negative: onto the road), key | vehicle | light }
local function buildOne(e, item)
  local pos, dir, half = frameAt(e, item.at)
  if not pos then e.failed = (e.failed or 0) + 1; return end
  local right = vec3(dir.y, -dir.x, 0)
  local g = ground(pos + right * (half + (item.edge or 0)))
  if not g then e.failed = (e.failed or 0) + 1; return end
  local id
  if item.vehicle then
    id = spawnVehicle(item.vehicle, g, dir)
  elseif item.light then
    id = makeLight(g + vec3(0, 0, item.lift or 3))
    e.flashLight = id
  elseif item.sig then
    -- (the site traffic light's lamps: a coloured light each)
    local isRed = item.sig == 'red'
    id = makeLight(g + vec3(0, 0, item.lift or 3.4), isRed and '1 0.08 0.05 1' or '0.1 1 0.3 1', 22, 9)
    if isRed then e.sigRedId = id else e.sigGreenId = id end
  elseif item.lamp then
    -- (a working light that stays on, night roadworks)
    id = makeLight(g + vec3(0, 0, item.lift or 5), '1 0.95 0.82 1', 8, 34)
    local l = id and getObjectByID(id)
    if l then pcall(function() l.isEnabled = true end) end
  else
    id = makeStatic(item.key, g, dir, item.yaw, item.lift)
  end
  if id then table.insert(e.props, id); e.placed = (e.placed or 0) + 1 else e.failed = (e.failed or 0) + 1 end
end

-- (2026-11-08) an order to a vehicle that has only just been spawned or woken up is lost (ai.setMode returns at once
-- while it has no wheels yet): it is given again until the vehicle moves. fn() -> the command, fresh each time.
local function kickTick(e, t)
  if not e.unit or not e.kickFn or t < (e.kickAt or 0) then return end
  local v = getObjectByID(e.unit)
  if not v then e.kickFn = nil; return end
  local sp = vec3(v:getVelocity()):length()
  -- (a vehicle just put down has a speed too: moved is moved)
  local vp = vec3(v:getPosition())
  e.kickP0 = e.kickP0 or vp
  local gone = sp > 3 and (vp - e.kickP0):length() > 5
  if gone or t - (e.unitAt or t) > 30 then
    log('I', 'fernfahrer', string.format('%s: unit %s after %.1f s (%.1f m/s)', e.kind, gone and 'on its way' or 'did not start', t - e.unitAt, sp))
    e.kickFn = nil
    return
  end
  e.kickAt = t + 1.5
  local cmd = e.kickFn()
  if cmd then v:queueLuaCommand(cmd) end
end

local function queue(e, list)
  e.queue = e.queue or {}
  e.items = e.items or {}
  for _, it in ipairs(list) do table.insert(e.queue, it); table.insert(e.items, it) end
end

-- (2026-11-11: "um die Baustelle drumherum fahren und nicht einfach durch" - the props have no collision on purpose, so the traffic could
-- squeeze past in an emergency; it drove straight through them. What is shut, worked out from what was put on the road: from the
-- innermost piece standing on the asphalt to the right-hand edge, from the first to the last of them. Road-lateral (metres right of the
-- centre line, in the zone's direction) and along the zone from its start (s). Signs, lights and the camera stand beside the road)
local function blockOf(e)
  local s0, s1, l0
  for _, it in ipairs(e.items or {}) do
    local k = it.key or (it.vehicle and 'vehicle') or ''
    if it.at and (it.edge or 0) < -0.25 and not k:find('^sign') and not k:find('^cam') and k ~= 'flood' and k ~= 'triangle' then
      local _, _, half = frameAt(e, it.at)
      if half then
        local lat = half + it.edge - (it.vehicle and 1.0 or 0.4)
        s0, s1 = math.min(s0 or it.at, it.at), math.max(s1 or it.at, it.at)
        l0 = math.min(l0 or lat, lat)
      end
    end
  end
  if not s0 then return nil end
  return { s0 = s0 - 3, s1 = s1 + 3, l0 = l0, l1 = 99 }
end
M._blockOf = blockOf

-- the police check's bay: the stock parking-spot marker
local function showBay(e)
  local pos, dir, half = frameAt(e, e.bayAt)
  if not pos then return end
  local right = vec3(dir.y, -dir.x, 0)
  local g = ground(pos + right * (half - 0.5))
  if not g then return end
  local okC, Ctor = pcall(require, 'scenario/raceMarkers/parkingraceSpotMarker')
  if not okC or type(Ctor) ~= 'function' then return end
  local mk = Ctor('fernfahrerControl')
  mk:createMarkers()
  local scl = vec3(4.0, 22, 1)
  mk:setSpot(g, quatFromDir(dir, vec3(0, 0, 1)), scl)
  mk:setColor({ 0.3, 0.6, 1, 1 })
  mk:show()
  e.bay = { marker = mk, pos = g, dir = dir, scl = scl }
end

local function inBay(e, pos)
  local b = e.bay
  if not b or not pos then return false end
  local d = pos - b.pos
  return math.abs(d:dot(b.dir)) <= b.scl.y / 2 + 3 and math.abs(d:dot(vec3(b.dir.y, -b.dir.x, 0))) <= b.scl.x / 2 + 1.5
end

local function clearProps(e)
  for _, id in ipairs(e and e.props or {}) do
    if pool.owns(id) then pool.give(id)
    else
      local o = getObjectByID(id)
      if o then o:delete() end
    end
  end
  if e and e.bay then pcall(function() e.bay.marker:hide(); e.bay.marker:clearMarkers() end); e.bay = nil end
  if e then e.props, e.queue = {}, nil end
end

local function cameraPost(at, edge)
  return {
    { at = at, edge = edge, key = 'camPole' },
    { at = at, edge = edge, key = 'camBox', lift = 3.35 },
    { at = at, edge = edge - 0.4, light = true, lift = 3.3 },
    { at = at - 3, edge = edge + 0.5, key = 'cone' },
    { at = at + 3, edge = edge + 0.5, key = 'cone' },
  }
end

local function fireFlash(e)
  M.flashAt = now()
  local l = e and e.flashLight and getObjectByID(e.flashLight)
  if l then l.isEnabled = true; e.flashOff = now() + 0.18 end
end

-- the kinds ---------------------------------------------------------------------------------------------------

M.KINDS = {}

-- (2026-11-08: different roadworks, each laid out from the same pieces: { title, sub, weight, zone (m), limit(road),
-- build(list, Z, lane, sign, e) }; lane: how far into the road the closed strip reaches (own lane, m). `night`: only in
-- the dark, `signal`: an alternating traffic light in front.)
local function ins(list, it) list[#list + 1] = it end
local function warnSigns(list, sign, far)
  ins(list, { at = far and -280 or -200, edge = 1.2, key = 'signWork' })
  ins(list, { at = far and -200 or -140, edge = 1.2, key = 'signNarrow' })
  ins(list, { at = -130, edge = 1.2, key = sign })
  if far then ins(list, { at = -110, edge = 1.2, key = 'signNoPass' }) end
  ins(list, { at = -45, edge = 1.2, key = sign })
end
local function endBoards(list, Z) for k = 0, 3 do ins(list, { at = Z + 2 + k * 6, edge = 0.3 + k * 0.4, key = 'board' }) end end
-- the closed strip's slanted start, boards from the shoulder to `lane` into the road
local function taper(list, lane, len)
  local n = math.max(4, math.floor(len / 6))
  for k = 0, n do ins(list, { at = -len + k * (len / n), edge = 1.2 - (1.2 + lane) * (k / n), key = 'board' }) end
end
M.ROADWORKS = {
  -- the original: work beside the road, barriers along the asphalt's edge
  rand = { title = 'Arbeiten am Fahrbahnrand', sub = 'Rechts wird gearbeitet', weight = 3, zone = 320,
    limit = function(road) return road >= 100 and 80 or (road >= 70 and 60 or 30) end,
    build = function(list, Z, lane, sign, e)
      warnSigns(list, sign, true)
      for k = 0, 5 do ins(list, { at = -36 + k * 6, edge = 1.6 - k * 0.32, key = 'board' }) end
      local n = 0
      for a = 4, Z - 6, 8 do
        n = n + 1
        ins(list, { at = a, edge = 0.1, key = n % 2 == 0 and 'barrierRed' or 'barrier' })
        if n % 2 == 1 then ins(list, { at = a + 4, edge = 0.15, key = 'barrel' }) end
        if n % 7 == 0 then ins(list, { at = a + 4, edge = 0.3, key = 'board' }) end
      end
      local w = Z * 0.35
      for _, it in ipairs({
        { at = 8, edge = 1.4, key = 'sandbarrel' }, { at = 10, edge = 2.3, key = 'sandbarrel' }, { at = 12, edge = 3.2, key = 'sandbarrel' },
        { at = w - 30, edge = 2.0, key = 'flood' }, { at = w, edge = 4.5, key = 'excavator' }, { at = w + 18, edge = 4.0, key = 'pile' },
        { at = w + 34, edge = 2.8, key = 'pileSmall' }, { at = w + 48, edge = 2.0, key = 'slab' }, { at = w + 48, edge = 2.0, key = 'slab', lift = 1.2 },
        { at = w + 52, edge = 2.0, key = 'slab' }, { at = w + 66, edge = 1.6, key = 'jersey' }, { at = w + 69.4, edge = 1.6, key = 'jersey' },
        { at = w + 96, edge = 2.2, key = 'flood' }, { at = w + 118, edge = 3.5, key = 'pileSmall' },
      }) do ins(list, it) end
      for a = w - 22, w + 130, 2.1 do ins(list, { at = a, edge = 6.5, key = 'fence' }) end
      endBoards(list, Z)
    end },
  -- one lane shut, the traffic takes turns at a site traffic light
  ampel = { title = 'Einspurig mit Baustellenampel', sub = 'Nur eine Spur – Ampel beachten', weight = 2.5, zone = 170, signal = true,
    limit = function(road) return road >= 70 and 50 or 30 end,
    build = function(list, Z, lane, sign)
      warnSigns(list, sign)
      ins(list, { at = -6, edge = 0.9, key = 'flood', yaw = 180 })
      ins(list, { at = -6, edge = 0.9, sig = 'red', lift = 3.6 })
      ins(list, { at = -6, edge = 0.9, sig = 'green', lift = 3.2 })
      taper(list, lane, 24)
      for a = 3, Z - 4, 5 do ins(list, { at = a, edge = -lane + 0.1, key = (math.floor(a / 5) % 2 == 0) and 'barrierRed' or 'barrier' }) end
      for _, it in ipairs({
        { at = 30, edge = -1.8, key = 'excavator' }, { at = 52, edge = -1.4, key = 'pile' }, { at = 70, edge = -1.9, key = 'pileSmall' },
        { at = 86, edge = -1.2, key = 'sandbarrel' }, { at = 92, edge = -2.0, key = 'sandbarrel' }, { at = 104, edge = -1.5, key = 'slab' },
        { at = 120, edge = -1.6, key = 'jersey' }, { at = 140, edge = 1.8, key = 'flood' },
      }) do ins(list, it) end
      for a = Z - 2, Z + 16, 6 do ins(list, { at = a, edge = -lane + (a - Z + 2) * (lane / 18), key = 'board' }) end
    end },
  -- the surface renewed: a narrower lane past heaps, two excavators, a long wall
  belag = { title = 'Fahrbahnerneuerung', sub = 'Verengte Fahrspur', weight = 2, zone = 260,
    limit = function(road) return road >= 100 and 60 or (road >= 70 and 50 or 30) end,
    build = function(list, Z, lane, sign)
      warnSigns(list, sign, true)
      taper(list, 1.0, 30)
      for a = 2, Z - 2, 6 do ins(list, { at = a, edge = -1.0, key = 'barrel' }) end
      for a = 10, Z - 10, 3.4 do ins(list, { at = a, edge = 0.5, key = 'jersey' }) end
      for _, it in ipairs({
        { at = 40, edge = 3.2, key = 'excavator', yaw = 30 }, { at = 66, edge = 3.0, key = 'pile' }, { at = 92, edge = 2.6, key = 'pileSmall' },
        { at = 120, edge = 3.4, key = 'pile' }, { at = 150, edge = 3.0, key = 'excavator', yaw = -40 }, { at = 180, edge = 2.6, key = 'pileSmall' },
        { at = 212, edge = 2.8, key = 'slab' }, { at = 216, edge = 2.8, key = 'slab', lift = 1.2 }, { at = 60, edge = 2.0, key = 'flood' }, { at = 200, edge = 2.0, key = 'flood' },
      }) do ins(list, it) end
      endBoards(list, Z)
    end },
  -- a concrete wall along the lane: nothing to see but a tight squeeze
  wand = { title = 'Betonschutzwand', sub = 'Enge Durchfahrt – Spur halten', weight = 2, zone = 300,
    limit = function(road) return road >= 100 and 60 or (road >= 70 and 50 or 30) end,
    build = function(list, Z, lane, sign)
      warnSigns(list, sign, true)
      ins(list, { at = -70, edge = 1.2, key = 'signKeepL' })
      taper(list, 0.7, 36)
      for a = 0, Z, 3.4 do ins(list, { at = a, edge = -0.7, key = 'jersey' }) end
      for a = 20, Z - 20, 40 do ins(list, { at = a, edge = 1.5, key = 'flood' }) end
      endBoards(list, Z)
    end },
  -- work of short duration: a work van, cones, arrow boards – over in a day
  kurz = { title = 'Tagesbaustelle', sub = 'Kurzer Abschnitt – langsam vorbei', weight = 2.5, zone = 75,
    limit = function(road) return road >= 100 and 80 or (road >= 70 and 60 or 30) end,
    build = function(list, Z, lane, sign)
      ins(list, { at = -120, edge = 1.2, key = 'signWork' })
      ins(list, { at = -70, edge = 1.2, key = sign })
      for k = 0, 6 do ins(list, { at = -32 + k * 5, edge = 1.1 - k * 0.3, key = 'cone' }) end
      for a = 2, Z - 2, 7 do ins(list, { at = a, edge = -0.9, key = 'cone' }) end
      ins(list, { at = 16, edge = 0.4, vehicle = 'civil' })
      ins(list, { at = 8, edge = -0.1, key = 'board' })
      ins(list, { at = 34, edge = 1.3, key = 'pileSmall' })
      ins(list, { at = 44, edge = 0.8, key = 'sandbarrel' }); ins(list, { at = 47, edge = 1.4, key = 'sandbarrel' })
      for k = 0, 3 do ins(list, { at = Z + k * 5, edge = -0.9 + k * 0.5, key = 'cone' }) end
    end },
  -- a pit in the lane: a ring of barriers round it
  kanal = { title = 'Kanalarbeiten', sub = 'Grube in der Fahrspur', weight = 1.8, zone = 110,
    limit = function(road) return road >= 70 and 50 or 30 end,
    build = function(list, Z, lane, sign)
      warnSigns(list, sign)
      taper(list, lane * 0.8, 24)
      local L = lane * 0.8
      for a = 4, Z - 4, 4 do ins(list, { at = a, edge = -L, key = (math.floor(a / 4) % 2 == 0) and 'barrierRed' or 'barrier' }) end
      ins(list, { at = 34, edge = -1.2, key = 'excavator', yaw = 90 })
      ins(list, { at = 52, edge = -1.3, key = 'pile' }); ins(list, { at = 66, edge = -1.0, key = 'slab' })
      ins(list, { at = 78, edge = -1.1, key = 'sandbarrel' }); ins(list, { at = 81, edge = -1.8, key = 'sandbarrel' })
      for k = 0, 3 do ins(list, { at = Z + k * 6, edge = -L + (L + 0.4) * ((k + 1) / 4), key = 'board' }) end
    end },
  -- a bridge repaired: fences close along the road, the wall on the edge
  bruecke = { title = 'Brückensanierung', sub = 'Enge Durchfahrt', weight = 1.5, zone = 180,
    limit = function(road) return road >= 70 and 50 or 30 end,
    build = function(list, Z, lane, sign)
      warnSigns(list, sign, true)
      taper(list, 0.6, 24)
      for a = 0, Z, 3.4 do ins(list, { at = a, edge = -0.6, key = 'jersey' }) end
      for a = 0, Z, 2.1 do ins(list, { at = a, edge = 1.6, key = 'fence' }) end
      for a = 16, Z - 16, 36 do ins(list, { at = a, edge = 2.6, key = 'flood' }) end
      endBoards(list, Z)
    end },
  -- at night, under floodlights
  nacht = { title = 'Nachtbaustelle', sub = 'Flutlicht – langsam vorbei', weight = 3, zone = 200, night = true,
    limit = function(road) return road >= 100 and 60 or (road >= 70 and 50 or 30) end,
    build = function(list, Z, lane, sign)
      warnSigns(list, sign)
      taper(list, 1.0, 30)
      for a = 3, Z - 3, 6 do ins(list, { at = a, edge = -1.0, key = 'barrel' }) end
      for a = 24, Z - 16, 34 do
        ins(list, { at = a, edge = 1.2, key = 'flood' })
        ins(list, { at = a, edge = 0.6, lamp = true, lift = 5 })
      end
      ins(list, { at = 60, edge = 3.2, key = 'excavator' }); ins(list, { at = 110, edge = 2.8, key = 'pile' }); ins(list, { at = 150, edge = 2.4, key = 'pileSmall' })
      endBoards(list, Z)
    end },
}
M.SIGNAL_RED_S, M.SIGNAL_GREEN_S = 26, 20
function M.pickRoadwork(night)
  local keys, sum = {}, 0
  for k in pairs(M.ROADWORKS) do keys[#keys + 1] = k end
  table.sort(keys)
  local list = {}
  for _, k in ipairs(keys) do
    local v = M.ROADWORKS[k]
    if not v.night or night then list[#list + 1] = { k, v.weight }; sum = sum + v.weight end
  end
  local r = math.random() * sum
  for _, x in ipairs(list) do r = r - x[2]; if r <= 0 then return x[1] end end
  return list[#list][1]
end

M.KINDS.roadworks = {
  weight = 3,
  make = function(e, ctx)
    local night = ctx.night and ctx.night() or false
    local key = e.force or M.pickRoadwork(night)
    local v = M.ROADWORKS[key]
    local road = (ctx.roadLimit and ctx.roadLimit()) or 100
    e.variant, e.limit, e.zoneLen, e.signal = key, v.limit(road), v.zone, v.signal
    e.radar = not v.signal and math.random() < 0.3
    e.finish = along(e.points, e.start, v.zone, e.startIdx)
    e.title, e.icon, e.sub = v.title, '🚧', v.sub
  end,
  spawn = function(e, ctx)
    local v, Z = M.ROADWORKS[e.variant], e.zoneLen
    local sign = 'sign' .. e.limit
    -- the strip to shut: the own lane (half of a two-way road; about a lane's width on a wide carriageway)
    local half = 3.25
    if e.line then local _, _, h = frameAt(e, 0); half = h or half end
    local lane = math.max(2.6, math.min(3.6, half))
    local list = {}
    v.build(list, Z, lane, sign, e)
    if e.radar then for _, it in ipairs(cameraPost(40, 1.2)) do ins(list, it) end end
    queue(e, list)
  end,
  update = function(e, ctx, dt, p)
    local ds, de = haversine(p, e.start), e.finish and haversine(p, e.finish) or math.huge
    -- the site traffic light: red and green in turns; over the line on red costs
    if e.signal and e.spawned then
      local t = now()
      if not e.sigT or t > e.sigT then
        e.sigGreen = not e.sigGreen
        e.sigT = t + (e.sigGreen and M.SIGNAL_GREEN_S or M.SIGNAL_RED_S)
        local r, g = e.sigRedId and getObjectByID(e.sigRedId), e.sigGreenId and getObjectByID(e.sigGreenId)
        if r then r.isEnabled = not e.sigGreen end
        if g then g.isEnabled = e.sigGreen and true or false end
        e.sub = e.sigGreen and 'Ampel grün – fahren' or 'Ampel rot – bitte warten'
      end
      if not e.sigPassed and ds < 12 and not e.inZone then
        local v = ctx.speedKmh()
        if v > 12 then
          e.sigPassed = true
          if not e.sigGreen then ctx.fine(120, 'Rote Baustellenampel überfahren') end
        end
      end
    end
    if not e.inZone and ds < C.PASS_M then
      e.inZone = true
    end
    if e.inZone then
      local v = ctx.speedKmh()
      if e.radar and not e.flashed and v > e.limit + 5 and ds > 30 then
        e.overT = (e.overT or 0) + dt
        if e.overT > 1 then
          e.flashed = true
          local over = math.floor(v - e.limit)
          ctx.fine(M.speedFine(over) + 20, string.format('Geblitzt in der Baustelle: %d km/h zu schnell', over))
          fireFlash(e)
        end
      else
        e.overT = 0
      end
      if de < C.PASS_M or ds > (e.zoneLen or C.ZONE_M) + 150 then e.inZone = false; e.done = true end
    end
  end,
}

M.KINDS.radar = {
  weight = 2,
  make = function(e, ctx) e.title, e.icon = 'Blitzer', '📸'; e.hidden = math.random() < 0.5 end,
  spawn = function(e, ctx) queue(e, cameraPost(0, 1.4)) end,
  update = function(e, ctx, dt, p)
    local d = haversine(p, e.start)
    if d < 25 and not e.done then
      e.done = true
      local limit = ctx.ruleLimit and ctx.ruleLimit() or ctx.roadLimit()     -- (a truck: its own limit, 80 / 60)
      local v = ctx.speedKmh()
      if limit and v > limit + 3 then
        local over = math.floor(v - limit - 3)
        if over > 0 then
          ctx.fine(M.speedFine(over), string.format('Geblitzt: %d km/h zu schnell (%d erlaubt)', over, limit))
          fireFlash(e)
        end
      end
    end
  end,
}

M.KINDS.control = {
  weight = 2,
  needsJob = true,
  make = function(e, ctx) e.title, e.icon = 'Polizeikontrolle', '🚓'; e.bayAt = -14 end,
  spawn = function(e, ctx)
    local road = ctx.roadLimit() or 100
    local list = {
      { at = 14, edge = 0.9, vehicle = 'police' },
      { at = -120, edge = 1.2, key = 'signDanger' },
      { at = -80, edge = 1.2, key = road >= 80 and 'sign60' or 'sign30' },
    }
    -- cones guiding onto the shoulder, around the bay
    for k = 0, 5 do table.insert(list, { at = -60 + k * 7, edge = 0.6 - k * 0.25, key = 'cone' }) end
    for k = 0, 3 do table.insert(list, { at = -26 + k * 8, edge = -1.9, key = 'cone' }) end
    table.insert(list, { at = 28, edge = 0.3, key = 'cone' }); table.insert(list, { at = 36, edge = 0.6, key = 'cone' })
    queue(e, list)
  end,
  update = function(e, ctx, dt, p)
    local d = haversine(p, e.start)
    local v = ctx.speedKmh()
    if not e.bay and e.line then pcall(showBay, e) end
    if e.bay then pcall(e.bay.marker.update, e.bay.marker, dt) end
    if not e.called and d < 400 then
      e.called = true
      ctx.notify('Polizeikontrolle – rechts in die blaue Fläche fahren und anhalten', 8)
    end
    if e.done then return end
    local pp = ctx.playerPos and ctx.playerPos()
    local stopped = v < 3 and (inBay(e, pp) or (not e.bay and d < 60))
    if stopped then
      e.stopT = (e.stopT or 0) + dt
      if e.stopT > C.CONTROL_STOP_S then
        e.done = true
        if e.bay then pcall(function() e.bay.marker:setColor({ 0.3, 0.95, 0.5, 1 }) end) end
        local found = ctx.controlCheck()
        -- (2026-11-08: the officer comes to the window – a talk, career.lua L.cop*)
        if ctx.controlDialog then
          ctx.controlDialog(found)
        elseif #found == 0 then
          ctx.message('Polizei: Papiere, Fahrtenschreiber und Ladung in Ordnung. Gute Fahrt!')
          ctx.xp(50)
        else
          for _, f in ipairs(found) do ctx.fine(f.amount, f.reason) end
        end
      end
    else
      e.stopT = 0
    end
    -- driven past without stopping
    if not e.done and d < 30 and v > 20 and not e.passedFast then
      local pastStart = e.finishPass or along(e.points, e.start, 20, e.startIdx)
      e.finishPass = pastStart
      if pastStart and haversine(p, pastStart) < 15 then
        e.passedFast, e.done = true, true
        ctx.fine(250, 'Polizeikontrolle missachtet')
      end
    end
  end,
}

-- everyday things on the road (2026-11-04: "es muss auch mal was Interessanteres passieren") ------------------

-- a car broken down on the shoulder: hazard lights, the warning triangle well before it, two cones
M.KINDS.breakdown = {
  weight = 2,
  make = function(e, ctx)
    e.title, e.icon = 'Pannenfahrzeug', '🚗'
    e.sub = 'Steht auf dem Seitenstreifen – Abstand halten, langsamer'
    e.zoneLen, e.zoneLimit = 70, math.max(30, (ctx.roadLimit() or 80) - 20)
  end,
  spawn = function(e, ctx)
    queue(e, {
      { at = -60, edge = 0.4, key = 'triangle' },
      { at = -8, edge = 0.2, key = 'cone' }, { at = -3, edge = 0.0, key = 'cone' },
      { at = 4, edge = 1.3, vehicle = 'civil' },
    })
  end,
  update = function(e, ctx, dt, p)
    local d = haversine(p, e.start)
    if not e.passed and d < 25 then e.passed = true end
    e.inZone = (d < 90 and not e.done) or nil
    if e.passed and d >120 then e.done = true end
  end,
}

-- lost cargo on the road: crates and a pallet in the lane, a warning sign before them
M.KINDS.cargo = {
  weight = 2,
  make = function(e, ctx)
    e.title, e.icon = 'Verlorene Ladung', '📦'
    e.sub = 'Gegenstände auf der Fahrbahn – langsam vorbei'
    e.zoneLen, e.zoneLimit = 60, 40
  end,
  spawn = function(e, ctx)
    queue(e, {
      { at = -110, edge = 1.2, key = 'signDanger' },
      { at = 0, edge = -1.6, key = 'crate', yaw = 25 }, { at = 3, edge = -2.6, key = 'pallet', yaw = -12 },
      { at = 7, edge = -0.9, key = 'crate', yaw = 70 }, { at = 12, edge = -3.1, key = 'crate', yaw = 5 },
      { at = 16, edge = 0.4, key = 'pallet', yaw = 40 },
    })
  end,
  update = function(e, ctx, dt, p)
    local d = haversine(p, e.start)
    if not e.passed and d < 20 then e.passed = true end
    e.inZone = (d < 90 and not e.done) or nil
    if e.passed and d >100 then e.done = true end
  end,
}

-- an accident ahead: a crashed car in the lane, the police there with its lights, cones closing the lane – a jam
M.KINDS.crash = {
  weight = 2,
  make = function(e, ctx)
    e.title, e.icon = 'Unfall voraus', '🚓'
    e.sub = 'Fahrspur gesperrt – Stau, langsam vorbei'
    e.zoneLen, e.zoneLimit = 120, 30
  end,
  spawn = function(e, ctx)
    local list = {
      { at = -150, edge = 1.2, key = 'signDanger' },
      { at = -90, edge = 1.2, key = 'sign60' },
      { at = 6, edge = -2.4, vehicle = 'civil' },
      { at = 22, edge = -1.0, vehicle = 'police' },
    }
    for k = 0, 6 do table.insert(list, { at = -30 + k * 5, edge = 0.4 - k * 0.45, key = 'cone' }) end
    queue(e, list)
  end,
  update = function(e, ctx, dt, p)
    local d = haversine(p, e.start)
    if not e.passed and d < 30 then e.passed = true end
    e.inZone = (d < 90 and not e.done) or nil
    if e.passed and d >160 then e.done = true end
  end,
}

-- an emergency vehicle from behind with blue lights and siren: it passes; the HUD says to keep right
M.KINDS.siren = {
  weight = 2,
  make = function(e, ctx)
    local amb = math.random() < 0.6
    e.unitKind = amb and 'ambulance' or 'police'
    e.title, e.icon = amb and 'Rettungswagen im Einsatz' or 'Polizei im Einsatz', amb and '🚑' or '🚨'
    e.sub = 'Von hinten mit Blaulicht – rechts halten, Platz machen'
    e.noScene = true                         -- (nothing laid out on the road: the vehicle comes from behind)
  end,
  update = function(e, ctx, dt, p)
    -- (2026-11-04: once over, never again – the event lives on until the player is 450 m past it, and each frame here
    -- spawned a new car when the point ahead was not found: 54 patrol cars in 100 s, 2 fps, the game crashed)
    if e.done or e.tried and not e.unit then return end
    -- (when the player is about at the event's start: the vehicle 220 m behind, then racing to a point far ahead)
    if not e.unit and haversine(p, e.start) < 300 then
      e.tried = true                         -- (one try only, whatever comes of it)
      local pp, dir = ctx.playerPos and ctx.playerPos(), ctx.playerDir and ctx.playerDir()
      if not pp or not dir or not (map and map.findClosestRoad) then e.done = true; return end
      -- (the point ahead first – no car at all without it; BeamNG.Earth's road graph may not reach 900 m yet)
      local aheadNode
      -- (2026-11-08: along the road the truck is on – the nearest road to a point ahead may be the other carriageway)
      aheadNode = accidents.nodeAlong(pp, dir, 900)
      if not aheadNode then
        for _, ahead in ipairs({ 900, 600, 400, 250 }) do
          local okA, n = pcall(map.findClosestRoad, pp + dir * ahead)
          if okA and n then aheadNode = n; break end
        end
      end
      if not aheadNode then e.done = true; log('I', 'fernfahrer', 'siren: no road ahead – skipped'); return end
      -- (both ends on the road graph: the spot 220 m back snapped to its nearest road node)
      local okB, backNode = pcall(map.findClosestRoad, pp - dir * 220)
      local nodes = map.getMap and map.getMap().nodes
      local bn = okB and backNode and nodes and nodes[backNode]
      local back = bn and (ground(bn.pos) or bn.pos) or ground(pp - dir * 220) or (pp - dir * 220)
      -- (on the way the truck itself came: the right carriageway, the right direction)
      local tp, td = accidents.behind(220)
      if tp then back, dir = tp, td end
      local id = pool.take(e.unitKind, back + vec3(0, 0, 0.4), dir)
      local veh = id and getObjectByID(id)
      if not veh then e.done = true; if id then pcall(pool.give, id) end; return end
      M.protect(id)
      table.insert(e.props, id)
      e.unit, e.unitAt, e.announced = id, now(), true
      e.kickAt = e.unitAt + 0.3
      e.sirenMs = function()
        local lim = ctx.roadLimit and ctx.roadLimit() or 80
        return math.max(16, math.min(30, (lim or 80) / 3.6 * 1.25 + 2))
      end
      e.kickFn = function()
        -- (a point ahead of where the player is now; within the road graph, which ends some hundred metres on)
        local p2, d2 = ctx.playerPos and ctx.playerPos(), ctx.playerDir and ctx.playerDir()
        local node = aheadNode
        if p2 and d2 then local n = accidents.nodeAlong(p2, d2, 300); if n then node = n end end
        -- (2026-11-09: no speed limit, aggression 0.85 and no lane: it went straight on into the first bend. Now fast, but on the road)
        return string.format('controller.setFreeze(0) electrics.set_lightbar_signal(2) ai.setMode("manual") ' ..
          'ai.setTarget(%q) ai.setSpeedMode("limit") ai.setSpeed(%.1f) ai.setAggression(0.5) ai.setAvoidCars("on") ai.driveInLane("on")', node, e.sirenMs())
      end
      ctx.notify(e.icon .. ' ' .. e.title .. ' von hinten – rechts halten!', 7)
      e.inZone = true
    end
    if e.unit then
      kickTick(e, now())
      local v = getObjectByID(e.unit)
      local pp = ctx.playerPos and ctx.playerPos()
      -- (2026-11-09) under way: always a stretch of road ahead of itself to drive to, in its lane; only close behind the truck, which has
      -- moved over, down the middle of the road to get past
      if v and not e.kickFn and now() >= (e.sirenAt or 0) then
        e.sirenAt = now() + 3
        local vp, vd = vec3(v:getPosition()), vec3(v:getDirectionVector())
        vd.z = 0
        if vd:length() > 0.1 then
          vd = vd:normalized()
          local node = accidents.nodeAlong(vp, vd, 300)
          local pd = ctx.playerDir and ctx.playerDir()
          local rel = pp and (pp - vp):dot(vd) or -1
          local past = pp and pd and pd:dot(vd) > 0.5 and rel > -25 and rel < 80
          if node then v:queueLuaCommand(string.format('ai.setTarget(%q) ai.setSpeed(%.1f) ai.driveInLane(%q)', node, e.sirenMs(), past and 'off' or 'on')) end
        end
      end
      -- (passed and gone ahead, or a minute up: over)
      if not v or now() - e.unitAt > 60 or (pp and (v:getPosition() - pp):length() > 450 and now() - e.unitAt > 15) then
        e.done, e.inZone = true, false
      end
    end
  end,
}

-- (2026-11-07) more kinds: an oil spill, a police laser check, a heavy load with its escort, a wrong-way driver on the
-- radio --------------------------------------------------------------------------------------------------------------

-- an oil spill: the lane slippery, warning signs and barrels, slow past
M.KINDS.oil = {
  weight = 1.5,
  make = function(e, ctx)
    e.title, e.icon = 'Ölspur', '🛢'
    e.sub = 'Fahrbahn rutschig – Tempo 40, vorsichtig bremsen'
    e.zoneLen, e.zoneLimit = 140, 40
  end,
  spawn = function(e, ctx)
    local list = { { at = -160, edge = 1.2, key = 'signDanger' }, { at = -100, edge = 1.2, key = 'sign50' } }
    for k = 0, 4 do table.insert(list, { at = -10 + k * 22, edge = 0.5, key = 'sandbarrel' }) end
    queue(e, list)
  end,
  update = function(e, ctx, dt, p)
    local d = haversine(p, e.start)
    if not e.passed and d < 30 then e.passed = true end
    e.inZone = (d < 110 and not e.done) or nil
    if e.passed and d > 160 then e.done = true end
  end,
}

-- the police with a laser gun: a patrol car at the roadside measuring – mostly not seen in time (no warning sign)
M.KINDS.laser = {
  weight = 1.5,
  make = function(e, ctx) e.title, e.icon = 'Lasermessung', '🚓'; e.hidden = math.random() < 0.6 end,
  spawn = function(e, ctx) queue(e, { { at = 6, edge = 1.6, vehicle = 'police' } }) end,
  update = function(e, ctx, dt, p)
    local d = haversine(p, e.start)
    if d < 40 and not e.done then
      e.done = true
      local limit = ctx.ruleLimit and ctx.ruleLimit() or ctx.roadLimit()
      local v = ctx.speedKmh()
      if limit and v > limit + 3 then
        local over = math.floor(v - limit - 3)
        if over > 0 then ctx.fine(M.speedFine(over), string.format('Lasermessung der Polizei: %d km/h zu schnell (%d erlaubt)', over, limit)) end
      end
    end
  end,
}

-- a heavy load ahead with its police escort: slow in the lane, lights on – not to be pushed past
M.KINDS.heavy = {
  weight = 1,
  make = function(e, ctx)
    e.title, e.icon = 'Schwertransport', '🚛'
    e.sub = 'Mit Polizeibegleitung – langsam, nicht drängeln'
    e.noScene = true
  end,
  update = function(e, ctx, dt, p)
    if e.done or (e.tried and not e.unit) then return end
    if not e.unit and haversine(p, e.start) < 500 then
      e.tried = true
      local pp, dir = ctx.playerPos and ctx.playerPos(), ctx.playerDir and ctx.playerDir()
      if not pp or not dir or not (map and map.findClosestRoad and map.getMap) then e.done = true; return end
      local okS, sNode = pcall(map.findClosestRoad, pp + dir * 280)
      local okA, aheadNode = pcall(map.findClosestRoad, pp + dir * 1500)
      local nodes = map.getMap().nodes
      local sn = okS and sNode and nodes[sNode]
      if not sn or not okA or not aheadNode then e.done = true; return end
      local id = pool.take('police', (ground(sn.pos) or sn.pos) + vec3(0, 0, 0.4), dir)
      local veh = id and getObjectByID(id)
      if not veh then e.done = true; return end
      M.protect(id)
      table.insert(e.props, id)
      e.unit, e.unitAt, e.announced, e.inZone = id, now(), true, true
      e.kickAt = e.unitAt + 0.3
      e.kickFn = function()
        return string.format('controller.setFreeze(0) electrics.set_lightbar_signal(1) electrics.set_warn_signal(1) ai.setMode("manual") ' ..
          'ai.setTarget(%q) ai.setSpeedMode("set") ai.setSpeed(8.5) ai.setAggression(0.2) ai.driveInLane("on")', aheadNode)
      end
    end
    if e.unit then
      kickTick(e, now())
      local v = getObjectByID(e.unit)
      local pp = ctx.playerPos and ctx.playerPos()
      if not v or now() - e.unitAt > 150 or (pp and (v:getPosition() - pp):length() > 900) then e.done, e.inZone = true, false end
    end
  end,
}

-- a wrong-way driver on the radio: no scene – the traffic report, the warner's sign, and a while to be careful
M.KINDS.ghost = {
  weight = 0.6,
  make = function(e, ctx)
    e.title, e.icon = 'Falschfahrer gemeldet', '⚠'
    e.sub = 'Verkehrsfunk: äußerst rechts fahren, nicht überholen'
    e.noScene = true
  end,
  update = function(e, ctx, dt, p)
    if not e.said and haversine(p, e.start) < 1600 then
      e.said, e.saidAt = true, now()
      ctx.message('Verkehrsfunk: Auf deiner Strecke ist ein Falschfahrer gemeldet. Fahr äußerst rechts und überhol nicht.', 'Verkehrsfunk')
      ctx.notify('📻 Verkehrsfunk: Falschfahrer auf deiner Strecke – äußerst rechts fahren!', 8)
    end
    e.inZone = e.said and not e.done or nil
    if e.said and now() - e.saidAt > 90 then e.done = true end
  end,
}

-- (2026-11-08) more everyday scenes ----------------------------------------------------------------------------------

-- potholes: a stretch patched up badly, cones round the worst
M.KINDS.potholes = {
  weight = 1.5,
  make = function(e, ctx)
    e.title, e.icon = 'Fahrbahnschäden', '🕳'
    e.sub = 'Schlaglöcher – runter vom Gas'
    e.zoneLen, e.zoneLimit = 90, math.min(50, (ctx.roadLimit() or 80) - 20)
  end,
  spawn = function(e, ctx)
    local list = { { at = -130, edge = 1.2, key = 'signDanger' }, { at = -80, edge = 1.2, key = 'sign50' } }
    for _, a in ipairs({ 6, 30, 58 }) do
      ins(list, { at = a - 3, edge = -1.0, key = 'cone' }); ins(list, { at = a + 3, edge = -1.0, key = 'cone' })
      ins(list, { at = a, edge = -2.0, key = 'cone' }); ins(list, { at = a, edge = -0.2, key = 'cone' })
    end
    queue(e, list)
  end,
  update = function(e, ctx, dt, p)
    local d = haversine(p, e.start)
    if not e.passed and d < 25 then e.passed = true end
    e.inZone = (d < 110 and not e.done) or nil
    if e.passed and d > 150 then e.done = true end
  end,
}

-- the verges being cut: a working vehicle on the shoulder, boards before it
M.KINDS.mowing = {
  weight = 1.5,
  make = function(e, ctx)
    e.title, e.icon = 'Mäharbeiten', '🌿'
    e.sub = 'Arbeitsfahrzeug am Rand – Abstand halten'
    e.zoneLen, e.zoneLimit = 60, math.max(30, (ctx.roadLimit() or 80) - 30)
  end,
  spawn = function(e, ctx)
    local list = { { at = -100, edge = 1.2, key = 'signWork' } }
    for k = 0, 3 do ins(list, { at = -24 + k * 6, edge = 1.1 - k * 0.3, key = 'board' }) end
    ins(list, { at = 10, edge = 0.8, vehicle = 'civil' })
    ins(list, { at = 34, edge = 2.4, key = 'pileSmall' })
    queue(e, list)
  end,
  update = function(e, ctx, dt, p)
    local d = haversine(p, e.start)
    if not e.passed and d < 20 then e.passed = true end
    e.inZone = (d < 80 and not e.done) or nil
    if e.passed and d > 110 then e.done = true end
  end,
}

-- a lorry's load of grit on the road: barrels, a sign, a long slippery stretch
M.KINDS.grit = {
  weight = 1,
  make = function(e, ctx)
    e.title, e.icon = 'Rollsplitt', '⚠'
    e.sub = 'Loser Splitt auf der Fahrbahn – Tempo 40'
    e.zoneLen, e.zoneLimit = 150, 40
  end,
  spawn = function(e, ctx)
    local list = { { at = -150, edge = 1.2, key = 'signDanger' }, { at = -90, edge = 1.2, key = 'sign50' } }
    for a = 0, 140, 30 do ins(list, { at = a, edge = 0.6, key = 'barrel' }) end
    ins(list, { at = 70, edge = 1.8, key = 'pileSmall' })
    queue(e, list)
  end,
  update = function(e, ctx, dt, p)
    local d = haversine(p, e.start)
    if not e.passed and d < 30 then e.passed = true end
    e.inZone = (d < 170 and not e.done) or nil
    if e.passed and d > 200 then e.done = true end
  end,
}

-- now and then a police car or an ambulance in the ordinary traffic (2026-11-04: "ganz selten, alle 20 Minuten"):
-- no lights, no scene – it comes the other way and drives past. About every PATROL_S of driving (±25 %), out of
-- sight ahead (500–700 m along the road, on the other side), driving as traffic; given back once well past or after
-- PATROL_LIFE_S. The police car comes from the pool (no hitch); the ambulance is spawned (rarer).
local patrol = { next = nil, id = nil, born = 0 }
M.PATROL_S, M.PATROL_LIFE_S = 20 * 60, 150

local function patrolEnd()
  if patrol.id then
    local id = patrol.id
    patrol.id = nil
    pcall(function() if pool.owns(id) then pool.give(id) else local o = getObjectByID(id); if o then o:delete() end end end)
  end
end

local function patrolTick(ctx, dt)
  local t = now()
  patrol.next = patrol.next or (t + M.PATROL_S * (0.6 + math.random() * 0.5))
  local pp = ctx.playerPos and ctx.playerPos()
  if patrol.id then
    local o = getObjectByID(patrol.id)
    local d = o and pp and (o:getPosition() - pp):length() or 1e9
    if not o or t - patrol.born > M.PATROL_LIFE_S or (t - patrol.born > 25 and d > 800) then patrolEnd() end
    return
  end
  if t < patrol.next then return end
  local dir = ctx.playerDir and ctx.playerDir()
  if not pp or not dir or ctx.speedKmh() < 30 or ev then patrol.next = t + 30; return end    -- (driving, no scene going)
  patrol.next = t + M.PATROL_S * (0.75 + math.random() * 0.5)
  if not (map and map.findClosestRoad and map.getMap) then return end
  local okN, nodeName = pcall(map.findClosestRoad, pp + dir * (500 + math.random() * 200))
  local nodes = map.getMap().nodes
  local n = okN and nodeName and nodes and nodes[nodeName]
  if not n then return end
  -- (its way: back towards the player; on the right of it – the other side of the road from the player)
  local back = flat(pp - n.pos) or (dir * -1)
  local right = vec3(back.y, -back.x, 0)
  local spot = ground(n.pos + right * math.min(2.2, (n.radius or 3) * 0.5)) or n.pos
  local kind = math.random() < 0.7 and 'police' or 'ambulance'
  local id = pool.take(kind, spot + vec3(0, 0, 0.4), back)
  local veh = id and getObjectByID(id)
  if not veh then return end
  M.protect(id)
  veh:queueLuaCommand('controller.setFreeze(0) electrics.set_lightbar_signal(0) electrics.set_warn_signal(0) ' ..
    'ai.setMode("traffic") ai.setSpeedMode("legal") ai.setAggression(0.3) ai.driveInLane("on")')
  patrol.id, patrol.born = id, t
  log('I', 'fernfahrer', string.format('patrol: a %s in the traffic, %.0f m ahead', kind, (spot - pp):length()))
end

-- (for the list of events and its drawings, tools/dump_events.js: what a kind lays out, without the game)
function M.layoutOf(kind, variant, road)
  local k = M.KINDS[kind]
  if not k then return nil end
  local e = { kind = kind, force = variant, points = nil, start = { lat = 0, lon = 0 }, props = {} }
  local ctx = setmetatable({ roadLimit = function() return road or 100 end, night = function() return variant == 'nacht' end },
    { __index = function() return function() return nil end end })
  k.make(e, ctx)
  if k.spawn then k.spawn(e, ctx) end
  return { title = e.title, sub = e.sub, icon = e.icon, limit = e.limit or e.zoneLimit, zone = e.zoneLen, items = e.queue or {}, noScene = e.noScene, hidden = e.hidden, weight = k.weight }
end

-- the loop -----------------------------------------------------------------------------------------------------

-- (2026-11-08) what comes next. Variety without chaos: each kind keeps its weight and the day its mild mood (0.6 … 1.5),
-- but what has just been seen steps back: the last one almost never again at once, the ones before it less and less so,
-- also a kind of the same family (police / road surface / vehicles) right after another; and what has not come for a long
-- time gets more likely. So all kinds come round, none takes over.
M.FAMILY = { radar = 'police', laser = 'police', control = 'police', roadworks = 'road', potholes = 'road', mowing = 'road',
  grit = 'road', oil = 'road', breakdown = 'car', crash = 'car', cargo = 'car', heavy = 'car', ghost = 'car', siren = 'car' }
M.RECENT_FACTOR = { 0.04, 0.2, 0.42, 0.65, 0.85 }
M.recent, M.sinceKind = {}, {}
function M.pickKind(day, hasJob, rnd)
  local function mood(i)
    local x = math.sin(day * 12.9898 + i * 78.233) * 43758.5453
    return 0.6 + 0.9 * (x - math.floor(x))
  end
  local keys = {}
  for key in pairs(M.KINDS) do keys[#keys + 1] = key end
  table.sort(keys)
  local list, sum = {}, 0
  local lastFam = M.recent[1] and M.FAMILY[M.recent[1]]
  for i, key in ipairs(keys) do
    local k = M.KINDS[key]
    if not k.needsJob or hasJob then
      local w = (k.weight or 1) * mood(i)
      for age, seen in ipairs(M.recent) do if seen == key then w = w * (M.RECENT_FACTOR[age] or 1); break end end
      if lastFam and M.FAMILY[key] == lastFam then w = w * 0.55 end
      w = w * math.min(2.2, 1 + (M.sinceKind[key] or 0) * 0.12)       -- (not seen for many events: up to 2.2 ×)
      list[#list + 1] = { key = key, k = k, w = w }; sum = sum + w
    end
  end
  if sum <= 0 then return nil end
  local r = rnd() * sum
  for _, x in ipairs(list) do r = r - x.w; if r <= 0 then return x end end
  return list[#list]
end
function M.noteKind(key)
  M.lastKind = key
  table.insert(M.recent, 1, key)
  M.recent[#M.RECENT_FACTOR + 1] = nil
  for k in pairs(M.KINDS) do M.sinceKind[k] = (M.sinceKind[k] or 0) + 1 end
  M.sinceKind[key] = 0
end

local function roll(ctx)
  local points = ctx.routePoints()
  local p = ctx.here()
  -- (2026-11-08: the office's "Ereignis testen": that scene next, a little way ahead on the route)
  local forced = M.forceNext
  if forced and points and p then
    local k = M.KINDS[forced[1]]
    local start, idx = along(points, p, 750)
    if not k or not start then return end
    local copy = {}
    for i = math.max(1, (idx or 1) - 60), math.min(#points, (idx or 1) + 200) do copy[#copy + 1] = { points[i][1], points[i][2] } end
    local _, cidx = along(copy, start, 0)
    ev = { kind = forced[1], def = k, start = start, startIdx = cidx, points = copy, props = {}, born = now(), force = forced[2] }
    k.make(ev, ctx)
    ev.hidden = nil
    lastAt = now()
    M.forceNext = nil
    return
  end
  if not points or not p or ctx.speedKmh() < 40 then return end
  local pick = M.pickKind(ctx.dayNo and ctx.dayNo() or 1, ctx.hasJob(), math.random)
  if not pick then return end
  local dist =C.AHEAD_M[1] + math.random() * (C.AHEAD_M[2] - C.AHEAD_M[1])
  local start, idx = along(points, p, dist)
  if not start then return end
  -- (2026-11-08: a scene needs road after its start; right at the route's end it cannot be laid out)
  if not along(points, start, 320, idx) then return end
  M.noteKind(pick.key)
  -- (a copy of the route: the GPS may change its table while the event lives)
  local copy = {}
  for i = math.max(1, (idx or 1) - 60), math.min(#points, (idx or 1) + 200) do copy[#copy + 1] = { points[i][1], points[i][2] } end
  local _, cidx = along(copy, start, 0)
  ev = { kind = pick.key, def = pick.k, start = start, startIdx = cidx, points = copy, props = {}, born = now() }
  pick.k.make(ev, ctx)
  lastAt = now()
end

function M.update(ctx, dt)
  local t = now()
  local okP, errP = pcall(patrolTick, ctx, dt)
  if not okP then log('W', 'fernfahrer', 'patrol: ' .. tostring(errP)); patrolEnd() end
  if not ev then
    if M.forceNext and t - lastRoll > 1 then lastRoll = t; roll(ctx); return end
    -- (2026-11-07: the gap after an event drawn anew each time – between a short and a long while)
    if t - lastRoll > C.CHECK_S and t - lastAt > (M.nextGap or C.GAP_S) then
      lastRoll = t
      if math.random() < C.CHANCE then roll(ctx); M.nextGap = C.GAP_S * (0.35 + math.random() * 1.5) end
    end
    return
  end
  local p = ctx.here()
  if not p then return end
  local d = haversine(p, ev.start)
  -- (2026-11-05: no messages in the middle of the screen for what is ahead – roadworks, a camera, a broken-down car
  -- show in the route advisor's warner, if it is switched on (M.hud). Only what asks something of the driver speaks
  -- up: an emergency vehicle from behind, a police check)
  if not ev.announced and d < C.ANNOUNCE_M and not ev.hidden then
    ev.announced = true
    if ev.kind == 'roadworks' then ctx.story('firstRoadworks') end
  end
  if not ev.spawned and d < C.SPAWN_M and ev.def.spawn and t - (ev.lineTry or 0) > 0.5 then
    ev.lineTry = t
    -- the road there, from the game's graph (it is loaded this close)
    local okL, line, why = pcall(buildLine, ev, ctx)
    if not okL then why = line; line = nil end
    if okL and line then
      ev.line = line
      ev.spawned = true
      local okS, err = pcall(ev.def.spawn, ev, ctx)
      if not okS then log('W', 'fernfahrer', 'event props: ' .. tostring(err)) end
      local pos, dir = frameAt(ev, 0)
      if pos then
        local lim = ev.kind == 'roadworks' and ev.limit or ev.zoneLimit or (ev.kind == 'control' and 40 or ((ctx.roadLimit() or 100) - 5))
        ev.zone = { pos = pos, dir = dir, len = ev.zoneLen or 50, limit = lim, kind = ev.kind, block = blockOf(ev) }
        if ev.zone.block then log('I', 'fernfahrer', string.format('event %s: road shut from %.1f m right of the centre, %.0f to %.0f m', ev.kind, ev.zone.block.l0, ev.zone.block.s0, ev.zone.block.s1)) end
      end
    elseif d < C.SPAWN_M * 0.5 then
      -- (2026-11-08: no road to lay it out on: no event at all – a police check without car and bay was all that was left)
      log('W', 'fernfahrer', 'event ' .. ev.kind .. ': no road line here (' .. tostring(why) .. '), called off')
      clearProps(ev)
      ev = nil
      return
    end
  end
  if ev.queue and #ev.queue > 0 then
    for _ = 1, C.PER_FRAME do
      local item = table.remove(ev.queue, 1)
      if not item then break end
      local ok, err = pcall(buildOne, ev, item)
      if not ok then ev.failed = (ev.failed or 0) + 1; log('W', 'fernfahrer', 'event prop: ' .. tostring(err)) end
    end
    if #ev.queue == 0 then
      log('I', 'fernfahrer', string.format('event %s: %d props placed, %d failed', ev.kind, ev.placed or 0, ev.failed or 0))
    end
  end
  if ev.flashOff and t > ev.flashOff then
    ev.flashOff = nil
    local l = ev.flashLight and getObjectByID(ev.flashLight)
    if l then l.isEnabled = false end
  end
  ev.def.update(ev, ctx, dt, p)
  local beyond = ev.done and d > 450
  if beyond or t - ev.born > C.MAX_AGE_S or (not ev.done and d > C.AHEAD_M[2] + 1500) then
    clearProps(ev)
    ev = nil
  end
end

-- (for the offline check, tools/sim_events.js)
M._buildLine, M._frameAt, M._along = buildLine, frameAt, along

function M.zones()
  return ev and ev.zone and { ev.zone } or nil
end

function M.limitOverride()
  return ev and ev.kind == 'roadworks' and ev.inZone and ev.limit or nil
end

function M.hud(here)
  if not ev or not here then return nil end
  if ev.hidden and not ev.done then return nil end
  if not ev.announced and not ev.inZone then return nil end
  if ev.done and not ev.inZone then return nil end
  return { kind = ev.kind, title = ev.title, icon = ev.icon, limit = ev.limit or ev.zoneLimit, inZone = ev.inZone or nil, sub = ev.sub,
    dist = math.floor(haversine(here, ev.start)), radar = ev.kind == 'roadworks' and ev.radar or nil }
end

function M.flash() return M.flashAt and now() - M.flashAt < 1.2 or nil end

-- a scene on request (kind, roadworks variant): the one under way goes
function M.test(kind, variant)
  if not M.KINDS[kind] then return false end
  if ev then clearProps(ev); ev = nil end
  M.forceNext = { kind, variant }
  return true
end

function M.reset()
  clearProps(ev)
  ev = nil
  patrolEnd()
  patrol.next = nil
end

return M
