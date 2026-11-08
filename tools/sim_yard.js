// Offline check of fernfahrer/yard.lua's search on a real BeamNG.Earth road graph: flat ground, a "building" (a box
// 14 m high) put on the first place the search would take, so it has to go to the next one; prints the place found,
// checks that no road passes through the yard and that it misses the building.
// node tools/sim_yard.js <yard.lua> <navgraph.json> <fengari dir>
const fs = require('fs'), path = require('path')
const [file, graphFile, fdir] = process.argv.slice(2)
const { lua, lauxlib, lualib, to_luastring } = require(path.join(fdir, 'node_modules', 'fengari'))
const src = fs.readFileSync(file, 'utf8')
const g = JSON.parse(fs.readFileSync(graphFile, 'utf8'))
const lit = v => v === null || v === undefined ? 'nil' : Array.isArray(v) ? '{' + v.map(lit).join(',') + '}'
  : typeof v === 'object' ? '{' + Object.entries(v).map(([k, x]) => '[' + JSON.stringify(k) + ']=' + lit(x)).join(',') + '}'
  : typeof v === 'string' ? JSON.stringify(v) : String(v)
// the home: a node with links, roughly in the middle of the graph
const names = Object.keys(g.nodes)
const xs = names.map(n => g.nodes[n][0]), ys = names.map(n => g.nodes[n][1])
const mx = (Math.min(...xs) + Math.max(...xs)) / 2, my = (Math.min(...ys) + Math.max(...ys)) / 2
let home = names[0], hd = 1e18
for (const n of names) { const d = (g.nodes[n][0] - mx) ** 2 + (g.nodes[n][1] - my) ** 2; if (d < hd) { hd = d; home = n } }
const code = `
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local V = {} V.__index = V
function vec3(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
V.__add = function(a, b) return vec3(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return vec3(a.x - b.x, a.y - b.y, a.z - b.z) end
function V:length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function V:normalized() local l = self:length(); return vec3(self.x / l, self.y / l, self.z / l) end
function log() end
local G, E = ${lit(g.nodes)}, ${lit(g.edges)}
local nodes = {}
for name, n in pairs(G) do nodes[name] = { pos = vec3(n[1], n[2], n[3]), links = {}, radius = 3.5 } end
for _, e in ipairs(E) do if nodes[e[1]] and nodes[e[2]] then nodes[e[1]].links[e[2]] = {}; nodes[e[2]].links[e[1]] = {} end end
map = { getMap = function() return { nodes = nodes } end }
-- the ground: flat at 0, a building box (set below) 14 m high
local BLD
function castRayStatic(o, dir, max)
  local h = 0
  if BLD and o.x > BLD[1] and o.x < BLD[3] and o.y > BLD[2] and o.y < BLD[4] then h = 14 end
  return o.z - h
end
local objs = {}
function createObject() local o = { f = {} }; function o:setField(k, _, v) self.f[k] = v end; function o:registerObject() objs[#objs + 1] = self end
  function o:getID() return #objs end; function o:setPosRot(x, y, z) self.p = { x, y, z } end; function o:setPosition(p) self.p = { p.x, p.y, p.z } end; function o:delete() self.dead = true end; return o end
scenetree = { findObjectById = function(id) return objs[id] end }
function quatFromDir() return { x = 0, y = 0, z = 0, w = 1 } end
local M = (function() ${src} end)()
local H = nodes[${JSON.stringify(home)}].pos
local out = {}
-- the first candidate the search would take: a building on it
local c0 = M._candidates(H, nodes)
local first
for _, f in ipairs(c0) do if not M._roadInside(f, nodes) then first = f; break end end
out[#out + 1] = string.format('%d candidates around the home, the first free of roads %.0f m from it', #c0, first and first.d or -1)
local cx, cy = first.ox + first.ey.x * 24, first.oy + first.ey.y * 24
BLD = { cx - 6, cy - 6, cx + 6, cy + 6 }
local anchor = { geodeticToWorld = function(_, la, lo) return lo * 111320, la * 111320, 0 end,
  worldToGeodetic = function(_, x, y) return y / 111320, x / 111320, 0 end }
local S = { home = {} }
local ctx = { save = function() return S end, homeWorld = function() return H end, playerPos = function() return vec3(H.x, H.y, 0) end,
  anchor = function() return anchor end, anchorId = function() return 1 end, loading = function() return false end,
  night = function() return true end, found = function() out[#out + 1] = 'found() called' end }
for i = 1, 400 do M.update(ctx); if S.yard then break end end
if not S.yard or not S.yard.lat then out[#out + 1] = 'NO YARD: ' .. tostring(M.status); return table.concat(out, '\\n') end
local x, y = anchor:geodeticToWorld(S.yard.lat, S.yard.lon)
local h = math.rad(S.yard.hdg)
local ey = vec3(math.sin(h), math.cos(h), 0)
local ex = vec3(ey.y, -ey.x, 0)
local f = { ox = x, oy = y, ex = ex, ey = ey }
out[#out + 1] = string.format('yard at %.1f, %.1f, heading %.0f deg, %.0f m from the home; status %s', x, y, S.yard.hdg,
  math.sqrt((x + ey.x * 24 - H.x) ^ 2 + (y + ey.y * 24 - H.y) ^ 2), M.status)
out[#out + 1] = 'road inside: ' .. tostring(M._roadInside(f, nodes))
-- the building's corners in the yard's frame
local hit = false
for _, p in ipairs({ { BLD[1], BLD[2] }, { BLD[3], BLD[2] }, { BLD[1], BLD[4] }, { BLD[3], BLD[4] }, { cx, cy } }) do
  local dx, dy = p[1] - x, p[2] - y
  local lx, ly = dx * ex.x + dy * ex.y, dx * ey.x + dy * ey.y
  if math.abs(lx) < 24 and ly > 0 and ly < 48 then hit = true end
end
out[#out + 1] = 'building inside the yard: ' .. tostring(hit)
local o = objs[1]
out[#out + 1] = string.format('objects: %d (yard shape %s, collision %s), lamps lit at night: %s', #objs, tostring(o.f.shapeName):match('[^/]+$'), tostring(o.f.collisionType), tostring(#objs == 5))
local sp = M.parkSpot()
local dx, dy = sp.pos.x - x, sp.pos.y - y
out[#out + 1] = string.format('truck place: %.1f m along, %.1f m in (facing the gate: %s)', dx * ex.x + dy * ex.y, dx * ey.x + dy * ey.y, tostring(sp.dir.x * ey.x + sp.dir.y * ey.y < -0.99))
return table.concat(out, '\\n')
`
const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L)
if (lauxlib.luaL_loadstring(L, to_luastring(code)) !== 0 || lua.lua_pcall(L, 0, 1, 0) !== 0) { console.log('ERR', lua.lua_tojsstring(L, -1)); process.exit(1) }
console.log(lua.lua_tojsstring(L, -1))
