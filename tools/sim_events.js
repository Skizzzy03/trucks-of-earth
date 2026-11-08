// Offline check of events.lua's road line on a real BeamNG.Earth road graph (fengari): a route along the graph's
// longest chain, the world 120 m above sea level (as Earth's ground is), the event 600 m ahead; prints the line and
// where some props would stand relative to the road.
// node tools/sim_events.js <events.lua> <navgraph.json> <fengari dir>
const fs = require('fs'), path = require('path')
const [luaFile, graphFile, fdir] = process.argv.slice(2)
const { lua, lauxlib, lualib, to_luastring } = require(path.join(fdir, 'node_modules', 'fengari'))
const g = JSON.parse(fs.readFileSync(graphFile, 'utf8'))
const adj = {}
g.edges.forEach(e => { (adj[e[0]] = adj[e[0]] || []).push(e[1]); (adj[e[1]] = adj[e[1]] || []).push(e[0]) })
const P = n => g.nodes[n]
let best = null
for (const e of g.edges) {
  if (e[2] !== 0 || e[6] < 0.8) continue
  const chain = [e[0], e[1]]
  for (let k = 0; k < 80; k++) {
    const a = P(chain[chain.length - 2]), b = P(chain[chain.length - 1])
    const dx = b[0] - a[0], dy = b[1] - a[1], l = Math.hypot(dx, dy)
    let nx = null, bd = 0.9
    for (const m of adj[chain[chain.length - 1]] || []) {
      if (m === chain[chain.length - 2]) continue
      const c = P(m), ex = c[0] - b[0], ey = c[1] - b[1], el = Math.hypot(ex, ey)
      const d = (dx * ex + dy * ey) / (l * el)
      if (d > bd) { bd = d; nx = m }
    }
    if (!nx || chain.includes(nx)) break
    chain.push(nx)
  }
  let len = 0
  for (let i = 1; i < chain.length; i++) len += Math.hypot(P(chain[i])[0] - P(chain[i - 1])[0], P(chain[i])[1] - P(chain[i - 1])[1])
  if (!best || len > best.len) best = { chain, len }
}
console.log(`route: ${best.chain.length} nodes, ${best.len.toFixed(0)} m`)
const lit = v => v === null || v === undefined ? 'nil' : Array.isArray(v) ? '{' + v.map(lit).join(',') + '}'
  : typeof v === 'object' ? '{' + Object.entries(v).map(([k, x]) => '[' + JSON.stringify(k) + ']=' + lit(x)).join(',') + '}'
  : typeof v === 'string' ? JSON.stringify(v) : String(v)
const code = `
local V = {} V.__index = V
function vec3(x, y, z) if type(x) == 'table' then return setmetatable({x=x.x,y=x.y,z=x.z or 0}, V) end return setmetatable({x=x or 0,y=y or 0,z=z or 0}, V) end
V.__add = function(a,b) return vec3(a.x+b.x,a.y+b.y,a.z+b.z) end
V.__sub = function(a,b) return vec3(a.x-b.x,a.y-b.y,a.z-b.z) end
V.__mul = function(a,b) if type(a)=='number' then a,b=b,a end return vec3(a.x*b,a.y*b,a.z*b) end
V.__unm = function(a) return vec3(-a.x,-a.y,-a.z) end
function V:dot(b) return self.x*b.x+self.y*b.y+self.z*b.z end
function V:length() return math.sqrt(self:dot(self)) end
function V:squaredLength() return self:dot(self) end
function V:distance(b) return (self-b):length() end
function quatFromDir() return {x=0,y=0,z=0,w=1} end
function log(l, t, m) print('LOG ' .. m) end
FS = { fileExists = function() return false end }
package.loaded['fernfahrer/pool'] = { take = function() end, give = function() end, owns = function() return false end }
package.loaded['fernfahrer/priority'] = { realHalf = function() return nil end }
local G = ${lit(g)}
local LIFT = 120                                      -- the ground above sea level
nodes = {}
for name, n in pairs(G.nodes) do nodes[name] = { pos = vec3(n[1], n[2], n[3] + LIFT), radius = n[4], links = {} } end
for _, e in ipairs(G.edges) do
  local a, b = nodes[e[1]], nodes[e[2]]
  if a and b then local l = { inRadius = e[8], drivability = e[7] }; a.links[e[2]] = l; b.links[e[1]] = l end
end
map = {}
function map.getMap() return { nodes = nodes } end
function map.findClosestRoad(p)
  local bn1, bn2, bd
  for n1, a in pairs(nodes) do for n2 in pairs(a.links) do
    local b = nodes[n2]; local ab = b.pos - a.pos; local l2 = ab:squaredLength()
    if l2 > 0.01 then local t = math.max(0, math.min(1, (p - a.pos):dot(ab) / l2)); local d = (a.pos + ab * t - p):length()
      if not bd or d < bd then bn1, bn2, bd = n1, n2, d end end
  end end
  return bn1, bn2, bd
end
-- the ground: the height of the nearest node (flat)
function castRayStatic(top, dir, len)
  local bd, bz
  for _, n in pairs(nodes) do local dx, dy = n.pos.x - top.x, n.pos.y - top.y; local d = dx*dx + dy*dy
    if not bd or d < bd then bd, bz = d, n.pos.z end end
  local hit = top.z - bz
  return (hit >= 0 and hit <= len) and hit or nil
end
local K = 111320
local anchor = { geodeticToWorld = function(self, lat, lon, h) return lon * K, lat * K, h or 0 end }
local E = (function() ${fs.readFileSync(luaFile, 'utf8')} end)()
local chain = ${lit(best.chain)}
local points = {}
for i, n in ipairs(chain) do points[i] = { nodes[n].pos.y / K, nodes[n].pos.x / K } end
local here = { lat = points[1][1], lon = points[1][2] }
local start, idx = E._along(points, here, 600)
local ev = { kind = 'roadworks', start = start, startIdx = idx, points = points }
local ctx = { anchor = function() return anchor end, playerPos = function() return nodes[chain[1]].pos end }
local line, why = E._buildLine(ev, ctx)
if not line then print('NO LINE: ' .. tostring(why)) return end
print(string.format('line: %d points, s %.0f .. %.0f m, half %.2f m', #line, line[1].s, line[#line].s, line[1].half))
ev.line = line
for _, s in ipairs({ -280, -130, -110, 0, 100, 300 }) do
  local pos, dir, half = E._frameAt(ev, s)
  if pos then
    -- the distance from the route's own point there (the route runs on the graph here: should be ~0)
    local q = E._along(points, here, 600 + s)
    local qx, qy = q and q.lon * K, q and q.lat * K
    print(string.format('s=%5d  centre (%.1f, %.1f, z %.1f)  dir (%.2f, %.2f)  half %.2f  off route %.1f m', s, pos.x, pos.y, pos.z, dir.x, dir.y, half,
      q and math.sqrt((pos.x - qx)^2 + (pos.y - qy)^2) or -1))
  else print('s=' .. s .. ': no frame') end
end
`
const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L)
if (lauxlib.luaL_loadstring(L, to_luastring(code)) !== 0) { console.log('load error:', lua.lua_tojsstring(L, -1)); process.exit(1) }
if (lua.lua_pcall(L, 0, 0, 0) !== 0) { console.log('run error:', lua.lua_tojsstring(L, -1)); process.exit(1) }
