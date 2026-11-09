-- Trucks of Earth: the music under the moments (art/sound/fernfahrer/mood, composed by tools/build_mood.js). One bed at a time, played through the game's own audio
-- the way the navi's voice goes; when a piece has run, the next begins while the last one is still fading. A short piece (a delivery, a new day) stops the bed for its length.
-- M.want(name or nil, t) every second from career.lua, M.sting(name, t), M.knock(kind), M.setLevel(x).
local M = {}
M.DIR = 'art/sound/fernfahrer/mood/'
M.BED = {
  rast = { { 'rast1', 60 }, { 'rast2', 42 }, vol = 0.55 },
  droh = { { 'droh', 32 }, vol = 0.6 }, warm = { { 'warm', 32 }, vol = 0.5 }, komisch = { { 'komisch', 28 }, vol = 0.5 }, polizei = { { 'polizei', 36 }, vol = 0.55 },
  fahrt_tag = { { 'fahrt_tag', 52 }, vol = 0.5, once = true }, fahrt_nacht = { { 'fahrt_nacht', 52 }, vol = 0.5, once = true },
}
M.STING = { ok_gut = { 11, 0.7 }, ok_mau = { 9, 0.65 }, morgen = { 13, 0.55 }, panne = { 11, 0.6 } }
local OVERLAP, COOLDOWN = 3.2, 25
local level, cur, src, last, nextAt, idx, stingEnd, stingAt = 1, nil, nil, nil, 0, 0, 0, -99

local function play(file, vol)
  if not (Engine and Engine.Audio and Engine.Audio.playOnce) then return nil end
  local ok, res = pcall(Engine.Audio.playOnce, 'AudioGui', M.DIR .. file .. '.wav', { volume = math.min(1, vol) })
  return ok and type(res) == 'table' and res.sourceId or nil
end
local function fadeOut(id, s)
  if not id or not scenetree or not scenetree.findObjectById then return end
  local o = scenetree.findObjectById(id)
  if o and o.stop then pcall(o.stop, o, s, 1) end
end
function M.setLevel(x) level = x or 1 end
local function stopBed(s) fadeOut(src, s); fadeOut(last, s); src, last = nil, nil end
function M.want(name, t)
  if t < stingEnd then name = nil end
  if name ~= cur then
    stopBed(1.8)
    cur, nextAt, idx = name, t, name and math.random(1, #M.BED[name]) or 0
  end
  if not cur or t < nextAt then return end
  local B = M.BED[cur]
  idx = (idx % #B) + 1
  last, src = src, play(B[idx][1], B.vol * level)
  nextAt = B.once and math.huge or (t + B[idx][2] - OVERLAP)
end
function M.sting(name, t)
  local s = M.STING[name]
  if not s or t - stingAt < COOLDOWN then return nil end
  stingAt, stingEnd = t, t + s[1] - 1.5
  stopBed(0.8)
  cur = nil
  play(name, s[2] * level)
  return s[1]
end
-- (a knuckle on the driver's door: only the left channel in the file, whatever the music is set to)
function M.knock(kind) play(kind == 2 and 'klopf2' or 'klopf1', 0.9) end
function M.stop() stopBed(1); cur = nil end
return M
