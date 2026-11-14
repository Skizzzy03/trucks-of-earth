-- Trucks of Earth (2026-11-10): people who are really there, not only a face in the window.
--  * The breakdown service's mechanic: gets out beside the service car, walks round to the driver's door, knocks and asks what
--    the trouble is (the talk window with his face, answers to pick), goes to the fault, works, walks back to his car and gets
--    in; only then the car drives off.
--  * The hitchhiker: now and then she stands at the edge of a country road ahead. Stop near her and she comes to the
--    passenger door; take her along and she sits beside the driver in the cab until she gets off again.
-- M.attach(ctx); M.frame(dt) every frame (the figures move with the truck); M.serviceStart(s, carId) -> true when he comes;
-- M.servicePhase() -> nil | 'come' | 'talk' | 'walk' | 'work' | 'back' | 'done'; M.answer(i) -> true when it was his talk;
-- M.clean() (everything gone), M.serviceClean().
local M = {}
local X
local SH = '/levels/beamng_earth/art/shapes/ffa/ff_npc_'
M.WALK = 1.35            -- m/s, walking
M.SIDE_KM = { 25, 60 }   -- km between two hitchhikers at the roadside
M.SIDE_AHEAD = 260       -- m ahead along the road where she stands
local seq = 0
local function now() return os.clock() end
local crew, ride, side, outW = nil, nil, nil, nil
local PX = require('fernfahrer/passenger')
local PEOPLE = require('fernfahrer/people')
local SAGA = require('fernfahrer/saga')
local chat                -- the passenger's talk on the way: { id, who, line, out, raw, till }
local secT = 0

local function flat(v)
  local w = vec3(v.x, v.y, 0)
  local l = w:length()
  return l > 1e-3 and w * (1 / l) or nil
end
local function onGround(q)
  local top = vec3(q.x, q.y, q.z + 2.5)
  local hit = castRayStatic(top, vec3(0, 0, -1), 12)
  return (hit and hit < 12) and vec3(q.x, q.y, top.z - hit) or vec3(q.x, q.y, q.z)
end
local function figure(kind)
  local o = createObject('TSStatic')
  if not o then return nil end
  -- (2026-11-10: as the cab's accessories are made - a thing that moves every frame, marked as one: without it TAA and FSR smeared her, she seemed to jump about in the seat)
  o.useInstanceRenderData = false
  o:setField('dynamic', 0, 'true')
  o:setField('shapeName', 0, SH .. kind .. '.dae')
  o:setField('collisionType', 0, 'None')
  o:setField('decalType', 0, 'None')
  o.canSave = false
  seq = seq + 1
  o:registerObject('ff_crew_' .. seq)
  return o
end
local function put(o, p, dir, up)
  if not o or not p or not dir then return end
  local rot = quatFromDir(dir, up or vec3(0, 0, 1))
  o:setPosRot(p.x, p.y, p.z, rot.x, rot.y, rot.z, rot.w)
end
local function kill(o) if o then pcall(function() o:delete() end) end end

-- the truck as it stands: where its driver's eye is, which side the driver sits, how wide and long it is
local function frameOf(v)
  local p = X.vehPos(v)
  local d = flat(vec3(v:getDirectionVector())) or vec3(0, 1, 0)
  local left = vec3(-d.y, d.x, 0)
  local F = { p = p, d = d, left = left, side = left, lat0 = 1, len = v:getInitialLength() or 8, halfW = (v:getInitialWidth() or 2.5) * 0.5 }
  F.eye = p + d * 0.5 + vec3(0, 0, 1.6)
  pcall(function()
    local camNode, rhd = core_camera.getDriverData(v)
    if not camNode then return end
    F.eye = p + vec3(v:getNodePosition(camNode))
    F.side = rhd and -left or left
  end)
  F.lat0 = (F.eye - p):dot(F.side)
  -- (the front: from the box round the vehicle where it is sound, else a little in front of the driver - a cab-over)
  F.front = F.eye + F.d * 1.6 - F.side * F.lat0
  pcall(function()
    local bb = v:getSpawnWorldOOBB()
    local c = vec3(bb:getCenter())
    if (c - p):length() < F.len then
      local f2 = c + F.d * (F.len * 0.5)
      if (f2 - F.eye):dot(F.d) > 0.6 then F.front = vec3(f2.x, f2.y, F.eye.z) - F.side * ((vec3(f2.x, f2.y, F.eye.z) - p):dot(F.side)) end
    end
  end)
  return F
end
-- standing at a door: beside it, as high as the window (from a lorry's cab one looks over someone on the ground)
local function doorSpot(F, passenger)
  local s = passenger and -F.side or F.side
  local lat = passenger and -F.lat0 or F.lat0
  local spot = F.eye + s * (F.halfW + 0.55 - lat) + F.d * 0.15
  local g = onGround(spot)
  return vec3(spot.x, spot.y, math.max(g.z, F.eye.z - 1.55)), -s, s
end
-- a point beside the truck on a side, at the same distance along it as q
-- (2026-11-11: on the ground. It was at the height of the vehicle's middle - a lorry's is a metre up - and the last steps of a walk climb to the
-- height of their end point: getting out, she rose into the air, "wie Jesus")
local function besideAt(F, q, s, out)
  local along = (q - F.p):dot(F.d)
  local w = F.p + F.d * along + s * (F.halfW + (out or 1.0))
  return onGround(vec3(w.x, w.y, F.p.z))
end

-- walking along points: the ground under the feet, a little bob; the last point may be up at a window (then up the last 1.5 m)
local function walker(o, from, dir)
  return { o = o, pos = vec3(from.x, from.y, from.z), dir = dir, path = {}, i = 1, ph = 0 }
end
local function walkTo(w, pts) w.path, w.i = pts, 1 end
local function walkStep(w, dt)
  local tgt = w.path[w.i]
  if not tgt then return true end
  local to = vec3(tgt.x - w.pos.x, tgt.y - w.pos.y, 0)
  local dist = to:length()
  local step = (w.speed or M.WALK) * dt
  if dist <= step or dist < 0.02 then
    w.pos = vec3(tgt.x, tgt.y, w.pos.z)
    w.i = w.i + 1
  else
    w.pos = w.pos + to * (step / dist)
    w.dir = to * (1 / dist)
  end
  w.ph = w.ph + dt * 7.2
  local z = onGround(w.pos).z
  local last = w.path[#w.path]
  if last and last.z > z + 0.05 then
    local left = vec3(last.x - w.pos.x, last.y - w.pos.y, 0):length()
    if w.i >= #w.path then z = z + (last.z - z) * math.max(0, math.min(1, 1 - left / 1.5)) end
  end
  w.pos.z = z
  put(w.o, vec3(w.pos.x, w.pos.y, z + math.abs(math.sin(w.ph)) * 0.035), w.dir)
  return w.i > #w.path
end
local function stand(w, dir, t)
  -- (standing: weight from one foot to the other, now and then)
  local sway = math.sin((t or 0) * 1.1) * 0.06
  local d = dir or w.dir
  local perp = vec3(-d.y, d.x, 0)
  put(w.o, w.pos, flat(d + perp * sway) or d)
end

-- --- the mechanic --------------------------------------------------------------------------------------------------
local NAMES = { 'Jens', 'Micha', 'Tobi', 'Kalle', 'Sven', 'Dirk', 'Olli', 'Basti' }
local SAY = {
  tire = { '„Ein Reifen ist geplatzt.“', 'Alles klar, Reifen haben wir dabei. Bleiben Sie ruhig sitzen, das geht schnell.' },
  radiator = { '„Der Motor wird heiß, unten läuft Wasser raus.“', 'Klingt nach dem Kühler. Gut, dass Sie gleich angehalten haben, sonst wäre der Motor hin. Ich schau mir das an.' },
  hose = { '„Er hat keine Leistung mehr, nur noch Notlauf.“', 'Typisch Ladeluftschlauch. Hab ich dabei, dauert nicht lange.' },
  oil = { '„Die Öldruck-Lampe ist angegangen.“', 'Gut, dass Sie stehen geblieben sind. Ich schau, wo das Öl rausläuft, und mach das dicht.' },
  recover = { '„Ich hatte einen Unfall, er fährt kaum noch.“', 'Oha, da hat’s ordentlich gekracht. Ich mach ihn so weit fahrbereit, dass Sie weiterkommen. Den Rest muss eine Werkstatt machen.' },
}
local function crewSend()
  if not crew or not crew.talk then return end
  local k = crew.talk
  X.trigger('FernfahrerCop', { id = k.id, who = crew.name .. ' · Pannendienst', face = 'mechanic', seed = crew.seed, mood = k.mood, react = k.react, line = k.line, choices = k.out })
end
local function crewSay(line, react, choices)
  local k = crew.talk or { id = 0, mood = 1 }
  k.id, k.line, k.react, k.raw = k.id + 1, line, react, choices
  k.out = {}
  for i, c in ipairs(choices) do k.out[i] = { t = c.t, sub = c.sub } end
  crew.talk = k
  crewSend()
end
local function crewTalkStart()
  local s = crew.s
  local say = SAY[s.kind] or SAY.recover
  -- (2026-11-11: his own words; and if he has been here before, he remembers - people.lua)
  local hello = crew.prof and PEOPLE.greeting(X.state(), crew.prof) or string.format('Hi, ich bin %s vom %s. Wie kann ich Ihnen helfen, was ist das Problem?', crew.name, crew.club or 'Pannendienst')
  crewSay(hello, 'nod', {
    { t = say[1], go = 'right' },
    { t = '„Keine Ahnung, er läuft einfach nicht richtig.“', sub = 'er sucht selbst, das dauert länger', go = 'search' },
    { t = '„Machen Sie bitte schnell, ich hab’s eilig.“', go = 'hurry' },
  })
end
local function crewTalkEnd()
  crew.talk = nil
  X.trigger('FernfahrerCop', { off = true })
  X.look(false)
  crew.phase = 'walk'
  local F = crew.F
  local spot, face
  if crew.s.kind == 'tire' then
    -- (the front wheel on the driver's side)
    spot = besideAt(F, F.eye - F.d * 0.4, F.side, 0.5)
    face = -F.side
  else
    -- (in front of the cab: the engine, the radiator)
    local corner = besideAt(F, F.front + F.d * 0.8, F.side, 0.8)
    spot = onGround(vec3(F.front.x, F.front.y, F.p.z) + F.d * 0.75)
    face = -F.d
    crew.via = corner
  end
  crew.spot, crew.face = spot, face
  local pts = {}
  pts[#pts + 1] = besideAt(F, crew.w.pos, F.side, 0.9)
  if crew.via then pts[#pts + 1] = crew.via end
  pts[#pts + 1] = spot
  walkTo(crew.w, pts)
end
-- --- the passenger talks (2026-11-10): every minute or two while driving - her story in three parts between other things; the answers count (her mood, and so what she leaves behind)
local function chatSend()
  if not chat then return end
  chat.sent = now()
  X.trigger('FernfahrerCop', { id = chat.id, who = chat.who, face = 'hitch', seed = chat.seed, mood = chat.mood, react = chat.react, line = chat.line, choices = chat.out })
end
local function chatClose()
  if not chat then return end
  chat = nil
  X.trigger('FernfahrerCop', { off = true })
end
local function chatOpen(topic, h)
  local cargo = (X.cargo and X.cargo()) or 'Kram'
  local fill = function(s) return s and (s:gsub('%%CARGO%%', cargo):gsub('%%NAME%%', h.name or '')) or nil end
  chat = { id = (h.chatId or 0) + 1, who = h.name .. ' · Beifahrerin', seed = h.seed, mood = math.max(-4, math.min(4, h.mood or 0)), react = 'nod',
    line = fill(topic.say), out = {}, raw = topic.ch, till = now() + 25, fill = fill }
  h.chatId = chat.id
  for i, c in ipairs(topic.ch) do chat.out[i] = { t = fill(c.t) } end
  chatSend()
end
local function chatAnswer(i)
  local c = chat.raw and chat.raw[tonumber(i) or 1]
  if not c then return end
  local h = X.state().hitch
  if h then h.mood = (h.mood or 0) + (c.m or 0) end
  if c.fx == 'snack' and X.snack then X.snack() end
  if (c.fx == 'cig' or c.fx == 'joint') and X.leave then X.leave(c.fx == 'cig' and 'cigarette' or 'joint', c.fx == 'cig' and 6 or 1) end
  chat.id = chat.id + 1
  chat.line, chat.out, chat.raw = chat.fill(c.r), {}, nil
  chat.react = (c.m or 0) > 0 and 'laugh' or ((c.m or 0) < 0 and 'sad' or 'nod')
  chat.mood = math.max(-4, math.min(4, h and h.mood or 0))
  chat.till = now() + 8
  chatSend()
end
local function chatTick()
  local h = X.state().hitch
  if not ride or not h then chatClose(); return end
  local t = now()
  -- (someone at the door, the mechanic: their talk has the window)
  if chat and (X.encActive() or crew) then chatClose(); ride.talkAt = t + 60 end
  if chat then
    if t > chat.till then
      -- (no answer: she looks out of the window; asked again a little later)
      chatClose()
      ride.talkAt = t + 60 + math.random() * 80
    elseif t - (chat.sent or 0) >= 1 then chatSend() end
    return
  end
  if not ride.talkAt then ride.talkAt = t + 30 + math.random() * 30 end
  local v = X.truck()
  if t < ride.talkAt or not v or X.speed(v) < 4 or X.encActive() or crew then return end
  h.seed = h.seed or math.random(1, 4000)
  h.name = h.name or PX.NAMES[math.random(#PX.NAMES)]
  h.story = h.story or math.random(#PX.STORIES)
  h.chap, h.n = h.chap or 0, (h.n or 0) + 1
  local story, topic = (h.saga and SAGA.RONJA) or PX.STORIES[h.story] or PX.STORIES[1], nil
  if h.again and not h.greeted then
    h.greeted = true
    topic = { say = PX.AGAIN[math.random(#PX.AGAIN)], ch = PX.AGAIN_CH }
  elseif h.again and not h.sequelDone and PX.SEQUEL[h.story] then
    h.sequelDone = true
    topic = PX.SEQUEL[h.story]
  elseif h.chap < #story and (h.chap == 0 or h.n % 2 == 1) then
    h.chap = h.chap + 1
    topic = story[h.chap]
  else
    h.used = h.used or {}
    local free = {}
    for k = 1, #PX.SMALL do if not h.used[tostring(k)] then free[#free + 1] = k end end
    if #free == 0 then h.used = {}; for k = 1, #PX.SMALL do free[#free + 1] = k end end
    local k = free[math.random(#free)]
    h.used[tostring(k)] = true
    topic = PX.SMALL[k]
  end
  chatOpen(topic, h)
end
function M.answer(i)
  if chat then
    if chat.raw then chatAnswer(i) end
    return true
  end
  if not crew or not crew.talk then return false end
  local c = crew.talk.raw and crew.talk.raw[tonumber(i) or 1]
  if not c then return true end
  local s = crew.s
  local say = SAY[s.kind] or SAY.recover
  if c.go == 'right' then
    crew.talk.mood = 2
    local more = { { t = '„Danke!“', go = 'chat' } }
    if s.kind == 'recover' then more[2] = { t = '„Kriegen Sie den wieder ganz hin?“', go = 'whole' } end
    crewSay(say[2], 'nod', more)
  elseif c.go == 'chat' and crew.prof and not crew.chatted then
    -- (2026-11-11: a word before he gets to work: the story's legend the first time, now and then the news of it, else one of his own)
    crew.chatted = true
    local tp = SAGA.mechanicTopic() or SAGA.gossip()
    if tp then crew.sagaTopic = (tp == SAGA.MECH_TOPIC) or nil
    else tp, crew.topicIdx = PEOPLE.topic(X.state(), crew.prof) end
    crew.topic = tp
    local out = {}
    for i, ch in ipairs(tp.ch) do out[i] = { t = ch.t, go = 'reply', i = i } end
    crewSay(tp.say, 'think', out)
  elseif c.go == 'reply' and crew.topic then
    local ch = crew.topic.ch[c.i] or crew.topic.ch[1]
    crew.mood = (crew.mood or 0) + (ch.m or 0)
    if crew.sagaTopic then SAGA.step('legend') end
    crewSay(ch.r, (ch.m or 0) > 0 and 'laugh' or 'nod', { { t = '„Na dann, an die Arbeit.“', go = 'end' } })
  elseif c.go == 'search' then
    s.dur = (s.dur or 40) * 1.3
    crew.talk.mood = 0
    crewSay('Na gut, dann such ich mal. Ich schau mir alles einmal an, das kann etwas länger dauern.', 'think', { { t = '„Danke Ihnen.“', go = 'chat' } })
  elseif c.go == 'hurry' then
    s.dur = (s.dur or 40) * 0.9
    crew.talk.mood = -1
    crewSay('Ich beeil mich. Aber gepfuscht wird bei mir nicht.', 'shake', { { t = '„Schon gut. Danke.“', go = 'end' } })
  elseif c.go == 'whole' then
    crewSay('Ganz? Nee. Ich bin Pannenhelfer, kein Zauberer. Notreparatur, damit Sie sicher weiterkommen, und dann ab in die Werkstatt.', 'laugh', { { t = '„Alles klar.“', go = 'end' } })
  else
    crewTalkEnd()
  end
  return true
end

function M.serviceStart(s, carId)
  M.serviceClean()
  local v = X.truck()
  local uv = carId and getObjectByID(carId)
  if not v or not uv then return false end
  local F = frameOf(v)
  local up = X.vehPos(uv)
  local ud = flat(vec3(uv:getDirectionVector())) or F.d
  local uleft = vec3(-ud.y, ud.x, 0)
  local door = onGround(up + uleft * ((uv:getInitialWidth() or 2) * 0.5 + 0.45) + ud * 0.4)
  local o = figure('mechanic')
  if not o then return false end
  local here = X.here and X.here()
  local prof = PEOPLE.pickMechanic(X.state(), here and here.lat, here and here.lon)
  crew = { s = s, F = F, carId = carId, door = door, name = prof.name, seed = prof.seed, club = prof.club or s.club, prof = prof, place = X.placeName and X.placeName() or nil,
    w = walker(o, door, flat(F.p - door) or F.d), phase = 'come', t0 = now() }
  put(o, door, crew.w.dir)
  -- (round to the driver's side first, along the truck, then to the door)
  local dSpot = doorSpot(F, false)
  walkTo(crew.w, { besideAt(F, door, F.side, 1.0), besideAt(F, dSpot, F.side, 1.0), dSpot })
  crew.dSpot = dSpot
  crew.wait = now() + 1.2      -- (the car door first)
  return true
end
function M.servicePhase() return crew and crew.phase or nil end
function M.serviceClean()
  if not crew then return end
  if crew.talk then X.trigger('FernfahrerCop', { off = true }); X.look(false) end
  kill(crew.w and crew.w.o)
  crew = nil
end
local function crewFrame(dt)
  if not crew then return end
  local t = now()
  local c = crew
  if c.wait and t < c.wait then return end
  c.wait = nil
  if c.phase == 'come' then
    if walkStep(c.w, dt) then
      c.phase = 'knock'
      c.at = t + 1.4
      X.knock(2)
      stand(c.w, -c.F.side, t)
    end
  elseif c.phase == 'knock' then
    stand(c.w, -c.F.side, t)
    if t >= c.at then
      c.phase = 'talk'
      X.look(true, -66)
      c.at = t + 1.0
    end
  elseif c.phase == 'talk' then
    stand(c.w, -c.F.side, t)
    if c.at and t >= c.at then c.at = nil; crewTalkStart(); c.sent = t end
    if c.talk and t - (c.sent or 0) >= 1 then c.sent = t; crewSend() end
  elseif c.phase == 'walk' then
    if walkStep(c.w, dt) then
      c.phase = 'work'
      c.s.t0 = t
      c.s.dur = c.s.dur or 40
    end
  elseif c.phase == 'work' then
    -- (at work: bent over, a little to and fro)
    local bob = math.sin(t * 2.3) * 0.04 - 0.03
    local perp = vec3(-c.face.y, c.face.x, 0)
    put(c.w.o, c.w.pos + vec3(0, 0, bob), flat(c.face + perp * math.sin(t * 0.9) * 0.25) or c.face)
    if t - c.s.t0 >= c.s.dur then
      c.phase = 'back'
      local F = c.F
      local pts = {}
      if c.via then pts[#pts + 1] = c.via end
      pts[#pts + 1] = besideAt(F, c.door, F.side, 1.0)
      pts[#pts + 1] = c.door
      walkTo(c.w, pts)
      local pr = c.prof
      X.message(c.s.kind == 'recover' and ((pr and pr.recover) or 'So, fahrbereit. Fahren Sie vorsichtig und lassen Sie den Rest in der Werkstatt machen.')
        or ((pr and pr.fix) or 'Erledigt, alles wieder dicht. Gute Fahrt!'), c.name .. ' · Pannendienst')
      if pr then pcall(PEOPLE.noteMechanic, X.state(), pr, c.s.kind, c.place, c.topicIdx, (c.mood or 0) + ((c.talk and c.talk.mood) or 0)) end
    end
  elseif c.phase == 'back' then
    if walkStep(c.w, dt) then
      kill(c.w.o)
      c.w.o = nil
      c.phase = 'done'
    end
  end
end

-- --- the passenger ---------------------------------------------------------------------------------------------------
-- (where in the cab: the driver's eye mirrored to the other side, a little back, the seat 0.74 below the eye; kept in the truck's own frame)
local function rideFrame()
  if not ride then return end
  local v = X.truck()
  if not v then if X.cabRider then X.cabRider(nil) end; kill(ride.o); ride = nil; return end
  -- (held by the cab's frame, as the accessories are: only when that is not running, placed here)
  if X.cabRider and X.cabRider(ride.o) then return end
  if not ride.loc then
    local F = frameOf(v)
    local e = F.eye - F.p
    local up = vec3(0, 0, 1)
    ride.loc = { a = e:dot(F.d) - 0.12, b = -e:dot(F.left), c = e:dot(up) - 0.74 }
  end
  local d = vec3(v:getDirectionVector())
  local u = vec3(v:getDirectionVectorUp())
  local l = u:cross(d)
  local p = X.vehPos(v) + d * ride.loc.a + l * ride.loc.b + u * ride.loc.c
  put(ride.o, p, d, u)
end
local function rideOn()
  if ride or not X.truck() then return end
  local o = figure('hitch_sit')
  if not o then return end
  ride = { o = o, id = X.truck():getID() }
  rideFrame()
end
-- she gets out: at the passenger door, a few steps away from the truck, gone
local function rideOff()
  if not ride then return end
  chatClose()
  if X.cabRider then X.cabRider(nil) end
  kill(ride.o)
  ride = nil
  local v = X.truck()
  if not v then return end
  local F = frameOf(v)
  local spot = doorSpot(F, true)
  local g = onGround(spot)
  local o = figure('hitch')
  if not o then return end
  outW = walker(o, g, -F.side)
  walkTo(outW, { besideAt(F, g, -F.side, 3.5), besideAt(F, g - F.d * 12, -F.side, 3.8) })
  outW.till = now() + 25
end
-- (2026-11-10) she says goodbye: her face in the window for a few seconds as she gets out, waving
local byeTill
local function sayBye(b)
  if not b or not b.line then return end
  chatClose()
  X.trigger('FernfahrerCop', { id = 9000 + math.random(1, 900), who = tostring(b.name) .. ' · steigt aus', face = 'hitch', seed = b.seed or 7,
    mood = math.max(-4, math.min(4, b.mood or 0)), react = (b.mood or 0) < 0 and 'nod' or 'laugh', line = b.line, choices = {} })
  byeTill = now() + 7
end
function M.ride(on, bye) if on then rideOn() else rideOff(); sayBye(bye) end end

-- --- the hitchhiker at the roadside -------------------------------------------------------------------------------------
-- along the road graph from the truck, the straightest way, dist m: the spot at the right edge there, and the heading; nil where it does not fit
local function roadAhead(p, d, dist)
  if not (map and map.getMap and map.findClosestRoad) then return nil end
  local okR, n1, n2 = pcall(map.findClosestRoad, p)
  local nodes = okR and n1 and n2 and map.getMap().nodes
  if not nodes or not nodes[n1] or not nodes[n2] then return nil end
  local prev, cur = n1, n2
  if (vec3(nodes[n2].pos) - vec3(nodes[n1].pos)):dot(d) < 0 then prev, cur = n2, n1 end
  local heading = flat(vec3(nodes[cur].pos) - vec3(nodes[prev].pos)) or d
  local travelled = (vec3(nodes[cur].pos) - p):length()
  for _ = 1, 80 do
    if travelled >= dist then break end
    local best, bestDot = nil, 0.8
    for nb in pairs(nodes[cur].links or {}) do
      if nb ~= prev and nodes[nb] then
        local dd = flat(vec3(nodes[nb].pos) - vec3(nodes[cur].pos))
        if dd and dd:dot(heading) > bestDot then best, bestDot = nb, dd:dot(heading) end
      end
    end
    if not best then return nil end
    heading = flat(vec3(nodes[best].pos) - vec3(nodes[cur].pos)) or heading
    travelled = travelled + (vec3(nodes[best].pos) - vec3(nodes[cur].pos)):length()
    prev, cur = cur, best
  end
  if travelled < dist then return nil end
  local deg = 0
  for _ in pairs(nodes[cur].links or {}) do deg = deg + 1 end
  if deg ~= 2 then return nil end
  local link = nodes[prev].links and nodes[prev].links[cur]
  if type(link) == 'table' and link.oneWay then return nil end
  local right = vec3(heading.y, -heading.x, 0)
  local half = math.max(2.2, math.min(6, nodes[cur].radius or 3))
  local q = vec3(nodes[cur].pos) + right * (half + 1.4)
  return onGround(q), heading
end
local function sideSpawn(v)
  local p = X.vehPos(v)
  local d = flat(vec3(v:getDirectionVector()))
  if not d then return false end
  local q, heading = roadAhead(p, d, M.SIDE_AHEAD)
  if not q then return false end
  local o = figure('hitch')
  if not o then return false end
  local right = vec3(heading.y, -heading.x, 0)
  -- (looking at the traffic that comes, a little towards the road)
  local look = flat(-heading - right * 0.45) or -heading
  side = { w = walker(o, q, look), home = q, look = look, phase = 'wait', t0 = now() }
  put(o, q, look)
  log('I', 'fernfahrer', string.format('a hitchhiker at the roadside, %d m ahead', M.SIDE_AHEAD))
  return true
end
local function sideClean() if side then kill(side.w.o); side = nil end end
local function sideFrame(dt)
  if not side then return end
  local v = X.truck()
  if not v then return sideClean() end
  local t = now()
  local p = X.vehPos(v)
  local rel = side.w.pos - p
  local dist = rel:length()
  local s = side
  if s.phase == 'wait' or s.phase == 'home' then
    if s.phase == 'home' then
      if walkStep(s.w, dt) then s.phase = 'wait' end
    else
      stand(s.w, s.look, t)
    end
    if dist > 500 or (dist > 150 and rel:dot(flat(vec3(v:getDirectionVector())) or rel) < 0) then return sideClean() end
    -- (2026-11-10: no word of her far ahead - she is a surprise, seen late, and stopping for her may take a hard stop. The note only when she is nearly beside the truck)
    if not s.told and dist < 70 and not s.no then s.told = true; X.notify('🎒 Am Straßenrand: jemand hält den Daumen raus!', 4) end
    if s.phase == 'wait' and not s.no and dist < 90 and X.speed(v) < 1.2 and not X.encActive() and not X.hitchOn() then
      local F = frameOf(v)
      local spot = doorSpot(F, true)
      s.F, s.spot = F, spot
      s.phase = 'come'
      -- (stopped a good way past her: she runs to catch up)
      s.w.speed = dist > 25 and 2.6 or nil
      walkTo(s.w, { besideAt(F, s.w.pos, -F.side, 1.0), besideAt(F, spot, -F.side, 1.0), spot })
    end
  elseif s.phase == 'come' then
    if X.speed(v) > 2 then s.phase = 'home'; s.no = true; walkTo(s.w, { s.home }); return end
    if walkStep(s.w, dt) then
      s.w.speed = nil
      -- (2026-11-11: now and then one met before - people.lua; never while the story waits for Ronja)
      local key, seed = 'tramper_strasse', nil
      local stt = X.state()
      if not SAGA.wantRonja() then
        local name, rec = PEOPLE.knownHitch(stt, X.km(), 0.3)
        if name then stt.hitchNext = { name = name, rec = rec }; key, seed = 'tramper_wieder', rec.seed end
      end
      if X.encStart(key, { noStage = true, yaw = 66, seed = seed }) then s.phase = 'talk' else stt.hitchNext = nil; s.phase = 'home'; s.no = true; walkTo(s.w, { s.home }) end
    end
  elseif s.phase == 'talk' then
    stand(s.w, s.F.side, t)
    if not X.encActive() then
      if X.hitchOn() then
        -- (she climbs in: from here she sits beside the driver)
        sideClean()
        rideOn()
      else
        s.phase, s.no = 'home', true
        walkTo(s.w, { besideAt(s.F, s.w.pos, -s.F.side, 1.5), s.home })
      end
    end
  end
end
local function sideTick()
  if side or ride then return end
  local st = X.state()
  local km = X.km()
  -- (the first one soon after the start: 6 to 14 km)
  st.sideKm = st.sideKm or (km + 6 + math.random() * 8)
  if km < st.sideKm then return end
  local v = X.truck()
  if not v or X.speed(v) < 8 or not X.sideOk() or X.hitchOn() then return end
  if sideSpawn(v) then
    st.sideKm = km + M.SIDE_KM[1] + math.random() * (M.SIDE_KM[2] - M.SIDE_KM[1])
  else
    st.sideKm = km + 1
  end
end

function M.attach(ctx) X = ctx end
function M.frame(dt)
  if not X then return end
  local ok, err = pcall(function()
    crewFrame(dt)
    rideFrame()
    chatTick()
    sideFrame(dt)
    if outW then
      if walkStep(outW, dt) then stand(outW, outW.dir, now()) end
      local v = X.truck()
      if now() > outW.till or (v and (X.vehPos(v) - outW.pos):length() > 150) then kill(outW.o); outW = nil end
    end
    local t = now()
    if byeTill and t > byeTill then byeTill = nil; if not chat then X.trigger('FernfahrerCop', { off = true }) end end
    if t - secT >= 1 then
      secT = t
      -- (a passenger from the save: she sits in again; a truck swapped: she moves with it)
      if X.hitchOn() and not ride and not side and not X.encActive() then rideOn() end
      if ride and X.truck() and ride.id ~= X.truck():getID() then if X.cabRider then X.cabRider(nil) end; kill(ride.o); ride = nil end
      if not X.hitchOn() and ride then rideOff() end
      sideTick()
    end
  end)
  if not ok then
    log('E', 'fernfahrer', 'crew: ' .. tostring(err))
    M.clean()
  end
end
function M.clean()
  M.serviceClean()
  chatClose()
  if ride then if X.cabRider then X.cabRider(nil) end; kill(ride.o); ride = nil end
  sideClean()
  if outW then kill(outW.o); outW = nil end
end
return M
