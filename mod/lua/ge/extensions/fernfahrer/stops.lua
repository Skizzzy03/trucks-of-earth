-- Trucks of Earth: the stop rings. At the place the player is near (career.lua updateNear: a rest area, a fuel
-- stop, a workshop, a dealer, a port, the yard) a glowing ring lies on the road beside it with a marker turning above
-- (props: ff_ring_<colour>.dae / ff_gem_<colour>.dae, tools/build_props.js); driven into and stopped, Enter (or the
-- action key) opens the place's menu (FernfahrerStop.vue). No collision: drawn only.
-- M.update(ctx, dt) every frame, M.hud(), M.reset(), M.inside().

local M = {}

M.DIR = '/levels/beamng_earth/art/shapes/fernfahrer/props/'
M.RADIUS = 6.5                 -- (inside: the truck's centre this near the ring's centre)
M.COLOR = { sleep = 'green', refuel = 'orange', repair = 'red', dealerTruck = 'blue', dealerCar = 'blue',
  ferry = 'violet', fly = 'violet', rental = 'violet', underground = 'red', home = 'yellow', freight = 'cyan', tour = 'green' }
M.HINT = { sleep = 'Rastplatz – schlafen, tanken, einkaufen', refuel = 'Tankstelle – tanken, schlafen', repair = 'Werkstatt – reparieren',
  dealerTruck = 'Händler – Fahrzeuge kaufen', dealerCar = 'Händler – Fahrzeuge kaufen', ferry = 'Hafen – Überfahrt buchen',
  fly = 'Flughafen – Flug buchen', rental = 'Mietwagen-Schalter – Auto auswählen', home = 'Firmenhof – Büro, schlafen, Werkstatt', freight = 'Firma – Fracht übernehmen',
  tour = 'Anhalten – die Milch wird von selbst umgepumpt', underground = 'Hier fragt keiner nach Papieren' }

local ring                     -- { key, pos (vec3), ids = { ring, gem }, place }
local t = 0

local function deleteId(id)
  local o = id and scenetree.findObjectById(id)
  if o then pcall(function() o:delete() end) end
end

local function clear()
  if not ring then return end
  for _, id in ipairs(ring.ids or {}) do deleteId(id) end
  ring = nil
end

local function makeStatic(shape, name)
  local o = createObject('TSStatic')
  if not o then return nil end
  o:setField('shapeName', 0, M.DIR .. shape .. '.dae')
  o:setField('collisionType', 0, 'None')
  o:setField('decalType', 0, 'None')
  o.canSave = false
  o:registerObject(name)
  return o:getID()
end

local function ground(x, y, zRef, up)
  local top = (zRef or 0) + (up or 60)
  local d = castRayStatic(vec3(x, y, top), vec3(0, 0, -1), 200)
  if not d or d >= 200 then return nil end
  return top - d
end

-- where the ring lies for a place: the yard's spot, else the road point nearest to the place (on the road the truck
-- comes along: a place's own point is often inside its building)
local function spotFor(place, ctx)
  if place.action == 'home' and ctx.yardSpot then
    local s = ctx.yardSpot()
    if s then return s end
  end
  local a = ctx.anchor()
  if not a or not place.lat then return nil end
  local x, y = a:geodeticToWorld(place.lat, place.lon, 0)
  local pp = ctx.playerPos()
  local zg = ground(x, y, pp and pp.z or 0) or (pp and pp.z) or 0
  local p = vec3(x, y, zg)
  if map and map.findClosestRoad and map.getMap then
    local ok, n1, n2 = pcall(map.findClosestRoad, p)
    local nodes = ok and n1 and n2 and map.getMap().nodes
    if nodes and nodes[n1] and nodes[n2] then
      local a1, b1 = vec3(nodes[n1].pos), vec3(nodes[n2].pos)
      local ab = b1 - a1
      local l2 = ab.x * ab.x + ab.y * ab.y
      local k = l2 > 0 and math.max(0, math.min(1, ((p.x - a1.x) * ab.x + (p.y - a1.y) * ab.y) / l2)) or 0
      local q = a1 + ab * k
      local zq = ground(q.x, q.y, q.z) or q.z
      -- (not too far from the place itself: a road 150 m away is not its forecourt)
      -- (the home without its yard built: the nearest road even a little farther – a ring in a field is never found)
      local reach = place.action == 'home' and 450 or 160
      if (q.x - x) ^ 2 + (q.y - y) ^ 2 < reach ^ 2 then return vec3(q.x, q.y, zq) end
    end
  end
  return p
end

local function place(o, pos, yaw)
  local q = quatFromDir(vec3(math.sin(yaw), math.cos(yaw), 0), vec3(0, 0, 1))
  o:setPosRot(pos.x, pos.y, pos.z, q.x, q.y, q.z, q.w)
end

-- (2026-11-08) a rest area on a motorway has two sides and often only one point on the map: the ring lies on the side
-- the driver is on. The road at the place, and the roads running along it left and right of it, farthest within reach.
local function edgeAt(p)
  local ok, n1, n2 = pcall(map.findClosestRoad, p)
  local nodes = ok and n1 and n2 and map.getMap().nodes
  if not nodes or not nodes[n1] or not nodes[n2] then return nil end
  local a1, b1 = vec3(nodes[n1].pos), vec3(nodes[n2].pos)
  local ab = b1 - a1
  local l2 = ab.x * ab.x + ab.y * ab.y
  if l2 < 0.01 then return nil end
  local k = math.max(0, math.min(1, ((p.x - a1.x) * ab.x + (p.y - a1.y) * ab.y) / l2))
  local l = math.sqrt(l2)
  local link = nodes[n1].links and nodes[n1].links[n2]
  return a1 + ab * k, vec3(ab.x / l, ab.y / l, 0), link and link.oneWay
end
local function findSides(primary, action)
  if not (map and map.findClosestRoad and map.getMap) then return nil end
  local q0, u0, oneWay0 = edgeAt(primary)
  if not q0 then return nil end
  local n = vec3(u0.y, -u0.x, 0)
  local out = { vec3(primary) }
  for _, sgn in ipairs({ 1, -1 }) do
    local far
    for _, k in ipairs({ 18, 30, 45, 60, 80, 105, 130 }) do
      local pr = q0 + n * (sgn * k)
      local q, u, oneWay = edgeAt(pr)
      if q and math.abs(u:dot(u0)) > 0.8 and (action == 'sleep' or (oneWay and oneWay0)) then
        local off = (q - q0):dot(n) * sgn
        if off > 12 and off < 150 and (q.x - pr.x) ^ 2 + (q.y - pr.y) ^ 2 < 625 and (not far or off > far.off) then far = { q = q, off = off } end
      end
    end
    if far then out[#out + 1] = vec3(far.q.x, far.q.y, ground(far.q.x, far.q.y, far.q.z, 6) or far.q.z) end
  end
  return out
end
local function sidesTick(pp)
  if not ring or not pp then return end
  if t < (ring.sideAt or 0) then return end
  ring.sideAt = t + 1
  if ring.sideTries ~= false and (not ring.sides or #ring.sides < 2) and t >= (ring.sideRetry or 0) then
    ring.sideRetry = t + 3                     -- (Earth's road graph comes in as the driver gets nearer)
    ring.sideTries = (ring.sideTries or 0) + 1
    ring.sides = findSides(ring.home or ring.pos, ring.place.action) or ring.sides
    if ring.sideTries >= 8 then ring.sideTries = false end
  end
  local best, bd
  for _, s in ipairs(ring.sides or {}) do
    local d = (s.x - pp.x) ^ 2 + (s.y - pp.y) ^ 2
    if not bd or d < bd then best, bd = s, d end
  end
  if best then
    local cur = math.sqrt((ring.pos.x - pp.x) ^ 2 + (ring.pos.y - pp.y) ^ 2)
    if math.sqrt(bd) + 12 < cur then ring.pos = vec3(best) end
  end
end

-- Earth's origin shift (yard.lua's hook): the ring moved with the world
function M.transform(xf)
  if not ring or not ring.pos then return end
  local function mv(p) local x, y, z = xf:apply(p.x, p.y, p.z); return vec3(x, y, z) end
  ring.pos = mv(ring.pos)
  if ring.home then ring.home = mv(ring.home) end
  for i, s in ipairs(ring.sides or {}) do ring.sides[i] = mv(s) end
end

-- ctx: { near() → place or nil (id, action, name, icon, typeName, lat, lon), playerPos(), anchor(), yardSpot(),
--        speed() m/s }
function M.update(ctx, dt)
  t = t + (dt or 0)
  local p = ctx.near()
  local key = p and M.COLOR[p.action] and (tostring(p.id) .. ':' .. p.action) or nil
  if not key then clear(); return end
  if not ring or ring.key ~= key then
    clear()
    local pos = spotFor(p, ctx)
    if not pos then return end
    local c = M.COLOR[p.action]
    ring = { key = key, pos = pos, home = vec3(pos), place = p, ids = { makeStatic('ff_ring_' .. c, 'ff_stop_ring'), makeStatic('ff_gem_' .. c, 'ff_stop_gem') } }
  end
  ring.place = p
  -- the yard's spot moves with the yard (built a little later than the ring may be)
  if p.action == 'home' and ctx.yardSpot then
    local s = ctx.yardSpot()
    if s and (s - ring.pos):length() > 0.5 then ring.pos = s end
  end
  if (p.action == 'sleep' or p.action == 'refuel') and not p.parking then pcall(sidesTick, ctx.playerPos()) end
  local r = ring.ids[1] and scenetree.findObjectById(ring.ids[1])
  if r then place(r, ring.pos, t * 0.15) end
  local g = ring.ids[2] and scenetree.findObjectById(ring.ids[2])
  if g then place(g, ring.pos + vec3(0, 0, 3.4 + math.sin(t * 1.8) * 0.25), t * 1.6) end
  local pp = ctx.playerPos()
  ring.dist = pp and math.sqrt((pp.x - ring.pos.x) ^ 2 + (pp.y - ring.pos.y) ^ 2) or nil
  ring.inside = ring.dist and ring.dist <= M.RADIUS or false
  -- (where it is seen from the cab: the angle off the vehicle's nose, degrees – right +, left −; 2026-11-05)
  local d = ctx.playerDir and ctx.playerDir()
  if pp and d and ring.dist and ring.dist > 0.5 then
    local hx, hy = d.x, d.y
    local tx, ty = ring.pos.x - pp.x, ring.pos.y - pp.y
    ring.rel = math.deg(math.atan2(hx * ty - hy * tx, hx * tx + hy * ty)) * -1
  else
    ring.rel = nil
  end
end

function M.inside() return ring and ring.inside and ring.place or nil end

-- for the HUD: the prompt (inside) or the way there (near: from SHOW_M on, with the direction)
M.SHOW_M = 220
function M.hud()
  if not ring then return nil end
  local p = ring.place
  if not ring.inside and not (ring.dist and ring.dist < M.SHOW_M) then return nil end
  return { name = p.name, icon = p.icon, typeName = p.typeName, hint = p.hint or M.HINT[p.action], color = M.COLOR[p.action],
    inside = ring.inside or nil, dist = ring.dist, rel = ring.rel, action = p.action }
end

function M.reset() clear() end

return M
