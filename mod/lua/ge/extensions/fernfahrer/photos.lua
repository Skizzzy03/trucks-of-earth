-- Trucks of Earth: the automatic photo mode for the project page (settings: "Automatik-Fotomodus"). Goes through everything by itself: the office's pages, a part of the online shop (not all of
-- it, some things should stay a surprise), the handbook, the menus of a fuel station, a workshop and an underground place, the cab workshop, a knock at the door, then the truck under way from near
-- and far, from inside, and with a cigarette and a beer at the wheel. All into screenshots/trucks_of_earth_github. Written as one script: a coroutine, resumed every frame.
local M = {}
M.DIR = 'screenshots/trucks_of_earth_github/'
M.GAP_S = 5

-- f, r, u: where the camera stands, seen from the truck (metres forward, right, up); at: metres forward the look goes to; fov
local POSE = {
  rear_left = { -20, -8, 3.4, 0, 52 }, front_right = { 16, 7, 1.7, 0, 52 }, side = { -2, 13, 2.2, -2, 52 }, high_rear = { -34, 0, 13, 4, 52 },
  front_low = { 11, -3.5, 0.9, -2, 52 }, rear_right = { -24, 9, 2.4, 0, 52 }, chase = { -19, 0, 5.5, 8, 52 },
  fern_vorne = { 62, -14, 4, -3, 24 }, fern_seite = { 2, 48, 5, -3, 26 }, fern_oben = { -42, 26, 30, 4, 34 }, fern_hinten = { -70, 12, 7, 0, 24 }, fern_drohne = { 45, 10, 24, -2, 30 },
}
local function cabPose(fn) return { cab = fn } end
local CAB = {
  scheibe = cabPose(function(L, m) return m + L.F * 3.6 + L.U * 0.15, m + L.F * 0.9 - L.U * 0.16, 40 end),
  fahrersitz = cabPose(function(L, m) return L.eye, m + L.F * 0.9 - L.U * 0.3, 72 end),
  beifahrer = cabPose(function(L) return L.eye + L.R * (1.12 * L.flip), L.eye + L.F * 0.9 - L.U * 0.3 + L.R * (0.2 * L.flip), 70 end),
  decke = cabPose(function(L, m) return m - L.F * 0.3 + L.U * 0.42, m + L.F * 0.9 - L.U * 0.35, 74 end),
}
local DRIVE = {
  { 'rear_left' }, { 'fern_vorne' }, { 'front_right' }, { 'chase', ui = true }, { 'fern_seite' }, { 'side' }, { false, ui = true }, { 'fern_oben' }, { 'high_rear' }, { 'front_low' },
  { 'fern_hinten' }, { 'rear_right' }, { 'scheibe' }, { 'fahrersitz' }, { 'beifahrer' }, { 'decke' }, { 'fern_drohne' }, { 'chase', ui = true },
}
local TABS = { 'home', 'messages', 'market', 'map', 'travel', 'fleet', 'dealer', 'bank', 'club', 'docs', 'stats', 'school', 'settings' }
local STOPS = { { 'fuel', { 'fuel', 'shop', 'rest' } }, { 'workshop', { 'work' } }, { 'underground', { 'shady' } } }
local CARDS = { 0, 2, 11, 20 }

local api, st, co
local n = 0

local function setCef(on)
  local v = rawget(_G, 'ui_visibility')
  if v and v.setCef then pcall(v.setCef, on) end
end
local function shoot(name)
  n = n + 1
  local file = string.format('%s%02d_%s', M.DIR, n, name)
  pcall(createScreenshot2, { filename = file, writeJPG = true, superSampling = 1, tiles = 1, overlap = 0, rescaleFactor = 1,
    upload = false, bufferType = 'color', jobType = 'full', objectTypeWhitelistMask = 0, objectTypeBlacklistMask = 0,
    shadowCasterObjectTypeWhitelistMask = 0, shadowCasterObjectTypeBlacklistMask = 0 })
  log('I', 'fernfahrer', 'photo ' .. file)
end

-- the camera of the shot: the hook of vices.lua hands the game's pose in and draws what comes back
function M.pose(x, y, z, qx, qy, qz, qw, fov)
  local p = st and st.pose
  if not p then return nil end
  if p.cab then
    local L = api.cab()
    if not L then return nil end
    local m = L.eye + L.R * (0.55 * L.flip)
    local e, look, f = p.cab(L, m)
    local q = quatFromDir((look - e):normalized(), L.U)
    return e.x, e.y, e.z, q.x, q.y, q.z, q.w, f
  end
  local v = api.truck()
  if not v then return nil end
  local c = vec3(v:getPosition())
  local fw = vec3(v:getDirectionVector()); fw.z = 0
  if fw:length() < 0.1 then return nil end
  fw = fw:normalized()
  local r = vec3(fw.y, -fw.x, 0)
  local e = c + fw * p[1] + r * p[2] + vec3(0, 0, p[3])
  local top = vec3(e.x, e.y, e.z + 40)
  local d = castRayStatic(top, vec3(0, 0, -1), 120)
  if d and d < 120 and e.z < top.z - d + 1.1 then e.z = top.z - d + 1.1 end
  local target = c + fw * p[4] + vec3(0, 0, 1.9)
  local q = quatFromDir((target - e):normalized(), vec3(0, 0, 1))
  return e.x, e.y, e.z, q.x, q.y, q.z, q.w, p[5]
end

local function sleep(s)
  local e = os.clock() + s
  while os.clock() < e do coroutine.yield() end
end
local function waitFor(fn, s)
  local e = os.clock() + s
  while os.clock() < e do
    if fn() then return true end
    coroutine.yield()
  end
  return false
end
local function shot(name, pose, ui)
  waitFor(function() return not api.busy() end, 60)
  st.pose = pose
  api.setOverride(pose and M.pose or nil)
  if not ui then setCef(false) end
  sleep(pose and 1.0 or 0.5)
  shoot(name)
  sleep(1.2)
  st.pose = nil
  api.setOverride(nil)
  setCef(true)
end

local function script()
  api.closeUi()
  sleep(4)
  for _, tab in ipairs(TABS) do
    api.closeUi(); sleep(1.2); api.office(tab)
    sleep(tab == 'map' and 5 or 3.2)
    shot('buero_' .. tab, nil, true)
  end
  -- the online shop: a look at two shelves, the rest is for finding out
  api.closeUi(); sleep(1.2); api.office('shop')
  sleep(3.2)
  api.shopCat('hang'); sleep(1.2); shot('shop_am_spiegel', nil, true)
  api.shopCat('gadget'); sleep(1.2); shot('shop_geraete', nil, true)
  api.closeUi()
  sleep(2)
  api.handbook({ open = true })
  sleep(2)
  for i, c in ipairs(CARDS) do api.handbook({ i = c }); sleep(0.8); shot('handbuch_' .. i, nil, true) end
  api.handbook({ close = true })
  sleep(1.5)
  for _, s in ipairs(STOPS) do
    if api.stopAt(s[1]) then
      sleep(3.2)
      for _, tab in ipairs(s[2]) do api.stopTab(tab); sleep(1.2); shot('halt_' .. s[1] .. '_' .. tab, nil, true) end
      api.closeUi()
      sleep(2)
    end
  end
  if api.garage() then sleep(3.5); shot('kabine_einrichten', nil, true); api.closeUi(); sleep(2.5) end
  -- a knock at the door: only standing
  if api.speedKmh() < 2 then
    api.encStart()
    if waitFor(api.encActive, 25) then
      sleep(9)
      shot('begegnung', nil, true)
    end
    api.encEnd()
    sleep(2)
  end
  -- under way
  local ours = api.driveStart()
  sleep(ours and 16 or 4)
  waitFor(function() return api.speedKmh() > 25 end, 45)
  for _, s in ipairs(DRIVE) do
    local pose = s[1] and (POSE[s[1]] or CAB[s[1]]) or nil
    shot(s[1] and (s[1] .. (s.ui and '_hud' or '')) or 'cockpit_hud', pose, s.ui)
    sleep(M.GAP_S)
  end
  -- a cigarette and a beer at the wheel
  api.driverCam()
  sleep(2)
  for _, kind in ipairs({ 'cigarette', 'beer' }) do
    api.vice(kind)
    sleep(3)
    shot(kind .. '_1', nil, false)
    sleep(2.2)
    shot(kind .. '_2', nil, true)
    waitFor(function() return not api.viceBusy() end, 30)
    sleep(2)
  end
  api.restoreCam()
  if ours then api.driveEnd() end
end

function M.start(a)
  api = a
  n = 0
  if not FS:directoryExists(M.DIR) then FS:directoryCreate(M.DIR) end
  st = {}
  co = coroutine.create(script)
  a.notify('📸 Automatik-Fotomodus läuft. Er macht alles allein, Strg+Umschalt+C bricht ab.', 6)
end
function M.active() return st ~= nil end

local function finish(text)
  if not st then return end
  st, co = nil, nil
  api.setOverride(nil)
  setCef(true)
  pcall(api.closeUi)
  api.done()
  api.notify(text, 8)
end

function M.tick()
  if not st or not co then return end
  local ok, err = coroutine.resume(co)
  if not ok then log('E', 'fernfahrer', 'photo series: ' .. tostring(err)); finish('📸 Automatik-Fotomodus abgebrochen, ein Schritt ging schief.')
  elseif coroutine.status(co) == 'dead' then finish(string.format('📸 Fertig: %d Fotos in screenshots/trucks_of_earth_github.', n)) end
end
function M.stop() finish('📸 Automatik-Fotomodus beendet.') end
function M.reset() if st then st, co = nil, nil; if api then api.setOverride(nil) end setCef(true) end end

return M
