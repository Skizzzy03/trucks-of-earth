-- Trucks of Earth: the cinematic mode while the autodrive drives: camera shots from outside, a new one every few seconds – behind,
-- beside, a fly-by from the verge, from above, from in front, at the wheels, around the truck. Like cinematic.lua it only replaces the
-- pose the game draws (vices.lua's hook), nothing of the game's camera or the controls is touched. A view blocked by trees or a
-- house ends its shot early.
-- M.start(getVehicle, hasTrailer), M.stop(), M.active(), M.pose(...) (the hook's override).

local M = {}

local S
local ORDER = { 'chase', 'flyby', 'side', 'drone', 'front', 'flyby', 'wheel', 'orbit' }

local function rnd(a, b) return a + math.random() * (b - a) end
local function lerp(a, b, k) return a + (b - a) * k end
local function ease(k) k = math.max(0, math.min(1, k)); return k * k * (3 - 2 * k) end

local function newShot(t, c, f, r, speed)
  local name
  if speed < 4 then name = math.random() < 0.5 and 'orbit' or 'chase'
  else
    S.bag = S.bag and #S.bag > 0 and S.bag or nil
    if not S.bag then
      S.bag = {}
      for i, v in ipairs(ORDER) do S.bag[i] = v end
      for i = #S.bag, 2, -1 do local j = math.random(i); S.bag[i], S.bag[j] = S.bag[j], S.bag[i] end
    end
    name = table.remove(S.bag)
    if name == S.lastName and #S.bag > 0 then name = table.remove(S.bag) end
  end
  S.lastName = name
  local dur = rnd(8, 12)
  local shot = { name = name, t0 = t, side = math.random() < 0.5 and 1 or -1, a0 = rnd(0, math.pi * 2), occl = 0, checkAt = t + 0.5 }
  if name == 'flyby' then
    dur = math.max(6, math.min(12, 110 / math.max(5, speed)))
    -- (a place on the verge, on the right of the road, the truck comes past it about the middle of the shot)
    shot.fixed = c + f * (speed * dur * 0.55 + 12) + r * rnd(8, 12)
    shot.fixed.z = c.z + rnd(1.2, 2.6)
  end
  shot.t1 = t + dur
  shot.dur = dur
  return shot
end

-- the camera of a shot: position, what it looks at, field of view
local function place(s, k, c, f, r, mid, tr)
  local up = vec3(0, 0, 1)
  if s.name == 'chase' then
    return c - f * (tr and 30 or 15) + r * math.sin(k * 3 + s.a0) * 3 + up * 6, mid + f * 8, 50
  elseif s.name == 'flyby' then
    return vec3(s.fixed), mid, 34
  elseif s.name == 'side' then
    return c + r * (s.side * (11 + 2 * math.sin(k * 2))) + f * lerp(10, -22, ease(k)) + up * 2.4, mid, 44
  elseif s.name == 'drone' then
    return c - f * lerp(50, 16, ease(k)) + r * (s.side * 9) + up * lerp(32, 15, ease(k)), c + f * 12, 48
  elseif s.name == 'front' then
    return c + f * lerp(15, 21, k) + r * (s.side * 3) + up * 1.5, c + up * 2.1, 42
  elseif s.name == 'wheel' then
    return c + r * (s.side * 3.4) + f * lerp(2.5, -1, k) + up * 0.8, c - f * (tr and 11 or 5) + up * 1.1, 58
  end
  local a = s.a0 + k * 1.7                                      -- (orbit)
  return c + (f * math.cos(a) + r * math.sin(a)) * 21 + up * 5, mid, 44
end

function M.start(getVehicle, hasTrailer)
  S = { veh = getVehicle, trailer = hasTrailer, last = os.clock(), lift = 0 }
end
function M.stop() S = nil end
function M.active() return S ~= nil end

function M.pose()
  if not S then return nil end
  local v = S.veh()
  if not v then return nil end
  local t = os.clock()
  local dt = math.min(0.1, t - S.last)
  S.last = t
  local c = vec3(v:getPosition())
  local d = vec3(v:getDirectionVector())
  d.z = 0
  if d:length() < 0.1 then return nil end
  d = d:normalized()
  -- (the heading a little behind the truck's: the camera does not shake with the road)
  S.dir = S.dir and (S.dir + (d - S.dir) * (1 - math.exp(-dt / 0.9))):normalized() or d
  local f = S.dir
  local r = vec3(f.y, -f.x, 0)
  local tr = S.trailer()
  local mid = c - f * (tr and 6 or 0) + vec3(0, 0, 2)
  local speed = vec3(v:getVelocity()):length()
  if not S.shot or t >= S.shot.t1 then S.shot = newShot(t, c, f, r, speed) end
  local s = S.shot
  local k = (t - s.t0) / s.dur
  local e, look, fov = place(s, k, c, f, r, mid, tr)
  -- never under the ground (looked for from just above: not onto the tree tops)
  local top = vec3(e.x, e.y, math.max(e.z, c.z) + 3)
  local g = castRayStatic(top, vec3(0, 0, -1), 60)
  local need = (g and g < 60) and math.max(0, top.z - g + 0.7 - e.z) or 0
  S.lift = lerp(S.lift, need, 1 - math.exp(-dt / 0.15))
  e.z = e.z + S.lift
  -- a view blocked for a moment: the next shot
  if t >= s.checkAt then
    s.checkAt = t + 0.25
    local to = look - e
    local dist = to:length()
    local hit = dist > 4 and castRayStatic(e, to:normalized(), dist - 3) or nil
    if hit and hit < dist - 3 then s.occl = s.occl + 0.25 else s.occl = 0 end
    if s.occl >= 0.75 then s.t1 = t end
  end
  local q = quatFromDir((look - e):normalized(), vec3(0, 0, 1))
  return e.x, e.y, e.z, q.x, q.y, q.z, q.w, fov
end

return M
