-- Trucks of Earth: a beer, a cigarette, a joint in the cab (HUD buttons, FernfahrerKabine). A short scene in
-- front of the driver's camera with the mod's own props (levels/beamng_earth/art/shapes/fernfahrer/props, built by
-- tools/build_props.js): the cigarette / joint to the lips and lit with a lighter, smoked with a puff now and then; the
-- can comes up, is opened ("pssst"), one sip and back down. The body keeps the rest: blood alcohol (‰) and THC
-- (ng/ml) over game time – a police check (career controlCheck) and an accident report (accidents.lua) read them.
-- M.attach(state) with the save's table, M.start(kind, ctx), M.render() every frame before drawing (onPreRender: the
-- camera of this frame), M.tick(gameHours), M.readings(), M.hud(), M.reset().

local M = {}

M.DIR = '/levels/beamng_earth/art/shapes/fernfahrer/props/'
M.BEER_BAC = 0.24          -- (‰ per 0.33 l can, 5 %: about 13 g of alcohol in an 80 kg man)
M.ABSORB_PER_H = 0.7       -- (‰ per game hour taken up from the stomach)
M.BURN_PER_H = 0.15        -- (‰ per game hour broken down)
M.SMOKE_BURN = 4           -- (the alcohol goes this much faster while a cigarette is being smoked)
M.JOINT_THC = 14           -- (ng/ml in the blood after a joint)
M.THC_HALF_H = 2.0         -- (game hours: from 14 to the 3.5 limit in about 4 h)
M.SMOKE_S = { cigarette = 75, joint = 95 }   -- (seconds of real time from lit to put out)

local st                    -- the save's table: { bac, stomach, thc, beers, cigs, joints }
local A                     -- the scene running: { kind, t, objs = {}, lights = {}, ... }
local n = 0

function M.attach(state)
  st = state
  st.bac, st.stomach, st.thc = st.bac or 0, st.stomach or 0, st.thc or 0
  st.beers, st.cigs, st.joints = st.beers or 0, st.cigs or 0, st.joints or 0
end

-- the body over game time
function M.tick(hours)
  if not st or not hours or hours <= 0 then return end
  local take = math.min(st.stomach, M.ABSORB_PER_H * hours)
  st.stomach = st.stomach - take
  local burn = M.BURN_PER_H * ((A and A.kind == 'cigarette') and M.SMOKE_BURN or 1)
  st.bac = math.max(0, st.bac + take - (st.bac > 0 and burn * hours or 0))
  if st.thc > 0.05 then st.thc = st.thc * 0.5 ^ (hours / M.THC_HALF_H) else st.thc = 0 end
end

function M.readings()
  if not st then return { bac = 0, thc = 0 } end
  return { bac = st.bac, thc = st.thc }
end

-- objects ----------------------------------------------------------------------------------------------------------

local function makeStatic(shape)
  local o = createObject('TSStatic')
  if not o then return nil end
  o:setField('shapeName', 0, M.DIR .. shape .. '.dae')
  o:setField('collisionType', 0, 'None')
  o:setField('decalType', 0, 'None')
  o.canSave = false
  n = n + 1
  o:registerObject('ff_vice_' .. n)
  return o
end

local function makeLight(color, radius)
  local l = createObject('PointLight')
  if not l then return nil end
  l.canSave = false
  pcall(function()
    l.radius = radius
    l:setField('color', 0, color)
    l:setField('brightness', 0, '0')
    l:setField('castShadows', 0, '0')
  end)
  n = n + 1
  l:registerObject('ff_vice_l' .. n)
  return l
end

local function drop(o) if o then pcall(function() o:delete() end) end end

local function clear()
  if not A then return end
  for _, o in pairs(A.objs) do drop(o) end
  for _, l in pairs(A.lights) do drop(l) end
  A = nil
end

-- the camera ---------------------------------------------------------------------------------------------------------

local function camFrame()
  local pos, q
  if core_camera and core_camera.getPosition then
    local ok, p = pcall(core_camera.getPosition)
    local okQ, qq = pcall(core_camera.getQuat)
    if ok and okQ then pos, q = p, qq end
  end
  if (not pos or not q) and getCameraPosition and getCameraQuat then pos, q = getCameraPosition(), getCameraQuat() end
  if not pos or not q then return nil end
  q = quat(q)
  return vec3(pos), q * vec3(0, 1, 0), q * vec3(1, 0, 0), q * vec3(0, 0, 1)
end

function M.driverView()
  if not core_camera or not core_camera.getActiveCamName then return true end
  local ok, name = pcall(core_camera.getActiveCamName, 0)
  if not ok then ok, name = pcall(core_camera.getActiveCamName) end
  return not ok or name == nil or name == 'driver'
end

local function rot(v, k, a)       -- v turned about the unit axis k by a (radians)
  local c, s = math.cos(a), math.sin(a)
  return v * c + k:cross(v) * s + k * (k:dot(v) * (1 - c))
end

-- keyframes: { t, f, r, u, p (pitch°), y (yaw°), roll (°) } in the camera's frame (forward, right, up; metres)
local function smooth(x) return x * x * (3 - 2 * x) end
local function sample(track, t)
  if t <= track[1].t then return track[1] end
  for i = 1, #track - 1 do
    local a, b = track[i], track[i + 1]
    if t <= b.t then
      local k = smooth((t - a.t) / math.max(1e-6, b.t - a.t))
      local out = {}
      for _, key in ipairs({ 'f', 'r', 'u', 'p', 'y', 'roll' }) do out[key] = (a[key] or 0) + ((b[key] or 0) - (a[key] or 0)) * k end
      return out
    end
  end
  return track[#track]
end

-- place `o` at the keyframe pose: its +y along the camera's forward turned by pitch / yaw, its +z the turned up
local function pose(o, k, cam, F, Rt, U, dz)
  local fwd, up = F, U
  if (k.y or 0) ~= 0 then fwd, up = rot(fwd, U, math.rad(k.y)), up end
  local right = fwd:cross(up):normalized()
  if (k.p or 0) ~= 0 then local a = math.rad(k.p); fwd, up = rot(fwd, right, a), rot(up, right, a) end
  if (k.roll or 0) ~= 0 then up = rot(up, fwd, math.rad(k.roll)) end
  local p = cam + F * (k.f or 0) + Rt * (k.r or 0) + U * (k.u or 0) + (dz and up * dz or vec3(0, 0, 0))
  local q = quatFromDir(fwd, up)
  o:setPosRot(p.x, p.y, p.z, q.x, q.y, q.z, q.w)
  return p, fwd, up
end

-- the scenes ---------------------------------------------------------------------------------------------------------

local MOUTH = { f = 0.115, r = 0.0, u = -0.085, p = -9 }        -- (between the lips, pointing a little down)
local function mouthAt(t, extra) local k = { t = t }; for a, b in pairs(MOUTH) do k[a] = b end; for a, b in pairs(extra or {}) do k[a] = b end; return k end

local SCENES = {
  beer = {
    can = {
      { t = 0, f = 0.42, r = 0.24, u = -0.48, p = 0 },
      { t = 0.9, f = 0.36, r = 0.07, u = -0.19, p = 0 },
      { t = 1.6, f = 0.36, r = 0.07, u = -0.19, p = 0 },              -- (opened here)
      { t = 2.4, f = 0.15, r = 0.0, u = -0.115, p = 58 },              -- (to the lips, tipped)
      { t = 3.5, f = 0.15, r = 0.0, u = -0.11, p = 66 },               -- (a sip)
      { t = 4.3, f = 0.36, r = 0.07, u = -0.19, p = 0 },
      { t = 5.1, f = 0.42, r = 0.24, u = -0.5, p = 0 },
    },
    sounds = { { t = 1.05, name = 'pssst' }, { t = 2.7, name = 'gulp' } },
    len = 5.2,
  },
}
-- (2026-11-08) a coffee and an energy drink: the same movement as the beer, nothing in the blood
SCENES.energy = { can = SCENES.beer.can, sounds = SCENES.beer.sounds, len = 5.2 }
SCENES.coffee = { can = SCENES.beer.can, sounds = { { t = 2.7, name = 'gulp' } }, len = 5.2 }
local function isDrink(kind) return kind == 'beer' or kind == 'coffee' or kind == 'energy' end

local function smokeScene(kind)
  local L = M.SMOKE_S[kind]
  local tipLen = kind == 'joint' and 0.098 or 0.084
  return {
    stick = {
      { t = 0, f = 0.42, r = 0.2, u = -0.46, p = -20, y = 25 },
      mouthAt(0.9), mouthAt(L - 1.2), { t = L, f = 0.4, r = 0.18, u = -0.5, p = -30, y = 20 },
    },
    -- the lighter comes up under the tip, clicks, the flame for a moment; then away
    lighter = {
      { t = 0.6, f = 0.34, r = 0.14, u = -0.52, p = 0, roll = -10 },
      { t = 1.4, f = MOUTH.f + tipLen + 0.012, r = 0.012, u = MOUTH.u - 0.094, p = 0, roll = -8 },
      { t = 2.9, f = MOUTH.f + tipLen + 0.012, r = 0.012, u = MOUTH.u - 0.094, p = 0, roll = -8 },
      { t = 3.6, f = 0.34, r = 0.14, u = -0.52, p = 0, roll = -10 },
    },
    lighterLen = 3.6, flameFrom = 1.55, flameTo = 2.85, litAt = 2.1,
    sounds = { { t = 1.5, name = 'click' }, { t = 1.55, name = 'flame' }, { t = 2.3, name = 'puff' } },
    len = L, tipLen = tipLen,
  }
end
SCENES.cigarette = smokeScene('cigarette')
SCENES.joint = smokeScene('joint')

function M.busy() return A ~= nil end

-- (the 3D props in front of the camera: off – in game they were not to be seen, 2026-11-03; the scene is drawn by
-- the full-screen HUD overlay FernfahrerSzene instead, and the camera itself moves: the head back for the sip, a nod)
M.PROPS = false

-- the view under the influence: the camera sways a little, the field of view breathes. BeamNG's camera hands its
-- final pose to setCameraPosRotFovNearClipC once a frame (core/cameraModes/gameengine.lua, a global looked up on
-- every call): wrapped, the pose gets a small turn in the camera's own frame on its way. 0 = untouched.
local function qmul(ax, ay, az, aw, bx, by, bz, bw)
  return aw * bx + ax * bw + ay * bz - az * by,
         aw * by - ax * bz + ay * bw + az * bx,
         aw * bz + ax * by - ay * bx + az * bw,
         aw * bw - ax * bx - ay * by - az * bz
end

M.fxEnabled = true          -- (the office's "Rausch-Effekt": off = no sway, no tint; the readings still count)
function M.intensity()
  if not st or not M.fxEnabled then return 0 end
  local i = math.min(1, st.bac / 0.8) * 0.7 + math.min(1, st.thc / 10) * 0.8
  return math.min(1.2, i)
end

local function bell(t, a, b) if t <= a or t >= b then return 0 end return math.sin((t - a) / (b - a) * math.pi) end

-- (2026-11-08) the head turned towards someone at the driver's window: degrees to the left, and up; 0, 0 = straight ahead.
-- Eased, and only from the cab.
local look = { y = 0, p = 0, ty = 0, tp = 0, at = nil }
function M.setLook(yaw, pitch) look.ty, look.tp = yaw or 0, pitch or 0 end
local function inCab()
  if not core_camera or not core_camera.getActiveCamName then return true end
  local ok, name = pcall(core_camera.getActiveCamName, 0)
  name = ok and tostring(name or '') or ''
  return name == 'driver' or name:find('^occupant') ~= nil or name:find('onboard') ~= nil or name:find('cockpit') ~= nil or name:find('interior') ~= nil
end

-- degrees: pitch (up +), roll, yaw; and the change of the field of view
function M.camOffset()
  local I = M.intensity()
  local t = os.clock()
  local pitch, roll, yaw, dfov = 0, 0, 0, 0
  local dt = math.min(0.1, t - (look.at or t))
  look.at = t
  local k = 1 - math.exp(-dt * 2.6)
  look.y, look.p = look.y + (look.ty - look.y) * k, look.p + (look.tp - look.p) * k
  if math.abs(look.y) > 0.05 and inCab() then
    -- (a little life in it: nobody holds their head perfectly still)
    yaw = look.y + math.sin(t * 0.7) * 0.8
    pitch = look.p + math.sin(t * 0.53 + 1) * 0.4
  end
  if I > 0.02 then
    roll = I * 1.6 * math.sin(t * 0.55)
    pitch = pitch + I * 0.6 * math.sin(t * 0.37 + 1)
    yaw = yaw + I * 0.9 * math.sin(t * 0.29 + 2)
    dfov = I * 3.0 * math.sin(t * 0.8)
  end
  if A and isDrink(A.kind) then
    pitch = pitch + 8 * bell(A.t, 2.0, 3.9) - 3 * bell(A.t, 4.3, 4.9)    -- (the head back for the sip, then a nod)
  elseif A then
    pitch = pitch - 2.5 * bell(A.t, 1.2, 3.0)                            -- (looking down at the flame)
  end
  return pitch, roll, yaw, dfov
end

local origSet
local lastQ
function M.installCam()
  local f = rawget(_G, 'setCameraPosRotFovNearClipC')
  if origSet or type(f) ~= 'function' then return end
  origSet = f
  rawset(_G, 'setCameraPosRotFovNearClipC', function(x, y, z, qx, qy, qz, qw, fov, near)
    -- (2026-11-09, BeamNG.Earth 1.9) its 3D map flies the camera up to the globe: no camera flight or wobble of ours on that
    local m3 = rawget(_G, 'beamngEarth_map3d')
    if m3 and m3.isActive and (m3.isActive() or m3.isTransitioning()) then return origSet(x, y, z, qx, qy, qz, qw, fov, near) end
    -- (2026-11-09: what stands in the cab first: a pose close to it must not be one frame behind a truck doing 25 m/s)
    if M.override and M.camHook then pcall(M.camHook) end
    -- a camera flight (cinematic.lua): it gets the game's pose and returns the one to draw
    if M.override then
      local okO, ox, oy, oz, oqx, oqy, oqz, oqw, ofov = pcall(M.override, x, y, z, qx, qy, qz, qw, fov)
      if okO and ox then x, y, z, qx, qy, qz, qw, fov = ox, oy, oz, oqx, oqy, oqz, oqw, ofov or fov
      elseif not okO then M.override = nil end
    end
    -- (2026-11-08) a joint: the look follows slowly (the camera turns late); only while the THC is up
    if st and M.fxEnabled and st.thc >= 3 then
      local k = 1 - math.min(0.72, 0.4 + st.thc * 0.025)
      if lastQ then
        local d = lastQ[1] * qx + lastQ[2] * qy + lastQ[3] * qz + lastQ[4] * qw
        if d > 0.9 then
          local s = d < 0 and -1 or 1
          local ax, ay, az, aw = lastQ[1] * s + (qx - lastQ[1] * s) * k, lastQ[2] * s + (qy - lastQ[2] * s) * k, lastQ[3] * s + (qz - lastQ[3] * s) * k, lastQ[4] * s + (qw - lastQ[4] * s) * k
          local l = math.sqrt(ax * ax + ay * ay + az * az + aw * aw)
          if l > 1e-6 then qx, qy, qz, qw = ax / l, ay / l, az / l, aw / l end
        end
      end
      lastQ = { qx, qy, qz, qw }
    else
      lastQ = nil
    end
    local ok, p, r, yw, df = pcall(M.camOffset)
    if ok and p and (p ~= 0 or r ~= 0 or yw ~= 0 or df ~= 0) then
      -- (yaw about the camera's up, pitch about its right, roll about its forward; applied in its own frame)
      local hy, hp, hr = math.rad(yw) / 2, math.rad(p) / 2, math.rad(r) / 2
      local lx, ly, lz, lw = qmul(0, 0, math.sin(hy), math.cos(hy), math.sin(hp), 0, 0, math.cos(hp))
      lx, ly, lz, lw = qmul(lx, ly, lz, lw, 0, math.sin(hr), 0, math.cos(hr))
      qx, qy, qz, qw = qmul(qx, qy, qz, qw, lx, ly, lz, lw)
      fov = (fov or 60) + df
    end
    -- (2026-11-09: what sits in the cab is placed here, with the very state the camera of this frame was made from)
    if M.camHook then pcall(M.camHook) end
    return origSet(x, y, z, qx, qy, qz, qw, fov, near)
  end)
end

function M.uninstallCam()
  if origSet then rawset(_G, 'setCameraPosRotFovNearClipC', origSet); origSet = nil end
end

-- ctx: { notify(text), sound(name), driving() → speed m/s }
function M.start(kind, ctx)
  if not st or not SCENES[kind] then return false end
  if A then ctx.notify(isDrink(A.kind) and 'Erst austrinken …' or 'Erst zu Ende rauchen …'); return false end
  local sc = SCENES[kind]
  A = { kind = kind, t = 0, sc = sc, objs = {}, lights = {}, played = {}, ctx = ctx, view = M.driverView() }
  if kind == 'beer' then
    if M.PROPS then A.objs.can = makeStatic('ff_beer') end
    st.beers = st.beers + 1
    st.stomach = st.stomach + M.BEER_BAC
  elseif isDrink(kind) then
    -- (coffee, energy: nothing for the blood; the career takes the tiredness off)
  else
    if M.PROPS then
      A.objs.stick = makeStatic(kind == 'joint' and 'ff_joint' or 'ff_cigarette')
      A.objs.lighter = makeStatic('ff_lighter')
      A.lights.ember = makeLight('1 0.38 0.08 1', 0.6)
    end
    if kind == 'joint' then st.joints = st.joints + 1 else st.cigs = st.cigs + 1 end
  end
  -- the overlay plays the same timeline (FernfahrerSzene): the times it needs
  if ctx.scene then pcall(ctx.scene, { kind = kind, len = sc.len, litAt = sc.litAt, flameFrom = sc.flameFrom, flameTo = sc.flameTo }) end
  return true
end

local function hideAll()
  for _, o in pairs(A.objs) do pcall(function() o:setPosRot(0, 0, -5000, 0, 0, 0, 1) end) end
  for _, l in pairs(A.lights) do pcall(function() l:setField('brightness', 0, '0') end) end
end

-- the scene on, one frame: at the camera of this frame (called before drawing)
function M.render(dt)
  if not A then return end
  A.t = A.t + (dt or 0)
  local t, sc = A.t, A.sc
  for _, s in ipairs(sc.sounds or {}) do
    if t >= s.t and not A.played[s.name] then A.played[s.name] = true; pcall(A.ctx.sound, s.name) end
  end
  -- a joint: the THC comes in while smoking
  if A.kind == 'joint' and t > sc.litAt then st.thc = math.max(st.thc, M.JOINT_THC * math.min(1, (t - sc.litAt) / (sc.len * 0.6))) end
  if t >= sc.len then
    if A.kind == 'joint' then A.ctx.notify('Joint aus. Polizeikontrollen finden THC noch Stunden später (Grenzwert 3,5 ng/ml).', 7) end
    if A.ctx.scene then pcall(A.ctx.scene, { kind = false }) end
    clear()
    return
  end
  if not M.PROPS then
    -- the drags: the sound and the overlay's glow / smoke
    if not isDrink(A.kind) and t > sc.litAt + 3 and t < sc.len - 1.5 then
      local nPuff = math.floor((t - sc.litAt - 3) / 12)
      if nPuff ~= A.nPuff then
        A.nPuff = nPuff
        pcall(A.ctx.sound, 'puff')
        if A.ctx.scene then pcall(A.ctx.scene, { puff = nPuff + 1 }) end
      end
    end
    return
  end
  local cam, F, Rt, U = camFrame()
  A.view = M.driverView()
  if not cam or not A.view then hideAll(); return end
  if A.kind == 'beer' then
    if A.objs.can then
      local k = sample(sc.can, t)
      -- (opening: the can gives a little jolt)
      if t > 1.0 and t < 1.3 then k = { f = k.f, r = k.r, u = k.u + math.sin((t - 1.0) * 60) * 0.003, p = k.p } end
      pose(A.objs.can, k, cam, F, Rt, U)
    end
    return
  end
  -- smoking: the stick, a puff every 12 s (it comes up a little, the tip glows)
  local k = sample(sc.stick, t)
  local puff = 0
  if t > sc.litAt + 3 and t < sc.len - 1.5 then
    local ph = (t - sc.litAt - 3) % 12
    if ph < 1.6 then puff = math.sin(ph / 1.6 * math.pi) end
    local nPuff = math.floor((t - sc.litAt - 3) / 12)
    if nPuff ~= A.nPuff then A.nPuff = nPuff; pcall(A.ctx.sound, 'puff') end
  end
  k = { f = k.f, r = k.r, u = k.u, p = (k.p or 0) + puff * 6, y = k.y }
  local _, fwd = pose(A.objs.stick, k, cam, F, Rt, U)
  local p0 = cam + F * k.f + Rt * k.r + U * k.u
  local tip = p0 + fwd * (sc.tipLen + 0.004)
  if A.lights.ember then
    local lit = t > sc.litAt
    local b = lit and (0.35 + puff * 1.1 + math.random() * 0.08) or 0
    pcall(function() A.lights.ember:setPosition(tip); A.lights.ember:setField('brightness', 0, string.format('%.2f', b)) end)
  end
  if A.objs.lighter then
    if t <= sc.lighterLen then
      local lk = sample(sc.lighter, math.max(t, sc.lighter[1].t))
      local lp, _, lup = pose(A.objs.lighter, lk, cam, F, Rt, U)
      -- the flame on top while it burns, flickering
      if t > sc.flameFrom and t < sc.flameTo then
        if not A.objs.flame then A.objs.flame = makeStatic('ff_flame'); A.lights.flame = makeLight('1 0.62 0.25 1', 1.4) end
        local fk = { f = lk.f, r = lk.r, u = lk.u, p = lk.p, roll = (lk.roll or 0) + (math.random() - 0.5) * 6 }
        pose(A.objs.flame, fk, cam, F, Rt, U, 0.079)
        pcall(function()
          A.lights.flame:setPosition(lp + lup * 0.09)
          A.lights.flame:setField('brightness', 0, string.format('%.2f', 1.2 + math.random() * 0.5))
        end)
      elseif A.objs.flame then
        drop(A.objs.flame); drop(A.lights.flame); A.objs.flame, A.lights.flame = nil, nil
      end
    else
      drop(A.objs.lighter); A.objs.lighter = nil
    end
  end
end

function M.hud()
  local r = { bac = st and st.bac or 0, thc = st and st.thc or 0, busy = A and A.kind or nil }
  if st and st.stomach > 0.01 then r.rising = true end
  r.fx = M.intensity()                                -- (the overlay's tint and vignette)
  r.thcShare = st and M.fxEnabled and math.min(1, st.thc / 10) or 0   -- (effect off: no tint either)
  return r
end

function M.reset()
  if A and A.ctx and A.ctx.scene then pcall(A.ctx.scene, { kind = false }) end
  clear()
  M.uninstallCam()
end

-- (offline tests)
M._sample = sample
M._scenes = SCENES

return M
