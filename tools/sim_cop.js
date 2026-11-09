// Offline check of the police talk (career.lua L.cop*): every path of answers ends, nothing errors.
// node tools/sim_cop.js <career.lua> <fengari dir>
const fs = require('fs'), path = require('path')
const [file, fdir] = process.argv.slice(2)
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require(path.join(fdir, 'node_modules', 'fengari'))
const src = fs.readFileSync(file, 'utf8')
const a = src.indexOf('L.COP = {'), b = src.indexOf('-- (2026-11-08) ADR papers')
if (a < 0 || b < 0) throw new Error('block not found')
const block = src.slice(a, b)
const code = `
vices = { installCam = function() end, setLook = function() end }
local L, M, R, S = {}, {}, {}, {}
local fines, trig = {}, 0
local function round(x, s) s = s or 1; return math.floor(x / s + 0.5) * s end
local function money(v) return tostring(v) .. ' EUR' end
local function now() return 0 end
local function message() end
local function notify() end
local function addXp() end
local function save() end
local function deleteTrailer() end
local function navClear() end
local function activeDef() return { model = 'x', config = 'y' } end
local function playerVeh() return nil end
local function careerVeh() return nil end
local function vehSpeed() return 0 end
guihooks = { trigger = function() trig = trig + 1 end }
core_vehicles = { replaceVehicle = function() end }
L.pay = function() end
M.fine = function(amount, reason) fines[#fines + 1] = amount end
${block}
local kinds = { 'tacho', 'alcohol', 'thc', 'unsafe', 'load', 'limiter', 'adr', false }
local runs, seized, lost = 0, 0, 0
for run = 1, 4000 do
  math.randomseed(run)
  local own = (run % 2 == 0) and { price = 80000, brand = 'b', modelName = 'm' } or nil
  L.ownTruck = function() return own end
  S.money = 5000
  S.job = (run % 3 ~= 0) and { adr = run % 5 == 0, smuggle = run % 4 == 0 } or nil
  local found = {}
  for i = 1, math.random(0, 4) do
    found[i] = { amount = math.random(50, 4500), reason = 'r' .. i, kind = kinds[math.random(#kinds)] or nil }
  end
  R.cop = nil
  fines = {}
  L.copStart(found)
  local n = 0
  while R.cop do
    n = n + 1
    assert(n < 60, 'no end')
    local c = R.cop
    assert(type(c.line) == 'string' and #c.line > 0, 'no line at ' .. tostring(c.stage))
    assert(type(c.choices) == 'table' and #c.choices > 0, 'no choices at ' .. tostring(c.stage))
    local stage, was = c.stage, c.seized
    M.copAnswer(math.random(#c.choices))
    if was then seized = seized + 1 end
  end
  runs = runs + 1
end
RESULT = 'runs ' .. runs .. ', all ended; seized paths ' .. seized
`
const L = lauxlib.luaL_newstate()
lualib.luaL_openlibs(L)
if (lauxlib.luaL_dostring(L, to_luastring(code))) { console.error(to_jsstring(lua.lua_tostring(L, -1))); process.exit(1) }
lua.lua_getglobal(L, to_luastring('RESULT'))
console.log(to_jsstring(lua.lua_tostring(L, -1)))
