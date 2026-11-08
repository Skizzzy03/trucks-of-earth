// Offline check of fernfahrer/stops.lua: a rest area beside a road; the truck drives up, into the ring, stops.
// node tools/sim_stops.js <stops.lua> <fengari dir>
const fs = require('fs'), path = require('path')
const [file, fdir] = process.argv.slice(2)
const { lua, lauxlib, lualib, to_luastring } = require(path.join(fdir, 'node_modules', 'fengari'))
const src = fs.readFileSync(file, 'utf8')
const code = `
local V = {} V.__index = V
function vec3(x, y, z) if type(x) == 'table' then return setmetatable({ x = x.x, y = x.y, z = x.z }, V) end return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
V.__add = function(a, b) return vec3(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return vec3(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__mul = function(a, b) if type(a) == 'number' then a, b = b, a end return vec3(a.x * b, a.y * b, a.z * b) end
function V:length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function castRayStatic(o) return o.z - 2 end                      -- (ground at z = 2)
-- a road along x at y = 0 from x = -200 to 200; the rest area's point 40 m off it (inside its building)
local nodes = { a = { pos = vec3(-200, 0, 2) }, b = { pos = vec3(200, 0, 2) } }
map = { getMap = function() return { nodes = nodes } end, findClosestRoad = function() return 'a', 'b', 40 end }
local objs = {}
function createObject() local o = { f = {} }; function o:setField(k, _, v) self.f[k] = v end; function o:registerObject() objs[#objs + 1] = self end
  function o:getID() return #objs end; function o:setPosRot(x, y, z) self.p = { x, y, z } end; function o:delete() self.dead = true end; return o end
scenetree = { findObjectById = function(id) return objs[id] end }
function quatFromDir() return { x = 0, y = 0, z = 0, w = 1 } end
local M = (function() ${src} end)()
local anchor = { geodeticToWorld = function(_, la, lo) return lo, la, 0 end }
local place = { id = 7, action = 'sleep', name = 'Rastplatz Hünxe', icon = '🅿️', typeName = 'Rastplatz', lat = 40, lon = 30 }
local P = vec3(-150, 0, 2.5)
local ctx = { near = function() return place end, playerPos = function() return P end, anchor = function() return anchor end }
local out = {}
M.update(ctx, 0.1)
local h = M.hud()
out[#out + 1] = string.format('ring at %.1f, %.1f, %.1f (on the road beside the place: %s) – colour %s, %d objects',
  objs[1].p[1], objs[1].p[2], objs[1].p[3], tostring(math.abs(objs[1].p[2]) < 0.01), h.color, #objs)
out[#out + 1] = string.format('far: inside=%s dist=%.0f m, hint "%s"', tostring(h.inside), h.dist, h.hint)
P = vec3(28, 3, 2.5); M.update(ctx, 0.1); h = M.hud()
out[#out + 1] = string.format('in the ring: inside=%s, M.inside() = %s', tostring(h.inside), M.inside() and M.inside().name or 'nil')
local g1 = objs[2].p[3]; M.update(ctx, 0.5); out[#out + 1] = string.format('marker floats and turns: %.2f → %.2f m', g1, objs[2].p[3])
place = nil; M.update(ctx, 0.1)
out[#out + 1] = 'away from the place: ring gone = ' .. tostring(objs[1].dead and objs[2].dead and M.hud() == nil)
return table.concat(out, '\\n')
`
const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L)
if (lauxlib.luaL_loadstring(L, to_luastring(code)) !== 0 || lua.lua_pcall(L, 0, 1, 0) !== 0) { console.log('ERR', lua.lua_tojsstring(L, -1)); process.exit(1) }
console.log(lua.lua_tojsstring(L, -1))
