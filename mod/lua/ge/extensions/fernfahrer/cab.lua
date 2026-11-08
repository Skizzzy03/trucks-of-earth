-- Trucks of Earth: mirrors and seat (HUD FernfahrerCockpit, a fold-out strip as ETS2's in-cab adjustment).
-- Mirrors through BeamNG's own core_vehicle_mirror (angles per vehicle and config, saved in settings/mirrorOffsets.json;
-- the driver's view turned onto the mirror being set). The seat through the driver camera itself (occupant.lua:
-- seatPosition y forward/back and z up/down ±0.4 m, seatRotation −30..20°, manualzoom.fov – it saves them per vehicle
-- when its saveTimeout runs out).

local M = {}

-- the camera the driver sees through: an occupant camera (occupant.lua, it has the seat). The game's
-- getDriverCameraNameById returns the hidden 'onboard.driver' data first when a vehicle has it – a camera without a
-- seat: the seat buttons changed nothing (2026-11-04). So: the active camera if it has a seat, else the occupant
-- camera meant for the driver, else any occupant camera.
local function driverCam(veh)
  if not core_camera then return nil end
  local vid = veh:getID()
  local okD, cams = pcall(core_camera.getCameraDataById, vid)
  cams = okD and type(cams) == 'table' and cams or {}
  local okA, active = pcall(core_camera.getActiveCamName, 0)
  if okA and active and cams[active] and (cams[active].seatPosition or tostring(active):find('^occupant')) then
    return cams[active], active
  end
  local any
  for name, c in pairs(cams) do
    if type(c) == 'table' and tostring(name):find('^occupant%.') then
      if c.defaultPermissionMode == 'driver' then return c, name end
      any = any or { c, name }
    end
  end
  if any then return any[1], any[2] end
  if core_camera.getDriverCameraNameById then
    local ok, name, cam = pcall(core_camera.getDriverCameraNameById, vid)
    if ok then return cam, name end
  end
end

-- a friendly name for a mirror mesh
local function mirrorLabel(name, label)
  local n = tostring(name):lower()
  if label and not tostring(label):find('^ui%.') and label ~= '' then return label end
  if n:find('inner') or n:find('interior') or n:find('center') or n:find('rearview') then return 'Innenspiegel' end
  local side = (n:find('left') or n:find('_l$') or n:find('_l_') or n:find('%.l$') or n:find('_fl')) and 'links'
    or ((n:find('right') or n:find('_r$') or n:find('_r_') or n:find('%.r$') or n:find('_fr')) and 'rechts') or nil
  local kind = (n:find('wide') or n:find('lower') or n:find('ramp') or n:find('spot') or n:find('blind')) and 'Weitwinkel'
    or ((n:find('front') or n:find('curb') or n:find('bumper')) and 'Rampe/Front' or 'Außenspiegel')
  return kind .. (side and (' ' .. side) or '')
end

local function mirrorsOf(veh)
  if not core_vehicle_mirror then pcall(extensions.load, 'core_vehicle_mirror') end
  local ok, t = pcall(core_vehicle_mirror.getAnglesOffset, veh:getID(), veh)
  local out = {}
  for name, m in pairs(ok and t or {}) do
    out[#out + 1] = { name = name, label = mirrorLabel(name, m.label), x = m.angleOffset and m.angleOffset.x or 0,
      z = m.angleOffset and m.angleOffset.z or 0, cx = m.clampX or { -20, 20 }, cz = m.clampZ or { -20, 20 } }
  end
  table.sort(out, function(a, b) return a.label < b.label end)
  return out
end

function M.view(veh)
  if not veh then return { none = true } end
  local v = { mirrors = mirrorsOf(veh) }
  local cam = driverCam(veh)
  if cam then
    local sp = cam.seatPosition
    v.seat = { y = sp and sp.y or 0, z = sp and sp.z or 0, tilt = cam.seatRotation or 0,
      fov = cam.manualzoom and cam.manualzoom.fov or nil, ready = sp ~= nil }
  end
  local okC, active = pcall(core_camera.getActiveCamName, 0)
  v.inCab = okC and (active == 'driver' or tostring(active):find('^occupant') ~= nil) or false
  return v
end

-- a mirror: turned by dx (up/down) and dz (left/right) degrees, or back to straight; the view on it
function M.mirror(veh, name, dx, dz, reset)
  if not veh or not core_vehicle_mirror then return end
  for _, m in ipairs(mirrorsOf(veh)) do
    if m.name == name then
      local x = reset and 0 or math.max(m.cx[1], math.min(m.cx[2], m.x + (dx or 0)))
      local z = reset and 0 or math.max(m.cz[1], math.min(m.cz[2], m.z + (dz or 0)))
      pcall(core_vehicle_mirror.setAngleOffset, name, x, z, veh, true)
      pcall(core_vehicle_mirror.focusOnMirror, name)
      return
    end
  end
end

-- the view back to straight ahead (the strip closed or another page)
function M.unfocus() if core_vehicle_mirror then pcall(core_vehicle_mirror.focusOnMirror) end end

-- the driver's view on (the seat is the driver camera's)
function M.toCab(veh)
  if not veh then return end
  local okA, active = pcall(core_camera.getActiveCamName, 0)
  if okA and (active == 'driver' or tostring(active):find('^occupant')) then return end     -- (already in the cab)
  local ok, name = pcall(core_camera.getDriverCameraNameById, veh:getID())
  if not (ok and name) then local _, n = driverCam(veh); name = n end
  if name then pcall(core_camera.setByName, 0, name, false) end
end

-- the seat: 'y' forward/back, 'z' up/down (metres), 'tilt' (degrees), 'fov' (degrees), 'reset'
function M.seat(veh, what, d)
  local cam = veh and driverCam(veh)
  if not cam then return end
  if what == 'reset' then
    if cam.resetSeat then pcall(cam.resetSeat, cam) end
    if cam.manualzoom then cam.manualzoom.fov = 70 end
  elseif what == 'fov' then
    if cam.manualzoom then cam.manualzoom.fov = math.max(40, math.min(110, (cam.manualzoom.fov or 70) + d)) end
  else
    if not cam.seatPosition then return end           -- (the driver camera has not run yet: the cab view first)
    if what == 'y' then cam.seatPosition.y = math.max(-0.4, math.min(0.4, cam.seatPosition.y + d))
    elseif what == 'z' then cam.seatPosition.z = math.max(-0.4, math.min(0.4, cam.seatPosition.z + d))
    elseif what == 'tilt' then cam.seatRotation = math.max(-30, math.min(20, (cam.seatRotation or 0) + d)) end
  end
  cam.saveTimeout = 0.3                                 -- (the camera saves it per vehicle)
end

return M
