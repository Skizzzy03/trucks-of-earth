-- Trucks of Earth: trailer spots on the depot's grounds. A spot is laid beside the road nearest the depot's
-- OpenStreetMap point (the game's road graph, filled by BeamNG.Earth near the player), aligned with that road, with
-- the stock parking-spot marker (scenario/raceMarkers/parkingraceSpotMarker: glowing outline + ground stripes).
-- career.lua: M.compute(lat, lon, anchor) -> spot {pos, rot, dir, scl} or nil; M.show(spot, color); M.hide();
-- M.update(dt) every frame; M.contains(spot, pos, margin).

local M = {}

M.SIZE = vec3(4.2, 17, 1)     -- a semi trailer's footprint plus room
M.SIDE_M = 4.0                -- from the road's edge onto the grounds

local markerCtor
local marker, shown

local function ctor()
  if markerCtor == nil then
    local ok, c = pcall(require, 'scenario/raceMarkers/parkingraceSpotMarker')
    markerCtor = ok and type(c) == 'function' and c or false
  end
  return markerCtor or nil
end

local function ground(pos)
  local top = vec3(pos.x, pos.y, pos.z + 60)
  local hit = castRayStatic(top, vec3(0, 0, -1), 200)
  if not hit or hit >= 200 then return nil end
  return vec3(pos.x, pos.y, top.z - hit)
end

-- the spot for a depot at (lat, lon), or nil when the road graph / ground there is not loaded yet
function M.compute(lat, lon, anchor)
  if not anchor or not anchor.geodeticToWorld or not map or not map.findClosestRoad or not map.getMap then return nil end
  local x, y, z = anchor:geodeticToWorld(lat, lon, 0)
  local probe = ground(vec3(x, y, z)) or vec3(x, y, z)
  local ok, n1, n2, d = pcall(map.findClosestRoad, probe)
  if not ok or not n1 or not n2 or (d and d > 250) then return nil end
  local nodes = map.getMap().nodes
  local a, b = nodes[n1], nodes[n2]
  if not a or not b then return nil end
  local seg = b.pos - a.pos
  seg.z = 0
  local len = seg:length()
  if len < 1 then return nil end
  local dir = seg * (1 / len)
  -- the point of that road nearest the depot, then onto the depot's side of it
  local t = math.max(0, math.min(1, (probe - a.pos):dot(dir) / len))
  local onRoad = a.pos + dir * (t * len)
  local right = vec3(dir.y, -dir.x, 0)
  local side = (probe - onRoad):dot(right) >= 0 and 1 or -1
  local half = ((a.radius or 3) + (b.radius or 3)) / 2
  local pos = ground(onRoad + right * side * (half + M.SIDE_M + M.SIZE.x / 2))
  if not pos then return nil end
  local spot = { pos = pos, dir = dir, rot = quatFromDir(dir, vec3(0, 0, 1)), scl = M.SIZE, lat = lat, lon = lon }
  -- where it is on the Earth, so it survives BeamNG.Earth moving the world's origin (a rebase): refresh()
  if anchor.worldToGeodetic then spot.glat, spot.glon = anchor:worldToGeodetic(pos.x, pos.y, pos.z) end
  return spot
end

-- the spot's world position again from its lat / lon (after a rebase the world coordinates have moved)
function M.refresh(spot, anchor)
  if not spot or not spot.glat or not anchor or not anchor.geodeticToWorld then return spot end
  local x, y = anchor:geodeticToWorld(spot.glat, spot.glon, 0)
  if math.abs(x - spot.pos.x) > 1 or math.abs(y - spot.pos.y) > 1 then
    spot.pos = ground(vec3(x, y, spot.pos.z)) or vec3(x, y, spot.pos.z)
    if shown == spot and marker then marker:setSpot(spot.pos, spot.rot, spot.scl) end
  end
  return spot
end

function M.show(spot, color)
  if not spot then return M.hide() end
  local c = ctor()
  if not c then return end
  if not marker then
    marker = c('fernfahrerSpot')
    marker:createMarkers()
  end
  marker:setSpot(spot.pos, spot.rot, spot.scl)
  marker:setColor(color or { 1, 0.69, 0.18, 1 })
  marker:show()
  shown = spot
end

function M.setColor(color) if marker then marker:setColor(color) end end

function M.hide()
  if marker then
    pcall(function() marker:hide(); marker:clearMarkers() end)
    marker = nil
  end
  shown = nil
end

function M.update(dt)
  if marker and shown then pcall(marker.update, marker, dt) end
end

-- is `pos` inside the spot (with some margin, in metres)?
function M.contains(spot, pos, margin)
  if not spot or not pos then return false end
  margin = margin or 2
  local d = pos - spot.pos
  local along = math.abs(d:dot(spot.dir))
  local across = math.abs(d:dot(vec3(spot.dir.y, -spot.dir.x, 0)))
  return along <= spot.scl.y / 2 + margin and across <= spot.scl.x / 2 + margin and math.abs(d.z) < 4
end

return M
