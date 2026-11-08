// Offline check of the spoken directions (career.lua updateNav) on a real BeamNG.Earth road graph: a route along the
// graph that turns at a junction, the player driving along it; prints every announcement.
// node tools/sim_nav.js <career.lua> <navgraph.json> <fengari dir>
const fs = require('fs'), path = require('path')
const [careerFile, graphFile, fdir] = process.argv.slice(2)
const { lua, lauxlib, lualib, to_luastring } = require(path.join(fdir, 'node_modules', 'fengari'))
const src = fs.readFileSync(careerFile, 'utf8')
const i0 = src.indexOf('local NAV = {'), i1 = src.indexOf('-- the company network', i0)
const navCode = src.slice(i0, i1)
const g = JSON.parse(fs.readFileSync(graphFile, 'utf8'))
const N = g.nodes, adj = {}
g.edges.forEach(e => { (adj[e[0]] = adj[e[0]] || []).push(e[1]); (adj[e[1]] = adj[e[1]] || []).push(e[0]) })
const dir = (a, b) => { const dx = N[b][0] - N[a][0], dy = N[b][1] - N[a][1], l = Math.hypot(dx, dy); return [dx / l, dy / l] }
// a junction with a near-right-angle turn, and 400 m of straight-ish road before it and 300 m after
function straight(prev, cur, want) {
  const path = [cur]; let len = 0
  while (len < want) {
    const d0 = dir(prev, cur); let best = null, bd = 0.85
    for (const m of adj[cur] || []) { if (m === prev) continue; const d = dir(cur, m); const dot = d0[0] * d[0] + d0[1] * d[1]; if (dot > bd) { bd = dot; best = m } }
    if (!best) break
    len += Math.hypot(N[best][0] - N[cur][0], N[best][1] - N[cur][1]); path.push(best); prev = cur; cur = best
  }
  return { path, len }
}
let route = null
for (const j of Object.keys(adj)) {
  if (adj[j].length < 3) continue
  for (const a of adj[j]) for (const b of adj[j]) {
    if (a === b) continue
    const din = dir(a, j), dout = dir(j, b)
    const cross = din[0] * dout[1] - din[1] * dout[0], dot = din[0] * dout[0] + din[1] * dout[1]
    if (Math.abs(dot) > 0.35) continue        // ~70-110Â°
    const back = straight(j, a, 400), fwd = straight(j, b, 300)
    if (back.len >= 380 && fwd.len >= 250) { route = { pts: back.path.reverse().concat([j], fwd.path), turn: cross < 0 ? 'rechts' : 'links', j: j }; break }
  }
  if (route) break
}
if (!route) { console.log('no suitable junction in this graph'); process.exit(0) }
const K = 111320
let pts = route.pts.map(n => [N[n][1] / K, N[n][0] / K])
// SPARSE=n: only every n-th point kept (and the junction) – like the GPS route on country roads
if (process.env.SPARSE) { const k = +process.env.SPARSE, j = route.pts.length - 1 - (route.fwdN || 0); pts = pts.filter((p, i) => i % k === 0 || i === pts.length - 1 || route.pts[i] === route.j) }
console.log(`route: ${pts.length} points, turn expected: ${route.turn} (world frame: +y north)`)
const lit = v => v === null || v === undefined ? 'nil' : Array.isArray(v) ? '{' + v.map(lit).join(',') + '}'
  : typeof v === 'object' ? '{' + Object.entries(v).map(([k, x]) => '[' + JSON.stringify(k) + ']=' + lit(x)).join(',') + '}'
  : typeof v === 'string' ? JSON.stringify(v) : String(v)
const code = `
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local V = {} V.__index = V
function vec3(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
local G = ${lit(g.nodes)}
local E = ${lit(g.edges)}
local nodes = {}
for name, n in pairs(G) do nodes[name] = { pos = vec3(n[1], n[2], n[3]), links = {} } end
for _, e in ipairs(E) do if nodes[e[1]] and nodes[e[2]] then nodes[e[1]].links[e[2]] = {}; nodes[e[2]].links[e[1]] = {} end end
map = { getMap = function() return { nodes = nodes } end }
local K = ${K}
local anchor = { geodeticToWorld = function(self, lat, lon) return lon * K, lat * K, 0 end }
local function earthCore() return { _state = function() return { anchor = anchor } end } end
local PTS = ${lit(pts)}
local function earthModule() return { route = function() return { points = PTS } end } end
local S = { settings = {} }
local L, M = {}, {}
local logTag = 'sim'
local played = {}
Engine = { Audio = { playOnce = function(ch, path) played[#played + 1] = path end } }
function log() end
local R = {}
local P = { lat = PTS[1][1], lon = PTS[1][2] }
local function here() return P end
${navCode}
local said, lastSay = {}, nil
-- drive along the route in 5 m steps
local function lerp(a, b, f) return a + (b - a) * f end
for i = 1, #PTS - 1 do
  local a, b = PTS[i], PTS[i + 1]
  local d = hav(a[1], a[2], b[1], b[2])
  local steps = math.max(1, math.floor(d / 5))
  for s = 0, steps - 1 do
    P = { lat = lerp(a[1], b[1], s / steps), lon = lerp(a[2], b[2], s / steps) }
    L.updateNav()
    if R.nav and R.nav.text and R.nav.sayId ~= lastSay then lastSay = R.nav.sayId; said[#said + 1] = string.format('%-38s (Pfeil %s) -> %s', R.nav.text, R.nav.dir, tostring(played[#played])) end
  end
end
return #said > 0 and table.concat(said, '\\n') or 'NO ANNOUNCEMENT'
`
const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L)
if (lauxlib.luaL_loadstring(L, to_luastring(code)) !== 0) { console.log('load', lua.lua_tojsstring(L, -1)); process.exit(1) }
if (lua.lua_pcall(L, 0, 1, 0) !== 0) { console.log('run', lua.lua_tojsstring(L, -1)); process.exit(1) }
console.log(lua.lua_tojsstring(L, -1))

