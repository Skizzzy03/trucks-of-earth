-- Trucks of Earth: rest areas and car parks as places of their own (2026-11-10, "ich finde nie was zum Schlafen").
-- Two sources: the rest areas shipped with the mod (/fernfahrer/places/<lat>_<lon>.json, type "rest", from OpenStreetMap: rest areas,
-- services, lorry car parks) - read straight from the tiles, not through the company network (that keeps only a few per region) -
-- and the car parks BeamNG.Earth builds as one drives (parked.lua: the stalls of its road tiles, remembered between sessions).
-- A car park beside a motorway counts as a rest area. A car park within MATCH_M of a shipped rest area is that rest area's car park:
-- its ring goes onto one of its stalls.
-- M.around(lat, lon, m) -> list of places { id, name, kind ('rest' | 'parking'), lat, lon, d, ringLat, ringLon, ringHdg, n }
-- M.nearest(lat, lon, maxM, kind), M.get(id), M.init(parked).

local M = {}
M.MATCH_M = 220
M.DIR = '/fernfahrer/places/'

local parked
local tiles = {}

function M.init(p) parked = p end

local function dist(lat1, lon1, lat2, lon2)
  local kx = 111320 * math.cos(math.rad(lat1))
  return math.sqrt(((lon2 - lon1) * kx) ^ 2 + ((lat2 - lat1) * 111320) ^ 2)
end
M.dist = dist

local function tile(la, lo)
  local key = la .. '_' .. lo
  local t = tiles[key]
  if t then return t end
  t = {}
  local ok, d = pcall(jsonReadFile, string.format('%s%d_%d.json', M.DIR, la, lo))
  for _, p in ipairs(ok and type(d) == 'table' and d.places or {}) do
    local lat, lon = tonumber(p[3]), tonumber(p[4])
    if p[1] == 'rest' and lat and lon then
      local name = (type(p[2]) == 'string' and p[2] ~= '') and p[2] or 'Rastplatz'
      t[#t + 1] = { id = string.format('rest:%.5f:%.5f', lat, lon), name = name, kind = 'rest', lat = lat, lon = lon, detail = p[5] ~= '' and p[5] or nil }
    end
  end
  tiles[key] = t
  return t
end

local function shippedAround(lat, lon, m)
  local out = {}
  local dLa = m / 111320
  local dLo = m / (111320 * math.max(0.2, math.cos(math.rad(lat))))
  for la = math.floor(lat - dLa), math.floor(lat + dLa) do
    for lo = math.floor(lon - dLo), math.floor(lon + dLo) do
      for _, r in ipairs(tile(la, lo)) do
        if math.abs(r.lat - lat) < dLa and math.abs(r.lon - lon) < dLo then
          local d = dist(lat, lon, r.lat, r.lon)
          if d <= m then out[#out + 1] = { r = r, d = d } end
        end
      end
    end
  end
  return out
end

-- the places around, nearest first. opts.classify: car parks this near (m) are asked whether they are beside a motorway (a few per call)
function M.around(lat, lon, m, opts)
  local out = {}
  local rest = shippedAround(lat, lon, m + M.MATCH_M)
  local lotList = parked and parked.lotsAround and parked.lotsAround(lat, lon, m + M.MATCH_M) or {}
  local asked = 0
  local cl = opts and opts.classify or 0
  for _, l in ipairs(lotList) do
    if l.hw == nil and l.d < cl and asked < 3 and parked.classify then asked = asked + 1; l.hw = parked.classify(l.cell) end
  end
  -- (the car parks in cells of about 220 m: a rest area looks only at the ones round it - thousands of each on the office's map)
  local grid = {}
  local GLA, GLO = 0.002, 0.0032
  for i, l in ipairs(lotList) do
    local k = math.floor(l.lat / GLA) .. ':' .. math.floor(l.lon / GLO)
    grid[k] = grid[k] or {}
    table.insert(grid[k], i)
  end
  local used = {}
  for _, x in ipairs(rest) do
    local r = x.r
    -- (its car park: of the ones the world has there, the one nearest to the driver - a motorway rest area has one on each side)
    local best, bd
    local cx, cy = math.floor(r.lat / GLA), math.floor(r.lon / GLO)
    for gx = cx - 1, cx + 1 do
      for gy = cy - 1, cy + 1 do
        for _, i in ipairs(grid[gx .. ':' .. gy] or {}) do
          local l = lotList[i]
          if dist(r.lat, r.lon, l.lat, l.lon) < M.MATCH_M and (not bd or l.d < bd) then best, bd = i, l.d end
        end
      end
    end
    local p = { id = r.id, name = r.name, kind = 'rest', lat = r.lat, lon = r.lon, d = x.d, detail = r.detail }
    if best then
      local l = lotList[best]
      used[best] = true
      p.ringLat, p.ringLon, p.ringHdg, p.n = l.sla, l.slo, l.sh, l.n
    end
    if x.d <= m then out[#out + 1] = p end
  end
  for i, l in ipairs(lotList) do
    if not used[i] and l.d <= m then
      out[#out + 1] = { id = l.id, name = l.hw and 'Rastplatz' or 'Parkplatz', kind = l.hw and 'rest' or 'parking', lot = true, lat = l.lat, lon = l.lon, d = l.d,
        ringLat = l.sla, ringLon = l.slo, ringHdg = l.sh, n = l.n }
    end
  end
  table.sort(out, function(a, b) return a.d < b.d end)
  return out
end

-- the nearest one (kind 'rest', 'parking' or nil: either), within maxM
function M.nearest(lat, lon, maxM, kind)
  for _, m in ipairs({ 3000, 12000, maxM or 40000 }) do
    if m <= (maxM or 40000) then
      for _, p in ipairs(M.around(lat, lon, m)) do
        if not kind or p.kind == kind then return p end
      end
    end
  end
  return nil
end

-- a place by its id (for the route: the map's markers carry it)
function M.get(id)
  id = tostring(id or '')
  local la, lo = id:match('^rest:([%d%.%-]+):([%d%.%-]+)$')
  if la then
    la, lo = tonumber(la), tonumber(lo)
    for _, r in ipairs(tile(math.floor(la), math.floor(lo))) do
      if math.abs(r.lat - la) < 1e-5 and math.abs(r.lon - lo) < 1e-5 then return r end
    end
    return { id = id, name = 'Rastplatz', kind = 'rest', lat = la, lon = lo }
  end
  if id:sub(1, 4) == 'lot:' and parked and parked.lotById then
    local l = parked.lotById(id)
    if l then return { id = l.id, name = l.hw and 'Rastplatz' or 'Parkplatz', kind = l.hw and 'rest' or 'parking', lot = true, lat = l.lat, lon = l.lon, ringLat = l.sla, ringLon = l.slo, ringHdg = l.sh, n = l.n } end
  end
  return nil
end

function M.reset() tiles = {} end

return M
