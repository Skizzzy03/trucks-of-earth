-- (2026-11-05: the towns now come from GeoNames, CC BY 4.0 – /fernfahrer/towns, Germany and its neighbours; the street
-- tiles of one region were left out of the published mod: nameAt answers nil where there are none)
-- Trucks of Earth: street names and places from OpenStreetMap, shipped with the mod (tools/build_streets.js):
-- BeamNG.Earth's road data has none, and the police report wants "auf der Ahauser Straße (L 581) in Velen".
-- Files: /fernfahrer/streets/streets_<lat>_<lon>.json per 0.1° tile = { names, pts = {{lat*1e5, lon*1e5, nameIdx}} }
--        /fernfahrer/streets/settlements.json = { list = {{name, kind, lat, lon}} }
-- Loaded only when asked (an accident), one tile at a time, kept in memory after.
-- M.nameAt(lat, lon) -> street name or nil; M.placeAt(lat, lon) -> { name, kind, dist, inside } or nil.
-- Data © OpenStreetMap contributors, ODbL.

local M = {}

local DIR = '/fernfahrer/streets/'
local TILE = 0.1
M.MATCH_M = 40           -- the nearest named road point this close counts

local tiles = {}
local settlements = nil

local function hav(a1, o1, a2, o2)
  local p1, p2 = math.rad(a1), math.rad(a2)
  local dp, dl = p2 - p1, math.rad(o2 - o1)
  local x = math.sin(dp / 2) ^ 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ^ 2
  return 2 * 6371000 * math.asin(math.min(1, math.sqrt(x)))
end

local function key(lat, lon)
  return string.format('%.1f_%.1f', math.floor(lat / TILE + 1e-9) * TILE, math.floor(lon / TILE + 1e-9) * TILE)
end

local function tile(k)
  if tiles[k] == nil then
    local f = DIR .. 'streets_' .. k .. '.json'
    local d = FS:fileExists(f) and jsonReadFile(f) or nil
    tiles[k] = type(d) == 'table' and d or false
  end
  return tiles[k] or nil
end

-- the street at (lat, lon): the nearest named point of this tile and the neighbours
function M.nameAt(lat, lon)
  if not lat or not lon then return nil end
  local best, bd
  local la, lo = lat * 1e5, lon * 1e5
  local cosLat = math.cos(math.rad(lat))
  for da = -1, 1 do
    for dlo = -1, 1 do
      local t = tile(key(lat + da * TILE, lon + dlo * TILE))
      if t and t.pts then
        -- the nearest road piece: between two following points of the same road (the points stand at the map's
        -- vertices – far apart on a long straight one), else the point itself
        local prev
        for _, p in ipairs(t.pts) do
          local py, px = (p[1] - la) * 1.11320, (p[2] - lo) * 1.11320 * cosLat    -- (m: 1e-5 deg = 1.11 m; us at 0,0)
          local d2 = px * px + py * py
          if prev and prev[3] == p[3] then
            local qy, qx = (prev[1] - la) * 1.11320, (prev[2] - lo) * 1.11320 * cosLat
            local sx, sy = px - qx, py - qy
            local l2 = sx * sx + sy * sy
            if l2 > 0.01 and l2 < 400 * 400 then
              local tt = math.max(0, math.min(1, -(qx * sx + qy * sy) / l2))
              local cx, cy = qx + sx * tt, qy + sy * tt
              d2 = math.min(d2, cx * cx + cy * cy)
            end
          end
          if d2 < (M.MATCH_M * M.MATCH_M) and (not bd or d2 < bd) then best, bd = t.names[p[3] + 1], d2 end
          prev = p
        end
      end
    end
  end
  return best
end

-- the place: the nearest settlement; inside it when within its usual radius (a city ~4 km, a hamlet ~0.5 km)
local RADIUS = { city = 5000, town = 2500, suburb = 1500, quarter = 900, village = 1300, hamlet = 600 }
-- (2026-11-05: the towns of Germany and around, per 1-degree tile: /fernfahrer/towns/<lat>_<lon>.json { list };
-- the old single settlements.json – one region only – is read where no tile is)
local TOWNS = '/fernfahrer/towns/'
local townTiles = {}
local function townTile(la, lo)
  local k = la .. '_' .. lo
  if townTiles[k] == nil then
    local f = TOWNS .. k .. '.json'
    local d = FS:fileExists(f) and jsonReadFile(f) or nil
    townTiles[k] = type(d) == 'table' and d.list or false
  end
  return townTiles[k] or nil
end
-- (noSuburbs: districts left out – the town banner names the town, not each district of a city)
function M.placeAt(lat, lon, noSuburbs)
  if not lat or not lon then return nil end
  local lists = {}
  for la = math.floor(lat - 0.15), math.floor(lat + 0.15) do
    for lo = math.floor(lon - 0.25), math.floor(lon + 0.25) do
      local t = townTile(la, lo)
      if t then lists[#lists + 1] = t end
    end
  end
  if #lists == 0 then
    if settlements == nil then
      local f = DIR .. 'settlements.json'
      local d = FS:fileExists(f) and jsonReadFile(f) or nil
      settlements = type(d) == 'table' and d.list or false
    end
    if settlements then lists[1] = settlements end
  end
  if #lists == 0 then return nil end
  local best, bd, inside
  for _, list in ipairs(lists) do
    for _, s in ipairs(list) do
      if math.abs(s[3] - lat) < 0.15 and math.abs(s[4] - lon) < 0.25 and not (noSuburbs and s[2] == 'suburb') then
        local d = hav(lat, lon, s[3], s[4])
        local r = RADIUS[s[2]] or 1000
        -- (GeoNames tiles carry the population: a big city reaches farther, a hamlet only a few hundred metres)
        local pop = s[5]
        if pop then
          r = pop >= 500000 and 9000 or pop >= 100000 and 5500 or pop >= 30000 and 3200 or pop >= 10000 and 2200
            or pop >= 3000 and 1400 or pop >= 500 and 900 or 600
        end
        -- (inside one beats nearer outside ones; among the inside ones the smaller kind: a quarter of a city)
        local score = d / r
        if not bd or score < bd then best, bd, inside = s, score, d <= r end
      end
    end
  end
  if not best then return nil end
  return { name = best[1], kind = best[2], dist = hav(lat, lon, best[3], best[4]), inside = inside }
end

-- (2026-11-11) the country route ("eine Landroute will ich fahren anstatt eine Autobahnroute"): BeamNG.Earth's router has no "avoid motorways",
-- so the way goes from village to village: about every `step` metres along the line from start to destination the nearest small town or
-- village within 6 km (no cities: their centres are slow), each one further along than the one before. A router asked for 10-15 km between
-- two villages takes the country road. Returns { {name, lat, lon} ... } in order.
function M.townsAlong(lat0, lon0, lat1, lon1, step)
  local D = hav(lat0, lon0, lat1, lon1)
  local n = math.floor(D / (step or 12000))
  if n < 1 then return {} end
  local kx, ky = 111320 * math.cos(math.rad(lat0)), 111320
  local ex, ey = (lon1 - lon0) * kx, (lat1 - lat0) * ky
  local L2 = ex * ex + ey * ey
  local out, lastF = {}, 0.0
  for k = 1, n do
    local f = k / (n + 1)
    local tla, tlo = lat0 + (lat1 - lat0) * f, lon0 + (lon1 - lon0) * f
    local best, bs
    -- (first a village or small town within 6 km; where there is none - the Ruhr is all cities - a district or a bigger town within 10 km)
    for pass = 1, 2 do
      local R = pass == 1 and 6000 or 10000
      for la = math.floor(tla - 0.1), math.floor(tla + 0.1) do
        for lo = math.floor(tlo - 0.16), math.floor(tlo + 0.16) do
          for _, s in ipairs(townTile(la, lo) or {}) do
            local pop, kind = s[5], s[2]
            local okKind = pass == 1 and (kind ~= 'city' and kind ~= 'suburb' and kind ~= 'quarter' and (not pop or (pop >= 150 and pop < 40000)))
              or (pass == 2 and kind ~= 'city' and (not pop or pop < 150000))
            if okKind and math.abs(s[3] - tla) < 0.1 and math.abs(s[4] - tlo) < 0.16 then
              local d = hav(tla, tlo, s[3], s[4])
              local px, py = (s[4] - lon0) * kx, (s[3] - lat0) * ky
              local fs = (px * ex + py * ey) / L2
              if d < R and fs > lastF + 0.03 and fs < 0.97 then
                local sc = d + ((pop and pop < 400) and 1200 or 0)
                if not bs or sc < bs then best, bs = { name = s[1], lat = s[3], lon = s[4], f = fs }, sc end
              end
            end
          end
        end
      end
      if best then break end
    end
    if best then out[#out + 1] = best; lastF = best.f end
  end
  return out
end

-- (2026-11-11) a village between minM and maxM from a point (the story's barn): small places only, one at random
function M.villageNear(lat, lon, minM, maxM)
  local dLa = maxM / 111320
  local dLo = maxM / (111320 * math.max(0.2, math.cos(math.rad(lat))))
  local list = {}
  for la = math.floor(lat - dLa), math.floor(lat + dLa) do
    for lo = math.floor(lon - dLo), math.floor(lon + dLo) do
      for _, s in ipairs(townTile(la, lo) or {}) do
        local pop = s[5]
        if (s[2] == 'village' or s[2] == 'hamlet' or (pop and pop >= 80 and pop <= 3000)) and s[2] ~= 'suburb' and s[2] ~= 'quarter' and s[2] ~= 'city' then
          local d = hav(lat, lon, s[3], s[4])
          if d >= minM and d <= maxM then list[#list + 1] = { name = s[1], lat = s[3], lon = s[4] } end
        end
      end
    end
  end
  if #list == 0 then return nil end
  return list[math.random(#list)]
end

-- (2026-11-10) the built-up core of a town: only where the houses stand close ("genau da, wo viele Häuser sind"), not the whole area
-- placeAt counts as the town - its edge, the fields and the industrial estates round it are fine for a yard. The core's radius by size;
-- a village has none. Returns the town's name and how far from its centre, or nil.
function M.coreRadius(kind, pop)
  if pop then
    return pop >= 500000 and 3500 or pop >= 100000 and 1800 or pop >= 30000 and 900 or pop >= 10000 and 550 or pop >= 3000 and 300 or 0
  end
  return ({ city = 2000, town = 500, suburb = 350, quarter = 300 })[kind] or 0
end
function M.coreAt(lat, lon)
  if not lat or not lon then return nil end
  local lists = {}
  for la = math.floor(lat - 0.05), math.floor(lat + 0.05) do
    for lo = math.floor(lon - 0.08), math.floor(lon + 0.08) do
      local t = townTile(la, lo)
      if t then lists[#lists + 1] = t end
    end
  end
  if #lists == 0 and settlements then lists[1] = settlements end
  for _, list in ipairs(lists) do
    for _, s in ipairs(list) do
      if math.abs(s[3] - lat) < 0.05 and math.abs(s[4] - lon) < 0.08 then
        local r = M.coreRadius(s[2], s[5])
        if r > 0 then
          local d = hav(lat, lon, s[3], s[4])
          if d <= r then return s[1], d, s[2] end
        end
      end
    end
  end
  return nil
end

return M
