// Walks every rest-area scene: all targets exist, every node can be reached, thousands of random talks end without an error. node sim_encounters.js
const fs = require('fs'), path = require('path')
const fengari = require('fengari'), { lua, lauxlib, lualib, to_luastring: S, to_jsstring: J } = fengari
const src = fs.readFileSync('C:/Users/test/Desktop/fernfahrer_karriere/lua/ge/extensions/fernfahrer/encounters.lua', 'utf8')
const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L)
const test = `
local M = (function() ${src} end)()
local log, money = {}, 5000
local X = { money=function() return money end, fmt=function(v) return tostring(v)..' EUR' end, pay=function(c,a,l) assert(type(a)=='number' and l); money=money+a end, xp=function(n) assert(n>0) end,
  notify=function(s) assert(type(s)=='string') end, message=function(s) assert(type(s)=='string') end, save=function() end, fine=function(a,w) assert(a and w) end, km=function() return KM end,
  job=function() return {} end, hasTrailer=function() return true end, trigger=function(n,d) LAST=d end, give=function(id) assert(id) end, cab=function(k,n) assert(k and n) end, tired=function(d) assert(d) end,
  diesel=function(l) assert(l) end, fail=function(k) assert(k) end, freight=function(f) assert(f<1) end, look=function() end, bed=function() end, knock=function() end, stage=function(s) assert(s:find('ff_npc_')) end, clean=function() end }
KM = 0
local st = {}
M.attach(st, X)
-- the graph
local problems, seen = {}, {}
for key, sc in pairs(M.SC) do
  local reach = { [sc.start] = true }
  assert(sc.n[sc.start], key .. ' start')
  local changed = true
  while changed do changed = false
    for id, n in pairs(sc.n) do if reach[id] then for _, c in ipairs(n.ch or {}) do
      local tg = { c.to, c.roll and c.roll[2], c.roll and c.roll[3] }
      for i = 1, 3 do local t = tg[i]; if t then
        if not sc.n[t] then problems[#problems+1] = key..': '..id..' -> '..t end
        if not reach[t] then reach[t] = true; changed = true end
      end end
    end end end
  end
  for id in pairs(sc.n) do if not reach[id] then problems[#problems+1] = key..': nicht erreichbar '..id end end
end
for _, k in ipairs(M.ORDER) do assert(M.SC[k], k) end
-- random talks
local realClock = os.clock
local t = 100; os.clock = function() return t end
local runs = 0
for r = 1, 6000 do
  money = ({ 0, 35, 5000 })[r % 3 + 1]
  local key = M.ORDER[r % #M.ORDER + 1]
  assert(M.start(key))
  for i = 1, 4 do t = t + 2; M.tick(false) end
  local steps = 0
  while M.active() do
    steps = steps + 1; assert(steps < 200, 'endlos: '..key)
    local n = #LAST.choices
    assert(n >= 1 and LAST.line and #LAST.line > 0, 'leer '..key)
    assert(not LAST.line:find('%%ROB'), 'ROB in Text')
    for _, c in ipairs(LAST.choices) do assert(not (c.sub or ''):find('%%ROB')) end
    M.answer(math.random(n))
  end
  assert(LAST.off, 'off')
  KM = KM + 40; M.kmTick(KM); runs = runs + 1
end
local found = {}
st.pack = { km = 1e9 }; M.contraband(found); assert(#found == 1 and st.pack == nil)
for i = 1, 40 do local k = M.pick(); assert(M.SC[k]); st.seen[#st.seen+1] = k; if #st.seen > 6 then table.remove(st.seen,1) end end
return runs .. ' Gespraeche ok, Probleme: ' .. (#problems == 0 and 'keine' or table.concat(problems, '; '))
`
if (lauxlib.luaL_loadstring(L, S(test)) !== lua.LUA_OK || lua.lua_pcall(L, 0, 1, 0) !== lua.LUA_OK) { console.error('FEHLER', J(lua.lua_tostring(L, -1))); process.exit(1) }
console.log(J(lua.lua_tostring(L, -1)))
