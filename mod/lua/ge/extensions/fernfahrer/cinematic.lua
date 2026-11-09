-- Trucks of Earth: the camera flight at the start of a day over the company yard (the day's title card on top).
-- It does not switch the camera: the final pose the game draws is replaced on its way (vices.lua's hook on
-- setCameraPosRotFovNearClipC), so nothing of the game's camera or controls is touched. A sweep around the yard from
-- the road side – high and far to low and near – then a soft blend into the game's own camera. Enter skips it.
-- M.start(center, ey), M.pose(...) (the hook's override), M.skip(), M.active().

local M = {}

M.DURATION = 8.5          -- seconds of the whole flight
M.BLEND = 1.8             -- the last seconds: into the game's camera
M.SWEEP = math.rad(150)   -- around the yard
M.FOV = 55

local F                   -- the flight: { t0, cx, cy, cz, a0, done }

local function smooth(k) k = math.max(0, math.min(1, k)); return k * k * (3 - 2 * k) end
local function lerp(a, b, k) return a + (b - a) * k end

-- center: the yard's middle on its concrete (vec3); ey: the yard's depth axis (from the road into the yard)
function M.start(center, ey)
  if not center then return false end
  -- (start on the road side, a little to the left, and sweep round)
  local a0 = math.atan2(-ey.y, -ey.x) - M.SWEEP * 0.45
  F = { t0 = os.clock(), cx = center.x, cy = center.y, cz = center.z, a0 = a0 }
  return true
end

function M.active()
  -- (F.done comes from the camera hook: without a hook running the flight must still end, the introduction waits for it)
  if F and not F.done and os.clock() - F.t0 > M.DURATION + 3 then F.done = true end
  return F ~= nil and not F.done
end

-- Enter: straight into the blend
function M.skip()
  if not F or F.done then return end
  local t = os.clock() - F.t0
  if t < M.DURATION - M.BLEND then F.t0 = os.clock() - (M.DURATION - M.BLEND) end
end

-- the flight's own pose at time t (position and look target)
local function flightPose(t)
  local k = smooth(t / (M.DURATION - M.BLEND * 0.5))
  local a = F.a0 + M.SWEEP * k
  local r = lerp(70, 30, k)
  local h = lerp(34, 9, k)
  local px, py, pz = F.cx + math.cos(a) * r, F.cy + math.sin(a) * r, F.cz + h
  local look = vec3(F.cx - px, F.cy - py, (F.cz + 3) - pz)
  return px, py, pz, look
end

-- the override: the game's pose in, the pose to draw out (nil: the game's own, the flight is over)
function M.pose(x, y, z, qx, qy, qz, qw, fov)
  if not F or F.done then return nil end
  local t = os.clock() - F.t0
  if t >= M.DURATION then F.done = true; return nil end
  local px, py, pz, look = flightPose(t)
  local q = quatFromDir(look:normalized(), vec3(0, 0, 1))
  local fx, fy, fz, fw, ffov = q.x, q.y, q.z, q.w, M.FOV
  -- the last seconds: blended into the game's camera (position and rotation, the shorter way round)
  local b = smooth((t - (M.DURATION - M.BLEND)) / M.BLEND)
  if b > 0 then
    if fx * qx + fy * qy + fz * qz + fw * qw < 0 then fx, fy, fz, fw = -fx, -fy, -fz, -fw end
    px, py, pz = lerp(px, x, b), lerp(py, y, b), lerp(pz, z, b)
    fx, fy, fz, fw = lerp(fx, qx, b), lerp(fy, qy, b), lerp(fz, qz, b), lerp(fw, qw, b)
    local l = math.sqrt(fx * fx + fy * fy + fz * fz + fw * fw)
    fx, fy, fz, fw = fx / l, fy / l, fz / l, fw / l
    ffov = lerp(M.FOV, fov or M.FOV, b)
  end
  return px, py, pz, fx, fy, fz, fw, ffov
end

function M.reset() F = nil end

return M
