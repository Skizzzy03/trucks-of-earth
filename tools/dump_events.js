// What every kind of road event lays out, taken from the mod's own events.lua (run without the game):
// node tools/dump_events.js <events.lua> <fengari dir> <out.json>
const fs = require('fs'), path = require('path')
const [file, fdir, out] = process.argv.slice(2)
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require(path.join(fdir, 'node_modules', 'fengari'))
const src = fs.readFileSync(file, 'utf8')
const code = `
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
function vec3(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
log = function() end
package.preload['fernfahrer/pool'] = function() return {} end
local chunk = assert(load(EV_SRC, 'events'))
local M = chunk()
local function js(v)
  local t = type(v)
  if t == 'nil' then return 'null' elseif t == 'number' or t == 'boolean' then return tostring(v)
  elseif t == 'string' then return string.format('%q', v):gsub('\\\\\\n', '\\\\n')
  elseif t == 'table' then
    if #v > 0 or next(v) == nil then local o = {}; for i, x in ipairs(v) do o[i] = js(x) end; return '[' .. table.concat(o, ',') .. ']' end
    local o = {}; for k, x in pairs(v) do o[#o + 1] = string.format('%q', tostring(k)) .. ':' .. js(x) end; return '{' .. table.concat(o, ',') .. '}'
  end
  return 'null'
end
local res = {}
local keys = {}
for k in pairs(M.KINDS) do keys[#keys + 1] = k end
table.sort(keys)
math.randomseed(3)
for _, k in ipairs(keys) do
  if k == 'roadworks' then
    local vs = {}
    for v in pairs(M.ROADWORKS) do vs[#vs + 1] = v end
    table.sort(vs)
    for _, v in ipairs(vs) do
      local l = M.layoutOf(k, v, 100)
      l.kind, l.variant, l.vweight = k, v, M.ROADWORKS[v].weight
      res[#res + 1] = l
    end
  else
    local l = M.layoutOf(k, nil, 100)
    l.kind = k
    res[#res + 1] = l
  end
end
RESULT = js(res)
`
const L = lauxlib.luaL_newstate()
lualib.luaL_openlibs(L)
lua.lua_pushstring(L, to_luastring(src)); lua.lua_setglobal(L, to_luastring('EV_SRC'))
if (lauxlib.luaL_dostring(L, to_luastring(code))) { console.error(to_jsstring(lua.lua_tostring(L, -1))); process.exit(1) }
lua.lua_getglobal(L, to_luastring('RESULT'))
const json = to_jsstring(lua.lua_tostring(L, -1))
const data = JSON.parse(json)
fs.writeFileSync(out, JSON.stringify(data))
console.log(data.length, 'scenes:', data.map(d => (d.variant || d.kind) + '(' + (d.items ? d.items.length : 0) + ')').join(', '))
