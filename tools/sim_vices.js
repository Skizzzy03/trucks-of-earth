// Offline check of fernfahrer/vices.lua: the scenes run frame by frame against a mock camera and mock objects
// (positions in front of the camera, sounds in order, everything deleted at the end), then the blood alcohol / THC
// over game time. node tools/sim_vices.js <vices.lua> <fengari dir>
const fs = require('fs'), path = require('path')
const [file, fdir] = process.argv.slice(2)
const { lua, lauxlib, lualib, to_luastring } = require(path.join(fdir, 'node_modules', 'fengari'))
const src = fs.readFileSync(file, 'utf8')
const code = `
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local V = {} V.__index = V
function vec3(x, y, z) if type(x) == 'table' then return setmetatable({ x = x.x, y = x.y, z = x.z }, V) end return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
V.__add = function(a, b) return vec3(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return vec3(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__mul = function(a, b) if type(a) == 'number' then a, b = b, a end return vec3(a.x * b, a.y * b, a.z * b) end
function V:dot(b) return self.x * b.x + self.y * b.y + self.z * b.z end
function V:cross(b) return vec3(self.y * b.z - self.z * b.y, self.z * b.x - self.x * b.z, self.x * b.y - self.y * b.x) end
function V:length() return math.sqrt(self:dot(self)) end
function V:normalized() local l = self:length(); return vec3(self.x / l, self.y / l, self.z / l) end
-- the camera: at (0, 0, 1.8) looking north (+y), up +z; its quat is the identity
local Q = {} Q.__index = Q
function quat(q) return setmetatable({ x = 0, y = 0, z = 0, w = 1 }, Q) end
Q.__mul = function(q, v) return vec3(v.x, v.y, v.z) end
function quatFromDir(f, u) return { x = f.x, y = f.y, z = f.z, w = 1, up = u } end
core_camera = { getPosition = function() return vec3(0, 0, 1.8) end, getQuat = function() return quat() end,
  getActiveCamName = function() return 'driver' end }
local objs, live = {}, 0
function createObject(kind)
  live = live + 1
  local o = { kind = kind, fields = {} }
  function o:setField(k, _, v) self.fields[k] = v end
  function o:registerObject(n) self.name = n; objs[#objs + 1] = self end
  function o:setPosRot(x, y, z, qx, qy, qz, qw) self.pos = { x, y, z }; self.dir = { qx, qy, qz } end
  function o:setPosition(p) self.pos = { p.x, p.y, p.z } end
  function o:delete() self.deleted = true; live = live - 1 end
  return o
end
local M = (function() ${src} end)()
local S = {}
M.attach(S)
local out, sounds = {}, {}
local ctx = { notify = function(t) out[#out + 1] = 'notify: ' .. t end, sound = function(n) sounds[#sounds + 1] = n end }
local function run(kind)
  sounds = {}
  assert(M.start(kind, ctx), 'start ' .. kind)
  assert(not M.start('beer', ctx), 'second start refused')
  local t, frames, maxF, minF, near, far = 0, 0, -1, 9, 0, 0
  local flameSeen = false
  while M.busy() and t < 200 do
    M.render(1 / 60); t = t + 1 / 60; frames = frames + 1
    for _, o in ipairs(objs) do
      if not o.deleted and o.pos and o.kind == 'TSStatic' then
        local f = o.pos[2]
        if f > maxF then maxF = f end
        if f < minF then minF = f end
        if o.fields.shapeName:find('flame') then flameSeen = true end
      end
    end
  end
  out[#out + 1] = string.format('%-9s %5.1f s, %d frames, forward %.2f..%.2f m, sounds: %s%s, objects left: %d',
    kind, t, frames, minF, maxF, table.concat(sounds, ' '), flameSeen and ', flame shown' or '', live)
end
run('beer'); run('cigarette'); run('joint')
out[#out + 1] = string.format('after: %.2f permille in the stomach, thc %.1f ng/ml', S.stomach, S.thc)
-- the body: 3 beers and the joint, then the game hours pass
S.stomach = S.stomach + 2 * M.BEER_BAC
local h = 0
for _, step in ipairs({ 0.25, 0.25, 0.5, 1, 1, 1, 2, 2, 4 }) do
  for i = 1, 60 do M.tick(step / 60) end
  h = h + step
  local r = M.readings()
  out[#out + 1] = string.format('  +%4.2f h: %.2f permille, THC %.1f ng/ml', h, r.bac, r.thc)
end
return table.concat(out, '\\n')
`
const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L)
if (lauxlib.luaL_loadstring(L, to_luastring(code)) !== 0) { console.log('load', lua.lua_tojsstring(L, -1)); process.exit(1) }
if (lua.lua_pcall(L, 0, 1, 0) !== 0) { console.log('run', lua.lua_tojsstring(L, -1)); process.exit(1) }
console.log(lua.lua_tojsstring(L, -1))
