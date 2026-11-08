-- Trucks of Earth: pictures for the documents (2026-11-04).
--  * the dashcam: a camera on the cab's back wall, up by the roof, filming forward through the windscreen, wide
--    (110° across) but not fish-eye. To cost little it is no video: a small picture (480×270) twice a second, only
--    while driving, into a ring of RING files (the last ~12 s). After a crash it records POST_S more, and the ring is
--    copied out as the accident's clip (a flip-book in the office).
--  * scene photos: when the police are at the scene, four pictures of it – from above, from either side, at an angle
--    from the front – attached to the accident report.
-- Pictures are one RenderView ('ffCam') rendered only in the frames a picture is taken (active for that frame,
-- saved two frames later), with the main view's exposure, the tone mapping, no shadows, coarse meshes, a short view.
-- Files: /temp/fernfahrer/cam/ring_NN.png, /temp/fernfahrer/docs/<id>_<n>.png (the UI shows them from there).
-- M.update(dt, ctx) each frame; ctx: { veh = the truck when driven (else nil), speed = m/s, enabled = bool }
-- M.crash(id) → starts a clip; M.clip(id) → { frames, fps } once done; M.photos(id, pos, dir) → paths (filled soon).

local M = {}

-- (one picture a second: the view renders only while a picture is taken – about 0.25 s of each second)
M.RING, M.FPS, M.POST_S = 14, 1, 4
M.SETTLE_S = 0.22        -- the view on this long before the picture is saved (the game's screenshots wait 0.1–0.15 s;
                         -- after 3 frames ≈ 50 ms the save always failed, 2026-11-04)
M.level = 0              -- 0: the cheap view (coarse meshes, no ground cover); 1: a plain view exactly as the game's
                         -- screenshots make it (after saves keep failing with 0)
M.DASH = { w = 480, h = 270, hfov = 110, far = 300 }
M.PHOTO = { w = 800, h = 450, far = 400 }
-- (relative, as the game's own saveToDisk callers write them – with a leading slash nothing was written, and the
-- UI asks for local://local/temp/... = the same place, 2026-11-04)
local DIR_RING, DIR_DOCS = 'temp/fernfahrer/cam/', 'temp/fernfahrer/docs/'
M.DIR_DOCS = DIR_DOCS

local rv                     -- the one view
local busy                   -- the shot in progress: { file, stage, frames, after }
local queue = {}             -- shots waiting: { pos, dir, up, hfov, w, h, far, file, after }
local ringN, ringT = 0, 0    -- frames written so far (index of the newest = ringN % RING), time of the last
local clips = {}             -- id -> { from, until_, frames = nil | {...}, fps }
local photosOf = {}

local dirsMade = false
local function ensureView(w, h)
  if not dirsMade then
    dirsMade = true
    for _, d in ipairs({ DIR_RING, DIR_DOCS }) do pcall(function() FS:directoryCreate(d, true) end) end
  end
  if not rv then
    rv = RenderViewManagerInstance:getOrCreateView('ffCam')
    rv.luaOwned = true
    rv.namedTexTargetColor = 'ffCam'
    rv.renderCubemap = false
    rv.renderEditorIcons = false
    pcall(function() rv.renderShadows = false end)
    pcall(function() rv.usePostEffects = true end)
    -- (no temporal upscaler – XeSS/DLSS/FSR at 67 % in the player's settings: it needs the frames before, a single
    -- picture had none, and nothing was saved, 2026-11-04)
    if M.level == 0 then
      pcall(function() rv.upscaleMode = 0 end)
      pcall(function() rv.upscaleRenderScale = 1 end)
    end
    if M.level == 0 and RenderSettings and RenderSettings.getGlobals then
      pcall(function()
        local s = RenderSettings.getGlobals()
        pcall(function() s.meshDetailAdjust = (s.meshDetailAdjust or 1) * 0.45 end)
        pcall(function() s.groundCoverScale = 0 end)
        rv.settingsOverride = s
        rv.settingsOverrideEnabled = true
      end)
    end
    pcall(function() rv.active = false end)
  end
  if M.level == 0 then pcall(function() rv.upscaleMode = 0 end) end      -- (kept: the engine may set it back)
  if rv.__w ~= w or rv.__h ~= h then
    rv.resolution = Point2I(w, h)
    rv.viewPort = RectI(0, 0, w, h)
    rv.__w, rv.__h = w, h
  end
  return rv
end

function M.destroy()
  if rv then pcall(function() RenderViewManagerInstance:destroyView(rv) end) end
  rv, busy, queue = nil, nil, {}
end

local function aim(s)
  local v = ensureView(s.w, s.h)
  local mat = MatrixF(true)
  mat:createOrientFromDirUp(s.dir, s.up or vec3(0, 0, 1))
  mat:setPosition(s.pos)
  v.cameraMatrix = mat
  local hf = math.rad(s.hfov)
  local vf = 2 * math.atan(math.tan(hf / 2) / (s.w / s.h))
  v.frustum = Frustum.construct(false, vf, s.w / s.h, 0.15, s.far)
  v.fov = math.deg(vf)
  -- (one frame, no time to adapt: the main view's exposure, as the game's own screenshots do – scaled by the career
  -- (M.exposureScale): by day from the cab the main view is opened up for the dark cab, the photos came out white)
  pcall(function()
    local main = RenderViewManagerInstance:getView('main')
    if main and main.currentExposure and main.currentExposure > 0 then v.currentExposure = main.currentExposure * (M.exposureScale or 1) end
  end)
  pcall(function() v.active = true end)
end

-- a shot through the game's own screenshot function (render_renderViews.takeScreenshot) – the way that works for the
-- game itself; it hides the UI for a moment, so it is the fallback for the photos only, not the dashcam
local function officialShot(s, done)
  local rvx = rawget(_G, 'render_renderViews')
  if not rvx then pcall(extensions.load, 'render_renderViews'); rvx = rawget(_G, 'render_renderViews') end
  if not (rvx and rvx.takeScreenshot) then done(false); return end
  local vf = 2 * math.atan(math.tan(math.rad(s.hfov) / 2) / (s.w / s.h))
  local q = quatFromDir(s.dir, s.up or vec3(0, 0, 1))
  local ok = pcall(rvx.takeScreenshot, {
    renderViewName = 'ffCamShot', pos = s.pos, rot = q, resolution = vec3(s.w, s.h, 0), fov = math.deg(vf),
    nearPlane = 0.15, farClip = s.far, filename = s.file, usePostEffects = true, copyMainViewExposure = true,
    screenshotDelay = 0.15,
  }, function(success) done(success and true or false) end)
  if not ok then done(false) end
end

-- the shot machine: aim and render in one frame, save two frames later, then the next shot
local function step()
  if busy then
    if busy.official then return end             -- (the game's screenshot job is running; its callback ends it)
    busy.frames = busy.frames + 1
    if busy.frames >= 3 and os.clock() - busy.t0 >= M.SETTLE_S then
      local okC, saved = pcall(function() return rv:saveToDisk(busy.file) end)
      local ok = okC and saved and true or false
      pcall(function() rv.active = false end)    -- (off until the next picture: no cost in between)
      if ok then M.saved = (M.saved or 0) + 1; M.failRow = 0
        if M.saved == 1 then log('I', 'fernfahrer', 'camera: first picture saved ' .. tostring(busy.file) .. ' (level ' .. M.level .. ')') end
      else
        -- (failing again and again with the cheap view: a plain one as the game's screenshots make)
        M.failRow = (M.failRow or 0) + 1
        if M.failRow >= 3 and M.level == 0 then
          M.level = 1
          log('W', 'fernfahrer', 'camera: saves keep failing – the plain view from now on')
          local b0 = busy
          busy = nil
          pcall(function() RenderViewManagerInstance:destroyView(rv) end)
          rv = nil
          if b0.after then pcall(b0.after, false) end
          return
        end
        M.fails = (M.fails or 0) + 1
        if M.fails <= 5 then log('W', 'fernfahrer', 'camera: could not save ' .. tostring(busy.file) .. ' (' .. tostring(saved) .. ')') end
        -- (the first time: is it the path or the view? the same picture into the user folder's root, as the game's
        -- vehicle viewer saves – the answer goes to the log)
        if M.fails == 1 then
          local okT, t2 = pcall(function() return rv:saveToDisk('fernfahrer_cam_test.png') end)
          local okR, res = pcall(function() return rv.resolution end)
          log('W', 'fernfahrer', string.format('camera diagnosis: root save %s, view %s, resolution %s', tostring(okT and t2),
            tostring(rv ~= nil), tostring(okR and res)))
        end
      end
      local b = busy
      busy = nil
      -- a photo that failed: once more through the game's own screenshot function
      if not ok and b.photo then
        busy = { official = true }
        officialShot(b.shot, function(ok2)
          busy = nil
          if ok2 then log('I', 'fernfahrer', 'camera: photo saved the game\'s way ' .. tostring(b.file)) end
          if b.after then pcall(b.after, ok2) end
        end)
        return
      end
      if b.after then pcall(b.after, ok) end
    end
    return
  end
  local s = table.remove(queue, 1)
  if not s then return end
  local okA, err = pcall(aim, s)
  if not okA then log('W', 'fernfahrer', 'camera: ' .. tostring(err)); return end
  busy = { file = s.file, frames = 0, t0 = os.clock(), after = s.after, photo = s.photo, shot = s }
end

-- the dashcam's place: between the two outside mirrors (the cab's front at their height), back to the rear wall,
-- up by the roof – without mirror nodes: over the reference node
local function dashPose(veh)
  local fwd, up = vec3(veh:getDirectionVector()), vec3(veh:getDirectionVectorUp())
  local right = fwd:cross(up):normalized()
  local okV, vd = pcall(function() return core_vehicle_manager.getVehicleData(veh:getID()) end)
  local mirrors = okV and vd and vd.vdata and vd.vdata.mirrors
  local l, r
  for _, m in pairs(mirrors or {}) do
    if type(m.idRef) == 'number' and m.idRef >= 0 then
      local okP, rel = pcall(function() return vec3(veh:getNodePosition(m.idRef)) end)
      if okP and rel then
        local side = rel:dot(right)
        if side < -0.5 and (not l or side < l:dot(right)) then l = rel end
        if side > 0.5 and (not r or side > r:dot(right)) then r = rel end
      end
    end
  end
  local base = veh:getPosition()
  local front = (l and r) and (l + r) * 0.5 or (up * 1.9 + fwd * 1.0)
  local pos = base + front - fwd * 1.5 + up * 0.45
  -- (a touch down: the road, not the sky)
  local dir = (fwd - up * 0.06):normalized()
  return pos, dir, up
end

local function ringFile(i) return string.format('%sring_%02d.png', DIR_RING, i % M.RING) end

-- (2026-11-04: the dashcam is gone – frame drops; only the photos for the police report remain. M.update just works
-- through the queued photos; it has nothing to do – and costs nothing – otherwise)
function M.busy() return busy ~= nil or #queue > 0 end
function M.update(dt, ctx)
  step()
  if true then return end
  local t = os.clock()
  local veh = ctx and ctx.enabled and ctx.veh
  if not veh then return end
  local recording = (ctx.speed or 0) > 1.4 or next(clips) ~= nil
  if recording and not busy and #queue == 0 and t - ringT >= 1 / M.FPS then
    ringT = t
    local okP, pos, dir, up = pcall(dashPose, veh)
    if okP and pos then
      local n = ringN
      table.insert(queue, { pos = pos, dir = dir, up = up, hfov = M.DASH.hfov, w = M.DASH.w, h = M.DASH.h, far = M.DASH.far,
        file = ringFile(n), after = function(ok) if ok then ringN = n + 1 end end })
    end
  end
  -- clips: once the time after the crash is filmed, the ring copied out in order (only pictures that exist)
  for id, c in pairs(clips) do
    if not c.frames and t > c.until_ then
      local frames = {}
      local count = math.min(M.RING, ringN)
      for i = ringN - count, ringN - 1 do
        local src, dst = ringFile(i), string.format('%s%s_dash_%02d.png', DIR_DOCS, id, #frames)
        local okC, r = pcall(function() return FS:copyFile(src, dst) end)
        local exists = okC and (r == true or r == 0 or r == nil) and FS:fileExists(dst)
        if exists then frames[#frames + 1] = dst end
      end
      c.frames = frames
      log('I', 'fernfahrer', string.format('dashcam: clip %s, %d frames', id, #frames))
    end
  end
end

-- the clips finished since the last call: { id = { frames, fps } } (handed over once)
function M.takeDone()
  local out
  for id, c in pairs(clips) do
    if c.frames then out = out or {}; out[id] = { frames = c.frames, fps = c.fps }; clips[id] = nil end
  end
  return out
end

-- old pictures gone (a clip dropped from the dashcam folder, a document dropped)
function M.removeFiles(list)
  for _, f in ipairs(list or {}) do pcall(function() FS:removeFile(type(f) == 'table' and f.file or f) end) end
end

-- a crash: the ring is kept as it is plus POST_S more
function M.crash(id)
  if not id or clips[id] then return end
  clips[id] = { until_ = os.clock() + M.POST_S, fps = M.FPS }
end

-- the clip of a crash (nil while still filming); once taken it is handed over and forgotten here
function M.clip(id)
  local c = id and clips[id]
  if not c or not c.frames then return nil end
  clips[id] = nil
  return #c.frames > 0 and { frames = c.frames, fps = c.fps } or nil
end
function M.clipPending(id) return id and clips[id] ~= nil and clips[id].frames == nil end

-- the scene photographed: four views that hold all of it – pts: the crash, the truck and trailer, the other
-- vehicles, the police car and the ambulance (2026-11-04: shot at 16 m around one point the pictures showed the police
-- car and little else). From the box round them: its middle and its radius (plus room for the vehicles' length) give
-- the height of the view from above and the distance of the three views at an angle.
function M.photos(id, pts, dir)
  if not id or not pts then return {} end
  if pts.x then pts = { pts } end                -- (one point given)
  dir = dir or vec3(0, 1, 0)
  dir = vec3(dir.x, dir.y, 0)
  dir = dir:length() > 0.1 and dir:normalized() or vec3(0, 1, 0)
  local right = vec3(dir.y, -dir.x, 0)
  local z = vec3(0, 0, 1)
  local minX, minY, maxX, maxY, sumZ = math.huge, math.huge, -math.huge, -math.huge, 0
  for _, p in ipairs(pts) do
    minX, maxX = math.min(minX, p.x), math.max(maxX, p.x)
    minY, maxY = math.min(minY, p.y), math.max(maxY, p.y)
    sumZ = sumZ + p.z
  end
  local mid = vec3((minX + maxX) / 2, (minY + maxY) / 2, sumZ / #pts)
  local r = 0
  for _, p in ipairs(pts) do r = math.max(r, vec3(p.x - mid.x, p.y - mid.y, 0):length()) end
  r = math.min(90, r + 9)                         -- (a truck is long: room round the outermost points)
  local c = mid + z * 1.0
  local aspect = M.PHOTO.w / M.PHOTO.h
  -- from above: everything inside the shorter side of the picture
  local topH = 70
  local vTop = 2 * math.atan(math.tan(math.rad(topH) / 2) / aspect)
  local height = math.max(22, math.min(160, r / math.tan(vTop / 2) * 1.08))
  -- at an angle (25° down): far enough back for the whole width
  local angH = 64
  local dist = math.max(18, math.min(200, r / math.tan(math.rad(angH) / 2) * 1.12))
  local elev = math.rad(24)
  local function around(a)     -- a: the direction from the scene to the camera, flat
    a = a:normalized()
    return c + a * (dist * math.cos(elev)) + z * (dist * math.sin(elev))
  end
  local shots = {
    -- from above: straight down, the truck's way up the picture
    { pos = mid + z * height, dir = vec3(0, 0, -1), up = dir, hfov = topH, label = 'Übersicht von oben', far = height + 60 },
    { pos = around(right - dir * 0.6), label = 'von rechts hinten' },
    { pos = around(-right + dir * 0.6), label = 'von links vorn' },
    { pos = around(dir + right * 0.35), label = 'von vorn' },
  }
  for _, s in ipairs(shots) do s.hfov = s.hfov or angH; s.far = s.far or (dist + r * 2 + 80) end
  local out = {}
  for i, s in ipairs(shots) do
    if not s.dir then s.dir = (c - s.pos):normalized() end
    local file = string.format('%s%s_%d.png', DIR_DOCS, id, i)
    local entry = { file = file, label = s.label }
    out[#out + 1] = entry
    table.insert(queue, { pos = s.pos, dir = s.dir, up = s.up or z, hfov = s.hfov, w = M.PHOTO.w, h = M.PHOTO.h,
      far = s.far, file = file, photo = true, after = function(ok) entry.ok = ok or nil end })
  end
  photosOf[id] = out
  return out
end

function M.reset()
  M.destroy()
  clips, photosOf, ringN = {}, {}, 0
end

return M
