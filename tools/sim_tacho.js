// Offline check of fernfahrer/tacho.lua: driving days in game time, step by step.
// node tools/sim_tacho.js <tacho.lua> <fengari dir>
const fs = require('fs'), path = require('path')
const [file, fdir] = process.argv.slice(2)
const { lua, lauxlib, lualib, to_luastring } = require(path.join(fdir, 'node_modules', 'fengari'))
const src = fs.readFileSync(file, 'utf8')
const code = `
local M = (function() ${src} end)()
local T = M.new()
local out = {}
local notes = {}
local function notify(t) notes[#notes + 1] = t end
-- game minutes of an activity: driving (speed 20 m/s) or standing
local function drive(min) for i = 1, min * 6 do M.update(T, 1, 20, notify) end end      -- (1 real s = 10 game s)
local function stand(min) for i = 1, min * 6 do M.update(T, 1, 0, notify) end end
local function show(label)
  local v = M.view(T)
  out[#out + 1] = string.format('%-44s act=%-5s bis Pause %s | heute %s gefahren, noch %s | Woche %s | split=%s | Verst.=%d',
    label, v.act, v.driveText, v.dayDrivenText, v.dayText, v.weekDrivenText, tostring(v.split or false), v.violations)
  for _, n in ipairs(notes) do out[#out + 1] = '    > ' .. n end
  notes = {}
end
drive(240); show('4 h gefahren')
stand(3); show('3 min an der Ampel (keine Pause)')
drive(20); show('weiter, 20 min')
M.setActivity(T, 'rest', 0); stand(20); show('20 min Pause gedrückt (Teil 1)')
drive(60); show('1 h gefahren')
M.setActivity(T, 'rest', 0); stand(30); show('30 min Pause (Teil 2) → gültig')
drive(270); show('4:30 gefahren')
stand(50); show('50 min gestanden OHNE Pause-Knopf')
drive(20); show('weiter 20 min → Verstoß')
M.setActivity(T, 'rest', 0); stand(45); show('45 min Pause')
drive(200); show('noch 3:20 → über 9 h/Tag')
M.rest(T, 11); show('Schlafen 11 h')
drive(10); show('neuer Tag, 10 min')
local ok, why = M.setActivity(T, 'rest', 25); out[#out + 1] = 'Pause während der Fahrt: ' .. tostring(ok) .. ' – ' .. tostring(why)
M.restFor(T, 2 * 3600, notify); show('Fähre 2 h')
local v = M.view(T); out[#out + 1] = 'Diagramm-Segmente 24 h: ' .. #v.chart
-- reduced rests: four 9 h rests in a week → the 4th is a violation; then a weekly rest resets
for k = 1, 4 do drive(10); M.restFor(T, 9 * 3600, notify); drive(5); show('Tag ' .. k .. ': 9 h geruht, losgefahren (redLeft ' .. M.view(T).redLeft .. ')') end
M.restFor(T, 45 * 3600, notify); drive(5); show('Wochenruhe 45 h (redLeft ' .. M.view(T).redLeft .. ')')
-- the two weeks: 50 h, weekly rest, then 41 h → over 90 h
T.week = 50 * 3600; M.restFor(T, 24 * 3600, notify); drive(5); T.week = 40 * 3600; drive(61); show('Doppelwoche: 50 h + 41 h (noch ' .. M.view(T).fortnightText .. ')')
return table.concat(out, '\\n')
`
const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L)
if (lauxlib.luaL_loadstring(L, to_luastring(code)) !== 0 || lua.lua_pcall(L, 0, 1, 0) !== 0) { console.log('ERR', lua.lua_tojsstring(L, -1)); process.exit(1) }
console.log(lua.lua_tojsstring(L, -1))
