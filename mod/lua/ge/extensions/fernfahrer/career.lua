-- Trucks of Earth: a compact truck-style career mode on BeamNG.Earth.
-- Started from the main menu (More > Trucks of Earth, ui/ui-vue/mods/fernfahrer/index.js): loads the Earth level;
-- the setup screen picks the home yard on the map and names the company; real places around the home (Earth geocoder,
-- OpenStreetMap) become freight depots and facilities (fuel, workshops, truck and car dealers, viewpoints); the freight
-- market offers loads between depots; the Earth GPS routes the drives; dealers and workshops work on site only.
-- UI: Vue routes fernfahrerSetup / fernfahrerOffice (pull: uiState / uiCatalog), HUD apps ui/modules/apps/Fernfahrer*
-- (push: guihooks 'FernfahrerHud'), the HUD profile settings/ui_apps/originalLayouts/default/fernfahrer.uilayout.json.
-- Extension points: registerCargo / registerDepotType / registerStory, and the hooks onFernfahrerJobAccepted(job),
-- onFernfahrerJobCompleted(report), onFernfahrerVehicleBought(vehicle), onFernfahrerDiscovery(place) for add-ons.

local M = {}
local L = {}            -- (helpers: the main chunk stays under LuaJIT's 200 locals)
local logTag = 'fernfahrer'

local cargoData = require('fernfahrer/cargo')
local storyData = require('fernfahrer/story')
local citiesData = require('fernfahrer/cities')
local roadEvents = require('fernfahrer/events')
local spots = require('fernfahrer/spots')
local tacho = require('fernfahrer/tacho')
local travel = require('fernfahrer/travel')
local accidents = require('fernfahrer/accidents')
local trafficAI = require('fernfahrer/trafficai')
local priority = require('fernfahrer/priority')
local pool = require('fernfahrer/pool')
local streets = require('fernfahrer/streets')
local parked = require('fernfahrer/parked')
local vices = require('fernfahrer/vices')
local yard = require('fernfahrer/yard')
local stops = require('fernfahrer/stops')
local service = require('fernfahrer/service')
local cinematic = require('fernfahrer/cinematic')
table.insert(yard.shiftHooks, function(xf) stops.transform(xf); pcall(function() require('fernfahrer/accidents').transform(xf) end) end)
local PARKED = { off = 0, low = 6, auto = 10, high = 16 }

local LEGACY_SAVE = '/settings/fernfahrer/career.json'      -- the single save before career slots
local SLOT_DIR = '/settings/fernfahrer/careers/'           -- one file per career: <slot>.json
local TRUCKS_FILE = '/settings/fernfahrer/trucks.json'   -- optional: { "extra": [ {model, config, name, price} ] }
local AGENT_GROUP = '/vehicleGroups/agentTraffic/agent_traffic_eu.vehGroup.json'   -- agent_traffic_mod's EU cars
local EARTH_LEVEL = 'beamng_earth'
local APP_LAYOUT = 'fernfahrer'

local C = {
  SAVE_VERSION = 2,
  NET_VERSION = 8,          -- (5: rest areas; 6: the denser generated network, 2026-11-05; 7: fuel depots, chemical parks, steel works; 8: scrap yards, car dealers)          -- the place types searched; older networks get the new types added (3: no made-up places)
  START_MONEY = 5000,
  COMPANY_SHARE = 0.45,     -- share of the freight on a quick job (loaned truck)
  COST_PER_KM = 0.35,       -- own truck: toll and wear per km (diesel is bought at the pump)
  BASE_PAY = 600,
  PAY_PER_KM = 55,
  HOME_RADIUS_KM = 35,
  PICKUP_MAX_KM = 25,
  MIN_TRIP_KM = 3,
  ARRIVE_PICKUP_M = 120,
  ARRIVE_DELIVERY_M = 80,
  HOME_RADIUS_M = 250,      -- "at the yard"
  HUB_RADIUS_M = 150,       -- "at a logistics base" (free vehicle change)
  TRAILER_NEAR_M = 45,
  UNLOAD_S = 12,
  HITCH_TIMEOUT_S = 6,
  CARGO_DMG_FULL = 80000,
  FRAGILE_FACTOR = 1.6,
  CARGO_DMG_MAX_PENALTY = 0.6,
  REPAIR_PER_DMG = 0.5,
  LOANER_DMG_PER_DMG = 0.15,
  TRUCK_DMG_FULL = 60000,   -- for the HUD's damage %
  LATE_PENALTY = 0.2,
  LOAN_RATE = 0.08,
  LOAN_AUTO = 0.2,
  TRANSFER_BASE = 150,      -- a vehicle brought to you away from the yard / bases
  TRANSFER_PER_KM = 1.5,
  OFFERS = 12,
  OFFER_TTL_MIN = { 20, 45 },
  DEPOTS_PER_TYPE = 12,     -- per region
  REGION_KM = 30,
  DEDUP_M = 150,
  GEOCODE_GAP_S = 1.3,      -- between geocoder requests (a free public service: one at a time)
  GEOCODE_PAUSE_S = 90,     -- when it reports overload
  LONG_SHARE = 0.35,        -- share of long-haul offers
  LONG_MIN_KM = 80,
  LONG_MAX_KM = 600,
  LONG_KMH = 65,            -- average speed the long-haul deadlines assume
  LOW_FUEL = 0.12,
  DISCOVER_XP = 300,
  DISCOVER_MONEY = 150,
  ID_BASE = 7300000,
  HUD_S = 0.25,
  LIMIT_S = 0.5,
  NEAR_S = 0.5,
  FUEL_S = 2.5,
  MARKET_S = 30,
  SAVE_S = 30,
  BOOT_WAIT_S = 3,
  TRAFFIC_DELAY_S = 15,
  FPS_WINDOW_S = 15,
}

-- price per unit and MJ per unit (the stock career's factors, career/modules/fuel.lua)
local FUEL = {
  diesel = { price = 1.75, mj = 36.112, unit = 'L', name = 'Diesel' },
  gasoline = { price = 1.85, mj = 31.125, unit = 'L', name = 'Benzin' },
  electricEnergy = { price = 0.49, mj = 3.6, unit = 'kWh', name = 'Strom' },
}

local DEPOT_TYPES, DEPOT_BY_KEY = {}, {}
local CARGO, CARGO_BY_KEY = {}, {}
local STORY = {}

local FALLBACK_NAMES = { 'Hansen', 'Kraus', 'Weber', 'Nord-Agrar', 'Bergmann', 'Fischer', 'Lindner', 'Vogt', 'Brandt',
  'Seidel', 'Köhler', 'Rhein-Lager', 'Albrecht', 'Hoffmann', 'Schuster', 'Wagner' }

local S             -- saved career state
local R = {         -- runtime state
  mode = false, modeRequested = false, boot = nil, truckId = nil, trailerId = nil, offers = {}, tasks = {},
  reqId = 0, hudT = 0, limitT = 0, nearT = 0, fuelT = 0, marketT = 0, saveT = 0,
  trucks = nil, cars = nil, catalogTask = nil, unloadT = 0, hitchT = 0,
  pendingAdopt = nil, pendingTeleport = nil, report = nil, discover = nil, limit = nil, officeOpen = false,
  near = nil, fuel = nil, odo = 0, traffic = nil, fps = { t = 0, n = 0 },
}

------------------------------------------------------------------------------------------
-- registries (extension points)

function M.registerDepotType(d)
  if type(d) ~= 'table' or not d.key then return end
  if DEPOT_BY_KEY[d.key] then
    for i, x in ipairs(DEPOT_TYPES) do if x.key == d.key then DEPOT_TYPES[i] = d end end
  else
    table.insert(DEPOT_TYPES, d)
  end
  DEPOT_BY_KEY[d.key] = d
end

function M.registerCargo(c)
  if type(c) ~= 'table' or not c.key or not c.trailers then return end
  if CARGO_BY_KEY[c.key] then
    for i, x in ipairs(CARGO) do if x.key == c.key then CARGO[i] = c end end
  else
    table.insert(CARGO, c)
  end
  CARGO_BY_KEY[c.key] = c
end

function M.registerStory(key, text) STORY[key] = text end

for _, d in ipairs(cargoData.DEPOT_TYPES) do M.registerDepotType(d) end
for _, c in ipairs(cargoData.CARGO) do M.registerCargo(c) end
for k, t in pairs(storyData.TEXT) do STORY[k] = t end

------------------------------------------------------------------------------------------
-- helpers

local function clamp(x, a, b) return math.max(a, math.min(b, x)) end
local function round(x, step) step = step or 1; return math.floor(x / step + 0.5) * step end
local function now() return os.clock() end

local function haversine(lat1, lon1, lat2, lon2)
  local p1, p2 = math.rad(lat1), math.rad(lat2)
  local dp, dl = p2 - p1, math.rad(lon2 - lon1)
  local a = math.sin(dp / 2) ^ 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ^ 2
  return 2 * 6371000 * math.asin(math.min(1, math.sqrt(a)))
end

function L.destPoint(lat, lon, bearingDeg, distM)
  local d, b = distM / 6371000, math.rad(bearingDeg)
  local p1, l1 = math.rad(lat), math.rad(lon)
  local p2 = math.asin(math.sin(p1) * math.cos(d) + math.cos(p1) * math.sin(d) * math.cos(b))
  local l2 = l1 + math.atan2(math.sin(b) * math.sin(d) * math.cos(p1), math.cos(d) - math.sin(p1) * math.sin(p2))
  return math.deg(p2), (math.deg(l2) + 540) % 360 - 180
end

local function dist(a, b)
  if not a or not b or not a.lat or not b.lat then return nil end
  return haversine(a.lat, a.lon, b.lat, b.lon)
end

local function levelId() return getCurrentLevelIdentifier and getCurrentLevelIdentifier() or nil end
local function earthCore() return rawget(_G, 'beamngEarth_core') end
local function inEarth() return levelId() == EARTH_LEVEL and earthCore() ~= nil end

local function earthModule(name)
  local ok, m = pcall(require, 'beamngEarth/' .. name)
  return ok and type(m) == 'table' and m or nil
end

local function here()
  local c = earthCore()
  local st = c and c._state and c._state() or nil
  local pl = st and st.player
  if pl and pl.lat and pl.lon then return { lat = pl.lat, lon = pl.lon } end
end

local function playerVeh() return getPlayerVehicle(0) end
local function vehById(id) return id and getObjectByID(id) or nil end
local function vehPos(v) return v and vec3(v:getPosition()) or nil end
local function vehSpeed(v) return v and vec3(v:getVelocity()):length() or 0 end

local function inEurope()
  local p = here() or (S and S.home)
  return p and p.lat > 34 and p.lat < 72 and p.lon > -25 and p.lon < 45 or false
end

local function normPath(p)
  if type(p) ~= 'string' then return nil end
  return (p:gsub('\\', '/'):gsub('^/', '')):lower()
end

local function configOf(id)
  local vd = core_vehicle_manager and core_vehicle_manager.getVehicleData(id)
  return vd and vd.config and normPath(vd.config.partConfigFilename) or nil
end

local function fill(text, vars)
  return (tostring(text):gsub('{(%w+)}', function(k) return vars[k] ~= nil and tostring(vars[k]) or '' end))
end

local function message(text, from)
  from = from or storyData.FROM
  table.insert(S.log, 1, { t = os.time(), from = from, text = text })
  while #S.log > 60 do table.remove(S.log) end
  R.toast = { from = from, text = text, until_ = now() + 14, id = (R.toast and R.toast.id or 0) + 1 }
end

function M.story(key, vars)
  if not S or S.story[key] or not STORY[key] then return end
  S.story[key] = true
  local v = { company = S.company and S.company.name or 'deiner Firma', driver = S.company and S.company.driver or 'Chef' }
  for k, x in pairs(vars or {}) do v[k] = x end
  message(fill(STORY[key], v))
end
local story = M.story

local function notify(text, ttl)
  if ui_message then ui_message(text, ttl or 6, 'fernfahrer', 'local_shipping') end
end

local function money(v)
  local s = tostring(math.floor(math.abs(v) + 0.5)):reverse():gsub('(%d%d%d)', '%1.'):reverse():gsub('^%.', '')
  return (v < 0 and '−' or '') .. s .. ' €'
end

local function navigate(route)
  local r = rawget(_G, 'ui_router')
  if r and r.navigate and pcall(r.navigate, route) then return true end
  if guihooks then guihooks.trigger('ChangeState', { state = route }) end
end

-- coroutine tasks (geocoding and catalogs run over many frames)
local function waitFor(fn, timeout)
  local t0 = now()
  while true do
    local r = fn()
    if r then return r end
    if now() - t0 > timeout then return nil end
    coroutine.yield()
  end
end

local function runTask(fn) table.insert(R.tasks, coroutine.create(fn)) end

function L.tickTasks()
  for i = #R.tasks, 1, -1 do
    local co = R.tasks[i]
    local ok, err = coroutine.resume(co)
    if not ok then log('E', logTag, 'task failed: ' .. tostring(err)) end
    if coroutine.status(co) == 'dead' then table.remove(R.tasks, i) end
  end
end

------------------------------------------------------------------------------------------
-- save / load

local function defaults()
  return {
    version = C.SAVE_VERSION, netVersion = C.NET_VERSION, company = nil, home = nil, depots = {}, discovered = {},
    money = C.START_MONEY, xp = 0, level = 1, loan = 0,
    owned = {}, active = 'loaner',
    stats = { jobs = 0, km = 0, earned = 0, late = 0, damaged = 0, fuelL = 0, fuelCost = 0, discoveries = 0, fines = 0 },
    story = {}, log = {}, job = nil, fines = {}, tacho = tacho.new(),
    settings = { hitch = 'auto', speedWarn = true, traffic = 'auto', events = true, dayNight = true,
      radioOn = false },                          -- (a new career starts quiet: no music behind the loading and the setup)
    clockHours = 7.5,
  }
end

local function slotPath(slot) return SLOT_DIR .. slot .. '.json' end

-- The game clock: BeamNG.Earth's sky runs on a clock of ours (its BeamMP server clock: { hours, speed }) at the
-- tachograph's pace, so day and night pass as in the classic truck simulators; the sun, moon and stars stay right for the
-- place. Saved with the career (S.clockHours); sleeping moves it on.
local function earthSky()
  local ok, m = pcall(require, 'beamngEarth/sky')
  return ok and type(m) == 'table' and m.setServerClock and m or nil
end

-- The career's clock is S.clockHours, moved on with the game's own time (dtSim x SCALE: it stands while the game is
-- paused, like the tachograph and the deadlines – the sky's clock alone ran on the computer's time, so a few minutes
-- in the office or the pause menu cost half an hour of daylight). The sky is set to it every few seconds and
-- whenever the pause starts or ends (speed 0 while paused).
local function clockHours()
  if S and R.mode and S.settings.dayNight ~= false then return (S.clockHours or 8) % 24 end
  local sky = earthSky()
  local c = sky and sky.serverClock and sky.serverClock()
  if c and sky.serverHours then return sky.serverHours(c, os.time()) end
  return S and S.clockHours or 8
end

local function pushClock(paused)
  local sky = earthSky()
  if not sky or not S or S.settings.dayNight == false then return end
  if sky.getMode and sky.getMode() ~= 'real' then pcall(sky.setMode, 'real') end
  pcall(sky.setServerClock, { hours = (S.clockHours or 8) % 24, speed = paused and 0 or tacho.SCALE, epoch = os.time() })
end

local function startClock(hours)
  if S and hours then S.clockHours = hours % 24 end
  pushClock(false)
end

-- every frame: the clock on by the game time that passed
local function tickClock(dtSim)
  if not S or not R.mode or S.settings.dayNight == false then return end
  local paused = not dtSim or dtSim <= 0
  if not paused then
    local h = (S.clockHours or 8) + dtSim * tacho.SCALE / 3600
    if h >= 24 then S.dayNo = (S.dayNo or 1) + 1 end      -- (midnight: a new weekday)
    S.clockHours = h % 24
  end
  local t = now()
  -- (a check line once a minute: the clock stood still in one drive, 2026-11-03, and the log showed nothing)
  R.clockSimSum = (R.clockSimSum or 0) + (dtSim or 0)
  if t - (R.clockLogT or 0) > 60 then
    log('I', logTag, string.format('clock %02d:%02d, %.0f s of game time in the last %.0f s', math.floor(S.clockHours) % 24,
      math.floor((S.clockHours % 1) * 60), R.clockSimSum * tacho.SCALE, t - (R.clockLogT or t)))
    R.clockLogT, R.clockSimSum = t, 0
  end
  if paused ~= R.clockPaused or t - (R.clockPushT or 0) > 5 then
    R.clockPaused, R.clockPushT = paused, t
    pushClock(paused)
  end
end

local function stopClock()
  local sky = earthSky()
  if sky then pcall(sky.setServerClock, nil) end
end

local function clockText()
  local h = clockHours()
  return string.format('%02d:%02d', math.floor(h) % 24, math.floor((h % 1) * 60))
end

-- Saved compact (every 30 s: no need to make it pretty); every 10th save also as a backup copy, which load() falls
-- back on when the slot itself cannot be read (the game stopped in the middle of writing it).
local remember
local function save()
  if S and R.slot then
    S.lastPlayed = os.time()
    if remember then pcall(remember) end
    jsonWriteFile(slotPath(R.slot), S, false)
    R.saves = (R.saves or 0) + 1
    if R.saves % 10 == 1 then jsonWriteFile(slotPath(R.slot) .. '.bak', S, false) end
  end
end

local function load(slot)
  R.slot = slot
  local d = jsonReadFile(slotPath(slot))
  if type(d) ~= 'table' and FS:fileExists(slotPath(slot) .. '.bak') then
    d = jsonReadFile(slotPath(slot) .. '.bak')
    if type(d) == 'table' then log('W', logTag, 'career ' .. slot .. ': the save was unreadable, the backup copy is used') end
  end
  S = defaults()
  if type(d) == 'table' and (d.version or 1) >= C.SAVE_VERSION then
    local def = defaults()
    for k, v in pairs(d) do S[k] = v end
    S.netVersion = d.netVersion or 1
    for k, v in pairs(def.stats) do if S.stats[k] == nil then S.stats[k] = v end end
    for k, v in pairs(def.settings) do if S.settings[k] == nil then S.settings[k] = v end end
    S.story, S.log, S.owned, S.depots = S.story or {}, S.log or {}, S.owned or {}, S.depots or {}
    pcall(L.neutralizeSave)
    S.discovered = S.discovered or {}
    S.fines = S.fines or {}
    S.tacho = type(S.tacho) == 'table' and S.tacho or tacho.new()
    for _, o in ipairs(S.owned) do o.kind = o.kind or 'truck' end
  end
end

------------------------------------------------------------------------------------------
-- the books (the office's Finanzen): every change of the account with its category, the game day and the balance
-- after it – the graphs and the list of bookings come from here. pay(cat, amount, label) changes the money and books.
L.LEDGER_MAX = 500
function L.pay(cat, amount, label)
  amount = math.floor((tonumber(amount) or 0) * 100 + 0.5) / 100     -- (to the cent: the diesel)
  if amount == 0 or not S then return end
  S.money = S.money + amount
  S.ledger = S.ledger or {}
  table.insert(S.ledger, { d = S.dayNo or 1, h = math.floor((S.clockHours or 0) * 10) / 10, c = cat, a = amount, l = label, b = S.money })
  while #S.ledger > L.LEDGER_MAX do table.remove(S.ledger, 1) end
end

------------------------------------------------------------------------------------------
-- xp (kept simple; a skill system can hook in here later)

local function xpFor(level) return math.floor(800 * (level - 1) ^ 1.45) end

local function addXp(n)
  S.xp = S.xp + n
  while S.xp >= xpFor(S.level + 1) do
    S.level = S.level + 1
    notify('Level ' .. S.level .. ' erreicht!', 8)
  end
end

local function loanLimit() return 50000 + S.level * 15000 end

------------------------------------------------------------------------------------------
-- the speed limit under the player: BeamNG.Earth's road graph (OSM maxspeed; navgraph.currentGraph, edge[6] in
-- m/s), else the game's own map graph

local LIMIT_CELL = 60
local limitGrid = { key = nil }

function L.buildLimitGrid(g)
  local cells, maxV = {}, 0
  for _, e in ipairs(g.edges) do
    local a, b, v = g.nodes[e[1]], g.nodes[e[2]], tonumber(e[6])
    if a and b and v and v > 0 then
      if v > maxV then maxV = v end
      local x0, x1 = math.floor(math.min(a[1], b[1]) / LIMIT_CELL), math.floor(math.max(a[1], b[1]) / LIMIT_CELL)
      local y0, y1 = math.floor(math.min(a[2], b[2]) / LIMIT_CELL), math.floor(math.max(a[2], b[2]) / LIMIT_CELL)
      if (x1 - x0 + 1) * (y1 - y0 + 1) <= 100 then
        local seg = { a[1], a[2], b[1], b[2], v, (a[3] + b[3]) / 2 }
        for cx = x0, x1 do
          for cy = y0, y1 do
            local k = cx .. ',' .. cy
            local list = cells[k]
            if not list then list = {}; cells[k] = list end
            list[#list + 1] = seg
          end
        end
      end
    end
  end
  return cells, maxV > 60      -- (a graph in km/h, should a server send that)
end

local function segDist2(px, py, x0, y0, x1, y1)
  local dx, dy = x1 - x0, y1 - y0
  local l2 = dx * dx + dy * dy
  local t = l2 > 0 and clamp(((px - x0) * dx + (py - y0) * dy) / l2, 0, 1) or 0
  local qx, qy = x0 + t * dx - px, y0 + t * dy - py
  return qx * qx + qy * qy
end

local function earthLimitAt(pos)
  local ng = earthModule('navgraph')
  local g = ng and ng.currentGraph and ng.currentGraph()
  if not g or type(g.edges) ~= 'table' or type(g.nodes) ~= 'table' then return nil end
  local key = tostring(g.nodes) .. tostring(g.edges)
  if limitGrid.key ~= key then
    limitGrid.key = key
    limitGrid.cells, limitGrid.kmh = L.buildLimitGrid(g)
  end
  local cx, cy = math.floor(pos.x / LIMIT_CELL), math.floor(pos.y / LIMIT_CELL)
  local best, bd = nil, 15 * 15
  for ix = cx - 1, cx + 1 do
    for iy = cy - 1, cy + 1 do
      for _, s in ipairs(limitGrid.cells[ix .. ',' .. iy] or {}) do
        if math.abs(s[6] - pos.z) < 8 then
          local d = segDist2(pos.x, pos.y, s[1], s[2], s[3], s[4])
          if d < bd then best, bd = s, d end
        end
      end
    end
  end
  if not best then return nil end
  return limitGrid.kmh and best[5] or best[5] * 3.6
end

local function stockLimitAt(pos)
  if not map or not map.findClosestRoad or not map.getMap then return nil end
  local ok, n1, n2, d = pcall(map.findClosestRoad, pos)
  if not ok or not n1 or not n2 or (d and d > 15) then return nil end
  local nodes = map.getMap().nodes
  local l = nodes and nodes[n1] and nodes[n1].links and nodes[n1].links[n2]
  local v = l and tonumber(l.speedLimit)
  if not v or v <= 0 then return nil end
  return v > 60 and v or v * 3.6
end

local function speedLimitAt(pos)
  if not pos then return nil end
  local kmh = earthLimitAt(pos) or stockLimitAt(pos)
  if not kmh then return nil end
  return round(kmh, 5)
end

-- the truck's own limits (2026-11-05, German rules for trucks over 7.5 t; Einstellungen → LKW-Regeln): on a road posted
-- 110 or more (a motorway – the sign is for cars) 80, on roads posted over 50 up to 100 (country roads, expressways)
-- 60, in towns the sign. The map has no road classes, so the posted limit tells the kind of road.
L.TRUCK_MOTORWAY, L.TRUCK_RURAL, L.LIMITER_KMH = 80, 60, 90
function L.ruleLimit(lim)
  if not lim or not S or S.settings.truckRules == false or not L.activeKind or L.activeKind() ~= 'truck' then return lim end
  if lim >= 110 then return L.TRUCK_MOTORWAY end
  if lim > 50 then return math.min(lim, L.TRUCK_RURAL) end
  return lim
end
-- the limiter taken out in a workshop (2026-11-05): only in a truck of one's own; at a police check it may be found –
-- the cheap chip more often than the professional job. Found: a fine, and it goes back in (at the owner's cost).
L.LIMITER_MOD = {
  cheap = { price = 650, detect = 0.55, fine = 1500, name = 'Billig-Chip', sub = 'Günstig, aber auffällig – bei Kontrollen oft entdeckt' },
  pro = { price = 2900, detect = 0.12, fine = 1500, name = 'Profi-Umbau', sub = 'Teuer, sauber versteckt – wird nur selten entdeckt' },
}
L.LIMITER_REFIT = 350
-- the tank (2026-11-07: "den Tank halbieren" – the real world's tours are mostly regional; a bigger one in the
-- workshop): the share of the stock tank's volume
L.TANK_SMALL, L.TANK_BIG_PRICE = 0.5, 2400
function L.tankFactor()
  local o = L.ownTruck and L.ownTruck()
  return (o and o.tankBig) and 1 or L.TANK_SMALL
end
function L.ownTruck()
  if not S or S.active == 'loaner' or S.active == 'rental' then return nil end
  local o = S.owned and S.owned[S.active]
  return o and (o.kind or 'truck') == 'truck' and o or nil
end
function L.limiterOff() local o = L.ownTruck(); return o and o.limiterOff or nil end
-- the fines for driving too fast (the German catalogue for trucks, outside towns; in towns a little more)
function L.speedFine(over, inTown)
  local f = over <= 10 and 30 or over <= 15 and 70 or over <= 20 and 120 or over <= 25 and 175 or over <= 30 and 255 or over <= 40 and 400 or 560
  return inTown and math.floor(f * 1.25 / 5 + 0.5) * 5 or f
end
-- every half second: well over the limit for a while → a fine (at most one in 3 minutes); the limiter in the truck
function L.speedRulesTick(t, v)
  local truck = L.activeKind and L.activeKind() == 'truck' and R.truckId and v and v:getID() == R.truckId
  -- the limiter: 90 km/h in the truck with the truck's rules on – unless a workshop took it out (L.LIMITER_MOD)
  local want = truck and S.settings.truckRules ~= false and not L.limiterOff() and L.LIMITER_KMH or nil
  -- (2026-11-07: the truck's own limiter too – the European tractors have one in their ECU part (the Percheron's
  -- percheron_engine_ecu_speedlimit_90, 90 km/h in the vehicle controller); taken out in the workshop, or the truck's
  -- rules off, it stayed. Lifted now in the vehicle controller, as the part "Speed Limiter Delete" would.)
  local stockOff = (truck and (S.settings.truckRules == false or L.limiterOff())) and true or false
  -- (2026-11-07: the tank half the stock size in the career's trucks; the workshop's big tank: the stock size)
  local tank = truck and L.tankFactor() or nil
  if v and (R.limiterFor ~= v:getID() or R.limiterKmh ~= want or R.limiterStockOff ~= stockOff or R.limiterTank ~= tank) then
    R.limiterFor, R.limiterKmh, R.limiterStockOff, R.limiterTank = v:getID(), want, stockOff, tank
    v:queueLuaCommand(string.format('extensions.load("fernfahrer_limiter") if fernfahrer_limiter then fernfahrer_limiter.set(%s, %s) ' ..
      'if fernfahrer_limiter.setTank then fernfahrer_limiter.setTank(%s) end end',
      want and tostring(want) or 'nil', tostring(stockOff), tank and tostring(tank) or 'nil'))
  end
  -- (2026-11-05: no fines out of nowhere – too fast costs only where a speed camera really stands at the road,
  -- events.lua radar, against the truck's limit)
end

------------------------------------------------------------------------------------------
-- catalogs: every installed fifth-wheel tractor (trucks) and road car (cars), vanilla and mods

local EU_COUNTRIES = { germany = 1, italy = 1, france = 1, sweden = 1, netherlands = 1, ['united kingdom'] = 1, spain = 1,
  austria = 1, poland = 1, ['czech republic'] = 1, belgium = 1, finland = 1, norway = 1, denmark = 1, switzerland = 1 }

local function tr(s, fallback)
  if type(s) ~= 'string' then return fallback end
  if s:find('^vehiclesData') then
    local ok, t = pcall(translateLanguage, s, fallback or s, true)
    if ok and type(t) == 'string' and not t:find('^vehiclesData') then return t end
    return fallback or s
  end
  return s
end

local function isTractor(cfg)
  local bs = tostring(cfg['Body Style'] or ''):lower()
  return bs:find('fifth wheel') or bs:find('semi') or bs:find('tractor') or bs:find('sattel') or bs:find('cabover')
end

local CAR_BODY_SKIP = { ['box truck'] = 1, ['bus'] = 1, ['dump truck'] = 1, ['flatbed'] = 1 }

local function buildCatalogs()
  local trucks, cars = {}, {}
  local models = core_vehicles.getModelList(true).models or {}
  for n, m in ipairs(models) do
    local full = core_vehicles.getModel(m.key)
    local info = full and full.model or m
    local typ = tostring(info.Type or ''):lower()
    if (typ == 'truck' or typ == 'car') and full and full.configs then
      local key = info.key or m.key
      local eu = tostring(info.Region or ''):lower() == 'europe' or EU_COUNTRIES[tostring(info.Country or ''):lower()] ~= nil
      local brand, modelName = info.Brand or '', tr(info.Name, key)
      local carModel
      for _, cfg in pairs(full.configs) do
        local value = tonumber(cfg.Value) or 30000
        local entry = { model = key, config = 'vehicles/' .. key .. '/' .. cfg.key .. '.pc', brand = brand,
          modelName = modelName, configName = tr(cfg.Configuration, cfg.key), power = tonumber(cfg.Power),
          drivetrain = cfg.Drivetrain, eu = eu, preview = cfg.preview, years = cfg.Years or info.Years, body = cfg['Body Style'] }
        if typ == 'truck' and isTractor(cfg) then
          entry.kind, entry.price = 'truck', round(clamp(value * 0.3, 25000, 400000), 500)
          table.insert(trucks, entry)
        elseif not isTractor(cfg) and not CAR_BODY_SKIP[tostring(cfg['Body Style'] or ''):lower()]
            and tostring(cfg['Config Type'] or ''):lower() ~= 'prop' then
          entry.kind, entry.price = 'car', round(clamp(value, 1500, 3000000), 100)
          carModel = carModel or { model = key, brand = brand, modelName = modelName, eu = eu, configs = {}, preview = cfg.preview or (full.model and full.model.preview) }
          table.insert(carModel.configs, entry)
        end
      end
      if carModel then
        table.sort(carModel.configs, function(a, b) return a.price < b.price end)
        carModel.minPrice = carModel.configs[1].price
        table.insert(cars, carModel)
      end
    end
    if n % 4 == 0 then coroutine.yield() end
  end
  local extra = jsonReadFile(TRUCKS_FILE)
  if type(extra) == 'table' and type(extra.extra) == 'table' then
    for _, e in ipairs(extra.extra) do
      if e.model and e.config then
        local cfgPath = e.config:find('%.pc$') and e.config or ('vehicles/' .. e.model .. '/' .. e.config .. '.pc')
        table.insert(trucks, { kind = 'truck', model = e.model, config = cfgPath, brand = e.brand or '',
          modelName = e.name or e.model, configName = e.configName or '', power = e.power, eu = e.eu ~= false,
          price = tonumber(e.price) or 90000 })
      end
    end
  end
  table.sort(trucks, function(a, b) return a.price < b.price end)
  table.sort(cars, function(a, b) return a.minPrice < b.minPrice end)
  for i, t in ipairs(trucks) do t.idx = i end
  for i, c in ipairs(cars) do c.idx = i end
  R.trucks, R.cars = trucks, cars
  log('I', logTag, string.format('catalogs: %d tractors, %d car models', #trucks, #cars))
end

local function ensureCatalog()
  if R.trucks or R.catalogTask then return end
  R.catalogTask = true
  runTask(function()
    local ok, err = pcall(buildCatalogs)
    if not ok then log('E', logTag, 'catalog failed: ' .. tostring(err)); R.trucks, R.cars = {}, {} end
    R.catalogTask = nil
  end)
end

------------------------------------------------------------------------------------------
-- the player's vehicles

-- the loaner for quick jobs: in Europe the stock Cherrier Percheron tractor (fixed: it did not wait for the dealer
-- catalog, which is built in the background – a loaner fetched before it was ready came as the American T83), else
-- the Gavril T83 sleeper
local EU_LOANER = { kind = 'truck', model = 'percheron', config = 'vehicles/percheron/l370_4x2_fifthwheel_A.pc',
  brand = 'Cherrier', modelName = 'Percheron', configName = 'L370 4x2 Sattelzugmaschine', eu = true, price = 90000 }
local function loanerTruck()
  local cat = R.trucks or {}
  if inEurope() then
    if core_vehicles and core_vehicles.getModel and core_vehicles.getModel('percheron') then return EU_LOANER end
    for _, t in ipairs(cat) do if t.eu then return t end end
  end
  for _, t in ipairs(cat) do if normPath(t.config) == 'vehicles/us_semi/t83_sleeper.pc' then return t end end
  return cat[1] or { kind = 'truck', model = 'us_semi', config = 'vehicles/us_semi/t83_sleeper.pc', brand = 'Gavril', modelName = 'T-Series', configName = 'T83 Sleeper' }
end

local function activeDef()
  if S.active == 'rental' and S.rental then return S.rental, false end
  if S.active ~= 'loaner' and S.owned[S.active] then return S.owned[S.active], false end
  return loanerTruck(), true
end

local function activeKind()
  local def = activeDef()
  return def.kind or 'truck'
end
L.activeKind = activeKind


local function careerVeh()
  local v = vehById(R.truckId)
  if v then return v end
  R.truckId = nil
end

local function adoptPlayerVehicle()
  local v = playerVeh()
  if not v then return end
  local def = activeDef()
  if def and type(def.config) == 'string' and configOf(v:getID()) == normPath(def.config) then       -- (on foot: no vehicle of the career)
    R.truckId = v:getID()
    roadEvents.protect(R.truckId)
    return true
  end
end

local function damageOf(id)
  local o = map and map.objects and map.objects[id]
  local d = o and o.damage or 0
  -- (the damage brought back from the last session: the game counts only what happens after the spawn)
  if R.dmgBase and R.dmgBase.id == id then d = d + R.dmgBase.v end
  return d
end

------------------------------------------------------------------------------------------
-- navigation (BeamNG.Earth GPS: real routing, ground arrows)

local function navTo(place, name)
  local gps = place and earthModule('gps')
  if gps and gps.setDestination then gps.setDestination(place.lat, place.lon, name) end
  R.navName = name
end

local function navClear()
  local gps = earthModule('gps')
  if gps and gps.clear then pcall(gps.clear) end
  R.navName = nil
end

local function gpsStatus()
  local gps = earthModule('gps')
  return gps and gps.status and gps.status() or nil
end

-- BeamNG.Earth 1.8.1's arrival along the route (gps.arrived; older versions: nil) – only while the GPS leads to
-- `place` (its destination within 300 m of it)
function L.gpsArrived(st, place)
  local gps = earthModule('gps')
  if not (st and place and gps and gps.arrived and st.dist and st.lat) then return false end
  if haversine(st.lat, st.lon, place.lat, place.lon) > 300 then return false end
  local ok, yes = pcall(gps.arrived, st.dist, st.remaining, st.off or 0)
  return ok and yes or false
end

-- a destination typed or pasted (BeamNG.Earth 1.8.1: Google Maps / OpenStreetMap links too, places.parseLatLon;
-- before: coordinates only) → the navi goes there
function M.navToText(text)
  if not S or type(text) ~= 'string' or text == '' then return { ok = false, msg = 'Nichts eingegeben.' } end
  local places = earthModule('places')
  local lat, lon
  if places and places.parseLatLon then
    local ok, a, b = pcall(places.parseLatLon, text)
    if ok and tonumber(a) and tonumber(b) then lat, lon = tonumber(a), tonumber(b) end
  end
  if not lat then
    local a, b = text:match('([%-+]?%d+%.%d+)%s*[,; ]%s*([%-+]?%d+%.%d+)')
    lat, lon = tonumber(a), tonumber(b)
  end
  if not lat or math.abs(lat) > 90 or math.abs(lon) > 180 then
    return { ok = false, msg = 'Kein Ort erkannt – Koordinaten („52.22, 6.89“) oder einen Google-Maps-/OpenStreetMap-Link einfügen.' }
  end
  local p = here()
  local km = p and haversine(p.lat, p.lon, lat, lon) / 1000 or nil
  navTo({ lat = lat, lon = lon }, 'Ziel ' .. string.format('%.4f, %.4f', lat, lon))
  notify(string.format('🧭 Navi-Ziel gesetzt%s', km and string.format(' – %.0f km Luftlinie', km) or ''), 5)
  return { ok = true, msg = string.format('Navi-Ziel: %.5f, %.5f%s', lat, lon, km and string.format(' (%.0f km Luftlinie)', km) or '') }
end

-- the route planner (2026-11-04): several stops in a row. BeamNG.Earth's GPS leads to one destination at a time, so
-- the planner hands it the stops one after the other: arrived at one (within 60 m, or Earth's "arrived along the
-- route"), the next is set. S.route = { stops = { {name, lat, lon} }, idx = the stop being driven to, or nil }
L.ROUTE_MAX = 12
function L.route() S.route = S.route or { stops = {} }; return S.route end
function L.parseText(text)
  local places = earthModule('places')
  local lat, lon
  if places and places.parseLatLon then
    local ok, a, b = pcall(places.parseLatLon, text)
    if ok and tonumber(a) and tonumber(b) then lat, lon = tonumber(a), tonumber(b) end
  end
  if not lat then
    local a, b = tostring(text):match('([%-+]?%d+%.%d+)%s*[,; ]%s*([%-+]?%d+%.%d+)')
    lat, lon = tonumber(a), tonumber(b)
  end
  if lat and math.abs(lat) <= 90 and math.abs(lon) <= 180 then return lat, lon end
end
function L.routeView()
  local r = L.route()
  local out, total, prev = {}, 0, here()
  for i, s in ipairs(r.stops) do
    local km = prev and haversine(prev.lat, prev.lon, s.lat, s.lon) / 1000 * 1.25 or nil     -- (roads: ~a quarter more)
    if km and (not r.idx or i >= r.idx) then total = total + km end
    out[i] = { name = s.name, lat = s.lat, lon = s.lon, km = km and math.floor(km * 10 + 0.5) / 10 or nil,
      done = r.idx and i < r.idx or nil, active = r.idx == i or nil }
    prev = s
  end
  return { stops = out, idx = r.idx, totalKm = math.floor(total + 0.5) }
end
function M.routeAdd(lat, lon, name)
  if not S then return nil end
  local r = L.route()
  lat, lon = tonumber(lat), tonumber(lon)
  if not lat or not lon then return { ok = false, msg = 'Kein Ort.' } end
  if #r.stops >= L.ROUTE_MAX then return { ok = false, msg = 'Höchstens ' .. L.ROUTE_MAX .. ' Stopps.' } end
  r.stops[#r.stops + 1] = { name = (name and name ~= '') and tostring(name) or string.format('%.4f, %.4f', lat, lon), lat = lat, lon = lon }
  save()
  return { ok = true, msg = 'Stopp ' .. #r.stops .. ' hinzugefügt: ' .. r.stops[#r.stops].name, route = L.routeView() }
end
function M.routeAddText(text)
  local lat, lon = L.parseText(text)
  if not lat then return { ok = false, msg = 'Kein Ort erkannt – Koordinaten oder einen Google-Maps-/OpenStreetMap-Link einfügen.' } end
  return M.routeAdd(lat, lon, nil)
end
function M.routeAddHere()
  local p = here()
  if not p then return { ok = false, msg = 'Position unbekannt.' } end
  return M.routeAdd(p.lat, p.lon, 'Aktuelle Position')
end
function M.routeMove(i, d)
  local r = L.route()
  i, d = tonumber(i), tonumber(d)
  local j = i and d and i + d
  if not (i and j and r.stops[i] and r.stops[j]) then return L.routeView() end
  r.stops[i], r.stops[j] = r.stops[j], r.stops[i]
  if r.idx then r.idx = 1; navTo(r.stops[1], 'Route: ' .. r.stops[1].name) end    -- (re-planned from the first)
  save()
  return L.routeView()
end
function M.routeRemove(i)
  local r = L.route()
  i = tonumber(i)
  if i and r.stops[i] then
    table.remove(r.stops, i)
    if r.idx then
      if #r.stops == 0 then r.idx = nil; navClear()
      elseif i <= r.idx then r.idx = math.max(1, math.min(r.idx - (i < r.idx and 1 or 0), #r.stops)); navTo(r.stops[r.idx], 'Route: ' .. r.stops[r.idx].name) end
    end
    save()
  end
  return L.routeView()
end
function M.routeClear()
  local r = L.route()
  if r.idx then navClear() end
  r.stops, r.idx = {}, nil
  save()
  return L.routeView()
end
function M.routeStart()
  local r = L.route()
  if #r.stops == 0 then return L.routeView() end
  r.idx = 1
  navTo(r.stops[1], 'Route: ' .. r.stops[1].name)
  notify(string.format('🧭 Route gestartet: %d Stopps – erster: %s', #r.stops, r.stops[1].name), 6)
  save()
  return L.routeView()
end
function M.routeStop()
  local r = L.route()
  if r.idx then r.idx = nil; navClear(); notify('Route beendet.', 3); save() end
  return L.routeView()
end
-- once a second: arrived at the stop being driven to → the next
function L.routeTick()
  local r = S and S.route
  if not (r and r.idx and r.stops[r.idx]) then return end
  local s = r.stops[r.idx]
  local p = here()
  local st = gpsStatus()
  local arrived = (p and haversine(p.lat, p.lon, s.lat, s.lon) < 60) or L.gpsArrived(st, s)
  if not arrived then return end
  if r.idx < #r.stops then
    r.idx = r.idx + 1
    local nx = r.stops[r.idx]
    navTo(nx, 'Route: ' .. nx.name)
    notify(string.format('📍 Stopp %d erreicht: %s – weiter zu %s (%d/%d)', r.idx - 1, s.name, nx.name, r.idx, #r.stops), 6)
  else
    r.idx = nil
    navClear()
    notify('🏁 Route abgeschlossen: ' .. s.name, 6)
  end
  save()
end

-- our points on BeamNG.Earth's own map (2026-11-04): its "Places" pins show the saved places (places.uiState); the
-- career's points are added to that list while the career runs – the yard, the job's loading and unloading place,
-- the route's stops, the companies with loads waiting nearby. A click on one there sets the GPS (as for any place);
-- "Go" on one of ours sets the navi too instead of teleporting; renaming or deleting them is refused.
function L.earthPins()
  local pins = {}
  local function add(key, name, lat, lon) if lat and lon then pins[#pins + 1] = { id = 'ff:' .. key, name = name, lat = lat, lon = lon } end end
  if S.home then add('home', '🏠 ' .. (S.home.name or 'Firmenhof'), S.home.lat, S.home.lon) end
  local job = S.job
  if job then
    add('from', '📦 Laden: ' .. tostring(job.from and job.from.name), job.from and job.from.lat, job.from and job.from.lon)
    if job.to and not job.to.pending then add('to', '🏁 Abladen: ' .. tostring(job.to.name), job.to.lat, job.to.lon) end
  end
  for i, s in ipairs((S.route and S.route.stops) or {}) do add('r' .. i, string.format('🧭 Route %d: %s', i, s.name), s.lat, s.lon) end
  local p, seen, n = here(), {}, 0
  for _, o in ipairs(R.offers or {}) do
    local f = o.from
    if f and f.lat and not seen[f.id or f.name] and n < 10 and (not p or haversine(p.lat, p.lon, f.lat, f.lon) < 15000) then
      seen[f.id or f.name] = true
      n = n + 1
      add('o' .. n, '🟧 Fracht: ' .. tostring(f.name), f.lat, f.lon)
    end
  end
  return pins
end
function L.installEarthPins()
  local pl = earthModule('places')
  if not pl or pl.__ffPins or type(pl.uiState) ~= 'function' then return end
  local orig = { uiState = pl.uiState, uiGo = pl.uiGo, uiRename = pl.uiRename, uiDelete = pl.uiDelete }
  pl.__ffPins = orig
  pl.uiState = function(res)
    local out = orig.uiState(res)
    if R.mode and S and type(out) == 'table' and type(out.places) == 'table' then
      local okP, pins = pcall(L.earthPins)
      for _, q in ipairs(okP and pins or {}) do
        out.places[#out.places + 1] = { id = q.id, name = q.name, lat = q.lat, lon = q.lon,
          text = string.format('%.5f, %.5f · Trucks of Earth', q.lat, q.lon) }
      end
    end
    return out
  end
  local function ours(id) return type(id) == 'string' and id:sub(1, 3) == 'ff:' end
  local function pinOf(id) for _, q in ipairs(L.earthPins()) do if q.id == id then return q end end end
  pl.uiGo = function(id)
    if ours(id) then
      local q = pinOf(id)
      if q then navTo(q, q.name); notify('🧭 Navi: ' .. q.name, 4) end
      local out = pl.uiState({ ok = q ~= nil })
      return out
    end
    return orig.uiGo(id)
  end
  pl.uiRename = function(id, name)
    if ours(id) then return pl.uiState({ ok = false, error = 'Punkte der Spedition lassen sich nicht umbenennen.' }) end
    return orig.uiRename(id, name)
  end
  pl.uiDelete = function(id)
    if ours(id) then return pl.uiState({ ok = false, error = 'Punkte der Spedition werden von der Karriere verwaltet.' }) end
    return orig.uiDelete(id)
  end
end
function L.removeEarthPins()
  local pl = earthModule('places')
  local orig = pl and pl.__ffPins
  if not orig then return end
  pl.uiState, pl.uiGo, pl.uiRename, pl.uiDelete = orig.uiState, orig.uiGo, orig.uiRename, orig.uiDelete
  pl.__ffPins = nil
end

-- a video on the vehicle's own navigation screen (2026-11-04): the screen is a WebView of the vehicle (its
-- beamNavigator controller, jbeam screenMaterialName); BeamNG.Earth puts its map there the same way – the page sent
-- elsewhere with queueJSUITexture. Ours: ui/modules/apps/FernfahrerVideo/screen.html with the video and the address to
-- go back to (Earth's map page, or the stock navigator).
L.VIDEO_SCREEN = 'local://local/ui/modules/apps/FernfahrerVideo/screen.html'
function L.screenTags(veh)
  local okV, vd = pcall(function() return core_vehicle_manager.getVehicleData(veh:getID()) end)
  local ctrls = okV and vd and vd.vdata and vd.vdata.controller
  local tags = {}
  for _, c in pairs(ctrls or {}) do
    if type(c) == 'table' and tostring(c.fileName or c.name or ''):find('beamNavigator') then
      tags[#tags + 1] = c.screenMaterialName or '@screen_gps'
    end
  end
  return tags
end
function M.videoToScreen(src, t)
  local veh = careerVeh() or playerVeh()
  if not veh or type(src) ~= 'string' or src == '' then return { ok = false, msg = 'Kein Fahrzeug oder kein Video.' } end
  local tags = L.screenTags(veh)
  if #tags == 0 then return { ok = false, msg = 'Dieses Fahrzeug hat kein Navi-Display.' } end
  -- (already showing a video: the page stays, only the new one and its time – else the way back would be our page)
  if R.videoScreen and R.videoScreen.id == veh:getID() then
    for _, tag in ipairs(R.videoScreen.tags) do
      veh:queueJSUITexture(tag, 'window.ffLoad&&window.ffLoad(' .. jsonEncode(src) .. ',' .. string.format('%.2f', tonumber(t) or 0) .. ')')
    end
    return { ok = true, msg = 'Läuft auf dem Fahrzeug-Display.' }
  end
  pcall(L.videoScreenOff)
  for _, tag in ipairs(tags) do
    veh:queueJSUITexture(tag, 'window.location.replace(' .. jsonEncode(L.VIDEO_SCREEN .. '?src=') .. '+encodeURIComponent('
      .. jsonEncode(src) .. ')+"&t=' .. string.format('%.2f', tonumber(t) or 0) .. '&ret="+encodeURIComponent(window.location.href))')
  end
  R.videoScreen = { id = veh:getID(), tags = tags }
  return { ok = true, msg = 'Läuft auf dem Fahrzeug-Display (' .. #tags .. ').' }
end
function L.videoScreenOff()
  local vs = R.videoScreen
  R.videoScreen = nil
  local veh = vs and getObjectByID(vs.id)
  if not veh then return end
  for _, tag in ipairs(vs.tags) do pcall(function() veh:queueJSUITexture(tag, 'window.ffBack&&window.ffBack()') end) end
end
function M.videoScreenOff() pcall(L.videoScreenOff); return { ok = true } end
-- the screen's video kept on the video app's clock (the same time the helper's sound follows): t seconds, running
function M.videoScreenSync(t, playing)
  local vs = R.videoScreen
  local veh = vs and getObjectByID(vs.id)
  if not veh then return end
  local js = string.format('window.ffSync&&window.ffSync(%.2f,%s)', tonumber(t) or 0, playing and 'true' or 'false')
  for _, tag in ipairs(vs.tags) do pcall(function() veh:queueJSUITexture(tag, js) end) end
end

local function routeEnd()
  local gps = earthModule('gps')
  local r = gps and gps.route and gps.route()
  local pts = r and r.points
  local p = pts and pts[#pts]
  if p then return { lat = p[1], lon = p[2] } end
end

-- Spoken directions (the route advisor app speaks them: the browser's speech, a German voice when there is one):
-- the next turn on the Earth route – a heading change of more than NAV_TURN_DEG at a junction of the road graph
-- (bends of the road itself are not announced) – at 600 m, 200 m and "now"; the destination at its end.
local NAV = { TURN_DEG = 28, MIN_DEG = 12, FOLLOW_MAX_DEG = 65, MINOR_DRV = 0.45, UNKNOWN_DEG = 50, LOOK_M = 900, STAGES = { 600, 200, 45 }, JUNCTION_M = 45, NOW_S = 3.2, NOW_MAX_M = 110 }

local function hav(a1, o1, a2, o2)
  local p1, p2 = math.rad(a1), math.rad(a2)
  local dp, dl = p2 - p1, math.rad(o2 - o1)
  local x = math.sin(dp / 2) ^ 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ^ 2
  return 2 * 6371000 * math.asin(math.min(1, math.sqrt(x)))
end

local function bearing(a1, o1, a2, o2)
  local y = math.sin(math.rad(o2 - o1)) * math.cos(math.rad(a2))
  local x = math.cos(math.rad(a1)) * math.sin(math.rad(a2)) - math.sin(math.rad(a1)) * math.cos(math.rad(a2)) * math.cos(math.rad(o2 - o1))
  return math.deg(math.atan2(y, x))
end

-- the route point d m before / after index i (for a heading over a stretch, not one short segment)
local function pointAway(pts, i, d, step)
  local acc, j = 0, i
  while pts[j + step] and acc < d do
    acc = acc + hav(pts[j][1], pts[j][2], pts[j + step][1], pts[j + step][2])
    j = j + step
  end
  return pts[j]
end

-- A junction near (lat, lon): the game graph's nodes within JUNCTION_M taken together have more than two ways out
-- (one node with three links, or a junction split over several close nodes as Earth's graph has them on wide roads)
-- (2026-11-08) nil: the game has no roads there yet (they load as one comes near) – at 600 m that said "no junction"
-- and the turn was never announced, or only just before it
-- (2026-11-09) Is the route's bend here something to say? Not every bend at a junction is: a main road curving past a side
-- street is simply followed. Said only when another road worth the name leaves here and the route is not the straightest way
-- on (or the bend is sharp). h1, h2: the route's heading into and out of the point. true / false, or nil: no roads there yet.
-- The answer is kept per route point: it went back and forth as the roads loaded, and announced turns vanished again.
function L.navManeuver(lat, lon, h1, h2)
  local c = earthCore()
  local st = c and c._state and c._state()
  local anchor = st and st.anchor
  if not anchor or not anchor.geodeticToWorld or not (map and map.getMap) then return nil end
  local x, y = anchor:geodeticToWorld(lat, lon, 0)
  local nodes = map.getMap().nodes or {}
  local r2 = NAV.JUNCTION_M * NAV.JUNCTION_M
  local inside, any = {}, false
  for name, n in pairs(nodes) do
    local dx, dy = n.pos.x - x, n.pos.y - y
    if dx * dx + dy * dy < r2 then inside[name] = n; any = true end
  end
  if not any then return nil end
  local function rel(a, b) return (a - b + 540) % 360 - 180 end
  local exits = {}
  for name, n in pairs(inside) do
    for other, link in pairs(n.links or {}) do
      local o = nodes[other]
      local entryOnly = type(link) == 'table' and link.oneWay and link.inNode ~= name
      if o and not inside[other] and not entryOnly then
        local e = math.deg(math.atan2(o.pos.x - x, o.pos.y - y))
        local turn = rel(e, h1)
        if math.abs(turn) < 145 then         -- (not the way we came)
          exits[#exits + 1] = { turn = turn, off = math.abs(rel(e, h2)), drv = type(link) == 'table' and link.drivability or 1 }
        end
      end
    end
  end
  local route
  for _, e in ipairs(exits) do if not route or e.off < route.off then route = e end end
  if not route or route.off > 40 then return nil end
  local straightest, others = true, 0
  for _, e in ipairs(exits) do
    local same = math.abs(rel(e.turn, route.turn)) < 12
    local minor = e.drv < NAV.MINOR_DRV and route.drv >= NAV.MINOR_DRV     -- (field tracks and yards: no alternative to a road)
    if e ~= route and not same and not minor then
      others = others + 1
      if math.abs(e.turn) + 5 < math.abs(route.turn) then straightest = false end
    end
  end
  if others == 0 then return false end
  return not straightest or math.abs(route.turn) >= NAV.FOLLOW_MAX_DEG
end
L.NAV_CHECKS = 8                                 -- (new route points looked at per update: each walks the road graph)
function L.navManeuverAt(pts, pt, h1, h2)
  if R.navJPts ~= pts then R.navJPts, R.navJ = pts, {} end
  local key = string.format('%.5f,%.5f', pt[1], pt[2])
  local known = R.navJ[key]
  if known ~= nil then return known end
  if (R.navJLeft or 0) <= 0 then return 'busy' end
  R.navJLeft = R.navJLeft - 1
  local r = L.navManeuver(pt[1], pt[2], h1, h2)
  if r ~= nil then R.navJ[key] = r end
  return r
end

-- (2026-11-08) a roundabout on the route from point i: the road keeps turning left (right-hand traffic), vertex after
-- vertex, over a short way. Returns the index it ends at, or nil. (Its turns are one manoeuvre: "Kreisverkehr".)
function L.navRoundabout(pts, i)
  local run, left, len, last = 0, 0, 0, nil
  local j = math.max(2, i - 2)
  while pts[j + 1] and len < 130 do
    local a, b, c = pts[j - 1], pts[j], pts[j + 1]
    local d = (bearing(b[1], b[2], c[1], c[2]) - bearing(a[1], a[2], b[1], b[2]) + 540) % 360 - 180
    len = len + hav(b[1], b[2], c[1], c[2])
    if d < -7 then
      run, left, last = run + 1, left + (-d), j + 1
      if run >= 4 and left >= 95 then
        -- (on to where it stops turning left)
        local k = j + 1
        while pts[k + 1] and pts[k - 1] and (bearing(pts[k][1], pts[k][2], pts[k + 1][1], pts[k + 1][2]) - bearing(pts[k - 1][1], pts[k - 1][2], pts[k][1], pts[k][2]) + 540) % 360 - 180 < -7 do k = k + 1 end
        return k + 1
      end
    elseif d > 12 and run > 0 then
      run, left = 0, 0
    end
    j = j + 1
  end
  return nil
end

-- The cab radio: music from Windows (Spotify set to the output "Steam Streaming Speakers") taken by the radio
-- helper (fernfahrer_karriere/tools/radio, Fernfahrer-Radio.exe) and played through the speakers the way the game
-- says: full in the cab, muffled from outside, fading with the distance on foot, quieter while the navi speaks. The
-- game writes its state (settings/fernfahrer/radio_state.json, 4× a second); the helper answers with a heartbeat
-- (radio_helper.json). Nothing of the browser's audio (the internet radio there stayed silent in game, 2026-11-04).
L.RADIO_STATE, L.RADIO_HELPER = '/settings/fernfahrer/radio_state.json', '/settings/fernfahrer/radio_helper.json'
-- (2026-11-04: the helper also plays these itself, decoded with Windows Media Foundation – each checked with
-- `Fernfahrer-Radio.exe --probe`; and for Spotify it sets the player's own volume in the Windows mixer)
L.STATIONS = {
  { '1LIVE', 'https://wdr-1live-live.icecastssl.wdr.de/wdr/1live/live/mp3/128/stream.mp3' },
  { 'WDR 2', 'https://wdr-wdr2-rheinland.icecastssl.wdr.de/wdr/wdr2/rheinland/mp3/128/stream.mp3' },
  { 'NDR 2', 'https://icecast.ndr.de/ndr/ndr2/niedersachsen/mp3/128/stream.mp3' },
  { 'SWR3', 'https://liveradio.swr.de/sw282p3/swr3/play.mp3' },
  { 'Bayern 3', 'https://dispatcher.rndfnk.com/br/br3/live/mp3/mid' },
  { 'Antenne Bayern', 'https://stream.antenne.de/antenne' },
  { 'Hit Radio FFH', 'https://mp3.ffh.de/radioffh/hqlivestream.mp3' },
  { 'radio ffn', 'https://stream.ffn.de/ffn/mp3-192/stream.mp3' },
  { 'Radio Bob', 'https://streams.radiobob.de/bob-national/mp3-192/mediaplayer' },
  { 'Rock Antenne', 'https://stream.rockantenne.de/rockantenne/stream/mp3' },
  { 'Deutschlandfunk', 'https://st01.sslstream.dlf.de/dlf/01/128/mp3/stream.mp3' },
  { 'NPO Radio 2', 'https://icecast.omroep.nl/radio2-bb-mp3' },
  { 'Radio 538', 'https://22593.live.streamtheworld.com/RADIO538.mp3' },
  { 'Qmusic', 'https://icecast-qmusicnl-cdp.triple-it.nl/Qmusic_nl_live_96.mp3' },
}
-- (2026-11-08) the stations of the regions: added at the end (the numbers of the others stay what the saves hold them as);
-- driving into another state the radio changes to its station, with the noise of the dial in between
L.regions = require('fernfahrer/regions')
L.regionIdx = {}
for key, s in pairs(L.regions.STATE) do
  for i, st in ipairs(L.STATIONS) do if st[2] == s[3] then L.regionIdx[key] = i end end
end
do
  local keys = {}
  for key in pairs(L.regions.STATE) do keys[#keys + 1] = key end
  table.sort(keys)
  for _, key in ipairs(keys) do
    if not L.regionIdx[key] then
      local s = L.regions.STATE[key]
      L.STATIONS[#L.STATIONS + 1] = { s[2], s[3] }
      L.regionIdx[key] = #L.STATIONS
    end
  end
end
L.REGION_S, L.TUNE_WAV = 6, 'art/sound/fernfahrer/radio_tune.wav'
function L.radioTuneNoise()
  if R.radioMode ~= 'cab' or (S.settings.radioSrc or 'radio') ~= 'radio' then return end
  if Engine and Engine.Audio and Engine.Audio.playOnce then
    pcall(Engine.Audio.playOnce, 'AudioGui', L.TUNE_WAV, { volume = math.min(1, (S.settings.radioVol or 0.7) * 0.9 + 0.1) })
  end
end
function L.radioRegionTick(t)
  if t - (R.regionT or 0) < L.REGION_S or R.trip or R.sleep then return end
  R.regionT = t
  if S.settings.radioRegional == false or S.settings.radioOn == false or (S.settings.radioSrc or 'radio') ~= 'radio' then return end
  local p = here()
  if not p then return end
  local key = L.regions.at(p.lat, p.lon)
  if not key or key == S.settings.radioRegion then R.regionWant = nil; return end
  -- (the same answer twice in a row: no flicker along a border)
  if R.regionWant ~= key then R.regionWant = key; return end
  R.regionWant = nil
  S.settings.radioRegion = key
  S.settings.radioStation = L.regionIdx[key]
  L.radioTuneNoise()
  local s = L.regions.STATE[key]
  notify('📻 ' .. s[2] .. ' · ' .. s[1], 5)
  log('I', logTag, 'radio: region ' .. key .. ', station ' .. s[2])
  pcall(L.radioTick)
  save()
end
-- (2026-11-08) the favourites and the list of stations (the radio's ☰): with two favourites or more the tuning knob steps
-- through those; the numbers of the stations stay what the saves hold them as
function L.radioFavs()
  if type(S.settings.radioFavs) ~= 'table' then S.settings.radioFavs = {} end
  return S.settings.radioFavs
end
function L.radioStep(i, d)
  local f = L.radioFavs()
  if #f < 2 then return (i - 1 + d) % #L.STATIONS + 1 end
  local pos
  for k, v in ipairs(f) do if v == i then pos = k end end
  if not pos then pos = d > 0 and 0 or 1 end
  return f[(pos - 1 + d) % #f + 1]
end
function M.radioList()
  if not S then return nil end
  local regionOf, isFav, list = {}, {}, {}
  for key, i in pairs(L.regionIdx) do regionOf[i] = L.regions.STATE[key][1] end
  local favs = L.radioFavs()
  for _, v in ipairs(favs) do isFav[v] = true end
  for i, st in ipairs(L.STATIONS) do list[i] = { i = i, n = st[1], r = regionOf[i], f = isFav[i] or nil } end
  local cur = L.radioStation()
  return { list = list, cur = cur, regional = S.settings.radioRegional ~= false, favs = #favs }
end
function M.radioPick(i)
  i = tonumber(i)
  if not S or not i or not L.STATIONS[i] then return nil end
  S.settings.radioStation, S.settings.radioOn = i, true
  L.radioTuneNoise()
  notify('📻 ' .. L.STATIONS[i][1], 2)
  pcall(L.radioTick)
  save()
  return M.radioList()
end
function M.radioFav(i)
  i = tonumber(i)
  if not S or not i or not L.STATIONS[i] then return nil end
  local f, at = L.radioFavs(), nil
  for k, v in ipairs(f) do if v == i then at = k end end
  if at then table.remove(f, at) else f[#f + 1] = i end
  save()
  return M.radioList()
end
-- (2026-11-08) where the truck is: the state or the country, in the map's corner and as a banner at a border
L.WHERE_S = 3
function L.whereTick(t)
  if t - (R.whereT or 0) < L.WHERE_S or R.trip or R.sleep or R.pendingTeleport then return end
  R.whereT = t
  -- (BeamNG.Earth 1.9's modding API: the name of the road, as its status bar has it; nil before that version or without online names)
  local api = rawget(_G, 'beamngEarth_api')
  local okP, place = pcall(function() return api and api.has and api.has('place') and api.place() end)
  R.streetIn = okP and type(place) == 'table' and place.street or nil
  local p = here()
  local w = p and L.regions.where(p.lat, p.lon)
  if not w then return end
  local key = w.code .. '|' .. (w.state or '')
  if key == R.whereKey then R.whereWant = nil; return end
  -- (the first answer, and an arrival under a screen: said without a banner)
  if not R.whereKey or not L.screenGone(t) then R.whereKey, R.where, R.whereWant = key, w, nil; return end
  -- (the same answer twice in a row: no flicker along a border)
  if R.whereWant ~= key then R.whereWant = key; return end
  local old = R.where
  R.whereKey, R.where, R.whereWant = key, w, nil
  local country = not old or old.code ~= w.code
  guihooks.trigger('FernfahrerRegion', { kind = country and 'country' or 'state', code = w.code,
    name = country and w.country or w.state, sub = country and w.state or w.country })
  log('I', logTag, 'now in ' .. key)
end
function L.radioStation()
  local s = S and S.settings or {}
  local i = math.max(1, math.min(#L.STATIONS, tonumber(s.radioStation) or 1))
  return i, L.STATIONS[i]
end
function L.radioWrite(mode, dist)
  local s = S and S.settings or {}
  local _, st = L.radioStation()
  local d = { mode = mode, dist = math.floor((dist or 0) + 0.5),
    vol = s.radioVol or 0.7, duck = (R.navDuckUntil or 0) > now() or nil,
    src = s.radioSrc or 'radio', url = st and st[2] or '', cmd = R.radioCmd or '', seq = R.radioSeq or 0,
    eqB = s.radioEqB or 0, eqM = s.radioEqM or 0, eqT = s.radioEqT or 0 }
  -- the radio's source VIDEO (picked by hand at the radio – 2026-11-04: switching on its own went wrong): the video
  -- player's sound, played by the helper in step with the picture; no video running: silence
  if s.radioSrc == 'video' then
    local vid = L.videoActive()
    d.src, d.url = 'video', vid and vid.url or ''
    if vid then
      d.vplay = vid.playing and true or false
      -- (as text: a livestream's position is its clock time, Unix seconds – a JSON number would lose its digits)
      d.vpos = string.format('%.1f', vid.t + (vid.playing and (now() - vid.at) or 0))
    end
  end
  -- (written when something changed, else every 1.5 s as a sign of life – it was a disk write 4× a second)
  local key = string.format('%s|%d|%.2f|%s|%s|%s|%d|%d|%d|%d|%s|%s', d.mode, d.dist, d.vol, tostring(d.duck), d.src, d.url, d.seq,
    d.eqB, d.eqM, d.eqT, tostring(d.vplay), tostring(d.vpos and math.floor(tonumber(d.vpos) or 0)))
  local t = now()
  if key == R.radioKey and t - (R.radioWroteT or 0) < 1.5 then return end
  R.radioKey, R.radioWroteT = key, t
  d.t = os.time()
  pcall(jsonWriteFile, L.RADIO_STATE, d, false)
end
-- the cab app's buttons: 'stnext'/'stprev' (the station), 'play'/'next'/'prev' (Spotify's media keys)
function M.radioCmd(cmd)
  if not S then return end
  if cmd == 'stnext' or cmd == 'stprev' then
    local i = L.radioStation()
    S.settings.radioStation = L.radioStep(i, cmd == 'stnext' and 1 or -1)
    S.settings.radioOn = true
    L.radioTuneNoise()
    local _, st = L.radioStation()
    if st then notify('📻 ' .. st[1], 2) end        -- (the radio has no display: the station as a short message)
  else
    R.radioCmd, R.radioSeq = tostring(cmd), (R.radioSeq or 0) + 1
  end
  pcall(L.radioTick)
end
-- the video window (FernfahrerVideo) tells twice a second where its picture is: { url, t (s), playing }; nil = off
function M.videoState(v)
  if type(v) ~= 'table' or not v.url or v.url == '' then R.video = nil; return end
  R.video = { url = tostring(v.url), t = tonumber(v.t) or 0, playing = v.playing and true or false, at = now() }
end
function L.videoActive()
  local v = R.video
  if v and now() - v.at < 3 then return v end
  return nil
end
-- the camera in the cab? (2026-11-05: only the camera named "driver" counted – the occupant camera of the seat
-- settings and other mods' cockpit cameras were "outside", the radio always muffled.) By name, else by where the
-- camera is: inside the vehicle's box.
function L.camInCab(v)
  local okC, cam = pcall(core_camera.getActiveCamName, 0)
  cam = okC and tostring(cam or '') or ''
  if cam == 'driver' or cam:find('^occupant') or cam:find('onboard') or cam:find('cockpit') or cam:find('interior') then return true end
  if cam == 'orbit' or cam == 'chase' or cam == 'topDown' or cam == 'free' or cam == 'external' then return false end
  local ok, inside = pcall(function()
    local cp = core_camera.getPosition()
    local bb = v:getSpawnWorldOOBB()
    local c, h = vec3(bb:getCenter()), vec3(bb:getHalfExtents())
    local d = vec3(cp) - c
    for i = 0, 2 do
      local ax = vec3(bb:getAxis(i))
      local e = i == 0 and h.x or (i == 1 and h.y or h.z)
      if math.abs(d:dot(ax)) > e + 0.1 then return false end
    end
    return true
  end)
  return ok and inside or false
end
function L.radioTick()
  local mode, dist = 'cab', 0
  if S.settings.radioOn == false or R.loadAt or R.moodMute then mode = 'off'
  else
    local v, truck = playerVeh(), careerVeh()
    if v and truck and v:getID() == truck:getID() then
      mode = L.camInCab(v) and 'cab' or 'outside'
    elseif v and truck then
      mode, dist = 'walk', vehPos(v):distance(vehPos(truck))
    else
      mode = 'outside'
    end
  end
  R.radioMode = mode
  L.radioWrite(mode, dist)
  -- (the helper's heartbeat: the HUD says whether it runs)
  -- (more often while a video runs: its picture file, once the helper has it, goes to the HUD's player)
  if now() - (R.radioHelperT or 0) > (L.videoActive() and 0.75 or 2) then
    R.radioHelperT = now()
    local okH, hb = pcall(jsonReadFile, L.RADIO_HELPER)
    R.radioHelper = okH and type(hb) == 'table' and hb.t and math.abs(os.time() - hb.t) < 8 or false
    R.radioLevel = R.radioHelper and tonumber(hb.level) or 0
    R.radioInfo = R.radioHelper and { status = hb.status, title = hb.title, ok = hb.ok, src = hb.src,
      video = hb.video ~= '' and hb.video or nil, videoFor = hb.videoFor, videoMB = tonumber(hb.videoMB),
      live = hb.live ~= '' and hb.live or nil, liveFor = hb.liveFor } or nil
  end
end

-- one recorded phrase (art/sound/fernfahrer/nav/<name>.wav) through the game's own audio
function M.navSay(name)
  R.navDuckUntil = now() + 3.5                  -- (the radio quieter while it speaks)
  local path = 'art/sound/fernfahrer/nav/' .. tostring(name):gsub('[^%w_]', '') .. '.wav'
  if not (Engine and Engine.Audio and Engine.Audio.playOnce) then return false end
  local ok, err = pcall(Engine.Audio.playOnce, 'AudioGui', path, { volume = 1 })
  if not ok then log('W', logTag, 'navi voice ' .. path .. ': ' .. tostring(err)) end
  return ok
end

function L.updateNav()
  if S.settings.navVoice == false then R.nav = nil; return end
  R.navJLeft = L.NAV_CHECKS
  local gps = earthModule('gps')
  local r = gps and gps.route and gps.route()
  local pts = r and r.points
  local p = here()
  if not pts or #pts < 3 or not p then R.nav = nil; return end
  -- where the player is on the route: the nearest SEGMENT (on country roads and motorways the route's points lie
  -- hundreds of metres apart – the nearest point was >150 m off and the navi went quiet, only towns worked,
  -- 2026-11-03); near the last place first, else the whole route
  local kx, ky = 111320 * math.cos(math.rad(p.lat)), 111320
  local function nearest(a, b)
    local bi, bdd, bf
    for i = a, math.min(b, #pts - 1) do
      local ax, ay = (pts[i][2] - p.lon) * kx, (pts[i][1] - p.lat) * ky
      local bx, by = (pts[i + 1][2] - p.lon) * kx, (pts[i + 1][1] - p.lat) * ky
      local sx, sy = bx - ax, by - ay
      local l2 = sx * sx + sy * sy
      local f = l2 > 0 and math.max(0, math.min(1, -(ax * sx + ay * sy) / l2)) or 0
      local qx, qy = ax + sx * f, ay + sy * f
      local d = math.sqrt(qx * qx + qy * qy)
      if not bdd or d < bdd then bi, bdd, bf = i, d, f end
    end
    return bi, bdd, bf
  end
  local i0, bd, f0
  if R.navIdx and R.navPts == pts then i0, bd, f0 = nearest(math.max(1, R.navIdx - 30), R.navIdx + 400) end
  if not i0 or bd > 40 then i0, bd, f0 = nearest(1, #pts - 1) end
  R.navPts = pts
  if not i0 or bd > 120 then
    if R.navIdx then log('I', logTag, string.format('navi: off the route (%.0f m)', bd or -1)) end
    R.navIdx = nil; R.nav = nil; return
  end
  R.navIdx = i0
  local last = pts[#pts]
  local toEnd = 0
  -- (along the route: the rest of this segment, then on)
  local acc = hav(pts[i0][1], pts[i0][2], pts[i0 + 1][1], pts[i0 + 1][2]) * (1 - (f0 or 0))
  local turn
  for i = i0 + 1, #pts - 1 do
    -- (2026-11-08: each stretch was counted twice – "in 600 Metern" came 300 m before the turn, "jetzt" after it)
    if i > i0 + 1 then acc = acc + hav(pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2]) end
    if acc > NAV.LOOK_M then break end
    if R.navRingPts ~= pts then R.navRingPts, R.navRings = pts, {} end
    local inRing = false
    for _, rg in ipairs(R.navRings) do if i > rg[1] and i <= rg[2] then inRing = true end end
    local a, b = pointAway(pts, i, 25, -1), pointAway(pts, i, 25, 1)
    if not inRing and a and b and a ~= pts[i] and b ~= pts[i] then
      local h1 = bearing(a[1], a[2], pts[i][1], pts[i][2])
      local h2 = bearing(pts[i][1], pts[i][2], b[1], b[2])
      local d = (h2 - h1 + 540) % 360 - 180
      local ring = math.abs(d) > NAV.TURN_DEG and L.navRoundabout(pts, i) or nil
      if ring then
        R.navRings[#R.navRings + 1] = { i, ring }
        turn = { dist = acc, deg = d, key = string.format('%.5f,%.5f', pts[i][1], pts[i][2]), ring = true }
        break
      end
      -- (from 12°: leaving a main road at a fork or a slip road is a small bend; L.navManeuver decides)
      local isJ = false
      if math.abs(d) > NAV.MIN_DEG then
        isJ = L.navManeuverAt(pts, pts[i], h1, h2)
        if isJ == 'busy' then return end             -- (the rest next time; what is on the display stays)
      end
      -- (the roads there not loaded yet: only what is clearly a turn)
      if isJ or (isJ == nil and math.abs(d) >= NAV.UNKNOWN_DEG) then
        -- (the corner has several route points: within 60 m of the last turn it is the same turn, one key)
        local key = string.format('%.5f,%.5f', pts[i][1], pts[i][2])
        local lt = R.navTurn
        if lt and hav(lt.lat, lt.lon, pts[i][1], pts[i][2]) < 60 then key = lt.key
        else R.navTurn = { lat = pts[i][1], lon = pts[i][2], key = key } end
        turn = { dist = acc, deg = d, key = key }
        break
      end
    end
  end
  toEnd = hav(p.lat, p.lon, last[1], last[2])
  local cue
  if toEnd < 60 then
    cue = { key = 'end', stage = 0, dir = 'end', text = 'Sie haben Ihr Ziel erreicht', dist = toEnd, sound = 'end' }
  elseif turn then
    local ad = math.abs(turn.deg)
    local side = turn.deg > 0 and 'rechts' or 'links'
    local what = turn.ring and 'in den Kreisverkehr' or (ad > 150 and 'bitte wenden' or (ad < 60 and ('halb ' .. side .. ' halten') or (side .. ' abbiegen')))
    local stage
    -- ("jetzt" a few seconds before it, however fast: at 90 km/h 45 m were not two seconds)
    local v0 = playerVeh()
    local nowM = math.max(NAV.STAGES[3], math.min(NAV.NOW_MAX_M, (v0 and vehSpeed(v0) or 0) * NAV.NOW_S))
    for k, s in ipairs(NAV.STAGES) do if turn.dist <= (k == 3 and nowM or s) then stage = k end end
    if stage then
      local m = math.max(50, math.min(600, math.floor(turn.dist / 50 + 0.5) * 50))
      local text = stage == #NAV.STAGES and ('Jetzt ' .. what) or string.format('In %d Metern %s', m, what)
      -- (the recorded phrase: art/sound/fernfahrer/nav, tools/build_voice.ps1)
      local act = turn.ring and 'K' or (ad > 150 and 'U' or ((ad < 60 and 'H' or '') .. (turn.deg > 0 and 'R' or 'L')))
      cue = { key = turn.key, stage = stage, dir = turn.ring and 'roundabout' or ad > 150 and 'uturn' or (turn.deg > 0 and (ad < 60 and 'slightRight' or 'right') or (ad < 60 and 'slightLeft' or 'left')),
        text = text, dist = turn.dist, sound = stage == #NAV.STAGES and ('now_' .. act) or ('d' .. m .. '_' .. act) }
    else
      cue = { key = turn.key, stage = 0, dir = turn.deg > 0 and 'right' or 'left', text = nil, dist = turn.dist }
    end
  end
  if cue then
    local id = cue.key .. ':' .. cue.stage
    if cue.text and id ~= (R.nav and R.nav.spokenId) then cue.say, cue.spokenId = true, id else cue.spokenId = R.nav and R.nav.spokenId end
    -- (said once: the id stays, say only goes out with the first payload after it changed)
    if cue.say then
      R.navSayId = (R.navSayId or 0) + 1
      -- spoken by the game's audio (the UI's browser has no speech voices: the HUD stayed silent, 2026-11-03)
      if cue.sound and S.settings.navSound ~= false then M.navSay(cue.sound) end
      log('I', logTag, string.format('navi: "%s" (%s, %.0f m)', tostring(cue.text), tostring(cue.sound), cue.dist or -1))
    end
    cue.sayId = R.navSayId
  end
  R.nav = cue
end

------------------------------------------------------------------------------------------
-- the company network: real places around the home (BeamNG.Earth geocoder: Photon / OpenStreetMap)

local function nextReqId()
  R.reqId = R.reqId + 1
  return C.ID_BASE + R.reqId
end

local function geocode(q, lat, lon)
  local core = earthCore()
  if not core or not core.requestGeocode then return nil, 'offline' end
  local id = nextReqId()
  if not core.requestGeocode(id, q, lat, lon) then return nil, 'offline' end
  local res = waitFor(function() return core.takeGeocode(id) end, 10)
  if not res then return nil, 'timeout' end
  if res.error then
    log('W', logTag, 'geocode "' .. q .. '": ' .. tostring(res.error))
    return nil, tostring(res.error)
  end
  local results = type(res.results) == 'table' and res.results or {}
  if not R.loggedGeocode and #results > 0 then
    R.loggedGeocode = true
    log('I', logTag, 'geocode sample (' .. q .. '): ' .. dumps(results[1]))
  end
  return results
end

local function sleep(s) waitFor(function() return false end, s) end

-- a geocoder hit that is the kind of place asked for (not a street named after it, not a town)
local NOT_PLACES = { street = 1, residential = 1, primary = 1, secondary = 1, tertiary = 1, unclassified = 1,
  service = 1, track = 1, footway = 1, path = 1, road = 1, motorway = 1, trunk = 1, living_street = 1, pedestrian = 1,
  cycleway = 1, city = 1, town = 1, village = 1, hamlet = 1, suburb = 1, locality = 1, county = 1, state = 1,
  country = 1, district = 1, postcode = 1, bus_stop = 1, isolated_dwelling = 1, neighbourhood = 1 }
local STREETS = { 'stra[sß]+e%s*%d*$', 'str%.%s*%d*$', 'weg%s*%d*$', 'allee%s*%d*$', 'gasse%s*%d*$', 'damm%s*%d*$',
  'ring%s*%d*$', 'platz%s*%d*$', 'ufer%s*%d*$', 'chaussee%s*%d*$', ' street$', ' road$', ' lane$' }

function L.hitKind(r)
  local k = r.kind or r.osm_value or r.type or r.category
  return k and tostring(k):lower() or nil
end

local function plausible(r, t)
  local kind = L.hitKind(r)
  if kind and NOT_PLACES[kind] then return false end
  local name = tostring(r.name or ''):lower()
  for _, p in ipairs(STREETS) do if name:find(p) then return false end end
  if t.strict and kind then
    local ok = false
    for _, k in ipairs(t.kinds or {}) do if kind:find(k, 1, true) then ok = true end end
    return ok
  end
  return true
end

-- a place of the type (per region: at most DEPOTS_PER_TYPE of a type within REGION_KM)
-- (2026-11-08) real places under made-up names (names.lua). The same place always gets the same name.
L.names = require('fernfahrer/names')
function L.neutralName(typeKey, real, detail, lat, lon)
  if R.nameFor ~= S then
    R.nameFor, R.nameUsed, R.nameBy = S, {}, {}
  end
  local key = string.format('%s|%.5f|%.5f', tostring(typeKey), lat or 0, lon or 0)
  if R.nameBy[key] then return R.nameBy[key] end
  local function townFn(la, lo)
    local ok, pl = pcall(streets.placeAt, la, lo, true)
    return ok and pl and pl.name or nil
  end
  local name = L.names.make(typeKey, real, detail, lat, lon, townFn, R.nameUsed)
  R.nameBy[key] = name
  return name
end
-- (a save from before: its places renamed once, the running job with them)
function L.neutralizeSave()
  if not S or S.namesV == 1 or type(S.depots) ~= 'table' then return end
  local byId = {}
  for _, d in ipairs(S.depots) do
    d.name = L.neutralName(d.type, d.name, d.detail, d.lat, d.lon)
    byId[d.id] = d.name
  end
  local j = S.job
  if j then
    if j.from and byId[j.from.id] then j.from.name = byId[j.from.id] end
    if j.to and byId[j.to.id] then j.to.name = byId[j.to.id] end
  end
  S.namesV = 1
end
local function addDepot(typeKey, name, detail, lat, lon)
  local n = 0
  for _, d in ipairs(S.depots) do
    if d.type == typeKey then
      local dd = haversine(d.lat, d.lon, lat, lon)
      if dd < C.DEDUP_M then return false end
      if dd < C.REGION_KM * 1000 then n = n + 1 end
    end
  end
  if n >= C.DEPOTS_PER_TYPE then return false end
  S.nextDepot = (S.nextDepot or 0) + 1
  table.insert(S.depots, { id = S.nextDepot, type = typeKey, name = L.neutralName(typeKey, name, detail, lat, lon), detail = detail, lat = lat, lon = lon })
  return true
end

local function countOf(typeKey, near, km)
  local n = 0
  for _, d in ipairs(S.depots) do
    if d.type == typeKey and (not near or haversine(near.lat, near.lon, d.lat, d.lon) <= km * 1000) then n = n + 1 end
  end
  return n
end

local function cargoDepotsNear(p, km)
  local n = 0
  for _, d in ipairs(S.depots) do
    local t = DEPOT_BY_KEY[d.type]
    if t and not t.facility and haversine(p.lat, p.lon, d.lat, d.lon) <= km * 1000 then n = n + 1 end
  end
  return n
end

-- Search real places around `center` with the BeamNG.Earth geocoder (Photon, a free public service): one request at
-- a time with a gap between them, and a long pause when the server reports it overloaded ("circuit open": four in
-- parallel tripped it, 2026-11-02, and every search came back empty). opts: types (keys; default all enabled),
-- onlyMissing (types with none near the center yet), ring (also 12 km out, for the freight types), label.
-- The places shipped with the mod (/fernfahrer/places/<lat>_<lon>.json, one per 1-degree tile, built from
-- OpenStreetMap with the session's tools/build_places.js): read for the tiles within radiusKm of the center.
-- Returns the number of places added. The online geocoder only fills the gaps (it answered HTTP 403, 2026-11-02).
local function loadShippedPlaces(center, radiusKm)
  local dLat = radiusKm / 111
  local dLon = radiusKm / (111 * math.max(0.2, math.cos(math.rad(center.lat))))
  local cands = {}
  for la = math.floor(center.lat - dLat), math.floor(center.lat + dLat) do
    for lo = math.floor(center.lon - dLon), math.floor(center.lon + dLon) do
      local tile = jsonReadFile(string.format('/fernfahrer/places/%d_%d.json', la, lo))
      for _, p in ipairs(type(tile) == 'table' and tile.places or {}) do
        local lat, lon = tonumber(p[3]), tonumber(p[4])
        local def = DEPOT_BY_KEY[p[1]]
        if def and def.enabled ~= false and lat and lon and haversine(center.lat, center.lon, lat, lon) <= radiusKm * 1000 then
          table.insert(cands, p)
        end
      end
    end
  end
  -- shuffled: the per-region cap then keeps places from all over the area, not the first ones in the file
  for i = #cands, 2, -1 do
    local j = math.random(i)
    cands[i], cands[j] = cands[j], cands[i]
  end
  -- (2026-11-09: the tiles hold thousands of places now and each try walks all the known ones: only a few per type are tried)
  local added, tried, limit = 0, {}, C.DEPOTS_PER_TYPE * 3
  for _, p in ipairs(cands) do
    tried[p[1]] = (tried[p[1]] or 0) + 1
    if tried[p[1]] <= limit and addDepot(p[1], p[2], p[5] ~= '' and p[5] or nil, tonumber(p[3]), tonumber(p[4])) then added = added + 1 end
  end
  return added
end
M.loadShippedPlaces = loadShippedPlaces

-- Where the shipped company data has gaps (2026-11-05: a yard anywhere in Germany and around – the OSM data is not
-- everywhere yet): generic places at the real towns around (GeoNames, /fernfahrer/towns), so every region has a
-- network – a logistics centre, a trading estate, a builders' merchant … at a town of some size; a rest area, a fuel
-- stop and a workshop as well. Only for the kinds still missing within REGION_KM.
-- (2026-11-05, denser: not only where a kind is missing altogether – every kind up to `want` within REGION_KM, spread
-- over the towns and over a big city's districts (GeoNames PPLX "suburb"), nearer ones first; made-up company names)
-- { kind, the smallest place it stands at (inhabitants; districts always), how many within REGION_KM, names }
L.SYNTH = {
  { 'logistics', 3000, 6, { 'Logistikzentrum %s', 'Spedition %s', 'Cargo-Center %s', '%s Distribution GmbH', 'Umschlaglager %s', 'Transportlogistik %s' } },
  { 'industry', 2000, 6, { 'Gewerbegebiet %s', 'Industriepark %s', 'Metallwerk %s', 'Kunststofftechnik %s', '%s Maschinenbau AG', 'Werk %s' } },
  { 'supermarket', 5000, 4, { 'Zentrallager %s', 'Frischemarkt %s', 'Lebensmittel-Großhandel %s', 'Verbrauchermarkt %s' } },
  { 'building', 2000, 4, { 'Baustoffhandel %s', 'Baustoff-Zentrum %s', 'Holz & Baustoffe %s', 'Betonwerk %s' } },
  { 'farm', 300, 3, { 'Landhandel %s', 'Kornspeicher %s', 'Agrarzentrum %s' } },
  { 'hardware', 5000, 3, { 'Baumarkt %s', 'Heimwerkermarkt %s' } },
  { 'drinks', 3000, 3, { 'Getränkegroßhandel %s', 'Brauerei %s', 'Getränke-Logistik %s' } },
  { 'timber', 300, 2, { 'Sägewerk %s', 'Holzhandel %s' } },
  { 'post', 15000, 2, { 'Paketzentrum %s', 'Brief- und Paketverteilung %s' } },
  { 'furniture', 8000, 2, { 'Möbellager %s', 'Einrichtungshaus %s' } },
  { 'dairy', 800, 2, { 'Molkerei %s', 'Käserei %s' } },
  { 'port', 50000, 1, { 'Containerterminal %s', 'Binnenhafen %s' } },
  -- (2026-11-07: the dangerous goods' and the steel's places)
  { 'tankfarm', 20000, 2, { 'Tanklager %s', 'Mineralöl-Depot %s', 'Treibstofflager %s' } },
  { 'chemical', 30000, 1, { 'Chemiepark %s', 'Chemiewerk %s' } },
  { 'steel', 30000, 1, { 'Stahlwerk %s', 'Stahlhandel %s', 'Walzwerk %s' } },
  { 'scrap', 8000, 2, { 'Autoverwertung %s', 'Schrotthandel %s', 'Autoteile & Recycling %s' } },
  { 'cardealer', 8000, 3, { 'Autohaus %s', 'Auto-Zentrum %s', 'Fahrzeughandel %s' } },
  { 'fuel', 2000, 4, { 'Autohof %s', 'Truck-Stop %s', 'Tankhof %s' } },
  { 'rest', 300, 3, { 'Rastplatz bei %s', 'Parkplatz %s', 'Autohof-Parkplatz %s' } },
  { 'workshop', 4000, 2, { 'LKW-Service %s', 'Nutzfahrzeug-Werkstatt %s' } },
}
function L.synthPlaces(center, radiusKm)
  local towns = {}
  local dLat = radiusKm / 111
  local dLon = radiusKm / (111 * math.max(0.2, math.cos(math.rad(center.lat))))
  for la = math.floor(center.lat - dLat), math.floor(center.lat + dLat) do
    for lo = math.floor(center.lon - dLon), math.floor(center.lon + dLon) do
      local tile = jsonReadFile(string.format('/fernfahrer/towns/%d_%d.json', la, lo))
      for _, s in ipairs(type(tile) == 'table' and tile.list or {}) do
        local d = haversine(center.lat, center.lon, s[3], s[4])
        if d <= radiusKm * 1000 and d > 800 then
          towns[#towns + 1] = { name = s[1], kind = s[2], lat = s[3], lon = s[4], pop = s[5] or 0, d = d, k = d * (0.4 + math.random()) }
        end
      end
    end
  end
  if #towns == 0 then return 0 end
  -- (the inner cities stay free: no depot within 3 km of a big city's centre – they stand at the edges of town)
  local cities = {}
  for _, tw in ipairs(towns) do if tw.kind == 'city' or tw.pop >= 100000 then cities[#cities + 1] = tw end end
  local function inner(tw)
    for _, c in ipairs(cities) do if c ~= tw and haversine(c.lat, c.lon, tw.lat, tw.lon) < 3000 then return true end end
    return tw.kind == 'city'
  end
  local added, used, placed = 0, {}, {}
  for _, sp in ipairs(L.SYNTH) do
    local key, minPop, want, names = sp[1], sp[2], sp[3], sp[4]
    local def = DEPOT_BY_KEY[key]
    if def and def.enabled ~= false then
      local need = want - countOf(key, center, C.REGION_KM)
      placed[key] = placed[key] or {}
      -- (spread out: one per distance ring around the centre, nearer rings first; 3.5 km apart at least)
      for j = 1, math.max(0, need) do
        local band = 1500 + (radiusKm * 1000 - 1500) * 0.85 * (j - 0.5) / need
        local best, bs
        for _, tw in ipairs(towns) do
          local okSize = tw.kind == 'suburb' or tw.pop >= minPop or tw.kind == 'town'
          local uk = key .. '|' .. tw.name
          if okSize and not used[uk] and (used[tw.name] or 0) < 3 and not inner(tw) then
            local far = true
            for _, q in ipairs(placed[key]) do if haversine(q.lat, q.lon, tw.lat, tw.lon) < 3500 then far = false; break end end
            if far then
              local sc = math.abs(tw.d - band) + math.random() * 4000
              if not bs or sc < bs then best, bs = tw, sc end
            end
          end
        end
        if not best then break end
        local la, lo = L.destPoint(best.lat, best.lon, (#key * 47 + added * 73) % 360, 300 + (added % 4) * 140)
        local name = string.format(names[(added % #names) + 1], best.name)
        used[key .. '|' .. best.name] = true
        if addDepot(key, name, best.name, la, lo) then
          added = added + 1
          used[best.name] = (used[best.name] or 0) + 1
          table.insert(placed[key], best)
        end
      end
    end
  end
  return added
end

-- (2026-11-07) the wide network: companies, fuel stations, rest areas and workshops at every bigger city within
-- WIDE_KM of the home, not only where the player has been – the office's map shows Hamburg's before one gets there,
-- and a long haul ends where there are loads to take. Built once per career (S.wideNet), in the background, a city
-- per frame or two: the shipped OSM places there, then the generated ones for the gaps.
L.WIDE_KM, L.WIDE_CITY_KM, L.WIDE_MIN_POP, L.WIDE_VERSION = 650, 14, 80000, 3
function L.buildWideNet()
  if not S or not S.home or (S.wideNet or 0) >= L.WIDE_VERSION or R.wideNetTask then return end
  R.wideNetTask = true
  runTask(function()
    local home = S.home
    local centers, seen = {}, {}
    local function addCenter(name, lat, lon)
      if not lat or not lon then return end
      local d = haversine(home.lat, home.lon, lat, lon)
      if d > L.WIDE_KM * 1000 or d < 25000 then return end           -- (the home's own region has its network)
      for _, c in ipairs(centers) do if haversine(c.lat, c.lon, lat, lon) < 18000 then return end end
      centers[#centers + 1] = { name = name, lat = lat, lon = lon, d = d }
    end
    for _, c in ipairs(citiesData.LIST) do addCenter(c[1], c[2], c[3]) end
    -- (the bigger towns too: GeoNames tiles around the home, a tile per frame)
    local dLat = L.WIDE_KM / 111
    local dLon = L.WIDE_KM / (111 * math.max(0.2, math.cos(math.rad(home.lat))))
    for la = math.floor(home.lat - dLat), math.floor(home.lat + dLat) do
      for lo = math.floor(home.lon - dLon), math.floor(home.lon + dLon) do
        local path = string.format('/fernfahrer/towns/%d_%d.json', la, lo)
        if FS:fileExists(path) then
          local tile = jsonReadFile(path)
          for _, s in ipairs(type(tile) == 'table' and tile.list or {}) do
            if (s[5] or 0) >= L.WIDE_MIN_POP then addCenter(s[1], s[3], s[4]) end
          end
          coroutine.yield()
        end
      end
    end
    table.sort(centers, function(a, b) return a.d < b.d end)
    local before = #S.depots
    for i, c in ipairs(centers) do
      pcall(loadShippedPlaces, c, L.WIDE_CITY_KM)
      pcall(L.synthPlaces, c, L.WIDE_CITY_KM)
      coroutine.yield()
      if i % 10 == 0 then coroutine.yield() end
    end
    -- (2026-11-08) the network along the roads, not only at the cities: fuel stations, rest areas and workshops of every
    -- tile in reach, one of a kind per cell of about 14 x 20 km – the places nearer by come in as one drives (discoverRegion)
    do
      local STOP, cells = { fuel = true, rest = true, workshop = true }, {}
      local function cell(t, la, lo) return t .. ':' .. math.floor(la / 0.2) .. ':' .. math.floor(lo / 0.3) end
      for _, d in ipairs(S.depots) do if STOP[d.type] then cells[cell(d.type, d.lat, d.lon)] = true end end
      local reach, added = L.WIDE_KM * 1000, 0
      for la = math.floor(home.lat - dLat), math.floor(home.lat + dLat) do
        for lo = math.floor(home.lon - dLon), math.floor(home.lon + dLon) do
          local path = string.format('/fernfahrer/places/%d_%d.json', la, lo)
          if FS:fileExists(path) then
            local tile = jsonReadFile(path)
            for _, p in ipairs(type(tile) == 'table' and tile.places or {}) do
              local plat, plon = tonumber(p[3]), tonumber(p[4])
              local def = DEPOT_BY_KEY[p[1]]
              if STOP[p[1]] and def and def.enabled ~= false and plat and plon and not cells[cell(p[1], plat, plon)]
                 and haversine(home.lat, home.lon, plat, plon) <= reach then
                cells[cell(p[1], plat, plon)] = true
                S.nextDepot = (S.nextDepot or 0) + 1
                local detail = p[5] ~= '' and p[5] or nil
                table.insert(S.depots, { id = S.nextDepot, type = p[1], name = L.neutralName(p[1], p[2], detail, plat, plon), detail = detail, lat = plat, lon = plon })
                added = added + 1
              end
            end
            coroutine.yield()
          end
        end
      end
      log('I', logTag, string.format('wide network: %d stops along the roads', added))
    end
    S.wideNet = L.WIDE_VERSION
    R.wideNetTask = nil
    log('I', logTag, string.format('wide network: %d cities, %d places added (%d in all)', #centers, #S.depots - before, #S.depots))
    save()
  end)
end

function M.discoverAround(center, opts)
  if not center or (R.discover and R.discover.running) then return end
  opts = opts or {}
  -- first what the mod brings; the geocoder only for the types still missing there
  local shipped = loadShippedPlaces(center, opts.radiusKm or C.HOME_RADIUS_KM)
  local okS, synth = pcall(L.synthPlaces, center, opts.radiusKm or C.HOME_RADIUS_KM)
  if okS and synth > 0 then
    log('I', logTag, string.format('discovery %s: %d generic places at the towns around (gaps in the OSM data)', tostring(opts.label), synth))
    shipped = shipped + synth
  end
  if shipped > 0 then
    log('I', logTag, string.format('discovery %s: %d places from the shipped OSM data', tostring(opts.label), shipped))
    opts.onlyMissing = true
    R.offers = {}
    save()
  end
  if R.geocodeBlocked then
    if opts.label == 'home' then
      S.netVersion = C.NET_VERSION
      story(cargoDepotsNear(center, opts.radiusKm or C.HOME_RADIUS_KM) >= 6 and 'network' or 'networkPoor', { n = #S.depots })
    end
    return
  end
  local wanted
  if opts.types then wanted = {}; for _, k in ipairs(opts.types) do wanted[k] = true end end
  local radiusM = (opts.radiusKm or C.HOME_RADIUS_KM) * 1000
  local jobs = {}
  for _, t in ipairs(DEPOT_TYPES) do
    if t.enabled ~= false and (not wanted or wanted[t.key])
        and (not opts.onlyMissing or countOf(t.key, center, C.REGION_KM) == 0) then
      table.insert(jobs, { t = t, q = t.queries[1], qi = 1, p = { center.lat, center.lon } })
      if opts.ring and not t.facility then
        local b = math.random() * 360
        for k = 0, 1 do
          local la, lo = L.destPoint(center.lat, center.lon, b + k * 180, 12000)
          table.insert(jobs, { t = t, q = t.queries[1], qi = 1, p = { la, lo } })
        end
      end
    end
  end
  if #jobs == 0 then
    if opts.label == 'home' then
      S.netVersion = C.NET_VERSION
      if shipped > 0 then story('network', { n = #S.depots }) end
      save()
    end
    return
  end
  R.discover = { running = true, done = 0, total = #jobs, found = 0, label = opts.label }
  runTask(function()
    local i, fails, pauses = 1, 0, 0
    while i <= #jobs do
      local j = jobs[i]
      local results, err = geocode(j.q, j.p[1], j.p[2])
      if results == nil and tostring(err):find('HTTP 403', 1, true) then
        R.geocodeBlocked = true                  -- the public service refuses us: no point asking again this session
        log('W', logTag, 'geocoder refuses requests (HTTP 403): only the shipped places are used')
        break
      end
      if results == nil then
        fails = fails + 1
        if err == 'offline' or fails >= 3 then
          if pauses >= 3 then break end
          pauses, fails = pauses + 1, 0
          R.discover.paused = true
          sleep(C.GEOCODE_PAUSE_S)
          R.discover.paused = nil
        else
          sleep(C.GEOCODE_GAP_S * 3)
        end
      else
        fails = 0
        local found = 0
        for _, r in ipairs(results) do
          local la, lo = tonumber(r.lat), tonumber(r.lon)
          if la and lo and haversine(center.lat, center.lon, la, lo) <= radiusM and plausible(r, j.t)
              and addDepot(j.t.key, r.name or j.t.name, r.detail, la, lo) then
            found = found + 1
          end
        end
        R.discover.found = R.discover.found + found
        -- nothing under this wording here: the type's next wording, once
        if found == 0 and j.t.queries[j.qi + 1] then
          table.insert(jobs, { t = j.t, q = j.t.queries[j.qi + 1], qi = j.qi + 1, p = j.p })
          R.discover.total = R.discover.total + 1
        end
        R.discover.done = R.discover.done + 1
        i = i + 1
        sleep(C.GEOCODE_GAP_S)
      end
    end
    R.discover.running = false
    local n = cargoDepotsNear(center, opts.radiusKm or C.HOME_RADIUS_KM)
    log('I', logTag, string.format('discovery %s: %d new places, %d freight depots in reach, %d places total',
      tostring(opts.label), R.discover.found, n, #S.depots))
    if opts.label == 'home' then
      if n < 6 then
        story('networkPoor', { n = n })
        R.discoverRetryAt = now() + 180          -- the geocoder may be busy: again in a few minutes
      else
        story('network', { n = #S.depots })
      end
      S.netVersion = C.NET_VERSION
    end
    R.offers = {}
    save()
  end)
end

function M.discoverDepots(onlyMissing)
  if S and S.home then M.discoverAround(S.home, { onlyMissing = onlyMissing, ring = true, label = 'home' }) end
end

-- freight depots around wherever the player is (after a long haul): the market there
local function discoverRegion(p)
  local types = {}
  for _, t in ipairs(DEPOT_TYPES) do if not t.facility or t.key == 'fuel' then table.insert(types, t.key) end end
  M.discoverAround(p, { types = types, onlyMissing = true, radiusKm = C.REGION_KM, label = 'region' })
end

local function placeView(d)
  if not d then return nil end
  local t = DEPOT_BY_KEY[d.type]
  return { id = d.id, name = d.name, detail = d.detail, lat = d.lat, lon = d.lon, type = d.type,
    typeName = t and t.name or d.type, icon = t and t.icon or '📍', facility = t and t.facility or false,
    discovered = S.discovered[tostring(d.id)] or nil, pending = d.pending, city = d.city }
end

local function nearestOf(typeKey, from)
  from = from or here()
  if not from then return nil end
  local best, bd
  for _, d in ipairs(S.depots) do
    if d.type == typeKey then
      local dd = haversine(from.lat, from.lon, d.lat, d.lon)
      if not bd or dd < bd then best, bd = d, dd end
    end
  end
  return best, bd
end

------------------------------------------------------------------------------------------
-- freight market (offers expire and new ones come in, as at a real freight exchange)

function L.depotsOf(types)
  local set, out = {}, {}
  for _, t in ipairs(types) do set[t] = true end
  for _, d in ipairs(S.depots) do if set[d.type] then table.insert(out, d) end end
  return out
end

local function pickDepot(types, near, maxM, exclude)
  local list = {}
  for _, d in ipairs(L.depotsOf(types)) do
    local dd = haversine(near.lat, near.lon, d.lat, d.lon)
    if d ~= exclude and (not maxM or dd <= maxM) then table.insert(list, { d = d, w = 1 / (1 + dd / 5000) }) end
  end
  if #list == 0 then return nil end
  local sum = 0
  for _, x in ipairs(list) do sum = sum + x.w end
  local r = math.random() * sum
  for _, x in ipairs(list) do r = r - x.w; if r <= 0 then return x.d end end
  return list[#list].d
end

local function makeOffer(cargo, from, to, start, long)
  local km = haversine(from.lat, from.lon, to.lat, to.lon) / 1000 * 1.3
  local pickupKm = haversine(start.lat, start.lon, from.lat, from.lon) / 1000 * 1.3
  local urgent = math.random() < (long and 0.1 or 0.2)
  local avail = L.trailersOf(cargo)
  if #avail == 0 then avail = cargo.trailers end
  local trailer = avail[math.random(#avail)]
  local tinfo = L.trailerInfo(trailer[1], trailer[2])
  local freight = round((C.BASE_PAY + km * C.PAY_PER_KM) * (cargo.mult or 1) * (urgent and 1.25 or 1) * (L.hasUp('warehouse') and 1.06 or 1), 10)
  local hours = long and ((km + pickupKm) / C.LONG_KMH * 1.4 + 0.5) or ((km + pickupKm) / 45 * (urgent and 1.25 or 1.6) + 1 / 6)
  return {
    id = nextReqId(), cargo = cargo.key, cargoName = cargo.name, icon = cargo.icon, tons = cargo.t, urgent = urgent,
    fragile = cargo.fragile, long = long or nil, adr = cargo.adr or nil, secure = cargo.secure or nil,
    trailer = { model = trailer[1], config = trailer[2], name = tinfo.name, preview = tinfo.preview },
    from = placeView(from), to = placeView(to), distKm = round(km, 0.1), pickupKm = round(pickupKm, 0.1),
    freight = freight, xp = round(150 + km * 12),
    deadline = round(hours * 3600, 60),
    expires = now() + 60 * (C.OFFER_TTL_MIN[1] + math.random() * (C.OFFER_TTL_MIN[2] - C.OFFER_TTL_MIN[1])) * (long and 1.5 or 1),
  }
end

-- a long haul from `from` to a city 80-600 km away: a known depot of the receiving kind there, else the city itself
-- (the real depot is looked up when the job is taken: resolveDestination)
local function longOffer(cargo, from, start)
  local cands = {}
  for _, c in ipairs(citiesData.LIST) do
    local d = haversine(from.lat, from.lon, c[2], c[3])
    if d >= C.LONG_MIN_KM * 1000 and d <= C.LONG_MAX_KM * 1000 then table.insert(cands, c) end
  end
  if #cands == 0 then return nil end
  local city = cands[math.random(#cands)]
  local cp = { lat = city[2], lon = city[3] }
  local to = pickDepot(cargo.to, cp, 25000)
  if not to then
    local t = DEPOT_BY_KEY[cargo.to[math.random(#cargo.to)]]
    if not t then return nil end
    to = { id = 'city:' .. city[1] .. ':' .. t.key, type = t.key, name = t.name .. ' ' .. city[1], detail = city[1],
      lat = city[2], lon = city[3], pending = true, city = city[1] }
  end
  return makeOffer(cargo, from, to, start, true)
end

-- (2026-11-07) a trailer's name and photo for the offers (the game's own picture of that configuration)
L.TRAILER_KIND = { dryvan = 'Koffer-Auflieger', eu_trailers = 'Auflieger', tanker = 'Tank-Auflieger', flatbed = 'Pritschen-Auflieger',
  containerTrailer = 'Container-Chassis', log_trailer = 'Langholz-Auflieger' }
L.trailerInfoCache = {}
function L.trailerInfo(model, config)
  local key = tostring(model) .. '/' .. tostring(config)
  if L.trailerInfoCache[key] then return L.trailerInfoCache[key] end
  local info = { name = L.TRAILER_KIND[model] or 'Auflieger' }
  pcall(function()
    local full = core_vehicles.getModel(model)
    local cfg = full and full.configs and full.configs[config]
    if cfg then
      info.preview = cfg.preview
      local cn = tr(cfg.Configuration, nil)
      if cn and cn ~= '' then info.name = info.name .. ' · ' .. cn end
    end
  end)
  if not info.preview then
    for _, ext in ipairs({ '.jpg', '.png' }) do
      local p = '/vehicles/' .. model .. '/' .. config .. ext
      if FS:fileExists(p) then info.preview = p; break end
    end
  end
  L.trailerInfoCache[key] = info
  return info
end

-- (2026-11-07) a cargo's trailers that are installed (a mod's car transporter, say, only when that mod is there)
L.trailerOk = {}
function L.trailersOf(c)
  local out = {}
  for _, tr in ipairs(c.trailers or {}) do
    local ok = L.trailerOk[tr[1]]
    if ok == nil then
      ok = (core_vehicles and core_vehicles.getModel and core_vehicles.getModel(tr[1])) and true or false
      L.trailerOk[tr[1]] = ok
    end
    if ok then out[#out + 1] = tr end
  end
  return out
end

local function enabledCargo(fromType)
  local out = {}
  for _, c in ipairs(CARGO) do
    if c.enabled ~= false and not c.special and #L.trailersOf(c) > 0 then
      local ok = not fromType
      for _, t in ipairs(fromType and c.from or {}) do if t == fromType then ok = true end end
      if ok then table.insert(out, c) end
    end
  end
  return out
end

local function topUpOffers(townFirst)
  if not S or not S.home then return end
  local start = here() or S.home
  local enabled = enabledCargo()
  if #enabled == 0 then return end
  local localDepots = cargoDepotsNear(start, C.PICKUP_MAX_KM) > 0
  -- far from any known depot (after a long haul): return loads from where the last load went, home or onward
  local origin = not localDepots and R.lastDelivery and dist(start, R.lastDelivery) < 5000 and R.lastDelivery or nil
  -- (as in ETS2: after a delivery the next loads wait at companies in the same town – a few km: those first)
  if townFirst and localDepots then
    -- (the old offers far from here go: the market is this town's now – the list grew with every delivery)
    for i = #R.offers, 1, -1 do
      local o = R.offers[i]
      if not o.special and o.from and o.from.lat and haversine(start.lat, start.lon, o.from.lat, o.from.lon) > C.PICKUP_MAX_KM * 1000 then
        table.remove(R.offers, i)
      end
    end
    while #R.offers > C.OFFERS + (L.hasUp('warehouse') and 3 or 0) do
      local far, fi = -1, nil
      for i, o in ipairs(R.offers) do if not o.special and (o.pickupKm or 0) > far then far, fi = o.pickupKm or 0, i end end
      if not fi then break end
      table.remove(R.offers, fi)
    end
    local town = 0
    for _ = 1, 16 do
      if town >= 4 then break end
      local cargo = enabled[math.random(#enabled)]
      local from = pickDepot(cargo.from, start, 6000)
      if from then
        local o
        if math.random() < C.LONG_SHARE then o = longOffer(cargo, from, start)
        else
          local to = pickDepot(cargo.to, from, C.HOME_RADIUS_KM * 2000, from)
          if to and haversine(from.lat, from.lon, to.lat, to.lon) >= C.MIN_TRIP_KM * 1000 then o = makeOffer(cargo, from, to, start) end
        end
        if o then table.insert(R.offers, o); town = town + 1 end
      end
    end
  end
  local tries = 0
  while #R.offers < C.OFFERS + (L.hasUp('warehouse') and 3 or 0) and tries < 150 do
    tries = tries + 1
    local o
    if origin then
      local list = enabledCargo(origin.type)
      local cargo = (#list > 0 and list or enabled)[math.random(#list > 0 and #list or #enabled)]
      local to = math.random() < 0.6 and pickDepot(cargo.to, S.home, C.HOME_RADIUS_KM * 1000) or nil
      o = to and makeOffer(cargo, origin, to, start, true) or longOffer(cargo, origin, start)
      if o then o.backhaul = true end
    elseif localDepots then
      local cargo = enabled[math.random(#enabled)]
      local from = pickDepot(cargo.from, start, C.PICKUP_MAX_KM * 1000)
      if from then
        if math.random() < C.LONG_SHARE then
          o = longOffer(cargo, from, start)
        else
          local to = pickDepot(cargo.to, from, C.HOME_RADIUS_KM * 2000, from)
          if to and haversine(from.lat, from.lon, to.lat, to.lon) >= C.MIN_TRIP_KM * 1000 then o = makeOffer(cargo, from, to, start) end
        end
      end
    end
    if o then table.insert(R.offers, o) end
    if not origin and not localDepots then break end
  end
  -- the standing tours (cargo.lua SPECIAL): always offered, wherever the player is, until taken
  for _, sp in ipairs(cargoData.SPECIAL or {}) do
    local have = S.job and S.job.special == sp.key
    for _, x in ipairs(R.offers) do if x.special == sp.key then have = true end end
    local cargo
    for _, c in ipairs(cargoData.CARGO) do if c.key == sp.cargo then cargo = c end end
    if not have and cargo then
      local o = makeOffer(cargo, sp.from, sp.to, start)
      o.special, o.expires, o.urgent, o.note = sp.key, nil, false, sp.note
      o.from = { id = sp.from.id, name = sp.from.name, detail = sp.from.detail, lat = sp.from.lat, lon = sp.from.lon,
        type = sp.from.type, typeName = sp.from.typeName, icon = sp.from.icon }
      o.to = { id = sp.to.id, name = sp.to.name, detail = sp.to.detail, lat = sp.to.lat, lon = sp.to.lon,
        type = sp.to.type, typeName = sp.to.typeName, icon = sp.to.icon }
      table.insert(R.offers, 1, o)
    end
  end
  table.sort(R.offers, function(a, b) return (a.long and 1 or 0) < (b.long and 1 or 0) or ((a.long and 1 or 0) == (b.long and 1 or 0) and a.pickupKm < b.pickupKm) end)
end

-- (2026-11-05) loads asked for on the spot: at a company's ring with fewer than three waiting there, some more made
-- from this company – to customers around, now and then a long haul
function L.offersAt(place)
  if not place or not place.id or S.job then return end
  local depot
  for _, d in ipairs(S.depots) do if d.id == place.id then depot = d end end
  if not depot then return end
  local have = 0
  for _, o in ipairs(R.offers) do if o.from and o.from.id == depot.id then have = have + 1 end end
  local list = enabledCargo(depot.type)
  if #list == 0 then return end
  local start = here() or depot
  for _ = 1, 12 do
    if have >= 3 then break end
    local cargo = list[math.random(#list)]
    local o
    if math.random() < C.LONG_SHARE then o = longOffer(cargo, depot, start)
    else
      local to = pickDepot(cargo.to, depot, C.HOME_RADIUS_KM * 2000, depot)
      if to and haversine(depot.lat, depot.lon, to.lat, to.lon) >= C.MIN_TRIP_KM * 1000 then o = makeOffer(cargo, depot, to, start) end
    end
    if o then o.onSite = true; table.insert(R.offers, o); have = have + 1 end
  end
end

-- (2026-11-05) the market's offers are the customers' requests to the company: once per request the driver may name
-- another price. Less is always taken (a happy customer: a little more experience); more is taken the less likely the
-- more it is; refused, the customer keeps to the price – or, asked too much, gives the load to somebody else.
function M.negotiate(id, pct)
  pct = math.max(-0.2, math.min(0.3, tonumber(pct) or 0))
  local o, idx
  for i, x in ipairs(R.offers) do if tostring(x.id) == tostring(id) then o, idx = x, i end end
  if not o then return { ok = false, msg = 'Die Anfrage gibt es nicht mehr.' } end
  if o.negotiated then return { ok = false, msg = 'Mit diesem Kunden ist schon verhandelt.' } end
  o.negotiated = true
  local from = o.from and o.from.name or 'Der Kunde'
  if pct <= 0 then
    o.freight = round(o.freight * (1 + pct), 10)
    o.xp = round((o.xp or 0) * (1 - pct * 1.5))
    return { ok = true, accepted = true, freight = o.freight, msg = string.format('%s freut sich: %s – und merkt sich das.', from, money(o.freight)) }
  end
  local chance = math.max(0.08, 1 - pct * 2.6 + (o.urgent and 0.1 or 0))
  if math.random() < chance then
    o.freight = round(o.freight * (1 + pct), 10)
    return { ok = true, accepted = true, freight = o.freight, msg = string.format('%s ist einverstanden: %s.', from, money(o.freight)) }
  end
  if pct >= 0.15 and math.random() < 0.35 then
    table.remove(R.offers, idx)
    return { ok = true, accepted = false, withdrawn = true, msg = string.format('%s hat den Auftrag an eine andere Spedition gegeben.', from) }
  end
  return { ok = true, accepted = false, freight = o.freight, msg = string.format('%s bleibt bei %s.', from, money(o.freight)) }
end

function M.refreshOffers()
  R.offers = {}
  topUpOffers()
end

function L.maintainMarket()
  local t = now()
  for i = #R.offers, 1, -1 do
    if R.offers[i].expires and R.offers[i].expires < t then table.remove(R.offers, i) end
  end
  -- somewhere new: learn the freight depots around (one request at a time, in the background)
  local p = here()
  -- (2026-11-05: also where there are only a few – Hamburg had some real places in its centre and nothing else)
  if p and S.home and not (R.discover and R.discover.running) and cargoDepotsNear(p, C.PICKUP_MAX_KM) < 8
      and (not R.regionTried or dist(p, R.regionTried) > 15000) then
    R.regionTried = p
    discoverRegion(p)
  end
  if R.discoverRetryAt and t > R.discoverRetryAt and not (R.discover and R.discover.running) then
    R.discoverRetryAt = nil
    M.discoverDepots(true)
  end
  -- (the wide network once the home's own is there)
  if S.home and (S.wideNet or 0) < L.WIDE_VERSION and not (R.discover and R.discover.running) and #S.depots > 0 then
    L.buildWideNet()
  end
  topUpOffers()
end

-- a long haul taken: the real depot of its kind in the destination city (one geocoder request)
local function resolveDestination(job)
  local to = job.to
  if not to or not to.pending then return end
  local t = DEPOT_BY_KEY[to.type]
  -- the shipped OpenStreetMap places of that city first
  local cp = { lat = to.lat, lon = to.lon }
  pcall(loadShippedPlaces, cp, 20)
  local known = pickDepot({ to.type }, cp, 20000)
  if known then
    to.lat, to.lon, to.name, to.detail, to.id = known.lat, known.lon, known.name, known.detail or to.city, known.id
    to.pending = nil
    save()
    return
  end
  if R.geocodeBlocked then to.pending = nil; return end
  runTask(function()
    local best, bd
    for _, q in ipairs(t and t.queries or {}) do
      local results = geocode(q, to.lat, to.lon)
      for _, r in ipairs(results or {}) do
        local la, lo = tonumber(r.lat), tonumber(r.lon)
        if la and lo and plausible(r, t) then
          local d = haversine(to.lat, to.lon, la, lo)
          if d < 20000 and (not bd or d < bd) then best, bd = r, d end
        end
      end
      if best then break end
      sleep(C.GEOCODE_GAP_S)
    end
    if S.job ~= job then return end
    if best then
      local la, lo = tonumber(best.lat), tonumber(best.lon)
      addDepot(to.type, best.name or to.name, best.detail or to.city, la, lo)
      to.lat, to.lon, to.name, to.detail = la, lo, L.neutralName(to.type, best.name or to.name, best.detail or to.city, la, lo), best.detail or to.city
    end
    to.pending = nil
    if job.phase == 'toDelivery' or job.phase == 'atDelivery' then navTo(to, 'Kunde: ' .. tostring(to.name)) end
    save()
  end)
end

------------------------------------------------------------------------------------------
-- trailer

function L.findTruckCoupler(id)
  for cid, tag in pairs(core_vehicles.vehsCouplerTags[id] or {}) do
    if type(tag) == 'string' and tag:find('^fifthwheel') then return cid, tag end
  end
end

function L.findKingpin(id, tag)
  local fallback
  for cid, data in pairs(core_vehicles.vehsCouplerCache[id] or {}) do
    if data.tag == tag then return cid end
    if type(data.tag) == 'string' and data.tag:find('^fifthwheel') then fallback = cid end
  end
  return fallback
end

local function isCoupled()
  return R.truckId and R.trailerId and core_trailerRespawn
    and core_trailerRespawn.isVehicleCoupledToTrailer(R.truckId, R.trailerId) or false
end

local function autoHitch()
  local truck, trailer = careerVeh(), vehById(R.trailerId)
  if not truck or not trailer then return false end
  local tcid, tag = L.findTruckCoupler(R.truckId)
  local kcid = tcid and L.findKingpin(R.trailerId, tag)
  if not tcid or not kcid then
    notify(tcid and 'Dieser Auflieger hat keinen Königszapfen – er passt nicht auf die Sattelkupplung.' or 'Dieser LKW hat keine Sattelkupplung – bitte eine Zugmaschine fahren.', 6)
    return false
  end
  spawn.placeTrailer(R.truckId, core_vehicles.vehsCouplerOffset[R.truckId][tcid], R.trailerId,
    core_vehicles.vehsCouplerOffset[R.trailerId][kcid], tag)
  truck:queueLuaCommand(string.format('beamstate.activateAutoCoupling(%q)', tag))
  return true
end

function L.parkTrailerBehind(gap)
  local truck, trailer = careerVeh(), vehById(R.trailerId)
  if not truck or not trailer then return end
  local carBB, trBB = truck:getSpawnWorldOOBB(), trailer:getSpawnWorldOOBB()
  local pos = vec3(carBB:getCenter()) - vec3(truck:getDirectionVectorUp()) * carBB:getHalfExtents().z
  local diff = vec3(trailer:getPosition()) - (vec3(trBB:getCenter()) - vec3(trailer:getDirectionVectorUp()) * trBB:getHalfExtents().z)
  local dir = vec3(truck:getDirectionVector()):normalized()
  pos = pos - dir * (carBB:getHalfExtents().y + trBB:getHalfExtents().y + gap) + diff
  trailer:setPosition(pos.x, pos.y, pos.z)
end

local function deleteTrailer()
  local t = vehById(R.trailerId)
  if t then t:delete() end
  R.trailerId = nil
  spots.hide()                                   -- (the job's spot markers go with it)
  R.pickupSpot, R.dropSpot, R.spotTry = nil, nil, nil
end

-- the trailer: standing in its marked spot on the depot's grounds (spot), else (no spot found) behind the truck
local function spawnTrailer(spot)
  local job = S.job
  local truck = careerVeh()
  if not job or not truck then return end
  local pos, rot
  if spot then
    pos, rot = spot.pos + vec3(0, 0, 0.5), spot.rot
  else
    local dir = vec3(truck:getDirectionVector()):normalized()
    local up = vec3(truck:getDirectionVectorUp()):normalized()
    pos, rot = vehPos(truck) - dir * 22 + up * 0.5, quatFromDir(dir, up)
  end
  local veh = core_vehicles.spawnNewVehicle(job.trailer.model, {
    config = 'vehicles/' .. job.trailer.model .. '/' .. job.trailer.config .. '.pc',
    pos = pos, rot = rot, autoEnterVehicle = false,
  })
  if not veh then
    notify('Auflieger konnte nicht bereitgestellt werden.', 6)
    job.phase = 'needTrailer'
    return
  end
  R.trailerId = veh:getID()
  roadEvents.protect(R.trailerId)
  R.lastCond = nil
  if spot then
    job.phase = 'toTrailer'
    R.hitchStep, R.closeT = nil, 0
  else
    job.phase = 'hitching'
    R.hitchT = now()
    R.hitchStep = 'wait'
  end
end

-- where the player is, for "continue" (M.resume): back on the same road facing the same way, the job's trailer behind
-- the truck when it was on. Kept with every save while driving the career's own vehicle (not during a passage).
remember = function()
  if not R.mode or R.trip or R.pendingTeleport or R.orient then return end
  local v, pv = careerVeh(), playerVeh()
  if not v or not pv or pv:getID() ~= v:getID() then return end
  local p = here()
  if not p then return end
  local d = vec3(v:getDirectionVector())
  S.resume = { lat = p.lat, lon = p.lon, hdg = math.deg(math.atan2(d.x, d.y)) % 360,
    trailer = (S.job and isCoupled()) and true or nil }
end

local function earthAnchor()
  local c = earthCore()
  local st = c and c._state and c._state() or nil
  return st and st.anchor or nil
end

local function clearSpots()
  spots.hide()
  R.pickupSpot, R.dropSpot, R.spotTry = nil, nil, nil
end

function M.hitchNow()
  if not S or not S.job or not R.trailerId then return end
  if vehSpeed(careerVeh()) > 1.5 then notify('Zum Ankuppeln bitte anhalten.', 4); return end
  local tv, cv = vehById(R.trailerId), careerVeh()
  if tv and cv and vehPos(cv):distance(vehPos(tv)) > 25 then notify('Fahr näher an den Auflieger heran (unter 25 m).', 4); return end
  if autoHitch() then R.hitchT = now(); R.hitchStep = 'locking'; S.job.phase = 'hitching' end
end

function M.unhitchNow()
  local truck = careerVeh()
  if truck and isCoupled() then truck:queueLuaCommand('beamstate.detachCouplers()') end
end

------------------------------------------------------------------------------------------
-- places on site: the yard, logistics bases, fuel, workshops, dealers, viewpoints

local function atHome() local d = dist(here(), S.home); return d and d <= C.HOME_RADIUS_M end

-- free vehicle change here: the yard, a logistics / parcel base, a dealer
local function atHub()
  if atHome() then return true end
  local n = R.near
  if not n then return false end
  local t = DEPOT_BY_KEY[n.type]
  return t and (t.hub or n.action == 'dealerTruck' or n.action == 'dealerCar') and n.dist <= math.max(C.HUB_RADIUS_M, t.radius or 0) or false
end

local function transferFee()
  if atHub() then return 0 end
  local d = dist(here(), S.home) or 0
  return round(C.TRANSFER_BASE + d / 1000 * C.TRANSFER_PER_KM, 10)
end

local function updateNear()
  local p = here()
  if not p then R.near = nil; return end
  local best
  for _, d in ipairs(S.depots) do
    local t = DEPOT_BY_KEY[d.type]
    -- (a cheap look at the coordinates first: the wide network has thousands of places, 2026-11-07)
    if t and (t.facility or t.hub) and math.abs(d.lat - p.lat) < 0.02 and math.abs(d.lon - p.lon) < 0.03 then
      local r = t.radius or C.HUB_RADIUS_M
      local dd = haversine(p.lat, p.lon, d.lat, d.lon)
      if dd <= r and (not best or dd < best.dist) then
        best = { id = d.id, type = d.type, name = d.name, icon = t.icon, typeName = t.name, action = t.action, dist = dd, lat = d.lat, lon = d.lon }
      end
    end
  end
  -- a company with loads waiting (its offers in the market, as ETS2's freight at the yard): its ring, Enter, take one
  if not S.job then
    for _, o in ipairs(R.offers or {}) do
      local f = o.from
      local dd = f and f.lat and haversine(p.lat, p.lon, f.lat, f.lon)
      if dd and dd <= 250 and not o.smuggle and (not best or dd < best.dist) then
        best = { id = f.id, type = f.type, name = f.name, icon = '📦', typeName = 'Fracht abholbereit', action = 'freight', dist = dd,
          lat = f.lat, lon = f.lon }
      end
    end
    -- (2026-11-05) every company that ships goods has its ring: drive in, ask there for a load (uiStop makes some)
    -- (the kinds that ship anything: worked out once – this runs every NEAR_S over all the depots, 2026-11-07)
    if not R.shipsType then
      R.shipsType = {}
      for k in pairs(DEPOT_BY_KEY) do R.shipsType[k] = #enabledCargo(k) > 0 end
    end
    for _, d in ipairs(S.depots) do
      local t = DEPOT_BY_KEY[d.type]
      if t and not t.facility and not t.hub and R.shipsType[d.type] and math.abs(d.lat - p.lat) < 0.004 and math.abs(d.lon - p.lon) < 0.006 then
        local dd = haversine(p.lat, p.lon, d.lat, d.lon)
        if dd <= 250 and (not best or dd < best.dist - 1) then
          best = { id = d.id, type = d.type, name = d.name, icon = t.icon or '📦', typeName = t.name .. ' – Fracht anfragen', action = 'freight',
            dist = dd, lat = d.lat, lon = d.lon }
        end
      end
    end
  end
  -- ferry ports, the tunnel terminal, airports (travel.lua)
  for _, x in ipairs(travel.hubsNear(p, 1.5)) do
    local h = x.hub
    local r = h.kind == 'airport' and 1500 or 600
    if x.dist <= r and (not best or x.dist < best.dist) then
      best = { id = h.id, type = h.kind, name = h.name, icon = h.kind == 'airport' and '✈' or '⚓',
        typeName = h.kind == 'airport' and 'Flughafen' or (h.train and 'Autozug-Terminal' or 'Fährhafen'),
        action = h.kind == 'airport' and 'fly' or 'ferry', dist = x.dist, lat = h.lat, lon = h.lon }
    end
  end
  local dh = dist(p, S.home)
  if dh and dh <= C.HOME_RADIUS_M and (not best or dh < best.dist) then
    best = { id = 'home', type = 'home', name = S.home.name or 'Firmenhof', icon = '🏠', typeName = 'Dein Hof', action = 'home', dist = dh,
      lat = S.home.lat, lon = S.home.lon }
  end
  -- (the milk round's next stop: its ring, whatever else is near)
  if S.tour and L.tourTarget then
    local tg = L.tourTarget(S.tour)
    local farm = S.tour.i <= #S.tour.stops
    local dd = haversine(p.lat, p.lon, tg.lat, tg.lon)
    if dd <= 400 then
      best = { id = 'tour' .. S.tour.i, type = 'milk', name = tg.name, icon = '🥛', typeName = farm and 'Milchhof' or 'Molkerei – abliefern', action = 'tour',
        dist = dd, lat = tg.lat, lon = tg.lon }
    end
  end
  -- (2026-11-09) on foot after a flight: the rental desk, whatever else is near
  if L.onFoot() and S.rentalDesk and S.rentalDesk.placed then
    local dd = haversine(p.lat, p.lon, S.rentalDesk.lat, S.rentalDesk.lon)
    if dd <= 800 then
      best = { id = 'rental', type = 'rental', name = 'Mietwagen-Schalter', icon = '🚗', typeName = 'Mietwagen auswählen', action = 'rental', dist = dd,
        lat = S.rentalDesk.lat, lon = S.rentalDesk.lon }
    end
  end
  -- (2026-11-08) the fuel stations and car parks the world itself has (parked.lua). A car park only with nothing else
  -- near and only when slowing down: a ring at every supermarket would be all one sees in a town.
  if not (S.tour and best and best.action == 'tour') then
    local f, df = parked.fuelNear(p.lat, p.lon, 70)
    if f and (not best or df < best.dist) then
      best = { id = 'earthfuel:' .. tostring(f.id), type = 'fuel', name = L.neutralName('fuel', f.name, nil, f.lat, f.lon), icon = '⛽', typeName = 'Tankstelle', action = 'refuel', dist = df, lat = f.lat, lon = f.lon }
    end
    local v0 = playerVeh()
    if not best and v0 and vehSpeed(v0) <= 11 then
      local lot, dl = parked.lotNear(p.lat, p.lon, 90)
      if lot then
        best = { id = 'lot:' .. lot.id, type = 'parkinglot', parking = true, name = 'Parkplatz', icon = '🅿️', typeName = 'Parkplatz',
          action = 'sleep', hint = 'Parkplatz – Pause machen und schlafen', dist = dl, lat = lot.lat, lon = lot.lon }
      end
    end
  end
  R.near = best
  -- a viewpoint seen for the first time
  if best and best.action == 'discover' and not S.discovered[tostring(best.id)] then
    S.discovered[tostring(best.id)] = true
    S.stats.discoveries = (S.stats.discoveries or 0) + 1
    L.pay('Entdeckung', C.DISCOVER_MONEY, best.name)
    addXp(C.DISCOVER_XP)
    notify(string.format('Entdeckt: %s  ·  +%d XP  ·  +%d €', best.name, C.DISCOVER_XP, C.DISCOVER_MONEY), 8)
    story('firstDiscovery')
    extensions.hook('onFernfahrerDiscovery', best)
    save()
  end
  if best and (best.action == 'dealerTruck' or best.action == 'dealerCar') then story('dealerHere') end
  -- the route advisor's minimap: the places around (facilities first), at most 60
  local list = {}
  local dLat = 6000 / 111320
  for _, d in ipairs(S.depots) do
    local dd = math.abs(d.lat - p.lat) < dLat and haversine(p.lat, p.lon, d.lat, d.lon) or math.huge
    if dd < 6000 then
      local t = DEPOT_BY_KEY[d.type]
      table.insert(list, { lat = d.lat, lon = d.lon, t = d.type, f = t and t.facility or false, n = d.name, d = dd })
    end
  end
  for _, x in ipairs(travel.hubsNear(p, 6)) do
    table.insert(list, { lat = x.hub.lat, lon = x.hub.lon, t = x.hub.kind, f = true, n = x.hub.name, d = x.dist })
  end
  -- (2026-11-09: Earth's own fuel stations round here on the HUD's map too)
  for _, f in pairs(parked.fuelAll()) do
    if math.abs(f.lat - p.lat) < 0.1 and math.abs(f.lon - p.lon) < 0.15 then
      local df = haversine(p.lat, p.lon, f.lat, f.lon)
      if df < 12000 then table.insert(list, { lat = f.lat, lon = f.lon, t = 'fuel', n = L.neutralName('fuel', f.name, nil, f.lat, f.lon), d = df }) end
    end
  end
  -- (companies with loads waiting: a marker of their own with the number of trailers)
  local jobs = {}
  for _, o in ipairs(S.job and {} or R.offers or {}) do
    local f = o.from
    if f and f.lat then
      local j = jobs[f.id]
      if not j then
        j = { lat = f.lat, lon = f.lon, t = 'freight', f = true, n = f.name, d = haversine(p.lat, p.lon, f.lat, f.lon), j = 0 }
        jobs[f.id] = j
        if j.d < 12000 then table.insert(list, j) end
      end
      j.j = j.j + 1
    end
  end
  table.sort(list, function(a, b) if a.f ~= b.f then return a.f end return a.d < b.d end)
  for i = #list, 61, -1 do list[i] = nil end
  R.mapPlaces = list
  -- the planned route near the player (every few calls: the route can have thousands of points)
  R.routeTick = (R.routeTick or 0) + 1
  if R.routeTick % 4 == 1 then
    local gps = earthModule('gps')
    local r = gps and gps.route and gps.route()
    local line = {}
    if r and r.points then
      local step = math.max(1, math.floor(#r.points / 400))
      for i = 1, #r.points, step do
        local q = r.points[i]
        if haversine(p.lat, p.lon, q[1], q[2]) < 8000 then table.insert(line, { q[1], q[2] }) end
      end
      local last = r.points[#r.points]
      if last then table.insert(line, { last[1], last[2] }) end
    end
    R.routeLine = line
  end
  -- (its own hook, twice a second: the 5 Hz HUD payload stays small)
  guihooks.trigger('FernfahrerMap', { places = R.mapPlaces, route = R.routeLine })
end

-- fuel: read the player's tanks every few seconds (fuel %, litres, consumption, range)
local function updateFuel()
  local v = playerVeh()
  if not v or not core_vehicleBridge then R.fuel = nil; return end
  local id = v:getID()
  core_vehicleBridge.requestValue(v, function(ret)
    local tanks = ret and ret[1]
    if type(tanks) ~= 'table' then return end
    local cur, max, unit, name, mjSum = 0, 0, nil, nil, nil
    for _, tank in ipairs(tanks) do
      local f = FUEL[tank.energyType]
      if f and tank.maxEnergy and tank.maxEnergy > 0 then
        cur = cur + (tank.currentEnergy or 0) / 1e6 / f.mj
        max = max + tank.maxEnergy / 1e6 / f.mj
        unit, name = f.unit, f.name
        mjSum = true
      end
    end
    if not mjSum then R.fuel = nil; return end
    local prev = R.fuel
    local f = { vehId = id, amount = cur, capacity = max, ratio = max > 0 and cur / max or 0, unit = unit, name = name,
      per100 = prev and prev.vehId == id and prev.per100 or nil }
    -- consumption over the distance driven since the last reading (smoothed), for the range
    if prev and prev.vehId == id and R.odo > 50 and prev.amount > cur then
      local per100 = (prev.amount - cur) / (R.odo / 1000) * 100
      if per100 > 1 and per100 < 200 then f.per100 = f.per100 and f.per100 * 0.8 + per100 * 0.2 or per100 end
      R.odo = 0
    elseif not prev or prev.vehId ~= id or cur > prev.amount + 1 then
      R.odo = 0
    else
      f.amount = cur
    end
    if f.ratio < C.LOW_FUEL and (not prev or prev.ratio >= C.LOW_FUEL) then
      notify('Tank fast leer – nächste Tankstelle anfahren!', 8)
      story('lowFuel')
    end
    R.fuel = f
    -- (2026-11-07) the career vehicle's tanks remembered: a reset or a new spawn fills them up in the game – they are
    -- put back to this (L.restoreFuelOf). Not while a putting-back is under way.
    if id == R.truckId and not (R.fuelHoldUntil and now() < R.fuelHoldUntil) then
      local keep = {}
      for _, tank in ipairs(tanks) do
        if tank.name and tank.currentEnergy and tank.maxEnergy and tank.maxEnergy > 0 then
          keep[#keep + 1] = { name = tank.name, currentEnergy = tank.currentEnergy, maxEnergy = tank.maxEnergy }
        end
      end
      R.lastTanks = { id = id, tanks = keep }
      S.fuelMem = S.fuelMem or {}
      S.fuelMem[tostring(S.active)] = f.ratio
    end
  end, 'energyStorage')
end

-- the tanks put back after the game filled them (a reset: the last reading; a new spawn of the vehicle: its share)
function L.restoreFuelOf(v, delay)
  if not v or not core_vehicleBridge then return end
  local id = v:getID()
  R.fuelHoldUntil = now() + (delay or 0.5) + 2
  if R.lastTanks and R.lastTanks.id == id then
    R.restoreFuel = { id = id, tanks = R.lastTanks.tanks, t = now() + (delay or 0.5) }
    return
  end
  local ratio = S and S.fuelMem and S.fuelMem[tostring(S.active)]
  if not ratio then return end
  R.restoreRatio = { id = id, ratio = ratio, t = now() + (delay or 1.0) }
end
-- the game's reset of the career vehicle (Insert, the recovery, a teleport with reset): the fuel stays as it was;
-- the vehicle is whole again (as before) – the damage kept from the last session goes with it
function M.onVehicleResetted(vid)
  if not R.mode or not S or vid ~= R.truckId then return end
  local v = getObjectByID(vid)
  -- (the limiter and the tank's size told again straight away: a reload of the vehicle starts its Lua anew, and the
  -- fuel put back must find the tank at its career size)
  R.limiterFor, R.wearSig = nil, nil
  pcall(L.acc.forgetFrame)
  if v and L.speedRulesTick then pcall(L.speedRulesTick, now(), v) end
  L.restoreFuelOf(v, 0.4)
  if R.condRestoringUntil and now() < R.condRestoringUntil then return end
  -- (2026-11-07: a teleport is no repair – BeamNG.Earth's map, "Zum Hof", a trip reset the vehicle on the way and the
  -- damage was gone. A reset far from where the truck just was, or while a teleport of ours / Earth's is under way:
  -- the kept condition goes back on. Only a reset on the spot (Insert, the recovery) repairs, as before.)
  -- (2026-11-09: only a repair that was paid for makes the truck whole. Every other reset, far away or on the spot, gives back what it was, to the point: the value read
  -- just before. The parts put back do not add up to exactly that, so the books are squared afterwards. With the developer switch a reset on the spot repairs as in the game.)
  if R.ownRepairUntil and now() < R.ownRepairUntil then
    R.dmgBase = nil
    L.clearCond()
    return
  end
  local jumped = false
  if v and R.truckLastPos then
    local p = v:getPosition()
    jumped = (p.x - R.truckLastPos.x) ^ 2 + (p.y - R.truckLastPos.y) ^ 2 > 150 ^ 2
  end
  local c = earthCore()
  local st = c and c._state and c._state() or nil
  local teleporting = (R.keepCondUntil and now() < R.keepCondUntil) or R.pendingTeleport ~= nil or R.trip ~= nil
    or (st and (st.pending or st.rebasing)) or false
  if S.settings.devResets and not jumped and not teleporting then
    R.dmgBase, R.dmgTarget, R.dmgLive = nil, nil, 0
    L.clearCond()
    return
  end
  R.dmgTarget = { v = (R.dmgTarget and R.dmgTarget.v) or R.dmgLive or 0, at = now() + 3.2 }
  R.condRestoreAt = now() + 0.6
end
-- (before a teleport of ours: the condition written fresh, and kept through the resets on the way)
function L.keepCondForTeleport()
  R.keepCondUntil = now() + 90
  pcall(L.requestCond)
end

-- (2026-11-07) the truck's condition kept between sessions: BeamNG's own part conditions (mileage, bent beams,
-- paint – as its career saves them) every CONDITION_S and at the save, in a file of its own per career and vehicle;
-- put back when the vehicle is spawned again. A reset afterwards repairs it as always (no reset snapshot kept).
L.CONDITION_S = 30
function L.condPath()
  return string.format('/settings/fernfahrer/condition_%s_%s.json', tostring(R.slot or 'x'), tostring(S and S.active or 'x'):gsub('[^%w_%-]', '_'))
end
function L.clearCond() pcall(function() if FS:fileExists(L.condPath()) then FS:removeFile(L.condPath()) end end) end
function L.requestCond()
  local v = careerVeh()
  if not v or (R.condRestoringUntil and now() < R.condRestoringUntil) then return end
  v:queueLuaCommand('if partCondition and partCondition.getConditions then local c = partCondition.getConditions() ' ..
    'if c then obj:queueGameEngineLua("if fernfahrer_career then fernfahrer_career.onConditions(" .. obj:getID() .. "," .. serialize(c) .. ") end") end end')
end
function M.onConditions(id, c)
  if not S or id ~= R.truckId or type(c) ~= 'table' then return end
  R.lastCond = c
  local dmg = damageOf(id)
  -- (a whole vehicle: nothing to keep – the file goes, a spawn stays new)
  if dmg < 50 then L.clearCond(); return end
  pcall(jsonWriteFile, L.condPath(), { active = S.active, dmg = dmg, cond = c }, false)
end
function L.condTick(t)
  if R.near and (R.near.action == 'repair' or R.near.action == 'home') and t - (R.partReqT or 0) > 4 then R.partReqT = t; L.requestCond() end
  local cv = R.truckId and getObjectByID(R.truckId)
  if cv then
    -- (where the truck was: a reset far from it is a teleport, see onVehicleResetted)
    R.truckLastPos = cv:getPosition()
    -- (2026-11-09: the damage as it stands, for a reset to give back; a reset's zero must not get in here, so it only ever rises until a repair or a new truck)
    if R.dmgLiveId ~= R.truckId then R.dmgLiveId, R.dmgLive = R.truckId, 0 end
    if not R.condRestoreAt and not R.dmgTarget then R.dmgLive = math.max(R.dmgLive or 0, damageOf(R.truckId)) end
    if R.dmgTarget and not R.condRestoreAt and t > R.dmgTarget.at then
      local raw = damageOf(R.truckId) - ((R.dmgBase and R.dmgBase.id == R.truckId and R.dmgBase.v) or 0)
      local want = R.dmgTarget.v
      R.dmgTarget = nil
      R.dmgBase = { id = R.truckId, v = want - raw }
      R.dmgLive, R.condDmgSaved, R.condT = want, want, t
      L.requestCond()
    end
    -- (put back after a teleport's reset)
    if R.condRestoreAt and t > R.condRestoreAt then R.condRestoreAt = nil; pcall(L.restoreCond, cv) end
  end
  -- (written after a fresh knock too, not only every CONDITION_S: a teleport soon after keeps it)
  if cv and t - (R.condDmgT or 0) > 3 then
    R.condDmgT = t
    local d = damageOf(R.truckId)
    if math.abs(d - (R.condDmgSaved or 0)) > 25 then R.condDmgSaved = d; R.condT = t; L.requestCond(); return end
  end
  if t - (R.condT or 0) < L.CONDITION_S then return end
  R.condT = t
  L.requestCond()
end
-- spawned again: the kept condition back on (instead of the used-vehicle wear); true when there was one
function L.restoreCond(v)
  if not v then return false end
  local okR, d = pcall(jsonReadFile, L.condPath())
  if not okR or type(d) ~= 'table' or type(d.cond) ~= 'table' or d.active ~= S.active then return false end
  R.condRestoringUntil = now() + 3
  v:queueLuaCommand('if partCondition and partCondition.initConditions then partCondition.initConditions(' .. serialize(d.cond) .. ') ' ..
    'if partCondition.setResetSnapshotKey then partCondition.setResetSnapshotKey(nil) end end')
  R.dmgBase = { id = v:getID(), v = tonumber(d.dmg) or 0 }
  log('I', logTag, string.format('vehicle condition of the last session put back (%d damage)', math.floor(R.dmgBase.v)))
  return true
end

local function loanerActive() return S.active == 'loaner' end

-- refuel the player's vehicle; the loaner's diesel is paid by the client (quick job), own vehicles pay at the pump
function M.refuel(veh)
  veh = veh or playerVeh()
  if not veh or not core_vehicleBridge then return end
  local free = loanerActive() and R.truckId == veh:getID()
  core_vehicleBridge.requestValue(veh, function(ret)
    local tanks = ret and ret[1]
    if type(tanks) ~= 'table' then return end
    local budget = free and math.huge or math.max(0, S.money)
    local disc = (atHome() and L.hasUp('pump')) and 0.85 or 1          -- (the yard's own pump)
    local amount, cost, unit, fname = 0, 0, 'L', 'Kraftstoff'
    for _, tank in ipairs(tanks) do
      local f = FUEL[tank.energyType]
      if f and tank.maxEnergy and tank.currentEnergy then
        local missing = math.max(0, (tank.maxEnergy - tank.currentEnergy) / 1e6 / f.mj)
        local buy = math.min(missing, budget / (f.price * disc))
        if buy > 0.05 then
          core_vehicleBridge.executeAction(veh, 'setEnergyStorageEnergy', tank.name, tank.currentEnergy + buy * f.mj * 1e6)
          amount, cost, unit, fname = amount + buy, cost + buy * f.price * disc, f.unit, f.name
          budget = budget - buy * f.price * disc
        end
      end
    end
    if amount < 0.1 then notify('Der Tank ist schon voll.', 4); return end
    cost = round(cost, 0.01)
    if not free then L.pay('Diesel', -cost, string.format('%.0f l getankt', amount)) end
    S.stats.fuelL = (S.stats.fuelL or 0) + amount
    S.stats.fuelCost = (S.stats.fuelCost or 0) + (free and 0 or cost)
    local text = string.format('⛽ %.0f %s %s getankt · %s', amount, unit, fname, free and 'bezahlt der Auftraggeber' or money(-cost))
    if not free and budget < 1 then text = text .. ' (Geld reichte nicht für einen vollen Tank)' end
    notify(text, 8)
    story('firstFuel')
    R.fuelT = 0
    save()
  end, 'energyStorage')
end

-- (2026-11-07) the yard's upgrades – the company grows (bought in the office's fleet page; their props in yard.lua):
-- a diesel pump (refuel at the yard, cheaper), a workshop (repairs at the yard cheaper), a warehouse (more and better
-- paid requests). Kept in S.yardUp.
L.YARD_UP = {
  { key = 'pump', name = 'Hof-Tankstelle', icon = '⛽', price = 25000, text = 'Zwei Zapfsäulen auf dem Hof: tanken am Hof, 15 % günstiger.' },
  { key = 'workshop', name = 'Hof-Werkstatt', icon = '🔧', price = 40000, text = 'Werkzeug und Reifenlager in der Halle: Reparaturen am Hof 30 % günstiger.' },
  { key = 'warehouse', name = 'Lager & Disposition', icon = '📦', price = 60000, text = 'Ein Lager mit Disponentin: 3 Anfragen mehr in der Frachtbörse und 6 % mehr Lohn.' },
}
function L.hasUp(k) return S and S.yardUp and S.yardUp[k] or false end
function M.buyYardUpgrade(key)
  if not S then return { ok = false } end
  local up
  for _, u in ipairs(L.YARD_UP) do if u.key == key then up = u end end
  if not up then return { ok = false, msg = 'Unbekannter Ausbau.' } end
  if L.hasUp(key) then return { ok = false, msg = 'Schon gebaut.' } end
  if S.money < up.price then return { ok = false, msg = 'Nicht genug Geld – vielleicht hilft die Bank?' } end
  L.pay('Hof', -up.price, up.name)
  S.yardUp = S.yardUp or {}
  S.yardUp[key] = true
  pcall(yard.setUpgrades, S.yardUp)
  R.offers = R.offers or {}
  notify(string.format('%s %s gebaut – %s', up.icon, up.name, up.text), 8)
  save()
  return { ok = true }
end
function L.yardUpView()
  local out = {}
  for _, u in ipairs(L.YARD_UP) do
    out[#out + 1] = { key = u.key, name = u.name, icon = u.icon, price = u.price, text = u.text, owned = L.hasUp(u.key) or nil }
  end
  return out
end

-- (2026-11-07) fuel help: run dry somewhere (resets keep the tank as it was now) – the breakdown service brings
-- enough for 20 % of the tank: a call-out fee and the diesel at the pump price (the company's loaner: the fee only)
M.FUEL_HELP_FEE, M.FUEL_HELP_TO = 140, 0.2
function M.fuelHelp()
  if not S then return end
  local veh = careerVeh() or playerVeh()
  if not veh or not core_vehicleBridge then return end
  if vehSpeed(veh) > 2 then notify('Tankhilfe: erst anhalten.', 4); return end
  local free = loanerActive() and R.truckId == veh:getID()
  core_vehicleBridge.requestValue(veh, function(ret)
    local tanks = ret and ret[1]
    if type(tanks) ~= 'table' then return end
    local amount, cost = 0, 0
    for _, tank in ipairs(tanks) do
      local f = FUEL[tank.energyType]
      if f and tank.maxEnergy and tank.maxEnergy > 0 and tank.currentEnergy then
        local want = tank.maxEnergy * M.FUEL_HELP_TO
        if tank.currentEnergy < want then
          local add = (want - tank.currentEnergy) / 1e6 / f.mj
          core_vehicleBridge.executeAction(veh, 'setEnergyStorageEnergy', tank.name, want)
          amount, cost = amount + add, cost + add * f.price
        end
      end
    end
    if amount < 0.5 then notify('Tankhilfe: noch genug im Tank – fahr zur nächsten Tankstelle.', 5); return end
    local total = round(M.FUEL_HELP_FEE * (free and 0.5 or 1) + (free and 0 or cost), 1)
    L.pay('Pannenhilfe', -total, string.format('Tankhilfe %.0f l', amount))
    notify(string.format('⛽ Tankhilfe war da: %.0f l Diesel · %s – damit kommst du zur nächsten Tankstelle.', amount, money(-total)), 8)
    R.fuelT = 0
    save()
  end, 'energyStorage')
end

-- the drivetrain app: the player vehicle's differentials (asked once a second; the vehicle answers onDrivetrain)
local DRIVE_Q = "local t = {} for _, d in ipairs(powertrain.getDevicesByCategory('differential') or {}) do " ..
  "local a = {} for _, m in pairs(d.availableModes or {}) do a[#a + 1] = m end " ..
  "t[#t + 1] = { n = d.name, u = d.uiName, m = d.mode, a = a } end " ..
  "obj:queueGameEngineLua('if fernfahrer_career then fernfahrer_career.onDrivetrain(' .. serialize(t) .. ',' .. obj:getID() .. ') end')"

function L.pollDrivetrain()
  local v = playerVeh()
  if v then v:queueLuaCommand(DRIVE_Q) else R.drive = nil end
end

function M.onDrivetrain(diffs, id)
  local v = playerVeh()
  if not v or v:getID() ~= id then return end
  table.sort(diffs, function(a, b) return tostring(a.n) < tostring(b.n) end)
  R.drive = { diffs = diffs }
end

function M.toggleDiff(name)
  local v = playerVeh()
  if not v or type(name) ~= 'string' or not name:match('^[%w_]+$') then return end
  v:queueLuaCommand(string.format('powertrain.toggleDeviceMode(%q)', name))
  R.driveT = 0                                   -- (the app shows the new mode right away)
end

-- the Earth / stock gas stations' pump prompt pays in this mode
local function patchGasStations()
  local gs = rawget(_G, 'freeroam_gasStations')
  if not gs or gs.__fernfahrer then return end
  local orig = gs.refuelCar
  gs.refuelCar = function(station, fuelTypes, veh)
    if R.mode then return M.refuel(veh) end
    return orig(station, fuelTypes, veh)
  end
  gs.__fernfahrer = true
end

local function repairCost(veh)
  if loanerActive() then return 0 end
  local def = activeDef()
  local disc = (atHome() and L.hasUp('workshop')) and 0.7 or 1        -- (the yard's own workshop)
  return round(math.min((def.price or 80000) * 0.3, math.max(50, damageOf(veh:getID()) * C.REPAIR_PER_DMG)) * disc, 10)
end

-- (2026-11-08) what is left for the company to pay once the insurance has had its say
-- (2026-11-09: "repair" was the accident only and cheap. It is the whole truck now, everything made good in one go, and that costs what it costs; the parts one by one stay below it)
function L.partNeeded(own, g, H)
  local h = H and H[g.key]
  return h and (h.int < 0.995 or (g.key == 'karosserie' and h.vis < 0.95) or (g.key == 'motor' and (own.km or 0) >= 150000 and not (own.repaired and own.repaired.motor)))
end
function L.fullCost(veh, gross)
  local own = L.ownTruck()
  if not own or loanerActive() then return gross end
  local H, sum, any = L.partHealth(), 0, false
  for _, g in ipairs(L.PARTS) do
    if L.partNeeded(own, g, H) then any = true; sum = sum + L.partCost(own, g.key, H[g.key]) end
  end
  if not any and damageOf(veh:getID()) <= 100 then return 0 end
  local price = own.newPrice or own.price or 80000
  return round(math.min(price * 0.7, math.max(price * 0.05, sum, gross * 2.5)), 50)
end
function L.repairPay(veh)
  local gross = repairCost(veh)
  local ok, q = pcall(service.quote, gross)
  return math.max(0, L.fullCost(veh, gross) - (ok and (gross - q.pay) or 0))
end
-- (the conditions with the parts of these groups, or all of them, made good: kilometres stay)
function L.condFixed(groups)
  if type(R.lastCond) ~= 'table' then return nil end
  local c = {}
  for id, p in pairs(R.lastCond) do
    local q = {}
    if type(p) == 'table' then for k, x in pairs(p) do q[k] = x end end
    local g = L.partGroup(id)
    if not groups or groups[g] then
      q.integrityValue, q.integrityState = 1, nil
      if not groups or g == 'karosserie' then q.visualValue, q.visualState = 1, nil end
    end
    c[id] = q
  end
  return c
end
-- (the part of the accident's damage that sits in this group)
function L.partShare(key)
  local mine, all = 0, 0
  for id, p in pairs(R.lastCond or {}) do
    if type(p) == 'table' and tonumber(p.integrityValue) then
      local bad = 1 - p.integrityValue
      all = all + bad
      if L.partGroup(id) == key then mine = mine + bad end
    end
  end
  return all > 0 and mine / all or 0
end
-- repair in place at a workshop or the yard (the vehicle's reset), keeping its fuel
function M.repair()
  local veh = playerVeh()
  if not veh then return end
  if not (atHome() or (R.near and R.near.action == 'repair')) then notify('Reparieren geht in einer Werkstatt oder am Hof.', 5); return end
  if R.trailerId and isCoupled() then notify('Bitte erst den Auflieger abkuppeln.', 5); return end
  if vehSpeed(veh) > 1 then notify('Bitte anhalten.', 3); return end
  local gross = repairCost(veh)
  local q = service.quote(gross)
  local cost = L.repairPay(veh)
  if S.money < cost then notify('Nicht genug Geld für die Reparatur (' .. money(cost) .. ').', 5); return end
  core_vehicleBridge.requestValue(veh, function(ret)
    local function finish()
    local tanks = ret and ret[1] or {}
    if cost > 0 then L.pay('Werkstatt', -cost, 'Reparatur') end
    service.commit(q)
    local rot = quatFromDir(vec3(veh:getDirectionVector()), vec3(veh:getDirectionVectorUp()))
    R.ownRepairUntil, R.dmgTarget, R.dmgLive = now() + 3, nil, 0
    spawn.safeTeleport(veh, vehPos(veh), rot)
    R.restoreFuel = { id = veh:getID(), tanks = tanks, t = now() + 1.0, cond = L.condFixed(nil) }
    do
      local own = L.ownTruck()
      if own then
        own.repaired = own.repaired or {}
        for _, g in ipairs(L.PARTS) do own.repaired[g.key] = true end
        own.wear = own.wear or {}
        own.wear.visual = 1
        R.wearSig = nil
      end
    end
    notify('Repariert' .. (cost > 0 and (' · ' .. money(-cost)) or (gross > 0 and ' – bezahlt die Versicherung' or ' (Leih-LKW: kostenlos)'))
      .. ((q.covered > 0 and cost > 0) and (' · ' .. tostring(q.text)) or ''), 6)
    story('firstRepair')
    message('Der Lkw ist komplett instand gesetzt. Nur der Kilometerstand ist geblieben.', 'Werkstatt')
    save()
    end
    if not L.workStart({ title = 'Komplettreparatur', sub = 'Karosserie, Motor, Antrieb und Fahrwerk', done = finish }) then finish() end
  end, 'energyStorage')
end

------------------------------------------------------------------------------------------
-- vehicles: fetch (spawn here), dealers on site

-- the active vehicle replaces the current one here (free at the yard / a base / a dealer, else a transfer fee)
function M.fetchVehicle(idx)
  if not S then return end
  if S.job and R.trailerId then notify('Erst den aktuellen Auftrag beenden.', 4); return end
  local prev = S.active
  if idx ~= nil then
    local o = S.owned[idx]
    if o and o.seized then notify('Dieser LKW ist beschlagnahmt – erst auslösen.', 5); return end
    if o and o.driver then notify(o.driver.name .. ' ist damit unterwegs – erst den Fahrer abziehen.', 5); return end
    if idx == 'loaner' or S.owned[idx] then S.active = idx else return end
  end
  local def = activeDef()
  local fee = transferFee()
  if fee > 0 then
    if S.money < fee then S.active = prev; notify('Überführung kostet ' .. money(fee) .. ' – nicht genug Geld.', 5); return end
    L.pay('Überführung', -fee, 'Fahrzeug überführt')
    notify('Fahrzeug wird überführt · ' .. money(-fee), 6)
  end
  if playerVeh() then
    core_vehicles.replaceVehicle(def.model, { config = def.config, autoEnterVehicle = true })
  else
    core_vehicles.spawnNewVehicle(def.model, { config = def.config, autoEnterVehicle = true })
  end
  R.truckId = nil
  R.fuel = nil
  R.pendingAdopt = now() + 0.5
  save()
end
M.spawnTruck = function() M.fetchVehicle() end

local function buyVehicle(entry, kind)
  if S.money < entry.price then notify('Nicht genug Geld – vielleicht hilft die Bank?', 5); return end
  L.pay('Fahrzeuge', -entry.price, 'Kauf: ' .. tostring(entry.brand or '') .. ' ' .. tostring(entry.modelName or ''))
  local v = { kind = kind, model = entry.model, config = entry.config, brand = entry.brand, modelName = entry.modelName,
    configName = entry.configName, power = entry.power, eu = entry.eu, price = entry.price, km = entry.km or 0,
    used = entry.used or nil, wear = entry.wear, preview = entry.preview, bought = os.time(), defects = entry.defects }
  table.insert(S.owned, v)
  extensions.hook('onFernfahrerVehicleBought', v)
  story(kind == 'truck' and 'ownTruck' or 'carBought')
  notify((kind == 'truck' and 'LKW' or 'Auto') .. ' gekauft: ' .. v.brand .. ' ' .. v.modelName, 6)
  if not S.job then M.fetchVehicle(#S.owned) end      -- at the dealer: free, right here
  save()
end

function M.buyTruck(idx)
  if not (R.near and R.near.action == 'dealerTruck') then notify('LKW gibt es nur beim LKW-Händler vor Ort.', 5); return end
  local t = R.trucks and R.trucks[idx]
  if t then buyVehicle(t, 'truck') end
end

function M.buyCar(modelIdx, cfgIdx)
  if not (R.near and R.near.action == 'dealerCar') then notify('Autos gibt es nur im Autohaus vor Ort.', 5); return end
  local m = R.cars and R.cars[modelIdx]
  local c = m and m.configs[cfgIdx]
  if c then buyVehicle(c, 'car') end
end

-- Used trucks: each truck dealer has a few, its own stock for a game week (the same for everyone who comes by that
-- week; a sold one is gone). Kilometres and the look of the wear (BeamNG's own part condition, as the stock career's
-- used cars: partCondition.initConditions with the mileage and a visual value) come with them; the price follows.
function L.lcg(seed)
  local s = seed % 2147483647
  if s <= 0 then s = s + 2147483646 end
  return function(a, b)
    s = (s * 16807) % 2147483647
    local f = (s - 1) / 2147483646
    if a then return a + f * (b - a) end
    return f
  end
end

function L.hashStr(str)
  local h = 5381
  for i = 1, #str do h = (h * 33 + str:byte(i)) % 2147483647 end
  return h
end

-- the look of a truck with this many km (1 = new): as vehicleShopping.getVisualValueFromMileage, plus some wear
local function visualFromKm(km, extra)
  local m = km * 1000
  local v
  if m <= 1e7 then v = 1 elseif m <= 5e7 then v = 1 - (m - 1e7) / 4e7 * 0.05
  elseif m <= 1e8 then v = 0.95 - (m - 5e7) / 5e7 * 0.025 elseif m <= 2e8 then v = 0.925 - (m - 1e8) / 1e8 * 0.045
  elseif m <= 5e8 then v = 0.88 - (m - 2e8) / 3e8 * 0.055 else v = 0.8 end
  return math.max(0.7, v - (extra or 0))
end

function L.dealerHas(id, brand) return L.hashStr(tostring(id) .. '|' .. tostring(brand)) % 100 < 62 end
local function usedStock(dealerId)
  if not R.trucks or #R.trucks == 0 then return {} end
  local week = math.floor((S.stats.km or 0) / 1500) + math.floor(os.time() / (7 * 86400))   -- (changes as you play)
  local key = tostring(dealerId) .. ':' .. week
  R.usedCache = R.usedCache or {}
  if R.usedCache[key] then return R.usedCache[key] end
  local rnd = L.lcg(L.hashStr(key))
  local europe = inEurope()
  local pool = {}
  for _, t in ipairs(R.trucks) do
    if not europe or t.eu or rnd() < 0.25 then pool[#pool + 1] = t end
  end
  if #pool == 0 then pool = R.trucks end
  -- (2026-11-09: not everything at every dealer: each one deals in its own brands)
  local spec = {}
  for _, t in ipairs(pool) do if L.dealerHas(dealerId, t.brand) then spec[#spec + 1] = t end end
  if #spec >= 4 then pool = spec end
  local list, seen = {}, {}
  local n = 13 + math.floor(rnd() * 5)
  for k = 1, n do
    local t
    for _ = 1, 6 do t = pool[1 + math.floor(rnd() * #pool)]; if (seen[t.config] or 0) < 2 then break end end
    seen[t.config] = (seen[t.config] or 0) + 1
    local km = math.floor(rnd(60000, 1150000) / 1000) * 1000
    local age = math.floor(km / 120000 + rnd(0, 3))
    local marks = rnd() < 0.35                                   -- (a few dents and scratches)
    local wear = { visual = visualFromKm(km, marks and 0.05 or 0), integrity = marks and rnd(0.9, 0.97) or 1 }
    local f = math.max(0.28, 0.88 - km / 1500000 * 0.55 - age * 0.025 - (marks and 0.04 or 0))
    local id = string.format('%s-%d', key, k)
    if not (S.soldUsed and S.soldUsed[id]) then
      list[#list + 1] = { usedId = id, used = true, kind = 'truck', model = t.model, config = t.config, brand = t.brand,
        modelName = t.modelName, configName = t.configName, power = t.power, drivetrain = t.drivetrain, eu = t.eu,
        preview = t.preview, km = km, age = age, marks = marks or nil, wear = wear, newPrice = t.price,
        price = round(t.price * f, 500), condition = math.floor(wear.visual * wear.integrity * 100 + 0.5) }
      -- (2026-11-08) hidden defects: nothing in the listing says so; such a truck is a little cheaper than it should be,
      -- the workshop's check finds it
      local dr = rnd()
      local chance = 0.25 + math.min(0.35, km / 3000000)
      if dr < chance then
        local e = list[#list]
        e.defects = rnd() < 0.5 and { axle = true } or { turbo = true }
        if dr < chance * 0.15 then e.defects = { axle = true, turbo = true } end
        e.price = round(e.price * 0.88, 500)
      end
    end
  end
  table.sort(list, function(a, b) return a.price < b.price end)
  R.usedCache[key] = list
  return list
end

function M.buyUsedTruck(usedId)
  if not (R.near and R.near.action == 'dealerTruck') then notify('LKW gibt es nur beim LKW-Händler vor Ort.', 5); return end
  for _, e in ipairs(usedStock(R.near.id)) do
    if e.usedId == usedId then
      if S.money < e.price then notify('Nicht genug Geld – vielleicht hilft die Bank?', 5); return end
      S.soldUsed = S.soldUsed or {}
      S.soldUsed[usedId] = true
      R.usedCache = nil
      buyVehicle(e, 'truck')
      return
    end
  end
end

-- (2026-11-09) the showrooms. Every dealer is a business of its own: its kind of stock (the same dealer stays what it is), a handful of
-- vehicles that change with time, the same for that dealer that week. Sold is gone.
L.CAR_STYLES = {
  { key = 'budget', name = 'Gebrauchtwagenmarkt', tag = 'Günstig, ehrlich, mit Geschichte', price = 'Eher günstig', max = 26000, km = { 90000, 280000 } },
  { key = 'family', name = 'Familien- und Alltagsautos', tag = 'Gepflegte Gebrauchte für jeden Tag', price = 'Mittlere Preise', powerMax = 240, km = { 25000, 150000 } },
  { key = 'premium', name = 'Premium & Sportwagen', tag = 'Das Besondere, frisch aufbereitet', price = 'Eher teuer', min = 45000, km = { 5000, 70000 }, newShare = 0.3 },
  { key = 'work', name = 'Gelände- und Nutzwagen', tag = 'Robust, kräftig, zum Arbeiten', price = 'Mittlere Preise', body = { suv = true, pickup = true, van = true, wagon = true }, km = { 40000, 210000 } },
}
L.TRUCK_STYLES = {
  { key = 'exchange', name = 'Nutzfahrzeug-Börse', tag = 'Gebrauchte Zugmaschinen zum fairen Preis', price = 'Eher günstig', used = 12, new = 0 },
  { key = 'center', name = 'Truck-Center', tag = 'Neue und junge Gebrauchte aus einer Hand', price = 'Mittel bis teuer', used = 7, new = 5 },
  { key = 'long', name = 'Fernverkehr-Spezialist', tag = 'Starke Zugmaschinen für die lange Strecke', price = 'Eher teuer', used = 8, new = 4, powerMin = 400 },
}
function L.dealerStyle(id, kind)
  local list = kind == 'truck' and L.TRUCK_STYLES or L.CAR_STYLES
  return list[1 + L.hashStr(tostring(id)) % #list]
end
function L.carStock(id, style)
  local week = math.floor((S.stats.km or 0) / 1500) + math.floor(os.time() / (7 * 86400))
  local key = 'car:' .. tostring(id) .. ':' .. week
  R.carCache = R.carCache or {}
  if R.carCache[key] then return R.carCache[key] end
  local rnd = L.lcg(L.hashStr(key))
  local pool, all = {}, {}
  for _, m in ipairs(R.cars or {}) do
    for _, c in ipairs(m.configs or {}) do
      local p = c.price or 0
      all[#all + 1] = c
      if (not style.max or p <= style.max) and (not style.min or p >= style.min) and (not style.powerMax or (c.power or 0) <= style.powerMax)
         and (not style.body or style.body[tostring(c.body or ''):lower()]) then pool[#pool + 1] = c end
    end
  end
  if #pool < 5 then pool = all end
  local list, taken = {}, {}
  for k = 1, 10 + math.floor(rnd() * 5) do
    local c
    for _ = 1, 12 do
      c = pool[1 + math.floor(rnd() * #pool)]
      if c and not taken[c.config] then break end
    end
    if c and not taken[c.config] then
      taken[c.config] = true
      local isNew = rnd() < (style.newShare or 0)
      local km = isNew and 0 or math.floor(rnd(style.km[1], style.km[2]) / 500) * 500
      local age = isNew and 0 or math.floor(km / 18000 + rnd(0, 2))
      local marks = not isNew and rnd() < 0.3
      local wear = not isNew and { visual = visualFromKm(km * 3, marks and 0.05 or 0), integrity = marks and rnd(0.9, 0.97) or 1 } or nil
      local f = isNew and 1 or math.max(0.22, 0.86 - km / 320000 * 0.55 - age * 0.03 - (marks and 0.05 or 0))
      local sid = key .. ':' .. k
      if not (S.soldUsed and S.soldUsed[sid]) then
        list[#list + 1] = { showId = sid, usedId = sid, used = not isNew or nil, kind = 'car', model = c.model, config = c.config, brand = c.brand,
          modelName = c.modelName, configName = c.configName, power = c.power, drivetrain = c.drivetrain, eu = c.eu, preview = c.preview,
          km = km, age = age, marks = marks or nil, wear = wear, newPrice = c.price, price = math.max(500, round(c.price * f, 100)),
          condition = wear and math.floor(wear.visual * wear.integrity * 100 + 0.5) or 100 }
      end
    end
  end
  table.sort(list, function(a, b) return a.price < b.price end)
  R.carCache[key] = list
  return list
end
function L.showroom()
  local near = R.near
  if not near or (near.action ~= 'dealerTruck' and near.action ~= 'dealerCar') then return nil end
  local kind = near.action == 'dealerTruck' and 'truck' or 'car'
  local style = L.dealerStyle(near.id, kind)
  local items = {}
  if kind == 'car' then
    items = L.carStock(near.id, style)
  else
    local used = usedStock(near.id)
    for i = 1, math.min(style.used, #used) do items[#items + 1] = used[i] end
    if style.new > 0 and R.trucks and #R.trucks > 0 then
      local rnd = L.lcg(L.hashStr('new:' .. tostring(near.id)))
      local taken = {}
      for _ = 1, style.new * 12 do
        local i = 1 + math.floor(rnd() * #R.trucks)
        local t = R.trucks[i]
        if not taken[i] and (not inEurope() or t.eu) and (not style.powerMin or (t.power or 0) >= style.powerMin) and L.dealerHas(near.id, t.brand) then
          taken[i] = true
          local e = {}
          for k, v in pairs(t) do e[k] = v end
          e.showId, e.idx = 'new:' .. i, i
          items[#items + 1] = e
          if #taken >= style.new then break end
        end
        local n = 0
        for _ in pairs(taken) do n = n + 1 end
        if n >= style.new then break end
      end
    end
    for _, e in ipairs(items) do e.showId = e.showId or e.usedId end
    table.sort(items, function(a, b) return a.price < b.price end)
  end
  return { dealer = { name = near.name, kind = kind, key = style.key, style = style.name, tag = style.tag .. ' · ' .. tostring(style.price) }, items = items }
end
function M.uiShowroom()
  ensureCatalog()
  return L.showroom() or {}
end
function M.buyShowroom(showId)
  local room = L.showroom()
  if not room then notify('Fahrzeuge gibt es nur beim Händler vor Ort.', 5); return end
  for _, e in ipairs(room.items) do
    if e.showId == showId then
      if S.money < e.price then notify('Nicht genug Geld – vielleicht hilft die Bank?', 5); return end
      if e.used or e.kind == 'car' then
        S.soldUsed = S.soldUsed or {}
        S.soldUsed[e.usedId or showId] = true
        R.usedCache, R.carCache = nil, nil
      end
      buyVehicle(e, e.kind)
      return
    end
  end
end

-- an owned vehicle as it comes out of the garage: its kilometres and its wear (BeamNG's part condition)
function L.applyWear(v, def)
  if not v or not def or def.rental then return end
  local km = def.km or 0
  if km < 500 and not def.wear then
    -- (new: no wear – but the part conditions started, so the truck's condition can be kept between sessions)
    v:queueLuaCommand('if partCondition and partCondition.ensureConditionsInit then partCondition.ensureConditionsInit(0, 1, 1) end')
    return
  end
  local w = def.wear or {}
  local visual = math.min(w.visual or 1, visualFromKm(km))
  v:queueLuaCommand(string.format('if partCondition and partCondition.initConditions then partCondition.initConditions(nil, %d, %.3f, %.3f) end',
    math.floor(km * 1000), w.integrity or 1, visual))
  if def.repaired then v:queueLuaCommand(L.partsCmd(def.repaired)) end
end

function M.sellVehicle(idx)
  local t = S.owned[idx]
  if not t or S.job then return end
  if t.seized or t.driver then notify(t.seized and 'Beschlagnahmte Fahrzeuge kann man nicht verkaufen.' or 'Erst den Fahrer abziehen.', 5); return end
  local value = round(t.price * math.max(0.4, 0.75 - (t.km or 0) / 20000), 100)
  L.pay('Fahrzeuge', value, 'Verkauf: ' .. tostring(t.brand or '') .. ' ' .. tostring(t.modelName or ''))
  pcall(L.acc.strip, t)                          -- (its accessories go back on the shelf)
  table.remove(S.owned, idx)
  if S.active == idx then S.active = 'loaner'
  elseif type(S.active) == 'number' and S.active > idx then S.active = S.active - 1 end
  notify(string.format('Fahrzeug verkauft für %s.', money(value)), 5)
  save()
end
M.sellTruck = M.sellVehicle

------------------------------------------------------------------------------------------
-- jobs

function M.acceptOffer(id)
  if not S or S.job then notify('Du hast schon einen Auftrag.', 4); return end
  local o
  for _, x in ipairs(R.offers) do if x.id == id then o = x end end
  if not o then return end
  if activeKind() ~= 'truck' then
    notify('Für Aufträge brauchst du einen LKW – Fahrzeug am Hof oder an einem Logistik-Stützpunkt wechseln.', 7)
    return
  end
  if not careerVeh() and not adoptPlayerVehicle() then
    notify('Steig erst in deinen LKW (Büro → Fuhrpark → Holen).', 6)
    return
  end
  local _, loaner = activeDef()
  S.job = {
    cargo = o.cargo, cargoName = o.cargoName, icon = o.icon, tons = o.tons, urgent = o.urgent, fragile = o.fragile,
    trailer = o.trailer, from = o.from, to = o.to, distKm = o.distKm, pickupKm = o.pickupKm, freight = o.freight,
    xp = o.xp, deadline = o.deadline, elapsed = 0, phase = 'toPickup', loaner = loaner,
  }
  S.job.long = o.long
  S.job.special = o.special
  -- (2026-11-08) load securing, dangerous-goods papers, goods without papers (the tutorial's first job: straps spared)
  S.job.secure = (o.secure and not (S.tut and not S.tut.done)) or nil
  S.job.adr, S.job.smuggle, S.job.heat = o.adr, o.smuggle, o.heat
  if o.adr then message('Gefahrgut: Pack im Büro beim laufenden Auftrag die ADR-Papiere ein. Ohne sie wird eine Kontrolle sehr teuer.') end
  for i, x in ipairs(R.offers) do if x == o then table.remove(R.offers, i) break end end
  resolveDestination(S.job)
  navTo(S.job.from, 'Laden: ' .. tostring(S.job.from.name))
  story('firstJob')
  if o.long then story('firstLongHaul') end
  message(string.format('Auftrag angenommen: %s von %s nach %s.', o.cargoName, tostring(o.from.name), tostring(o.to.name)))
  extensions.hook('onFernfahrerJobAccepted', S.job)
  save()
end

function M.cancelJob()
  if not S or not S.job then return end
  local fee = (S.job.routeError or S.job.phase == 'toPickup') and 0 or round(S.job.freight * 0.1, 10)
  L.pay('Vertragsstrafe', -fee, 'Auftrag storniert')
  deleteTrailer()
  navClear()
  S.job = nil
  message(fee > 0 and string.format('Auftrag storniert. Vertragsstrafe: %s.', money(fee)) or 'Auftrag storniert (ohne Gebühr, noch nicht geladen).')
  save()
end

function M.requestNewTrailer()
  local job = S and S.job
  if not job or job.phase ~= 'needTrailer' then return end
  deleteTrailer()
  job.freight = round(job.freight * 0.95, 10)
  job.phase = 'atPickup'
end

local function cargoCondition()
  if not R.trailerId then return 1 end
  local f = S.job and S.job.fragile and C.FRAGILE_FACTOR or 1
  return clamp(1 - (damageOf(R.trailerId) + (S.job and S.job.dmgCarry or 0)) * f / C.CARGO_DMG_FULL, 0, 1)
end

function L.completeJob()
  local job = S.job
  local cond = cargoCondition()
  local truckDmg = R.truckId and damageOf(R.truckId) or 0
  local rep = { cargoName = job.cargoName, icon = job.icon, from = job.from.name, to = job.to.name, km = job.distKm, lines = {} }
  local gross = job.loaner and job.freight * C.COMPANY_SHARE or job.freight
  table.insert(rep.lines, { job.loaner and 'Schnellauftrag (45 % der Fracht)' or 'Frachtlohn', round(gross) })
  local late = job.elapsed > job.deadline
  if late then
    local p = -round(gross * C.LATE_PENALTY)
    table.insert(rep.lines, { 'Verspätung', p })
    gross = gross + p
  end
  local dmgPenalty = math.min(C.CARGO_DMG_MAX_PENALTY, 1 - cond)
  if dmgPenalty > 0.01 then
    local p = -round(gross * dmgPenalty)
    table.insert(rep.lines, { string.format('Ladungsschaden (%d %%)', round((1 - cond) * 100)), p })
    gross = gross + p
  end
  -- the stars: on time, the cargo, the driving style, the tachograph (the card after unloading)
  local stl = job.style or {}
  local left = (job.deadline - job.elapsed) / math.max(1, job.deadline)
  local function clampStar(x) return math.max(1, math.min(5, math.floor(x + 0.5))) end
  local sTime = late and (job.elapsed > job.deadline * 1.25 and 1 or 2) or (left >= 0.15 and 5 or 4)
  local sCargo = cond >= 0.98 and 5 or cond >= 0.9 and 4 or cond >= 0.75 and 3 or cond >= 0.5 and 2 or 1
  local overShare = (stl.over or 0) / math.max(60, stl.t or 0)
  local sStyle = clampStar(5 - overShare * 25 - (stl.harsh or 0) * 0.6)
  local newV = math.max(0, (S.tacho and S.tacho.vtotal or 0) - (stl.tv0 or (S.tacho and S.tacho.vtotal) or 0))
  local sTacho = newV == 0 and 5 or (newV == 1 and 3 or 1)
  rep.stars = {
    { 'Pünktlichkeit', sTime, late and 'zu spät' or (left >= 0.15 and 'deutlich vor der Frist' or 'knapp in der Frist') },
    { 'Ladung', sCargo, string.format('%d %% unversehrt', round(cond * 100)) },
    { 'Fahrstil', sStyle, string.format('%d %% der Zeit zu schnell · %d× hart gebremst', round(overShare * 100), stl.harsh or 0) },
    { 'Fahrtenschreiber', sTacho, newV == 0 and 'keine Verstöße' or (newV .. ' Verstoß' .. (newV > 1 and 'e' or '')) },
  }
  rep.rating = (sTime + sCargo + sStyle + sTacho) / 4
  if rep.rating >= 4.5 then
    local p = round(gross * 0.05)
    table.insert(rep.lines, { 'Bonus: Top-Lieferung', p })
    gross = gross + p
  end
  local net = gross
  if job.loaner then
    local p = -round(math.min(gross * 0.3, truckDmg * C.LOANER_DMG_PER_DMG))
    if p < 0 then table.insert(rep.lines, { 'Selbstbeteiligung Leih-LKW', p }); net = net + p end
  else
    local def = S.owned[S.active]
    local costs = -round((job.distKm + (job.pickupKm or 0)) * C.COST_PER_KM)
    table.insert(rep.lines, { 'Maut & Verschleiß', costs })
    net = net + costs
    if def then def.km = (def.km or 0) + job.distKm end
  end
  if S.loan > 0 and net > 0 then
    local pay = math.min(S.loan, round(net * C.LOAN_AUTO))
    S.loan = S.loan - pay
    table.insert(rep.lines, { 'Kreditrate', -pay })
    net = net - pay
  end
  net = round(net)
  rep.total, rep.xp, rep.late, rep.cond = net, job.xp, late, cond
  -- (booked by line: the freight with its penalties and bonus, the tolls, the loan rate)
  local booked, freight = 0, 0
  local what = tostring(job.cargoName) .. ' · ' .. tostring(job.from.name) .. ' → ' .. tostring(job.to.name)
  for _, l in ipairs(rep.lines) do
    local label, v = tostring(l[1]), l[2] or 0
    if label:find('Maut') then L.pay('Maut & Verschleiß', v, what)
    elseif label:find('Kreditrate') then L.pay('Kredit', v, 'Kreditrate aus Lieferung')
    elseif label:find('Selbstbeteiligung') then L.pay('Werkstatt', v, 'Selbstbeteiligung Leih-LKW')
    else freight = freight + v end
    booked = booked + v
  end
  L.pay('Fracht', freight + (net - booked), what)
  S.stats.jobs = S.stats.jobs + 1
  pcall(service.onDelivery, dmgPenalty <= 0.05)
  S.stats.km = S.stats.km + job.distKm
  pcall(L.statDelivery, job, rep)
  S.stats.earned = S.stats.earned + math.max(0, net)
  if late then S.stats.late = S.stats.late + 1 end
  if dmgPenalty > 0.05 then S.stats.damaged = S.stats.damaged + 1 end
  addXp(job.xp)
  deleteTrailer()
  navClear()
  R.lastDelivery = { id = job.to.id, lat = job.to.lat, lon = job.to.lon, type = job.to.type, name = job.to.name, detail = job.to.detail }
  S.job = nil
  R.report = rep
  rep.clock, rep.day = clockText(), S.dayNo
  pcall(L.moodSting, (rep.rating or 3) >= 2.5 and 'ok_gut' or 'ok_mau')
  -- the card comes up a moment later (FernfahrerReport.vue); kept as a delivery note in the documents
  R.reportAt = now() + 1.2
  R.reportDoc = { kind = 'delivery', title = 'Lieferschein & Abrechnung', t = os.time(), clock = rep.clock,
    cargoName = rep.cargoName, from = rep.from, to = rep.to, km = rep.km, lines = rep.lines, total = rep.total,
    stars = rep.stars, rating = rep.rating, town = rep.to }
  notify(string.format('Lieferung abgeschlossen: %+d €  ·  +%d XP', net, rep.xp), 8)
  story('firstDelivery')
  if late then story('late') end
  if dmgPenalty > 0.15 then story('damaged') end
  if S.stats.jobs >= 3 then story('threeJobs') end
  if S.stats.jobs >= 10 then story('tenJobs') end
  if S.active == 'loaner' and (S.stats.jobs >= 4 or S.money >= 30000) then story('ownTruckHint') end
  extensions.hook('onFernfahrerJobCompleted', rep)
  R.offers = {}            -- the market around the new spot: the next loads in this town first (ETS2)
  topUpOffers(true)
  do
    local here0 = here()
    local near, best = {}, nil
    for _, o in ipairs(R.offers) do
      local d = here0 and dist(here0, o.from) or nil
      if d and d < 6500 and not near[o.from.id] then
        near[o.from.id] = true
        if not best or d < best.d then best = { d = d, name = o.from.name } end
      end
    end
    local n = 0
    for _ in pairs(near) do n = n + 1 end
    if best then
      message(string.format('Anschlussfracht in der Nähe: %d %s mit Ladung – die nächste ist %s (%s). Auf der Karte orange markiert, dort im türkisen Kreis Enter.',
        n, n == 1 and 'Firma' or 'Firmen', best.name, best.d < 1000 and (math.floor(best.d / 10) * 10 .. ' m') or (string.format('%.1f km', best.d / 1000):gsub('%.', ','))))
    end
  end
  save()
end

function L.phaseText(job)
  local p = job.phase
  if p == 'toPickup' then return 'Fahre zur Ladestelle' end
  if p == 'toTrailer' then
    return S.settings.hitch == 'auto' and 'Zum Auflieger (grüne Fläche) – rückwärts ran und anhalten'
      or 'Zum Auflieger (grüne Fläche) – rückwärts darunter und L drücken'
  end
  if p == 'atPickup' then return 'Anhalten – Auflieger wird bereitgestellt' end
  if p == 'hitching' then
    if R.hitchStep == 'manual' then return 'Unter den Auflieger setzen und L drücken' end
    return 'Auflieger wird angekuppelt …'
  end
  if p == 'toDelivery' then
    if job.loadLost then return 'Ladung verloren – Auftrag gescheitert' end
    if R.trailerId and not isCoupled() then return 'Auflieger verloren! Zurück und ankuppeln (L)' end
    if L.needsSecure() then return 'Ladung sichern: anhalten, Strg+Umschalt+G' end
    if R.dropSpot then return 'Auflieger in die blaue Fläche stellen' end
    return 'Fahre zum Kunden'
  end
  if p == 'atDelivery' then
    return R.dropSpot and 'Auflieger steht in der Fläche – anhalten und abkuppeln (L)' or 'Auflieger abstellen: anhalten und abkuppeln (L)'
  end
  if p == 'unloading' then return 'Wird entladen …' end
  if p == 'needTrailer' then return 'Auflieger fehlt – neu bereitstellen lassen' end
  if p == 'onFerry' then return 'Überfahrt – gleich da' end
  return ''
end

local function nearTarget(target, radius)
  local p = here()
  local d = dist(p, target)
  if d and d <= radius then return true end
  local e = routeEnd()
  if e then
    local d2 = dist(p, e)
    if d2 and d2 <= radius and dist(e, target) < 2000 then return true end
  end
  return false
end

local function trailerNearTruck()
  local a, b = vehPos(careerVeh()), vehPos(vehById(R.trailerId))
  return a and b and a:distance(b) <= C.TRAILER_NEAR_M
end

local function watchCargo()
  if not R.trailerId then return end
  local cond = cargoCondition()
  if R.lastCond and cond < R.lastCond - 0.01 then
    R.cargoHit = { t = now() + 4, cond = cond }
    notify(string.format('Ladung beschädigt! Zustand %d %%', round(cond * 100)), 5)
    story('cargoHit')
  end
  R.lastCond = cond
end

-- (2026-11-08) the EU tanker configurations are drawbar trailers (a dolly with a pintle), no semi trailers: a job that was
-- given one could never be hitched. Such a job gets the semi tanker of the same kind, at the loading place again.
L.SEMI_TANKER = { diesel = 'diesel_3', petrol = 'petroleum_3', milk = 'milk_3', cream = 'milk_3' }
function L.healTrailer(job)
  local tr = job and job.trailer
  if not tr or tr.model ~= 'eu_trailers' or not tostring(tr.config):find('^tanker') then return false end
  local cfg = L.SEMI_TANKER[job.cargo] or (tostring(tr.config):find('milk') and 'milk_3' or 'diesel_3')
  local info = L.trailerInfo('tanker', cfg)
  job.trailer = { model = 'tanker', config = cfg, name = info.name, preview = info.preview }
  deleteTrailer()
  R.hitchStep, R.closeT = nil, 0
  job.phase = 'toPickup'
  navTo(job.from, 'Laden: ' .. tostring(job.from.name))
  message('Der Tank-Auflieger für deinen Auftrag wurde getauscht – der alte passte nicht auf die Sattelkupplung. Er steht gleich an der Ladestelle bereit.')
  save()
  return true
end

local function updateJob(dtSim)
  local job = S.job
  if not job then return end
  pcall(L.healTrailer, job)
  job.elapsed = job.elapsed + dtSim
  local truck = careerVeh()
  if not truck and not adoptPlayerVehicle() then return end
  truck = careerVeh()
  local inTruck = be:getPlayerVehicleID(0) == R.truckId
  local speed = vehSpeed(truck)

  local t = now()
  local trySpot = not R.spotTry or t - R.spotTry > 2

  if job.phase == 'toPickup' then
    -- close to the depot: the trailer is put in a marked spot on its grounds; the GPS leads to it
    if not R.pickupSpot and trySpot and (dist(here(), job.from) or 1e9) < 450 then
      R.spotTry = t
      local ok, spot = pcall(spots.compute, job.from.lat, job.from.lon, earthAnchor())
      if ok and spot then
        R.pickupSpot = spot
        spots.show(spot, { 0.3, 0.95, 0.5, 1 })
        spawnTrailer(spot)
        if spot.glat then navTo({ lat = spot.glat, lon = spot.glon }, 'Auflieger: ' .. tostring(job.from.name)) end
        notify('🅿️ Dein Auflieger steht in der grünen Fläche bei ' .. tostring(job.from.name), 7)
        return
      end
    end
    if not R.pickupSpot and inTruck and speed < 3 and nearTarget(job.from, C.ARRIVE_PICKUP_M) then job.phase = 'atPickup' end
  elseif job.phase == 'toTrailer' then
    local trailer = vehById(R.trailerId)
    if not trailer then clearSpots(); job.phase = 'needTrailer'; return end
    spots.refresh(R.pickupSpot, earthAnchor())
    -- automatic hitching: backed up close to the trailer and stopped for a moment
    local d = vehPos(truck):distance(vehPos(trailer))
    if S.settings.hitch == 'auto' and inTruck and d < 20 and speed < 1 then
      R.closeT = (R.closeT or 0) + dtSim
      if R.closeT > 1.5 and autoHitch() then
        job.phase, R.hitchStep, R.hitchT = 'hitching', 'locking', t
      end
    else
      R.closeT = 0
    end
    if isCoupled() then job.phase, R.hitchStep, R.hitchT = 'hitching', 'locking', t end
  elseif job.phase == 'atPickup' then
    if speed < 1 then navClear(); spawnTrailer() end
  elseif job.phase == 'hitching' then
    local t = now() - R.hitchT
    if R.hitchStep == 'wait' and t > 1.0 then
      local trailer = vehById(R.trailerId)
      if trailer and (not trailer.isReady or trailer:isReady()) then
        if S.settings.hitch == 'auto' and autoHitch() then
          R.hitchStep = 'locking'
        else
          L.parkTrailerBehind(4)
          R.hitchStep = 'manual'
          notify('Setz zurück unter den Auflieger und drück L zum Ankuppeln.', 8)
        end
        R.hitchT = now()
      end
    elseif R.hitchStep == 'locking' and not isCoupled() and t > C.HITCH_TIMEOUT_S then
      R.hitchStep = 'manual'
      notify('Automatisches Ankuppeln hat nicht geklappt – bitte selbst mit L ankuppeln.', 8)
    end
    if isCoupled() then
      job.phase = 'toDelivery'
      clearSpots()
      R.lastCond = cargoCondition()
      navTo(job.to, 'Kunde: ' .. tostring(job.to.name))
      notify('Auflieger gekuppelt – gute Fahrt!', 5)
    end
  elseif job.phase == 'toDelivery' then
    local trailer = vehById(R.trailerId)
    if not trailer then clearSpots(); job.phase = 'needTrailer'; return end
    watchCargo()
    -- the driving style on the way (the settlement card's stars): time well over the limit, hard braking
    if dtSim > 0 then
      local stl = job.style or { t = 0, over = 0, harsh = 0, tv0 = S.tacho and S.tacho.vtotal or 0 }
      job.style = stl
      stl.t = stl.t + dtSim
      if R.limit and speed * 3.6 > R.limit + 8 then stl.over = stl.over + dtSim end
      local dv = R.styleV and (speed - R.styleV) / dtSim or 0
      R.styleV = speed
      if dv < -4.5 and speed > 3 and (not R.harshAt or t - R.harshAt > 3) then stl.harsh = stl.harsh + 1; R.harshAt = t end
    end
    local st = gpsStatus()
    job.routeError = st and st.routeError or nil
    -- close to the customer: the drop spot is marked on the grounds and the GPS leads to it
    if not R.dropSpot and trySpot and not job.to.pending and (dist(here(), job.to) or 1e9) < 500 then
      R.spotTry = t
      local ok, spot = pcall(spots.compute, job.to.lat, job.to.lon, earthAnchor())
      if ok and spot then
        R.dropSpot = spot
        spots.show(spot, { 0.37, 0.7, 1, 1 })
        if spot.glat then navTo({ lat = spot.glat, lon = spot.glon }, 'Kunde: ' .. tostring(job.to.name)) end
        notify('🅿️ Abstellfläche beim Kunden markiert (blau) – Auflieger dort abstellen', 7)
      end
    end
    -- at the customer, standing with the trailer for a while but not in the marked spot (it may lie where it cannot be
    -- seen or reached: Enschede, 2026-11-03 – no blue area): the place where the truck stands is the drop place
    -- (BeamNG.Earth 1.8.1: "arrived" along the planned route – its end reached on it, or the place reached off it
    -- across a yard; a gate round a corner is no longer "too far" in a straight line)
    local atCustomer = (nearTarget(job.to, C.ARRIVE_DELIVERY_M) or L.gpsArrived(st, job.to)) and trailerNearTruck() and speed < 1
    R.nearSince = atCustomer and (R.nearSince or t) or nil
    if R.dropSpot and R.nearSince and t - R.nearSince > 6 and not spots.contains(R.dropSpot, vehPos(trailer), 3) then
      clearSpots()
      job.phase = 'atDelivery'
      notify('Abgabe hier beim Kunden – Auflieger abkuppeln.', 7)
      return
    end
    if R.dropSpot then
      spots.refresh(R.dropSpot, earthAnchor())
      if spots.contains(R.dropSpot, vehPos(trailer), 3) then
        job.phase = 'atDelivery'
        spots.setColor({ 0.3, 0.95, 0.5, 1 })
      end
    elseif nearTarget(job.to, C.ARRIVE_DELIVERY_M) and trailerNearTruck() then
      job.phase = 'atDelivery'
    end
  elseif job.phase == 'atDelivery' then
    local trailer = vehById(R.trailerId)
    if not trailer then clearSpots(); job.phase = 'needTrailer'; return end
    watchCargo()
    local stillThere = R.dropSpot and spots.contains(R.dropSpot, vehPos(trailer), 6) or (not R.dropSpot and nearTarget(job.to, C.ARRIVE_DELIVERY_M * 1.5))
    if not stillThere then
      job.phase = 'toDelivery'
      if R.dropSpot then spots.setColor({ 0.37, 0.7, 1, 1 }) end
    elseif not isCoupled() and speed < 1 and (R.dropSpot or trailerNearTruck()) then
      job.phase = 'unloading'
      R.unloadT = 0
    end
  elseif job.phase == 'unloading' then
    if isCoupled() then job.phase = 'atDelivery'; return end
    R.unloadT = R.unloadT + dtSim
    if R.unloadT >= C.UNLOAD_S then L.completeJob() end
  end
end

------------------------------------------------------------------------------------------
-- navigation targets the player picks (the route advisor, the office map)

-- (2026-11-09) the accessories for the cab: the online shop, the workshop
L.acc = require('fernfahrer/accessories')
-- (2026-11-09) people at the rest area (encounters.lua): the truck has stood for a moment in the ring, someone knocks. Never in the first tour, not after every stop.
-- (2026-11-09) "attempt to index a nil value" in the game's own traffic/vehicle.lua, checkCollisions: a vehicle just deleted (a service truck leaving) was still in map.objects for that frame.
-- One failed check is nothing to bring a red error up for: the method is called through a guard.
function L.trafficGuard(t)
  if t - (R.tgT or 0) < 5 then return end
  R.tgT = t
  local gt = rawget(_G, 'gameplay_traffic')
  if not gt or not gt.getTrafficData then return end
  local _, tv = next(gt.getTrafficData() or {})
  local cls = tv and getmetatable(tv)
  if type(cls) ~= 'table' or type(cls.checkCollisions) ~= 'function' or cls.ffGuarded then return end
  local orig = cls.checkCollisions
  cls.ffGuarded = true
  cls.checkCollisions = function(self, ...)
    local ok, err = pcall(orig, self, ...)
    if not ok then log('D', logTag, 'traffic check skipped for one frame: ' .. tostring(err)) end
  end
  log('I', logTag, 'traffic: collision check guarded')
end
-- (2026-11-09) "Zum Hof": the truck sank into the ground: it was set down the moment the yard's objects existed, before their collision was in. Now it is held still meanwhile, set down
-- a moment after the yard stands, and looked at again; the loading screen stays until that is done (uiTrip waits for R.parkAtYard).
function L.parkDone(v)
  if v then v:queueLuaCommand('controller.setFreeze(0)') end
  R.parkAtYard = nil
end
function L.parkTick(t)
  local P, v = R.parkAtYard, careerVeh()
  if v and P.frozen ~= v:getID() and not P.settleAt then P.frozen = v:getID(); v:queueLuaCommand('controller.setFreeze(1)') end
  local sp = yard.parkSpot()
  if P.settleAt then
    if t < P.settleAt then return end
    P.settleAt = nil
    if v and sp and vehPos(v).z < sp.pos.z - 0.8 and (P.tries or 0) < 4 then
      log('W', logTag, string.format('yard: the truck stood %.1f m low, set down again', sp.pos.z - 0.6 - vehPos(v).z))
    else
      return L.parkDone(v)
    end
  end
  -- (2026-11-09: the ground has to be there; the houses around may take a minute, the truck stands on the yard's own slab and does not wait for them)
  local w = earthLoading()
  if sp and v and not (w and (w.ground or (w.buildings and yard.builtAge() < 10))) and yard.builtAge() >= 1.8 and vehPos(v):distance(sp.pos) < 800 then
    log('I', logTag, string.format('yard: truck set down at the hall (it was %.0f m away)', vehPos(v):distance(sp.pos)))
    pcall(spawn.safeTeleport, v, sp.pos, quatFromDir(sp.dir, vec3(0, 0, 1)))
    v:queueLuaCommand('controller.setFreeze(0)')
    P.tries, P.settleAt, P.frozen = (P.tries or 0) + 1, t + 1.8, v:getID()
  elseif t > P.untilT then
    L.parkDone(v)
  end
end
-- (2026-11-09) the workshop by parts. BeamNG keeps the condition per part, so one group can be put right on its own: its parts' integrity back to 1, their odometer untouched.
-- The kilometres stay: nothing is exchanged for a new engine. Applied in the vehicle's own Lua, again after each spawn (own.repaired).
L.PARTS = {
  { key = 'motor', icon = '🔩', verb = 'Motor instand setzen', pat = { 'engine', 'turbo', 'radiator', 'intake', 'exhaust', 'oilpan', 'fuel', 'ecu', 'injector', 'intercooler' } },
  { key = 'antrieb', icon = '⚙', verb = 'Getriebe und Antrieb überholen', pat = { 'transmission', 'gearbox', 'clutch', 'transfer', 'differential', 'driveshaft', 'halfshaft', 'finaldrive' } },
  { key = 'fahrwerk', icon = '🛞', verb = 'Fahrwerk und Bremsen überholen', pat = { 'suspension', 'axle', 'leaf', 'coilover', 'spring', 'shock', 'steering', 'wheel', 'tire', 'brake', 'hub', 'strut' } },
  { key = 'karosserie', icon = '🎨', verb = 'Karosserie aufbereiten' },
}
function L.partGroup(id)
  local s = tostring(id):lower()
  for _, g in ipairs(L.PARTS) do for _, q in ipairs(g.pat or {}) do if s:find(q, 1, true) then return g.key end end end
  return 'karosserie'
end
function L.partsCmd(groups)
  local G = {}
  for _, g in ipairs(L.PARTS) do if g.pat then G[#G + 1] = { g.key, g.pat } end end
  return 'if partCondition and partCondition.getConditions then local G = ' .. serialize(G) .. ' local W = ' .. serialize(groups) .. ' local c = partCondition.getConditions() ' ..
    'if c then for id, p in pairs(c) do local s, g = tostring(id):lower(), "karosserie" ' ..
    'for _, e in ipairs(G) do for _, q in ipairs(e[2]) do if s:find(q, 1, true) then g = e[1] break end end if g ~= "karosserie" then break end end ' ..
    'if W[g] then p.integrityValue = 1 p.integrityState = nil if g == "karosserie" then p.visualValue = 1 p.visualState = nil end end end ' ..
    'partCondition.initConditions(c) if partCondition.setResetSnapshotKey then partCondition.setResetSnapshotKey(nil) end end end'
end
function L.partHealth()
  if type(R.lastCond) ~= 'table' then return nil end
  local H = {}
  for id, p in pairs(R.lastCond) do
    if type(p) == 'table' and tonumber(p.integrityValue) then
      local k, h = L.partGroup(id), nil
      h = H[k] or { int = 1, vis = 1 }
      h.int, h.vis = math.min(h.int, p.integrityValue), math.min(h.vis, tonumber(p.visualValue) or 1)
      H[k] = h
    end
  end
  return H
end
function L.partCost(own, key, h)
  local price = own.newPrice or own.price or 80000
  local bad = 1 - math.min(h.int, key == 'karosserie' and h.vis or 1)
  if key == 'motor' then return round(math.max(1200, price * 0.015) + (own.km or 0) * 0.003 + bad * price * 0.2, 50) end
  return round(math.max(key == 'karosserie' and 400 or 700, bad * price * 0.2), 50)
end
function L.kmText(km) return (tostring(math.floor((km or 0) / 1000 + 0.5) * 1000):reverse():gsub('(%d%d%d)', '%1.'):reverse():gsub('^%.', '')) end
function L.partActs(add)
  local own = L.ownTruck()
  local H = L.partHealth()
  if not own or not H or L.activeKind() ~= 'truck' then return end
  local done = own.repaired or {}
  for _, g in ipairs(L.PARTS) do
    local h = H[g.key]
    if h and (h.int < 0.995 or (g.key == 'karosserie' and h.vis < 0.95) or (g.key == 'motor' and (own.km or 0) >= 150000 and not done.motor)) then
      local c = L.partCost(own, g.key, h)
      local text = g.key == 'motor' and ('Läuft nicht mehr rund. Die ' .. L.kmText(own.km) .. ' km bleiben') or (g.key == 'karosserie' and 'Lack, Dellen und Rost, die Technik bleibt, wie sie ist' or 'Nur diese Teile, der Rest bleibt, wie er ist')
      add('part:' .. g.key, g.icon, g.verb, string.format('%s · %s', money(c), text), { disabled = S.money < c or nil })
    end
  end
end
-- (after the reset of an accident repair: the wear and the kilometres of every part back on, only the accident's damage gone)
function L.condApply(v, cond, keepState)
  local c = {}
  for id, p in pairs(cond) do
    local q = {}
    for k, x in pairs(p) do q[k] = x end
    if not keepState then q.integrityState, q.visualState = nil, nil end
    c[id] = q
  end
  R.condRestoringUntil = now() + 3
  v:queueLuaCommand('if partCondition and partCondition.initConditions then partCondition.initConditions(' .. serialize(c) .. ') if partCondition.setResetSnapshotKey then partCondition.setResetSnapshotKey(nil) end end')
end
function L.accCamHook()
  if not S or not R.accDt then return end
  R.accHookT = now()
  L.acc.noLearn = vices.override ~= nil
  local dt = R.accDt
  R.accDt = nil
  pcall(L.acc.render, careerVeh(), L.accTruck(), dt)
end
-- (2026-11-09) the work done, shown: the truck held still, the camera going round it in three shots, ratchets and an impact wrench; what was ordered happens at the end
function L.workMsg(text) notify('🛠 ' .. text, 8); message(text, 'Werkstatt') end
function L.workStart(o)
  local v = careerVeh() or playerVeh()
  if not v or R.workShow then return false end
  local len = o.len or 10
  R.workShow = { t0 = now(), len = len, done = o.done, id = v:getID() }
  v:queueLuaCommand('controller.setFreeze(1)')
  navigate('play')
  vices.installCam()
  vices.override = L.workCam
  guihooks.trigger('FernfahrerWork', { title = o.title, sub = o.sub, len = len })
  if Engine and Engine.Audio and Engine.Audio.playOnce then
    local ok, res = pcall(Engine.Audio.playOnce, 'AudioGui', 'art/sound/fernfahrer/mood/gad_werkstatt.wav', { volume = 0.8 })
    R.workShow.src = ok and type(res) == 'table' and res.sourceId or nil
  end
  R.navDuckUntil = now() + len
  return true
end
function L.workCam(x, y, z, qx, qy, qz, qw, fov)
  local W = R.workShow
  local v = W and getObjectByID(W.id)
  if not v then return x, y, z, qx, qy, qz, qw, fov end
  local c, F = vehPos(v), vec3(v:getDirectionVector())
  F.z = 0
  F = F:normalized()
  local side, up = vec3(F.y, -F.x, 0), vec3(0, 0, 1)
  local k = math.min(0.999, (now() - W.t0) / W.len)
  local shot, s = math.floor(k * 3) + 1, (k * 3) % 1
  local pos, at
  if shot == 2 then
    pos, at = c + F * (4.4 - s * 0.9) + side * 3 + up * 0.5, c + F * 2.4 + up * 0.6
  else
    local a = shot == 1 and (0.7 + s * 0.9) or (3.7 + s * 0.8)
    local r = shot == 1 and 8.2 or 7.2
    pos, at = c + F * (math.cos(a) * r) + side * (math.sin(a) * r) + up * (shot == 1 and 2.1 or 3.1), c + up * 0.9
  end
  local q = quatFromDir((at - pos):normalized(), up)
  return pos.x, pos.y, pos.z, q.x, q.y, q.z, q.w, 50
end
function L.workEnd()
  local W = R.workShow
  if not W then return end
  R.workShow, R.stopOpen = nil, false
  if vices.override == L.workCam then vices.override = nil end
  local v = getObjectByID(W.id)
  if v then v:queueLuaCommand('controller.setFreeze(0)') end
  if W.src and scenetree and scenetree.findObjectById then local o = scenetree.findObjectById(W.src); if o and o.stop then pcall(o.stop, o, 0.4, 1) end end
  guihooks.trigger('FernfahrerWork', { off = true })
  if W.done then pcall(W.done) end
end
function L.workTick()
  local W = R.workShow
  if not W then return end
  R.stopOpen = true                                 -- (no mirrors, no HUD over it, nobody knocking)
  if now() - W.t0 >= W.len then L.workEnd() end
end
function M.workSkip() if R.workShow then R.workShow.len = 0 end end
L.enc = require('fernfahrer/encounters')
-- (2026-11-09) quiet music under the moments (mood.lua). The radio goes silent only for the rest area and a talk at the window, and comes back; "Nur ohne Radio" leaves it alone.
L.mood = require('fernfahrer/mood')
L.MOOD_LEVEL = { low = 0.6, mid = 1, high = 1.4 }
function L.moodRadio() return S.settings.radioOn ~= false and R.radioHelper == true end
function L.moodTick(force)
  local t = now()
  if not force and t - (R.moodT or 0) < 1 then return end
  local dtc = math.min(2, t - (R.moodT or t))
  R.moodT = t
  local set = S and S.settings and S.settings.mood or 'all'
  if not S or not R.mode or set == 'off' or R.workShow or R.loadAt or R.trip or R.pendingTeleport or R.sleep or R.officeOpen or R.boot ~= nil or cinematic.active() or L.gamePaused() then
    R.moodMute = nil
    L.mood.want(nil, t)
    return
  end
  L.mood.setLevel(L.MOOD_LEVEL[S.settings.moodVol or 'mid'] or 1)
  local v = careerVeh()
  local spd = v and vehSpeed(v) or 0
  local talk, want, drive = R.cop ~= nil or L.enc.active(), nil, false
  if R.cop then want = 'polizei'
  elseif talk then want = R.moodBed or nil
  else
    local n = R.near
    local atRest = v ~= nil and n ~= nil and (n.type == 'rest' or n.parking) and stops.inside() ~= nil
    if atRest and spd < 0.6 then R.moodStill = (R.moodStill or 0) + dtc elseif spd > 3 or not atRest then R.moodStill = 0 end
    if (R.moodStill or 0) >= 4 then want = 'rast'
    else
      -- (on the road, now and then, when nothing else is playing)
      R.moodDriveAt = R.moodDriveAt or (t + 300 + math.random() * 400)
      if R.moodDriveUntil and t >= R.moodDriveUntil then R.moodDriveUntil = nil end
      if not R.moodDriveUntil and t >= R.moodDriveAt and spd > 12 then
        R.moodDriveUntil, R.moodDriveAt = t + 52, t + 700 + math.random() * 800
        local h = S.clockHours or 12
        R.moodDriveCue = (h >= 21 or h < 5) and 'fahrt_nacht' or 'fahrt_tag'
      end
      if R.moodDriveUntil then want, drive = R.moodDriveCue, true end
    end
  end
  local radio = L.moodRadio()
  R.moodMute = (radio and set == 'all' and (talk or (want ~= nil and not drive))) or nil
  if radio and (drive or set == 'noradio') then want = nil end
  L.mood.want(want, t)
end
function L.moodSting(name)
  if not S or not S.settings or S.settings.mood == 'off' or R.loadAt then return end
  local radio = L.moodRadio()
  if radio and S.settings.mood == 'noradio' then return end
  L.mood.setLevel(L.MOOD_LEVEL[S.settings.moodVol or 'mid'] or 1)
  local len = L.mood.sting(name, now())
  if len and radio then R.navDuckUntil = now() + len end
end
function L.encDiesel(liters)
  local veh = playerVeh()
  if not veh or not core_vehicleBridge then return end
  core_vehicleBridge.requestValue(veh, function(ret)
    local left = liters
    for _, tank in ipairs((ret and ret[1]) or {}) do
      local f = FUEL[tank.energyType]
      if f and tank.maxEnergy and tank.currentEnergy and left > 0 then
        local add = math.min(left, math.max(0, (tank.maxEnergy - tank.currentEnergy) / 1e6 / f.mj))
        if add > 0.05 then core_vehicleBridge.executeAction(veh, 'setEnergyStorageEnergy', tank.name, tank.currentEnergy + add * f.mj * 1e6); left = left - add end
      end
    end
    R.fuelT = 0
  end, 'energyStorage')
end
function L.encCtx()
  return {
    money = function() return S.money end, fmt = money, pay = function(c, a, l) L.pay(c, a, l) end, xp = function(n) addXp(n) end,
    notify = notify, message = message, save = function() save() end, fine = function(a, w) M.fine(a, w) end,
    km = function() return S.stats.odoKm or 0 end, job = function() return S.job end, hasTrailer = function() return R.trailerId ~= nil end,
    trigger = function(n, d) guihooks.trigger(n, d) end,
    give = function(id) S.acc = S.acc or {}; S.acc.inv = S.acc.inv or {}; S.acc.inv[id] = (S.acc.inv[id] or 0) + 1 end,
    cab = function(k, n) local i = L.inv(); i[k] = (i[k] or 0) + n end,
    tired = function(d) S.fatigue = math.max(0, math.min(1, (S.fatigue or 0) + d)) end,
    diesel = function(l) pcall(L.encDiesel, l) end, fail = function(k) pcall(service.forceFail, k) end,
    freight = function(f) if S.job then S.job.freight = round(S.job.freight * f, 10) end end,
    look = function(on) if on then vices.installCam(); vices.setLook(-66, -5) else vices.setLook(0, 0) end end,
    stage = function(shape) local v = careerVeh(); if v then pcall(L.restCheckStage, v, shape) end end,
    clean = function() L.restCheckClean() end,
    bed = function(b) R.moodBed = b or false; pcall(L.moodTick, true) end,
    knock = function(k) L.mood.knock(k) end,
  }
end
function L.encAttach()
  if R.encFor == S then return end
  L.enc.reset()
  S.enc = S.enc or {}
  L.enc.attach(S.enc, L.encCtx())
  R.encFor = S
end
function L.encForce()
  L.encAttach()
  R.encTest = L.enc.nextForTest()
  R.encStill = 0
  notify('Halte an und bleib kurz stehen: Gleich klopft jemand an die Tür.', 6)
end
function L.encTick(t)
  if not S or not R.mode or t - (R.encT or 0) < (L.enc.active() and 0.12 or 1) then return end
  local dtc = math.min(2, t - (R.encT or t))
  R.encT = t
  L.encAttach()
  L.enc.kmTick(S.stats.odoKm or 0)
  local v = careerVeh()
  if L.enc.active() then L.enc.tick(v ~= nil and vehSpeed(v) > 3); return end
  if not v or vehSpeed(v) > 0.6 or R.cop or R.rcScene or R.restCheck or R.trip or R.pendingTeleport or R.sleep or R.officeOpen or R.stopOpen
    or cinematic.active() or L.gamePaused() then R.encStill = 0; return end
  if R.encTest then
    R.encStill = (R.encStill or 0) + dtc
    if R.encStill >= 2 then local k = R.encTest; R.encTest = nil; L.enc.start(k) end
    return
  end
  local n = R.near
  if not (n and (n.type == 'rest' or n.parking) and stops.inside()) then R.encVisit, R.encStill = nil, 0; return end
  if R.encVisit == n.id or (S.tut and not S.tut.done) then return end
  R.encStill = (R.encStill or 0) + dtc
  R.encWait = R.encWait or (3 + math.random() * 6)
  if R.encStill < R.encWait then return end
  R.encVisit, R.encWait = n.id, nil
  local km, nxt = S.stats.odoKm or 0, L.enc.nextKm()
  if nxt and (km < nxt or math.random() > L.enc.CHANCE) then return end         -- (the first time: always)
  if L.enc.start(L.enc.pick()) then L.enc.setNext(km) end
end
function L.accTruck()
  local def, loaner = activeDef()
  if not def or def.rental or def.kind == 'car' then return nil end
  if loaner then
    -- (2026-11-09: the hired truck has a little of its own: what can be hung up)
    S.loanerFit = S.loanerFit or { loaner = true }
    local t = S.loanerFit
    t.model, t.brand, t.modelName = def.model, 'Leih-Lkw', def.modelName or ''
    return t
  end
  return def
end
function L.accTick(t)
  if not S then return end
  if R.accFor ~= S then S.acc = S.acc or {}; L.acc.attach(S.acc); R.accFor = S
    L.acc.setCtx({ notify = notify, tired = function(d) S.fatigue = math.max(0, math.min(1, (S.fatigue or 0) + d)) end,
      cab = function(k, n) local i = L.inv(); i[k] = (i[k] or 0) + n end, clock = function() return clockText() end,
      play = function(f, vol) if Engine and Engine.Audio and Engine.Audio.playOnce then pcall(Engine.Audio.playOnce, 'AudioGui', 'art/sound/fernfahrer/mood/' .. f .. '.wav', { volume = vol }) end end,
      radioLine = function()
        if S.settings.radioOn == false or not R.radioHelper then return 'Radio aus' end
        local i = R.radioInfo
        return (i and (i.title ~= '' and i.title or i.status)) or 'Radio'
      end })
  end
  if t - (R.accT or 0) < 2 then return end
  R.accT = t
  local got = L.acc.tick()
  if got then notify('📦 Dein Paket ist am Hof: ' .. got .. '. Einbauen in der Werkstatt am Hof.', 8); save() end
  if t - (R.fuelSaveT or 0) > 60 then R.fuelSaveT = t; pcall(parked.fuelSave) end
end
function M.uiShop()
  if R.accFor ~= S then L.accTick(now()) end
  local v = L.acc.shopView(L.accTruck())
  v.money = S.money
  return v
end
function M.shopOrder(id)
  local it = L.acc.BY[id]
  if not it then return M.uiShop() end
  if S.money < it.price then notify('Nicht genug Geld für ' .. it.name .. '.', 4); return M.uiShop() end
  L.pay('Einkauf', -it.price, 'Online-Shop: ' .. it.name)
  L.acc.order(id)
  notify('📦 Bestellt: ' .. it.name .. '. Wird an deinen Hof geliefert.', 5)
  save()
  return M.uiShop()
end
function M.uiGarage()
  if R.accFor ~= S then L.accTick(now()) end
  local t = L.accTruck()
  if not t then return { error = 'In diesem Fahrzeug kann nichts eingebaut werden.' } end
  return L.acc.garageView(t)
end
function M.garageFit(id) if L.acc.fit(L.accTruck(), id) then save() end; return M.uiGarage() end
function M.garageRemove(id) if L.acc.unfit(L.accTruck(), id) then save() end; return M.uiGarage() end
function M.garageNudge(id, axis, d) L.acc.nudge(L.accTruck(), id, axis, d); save(); return M.uiGarage() end
function L.garageCam(x, y, z, qx, qy, qz, qw, fov)
  local c = L.acc.garageCam(R.garageView or 'fahrer')
  if not c then return x, y, z, qx, qy, qz, qw, fov end
  local q = quatFromDir(c.dir, c.up)
  return c.pos.x, c.pos.y, c.pos.z, q.x, q.y, q.z, q.w, c.fov
end
function M.garageView(mode) R.garageView = mode end
function M.garageSelect(id) L.acc.sel = id end
function M.garageAlign(id) L.acc.alignDash(L.accTruck(), id); save(); return M.uiGarage() end
function M.garagePhotos() return L.acc.photos() end
function M.garagePhoto(file) L.acc.choosePhoto(L.accTruck(), file); save(); return M.uiGarage() end
function M.garageFace(id) L.acc.face(L.accTruck(), id); save(); return M.uiGarage() end
function M.garageOpen()
  R.stopOpen, R.brakeOffAt = true, nil
  L.autoBrake()
  local ok, name = pcall(core_camera.getActiveCamName, 0)
  R.garageCam = ok and name or nil
  pcall(core_camera.setByName, 0, 'onboard.driver')
  vices.setLook(0, 0)
  vices.installCam()
  R.garageOn, R.garageView = true, 'fahrer'
  L.acc.inGarage = true
  vices.override = L.garageCam
  return true
end
function M.garageClose()
  R.stopOpen, R.brakeOffAt = false, now() + 0.8
  R.garageOn = nil
  L.acc.inGarage = false
  L.acc.sel = nil
  if vices.override == L.garageCam then vices.override = nil end
  vices.setLook(0, 0)
  if R.garageCam and R.garageCam ~= 'onboard.driver' then pcall(core_camera.setByName, 0, R.garageCam) end
  R.garageCam = nil
  save()
end

function M.navToPlace(id)
  -- (a fuel station of Earth's: not in the depots)
  if type(id) == 'string' and id:sub(1, 10) == 'earthfuel:' then
    local f = parked.fuelAll()[id:sub(11)]
    if not f then for k, x in pairs(parked.fuelAll()) do if tostring(k) == id:sub(11) then f = x; break end end end
    if f then local n = L.neutralName('fuel', f.name, nil, f.lat, f.lon); navTo({ lat = f.lat, lon = f.lon, name = n }, n); notify('Route: ' .. n, 4) end
    return
  end
  if type(id) == 'string' and id:sub(1, 4) == 'far:' then
    local la, lo, ty = id:match('^far:([%d%.%-]+):([%d%.%-]+):(%w+)$')
    local t = ty and DEPOT_BY_KEY[ty]
    if t and tonumber(la) and tonumber(lo) then navTo({ lat = tonumber(la), lon = tonumber(lo), name = t.name }, t.name); notify('Route: ' .. t.name, 4) end
    return
  end
  for _, d in ipairs(S.depots) do
    if d.id == id then navTo(d, d.name); notify('Route: ' .. d.name, 4); return end
  end
end

function M.navToNearest(typeKey)
  local d = nearestOf(typeKey)
  if d then navTo(d, d.name); notify('Route zur nächsten ' .. (DEPOT_BY_KEY[typeKey] and DEPOT_BY_KEY[typeKey].name or 'Station') .. ': ' .. d.name, 5)
  else notify('Keine bekannte Station dieser Art in der Nähe.', 4) end
end

function M.navToHome() if S.home then navTo(S.home, S.home.name or 'Hof') end end

function M.navToJob()
  local job = S.job
  if not job then return end
  local pickup = job.phase == 'toPickup' or job.phase == 'atPickup' or job.phase == 'toTrailer'
  local t = pickup and job.from or job.to
  -- the marked spot when there is one
  local spot = pickup and R.pickupSpot or (not pickup and R.dropSpot) or nil
  if spot and spot.glat then t = { lat = spot.glat, lon = spot.glon, name = t.name } end
  navTo(t, (pickup and 'Laden: ' or 'Kunde: ') .. tostring(t.name))
end

------------------------------------------------------------------------------------------
-- traffic: BeamNG's traffic system with agent_traffic_mod's European cars when installed; the amount from the
-- PC's memory, then adjusted to the frame rate

function L.trafficBase()
  local gb = 16
  pcall(function() gb = (Engine.Platform.getMemoryInfo().osPhysAvailable or 16 * 2 ^ 30) / 2 ^ 30 end)
  local base = gb >= 30 and 8 or (gb >= 15 and 6 or 4)
  local mode = S.settings.traffic
  if mode == 'low' then base = math.max(2, base - 3) elseif mode == 'high' then base = base + 4 end
  return base
end

-- the simplified traffic vehicles (content/vehicles/simple_traffic): European models in Europe, American elsewhere;
-- a random mix of `n` (nil when the game lacks them)
L.SIMPLE_EU = { 'etk800_eu_base_sedan', 'etk800_eu_base_wagon', 'etk800_eu_high_wagon', 'etki_eu_facelift', 'etki_eu_pre',
  'etkc_eu_kc4', 'lansdale_eu_facelift_base', 'lansdale_eu_pre_mid', 'lansdale_eu_pre_van', 'sunburst2_eu_sedan_base',
  'sunburst2_eu_wagon_base', 'sunburst2_eu_wagon_sport', 'legran_wagon_facelift_regulier', 'legran_sedan_facelift_s',
  'covet_base', 'covet_high', 'vivace_base', 'vivace_standard', 'vivace_ev', 'bx_base_hatch', 'tograc_base',
  'tograc_standard', 'ardente_standard', 'ardente_ev', 'van_passenger_facelift', 'van_vanster_facelift', 'van_delivery',
  'van_cargobox', 'covet_drivingschool', 'etk800_eu_xc' }
L.SIMPLE_US = { 'fullsize_stock', 'fullsize_fleet', 'fullsize_taxi', 'midsize_dx', 'midsize_lx', 'pessima_standard',
  'pessima_sport', 'pickup_d15', 'pickup_d25', 'pickup_d15_fleet', 'roamer_base', 'roamer_standard_facelift',
  'wendover_pre_base', 'wendover_facelift_base', 'lansdale_facelift_base', 'lansdale_pre_mid', 'bastion_base',
  'bastion_taxi', 'sunburst2_sedan_base', 'sunburst2_wagon_base', 'van_passenger', 'van_vanster', 'van_delivery',
  'covet_base', 'etk800_base_wagon', 'legran_sedan_pre_regulier', 'pickup_d10', 'van_cargobox' }
function L.trafficSource()
  local v = S and S.settings.trafficCars
  if v == 'agent' or v == 'simple' then
    if v == 'agent' and not FS:fileExists(AGENT_GROUP) then return 'simple' end
    return v
  end
  return FS:fileExists(AGENT_GROUP) and 'agent' or 'simple'
end
function L.simpleGroup(n)
  if not (core_vehicles and core_vehicles.getModel and core_vehicles.getModel('simple_traffic')) then return nil end
  local src = inEurope() and L.SIMPLE_EU or L.SIMPLE_US
  local bag, out = {}, {}
  for i, c in ipairs(src) do bag[i] = c end
  for i = 1, math.max(1, n) do
    if #bag == 0 then for j, c in ipairs(src) do bag[j] = c end end
    local c = table.remove(bag, math.random(#bag))
    out[i] = { model = 'simple_traffic', config = c, paintName = 'random' }
  end
  return out
end

function M.startTraffic()
  if not S or S.settings.traffic == 'off' then return true end
  if not gameplay_traffic then extensions.load('gameplay_traffic') end
  local gt = rawget(_G, 'gameplay_traffic')
  if not gt then return false end
  if gt.getState and gt.getState() == 'on' then return true end
  local amount = L.trafficBase()
  -- a pool larger than what drives: the extra cars stand switched off (memory only, no physics) and the traffic
  -- system swaps them in as it respawns cars out of sight – so the mix changes over time (now a bus, later a lorry)
  -- while never more than `amount` drive at once
  local POOL_EXTRA = 4
  local total = amount + POOL_EXTRA
  local group
  -- (2026-11-07) the cars: Agent Traffic's European set (its own light cars, when the mod is installed – the default
  -- then) or the game's simplified traffic vehicles; setting "trafficCars"
  local src = L.trafficSource()
  local d = src == 'agent' and jsonReadFile(AGENT_GROUP) or nil
  if src == 'simple' then group = L.simpleGroup(total) end
  if not group and type(d) == 'table' and type(d.data) == 'table' and #d.data > 0 then
    group = d.data
    if core_multiSpawn and core_multiSpawn.fitGroup then
      local ok, fitted = pcall(core_multiSpawn.fitGroup, d.data, total)
      if ok and type(fitted) == 'table' and #fitted > 0 then group = fitted end
    end
  end
  -- variety: Agent Traffic has cars only – a bus, a lorry and a van from the game itself take three of the pool's
  -- places: heavy vehicles cost the most, so only these few, and they take turns with the cars
  if group and #group >= 6 then
    local heavy = inEurope() and {
      { model = 'citybus', config = 'city', paintName = 'random' },
      { model = 'percheron', config = 's310_4x2_box_A', paintName = 'random' },
      { model = 'van', config = 'h25_vanster', paintName = 'random' },
    } or {
      { model = 'citybus', config = 'city', paintName = 'random' },
      { model = 'md_series', config = 'md_70_cargobox_facelift', paintName = 'random' },
      { model = 'van', config = 'deliverytruck', paintName = 'random' },
    }
    local copy = {}
    for i, e in ipairs(group) do copy[i] = e end
    -- (with the simplified cars: one heavy vehicle in the pool only – the game has no simplified bus or lorry; it
    -- takes turns with the cars, so most of the time none drives)
    local nHeavy = 1
    local order = { 1, 2, 3 }
    if nHeavy == 1 and math.random() < 0.5 then order = { 2, 1, 3 } end
    for k = 1, nHeavy do
      local hv = heavy[order[k]]
      if core_vehicles.getModel(hv.model) then copy[#copy - k + 1] = hv end
    end
    group = copy
  end
  local ok, err = pcall(gt.setupTraffic, total, { vehGroup = group, activeAmount = amount })
  if not ok then log('W', logTag, 'traffic: ' .. tostring(err)); return false end
  R.traffic = { max = amount, active = amount, pool = total,
    source = (src == 'simple' and group) and 'BeamNG vereinfacht' or (group and 'Agent Traffic (EU)' or 'BeamNG') }
  log('I', logTag, string.format('traffic: %d driving, %d in the pool (%s)', amount, total, R.traffic.source))
  return true
end

function M.stopTraffic()
  local gt = rawget(_G, 'gameplay_traffic')
  if gt and gt.deleteVehicles then pcall(gt.deleteVehicles) end
  R.traffic = nil
end

function M.openAgentTrafficTool()
  local at = rawget(_G, 'core_agentTrafficTool')
  if at and at.show then at.show(); navigate('play')
  else notify('Agent Traffic Tool nicht gefunden (Mod aktiv?).', 5) end
end

-- (2026-11-04: the Pedestrians mod is no longer part of the career – the walkers cost too much)

-- Realistic AI Traffic Behaviors, when switched on: a truck-sim profile – smarter driving and overtaking on the
-- mode's own traffic, nothing extra (no own spawns, accidents, races, police, off-screen simulation, parking AI);
-- its debug window closed
local REALAI_PROFILE = {
  performanceMode = true, densityMultiplier = 1.0, globalAggression = 0.75, autoRaceEnabled = false,
  autoParkEnabled = false, enhanceOnly = true, enableTrafficSpawning = false, enableAccidentGeneration = false,
  enablePoliceEmergencySpawning = false, enableOffscreenEvents = false, enableOffscreenAI = false,
  offroadEnabled = false, raceLengthMeters = 900, maxRacers = 2,
}
-- Its drivers honk whenever they have to go slower than they like – behind a truck, that is all the time, and every
-- blocked moment makes them more likely to (up to 70 %). The mod has no setting for it, so each traffic car's horn
-- gets a brake inside the car: at most once in HORN_GAP_S, and only every other time (BeamNG's own horn calls and
-- the mod's both end in electrics.horn / electrics.set('horn')). The player's vehicles are left alone.
local HORN_GAP_S, HORN_PASS = 30, 0.5
local HORN_PATCH = string.format([[
if not _ffHornTamed and electrics then
  _ffHornTamed = true
  local last, gap, pass = -1e9, %d, %.2f
  local function allow()
    local n = os.clock()
    if n - last < gap or math.random() > pass then return false end
    last = n
    return true
  end
  if electrics.horn then
    local o = electrics.horn
    electrics.horn = function(on, ...) if on and not allow() then return end return o(on, ...) end
  end
  if electrics.set then
    local o = electrics.set
    electrics.set = function(k, v, ...) if k == 'horn' and v and v ~= 0 and not allow() then return end return o(k, v, ...) end
  end
end]], HORN_GAP_S, HORN_PASS)

local function tameHorns()
  local gt = rawget(_G, 'gameplay_traffic')
  if not rawget(_G, 'realAITraffic_bootstrap') or not gt or not gt.getTrafficList then return end
  local okL, list = pcall(gt.getTrafficList)
  if not okL or type(list) ~= 'table' then return end
  local playerId = be:getPlayerVehicleID(0)
  for _, id in pairs(list) do
    if id ~= playerId and id ~= R.truckId and id ~= R.trailerId then
      local v = getObjectByID(id)
      if v then v:queueLuaCommand(HORN_PATCH) end   -- (once per car: the flag lives in the car's Lua)
    end
  end
end

local function applyRealAI()
  local ra = rawget(_G, 'realAITraffic_bootstrap')
  if not ra then return false end
  pcall(function()
    if ra.applyUiSettings then ra.applyUiSettings(REALAI_PROFILE) end
    if ra.flushSettings then ra.flushSettings() end
    if ra.hideUI then ra.hideUI() end
  end)
  log('I', logTag, 'Realistic AI Traffic: truck profile applied')
  return true
end
M.applyRealAI = applyRealAI

local function adaptTraffic(dtReal)
  local f = R.fps
  f.t, f.n = f.t + dtReal, f.n + 1
  if f.t < C.FPS_WINDOW_S then return end
  local fps = f.n / f.t
  f.t, f.n = 0, 0
  R.fpsAvg = fps
  -- (aiming at 60 fps: the traffic gives way below 38 and comes back above 57; never fewer than 3 cars)
  local tr = R.traffic
  local gt = rawget(_G, 'gameplay_traffic')
  if not tr or not gt or not gt.setActiveAmount or S.settings.traffic == 'off' then return end
  if fps < 38 and tr.active > 3 then
    tr.active = tr.active - 1
    pcall(gt.setActiveAmount, tr.active)
  elseif fps > 57 and tr.active < tr.max then
    tr.active = tr.active + 1
    pcall(gt.setActiveAmount, tr.active)
  end
end

------------------------------------------------------------------------------------------
-- company: setup, home, bank, options

function M.uiSetup(d)
  if type(d) ~= 'table' then return { ok = false, error = 'keine Daten' } end
  local lat, lon = tonumber(d.lat), tonumber(d.lon)
  local name = tostring(d.company or ''):sub(1, 40)
  if not lat or not lon then return { ok = false, error = 'Bitte einen Hof auf der Karte wählen.' } end
  if name:gsub('%s', '') == '' then return { ok = false, error = 'Bitte einen Firmennamen eingeben.' } end
  R.tripNext = nil                               -- (the setup is done: the next loading screen ends on the road)
  deleteTrailer()
  navClear()
  S = defaults()
  S.company = { name = name, driver = tostring(d.driver or ''):sub(1, 30), founded = os.time() }
  if S.company.driver == '' then S.company.driver = 'Chef' end
  S.home = { lat = lat, lon = lon, name = tostring(d.homeName or 'Firmenhof'):sub(1, 60) }
  -- the start money by the chosen difficulty (2026-11-05: easy 100 000, medium 50 000, hard 10 000)
  local START = { easy = 100000, medium = 50000, hard = 10000 }
  S.difficulty = START[d.difficulty] and d.difficulty or 'medium'
  S.money = START[S.difficulty]
  R.offers, R.report = {}, nil
  story('founded')
  save()
  M.goHome(true)
  M.discoverDepots()
  -- (2026-11-05: as "Weiterspielen" – the loading screen until the yard is there, then the day's card, the camera
  -- flight and the introduction; it went straight onto the road before, with the world still loading round it)
  R.tripView = { mode = 'road', world = true, from = S.company.name, to = S.home.name or 'Firmenhof' }
  R.worldLoad = true
  R.tripArrivedAt = nil
  R.titleAt = now() + 3
  R.titleWait = nil
  return { ok = true, travel = true }
end

function M.goHome(withVehicle)
  if not S or not S.home then return end
  if L.pursuit.active() then notify('Nicht, solange die Polizei hinter dir her ist.', 4); return end
  -- (on foot at an airport: home in the own truck or the loaner – and no way of being stranded without money)
  if L.onFoot() then
    S.rental, S.rentalDesk, S.active = nil, nil, 'loaner'
    for id in pairs(S.owned or {}) do S.active = id; break end
    withVehicle = true
  end
  if R.trailerId then notify('Mit Auflieger geht das nicht – erst den Auftrag beenden.', 5); return end
  -- (2026-11-07: the damage goes along – the condition written fresh first, kept through the resets on the way)
  L.keepCondForTeleport()
  -- (the loading screen over the whole move: no more landing at the home marker, hovering there while the world
  -- loads and then a second jump to the yard – the screen stays until the truck stands in front of the hall)
  R.tripView = { mode = 'road', world = true, from = 'Unterwegs', to = S.company and S.company.name or 'Firmenhof' }
  R.tripArrivedAt, R.calmSince = nil, nil
  navigate('fernfahrerTravel')
  -- straight to the yard when it is known (the home marker only before the first yard)
  if S.yard and S.yard.lat then
    R.teleportTarget = { lat = S.yard.lat, lon = S.yard.lon, name = S.company and S.company.name or 'Firmenhof' }
  end
  R.teleportTries = 0
  R.pendingTeleport = now() + (withVehicle and 2.1 or 0.6)   -- (the condition back from the vehicle first)
  R.parkAtYard = { t = now() + 1, untilT = now() + 130 }     -- (then in front of the hall, once the yard stands)
  if withVehicle then
    runTask(function()
      local t0 = now()
      while now() - t0 < 0.5 do coroutine.yield() end
      local def = activeDef()
      if playerVeh() then core_vehicles.replaceVehicle(def.model, { config = def.config, autoEnterVehicle = true })
      else core_vehicles.spawnNewVehicle(def.model, { config = def.config, autoEnterVehicle = true }) end
      R.truckId, R.fuel = nil, nil
      R.pendingAdopt = now() + 0.5
    end)
  end
end

------------------------------------------------------------------------------------------
-- travel: ferries (the truck and its trailer go along) and flights (the driver alone; a rental car at the arrival)

local EU_CC = { DE = 1, AT = 1, CH = 1, FR = 1, NL = 1, BE = 1, LU = 1, DK = 1, SE = 1, NO = 1, FI = 1, EE = 1, PL = 1,
  CZ = 1, IT = 1, ES = 1, PT = 1, GB = 1, IE = 1, GR = 1, TR = 1 }

local function hubHere()
  local p = here()
  if not p then return nil end
  for _, x in ipairs(travel.hubsNear(p, 1.5)) do
    if x.dist <= (x.hub.kind == 'airport' and 1500 or 600) then return x.hub, x.dist end
  end
end

-- (2026-11-09) A flight takes the driver alone: on arrival one is on foot and walks to the rental desk (a ring near the arrival),
-- where a car is picked from cheap to dear (FernfahrerRental.vue). On foot: S.rental = L.FOOT, the game's walking figure.
L.FOOT = { kind = 'foot', foot = true, rental = true, model = 'unicycle', brand = '', modelName = 'Zu Fuß', configName = '', price = 0,
  config = { model = 'unicycle', format = 2, parts = { unicycle_meshes = 'unicycle_character' } } }
function L.onFoot() return S and S.active == 'rental' and S.rental and S.rental.foot and true or false end
L.RENT_CLASSES = { { 0, 16000, 'Kleinwagen' }, { 16000, 32000, 'Kompaktklasse' }, { 32000, 60000, 'Mittelklasse' }, { 60000, 120000, 'Oberklasse' }, { 120000, math.huge, 'Luxus & Sport' } }
L.RENT_SKIP = { 'police', 'polizei', 'race', 'drift', 'rally', 'taxi', 'ambulan', 'bare', 'stripped', 'derby', 'safari', 'baja', 'hillclimb', 'track', 'trial', 'prerunner', 'interceptor' }
function L.rentalOffers()
  local desk = S.rentalDesk
  local key = desk and desk.id or '?'
  if R.rentalOffers and R.rentalKey == key then return R.rentalOffers end
  local out, eu = {}, not desk or EU_CC[desk.cc or ''] ~= nil
  for _, cl in ipairs(L.RENT_CLASSES) do
    local cands = {}
    for _, m in ipairs(R.cars or {}) do
      for _, c in ipairs(m.configs or {}) do
        local name = tostring(c.configName or ''):lower()
        local bad = false
        for _, w in ipairs(L.RENT_SKIP) do if name:find(w, 1, true) then bad = true; break end end
        if not bad and c.price >= cl[1] and c.price < cl[2] then cands[#cands + 1] = c; break end     -- (a model once per class)
      end
    end
    for i = #cands, 2, -1 do local j = math.random(i); cands[i], cands[j] = cands[j], cands[i] end
    table.sort(cands, function(a, b) return ((a.eu and true or false) == eu and 0 or 1) < ((b.eu and true or false) == eu and 0 or 1) end)
    for i = 1, math.min(3, #cands) do
      local c = cands[i]
      out[#out + 1] = { model = c.model, config = c.config, brand = c.brand, modelName = c.modelName, configName = c.configName, class = cl[3],
        power = c.power, drivetrain = c.drivetrain, preview = c.preview, rate = round(clamp(c.price * 0.0022, 39, 690), 1) }
    end
  end
  table.sort(out, function(a, b) return a.rate < b.rate end)
  for i, o in ipairs(out) do o.i = i end
  R.rentalOffers, R.rentalKey = out, key
  return out
end
function M.uiRental()
  if not S then return nil end
  ensureCatalog()
  return { offers = L.rentalOffers(), money = S.money, desk = S.rentalDesk and S.rentalDesk.name or 'Flughafen', onFoot = L.onFoot() }
end
function M.rentalTake(i)
  if not S or not L.onFoot() then return { ok = false, error = 'Du hast schon ein Fahrzeug.' } end
  local o = L.rentalOffers()[tonumber(i) or 0]
  if not o then return { ok = false, error = 'Dieses Angebot gibt es nicht mehr.' } end
  if S.money < o.rate then return { ok = false, error = 'Dafür reicht dein Geld nicht.' } end
  L.pay('Reisen', -o.rate, 'Mietwagen ' .. tostring(o.brand) .. ' ' .. tostring(o.modelName))
  S.stats.travelCost = (S.stats.travelCost or 0) + o.rate
  S.rental = { kind = 'car', model = o.model, config = o.config, brand = o.brand, modelName = o.modelName, configName = 'Mietwagen', price = 0, rental = true }
  S.active, S.rentalDesk, R.rentalOffers = 'rental', nil, nil
  core_vehicles.replaceVehicle(o.model, { config = o.config, autoEnterVehicle = true })
  R.truckId, R.fuel = nil, nil
  R.pendingAdopt = now() + 0.5
  navClear()
  notify('Dein Mietwagen: ' .. tostring(o.brand) .. ' ' .. tostring(o.modelName) .. ' · gute Fahrt!', 6)
  save()
  return { ok = true }
end
-- after the landing: the desk placed a little way off, the message; walking into its ring opens the desk
function L.rentalTick(t)
  if not L.onFoot() or not S.rentalDesk then return end
  local desk = S.rentalDesk
  if R.rentalHinted ~= desk.id and L.screenGone(t) and not R.boot then
    R.rentalHinted = desk.id
    local p = here()
    if p and not desk.placed then
      desk.lat, desk.lon, desk.placed = p.lat + 28 / 111320, p.lon + 12 / (111320 * math.cos(math.rad(p.lat))), true
    end
    guihooks.trigger('FernfahrerRegion', { kind = 'notice', eyebrow = 'Gelandet · ' .. tostring(desk.name), name = 'Mietwagen-Schalter',
      sub = 'Sie haben jetzt die Möglichkeit, einen Mietwagen auszuwählen.' })
    notify('Sie haben jetzt die Möglichkeit, einen Mietwagen auszuwählen. Geh zum leuchtenden Kreis.', 12)
    navTo(desk, 'Mietwagen-Schalter')
    save()
  end
  local inRing = R.near and R.near.action == 'rental' and stops.inside()
  if inRing and not R.rentalOpened and not R.officeOpen and not R.stopOpen then
    R.rentalOpened = true
    navigate('fernfahrerRental')
  elseif not inRing then
    R.rentalOpened = nil
  end
end

-- the hours on board: the clock and the deadlines move on; a long crossing is the daily rest, a short one the break
local function passTime(hours)
  if S.settings.dayNight ~= false then
    local h0 = clockHours()
    S.dayNo = (S.dayNo or 1) + math.floor((h0 + hours) / 24)
    local h = (h0 + hours) % 24
    S.clockHours = h
    startClock(h)
  end
  pcall(vices.tick, hours)                      -- (sobering up on board)
  pcall(L.fatigueRest, hours)                   -- (sleep and crossings: rested afterwards, 2026-11-08)
  -- (on board the driver rests: a long crossing is the daily rest, a short one the break – EU rules allow it)
  if S.tacho then tacho.restFor(S.tacho, hours * 3600, notify) end
  if S.job then S.job.elapsed = S.job.elapsed + hours * 3600 / tacho.SCALE end
end

local function startTrip(to, mode, opts)
  -- the passage screen (FernfahrerTravel.vue) covers the move; it goes back to the road once uiTrip says arrived
  R.tripView = opts and opts.view or { mode = mode, to = to.name }
  R.tripView.mode = mode
  R.tripView.night = (function() local h = clockHours(); return h < 6 or h >= 21 end)() or nil
  R.tripView.arrival = clockText()               -- (the clock has been moved on by passTime already)
  R.tripView.trailer = opts and opts.trailer or nil
  navigate('fernfahrerTravel')
  R.trip = { to = { lat = to.lat, lon = to.lon, name = to.name, id = to.id, cc = to.cc }, mode = mode, t0 = now(),
    foot = opts and opts.foot, trailer = opts and opts.trailer }
  R.teleportTarget = { lat = to.lat, lon = to.lon, name = to.name }
  R.teleportTries = 0
  L.keepCondForTeleport()                          -- (the damage goes along on the ferry, 2026-11-07)
  R.pendingTeleport = now() + 1.0
  navClear()
  save()
end

-- the options at the port / airport where the player stands (for the office's travel page)
local function travelView()
  local p = here()
  local hub = hubHere()
  local kind = activeKind()
  local v = { kind = kind, job = S.job ~= nil, trailer = R.trailerId ~= nil, ferries = {}, airports = {} }
  if hub then
    v.hub = { id = hub.id, name = hub.name, kind = hub.kind, train = hub.train or nil, cc = hub.cc }
    v.options = {}
    if hub.kind == 'ferry' then
      for i, r in ipairs(travel.routesFrom(hub.id)) do
        table.insert(v.options, { idx = i, to = r.to.name, cc = r.to.cc, hours = r.hours, operator = r.operator,
          km = math.floor(r.km), price = kind == 'truck' and r.truck or r.car, train = r.to.train or nil })
      end
    else
      for i, f in ipairs(travel.flightsFrom(hub.id)) do
        table.insert(v.options, { idx = i, to = f.to.name, iata = f.to.iata, cc = f.to.cc, hours = f.hours,
          km = math.floor(f.km), price = f.price })
      end
    end
  end
  if p then
    for _, x in ipairs(travel.hubsNear(p, 4000)) do
      local list = x.hub.kind == 'airport' and v.airports or v.ferries
      if #list < 8 then
        table.insert(list, { id = x.hub.id, name = x.hub.name, cc = x.hub.cc, dist = x.dist, train = x.hub.train or nil,
          iata = x.hub.iata })
      end
    end
  end
  return v
end

-- What BeamNG.Earth still has to load around the player (its perf report reads the same): a teleport under way,
-- the ground block, road tiles, tree tiles. nil when the world there is ready to be seen.
local function earthLoading()
  local c = earthCore()
  local st = c and c._state and c._state()
  if not st then return nil end
  local w = {}
  if st.pending or (st.clock and st.clock < (st.loadingUntil or 0)) or st.placeFrames or st.rebasing then w.ground = true end
  if st.terrainPending or st.commitFrames then w.ground = true end
  -- (2026-11-08) the clock of this arrival: a fixed time from the new world on. It ran anew whenever Earth said "ready" for a
  -- moment, and with colliders still coming in that kept the loading screen, the day's card and the introduction waiting.
  if not R.notReadySince or R.trip or R.pendingTeleport or R.notReadyAnchor ~= st.anchorId then R.notReadyAnchor, R.notReadySince = st.anchorId, now() end
  if now() - R.notReadySince > L.GROUND_WAIT_S then w.ground = nil end
  local okR, roads = pcall(require, 'beamngEarth/roads')
  local rs = okR and roads.status and select(2, pcall(roads.status)) or nil
  local nRoads = type(rs) == 'table' and ((rs.queued or 0) + (rs.walksQueued or 0)) or 0
  if nRoads > 2 then w.roads = nRoads end
  -- the tiles around the player all in, their buildings, decks and sidewalks made and solid (Earth's own test,
  -- roads.readyAround: the counts above were near zero while buildings still came in – the screen went too early
  -- after a trip, 2026-11-03)
  local okA, ready
  if okR and roads.readyAround and st.anchorId and st.player and st.player.x then
    okA, ready = pcall(roads.readyAround, st.anchorId, st.player.x, st.player.y, 350)
  end
  local okT, trees = pcall(require, 'beamngEarth/trees')
  local ts = okT and trees.status and select(2, pcall(trees.status)) or nil
  local nTrees = type(ts) == 'table' and (ts.pending or 0) or 0
  if nTrees > 3 then w.trees = nTrees end
  -- (2026-11-08) Earth's test can stay false for good at a place, or flicker while colliders still come in. So: once true for
  -- this world it has been true; false it counts while something is still coming in (the queues or its collision rebuilds
  -- move), and at most BUILDINGS_WAIT_S. The screen waits for the world – and still always ends.
  if okA then
    if ready then R.readySeen = st.anchorId end
    local sig = nRoads .. ':' .. nTrees .. ':' .. tostring(roads.reloads and roads.reloads() or 0)
    if sig ~= R.loadSig then R.loadSig, R.loadSigT = sig, now() end
    local since = now() - R.notReadySince
    local stalled = since > L.BUILDINGS_MIN_S and now() - R.loadSigT > L.STALL_S
    if not ready and R.readySeen ~= st.anchorId and since < L.BUILDINGS_WAIT_S and not stalled then w.buildings = true end
  end
  if next(w) then return w end
  return nil
end

-- the passage screen's poll: still on until the move is done and the world at the other end has loaded (at most
-- TRIP_LOAD_MAX_S after the arrival): nobody sees the ground and the roads come in
-- (2026-11-08: the loading screen gone and the HUD's apps up again: the day's card and the introduction are events of an
-- app of the driving layout – sent while the screen was still on they were lost, and a new career had no introduction)
function L.screenGone(t) return not R.tripPollAt or t - R.tripPollAt > 4 end
-- (the day's card: the screen gone, the world standing – but at most TITLE_HOLD_S more, it must come; a screen left with Esc
-- never got to clear R.worldLoad)
L.TITLE_HOLD_S = 8
function L.titleReady(t)
  if R.boot or not L.screenGone(t) then R.titleHold = nil; return false end
  R.worldLoad = nil
  R.titleHold = R.titleHold or t
  if L.worldStands() or t - R.titleHold > L.TITLE_HOLD_S then R.titleHold = nil; return true end
  return false
end
-- (the introduction: sent until its app says it is open, every 3 s and at most 10 times – an event sent to an app that is
-- not up is lost without a trace)
function L.tutSend(t, n)
  if not S or S.tutorialDone or n >= 10 then
    if n >= 10 then log('W', logTag, 'introduction: no answer from the app') end
    R.tutAckAt, R.tutAckN = nil, nil
    return
  end
  if not L.screenGone(t) or cinematic.active() or R.sleep or R.officeOpen or R.stopOpen or L.welcomePending() then R.tutAckAt, R.tutAckN = t + 1, n; return end
  local _, loaner = activeDef()
  guihooks.trigger('FernfahrerTutorial', { company = S.company and S.company.name or 'deine Spedition',
    home = S.home and S.home.name or 'dein Hof', loaner = loaner, rules = S.settings.truckRules ~= false })
  R.tutAckAt, R.tutAckN = t + 3, n + 1
  log('I', logTag, 'introduction sent (' .. (n + 1) .. ')')
end
-- (2026-11-09, BeamNG.Earth 1.9) Earth asks every player about its statistics on a page of its own, 2 s after the level starts:
-- in a career that took over the loading screen or the setup. The page and the choice stay Earth's (it sends nothing until then);
-- it only comes a little later here, when the player has arrived and nothing else is on the screen, and before the introduction.
L.WELCOME_ROUTE, L.WELCOME_CALM_S = 'beamngEarthWelcome', 6.5
function L.welcomeHold()
  local st = rawget(_G, 'beamngEarth_settings')
  if st and st.privacyNeeded and st.privacyNeeded() then st.welcomeSuppressed = true end
end
function L.welcomePending()
  return R.mode and (not R.welcomeDone or R.uiRoute == L.WELCOME_ROUTE) or false
end
function L.welcomeTick(t)
  if R.welcomeDone or not R.mode then return end
  local st = rawget(_G, 'beamngEarth_settings')
  if not (st and st.privacyNeeded and st.showWelcome) or not st.privacyNeeded() then
    if st then st.welcomeSuppressed = nil end
    R.welcomeDone = true
    return
  end
  st.welcomeSuppressed = true
  local calm = S and S.company and S.home and L.screenGone(t) and not (R.trip or R.pendingTeleport or R.sleep or R.officeOpen or R.stopOpen
    or R.cop or cinematic.active() or L.cine.active()) and (R.uiRoute == nil or R.uiRoute == 'play')
  if not calm then R.welcomeCalm = nil; return end
  R.welcomeCalm = R.welcomeCalm or t
  if t - R.welcomeCalm < L.WELCOME_CALM_S then return end
  st.welcomeSuppressed = nil
  R.welcomeDone = true
  pcall(st.showWelcome)
  log('I', logTag, 'BeamNG.Earth welcome page shown')
end
function M.onUiChangedState(toState) R.uiRoute = toState end
function M.tutorialShown()
  if R.tutAckAt then log('I', logTag, 'introduction open') end
  R.tutAckAt, R.tutAckN = nil, nil
end
L.BUILDINGS_WAIT_S, L.BUILDINGS_MIN_S, L.STALL_S, L.GROUND_WAIT_S = 70, 15, 9, 60
L.ARRIVAL_MIN_S, L.TREES_MAX_S = 15, 60    -- (right after an arrival nothing is queued yet: that is no "all in"; trees: only so long)
-- (the ground and the houses in: what the day's card waits for – Earth's trees can trickle in for minutes)
function L.worldStands()
  local w = earthLoading()
  return not (w and (w.ground or w.buildings))
end
local TRIP_LOAD_MAX_S = 100   -- (the last resort: the screen always goes by itself)
local SETTLE_S = 5            -- (all in for this long before the screen goes: a tile made after a quiet moment)
L.NEW_CAREER_WAIT_S = 12
-- (the loading screen left with Esc: a career without a yard still gets its setup screen)
function M.uiTravelLeft()
  if R.mode and S and not (S.company and S.home) then navigate('fernfahrerSetup') end
end
function M.uiTrip()
  R.screenAt = now()                             -- (the loading/travel screen asks while it is open: no mirrors over it)
  R.tripPollAt = R.screenAt
  local moving = R.trip ~= nil or R.pendingTeleport ~= nil or (R.worldLoad and R.boot ~= nil and now() - R.boot < 120) or false
  if not moving and R.worldLoad then R.worldLoad = nil; R.tripArrivedAt = R.tripArrivedAt or now() end
  local loading = earthLoading()
  if moving or loading then R.calmSince = nil
  elseif R.tripArrivedAt and now() - R.tripArrivedAt <= TRIP_LOAD_MAX_S then
    R.calmSince = R.calmSince or now()
    if now() - R.calmSince < SETTLE_S then loading = { settling = true } end
  end
  if not moving and (not R.tripArrivedAt or now() - R.tripArrivedAt > TRIP_LOAD_MAX_S) then loading = nil end
  -- (2026-11-08: a ferry's or a flight's screen went while the roads were still missing: a least time after every arrival,
  -- and the trees alone hold it only so long)
  if not moving and R.tripArrivedAt then
    local since = now() - R.tripArrivedAt
    if not loading and since < L.ARRIVAL_MIN_S then loading = { settling = true }
    elseif loading and since > L.TREES_MAX_S and not (loading.ground or loading.buildings or loading.roads) then loading = nil end
  end
  -- (2026-11-07) arrived at the home: the screen stays until the yard stands (its search waits for the world), at most
  -- YARD_WAIT_S – the card, the flight and the introduction then have their yard
  if not moving and not loading and R.tripArrivedAt and S and S.home and not R.tripNext and now() - R.tripArrivedAt < 110
     and not yard.built() and not (S.yard and S.yard.failed) and (dist(here(), S.home) or 1e9) < 400 then
    loading = { yard = true }
  end
  -- ("Zum Hof": the screen stays until the truck stands in front of the hall)
  if not moving and R.parkAtYard and now() < R.parkAtYard.untilT and not (S and S.yard and S.yard.failed) then
    loading = loading or {}
    loading.yard = true
  end
  -- (2026-11-09: at the yard, the truck parked: the houses and trees further off are no reason to keep the screen up for a minute and a half)
  if not moving and loading and not loading.yard and not loading.ground and yard.built() and R.tripView and R.tripView.world and R.tripArrivedAt and now() - R.tripArrivedAt > 8 and (dist(here(), S and S.home) or 1e9) < 900 then loading = nil end
  -- (2026-11-08) a new career: the setup screen comes next and the first drive starts at the chosen yard, so the buildings
  -- and trees of this spot are not waited for (they kept the screen up for its whole 90 s): only the ground, and not for long
  if not moving and loading and R.tripNext == 'fernfahrerSetup'
     and (not loading.ground or (R.tripArrivedAt and now() - R.tripArrivedAt > L.NEW_CAREER_WAIT_S)) then
    if R.newWaitLog ~= R.slot then R.newWaitLog = R.slot; log('I', logTag, 'new career: on to the setup, the world still had ' .. jsonEncode(loading)) end
    loading = nil
  end
  local active = moving or loading ~= nil
  -- (the loading screen once stayed up after the first load until Esc, 2026-11-04: the time it has been done is kept –
  -- onUpdate sends the UI back to the road if a screen still asks well after)
  if active then R.tripDoneSince = nil else R.tripDoneSince = R.tripDoneSince or now() end
  return { active = active, trip = R.tripView, loading = loading, moving = moving, next = R.tripNext }
end

function M.navToHub(id)
  local h = travel.byId(id)
  if h then navTo(h, h.name); notify('Route: ' .. h.name, 4) end
end

function M.travel(idx)
  if not S or R.trip then return end
  local hub = hubHere()
  if not hub then notify('Reisen geht am Fährhafen oder am Flughafen.', 5); return end
  if vehSpeed(playerVeh()) > 1 then notify('Bitte anhalten.', 3); return end
  local job = S.job
  if hub.kind == 'ferry' then
    local r = travel.routesFrom(hub.id)[tonumber(idx) or 0]
    if not r then return end
    local price = activeKind() == 'truck' and r.truck or r.car
    local coupled = job and R.trailerId and isCoupled()
    if R.trailerId and not coupled then notify('Erst den Auflieger ankuppeln – er fährt mit auf die Fähre.', 6); return end
    if S.money < price then notify('Das Ticket kostet ' .. money(price) .. ' – nicht genug Geld.', 5); return end
    L.pay('Reisen', -price, (hub.train and 'Autozug ' or 'Fähre ') .. tostring(hub.name) .. ' → ' .. tostring(r.to.name))
    S.stats.travelCost = (S.stats.travelCost or 0) + price
    passTime(r.hours)
    if coupled then
      deleteTrailer()                                -- (comes back behind the truck at the other side)
      job.phase = 'onFerry'
    end
    startTrip(r.to, 'ferry', { trailer = coupled and true or nil,
      view = { from = hub.name, to = r.to.name, hours = r.hours, operator = r.operator, train = hub.train or nil } })
    message(string.format('%s gebucht: %s → %s, %s h, %s.', hub.train and 'Autozug' or 'Fähre', hub.name, r.to.name,
      tostring(r.hours):gsub('%.', ','), money(price)), 'Mira (Disposition)')
  else
    if job then notify('Mit laufendem Auftrag kannst du nicht fliegen – Fähre nehmen oder erst abliefern.', 6); return end
    local f = travel.flightsFrom(hub.id)[tonumber(idx) or 0]
    if not f then return end
    local total = f.price
    if S.money < total then notify('Der Flug kostet ' .. money(total) .. ' – nicht genug Geld.', 5); return end
    L.pay('Reisen', -total, 'Flug ' .. tostring(hub.name) .. ' → ' .. tostring(f.to.name))
    S.stats.travelCost = (S.stats.travelCost or 0) + total
    passTime(f.hours)
    startTrip(f.to, 'fly', { foot = true,
      view = { from = hub.name, to = f.to.name, fromCode = hub.iata, toCode = f.to.iata, hours = f.hours } })
    message(string.format('Flug %s → %s (%s) gebucht, %s. Dein Fahrzeug bleibt hier – holen kannst du es später über den Fuhrpark (Überführung). Am Ziel holst du dir zu Fuß einen Mietwagen.',
      hub.iata or hub.name, f.to.name, f.to.iata or '', money(total)), 'Mira (Disposition)')
  end
end

-- the arrival: BeamNG.Earth has moved the player there
local function arrive()
  local trip = R.trip
  R.trip = nil
  R.tripArrivedAt = now()
  if trip.foot then
    S.rental, S.active = L.FOOT, 'rental'
    S.rentalDesk = { id = trip.to.id or trip.to.name, name = trip.to.name, cc = trip.to.cc, lat = trip.to.lat, lon = trip.to.lon }
    R.rentalHinted, R.rentalOffers = nil, nil
    local def = L.FOOT
    if playerVeh() then core_vehicles.replaceVehicle(def.model, { config = def.config, autoEnterVehicle = true })
    else core_vehicles.spawnNewVehicle(def.model, { config = def.config, autoEnterVehicle = true }) end
    R.truckId, R.fuel = nil, nil
    notify('Gelandet: ' .. trip.to.name, 6)
  elseif trip.mode == 'road' then
    notify('Weiter geht’s – ' .. trip.to.name, 6)
    R.orient = { t = now() + 1.0, hdg = trip.hdg }       -- (facing the way it was driven, before the trailer comes)
  else
    notify('Angekommen: ' .. trip.to.name, 6)
  end
  if trip.trailer and S.job then R.ferryTrailerAt = now() + 2.5 end
  if S.job and not trip.trailer then M.navToJob() end
  discoverRegion(here())
  save()
end

-- Continue where the last session ended (S.resume, remember): the vehicle there – on the road it was on, the same way
-- round – and a job's trailer behind it, hitched as after a ferry. The passage screen covers the load ("Weiterfahrt").
-- At the yard (and without a trailer) the usual start at the yard. False: nothing to resume.
function M.resume()
  local r = S.resume
  if not r or not r.lat or not r.lon or S.settings.resume == false then return false end
  local trailer = r.trailer and S.job and S.job.phase ~= 'toPickup' or false
  if not trailer and S.home and (dist(r, S.home) or 0) < 400 then return false end
  local def = activeDef()
  if playerVeh() then core_vehicles.replaceVehicle(def.model, { config = def.config, autoEnterVehicle = true })
  else core_vehicles.spawnNewVehicle(def.model, { config = def.config, autoEnterVehicle = true }) end
  R.truckId, R.fuel = nil, nil
  R.pendingAdopt = now() + 0.5
  if trailer then S.job.phase = 'onFerry' end
  local pl = streets.placeAt(r.lat, r.lon)
  local road = streets.nameAt(r.lat, r.lon)
  local name = pl and (pl.inside and pl.name or ('bei ' .. pl.name)) or 'deine letzte Position'
  startTrip({ lat = r.lat, lon = r.lon, name = name }, 'road', { trailer = trailer or nil,
    view = { from = S.company and S.company.name or 'Pause', to = name, road = road, job = S.job and S.job.to and S.job.to.name or nil } })
  R.trip.hdg = r.hdg
  R.pendingTeleport = now() + 1.5                    -- (the vehicle spawned first)
  return true
end

function M.moveHomeHere()
  local p = here()
  if not p or not S.home then return end
  S.home.lat, S.home.lon = p.lat, p.lon
  yard.forget(S)                                 -- (the buildings come to the new place)
  save()
  notify('Hof verlegt. „Netz neu erkunden“ sucht Orte rund um den neuen Hof.', 6)
end

function M.rediscover()
  if R.discover and R.discover.running then return end
  S.depots = {}
  R.offers = {}
  M.discoverDepots()
end

function M.takeLoan(amount)
  amount = math.min(tonumber(amount) or 0, loanLimit() - S.loan)
  if amount <= 0 then notify('Kreditrahmen ausgeschöpft.', 4); return end
  L.pay('Kredit', amount, 'Kredit aufgenommen')
  S.loan = S.loan + round(amount * (1 + C.LOAN_RATE))
  save()
end

function M.repayLoan(amount)
  amount = math.min(tonumber(amount) or S.loan, S.loan, math.max(0, S.money))
  if amount <= 0 then return end
  L.pay('Kredit', -amount, 'Kredit getilgt')
  S.loan = S.loan - amount
  save()
end

function M.setOption(key, value)
  if key == 'eventTest' and value == 'npc' then L.encForce(); return end
  if key == 'eventTest' and type(value) == 'string' and value:sub(1, 5) == 'fail:' then service.forceFail(value:sub(6)); return end
  if key == 'loadMusic' then S.settings.loadMusic = value and true or false; pcall(L.loadMusicTick) end
  if key == 'breakdowns' then S.settings.breakdowns = value and true or false end
  if key == 'autoPhotos' then
    S.settings.autoPhotos = value and true or false
    if value and not R.photos then R.photoWanted, R.photoLook = true, 0 elseif not value and R.photos then R.photos.stop() end
  end
  if key == 'photoSeries' then S.settings.photoSeries = value and true or false; if not value and L.shots.active() then L.shotsStop() end end
  if key == 'devResets' then S.settings.devResets = value and true or false; pcall(L.resetGuard) end
  if key == 'radioRegional' then S.settings.radioRegional = value and true or false end
  if key == 'mood' and (value == 'all' or value == 'noradio' or value == 'off') then S.settings.mood = value end
  if key == 'moodVol' and L.MOOD_LEVEL[value] then S.settings.moodVol = value end
  if key == 'hitch' and (value == 'auto' or value == 'manual') then S.settings.hitch = value end
  if key == 'speedWarn' then S.settings.speedWarn = value and true or false end
  -- (the truck's rules: its own limits, the 90 km/h limiter, fines for driving too fast – each can be switched off)
  if key == 'truckRules' then S.settings.truckRules = value and true or false; R.limitEff = L.ruleLimit(R.limit) end
  if key == 'limiter' then S.settings.limiter = value and true or false end
  if key == 'speedFines' then S.settings.speedFines = value and true or false end
  if key == 'tutorial' then M.tutorialAgain(); return end
  if key == 'routeWarn' then S.settings.routeWarn = value and true or false end
  if key == 'dayNight' then
    S.settings.dayNight = value and true or false
    if R.mode then if S.settings.dayNight then startClock() else stopClock() end end
  end
  if key == 'events' then
    S.settings.events = value and true or false
    if not S.settings.events then pcall(roadEvents.reset) end
  end
  if key == 'eventTest' and type(value) == 'string' then
    local kind, variant = value:match('^(%w+):?(%w*)$')
    if kind and pcall(roadEvents.test, kind, variant ~= '' and variant or nil) then
      notify('Ereignis kommt etwa 750 m voraus auf deiner Route (dafür muss eine Route gesetzt sein).', 6)
    end
    return
  end
  if key == 'cb' then S.settings.cb = value and true or false end
  if key == 'realWeather' then
    S.settings.realWeather = value and true or false
    if S.settings.realWeather then pcall(L.realWeather)
    else
      local st = rawget(_G, 'beamngEarth_settings')
      if st and st.set then pcall(st.set, 'weatherMode', 'manual') end
    end
  end
  if key == 'trafficCars' and (value == 'agent' or value == 'simple') then
    S.settings.trafficCars = value
    if R.mode and S.settings.traffic ~= 'off' then M.stopTraffic(); R.trafficAt = now() + 2 end
  end
  if key == 'traffic' and (value == 'off' or value == 'low' or value == 'auto' or value == 'high') then
    S.settings.traffic = value
    if R.mode then
      M.stopTraffic()
      if value ~= 'off' then R.trafficAt = now() + 2 end
    end
  end
  -- the performance mode (2026-11-04: "Leistung muss unbedingt verbessert werden"): 'max' – less traffic, no parked
  -- cars, a third of the walkers, the mirrors at their cheapest; 'balanced' brings the earlier settings back
  if key == 'perfMode' and (value == 'max' or value == 'balanced') and value ~= (S.settings.perfMode or 'balanced') then
    S.settings.perfMode = value
    if value == 'max' then
      S.settings.perfPrev = { traffic = S.settings.traffic or 'auto', parked = S.settings.parked or 'auto' }
      M.setOption('traffic', 'low')
      M.setOption('parked', 'off')
      if L.mirrors then pcall(L.mirrors.setQuality, 'eco') end
    else
      local p = S.settings.perfPrev or {}
      M.setOption('traffic', p.traffic or 'auto')
      M.setOption('parked', p.parked or 'auto')
      S.settings.perfPrev = nil
    end
  end
  if key == 'parked' and PARKED[value] then
    S.settings.parked = value
    if R.mode then
      if PARKED[value] == 0 then pcall(parked.stop)
      else local v = playerVeh(); if v then pcall(parked.start, PARKED[value], vehPos(v)) end end
    end
  end
  if key == 'navSound' then S.settings.navSound = value and true or false end
  if key == 'intro' then S.settings.intro = value and true or false end
  if key == 'radioOn' then S.settings.radioOn = value and true or false end
  if key == 'radioVol' then S.settings.radioVol = math.max(0, math.min(1, tonumber(value) or 0.7)) end
  if key == 'radioEqB' or key == 'radioEqM' or key == 'radioEqT' then S.settings[key] = math.max(-12, math.min(12, math.floor((tonumber(value) or 0) + 0.5))) end
  if key == 'radioSrc' and (value == 'radio' or value == 'spotify' or value == 'line' or value == 'video') then S.settings.radioSrc = value; S.settings.radioOn = true end
  if key == 'drugFx' then S.settings.drugFx = value and true or false; vices.fxEnabled = S.settings.drugFx end
  if key == 'slowmo' then S.settings.slowmo = value and true or false end
  if key == 'navVoice' then S.settings.navVoice = value and true or false; if not value then R.nav = nil end end
  if key == 'smartTraffic' then
    S.settings.smartTraffic = value and true or false
    priority.enabled = S.settings.smartTraffic
    if not S.settings.smartTraffic then pcall(trafficAI.reset) end
  end
  if key == 'accidents' then
    S.settings.accidents = value and true or false
    if not S.settings.accidents then pcall(accidents.reset) end
  end
  if key == 'aiTraffic' then
    S.settings.aiTraffic = value and true or false
    M.setModOption('aiTraffic', S.settings.aiTraffic)
    notify('KI-Verkehr ' .. (S.settings.aiTraffic and 'realistisch (Beta)' or 'Standard') .. ' – wirkt nach dem nächsten Spielstart ganz.', 6)
  end
  save()
end

function M.dismissReport() R.report = nil end
function M.uiReport() R.screenAt = now(); return R.report end

function M.resetCareer()
  deleteTrailer()
  navClear()
  S = defaults()
  R.offers, R.report = {}, nil
  save()
  if R.mode then navigate('fernfahrerSetup') end
end

------------------------------------------------------------------------------------------
-- the game mode

-- Installed mods that belong to the mode, switched on when the career picker opens (the player asked not to have
-- to know which ones to enable). Only mods already in the player's mods folder; missing ones are just listed.
local MODS = {
  { id = 'beamng_earth', name = 'BeamNG.Earth', why = 'die echte Welt (Pflicht)' },
  { id = 'agent_traffic_mod', name = 'Agent Traffic', why = 'europäischer Verkehr' },
  { id = 'agent_traffic_addon_stockgroups', name = 'Agent Traffic Stock Groups', why = 'Fahrzeuggruppen für den Verkehr' },
  { id = 'cherrier_potent_lite', name = 'Cherrier/Wentward Potent Lite', why = 'europäische Frontlenker-Zugmaschine' },
  { id = 'bella_semipack', name = "Bella's Semi Add-on", why = 'mehr Teile für die Zugmaschinen' },
  { id = 'efc_us_semi_drive_exp', name = 'T-Series Drivetrain Expansion', why = 'mehr Antriebe für die T-Series' },
  { id = 'yb_teseries_extended_sleeper', name = 'Extended T-Series Sleeper', why = 'Fernverkehrskabine' },
  { id = 'ra66_tseries', name = "'87-'98 Gavril MT-Series", why = 'weitere Zugmaschinen beim Händler' },
  { id = 'ra66_truckwheelmod', name = 'Truck Wheel Mod', why = 'LKW-Räder' },
  { id = 'jl4_trailer_abs', name = 'Trailer ABS', why = 'ABS für Auflieger: realistischer bremsen' },
  { id = 'ta_trailer_expansion', name = 'TA Trailer Expansion', why = 'mehr Auflieger-Teile' },
  { id = 'fdcpack', name = 'Fictional Delivery Companies Pack', why = 'Speditions-Lackierungen' },
  { id = 'zeit_reverse_cam', name = 'Reverse Camera', why = 'Rückfahrkamera zum Rangieren' },
}

-- switched on or off by the player's choice (kept in OPTIONS_FILE, for every career)
local OPTIONS_FILE = '/settings/fernfahrer/options.json'
local OPTIONAL_MODS = {
  { id = 'realistic_ai_traffic_behaviors', name = 'Realistic AI Traffic Behaviors', key = 'aiTraffic', default = false,
    extPrefix = 'realAITraffic_',
    why = 'KI überholt und wechselt die Spur – Beta: kann ruckeln, die KI greift sich manchmal abgestellte Fahrzeuge' },
}
-- A mod switched off while its extensions run: its files go, its extensions keep calling for them – every frame
-- ("extension unavailable: realAITraffic_manager", so much that the game's log went nearly silent and the frame
-- rate fell to 30, 2026-11-03). So they are unloaded with it.
local function unloadModExtensions(prefix)
  if not prefix then return end
  local names = {}
  for k, v in pairs(_G) do
    if type(k) == 'string' and k:sub(1, #prefix) == prefix and type(v) == 'table' then names[#names + 1] = k end
  end
  for _, n in ipairs(names) do pcall(extensions.unload, n) end
  if #names > 0 then log('I', logTag, string.format('unloaded %d extensions of a switched-off mod (%s*)', #names, prefix)) end
end

local function readOptions()
  local o = FS:fileExists(OPTIONS_FILE) and jsonReadFile(OPTIONS_FILE) or nil
  return type(o) == 'table' and o or {}
end

-- Mods that clash with BeamNG.Earth in this mode: switched off by the picker. Realistic Headlights' light flares
-- (zeit/customLightFlares.lua) run on every changed file and log a deprecation error each time; Earth writes files
-- all the time (4931 errors in 16 minutes, 2026-11-03).
local CLASHING_MODS = { { id = 'realisticheadlights', name = 'Realistic Headlights', ext = 'zeit_customLightFlares' } }

-- (a mod switched off mid-session stays loaded until the restart: its extension goes now)
local function unloadClashing()
  for _, m in ipairs(CLASHING_MODS) do
    if m.ext and rawget(_G, m.ext) then
      pcall(extensions.unload, m.ext)
      log('I', logTag, 'extension unloaded (clashes with BeamNG.Earth): ' .. m.ext)
    end
  end
end

local function modState()
  local mm = rawget(_G, 'core_modmanager')
  local out = {}
  for _, m in ipairs(MODS) do
    local db = mm and mm.getModDB and mm.getModDB(m.id)
    table.insert(out, { id = m.id, name = m.name, why = m.why, installed = db ~= nil, active = db and db.active or false })
  end
  local opts = readOptions()
  for _, m in ipairs(OPTIONAL_MODS) do
    local db = mm and mm.getModDB and mm.getModDB(m.id)
    local on = opts[m.key]
    if on == nil then on = m.default end
    table.insert(out, { id = m.id, name = m.name, why = m.why, installed = db ~= nil, active = db and db.active or false,
      optional = true, key = m.key, on = on })
  end
  return out
end

-- at the game's start: the player's choice for the optional mods (a new mod in the folder starts active)
function M.onModManagerReady()
  local mm = rawget(_G, 'core_modmanager')
  if not (mm and mm.getModDB and mm.deactivateMod) then return end
  local opts = readOptions()
  for _, m in ipairs(OPTIONAL_MODS) do
    local db = mm.getModDB(m.id)
    local want = opts[m.key]
    if want == nil then want = m.default end
    if db and db.active and not want then unloadModExtensions(m.extPrefix); pcall(mm.deactivateMod, m.id) end
  end
end

function M.setModOption(key, on)
  local o = readOptions()
  o[key] = on and true or false
  jsonWriteFile(OPTIONS_FILE, o, true)
  return M.ensureMods()
end

function M.ensureMods()
  local mm = rawget(_G, 'core_modmanager')
  local switched = {}
  if mm and mm.getModDB and mm.activateMod then
    for _, m in ipairs(MODS) do
      local db = mm.getModDB(m.id)
      if db and not db.active then
        local ok, err = pcall(mm.activateMod, m.id)
        if ok then table.insert(switched, m.name) else log('W', logTag, 'mod ' .. m.id .. ': ' .. tostring(err)) end
      end
    end
  end
  if mm and mm.getModDB and mm.deactivateMod then
    for _, m in ipairs(CLASHING_MODS) do
      local db = mm.getModDB(m.id)
      if db and db.active then
        local ok = pcall(mm.deactivateMod, m.id)
        if ok then log('I', logTag, 'mod switched off (clashes with BeamNG.Earth): ' .. m.name) end
      end
    end
  end
  if mm and mm.getModDB and mm.activateMod and mm.deactivateMod then
    local opts = readOptions()
    for _, m in ipairs(OPTIONAL_MODS) do
      local db = mm.getModDB(m.id)
      local want = opts[m.key]
      if want == nil then want = m.default end
      if db and want and not db.active then
        if pcall(mm.activateMod, m.id) then table.insert(switched, m.name) end
      elseif db and not want and db.active then
        unloadModExtensions(m.extPrefix)
        pcall(mm.deactivateMod, m.id)
      end
    end
  end
  unloadClashing()
  if #switched > 0 then
    R.trucks, R.cars = nil, nil           -- new vehicles: the dealers' stock again
    log('I', logTag, 'mods switched on: ' .. table.concat(switched, ', '))
  end
  return { switched = switched, mods = modState() }
end

-- the career picker (main menu > More > Trucks of Earth): every slot with what it is
function M.uiCareers()
  local list = {}
  for _, path in ipairs(FS:findFiles(SLOT_DIR, '*.json', 0, false, false)) do
    local slot = path:match('([^/]+)%.json$')
    local d = slot and jsonReadFile(path)
    if type(d) == 'table' then
      table.insert(list, { id = slot, company = d.company and d.company.name or nil,
        driver = d.company and d.company.driver or nil, home = d.home and d.home.name or nil,
        money = d.money, level = d.level, jobs = d.stats and d.stats.jobs or 0, km = d.stats and d.stats.km or 0,
        trucks = d.owned and #d.owned or 0, lastPlayed = d.lastPlayed or (d.company and d.company.founded) or 0,
        founded = d.company and d.company.founded or nil,
        -- (the title screen's card: the job under way, the game day and time)
        job = type(d.job) == 'table' and { cargo = d.job.cargoName, to = d.job.to and d.job.to.name or nil } or nil,
        day = d.dayNo, clock = d.clockHours })
    end
  end
  table.sort(list, function(a, b) return (a.lastPlayed or 0) > (b.lastPlayed or 0) end)
  return { careers = list, earth = core_levels and core_levels.getLevelByName(EARTH_LEVEL) ~= nil or false, mods = modState() }
end

local function startLevel()
  if not core_levels or not core_levels.getLevelByName(EARTH_LEVEL) then
    if guihooks then
      guihooks.trigger('showConfirmationDialog', { title = 'Trucks of Earth',
        text = 'Für diesen Spielmodus wird die Mod BeamNG.Earth benötigt (Level „beamng_earth“ nicht gefunden).',
        buttons = { { label = 'OK', default = true, isCancel = true } } })
    end
    return false
  end
  R.modeRequested = true
  M.loadMusic(true, 240)                         -- (over the game's own loading screen too; the passage screen takes over)
  if not freeroam_freeroam then extensions.load('freeroam_freeroam') end
  freeroam_freeroam.startFreeroamByName(EARTH_LEVEL)
  return true
end

-- continue a career
function M.startCareer(slot)
  slot = tostring(slot or ''):gsub('[^%w_%-]', '')
  if slot == '' or not FS:fileExists(slotPath(slot)) then return { ok = false, error = 'Karriere nicht gefunden' } end
  load(slot)
  R.offers, R.report = {}, nil
  return { ok = startLevel() }
end

-- a new, empty career: the setup screen comes up in the level
function M.newCareer()
  local n = 1
  while FS:fileExists(slotPath('karriere_' .. n)) do n = n + 1 end
  R.slot = 'karriere_' .. n
  S = defaults()
  R.offers, R.report = {}, nil
  save()
  return { ok = startLevel(), id = R.slot }
end

function M.deleteCareer(slot)
  slot = tostring(slot or ''):gsub('[^%w_%-]', '')
  if slot == '' or slot == R.slot and R.mode then return { ok = false } end
  FS:removeFile(slotPath(slot))
  return { ok = true }
end

-- (kept for key bindings / old buttons: the most recent career, else a new one)
function M.startMode()
  local list = M.uiCareers().careers
  if list[1] then return M.startCareer(list[1].id) end
  return M.newCareer()
end

local function restoreSettings()
  if R.prevGasSetting ~= nil and settings and settings.setValue then
    pcall(settings.setValue, 'enableGasStationsInFreeroam', R.prevGasSetting)
    R.prevGasSetting = nil
  end
end

function M.stopMode()
  pcall(L.requestCond)                          -- (the truck's condition once more – it may still come back in time)
  save()
  R.mode = false
  restoreSettings()
  stopClock()
  if returnToMainMenu then returnToMainMenu() end
end

function M.isActive() return R.mode end

local function boot()
  R.boot = nil
  local gs = rawget(_G, 'core_gamestate')
  if gs and gs.setGameState then pcall(gs.setGameState, 'freeroam', APP_LAYOUT, 'freeroam') end
  -- the gas stations' pump prompt (BeamNG.Earth's stations go through the stock module only with this on)
  if settings and settings.getValue and settings.getValue('enableGasStationsInFreeroam') ~= true then
    R.prevGasSetting = settings.getValue('enableGasStationsInFreeroam') or false
    pcall(settings.setValue, 'enableGasStationsInFreeroam', true)
  end
  patchGasStations()
  unloadClashing()
  -- (the office shows what is really set: the optional mod's switch lives in options.json, for every career)
  S.settings.aiTraffic = readOptions().aiTraffic == true
  priority.enabled = S.settings.smartTraffic ~= false
  pcall(priority.install)                        -- (main roads as priority roads on every new Earth road graph)
  pcall(yard.setUpgrades, S.yardUp or {})        -- (the yard's upgrades: their props)
  applyRealAI()
  R.realAIAt = now() + 20                        -- (once more after the traffic has started)
  -- the road scenes' vehicles (patrol car, ambulance) spawned now, while the game is still settling: no hitch later
  do
    local v = playerVeh()
    if v then pcall(pool.prepare, vehPos(v)) end
  end
  ensureCatalog()
  startClock()                                  -- day and night at the tachograph's pace
  pcall(L.realWeather)                          -- (the real weather of the place, 2026-11-08)
  R.trafficAt = now() + C.TRAFFIC_DELAY_S
  if not S.company or not S.home then
    -- (the loading screen is up: it goes on to the setup itself once the world is there)
    if R.tripNext ~= 'fernfahrerSetup' then navigate('fernfahrerSetup') end
    return
  end
  if not M.resume() then M.goHome(true) end
  R.titleAt = now() + 3                          -- (the day's title card, once the world is there)
  S.story.welcomeBack = nil
  story('welcomeBack')
  -- older versions made up "Kunde in der Umgebung" places when the search failed: those go, real ones are searched
  for i = #S.depots, 1, -1 do if S.depots[i].synthetic then table.remove(S.depots, i) end end
  if #S.depots == 0 then M.discoverDepots()
  elseif (S.netVersion or 1) < C.NET_VERSION then M.discoverDepots(true) end
end

function M.toggleOffice(tab)
  if not R.mode then return end
  if not S.company or not S.home then navigate('fernfahrerSetup'); return end
  if tab then R.officeTab = tab; navigate('fernfahrerOffice'); return end
  if R.officeOpen then navigate('play') else navigate('fernfahrerOffice') end
end

function M.uiOfficeOpen(on) R.officeOpen = on and true or false end

------------------------------------------------------------------------------------------
-- fines, the tachograph's rest, roadside help, road events

function M.fine(amount, reason)
  amount = round(tonumber(amount) or 0)
  if amount <= 0 or not S then return end
  L.pay('Bußgelder', -amount, tostring(reason))
  S.stats.fines = (S.stats.fines or 0) + amount
  table.insert(S.fines, 1, { t = os.time(), amount = amount, reason = reason })
  while #S.fines > 30 do table.remove(S.fines) end
  notify(string.format('Bußgeld %s: %s', money(amount), tostring(reason)), 8)
  story('firstFine')
  extensions.hook('onFernfahrerFine', amount, reason)
  save()
end

local function isTruckDriving()
  return activeKind() == 'truck' and R.truckId ~= nil and be:getPlayerVehicleID(0) == R.truckId
end

-- where the daily rest may be taken: a rest area, a fuel stop (Autohof), the yard, a logistics base
local function canRest()
  if atHome() then return true end
  local n = R.near
  local t = n and DEPOT_BY_KEY[n.type]
  return n and (n.action == 'sleep' or n.action == 'refuel' or (t and t.hub)) or false
end

-- sleep: the screen goes dark, the clock moves on 11 hours (the regular daily rest), the tachograph starts a new day
M.SLEEP_H = 11
-- a rest of `hours` in the cab (the stop menu: a 45 min break, a daily or weekly rest): the screen dark, the clock,
-- the tachograph (rest), the job's deadline and the body (passTime) move on; a break of under 6 h anywhere standing,
-- longer only where one may sleep
local WEEKDAYS = { 'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag' }
local function weekday() return WEEKDAYS[((S.dayNo or 1) - 1) % 7 + 1] end
function M.sleepFor(hours)
  if not S then return end
  if L.pursuit.active() then notify('Nicht, solange die Polizei hinter dir her ist.', 4); return end
  hours = tonumber(hours) or M.SLEEP_H
  if hours >= 6 and not canRest() then notify('Schlafen geht an Rastplätzen, Autohöfen/Tankstellen, am Hof und an Logistik-Stützpunkten.', 6); return end
  if vehSpeed(playerVeh()) > 1 then notify('Bitte anhalten.', 3); return end
  if R.sleep then return end
  -- (2026-11-04: our own sleep screen – FernfahrerSzene 'FernfahrerSleep' – instead of ui_fadeScreen.cycle: that one is
  -- BeamNG's loading screen and fades back only when the UI reports the black; with the menu just closed the report
  -- got lost and the screen stayed on "Einen Moment". Ours runs on this clock alone: L.sleepTick)
  local h0 = clockHours()
  local dayTo = WEEKDAYS[(((S.dayNo or 1) + math.floor((h0 + hours) / 24)) - 1) % 7 + 1]
  local label = hours < 1 and string.format('Pause %d min', math.floor(hours * 60 + 0.5))
    or (hours >= 24 and 'Wochenruhe ' or 'Tagesruhe ') .. string.format('%d h', math.floor(hours + 0.5))
  local place
  local p = here()
  local okP, pl = pcall(streets.placeAt, p and p.lat, p and p.lon)
  place = R.near and R.near.name or (okP and pl and pl.name) or nil
  local dur = hours < 6 and 4.8 or (hours >= 24 and 8.5 or 7.5)
  local t0 = now()
  R.sleep = { t0 = t0, hours = hours, dur = dur, data = { on = true, key = string.format('%.3f', t0), hours = hours, dur = dur,
    label = label, fromH = h0, toH = (h0 + hours) % 24, dayFrom = weekday(), dayTo = dayTo, place = place,
    kind = hours < 6 and 'pause' or (hours >= 24 and 'week' or 'night') } }
  R.titleUntil = now() + dur + 2                  -- (no mirrors over it)
  L.sleepSend(t0)
end
-- (sent again 4× a second with its time so far: the stop menu closing rebuilds the HUD apps – the first word went to
-- an app not there yet and the screen never came, 2026-11-04; a fresh app joins in where it is)
function L.sleepSend(t)
  local z = R.sleep
  if not z or z.done then return end
  z.sentAt = t
  z.data.el = t - z.t0
  guihooks.trigger('FernfahrerSleep', z.data)
end
-- the sleep screen's course: dark after 1 s – the time passes then (passTime, the save); its end: the new day's card
function L.sleepTick(t)
  local z = R.sleep
  if not z then return end
  if t - (z.sentAt or 0) > 0.25 and t - z.t0 < z.dur - 1 then L.sleepSend(t) end
  if not z.passed and t - z.t0 > 1.1 then
    z.passed = true
    passTime(z.hours)
    if z.hours >= 6 then story('firstRest') end
    save()
  end
  -- (the screen tells when it is done; without it – the app not in the layout – after its time plus a little)
  if z.passed and (z.done or t - z.t0 > z.dur + 1.5) then
    R.sleep = nil
    if not z.done then guihooks.trigger('FernfahrerSleep', { on = false }) end
    local long = z.hours >= 6
    R.titleAt = t + 0.6
    R.titleText = long and 'Ausgeschlafen' or 'Pause beendet'
    notify(long and string.format('Ausgeschlafen – %s, %s Uhr. Lenkzeit wieder voll.', weekday(), clockText())
      or string.format('Pause beendet – %s Uhr.', clockText()), 7)
  end
end
-- a town driven into (2026-11-05): the banner "Neuer Ort entdeckt" / "Wieder in …" – every 2 s the town under the
-- truck (streets.placeAt: inside its radius); announced when it changes, the same one not again within 3 minutes
function L.townTick(t)
  if t - (R.townT or 0) < 2 or R.sleep or R.trip or R.officeOpen or R.stopOpen then return end
  R.townT = t
  local p = here()
  if not p then return end
  local ok, pl = pcall(streets.placeAt, p.lat, p.lon, true)
  local name = ok and pl and pl.inside and (pl.kind == 'city' or pl.kind == 'town' or pl.kind == 'village') and pl.name or nil
  if not name then R.townIn = nil; return end
  if name == R.townIn then return end
  R.townIn = name
  R.townSeenAt = R.townSeenAt or {}
  if R.townSeenAt[name] and t - R.townSeenAt[name] < 180 then return end
  R.townSeenAt[name] = t
  S.towns = S.towns or {}
  local n = (S.towns[name] or 0) + 1
  S.towns[name] = n
  local first = n == 1
  S.townInfo = S.townInfo or {}
  local ti = S.townInfo[name] or { f = os.time() }
  ti.k, ti.l = pl.kind, os.time()
  S.townInfo[name] = ti
  if first then S.stats.towns = (S.stats.towns or 0) + 1 end
  guihooks.trigger('FernfahrerTown', { name = name, kind = pl.kind, first = first, count = S.stats.towns or 0 })
  if first then pcall(addXp, 15) end
end
-- the introduction closed ('office': straight on into the office's freight market); again from the settings.
-- (2026-11-05) Then the first job is the tutorial's route: a small card says what to do at each step – take a job in
-- the office, drive to the company, back onto the trailer, drive, the blue area, unhitch – until it is delivered.
function M.tutorialDone(then_)
  if not S then return end
  S.tutorialDone = true
  S.tut = { jobs0 = S.stats.jobs or 0 }
  R.tutKey = nil
  -- (a look round first: the reminder to go to the office comes after a minute)
  R.tutOfficeAt = now() + (then_ == 'office' and 0 or 60)
  save()
  if then_ == 'office' then M.toggleOffice('market') end
end
L.TUT = {
  office = { n = 1, title = 'Deinen ersten Auftrag annehmen', text = 'Öffne das <b>Büro</b> und such dir in der <b>Frachtbörse</b> eine Ladung aus. Kurze Strecken sind für den Anfang am besten.', keys = 'Strg+Umschalt+F' },
  pickup = { n = 2, title = 'Zur Ladestelle fahren', text = 'Folge dem <b>Navi</b> zur Firma. Dort steht dein Auflieger in einer <b>grünen Fläche</b> bereit.' },
  trailer = { n = 3, title = 'Den Auflieger ankuppeln', text = 'Setz <b>rückwärts</b> vor den Auflieger und halt an (unter 20 m). Nach ein, zwei Sekunden wird er <b>automatisch angekuppelt</b>. Klappt das nicht: Taste <b>L</b> oder unten <b>„Ankuppeln“</b>.', keys = 'L' },
  drive = { n = 4, title = 'Zum Kunden fahren', text = 'Gut gekuppelt! Jetzt zum Kunden. Als LKW gelten <b>80 km/h</b> auf der Autobahn und <b>60</b> auf Landstraßen. Fahr sanft – Schäden an der Ladung kosten Lohn. Der Fahrtenschreiber zählt deine Lenkzeit.' },
  drop = { n = 5, title = 'Abstellen beim Kunden', text = 'Beim Kunden ist eine <b>blaue Fläche</b> markiert. Stell den Auflieger hinein – sie wird <b>grün</b>, wenn er richtig steht.' },
  unhitch = { n = 6, title = 'Abkuppeln und entladen', text = 'Jetzt <b>abkuppeln</b>: Taste <b>L</b> oder unten <b>„Abkuppeln“</b>. Danach wird entladen – kurz stehen bleiben.', keys = 'L' },
  done = { n = 7, title = 'Erster Auftrag geschafft!', text = 'Der Lohn ist auf deinem Konto, der Lieferschein liegt im Büro. Ab jetzt fährst du auf eigene Faust – mehr Aufträge gibt es in der Frachtbörse. Kurze Erklärfilme zum Fahren findest du im Büro unter <b>Fahrschule</b>. Gute Fahrt!', last = true },
}
function L.tutTick(t)
  local tut = S.tut
  if not tut or tut.done then return end
  if t - (R.tutT or 0) < 0.5 then return end
  R.tutT = t
  local job, stage = S.job, nil
  if (S.stats.jobs or 0) > (tut.jobs0 or 0) then stage = 'done'
  elseif not job then stage = (not R.tutOfficeAt or t >= R.tutOfficeAt) and 'office' or nil
  elseif job.phase == 'toTrailer' or job.phase == 'hitching' then stage = 'trailer'
  elseif job.phase == 'toDelivery' then stage = R.dropSpot and 'drop' or 'drive'
  elseif job.phase == 'atDelivery' or job.phase == 'unloading' then stage = 'unhitch'
  else stage = 'pickup' end
  local hidden = R.officeOpen or R.stopOpen or R.sleep or R.trip or nil
  local key = tostring(stage) .. '|' .. tostring(hidden)
  if key == R.tutKey then return end
  R.tutKey = key
  local d = stage and L.TUT[stage]
  guihooks.trigger('FernfahrerTutHint', d and { stage = stage, n = d.n, total = 7, title = d.title, text = d.text, keys = d.keys,
    last = d.last, hidden = hidden } or { off = true })
  if stage == 'done' then tut.done = true; save() end
end
-- (the card's ×: the tutorial's route ended early)
function M.tutorialSkip()
  if S and S.tut then S.tut.done = true; R.tutKey = nil; save() end
  guihooks.trigger('FernfahrerTutHint', { off = true })
end
function M.tutorialAgain()
  if not S then return end
  S.tutorialDone = false
  S.tut = nil
  R.tutorialAt = now() + 1.5
  navigate('play')
end
-- (the sleep screen: its own end reached)
function M.sleepDone() if R.sleep and R.sleep.passed then R.sleep.done = true end end
function M.rest() M.sleepFor(M.SLEEP_H) end
M.sleep = M.rest

-- the stop menu (FernfahrerStop.vue): what the place in whose ring the truck stands offers
local REST_OPTIONS = {
  { h = 0.75, label = 'Pause 45 min', sub = 'Lenkzeitunterbrechung – 4:30 Lenkzeit wieder voll' },
  { h = 9, label = 'Tagesruhe 9 h', sub = 'verkürzte tägliche Ruhezeit (max. 3× pro Woche)' },
  { h = 11, label = 'Tagesruhe 11 h', sub = 'reguläre tägliche Ruhezeit – neuer Tag', best = true },
  { h = 24, label = 'Wochenruhe 24 h', sub = 'verkürzte wöchentliche Ruhezeit' },
  { h = 45, label = 'Wochenruhe 45 h', sub = 'reguläre wöchentliche Ruhezeit' },
}
function M.uiStop()
  local p = R.photoNear or stops.inside() or R.near
  if not S or not p then return { none = true } end
  local v = { place = { name = p.name, icon = p.icon, typeName = p.typeName, action = p.action, color = stops.COLOR[p.action] },
    clock = clockText(), weekday = weekday(), money = S.money, moneyText = money(S.money), actions = {}, rest = {}, tacho = tacho.view(S.tacho),
    inv = L.inv(), fatigue =(function() local ok, f = pcall(L.fatigueView); return ok and f or nil end)() }
  local veh = playerVeh()
  local a = p.action
  local function add(id, icon, label, sub, extra)
    local x = { id = id, icon = icon, label = label, sub = sub }
    for k, val in pairs(extra or {}) do x[k] = val end
    v.actions[#v.actions + 1] = x
  end
  -- (the yard's own pump, once built: refuel at the yard)
  if a == 'refuel' or (a == 'sleep' and not p.parking) or (a == 'home' and L.hasUp('pump')) then
    local r = R.fuel and R.fuel.ratio or nil
    add('refuel', '⛽', 'Volltanken', r and string.format('Tank %d %% voll', math.floor(r * 100 + 0.5)) or 'Tank auffüllen',
      { disabled = r and r > 0.97 or nil, ratio = r })
  end
  -- (2026-11-07) the fuel station's shop: beer and cigarettes; at some stations someone round the corner
  if a == 'refuel' or (a == 'sleep' and not p.parking) then
    local sv = L.shopView(p)
    if a ~= 'refuel' then sv.back = nil end                -- (the back door is a fuel station's)
    for _, it in ipairs(sv.items) do
      add('buy:' .. it.id, it.icon, it.label .. ' – ' .. it.priceText, (it.why or it.sub) .. (it.have and (' · dabei: ' .. tostring(it.have)) or ''),
        { disabled = it.disabled, warn = it.back, shop = { name = it.label, sub = it.sub, why = it.why, price = it.priceText, kind = it.kind, have = it.have, back = it.back } })
    end
    if sv.back and not sv.back.open then
      add('back:try', '🚶', 'Um die Ecke gehen …', sv.back.gone and 'Der Typ ist gerade weg – später wieder' or 'Am Hinterausgang lungert jemand herum',
        { disabled = sv.back.gone, warn = true, game = true })
    end
  end
  if a == 'repair' or a == 'home' then
    local dmg = veh and damageOf(veh:getID()) or 0
    local fullC = veh and L.repairPay(veh) or 0
    local fullAny = dmg > 100 or fullC > 0
    add('repair', '🔧', 'Komplett reparieren', fullAny and ('Kosten ' .. money(fullC)) or 'Keine Schäden', { disabled = not fullAny or S.money < fullC or nil })
  end
  -- the speed limiter out (or back in), in a truck of one's own, at a workshop or the yard
  if (a == 'repair' or a == 'home') and S.settings.truckRules ~= false and L.activeKind() == 'truck' then
    local own, off = L.ownTruck(), L.limiterOff()
    if off then
      add('limiter:back', '🔒', 'Begrenzer wieder einbauen', string.format('%s · wieder legal mit 90 km/h', money(L.LIMITER_REFIT)),
        { disabled = S.money < L.LIMITER_REFIT or nil })
    else
      for _, k in ipairs({ 'cheap', 'pro' }) do
        local m = L.LIMITER_MOD[k]
        add('limiter:' .. k, k == 'pro' and '🛠' or '🔧', 'Begrenzer ausbauen – ' .. m.name,
          own and string.format('%s · %s', money(m.price), m.sub) or 'Nur bei eigenen LKW (nicht beim Firmen-Leihwagen)',
          { disabled = (not own or S.money < m.price) or nil, warn = true })
      end
    end
  end
  -- (2026-11-08) driver assistance, bought for a truck of one's own
  if (a == 'repair' or a == 'home') and L.activeKind() == 'truck' then
    local own = L.ownTruck()
    if own then
      for _, k in ipairs({ 'ldw', 'lka', 'acc' }) do
        local d = L.ASSIST[k]
        if not (own.assist and own.assist[k]) then
          add('assist:' .. k, d.icon, d.name .. ' einbauen', string.format('%s · %s', money(d.price), d.text), { disabled = S.money < d.price or nil })
        end
      end
    end
  end
  -- the big tank (2026-11-07): the career's trucks have half the stock tank; at a workshop or the yard the full one
  if (a == 'repair' or a == 'home') and L.activeKind() == 'truck' then
    local own = L.ownTruck()
    if not (own and own.tankBig) then
      add('tank:big', '🛢', 'Großer Tank einbauen', own and string.format('%s · doppelt so viel Diesel (Werksgröße)', money(L.TANK_BIG_PRICE))
        or 'Nur bei eigenen LKW (nicht beim Firmen-Leihwagen)', { disabled = (not own or S.money < L.TANK_BIG_PRICE) or nil })
    end
  end
  if a == 'dealerTruck' or a == 'dealerCar' then add('dealer', '🚛', 'Zum Händler', 'Neue und gebrauchte Fahrzeuge') end
  if a == 'home' or a == 'workshop' then add('garage', '🎨', 'Kabine einrichten', 'Zubehör einbauen und verschieben') end
  -- the loads waiting at this company (ETS2: taken at the yard); the trailer is set out here once taken
  if a == 'freight' then
    pcall(L.offersAt, p)
    local _, loaner = activeDef()
    for _, o in ipairs(R.offers or {}) do
      if o.from and o.from.id == p.id and not o.smuggle then
        local pay = loaner and round(o.freight * C.COMPANY_SHARE) or o.freight
        -- (2026-11-07: the details along – the stop menu shows them on a page of their own before the job is taken)
        local tr_ = o.trailer or {}
        local ti = tr_.model and L.trailerInfo(tr_.model, tr_.config) or {}
        add('take:' .. tostring(o.id), o.icon or '📦', tostring(o.cargoName) .. ' → ' .. tostring(o.to.name),
          string.format('%s · %s km · %d t%s%s', money(pay), (string.format('%.0f', o.distKm or 0)), o.tons or 0,
            o.urgent and ' · eilig' or '', o.fragile and ' · zerbrechlich' or ''), { disabled = S.job ~= nil or nil,
          offer = { cargo = o.cargoName, icon = o.icon, tons = o.tons, from = o.from and o.from.name, to = o.to and o.to.name,
            toCity = o.to and (o.to.city or o.to.detail), distKm = o.distKm, pay = money(pay), deadline = o.deadline,
            urgent = o.urgent or nil, fragile = o.fragile or nil, adr = o.adr or nil, long = o.long or nil, secure = o.secure or nil,
            trailerName = tr_.name or ti.name or 'Auflieger', trailerPic = tr_.preview or ti.preview,
            expiresIn = o.expires and math.max(0, o.expires - now()) or nil } })
      end
    end
  end
  -- the milk round from a dairy (2026-11-07)
  if S.tour then
    add('milktour:end', '✖', 'Milchtour abbrechen', 'Ohne Bezahlung – du bekommst dein Fahrzeug zurück', { warn = true })
  elseif p.type == 'dairy' then
    add('milktour', '🥛', 'Milchtour fahren', string.format('Mit dem Sammelwagen der Molkerei die Höfe im Umkreis von %d km abfahren', math.ceil(L.MILK_KM)),
      { disabled = (S.job ~= nil or R.trailerId ~= nil) or nil })
  end
  -- (2026-11-09) goods without papers: only at the places for it, on the map
  if a == 'underground' then pcall(L.smuggleAt, p) end
  do
    local _, loaner = activeDef()
    for _, o in ipairs(R.offers or {}) do
      if o.smuggle and o.from and o.from.id == p.id then
        local pay = loaner and round(o.freight * C.COMPANY_SHARE) or o.freight
        local ti = L.trailerInfo(o.trailer.model, o.trailer.config)
        add('take:' .. tostring(o.id), '🤫', 'Unter der Hand: ' .. tostring(o.cargoName), string.format('%s · %s km · nach %s', money(pay), string.format('%.0f', o.distKm or 0), tostring(o.to.name)),
          { disabled = S.job ~= nil or nil, warn = true, offer = { cargo = o.cargoName, icon = o.icon, tons = o.tons, from = o.from.name, to = o.to.name, distKm = o.distKm, pay = money(pay),
            deadline = o.deadline, smuggle = true, trailerName = o.trailer.name or ti.name, trailerPic = o.trailer.preview or ti.preview, expiresIn = o.expires and math.max(0, o.expires - now()) or nil } })
      end
    end
  end
  if a == 'repair' or a == 'home' then pcall(L.partActs, add) end
  -- (2026-11-08) what a used truck is hiding: the workshop's check finds it, then it can be put right
  if (a == 'repair' or a == 'home') and L.activeKind() == 'truck' then
    local own = L.ownTruck()
    if own and own.used then
      if not own.defectsKnown then
        add('diag', '🩺', 'Werkstatt-Check', '180 € · sucht nach versteckten Mängeln', { disabled = S.money < 180 or nil })
      else
        for k, on in pairs(own.defects or {}) do
          local d = on and L.DEFECT[k]
          if d then add('fix:' .. k, '🛠', d.name .. ' beheben', string.format('%s · %s', money(d.fix), d.text), { disabled = S.money < d.fix or nil }) end
        end
      end
    end
  end
  if a == 'ferry' or a == 'fly' then add('travel', a == 'fly' and '✈' or '⚓', a == 'fly' and 'Flug buchen' or 'Überfahrt buchen', 'Fahrplan und Preise') end
  if a == 'home' then
    add('office', '🏢', 'Ins Büro', 'Aufträge, Fuhrpark, Bank, Dokumente')
    add('fleet', '🚚', 'Fahrzeug wechseln', 'Fuhrpark & Werkstatt')
  end
  -- rest: everywhere standing a break; sleeping where one may
  local may = canRest()
  for _, o in ipairs(REST_OPTIONS) do
    local after = (clockHours() + o.h) % 24
    local sub = o.sub
    if o.h == 9 and v.tacho and v.tacho.redLeft then sub = string.format('verkürzte tägliche Ruhezeit – noch %d× bis zur Wochenruhe', v.tacho.redLeft) end
    v.rest[#v.rest + 1] = { h = o.h, label = o.label, sub = sub, best = o.best or nil,
      after = string.format('%02d:%02d', math.floor(after), math.floor((after % 1) * 60)),
      disabled = (o.h >= 6 and not may) or nil }
  end
  v.canSleep = may
  return v
end

function M.stopDo(id, arg)
  if not S then return end
  if id == 'sleep' then navigate('play'); return M.sleepFor(arg) end
  local take = tostring(id):match('^take:(.+)$')
  if take then navigate('play'); return M.acceptOffer(tonumber(take) or take) end
  if id == 'refuel' then navigate('play'); return M.refuel() end
  if id == 'repair' then return M.repair() end
  local lim = tostring(id):match('^limiter:(%w+)$')
  if lim then
    local own = L.ownTruck()
    if not own then notify('Den Begrenzer gibt es nur bei eigenen LKW zu verändern.', 5); return end
    if lim == 'back' then
      if S.money < L.LIMITER_REFIT then notify('Nicht genug Geld.', 4); return end
      S.money = S.money - L.LIMITER_REFIT
      own.limiterOff = nil
      notify('🔒 Begrenzer wieder eingebaut – der LKW fährt höchstens 90 km/h.', 6)
    else
      local m = L.LIMITER_MOD[lim]
      if not m or S.money < m.price then notify('Nicht genug Geld.', 4); return end
      S.money = S.money - m.price
      own.limiterOff = lim
      notify(string.format('🔧 Begrenzer ausgebaut (%s). Bei Polizeikontrollen kann es auffallen …', m.name), 7)
    end
    R.limiterKmh = -1                              -- (the truck told at the next look)
    save()
    return
  end
  if id == 'diag' then
    local own = L.ownTruck()
    if not own or S.money < 180 then return end
    L.pay('Werkstatt', -180, 'Werkstatt-Check')
    own.defectsKnown = true
    local names = {}
    for k, on in pairs(own.defects or {}) do if on and L.DEFECT[k] then names[#names + 1] = L.DEFECT[k].name end end
    notify(#names > 0 and ('🩺 Gefunden: ' .. table.concat(names, ', ')) or '🩺 Keine versteckten Mängel, der LKW ist in Ordnung.', 8)
    save()
    return
  end
  local pg = tostring(id):match('^part:(%w+)$')
  if pg then
    local own, veh, H = L.ownTruck(), playerVeh(), L.partHealth()
    if not own or not veh or not H or not H[pg] then return end
    local c = L.partCost(own, pg, H[pg])
    if S.money < c then return end
    if damageOf(veh:getID()) > 100 and R.trailerId and isCoupled() then notify('Bitte erst den Auflieger abkuppeln.', 5); return end
    L.pay('Werkstatt', -c, 'Werkstatt: ' .. pg)
    local title = ({ motor = 'Motor wird instand gesetzt', antrieb = 'Getriebe und Antrieb werden überholt', fahrwerk = 'Fahrwerk und Bremsen werden überholt', karosserie = 'Karosserie wird aufbereitet' })[pg]
    local function finish()
      own.repaired = own.repaired or {}
      own.repaired[pg] = true
      if pg == 'karosserie' then own.wear = own.wear or {}; own.wear.visual = 1 end
      local dmgNow = damageOf(veh:getID())
      if dmgNow > 100 then
        -- (dents only go with a reset: this group whole, everything else put back as it was, the damage less this group's share)
        local cond = L.condFixed({ [pg] = true })
        R.ownRepairUntil, R.dmgTarget, R.dmgLive = now() + 3, { v = dmgNow * (1 - L.partShare(pg)), at = now() + 3.2 }, dmgNow
        spawn.safeTeleport(veh, vehPos(veh), quatFromDir(vec3(veh:getDirectionVector()), vec3(veh:getDirectionVectorUp())))
        R.restoreFuel = { id = veh:getID(), tanks = {}, t = now() + 1.0, cond = cond, keep = true }
      else
      veh:queueLuaCommand(L.partsCmd({ [pg] = true }))
      end
      R.wearSig, R.partReqT, R.condT = nil, 0, 0
      L.workMsg(({ motor = 'Der Motor läuft wieder rund. Der Tacho steht weiter bei ' .. L.kmText(own.km) .. ' km.', antrieb = 'Getriebe und Antrieb sind überholt.', fahrwerk = 'Fahrwerk und Bremsen sind überholt.', karosserie = 'Die Karosserie ist aufbereitet. Sieht wieder gut aus.' })[pg])
      save()
    end
    if not L.workStart({ title = title, sub = 'Kilometerstand bleibt erhalten', done = finish }) then finish() end
    return
  end
  local fix = tostring(id):match('^fix:(%w+)$')
  if fix then
    local own, d = L.ownTruck(), L.DEFECT[fix]
    if not own or not d or not (own.defects and own.defects[fix]) or S.money < d.fix then return end
    L.pay('Werkstatt', -d.fix, d.name .. ' behoben')
    local function finish()
      own.defects[fix] = nil
      R.wearSig = nil
      L.workMsg(d.done or (d.name .. ' behoben.'))
      save()
    end
    if not L.workStart({ title = d.name .. ' wird behoben', sub = d.text, done = finish }) then finish() end
    return
  end
  local asg = tostring(id):match('^assist:(%w+)$')
  if asg then
    local own, d = L.ownTruck(), L.ASSIST[asg]
    if not own or not d or S.money < d.price then return end
    L.pay('Werkstatt', -d.price, d.name .. ' eingebaut')
    own.assist = own.assist or {}
    own.assist[asg] = true
    notify(d.icon .. ' ' .. d.name .. ' eingebaut.', 6)
    save()
    return
  end
  if id == 'milktour' then return M.milkTour() end
  if id == 'milktour:end' then navigate('play'); return M.milkTourCancel() end
  local buy = tostring(id):match('^buy:(%w+)$')
  if buy then return L.shopBuy(stops.inside() or R.near, buy) end
  -- (the back door: the stop menu plays the minigame, this is its end – passed or not)
  if id == 'back:result' then return L.backResult(stops.inside() or R.near, arg == true or arg == 'ok') end
  if id == 'tank:big' then
    local own = L.ownTruck()
    if not own then notify('Den großen Tank gibt es nur für eigene LKW.', 5); return end
    if own.tankBig then return end
    if S.money < L.TANK_BIG_PRICE then notify('Nicht genug Geld.', 4); return end
    L.pay('Werkstatt', -L.TANK_BIG_PRICE, 'Großer Tank eingebaut')
    own.tankBig = true
    R.limiterTank = -1                              -- (the truck told at the next look)
    notify('🛢 Großer Tank eingebaut – doppelt so viel Diesel. Volltanken nicht vergessen.', 6)
    save()
    return
  end
  if id == 'dealer' then return M.toggleOffice('dealer') end
  if id == 'garage' then navigate('fernfahrerGarage'); return end
  if id == 'travel' then return M.toggleOffice('travel') end
  if id == 'office' then return M.toggleOffice('market') end
  if id == 'fleet' then return M.toggleOffice('fleet') end
end

function M.uiStopOpen(on)
  -- (2026-11-09: from the ring's menu into the cab workshop the brake has to stay on: it only comes off a moment after the last menu has closed)
  if on then R.stopOpen, R.brakeOffAt = true, nil; L.autoBrake()
  else R.stopOpen, R.brakeOffAt = R.garageOn and true or false, now() + 0.8 end
end

-- mirrors and seat (HUD FernfahrerCockpit → cab.lua)
function M.uiCab()
  local v = require('fernfahrer/cab').view(playerVeh())
  if type(v) == 'table' then
    v.virtual = { on = S and S.settings and S.settings.mirrorsOn or false, w = L.mirrors and L.mirrors.cfg.w or 220,
      q = L.mirrors and L.mirrors.cfg.q or (S and S.settings and S.settings.mirrorCfg and S.settings.mirrorCfg.q) or 'eco' }
    local mm = L.mirrorsMod()
    v.virtual.hfov, v.virtual.yaw, v.virtual.bright = mm.cfg.hfov, mm.cfg.yaw, mm.cfg.bright
    v.virtual.mode = mm.cfg.mode or 'flip'
    v.virtual.auto = mm.cfg.hfov == mm.AUTO.hfov and mm.cfg.yaw == mm.AUTO.yaw and mm.cfg.bright == mm.AUTO.bright
  end
  return v
end
function M.cabMirror(name, dx, dz, reset) require('fernfahrer/cab').mirror(playerVeh(), name, dx, dz, reset) end
function M.cabUnfocus() require('fernfahrer/cab').unfocus() end
function M.cabSeat(what, d) require('fernfahrer/cab').seat(playerVeh(), what, d) end
function M.cabView() require('fernfahrer/cab').toCab(playerVeh()) end

-- the virtual mirrors (mirrors.lua): on/off (key Ctrl+Shift+M, the 🪞 page), size; shown while driving the truck
function L.mirrorsMod()
  if not L.mirrors then
    L.mirrors = require('fernfahrer/mirrors')
    L.mirrors.load(S and S.settings and S.settings.mirrorCfg)
    L.mirrors.setOn(S and S.settings and S.settings.mirrorsOn)
  end
  return L.mirrors
end
-- the scene photos for the police report (camera.lua; the dashcam was taken out 2026-11-04: frame drops). The module
-- is loaded only when a photo is asked for, and works only while photos are queued.
function L.camMod()
  if not L.cam then L.cam = require('fernfahrer/camera') end
  return L.cam
end
function L.camTick(dt)
  if not L.cam or not (S and R.mode) then return end
  if L.cam.busy() then L.cam.update(dt, nil) end
end

-- the crash in slow motion (2026-11-04): the moment the truck takes real damage at speed, the simulation drops to a
-- fraction of real time for a moment (BeamNG's own slow motion, simTimeAuthority) and eases back; with it a dull
-- thump and a ringing in the ears that fades (the Kabine app's sounds). Only from real time (the player's own slow
-- motion is left alone), not paused, at most every SLOWMO_GAP_S.
L.SLOWMO = { minKmh = 25, minDmg = 350, gapS = 14 }
-- the speed over the real seconds after the hit, like a film edit (2026-11-04: "länger, filmmäßig, abwechselnd"):
-- at once nearly still, a short rush, slowed hard again for the parts flying, then easing back to real time.
-- { real seconds, simulation speed } – straight lines in between
L.SLOWMO_CURVE = {
  { 0.0, 0.06 }, { 1.4, 0.08 },       -- the impact: almost frozen
  { 1.75, 0.55 }, { 2.3, 0.6 },       -- a burst
  { 2.6, 0.1 }, { 4.6, 0.12 },        -- slow again: the debris, the truck still moving
  { 5.4, 0.35 }, { 6.6, 1.0 },        -- back to real time
}
function L.slowmoAt(s)
  local c = L.SLOWMO_CURVE
  if s <= c[1][1] then return c[1][2] end
  for i = 2, #c do
    if s <= c[i][1] then
      local a, b = c[i - 1], c[i]
      return a[2] + (b[2] - a[2]) * (s - a[1]) / (b[1] - a[1])
    end
  end
  return nil                                   -- (past the end)
end
function L.crashHit(kmh, dmg)
  if not S or S.settings.slowmo == false then return end
  local sta = rawget(_G, 'simTimeAuthority')
  if not (sta and sta.setInstant and sta.set) then return end
  local t = now()
  if R.slowmo or t - (R.slowmoAt or -1e9) < L.SLOWMO.gapS then return end
  local okG, cur = pcall(sta.get)
  if okG and cur and cur < 0.99 then return end
  if L.gamePaused() then return end
  R.slowmo, R.slowmoAt = { t0 = t }, t
  pcall(sta.setInstant, L.slowmoAt(0))
  guihooks.trigger('FernfahrerSound', { name = 'tinnitus', strength = math.min(1, (kmh or 30) / 80) })
end
function L.slowmoTick()
  if not R.slowmo then return end
  local sta = rawget(_G, 'simTimeAuthority')
  if not (sta and sta.setInstant) then R.slowmo = nil; return end
  -- (paused in the middle – the menu: the speed back to normal, the effect over)
  if L.gamePaused() then R.slowmo = nil; pcall(sta.setInstant, 1); return end
  local s = L.slowmoAt(now() - R.slowmo.t0)
  if not s then
    R.slowmo = nil
    pcall(sta.setInstant, 1)
    return
  end
  pcall(sta.setInstant, s)
end
-- every frame: the player vehicle's damage against the frame before (the crash detection of accidents.lua looks only
-- every 0.25 s – too late for a slow motion that should catch the impact); the speed is the one of the frame before
function L.hitCheck()
  local v = playerVeh()
  if not v then R.hitId = nil; return end
  local id = v:getID()
  local d = damageOf(id)
  local kmh = vehSpeed(v) * 3.6
  if R.hitId == id and d - (R.hitDmg or d) > L.SLOWMO.minDmg and (R.hitKmh or 0) >= L.SLOWMO.minKmh then
    L.crashHit(R.hitKmh, d - R.hitDmg)
  end
  R.hitId, R.hitDmg = id, d
  -- (the speed before: kept from the frames before the impact, not the one it has already lost)
  if not R.slowmo then R.hitKmh = kmh end
end
function L.slowmoOff()
  if R.slowmo then
    R.slowmo = nil
    local sta = rawget(_G, 'simTimeAuthority')
    if sta and sta.setInstant then pcall(sta.setInstant, 1) end
  end
end

-- the game paused (its menu over the world): the mirrors would stand above it too
function L.gamePaused()
  local sta = rawget(_G, 'simTimeAuthority')
  if sta and sta.getPause then local ok, p = pcall(sta.getPause); if ok and p then return true end end
  local bt = rawget(_G, 'bullettime')
  if bt and bt.getPause then local ok, p = pcall(bt.getPause); if ok and p then return true end end
  return false
end
function L.mirrorsTick(dt)
  if not (S and S.settings and S.settings.mirrorsOn) and not L.mirrors then return end
  local mm = L.mirrorsMod()
  local v, truck = playerVeh(), careerVeh()
  -- (the mirrors are ImGui, drawn above every page of the UI: hidden whenever a screen is up – the loading screen at
  -- the start, a trip, the title card, the office, a stop's menu, the settlement – 2026-11-04)
  local t = now()
  -- (2026-11-08: a day's card that never came kept them hidden for good – "virtual mirrors on", and nothing there)
  local screenUp = R.boot ~= nil or R.trip ~= nil or R.pendingTeleport ~= nil
    or (R.screenAt and t - R.screenAt < 2) or (R.titleUntil and t < R.titleUntil) or (R.titleAt and t < R.titleAt + 20)
    or R.officeOpen or R.stopOpen or R.reportAt ~= nil or cinematic.active() or L.cine.active() or L.gamePaused()
  local drivingTruck = v and truck and v:getID() == truck:getID() and not screenUp and activeKind() == 'truck'
  if S.settings.mirrorsOn then
    local st = drivingTruck and 'shown' or (screenUp and 'hidden: a screen is up' or 'hidden: not driving the truck')
    if st ~= R.mirrorLog then R.mirrorLog = st; log('I', logTag, 'mirrors ' .. st) end
  end
  mm.update(dt, { veh = drivingTruck and truck or nil, save = function(cfg) S.settings.mirrorCfg = cfg end })
end
function M.mirrorsToggle()
  if not R.mode or not S then return end
  local on = L.mirrorsMod().toggle()
  S.settings.mirrorsOn = on
  notify(on and 'Virtuelle Spiegel an (Strg+Umschalt+M) – Fenster lassen sich verschieben.' or 'Virtuelle Spiegel aus.', 3)
end
function M.mirrorsView(what, d)
  if not S then return end
  local mm = L.mirrorsMod()
  mm.setView(what, d)
  S.settings.mirrorCfg = mm.cfg
end
function M.mirrorsQuality(q)
  if not S then return end
  local mm = L.mirrorsMod()
  mm.setQuality(q)
  S.settings.mirrorCfg = mm.cfg
end
function M.mirrorsSize(d)
  if not S then return end
  local mm = L.mirrorsMod()
  mm.setSize(d)
  S.settings.mirrorCfg = mm.cfg
end

-- Enter in a stop ring: the place's menu (only there, only standing: elsewhere the key stays the game's)
function M.enterStop()
  if cinematic.active() then cinematic.skip(); return end          -- (Enter during the day's camera flight: skip)
  if not R.mode or not S or R.officeOpen or R.stopOpen then return end
  if not stops.inside() then return end
  if vehSpeed(playerVeh()) > 2 then notify('Erst anhalten.', 3); return end
  navigate('fernfahrerStop')
end

-- the tachograph's OUT mode: a private drive without a job is not recorded (no driving time, no rest either)
function M.privateToggle()
  if not S then return end
  if not S.privateDrive and S.job then notify('Privatfahrt geht nur ohne Auftrag.', 4); return end
  S.privateDrive = not S.privateDrive or nil
  R.hudSlowT = nil
  notify(S.privateDrive and 'Fahrtenschreiber auf OUT – Privatfahrt, Lenkzeit wird nicht erfasst.' or 'Fahrtenschreiber wieder an – Lenkzeit wird erfasst.', 5)
end

-- the tachograph's buttons (HUD FernfahrerTacho): other work, availability, break / rest – while standing
function M.tachoSet(act)
  if not S or not S.tacho then return end
  local ok, why = tacho.setActivity(S.tacho, act, vehSpeed(playerVeh()))
  R.hudSlowT = nil                               -- (the HUD's tachograph at once, not up to a second later)
  if not ok then notify(why, 4); return end
  if act == 'rest' then
    notify('Fahrtenschreiber: Pause läuft. Gültig ab 45 min am Stück (oder 15 + 30 min). Losfahren beendet die Pause.', 6)
  end
end

-- the breakdown service is called: it drives up and works first (service.lua)
function M.roadside() service.request() end
-- (2026-11-08) its work done: the vehicle back on its wheels and whole where it is, the trailer hitched again
function L.serviceRepair(fee, label, after)
  local veh = careerVeh() or playerVeh()
  if not veh then return end
  local hadTrailer = R.trailerId ~= nil and S.job and (S.job.phase == 'toDelivery' or S.job.phase == 'atDelivery')
  core_vehicleBridge.requestValue(veh, function(ret)
    local tanks = ret and ret[1] or {}
    if fee > 0 then L.pay('Pannendienst', -fee, tostring(label)) end
    local d = vec3(veh:getDirectionVector())
    d.z = 0
    if d:length() < 0.01 then d = vec3(0, 1, 0) end
    local rot = quatFromDir(d:normalized(), vec3(0, 0, 1))          -- upright, same heading
    spawn.safeTeleport(veh, vehPos(veh) + vec3(0, 0, 0.5), rot)
    R.restoreFuel = { id = veh:getID(), tanks = tanks, t = now() + 1.0 }
    if hadTrailer then R.rehitchAt = now() + 2.0 end
    story('roadside')
    if after then after() end
    save()
  end, 'energyStorage')
end

-- A gap in BeamNG.Earth's world (2026-11-05): a bridge or a piece of road missing on the route – the truck would fall
-- into the river and the job be ruined. Strg+Umschalt+B (or the cockpit's 🌉): the route ahead is walked every 8 m;
-- where the game's road graph says the road is but no surface is there, that is the gap; the truck (and its trailer,
-- coupled again) is set down on the route just after it, facing on along it, repaired – free, and the accident
-- the fall may have started is called off. Without a route: straight on along the road the truck stands on.
L.RESCUE = { STEP = 8, FROM = 15, TO = 1600, OK_RUN = 4, Z_TOL = 1.8, GAP_S = 20 }
-- the road height the game's graph gives at a point (its nearest link), or nil
function L.roadZAt(p)
  if not (map and map.findClosestRoad and map.getMap) then return nil end
  local ok, n1, n2 = pcall(map.findClosestRoad, p)
  local nodes = ok and n1 and n2 and map.getMap().nodes
  local a, b = nodes and nodes[n1], nodes and nodes[n2]
  if not a or not b then return nil end
  local A, B = vec3(a.pos), vec3(b.pos)
  local ab = B - A
  local l2 = ab.x * ab.x + ab.y * ab.y
  local k = l2 > 0 and clamp(((p.x - A.x) * ab.x + (p.y - A.y) * ab.y) / l2, 0, 1) or 0
  local q = A + ab * k
  if (q.x - p.x) ^ 2 + (q.y - p.y) ^ 2 > 25 ^ 2 then return nil end
  return q.z
end
-- the surface under a point (the first thing a ray from above meets), or nil
function L.surfaceZAt(x, y, zRef)
  local top = zRef + 40
  local d = castRayStatic(vec3(x, y, top), vec3(0, 0, -1), 120)
  if not d or d >= 120 then return nil end
  return top - d
end
-- the samples along the way ahead: the route's (world positions every STEP m), else straight on
function L.rescuePath(v)
  local anchor = earthAnchor()
  local pp, dir = vehPos(v), vec3(v:getDirectionVector())
  dir.z = 0
  dir = dir:length() > 0.01 and dir:normalized() or vec3(0, 1, 0)
  local out = {}
  local gps = earthModule('gps')
  local r = gps and gps.route and gps.route()
  local pts = r and r.points
  if anchor and pts and #pts >= 2 then
    local W = {}
    for i, q in ipairs(pts) do local x, y = anchor:geodeticToWorld(q[1], q[2], 0); W[i] = vec3(x, y, 0) end
    -- (where on it the truck is: the nearest segment)
    local bi, bk, bd = 1, 0, 1e18
    for i = 1, #W - 1 do
      local a, b = W[i], W[i + 1]
      local ab = b - a
      local l2 = ab.x * ab.x + ab.y * ab.y
      local k = l2 > 0 and clamp(((pp.x - a.x) * ab.x + (pp.y - a.y) * ab.y) / l2, 0, 1) or 0
      local q = a + ab * k
      local d = (q.x - pp.x) ^ 2 + (q.y - pp.y) ^ 2
      if d < bd then bi, bk, bd = i, k, d end
    end
    if bd < 120 ^ 2 then
      local acc, i, k = 0, bi, bk
      while i < #W and acc <= L.RESCUE.TO do
        local a, b = W[i], W[i + 1]
        local seg = b - a
        local len = math.sqrt(seg.x * seg.x + seg.y * seg.y)
        local s = k * len
        while s < len and acc <= L.RESCUE.TO do
          local f = len > 0 and s / len or 0
          local p = a + seg * f
          out[#out + 1] = { pos = vec3(p.x, p.y, pp.z), dir = len > 0 and vec3(seg.x / len, seg.y / len, 0) or dir, d = acc }
          s = s + L.RESCUE.STEP
          acc = acc + L.RESCUE.STEP
        end
        i, k = i + 1, 0
      end
      if #out > 0 then return out, true end
    end
  end
  for d = 0, L.RESCUE.TO, L.RESCUE.STEP do out[#out + 1] = { pos = pp + dir * d, dir = dir, d = d } end
  return out, false
end
-- where to set the truck down: the first stretch of OK_RUN good samples after a gap (or, no gap seen, after FROM m)
-- (2026-11-05, again: a stretch free for the whole rig – the truck's place and 24 m behind it for the trailer, the
-- full width of the lane; anything in the way counts – a missing bridge, a house on the road, a bump. Each sample:
-- three rays across the lane, the surface within TOL of the road's height and level across)
L.RESCUE.TOL, L.RESCUE.HALF_W, L.RESCUE.BACK = 0.9, 1.5, 3       -- (m; m to the side; samples behind for the trailer)
function L.rescueSampleOk(s, zRef)
  local rz = L.roadZAt(s.pos)
  local ref = rz or zRef
  local side = vec3(-s.dir.y, s.dir.x, 0) * L.RESCUE.HALF_W
  local zs = {}
  for k, off in ipairs({ vec3(0, 0, 0), side, side * -1 }) do
    local p = s.pos + off
    local z = L.surfaceZAt(p.x, p.y, ref)
    if not z or math.abs(z - ref) > (rz and L.RESCUE.TOL or 2.0) then return false, rz ~= nil end
    zs[k] = z
  end
  if math.abs(zs[2] - zs[3]) > 0.8 then return false, true end    -- (a kerb, a ditch, half a house across the lane)
  return true, false, zs[1]
end
function L.rescueTarget(v)
  local path, onRoute = L.rescuePath(v)
  local zPrev = vehPos(v).z
  local gapSeen, okList = false, {}
  for i, s in ipairs(path) do
    if s.d >= L.RESCUE.FROM - L.RESCUE.BACK * L.RESCUE.STEP then
      local ok, blocked, z = L.rescueSampleOk(s, zPrev)
      okList[i] = ok and z or false
      if ok then zPrev = z elseif blocked then gapSeen = true end
      -- the truck at sample i: free from BACK samples behind it to one ahead
      if ok and s.d >= L.RESCUE.FROM + L.RESCUE.BACK * L.RESCUE.STEP and (gapSeen or s.d > 40) and path[i + 1] then
        local free = true
        for k = i - L.RESCUE.BACK, i - 1 do if not okList[k] then free = false; break end end
        if free then
          local ok2 = L.rescueSampleOk(path[i + 1], z)
          if ok2 then return { pos = vec3(s.pos.x, s.pos.y, z), dir = s.dir, d = s.d }, gapSeen, onRoute end
        end
      end
    end
  end
  return nil, gapSeen, onRoute
end
function M.earthRescue()
  if not R.mode or not S then return end
  local v = playerVeh()
  if not v then return end
  local t = now()
  -- (pressed again soon: on from where it set down – a short wait only, the world there has to come in)
  if R.rescueAt and t - R.rescueAt < 2.5 then return end
  if vehSpeed(v) > 25 / 3.6 then notify('Kartenfehler-Hilfe: erst langsamer werden oder anhalten.', 4); return end
  local okT, target, gapSeen, onRoute = pcall(L.rescueTarget, v)
  if not okT then log('W', logTag, 'earth rescue: ' .. tostring(target)) end
  if not okT or not target then
    notify('Vor dir ist auf der Route keine freie Strecke zu finden – das Navi setzen oder ein Stück weiter (die Welt dort lädt noch) und noch einmal drücken.', 7)
    return
  end
  R.rescueAt = t
  local rot = quatFromDir(target.dir, vec3(0, 0, 1))
  local pos = target.pos + vec3(0, 0, 0.5)
  -- (the truck reset at the place – a coupled trailer is set behind it by the game itself (core_trailerRespawn on the
  -- reset) and coupled again; a trailer that came loose is set behind it the same way a moment later. Before, the
  -- trailer was moved on its own first and the two fought over the place.)
  local tr = R.trailerId and vehById(R.trailerId)
  local hadTrailer = tr ~= nil and isCoupled()
  pcall(spawn.safeTeleport, v, pos, rot, nil, nil, nil, nil, true)
  -- (then the trailer on the fifth wheel and locked – also when it was coupled: the reset leaves it beside the truck)
  if tr then R.rehitchAt = t + (hadTrailer and 1.0 or 1.5) end
  pcall(accidents.reset)                         -- (a "crash" into the gap is no accident: no police, no report)
  R.slowmoUntil = nil
  S.stats.mapRescues = (S.stats.mapRescues or 0) + 1
  log('I', logTag, string.format('earth rescue: %d m on %s, gap %s', math.floor(target.d), onRoute and 'the route' or 'the road', tostring(gapSeen)))
  notify(string.format('🌉 Kartenfehler überbrückt – %d m weiter %s abgesetzt. Kostenlos, Schäden durch den Fehler sind erlassen.',
    math.floor(target.d + 0.5), onRoute and 'auf der Route' or 'auf der Straße'), 8)
  guihooks.trigger('FernfahrerRescue', { dist = math.floor(target.d + 0.5), gap = gapSeen })
  save()
end
-- back onto the road (2026-11-07): stuck off it, in a field, wedged – the truck (and its trailer, coupled again) set on
-- the nearest road of the game's graph, facing the way it went, where the lane is free; free of charge as the bridge
-- help. Along that road a little on when the nearest spot is blocked.
function M.roadBack()
  if not R.mode or not S then return end
  local v = playerVeh()
  if not v then return end
  local t = now()
  if R.rescueAt and t - R.rescueAt < 2.5 then return end
  if vehSpeed(v) > 25 / 3.6 then notify('Erst langsamer werden oder anhalten.', 4); return end
  if not (map and map.findClosestRoad and map.getMap) then notify('Keine Straßendaten hier.', 4); return end
  local p = vehPos(v)
  local okR, n1, n2 = pcall(map.findClosestRoad, p)
  local nodes = okR and n1 and n2 and map.getMap().nodes
  local a, b = nodes and nodes[n1], nodes and nodes[n2]
  if not a or not b then notify('Keine Straße in der Nähe gefunden.', 5); return end
  local A, B = vec3(a.pos), vec3(b.pos)
  local ab = B - A
  ab.z = 0
  local len = ab:length()
  if len < 0.5 then notify('Keine Straße in der Nähe gefunden.', 5); return end
  local dir = ab / len
  local heading = vec3(v:getDirectionVector()); heading.z = 0
  if heading:length() > 0.1 and heading:dot(dir) < 0 then dir = dir * -1 end
  local k = clamp(((p.x - A.x) * ab.x + (p.y - A.y) * ab.y) / (len * len), 0, 1)
  local q = A + (B - A) * k
  -- (the spot, else along the road a few steps either way: the first where the lane is free for truck and trailer)
  local target
  for _, off in ipairs({ 0, 8, 16, -8, 24, -16, 32, 48, 64 }) do
    local c = q + dir * off
    local s = { pos = vec3(c.x, c.y, c.z), dir = dir, d = 0 }
    local ok, _, z = L.rescueSampleOk(s, c.z)
    local back = ok and L.rescueSampleOk({ pos = c - dir * 14, dir = dir, d = 0 }, z)
    if ok and back then target = { pos = vec3(c.x, c.y, z), dir = dir }; break end
  end
  if not target then notify('Die Straße hier ist nicht frei – die Kartenfehler-Hilfe 🌉 setzt dich auf der Route weiter.', 6); return end
  R.rescueAt = t
  -- (2026-11-08: only moved, not repaired – every dent and a flat tyre stay; the bridge help above does repair. A coupled
  -- trailer has to let go first; when it is hitched again the game resets it, so what the load has taken is carried over)
  local tr = R.trailerId and vehById(R.trailerId)
  local coupled = tr and isCoupled()
  if tr and S.job then S.job.dmgCarry = (S.job.dmgCarry or 0) + damageOf(R.trailerId) end
  if coupled then v:queueLuaCommand('beamstate.detachCouplers()') end
  R.roadBackDo = { id = v:getID(), at = t + (coupled and 0.35 or 0), pos = target.pos + vec3(0, 0, 0.5), rot = quatFromDir(target.dir, vec3(0, 0, 1)), trailer = tr ~= nil }
  pcall(accidents.reset)
  notify('🛣 Zurück auf der Straße – kostenlos. Schäden bleiben, repariert wird in der Werkstatt.', 6)
end

-- a crash alone (accidents.lua 'ask'): the HUD's phone – call the police (they come, a report, maybe a fine) or not
function M.callPolice() if accidents.callPolice() then notify('📞 Polizei wird verständigt …', 4) end end
function M.dismissCall() accidents.dismissCall() end

-- BeamNG.Earth's autodrive (its map's GPS button: the vehicle's own AI drives the route, in its lane, at the limit) –
-- on and off from the route advisor (🤖) or Strg+Umschalt+A, while driving (2026-11-05)
function M.autodriveToggle()
  if not R.mode or not S then return end
  local gps = earthModule('gps')
  if not (gps and gps.setAutodrive and gps.autodrive) then notify('Autodrive gibt es mit BeamNG.Earth 1.8 und neuer.', 5); return end
  local on = not gps.autodrive()
  if on then
    local r = gps.route and gps.route()
    if not (r and r.points and #r.points > 1) then notify('Autodrive braucht ein Ziel – erst einen Auftrag oder ein Navi-Ziel setzen.', 5); return end
  end
  local okA, now_ = pcall(gps.setAutodrive, on)
  local isOn = okA and now_ or false
  notify(isOn and '🤖 Autodrive an – der LKW fährt die Route selbst. Aus mit 🤖 oder Strg+Umschalt+A.' or '🤖 Autodrive aus – du fährst wieder selbst.', 5)
end
-- (2026-11-09) the cinematic mode: while the autodrive drives, shots from outside (drivecine.lua), the HUD out of the picture
L.cine = require('fernfahrer/drivecine')
function L.cineCef(on)
  local vis = rawget(_G, 'ui_visibility')
  if vis and vis.setCef then pcall(vis.setCef, on) end
end
function L.cineStop()
  if L.cine.active() then
    L.cine.stop()
    if vices.override == L.cine.pose then vices.override = nil end
  end
  R.cineHideAt = nil
  if R.cineHidden then R.cineHidden = nil; L.cineCef(true) end
end
function M.cineToggle()
  if not R.mode or not S then return end
  if L.shots.active() then L.shotsStop(); return end
  if R.photos then R.photos.stop(); return end
  if L.cine.active() then L.cineStop(); notify('🎬 Cinematic aus.', 3); return end
  if not L.autodriveOn() then notify('Den Cinematic-Modus gibt es im Autodrive (Strg+Umschalt+A).', 5); return end
  if cinematic.active() then return end
  vices.installCam()
  L.cine.start(function() return careerVeh() or playerVeh() end, function() return R.trailerId ~= nil end)
  vices.override = L.cine.pose
  R.cineHideAt = now() + 2.5
  notify('🎬 Cinematic an – Strg+Umschalt+C beendet ihn. Die Anzeigen verschwinden gleich.', 3)
end
function L.cineTick(t)
  if not L.cine.active() then return end
  if not L.autodriveOn() or L.gamePaused() or R.officeOpen or R.stopOpen or R.trip or R.pendingTeleport or R.sleep or R.cop then
    L.cineStop()
    return
  end
  if R.cineHideAt and t > R.cineHideAt then R.cineHideAt, R.cineHidden = nil, true; L.cineCef(false) end
end
function L.autodriveOn()
  local gps = earthModule('gps')
  local ok, on = pcall(function() return gps and gps.autodrive and gps.autodrive() end)
  return ok and on or false
end

-- (now and then, while driving: under the road by several metres – fallen through a gap? the hint for the key)
function L.gapHintTick(t)
  if t - (R.gapHintT or 0) < 1 then return end
  R.gapHintT = t
  local v = playerVeh()
  if not v or vehSpeed(v) > 8 then return end
  local p = vehPos(v)
  local rz = L.roadZAt(p)
  if rz and p.z < rz - 4 and t - (R.gapHintShown or -1e9) > 90 then
    R.gapHintShown = t
    guihooks.trigger('FernfahrerGapHint', {})
    notify('Unter der Straße gelandet? Fehlt hier eine Brücke (BeamNG.Earth), hilft Strg+Umschalt+B oder 🌉 im Cockpit – kostenlos.', 9)
  end
end

-- One key for "what makes sense here" (Strg+Umschalt+G): hitch, unhitch, fuel, repair, dealer, rest, else the office.
function M.primaryAction()
  if not R.mode or not S then return end
  local job = S.job
  local v = playerVeh()
  local stopped = vehSpeed(v) < 1.5
  local tv, cv = vehById(R.trailerId), careerVeh()
  if job and tv and cv and (job.phase == 'toTrailer' or (job.phase == 'hitching' and R.hitchStep == 'manual')) then
    if vehPos(cv):distance(vehPos(tv)) < 25 then return M.hitchNow() end
  end
  if job and L.needsSecure() and job.phase == 'toDelivery' and stopped and isCoupled() then return M.secureLoad() end
  if job and job.phase == 'atDelivery' and isCoupled() then return M.unhitchNow() end
  if R.near and R.near.action == 'rental' and stops.inside() then navigate('fernfahrerRental'); return end
  if stops.inside() and stopped then navigate('fernfahrerStop'); return end
  local n = R.near
  if n and stopped then
    if n.action == 'refuel' and (not R.fuel or R.fuel.ratio < 0.97) then return M.refuel() end
    if (n.action == 'repair' or n.action == 'home') and v and damageOf(v:getID()) > 100 then navigate('fernfahrerStop'); return end
    if n.action == 'dealerTruck' or n.action == 'dealerCar' then return M.toggleOffice('dealer') end
    if n.action == 'ferry' or n.action == 'fly' then return M.toggleOffice('travel') end
  end
  if stopped and canRest() and S.tacho and S.tacho.day > 1800 then return M.rest() end
  return M.toggleOffice()
end

-- what a police check finds
local function controlCheck()
  local found = tacho.takeViolations(S.tacho)
  -- the breath test and the drug pre-test (the cab's beer / joint: vices.lua), German limits
  local rd = vices.readings()
  local bacText = (string.format('%.2f', rd.bac):gsub('%.', ','))
  local high = rd.thc >= 3.5
  if rd.bac >= 1.1 then
    table.insert(found, { kind = 'alcohol', amount = 3000, reason = string.format('Trunkenheit im Verkehr, %s ‰ (§ 316 StGB) – Strafanzeige, Führerschein sichergestellt', bacText) })
  elseif rd.bac >= 0.5 then
    table.insert(found, { kind = 'alcohol', amount = high and 1000 or 500, reason = string.format('%s ‰ Alkohol%s (§ 24a StVG) – 2 Punkte, 1 Monat Fahrverbot', bacText, high and ' und THC' or '') })
    high = false
  elseif rd.bac >= 0.3 then
    message(string.format('Polizei: Atemalkohol %s ‰ – unter der Grenze, aber ab 0,3 ‰ zählt jeder Fahrfehler als Straftat. Lass das Bier lieber stehen.', bacText), 'Polizei')
  end
  if high then
    table.insert(found, { kind = 'thc', amount = 500, reason = (string.format('THC im Blut, ca. %.1f ng/ml (Grenzwert 3,5 – § 24a StVG) – 2 Punkte, 1 Monat Fahrverbot', rd.thc):gsub('(%d)%.(%d)', '%1,%2')) })
  end
  local v = playerVeh()
  if v and damageOf(v:getID()) / C.TRUCK_DMG_FULL > 0.6 then
    table.insert(found, { kind = 'unsafe', amount = 90, reason = 'Fahrzeug nicht verkehrssicher (schwerer Schaden)' })
  end
  if R.trailerId and S.job and (cargoCondition() < 0.5 or L.needsSecure()) then
    table.insert(found, { kind = 'load', amount = L.needsSecure() and 240 or 60, reason = 'Ladung mangelhaft gesichert' })
  end
  -- (2026-11-08) dangerous goods without their papers
  if S.job and S.job.adr and not S.job.papers then
    table.insert(found, { kind = 'adr', amount = 4500, reason = 'Gefahrgut ohne ADR-Beförderungspapiere (GGVSEB)' })
  end
  -- the limiter taken out: the officers read out the truck's controller – the cheap chip shows more often
  local off = L.limiterOff()
  local mod = off and L.LIMITER_MOD[off]
  if mod and math.random() < mod.detect then
    local own = L.ownTruck()
    own.limiterOff = nil
    R.limiterKmh = -1                              -- (the limiter back in the truck at once)
    table.insert(found, { kind = 'limiter', amount = mod.fine + L.LIMITER_REFIT,
      reason = string.format('Geschwindigkeitsbegrenzer manipuliert (%s entdeckt) – Begrenzer muss wieder eingebaut werden', mod.name) })
  end
  return found
end

local eventCtx = {
  dayNo = function() return S and S.dayNo or 1 end,
  here = function() return here() end,
  playerPos = function() local v = playerVeh(); return v and vehPos(v) or nil end,
  playerDir = function()
    local v = playerVeh()
    if not v then return nil end
    local d = v:getDirectionVector(); d = vec3(d.x, d.y, 0)
    return d:length() > 1e-3 and d:normalized() or nil
  end,
  speedKmh = function() local v = playerVeh(); return v and vehSpeed(v) * 3.6 or 0 end,
  roadLimit = function() return R.limit end,
  ruleLimit = function() return R.limitEff or R.limit end,
  night = function() local h = clockHours(); return h < 6.5 or h >= 20 end,
  routePoints = function()
    local gps = earthModule('gps')
    local r = gps and gps.route and gps.route()
    return r and r.points or nil
  end,
  anchor = function()
    local c = earthCore()
    local st = c and c._state and c._state() or nil
    return st and st.anchor or nil
  end,
  hasJob = function() return S and S.job ~= nil end,
  fine = function(a, r) M.fine(a, r) end,
  notify = function(t, ttl) notify(t, ttl) end,
  message = function(t) message(t, 'Polizei') end,
  story = function(k) story(k) end,
  xp = function(n) addXp(n) end,
  controlCheck = controlCheck,
  controlDialog = function(found) L.copStart(found) end,
}

-- the company's documents (accident reports, …): newest first, at most 60
local function addDocument(doc)
  S.documents = S.documents or {}
  table.insert(S.documents, 1, doc)
  for i = #S.documents, 101, -1 do S.documents[i] = nil end   -- (delivery notes and police reports: the last 100)
  S.stats.accidents = (S.stats.accidents or 0) + (doc.kind == 'accident' and 1 or 0)
  save()
end

-- the place of an accident: the kind of road (from its limit) and the nearest town / known place
local function streetPhrase(name)
  -- "auf der Ahauser Straße", "auf dem Nordring", "auf der Straße „Zum Ehrenmal“", "auf der B 70"
  local first = name:match('^(%S+)%s')
  local PREP = { Am = 1, An = 1, Im = 1, In = 1, Zum = 1, Zur = 1, Auf = 1, Hinter = 1, Unter = 1, Vor = 1, Bei = 1,
    ['Über'] = 1, Op = 1, De = 1, Het = 1 }
  if first and PREP[first] then return 'auf der Straße „' .. name .. '“' end
  local base = name:gsub('%s*%b()%s*$', ''):lower()
  for _, ending in ipairs({ 'weg', 'ring', 'damm', 'platz', 'pfad', 'markt', 'steig', 'wall', 'graben', 'deich', 'kamp', 'esch' }) do
    if base:sub(-#ending) == ending then return 'auf dem ' .. name end
  end
  return 'auf der ' .. name
end

local function placeOf(lat, lon)
  if not lat then return nil end
  local lim = R.limit
  -- the street and the place from OpenStreetMap (shipped: fernfahrer/streets), else the kind of road
  local okS, street = pcall(streets.nameAt, lat, lon)
  local okP, pl = pcall(streets.placeAt, lat, lon)
  street = okS and street or nil
  pl = okP and pl or nil
  local kind = (not lim or lim >= 110) and 'Autobahn' or (lim >= 70 and 'Landstraße' or 'innerorts')
  if street then
    local road = streetPhrase(street) .. string.format(' (%s%s)', kind, (lim and lim < 110) and string.format(', Tempo %d', lim) or '')
    local near
    if pl then near = pl.inside and ('in ' .. pl.name) or string.format('bei %s (%s km)', pl.name, (string.format('%.1f', pl.dist / 1000):gsub('%.', ','))) end
    return { road = road, near = near, street = street, town = pl and pl.name or nil }
  end
  local road = (not lim or lim >= 110) and 'der Autobahn' or (lim >= 70 and 'der Landstraße' or 'einer Straße innerorts')
  if lim and lim < 110 then road = road .. string.format(' (Tempo %d)', lim) end
  if pl then return { road = 'auf ' .. road, near = pl.inside and ('in ' .. pl.name) or ('bei ' .. pl.name), town = pl.name } end
  local near, best
  for _, d in ipairs(S.depots) do
    local dd = haversine(lat, lon, d.lat, d.lon)
    if dd < 1500 and (not best or dd < best) then near, best = 'Höhe ' .. d.name, dd end
  end
  local city, cb
  for _, c in ipairs(citiesData.LIST or {}) do
    local dd = haversine(lat, lon, c[2], c[3])
    if not cb or dd < cb then city, cb = c[1], dd end
  end
  if city and cb < 60000 then
    local cityText = cb < 8000 and city or string.format('%s (%d km entfernt)', city, math.floor(cb / 1000))
    near = near and (near .. ', ' .. cityText) or cityText
  end
  return { road = 'auf ' .. road, near = near and ('bei ' .. near) or nil }
end

local trafficCtx = {
  playerVeh = function() return playerVeh() end,
  trailerId = function() return R.trailerId end,
  roadLimit = function() return R.limit end,
  ruleLimit = function() return R.limitEff or R.limit end,
  night = function() local h = clockHours(); return h < 6.5 or h >= 20 end,
  zones = function()
    local out = {}
    for _, z in ipairs(roadEvents.zones() or {}) do out[#out + 1] = z end
    for _, z in ipairs(accidents.zones() or {}) do out[#out + 1] = z end
    return out
  end,
  protect = function(id) roadEvents.protect(id) end,
  enabled = function() return S.settings.smartTraffic ~= false and S.settings.traffic ~= 'off' end,
}

local accidentCtx = {
  -- (camera.lua: the dashcam's clip and the scene photos for the report)
  -- (the photos' exposure: by day darker – from the cab the main view was opened up for the dark cab; dawn and dusk in
  -- between; at night as the main view, 2026-11-07)
  photos = function(id, pos, dir)
    local cm = L.camMod()
    local h = clockHours()
    local day = (h >= 8 and h <= 18) and 1 or ((h >= 6.5 and h < 8) and (h - 6.5) / 1.5 or ((h > 18 and h <= 20) and (20 - h) / 2 or 0))
    local v = playerVeh()
    local inCab = v and L.camInCab(v) or false
    cm.exposureScale = 1 - day * (inCab and 0.6 or 0.4)
    return cm.photos(id, pos, dir)
  end,
  playerVeh = function() return playerVeh() end,
  damageOf = function(id) return damageOf(id) end,
  speedKmh = function() local v = playerVeh(); return v and vehSpeed(v) * 3.6 or 0 end,
  roadLimit = function() return R.limit end,
  ruleLimit = function() return R.limitEff or R.limit end,
  night = function() local h = clockHours(); return h < 6.5 or h >= 20 end,
  here = function() return here() end,
  placeOf = placeOf,
  trailerId = function() return R.trailerId end,
  clockText = function() return clockText() end,
  addDocument = addDocument,
  fine = function(a, r) M.fine(a, r) end,
  notify = function(t, ttl) notify(t, ttl) end,
  message = function(t, from) message(t, from) end,
  protect = function(id) roadEvents.protect(id) end,
  busy = function() return R.trip ~= nil or R.pendingTeleport ~= nil end,
  impairment = function() return vices.readings() end,
  vehicleName = function() local d = activeDef(); return (d.brand or '') .. ' ' .. (d.modelName or '') end,
  onReport = function(doc) service.onReport(doc) end,
}
service.attach({
  onFail = function() pcall(L.moodSting, 'panne') end,
  S = function() return S end, actx = accidentCtx,
  notify = function(t, ttl) notify(t, ttl) end, message = function(t, from) message(t, from) end,
  pay = function(c, a, l) L.pay(c, a, l) end, save = function() save() end,
  money = function() return S.money end, moneyText = function(v) return money(v) end,
  truck = function() return careerVeh() end, speed = function(v) return vehSpeed(v) end,
  def = function() return activeDef() end, loaner = function() return loanerActive() end,
  repair = function(f, l, a) L.serviceRepair(f, l, a) end,
  inv = function() return L.inv() end, invMax = function(k) return L.INV_MAX[k] or 6 end,
  canFail = function() return R.mode and not R.boot and not R.trip and not R.sleep and not R.officeOpen and not R.stopOpen and R.pendingTeleport == nil end,
})
function M.onEngineTemp(w, o) service.onTemp(w, o) end
function M.clubAct(id, arg) service.act(id, arg) end

-- the company yard's buildings (yard.lua)
local yardCtx = {
  save = function() return S end,
  homeWorld = function()
    local a = earthAnchor()
    if not a or not S or not S.home then return nil end
    local x, y = a:geodeticToWorld(S.home.lat, S.home.lon, 0)
    return vec3(x, y, 0)
  end,
  playerPos = function() local v = playerVeh(); return v and vehPos(v) or nil end,
  anchor = function() return earthAnchor() end,
  anchorId = function()
    local c = earthCore()
    local st = c and c._state and c._state()
    return st and st.anchorId or nil
  end,
  -- (2026-11-07: the world quiet for YARD_CALM_S first – in Bremen the search ran before the houses were in, found
  -- "free" ground and gave up / built into them)
  loading = function()
    -- (only the ground and the houses matter here: Earth's tree and far tiles kept trickling in for minutes in the log
    -- of 2026-11-07 and the yard was never searched)
    local w = earthLoading()
    if (w and (w.ground or w.buildings)) or R.trip ~= nil or R.pendingTeleport ~= nil then R.yardCalm = nil; return true end
    R.yardCalm = R.yardCalm or now()
    return now() - R.yardCalm < 6
  end,
  night = function() local h = clockHours(); return h < 6.5 or h >= 20 end,
  found = function()
    notify('🏗️ Dein Firmenhof steht: Halle für den LKW, Büro, Stellplätze.', 8)
    message('Der Hof ist fertig! Die Halle ist groß genug für die Zugmaschine mit Auflieger – einfach durchs Tor und rein. Das Büro ist gleich daneben.')
    save()
  end,
}

-- the stop rings (stops.lua)
local stopsCtx = {
  near = function() return R.near end,
  playerPos = function() local v = playerVeh(); return v and vehPos(v) or nil end,
  playerDir = function() local v = playerVeh(); return v and vec3(v:getDirectionVector()) or nil end,
  anchor = function() return earthAnchor() end,
  yardSpot = function() return yard.officeSpot() end,
}

------------------------------------------------------------------------------------------
-- UI data

local function nearView()
  local n = R.near
  if not n then return nil end
  local v = { id = n.id, type = n.type, name = n.name, icon = n.icon, typeName = n.typeName, action = n.action, dist = n.dist }
  if n.action == 'repair' or n.action == 'home' then
    local veh = playerVeh()
    v.repairCost = veh and L.repairPay(veh) or nil
  end
  v.freeChange = atHub()
  return v
end

local function hudPayload()
  if not R.mode then return { mode = false } end
  local job = S.job
  local veh = playerVeh()
  local def, loaner = activeDef()
  local h = {
    mode = true, company = S.company and S.company.name, money = S.money, level = S.level, xp = S.xp,
    xpFrom = xpFor(S.level), xpTo = xpFor(S.level + 1), loan = S.loan,
    truckOk = careerVeh() ~= nil, inTruck = R.truckId ~= nil and be:getPlayerVehicleID(0) == R.truckId,
    activeKind = def.kind or 'truck', vehicleName = (def.brand or '') .. ' ' .. (def.modelName or ''), loaner = loaner,
    limit = R.limit, speedWarn = S.settings.speedWarn, near = nearView(), fuel = R.fuel, navName = R.navName,
    discovering = R.discover and R.discover.running and { done = R.discover.done, total = R.discover.total,
      paused = R.discover.paused, label = R.discover.label } or nil,
  }
  h.speed = veh and vehSpeed(veh) * 3.6 or 0
  h.damage = veh and clamp(damageOf(veh:getID()) / C.TRUCK_DMG_FULL, 0, 1) or 0
  -- road events: the roadworks' limit replaces the road's while inside; the warning sign; a camera flash
  h.roadLimit = R.limit
  -- (the truck's own limit where it is lower than the sign: 80 on the motorway, 60 on country roads)
  local eff = R.limitEff or R.limit
  local ov = roadEvents.limitOverride()
  h.limit = ov and math.min(ov, eff or ov) or eff
  h.truckRule = eff and R.limit and eff < R.limit or nil
  -- the minimap
  h.player = here()
  if veh then
    local dv = vec3(veh:getDirectionVector())
    h.heading = math.deg(math.atan2(dv.x, dv.y))     -- (BeamNG.Earth's frame: +y is north near the anchor)
  end
  h.clock = clockText()
  h.night = (function() local hh = clockHours(); return hh < 6 or hh >= 21 end)() or nil
  h.drive = R.drive
  h.nav = R.nav and { dir = R.nav.dir, text = R.nav.text, dist = R.nav.dist, sayId = R.nav.sayId, stage = R.nav.stage } or nil
  h.navSound = S.settings.navSound ~= false
  h.vices = vices.hud()
  h.inv = L.inv()                                          -- (what is in the cab: the cabin app's counts)
  h.assist = L.assistView()                                 -- (the cruise control app's switches)
  h.accBusy = R.accBusy
  h.photoSet, h.photoRun = S.settings.photoSeries and true or nil, L.shots.active() or nil
  if R.viewHint then h.viewHint = { id = R.viewHint.id, name = R.viewHint.name, km = R.viewHint.km, where = R.viewHint.where, canGo = S.job == nil or nil } end
  do local okS, sv = pcall(service.hud); if okS and sv then h.breakdown, h.service = sv.breakdown, sv.service end end
  do local ph = L.pursuit.hud(); if ph then h.service = ph end end
  do local okG, g = pcall(function() return L.acc.hudGadgets(L.accTruck()) end); h.gadgets = okG and g or nil end
  h.fatigue = L.fatigueView()                           -- (tiredness: the tachograph app)
  h.stop = stops.hud()
  h.radio = { on = S.settings.radioOn ~= false, vol = S.settings.radioVol or 0.7, helper = R.radioHelper or false,
    music = (R.radioLevel or 0) > 0.002 or nil, src = S.settings.radioSrc or 'radio', videoOn = L.videoActive() ~= nil or nil,
    station = (select(2, L.radioStation()) or {})[1], info = R.radioInfo,
    eq = { b = S.settings.radioEqB or 0, m = S.settings.radioEqM or 0, t = S.settings.radioEqT or 0 },
    favs = type(S.settings.radioFavs) == 'table' and #S.settings.radioFavs or 0 }
  h.where = R.where and { code = R.where.code, state = R.where.state, country = R.where.country, town = R.townIn, street = R.streetIn } or nil
  h.accident = accidents.hud()
  h.home = S.home and { lat = S.home.lat, lon = S.home.lon } or nil
  h.event = roadEvents.hud(here())
  h.routeWarn = S.settings.routeWarn == true or nil        -- (the route advisor's warner: cameras, roadworks …)
  h.autodrive = L.autodriveOn() or nil                     -- (BeamNG.Earth's autodrive running)
  h.cine = L.cine.active() or nil
  h.flash = roadEvents.flash()
  -- (the slower parts of the HUD are made once a second, the nearest fuel station every 3 s – the HUD goes 4× a
  -- second and both walk long lists: the tachograph's day, all known depots)
  local tNow = now()
  if not R.hudSlowT or tNow - R.hudSlowT > 1 then
    R.hudSlowT = tNow
    R.hudTacho = activeKind() == 'truck' and tacho.view(S.tacho) or nil
  end
  h.tacho = R.hudTacho
  h.privateDrive = S.privateDrive or nil
  h.canRest = canRest() and h.speed < 3 or nil
  if veh then
    local up = vec3(veh:getDirectionVectorUp())
    h.stuck = (up.z < 0.5 or h.damage > 0.5) or nil       -- on its side / badly damaged: roadside help offered
  end
  if S.fines[1] and os.time() - S.fines[1].t < 10 then h.lastFine = S.fines[1] end
  if R.fuel and R.fuel.per100 then h.range = R.fuel.amount / R.fuel.per100 * 100 * 1000 end
  if not R.hudFuelT or tNow - R.hudFuelT > 3 then
    R.hudFuelT = tNow
    local nf, nfd = nearestOf('fuel')
    R.hudFuel = nf and { name = nf.name, dist = nfd } or nil
  end
  h.nextFuel = R.hudFuel
  local st = gpsStatus()
  if st then h.gps = { remaining = st.remaining, eta = st.eta, name = st.name, routeError = st.routeError } end
  if R.toast and now() < R.toast.until_ then h.toast = { from = R.toast.from, text = R.toast.text, id = R.toast.id } end
  if job then
    local target = (job.phase == 'toPickup' or job.phase == 'atPickup') and job.from or job.to
    local remaining, eta = dist(here(), target), nil
    if st and st.remaining and R.navName and R.navName:find(tostring(target.name), 1, true) then remaining, eta = st.remaining, st.eta end
    if not eta and remaining then eta = remaining / 16 end
    h.job = {
      phase = job.phase, text = L.phaseText(job), cargoName = job.cargoName, icon = job.icon, tons = job.tons,
      fragile = job.fragile, from = job.from.name, to = job.to.name, target = target.name, dist = remaining, eta = eta,
      timeLeft = job.deadline - job.elapsed, pay = job.loaner and round(job.freight * C.COMPANY_SHARE) or job.freight,
      cond = cargoCondition(), coupled = isCoupled(), hasTrailer = R.trailerId ~= nil,
      unload = job.phase == 'unloading' and clamp(R.unloadT / C.UNLOAD_S, 0, 1) or nil,
      manualHitch = R.hitchStep == 'manual', routeError = job.routeError,
      hit = R.cargoHit and now() < R.cargoHit.t or nil,
      spot = (R.pickupSpot and 'pickup') or (R.dropSpot and 'drop') or nil,
      targetPos = { lat = target.lat, lon = target.lon },
    }
    -- the trailer's distance while going to it / the drop spot's while delivering
    local tv, cv = vehById(R.trailerId), careerVeh()
    if job.phase == 'toTrailer' and tv and cv then h.job.trailerDist = vehPos(cv):distance(vehPos(tv)) end
    if R.dropSpot and tv then h.job.spotDist = vehPos(tv):distance(R.dropSpot.pos) end
    h.job.needSecure = L.needsSecure() or nil
    h.job.adr, h.job.papers, h.job.smuggle = job.adr, job.papers, job.smuggle
    if job.adr and not job.papers then
      local pd = L.papersAway()
      h.job.papersAway = pd and math.floor(pd) or nil
      h.job.papersHere = (pd and pd <= L.PAPERS_M) or nil
      if h.job.papersHere and not job.papersSaid then
        job.papersSaid = true
        notify('📄 Hier liegen die ADR-Papiere. Jetzt einpacken – unterwegs geht das nicht mehr.', 8)
      end
    end
  else
    h.homeDist = dist(here(), S.home)
  end
  return h
end

-- the office and setup screens (polled; catalogs come separately: uiCatalog)
function M.uiState(withPlaces, withLedger)
  if not S then return nil end
  local def, loaner = activeDef()
  -- (the places only when the page shows them: thousands of them, polled every second)
  local places = nil
  -- (2026-11-07: with the wide network thousands – sent when the office opens (withPlaces nil) and when they changed,
  -- else the page keeps what it has)
  if withPlaces ~= false then
    local sig = #S.depots + (parked.fuelCount or 0) * 100000
    if withPlaces == nil or sig ~= R.placesSig or now() - (R.placesSentAt or 0) > 30 then
      places = {}
      for _, d in ipairs(S.depots) do table.insert(places, placeView(d)) end
      pcall(L.farAdd, places)
      -- (2026-11-09: the fuel stations Earth itself builds, unless one of ours stands within about 150 m)
      local cell, grid = 0.002, {}
      for _, d in ipairs(S.depots) do if d.type == 'fuel' then grid[math.floor(d.lat / cell) .. ':' .. math.floor(d.lon / (cell * 1.6))] = true end end
      local tf = DEPOT_BY_KEY.fuel
      for fid, f in pairs(parked.fuelAll()) do
        local cx, cy, known = math.floor(f.lat / cell), math.floor(f.lon / (cell * 1.6)), false
        for dx = -1, 1 do for dy = -1, 1 do if grid[(cx + dx) .. ':' .. (cy + dy)] then known = true end end end
        if not known then
          places[#places + 1] = { id = 'earthfuel:' .. tostring(fid), name = L.neutralName('fuel', f.name, nil, f.lat, f.lon), detail = 'aus BeamNG.Earth', lat = f.lat, lon = f.lon,
            type = 'fuel', typeName = tf and tf.name or 'Tankstelle', icon = tf and tf.icon or '⛽', facility = true }
        end
      end
      R.placesSig, R.placesSentAt = sig, now()
    end
  end
  local c = earthCore()
  local st = c and c._state and c._state() or nil
  local cargoList, typeList = {}, {}
  for _, cg in ipairs(CARGO) do
    if not cg.special then table.insert(cargoList, { key = cg.key, name = cg.name, icon = cg.icon, enabled = cg.enabled ~= false, adr = cg.adr }) end
  end
  -- (the counts in one pass: per type over all depots it was ~20 walks of thousands, every second the office polls)
  local counts = {}
  for _, d in ipairs(S.depots) do counts[d.type] = (counts[d.type] or 0) + 1 end
  for _, t in ipairs(DEPOT_TYPES) do
    table.insert(typeList, { key = t.key, name = t.name, icon = t.icon, facility = t.facility or false, count = counts[t.key] or 0 })
  end
  local tab = R.officeTab
  R.officeTab = nil
  local offers, t = {}, now()
  for _, o in ipairs(R.offers) do
    local v = {}
    for k, x in pairs(o) do v[k] = x end
    v.expiresIn = o.expires and math.max(0, o.expires - t) or nil
    offers[#offers + 1] = v
  end
  return {
    mode = R.mode, inEarth = inEarth(), connected = st ~= nil and st.player ~= nil, player = here(),
    company = S.company, home = S.home, places = places, types = L.withUg(typeList), discover = R.discover,
    money = S.money, level = S.level, xp = S.xp, xpTo = xpFor(S.level + 1), loan = S.loan, loanLimit = loanLimit(),
    yardUp = L.yardUpView(),
    loanRate = C.LOAN_RATE, companyShare = C.COMPANY_SHARE, fuelPrices = { diesel = FUEL.diesel.price, gasoline = FUEL.gasoline.price },
    offers = offers, job = S.job and hudPayload().job or nil,
    owned = S.owned, active = S.active, activeDef = def, loaner = loaner, europe = inEurope(), vehOk = careerVeh() ~= nil,
    near = R.mode and nearView() or nil, transferFee = R.mode and transferFee() or 0, atHome = R.mode and atHome() or false,
    stats = S.stats, log = S.log, settings = S.settings, report = R.report, cargo = cargoList,
    traffic = R.traffic, fps = R.fpsAvg and round(R.fpsAvg) or nil, canHire = next(S.yardUp or {}) ~= nil or nil,
    weather = (function() local w = rawget(_G, 'beamngEarth_weather'); local ok, l = pcall(function() return w and w.statusLine and w.statusLine() end); return ok and l or nil end)(),
    agentTool = rawget(_G, 'core_agentTrafficTool') ~= nil, catalogLoading = R.catalogTask ~= nil,
    openTab = tab, fines = S.fines, tacho = tacho.view(S.tacho), canRest = R.mode and canRest() or false,
    clock = clockText(), travel = R.mode and travelView() or nil, rental = S.active == 'rental' or nil,
    documents = S.documents or {},
    statsView = (function() local ok, v = pcall(L.statsView); return ok and v or nil end)(),
    clubView = (function() local ok, v = pcall(service.view); return ok and v or nil end)(),
    route = L.routeView(),
    -- (the Zentrale's tiles: the day, the vehicle's state)
    weekday = weekday(), yard = yard.built() or nil, day = S.dayNo or 1,
    -- (the Finanzen page: the books – only when it is open)
    ledger = withLedger and (S.ledger or {}) or nil,
    rating = (function()
      local n, sum = 0, 0
      for _, d in ipairs(S.documents or {}) do if d.kind == 'delivery' and d.rating then n, sum = n + 1, sum + d.rating end end
      return n > 0 and { avg = sum / n, n = n } or nil
    end)(),
    damage = careerVeh() and clamp(damageOf(R.truckId) / C.TRUCK_DMG_FULL, 0, 1) or nil,
  }
end

-- the dealers' stock: 'truck' (tractors) or 'car' (models with their configs)
function M.uiCatalog(kind)
  ensureCatalog()
  if kind == 'car' then return R.cars or {} end
  if kind == 'truckUsed' then return R.near and R.near.action == 'dealerTruck' and usedStock(R.near.id) or {} end
  return R.trucks or {}
end

function M.uiOfficeReady()
  local c0 = os.clock()
  ensureCatalog()
  if #R.offers == 0 then topUpOffers() end
  local c1 = os.clock()
  local st = M.uiState()
  local c2 = os.clock()
  -- (the office's opening in the log when it is slow: a 300 ms hitch came with it, 2026-11-07)
  if c2 - c0 > 0.05 then
    log('I', logTag, string.format('office open: %.0f ms (offers %.0f, state %.0f, %d places)', (c2 - c0) * 1000,
      (c1 - c0) * 1000, (c2 - c1) * 1000, S and #S.depots or 0))
  end
  return st
end

------------------------------------------------------------------------------------------
-- hooks

function M.onExtensionLoaded()
  pcall(L.layoutAdd)
  math.randomseed(os.time())
  -- the single save of older versions becomes the first career slot
  if FS:fileExists(LEGACY_SAVE) and #FS:findFiles(SLOT_DIR, '*.json', 0, false, false) == 0 then
    local d = jsonReadFile(LEGACY_SAVE)
    if type(d) == 'table' then
      jsonWriteFile(slotPath('karriere_1'), d, true)
      FS:removeFile(LEGACY_SAVE)
      log('I', logTag, 'old save moved to career slot karriere_1')
    end
  end
  log('I', logTag, 'Trucks of Earth geladen')
end

function M.onClientPostStartMission(levelPath)
  local earth = type(levelPath) == 'string' and levelPath:find('/' .. EARTH_LEVEL .. '/', 1, true) ~= nil
  if R.modeRequested and earth then
    R.mode = true
    R.boot = now()
    R.welcomeDone, R.welcomeCalm = nil, nil
    pcall(L.welcomeHold)
    parked.anchor = function() return earthAnchor() end
    pcall(parked.install)                         -- (before Earth's first road tiles: their kerbside spots are sorted)
    parked.enabled = true
    -- the careers screen ("Weiterspielen") stayed open over the world (2026-11-03): the loading screen instead, on
    -- until the start (the yard or the last position) is reached and loaded; a new career gets its setup screen
    if S and S.company and S.home then
      local r = S.resume
      R.tripView = { mode = 'road', world = true, from = S.company.name,
        to = r and r.lat and 'Weiterfahrt' or (S.home.name or 'Firmenhof') }
      R.worldLoad = true
      R.tripArrivedAt = nil
      R.tripNext = nil
      navigate('fernfahrerTravel')
    else
      -- (2026-11-05: a new career too – the loading screen until the world stands, then the setup screen; the world
      -- popped up half-built behind the setup before)
      R.tripView = { mode = 'road', world = true, from = 'Neue Karriere', to = 'Deine Spedition' }
      R.worldLoad = true
      R.tripArrivedAt = nil
      R.tripNext = 'fernfahrerSetup'
      navigate('fernfahrerTravel')
    end
  elseif not earth then
    R.mode = false
  end
  R.modeRequested = false
  R.vicesFor = nil              -- (a new level: the camera hook of vices.lua installed again, the last one went)
  R.offers, R.truckId, R.trailerId, R.traffic = {}, nil, nil, nil
  if S and S.job and S.job.phase ~= 'toPickup' then S.job.phase = 'needTrailer' end
  spots.hide()
  R.pickupSpot, R.dropSpot, R.spotTry = nil, nil, nil
end

function M.onClientEndMission()
  pcall(L.cineStop)
  if R.mode then save(); stopClock() end
  pcall(roadEvents.reset)
  pcall(accidents.reset)
  pcall(trafficAI.reset)
  pcall(pool.reset)
  pcall(vices.reset)
  pcall(yard.reset)
  pcall(stops.reset)
  pcall(cinematic.reset)
  vices.override = nil
  pcall(L.radioWrite, 'normal', 0)               -- (out of the career: the music as it comes)
  if L.mirrors then pcall(L.mirrors.destroy); pcall(L.mirrors.forget) end
  if L.cam then pcall(L.cam.reset) end
  pcall(L.slowmoOff)
  pcall(L.removeEarthPins); R.pinsOn = nil
  pcall(L.videoScreenOff)
  priority.enabled = false                  -- (free roam on Earth: the graph as Earth sends it)
  R.mode = false
  restoreSettings()
end

-- the cab's scene (vices.lua) at the camera of this frame
function M.onPreRender(dt)
  if R.mode and S and L.acc and R.accFor == S then
    R.accDt = dt
    vices.camHook = L.accCamHook
    local okA, errA = true, nil
    if now() - (R.accHookT or 0) > 0.25 then okA, errA = pcall(L.acc.render, careerVeh(), L.accTruck(), dt) end
    if not okA then log('E', logTag, 'accessories: ' .. tostring(errA)); pcall(L.acc.reset) end
  end
  if R.mode and vices.busy() then
    local ok, err = pcall(vices.render, dt)
    if not ok then log('E', logTag, 'cab scene: ' .. tostring(err)); pcall(vices.reset) end
  end
end

-- the HUD's buttons (FernfahrerKabine): a beer, a cigarette, a joint
-- (2026-11-07) what the driver has with him: beer, cigarettes, joints – counted, bought on the way (the fuel
-- station's shop in its stop menu; the joints only "round the corner" at some stations, after the dealer's little
-- test, the stop menu's minigame)
L.INV_MAX = { beer = 24, cigarette = 60, joint = 10, coffee = 6, energy = 6 }
L.DRINK_FATIGUE = { coffee = 0.2, energy = 0.12 }   -- (what a cup / a can takes off the tiredness, in the cab)
L.INV_NAME = { beer = 'Bier', cigarette = 'Zigaretten', joint = 'Joints', coffee = 'Kaffee', energy = 'Energydrinks' }
L.SHOP = {
  { id = 'beer1', kind = 'beer', n = 1, price = 1.29, icon = '🍺', label = 'Dose Bier', sub = '0,33 l, gekühlt' },
  { id = 'beer6', kind = 'beer', n = 6, price = 6.99, icon = '🍻', label = 'Sixpack Bier', sub = '6 × 0,33 l' },
  { id = 'cig20', kind = 'cigarette', n = 20, price = 9.50, icon = '🚬', label = 'Schachtel Zigaretten', sub = '20 Stück' },
  { id = 'joint1', kind = 'joint', n = 1, price = 10, icon = '🌿', label = 'Ein Joint', sub = 'fertig gedreht', back = true },
  { id = 'joint3', kind = 'joint', n = 3, price = 27, icon = '🌿', label = 'Drei Joints', sub = 'Mengenrabatt', back = true },
  -- (against tiredness: into the cab, drunk from the HUD's cab app when wanted, 2026-11-08)
  { id = 'coffee', kind = 'coffee', n = 1, price = 2.90, icon = '☕', label = 'Kaffee to go', sub = 'Macht wach · Müdigkeit −20 %' },
  { id = 'energy', kind = 'energy', n = 1, price = 2.29, icon = '🥤', label = 'Energydrink', sub = 'Kurz wach · Müdigkeit −12 %' },
}
L.BACK_SHARE = 0.6             -- (the share of fuel stations with someone at the back; 0.4 was too rare, 2026-11-07)
L.BACK_OPEN_S, L.BACK_GONE_S = 600, 1800
function L.inv()
  if not S then return {} end
  if type(S.inv) ~= 'table' then S.inv = { beer = 2, cigarette = 10, joint = 0 } end    -- (a start: what was in the cab)
  return S.inv
end
-- a station with a back door: fixed per station (its id), so it is always the same ones
function L.backAt(p)
  if not p then return false end
  local s, h = tostring(p.id or p.name or ''), 7
  for i = 1, #s do h = (h * 31 + s:byte(i)) % 1000003 end
  return (h % 1000) / 1000 < L.BACK_SHARE
end
function L.backKey(p) return tostring(p and (p.id or p.name) or '') end
function L.shopView(p)
  local inv = L.inv()
  local key, t = L.backKey(p), now()
  R.backOpen, R.backGone = R.backOpen or {}, R.backGone or {}
  local open = R.backOpen[key] and t < R.backOpen[key] or false
  local items = {}
  for _, it in ipairs(L.SHOP) do
    if not it.back or open then
      local full = it.kind and (inv[it.kind] or 0) + it.n > (L.INV_MAX[it.kind] or 99) or false
      items[#items + 1] = { id = it.id, icon = it.icon, label = it.label, sub = it.sub, price = it.price, back = it.back or nil,
        priceText = money(it.price), have = it.kind and (inv[it.kind] or 0) or nil, kind = it.kind,
        disabled = (S.money < it.price or full) or nil, why = full and 'Mehr passt nicht in die Kabine' or nil }
    end
  end
  local back = nil
  if L.backAt(p) then
    back = { open = open or nil, gone = (R.backGone[key] and t < R.backGone[key]) or nil }
  end
  return { items = items, inv = inv, back = back }
end
function L.shopBuy(p, id)
  local it
  for _, x in ipairs(L.SHOP) do if x.id == id then it = x end end
  if not it then return end
  local inv = L.inv()
  if it.back then
    local key = L.backKey(p)
    if not (R.backOpen and R.backOpen[key] and now() < R.backOpen[key]) then notify('Hier verkauft dir keiner sowas.', 4); return end
  end
  if S.money < it.price then notify('Nicht genug Geld.', 4); return end
  if (inv[it.kind] or 0) + it.n > (L.INV_MAX[it.kind] or 99) then notify('Mehr passt nicht in die Kabine.', 4); return end
  L.pay('Einkauf', -it.price, it.label .. (it.back and ' (Hinterausgang)' or ' (Tankstelle)'))
  inv[it.kind] = (inv[it.kind] or 0) + it.n
  notify(string.format('%s %s gekauft – %d %s in der Kabine.', it.icon, it.label, inv[it.kind], L.INV_NAME[it.kind]), 4)
  save()
end
-- the minigame's end (FernfahrerStop.vue): passed – the back door open for a while; failed – he is gone for a while
function L.backResult(p, ok)
  if not L.backAt(p) then return end
  local key = L.backKey(p)
  R.backOpen, R.backGone = R.backOpen or {}, R.backGone or {}
  if R.backGone[key] and now() < R.backGone[key] then return end
  if ok then
    R.backOpen[key] = now() + L.BACK_OPEN_S
    notify('🌿 „Passt. Was brauchst du?“ – hinter der Tankstelle gibt es jetzt mehr.', 6)
  else
    R.backGone[key] = now() + L.BACK_GONE_S
    notify('Der Typ am Hinterausgang ist misstrauisch geworden und verschwunden.', 6)
  end
end

-- (2026-11-07) the milk round: at a dairy the company's milk collection truck (a Percheron with its own tank) is
-- lent out; it goes round the farms in the villages around – stop at each, the milk is pumped over – and back to the
-- dairy, where it is unloaded and paid. Then one's own vehicle again. S.tour = { dairy, stops, i, liters, prevActive }.
L.MILK_TRUCK = { kind = 'truck', model = 'percheron', config = 'vehicles/percheron/s410_6x2_tag_tankerMilk_A.pc', brand = 'Cherrier',
  modelName = 'Percheron', configName = 'Milchsammelwagen (Molkerei)', price = 0, rental = true, eu = true }
L.MILK_STOPS, L.MILK_CAP, L.PUMP_S, L.MILK_KM = 4, 20000, 18, 9.5    -- (never farther than 10 km from the dairy, 2026-11-08)
function L.villagesNear(c, minKm, maxKm, n)
  local cands = {}
  -- (the agricultural traders within reach first: real places on proper roads)
  for _, d in ipairs(L.depotsOf({ 'farm' })) do
    local dd = haversine(c.lat, c.lon, d.lat, d.lon)
    if dd >= minKm * 1000 and dd <= maxKm * 1000 then
      cands[#cands + 1] = { name = tostring(d.detail or d.name):gsub('^Landhandel ', ''), lat = d.lat, lon = d.lon, k = math.random() - 1 }
    end
  end
  local dLat = maxKm / 111
  local dLon = maxKm / (111 * math.max(0.2, math.cos(math.rad(c.lat))))
  for la = math.floor(c.lat - dLat), math.floor(c.lat + dLat) do
    for lo = math.floor(c.lon - dLon), math.floor(c.lon + dLon) do
      local tile = jsonReadFile(string.format('/fernfahrer/towns/%d_%d.json', la, lo))
      for _, s in ipairs(type(tile) == 'table' and tile.list or {}) do
        local d = haversine(c.lat, c.lon, s[3], s[4])
        if d >= minKm * 1000 and d <= maxKm * 1000 and (s[5] or 0) < 6000 and s[2] ~= 'suburb' then
          cands[#cands + 1] = { name = s[1], lat = s[3], lon = s[4], k = math.random() }
        end
      end
    end
  end
  table.sort(cands, function(a, b) return a.k < b.k end)
  local out = {}
  for _, x in ipairs(cands) do
    local far = true
    for _, q in ipairs(out) do if haversine(q.lat, q.lon, x.lat, x.lon) < 2500 then far = false; break end end
    if far then out[#out + 1] = x end
    if #out >= n then break end
  end
  -- a round: each time the nearest one not yet visited
  local route, from = {}, c
  while #out > 0 do
    local bi, bd
    for i, x in ipairs(out) do local d = haversine(from.lat, from.lon, x.lat, x.lon); if not bd or d < bd then bi, bd = i, d end end
    from = table.remove(out, bi)
    route[#route + 1] = from
  end
  return route
end
function L.tourTarget(T) return T.i <= #T.stops and T.stops[T.i] or T.dairy end
function L.tourNav(T)
  local tg = L.tourTarget(T)
  navTo({ lat = tg.lat, lon = tg.lon }, T.i <= #T.stops and ('Milch holen: ' .. tg.name) or ('Zurück zur ' .. T.dairy.name))
end
function M.milkTour()
  if not S or not R.mode then return end
  local p = stops.inside() or R.near
  if not p or p.type ~= 'dairy' then notify('Die Milchtour startet an einer Molkerei.', 5); return end
  if S.tour then notify('Du bist schon auf Milchtour.', 4); return end
  if S.job or R.trailerId then notify('Erst den laufenden Auftrag beenden.', 5); return end
  if not (core_vehicles.getModel and core_vehicles.getModel(L.MILK_TRUCK.model)) then notify('Der Milchsammelwagen fehlt im Spiel.', 5); return end
  local stopsList = L.villagesNear(p, 1.2, L.MILK_KM, L.MILK_STOPS)
  if #stopsList < 2 then notify('Keine Höfe in der Nähe gefunden.', 5); return end
  local km, from = 0, p
  for _, s in ipairs(stopsList) do
    s.liters = math.random(25, 55) * 100
    s.name = 'Milchhof ' .. s.name
    km = km + haversine(from.lat, from.lon, s.lat, s.lon) / 1000 * 1.3
    from = s
  end
  km = km + haversine(from.lat, from.lon, p.lat, p.lon) / 1000 * 1.3
  S.tour = { dairy = { lat = p.lat, lon = p.lon, name = p.name, id = p.id }, stops = stopsList, i = 1, liters = 0,
    prevActive = S.active, km = round(km, 0.1), t0 = now() }
  S.rental = L.MILK_TRUCK
  S.active = 'rental'
  if playerVeh() then core_vehicles.replaceVehicle(L.MILK_TRUCK.model, { config = L.MILK_TRUCK.config, autoEnterVehicle = true })
  else core_vehicles.spawnNewVehicle(L.MILK_TRUCK.model, { config = L.MILK_TRUCK.config, autoEnterVehicle = true }) end
  R.truckId, R.fuel = nil, nil
  R.pendingAdopt = now() + 0.5
  navigate('play')
  L.tourNav(S.tour)
  message(string.format('Heute fährst du für die %s die Milch ein: %d Höfe, rund %.0f km. An jedem Hof anhalten – die Milch wird umgepumpt. Danach zurück zur Molkerei.',
    p.name, #stopsList, km), 'Mira (Disposition)')
  save()
end
function L.tourEnd(paid)
  local T = S.tour
  if not T then return end
  S.tour = nil
  S.active = T.prevActive or 'loaner'
  S.rental = nil
  local def = activeDef()
  if def and playerVeh() then core_vehicles.replaceVehicle(def.model, { config = def.config, autoEnterVehicle = true }) end
  R.truckId, R.fuel = nil, nil
  R.pendingAdopt = now() + 0.5
  navClear()
  R.tourNavSet = nil
  guihooks.trigger('FernfahrerTutHint', { off = true })
  L.hintOffSoon()
  save()
end
-- the milk round's card at the right of the screen (Szene's hint card): where next, what is in the tank
-- (2026-11-08) the card goes off again for a few seconds: said while a menu is open, the HUD is not there to hear it
function L.hintOffSoon() R.hintOffUntil = now() + 6 end
function L.tourCard(T, t, d)
  if S.tut and not S.tut.done then return end
  local n, total = T.i, #T.stops + 1
  local tg = L.tourTarget(T)
  local title, text
  if T.pumpUntil then
    title = '🥛 Milch wird umgepumpt …'
    text = string.format('<b>%s</b> – noch %d s stehen bleiben.<br>Im Tank: <b>%s l</b> von %s l', tg.name, math.max(0, math.ceil(T.pumpUntil - t)),
      tostring(T.liters), tostring(L.MILK_CAP))
  elseif T.i <= #T.stops then
    title = string.format('Hof %d von %d: %s', T.i, #T.stops, tg.name)
    text = string.format('Noch <b>%.1f km</b>. Fahr in den leuchtenden Kreis und halte an – die Milch wird dann von selbst umgepumpt.<br>Im Tank: <b>%s l</b>', d / 1000, tostring(T.liters))
  else
    title = 'Zurück zur Molkerei'
    text = string.format('Noch <b>%.1f km</b> bis %s. In den Kreis fahren und anhalten – dann wird abgeladen und bezahlt.<br>Im Tank: <b>%s l</b>', d / 1000, tostring(T.dairy.name), tostring(T.liters))
  end
  guihooks.trigger('FernfahrerTutHint', { stage = 'milk' .. tostring(T.i), n = n, total = total, title = title, text = text, ey = 'Milchtour · ' .. n .. '/' .. total,
    btn = 'Milchtour abbrechen', cancel = 'milkTourCancel' })
end
function M.milkTourCancel()
  if not S or not S.tour then return end
  notify('Milchtour abgebrochen – der Sammelwagen bleibt an der Molkerei.', 6)
  L.tourEnd(false)
end
function L.tourTick(t)
  if R.hintOffUntil then
    if t > R.hintOffUntil or (S and S.tut and not S.tut.done) then R.hintOffUntil = nil
    elseif t - (R.hintOffT or 0) > 1 then R.hintOffT = t; guihooks.trigger('FernfahrerTutHint', { off = true }) end
  end
  local T = S and S.tour
  if not T or not R.mode or R.pendingAdopt then return end
  if t - (R.tourT or 0) < 0.5 then return end
  R.tourT = t
  local v = careerVeh()
  local p = here()
  if not v or not p then return end
  if not R.tourNavSet then R.tourNavSet = true; L.tourNav(T) end
  local tg = L.tourTarget(T)
  local d = haversine(p.lat, p.lon, tg.lat, tg.lon)
  local still = vehSpeed(v) < 0.8
  local atFarm = T.i <= #T.stops
  pcall(L.tourCard, T, t, d)
  if T.pumpUntil then
    if not still or d > 80 then
      T.pumpUntil = nil
      notify('Pumpen unterbrochen – wieder anhalten.', 4)
    elseif t >= T.pumpUntil then
      T.pumpUntil = nil
      local l = math.min(tg.liters, L.MILK_CAP - T.liters)
      T.liters = T.liters + l
      T.i = T.i + 1
      notify(string.format('🥛 %s: %s l übernommen – %s l im Tank.', tg.name, tostring(l), tostring(T.liters)), 6)
      if T.liters >= L.MILK_CAP then T.i = #T.stops + 1; notify('Der Tank ist voll – zurück zur Molkerei.', 6) end
      L.tourNav(T)
      save()
    end
    return
  end
  -- (in the ring, the place's glowing circle; without one – no road near that point – close by)
  local ins = stops.inside()
  if ((ins and ins.action == 'tour') or d < 30) and still then
    T.standSince = T.standSince or t
    if t - T.standSince > 3 then
      T.standSince = nil
      if atFarm then
        T.pumpUntil = t + L.PUMP_S
        notify('🥛 Der Schlauch ist dran – die Milch wird umgepumpt … (stehen bleiben)', 6)
      else
        local pay = round(C.BASE_PAY * 0.6 + T.km * C.PAY_PER_KM * 1.1 + 40 * (T.i - 1) + T.liters * 0.004, 10)
        L.pay('Auftrag', pay, 'Milchtour ' .. tostring(T.dairy.name))
        addXp(round(100 + T.km * 10))
        S.stats.jobs = (S.stats.jobs or 0) + 1
        notify(string.format('🥛 Milchtour geschafft: %s l abgeliefert · %s', tostring(T.liters), money(pay)), 8)
        L.tourEnd(true)
      end
    end
  else
    T.standSince = nil
  end
end

-- (2026-11-08) real weather and sky from BeamNG.Earth (clouds, rain, fog, wind at the player – Open-Meteo through its
-- server), with the career's own clock for the time of day. Earth's setting was found on "manual" (it steps back there
-- when anything changes the weather): put back at the start and looked at now and then. Setting "realWeather".
function L.realWeather()
  if not S or S.settings.realWeather == false then return end
  local st = rawget(_G, 'beamngEarth_settings')
  if st and st.get and st.set then
    if st.get('weatherMode') ~= 'real' then
      pcall(st.set, 'weatherMode', 'real')
      log('I', logTag, 'real weather: BeamNG.Earth was on manual – set to real')
    end
    if st.get('clouds') == false then pcall(st.set, 'clouds', true) end
    if S.settings.dayNight ~= false and st.get('skyMode') ~= 'real' then pcall(st.set, 'skyMode', 'real') end
  end
  local w = rawget(_G, 'beamngEarth_weather')
  if w and w.getMode and w.setMode and w.getMode() ~= 'real' then pcall(w.setMode, 'real') end
end
-- (2026-11-09) a check at a rest area: the police wave the truck off to the next one. There the officer stands at the driver's door (on the road
-- he comes to the door on the right); ignored, it costs. The talk itself is the same as on the road (L.cop*).
L.RCHK = { EVERY_KM = { 45, 95 }, FIRST_KM = 20, RETRY_KM = 6, NEAR_M = { 1200, 7000 }, GIVE_UP_S = 480, PAST_M = 1400, STOP_S = 2.5 }
L.RCHK.SHAPE = '/levels/beamng_earth/art/shapes/fernfahrer/props/ff_officer.dae'
function L.restCheckClean()
  local sc = R.rcScene
  R.rcScene = nil
  if not sc then return end
  if sc.officer then pcall(function() local o = scenetree.findObjectById(sc.officer); if o then o:delete() end end) end
  if sc.car then pcall(pool.give, sc.car) end
end
function L.restCheckStage(v, shape)
  local p, d = vehPos(v), vec3(v:getDirectionVector())
  d.z = 0
  d = d:length() > 0.1 and d:normalized() or vec3(0, 1, 0)
  local left = vec3(-d.y, d.x, 0)
  local function onGround(q)
    local top = vec3(q.x, q.y, q.z + 3)
    local hit = castRayStatic(top, vec3(0, 0, -1), 10)
    return (hit and hit < 10) and vec3(q.x, q.y, top.z - hit) or vec3(q.x, q.y, q.z - 1)
  end
  local sc = {}
  local o = createObject('TSStatic')
  if o then
    o:setField('shapeName', 0, shape or L.RCHK.SHAPE)
    o:setField('collisionType', 0, 'None')
    o:setField('decalType', 0, 'None')
    o.canSave = false
    o:registerObject('ff_rest_officer')
    local g = onGround(p + d * 0.6 + left * 2.35)
    local rot = quatFromDir(-left, vec3(0, 0, 1))        -- (looking at the door)
    o:setPosRot(g.x, g.y, g.z, rot.x, rot.y, rot.z, rot.w)
    sc.officer = o:getID()
  end
  local g2 = onGround(p + d * 15 + left * 0.6)
  local id = (not shape) and pool.take('police', g2 + vec3(0, 0, 0.4), -d) or nil
  if id then
    sc.car = id
    local pv = getObjectByID(id)
    if pv then pv:queueLuaCommand('controller.setFreeze(1) electrics.set_lightbar_signal(1)') end
  end
  R.rcScene = sc
end
function L.restCheckTick(t)
  if R.rcScene and not R.cop and not L.enc.active() then L.restCheckClean() end
  if t - (R.rcT or 0) < 1 then return end
  local dtc = t - (R.rcT or t)
  R.rcT = t
  if not S or not R.mode or R.cop or R.trip or R.pendingTeleport or R.sleep or L.enc.active() then return end
  local p, v = here(), careerVeh()
  if not p or not v then return end
  local rc = R.restCheck
  if not rc then
    if not S.job or vehSpeed(v) < 12 then return end
    local km = S.stats.odoKm or 0
    S.rcNextKm = S.rcNextKm or (km + L.RCHK.FIRST_KM)
    if km < S.rcNextKm then return end
    local d = vec3(v:getDirectionVector())
    local best, bestD
    for _, q in ipairs(S.depots) do
      if q.type == 'rest' and math.abs(q.lat - p.lat) < 0.08 and math.abs(q.lon - p.lon) < 0.12 then
        local dd = haversine(p.lat, p.lon, q.lat, q.lon)
        if dd > L.RCHK.NEAR_M[1] and dd < L.RCHK.NEAR_M[2] and (not bestD or dd < bestD) then
          -- (ahead: the bearing against the truck's heading, Earth's x east, y north)
          local ex, ey = (q.lon - p.lon) * math.cos(math.rad(p.lat)), q.lat - p.lat
          local l = math.sqrt(ex * ex + ey * ey)
          if l > 0 and (ex * d.x + ey * d.y) / l / math.max(0.01, math.sqrt(d.x * d.x + d.y * d.y)) > 0.75 then best, bestD = q, dd end
        end
      end
    end
    if not best then S.rcNextKm = km + L.RCHK.RETRY_KM; return end
    S.rcNextKm = km + L.RCHK.EVERY_KM[1] + math.random() * (L.RCHK.EVERY_KM[2] - L.RCHK.EVERY_KM[1])
    R.restCheck = { id = best.id, name = best.name, lat = best.lat, lon = best.lon, t0 = t, best = bestD }
    notify(string.format('🚓 Polizei: Fahren Sie zur Kontrolle auf den %s (%.1f km) und halten Sie dort an!', best.name, bestD / 1000):gsub('%.(%d km)', ',%1'), 12)
    guihooks.trigger('FernfahrerRegion', { kind = 'police', code = 'D', eyebrow = 'Anweisung der Polizei', name = 'Polizeikontrolle', sub = 'Nächster Rastplatz: ' .. best.name })
    return
  end
  local dd = haversine(p.lat, p.lon, rc.lat, rc.lon)
  rc.best = math.min(rc.best, dd)
  if dd > rc.best + L.RCHK.PAST_M or t - rc.t0 > L.RCHK.GIVE_UP_S then
    R.restCheck = nil
    M.fine(180, 'Aufforderung zur Kontrolle auf dem Rastplatz nicht befolgt')
    return
  end
  if R.near and R.near.id == rc.id and stops.inside() and vehSpeed(v) < 1.2 then
    rc.still = (rc.still or 0) + dtc
    if rc.still >= L.RCHK.STOP_S then
      R.restCheck = nil
      pcall(L.restCheckStage, v)
      L.copStart(controlCheck())
    end
  else
    rc.still = 0
  end
end

function L.weatherTick(t)
  if t - (R.weatherT or 0) < 30 then return end
  R.weatherT = t
  L.realWeather()
end

-- (2026-11-08) tiredness: 0 (rested) … 1 (at the end). Awake it grows by the game hours (a full day's 16 h to the
-- top); a break on the tachograph takes it down slowly, sleep for good (8 h: all of it), a coffee a bit at once. Very
-- tired the eyes close for a moment now and then ('FernfahrerBlink', Szene).
L.FATIGUE_AWAKE_H, L.FATIGUE_REST_H = 16, 8
L.FATIGUE_TEXT = { 'Ausgeschlafen', 'Wird langsam müde', 'Müde – bald schlafen', 'Völlig übermüdet!' }
function L.fatigueLevel(f) return f >= 0.9 and 4 or (f >= 0.7 and 3 or (f >= 0.45 and 2 or 1)) end
function L.fatigueRest(hours)
  if not S then return end
  S.fatigue = math.max(0, (S.fatigue or 0) - (tonumber(hours) or 0) / L.FATIGUE_REST_H)
end
function L.fatigueTick(hours)
  if not S or not hours or hours <= 0 then return end
  local resting = S.tacho and S.tacho.act == 'rest' and not S.privateDrive
  if resting then L.fatigueRest(hours) else S.fatigue = math.min(1, (S.fatigue or 0.1) + hours / L.FATIGUE_AWAKE_H * (L.acc.fanOn() and 0.85 or 1)) end
  local f, lv = S.fatigue, L.fatigueLevel(S.fatigue)
  -- (one word when it gets worse: in the messages; only the last stage on the screen)
  if lv > (S.fatigueSaid or 1) then
    S.fatigueSaid = lv
    if lv == 3 then message('Du wirst müde. Mach bald Feierabend – schlafen geht an Rastplatz, Autohof, Tankhof oder am Hof.', 'Mira (Disposition)')
    elseif lv == 4 then notify('😴 Du bist völlig übermüdet – dir fallen die Augen zu. Such dir einen Rastplatz!', 8) end
  elseif lv < (S.fatigueSaid or 1) then S.fatigueSaid = lv end
  -- the eyes
  local t, v = now(), careerVeh()
  if f >= 0.7 and v and vehSpeed(v) > 3 and not R.officeOpen and not R.stopOpen and R.trip == nil then
    if not R.blinkAt then R.blinkAt = t + 20 + math.random() * 40 end
    if t >= R.blinkAt then
      local bad = f >= 0.9
      guihooks.trigger('FernfahrerBlink', { dur = bad and (0.9 + math.random() * 0.8) or (0.25 + math.random() * 0.25) })
      R.blinkAt = t + (bad and (15 + math.random() * 20) or (40 + math.random() * 50))
    end
  else
    R.blinkAt = nil
  end
end
function L.fatigueView()
  local f = (S and S.fatigue) or 0
  local lv = L.fatigueLevel(f)
  return { pct = math.floor(f * 100 + 0.5), level = lv, text = L.FATIGUE_TEXT[lv] }
end

-- (2026-11-08) driver assistance for a truck of one's own (bought in the workshop, switched in the cruise control app):
-- the distance keeper (with the cruise control), the lane keeper (a gentle steering hand), the lane warner (a beep).
L.ASSIST = {
  acc = { name = 'Abstandsregeltempomat', icon = '📡', price = 6800, text = 'hält mit dem Tempomat Abstand zum Vordermann' },
  lka = { name = 'Spurhalteassistent', icon = '🛣', price = 5200, text = 'lenkt sanft zurück in die Spur' },
  ldw = { name = 'Spurverlassenswarner', icon = '🔔', price = 1800, text = 'piept, wenn du die Spur verlässt' },
}
function M.assistToggle(k)
  local own = L.ownTruck()
  if not own or not (own.assist and own.assist[k]) then return end
  own.assistOff = own.assistOff or {}
  own.assistOff[k] = not own.assistOff[k] or nil
  save()
end
function L.assistOn(own, k) return own.assist and own.assist[k] and not (own.assistOff and own.assistOff[k]) end
function L.assistView()
  local own = L.ownTruck and L.ownTruck()
  if not own or not own.assist then return nil end
  local out = {}
  for k, d in pairs(L.ASSIST) do
    if own.assist[k] then out[k] = { on = L.assistOn(own, k) and true or false, icon = d.icon, name = d.name } end
  end
  return out
end
function M.onLaneBeep() guihooks.trigger('FernfahrerSound', { name = 'lane' }) end
function M.onAccState(on) R.accBusy = on and true or nil end
function M.onAccOff() R.accBusy = nil; notify('Tempomat aus: Für die Abstandsautomatik bist du jetzt zu langsam.', 4) end
-- (2026-11-09) the radial menu open at a standstill: the handbrake on, so the truck does not roll off; off again when it closes, if it was us who put it on
function L.autoBrake()
  if not R.mode then return end
  local v = careerVeh() or playerVeh()
  if v then v:queueLuaCommand('if (electrics.values.wheelspeed or 0) < 2.5 and (electrics.values.parkingbrake or 0) < 0.5 then input.event("parkingbrake", 1, 1) obj:queueGameEngineLua("if fernfahrer_career then fernfahrer_career.onRadialBrake() end") end') end
end
function L.autoBrakeOff()
  if not R.radialBrake then return end
  R.radialBrake = nil
  local v = careerVeh() or playerVeh()
  if v then v:queueLuaCommand('input.event("parkingbrake", 0, 1)') end
end
function M.onQuickAccessOpened() L.autoBrake() end
function M.onRadialBrake() R.radialBrake = true end
function M.onHideRadialMenu() if not R.stopOpen then L.autoBrakeOff() end end
function L.assistTick(t)
  if t - (R.assistT or 0) < 0.2 then return end
  R.assistT = t
  local own, v = L.ownTruck(), careerVeh()
  if not own or not v or not own.assist or be:getPlayerVehicleID(0) ~= R.truckId then return end
  local acc, lka, ldw = L.assistOn(own, 'acc'), L.assistOn(own, 'lka'), L.assistOn(own, 'ldw')
  if not (acc or lka or ldw) then return end
  local pos, f = vehPos(v), vec3(v:getDirectionVector())
  f.z = 0
  if f:length() < 0.5 then return end
  f = f:normalized()
  local right = vec3(f.y, -f.x, 0)
  local steer, beep, gap, lead = 0, false, nil, nil
  local lkaRaw = 0
  -- the lane: on the game's road graph
  if (lka or ldw) and map and map.findClosestRoad and map.getMap then
    local front = pos + f * 3
    local ok, n1, n2, dist = pcall(map.findClosestRoad, front)
    local nodes = ok and n1 and n2 and map.getMap().nodes
    local a, b = nodes and nodes[n1], nodes and nodes[n2]
    if a and b and dist and dist < 12 then
      local d = vec3(b.pos.x - a.pos.x, b.pos.y - a.pos.y, 0)
      if d:length() > 0.5 then
        d = d:normalized()
        if d:dot(f) < 0 then d = d * -1 end
        local rr = vec3(d.y, -d.x, 0)
        local off = vec3(front.x - a.pos.x, front.y - a.pos.y, 0):dot(rr)
        local link = a.links and a.links[n2]
        local half = math.max(a.radius or 3, 2)
        local oneWay = link and link.oneWay
        local laneW, target
        if oneWay then
          local lanes = math.max(1, math.floor(2 * half / 3.4 + 0.5))
          laneW = 2 * half / lanes
          target = -half + laneW * (math.floor((off + half) / laneW) + 0.5)
        else
          laneW, target = half, half / 2
        end
        local err = target - off
        if math.abs(err) < 3 then
          if ldw and math.abs(err) > math.max(0.7, laneW / 2 - 0.7) then beep = true end
          if lka then
            local e2 = math.abs(err) > 0.35 and (err - 0.35 * (err > 0 and 1 or -1)) or 0
            lkaRaw = math.max(-0.05, math.min(0.05, e2 * 0.03 - f:dot(rr) * 0.35))
          end
        end
      end
    end
  end
  -- (2026-11-09: from one bit of road to the next the numbers jump; what goes to the steering is their smooth course)
  R.lkaS = (R.lkaS or 0) + (lkaRaw - (R.lkaS or 0)) * 0.25
  if lka then steer = R.lkaS end
  -- the distance: whatever is ahead in the lane
  if acc then
    local objs = map and map.getTrackedObjects and map.getTrackedObjects() or {}
    for id, o in pairs(objs) do
      if id ~= R.truckId and id ~= R.trailerId and o.pos then
        local rel = vec3(o.pos.x - pos.x, o.pos.y - pos.y, 0)
        local along, lat = rel:dot(f), rel:dot(right)
        local ospeed = o.vel and vec3(o.vel):dot(f) or 0
        -- (further ahead, so that it can start early; what comes towards the truck is no one to follow)
        if along > 6 and along < 250 and math.abs(lat) < 1.9 + along * 0.005 and ospeed > -1.5 and (not gap or along < gap) then
          gap, lead = along - 5, ospeed
        end
      end
    end
  end
  v:queueLuaCommand(string.format('if fernfahrer_wear then fernfahrer_wear.assist(%.4f, %s, %s, %s) end', steer, tostring(beep), gap and string.format('%.1f', gap) or 'nil', lead and string.format('%.2f', lead) or 'nil'))
end

-- (2026-11-08) the tint and vignette of being drunk or high: drawn with ImGui, in the game's picture – as a full-window
-- page of the UI, even with pointer-events off, the view could no longer be turned with the mouse
function L.fxDraw()
  local I = vices.intensity and vices.intensity() or 0
  if I < 0.03 or not ui_imgui then return end
  if R.officeOpen or R.stopOpen or R.cop or R.boot ~= nil or R.trip ~= nil then return end
  local im = ui_imgui
  local get = im.GetBackgroundDrawList2 or im.GetForegroundDrawList2
  local vp = im.GetMainViewport()
  local dl = get(vp)
  local x0, y0, w, h = vp.Pos.x, vp.Pos.y, vp.Size.x, vp.Size.y
  local x1, y1 = x0 + w, y0 + h
  local col = function(r, g, b, a) return im.GetColorU322(im.ImVec4(r, g, b, a)) end
  local a = math.min(0.75, I * 0.6) * (0.82 + 0.18 * math.sin(os.clock() * 1.05))
  local dark, clear = col(0, 0, 0, a), col(0, 0, 0, 0)
  local mx, my = w * 0.3, h * 0.3
  im.ImDrawList_AddRectFilledMultiColor(dl, im.ImVec2(x0, y0), im.ImVec2(x0 + mx, y1), dark, clear, clear, dark)
  im.ImDrawList_AddRectFilledMultiColor(dl, im.ImVec2(x1 - mx, y0), im.ImVec2(x1, y1), clear, dark, dark, clear)
  im.ImDrawList_AddRectFilledMultiColor(dl, im.ImVec2(x0, y0), im.ImVec2(x1, y0 + my), dark, dark, clear, clear)
  im.ImDrawList_AddRectFilledMultiColor(dl, im.ImVec2(x0, y1 - my), im.ImVec2(x1, y1), clear, clear, dark, dark)
  local rd = vices.readings()
  local share = math.min(1, (rd.thc or 0) / 10)
  local tint = share > 0.05 and col(0.3, 0.55, 0.12, 0.06 + share * 0.08) or col(0.65, 0.42, 0.12, I * 0.05)
  im.ImDrawList_AddRectFilled(dl, im.ImVec2(x0, y0), im.ImVec2(x1, y1), tint)
end

-- (2026-11-08) a new HUD app in a layout saved before it existed: added once
L.HUD_RIGHT = {
  -- (2026-11-09: tachograph and cab down beside the drive train; the Tempomat's and the drive train's frames follow the driver
  -- assistance bought in the workshop: FernfahrerTempomat / FernfahrerAntrieb app.js)
  -- (2026-11-09: the frames are high enough for anything now and let the mouse through; tachograph and Tempomat stand on the same line, cab and drive train measure what is below them)
  fernfahrerTacho = { bottom = '436px', right = '8px', width = '210px', height = '300px', pe = 'none' },
  fernfahrerKabine = { bottom = '436px', right = '8px', width = '210px', height = '470px', pe = 'none' },
  fernfahrerTempomat = { bottom = '436px', right = '224px', width = '182px', height = '130px', pe = 'none' },
  fernfahrerAntrieb = { bottom = '436px', right = '224px', width = '182px', height = '470px', pe = 'none' },
  fernfahrerRadio = { bottom = '8px', left = '5px', width = '300px', height = '190px' },
  navigation = { bottom = '200px', left = '5px', width = '300px', height = '300px' },
  damageApp = { bottom = '510px', left = '5px', width = '158px', height = '280px' },
  beamngEarthCredits = { bottom = '0px', left = '310px', width = '560px', height = '64px' },
  -- (the game's key hints: their frame takes the mouse, it lay over the cab app)
  inputHints = { top = '120px', right = '420px', width = '450px', height = '500px' },
}
function L.layoutRight()
  local flag = '/settings/fernfahrer/layout_right7.json'
  local f = '/settings/ui_apps/layouts/default/fernfahrer.uilayout.json'
  if FS:fileExists(flag) or not FS:fileExists(f) then return end
  local d = jsonReadFile(f)
  if type(d) ~= 'table' or type(d.apps) ~= 'table' then return end
  for _, x in ipairs(d.apps) do
    local p = L.HUD_RIGHT[x.appName]
    if p then x.placement = { position = 'absolute', top = p.top, bottom = p.bottom, left = p.left, right = p.right, width = p.width, height = p.height, ['pointer-events'] = p.pe } end
  end
  jsonWriteFile(f, d, true)
  jsonWriteFile(flag, { done = true })
end
function L.layoutAdd()
  pcall(L.layoutRight)
  local flag = '/settings/fernfahrer/layout_tempomat.json'
  local f = '/settings/ui_apps/layouts/default/fernfahrer.uilayout.json'
  if FS:fileExists(flag) or not FS:fileExists(f) then return end
  local d = jsonReadFile(f)
  if type(d) ~= 'table' or type(d.apps) ~= 'table' then return end
  for _, x in ipairs(d.apps) do if x.appName == 'fernfahrerTempomat' then jsonWriteFile(flag, { done = true }); return end end
  table.insert(d.apps, { appName = 'fernfahrerTempomat', placement = { position = 'absolute', bottom = '436px', right = '224px', width = '182px', height = '130px', ['pointer-events'] = 'none' } })
  jsonWriteFile(f, d, true)
  jsonWriteFile(flag, { done = true })
end

-- (2026-11-08) the game world behind the office and the stop menus goes soft: the game's own screen blur (the same as in
-- its menus; a blur in the page could only ever blur the page), faded in and out
L.MENU_BLUR_S = 0.32
-- (2026-11-09) in the career the game's own ways to a whole truck are shut: reset, recovery, reload, home, the vehicle and parts menus (the keys and the radial menu's entries, which ask
-- the same filter). The settings have a developer switch for those who want them back.
function L.resetGuard()
  local block = (R.mode and S and S.settings and not S.settings.devResets) and true or false
  if block == (R.resetBlocked or false) then return end
  local af = rawget(_G, 'core_input_actionFilter')
  if not af then extensions.load('core_input_actionFilter'); af = rawget(_G, 'core_input_actionFilter') end
  if not af then return end
  R.resetBlocked = block
  af.setGroup('ffCareerResets', af.createActionTemplate({ 'vehicleTeleporting', 'vehicleMenues', 'resetPhysics' }))
  af.addAction(0, 'ffCareerResets', block)
end
function L.menuBlurTick(dt)
  pcall(L.resetGuard)
  local want = ((R.officeOpen or R.stopOpen) and not R.garageOn) and 1 or 0
  local b = R.menuBlur or 0
  if b == want and (b == 0 or R.menuBlurSet == b) then return end
  local step = (dt or 0.016) / L.MENU_BLUR_S
  b = want > b and math.min(want, b + step) or math.max(want, b - step)
  R.menuBlur = b
  if not rawget(_G, 'ui_gameBlur') then extensions.load('ui_gameBlur') end
  local gb = rawget(_G, 'ui_gameBlur')
  if not gb then return end
  if b <= 0 then gb.removeGroup('ffMenu')
  else
    -- (smooth at both ends)
    local e = b * b * (3 - 2 * b)
    gb.replaceGroup('ffMenu', { all = { 0, 0, 1, 1, e } })
  end
  R.menuBlurSet = b
end

-- (2026-11-08) securing the load: open loads and general cargo have to be strapped down before driving off (the key,
-- standing, coupled). Forgotten, or driven far too hard, the load comes off: on open trailers physically (their strap
-- beams are break groups), and the job is lost – no pay, the recovery to pay.
L.SECURE_S, L.LOST_FEE = 12, 350
function L.needsSecure()
  local j = S and S.job
  return (j and j.secure and not j.secured and not j.loadLost) and true or false
end
function M.secureLoad()
  if not S or not S.job then return end
  if S.job.secured then notify('Die Ladung ist schon gesichert.', 3); return end
  if not L.needsSecure() then return end
  if not R.trailerId or not isCoupled() then notify('Erst ankuppeln, dann die Ladung sichern.', 4); return end
  if vehSpeed(careerVeh()) > 0.8 then notify('Zum Sichern bitte anhalten.', 4); return end
  if not R.securing then R.securing = { t0 = now(), n = -1 } end
end
function L.secureCard(n, title, text, keys)
  if S.tut and not S.tut.done then return end
  guihooks.trigger('FernfahrerTutHint', { stage = 'secure' .. tostring(title), n = n, total = 4, title = title, text = text, keys = keys, ey = 'Ladungssicherung' })
  R.secureCard = true
end
function L.loseLoad(reason)
  local job = S.job
  if not job or job.loadLost then return end
  job.loadLost = true
  R.lostAt, R.securing = now(), nil
  local tv = vehById(R.trailerId)
  if tv then
    tv:queueLuaCommand([[local seen = {}
      local function t(g) if type(g) == 'string' and not seen[g] and (g:find('[Ss]trap') or g:find('chain')) then seen[g] = true; beamstate.breakBreakGroup(g) end end
      for _, b in pairs(v.data.beams) do
        if type(b.breakGroup) == 'table' then for _, g in pairs(b.breakGroup) do t(g) end else t(b.breakGroup) end
      end]])
  end
  notify('💥 Ladung verloren! ' .. reason, 10)
  message('Die Ladung ist runter. Der Auftrag ist gescheitert – dafür gibt es kein Geld, und die Bergung geht auf deine Rechnung.')
  if R.secureCard then guihooks.trigger('FernfahrerTutHint', { off = true }); R.secureCard = nil end
end
function L.failLost()
  local job = S.job
  local fee = L.LOST_FEE
  local lines = { { 'Ladung verloren – kein Frachtlohn', 0 }, { 'Bergung und Reinigung der Fahrbahn', -fee } }
  L.pay('Bußgelder', -fee, 'Bergung verlorener Ladung: ' .. tostring(job.cargoName))
  S.stats.damaged = (S.stats.damaged or 0) + 1
  local rep = { cargoName = job.cargoName, icon = job.icon, from = job.from.name, to = job.to.name, km = job.distKm, lines = lines, total = -fee, xp = 0,
    late = false, cond = 0, rating = 1, clock = clockText(), day = S.dayNo,
    stars = { { 'Ladung', 1, 'verloren' } } }
  deleteTrailer()
  navClear()
  S.job = nil
  R.lostAt = nil
  pcall(L.moodSting, 'ok_mau')
  R.report, R.reportAt = rep, now() + 1.2
  R.reportDoc = { kind = 'delivery', title = 'Schadensmeldung: Ladung verloren', t = os.time(), clock = rep.clock, cargoName = rep.cargoName, from = rep.from, to = rep.to,
    km = rep.km, lines = rep.lines, total = rep.total, stars = rep.stars, rating = 1, town = rep.to }
  save()
end
function L.loadTick(t, dtSim)
  local job = S and S.job
  if not job then R.securing = nil; if R.secureCard then guihooks.trigger('FernfahrerTutHint', { off = true }); R.secureCard = nil; L.hintOffSoon() end; return end
  if job.loadLost then
    R.lostAt = R.lostAt or t
    if t > R.lostAt + 18 then L.failLost() end
    return
  end
  if not job.secure then return end
  local coupled = R.trailerId and isCoupled()
  local truck = careerVeh()
  local speed = truck and vehSpeed(truck) or 0
  -- the straps going on
  if R.securing then
    if speed > 0.8 or not coupled then
      R.securing = nil
      notify('Sichern abgebrochen – anhalten und noch einmal.', 4)
    else
      local n = math.floor((t - R.securing.t0) / (L.SECURE_S / 4))
      if n ~= R.securing.n then
        R.securing.n = n
        guihooks.trigger('FernfahrerSound', { name = 'click' })
        if n < 4 then L.secureCard(n, 'Gurte werden gespannt …', string.format('Gurt <b>%d von 4</b>. Stehen bleiben.', n + 1)) end
      end
      if n >= 4 then
        job.secured, R.securing = true, nil
        guihooks.trigger('FernfahrerTutHint', { off = true }); R.secureCard = nil
        notify('✔ Ladung gesichert – gute Fahrt!', 5)
        save()
      end
    end
    return
  end
  if L.needsSecure() and coupled and job.phase == 'toDelivery' and not R.secureCard then
    L.secureCard(0, 'Ladung sichern!', 'Bevor du losfährst, müssen die Gurte drauf. Sonst rutscht dir die Ladung vom Auflieger und der Auftrag ist verloren.', 'Strg+Umschalt+G')
  end
  -- what the load goes through
  if not coupled or (job.phase ~= 'toDelivery' and job.phase ~= 'atDelivery') or not dtSim or dtSim <= 0 then R.loadV = nil; return end
  R.loadDt = (R.loadDt or 0) + dtSim
  if R.loadDt < 0.1 then return end
  local dt = R.loadDt
  R.loadDt = 0
  local tv = vehById(R.trailerId)
  if not tv then return end
  local vel = vec3(tv:getVelocity())
  local a = R.loadV and (vel - R.loadV):length() / dt or 0
  R.loadV = vel
  if a > 120 then return end                               -- (a teleport, a reset: no forces)
  R.loadA = (R.loadA or 0) * 0.6 + a * 0.4
  local g = R.loadA
  local secured = job.secured
  if a > (secured and 60 or 30) then return L.loseLoad(secured and 'Der Aufprall hat die Gurte zerrissen.' or 'Beim Aufprall ist alles heruntergefallen.') end
  local st = job.loadStress or 0
  if secured then
    st = math.max(0, st + (g > 5.5 and (g - 5.5) * dt * 0.4 or -dt * 0.03))
  elseif speed > 6 then
    st = st + dt * 0.02 + math.max(0, g - 1.6) * dt * 0.8
  end
  job.loadStress = st
  if st > 0.4 and not job.loadWarned then
    job.loadWarned = true
    notify(secured and '⚠ Die Gurte ächzen – fahr ruhiger!' or '⚠ Die Ladung verrutscht! Anhalten und sichern (Strg+Umschalt+G)!', 7)
  end
  if st >= 1 then L.loseLoad(secured and 'Du bist zu wild gefahren, die Gurte haben nachgegeben.' or 'Du hast vergessen, sie zu sichern.') end
end

-- (2026-11-08) what the vehicle's own Lua is to do (wear.lua): defects of a used truck, the beer in the steering, the
-- joint and the cruise control, overloaded tyres. And hot brakes reported back.
L.DEFECT = { axle = { name = 'Verzogene Achse', text = 'der LKW zieht nach links', fix = 2400, done = 'Die Achse ist gerichtet. Der Lkw fährt wieder geradeaus.' },
  turbo = { name = 'Verschlissener Turbo', text = 'raucht unter Last, weniger Leistung', fix = 4800, done = 'Der Turbo ist erneuert. Volle Leistung und kein Rauch mehr.' } }
function L.wearTick(t)
  if t - (R.wearT or 0) < 1 then return end
  R.wearT = t
  local v = careerVeh()
  if not v then return end
  local def = activeDef()
  local d = (type(def) == 'table' and def.defects) or {}
  local rd = vices.readings()
  local job = S.job
  local over = (job and (job.tons or 0) >= 22) and 1.35 or 1
  local drift = rd.bac >= 0.3 and math.min(0.1, rd.bac * 0.08) or 0
  local high = rd.thc >= 3
  local sig = string.format('{ pull = %s, drift = %.3f, noCruise = %s, turbo = %s, overload = %.2f, smooth = %s }', d.axle and '-0.022' or '0', drift, tostring(high), tostring(d.turbo and true or false), over, tostring(type(def) == 'table' and def.repaired and def.repaired.motor and true or false))
  if sig ~= R.wearSig or R.wearFor ~= v:getID() then
    R.wearSig, R.wearFor = sig, v:getID()
    v:queueLuaCommand('extensions.load("fernfahrer_wear") if fernfahrer_wear then fernfahrer_wear.set(' .. sig .. ') end')
  end
  -- the trailer's tyres too
  if R.trailerId and R.wearTrailer ~= R.trailerId then
    local tv = vehById(R.trailerId)
    if tv then
      R.wearTrailer = R.trailerId
      tv:queueLuaCommand(string.format('extensions.load("fernfahrer_wear") if fernfahrer_wear then fernfahrer_wear.set({ overload = %.2f }) end', over))
    end
  end
  -- a joint: the picture smears (the game's own motion blur)
  local blur = high and vices.fxEnabled ~= false
  if blur ~= (R.blurOn or false) then
    R.blurOn = blur
    pcall(function()
      local fx = scenetree.findObject('PostFxMotionBlur')
      if not fx then return end
      if blur then fx:enable(); fx.strength = math.max(tonumber(settings.getValue('PostFXMotionBlurStrength')) or 0, 0.6)
      else
        fx.strength = tonumber(settings.getValue('PostFXMotionBlurStrength')) or 0
        if not settings.getValue('PostFXMotionBlurEnabled') then fx:disable() end
      end
    end)
  end
end
function M.onWheelState(id, maxT, burst)
  if not S or (id ~= R.truckId and id ~= R.trailerId) then return end
  local t = now()
  if burst then
    notify('💥 Reifenplatzer! Die Bremsen waren zu heiß – vorsichtig rechts ran.', 9)
    story('tyreBurst')
  elseif maxT > 430 and t - (R.brakeWarnT or 0) > 45 then
    R.brakeWarnT = t
    notify(string.format('🔥 Bremsen überhitzen (%d °C)! Runterschalten und Motorbremse nutzen – sonst platzt ein Reifen.', maxT), 7)
  end
end

-- (2026-11-08) the talk with the officer at a police check: what the check found comes up one by one; for each an honest
-- answer (a little cheaper, for certain), an excuse (it may work – or cost more), or an offer (rarely works).
L.COP = {
  tacho = { 0.55, 'Mit Verlaub, ich stand ewig im Stau und kam auf keinen Parkplatz.', 'Ihr Fahrtenschreiber sagt da etwas: ' },
  alcohol = { 0.2, 'Das ist bestimmt mein Mundwasser, ehrlich.', 'Der Atemtest zeigt: ' },
  thc = { 0.3, 'Das kann nur vom Passivrauchen auf dem Rastplatz sein.', 'Der Schnelltest ist positiv: ' },
  unsafe = { 0.6, 'Ich bin gerade auf dem Weg in die Werkstatt.', 'Ihr Fahrzeug sieht übel aus: ' },
  load = { 0.6, 'Die Gurte habe ich vor zehn Minuten noch nachgezogen.', 'Das gefällt mir nicht: ' },
  limiter = { 0.4, 'Das muss ein Fehler im Steuergerät sein.', 'Wir haben das Steuergerät ausgelesen: ' },
  adr = { 0.45, 'Die Papiere liegen im Büro, mein Disponent schickt sie sofort aufs Handy.', 'Bei Gefahrgut brauche ich die Papiere: ' },
  pack = { 0.3, 'Das Päckchen? Das muss jemand vergessen haben.', 'Was haben wir denn hier? ' },
}
function L.copOut() local c = R.cop; if c then c.id = (c.id or 0) + 1; L.copSend() end end
function L.copSend()
  local c = R.cop
  if c then guihooks.trigger('FernfahrerCop', { id = c.id, line = c.line, choices = c.choices, tag = c.tag, face = 'cop', seed = c.seed, mood = c.mood, react = c.react }) end
end
function L.copSay(stage, line, choices, tag, react)
  local c = R.cop
  c.stage, c.line, c.choices, c.tag, c.react = stage, line, choices, tag, react
  c.mood = math.max(-4, math.min(4, c.mood))
  L.copOut()
end
-- (2026-11-08) one question per kind of offence: the tachograph hands over every single violation, the officer asked the
-- same thing again after each answer and the talk seemed to go round in circles
function L.copMerge(found)
  local out, byKind = {}, {}
  for _, f in ipairs(found or {}) do
    local k = f.kind or 'tacho'
    local m = byKind[k]
    if m then m.amount, m.n = m.amount + f.amount, m.n + 1
    else m = { kind = f.kind, amount = f.amount, reason = f.reason, n = 1 }; byKind[k] = m; out[#out + 1] = m end
  end
  for _, m in ipairs(out) do if m.n > 1 then m.reason = string.format('%d Verstöße, zuletzt: %s', m.n, tostring(m.reason)) end end
  return out
end
function L.copStart(found)
  local job = S.job
  L.encAttach()
  L.enc.contraband(found)
  -- (2026-11-09: the mood of the day shows on the face, and it counts: a friendly officer lets more go)
  R.cop = { found = L.copMerge(found), i = 0, mood = math.random(-2, 2), out = {}, id = 0, sends = now(), seed = math.random(1, 4000) }
  -- (the head turns to the officer at the window)
  vices.installCam()
  vices.setLook(R.rcScene and -66 or 66, -5)     -- (at a rest area he stands at the driver's door, on the left)
  local ask = (job and job.adr) and ' und die ADR-Papiere.' or '.'
  local m = R.cop.mood
  L.copSay('intro', (m <= -1 and 'Verkehrskontrolle. Motor aus, Fahrzeugpapiere und Fahrerkarte' or (m >= 1 and 'Schönen guten Tag! Nur eine kleine Verkehrskontrolle. Fahrzeugpapiere und Fahrerkarte bitte' or 'Guten Tag, Verkehrskontrolle. Fahrzeugpapiere und Fahrerkarte bitte')) .. ask,
    { { t = 'Guten Tag. Bitte sehr.' }, { t = 'Worum geht es denn?' }, { t = 'Ich hab es eilig, machen wir es kurz.' } }, nil, m <= -1 and 'sneer' or nil)
end
function L.copNext()
  local c, job = R.cop, S.job
  if job and job.smuggle and not c.smDone then
    c.smDone = true
    return L.copSay('cargo', 'Was haben Sie denn geladen?', {
      { t = '„Stückgut. Hier ist der Frachtbrief.“' }, { t = '„Ich fahre nur, geladen hat die Firma.“' }, { t = '„Schauen Sie ruhig nach, ist alles sauber.“' } })
  end
  c.i = c.i + 1
  local f = c.found[c.i]
  if not f then return L.copEnd() end
  local def = L.COP[f.kind or 'tacho'] or L.COP.tacho
  c.cur = f
  L.copSay('find', (#c.found > 1 and string.format('Punkt %d von %d. ', c.i, #c.found) or '') .. def[3] .. tostring(f.reason) .. string.format('. Das macht %s.', money(f.amount)), {
    { t = '„Stimmt, das tut mir leid.“', sub = 'ehrlich: etwas billiger' },
    { t = '„' .. def[2] .. '“', sub = 'rausreden: kann klappen, kann teurer werden' },
    { t = '„Können wir das nicht unter uns regeln?“', sub = 'Schmiergeld: riskant' },
  })
end
function L.copReply(line, react) L.copSay('reply', line, { { t = 'Weiter' } }, nil, react) end
function L.copEnd()
  local c = R.cop
  local sum = 0
  for _, x in ipairs(c.out) do sum = sum + x.amount end
  if c.seized then
    return L.copSay('bye', string.format('Das Fahrzeug ist beschlagnahmt. Dazu %s. Sie hören von uns.', money(sum)), { { t = 'Aussteigen' } }, nil, 'threat')
  end
  if sum > 0 then
    L.copSay('bye', string.format('Macht zusammen %s. Ich schreibe das auf. Gute Fahrt – und fahren Sie vernünftig.', money(sum)), { { t = 'Auf Wiedersehen' } }, nil, 'nod')
  else
    c.mood = c.mood + 2
    L.copSay('bye', 'Dann ist alles in Ordnung. Gute Fahrt!', { { t = 'Danke, schönen Tag noch' } }, nil, 'nod')
  end
end
function L.copFinish()
  local c = R.cop
  R.cop = nil
  vices.setLook(0, 0)
  guihooks.trigger('FernfahrerCop', { off = true })
  if not c then return end
  if #c.out == 0 and not c.seized then addXp(50); return end
  for _, x in ipairs(c.out) do M.fine(x.amount, x.reason) end
  if c.lostCargo and S.job then
    message('Die Ware ist beschlagnahmt, der Auftrag ist weg.', 'Polizei')
    deleteTrailer(); navClear(); S.job = nil
  end
  if c.seized then L.seizeTruck() end
  save()
end
function L.seizeTruck()
  local own = L.ownTruck()
  if S.job then deleteTrailer(); navClear(); S.job = nil end
  if own then
    own.seized = true
    message(string.format('Dein %s %s ist beschlagnahmt. Auslösen kannst du ihn im Fuhrpark. Bis dahin fährst du den Leih-LKW.', tostring(own.brand), tostring(own.modelName)), 'Polizei')
    S.active = 'loaner'
    local def = activeDef()
    if playerVeh() then core_vehicles.replaceVehicle(def.model, { config = def.config, autoEnterVehicle = true }) end
    R.truckId, R.fuel = nil, nil
    R.pendingAdopt = now() + 0.5
  end
end
function L.seizeValue(o) return round((o.price or 60000) * 0.25, 100) end
function M.redeemTruck(i)
  local o = S and S.owned[i]
  if not o or not o.seized then return end
  local fee = L.seizeValue(o)
  if S.money < fee then notify('Die Auslöse kostet ' .. money(fee) .. ' – nicht genug Geld.', 5); return end
  L.pay('Bußgelder', -fee, 'Fahrzeug ausgelöst: ' .. tostring(o.modelName))
  o.seized = nil
  notify('Dein LKW ist wieder frei.', 5)
  save()
end
function M.useGadget(id) if S then L.acc.use(L.accTruck(), id) end end
function M.copAnswer(i)
  if L.enc.active() then return L.enc.answer(i) end
  local c = R.cop
  if not c then return end
  i = tonumber(i) or 1
  local stage = c.stage
  if stage == 'intro' then
    c.mood = c.mood + (i == 1 and 1 or (i == 2 and 0 or -2))
    return L.copReply(i == 3 and 'Immer mit der Ruhe. Das dauert so lange, wie es dauert.' or 'Einen Moment, ich schaue mir das an.', i == 3 and 'shake' or 'think')
  elseif stage == 'reply' then
    return L.copNext()
  elseif stage == 'bye' then
    return L.copFinish()
  elseif stage == 'find' then
    local f = c.cur
    local def = L.COP[f.kind or 'tacho'] or L.COP.tacho
    if i == 1 then
      c.out[#c.out + 1] = { amount = round(f.amount * 0.75, 10), reason = tostring(f.reason) }
      c.mood = c.mood + 1
      return L.copReply('Immerhin ehrlich. Ich drücke ein Auge zu und mache es etwas günstiger.', 'nod')
    elseif i == 2 then
      if math.random() < def[1] + c.mood * 0.11 then
        return L.copReply('Na gut. Diesmal belasse ich es bei einer Verwarnung.', 'sneer')
      end
      c.out[#c.out + 1] = { amount = round(f.amount * 1.25, 10), reason = tostring(f.reason) .. ' (uneinsichtig)' }
      c.mood = c.mood - 1
      return L.copReply('Das glauben Sie doch selbst nicht. Das wird jetzt teurer.', 'shake')
    else
      local bribe = math.max(150, round(f.amount * 0.3, 10))
      if math.random() < 0.22 + c.mood * 0.08 then
        L.pay('Bußgelder', -bribe, 'Barzahlung an der Straße')
        return L.copReply(string.format('… %s. Ich habe nichts gesehen. Fahren Sie weiter.', money(bribe)), 'wink')
      end
      c.out[#c.out + 1] = { amount = f.amount + 1500, reason = tostring(f.reason) .. ' und Bestechungsversuch' }
      c.mood = c.mood - 2
      return L.copReply('Das habe ich jetzt nicht gehört. Bestechungsversuch – das kostet Sie extra.', 'shock')
    end
  elseif stage == 'cargo' then
    local p = ({ 0.62, 0.42, 0.55 })[i] or 0.5
    if math.random() < p + c.mood * 0.06 then
      return L.copReply(i == 3 and 'Passt schon, ich habe heute keine Lust auf den Papierkram.' or 'Sieht in Ordnung aus.', 'nod')
    end
    return L.copSay('caught', 'Moment. Im Auflieger ist etwas ganz anderes als auf dem Papier. Das ist unverzollte Ware.', {
      { t = '„Davon wusste ich nichts, ich bin nur der Fahrer.“', sub = 'rausreden' },
      { t = '„Vielleicht regeln wir das unter uns? 2.000 € bar.“', sub = 'Schmiergeld' },
      { t = '„Ich sage nichts ohne meinen Anwalt.“', sub = 'teuer, aber der LKW bleibt' },
      { t = 'Gas geben', sub = 'abhauen: Die Polizei wird dich verfolgen' },
    }, 'smuggle', 'threat')
  elseif stage == 'caught' then
    if i == 4 then
      R.cop = nil
      vices.setLook(0, 0)
      guihooks.trigger('FernfahrerCop', { off = true })
      L.pursuitStart('Du bist bei der Kontrolle abgehauen. Die Polizei ist hinter dir her!')
      return
    end
    if i == 3 then
      c.out[#c.out + 1] = { amount = 12000, reason = 'Steuerhehlerei: unverzollte Ware' }
      c.lostCargo = true
      return L.copReply('Wie Sie wollen. Die Ware bleibt hier, die Anzeige geht raus.')
    elseif i == 1 and math.random() < 0.45 + c.mood * 0.06 then
      c.out[#c.out + 1] = { amount = 2500, reason = 'Ware ohne Zollpapiere befördert' }
      c.lostCargo = true
      return L.copReply('Das nehme ich Ihnen mal ab. Die Ware ist beschlagnahmt, Sie kommen mit einem blauen Auge davon.')
    elseif i == 2 and S.money >= 2000 and math.random() < 0.3 + c.mood * 0.05 then
      L.pay('Bußgelder', -2000, 'Barzahlung an der Straße')
      return L.copReply('… Sie waren nie hier. Verschwinden Sie.')
    end
    local own = L.ownTruck()
    c.out[#c.out + 1] = { amount = own and 18000 or 24000, reason = 'Schmuggel unverzollter Ware' }
    c.lostCargo = true
    if own then c.seized = true end
    return L.copReply(own and 'Das reicht. Der Lastwagen wird beschlagnahmt.' or 'Das reicht. Die Firma bekommt die Rechnung, und Sie auch.')
  end
end
function L.copTick(t)
  local c = R.cop
  if not c then return end
  if t - (c.sends or 0) > 1 then c.sends = t; L.copSend() end
  local v = careerVeh()
  if v and vehSpeed(v) > 5 then
    R.cop = nil
    vices.setLook(0, 0)
    guihooks.trigger('FernfahrerCop', { off = true })
    if S.job and S.job.smuggle and not S.job.chased then L.pursuitStart('Du bist bei der Kontrolle abgehauen. Die Polizei ist hinter dir her!'); return end
    M.fine(1500, 'Polizeikontrolle einfach verlassen')
  end
end

-- (2026-11-08) ADR papers: taken along from the office – without them a check gets very expensive
-- (only where the load is handed over: within 200 m of the pickup or, until it is coupled up, of the waiting trailer)
L.PAPERS_M = 200
function L.papersAway()
  local j = S and S.job
  local p = here()
  if not j or not j.adr or not p or not j.from or not j.from.lat then return nil end
  local d = haversine(p.lat, p.lon, j.from.lat, j.from.lon)
  if j.phase ~= 'toDelivery' and R.trailerId and R.truckId then
    local tv, mv = getObjectByID(R.trailerId), getObjectByID(R.truckId)
    if tv and mv then d = math.min(d, vec3(tv:getPosition()):distance(vec3(mv:getPosition()))) end
  end
  return d
end
function M.packPapers()
  if not (S and S.job and S.job.adr) or S.job.papers then return end
  local d = L.papersAway()
  if not d or d > L.PAPERS_M then notify('📄 Die ADR-Papiere gibt es nur am Abholort (Umkreis 200 m).', 5); return end
  S.job.papers = true
  notify('📄 ADR-Papiere eingepackt.', 4)
  save()
end

-- (2026-11-08) the statistics page: a driver's record kept for good (the delivery notes are thinned out in time)
function L.statAdd(x, from, to, km, rating, stars, t)
  x.jobs = x.jobs + 1
  if rating then
    x.n, x.sum = x.n + 1, x.sum + rating
    for _, s in ipairs(stars or {}) do
      if type(s) == 'table' and s[1] and tonumber(s[2]) then
        local c = x.cats[s[1]] or { n = 0, sum = 0 }
        c.n, c.sum = c.n + 1, c.sum + tonumber(s[2])
        x.cats[s[1]] = c
      end
    end
  end
  local key = tostring(from) .. ' → ' .. tostring(to)
  local r = x.routes[key] or { from = from, to = to, n = 0, rn = 0, sum = 0 }
  r.n, r.km, r.last = r.n + 1, km or r.km, t
  if rating then r.rn, r.sum = r.rn + 1, r.sum + rating; r.best = math.max(r.best or 0, rating) end
  x.routes[key] = r
end
function L.statX()
  if type(S.statx) == 'table' then return S.statx end
  local x = { jobs = 0, n = 0, sum = 0, cats = {}, routes = {}, deliv = {} }
  S.statx = x
  -- (what the delivery notes still tell: the record of a career from before there was one)
  for i = #(S.documents or {}), 1, -1 do
    local d = S.documents[i]
    if d.kind == 'delivery' then L.statAdd(x, d.from, d.to, d.km, d.rating, d.stars, d.t) end
  end
  return x
end
function L.statDelivery(job, rep)
  local x = L.statX()
  L.statAdd(x, rep.from, rep.to, rep.km, rep.rating, rep.stars, os.time())
  local p = here()
  local ok, pl = pcall(streets.placeAt, p.lat, p.lon, true)
  if ok and pl and pl.name then x.deliv[pl.name] = (x.deliv[pl.name] or 0) + 1 end
end
function L.statsView()
  local x = L.statX()
  local towns, routes, cats = {}, {}, {}
  local info = S.townInfo or {}
  for name, n in pairs(S.towns or {}) do
    local i = info[name] or {}
    towns[#towns + 1] = { name = name, n = n, k = i.k, f = i.f, l = i.l, d = x.deliv[name] }
  end
  for _, r in pairs(x.routes) do
    routes[#routes + 1] = { from = r.from, to = r.to, n = r.n, km = r.km, last = r.last, best = r.best, avg = r.rn > 0 and r.sum / r.rn or nil }
  end
  table.sort(routes, function(a, b)
    if a.n ~= b.n then return a.n > b.n end
    return (a.last or 0) > (b.last or 0)
  end)
  while #routes > 30 do routes[#routes] = nil end
  for name, c in pairs(x.cats) do cats[#cats + 1] = { name = name, avg = c.sum / c.n, n = c.n } end
  table.sort(cats, function(a, b) return a.name < b.name end)
  return { towns = towns, routes = routes, cats = cats, n = x.n, avg = x.n > 0 and x.sum / x.n or nil, jobs = x.jobs,
    odo = S.stats.odoKm or 0, freight = S.stats.km or 0, deliv = (function() local c = 0; for _ in pairs(x.deliv) do c = c + 1 end; return c end)() }
end
-- (the kilometres really driven: the truck's own way, a teleport or a ferry left out)
function L.odoTick(t)
  if t - (R.odoT or 0) < 1 then return end
  R.odoT = t
  local v = R.truckId and not R.trip and not R.sleep and getObjectByID(R.truckId)
  if not v then R.odoP = nil; return end
  local p = vec3(v:getPosition())
  if R.odoP then
    local d = math.sqrt((p.x - R.odoP.x) ^ 2 + (p.y - R.odoP.y) ^ 2)
    if d > 0.4 and d < 70 then S.stats.odoKm = (S.stats.odoKm or 0) + d / 1000 end
  end
  R.odoP = p
end

-- (2026-11-08) goods without papers: at back doors and at some rest areas someone asks. Very well paid; caught, it
-- gets very expensive or the truck is gone.
-- (2026-11-09: name, icon, tonnes, how hot: 0 they look the other way more easily, 2 they want it badly. Pays more the hotter it is.)
L.SMUGGLE = { { 'Unverzollte Zigaretten', '🚬', 12, 0 }, { 'Unversteuerter Alkohol', '🍾', 16, 0 }, { 'Markenfälschungen', '👜', 9, 0 }, { 'Ware ohne Papiere', '📦', 14, 0 }, { 'Unverzollter Tabak', '🍂', 13, 0 },
  { 'Gefälschte Ersatzteile', '⚙', 11, 1 }, { 'Gestohlene Elektronik', '📺', 8, 1 }, { 'Hehlerware aus dem Lager', '🧳', 10, 1 }, { 'Feuerwerk ohne Zulassung', '🎆', 7, 1 }, { 'Gestohlene Autoteile', '🚗', 15, 1 },
  { 'Gefälschte Medikamente', '💊', 6, 2 }, { 'Illegal entsorgter Giftmüll', '☣', 18, 2 }, { 'Beschlagnahmte Ware, die weg muss', '🚨', 9, 2 }, { 'Geschützte Tropenhölzer', '🪵', 20, 2 } }
-- (the places for it: some of the ports, timber yards, scrap yards and a few industrial estates have a dark corner. On the map, a ring like any other place.)
DEPOT_BY_KEY.underground = { key = 'underground', name = 'Underground', icon = '🕶️', facility = true, radius = 75, action = 'underground', queries = {} }
L.UG_KIND = {
  port = { 60, { 'Dunkles Hafengebiet', 'Alte Hafenbrache', 'Verlassener Kai' } },
  timber = { 30, { 'Dunkles Waldlager', 'Verlassenes Holzlager', 'Lichtung im Forst' } },
  scrap = { 30, { 'Schrottplatz am Waldrand', 'Hinter der Schrottpresse' } },
  industry = { 4, { 'Verlassenes Werksgelände', 'Stillgelegte Fabrik', 'Alte Halle' } },
  logistics = { 2, { 'Leere Lagerhalle', 'Hinterhof-Lager' } },
}
function L.ugSync(t)
  if t - (R.ugT or 0) < 10 then return end
  R.ugT = t
  if #S.depots == R.ugN then return end
  local have = {}
  for _, d in ipairs(S.depots) do if d.type == 'underground' then have[d.base] = true end end
  local add = {}
  for _, d in ipairs(S.depots) do
    local u = L.UG_KIND[d.type]
    if u and not have[d.id] then
      local h = L.hashStr('ug:' .. tostring(d.id) .. ':' .. tostring(d.lat))
      if h % 100 < u[1] then
        -- (a little way off the firm itself, so that its ring stays its own)
        add[#add + 1] = { id = 'ug' .. tostring(d.id), base = d.id, type = 'underground', name = u[2][1 + math.floor(h / 100) % #u[2]], detail = d.detail, lat = d.lat + 0.001, lon = d.lon + 0.0008 }
      end
    end
  end
  for _, d in ipairs(add) do table.insert(S.depots, d) end
  R.ugN = #S.depots
end
function L.withUg(list)
  local n = 0
  for _, d in ipairs(S.depots) do if d.type == 'underground' then n = n + 1 end end
  local t = DEPOT_BY_KEY.underground
  table.insert(list, { key = t.key, name = t.name, icon = t.icon, facility = true, count = n })
  return list
end
-- (2026-11-09) caught with it: the police come after the truck (pursuit.lua)
L.pursuit = require('fernfahrer/pursuit')
L.BUST_FINE = { 12000, 18000, 26000 }
function L.pursuitEndFx() accidents.muted = false end
function L.pursuitStart(text)
  local j = S and S.job
  if not j or not j.smuggle or L.pursuit.active() then return end
  j.chased = true
  accidents.muted = true
  L.pursuit.start({ veh = function() return careerVeh() end, protect = function(id) roadEvents.protect(id) end,
    note = function(why) notify(({ wreck = '💥 Eine Streife ist aus dem Spiel.', lost = '🚓 Eine Streife hat dich verloren.', duty = '🚓 Eine Streife bricht die Verfolgung ab.' })[why], 4) end,
    busted = L.pursuitBusted, escaped = L.pursuitEscaped, gone = L.pursuitEndFx })
  notify('🚨 ' .. tostring(text) .. ' Halt nicht an, wenn du es drauf ankommen lassen willst.', 9)
  message(tostring(text), 'Polizei')
end
function L.pursuitBusted()
  L.pursuitEndFx()
  local j, fine = S.job, L.BUST_FINE[((S.job and S.job.heat) or 0) + 1] or 18000
  M.fine(fine, 'Schmuggel und Flucht vor der Polizei')
  message('Sie haben dich gestellt. Die Ware ist beschlagnahmt, der Auftrag ist weg.', 'Polizei')
  notify('🚔 Gestellt. Die Ware ist weg.', 8)
  if L.ownTruck() and math.random() < 0.3 then L.seizeTruck()
  elseif j then deleteTrailer(); navClear(); S.job = nil end
  save()
end
function L.pursuitEscaped()
  L.pursuitEndFx()
  addXp(500)
  notify('😮‍💨 Abgehängt! Keine Streife mehr hinter dir. Bring die Ware ans Ziel.', 9)
  message('Du bist ihnen entkommen. Die Ware ist noch an Bord.', 'Funk')
  save()
end
-- a chance on the road, the hotter the load the more
function L.heatTick(t)
  if t - (R.heatT or 0) < 20 then return end
  R.heatT = t
  local j = S.job
  if not j or not j.smuggle or j.chased or L.pursuit.active() or R.cop or R.trip or R.sleep or R.boot ~= nil or R.officeOpen or R.stopOpen or not R.trailerId or not isCoupled() then return end
  local v = careerVeh()
  if not v or vehSpeed(v) < 8 then return end
  if math.random() < (({ 0.006, 0.012, 0.02 })[(j.heat or 0) + 1] or 0.012) then L.pursuitStart('Eine Zivilstreife hat deine Ladung bemerkt und ruft Verstärkung!') end
end
-- (2026-11-09) a viewpoint near the road: a word about it, once, and not all the time
L.shots = require('fernfahrer/cabphotos')
function L.viewTick(t)
  if R.viewHint and t > R.viewHint.till then R.viewHint = nil end
  if R.viewHint or t - (R.viewT or 0) < 4 or t - (R.viewLast or -999) < 180 then return end
  R.viewT = t
  local v, p = careerVeh(), here()
  if not v or not p or vehSpeed(v) < 5 or R.officeOpen or R.stopOpen or R.trip or R.boot ~= nil then return end
  R.viewSeen = R.viewSeen or {}
  local f = vec3(v:getDirectionVector())
  local best, bd, bdot, bcross
  for _, d in ipairs(S.depots) do
    if d.type == 'viewpoint' and math.abs(d.lat - p.lat) < 0.016 and math.abs(d.lon - p.lon) < 0.03 and not R.viewSeen[d.id] then
      local dd = haversine(p.lat, p.lon, d.lat, d.lon)
      if dd < 1500 and dd > 150 and (not bd or dd < bd) then
        local e, n = (d.lon - p.lon) * 111320 * math.cos(math.rad(p.lat)), (d.lat - p.lat) * 111320
        local l = math.max(1, math.sqrt(e * e + n * n))
        local dot, cross = (e * f.x + n * f.y) / l, (e * f.y - n * f.x) / l
        if dot > -0.3 then best, bd, bdot, bcross = d, dd, dot, cross end
      end
    end
  end
  if not best then return end
  R.viewSeen[best.id] = true
  R.viewLast = t
  local where = bdot > 0.7 and 'voraus' or (bcross > 0 and 'rechts' or 'links')
  local name = (best.name and best.name ~= '') and best.name or 'Aussichtspunkt'
  R.viewHint = { id = best.id, name = name, km = string.format('%.1f km', bd / 1000):gsub('%.', ','), where = where, till = t + 30 }
  notify(string.format('🔭 %s, %s %s. Lust auf einen Abstecher und ein Foto?', name, R.viewHint.km, where), 8)
end
-- the pictures
function L.shotFrame()
  local tr = L.accTruck()
  if tr and tr.acc and next(tr.acc) and L.acc.last and now() - (R.accHookT or 0) < 0.3 then return L.acc.last end
  local v = careerVeh() or playerVeh()
  if not v then return nil end
  local F, U = vec3(v:getDirectionVector()), vec3(v:getDirectionVectorUp())
  local Rt = F:cross(U):normalized()
  U = Rt:cross(F):normalized()
  return { eye = vec3(v:getPosition()) + U * 1.6 + F * 1.2 - Rt * 0.55, F = F, R = Rt, U = U, flip = 1 }
end
function L.shotsApi()
  vices.installCam()
  R.photoActive = true
  return { last = L.shotFrame, spots = function() return L.acc.spots() end, spot = function(id) return L.acc.spotOf(id) end, setCef = L.cineCef, setOverride = function(fn) vices.override = fn end,
    onceDone = function() R.photoActive = nil; notify('📷 Foto gespeichert. Du findest es in der BeamNG-Galerie und beim Bilderrahmen.', 6) end }
end
function L.shotsStop()
  local n = L.shots.stop()
  R.photoActive = nil
  if n then notify(string.format('📷 Fotoserie beendet: %d Bilder im Ordner screenshots/trucks_of_earth.', n), 7) end
end
function M.photoSeriesToggle()
  if not R.mode or not S then return end
  if L.shots.active() then L.shotsStop(); return end
  if not S.settings.photoSeries then notify('Die Fotoserie schaltest du in den Einstellungen ein.', 5); return end
  if not L.autodriveOn() then notify('Die Fotoserie gibt es im Autodrive (Strg+Umschalt+A).', 5); return end
  if cinematic.active() then return end
  L.cineStop()
  L.shots.start(L.shotsApi())
  notify('📷 Fotoserie läuft. Strg+Umschalt+C beendet sie.', 3)
end
function M.viewPhoto()
  if not R.mode or not S or L.shots.active() or L.cine.active() or cinematic.active() then return end
  L.shots.once(L.shotsApi())
end
function M.photoMode() guihooks.trigger('MenuOpenModule', 'pause.photomode') end
function L.shotsTick(t)
  if not L.shots.active() then return end
  if not L.shots.isOnce() and (not L.autodriveOn() or L.gamePaused() or R.officeOpen or R.stopOpen or R.trip or R.pendingTeleport or R.sleep or R.cop) then L.shotsStop(); return end
  L.shots.tick(t)
end
-- (2026-11-09) the map of the office shows Europe: a thin layer of the shipped places beyond the network around the home; what is near comes in by itself on the way there
function L.farAdd(out)
  if not R.farList then local ok, d = pcall(jsonReadFile, '/fernfahrer/places_far.json'); R.farList = (ok and type(d) == 'table') and d or {} end
  local h = S.home
  if not h then return end
  for _, p in ipairs(R.farList) do
    local t = DEPOT_BY_KEY[p[1]]
    if t and t.enabled ~= false and haversine(h.lat, h.lon, p[2], p[3]) > 600000 then
      out[#out + 1] = { id = 'far:' .. p[2] .. ':' .. p[3] .. ':' .. p[1], name = t.name, detail = p[4] ~= '' and p[4] or nil, lat = p[2], lon = p[3], type = p[1], typeName = t.name, icon = t.icon, facility = t.facility or false }
    end
  end
end
function L.extraTick(t)
  if not S or not R.mode then return end
  if R.brakeOffAt and t > R.brakeOffAt then R.brakeOffAt = nil; if not R.stopOpen and not R.garageOn then L.autoBrakeOff() end end
  pcall(L.ugSync, t); pcall(L.viewTick, t); pcall(L.heatTick, t); pcall(L.pursuit.tick, t); pcall(L.shotsTick, t)
end
function L.contactAt(p)
  local s, h = 'c' .. tostring(p and p.id or ''), 11
  for i = 1, #s do h = (h * 37 + s:byte(i)) % 1000003 end
  return h % 100 < 30
end
function L.smuggleAt(p)
  if not p or not S then return end
  S.smuggleKnown = true
  local n = 0
  for _, o in ipairs(R.offers) do if o.smuggle and o.from and o.from.id == p.id then n = n + 1 end end
  R.smuggleT = R.smuggleT or {}
  if n >= 3 or (R.smuggleT[p.id] and now() - R.smuggleT[p.id] < 600) then return end
  R.smuggleT[p.id] = now()
  local from
  for _, d in ipairs(S.depots) do if d.id == p.id then from = d; break end end
  if not from then return end
  for _ = 1, 3 - n do
    local to = pickDepot({ 'underground', 'logistics', 'industry', 'port' }, from, 180000, from)
    if not to then return end
    local g = L.SMUGGLE[math.random(#L.SMUGGLE)]
    local cargo = { key = 'smuggle', name = g[1], icon = g[2], t = g[3], mult = ({ 3.2, 3.8, 4.6 })[g[4] + 1], trailers = { { 'eu_trailers', 'box3a' }, { 'dryvan', '53ft' } } }
    local o = makeOffer(cargo, from, to, here() or from)
    o.smuggle, o.urgent, o.heat = true, false, g[4]
    table.insert(R.offers, o)
  end
end

-- (2026-11-08) drivers of one's own: a truck that stands in the fleet goes out with a hired driver, in the background.
-- Every few game hours a tour is done: the money comes in, the wage and the wear go out.
L.DRIVER_FEE = 1500
L.DRIVER_NAMES = { 'Kalle', 'Mehmet', 'Sabine', 'Jurek', 'Olaf', 'Marek', 'Svetlana', 'Heinz', 'Tomasz', 'Dieter', 'Ayşe', 'Uwe' }
function M.hireDriver(i)
  local o = S and S.owned[i]
  if not o or o.driver or o.seized or (o.kind or 'truck') ~= 'truck' then return end
  if S.active == i then notify('Diesen LKW fährst du gerade selbst.', 4); return end
  if not next(S.yardUp or {}) then notify('Fahrer gibt es erst, wenn du deinen Hof ausgebaut hast.', 5); return end
  if S.money < L.DRIVER_FEE then notify('Nicht genug Geld für die Einstellung.', 4); return end
  L.pay('Fahrer', -L.DRIVER_FEE, 'Einstellung')
  o.driver = { name = L.DRIVER_NAMES[math.random(#L.DRIVER_NAMES)], skill = 0.8 + math.random() * 0.4, next = 2 + math.random() * 4, tours = 0, earned = 0 }
  notify(o.driver.name .. ' fährt jetzt deinen ' .. tostring(o.modelName) .. '.', 5)
  save()
end
function M.fireDriver(i)
  local o = S and S.owned[i]
  if not o or not o.driver then return end
  notify(o.driver.name .. ' ist entlassen.', 4)
  o.driver = nil
  save()
end
function L.driversTick(hours)
  if not S or not hours or hours <= 0 then return end
  for _, o in ipairs(S.owned or {}) do
    local d = o.driver
    if d and not o.seized then
      d.next = (d.next or 5) - hours
      if d.next <= 0 then
        d.next = 6 + math.random() * 6
        local km = 180 + math.random() * 420
        local pay = (260 + km * 2.1) * (d.skill or 1)
        local wage = 140 + km * 0.32
        local wear = km * 0.34
        local crash = math.random() < 0.05 and (800 + math.random() * 2600) or 0
        local net = round(pay - wage - wear - crash, 10)
        L.pay('Fahrer', net, string.format('%s: Tour %d km%s', d.name, round(km), crash > 0 and ' (mit Unfallschaden)' or ''))
        o.km = (o.km or 0) + km
        d.tours, d.earned = (d.tours or 0) + 1, (d.earned or 0) + net
        if crash > 0 then message(string.format('%s hatte einen Unfall. Die Reparatur kostet %s.', d.name, money(crash)), 'Mira (Disposition)') end
      end
    end
  end
end

-- (2026-11-08) CB radio: every few minutes on the road another driver on the channel; what he says about the road ahead
-- is true when something is coming (the road events' own scene), else small talk.
L.CB_HANDLE = { 'Dieselkönig', 'Rostlaube', 'Nachteule', 'Bärchen', 'Kilometerfresser', 'Sturmvogel', 'Elbe-Express', 'Pott-Paule', 'Kaffeetasse', 'Schwarzer Peter' }
L.CB_TALK = {
  'Mahlzeit zusammen. Wer hat noch Kaffee?', 'Der Rastplatz bei {city} ist schon wieder dicht.', 'Hinter {city} rollt es heute gut.',
  'Pass auf bei {city}, die Rennleitung steht gern hinter der Brücke.', 'Noch drei Stunden, dann ist Feierabend.', 'Bei {city} gibt es den besten Kaffee an der Strecke, sag ich euch.',
  'Stau hinter der Ausfahrt {city}, drei Kilometer zäh.', 'Blitzer vor {city}, die stehen da fast jeden Tag.', 'Meine Frau denkt, ich bin in {city}. Bin ich auch fast.',
  'Wer fährt heute noch Richtung {city}? Over.', 'Das Wetter bei {city} ist auch nicht mehr, was es mal war.', 'Dem Disponenten sag ich nächstes Mal die Meinung. Over.',
}
function L.cbTick(t)
  if not S or S.settings.cb == false or R.cop then return end
  if not R.cbNext then R.cbNext = t + 90 + math.random() * 120 end
  if t < R.cbNext then return end
  local v = playerVeh()
  if not v or vehSpeed(v) < 6 then R.cbNext = t + 20; return end
  R.cbNext = t + 150 + math.random() * 270
  local p = here()
  if not p then return end
  local city, bd
  for _, c in ipairs(citiesData.LIST or {}) do
    local d = haversine(p.lat, p.lon, c[2], c[3])
    if not bd or d < bd then city, bd = c[1], d end
  end
  local h = L.CB_HANDLE[math.random(#L.CB_HANDLE)]
  local text
  local ev = roadEvents.hud(p)
  if ev and ev.dist and ev.dist > 300 then
    text = string.format('Achtung, %s, ungefähr %s km vor uns. Over.', tostring(ev.title), (string.format('%.1f', ev.dist / 1000):gsub('%.', ',')))
  else
    text = L.CB_TALK[math.random(#L.CB_TALK)]:gsub('{city}', tostring(city or 'der Autobahn'))
  end
  R.toast = { from = 'CB · ' .. h, text = text, until_ = now() + 10, id = (R.toast and R.toast.id or 0) + 1 }
  guihooks.trigger('FernfahrerSound', { name = 'cb' })
end

function M.vice(kind)
  if not R.mode or not S then return end
  if R.vicesFor ~= S then S.vices = S.vices or {}; vices.attach(S.vices); R.vicesFor = S end
  local inv = L.inv()
  if L.INV_MAX[kind] and (inv[kind] or 0) < 1 then
    notify(kind == 'joint' and 'Keine Joints mehr. Manche Tankstellen haben einen Hinterausgang …'
      or ((kind == 'beer' or kind == 'coffee') and 'Kein ' or 'Keine ') .. L.INV_NAME[kind] .. ' mehr – an der nächsten Tankstelle gibt es Nachschub.', 5)
    return
  end
  local ctx = {
    notify = function(t, ttl) notify(t, ttl or 4) end,
    sound = function(name) guihooks.trigger('FernfahrerSound', { name = name }) end,
    scene = function(d) guihooks.trigger('FernfahrerScene', d) end,
  }
  vices.installCam()
  if vices.start(kind, ctx) then
    if L.INV_MAX[kind] then inv[kind] = math.max(0, (inv[kind] or 0) - 1) end
    local v = playerVeh()
    local moving = v and vehSpeed(v) > 3
    if kind == 'beer' and moving then story('beerAtWheel') end
    if kind == 'joint' then story('jointAtWheel') end
    if L.DRINK_FATIGUE[kind] then
      S.fatigue = math.max(0, (S.fatigue or 0) - L.DRINK_FATIGUE[kind])
      notify(string.format('%s Müdigkeit jetzt %d %%.', kind == 'coffee' and '☕' or '🥤', math.floor(S.fatigue * 100 + 0.5)), 4)
    end
    save()
  end
end

function M.onVehicleDestroyed(id)
  if id == R.trailerId then R.trailerId = nil end
  if id == R.truckId then R.truckId = nil end
end

-- (2026-11-07) the mod's own time, part by part: the main loop marks where it is; once a minute the log gets the
-- parts that took the most (ms per frame on average, the worst frame) – "perf:" lines of fernfahrer in beamng.log
local PROF = { acc = {}, max = {}, frames = 0, at = 0, last = 0 }
function L.mkStart(t)
  PROF.last = os.clock()
  PROF.frames = PROF.frames + 1
  if PROF.at == 0 then PROF.at = t end
end
function L.mk(name)
  local c = os.clock()
  local d = c - PROF.last
  PROF.last = c
  PROF.acc[name] = (PROF.acc[name] or 0) + d
  if d > (PROF.max[name] or 0) then PROF.max[name] = d end
end
function L.mkReport(t)
  if t - PROF.at < 60 or PROF.frames == 0 then return end
  local list, total = {}, 0
  for k, v in pairs(PROF.acc) do list[#list + 1] = { k, v }; total = total + v end
  table.sort(list, function(a, b) return a[2] > b[2] end)
  local parts = {}
  for i = 1, math.min(6, #list) do
    local k, v = list[i][1], list[i][2]
    parts[#parts + 1] = string.format('%s %.2f ms (max %.0f)', k, v / PROF.frames * 1000, (PROF.max[k] or 0) * 1000)
  end
  log('I', logTag, string.format('perf: %.2f ms/frame in the mod over %d frames – %s', total / PROF.frames * 1000, PROF.frames, table.concat(parts, ', ')))
  PROF.acc, PROF.max, PROF.frames, PROF.at = {}, {}, 0, t
end

-- (2026-11-08: outside M.onUpdate on purpose – LuaJIT allows a function 60 upvalues, M.onUpdate is at that limit: one
-- more and the whole career no longer loads. New work in the frame goes into L.* functions like these.)
-- (2026-11-08) the music of the loading screens (tools/build_beat.js). AudioGui, the way the navi's voice goes: the game's
-- music slider is often at 0. It runs while the passage screen is up (FernfahrerTravel.vue) and from the moment a career
-- is started; again from the top when it has played through. The radio is quiet meanwhile.
L.LOAD_WAV, L.LOAD_LEN, L.LOAD_VOL = 'art/sound/fernfahrer/ladebeat.wav', 83.4, 0.7
function M.loadMusic(on, ttl)
  R.loadWant = on and true or false
  R.loadWantUntil = (on and ttl) and (now() + ttl) or nil
  pcall(L.loadMusicTick)
end
function L.loadMusicSource()
  return R.loadSrc and scenetree and scenetree.findObjectById and scenetree.findObjectById(R.loadSrc) or nil
end
function L.loadMusicTick()
  local t = now()
  if R.loadWantUntil and t > R.loadWantUntil then R.loadWant, R.loadWantUntil = false, nil end
  local want = R.loadWant and not (S and S.settings and S.settings.loadMusic == false)
  if want then
    -- (not started, played through, or its source – seen before – went with the old level)
    local src = L.loadMusicSource()
    if src then R.loadSeen = true end
    if not R.loadAt or t - R.loadAt >= L.LOAD_LEN or (R.loadSeen and not src) then
      R.loadSeen = false
      if not (Engine and Engine.Audio and Engine.Audio.playOnce) then return end
      local ok, res = pcall(Engine.Audio.playOnce, 'AudioGui', L.LOAD_WAV, { volume = L.LOAD_VOL })
      R.loadAt, R.loadSrc = t, ok and type(res) == 'table' and res.sourceId or nil
      if not ok then log('W', logTag, 'load music: ' .. tostring(res)) end
      log('I', logTag, 'load music: playing, source ' .. tostring(R.loadSrc))
    end
  elseif R.loadAt then
    local src = L.loadMusicSource()
    if src and src.stop then pcall(src.stop, src, 1.2, 1) end
    R.loadAt, R.loadSrc = nil, nil
  end
end
-- (the photo series for the project page, photos.lua: only with its file there and its flag set; not in the released mod)
L.PHOTO_FLAG = '/settings/fernfahrer/fotoserie.json'
function L.photoTick()
  if R.photoGoAt and now() > R.photoGoAt then R.photoGoAt = nil; if not L.autodriveOn() then M.autodriveToggle() end end
  if R.photos then return R.photos.tick() end
  if now() - (R.photoLook or 0) < 5 or R.boot or R.trip then return end
  R.photoLook = now()
  if not R.photoWanted and not FS:fileExists(L.PHOTO_FLAG) then return end
  R.photoWanted = nil
  local ok, ph = pcall(require, 'fernfahrer/photos')
  if not ok or type(ph) ~= 'table' then return end
  R.photos = ph
  R.photoActive = true
  vices.installCam()
  ph.start({
    truck = function() return careerVeh() or playerVeh() end,
    speedKmh = function() local v = careerVeh() or playerVeh(); return v and vehSpeed(v) * 3.6 or 0 end,
    busy = function() return R.cop ~= nil or R.sleep ~= nil or R.trip ~= nil or R.pendingTeleport ~= nil end,
    notify = function(t, ttl) notify(t, ttl) end,
    setOverride = function(f) vices.override = f end,
    cab = function() return L.shotFrame() end,
    office = function(tab) R.officeTab = tab; navigate('fernfahrerOffice') end,
    closeUi = function() R.photoNear = nil; navigate('play') end,
    shopCat = function(c) guihooks.trigger('FernfahrerPhotoUi', { shopCat = c }) end,
    stopAt = function(kind)
      local d = nearestOf(kind)
      local t = d and DEPOT_BY_KEY[kind]
      if not t then return false end
      R.photoNear = { id = d.id, type = d.type, name = d.name, icon = t.icon, typeName = t.name, action = t.action, dist = 0, lat = d.lat, lon = d.lon }
      navigate('fernfahrerStop')
      return true
    end,
    garage = function() if not L.accTruck() then return false end; navigate('fernfahrerGarage'); return true end,
    encStart = function() L.encForce() end,
    encActive = function() return L.enc.active() end,
    encEnd = function() R.encTest = nil; if L.enc.active() then pcall(L.enc.finish) end end,
    vice = function(kind)
      local inv = L.inv()
      if L.INV_MAX[kind] and (inv[kind] or 0) < 1 then inv[kind] = 1 end
      M.vice(kind)
    end,
    viceBusy = function() local okB, rd = pcall(vices.readings); return okB and rd and rd.busy ~= nil and rd.busy ~= false end,
    driverCam = function() local okC, name = pcall(core_camera.getActiveCamName, 0); R.photoCam = okC and name or nil; pcall(core_camera.setByName, 0, 'onboard.driver') end,
    restoreCam = function() if R.photoCam then pcall(core_camera.setByName, 0, R.photoCam); R.photoCam = nil end end,
    driveStart = function()
      if L.autodriveOn() then return false end
      local gps = earthModule('gps')
      if not (gps and gps.setAutodrive) then return false end
      local r = gps.route and gps.route()
      if not (r and r.points and #r.points > 1) then
        local p, best, bd = here(), nil, nil
        for _, d in ipairs(S.depots) do
          if p and (d.type == 'fuel' or d.type == 'logistics') then
            local dd = haversine(p.lat, p.lon, d.lat, d.lon)
            if dd > 6000 and dd < 40000 and (not bd or dd > bd) then best, bd = d, dd end
          end
        end
        if not best then return false end
        navTo(best, best.name)
        R.photoRoute = true
        R.photoGoAt = now() + 8
      else R.photoGoAt = now() + 0.5 end
      return true
    end,
    driveEnd = function()
      if L.autodriveOn() then M.autodriveToggle() end
      if R.photoRoute and not S.job then navClear() end
      R.photoRoute = nil
    end,
    handbook = function(d)
      if d.open then guihooks.trigger('FernfahrerTutorial', { company = S.company and S.company.name, home = S.home and S.home.name, loaner = false, rules = true })
      else guihooks.trigger('FernfahrerPhotoUi', d) end
    end,
    inRing = function() return stops.inside() ~= nil end,
    stopMenu = function() navigate('fernfahrerStop') end,
    stopTab = function(tab) guihooks.trigger('FernfahrerPhotoUi', { stopTab = tab }) end,
    done = function()
      R.photos, R.photoActive, R.photoNear, R.photoGoAt = nil, nil, nil, nil
      S.settings.autoPhotos = false
      pcall(FS.removeFile, FS, L.PHOTO_FLAG)
    end,
  })
end
function L.serviceFrame(dt)
  pcall(L.photoTick)
  local okV, errV = pcall(service.tick, dt)
  if not okV then log('E', logTag, 'service: ' .. tostring(errV)) end
  pcall(L.radioRegionTick, now())
  pcall(L.whereTick, now())
  pcall(L.accTick, now())
  pcall(L.welcomeTick, now())
  pcall(L.rentalTick, now())
  pcall(L.cineTick, now())
  pcall(L.extraTick, now())
end
function L.accidentFrame(dt)
  if S.settings.accidents == false then return end
  local okA, errA = pcall(accidents.update, accidentCtx, dt)
  if not okA then log('E', logTag, 'accidents: ' .. tostring(errA)) end
  L.mk('accidents')
end
function L.roadBackTick(t)
  local d = R.roadBackDo
  if not d or t <= d.at then return end
  R.roadBackDo = nil
  local rv = vehById(d.id)
  if rv then
    pcall(spawn.safeTeleport, rv, d.pos, d.rot, nil, nil, nil, nil, false)
    if d.trailer then R.rehitchAt = t + 1.0 end
  end
end

function M.onUpdate(dtReal, dtSim)
  if R.loadWant or R.loadAt then pcall(L.loadMusicTick) end
  pcall(L.moodTick)
  if not S then return end
  L.tickTasks()
  pcall(L.menuBlurTick, dtReal)
  if not R.mode then return end
  local t = now()
  L.mkStart(t)
  L.mirrorsTick(dtReal)
  L.mk('mirrors')
  do local okC, errC = pcall(L.camTick, dtReal); if not okC then log('W', logTag, 'camera: ' .. tostring(errC)) end end
  L.mk('camera')
  pcall(L.hitCheck)
  pcall(L.slowmoTick)
  L.mk('crash-check')
  if t - (R.routeT or 0) >= 1 then
    R.routeT = t
    pcall(L.routeTick)
    if not R.pinsOn then R.pinsOn = true; pcall(L.installEarthPins) end
  end
  -- a loading screen still asking 12 s after the world was ready (and after its own minimum time): back to the road
  if R.tripDoneSince and t - R.tripDoneSince > 12 and R.tripPollAt and t - R.tripPollAt < 1 and not R.officeOpen and not R.stopOpen then
    R.tripDoneSince = nil
    log('W', logTag, 'loading screen still up after the world was ready: closed')
    navigate(R.tripNext or 'play')
  end
  if R.vicesFor ~= S then S.vices = S.vices or {}; vices.attach(S.vices); R.vicesFor = S; vices.installCam() end
  vices.fxEnabled = S.settings.drugFx ~= false
  vices.tick((dtSim or 0) * tacho.SCALE / 3600)
  pcall(L.fatigueTick, (dtSim or 0) * tacho.SCALE / 3600)
  pcall(L.driversTick, (dtSim or 0) * tacho.SCALE / 3600)
  L.mk('route+vices')
  if R.boot and t - R.boot > C.BOOT_WAIT_S and here() then boot() end
  if R.pendingAdopt and t > R.pendingAdopt then
    R.pendingAdopt = nil
    local adopted = adoptPlayerVehicle()
    -- an own vehicle out of the garage: its kilometres and wear (a used one looks used)
    -- (the condition of the last session first; only without one the used vehicle's wear)
    local restored = adopted and select(2, pcall(L.restoreCond, careerVeh()))
    if adopted and not restored and S.active ~= 'loaner' and S.active ~= 'rental' then pcall(L.applyWear, careerVeh(), activeDef()) end
    -- (a fresh vehicle: its part conditions started now, while it is whole – else there is nothing to read back later)
    if adopted and not restored and (S.active == 'loaner' or S.active == 'rental') then
      local cv = careerVeh()
      if cv then cv:queueLuaCommand('if partCondition and partCondition.ensureConditionsInit then partCondition.ensureConditionsInit(0, 1, 1) ' ..
        'if partCondition.setResetSnapshotKey then partCondition.setResetSnapshotKey(nil) end end') end
    end
    -- (spawned anew – a new session, home, a ferry: the tanks as they were, not filled up by the spawn)
    if L.mirrors then pcall(L.mirrors.forgetVehicle) end  -- (a new vehicle: its own mirror nodes, 2026-11-07)
    R.wearSig, R.wearTrailer = nil, nil
    if adopted then
      R.limiterFor = nil                                   -- (the tank at its career size before the fuel goes back)
      pcall(L.speedRulesTick, t, careerVeh())
      pcall(L.restoreFuelOf, careerVeh(), 1.0)
    end
    if not adopted then
      local v = playerVeh()
      if v then R.truckId = v:getID() end
      -- still in the American loaner in Europe (from before): the European one instead, free, no job running
      local def = activeDef()
      if v and S.active == 'loaner' and not R.loanerSwapped and not S.job and not R.trailerId and def.eu
         and configOf(v:getID()) == 'vehicles/us_semi/t83_sleeper.pc' then
        R.loanerSwapped = true
        core_vehicles.replaceVehicle(def.model, { config = def.config, autoEnterVehicle = true })
        R.truckId, R.fuel = nil, nil
        R.pendingAdopt = now() + 0.5
        notify('Dein Leih-LKW ist jetzt eine europäische Zugmaschine: ' .. def.brand .. ' ' .. def.modelName, 6)
      end
    end
  end
  if R.pendingTeleport and t > R.pendingTeleport then
    R.pendingTeleport = nil
    local core = earthCore()
    local tg = R.teleportTarget or (S.home and { lat = S.home.lat, lon = S.home.lon, name = S.company and S.company.name or 'Firmenhof' })
    local ok = core and core.teleport and tg and core.teleport(tg.lat, tg.lon, tg.name)
    if ok then R.teleportTarget = nil; R.tripArrivedAt = now() end   -- (the loading screen waits for the world there)
    R.teleportTries = ok and 0 or (R.teleportTries or 0) + 1
    if not ok and R.teleportTries < 15 then R.pendingTeleport = t + 2 end
  end
  -- a ferry or a flight: arrived once Earth has the player at the other end
  if R.trip and t - R.trip.t0 > 4 and not R.pendingTeleport then
    local p = here()
    local c = earthCore()
    local st = c and c._state and c._state() or nil
    if p and (dist(p, R.trip.to) or 1e9) < 3000 and not (st and st.pending) then arrive()
    elseif t - R.trip.t0 > 180 then
      notify('Die Ankunft hat nicht geklappt – „Zum Hof“ im Fuhrpark bringt dich zurück.', 8)
      R.trip = nil
    end
  end
  if R.realAIAt and t > R.realAIAt then
    R.realAIAt = nil
    applyRealAI()
    roadEvents.protect(R.truckId)
    roadEvents.protect(R.trailerId)
  end
  -- (a mark of their own: the teleport (Earth loads the world in that call) was counted as the yard's – "yard 4109 ms"
  -- in the log of 2026-11-07 was the trip's teleport)
  L.mk('boot/adopt/teleport')
  -- the yard's buildings: searched, built, kept (a few times a second: its ray scans cost)
  if not R.boot and t - (R.yardT or 0) > 0.25 then
    R.yardT = t
    local okY, errY = pcall(yard.update, yardCtx)
    if not okY then log('E', logTag, 'yard: ' .. tostring(errY)) end
    -- (what the yard waits for, in the log when it changes: "yard not built" alone said nothing, 2026-11-07)
    local st = tostring(yard.status or ''):match('^%a+[%a ]*%a') or ''
    if st ~= R.yardStatusLogged then R.yardStatusLogged = st; log('I', logTag, 'yard status: ' .. tostring(yard.status)) end
  L.mk('yard')
  end
  if not R.boot then pcall(L.townTick, t); pcall(L.odoTick, t); pcall(L.gapHintTick, t); pcall(L.tutTick, t); pcall(L.condTick, t); pcall(L.tourTick, t); pcall(L.weatherTick, t)
    pcall(L.loadTick, t, dtSim); pcall(L.wearTick, t); pcall(L.copTick, t); pcall(L.restCheckTick, t); pcall(L.workTick); pcall(L.encTick, t); pcall(L.trafficGuard, t); pcall(L.cbTick, t); pcall(L.assistTick, t)
    do local okFx, errFx = pcall(L.fxDraw); if not okFx and not R.fxErr then R.fxErr = true; log('W', logTag, 'fx: ' .. tostring(errFx)) end end end
  L.mk('town/gap/tutorial/cond')
  -- the introduction (FernfahrerSzene 'FernfahrerTutorial'): once the flight is over and no menu is up
  if R.tutorialAt and t > R.tutorialAt and L.screenGone(t) and not cinematic.active() and not R.sleep and not R.officeOpen and not R.stopOpen then
    R.tutorialAt = nil
    L.tutSend(t, 0)
  end
  if R.tutAckAt and t > R.tutAckAt then L.tutSend(t, R.tutAckN or 0) end
  if R.sleep then
    local okZ, errZ = pcall(L.sleepTick, t)
    if not okZ then log('E', logTag, 'sleep: ' .. tostring(errZ)); R.sleep = nil; guihooks.trigger('FernfahrerSleep', { on = false }) end
  end
  -- the stop rings at the place nearby; the title card of a new day (after the start, after sleeping)
  if not R.boot then
    local okS, errS = pcall(stops.update, stopsCtx, dtReal or 0)
    if not okS then log('E', logTag, 'stops: ' .. tostring(errS)) end
  L.mk('stops')
  end
  -- (at the yard the title waits for the yard's buildings – up to 25 s – so the camera flight has them: it came
  -- 14 s before the yard was built and there was no flight, 2026-11-03)
  local atYard = S.home and not R.titleText and (dist(here(), S.home) or 1e9) < 400 and not (S.yard and S.yard.failed)
  if R.titleAt and t > R.titleAt and atYard and not yard.built() and t - (R.titleWait or t) < 25 then
    R.titleWait = R.titleWait or t
    R.titleAt = t + 0.5
  end
  if R.titleAt and t > R.titleAt and not R.trip and not R.pendingTeleport and L.titleReady(t) then
    R.titleAt, R.titleWait = nil, nil
    local place = R.near and R.near.action == 'home' and (S.home.name or 'Firmenhof') or nil
    if not place then
      local p = here()
      local okP, pl = pcall(streets.placeAt, p and p.lat, p and p.lon)
      place = okP and pl and (pl.inside and pl.name or ('bei ' .. pl.name)) or nil
    end
    -- the start of a day at the yard: a camera flight over it under the title card (not after sleeping: the fade)
    if not R.titleText and S.settings.intro ~= false then
      local c, ey = yard.center()
      -- (2026-11-09: a first day has to start on the yard, whatever happened while the world loaded)
      do
        local sp0, v0 = yard.parkSpot(), playerVeh()
        if sp0 and v0 and not S.tutorialDone and not S.job and vehSpeed(v0) < 1 and vehPos(v0):distance(sp0.pos) > 14 and vehPos(v0):distance(sp0.pos) < 800 then
          log('I', logTag, string.format('first day: the truck stood %.0f m off the yard, put in front of the hall', vehPos(v0):distance(sp0.pos)))
          pcall(spawn.safeTeleport, v0, sp0.pos, quatFromDir(sp0.dir, vec3(0, 0, 1)))
        end
      end
      local v = playerVeh()
      if c and v and vehPos(v):distance(c) < 500 then
        vices.installCam()
        if cinematic.start(c, ey) then vices.override = cinematic.pose; log('I', logTag, 'day start: camera flight over the yard') end
      else
        log('I', logTag, string.format('day start: no camera flight (yard %s, %s m away)', c and 'built' or 'not built',
          c and v and tostring(math.floor(vehPos(v):distance(c))) or '?'))
      end
    end
    R.titleUntil = t + 7                         -- (the title card's time on screen: no mirrors over it)
    -- a new career's first day: the introduction after the card (and the camera flight)
    if not S.tutorialDone and not R.titleText then R.tutorialAt = t + 6.5 end
    pcall(L.moodSting, 'morgen')
    guihooks.trigger('FernfahrerTitle', { day = weekday(), clock = clockText(), place = place,
      company = S.company and S.company.name or nil, text = R.titleText })
    R.titleText = nil
  end
  if vices.override and not cinematic.active() and not R.photoActive and not L.cine.active() and not R.workShow and not R.garageOn then vices.override = nil end    -- (the flight is over)
  -- a delivery done: its note filed, the settlement card up (not over another screen)
  if R.reportAt and t > R.reportAt and not R.officeOpen and not R.stopOpen then
    R.reportAt = nil
    if R.reportDoc then addDocument(R.reportDoc); R.reportDoc = nil end
    if R.report then navigate('fernfahrerReport') end
  end
  -- after "Zum Hof": the truck in front of the hall, facing the gate (once the yard stands there)
  -- (2026-11-07: as soon as the yard stands and the ground is in – under the loading screen, which waits for this)
  if R.parkAtYard and t > R.parkAtYard.t and not R.pendingTeleport and not R.trailerId and not R.pendingAdopt then pcall(L.parkTick, t) end
  -- after "continue": the vehicle along the road there, the way it was driven
  if R.orient and t > R.orient.t then
    local o = R.orient
    R.orient = nil
    local v = careerVeh() or playerVeh()
    if v and o.hdg then
      local h = math.rad(o.hdg)
      local dir = vec3(math.sin(h), math.cos(h), 0)
      local okR, n1, n2 = pcall(map.findClosestRoad, vehPos(v))
      local nodes = okR and n1 and n2 and map.getMap().nodes
      if nodes and nodes[n1] and nodes[n2] then
        local rd = vec3(nodes[n2].pos) - vec3(nodes[n1].pos)
        rd.z = 0
        if rd:length() > 1 then
          rd = rd:normalized()
          if rd:dot(dir) < 0 then rd = rd * -1 end
          if rd:dot(dir) > 0.7 then dir = rd end
        end
      end
      pcall(spawn.safeTeleport, v, vehPos(v) + vec3(0, 0, 0.3), quatFromDir(dir, vec3(0, 0, 1)))
    end
  end
  if R.ferryTrailerAt and t > R.ferryTrailerAt then
    R.ferryTrailerAt = nil
    if S.job and careerVeh() then spawnTrailer() end   -- (behind the truck; hitched as at the depot)
  end
  if R.restoreFuel and t > R.restoreFuel.t then
    local rf = R.restoreFuel
    R.restoreFuel = nil
    local v = vehById(rf.id)
    if v and rf.cond then pcall(L.condApply, v, rf.cond, rf.keep) end
    if v then
      for _, tank in ipairs(rf.tanks) do
        if tank.name and tank.currentEnergy then core_vehicleBridge.executeAction(v, 'setEnergyStorageEnergy', tank.name, tank.currentEnergy) end
      end
    end
  end
  -- (a new spawn of the career vehicle: its tanks at the share they had)
  if R.restoreRatio and t > R.restoreRatio.t then
    local rr = R.restoreRatio
    R.restoreRatio = nil
    local v = vehById(rr.id)
    if v and core_vehicleBridge then
      core_vehicleBridge.requestValue(v, function(ret)
        local tanks = ret and ret[1]
        for _, tank in ipairs(type(tanks) == 'table' and tanks or {}) do
          if tank.name and tank.maxEnergy and tank.maxEnergy > 0 and FUEL[tank.energyType] then
            core_vehicleBridge.executeAction(v, 'setEnergyStorageEnergy', tank.name, tank.maxEnergy * rr.ratio)
          end
        end
      end, 'energyStorage')
    end
  end
  if R.trafficAt and t > R.trafficAt then
    R.trafficAt = nil
    if not M.startTraffic() then
      R.trafficTries = (R.trafficTries or 0) + 1
      if R.trafficTries < 6 then R.trafficAt = t + 5 end
    else
      R.parkAt = t + 8
    end
  end
  -- the parked cars (after the traffic: one vehicle load after the other)
  if R.parkAt and t > R.parkAt then
    R.parkAt = nil
    local n = PARKED[S.settings.parked or 'auto'] or 10
    local v = playerVeh()
    if n > 0 and v then pcall(parked.start, n, vehPos(v)) end
  end
  patchGasStations()
  L.mk('misc+gas')

  local ok, err = pcall(updateJob, dtSim or 0)
  if not ok then log('E', logTag, 'job update: ' .. tostring(err)) end
  L.mk('job')

  local v = playerVeh()
  if v then R.odo = R.odo + vehSpeed(v) * (dtSim or 0) end
  adaptTraffic(dtReal or 0)
  L.mk('adaptTraffic')
  -- the tachograph runs while driving a truck; road events while driving at all
  -- (a private drive – the tachograph's OUT mode, no job: not recorded, 2026-11-05)
  if S.privateDrive and S.job then S.privateDrive = nil; notify('Fahrtenschreiber: Privatfahrt beendet – der Auftrag wird aufgezeichnet.', 5) end
  if isTruckDriving() and not S.privateDrive then tacho.update(S.tacho, dtSim or 0, vehSpeed(v), notify, story) end
  if v and S.settings.events ~= false then
    local okE, errE = pcall(roadEvents.update, eventCtx, dtSim or 0)
    if not okE then log('E', logTag, 'events: ' .. tostring(errE)) end
  L.mk('tacho+events')
  end
  do
    local okT, errT = pcall(trafficAI.update, trafficCtx, dtSim or 0)
    if not okT then log('E', logTag, 'traffic ai: ' .. tostring(errT)) end
  L.mk('trafficAI')
  end
  L.serviceFrame(dtSim or 0)
  L.accidentFrame(dtSim or 0)
  spots.update(dtReal or 0)
  L.mk('spots')
  -- after roadside help: the job's trailer back on the fifth wheel
  L.roadBackTick(t)
  if R.rehitchAt and t > R.rehitchAt then
    R.rehitchAt = nil
    if R.trailerId and not isCoupled() then
      if not autoHitch() then notify('Bitte den Auflieger wieder ankuppeln (L).', 6) end
    end
  end
  if t - R.limitT >= C.LIMIT_S then
    R.limitT = t
    local okL, lim = pcall(speedLimitAt, v and vehPos(v))
    if okL and lim then R.limit, R.limitSeen = lim, t
    elseif R.limitSeen and t - R.limitSeen > 4 then R.limit = nil end
    R.limitEff = L.ruleLimit(R.limit)
    local okR, errR = pcall(L.speedRulesTick, t, v)
    if not okR then log('W', logTag, 'speed rules: ' .. tostring(errR)) end
  L.mk('limit')
  end
  if t - R.nearT >= C.NEAR_S then
    R.nearT = t
    local okN, errN = pcall(updateNear)
    if not okN then log('E', logTag, 'near: ' .. tostring(errN)) end
  L.mk('near')
  end
  if t - R.fuelT >= C.FUEL_S then R.fuelT = t; pcall(updateFuel) end
  if t - (R.driveT or 0) >= 1 then R.driveT = t; pcall(L.pollDrivetrain) end
  if t - (R.hornT or 0) >= 5 then R.hornT = t; pcall(tameHorns) end
  L.mk('fuel+drive+horns')
  tickClock(dtSim)
  if t - (R.navT or 0) >= 1 then R.navT = t; pcall(L.updateNav) end
  L.mk('nav')
  if t - (R.radioT or 0) >= 0.25 then R.radioT = t; pcall(L.radioTick) end
  L.mk('radio')
  if t - R.marketT >= C.MARKET_S then R.marketT = t; pcall(L.maintainMarket) end
  L.mk('market')
  if t - R.hudT >= C.HUD_S then
    R.hudT = t
    local ok2, h = pcall(hudPayload)
    if ok2 then guihooks.trigger('FernfahrerHud', h) else log('E', logTag, 'hud: ' .. tostring(h)) end
  end
  L.mk('hud')
  if t - R.saveT >= C.SAVE_S then R.saveT = t; save() end
  L.mk('save')
  L.mkReport(t)
end

function M.onExit() save(); restoreSettings() end

function M.onSerialize()
  save()
  return { mode = R.mode, truckId = R.truckId, trailerId = R.trailerId, hitchStep = R.hitchStep, traffic = R.traffic,
    prevGasSetting = R.prevGasSetting, slot = R.slot }
end

function M.onDeserialized(d)
  if type(d) ~= 'table' then return end
  if d.slot then load(d.slot) end                -- (Ctrl+L: the career that was being played)
  R.mode, R.truckId, R.trailerId, R.hitchStep = d.mode or false, d.truckId, d.trailerId, d.hitchStep
  R.traffic, R.prevGasSetting = d.traffic, d.prevGasSetting
end

return M
