-- Trucks of Earth: virtual mirrors as in the classic truck simulators 2 – a left and a right mirror shown on the screen,
-- each a camera of its own (the engine's RenderView into a named texture, drawn with ImGui like the vehicle detail
-- viewer of the game's editor). The cameras sit at the truck's real outside mirrors (the jbeam mirror nodes), look
-- back along the side and follow the angles set for those mirrors (cockpit strip 🪞 / game mirror offsets). The game's
-- own mirrors are poor on low graphics settings (2026-11-04).
-- Two extra views of the scene cost frame time: off by default, toggled with the key (Ctrl+Shift+M) or the 🪞 page.
-- The windows can be dragged; their places and the size are kept in the career's settings.
-- M.update(dt, ctx) every frame (onPreRender); M.toggle(); M.setOn(b); M.setSize(d); M.destroy().

local M = {}

local im = ui_imgui
local imUtils
local SIDES = { 'L', 'R' }

M.on = false
-- hfov: the mirror's field of view across (degrees); yaw: how far it looks outward from straight back (degrees).
-- (2026-11-04: 30° vertical in a tall window was 22° across – only the trailer, never the corner of a house when
-- turning. Now set across, wider, a little more outward – a truck mirror is slightly convex. Both can be set by hand
-- in the 🪞 page's ⚙; "Auto" goes back to these.)
M.AUTO = { hfov = 52, yaw = 10, bright = 0.85 }
M.cfg = { w = 220, h = 300, hfov = M.AUTO.hfov, yaw = M.AUTO.yaw, bright = M.AUTO.bright, x = {}, y = {} }
local views = {}             -- side -> { name, rv }
local found = {}             -- vid -> { L = {node, mesh}, R = ... }
local saveAt = 0
local onSave                 -- (career: writes the settings)

local function vdataMirrors(veh)
  local okV, vd = pcall(function() return core_vehicle_manager.getVehicleData(veh:getID()) end)
  return okV and vd and vd.vdata and vd.vdata.mirrors or nil
end

-- the truck's outside mirrors: per side the mirror furthest out (the inner rear-view mirror is near the middle)
-- (2026-11-07: kept per vehicle AND its model and parts – a vehicle change (replaceVehicle) keeps the object's id, and
-- the old truck's mirror nodes pointed somewhere else on the new one: the right place in the HUD, the wrong picture)
local function vehKey(veh)
  local okJ, jb = pcall(function() return veh:getJBeamFilename() end)
  local okC, pc = pcall(function() return veh.partConfig end)
  local pcs = okC and pc or ''
  if type(pcs) ~= 'string' then pcs = tostring(pcs) end
  return tostring(veh:getID()) .. '|' .. tostring(okJ and jb or '') .. '|' .. pcs:sub(1, 200)
end
local function findMirrors(veh)
  local vid = vehKey(veh)
  if found[vid] then return found[vid] end
  local res = {}
  local fwd, up = veh:getDirectionVector(), veh:getDirectionVectorUp()
  local right = fwd:cross(up):normalized()
  for _, m in pairs(vdataMirrors(veh) or {}) do
    local node = m.idRef
    if type(node) == 'number' and node >= 0 then
      local okP, rel = pcall(function() return veh:getNodePosition(node) end)
      if okP and rel then
        local side = vec3(rel):dot(right)
        if math.abs(side) > 0.5 then
          local k = side < 0 and 'L' or 'R'
          if not res[k] or math.abs(side) > res[k].s then res[k] = { node = node, s = math.abs(side), mesh = m.mesh } end
        end
      end
    end
  end
  -- (nothing found yet – a vehicle just spawned has no data: looked again next time, not kept empty)
  if next(res) then found[vid] = res end
  return res
end
-- a vehicle changed or reset: its mirrors looked up anew
function M.forgetVehicle() found = {} end

-- the adjusted angle of that mirror (degrees: x up/down, z sideways), doubled as a mirror doubles a turn
local function offsetOf(veh, mesh)
  if not mesh or not core_vehicle_mirror then return 0, 0 end
  local okA, t = pcall(core_vehicle_mirror.getAnglesOffset, veh:getID(), veh)
  local o = okA and t and t[mesh] and t[mesh].angleOffset
  return o and (o.x or 0) * 2 or 0, o and (o.z or 0) * 2 or 0
end

local function camFor(veh, k)
  local fwd, up = veh:getDirectionVector(), veh:getDirectionVectorUp()
  local right = fwd:cross(up):normalized()
  local sgn = k == 'L' and -1 or 1
  local info = findMirrors(veh)[k]
  local rel
  if info then
    local okP, r = pcall(function() return veh:getNodePosition(info.node) end)
    rel = okP and r and vec3(r) or nil
  end
  -- (no mirror nodes: about where a truck's mirror is)
  rel = rel or (right * (sgn * 1.35) + up * 1.9 + fwd * 1.2)
  local pos = veh:getPosition() + rel + right * (sgn * 0.3)
  local ox, oz = offsetOf(veh, info and info.mesh)
  -- back along the side, a little outward and down (as a truck mirror is set: the trailer's edge at the inside)
  local yaw = math.rad((M.cfg.yaw or M.AUTO.yaw) + sgn * oz)
  local pitch = math.rad(3 + ox)
  local dir = (-fwd) * math.cos(yaw) + right * (sgn * math.sin(yaw))
  dir = (dir - up * math.tan(pitch)):normalized()
  return pos, dir, up
end

-- (2026-11-04: the first version cost ~15 of 50 fps. Each mirror view rendered the whole scene in full: with the
-- truck's own dynamic mirrors – each an extra cubemap render – reflections, shadows, full detail, 700 m. Now as the
-- game's split screen does for its extra views: no vehicle mirrors and reflections in them, no shadows, coarser
-- meshes, no ground cover, 320 m, a smaller texture, and the two mirrors drawn in turns, every other frame each.)
M.QUALITY = {
  eco = { scale = 0.5, far = 260, detail = 0.3, alternate = true },      -- (default: cheapest)
  normal = { scale = 0.7, far = 380, detail = 0.45, alternate = true },
  high = { scale = 1.0, far = 500, detail = 0.6, alternate = false },
}
M.PERF = M.QUALITY.eco
function M.setQuality(q)
  if not M.QUALITY[q] then return end
  M.cfg.q, M.PERF = q, M.QUALITY[q]
  -- (2026-11-08: applied to the views as they are. Destroying and remaking them here took the GPU driver down, twice
  -- in the log: the contexts destroyed, a 2.7 s wait, device removed. The picture's resolution stays what it was at
  -- the start of the session; distance, detail and the alternating follow at once.)
  for _, v in pairs(views) do if v.rv then pcall(M._quality, v.rv) end end
  saveAt = os.clock() + 0.3
end

local function quality(rv)
  pcall(function() rv.renderShadows = false end)
  pcall(function() rv.renderEditorGizmo = false end)
  -- (the tone mapping and the exposure as the main view: without them the picture was blown out, 2026-11-04)
  pcall(function() rv.usePostEffects = true end)
  if RenderSettings and RenderSettings.getGlobals then
    pcall(function()
      local s = RenderSettings.getGlobals()
      -- (the vehicle mirrors and reflections are NOT switched off here: done so, the truck's own mirrors went dead in
      -- the main view too, 2026-11-04 – they are updated by whichever view renders them)
      pcall(function() s.meshDetailAdjust = (s.meshDetailAdjust or 1) * M.PERF.detail end)
      pcall(function() s.groundCoverScale = 0 end)
      rv.settingsOverride = s                 -- (a struct by value: written back whole)
      rv.settingsOverrideEnabled = true
    end)
  end
end

M._quality = quality

local function ensureView(k)
  local v = views[k]
  if v and v.rv then return v end
  local name = 'ffMirror' .. k
  local rv = RenderViewManagerInstance:getOrCreateView(name)
  -- (no upscaler, first thing: before the view's first frame – the log showed an FSR 3 context made for each mirror)
  pcall(function() rv.upscaleMode = 0 end)
  pcall(function() rv.upscaleRenderScale = 1 end)
  rv.luaOwned = true
  rv.namedTexTargetColor = name
  rv.renderCubemap = false
  rv.renderEditorIcons = false
  quality(rv)
  -- (the main view's exposure once, as the game's split screen does – then the view adapts on its own; written
  -- every frame it never settled: the sky blown out white, 2026-11-04)
  pcall(function()
    local main = RenderViewManagerInstance:getView('main')
    if main then
      -- (no temporal upscaler (XeSS in the player's settings): the views are drawn in turns, a reconstruction from
      -- the frames before goes wrong – the sky white, the colours off)
      pcall(function() rv.upscaleMode = 0 end)
      pcall(function() rv.upscaleRenderScale = 1 end)
      if main.currentExposure and main.currentExposure > 0 then rv.currentExposure = main.currentExposure end
    end
  end)
  v = { name = name, rv = rv }
  views[k] = v
  return v
end

function M.destroy()
  for k, v in pairs(views) do
    if v.rv then pcall(function() RenderViewManagerInstance:destroyView(v.rv) end) end
    views[k] = nil
  end
end

-- Two ways to show a mirror (⚙ "Bild"):
--  'flip'   – mirrored like a real mirror: the view's texture drawn by ImGui turned round. The engine also composites
--             it, off the screen: only then does the view go through the whole post-processing (tone mapping) like
--             the split screen's views – without, the sky was white and the colours off (2026-11-04).
--  'engine' – the engine copies the finished picture into the window itself (compositeRect, as the split screen and
--             the rally clock do): the colours exactly as the main view, under the game's UI – but not mirrored.
local function screenRect(k)
  local r = M.rects and M.rects[k]
  return r
end

local function placeView(v, pos, dir, up, active, k)
  local rv = v.rv
  local engine = M.cfg.mode == 'engine'
  if engine then active = true end              -- (composited every frame: no turns, else it flickers)
  pcall(function() rv.active = active end)
  if not active then return end                 -- (its turn next frame: the texture keeps the last picture)
  -- (kept off every time: the log still showed an XeSS upscaler made for each mirror – a heavy one per view)
  pcall(function() if rv.upscaleMode ~= 0 then rv.upscaleMode = 0 end end)
  local scale = engine and 1 or M.PERF.scale
  local w = math.max(64, math.floor(M.cfg.w * scale))
  local h = math.max(64, math.floor(M.cfg.h * scale))
  local r = engine and screenRect(k)
  pcall(function()
    if r then rv.compositeRect = RectI(r.x, r.y, M.cfg.w, M.cfg.h)
    else rv.compositeRect = RectI(-(w + 16), -(h + 16), w, h) end      -- (off the screen: post-processed, not seen)
  end)
  local mat = MatrixF(true)
  mat:createOrientFromDirUp(dir, up)
  mat:setPosition(pos)
  rv.cameraMatrix = mat
  -- (the render target is made once: resizing it while driving re-creates the view's buffers – the size buttons and
  -- the quality only change how large the finished picture is drawn)
  if not v.w then
    rv.resolution = Point2I(w, h)
    rv.viewPort = RectI(0, 0, w, h)
    v.w, v.h = w, h
  end
  -- (the frustum takes the vertical angle: from the one across and the window's shape)
  local hf = math.rad(math.max(20, math.min(100, M.cfg.hfov or M.AUTO.hfov)))
  local vf = 2 * math.atan(math.tan(hf / 2) / (w / h))
  rv.frustum = Frustum.construct(false, vf, w / h, 0.3, M.PERF.far)
  rv.fov = math.deg(vf)
end

local FLAGS
local function flags()
  if not FLAGS then
    FLAGS = bit.bor(im.WindowFlags_NoDecoration, im.WindowFlags_NoSavedSettings, im.WindowFlags_NoFocusOnAppearing, im.WindowFlags_NoNav)
  end
  return FLAGS
end

local function draw()
  imUtils = imUtils or require('ui/imguiUtils')
  local okV, vm = pcall(function() return GFXDevice.getVideoMode() end)
  local sw = okV and vm and vm.width or 1920
  local w, h = M.cfg.w, M.cfg.h
  for _, k in ipairs(SIDES) do
    local v = views[k]
    if v then
      local x = M.cfg.x[k] or (k == 'L' and 14 or sw - w - 22)
      local y = M.cfg.y[k] or 70
      im.SetNextWindowPos(im.ImVec2(x, y), M.placed and im.Cond_Appearing or im.Cond_Always)
      im.SetNextWindowSize(im.ImVec2(w + 8, h + 8), im.Cond_Always)
      im.PushStyleVar2(im.StyleVar_WindowPadding, im.ImVec2(4, 4))
      im.PushStyleVar1(im.StyleVar_WindowRounding, 6)
      im.PushStyleVar1(im.StyleVar_WindowBorderSize, 1)
      local engine = M.cfg.mode == 'engine'
      -- (engine: only the frame – the picture is put under it by the engine; its window stays to drag it by)
      im.PushStyleColor2(im.Col_WindowBg, engine and im.ImVec4(0, 0, 0, 0) or im.ImVec4(0.05, 0.06, 0.07, 0.95))
      im.PushStyleColor2(im.Col_Border, im.ImVec4(0.35, 0.38, 0.42, 0.9))
      if im.Begin('##fernfahrerMirror' .. k, nil, flags()) then
        local p = im.GetWindowPos()
        if engine then
          M.rects = M.rects or {}
          M.rects[k] = p and { x = math.floor(p.x + 4), y = math.floor(p.y + 4) } or nil
          im.Dummy(im.ImVec2(w, h))
        else
          local okT, tex = pcall(imUtils.texObj, '#' .. v.name)
          -- (left/right turned round: a mirror)
          local b = M.cfg.bright or 0.85          -- (a mirror is a little darker than the world: and by hand in ⚙)
          if okT and tex and tex.tex then im.Image(tex.tex:getID(), im.ImVec2(w, h), im.ImVec2(1, 0), im.ImVec2(0, 1), im.ImVec4(b, b, b, 1)) end
        end
        if p and (math.abs(p.x - x) > 0.5 or math.abs(p.y - y) > 0.5) then
          M.cfg.x[k], M.cfg.y[k] = math.floor(p.x), math.floor(p.y)
          saveAt = os.clock() + 1.5
        end
      end
      im.End()
      im.PopStyleColor(2)
      im.PopStyleVar(3)
    end
  end
  M.placed = true
  if saveAt > 0 and os.clock() > saveAt then saveAt = 0; if onSave then pcall(onSave, M.cfg) end end
end

-- ctx: { veh = the career truck when the player drives it (else nil), save = function(cfg) }
function M.update(dt, ctx)
  onSave = ctx and ctx.save or onSave
  local veh = M.on and ctx and ctx.veh
  if not veh then
    -- (2026-11-07: only paused, no longer destroyed – every menu destroyed both views and made them again after it,
    -- each time with an FSR 3 upscaler context of its own torn down; seconds after the second time the GPU driver
    -- reset (d3d12 device removed). Destroyed only when the mirrors are switched off or the level ends.)
    for _, v in pairs(views) do if v.rv and v.live ~= false then pcall(function() v.rv.active = false end); v.live = false end end
    return
  end
  for _, v in pairs(views) do v.live = nil end
  M.frame = (M.frame or 0) + 1
  for i, k in ipairs(SIDES) do
    -- (in turns: one mirror per frame; the first frames both, so neither starts empty)
    local active = not M.PERF.alternate or M.frame <= 2 or (M.frame % 2) == (i - 1)
    local okE, v = pcall(ensureView, k)
    if okE and v then
      if active then
        local okC, pos, dir, up = pcall(camFor, veh, k)
        if okC and pos then pcall(placeView, v, pos, dir, up, true, k) end
      else
        pcall(placeView, v, nil, nil, nil, false, k)
      end
    end
  end
  local okD, err = pcall(draw)
  if not okD then log('W', 'fernfahrer', 'mirrors: ' .. tostring(err)); M.on = false; M.destroy() end
end

function M.setOn(b)
  M.on = b and true or false
  M.placed = false
  return M.on
end
function M.toggle() return M.setOn(not M.on) end

-- bigger/smaller in steps (the height follows: a truck mirror is tall)
function M.setSize(d)
  M.cfg.w = math.max(140, math.min(360, M.cfg.w + (tonumber(d) or 0)))
  M.cfg.h = math.floor(M.cfg.w * 1.36)
  saveAt = os.clock() + 0.5
end

function M.load(cfg)
  if type(cfg) ~= 'table' then return end
  M.cfg.w = tonumber(cfg.w) or M.cfg.w
  M.cfg.h = tonumber(cfg.h) or math.floor(M.cfg.w * 1.36)
  M.cfg.x = type(cfg.x) == 'table' and cfg.x or {}
  M.cfg.y = type(cfg.y) == 'table' and cfg.y or {}
  if M.QUALITY[cfg.q] then M.cfg.q, M.PERF = cfg.q, M.QUALITY[cfg.q] end
  M.cfg.hfov = tonumber(cfg.hfov) or M.AUTO.hfov
  M.cfg.yaw = tonumber(cfg.yaw) or M.AUTO.yaw
  M.cfg.bright = tonumber(cfg.bright) or M.AUTO.bright
  M.cfg.mode = cfg.mode == 'engine' and 'engine' or 'flip'
end

-- by hand (the 🪞 page's ⚙): 'hfov' / 'yaw' by d degrees, or 'auto' back to the defaults
function M.setView(what, d)
  if what == 'auto' then M.cfg.hfov, M.cfg.yaw, M.cfg.bright = M.AUTO.hfov, M.AUTO.yaw, M.AUTO.bright
  elseif what == 'mode' then
    M.cfg.mode = M.cfg.mode == 'engine' and 'flip' or 'engine'
    M.destroy(); M.rects = nil                  -- (made again the other way next frame)
  elseif what == 'bright' then M.cfg.bright = math.max(0.4, math.min(1, (M.cfg.bright or M.AUTO.bright) + (tonumber(d) or 0)))
  elseif what == 'hfov' then M.cfg.hfov = math.max(25, math.min(90, (M.cfg.hfov or M.AUTO.hfov) + (tonumber(d) or 0)))
  elseif what == 'yaw' then M.cfg.yaw = math.max(0, math.min(30, (M.cfg.yaw or M.AUTO.yaw) + (tonumber(d) or 0))) end
  saveAt = os.clock() + 0.5
end

function M.forget(vid) if vid then found[vid] = nil else found = {} end end

return M
