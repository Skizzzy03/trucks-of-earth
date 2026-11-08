-- Trucks of Earth: the vehicles of the road scenes (the patrol car of a police check or an accident, the
-- ambulance), kept for reuse. Spawning a car costs a hitch of about a second in the middle of a drive (the patrol
-- car, beamng.log 2026-11-03: 1244 ms); so each is spawned once – at the career's start, while the screen is still
-- dark – and parked out of the way, switched off (no physics, not drawn). A scene takes one (moved there, switched
-- on), gives it back afterwards. A car the game removed in between is spawned again when needed.
-- M.prepare(nearPos) once; M.take(kind, pos, dir) -> id; M.give(id).

local M = {}

-- (only vehicles without an HTML dashboard screen are kept switched off: BeamNG.Earth's dashboard feature asks a
-- switched-off ETK 800 for its '@etk800_screen' texture every frame – over a thousand errors, the game's log went
-- quiet, 2026-11-03. The ambulance (the van has a screen) is spawned when needed: after a crash, standing anyway.)
M.SPECS = {
  police = { 'sunburst2', 'police' },
  ambulance = { 'van', 'ambulance_eu', noPool = true },
  -- (the broken-down car, the crashed one: spawned when needed – the game's simplified one, 2026-11-07; the police and
  -- the ambulance stay full vehicles: there are no simplified ones with a light bar)
  civil = { 'simple_traffic', 'etk800_eu_base_wagon', noPool = true },
  -- (the breakdown service's van, painted yellow)
  service = { 'van', 'h25_worker', noPool = true, paint = { 0.98, 0.76, 0.04 } },
}

local free = {}          -- kind -> { ids }
local kindOf = {}        -- id -> kind

local function valid(id) local o = id and getObjectByID(id); return o ~= nil, o end

-- (a brake on any loop: at most one new car per kind every SPAWN_GAP_S and 6 a minute in all – a spawn costs a second
-- of hitch; a scene that asks more often goes without, 2026-11-04 after 54 patrol cars in 100 s)
M.SPAWN_GAP_S, M.SPAWN_PER_MIN = 20, 6
local lastSpawn, recent = {}, {}
local function now() return os.clock() end
local function spawnAllowed(kind)
  local t = now()
  if lastSpawn[kind] and t - lastSpawn[kind] < M.SPAWN_GAP_S then return false end
  for i = #recent, 1, -1 do if t - recent[i] > 60 then table.remove(recent, i) end end
  if #recent >= M.SPAWN_PER_MIN then return false end
  lastSpawn[kind] = t
  recent[#recent + 1] = t
  return true
end

local function spawnNew(kind, pos, dir)
  local s = M.SPECS[kind]
  if not s then return nil end
  if not spawnAllowed(kind) then log('W', 'fernfahrer', 'pool: spawn of a ' .. kind .. ' refused (too often)'); return nil end
  local paint
  if s.paint and createVehiclePaint then
    local okP, p = pcall(createVehiclePaint, { x = s.paint[1], y = s.paint[2], z = s.paint[3], w = 1 }, { 0.2, 0.7, 0, 0 })
    if okP then paint = p end
  end
  local ok, veh = pcall(core_vehicles.spawnNewVehicle, s[1], {
    config = 'vehicles/' .. s[1] .. '/' .. s[2] .. '.pc', pos = pos, rot = quatFromDir(dir or vec3(0, 1, 0), vec3(0, 0, 1)),
    autoEnterVehicle = false, paint = paint,
  })
  if not ok or not veh then log('W', 'fernfahrer', 'pool spawn ' .. kind .. ': ' .. tostring(veh)); return nil end
  local id = veh:getID()
  kindOf[id] = kind
  if gameplay_traffic and gameplay_traffic.removeTraffic then pcall(gameplay_traffic.removeTraffic, id) end
  pcall(function()
    local own = require('realAITraffic/trafficAI/vehicleOwnership')
    if own and own.markPlayerOwned then own.markPlayerOwned(id) end
  end)
  return id, veh
end

local function park(id)
  local ok, o = valid(id)
  if not ok then return end
  o:queueLuaCommand('ai.setMode("disabled") electrics.set_lightbar_signal(0) electrics.set_warn_signal(0) controller.setFreeze(1)')
  local p = o:getPosition()
  o:setPositionRotation(p.x, p.y, p.z - 400, 0, 0, 0, 1)     -- (under the world, then off)
  o:setActive(0)
end

-- spawn the scene vehicles in advance (near pos: a place the ground is loaded at; moved away straight after)
function M.prepare(nearPos)
  for kind, spec in pairs(M.SPECS) do
    free[kind] = free[kind] or {}
    if #free[kind] == 0 and not spec.noPool then
      local id = spawnNew(kind, nearPos + vec3(0, 0, 50), vec3(0, 1, 0))
      if id then table.insert(free[kind], id); park(id) end
    end
  end
end

-- a vehicle of this kind at pos, facing dir, switched on (frozen, lights off: the caller sets them)
function M.take(kind, pos, dir)
  local list = free[kind] or {}
  free[kind] = list
  while #list > 0 do
    local id = table.remove(list)
    local ok, o = valid(id)
    if ok then
      o:setActive(1)
      local rot = quatFromDir(dir, vec3(0, 0, 1))      -- (facing dir, as the game's own respawns)
      local sp = rawget(_G, 'spawn')
      if sp and sp.safeTeleport then
        pcall(sp.safeTeleport, o, pos, rot, true, nil, false)
      else
        o:setPositionRotation(pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, rot.w)
      end
      return id
    end
  end
  return (spawnNew(kind, pos + vec3(0, 0, 0.5), dir))
end

-- done with it: parked again (one of each kind is kept; more are deleted)
function M.give(id)
  local ok, o = valid(id)
  if not ok then kindOf[id] = nil; return end
  local kind = kindOf[id]
  if kind and #(free[kind] or {}) < 1 and not (M.SPECS[kind] and M.SPECS[kind].noPool) then
    park(id)
    table.insert(free[kind], id)
  else
    o:delete()
    kindOf[id] = nil
  end
end

function M.owns(id) return kindOf[id] ~= nil end

function M.reset() free, kindOf = {}, {} end

return M
