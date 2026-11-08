// Offline check of fernfahrer/cinematic.lua: the flight sampled over its time – distance and height to the yard,
// a smooth path (no jumps), the hand-back ending exactly on the game's camera, skip.
// node tools/sim_cinematic.js <cinematic.lua> <fengari dir>
const fs = require('fs'), path = require('path')
const [file, fdir] = process.argv.slice(2)
const { lua, lauxlib, lualib, to_luastring } = require(path.join(fdir, 'node_modules', 'fengari'))
const src = fs.readFileSync(file, 'utf8')
const code = `
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local V = {} V.__index = V
function vec3(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
function V:length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function V:normalized() local l = self:length(); return vec3(self.x / l, self.y / l, self.z / l) end
-- a quaternion whose +y looks along d (yaw / pitch, as BeamNG's quatFromDir for a camera)
function quatFromDir(d)
  local yaw = math.atan2(-d.x, d.y); local pitch = math.asin(math.max(-1, math.min(1, d.z)))
  local cy, sy, cp, sp = math.cos(yaw / 2), math.sin(yaw / 2), math.cos(pitch / 2), math.sin(pitch / 2)
  return { x = cy * sp, y = -sy * sp * 0, z = sy * cp, w = cy * cp }
end
local T = 0
os.clock = function() return T end
local M = (function() ${src} end)()
local out = {}
M.start(vec3(100, 200, 50), vec3(0, 1, 0))
-- the game's camera: behind the truck, 6 m up
local gx, gy, gz, gq = 100, 170, 56, { 0, 0, 0, 1 }
local last, maxJump, minD, maxD, minH, maxH = nil, 0, 1e9, 0, 1e9, -1e9
local t = 0
while M.active() and t < 20 do
  T = t
  local x, y, z, qx, qy, qz, qw, fov = M.pose(gx, gy, gz, gq[1], gq[2], gq[3], gq[4], 70)
  if x then
    if x ~= x or qw ~= qw then out[#out + 1] = 'NaN at ' .. t end
    local d = math.sqrt((x - 100) ^ 2 + (y - 200) ^ 2)
    if t < M.DURATION - M.BLEND then minD, maxD = math.min(minD, d), math.max(maxD, d); minH, maxH = math.min(minH, z - 50), math.max(maxH, z - 50) end
    if last then maxJump = math.max(maxJump, math.sqrt((x - last[1]) ^ 2 + (y - last[2]) ^ 2 + (z - last[3]) ^ 2)) end
    last = { x, y, z, qw, fov }
  end
  t = t + 1 / 60
end
out[#out + 1] = string.format('flight %.1f s: %.0f..%.0f m from the yard, %.0f..%.0f m up; biggest step per frame %.2f m', t, minD, maxD, minH, maxH, maxJump)
out[#out + 1] = string.format('last frame: %.2f, %.2f, %.2f (the game camera: %d, %d, %d), fov %.1f → game camera taken over: %s',
  last[1], last[2], last[3], gx, gy, gz, last[5], tostring(math.abs(last[1] - gx) < 0.05 and math.abs(last[3] - gz) < 0.05))
-- skip: Enter after 2 s → over within the blend time
M.start(vec3(100, 200, 50), vec3(0, 1, 0)); T = 2; M.skip()
local n = 0
while M.active() and n < 2000 do T = T + 1 / 60; M.pose(gx, gy, gz, 0, 0, 0, 1, 70); n = n + 1 end
out[#out + 1] = string.format('skipped after 2 s: over %.1f s later', n / 60)
return table.concat(out, '\\n')
`
const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L)
if (lauxlib.luaL_loadstring(L, to_luastring(code)) !== 0 || lua.lua_pcall(L, 0, 1, 0) !== 0) { console.log('ERR', lua.lua_tojsstring(L, -1)); process.exit(1) }
console.log(lua.lua_tojsstring(L, -1))
