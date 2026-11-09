-- Trucks of Earth: pictures. M.start: while the autodrive drives, one photo after the other of the cab and what has been fitted in it, until it is stopped: through the windscreen from in front,
-- from the sides, from inside, close to each piece. M.single: one photo of the truck from outside, without the HUD, at a viewpoint. All into the game's screenshot folder, so the picture frame
-- in the cab can show them. Like the cinematic mode this only replaces the pose the game draws (vices.lua's hook).
local M = {}
M.DIR = 'screenshots/trucks_of_earth/'
M.SETTLE_S, M.HOLD_S = 1.0, 1.6    -- (the picture has to be still for the anti-aliasing; then a moment before the next)

local S
local n = 0

local function rnd(a, b) return a + math.random() * (b - a) end
local function shoot(name)
  if not FS:directoryExists(M.DIR) then FS:directoryCreate(M.DIR) end
  n = n + 1
  local file = string.format('%s%s_%s_%03d', M.DIR, name, os.date('%Y-%m-%d_%H-%M-%S'), n)
  pcall(createScreenshot2, { filename = file, writeJPG = true, superSampling = 1, tiles = 1, overlap = 0, rescaleFactor = 1, upload = false, bufferType = 'color', jobType = 'full',
    objectTypeWhitelistMask = 0, objectTypeBlacklistMask = 0, shadowCasterObjectTypeWhitelistMask = 0, shadowCasterObjectTypeBlacklistMask = 0 })
end

-- the shots: where the camera stands and what it looks at, against the cab (L: eye, F, R, U, flip of accessories.lua); small changes each time round
local function front(f, r, u, fov)
  local jf, jr, ju = rnd(-0.3, 0.3), rnd(-0.3, 0.3), rnd(-0.15, 0.15)
  return function(L, m)
    return m + L.F * (f + jf) + L.R * (r + jr) + L.U * (u + ju), m + L.F * 0.9 - L.U * 0.16, fov
  end
end
local function newBag()
  local bag = {}
  for _ = 1, 2 do
    bag[#bag + 1] = front(4.4, 0, 0.1, 38); bag[#bag + 1] = front(2.7, 0, 0.3, 44); bag[#bag + 1] = front(3.5, -3, 0.2, 36)
    bag[#bag + 1] = front(3.5, 3, 0.2, 36); bag[#bag + 1] = front(3.2, 0, -1.5, 40); bag[#bag + 1] = front(2.7, 0, 2.3, 40)
  end
  -- (from far off: the whole truck in its landscape; a tree in the way and the shot is skipped)
  for _ = 1, 2 do
    local a, b, c = rnd(-12, 12), rnd(1, 7), rnd(-1, 1) >= 0 and 1 or -1
    bag[#bag + 1] = function(L, m) return m + L.F * 48 + L.R * a + L.U * b, m + L.F * 0.5, 24 end
    bag[#bag + 1] = function(L, m) return m + L.R * (38 * c) + L.F * 6 + L.U * (b + 1), m - L.F * 3, 26 end
    bag[#bag + 1] = function(L, m) return m - L.F * 32 + L.R * (20 * c) + L.U * 24, m - L.F * 2, 36 end
    bag[#bag + 1] = function(L, m) return m + L.F * 36 + L.R * (9 * c) + L.U * 20, m, 30 end
    bag[#bag + 1] = function(L, m) return m - L.F * 52 + L.R * (a * 0.8) + L.U * (b + 2), m - L.F * 4, 24 end
  end
  bag[#bag + 1] = function(L) return L.eye - L.R * (3.3 * L.flip) + L.F * 0.3 + L.U * 0.1, L.eye + L.R * (0.8 * L.flip) + L.F * 0.6, 38 end
  bag[#bag + 1] = function(L, m) return m + L.R * (3.9 * L.flip) + L.F * 0.3 + L.U * 0.1, m + L.F * 0.5 - L.R * (0.3 * L.flip), 38 end
  -- from inside: the driver's seat, the passenger's, from the dashboard back, from up by the roof
  bag[#bag + 1] = function(L, m) return L.eye, m + L.F * 0.9 - L.U * 0.35, 72 end
  bag[#bag + 1] = function(L) return L.eye + L.R * (1.12 * L.flip), L.eye + L.F * 0.9 - L.U * 0.3 + L.R * (0.2 * L.flip), 70 end
  bag[#bag + 1] = function(L, m) return m + L.F * 0.72 + L.U * 0.02, L.eye - L.F * 0.2, 78 end
  bag[#bag + 1] = function(L, m) return m - L.F * 0.3 + L.U * 0.42, m + L.F * 0.9 - L.U * 0.35, 74 end
  -- close to each piece: from the cab, and from the windscreen side
  for _, s in ipairs(S.spots()) do
    local jr, ju = rnd(-0.16, 0.16), rnd(0.06, 0.18)
    bag[#bag + 1] = function(L) local p = S.spot(s); if p then return p - L.F * 0.38 + L.R * jr + L.U * ju, p + L.U * 0.05, 46 end end
    bag[#bag + 1] = function(L) local p = S.spot(s); if p then return p + L.F * 0.26 + L.R * jr + L.U * 0.08, p + L.U * 0.05, 52 end end
  end
  for i = #bag, 2, -1 do local j = math.random(i); bag[i], bag[j] = bag[j], bag[i] end
  return bag
end

function M.active() return S ~= nil end
-- api: last() (the cab's frame), spots(), spot(id), veh(), setOverride(fn or nil), setCef(on)
function M.start(api)
  S = api
  S.taken = 0
  S.bag = newBag()
  S.setCef(false)
  S.setOverride(M.pose)
end
-- (one picture from outside, of the truck in the place it stands in)
function M.once(api)
  S = api
  S.taken, S.isOnce = 0, true
  S.bag = { function(L) return L.eye + L.F * 15 + L.R * 7 - L.U * 0.9, L.eye - L.F * 2 - L.U * 0.7, 42 end }
  S.setCef(false)
  S.setOverride(M.pose)
end
function M.isOnce() return S ~= nil and S.isOnce == true end
function M.stop()
  if not S then return end
  local a = S
  S = nil
  a.setOverride(nil)
  a.setCef(true)
  return a.taken
end

function M.pose(x, y, z, qx, qy, qz, qw, fov)
  if not S or not S.shot then return nil end
  local L = S.last()
  if not L then return nil end
  local m = L.eye + L.R * (0.55 * L.flip)
  local e, look, f = S.shot(L, m)
  if not e then return nil end
  -- (outside: never under the ground)
  local inCab = (e - m):length() < 1.8
  if not inCab then
    local top = vec3(e.x, e.y, math.max(e.z, m.z) + 3)
    local g = castRayStatic(top, vec3(0, 0, -1), 40)
    if g and g < 40 and e.z < top.z - g + 0.5 then e.z = top.z - g + 0.5 end
  end
  S.lastE, S.lastLook = e, look
  local q = quatFromDir((look - e):normalized(), inCab and L.U or vec3(0, 0, 1))
  return e.x, e.y, e.z, q.x, q.y, q.z, q.w, f
end

function M.tick(t)
  if not S then return end
  if not S.shot then
    if #S.bag == 0 then S.bag = newBag() end
    S.shot = table.remove(S.bag)
    S.t0, S.done, S.checked = t, false, false
    return
  end
  -- (something between the camera and the truck: the next one)
  if not S.done and not S.isOnce and not S.checked and t - S.t0 >= 0.3 and S.lastE then
    S.checked = true
    local to = S.lastLook - S.lastE
    local dist = to:length()
    if dist > 12 then
      local hit = castRayStatic(S.lastE, to:normalized(), dist - 8)
      if hit and hit < dist - 8 then S.shot = nil; return end
    end
  end
  if not S.done and t - S.t0 >= M.SETTLE_S then S.done = true; shoot(S.isOnce and 'aussicht' or 'kabine'); S.taken = S.taken + 1 end
  if S.done and S.isOnce and t - S.t0 >= M.SETTLE_S + 0.6 then local a = S; M.stop(); a.onceDone(); return end
  if S.done and t - S.t0 >= M.SETTLE_S + M.HOLD_S then S.shot = nil end
end

return M
