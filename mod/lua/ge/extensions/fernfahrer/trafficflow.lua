-- Trucks of Earth: the rhythm of the traffic (2026-11-10).
-- Rhythm: how much traffic there is follows the career's clock (rush hours, a quiet night) and comes in slow waves, not at one level.
-- The frame-rate governor in career.lua keeps the last word: this only sets the most it may bring out.
-- Jams: on a motorway (a carriageway of its own, two lanes or more), more often in the rush hours, the road ahead of the player fills up:
-- a radio message, then cars standing and creeping in both lanes, stop-and-go in waves running back up the queue, the hazard lights on at
-- the tail. There are never many cars (the machine has to carry them): the ones the player has passed are taken from behind and put on
-- the front of the queue, out of sight, so that it goes on for as long as the jam is long.
-- trafficai.lua calls M.update and M.capFor; api: roadAt, lanesHere, lengthOf, send, dlog, rnd, forget.

local M = {}
M.C = {
  TICK_S = 2,
  RHYTHM_S = 15,
  CHECK_S = 20,
  MAX_LINE_M = 2800,
  TAIL_M = { 780, 1100 },     -- the jam's end this far ahead of the player when it begins
  LEN_M = { 350, 1000 },
  MIN_LIMIT_KMH = 100,
  BUILD_M = 520,              -- cars are put there when the end of the jam is this close
  SPACING_M = { 9, 13 },
  PLACE_PER_LOOK = 3,
  MIN_FROM_PLAYER_M = 170,
  CONVEY_BEHIND_M = 70,       -- a car this far behind the player in the jam goes to the front
  CONVEY_S = 1.2,
  CONVEY_AHEAD_M = 120,
  APPROACH_M = 320,
  DECEL = 1.6,
  CREEP_MS = 1.0,
  WAVE_MS = 5.5,
  HEAD_FREE_M = 70,
  COOLDOWN_S = { 240, 420 },
  MAX_S = 480,
  LOST_S = 6,
}
local C = M.C

local api
M.member = {}
local jam, nextJamAt, rhythmT, tickT, checkT = nil, nil, 0, 0, 0

function M.init(a) api = a end
function M.active() return jam ~= nil end
function M.jam() return jam end

-- how much traffic at this hour (1: the day's usual)
-- (2026-11-10: the evening fuller - "abends ist mehr los": the rush hour from 16 to 19 the busiest of the day, the evening only thinning out after 20)
local HOURS = { { 0, 0.3 }, { 5, 0.3 }, { 6.5, 0.7 }, { 7.5, 1.15 }, { 9, 0.95 }, { 11, 0.8 }, { 14.5, 0.95 }, { 16, 1.2 }, { 17.5, 1.3 }, { 18.5, 1.2 }, { 19.5, 1.0 }, { 20.5, 0.8 }, { 22, 0.5 }, { 24, 0.3 } }
function M.hourFactor(h)
  h = h % 24
  for i = 1, #HOURS - 1 do
    local a, b = HOURS[i], HOURS[i + 1]
    if h >= a[1] and h <= b[1] then return a[2] + (b[2] - a[2]) * (h - a[1]) / (b[1] - a[1]) end
  end
  return 0.5
end

-- the slow coming and going of traffic, within a few minutes
function M.pulse(t) return 1 + 0.18 * math.sin(t * 2 * math.pi / 240) + 0.1 * math.sin(t * 2 * math.pi / 97) end

function M.rhythmTarget(base, pool, hours, t)
  local n = math.floor(base * M.hourFactor(hours) * M.pulse(t) + 0.5)
  return math.max(3, math.min(pool, n))
end

-- the road ahead, along the way the player is going: points with their distance, half width and lanes
local function lineAhead(p)
  local centre, heading, half0, back, fwd, nodes = api.roadAt(p.pos, p.dir)
  if not centre or not heading then return nil end
  local pts = { { x = centre.x, y = centre.y, z = centre.z, s = 0, half = half0 or 3.5, n = 1 } }
  local prev, cur, s = back, fwd, 0
  local hx, hy = heading.x, heading.y
  for _ = 1, 500 do
    local q = nodes[cur]
    if not q then break end
    local last = pts[#pts]
    local dx, dy = q.pos.x - last.x, q.pos.y - last.y
    s = s + math.sqrt(dx * dx + dy * dy)
    local link = (nodes[prev] and nodes[prev].links and nodes[prev].links[cur]) or (q.links and q.links[prev])
    if type(link) == 'table' then
      last.half = link.inRadius or last.half
      local _, plus = (link.lanes or '+'):gsub('%+', '')
      last.n = math.max(1, plus)
      last.oneWay = link.oneWay
    end
    pts[#pts + 1] = { x = q.pos.x, y = q.pos.y, z = q.pos.z, s = s, half = last.half, n = last.n, oneWay = last.oneWay }
    if s > C.MAX_LINE_M then break end
    local best, bestDot = nil, 0.7
    for m, l in pairs(q.links or {}) do
      if m ~= prev and nodes[m] and not (type(l) == 'table' and l.oneWay and l.inNode ~= cur) then
        local ex, ey = nodes[m].pos.x - q.pos.x, nodes[m].pos.y - q.pos.y
        local len = math.sqrt(ex * ex + ey * ey) + 1e-9
        local dot = (ex * hx + ey * hy) / len
        if dot > bestDot then best, bestDot, hx, hy = m, dot, ex / len, ey / len end
      end
    end
    if not best then break end
    prev, cur = cur, best
  end
  return pts
end

-- the point at distance s on the line, with direction and lanes
local function pointAt(j, s)
  local pts = j.pts
  for i = 1, #pts - 1 do
    local a, b = pts[i], pts[i + 1]
    if s <= b.s then
      local t = (s - a.s) / math.max(0.01, b.s - a.s)
      local dx, dy = b.x - a.x, b.y - a.y
      local l = math.sqrt(dx * dx + dy * dy) + 1e-9
      return a.x + dx * t, a.y + dy * t, a.z + (b.z - a.z) * t, dx / l, dy / l, a.half, a.n
    end
  end
  return nil
end

-- where on the line is this position? s, and how far beside it; nil: not on it
local function onLine(j, pos, dir)
  local pts, best, bestD, bestS, bestLat = j.pts, nil, 1e18, nil, nil
  for i = 1, #pts - 1 do
    local a, b = pts[i], pts[i + 1]
    local dx, dy = b.x - a.x, b.y - a.y
    local l2 = dx * dx + dy * dy + 1e-9
    local t = math.max(0, math.min(1, ((pos.x - a.x) * dx + (pos.y - a.y) * dy) / l2))
    local ex, ey = pos.x - (a.x + dx * t), pos.y - (a.y + dy * t)
    local d = ex * ex + ey * ey
    if d < bestD then
      bestD, best, bestS = d, i, a.s + t * (b.s - a.s)
      bestLat = math.sqrt(d)
    end
  end
  if not best then return nil end
  local a, b = pts[best], pts[best + 1]
  local dx, dy = b.x - a.x, b.y - a.y
  local l = math.sqrt(dx * dx + dy * dy) + 1e-9
  if dir and (dir.x * dx + dir.y * dy) / l < 0.7 then return nil end
  if bestLat > (a.half or 3.5) + 3 then return nil end
  return bestS, bestLat
end

local function wave(s, t) return C.CREEP_MS + C.WAVE_MS * math.max(0, math.sin(s * 0.018 + t * 0.7)) end

-- the speed for this car because of the jam, nil: none. Marks who is in it
function M.capFor(id, c, t)
  if not jam or not c.dir then return nil end
  local s = onLine(jam, c.pos, c.dir)
  if not s or s > jam.head then M.member[id] = jam.placed[id] and M.member[id] or nil; return nil end
  if s < jam.tail then
    local d = jam.tail - s
    if d > C.APPROACH_M then return nil end
    return math.sqrt(C.CREEP_MS * C.CREEP_MS + 2 * C.DECEL * d)
  end
  M.member[id] = true
  local toHead = jam.head - s
  if toHead < C.HEAD_FREE_M then return wave(s, t) + (C.HEAD_FREE_M - toHead) * 0.4 end
  return wave(s, t)
end

local function finish(ctx, why, t)
  if not jam then return end
  for id in pairs(jam.hazard) do api.send(id, 'electrics.set_warn_signal(false)') end
  M.member = {}
  api.dlog('jam over (%s): %d cars used, %d moved along', why, jam.count, jam.moved)
  if why == 'passed' and ctx.notify then ctx.notify('Verkehrsfunk: Stau zu Ende. Gute Fahrt!', 5) end
  jam = nil
  nextJamAt = t + api.rnd(C.COOLDOWN_S[1], C.COOLDOWN_S[2])
end

local function clearAt(all, x, y, r)
  for _, o in pairs(all) do
    local dx, dy = o.pos.x - x, o.pos.y - y
    if dx * dx + dy * dy < r * r then return false end
  end
  return true
end

-- a car into the jam at distance s, the given lane (0: the right-hand one). True when it went
local function place(id, s, lane, all)
  local x, y, z, tx, ty, half, n = pointAt(jam, s)
  if not x then return false end
  local w = 2 * half / math.max(1, n)
  local offset = half - w * (math.min(lane, n - 1) + 0.5)
  local px, py = x + ty * offset, y - tx * offset
  if not clearAt(all, px, py, 3) then return false end         -- (the next lane is 3.5 m away: it may be taken)
  local gt = rawget(_G, 'gameplay_traffic')
  if not gt or not gt.respawnVehicle then return false end
  M.member[id] = true
  jam.placed[id] = true
  local dir = vec3(tx, ty, 0)
  if not pcall(gt.respawnVehicle, id, vec3(px, py, z + 0.4), quatFromDir(dir, vec3(0, 0, 1))) then
    M.member[id], jam.placed[id] = nil, nil
    return false
  end
  api.forget(id)
  return true
end

local function lanesAt(s) local _, _, _, _, _, _, n = pointAt(jam, s); return n or 2 end

-- a car of the traffic that nobody sees and that is not in the jam
local function donor(list, all, p, pid)
  local best, far = nil, -1
  for _, id in pairs(list) do
    if id ~= pid and not M.member[id] then
      local o = all[id]
      if o then
        local rel = o.pos - p.pos
        local d, along = rel:length(), rel:dot(p.dir)
        if (d > C.MIN_FROM_PLAYER_M or along < -40) and d > far and not api.busy(id) then best, far = id, d end
      else
        return id                              -- (out of the scan altogether)
      end
    end
  end
  return best
end

local function startJam(p, t, ctx)
  local pts = lineAhead(p)
  if not pts then return false end
  local tail = api.rnd(C.TAIL_M[1], C.TAIL_M[2])
  local head = tail + api.rnd(C.LEN_M[1], C.LEN_M[2])
  local length = pts[#pts].s
  if length < tail + 300 then return false end
  head = math.min(head, length - 20)
  jam = { pts = pts, tail = tail, head = head, born = t, built = false, nextS = tail + 8, lane = 0, placed = {}, hazard = {}, count = 0, moved = 0, convT = 0, lostT = 0 }
  M.member = {}
  api.dlog('jam: end in %.0f m, %.0f m long', tail, head - tail)
  if ctx.notify then
    local function km(m) return (string.format('%.1f', m / 1000):gsub('%.', ',')) end
    ctx.notify('Verkehrsfunk: Stau voraus in etwa ' .. km(tail) .. ' km, rund ' .. km(head - tail) .. ' km lang.', 8)
  end
  return true
end
M.startJam = startJam

local function jamTick(t, p, pid, all, list, ctx)
  local ps = onLine(jam, p.pos, p.dir)
  if not ps then
    jam.lostT = jam.lostT + C.TICK_S
    if jam.lostT >= C.LOST_S then return finish(ctx, 'left the road', t) end
    return
  end
  jam.lostT = 0
  if ps > jam.head + 150 then return finish(ctx, 'passed', t) end
  if t - jam.born > C.MAX_S then return finish(ctx, 'too long', t) end
  local distance = jam.tail - ps
  if distance < C.BUILD_M then
    if not jam.built then
      jam.built = true
      if ctx.setTrafficTarget then ctx.setTrafficTarget(ctx.trafficPool and ctx.trafficPool() or 99) end
    end
    -- the cars into their places, from the end of the queue forwards
    for _ = 1, C.PLACE_PER_LOOK do
      if jam.nextS >= jam.head or jam.nextS <= ps + C.MIN_FROM_PLAYER_M then
        if jam.nextS <= ps + C.MIN_FROM_PLAYER_M then jam.nextS = ps + C.MIN_FROM_PLAYER_M + 10 else break end
      end
      local id = donor(list, all, p, pid)
      if not id then break end
      if place(id, jam.nextS, jam.lane, all) then
        jam.count = jam.count + 1
        if jam.nextS < jam.tail + 30 and not jam.hazard[id] then
          jam.hazard[id] = true
          api.send(id, 'electrics.set_warn_signal(true)')
        end
      end
      jam.lane = (jam.lane + 1) % math.max(1, lanesAt(jam.nextS))
      if jam.lane == 0 then jam.nextS = jam.nextS + api.rnd(C.SPACING_M[1], C.SPACING_M[2]) end
    end
  end
  -- the player is in it: the cars it has passed go to the front
  if ps > jam.tail and t - jam.convT >= C.CONVEY_S then
    local front = ps + C.CONVEY_AHEAD_M
    for id in pairs(M.member) do
      local o = all[id]
      if o and o.dir then
        local s = onLine(jam, o.pos, o.dir)
        if s and s > front then front = s end
      end
    end
    for id in pairs(M.member) do
      local o = all[id]
      local s = o and o.dir and onLine(jam, o.pos, o.dir)
      if s and s < ps - C.CONVEY_BEHIND_M then
        local at = front + api.rnd(C.SPACING_M[1], C.SPACING_M[2])
        if at < jam.head then
          jam.convT = t
          if jam.hazard[id] then api.send(id, 'electrics.set_warn_signal(false)'); jam.hazard[id] = nil end
          if place(id, at, jam.lane, all) then jam.moved = jam.moved + 1 end
          jam.lane = (jam.lane + 1) % math.max(1, lanesAt(at))
        end
        break
      end
    end
  end
end

-- every look of trafficai.lua. p: the player's snapshot; list: the traffic's ids
function M.update(t, p, pid, all, list, ctx)
  if t - tickT < C.TICK_S then return end
  tickT = t
  if not ctx.hours then return end
  local hours = ctx.hours()
  if t - rhythmT >= C.RHYTHM_S and not jam and ctx.setTrafficTarget and ctx.trafficBase then
    rhythmT = t
    ctx.setTrafficTarget(M.rhythmTarget(ctx.trafficBase(), ctx.trafficPool and ctx.trafficPool() or 99, hours, t))
  end
  if not p or not p.dir then return end
  if jam then return jamTick(t, p, pid, all, list, ctx) end
  if not nextJamAt then nextJamAt = t + api.rnd(60, 150) end
  if t < nextJamAt or t - checkT < C.CHECK_S then return end
  checkT = t
  local f = M.hourFactor(hours)
  if f < 0.6 or p.speed < 15 then return end
  local limit = ctx.roadLimit and ctx.roadLimit() or 0
  if not limit or limit < C.MIN_LIMIT_KMH then return end
  local li = api.lanesHere(p.pos, p.dir)
  if not li or not api.oneWay(p.pos, p.dir) then return end
  local chance = 0.03 + 0.5 * math.max(0, f - 0.7)
  if math.random() < chance then startJam(p, t, ctx) end
end

function M.reset(ctx)
  if jam then for id in pairs(jam.hazard) do api.send(id, 'electrics.set_warn_signal(false)') end end
  jam, nextJamAt = nil, nil
  M.member = {}
end

return M
