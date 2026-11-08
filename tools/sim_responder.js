// Offline check of accidents.lua: a motorway with two one-way carriageways, the truck drives north, crashes; where does
// the police car start, which node is it sent to, does it stop near the scene, is it ever teleported?
// node tools/sim_responder.js <accidents.lua> <fengari dir>
const fs = require('fs'), path = require('path')
const [file, fdir] = process.argv.slice(2)
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require(path.join(fdir, 'node_modules', 'fengari'))
const code = `
vec3 = nil
local V = {}
V.__index = V
function vec3(x, y, z)
  if type(x) == 'table' then return setmetatable({ x = x.x, y = x.y, z = x.z or 0 }, V) end
  return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V)
end
V.__add = function(a, b) return vec3(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return vec3(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__unm = function(a) return vec3(-a.x, -a.y, -a.z) end
V.__mul = function(a, b) if type(a) == 'number' then a, b = b, a end return vec3(a.x * b, a.y * b, a.z * b) end
function V:dot(b) return self.x * b.x + self.y * b.y + self.z * b.z end
function V:length() return math.sqrt(self:dot(self)) end
function V:normalized() return self * (1 / self:length()) end
function V:distance(b) return (self - b):length() end
function V:squaredDistance(b) local d = self - b; return d:dot(d) end

-- the road graph: carriageway a (x = 0, northbound), b (x = -12, southbound), a farm track c (x = 25, both ways)
local nodes = {}
local function add(prefix, x, n, oneWayForward)
  for i = 0, n do nodes[prefix .. i] = { pos = vec3(x, i * 60, 0), links = {} } end
  for i = 0, n - 1 do
    local a, b = prefix .. i, prefix .. (i + 1)
    local l
    if oneWayForward == nil then l = { drivability = 1, oneWay = false, inNode = a }
    elseif oneWayForward then l = { drivability = 1, oneWay = true, inNode = a }
    else l = { drivability = 1, oneWay = true, inNode = b } end
    nodes[a].links[b], nodes[b].links[a] = l, l
  end
end
add('a', 0, 30, true); add('b', -12, 30, false); add('c', 25, 30, nil)

local clock = 0
os.clock = function() return clock end
local cmds, teleports = {}, 0
local veh = {}
local function makeVeh(id, p, d) veh[id] = { id = id, p = vec3(p), v = vec3(0, 0, 0), d = d or vec3(0, 1, 0) }
  local o = veh[id]
  function o:getID() return self.id end
  function o:getPosition() return self.p end
  function o:getVelocity() return self.v end
  function o:getDirectionVector() return self.d end
  function o:queueLuaCommand(c) cmds[#cmds + 1] = { t = clock, id = self.id, c = c }; self.last = c
    if c:find('setTarget') then self.ordered = true end
    if c:find('setFreeze%(1%)') then self.parked = true end
    local s = c:match('ai.setSpeed%(([%d%.]+)%)'); if s then self.cap = tonumber(s) end
  end
  return o
end
function getObjectByID(id) return veh[id] end
function log(l, t, m) print('LOG ' .. m) end
function castRayStatic(p, d, m) return math.min(p.z, m - 0.1) end
function quatFromDir() return {} end
spawn = { safeTeleport = function(v, p) teleports = teleports + 1; v.p = vec3(p) end }
map = { objects = {}, getMap = function() return { nodes = nodes } end,
  findClosestRoad = function(p)
    local best, bd
    for name, n in pairs(nodes) do
      for m in pairs(n.links) do
        if name < m then
          local a, b = n.pos, nodes[m].pos
          local ab = b - a
          local k = math.max(0, math.min(1, (p - a):dot(ab) / ab:dot(ab)))
          local q = a + ab * k
          local dd = (p.x - q.x) ^ 2 + (p.y - q.y) ^ 2
          if not bd or dd < bd then best, bd = { name, m }, dd end
        end
      end
    end
    return best[1], best[2]
  end }
package.loaded['fernfahrer/pool'] = {
  take = function(kind, pos, dir)
    local id = kind == 'police' and 101 or 102
    local v = makeVeh(id, pos, dir)
    v.v = vec3(0, 0, -4)                    -- (just put down: it has a speed)
    return id
  end, give = function() end }

local M = load(ACC, 'accidents')()
local truck = makeVeh(1, vec3(0, 0, 1.2))
local dmg = 0
local ctx = { playerVeh = function() return truck end, damageOf = function() return dmg end, speedKmh = function() return 70 end,
  roadLimit = function() return 80 end, here = function() return { lat = 1, lon = 2 } end, placeOf = function() return {} end,
  trailerId = function() return nil end, clockText = function() return '12:00' end, addDocument = function(d) print('REPORT ' .. d.case) end,
  fine = function() end, notify = function() end, message = function() end, protect = function() end, busy = function() return false end,
  vehicleName = function() return 'LKW' end }
local function step(dt) clock = clock + dt
  map.objects = {}
  for id, v in pairs(veh) do map.objects[id] = { pos = v.p, damage = id == 1 and dmg or 0, vel = v.v } end
  M.update(ctx, dt)
end
-- drive north at 20 m/s for 620 m
for i = 1, 124 do truck.p = truck.p + vec3(0, 5, 0); step(0.25) end
-- nudge: a scene with another vehicle so the police are called at once
makeVeh(50, truck.p + vec3(0, 6, 0)); step(0.25)
dmg = 9000
truck.d = vec3(1, 0, 0)                     -- (the wreck points across the road)
step(0.25)
veh[50].dmgd = true
local oldObjects = map.objects
for i = 1, 14 do clock = clock + 0.25
  map.objects = {}
  for id, v in pairs(veh) do map.objects[id] = { pos = v.p, damage = id == 1 and dmg or (id == 50 and 500 or 0), vel = v.v } end
  M.update(ctx, 0.25)
end
local p = veh[101]
assert(p, 'no police car')
print(string.format('START police x=%.1f y=%.1f dir=%.2f,%.2f (truck y=%.0f)', p.p.x, p.p.y, p.d.x, p.d.y, truck.p.y))
print('ORDER ' .. tostring(p.last))
-- it drives along its carriageway only once its order got through (the first two orders get lost)
local got = 0
local n0 = 0
for i = 1, 2400 do
  local dt = 0.05
  for _, id in ipairs({ 101, 102 }) do
    local u = veh[id]
    if u and not u.parked then
      if u.ordered then u.got = (u.got or 0) + 1 end
      if (u.got or 0) > 40 then
        local sp = math.min(u.cap or 30, 30)
        u.v = vec3(0, sp, 0); u.p = u.p + u.v * dt
      else u.v = vec3(0, 0, 0) end
    elseif u then u.v = vec3(0, 0, 0) end
  end
  clock = clock + dt
  map.objects = {}
  for id, v in pairs(veh) do map.objects[id] = { pos = v.p, damage = id == 1 and dmg or (id == 50 and 500 or 0), vel = v.v } end
  M.update(ctx, dt)
  if p.parked and (not veh[102] or veh[102].parked) then break end
end
for _, id in ipairs({ 101, 102 }) do local u = veh[id]
  if u then print(string.format('END %d x=%.1f y=%.1f parked=%s, %.1f m from truck', id, u.p.x, u.p.y, tostring(u.parked), u.p:distance(truck.p))) end end
print('TELEPORTS ' .. teleports)
local b = M.behind(220)
print(string.format('BEHIND(220) y=%.0f', b.y))
local nd = M.nodeAlong(vec3(-12, 900, 0), vec3(0, -1, 0), 300)
print('SOUTHBOUND nodeAlong ' .. tostring(nd))
local wrong = M.nodeAlong(vec3(-3, 900, 0), vec3(0, 1, 0), 300)
print('NEAR THE MEDIAN, NORTHBOUND ' .. tostring(wrong))
`
const L = lauxlib.luaL_newstate()
lualib.luaL_openlibs(L)
const src = fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n')
lua.lua_pushstring(L, to_luastring(src)); lua.lua_setglobal(L, to_luastring('ACC'))
const st = lauxlib.luaL_loadstring(L, to_luastring(code))
if (st !== 0 || lua.lua_pcall(L, 0, 0, 0) !== 0) { console.error('ERROR', to_jsstring(lua.lua_tostring(L, -1))); process.exit(1) }
