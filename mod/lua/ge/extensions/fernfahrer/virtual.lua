-- Trucks of Earth: virtual traffic (2026-11-12).
-- "Virtueller Verkehr": the cars out of the player's sight are no BeamNG vehicles at all, only points on the road network, worked out
-- here - a few dozen of them for the price of a table. They drive (each its own pace, keeping its distance to the one in front, turning
-- off at junctions), they queue in a jam, and they come into being when the player could see them: a real car from far away (out of
-- sight, of no use where it is) becomes the virtual one, there, at its speed. The real car it was is not lost either: where it stood
-- it becomes a virtual one in its place. So the traffic the player has overtaken is still behind it, and there is as much of it as the
-- roads would have, not as many as the machine can carry. BeamNG's own respawning is off meanwhile (spawnValue 0, trafficai.lua).
-- trafficai.lua calls M.update every look; api (M.init): linksOf, roadAt, send, dlog, rnd, flow, nodes(), respawn(id, pos, dir), busy(id).

local M = {}
M.C = {
  STEP_S = 0.5,
  RADIUS_M = 1500,          -- the virtual world round the player
  SPAWN_MIN_M = 700,        -- new ones only this far away (out of sight) ...
  -- (2026-11-12, Verkehrstest 18-08: nearly never a virtual car - Earth has the roads loaded not that far round the truck; 118 came
  -- into being in 39 minutes, 116 of them at once at the end of the network. Now the ring follows how far the roads reach)
  SPAWN_REACH_SHARE = 0.65, -- ... or at this share of the distance nine in ten of the nodes round the player are within ...
  SPAWN_FLOOR_M = 380,      -- ... but never nearer than this
  GONE_M = 1800,            -- further than this: gone
  BASE_N = 90,              -- how many at the busiest hour (times the hour, the rhythm, the kind of road) (2026-11-12: 60, more traffic wanted)
  SPAWN_PER_STEP = 4,
  JAM_REAL_MS = 6,          -- (2026-11-12) in a jam (its speed below this) one stays virtual: the jam's own cars are put there by trafficflow.lua
  NODES_S = 15,             -- the list of nodes round the player, new this often
  MAT_MIN_M = 190,          -- a virtual car this far from the player and nearer than MAT_MAX_M becomes a real one
  MAT_MAX_M = 320,
  MAT_PER_STEP = 2,         -- (2026-11-12: 1 - a group coming into sight comes together)
  DONOR_M = 420,            -- a real car this far from the player (or DONOR_BEHIND_M behind it, getting further away) can become another one
  DONOR_BEHIND_M = 180,     -- (2026-11-12: 121 times no car to spare - the oncoming ones gone past the truck did not count, now everyone moving away)
  CLEAR_M = 14,             -- nobody this close where it comes into being ...
  CLEAR_LANE_S = 2.5,       -- ... and nobody in its lane within this many seconds of its speed
  NEW_S = 6,                -- a car just made real: trafficai.lua leaves its "put behind the player" alone this long
  IDM_A = 1.3, IDM_B = 2.2, IDM_T = 1.4, IDM_S0 = 3, LEN_M = 4.6,
  PACE = { 0.9, 1.05 },     -- each its own share of the limit
  STRAIGHT_POW = 3,         -- at a junction: the way on straight ahead the likelier
  START_MS = 0.6,           -- a new one starts at this share of its pace
  -- (2026-11-12) lane changes on roads with two or more lanes: past a slower one on the left, back to the right when there is room
  LC_LOOK_M = 70,           -- one in front nearer than this ...
  LC_GAIN_MS = 2,           -- ... and slower than it wants by this: to the left, if the lane is free
  LC_BACK_S = 1.5,          -- free: nobody behind in that lane within this many seconds of its speed (plus LC_BACK_M) ...
  LC_BACK_M = 10,
  LC_FRONT_M = 25,          -- ... nor ahead within this
  LC_RIGHT_M = 120,         -- back to the right: nobody there in front within this
  LC_HOLD_S = 6,            -- after a change, not again before this
  -- (2026-11-12, the player: "dass an einem Auto 3 weitere Autos hängen und die fahren dann in einer Schlange ... das vordere Auto reagiert
  -- als erstes und die hinteren fahren hinterher". Traffic comes in groups - behind a slower one, out of a town, off a slip road. Not tied
  -- together: each one drives itself and may turn off or pull out later, so a group breaks up and another forms)
  GAP_T = { 0.9, 2.4 },     -- (each one's time gap when on its own)
  -- (2026-11-12, Verkehrstest 22-57, the motorway: around the A3 most of the roads are town streets. Virtual cars were made real there,
  -- drove off away from the player and were taken again seconds later; on the motorway itself few real cars. And they did not know
  -- of wrecks: at full speed to just before one, made real there at that speed - crash after crash in its zone)
  BIG_ONLY_SHARE = 0.75,    -- the player on a big road (a carriageway of two lanes or more): new ones there this often, else anywhere
  -- (2026-11-13, Verkehrstest 18-24, stopped after 7 min: "komisches Gefühl bei der Anzahl der Autos" - one real car about on average. New
  -- virtual ones came on any road in the ring, mostly side roads and town streets; on the player's own road not one came within 150 m in
  -- 6.6 minutes. Now a share of them on the player's own road, along its course: oncoming ahead, ahead its way, behind catching up)
  OWN_ROAD_SHARE = 0.5,
  -- (2026-11-13, Verkehrstest 19-00: on the motorway 0.7 to 1.3 cars about - of 3084 new ones 2967 ran off the end of the loaded network
  -- after some 10 s: most went away from the player, ahead of it and faster, or on other roads the other way. New ones come towards the
  -- player now: oncoming or from behind on its road, on other roads only heading its way; on a one-way road the oncoming share comes behind)
  OWN_ROAD_MIX = { oncoming = 0.5, ahead = 0.1, behind = 0.4 },
  TOWARDS_SHARE = 0.9,      -- of those on other roads, this share must head towards the player (a few going away keep it lively)
  OWN_ROAD_TURN_COS = 0.5,  -- following the road on through a junction: only about straight on
  -- (2026-11-13, Verkehrstest 19-00: in the game only 149 of 3084 new ones came on the player's road - Earth had seldom loaded it 380 m
  -- and more: the walk ran off the end of the loaded network. Where it ends, the furthest point of it will do, if it is this far)
  OWN_ROAD_MIN_M = 220,     -- (2026-11-13, test 19-52: 300 - and in 5511 tries the loaded road was shorter)
  -- (2026-11-13, Verkehrstest 19-52: 1.8 real cars about, the noon scene on the country road without a single car for 7 minutes. Earth loads
  -- the player's road seldom 300 m, the virtual ones ran off its end (6 left of 64 wanted) - and the real cars slept in the pool, woken only
  -- by a virtual one becoming real. BeamNG's own respawning, the old safety net, does not touch reserve cars. Now a floor: fewer than
  -- REAL_FLOOR real cars within FLOOR_R_M, and a sleeping one is woken and put on the player's road out of the way - oncoming ahead or
  -- coming up from behind)
  -- (2026-11-14, Verkehrstest 15-35: "die Autos müssen dieselben Modelle werden, wenn es geht in gleicher Farbe" - 77 of 221 another model.
  -- Each placeholder now has its real car set aside from the start: a sleeping one of the pool (its model and colour drawn), and one that
  -- became a placeholder keeps its own real car - it comes back as itself. And "ab und zu wird ein echtes gleich wieder weg": one just made
  -- real stays real MIN_REAL_S at least)
  MIN_REAL_S = 20,
  -- (2026-11-14, Verkehrstest 18-43: still 348 times another model - the drawn placeholders outnumber the sleeping cars to set aside. One
  -- without a sleeping car picks an active one far off as its future real car (SOFT_*), and while it is still far off itself it takes on that
  -- car's model and colour: the change happens where nobody sees it)
  SOFT_EVERY_S = 1, SOFT_SWAP_M = 260,
  SHAPE_BEHIND_S = 2.5,
  SHAPE_URGENT_S = 0.6, SHAPE_NEAR_M = 20,   -- (2026-11-14, Verkehrstest 17-48: 1.2 s / 25 m - still 543 times another model, most made real early for a meeting)   -- (2026-11-14) made real in another model only when meeting a real one this soon, or this near
  -- (2026-11-14, Verkehrstest 15-35: "über Kreuzungen fahren die nicht echten Autos einfach drüber, und der echte Verkehr bremst für sie".
  -- A virtual car comes up to a junction (three roads or more) at JUNC_MS at most, and stops before it for a real vehicle about to cross)
  JUNC_LOOK_M = 40, JUNC_MS = 8, JUNC_REAL_M = 35, JUNC_REAL_S = 4, JUNC_STOP_M = 7,
  REAL_FLOOR = 6,
  -- (2026-11-14, Verkehrstest 23-53: the floor came once in 37 min - 884 times no road: Earth's own road was seldom 150 m long. Then one
  -- from behind, nearer, as far as the road goes, any way on through a junction)
  FLOOR_SHORT_M = { 70, 140 },
  FLOOR_R_M = 350,
  FLOOR_EVERY_S = 2,
  FLOOR_M = { 150, 260 },
  FLOOR_CLEAR_M = 20,
  FLOOR_BEHIND_DV = 5,      -- one from behind: at most this much faster than the truck (m/s)
  FLOOR_AHEAD_S = 4,        -- ... and nobody in its lane ahead within this many seconds of its speed
  -- (and a real car is put to sleep only when it is going away - one coming nearer would only be woken again, a stir for nothing)
  DEMAT_CLOSING_MS = 1,
  NEAR_ZONE_M = 60,
  NEAR_WRECK_ANY_M = 15,    -- (2026-11-14) and not this near a wreck or an accident whichever way it faces (past its zone's length)         -- not made real this close before a wreck, an accident or an obstacle (or in it)
  -- (2026-11-13, the player: "Platzhalter-Autos ... nur 50 Meter ... damit wir den Verkehr voll machen können, ohne Leistung zu ziehen.
  -- Das ist sehr wichtig". Placeholders: a virtual car in sight is drawn as the car's model alone (a TSStatic, no physics), moved here
  -- every frame along its road. Coming nearer than PROXY_MAT_M it becomes a real car; a real one further than PROXY_DEMAT_M becomes a
  -- placeholder again, and the real car is parked out of sight (invisible, AI off, asleep) as the next one to be used)
  PROXY_ON = true,
  -- (2026-11-13, the player after the look at 20 m: "die Farben sahen gut aus ... wir müssen auf jeden Fall weiter weg, so auf 40, 50 Meter.
  -- Und die müssen trotzdem Rücksicht nehmen und bremsen, wenn ich ankomme" - a placeholder drove into the truck: they saw only each other)
  PROXY_MAT_M = 45,
  PROXY_DEMAT_M = 130,      -- (2026-11-14: 90 - a car going away stays real a little longer, it vanished from sight too soon)
  REAL_LOOK_M = 120,        -- a virtual car keeps its distance to real vehicles (the truck, its trailer, the real traffic) ahead in its lane ...
  REAL_LAT_M = 2.3,         -- ... this far beside its line at most
  MAT_NEAR_REAL_M = 35,
  -- (2026-11-13, Verkehrstest 02-10: "die Autos werden zu spät echte Autos und dadurch passieren Unfälle". 165 times "no room", 28 made
  -- real, most at 10 to 40 m: the room check of a car out of nowhere (nobody coming up behind in the lane within its speed's seconds)
  -- forbade the one in front of the truck - the truck itself was the one coming up. A placeholder is there already: only not in another)
  PROXY_CLEAR_M = 6,        -- a placeholder becomes real unless a vehicle is this close to its place
  PROXY_BUMPER_M = 1.5,     -- ... or closer than half of both lengths and this (a van, a lorry)
  PROXY_TTC_S = 4,          -- ... and by the time to meet: coming fast, earlier (up to PROXY_MAT_MAX_M)
  PROXY_MAT_MAX_M = 150,
  VIRT_DECEL_MAX = 4.5,
  ZONE_B = 2.0,             -- (towards a zone: slowing at this, m/s²)     -- (a virtual car brakes no harder than a real one)
  MAT_SAFE_DECEL = 3.5,
  -- (2026-11-13, the player: "an der gleichen Stelle mit derselben Geschwindigkeit wie die Nicht-Physikautos ... dass man das kaum
  -- sieht, dass das jetzt umspringt". The donor's own speed and the placeholder's could differ a lot (it was driving somewhere else a
  -- moment before) - a fixed 0.25 s snap to the placeholder's speed then meant a hard, visible lurch. Now the time it takes depends on
  -- how big that gap is: a close match is instant, a big one eases in, never harder than MAT_ACCEL_CAP)
  -- (2026-11-13, Verkehrstest 13-42: that was wrong - a car moved with respawnVehicle is reset by the game and stands, whatever it did
  -- before. A long catching-up time left it slow in the traffic for over a second, and the ones behind braked hard for it. Back to a short,
  -- fixed time to the placeholder's speed)
  MAT_SNAP_S = 0.2,     -- made real only if a real car there could stop behind the one in front with this
  PROXY_JAM_MAT_M = 18,     -- in a jam (its speed below JAM_REAL_MS) a placeholder becomes real only this near     -- a real one closing on a placeholder this near in its lane: the placeholder becomes real (the game's AI sees only real ones)
  PROXY_FAR_M = 750,        -- drawn up to this far (2026-11-14: 480 - "die Platzhalter müssen einen größeren Bereich haben"; Earth loads about 500 m, so every virtual car on it is drawn)
  -- (2026-11-14, Verkehrstest 23-53: "man sieht die Autos Bild für Bild, und um Kurven teleportieren sie sich". Drawn, a placeholder stopped
  -- at the end of its edge until the next step moved it on (Earth's edges are a few metres: every half second a halt and a jump) and turned
  -- in one frame at every node. Now it is drawn along the way it will take - its next few edges - and round each node on an arc)
  AHEAD_N = 3,              -- the next nodes it will take, known in advance
  CORNER_M = 7,             -- each node rounded off over this much either side (at most 45 % of the edges there)
  EXTRAP_MAX_S = 0.8,       -- between two steps drawn on at its speed at most this long
  -- (2026-11-14, Verkehrstest 23-53: "es fahren immer noch viele Autos durch die nicht echten Autos durch". The real cars do not see a
  -- placeholder; it saw only real ones ahead in its lane. Now any real vehicle that would meet it within CONFLICT_S - from behind, coming
  -- the other way, across - makes it real at once (a real car then minds it); where it cannot be made real it gives way, and while one
  -- is right in it, it is not drawn)
  CONFLICT_LOOK_M = 70,
  CONFLICT_S = 3,
  CONFLICT_DT = 0.25,
  CONFLICT_LAT_M = 1.9,     -- (side by side closer than this, along closer than half their lengths and CONFLICT_ALONG_M: they meet)
  CONFLICT_ALONG_M = 0.8,
  CONFLICT_YIELD_S = 1.6,   -- not made real and meeting this soon: it brakes (one coming from behind: it does not)
  CONFLICT_REACH_M = 140,   -- made real for a meeting up to this far from the player
  PROXY_MAX = 70,           -- at most this many placeholders (the nearest)
  PROXY_Z_S = 1.0,          -- its height from the ground under it, looked again this often
  PROXY_PARK_M = 450,       -- a real car no longer needed stands this far behind the truck, on the road it came along
  PROXY_DEMAT_PER_STEP = 3,
  PROXY_MAT_PER_STEP = 4,
  PROXY_DIRS = { '/vehicles/agent_traffic_eu2/', '/vehicles/agent_traffic_eunew1/' },
  -- (2026-11-13, Verkehrstest 01-11: "die Straße war komplett kaputt". 1444 placeholders made - a free one was only taken again for the
  -- same model, the hidden ones stayed - and the graphics card ran out ("material cbv array exhausted", 8192 slots): roads and land
  -- drawn wrong. Now never more than PROXY_OBJ_MAX objects; a car takes whichever is free, and with it its model)
  PROXY_OBJ_MAX = 70,
  PROXY_SHAPES = 10,        -- of the models found, this many in use (fewer models, fewer materials)
  PLATOON_SHARE = 0.55,     -- of the new ones, this share comes as a group ...
  PLATOON_N = { 2, 4 },     -- ... of this many
  PLATOON_T = 1.1,          -- the ones behind keep this time gap (s) to the one in front (the others IDM_T) ...
  PLATOON_PACE = 1.04,      -- ... and would go a little faster than their leader: they stay on its tail
  PLATOON_CATCH = 1.08,     -- ... fallen back, this much keener until it is on its tail again
  PLATOON_HOLD_S = 60,      -- ... and for this long they do not pull out to pass it
  PLATOON_FOLLOW_T = 1.0,   -- made real: the mod's own driver keeps this time gap (driver.lua setFollowT)
}
local C = M.C
local api
M.cars = {}                  -- seq -> car
M.just = {}                  -- real id -> time it was made real
M.parked = {}                -- real id -> time it was parked (a placeholder took its place)
local proxyOf = {}           -- virtual car id -> { o, shape }
local proxyFree = {}         -- shape -> { objects }
local shapes = nil
M.stats = { n = 0, spawned = 0, removed = 0, made = 0, noDonor = 0, blocked = 0, toVirtual = 0, deadEnd = 0, steps = 0, noGround = 0, laneChanges = 0, reach = 0, spawnMin = 0 }
local seq, stepT, nodesT, nodeList = 0, -1e9, -1e9, {}
local spawnMin = C.SPAWN_MIN_M
local buckets = {}

function M.init(a) api = a end
function M._api() return api end            -- (the checks: the game side as trafficai.lua gave it)

-- (2026-11-14, Verkehrstest 20-47: a placeholder made real 7 m beside the truck - 53000 damage. The scan has no lengths: every real vehicle was
-- 4.6 m long here, the lorry and its trailer too. Their real length now, from the game)
local function lenOf(rid, o) return (o and o.len) or (api and api.lengthOf and api.lengthOf(rid)) or C.LEN_M end
local function flat(v) local l = math.sqrt(v.x * v.x + v.y * v.y); if l < 1e-6 then return nil end return vec3(v.x / l, v.y / l, 0) end

-- the lanes of the edge a -> b for one driving from a to b
local function lanesOf(link, a)
  local plus, minus = 0, 0
  if type(link.lanes) == 'string' then
    local _, p = link.lanes:gsub('%+', ''); local _, m = link.lanes:gsub('%-', ''); plus, minus = p, m
  end
  if plus + minus == 0 then return 1, link.oneWay and 0 or 1 end
  if link.oneWay then return math.max(1, plus + minus), 0 end
  local along = link.inNode == a
  local mine, against = along and plus or minus, along and minus or plus
  if mine == 0 then mine = 1 end
  return mine, against
end
M._lanesOf = lanesOf

local function allowed(link, from) return not link.oneWay or link.inNode == from end

-- a car onto the edge a -> b
local function setEdge(car, nodes, a, b, s)
  local na, nb = nodes[a], nodes[b]
  local link = api.linksOf(nodes, a)[b]
  if not na or not nb or not link then return false end
  local pa, pb = vec3(na.pos), vec3(nb.pos)
  local d = pb - pa
  local len = d:length()
  if len < 0.5 then return false end
  -- (the way it went, for the ones of its group behind it: the last few nodes)
  if car.b and car.b == a then
    car.via = car.via or {}
    car.via[a] = b
    car.viaN = (car.viaN or 0) + 1
    if car.viaN > 12 then car.via, car.viaN = { [a] = b }, 1 end
  end
  if car.b and car.b == a and car.a then car.prevA = car.a else car.prevA, car.ahead = nil, nil end
  car.a, car.b, car.s, car.len = a, b, s or 0, len
  car.pa, car.dir = pa, d * (1 / len)
  car.half = link.inRadius or na.radius or 3.5
  car.mine, car.against = lanesOf(link, a)
  car.lane = math.max(1, math.min(car.mine, car.lane or math.floor(api.rnd(1, car.mine + 0.999))))
  car.limit = (tonumber(link.speedLimit) or 22)
  car.want = car.limit * car.pace
  car.nextB = car.ahead and car.ahead[1] or nil
  return true
end

-- where it is in the world, and which way it faces
function M.posOf(car)
  local total = car.mine + car.against
  local w = 2 * car.half / math.max(1, total)
  local lat = -car.half + car.against * w + (car.lane - 0.5) * w
  local fd = flat(car.dir) or vec3(1, 0, 0)
  local right = vec3(fd.y, -fd.x, 0)
  local p = car.pa + car.dir * car.s + right * lat
  return p, fd
end

-- the way on from b (not back): straight ahead the likelier; nil: a dead end
local function pickFrom(nodes, car, ca, cb)
  -- (2026-11-12) one of a group takes the way its leader took (for a while: then it may go its own way)
  local ld = car.pl and M.cars[car.pl]
  if ld and ld.via and ld.via[cb] and car.plT and stepT - car.plT < C.PLATOON_HOLD_S then
    local k = ld.via[cb]
    local l = api.linksOf(nodes, cb)[k]
    if l and nodes[k] and k ~= ca and allowed(l, cb) then return k end
  end
  local links = api.linksOf(nodes, cb)
  local nb, na = nodes[cb], nodes[ca]
  if not nb then return nil end
  local fdir = (na and flat(vec3(nb.pos) - vec3(na.pos))) or (cb == car.b and flat(car.dir)) or nil
  local best, sum, opts = nil, 0, {}
  for k, l in pairs(links) do
    if k ~= ca and nodes[k] and allowed(l, cb) then
      local d = flat(vec3(nodes[k].pos) - vec3(nb.pos))
      local fd = fdir
      local dot = (d and fd) and d:dot(fd) or 0
      local wgt = math.max(0.03, ((dot + 1) / 2) ^ C.STRAIGHT_POW) * (tonumber(l.drivability) or 1)
      sum = sum + wgt
      opts[#opts + 1] = { k, wgt }
    end
  end
  if #opts == 0 then return nil end
  local r = api.rnd(0, sum)
  for _, o in ipairs(opts) do r = r - o[2]; if r <= 0 then return o[1] end end
  return opts[#opts][1]
end
local function pickNext(nodes, car) return pickFrom(nodes, car, car.a, car.b) end
-- (2026-11-14) the next few nodes it will take: the step follows them, and the drawing draws along them
local function fillAhead(nodes, car)
  car.ahead = car.ahead or {}
  local pa, pb = car.a, car.b
  for i = 1, #car.ahead do pa, pb = pb, car.ahead[i] end
  while #car.ahead < C.AHEAD_N do
    local k = pickFrom(nodes, car, pa, pb)
    if not k then break end
    car.ahead[#car.ahead + 1] = k
    pa, pb = pb, k
  end
  car.nextB = car.ahead[1]
end
M._fillAhead = fillAhead
M._setEdge = function(car, nodes, a, b, s0) return setEdge(car, nodes, a, b, s0) end
M._stepAt = function(t0) stepT = t0 end     -- (the checks: the time of the last step)

local function key(a, b) return tostring(a) .. '>' .. tostring(b) end
local function rebucket()
  buckets = {}
  for _, car in pairs(M.cars) do
    local k = key(car.a, car.b)
    local bk = buckets[k]; if not bk then bk = {}; buckets[k] = bk end
    bk[#bk + 1] = car
  end
end
-- the one in front in its lane: on its edge, else on the next; the gap (bumper to bumper) and its speed
local function leaderOf(car)
  local bestGap, bestV = nil, nil
  for _, o in ipairs(buckets[key(car.a, car.b)] or {}) do
    if o ~= car and o.s > car.s and o.lane == car.lane then
      local g = o.s - car.s - C.LEN_M
      if not bestGap or g < bestGap then bestGap, bestV = g, o.v end
    end
  end
  if bestGap or not car.nextB then return bestGap, bestV end
  for _, o in ipairs(buckets[key(car.b, car.nextB)] or {}) do
    if o.lane == math.min(car.lane, o.mine) then
      local g = car.len - car.s + o.s - C.LEN_M
      if not bestGap or g < bestGap then bestGap, bestV = g, o.v end
    end
  end
  return bestGap, bestV
end

local function newCar()
  repeat seq = seq + 1 until not M.cars[-seq]      -- (never over one there is)
  -- (2026-11-12: each its own time gap, from close to roomy - not all alike)
  local car = { id = -seq, pace = api.rnd(C.PACE[1], C.PACE[2]), T = C.GAP_T[1] + (C.GAP_T[2] - C.GAP_T[1]) * api.rnd(0, 1) ^ 1.3 }
  return car
end
M.reserved = {}                -- (2026-11-14) a sleeping real car -> the virtual car it is set aside for
M.madeAt = {}                  -- real car -> when it was made real (MIN_REAL_S)
M.justV = {}                   -- real car -> the speed it was made real at (trafficai holds it there for the first moments)
local function release(car)
  if car.donorId and M.reserved[car.donorId] == car.id then M.reserved[car.donorId] = nil end
  car.donorId = nil
end
-- a sleeping real car set aside for this virtual one: its model and colour are the placeholder's
-- (set aside for a placeholder that is drawn right now: that one keeps it; one not drawn gives it up to whoever needs it)
local function heldFor(id, car)
  local r = M.reserved[id]
  return r ~= nil and M.cars[r] ~= nil and (not car or r ~= car.id) and proxyOf[r] ~= nil
end
local function takeFrom(id)
  local r = M.reserved[id]
  if r and M.cars[r] and M.cars[r].donorId == id then M.cars[r].donorId = nil end
  M.reserved[id] = nil
end
M._heldFor = heldFor
local function reserveFor(car, drawing)
  if car.donorId then return end
  -- (a free one first; else one set aside for a placeholder not drawn now - drawn ones need theirs more)
  local pick
  for id in pairs(M.parked) do
    if not api.alive or api.alive(id) then
      local r = M.reserved[id]
      if not r or not M.cars[r] then pick = id; break end
      if not pick and not heldFor(id, car) and (drawing or proxyOf[car.id] ~= nil) then pick = id end
    end
  end
  if pick then
    local id = pick
    takeFrom(id)
    do
      M.reserved[id] = car.id
      car.donorId = id
      car.shape = M.shapeOf and M.shapeOf(id) or car.shape
      car.color = api.colorOf and api.colorOf(id) or car.color
      return
    end
  end
end
local function add(car) M.cars[car.id] = car; M.stats.spawned = M.stats.spawned + 1; reserveFor(car) end
local function remove(car, why)
  release(car)
  M.cars[car.id] = nil
  if M.dropProxy then M.dropProxy(car.id) end
  M.stats.removed = M.stats.removed + 1
  if why == 'dead end' then M.stats.deadEnd = M.stats.deadEnd + 1 end
end

-- the nodes round the player (refreshed every NODES_S)
local function refreshNodes(nodes, ppos)
  nodeList = {}
  local r2 = C.RADIUS_M * C.RADIUS_M
  local near = {}
  for id, n in pairs(nodes) do
    local np = n.pos
    if np then
      local dx, dy = np.x - ppos.x, np.y - ppos.y
      local d2 = dx * dx + dy * dy
      if d2 < r2 then near[#near + 1] = { id, d2 } end
    end
  end
  -- (how far the roads reach round the player: nine in ten of the nodes within)
  table.sort(near, function(x, y) return x[2] < y[2] end)
  local reach = #near > 0 and math.sqrt(near[math.max(1, math.floor(#near * 0.9))][2]) or 0
  spawnMin = math.max(C.SPAWN_FLOOR_M, math.min(C.SPAWN_MIN_M, reach * C.SPAWN_REACH_SHARE))
  M.stats.reach, M.stats.spawnMin = math.floor(reach), math.floor(spawnMin)
  local m2 = spawnMin * spawnMin
  for _, e in ipairs(near) do if e[2] > m2 then nodeList[#nodeList + 1] = e[1] end end
end

-- one more somewhere out of sight
local function bigLink(l) local mine = lanesOf(l, l.inNode); return l.oneWay and mine >= 2 end
-- (2026-11-13) the player's own road, followed about straight on: the edge a -> b (the walk's way) and how far along it, dist from the player
local function straightOn(nodes, a, b, anyTurn)
  local h = flat(vec3(nodes[b].pos) - vec3(nodes[a].pos))
  if not h then return nil end
  local best, bd = nil, anyTurn and -0.2 or C.OWN_ROAD_TURN_COS
  for k in pairs(api.linksOf(nodes, b)) do
    if k ~= a and nodes[k] then
      local hk = flat(vec3(nodes[k].pos) - vec3(nodes[b].pos))
      local dd = hk and hk:dot(h) or -1
      if dd > bd then best, bd = k, dd end
    end
  end
  return best
end
local function alongOwnRoad(nodes, ppos, pdir, dist, backwards, minM, anyTurn)
  local centre, _, _, back, fwd = api.roadAt(ppos, pdir)
  if not centre or not back or not fwd or not nodes[back] or not nodes[fwd] then M.stats.ownNoRoad = (M.stats.ownNoRoad or 0) + 1; return nil end
  local a, b = back, fwd
  if backwards then a, b = fwd, back end
  local travelled = vec3(nodes[b].pos):distance(ppos)
  for _ = 1, 80 do
    local len = vec3(nodes[b].pos):distance(vec3(nodes[a].pos))
    if travelled >= dist then return a, b, math.max(0, len - (travelled - dist)) end
    local nxt = straightOn(nodes, a, b, anyTurn)
    if not nxt then
      if travelled >= (minM or C.OWN_ROAD_MIN_M) then M.stats.ownShort = (M.stats.ownShort or 0) + 1; return a, b, len end
      M.stats.ownEnd = (M.stats.ownEnd or 0) + 1
      return nil
    end
    a, b = b, nxt
    travelled = travelled + vec3(nodes[b].pos):distance(vec3(nodes[a].pos))
  end
  return nil
end
M._alongOwnRoad = alongOwnRoad
-- where a new one goes on the player's own road: { a, b, s } in the car's own way of driving, or nil
local function ownRoadPick(nodes, p, dMin, dMax, noAhead, forceKind, minM, anyTurn)
  if not p or not p.pos or not p.dir then return nil end
  dMin = dMin or spawnMin
  dMax = dMax or math.max(spawnMin + 20, (M.stats.reach or spawnMin) * 0.95)
  local dist = api.rnd(dMin, math.max(dMin + 1, dMax))
  local r = api.rnd(0, 1)
  local mix = C.OWN_ROAD_MIX
  local kind = r < mix.oncoming and 'oncoming' or (r < mix.oncoming + mix.ahead and 'ahead' or 'behind')
  if noAhead and kind == 'ahead' then kind = 'behind' end
  if forceKind then kind = forceKind end
  for _ = 1, 2 do
    local a, b, s = alongOwnRoad(nodes, p.pos, p.dir, dist, kind == 'behind', minM, anyTurn)
    if not a then return nil end
    local len = vec3(nodes[b].pos):distance(vec3(nodes[a].pos))
    local wa, wb = a, b
    -- (the walk went a -> b away from the player: oncoming and those behind drive b -> a, towards the player)
    if kind == 'oncoming' or kind == 'behind' then a, b, s = b, a, len - s end
    local link = api.linksOf(nodes, a)[b]
    if link and allowed(link, a) then return { a = a, b = b, s = s, kind = kind } end
    -- (no oncoming on a one-way carriageway: from behind instead)
    if kind ~= 'oncoming' then return nil end
    kind = 'behind'
  end
  return nil
end

local function spawnOne(nodes, ppos, bigOnly, pick)
  if #nodeList == 0 and not pick then return false end
  local a, b
  if pick then
    a, b = pick.a, pick.b
  else
    a = nodeList[math.floor(api.rnd(1, #nodeList + 0.999))]
    local opts = {}
    for k, l in pairs(api.linksOf(nodes, a)) do if nodes[k] and allowed(l, a) and (not bigOnly or bigLink(l)) then opts[#opts + 1] = k end end
    if #opts == 0 then return false end
    b = opts[math.floor(api.rnd(1, #opts + 0.999))]
    -- (heading towards the player, most of them: one going away is soon at the end of the loaded network and gone)
    if api.rnd(0, 1) < C.TOWARDS_SHARE and vec3(nodes[b].pos):distance(ppos) > vec3(nodes[a].pos):distance(ppos) then
      local back = api.linksOf(nodes, b)[a]
      if back and allowed(back, b) then a, b = b, a else return false end
    end
  end
  local car = newCar()
  if not setEdge(car, nodes, a, b, 0) then return false end
  car.s = pick and math.min(car.len, math.max(0, pick.s)) or api.rnd(0, car.len)
  for _, o in ipairs(buckets[key(a, b)] or {}) do if math.abs(o.s - car.s) < 20 and o.lane == car.lane then return false end end
  car.v = car.want * C.START_MS
  local p = M.posOf(car)
  local minD = pick and math.min(spawnMin, C.OWN_ROAD_MIN_M) or spawnMin     -- (on the player's own road: as far as Earth has loaded it)
  if p:distance(ppos) < minD then return false end
  M.stats.minSpawnD = math.min(M.stats.minSpawnD or 1e9, p:distance(ppos))
  add(car)
  local k = key(a, b); buckets[k] = buckets[k] or {}; table.insert(buckets[k], car)
  -- (a group: the others behind it in its lane, at its time gap, a little keener than it)
  if api.rnd(0, 1) < C.PLATOON_SHARE then
    local n = math.floor(api.rnd(C.PLATOON_N[1], C.PLATOON_N[2] + 0.999))
    local prev = car
    for _ = 2, n do
      local gap = C.LEN_M + C.IDM_S0 + prev.v * C.PLATOON_T
      local s = prev.s - gap
      if s < 0 then break end
      local f = newCar()
      f.lane = car.lane
      if not setEdge(f, nodes, a, b, s) then break end
      local fd0 = M.posOf(f):distance(ppos)
      if fd0 < minD then break end             -- (out of sight, all of them)
      M.stats.minSpawnD = math.min(M.stats.minSpawnD or 1e9, fd0)
      f.pace = math.min(C.PACE[2] * 1.1, car.pace * C.PLATOON_PACE)
      f.want = f.limit * f.pace
      f.v = prev.v
      f.pl, f.plT = car.id, stepT
      f.plGap = C.PLATOON_T * api.rnd(0.8, 1.3)
      add(f)
      table.insert(buckets[k], f)
      M.stats.platoon = (M.stats.platoon or 0) + 1
      prev = f
    end
  end
  return true
end

-- a real car into a virtual one, where it is (nil: it is nowhere on the network)
function M.toVirtual(id, o)
  if not o or not o.pos or not o.dir then return nil end
  local centre, d, _, a, b, nodes = api.roadAt(o.pos, o.dir)
  if not centre or not a or not b or not nodes then return nil end
  local na, nb = nodes[a], nodes[b]
  if not na or not nb then return nil end
  -- (driving from a to b, or the other way?)
  local ab = flat(vec3(nb.pos) - vec3(na.pos))
  if not ab then return nil end
  if ab:dot(o.dir) < 0 then a, b = b, a; na, nb = nb, na; ab = -ab end
  local link = api.linksOf(nodes, a)[b]
  if not link or not allowed(link, a) then return nil end
  local car = newCar()
  car.lane = nil
  if not setEdge(car, nodes, a, b, 0) then return nil end
  car.s = math.max(0, math.min(car.len, (o.pos - vec3(na.pos)):dot(car.dir)))
  -- (its lane from where it is across the road)
  local total = car.mine + car.against
  local w = 2 * car.half / math.max(1, total)
  local fd = flat(car.dir)
  local lat = (o.pos - (car.pa + car.dir * car.s)):dot(vec3(fd.y, -fd.x, 0))
  car.lane = math.max(1, math.min(car.mine, math.floor((lat - (-car.half + car.against * w)) / w) + 1))
  car.v = o.speed or car.want * C.START_MS
  car.shape = M.shapeOf(id)                -- (2026-11-13: its placeholder in its own shape)
  -- (2026-11-14) and its own colour, and this very car is set aside for it: when it comes back, it comes back as itself
  car.color = api.colorOf and api.colorOf(id) or nil
  car.donorId = id
  M.reserved[id] = car.id
  M.cars[car.id] = car; M.stats.spawned = M.stats.spawned + 1
  M.stats.toVirtual = M.stats.toVirtual + 1
  return car
end

-- a real car that can be spared: far away, or well behind the player going away; nobody's in a jam or busy
-- (2026-11-13, the player: "die Modelle der Platzhalter mit den echten verbinden, damit wenn die auftauchen auch das Modell da ist - die Farbe
-- ist nicht so wichtig, Hauptsache die Form passt". A real car's model: from its configuration, cached)
local shapeById = {}
function M.shapeOf(id)
  if shapeById[id] == nil then shapeById[id] = (api.shapeOf and api.shapeOf(id)) or false end
  return shapeById[id] or nil
end
local function donor(list, all, p, pid, tid, shape, car)
  -- (2026-11-13) one parked out of sight first - of the placeholder's model if there is one
  local parkedAny = nil
  -- (2026-11-13) a sleeping one wakes only if BeamNG's active ones have room - else a far active one is taken, as before)
  local room = not api.poolRoom or api.poolRoom()
  -- (2026-11-14) the one set aside for it
  if car and car.donorId and room and M.parked[car.donorId] and (not api.alive or api.alive(car.donorId)) then
    M.stats.sameShape = (M.stats.sameShape or 0) + 1
    M.stats.ownDonor = (M.stats.ownDonor or 0) + 1
    return car.donorId
  end
  if car and car.softDonor and M.soft[car.softDonor] == car.id and not M.parked[car.softDonor] and not M.just[car.softDonor]
     and (not api.alive or api.alive(car.softDonor)) and (not shape or M.shapeOf(car.softDonor) == shape) then
    M.stats.sameShape = (M.stats.sameShape or 0) + 1
    M.stats.softUsed = (M.stats.softUsed or 0) + 1
    local id = car.softDonor
    M.soft[id], car.softDonor = nil, nil
    return id
  end
  for id in pairs(M.parked) do
    local r = M.reserved[id]
    if api.alive and not api.alive(id) then M.parked[id] = nil
    elseif heldFor(id, car) then
      -- (set aside for another one, drawn now)
    elseif not room then
      -- (none of the parked)
    else
      if shape and M.shapeOf(id) == shape then M.stats.sameShape = (M.stats.sameShape or 0) + 1; return id end
      parkedAny = parkedAny or id
    end
  end
  local best, far, bestSame, farSame = nil, -1, nil, -1
  local fl = api.flow
  for _, id in pairs(list) do
    if id ~= pid and id ~= tid and not (fl and (fl.member[id] or fl.cause[id] or fl.eco[id])) and not (api.busy and api.busy(id))
       and not (api.isActive and not api.isActive(id))
       -- (2026-11-12, Verkehrstest 22-07: one car made real 47 times, three times within a second - just moved, it was not yet where the scan
       -- sees it, so it looked like the best one far away. One just made real is no donor)
       and not M.just[id] and not M.parked[id] then
      local o = all[id]
      -- (2026-11-12, Verkehrstest 19-46: not one car in 7 minutes - all of them stood more than 1.7 km off, where the traffic began, out of
      -- trafficai's scan; those were left out, and BeamNG's respawning was off. Out of the scan: the best one there is)
      if not o then
        -- (out of the scan: as far as can be)
        if shape and M.shapeOf(id) == shape and farSame < 1e8 then bestSame, farSame = id, 1e8 end
        if far < 1e8 then best, far = id, 1e8 end
      end
      if o then
        local rel = o.pos - p.pos
        local d, along = rel:length(), rel:dot(p.dir)
        -- (getting further away from the player: its speed minus the player's, along the line between them)
        local ov = o.vel or (o.dir and o.dir * (o.speed or 0)) or vec3(0, 0, 0)
        local pv = p.vel or p.dir * (p.speed or 0)
        local away = d > 1 and (ov - pv):dot(rel * (1 / d)) > -0.5
        if d > C.DONOR_M or (along < -C.DONOR_BEHIND_M and away) then
          if d > far then best, far = id, d end
          if shape and d > farSame and M.shapeOf(id) == shape then bestSame, farSame = id, d end
        end
      end
    end
  end
  if bestSame then M.stats.sameShape = (M.stats.sameShape or 0) + 1; return bestSame end
  if shape and (parkedAny or best) then M.stats.otherShape = (M.stats.otherShape or 0) + 1 end
  return parkedAny or best
end

M._leaderOf = function(car) rebucket(); return leaderOf(car) end
M._donorFor = function(car) return donor({}, {}, { pos = vec3(0, 0, 0), dir = vec3(1, 0, 0) }, nil, nil, car.shape, car) end
-- (2026-11-13) the nearest real vehicle ahead of a virtual car in its lane (the truck and its trailer among them): the gap and its speed along
local junctionAhead
local function realLeader(car, all)
  if not all then return nil end
  local pos, fd = M.posOf(car)
  local right = vec3(fd.y, -fd.x, 0)
  local bestGap, bestV = nil, nil
  for rid, o in pairs(all) do
    if o.pos and not M.parked[rid] then         -- (a parked one is not on the road for anybody)
      local rel = o.pos - pos
      local along = rel:dot(fd)
      if along > 0 and along < C.REAL_LOOK_M and math.abs(rel:dot(right)) < C.REAL_LAT_M then
        local od = o.dir
        local sp = o.speed or 0
        local its = od and od:dot(fd) * sp or 0
        -- (one going its way, or one standing or slow across it; not one coming the other way in the next lane)
        if its > -1 or sp < 2 then
          local g = along - C.LEN_M - lenOf(rid, o) * 0.5 + 2.3
          if not bestGap or g < bestGap then bestGap, bestV = g, math.max(0, its) end
        end
      end
    end
  end
  return bestGap, bestV
end
M._realLeader = realLeader

-- (2026-11-14) a junction ahead (a node of three roads or more): the speed to come up to it with, and the gap to stop at if a real vehicle
-- is about to cross it (one on another road heading for the node within JUNC_REAL_S)
junctionAhead = function(car, nodes, all)
  local nb = nodes and nodes[car.b]
  if not nb then return nil end
  local toNode = car.len - car.s
  if toNode > C.JUNC_LOOK_M then return nil end
  local deg = 0
  for _ in pairs(api.linksOf(nodes, car.b)) do deg = deg + 1 end
  if deg < 3 then return nil end
  local w = math.sqrt(C.JUNC_MS * C.JUNC_MS + 2 * 2.0 * math.max(0, toNode - 5))
  local np = vec3(nb.pos)
  local fd = flat(car.dir)
  for rid, o in pairs(all or {}) do
    if o.pos and o.dir and not M.parked[rid] then
      local rel = np - o.pos
      local d = rel:length()
      if d < C.JUNC_REAL_M and d > 2 and fd and math.abs(o.dir:dot(fd)) < 0.7 then
        local sp = o.speed or 0
        local towards = rel:dot(o.dir) > 0
        if towards and (d / math.max(1, sp) < C.JUNC_REAL_S or d < 12) then
          return math.max(0, toNode - C.JUNC_STOP_M), w
        end
      end
    end
  end
  return nil, w
end
M._junctionAhead = function(car, nodes, all) return junctionAhead(car, nodes, all) end

-- (2026-11-12) a lane free for it here? (the ones in that lane on its edge: none behind within its speed's seconds, none just ahead)
local function laneFree(car, lane, front)
  for _, o in ipairs(buckets[key(car.a, car.b)] or {}) do
    if o ~= car and o.lane == lane then
      local ds = o.s - car.s
      if ds > -(C.LC_BACK_M + car.v * C.LC_BACK_S) and ds < (front or C.LC_FRONT_M) then return false end
    end
  end
  return true
end
local function changeLanes(car, t, capped)
  if car.mine < 2 or capped or (car.lcT and t - car.lcT < C.LC_HOLD_S) then return end
  local gap, lv = leaderOf(car)
  local inGroup = car.pl and M.cars[car.pl] and car.plT and t - car.plT < C.PLATOON_HOLD_S
  if not inGroup and gap and gap < C.LC_LOOK_M and lv and lv < car.want - C.LC_GAIN_MS and car.lane > 1 and laneFree(car, car.lane - 1) then
    car.lane = car.lane - 1
    car.lcT = t
    M.stats.laneChanges = M.stats.laneChanges + 1
  elseif car.lane < car.mine and (not gap or gap > C.LC_RIGHT_M) and laneFree(car, car.lane + 1, C.LC_RIGHT_M) then
    car.lane = car.lane + 1
    car.lcT = t
    M.stats.laneChanges = M.stats.laneChanges + 1
  end
end

-- room where it would come into being?
local function clearAt(pos, dir, v, all)
  local right = vec3(dir.y, -dir.x, 0)
  for _, o in pairs(all) do
    local rel = o.pos - pos
    if rel:length() < C.CLEAR_M then return false end
    if o.dir and o.dir:dot(dir) > 0.5 and math.abs(rel:dot(right)) < 2.5 then
      local along = rel:dot(dir)
      if along > -(v * C.CLEAR_LANE_S + 10) and along < v * 1.0 + 15 then return false end
    end
  end
  return true
end

-- (2026-11-14) the real vehicle (the truck, its trailer, the traffic) that would meet this placeholder soonest within CONFLICT_S: its id, when,
-- and whether it comes from behind in its lane
local function conflictOf(car, pos, fd, all)
  local right = vec3(fd.y, -fd.x, 0)
  local vv = fd * (car.v or 0)
  local best, bt, fromBehind
  for rid, o in pairs(all) do
    if o.pos and not M.parked[rid] then
      local rel = o.pos - pos
      if math.abs(rel.z) < 4 then
        rel = vec3(rel.x, rel.y, 0)
        if rel:length() < C.CONFLICT_LOOK_M then
          local ov = (o.dir or fd) * (o.speed or 0)
          local rv = vec3(ov.x - vv.x, ov.y - vv.y, 0)
          local hl = 0.5 * (C.LEN_M + lenOf(rid, o)) + C.CONFLICT_ALONG_M
          local tt = 0
          while tt <= C.CONFLICT_S do
            local dp = rel + rv * tt
            if math.abs(dp:dot(right)) < C.CONFLICT_LAT_M and math.abs(dp:dot(fd)) < hl then
              if not bt or tt < bt then best, bt = rid, tt; fromBehind = rel:dot(fd) < 0 and o.dir and o.dir:dot(fd) > 0.5 end
              break
            end
            tt = tt + C.CONFLICT_DT
          end
        end
      end
    end
  end
  return best, bt, fromBehind
end
M._conflictOf = conflictOf

-- before a wreck, an accident or an obstacle (or in it), its way: no place to become real
local function nearBlockOf(pos, fd, zonesNow, before)
  if not zonesNow then return false end
  for _, z in ipairs(zonesNow) do
    -- (2026-11-14, Verkehrstest 01-42: placeholders made real into a wreck three times in a minute - one standing the other way, or across.
    -- Near one, whichever way: no)
    if (z.kind == 'wreck' or z.kind == 'accident') and z.pos and (pos - z.pos):length() < (z.len or 40) + C.NEAR_WRECK_ANY_M then return true end
    if (z.kind == 'wreck' or z.kind == 'accident' or z.kind == 'obstacle') and z.pos and z.dir and fd:dot(z.dir) > 0.3 then
      local zr = pos - z.pos
      local al = zr:dot(z.dir)
      if al > -(before or C.NEAR_ZONE_M) and al < (z.len or 40) + 10 and math.abs(zr:dot(vec3(z.dir.y, -z.dir.x, 0))) < 12 then return true end
    end
  end
  return false
end

-- every look of trafficai.lua: p the player's snapshot, all: the real vehicles about, list: the traffic's ids
function M.update(t, p, pid, tid, all, list, ctx)
  if not ctx.virtualOn or not ctx.virtualOn() then
    if next(M.cars) then for cid in pairs(proxyOf) do M.dropProxy(cid) end; M.cars = {}; buckets = {} end
    if next(M.parked) then for id in pairs(M.parked) do if api.unpark then api.unpark(id) end end; M.parked = {} end
    return
  end
  if t - stepT < C.STEP_S then return end
  local dt = math.min(2, t - stepT)
  if stepT < 0 then dt = C.STEP_S end
  stepT = t
  if not p or not p.pos or not p.dir then return end
  local nodes = api.nodes()
  if not nodes then return end
  M.stats.steps = M.stats.steps + 1
  local ppos = p.pos
  if t - nodesT >= C.NODES_S then nodesT = t; refreshNodes(nodes, ppos) end
  for id, at in pairs(M.just) do if t - at > C.NEW_S then M.just[id] = nil end end
  rebucket()
  -- driving
  local fl = api.flow
  local jamOn = fl and fl.active and fl.active()
  local zonesNow = api.zones and api.zones() or nil
  for _, car in pairs(M.cars) do
    local ldv = car.pl and M.cars[car.pl] and M.cars[car.pl].via
    if ldv and ldv[car.b] and car.ahead and car.ahead[1] and ldv[car.b] ~= car.ahead[1] then car.ahead = nil end
    fillAhead(nodes, car)
    -- (2026-11-14) a real one about to meet it, and it could not be made real: it gives way)
    local want = car.want
    if car.yieldUntil and t < car.yieldUntil then want = 0 end
    local capped = false
    if jamOn and fl.capFor then
      local pos, fd = M.posOf(car)
      local okJ, jc = pcall(fl.capFor, car.id, { pos = pos, dir = fd }, t)
      if okJ and jc then want = math.min(want, jc); capped = jc < car.want - 1 end
    end
    changeLanes(car, t, capped)
    -- (the zones: a wreck, an accident, roadworks, a learned spot - their speed, as the real cars)
    if zonesNow then
      local pos, fd = M.posOf(car)
      for _, z in ipairs(zonesNow) do
        if z.pos and z.dir and z.limit and fd:dot(z.dir) > 0.5 then
          local rel = pos - z.pos
          local along = rel:dot(z.dir)
          local vz = math.max(4, z.limit / 3.6)
          -- (2026-11-13: the highest speed from which it can still slow to the zone's by its start - a smooth curve; before, braking was
          -- on or off by the speed of the moment, and it braked and sped up by turns)
          if along > -400 and along < (z.len or 40) and math.abs(rel:dot(vec3(z.dir.y, -z.dir.x, 0))) < 12 then
            want = math.min(want, math.sqrt(vz * vz + 2 * C.ZONE_B * math.max(0, -along)))
          end
        end
      end
    end
    local gap, lv = leaderOf(car)
    do
      local rg, rv = realLeader(car, all)
      if rg and (not gap or rg < gap) then gap, lv = rg, rv end
    end
    do
      local jg, jw = junctionAhead(car, nodes, all)
      if jw and jw < want then want = jw end
      if jg and (not gap or jg < gap) then gap, lv = jg, 0; M.stats.juncWait = (M.stats.juncWait or 0) + 1 end
    end
    local v = car.v
    -- (one of a group fallen back - starting off, after a light: it closes up again)
    if car.pl and M.cars[car.pl] and (not gap or gap > C.IDM_S0 + v * (car.plGap or C.PLATOON_T) * 2 + 8) then want = want * C.PLATOON_CATCH end
    local acc = C.IDM_A * (1 - (v / math.max(0.5, want)) ^ 4)
    if v > want then acc = math.min(acc, (want - v) * 1.2) end   -- (above what it wants - a zone ahead, a jam: down to it, not by a little)
    if gap then
      local dv = v - (lv or v)
      local tGap = (car.pl and M.cars[car.pl]) and (car.plGap or C.PLATOON_T) or (car.T or C.IDM_T)
      local sStar = C.IDM_S0 + math.max(0, v * tGap + v * dv / (2 * math.sqrt(C.IDM_A * C.IDM_B)))
      acc = acc - C.IDM_A * (sStar / math.max(0.3, gap)) ^ 2
    end
    -- (2026-11-13, Verkehrstest 02-30: 8 m/s² - placeholders stopped as no real car can, and were made real at a speed that could not stop
    -- behind what stood in front: 75 crashes in one spot, half of them younger than 5 s. A real car's braking, started early by the IDM)
    acc = math.max(-C.VIRT_DECEL_MAX, acc)
    car.v = math.max(0, v + acc * dt)
    -- (never into the one in front: with a real car's braking it may not stop in time - it stops at the bumper, at its speed)
    local adv = car.v * dt
    if gap and adv > gap - 0.5 then
      adv = math.max(0, gap - 0.5)
      car.v = math.min(car.v, lv or 0)
      M.stats.bumperStop = (M.stats.bumperStop or 0) + 1
    end
    car.s = car.s + adv
    while car.s > car.len do
      local over = car.s - car.len
      local nb = (car.ahead and table.remove(car.ahead, 1)) or pickNext(nodes, car)
      if not nb then remove(car, 'dead end'); break end
      local a = car.b
      if not setEdge(car, nodes, a, nb, over) then remove(car, 'dead end'); break end
    end
  end
  -- the population: gone when too far, new ones out of sight up to the number the hour wants
  local n = 0
  for _, car in pairs(M.cars) do
    local pos = M.posOf(car)
    if pos:distance(ppos) > C.GONE_M then remove(car, 'far') else n = n + 1 end
  end
  local playerBig = false
  do
    local _, _, _, _, _, _, plink = api.roadAt(p.pos, p.dir)
    playerBig = type(plink) == 'table' and bigLink(plink) or false
  end
  local hours = ctx.hours and ctx.hours() or 12
  local f = (fl and fl.hourFactor and fl.hourFactor(hours) or 1) * (fl and fl.pulse and fl.pulse(t) or 1) * (fl and fl.roadF or 1)
  local target = math.floor(C.BASE_N * f + 0.5)
  for _ = 1, C.SPAWN_PER_STEP do
    if n >= target then break end
    local bigOnly = playerBig and api.rnd(0, 1) < C.BIG_ONLY_SHARE
    local got = false
    if api.rnd(0, 1) < C.OWN_ROAD_SHARE then
      local pk = ownRoadPick(nodes, p)
      if pk then
        got = spawnOne(nodes, ppos, false, pk)
        if got then M.stats.ownRoad = (M.stats.ownRoad or 0) + 1 end
      end
    end
    if not got then got = spawnOne(nodes, ppos, bigOnly) end
    if not got and bigOnly then for _ = 1, 4 do got = spawnOne(nodes, ppos, true); if got then break end end end
    if got then n = n + 1 end
  end
  M.stats.n = n
  M.stats.target = target
  M.lastList = list
  M.demat(t, p, pid, tid, all, list)
  M.floor(t, p, pid, tid, all, nodes)
  M.softDonors(t, p, pid, tid, all, list)
  -- coming into sight: a real car takes its place
  local proxies = M.proxiesOn()
  local matMin, matMax = C.MAT_MIN_M, C.MAT_MAX_M
  if proxies then matMin, matMax = 12, C.PROXY_MAT_M end
  local made = 0
  local ring = {}
  for _, car in pairs(M.cars) do
    local pos, fd = M.posOf(car)
    local d = pos:distance(ppos)
    local nearReal = false
    if proxies and d >= matMax and d < C.PROXY_DEMAT_M + 20 then
      local rg, rv = nil, nil
      -- (a real one behind it in its lane, closing: looked at from that one - the placeholder is its leader)
      local right = vec3(fd.y, -fd.x, 0)
      for rid, o in pairs(all) do
        if o.pos and o.dir and not M.parked[rid] then
          local rel = pos - o.pos
          local along = rel:dot(fd)
          if along > 0 and along < C.MAT_NEAR_REAL_M and math.abs(rel:dot(right)) < C.REAL_LAT_M and o.dir:dot(fd) > 0.5 and (o.speed or 0) > car.v - 1 then nearReal = true; break end
        end
      end
    end
    -- (2026-11-14) one about to meet a real vehicle: made real now, the nearest such first
    local cf, cft, cfBehind = nil, nil, nil
    if proxies and d < C.CONFLICT_REACH_M then cf, cft, cfBehind = conflictOf(car, pos, fd, all) end
    if cf then
      car.conflictAt, car.conflictT, car.conflictBehind = t, cft, cfBehind
      -- (not made real just before a wreck, an accident, an obstacle: there it gives way, as a placeholder - the twin: made real there for a
      -- meeting, it went on through the block)
      if nearBlockOf(pos, fd, zonesNow, math.max(C.NEAR_ZONE_M, (car.v or 0) * 9)) then M.stats.nearZone = (M.stats.nearZone or 0) + 1
      else ring[#ring + 1] = { car, pos, fd, d - 1000 + cft * 100, 1, true, d } end
      M.stats.conflict = (M.stats.conflict or 0) + 1
    elseif nearReal then
      ring[#ring + 1] = { car, pos, fd, d, 1, true }
      M.stats.nearReal = (M.stats.nearReal or 0) + 1
    elseif d > matMin and d < (proxies and math.min(C.PROXY_MAT_MAX_M, math.max(matMax, ((-((fd * car.v - (p.vel or p.dir * (p.speed or 0))):dot((pos - ppos) * (1 / math.max(1, d))))) * C.PROXY_TTC_S))) or matMax) then
      -- (only one coming nearer: one going away out of sight would only be taken back)
      local rel = pos - ppos
      local pv = p.vel or p.dir * (p.speed or 0)
      local closing = -((fd * car.v - pv):dot(rel * (1 / math.max(1, d))))
      local nearBlock = nearBlockOf(pos, fd, zonesNow)
      if nearBlock then M.stats.nearZone = (M.stats.nearZone or 0) + 1
      elseif closing > 0.5 then ring[#ring + 1] = { car, pos, fd, d, closing }
      else M.stats.goingAway = (M.stats.goingAway or 0) + 1 end
    end
  end
  table.sort(ring, function(x, y) if x[4] ~= y[4] then return x[4] < y[4] end return x[1].id > y[1].id end)   -- (the nearest first)
  -- (2026-11-13, Verkehrstest 10-23: two of a standing virtual queue made real in the same step, 5 m apart - the first was not yet among
  -- the real ones the second was checked against: one into the other, 10000 damage each. Those made in this step count, and the room
  -- is by the lengths, a van's too)
  local placedNow = {}
  for _, r in ipairs(ring) do
    if made >= (proxies and C.PROXY_MAT_PER_STEP or C.MAT_PER_STEP) then break end
    local car, pos, fd, d = r[1], r[2], r[3], r[7] or r[4]
    local inJam = false
    if jamOn and fl.capFor then
      local okJ, jc = pcall(fl.capFor, car.id, { pos = pos, dir = fd }, t)
      inJam = okJ and jc ~= nil and jc < C.JAM_REAL_MS
    end
    -- (with placeholders a jam is drawn by them too: near the player it becomes real like any other, at the jam's speed)
    -- (2026-11-13, the player: "im Stau dürfen sie auch ruhig näher an mir dran sein" - at walking pace a placeholder stays one closer)
    if inJam and proxies and d > C.PROXY_JAM_MAT_M and not r[6] then M.stats.jamCloser = (M.stats.jamCloser or 0) + 1
    elseif inJam and not proxies then M.stats.inJam = (M.stats.inJam or 0) + 1 else
      -- (2026-11-14) where it is drawn, round the node too - the real car takes its place there, facing its way)
      if proxies then pos, fd = M.poseOf(car, t, nodes) end
      local z = pos.z
      if not proxies then
        local na, nb = nodes[car.a], nodes[car.b]
        if na and nb then z = na.pos.z + (nb.pos.z - na.pos.z) * (car.s / car.len) end
      end
      local clear
      if proxies then
        clear = true
        local here = vec3(pos.x, pos.y, z)
        for rid, o in pairs(all) do
          if o.pos and not M.parked[rid] and o.pos:distance(here) < math.max(C.PROXY_CLEAR_M, lenOf(rid, o) * 0.5 + C.LEN_M * 0.5 + C.PROXY_BUMPER_M) then clear = false; break end
        end
        if clear then
          for _, q in ipairs(placedNow) do
            if q:distance(here) < math.max(C.PROXY_CLEAR_M, C.LEN_M + C.PROXY_BUMPER_M + 2) then clear = false; M.stats.sameStep = (M.stats.sameStep or 0) + 1; break end
          end
        end
      else
        clear = clearAt(pos, fd, car.v, all)
      end
      -- (could a real car there stop behind the one in front of it? If not, it stays a placeholder and brakes on, as a placeholder)
      if clear and proxies then
        local g, lv = leaderOf(car)
        local rg, rv = realLeader(car, all)
        if rg and (not g or rg < g) then g, lv = rg, rv end
        if g and car.v > (lv or 0) + 0.5 then
          local need = (car.v - (lv or 0)) ^ 2 / (2 * math.max(0.5, g - 2))
          if need > C.MAT_SAFE_DECEL then clear = false; M.stats.tooFast = (M.stats.tooFast or 0) + 1 end
        end
      end
      if not clear then
        M.stats.blocked = M.stats.blocked + 1
      elseif api.groundOk and not api.groundOk(vec3(pos.x, pos.y, z)) then
        M.stats.noGround = M.stats.noGround + 1
      else
        local id = donor(list, all, p, pid, tid, proxies and car.shape or nil, car)
        if not id then
          M.stats.noDonor = M.stats.noDonor + 1
          break
        end
        -- (2026-11-14, Verkehrstest 16-46: 92 times another model - nothing of its own model to spare just then. Unless it is urgent (a real
        -- one about to meet it) or right at the truck, it stays a placeholder a little longer, until one of its model is free)
        local dShape = M.shapeOf(id)
        local wrongShape = proxies and car.shape and dShape and dShape ~= car.shape
        -- (2026-11-14, Verkehrstest 20-47: one coming up from behind was waited out to 0.6 s - made real then, right in front of it at 30 to
        -- 40 km/h with 3 to 6 m to go: rear-ended. From behind, urgent at SHAPE_BEHIND_S already)
        local urgent = (car.conflictAt == t and (car.conflictT or 9) < (car.conflictBehind and C.SHAPE_BEHIND_S or C.SHAPE_URGENT_S)) or d < C.SHAPE_NEAR_M
        if wrongShape and not urgent then
          M.stats.waitShape = (M.stats.waitShape or 0) + 1
          goto nextRing
        end
        -- (the real one it was: a virtual one where it is - unless it stood parked, then it was nowhere)
        takeFrom(id)
        car.donorId = nil
        if M.parked[id] then
          M.parked[id] = nil
          if api.unpark then api.unpark(id) end
        else
          M.toVirtual(id, all[id])
        end
        if api.respawn(id, vec3(pos.x, pos.y, z + 0.4), fd) then
          placedNow[#placedNow + 1] = vec3(pos.x, pos.y, z)
          M.dropProxy(car.id)
          api.send(id, string.format('thrusters.applyVelocity(obj:getDirectionVector() * %.1f, %.2f)', car.v, C.MAT_SNAP_S))
          M.just[id] = t
          M.madeAt[id], M.justV[id] = t, car.v
          -- (2026-11-14: counted where it happens - sameShape/otherShape count the search, also when it then waits)
          if proxies and car.shape then
            local rs = M.shapeOf(id)
            if rs == car.shape then M.stats.realSame = (M.stats.realSame or 0) + 1
            elseif rs then M.stats.realOther = (M.stats.realOther or 0) + 1 end
          end
          if car.pl then
            api.send(id, string.format('if fernfahrer_driver and fernfahrer_driver.setFollowT then fernfahrer_driver.setFollowT(%.2f) end', C.PLATOON_FOLLOW_T))
            M.stats.platoonReal = (M.stats.platoonReal or 0) + 1
          end
          release(car)
          M.cars[car.id] = nil
          M.stats.made = M.stats.made + 1
          made = made + 1
          api.dlog('virtual: car %d made real %.0f m away (%.0f km/h, lane %d/%d)%s', id, d, car.v * 3.6, car.lane, car.mine, car.conflictAt == t and ' - meeting a real one' or '')
        end
      end
    end
    ::nextRing::
  end
  M.afterConflicts(t)
end

-- (2026-11-14) after the making real: a placeholder still meeting a real vehicle gives way (unless that one comes from behind), and is not
-- drawn while one is right in it
function M.afterConflicts(t)
  for _, car in pairs(M.cars) do
    if car.conflictAt == t and car.conflictT then
      if car.conflictT <= C.CONFLICT_YIELD_S and not car.conflictBehind then car.yieldUntil = t + 1.0; M.stats.gaveWay = (M.stats.gaveWay or 0) + 1 end
      if car.conflictT < 0.01 then car.hideUntil = t + 0.8; M.stats.hidden = (M.stats.hidden or 0) + 1 end
    end
  end
end

-- (2026-11-14) a far active real car picked in advance for each drawn placeholder that has no sleeping one set aside
M.soft = {}                    -- real car -> virtual car it is picked for
function M.softDonors(t, p, pid, tid, all, list)
  if not M.proxiesOn() or not p or not p.pos then return end
  if t - (M.softT or -1e9) < C.SOFT_EVERY_S then return end
  M.softT = t
  for rid, cid in pairs(M.soft) do if not M.cars[cid] or M.cars[cid].softDonor ~= rid then M.soft[rid] = nil end end
  local fl = api.flow
  local free = {}
  for _, id in pairs(list or {}) do
    if id ~= pid and id ~= tid and not M.parked[id] and not M.just[id] and not M.soft[id]
       and not (fl and (fl.member[id] or fl.cause[id] or fl.eco[id])) and not (api.busy and api.busy(id)) then
      local o = all[id]
      local far = not o or o.pos:distance(p.pos) > C.DONOR_M
      if far then free[#free + 1] = id end
    end
  end
  for cid, car in pairs(M.cars) do
    if #free == 0 then break end
    if proxyOf[cid] and not car.donorId and not (car.softDonor and M.soft[car.softDonor] == cid) then
      reserveFor(car, true)
      if not car.donorId then
        -- (one of its own model if there is one; else, if it is far enough off, any - and it takes that model on)
        local pos = M.posOf(car)
        local d = pos:distance(p.pos)
        local pick
        for k, id in ipairs(free) do if M.shapeOf(id) == car.shape then pick = k; break end end
        if not pick and d > C.SOFT_SWAP_M then pick = 1 end
        if pick then
          local id = table.remove(free, pick)
          car.softDonor = id
          M.soft[id] = cid
          local sh = M.shapeOf(id)
          if sh and sh ~= car.shape then
            car.shape, car.color = sh, api.colorOf and api.colorOf(id) or nil
            M.dropProxy(cid)               -- (drawn anew in its new model, far off)
            M.stats.softSwap = (M.stats.softSwap or 0) + 1
          end
        end
      end
    end
  end
end

-- (2026-11-13) never an empty road: a sleeping real car woken onto the player's road when too few real ones are about
function M.floor(t, p, pid, tid, all, nodes)
  if not M.proxiesOn() or not p or not p.pos or not p.dir or not nodes then return end
  if t - (M.floorT or -1e9) < C.FLOOR_EVERY_S then return end
  M.floorT = t
  local nReal = 0
  for rid, o in pairs(all) do
    if o.pos and rid ~= pid and rid ~= tid and not M.parked[rid] and o.pos:distance(p.pos) < C.FLOOR_R_M then nReal = nReal + 1 end
  end
  M.stats.realNear = nReal
  if nReal >= C.REAL_FLOOR then return end
  if api.poolRoom and not api.poolRoom() then return end
  local id = nil
  for pid2 in pairs(M.parked) do
    local r = M.reserved[pid2]
    if api.alive and not api.alive(pid2) then M.parked[pid2] = nil
    elseif not heldFor(pid2) then id = pid2; break end
  end
  if id then takeFrom(id) end
  if not id then return end
  local pk = ownRoadPick(nodes, p, C.FLOOR_M[1], C.FLOOR_M[2], true)
  if not pk then
    pk = ownRoadPick(nodes, p, C.FLOOR_SHORT_M[1], C.FLOOR_SHORT_M[2], true, 'behind', C.FLOOR_SHORT_M[1], true)
    if pk then M.stats.floorShort = (M.stats.floorShort or 0) + 1 end
  end
  if not pk then M.stats.floorNoRoad = (M.stats.floorNoRoad or 0) + 1; return end
  local car = newCar()
  if not setEdge(car, nodes, pk.a, pk.b, 0) then return end
  car.s = math.min(car.len, math.max(0, pk.s))
  local pos, fd = M.posOf(car)
  local na, nb = nodes[pk.a], nodes[pk.b]
  local z = pos.z
  if na and nb then z = na.pos.z + (nb.pos.z - na.pos.z) * (car.s / math.max(1, car.len)) end
  local here = vec3(pos.x, pos.y, z)
  -- (one from behind: only a little faster than the truck - the twin: woken at the road's pace, they came up on the traffic too fast)
  local v = car.want * 0.9
  if pk.kind == 'behind' then v = math.min(v, (p.speed or 0) + C.FLOOR_BEHIND_DV) end
  local right = vec3(fd.y, -fd.x, 0)
  for rid, o in pairs(all) do
    if o.pos and not M.parked[rid] then
      local rel = o.pos - here
      local along = rel:dot(fd)
      local blocked = rel:length() < C.FLOOR_CLEAR_M
      -- (and nobody in its lane ahead within its few seconds)
      if not blocked and along > 0 and along < v * C.FLOOR_AHEAD_S + 15 and math.abs(rel:dot(right)) < 2.5 then blocked = true end
      if blocked then M.stats.floorBlocked = (M.stats.floorBlocked or 0) + 1; return end
    end
  end
  for _, vc in pairs(M.cars) do
    if M.posOf(vc):distance(here) < C.FLOOR_CLEAR_M then M.stats.floorBlocked = (M.stats.floorBlocked or 0) + 1; return end
  end
  if api.groundOk and not api.groundOk(here) then return end
  -- (2026-11-14) nor just before a wreck, an accident, an obstacle
  if nearBlockOf(here, fd, api.zones and api.zones() or nil, math.max(C.NEAR_ZONE_M, v * 9)) then M.stats.floorZone = (M.stats.floorZone or 0) + 1; return end
  M.parked[id] = nil
  if api.unpark then api.unpark(id) end
  if not api.respawn(id, vec3(here.x, here.y, here.z + 0.4), fd) then return end
  api.send(id, string.format('thrusters.applyVelocity(obj:getDirectionVector() * %.1f, %.2f)', v, C.MAT_SNAP_S))
  M.just[id] = t
  M.madeAt[id], M.justV[id] = t, v
  M.stats.floor = (M.stats.floor or 0) + 1
  api.dlog('virtual: car %d woken onto the player\'s road, %s, %.0f m (only %d real ones about)', id, pk.kind, here:distance(p.pos), nReal)
end

-- placeholders on? (the virtual traffic on, the switch, and what the game side gives)
function M.proxiesOn() return C.PROXY_ON and api and api.proxyNew ~= nil and api.park ~= nil end

-- (2026-11-13) a real car gone far from the player: a placeholder where it is, the real car parked out of sight
function M.demat(t, p, pid, tid, all, list)
  if not M.proxiesOn() or not p or not p.pos then return end
  local n = 0
  local fl = api.flow
  for _, id in pairs(list) do
    if n >= C.PROXY_DEMAT_PER_STEP then break end
    local o = all[id]
    if o and id ~= pid and id ~= tid and not M.parked[id] and not M.just[id] and not (M.madeAt[id] and t - M.madeAt[id] < C.MIN_REAL_S)
       and not (fl and (fl.member[id] or fl.cause[id] or fl.eco[id])) and not (api.busy and api.busy(id)) then
      local d = o.pos:distance(p.pos)
      local closing = 0
      if d > 1 and o.dir then
        local pv = p.vel or (p.dir and p.dir * (p.speed or 0)) or vec3(0, 0, 0)
        closing = -((o.dir * (o.speed or 0) - pv):dot((o.pos - p.pos) * (1 / d)))
      end
      if d > C.PROXY_DEMAT_M and d < C.PROXY_FAR_M and closing > C.DEMAT_CLOSING_MS then M.stats.keptComing = (M.stats.keptComing or 0) + 1 end
      if d > C.PROXY_DEMAT_M and d < C.PROXY_FAR_M and closing <= C.DEMAT_CLOSING_MS then
        local spot, sdir = nil, nil
        if api.parkSpot then spot, sdir = api.parkSpot(C.PROXY_PARK_M, p.pos, p.dir) end
        -- (2026-11-13: asleep where it is, if BeamNG's pool has it - no spot needed)
        if spot or (api.canDormant and api.canDormant(id)) then
          local car = M.toVirtual(id, o)
          if car then
            if api.park(id, spot, sdir) then
              M.parked[id] = t
              M.stats.parked = (M.stats.parked or 0) + 1
              n = n + 1
              api.dlog('virtual: car %d parked out of sight, a placeholder in its place (%.0f km/h)', id, (o.speed or 0) * 3.6)
            else
              M.cars[car.id] = nil
            end
          end
        end
      end
    end
  end
end

local proxyCount = 0
local shapesN = -1
-- (2026-11-13) the models of the real traffic, one entry for every car of it: a new placeholder looks like a car there is, so the real
-- one that takes its place can be of the same model. Before any are known: a few of the folders' models)
local function shapeList()
  local lst = M.lastList
  local n = lst and #lst or 0
  if shapes and #shapes > 0 and n == shapesN then return shapes end
  local out = {}
  if lst then for _, id in ipairs(lst) do local s = M.shapeOf(id); if s then out[#out + 1] = s end end end
  if #out == 0 then
    local all0 = {}
    if api.shapes then for _, s in ipairs(api.shapes(C.PROXY_DIRS) or {}) do all0[#all0 + 1] = s end end
    table.sort(all0)
    local step = math.max(1, #all0 / C.PROXY_SHAPES)
    for i = 1, #all0, step do out[#out + 1] = all0[math.floor(i)] end
  else
    shapesN = n
  end
  shapes = out
  return shapes
end
-- a free placeholder object: of this model if one is free, else any free one, else a new one while under the cap
local function takeProxy(car, list)
  car.shape = car.shape or list[math.floor(api.rnd(1, #list + 0.999))]
  local free = proxyFree[car.shape]
  local o = free and table.remove(free)
  if o then return o, car.shape end
  if proxyCount < C.PROXY_OBJ_MAX then
    o = api.proxyNew(car.shape)
    if o then proxyCount = proxyCount + 1; M.stats.proxies = proxyCount; return o, car.shape end
  end
  for shape, fl in pairs(proxyFree) do
    local o2 = table.remove(fl)
    if o2 then car.shape = shape; return o2, shape end
  end
  return nil
end
-- (2026-11-14) the placeholder objects gone (a new world): forget them all, new ones are made as needed
function M.lostProxies()
  proxyOf, proxyFree, proxyCount = {}, {}, 0
  M.materialsDone = nil
  M.stats.proxyLost = (M.stats.proxyLost or 0) + 1
  if api and api.dlog then api.dlog('placeholders: the objects are gone (a new world?) - made again') end
end
function M.dropProxy(cid)
  local e = proxyOf[cid]
  if not e then return end
  proxyOf[cid] = nil
  if api.proxyHide then api.proxyHide(e.o) end
  proxyFree[e.shape] = proxyFree[e.shape] or {}
  table.insert(proxyFree[e.shape], e.o)
end
-- (2026-11-14) where a virtual car is drawn this frame: on from its last step at its speed along its edge and the next ones it will take,
-- each node rounded off on an arc (a quadratic curve from CORNER_M before the node to CORNER_M after it), its lane kept, its height from
-- the nodes. Returns the position and the way it faces (flat)
local function latOf(car, link, a, half)
  local mine, against = lanesOf(link, a)
  local total = mine + against
  local w = 2 * half / math.max(1, total)
  local lane = math.max(1, math.min(mine, car.lane or 1))
  return -half + against * w + (lane - 0.5) * w
end
local function segOf(nodes, car, a, b)
  local na, nb = nodes[a], nodes[b]
  local link = na and nb and api.linksOf(nodes, a)[b]
  if not link then return nil end
  local A, B = vec3(na.pos), vec3(nb.pos)
  local len = A:distance(B)
  if len < 0.5 then return nil end
  local d = flat(B - A)
  if not d then return nil end
  local half = link.inRadius or na.radius or 3.5
  return { A = A, B = B, len = len, d = d, lat = latOf(car, link, a, half) }
end
local function onSeg(sg, x)
  local f = math.max(0, math.min(1, x / sg.len))
  return sg.A + (sg.B - sg.A) * f
end
function M.poseOf(car, t, nodes)
  local s = car.s + (car.v or 0) * math.max(0, math.min(C.EXTRAP_MAX_S, (t or stepT) - stepT))
  local total = car.mine + car.against
  local w = 2 * car.half / math.max(1, total)
  local cur = { A = vec3(car.pa), B = car.pa + car.dir * car.len, len = car.len, d = flat(car.dir) or vec3(1, 0, 0), lat = -car.half + car.against * w + (car.lane - 0.5) * w }
  if not nodes then
    local p = onSeg(cur, s)
    return p + vec3(cur.d.y, -cur.d.x, 0) * cur.lat, cur.d
  end
  -- (the edge before, for the arc at its start)
  local segs, k0 = { cur }, 1
  if car.prevA then
    local pv = segOf(nodes, car, car.prevA, car.a)
    if pv then table.insert(segs, 1, pv); k0 = 2 end
  end
  -- (the edges ahead, as far as it gets this frame and an arc's length on)
  local need, have = s + C.CORNER_M, car.len
  local pa, pb = car.a, car.b
  for i = 1, #(car.ahead or {}) do
    if have >= need then break end
    local sg = segOf(nodes, car, pb, car.ahead[i])
    if not sg then break end
    segs[#segs + 1] = sg
    have = have + sg.len
    pa, pb = pb, car.ahead[i]
  end
  -- (which edge it is on: from the start of the current one)
  local k, x = k0, s
  while x > segs[k].len and segs[k + 1] do x = x - segs[k].len; k = k + 1 end
  x = math.min(x, segs[k].len)
  local sg = segs[k]
  local function radius(s1, s2) return math.min(C.CORNER_M, s1.len * 0.45, s2.len * 0.45) end
  local p, d, lat
  local nxt, prv = segs[k + 1], segs[k - 1]
  local rN = nxt and radius(sg, nxt) or 0
  local rP = prv and radius(prv, sg) or 0
  local s1, s2, u = nil, nil, nil
  if nxt and x > sg.len - rN and rN > 0.3 then s1, s2, u = sg, nxt, (x - (sg.len - rN)) / (2 * rN)
  elseif prv and x < rP and rP > 0.3 then s1, s2, u = prv, sg, (x + rP) / (2 * rP) end
  if s1 then
    local r = math.min(C.CORNER_M, s1.len * 0.45, s2.len * 0.45)
    local J = s1.B
    local P0, P2 = J - s1.d * r, J + s2.d * r
    local a1, a2 = 1 - u, u
    p = P0 * (a1 * a1) + J * (2 * a1 * a2) + P2 * (a2 * a2)
    d = flat((J - P0) * a1 + (P2 - J) * a2) or s2.d
    lat = s1.lat + (s2.lat - s1.lat) * u
  else
    p, d, lat = onSeg(sg, x), sg.d, sg.lat
  end
  return p + vec3(d.y, -d.x, 0) * lat, d
end

-- where a virtual car is this frame: on from its last step at its speed, not past the end of its edge
local function nowPos(car, t)
  local s = math.min(car.len, car.s + car.v * math.max(0, math.min(1, t - stepT)))
  local total = car.mine + car.against
  local w = 2 * car.half / math.max(1, total)
  local lat = -car.half + car.against * w + (car.lane - 0.5) * w
  local fd = flat(car.dir) or vec3(1, 0, 0)
  local right = vec3(fd.y, -fd.x, 0)
  return car.pa + car.dir * s + right * lat, fd
end
-- every frame (trafficai.lua): the placeholders where their cars are
function M.render(t, ppos)
  if not M.proxiesOn() or not ppos then
    if next(proxyOf) then for cid in pairs(proxyOf) do M.dropProxy(cid) end end
    return
  end
  local list = shapeList()
  if #list == 0 then return end
  if api.loadMaterials and not M.materialsDone then M.materialsDone = true; api.loadMaterials(C.PROXY_DIRS) end
  local want = {}
  local nodesR = api.nodes and api.nodes()
  for cid, car in pairs(M.cars) do
    if not (car.hideUntil and t < car.hideUntil) then
      local pos, fdR = M.poseOf(car, t, nodesR)
      local d = pos:distance(ppos)
      if d < C.PROXY_FAR_M then want[#want + 1] = { car, d, pos, fdR } end
    end
  end
  table.sort(want, function(x, y) return x[2] < y[2] end)
  local keep = {}
  for i = 1, math.min(#want, C.PROXY_MAX) do keep[want[i][1].id] = want[i] end
  for cid in pairs(proxyOf) do if not keep[cid] then M.dropProxy(cid) end end
  for cid, w in pairs(keep) do
    local car, pos = w[1], w[3]
    local e = proxyOf[cid]
    if not e then
      -- (2026-11-14) drawn from now on: its real car set aside, its model and colour that car's
      if not car.donorId then reserveFor(car, true) end
      local o, shape = takeProxy(car, list)
      if o then
        e = { o = o, shape = shape }; proxyOf[cid] = e
        -- (2026-11-14) its colour: that of the real car set aside for it, else one of its own)
        if api.proxyColor then
          car.color = car.color or string.format('%.2f %.2f %.2f 1', api.rnd(0.05, 0.9), api.rnd(0.05, 0.9), api.rnd(0.05, 0.9))
          pcall(api.proxyColor, o, car.color)
        end
      end
    end
    if e then
      -- (its height: the ground under it, looked again now and then; between the looks the road's slope from the nodes - the pose has it)
      local nz = pos.z
      if not car.gzT or t - car.gzT > C.PROXY_Z_S or car.gzEdge ~= car.a then
        car.gzT, car.gzEdge = t, car.a
        local g = api.snapGround and api.snapGround(vec3(pos.x, pos.y, nz))
        car.gzOff = g and (g.z - nz) or (car.gzOff or 0)
      end
      -- (2026-11-14, Verkehrstest 14-30: the second run began after the world was loaded anew - every placeholder object gone with it, and
      -- each frame's move failed: "Attempted to call a function on an object that no longer exists", not one placeholder for 48 minutes.
      -- A move that fails: all of them are dropped and made again)
      local okMv = pcall(api.proxyMove, e.o, vec3(pos.x, pos.y, nz + (car.gzOff or 0)), w[4] or flat(car.dir) or vec3(1, 0, 0))
      if not okMv then M.lostProxies(); return end
    end
  end
  M.stats.proxiesNow = 0
  for _ in pairs(proxyOf) do M.stats.proxiesNow = M.stats.proxiesNow + 1 end
end

function M.isNew(id, t) local at = M.just[id]; return at ~= nil and (not t or t - at < C.NEW_S) end
function M.count() local n = 0; for _ in pairs(M.cars) do n = n + 1 end return n end
function M.reset()
  for cid in pairs(proxyOf) do M.dropProxy(cid) end
  M.cars, M.just, buckets, nodeList = {}, {}, {}, {}; stepT, nodesT = -1e9, -1e9; spawnMin = C.SPAWN_MIN_M
end

return M
