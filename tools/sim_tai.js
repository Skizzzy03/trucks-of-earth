// Offline check of trafficai.lua on a real BeamNG.Earth road graph (fengari): a slow truck on a long road, a car
// behind it, optionally oncoming cars; prints the decisions and the commands sent to the car.
// node tools/sim_tai.js <trafficai.lua> <navgraph.json> <fengari dir> [oncomingAtM]
const fs = require('fs'), path = require('path')
const [luaFile, graphFile, fdir, oncomingArg] = process.argv.slice(2)
const { lua, lauxlib, lualib, to_luastring } = require(path.join(fdir, 'node_modules', 'fengari'))
const g = JSON.parse(fs.readFileSync(graphFile, 'utf8'))

// the longest straight-ish chain of drivability-1 two-way edges: the test road
const adj = {}
g.edges.forEach(e => { if (e[2] === 0) { (adj[e[0]] = adj[e[0]] || []).push(e[1]); (adj[e[1]] = adj[e[1]] || []).push(e[0]) } })
const P = n => g.nodes[n]
let best = null
for (const e of g.edges) {
  if (e[2] !== 0 || e[6] < 1) continue
  const chain = [e[0], e[1]]
  for (let k = 0; k < 80; k++) {
    const a = P(chain[chain.length - 2]), b = P(chain[chain.length - 1])
    const dx = b[0] - a[0], dy = b[1] - a[1], l = Math.hypot(dx, dy)
    let nx = null, bd = 0.93
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
console.log(`test road: ${best.chain.length} nodes, ${best.len.toFixed(0)} m`)
const lit = v => v === null || v === undefined ? 'nil' : Array.isArray(v) ? '{' + v.map(lit).join(',') + '}'
  : typeof v === 'object' ? '{' + Object.entries(v).map(([k, x]) => '[' + JSON.stringify(k) + ']=' + lit(x)).join(',') + '}'
  : typeof v === 'string' ? JSON.stringify(v) : String(v)

const prelude = `
ONE_SIDED = ${process.env.ONE_SIDED ? "true" : "false"}
package.preload['fernfahrer/accidents'] = function() return { behind = function() return nil end, zones = function() return nil end } end
local V = {}
V.__index = V
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
local T = 0
os.clock = function() return T end
function setT(t) T = t end
LOG = {}
ONC = nil
function log(l, tag, msg) table.insert(LOG, string.format('t=%5.1f  %s%s', T, msg, ONC and string.format('  [Gegenverkehr %.0f m vor dem Auto]', ONC) or '')) end
local G = ${lit(g)}
nodes = {}
for name, n in pairs(G.nodes) do nodes[name] = { pos = vec3(n[1], n[2], n[3]), radius = n[4], links = {} } end
for _, e in ipairs(G.edges) do
  local a, b = nodes[e[1]], nodes[e[2]]
  if a and b then
    local link = { drivability = e[7], inRadius = e[8], outRadius = e[8], speedLimit = ${process.env.ROAD_MS || "e[6]"}, lanes = string.rep("-", e[5]) .. string.rep("+", e[4]), oneWay = e[3] == 1, inNode = e[1], outNode = e[2] }
    a.links[e[2]] = link; if not ONE_SIDED then b.links[e[1]] = link end
  end
end
map = { objects = {} }
function map.getMap() return { nodes = nodes } end
function map.findClosestRoad(p)
  local bn1, bn2, bd
  for n1, a in pairs(nodes) do
    for n2 in pairs(a.links) do
      local b = nodes[n2]
      local ab = b.pos - a.pos
      local l2 = ab:squaredLength()
      if l2 > 0.01 then
        local t = math.max(0, math.min(1, (p - a.pos):dot(ab) / l2))
        local d = (a.pos + ab * t - p):length()
        if not bd or d < bd then bn1, bn2, bd = n1, n2, d end
      end
    end
  end
  return bn1, bn2, bd
end
SENT = {}
local OBJ = {}
function getObjectByID(id)
  return OBJ[id] or { queueLuaCommand = function(_, c) table.insert(SENT, id .. ': ' .. c) end,
    getSpawnWorldOOBB = function() return { getHalfExtents = function() return vec3(1, id == 1 and 4.5 or (id == 2 and 6.5 or 2.3), 1) end } end }
end
gameplay_traffic = { getTrafficList = function() return TRAFFIC end, respawnVehicle = function(id) table.insert(SENT, id .. ': respawn') end }
`
const chainLit = lit(best.chain)
const oncomingAt = Number(oncomingArg || 0)
const scenario = `
local TAI = (function() ${fs.readFileSync(luaFile, 'utf8')} end)()
TAI.C.TICK_S = 0
if ${oncomingAt} > 0 then TAI.C.GAP_EVERY_S = { 9999, 9999 } end   -- (the oncoming test car does not obey a hold)
local chain = ${chainLit}
local cum = {0}
for i = 2, #chain do cum[i] = cum[i-1] + nodes[chain[i]].pos:distance(nodes[chain[i-1]].pos) end
-- a point s m along the chain, lat m right of the centre line, and the direction
local function at(s, lat)
  for i = 2, #chain do
    if cum[i] >= s then
      local a, b = nodes[chain[i-1]].pos, nodes[chain[i]].pos
      local d = (b - a) * (1 / (b - a):length())
      local p = a + (b - a) * ((s - cum[i-1]) / (cum[i] - cum[i-1]))
      return p + vec3(d.y, -d.x, 0) * lat, d
    end
  end
end
local truckS, carS, oncS = 120, 95, ${oncomingAt > 0 ? oncomingAt : -1}
TRAFFIC = { 3, 4 }
local ctx = { playerVeh = function() return { getPosition = function() return at(truckS, 1.4) end, getID = function() return 1 end } end,
  trailerId = function() return 2 end, roadLimit = function() return 100 end, zones = function() return {} end,
  protect = function() end, enabled = function() return true end }
local carLat = 1.6
for step = 0, 120 do
  setT(step * 0.5)
  truckS = truckS + 30 / 3.6 * 0.5               -- the truck at 30 km/h
  local passing = false
  for _, s in ipairs(SENT) do if s:find('laneChange') and s:find('^3:') then passing = true end end
  local carSpeed = passing and 22 or 30 / 3.6
  carS = math.min(carS + carSpeed * 0.5, carS + carSpeed * 0.5)
  if passing then carLat = math.max(-1.7, carLat - 1.2) end
  local tp, td = at(truckS, 1.4)
  local trp = at(truckS - 9, 1.4)
  local cp, cd = at(carS, carLat)
  map.objects = {
    [1] = { pos = tp, vel = td * (30 / 3.6), dirVec = td },
    [2] = { pos = trp, vel = td * (30 / 3.6), dirVec = td },
    [3] = { pos = cp, vel = cd * carSpeed, dirVec = cd },
  }
  if oncS > 0 then
    local op, od = at(math.max(0, truckS + oncS - step * 0.5 * 25), -1.6)
    if op then map.objects[4] = { pos = op, vel = -od * 25, dirVec = -od }; ONC = (op - cp):dot(cd) else ONC = nil end
  end
  TAI.update(ctx, 0.5)
  if not at(carS + 30, 0) then break end
end
local out = {'WATCH known=' .. TAI.watch.known .. ' looks=' .. TAI.watch.looks .. ' left=' .. TAI.watch.left}
for _, l in ipairs(LOG) do out[#out+1] = 'LOG ' .. l end
local seen = 0
for _, s in ipairs(SENT) do if s:find('^3:') and seen < 8 then out[#out+1] = 'CMD ' .. s:gsub('%s+', ' '); seen = seen + 1 end end
return table.concat(out, '\\n')
`
const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L)
for (const [n, c] of [['prelude', prelude], ['scenario', scenario]]) {
  if (lauxlib.luaL_loadstring(L, to_luastring(c)) !== 0) { console.log(n, 'load error:', lua.lua_tojsstring(L, -1)); process.exit(1) }
  if (lua.lua_pcall(L, 0, n === 'scenario' ? 1 : 0, 0) !== 0) { console.log(n, 'run error:', lua.lua_tojsstring(L, -1)); process.exit(1) }
}
console.log(lua.lua_tojsstring(L, -1))
