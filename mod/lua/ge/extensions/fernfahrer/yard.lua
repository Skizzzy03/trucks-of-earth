-- Trucks of Earth: the company yard as buildings of its own (levels/beamng_earth/art/shapes/fernfahrer/yard,
-- tools/build_yard.js): a concrete yard 48 x 48 m with fence and gate, a hall the truck and trailer drive into, an
-- office, truck bays, lamps. Never inside BeamNG.Earth's world: the place is searched once near the home – beside a
-- road of the game graph (the gate towards it), no road through it, and the ground scanned with rays from above: a hit
-- well above the rest is a building, a wall, a tree (Earth's buildings are meshes of their road tiles, there is no
-- footprint list; their colliders stand within ~320 m of the player, so the search runs when the player is near).
-- Kept in the save (S.yard: lat, lon, compass heading of the yard's depth axis); built again on every visit, moved
-- with Earth's origin shifts (wrapping beamngEarth/pumpjacks.transform: called in the same frame as Earth's own).
-- M.update(ctx) a few times a second, M.parkSpot(), M.reset().

local M = {}

M.SHAPE = '/levels/beamng_earth/art/shapes/fernfahrer/yard/ff_yard.dae'
-- the joints and painted lines: drawn only (as solid ledges a few mm high they burst the tyres, 2026-11-03)
M.DECO = '/levels/beamng_earth/art/shapes/fernfahrer/yard/ff_yard_deco.dae'
M.W, M.D = 24, 48              -- (half width along the road, depth into the yard: the model's slab)
M.SEARCH_M = 180               -- (the yard's centre at most this far from the home)
M.NEAR_M = 220                 -- (the search runs with the player this near the home: the colliders are there)
M.BUILD_M = 700                -- (built with the player this near; gone beyond DROP_M)
M.DROP_M = 2500
M.OBSTACLE_M = 1.3             -- (a ray hit this far above the ground's median: something stands there)
M.RELIEF_M = 1.4               -- (the ground inside may rise or fall at most this much)
-- the lamps' heads (model: tools/build_yard.js) and the truck's place in front of the hall, facing the gate
M.LAMPS = { { -21.6, 1.2 }, { 21.6, 1.2 }, { 2.4, 27 }, { -1.1, 46.8 } }
M.PARK = { -13, 12 }
-- the search's passes: radius from the home, the most relief and clutter allowed (the colliders stand within ~320 m
-- of the player, who is at the home: farther than that a building would not be seen)
M.PASSES = {
  { r = 180, relief = 1.4, obstacle = 1.3 },
  { r = 300, relief = 2.4, obstacle = 1.5 },
  { r = 300, relief = 3.0, obstacle = 1.7 },
}

local Y                        -- the yard built: { id, lights, ox, oy, oz, ex, ey (unit vectors), anchorId }
local search                   -- a search under way: { cands, i, home }
M.status = 'idle'

local function deleteId(id)
  local o = id and scenetree.findObjectById(id)
  if o then pcall(function() o:delete() end) end
end

local function clear()
  if not Y then return end
  deleteId(Y.id)
  deleteId(Y.deco)
  for _, id in pairs(Y.props or {}) do deleteId(id) end
  for _, l in ipairs(Y.lights or {}) do deleteId(l) end
  Y = nil
  if be and be.reloadCollision then pcall(function() be:reloadCollision() end) end
end

-- the ground height at (x, y): a ray from above (nil: nothing there yet)
local function groundAt(x, y, zRef)
  local top = zRef + 120
  local d = castRayStatic(vec3(x, y, top), vec3(0, 0, -1), 300)
  if not d or d >= 300 then return nil end
  return top - d
end

-- the yard's frame: front middle (x, y), depth axis ey; a local (lx, ly) in world
local function toWorld(f, lx, ly)
  return f.ox + f.ex.x * lx + f.ey.x * ly, f.oy + f.ex.y * lx + f.ey.y * ly
end

-- the ground inside scanned: the slab's top height, or nil and why
-- (step: the grid's spacing – 8 m for a cheap first look at every candidate, 3 m only for the one that passed it:
-- 289 rays for each of 3 candidates per call gave a 4.1 s frame in the log of 2026-11-07)
local function scan(f, zRef, lax, step)
  local hs = {}
  step = step or 3
  -- (every 3 m and right up to the edges: a house's corner reaching a few metres in slipped between the 4 m rays,
  -- the offline check of 2026-11-07)
  local xs, ys = {}, {}
  for lx = -M.W + 0.5, M.W - 0.5, step do xs[#xs + 1] = lx end
  if xs[#xs] < M.W - 0.6 then xs[#xs + 1] = M.W - 0.5 end
  for ly = 0.5, M.D - 0.5, step do ys[#ys + 1] = ly end
  if ys[#ys] < M.D - 0.6 then ys[#ys + 1] = M.D - 0.5 end
  for _, ly in ipairs(ys) do
    for _, lx in ipairs(xs) do
      local x, y = toWorld(f, lx, ly)
      local h = groundAt(x, y, zRef)
      if not h then return nil, 'wait' end
      hs[#hs + 1] = h
    end
  end
  local sorted = {}
  for i, h in ipairs(hs) do sorted[i] = h end
  table.sort(sorted)
  local med = sorted[math.floor(#sorted / 2) + 1]
  local lo, hi = med, med
  for _, h in ipairs(hs) do
    if h > med + (lax and lax.obstacle or M.OBSTACLE_M) then return nil, 'blocked' end
    if h < lo then lo = h end
    if h > hi then hi = h end
  end
  local info = { span = hi - lo, top = hi + 0.08 }
  if hi - lo > (lax and lax.relief or M.RELIEF_M) then return nil, 'slope', info end
  return hi + 0.08, nil, info
end

-- no road of the game graph inside (the yard's road, at the front, stays outside by its place)
local function roadInside(f, nodes, near)
  local cx, cy = toWorld(f, 0, M.D / 2)
  for _, n in pairs(near or nodes) do
    local p = n.pos
    if (p.x - cx) ^ 2 + (p.y - cy) ^ 2 < 150 ^ 2 then
      for k, _ in pairs(n.links or {}) do
        local q = nodes[k] and nodes[k].pos
        if q then
          local r = math.max(n.radius or 3, nodes[k].radius or 3)
          local len = math.sqrt((q.x - p.x) ^ 2 + (q.y - p.y) ^ 2)
          local steps = math.max(1, math.floor(len / 3))
          for s = 0, steps do
            local x, y = p.x + (q.x - p.x) * s / steps, p.y + (q.y - p.y) * s / steps
            local dx, dy = x - f.ox, y - f.oy
            local lx, ly = dx * f.ex.x + dy * f.ex.y, dx * f.ey.x + dy * f.ey.y
            -- (the road's edge reaching into the yard, its fence or its ramp)
            if math.abs(lx) < M.W + r + 1 and ly > 0.5 - r and ly < M.D + r + 1 then return true end
          end
        end
      end
    end
  end
  return false
end

-- candidates beside the roads around the home, nearest first
local function candidates(home, nodes, radius, near)
  local out, seen = {}, {}
  for a, n in pairs(near or nodes) do
    local p = n.pos
    if (p.x - home.x) ^ 2 + (p.y - home.y) ^ 2 < ((radius or M.SEARCH_M) + 60) ^ 2 then
      for b, _ in pairs(n.links or {}) do
        local key = a < b and (tostring(a) .. '|' .. tostring(b)) or (tostring(b) .. '|' .. tostring(a))
        local q = nodes[b] and nodes[b].pos
        if q and not seen[key] then
          seen[key] = true
          local dx, dy = q.x - p.x, q.y - p.y
          local len = math.sqrt(dx * dx + dy * dy)
          if len > 1 then
            local ux, uy = dx / len, dy / len
            local hw = math.max(n.radius or 3, nodes[b].radius or 3)
            for s = 5, len - 5, 10 do
              for _, side in ipairs({ 1, -1 }) do
                local ey = vec3(uy * side, -ux * side, 0)          -- (perpendicular, away from the road)
                local ex = vec3(ey.y, -ey.x, 0)
                local ox, oy = p.x + ux * s + ey.x * (hw + 3), p.y + uy * s + ey.y * (hw + 3)
                local cx, cy = ox + ey.x * M.D / 2, oy + ey.y * M.D / 2
                local dh = math.sqrt((cx - home.x) ^ 2 + (cy - home.y) ^ 2)
                -- (the home point itself stays free: a teleport home lands there)
                local hx, hy = home.x - ox, home.y - oy
                local hlx, hly = hx * ex.x + hy * ex.y, hx * ey.x + hy * ey.y
                local homeIn = math.abs(hlx) < M.W + 10 and hly > -10 and hly < M.D + 10
                if dh <= (radius or M.SEARCH_M) and not homeIn then
                  out[#out + 1] = { ox = ox, oy = oy, ex = ex, ey = ey, d = dh }
                end
              end
            end
          end
        end
      end
    end
  end
  table.sort(out, function(u, v) return u.d < v.d end)
  return out
end

-- build at frame f with the slab top at z
local function build(f, z, anchorId, night)
  clear()
  local o = createObject('TSStatic')
  if not o then return false end
  o:setField('shapeName', 0, M.SHAPE)
  o:setField('collisionType', 0, 'Visible Mesh Final')    -- (the engine's advice in the log: cheaper than 'Visible Mesh')
  o:setField('decalType', 0, 'None')
  o.canSave = false
  o:registerObject('ff_yard')
  if scenetree.MissionGroup then pcall(function() scenetree.MissionGroup:addObject(o) end) end
  Y = { id = o:getID(), lights = {}, ox = f.ox, oy = f.oy, oz = z, ex = f.ex, ey = f.ey, anchorId = anchorId }
  local d = createObject('TSStatic')
  if d then
    d:setField('shapeName', 0, M.DECO)
    d:setField('collisionType', 0, 'None')
    d:setField('decalType', 0, 'None')
    d.canSave = false
    d:registerObject('ff_yard_deco')
    if scenetree.MissionGroup then pcall(function() scenetree.MissionGroup:addObject(d) end) end
    Y.deco = d:getID()
  end
  M.place(night)
  if be and be.reloadCollision then pcall(function() be:reloadCollision() end) end
  return true
end

-- (2026-11-07) the yard's upgrades (career.lua YARD_UP, bought in the office): their props from the game's own art,
-- placed in the yard's frame { shape, x along the road, y into the yard, yaw (deg, 0: facing the gate), wcu materials }
local WCU_B, WCU_O = '/levels/west_coast_usa/art/shapes/buildings/', '/levels/west_coast_usa/art/shapes/objects/'
local GAR = '/art/shapes/garage_and_dealership/garage/'
M.UPGRADE_PROPS = {
  pump = { { WCU_B .. 's_fuel_pump_2015.dae', -19.5, 18, 90, true }, { WCU_B .. 's_fuel_pump_2015.dae', -19.5, 24, 90, true } },
  workshop = { { GAR .. 's_big_toolbox_01.dae', -6, 45.2, 180 }, { GAR .. 's_big_toolbox_02.dae', -4.4, 45.2, 180 },
    { WCU_O .. 'hr_tirestack_white.dae', -2.2, 44.6, 0, true }, { WCU_O .. 'hr_tirestack_blue.dae', -0.9, 44.6, 0, true } },
  warehouse = { { '/levels/beamng_earth/art/shapes/fernfahrer/props/ff_pallet.dae', 15, 26, 0 }, { '/levels/beamng_earth/art/shapes/fernfahrer/props/ff_pallet.dae', 16.5, 26, 0 },
    { '/levels/beamng_earth/art/shapes/fernfahrer/props/ff_crate.dae', 15, 28, 10 }, { '/levels/beamng_earth/art/shapes/fernfahrer/props/ff_crate.dae', 16.6, 28.2, -8 },
    { '/levels/beamng_earth/art/shapes/fernfahrer/props/ff_pallet.dae', 18, 26, 0 } },
}
M.upgrades = {}
local wcuMats = false
local function needWcuMats()
  if wcuMats then return end
  wcuMats = true
  for _, f in ipairs({ WCU_B .. 'main.materials.json', WCU_O .. 'main.materials.json' }) do
    if FS:fileExists(f) and loadJsonMaterialsFile then pcall(loadJsonMaterialsFile, f) end
  end
end
function M.setUpgrades(list)
  M.upgrades = list or {}
  if Y then M.place(Y.night) end
end
local function placeUpgrades(q)
  Y.props = Y.props or {}
  for key, props in pairs(M.UPGRADE_PROPS) do
    for i, p in ipairs(props) do
      local k = key .. i
      local id = Y.props[k]
      local o = id and scenetree.findObjectById(id)
      if M.upgrades[key] then
        if not o then
          if p[5] then needWcuMats() end
          o = createObject('TSStatic')
          if o then
            o:setField('shapeName', 0, p[1])
            o:setField('collisionType', 0, 'Visible Mesh Final')
            o:setField('decalType', 0, 'None')
            o.canSave = false
            o:registerObject('ff_yard_up_' .. k)
            Y.props[k] = o:getID()
          end
        end
        if o then
          local x, y = toWorld(Y, p[2], p[3])
          local a = math.rad(p[4] or 0)
          local dir = vec3(Y.ey.x * math.cos(a) - Y.ey.y * math.sin(a), Y.ey.x * math.sin(a) + Y.ey.y * math.cos(a), 0)
          local qq = quatFromDir(dir, vec3(0, 0, 1))
          o:setPosRot(x, y, Y.oz, qq.x, qq.y, qq.z, qq.w)
        end
      elseif o then
        pcall(function() o:delete() end)
        Y.props[k] = nil
      end
    end
  end
end

-- the yard (and its lamps) where Y says
function M.place(night)
  if not Y then return end
  local q = quatFromDir(Y.ey, vec3(0, 0, 1))
  for _, id in ipairs({ Y.id, Y.deco }) do
    local o = scenetree.findObjectById(id)
    if o then o:setPosRot(Y.ox, Y.oy, Y.oz, q.x, q.y, q.z, q.w) end
  end
  pcall(placeUpgrades, q)
  for i, lp in ipairs(M.LAMPS) do
    local id = Y.lights[i]
    local l = id and scenetree.findObjectById(id)
    if not l then
      l = createObject('PointLight')
      if l then
        l.canSave = false
        pcall(function()
          l.radius = 22
          l:setField('color', 0, '1 0.86 0.62 1')
          l:setField('brightness', 0, '1.4')
          l:setField('castShadows', 0, '0')
        end)
        l:registerObject('ff_yard_lamp' .. i)
        Y.lights[i] = l:getID()
      end
    end
    if l then
      local x, y = toWorld(Y, lp[1], lp[2])
      l:setPosition(vec3(x, y, Y.oz + 6.5))
      pcall(function() l.isEnabled = night and true or false end)
    end
  end
  Y.night = night
end

-- Earth's origin shift: everything moved by p' = R*p + t (as its pump jacks)
function M.transform(xf)
  if not Y then return end
  local ax, ay = xf:apply(Y.ox + Y.ey.x, Y.oy + Y.ey.y, Y.oz)
  Y.ox, Y.oy, Y.oz = xf:apply(Y.ox, Y.oy, Y.oz)
  local ey = vec3(ax - Y.ox, ay - Y.oy, 0):normalized()
  Y.ey, Y.ex = ey, vec3(ey.y, -ey.x, 0)
  Y.shifted = true
  M.place(Y.night)
end

-- (others moved with Earth's origin shifts too: stops.lua's rings)
M.shiftHooks = {}
local hooked = false
local function hook()
  if hooked then return end
  local ok, pj = pcall(require, 'beamngEarth/pumpjacks')
  if not ok or type(pj) ~= 'table' or not pj.transform then return end
  local orig = pj.transform
  pj.transform = function(xf, ...)
    local r = orig(xf, ...)
    pcall(M.transform, xf)
    for _, fn in ipairs(M.shiftHooks) do pcall(fn, xf) end
    return r
  end
  hooked = true
end

-- the truck's place: in front of the hall, facing the gate (world pos, direction), when the yard stands
function M.parkSpot()
  if not Y then return nil end
  local x, y = toWorld(Y, M.PARK[1], M.PARK[2])
  return { pos = vec3(x, y, Y.oz + 0.6), dir = vec3(-Y.ey.x, -Y.ey.y, 0) }
end

function M.built() return Y ~= nil end

-- the yard's stop ring: on the concrete in front of the office door (world pos, slab height)
function M.officeSpot()
  if not Y then return nil end
  local x, y = toWorld(Y, 11, 23.5)
  return vec3(x, y, Y.oz)
end
M.hook = function() hook() end

-- the yard's middle on its concrete and its depth axis (the day's camera flight)
function M.center()
  if not Y then return nil end
  local x, y = toWorld(Y, 0, M.D / 2)
  return vec3(x, y, Y.oz), Y.ey
end

-- ctx: { save() → S, homeWorld() → vec3, playerPos() → vec3, anchor(), anchorId(), loading() → bool, night() → bool,
--        found(yard) (first time) }
function M.update(ctx)
  hook()
  local S = ctx.save()
  local anchor, aid = ctx.anchor(), ctx.anchorId()
  local pp = ctx.playerPos()
  if not S or not anchor or not pp then return end
  if ctx.loading() then if not Y then M.status = 'waiting for the world' end; return end
  -- a new world (teleport, a new session) without the shift: the yard built again
  if Y and Y.anchorId ~= aid then
    if Y.shifted then Y.anchorId, Y.shifted = aid, nil else clear() end
  end
  if Y and Y.night ~= ctx.night() then M.place(ctx.night()) end
  -- found before: built when near
  if S.yard and S.yard.lat then
    local x, y = anchor:geodeticToWorld(S.yard.lat, S.yard.lon, 0)
    local d = math.sqrt((x - pp.x) ^ 2 + (y - pp.y) ^ 2)
    if Y and d > M.DROP_M then clear(); M.status = 'far'; return end
    if not Y and d < M.BUILD_M then
      local h = math.rad(S.yard.hdg or 0)
      local ey = vec3(math.sin(h), math.cos(h), 0)
      local f = { ox = x, oy = y, ex = vec3(ey.y, -ey.x, 0), ey = ey }
      local z = scan(f, pp.z)
      if z then build(f, z, aid, ctx.night()); M.status = 'built' else M.status = 'waiting for ground' end
    end
    return
  end
  -- (a search that failed in an older version: once more per session, with the passes)
  if S.yard and S.yard.failed and not M.retried then S.yard = nil; M.retried = true end
  if S.yard and S.yard.failed then return end
  -- not found yet: searched with the player near the home (a few candidates per call: the rays cost)
  local home = ctx.homeWorld()
  if not home then return end
  if (home.x - pp.x) ^ 2 + (home.y - pp.y) ^ 2 > M.NEAR_M ^ 2 then M.status = 'drive home to build'; return end
  local nodes = map and map.getMap and map.getMap().nodes
  if not nodes or not next(nodes) then return end
  -- (2026-11-05: in passes – strict and near first; then farther (still where the colliders are) and less strict about
  -- slope and clutter; at the very last the flattest free place seen. It gave up after one pass near Dorsten: no yard,
  -- no ring, no start.)
  -- (2026-11-07: the graph's nodes near the home picked once – Earth's whole graph was walked for every candidate)
  if not search then
    local near, rr = {}, (M.PASSES[#M.PASSES].r + 260) ^ 2
    for id, n in pairs(nodes) do
      local p = n.pos
      if p and (p.x - home.x) ^ 2 + (p.y - home.y) ^ 2 < rr then near[id] = n end
    end
    search = { near = near, cands = candidates(home, nodes, M.PASSES[1].r, near), i = 1, waits = 0, pass = 1 }
    log('I', 'fernfahrer', string.format('yard: searching near the home, %d places to look at', #search.cands))
    return
  end
  M.status = string.format('searching %d/%d (pass %d)', search.i, #search.cands, search.pass)
  local lax = M.PASSES[search.pass]
  local t0 = os.clock()
  for _ = 1, 4 do
    if os.clock() - t0 > 0.004 then return end          -- (a few ms per call at most)
    local f = search.cands[search.i]
    if not f then
      if search.pass < #M.PASSES then
        local nextPass, best = search.pass + 1, search.best
        search = { near = search.near, cands = candidates(home, nodes, M.PASSES[nextPass].r, search.near), i = 1, waits = 0, pass = nextPass, best = best }
        log('I', 'fernfahrer', string.format('yard: none found in pass %d – searching wider and less strict', nextPass - 1))
        return
      end
      -- the last resort: the flattest free place any pass saw (the slab evens it out)
      local b = search.best
      if b then
        local lat, lon = anchor:worldToGeodetic(b.f.ox, b.f.oy, 0)
        S.yard = { lat = lat, lon = lon, hdg = math.deg(math.atan2(b.f.ey.x, b.f.ey.y)) % 360, v = 1 }
        search = nil
        build(b.f, b.z, aid, ctx.night())
        M.status = 'built'
        log('I', 'fernfahrer', string.format('yard built (the best place there was, %.1f m relief) at %.5f, %.5f', b.relief, lat, lon))
        if ctx.found then pcall(ctx.found, S.yard) end
        return
      end
      S.yard = { failed = true }
      search = nil
      log('W', 'fernfahrer', 'yard: no free, flat place beside a road near the home')
      return
    end
    if not roadInside(f, nodes, search.near) then
      -- (a cheap 8 m look first; the full 3 m scan only where that found nothing in the way)
      local z, why, relief = scan(f, pp.z, lax, 8)
      if z then z, why, relief = scan(f, pp.z, lax, 3) end
      if relief and why ~= 'blocked' and (not search.best or relief.span < search.best.relief) then
        search.best = { f = f, z = relief.top, relief = relief.span }
      end
      if why == 'wait' then
        search.waits = search.waits + 1
        if search.waits < 12 then return end          -- (the ground there not loaded yet: again later)
      end
      if z then
        local lat, lon = anchor:worldToGeodetic(f.ox, f.oy, 0)
        S.yard = { lat = lat, lon = lon, hdg = math.deg(math.atan2(f.ey.x, f.ey.y)) % 360, v = 1 }
        search = nil
        build(f, z, aid, ctx.night())
        M.status = 'built'
        log('I', 'fernfahrer', string.format('yard built at %.5f, %.5f (%.0f m from the home)', lat, lon, f.d))
        if ctx.found then pcall(ctx.found, S.yard) end
        return
      end
    end
    search.i = search.i + 1
    search.waits = 0
  end
end

-- a new home (the office: move the yard here) or the level's end
function M.forget(S) if S then S.yard = nil end; search = nil; clear() end
function M.reset() search = nil; Y = nil end     -- (the level is gone: its objects with it)

-- (offline tests)
M._candidates, M._roadInside = candidates, roadInside

return M
