// Offline check of the police report (accidents.lua) with the street lookup (streets.lua) on the shipped OSM data:
// a walker hit at 70 km/h where 50 is allowed, at a real place. node tools/sim_report.js <fernfahrer lua dir> <streets dir> <fengari dir> [lat lon]
const fs = require('fs'), path = require('path')
const [luaDir, dataDir, fdir, latArg, lonArg] = process.argv.slice(2)
const { lua, lauxlib, lualib, to_luastring } = require(path.join(fdir, 'node_modules', 'fengari'))
const acc = fs.readFileSync(path.join(luaDir, 'accidents.lua'), 'utf8')
const str = fs.readFileSync(path.join(luaDir, 'streets.lua'), 'utf8')
const files = fs.readdirSync(dataDir).filter(f => f.endsWith('.json') && !f.startsWith('_'))
// the JSON files decoded in JS and handed to Lua as table literals
const lit = v => v === null || v === undefined ? 'nil' : Array.isArray(v) ? '{' + v.map(lit).join(',') + '}'
  : typeof v === 'object' ? '{' + Object.entries(v).map(([k, x]) => '[' + JSON.stringify(k) + ']=' + lit(x)).join(',') + '}'
  : typeof v === 'string' ? JSON.stringify(v) : String(v)
const FL = 'FILES={' + files.map(f => '[' + JSON.stringify(f) + ']=' + lit(JSON.parse(fs.readFileSync(path.join(dataDir, f), 'utf8')))).join(',') + '}'
const lat = Number(latArg || 51.8946), lon = Number(lonArg || 6.9839)
const code = `${FL}
FS = { fileExists = function(self, p) return FILES[p:match('[^/]+$')] ~= nil end }
function jsonReadFile(p) return FILES[p:match('[^/]+$')] end
function log() end
local V = {} V.__index = V
function vec3(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
package.loaded['fernfahrer/pool'] = {}
local ST = (function() ${str} end)()
local A = (function() ${acc} end)()
local lat, lon = ${lat}, ${lon}
local street, pl = ST.nameAt(lat, lon), ST.placeAt(lat, lon)
local ctx = { placeOf = function() return { road = 'auf der ' .. tostring(street) .. ' (innerorts, Tempo 50)',
  near = pl and ((pl.inside and 'in ' or 'bei ') .. pl.name), street = street, town = pl and pl.name } end,
  clockText = function() return '18:42' end }
local doc = A._buildReport(ctx, { involved = {}, peds = 1, preSpeed = 70, limit = 50, severity = 'schwer', ambulance = true,
  dmg = 3000, lat = lat, lon = lon, vehicle = 'Cherrier Percheron' })
local out = { 'Straße: ' .. tostring(street), 'Ort: ' .. tostring(pl and pl.name) .. ' (drin: ' .. tostring(pl and pl.inside) .. ')',
  'Schuld: ' .. doc.fault, 'Verletzte: ' .. doc.injured, 'Bußgeld: ' .. tostring(doc.fine), 'Punkte: ' .. tostring(doc.points),
  'Einschätzung: ' .. tostring(doc.verdict) }
for _, l in ipairs(doc.legal or {}) do out[#out + 1] = '  - ' .. l end
out[#out + 1] = 'Text: ' .. doc.text
return table.concat(out, '\\n')`
const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L)
if (lauxlib.luaL_loadstring(L, to_luastring(code)) !== 0) { console.log('load', lua.lua_tojsstring(L, -1)); process.exit(1) }
if (lua.lua_pcall(L, 0, 1, 0) !== 0) { console.log('run', lua.lua_tojsstring(L, -1)); process.exit(1) }
console.log(lua.lua_tojsstring(L, -1))
