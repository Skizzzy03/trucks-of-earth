-- Trucks of Earth: parked cars. BeamNG.Earth's road tiles carry the spots (car-park stalls and kerbside places,
-- beamngEarth/parking.lua onRows: rows {x, y, z, heading[, 1 = lot]}) and hand them to BeamNG's own parking system
-- (gameplay_parking); in this mode it is switched on (an amount by the player's setting) and the kerbside places are
-- kept only along town streets: a road of the game graph within KERB_M with drivability under 1 (residential) and
-- a limit of 50 km/h or less – none on main roads and country roads. Car-park stalls are always kept.
-- M.install() once (hooks the rows), M.start(amount, pos) once the traffic runs, M.stop().

local M = {}

M.KERB_M = 14
M.TOWN_MS = 14.5          -- (52 km/h)
M.enabled = true
M.stats = { kept = 0, dropped = 0 }

local function townStreet(x, y, z)
  if not (map and map.findClosestRoad and map.getMap) then return false end
  local ok, n1, n2, d = pcall(map.findClosestRoad, vec3(x, y, z))
  if not ok or not n1 or not n2 or (d and d > M.KERB_M) then return false end
  local nodes = map.getMap().nodes
  local link = nodes[n1] and nodes[n1].links and nodes[n1].links[n2]
  if not link then return false end
  return (link.drivability or 1) < 1 and (link.speedLimit or 99) <= M.TOWN_MS
end

-- (2026-11-08) what the world itself knows, as stops of the career: the car parks the parked cars stand on (a place to
-- rest) and every fuel station BeamNG.Earth builds – the shipped list misses many. Kept as lat / lon: it outlives Earth's
-- origin shifts. M.anchor is set by the career; M.lotsNear / M.fuelNear give what is around a place.
M.LOT_MIN = 8               -- (stalls that make it a car park worth a stop)
M.CELL = 0.0008             -- (degrees: about 80 m)
local lots, stalls, nStalls, fuels = {}, {}, 0, {}
local function geo(x, y, z)
  local a = M.anchor and M.anchor()
  if a and a.worldToGeodetic and x and y then return a:worldToGeodetic(x, y, z or 0) end
end
local function noteLots(rows)
  if nStalls > 60000 then stalls, nStalls = {}, 0 end
  for _, r in ipairs(rows) do
    if r[5] == 1 then
      local lat, lon = geo(tonumber(r[1]), tonumber(r[2]), tonumber(r[3]))
      if lat then
        local s = math.floor(lat * 40000) .. ':' .. math.floor(lon * 25000)
        if not stalls[s] then
          stalls[s], nStalls = true, nStalls + 1
          local k = math.floor(lat / M.CELL) .. ':' .. math.floor(lon / (M.CELL * 1.6))
          local c = lots[k] or { n = 0, la = 0, lo = 0, id = k }
          -- (one remembered from before: counted anew from its stalls, what it was known as kept)
          if c.saved then c = { n = 0, la = 0, lo = 0, id = k, hw = c.hw }; lots[k] = c end
          c.n, c.la, c.lo = c.n + 1, c.la + lat, c.lo + lon
          -- (2026-11-10: one real stall of it, the one nearest its middle: the ring goes there, not onto the road beside it -
          -- "da steht zwar Parkplatz, aber auf der Straße")
          local mla, mlo = c.la / c.n, c.lo / c.n
          if not c.sla or (lat - mla) ^ 2 + ((lon - mlo) * 0.62) ^ 2 < (c.sla - mla) ^ 2 + ((c.slo - mlo) * 0.62) ^ 2 then
            c.sla, c.slo, c.sh = lat, lon, tonumber(r[4])
          end
          if c.n == M.LOT_MIN then M.lotDirty = true; M.lotCount = (M.lotCount or 0) + 1 end
          lots[k] = c
        end
      end
    end
  end
end
local function noteFuel(recs)
  for _, r in ipairs(recs) do
    local spot = type(r) == 'table' and r.id and ((r.areas and r.areas[1]) or (r.props and r.props[1]))
    local electricOnly = false
    if spot and type(r.energy) == 'table' then
      electricOnly = true
      for _, e in ipairs(r.energy) do if e ~= 'electricEnergy' then electricOnly = false end end
    end
    if spot and spot.pos and not electricOnly and not fuels[r.id] then
      local lat, lon = geo(spot.pos[1], spot.pos[2], spot.pos[3])
      if lat then M.fuelDirty = true; M.fuelCount = (M.fuelCount or 0) + 1; fuels[r.id] = { id = r.id, lat = lat, lon = lon, name = (r.name and r.name ~= '') and r.name or ((r.brand and r.brand ~= '') and r.brand or 'Tankstelle') } end
    end
  end
end
-- the nearest car park within `m` of lat / lon: its middle, and how far; nil if none
function M.lotNear(lat, lon, m)
  local best, bd
  local kx, ky = 111320 * math.cos(math.rad(lat)), 111320
  for _, c in pairs(lots) do
    if c.n >= M.LOT_MIN then
      local la, lo = c.la / c.n, c.lo / c.n
      local d = math.sqrt(((lo - lon) * kx) ^ 2 + ((la - lat) * ky) ^ 2)
      if d <= m and (not bd or d < bd) then best, bd = c, d end
    end
  end
  if best then return { id = best.id, lat = best.la / best.n, lon = best.lo / best.n }, bd end
end
-- (2026-11-10) the nearest car park of all the world has shown, for the route (no distance limit but maxM)
function M.lotNearest(lat, lon, maxM)
  return M.lotNear(lat, lon, maxM or 30000)
end
-- (2026-11-10) the car parks as places: around lat / lon within m, the cells of one car park merged (a big one lies over several
-- 80 m cells), biggest first. { id, lat, lon, n (stalls), sla, slo, sh (a stall: where the ring lies, its heading), hw (beside a motorway) }
M.MERGE_M = 130
function M.lotsAround(lat, lon, m)
  local kx, ky = 111320 * math.cos(math.rad(lat)), 111320
  local dLa, dLo = m / ky + 0.002, m / kx + 0.003
  local cand = {}
  for _, c in pairs(lots) do
    if c.n >= M.LOT_MIN then
      local la, lo = c.la / c.n, c.lo / c.n
      if math.abs(la - lat) < dLa and math.abs(lo - lon) < dLo then cand[#cand + 1] = { c = c, la = la, lo = lo } end
    end
  end
  table.sort(cand, function(a, b) return a.c.n > b.c.n end)
  local out = {}
  for _, x in ipairs(cand) do
    local host
    for _, o in ipairs(out) do
      if math.sqrt(((o.lon - x.lo) * kx) ^ 2 + ((o.lat - x.la) * ky) ^ 2) < M.MERGE_M then host = o; break end
    end
    if host then
      host.n = host.n + x.c.n
      if x.c.hw then host.hw = true end
    else
      local d = math.sqrt(((x.lo - lon) * kx) ^ 2 + ((x.la - lat) * ky) ^ 2)
      if d <= m then
        out[#out + 1] = { id = 'lot:' .. x.c.id, lat = x.la, lon = x.lo, n = x.c.n, sla = x.c.sla, slo = x.c.slo, sh = x.c.sh, hw = x.c.hw, d = d, cell = x.c }
      end
    end
  end
  return out
end
function M.lotById(id)
  local c = lots[tostring(id):gsub('^lot:', '')]
  if c and c.n > 0 then return { id = 'lot:' .. c.id, lat = c.la / c.n, lon = c.lo / c.n, n = c.n, sla = c.sla, slo = c.slo, sh = c.sh, hw = c.hw, cell = c } end
end
-- beside a motorway? (a fast one-way road within ~150 m: the car park of a rest area). Asked once per car park, when the game's road
-- graph is there (near the player); nil: can't tell yet
function M.classify(c)
  if not c or c.hw ~= nil then return c and c.hw end
  local a = M.anchor and M.anchor()
  if not (a and a.geodeticToWorld and map and map.findClosestRoad and map.getMap) then return nil end
  local x, y = a:geodeticToWorld(c.la / c.n, c.lo / c.n, 0)
  local nodes = map.getMap().nodes
  local seen = 0
  for _, r in ipairs({ 0, 60, 120 }) do
    for k = 0, (r == 0 and 0 or 7) do
      local ang = k * math.pi / 4
      local p = vec3(x + math.cos(ang) * r, y + math.sin(ang) * r, 0)
      local okR, n1, n2, d = pcall(map.findClosestRoad, p)
      if okR and n1 and n2 and nodes[n1] and nodes[n2] then
        seen = seen + 1
        local link = (nodes[n1].links and nodes[n1].links[n2]) or (nodes[n2].links and nodes[n2].links[n1])
        if type(link) == 'table' and link.oneWay and (tonumber(link.speedLimit) or 0) >= 25 and (not d or d < 40) then
          c.hw = true; M.lotDirty = true
          return true
        end
      end
    end
  end
  if seen >= 6 then c.hw = false; M.lotDirty = true end
  return c.hw
end
-- remembered between sessions, as the fuel stations: the map shows the car parks one has seen
M.LOT_FILE = '/settings/fernfahrer/earth_lots.json'
M.LOT_MAX = 25000
function M.lotLoad()
  if M.lotLoaded then return end
  M.lotLoaded = true
  local ok, d = pcall(jsonReadFile, M.LOT_FILE)
  if ok and type(d) == 'table' then
    for _, x in ipairs(d) do
      if x.id and x.n and x.la and not lots[x.id] then
        lots[x.id] = { id = x.id, n = x.n, la = x.la * x.n, lo = x.lo * x.n, sla = x.sla, slo = x.slo, sh = x.sh, hw = x.hw, saved = true }
      end
    end
  end
end
function M.lotSave()
  if not M.lotDirty then return end
  M.lotDirty = false
  local list = {}
  for _, c in pairs(lots) do
    if c.n >= M.LOT_MIN and #list < M.LOT_MAX then
      list[#list + 1] = { id = c.id, n = c.n, la = c.la / c.n, lo = c.lo / c.n, sla = c.sla, slo = c.slo, sh = c.sh, hw = c.hw }
    end
  end
  pcall(jsonWriteFile, M.LOT_FILE, list, false)
end
-- (2026-11-09) all the fuel stations Earth has shown so far, remembered between sessions: they go on the office's map
M.FUEL_FILE = '/settings/fernfahrer/earth_fuel.json'
M.FUEL_MAX = 30000
function M.fuelAll() return fuels end
function M.fuelLoad()
  if M.fuelLoaded then return end
  M.fuelLoaded = true
  local ok, d = pcall(jsonReadFile, M.FUEL_FILE)
  if ok and type(d) == 'table' then
    for _, f in ipairs(d) do if f.id and f.lat and not fuels[f.id] then fuels[f.id] = f; M.fuelCount = (M.fuelCount or 0) + 1 end end
  end
end
function M.fuelSave()
  if not M.fuelDirty then return end
  M.fuelDirty = false
  local list = {}
  for _, f in pairs(fuels) do if #list < M.FUEL_MAX then list[#list + 1] = f end end
  pcall(jsonWriteFile, M.FUEL_FILE, list, false)
end
function M.fuelNear(lat, lon, m)
  local best, bd
  local kx, ky = 111320 * math.cos(math.rad(lat)), 111320
  for _, f in pairs(fuels) do
    local d = math.sqrt(((f.lon - lon) * kx) ^ 2 + ((f.lat - lat) * ky) ^ 2)
    if d <= m and (not bd or d < bd) then best, bd = f, d end
  end
  return best, bd
end
function M.resetPlaces() lots, stalls, nStalls, fuels = {}, {}, 0, {} end

function M.install()
  pcall(M.fuelLoad)
  pcall(M.lotLoad)
  -- (Earth's fuel stations: hooked once, whatever becomes of the parking below)
  local okG, gs = pcall(require, 'beamngEarth/gasstations')
  if okG and type(gs) == 'table' and gs.onRows and not gs.__fernfahrerFuel then
    local origG = gs.onRows
    gs.onRows = function(aid, key, recs)
      if type(recs) == 'table' then pcall(noteFuel, recs) end
      return origG(aid, key, recs)
    end
    gs.__fernfahrerFuel = true
  end
  local okP, pk = pcall(require, 'beamngEarth/parking')
  if not okP or type(pk) ~= 'table' or not pk.onRows or pk.__fernfahrerParked then return false end
  local orig = pk.onRows
  pk.onRows = function(aid, key, rows)
    if type(rows) == 'table' then pcall(noteLots, rows) end
    if M.enabled and type(rows) == 'table' then
      local keep = {}
      for _, r in ipairs(rows) do
        local x, y, z = tonumber(r[1]), tonumber(r[2]), tonumber(r[3]) or 0
        if r[5] == 1 or (x and y and townStreet(x, y, z)) then keep[#keep + 1] = r; M.stats.kept = M.stats.kept + 1
        else M.stats.dropped = M.stats.dropped + 1 end
      end
      rows = keep
    end
    return orig(aid, key, rows)
  end
  pk.__fernfahrerParked = true
  return true
end

-- the parked cars on: the stock system's own vehicles (lightweight parked configurations), `amount` of them
function M.start(amount, pos)
  local gp = rawget(_G, 'gameplay_parking')
  if not gp and extensions and extensions.load then pcall(extensions.load, 'gameplay_parking'); gp = rawget(_G, 'gameplay_parking') end
  if not gp or not gp.setupVehicles then return false end
  if gp.getState and gp.getState() then
    if gp.setActiveAmount then pcall(gp.setActiveAmount, amount) end
    return true
  end
  -- (2026-11-12) Earth's far cars would take the new parked cars for the player's own and delete them (career.lua L.farcarsHold)
  local car = rawget(_G, 'fernfahrer_career')
  if car and car.farcarsHold then pcall(car.farcarsHold, 90) end
  local ok, err = pcall(gp.setupVehicles, amount, { pos = pos })
  if not ok then log('W', 'fernfahrer', 'parked cars: ' .. tostring(err)) end
  return ok
end

function M.stop()
  local gp = rawget(_G, 'gameplay_parking')
  if gp and gp.deleteVehicles then pcall(gp.deleteVehicles) end
end

return M
