-- Trucks of Earth: our own driver for a traffic car (Beta, 2026-11-10). Switched on in the settings; off by default.
--
-- trafficai.lua (the traffic's "control room", in the game engine) decides what the cars are to do. BeamNG's AI does the
-- steering and the pedals. This driver takes those over as well, wherever the road is plain: it follows a line of its own from the
-- road graph, in its lane, plans the speed for the bends ahead, and keeps its distance to whatever really is on that line (not on
-- the straight line ahead of the car, which in a bend runs through the next lane and the oncoming cars).
--
-- It goes straight through junctions where its road is the main road. Where a decision is needed (the road ends in a junction, a
-- side road, traffic lights, stop signs, the road is lost, it is stuck, it is damaged), it hands the car back to BeamNG's AI, which
-- is still the one in charge of those; the control room tries to take it over again afterwards.
--
-- How it takes over: the game calls ai.updateGFX every frame just before the inputs, and BeamNG's own AI swaps that function when it
-- changes mode; this does the same. The AI stays in "traffic" mode, so the traffic system sees no difference. Should anybody set
-- the AI's mode meanwhile, its function is back in place and this one notices and steps aside.
--
-- All written for this mod. acquire(cap) / release(why) / setCap(ms; 0: the road's limit) / shift(metres to the right, over metres) /
-- setPassing(bool). Reports to fernfahrer_career.onOwnDriver(id, on, why).

local M = {}

local C = {
  STEP = 4,                -- m between the points of the line
  SMOOTH = 2,              -- points each side averaged: the kinks of the road graph must not reach the steering
  CURV_SPAN = 3,           -- points each side for the curvature
  AHEAD_M = 220,           -- line ready this far ahead (at least)
  AHEAD_S = 11,            -- ... and this many seconds
  LOOK_MIN = 6, LOOK_BASE = 4, LOOK_S = 0.40, LOOK_MAX = 36,  -- the steering looks this far ahead
  LOCK = 0.56,             -- rad: a usual wheel angle at full lock (the yaw feedback takes care of the difference)
  YAW_GAIN = 0.35,         -- (how much of the difference between the turn wanted and the real one goes straight to the wheel)
  LAT_P = 0.09, LAT_I = 0.05, LAT_I_MAX = 0.08,     -- off its line: steered back, slowly more if it stays off
  STEER_RATE = 1.7,        -- input per second
  LAT_CAR = 2.8, LAT_LORRY = 1.8,     -- m/s2 in a bend
  DECEL = 2.0,             -- m/s2 planned for bends and limits
  IDM_A = 1.3, IDM_B = 2.4, IDM_T = 1.5, IDM_S0 = 3.5,
  HANDOVER_S = 4, HANDOVER_M = 70,    -- back to the stock AI this far before a junction that needs a decision
  REFUSE_JUNCTION_M = 130,
  THROUGH_DOT = 0.75,      -- the way on at a junction: at most ~41 degrees off
  LOST_M = 3.5,            -- this far off its line: lost
  LOST_DOT = 0.5,
  BLOCKED_S = 20,          -- behind something standing this long: BeamNG's AI knows how to get round it
  STUCK_S = 6,
  DAMAGE = 3000,
  SHIFT_MIN_M = 25,
  EXTRA_DECAY = 0.16,      -- per second: a sideways correction fades (not while overtaking)
}

local active, stock = false, nil
local mapRef, graph, positions
local rx, ry, rz, rLim, rHalf, rMine, rW = {}, {}, {}, {}, {}, {}, {}   -- the raw line
local px, py, pz, nx, ny, kap, lim, half, mine, wid = {}, {}, {}, {}, {}, {}, {}, {}, {}, {}   -- smoothed, with normals (right)
local kapS = {}             -- curvature with its side (+: a left-hand bend)
local rawN, n, idx, frac = 0, 0, 1, 0
local vmax = {}
local prevNode, curNode, flaggedAt, ended
local laneK, extra, blendErr, blendRate, passing = 0, 0, 0, 0, false
local cap = 0
local myLen, myWid, wb, latA, isLorry = 4.6, 1.9, 2.7, C.LAT_CAR, false
local steer, intg, lastAcc, lastV, lastDx, lastDy = 0, 0, 0, 0, nil, nil
local leadGap, leadV, profT, lookT = nil, 0, 0, 0
local stuckT, blockedT = 0, 0
local latI = 0
local refuseUntil = 0
local juncs, blink = {}, 0
local goneTo = {}

local function notify(on, why)
  obj:queueGameEngineLua(string.format('if fernfahrer_career and fernfahrer_career.onOwnDriver then fernfahrer_career.onOwnDriver(%d, %s, %q) end', obj:getId(), tostring(on), why or ''))
end

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

local function dropAll()
  rx, ry, rz, rLim, rHalf, rMine, rW = {}, {}, {}, {}, {}, {}, {}
  px, py, pz, nx, ny, kap, lim, half, mine, wid, vmax = {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
  kapS = {}
  rawN, n, idx, frac = 0, 0, 1, 0
  juncs = {}
end

-- the lanes of edge a -> b going that way
local function lanesOf(a, b)
  local e = graph[a][b]
  local s = e.lanes
  if type(s) ~= 'string' or #s == 0 then
    if e.oneWay then return 1, 1 end
    return 1, 2
  end
  local _, plus = s:gsub('%+', '')
  local _, minus = s:gsub('%-', '')
  -- (a road for both ways with lanes only one way on the map: its right half is this direction's)
  if not e.oneWay and (plus == 0 or minus == 0) then return 1, 2 end
  local m = (e.oneWay or e.inNode == a) and plus or minus
  return math.max(1, m), math.max(1, plus + minus)
end

local function degree(node) local d = 0; for _ in pairs(graph[node]) do d = d + 1 end return d end

local release

local function bearing(a, b) return math.atan2(b.y - a.y, b.x - a.x) end

-- the way on from cur, coming from prev, and what it takes there (a table: rank 3: the main road straight on, 2: along it round a bend or
-- right off it, 1: left off it, or two equal roads, 0: out of a side road; signal: the light or stop sign). nil: this is for BeamNG's AI
local function nextNode(prev, cur)
  local sd = mapmgr.signalsData
  local signal = sd and sd[prev] and sd[prev][cur] and sd[prev][cur][1] or nil
  local pc, pp = positions[cur], positions[prev]
  local dx, dy = pc.x - pp.x, pc.y - pp.y
  local l = math.sqrt(dx * dx + dy * dy) + 1e-9
  dx, dy = dx / l, dy / l
  local inDrv = graph[prev][cur].drivability
  local list, top, tops = {}, inDrv, {}
  for k, e in pairs(graph[cur]) do
    top = math.max(top, e.drivability)
    tops[#tops + 1] = { k = k, d = e.drivability }
    if k ~= prev and not (e.oneWay and e.inNode ~= cur) and e.drivability > 0.05 then
      local q = positions[k]
      local ex, ey = q.x - pc.x, q.y - pc.y
      local m = math.sqrt(ex * ex + ey * ey) + 1e-9
      list[#list + 1] = { k = k, dot = (ex * dx + ey * dy) / m, cross = (dx * ey - dy * ex) / m, d = e.drivability }
    end
  end
  if #list == 0 then return nil end
  local legs = degree(cur)
  local function info(rank, pick, eq)
    local mainA, mainB
    if legs > 2 and not eq then
      table.sort(tops, function(a, b) return a.d > b.d end)
      if tops[1].d > (tops[3] and tops[3].d or 0) + 1e-3 then
        mainA, mainB = bearing(pc, positions[tops[1].k]), bearing(pc, positions[tops[2].k])
      end
    end
    return { node = cur, x = pc.x, y = pc.y, rank = rank, eq = eq or false, signal = signal, inB = bearing(pc, pp), outB = bearing(pc, positions[pick.k]),
      mainA = mainA, mainB = mainB, turn = pick.dot >= C.THROUGH_DOT and 0 or (pick.cross > 0 and -1 or 1), radius = (mapRef.radius and mapRef.radius[cur]) or 5, wait = 0, askT = 0 }
  end
  if legs <= 2 then
    return list[1].k, signal and info(3, list[1]) or nil
  end
  if legs >= 6 then return nil end                     -- (a big junction drawn as one node: BeamNG's AI)
  local best = list[1]
  for _, c in ipairs(list) do if c.dot > best.dot then best = c end end
  local others = 0
  for _, t2 in ipairs(tops) do if t2.k ~= prev and t2.k ~= best.k then others = math.max(others, t2.d) end end
  local pick, inf
  if best.dot >= C.THROUGH_DOT and best.d >= others then
    pick = best
    local onMain = inDrv > others + 1e-3 or best.d > others + 1e-3
    if onMain then
      if signal then inf = info(3, pick) end
    else
      inf = info(1, pick, true)
    end
  else
    -- no road straight on: where to? (lorries round corners are left to BeamNG's AI for now)
    if isLorry then return nil end
    local sum = 0
    for _, c in ipairs(list) do c.w = c.dot > -0.75 and c.d * c.d * (1 + c.dot) ^ 2 + 1e-3 or 0; sum = sum + c.w end
    if sum <= 0 then return nil end
    local x = math.random() * sum
    for _, c in ipairs(list) do x = x - c.w; if x <= 0 then pick = c; break end end
    pick = pick or list[1]
    local isMain = inDrv >= top - 1e-3
    local rank
    if isMain and pick.d >= top - 1e-3 then rank = 2
    elseif isMain then rank = pick.cross > 0 and 1 or 2
    elseif inDrv >= top * 0.98 then rank = 1
    else rank = 0 end
    inf = info(rank, pick, rank == 1 and inDrv >= top * 0.98 and pick.d >= top * 0.98 and not isMain)
  end
  -- (two junctions right behind each other, a dual carriageway crossing: BeamNG's AI)
  local np = positions[pick.k]
  if inf and degree(pick.k) > 2 and (np.x - pc.x) ^ 2 + (np.y - pc.y) ^ 2 < 324 then return nil end
  return pick.k, inf
end

local function pushRaw(x, y, z, l, h, m, w)
  rawN = rawN + 1
  rx[rawN], ry[rawN], rz[rawN], rLim[rawN], rHalf[rawN], rMine[rawN], rW[rawN] = x, y, z, l, h, m, w
end

-- edge a -> b onto the raw line
local function addEdge(a, b)
  local p, q = mapRef:getEdgePositions(a, b)
  local r1, r2 = mapRef:getEdgeRadii(a, b)
  local e = graph[a][b]
  local m, total = lanesOf(a, b)
  local lm = e.speedLimit or 14
  local dx, dy, dz = q.x - p.x, q.y - p.y, q.z - p.z
  local len = math.sqrt(dx * dx + dy * dy + dz * dz)
  local steps = math.max(1, math.floor(len / C.STEP + 0.5))
  local first = rawN == 0 and 0 or 1
  for i = first, steps do
    local t = i / steps
    local h = r1 + (r2 - r1) * t
    pushRaw(p.x + dx * t, p.y + dy * t, p.z + dz * t, lm, h, m, 2 * h / total)
  end
end

-- the smoothed points that can be made from what is on the raw line by now
local function refine()
  local S, K = C.SMOOTH, C.CURV_SPAN
  local before = n
  while n < rawN - S do
    local i = n + 1
    local a, b = math.max(1, i - S), math.min(rawN, i + S)
    -- (a symmetric window, so that the start of the line stays where it is)
    local w = math.min(i - a, b - i)
    local x, y, z, c = 0, 0, 0, 0
    for j = i - w, i + w do x, y, z, c = x + rx[j], y + ry[j], z + rz[j], c + 1 end
    n = i
    px[n], py[n], pz[n] = x / c, y / c, z / c
    lim[n], half[n], mine[n], wid[n] = rLim[i], rHalf[i], rMine[i], rW[i]
    kap[n], vmax[n] = 0, lim[n]
  end
  -- normals and curvature, for every point with both neighbours there
  -- (2026-11-10: from where it had got to. Only the last few before: a long edge brought many points at once, those between had no
  -- normals and the car's Lua died on them, its last gas and steering still on: cars driving off across the fields)
  for i = math.max(2, before - 1), n - 1 do
    local dx, dy = px[i + 1] - px[i - 1], py[i + 1] - py[i - 1]
    local l = math.sqrt(dx * dx + dy * dy) + 1e-9
    nx[i], ny[i] = dy / l, -dx / l       -- (right of the direction of travel)
  end
  if n >= 2 then nx[1], ny[1] = nx[2], ny[2] end
  for i = math.max(K + 1, before - K), n - K do
    local ax, ay = px[i] - px[i - K], py[i] - py[i - K]
    local bx, by = px[i + K] - px[i], py[i + K] - py[i]
    local cross = ax * by - ay * bx
    local la = math.sqrt(ax * ax + ay * ay) + 1e-9
    local lb = math.sqrt(bx * bx + by * by) + 1e-9
    kap[i] = math.abs(math.asin(clamp(cross / (la * lb), -1, 1))) / (0.5 * (la + lb))
    kapS[i] = cross >= 0 and kap[i] or -kap[i]
  end
end

local function extend(speed)
  local want = math.max(C.AHEAD_M, speed * C.AHEAD_S) / C.STEP
  while not ended and n - idx < want do
    local nx2, inf = nextNode(prevNode, curNode)
    if not nx2 then
      ended = true
      flaggedAt = rawN
      return
    end
    if inf then
      inf.rawIdx = rawN
      local stop = rawN - math.ceil((inf.radius + 3 + myLen * 0.5) / C.STEP)
      if inf.signal and inf.signal.pos then
        local bestD, sp = 1e18, inf.signal.pos
        for i = rawN, math.max(1, rawN - 40), -1 do
          local q = (rx[i] - sp.x) ^ 2 + (ry[i] - sp.y) ^ 2
          if q < bestD then bestD, stop = q, i end
        end
        stop = stop - math.ceil((myLen * 0.5 + 3) / C.STEP)
      end
      inf.stopIdx = math.max(1, stop)
      juncs[#juncs + 1] = inf
    end
    addEdge(curNode, nx2)
    prevNode, curNode = curNode, nx2
    refine()
  end
end

-- how far right of the road's centre the car's lane is at point i
local function laneOffset(i)
  local k = math.min(laneK, mine[i] - 1)
  return half[i] - wid[i] * (k + 0.5)
end

local function offsetAt(i, dist)
  local o = laneOffset(i) + extra
  -- (2026-11-10: a lorry's rear wheels run inside its front ones in a bend: in a right-hand bend over the edge. The line out by half of that there; in a left-hand bend the inside is the middle of the road)
  if isLorry and kapS[i] then o = o + clamp(kapS[i] * wb * wb * 0.5, -0.6, 0) end
  local left = math.max(0, math.abs(blendErr) - dist * blendRate)
  o = o + (blendErr >= 0 and left or -left)
  -- (never with its side nearer the road's edge than this: the width given in the graph is a little more than the asphalt)
  -- (2026-11-10: Earth's half width is that of the driving lanes, not of the asphalt (server navgraph.py driving_width): no margin
  -- on top. 0.65 m of it pushed the cars to the middle of every narrower road)
  -- (2026-11-10: a lorry's 0.45 m everywhere pushed it towards the line on any narrower road. On the straight 0.2 m; more only in a bend, where the rear wheels cut in)
  local room = half[i] - myWid * 0.5 - (isLorry and (0.2 + clamp(math.abs(kapS[i] or 0) * wb * wb * 0.5, 0, 0.3)) or 0.15)
  return clamp(o, -room, room)
end

local function trim()
  if idx < 300 then return end
  local cut = idx - 40
  local function shiftArr(a, count) for i = 1, count - cut do a[i] = a[i + cut] end for i = count - cut + 1, count do a[i] = nil end end
  for _, a in ipairs({ px, py, pz, nx, ny, kap, kapS, lim, half, mine, wid, vmax }) do shiftArr(a, n) end
  for _, a in ipairs({ rx, ry, rz, rLim, rHalf, rMine, rW }) do shiftArr(a, rawN) end
  n, rawN, idx = n - cut, rawN - cut, idx - cut
  if flaggedAt then flaggedAt = flaggedAt - cut end
  for _, j in ipairs(juncs) do j.rawIdx, j.stopIdx = j.rawIdx - cut, j.stopIdx - cut end
end

-- does this junction need the control room?
local function needsGo(j) return j.rank < 3 or (j.signal and j.turn < 0) end

-- must the car stop at this junction's line, as things are?
local function holdFor(j, v)
  local sig = j.signal and j.signal.action or 0
  if sig == 2 then return true end
  if sig == 1 then
    if j.pastAmber == nil then j.pastAmber = (j.stopIdx - idx) * C.STEP < v * v / 6 end
    if not j.pastAmber then return true end
  else
    j.pastAmber = nil
  end
  if sig == 3 and not j.stopped then return true end
  return needsGo(j) and not j.go
end

local function plan(v)
  -- limits and bends, then backwards so that it slows down in time
  local last = n - C.CURV_SPAN
  if last <= idx then return end
  local myCap = cap > 0 and cap or 1e9
  for i = idx, last do
    local b = kap[i] > 1e-4 and math.sqrt(latA / kap[i]) or 1e9
    vmax[i] = math.min(b, lim[i] * (cap > 0 and 1.2 or 1), myCap)
  end
  if ended then vmax[last] = math.min(vmax[last], 6) end
  for _, j in ipairs(juncs) do
    if j.stopIdx >= idx - 1 and j.stopIdx <= last and holdFor(j, v) then
      for i = j.stopIdx, last do vmax[i] = 0 end
      break
    end
  end
  for i = last - 1, idx, -1 do
    local d = C.STEP
    vmax[i] = math.min(vmax[i], math.sqrt(vmax[i + 1] * vmax[i + 1] + 2 * C.DECEL * d))
  end
end

-- the nearest vehicle really on the car's line
local function lookAhead(v, x, y)
  leadGap, leadV = nil, 0
  local horizon = math.min(n - 2, idx + math.floor(math.max(45, v * 6 + 25) / C.STEP))
  local objs = mapmgr.getObjects()
  local me = obj:getId()
  for id, o in pairs(objs) do
    if id ~= me and o.pos then
      local dx, dy = o.pos.x - x, o.pos.y - y
      if dx * dx + dy * dy < 40000 then
        local oL = obj:getObjectInitialLength(id)
        local oW = obj:getObjectInitialWidth(id)
        local i = idx
        while i <= horizon do
          local off = offsetAt(i, (i - idx) * C.STEP)
          local cx, cy = px[i] + nx[i] * off, py[i] + ny[i] * off
          local rx2, ry2 = o.pos.x - cx, o.pos.y - cy
          local lat = rx2 * nx[i] + ry2 * ny[i]
          -- (one coming the other way is passed close: real room is enough, no margin to stop for)
          local against = o.vel.x * -ny[i] + o.vel.y * nx[i] < -1
          local reach = (myWid + oW) * 0.5 + (against and 0.05 or 0.3)
          local alo = rx2 * ny[i] * -1 + ry2 * nx[i]    -- (along the line)
          if math.abs(alo) < C.STEP * 0.75 + oL * 0.5 and math.abs(lat) < reach then
            local gap = (i - idx) * C.STEP + alo - frac * C.STEP - (myLen + oL) * 0.5
            if gap > -myLen and (not leadGap or gap < leadGap) then
              leadGap = gap
              leadV = o.vel.x * -ny[i] + o.vel.y * nx[i]
            end
            break
          end
          i = i + 2
        end
      end
    end
  end
end

local function setBlink(want)
  if want == blink then return end
  blink = want
  if want < 0 then electrics.set_left_signal(true) elseif want > 0 then electrics.set_right_signal(true) else electrics.set_left_signal(false); electrics.set_right_signal(false) end
end

local function num(v) return v and string.format('%.4f', v) or 'nil' end

-- passing, asking, stopping at signs. True: the car has been given back
local function junctionStep(dt, av)
  for i = #juncs, 1, -1 do
    local j = juncs[i]
    if idx > j.rawIdx + math.ceil(14 / C.STEP) then
      if j.asked then obj:queueGameEngineLua(string.format('if fernfahrer_career and fernfahrer_career.onJunctionDone then fernfahrer_career.onJunctionDone(%d, %q) end', obj:getId(), j.node)) end
      setBlink(0)
      table.remove(juncs, i)
    end
  end
  local j = juncs[1]
  if not j then return false end
  local dist = (j.stopIdx - idx) * C.STEP
  if j.turn ~= 0 and dist <= math.max(45, av * 4) then setBlink(j.turn) end
  local sig = j.signal and j.signal.action or 0
  if sig == 3 and not j.stopped and av < 0.4 and dist <= C.STEP * 2 then
    j.stopT = (j.stopT or 0) + dt
    if j.stopT >= 1 then j.stopped, profT = true, 0 end
  end
  if needsGo(j) and not j.go and sig ~= 2 and (sig ~= 3 or j.stopped) and dist <= math.max(60, av * 6 + 15) then
    j.askT = j.askT - dt
    if j.askT <= 0 then
      j.askT, j.asked = 0.25, true
      obj:queueGameEngineLua(string.format('if fernfahrer_career and fernfahrer_career.onJunctionAsk then fernfahrer_career.onJunctionAsk(%d, %q, %.2f, %.2f, %.4f, %.4f, %d, %s, %s, %s, %.2f) end',
        obj:getId(), j.node, j.x, j.y, j.inB, j.outB, j.rank, tostring(j.eq), num(j.mainA), num(j.mainB), av > 1 and math.max(0, dist) / av or 0))
    end
  end
  if av < 0.5 and sig ~= 2 and holdFor(j, av) then
    j.wait = j.wait + dt
    if j.wait > 45 then release('junction wait'); return true end
  end
  return false
end

local function setInputs(s, t, b, p)
  input.event('steering', s, 'FILTER_AI', nil, nil, nil, 'ai')
  input.event('throttle', t, 'FILTER_AI', nil, nil, nil, 'ai')
  input.event('brake', b, 'FILTER_AI', nil, nil, nil, 'ai')
  input.event('parkingbrake', p, 'FILTER_AI', nil, nil, nil, 'ai')
end

local buildLine

local function step(dt)
  if dt <= 0 then return end
  -- (2026-11-10: Earth sends a new road map every few hundred metres: the line is drawn again, the car stays with us)
  if mapmgr.mapData ~= mapRef then
    if passing or not mapmgr.mapData or not mapmgr.mapData.graph then return release('map') end
    local why = buildLine()
    if why then return release(why == 'junction' and 'junction' or 'map') end
    return
  end
  local pos, vel, dir = obj:getPosition(), obj:getVelocity(), obj:getDirectionVector()
  local v = vel.x * dir.x + vel.y * dir.y
  local av = math.abs(v)
  -- where on the line it is
  local best, bestD = idx, 1e18
  for i = idx, math.min(n - 1, idx + 14) do
    local dx, dy = pos.x - px[i], pos.y - py[i]
    local d = dx * dx + dy * dy
    if d < bestD then best, bestD = i, d end
  end
  idx = best
  if idx >= n - 2 then return release('end of line') end
  local tx, ty = px[idx + 1] - px[idx], py[idx + 1] - py[idx]
  local tl = tx * tx + ty * ty + 1e-9
  frac = clamp(((pos.x - px[idx]) * tx + (pos.y - py[idx]) * ty) / tl, 0, 1)
  local lat = (pos.x - px[idx]) * nx[idx] + (pos.y - py[idx]) * ny[idx]
  local target = offsetAt(idx, frac * C.STEP)
  local tSq = math.sqrt(tl)
  local alignDot = (dir.x * tx + dir.y * ty) / tSq
  if math.abs(lat - target) > C.LOST_M or alignDot < C.LOST_DOT then return release('lost') end
  if beamstate and (beamstate.damage or 0) > C.DAMAGE then refuseUntil = os.clock() + 1e6; return release('damage') end

  -- the blend into the lane (taking over, a lane change) and sideways corrections fading
  if blendErr ~= 0 then
    local d = blendRate * av * dt
    if math.abs(blendErr) <= d then blendErr = 0 else blendErr = blendErr - (blendErr > 0 and d or -d) end
  end
  if not passing and extra ~= 0 then extra = extra * math.max(0, 1 - C.EXTRA_DECAY * dt) end

  extend(av)
  trim()
  if junctionStep(dt, av) then return end

  if ended and flaggedAt then
    local distance = (flaggedAt - idx) * C.STEP
    if distance <= math.max(C.HANDOVER_M, av * C.HANDOVER_S) then return release('junction') end
  end

  profT = profT - dt
  if profT <= 0 then profT = 0.2; plan(av) end
  lookT = lookT - dt
  if lookT <= 0 then lookT = 0.1; lookAhead(av, pos.x, pos.y) end

  -- steering: the point on the line a little ahead, the arc that leads there
  local L = clamp(C.LOOK_BASE + av * C.LOOK_S, C.LOOK_MIN, C.LOOK_MAX)
  if isLorry then L = L * 1.2 end
  local j = math.min(n - 1, idx + math.ceil(L / C.STEP))
  local off = offsetAt(j, (j - idx) * C.STEP)
  local gx, gy = px[j] + nx[j] * off - pos.x, py[j] + ny[j] * off - pos.y
  local right = { x = dir.y, y = -dir.x }
  local fw = gx * dir.x + gy * dir.y
  local si = gx * right.x + gy * right.y
  local curv = 2 * si / (fw * fw + si * si + 1e-3)
  local wheel = math.atan(wb * curv)
  -- what the car really turns at against what it should (the true steering lock, understeer)
  local yaw = 0
  if lastDx then yaw = math.asin(clamp(lastDx * dir.y - lastDy * dir.x, -1, 1)) / dt * -1 end
  lastDx, lastDy = dir.x, dir.y
  local err = lat - target
  latI = clamp(latI + err * C.LAT_I * dt, -C.LAT_I_MAX, C.LAT_I_MAX)
  local want = wheel / C.LOCK + clamp((curv * av - yaw) * C.YAW_GAIN, -0.25, 0.25) - clamp(err * C.LAT_P / (1 + av * 0.05) + latI, -0.25, 0.25)
  local maxS = C.STEER_RATE * dt
  steer = steer + clamp(clamp(want, -1, 1) - steer, -maxS, maxS)

  -- speed
  local idxAhead = math.min(n - 1, idx + math.ceil(av * 0.4 / C.STEP))
  local vt = math.min(vmax[idxAhead] or 0, vmax[idx] or 0)
  local accel = clamp((vt - av) * 0.8, -3.2, 1.6)
  if leadGap then
    local s0 = C.IDM_S0 + (isLorry and 1 or 0)
    local dv = av - leadV
    local sStar = s0 + math.max(0, av * C.IDM_T + av * dv / (2 * math.sqrt(C.IDM_A * C.IDM_B)))
    local g = math.max(0.3, leadGap)
    local idm = C.IDM_A * (1 - (av / math.max(vt, 1)) ^ 4 - (sStar / g) ^ 2)
    accel = math.min(accel, clamp(idm, -7, 1.6))
  end
  local aNow = (av - lastV) / dt
  lastV = av
  lastAcc = lastAcc + (aNow - lastAcc) * math.min(1, dt * 5)
  local t, b, pb = 0, 0, 0
  if accel > 0.05 then
    intg = clamp(intg + (accel - lastAcc) * 0.12 * dt, 0, 0.6)
    t = clamp(accel * 0.16 + intg + 0.04, 0, 1)
  elseif accel < -0.15 then
    intg = intg * math.max(0, 1 - dt * 2)
    b = clamp(-accel / 8.5, 0, 1)
  else
    intg = intg * math.max(0, 1 - dt)
  end
  -- standing, and not to move: the handbrake (the brake pedal of a stopped car in arcade mode is reverse)
  if av < 0.35 and accel <= 0.05 then t, b, pb = 0, 0, 1 end

  -- not getting anywhere
  if av < 0.5 and leadGap and leadGap < 20 then blockedT = blockedT + dt else blockedT = 0 end
  if av < 0.5 and not (leadGap and leadGap < 25) and vt > 2 then stuckT = stuckT + dt else stuckT = 0 end
  if blockedT > C.BLOCKED_S then return release('blocked') end
  if stuckT > C.STUCK_S then return release('stuck') end

  setInputs(steer, t, b, pb)
end

-- (whatever goes wrong in here: never the car's whole Lua. BeamNG's AI takes the car back)
local function update(dt)
  local ok, err = pcall(step, dt)
  if not ok then
    log('E', 'fernfahrer.driver', tostring(err))
    refuseUntil = os.clock() + 60
    pcall(release, 'error')
  end
end

release = function(why)
  if not active then return end
  active = false
  setBlink(0)
  if ai.updateGFX == update then ai.updateGFX = stock end
  setInputs(0, 0, 0, 0)
  stock = nil
  -- (back to a fresh route, from where the car is now)
  ai.setMode('traffic')
  local wait = why == 'junction' and 6 or (why == 'control room' and 0 or (why == 'map' and 3 or (why == 'error' and 60 or 15)))
  refuseUntil = math.max(refuseUntil, os.clock() + wait)
  notify(false, why)
end
M.release = release

function M.setCap(ms) cap = tonumber(ms) or 0; if active then profT = 0 end end

function M.setPassing(on) passing = on and true or false end

-- the control room's go for a junction
function M.junctionGo(node)
  for _, j in ipairs(juncs) do
    if j.node == node and not j.go then j.go = true; profT = 0 end
  end
end

-- move sideways: disp metres to the right, over so many metres. A whole lane's width on a road with several lanes is a lane change
function M.shift(disp, over)
  if not active then return end
  disp, over = tonumber(disp) or 0, math.max(C.SHIFT_MIN_M, tonumber(over) or C.SHIFT_MIN_M)
  local m, w = mine[idx], wid[idx]
  if m and m >= 2 and math.abs(disp) >= w * 0.6 then
    local before = laneOffset(idx)
    laneK = clamp(laneK + (disp > 0 and -1 or 1), 0, m - 1)
    blendErr = blendErr + before - laneOffset(idx)
  else
    extra = extra + disp
    blendErr = blendErr - disp
  end
  blendRate = math.abs(blendErr) / over
end

-- the line from where the car is, on the map as it is now. nil, or why not
buildLine = function()
  mapRef, graph, positions = mapmgr.mapData, mapmgr.mapData.graph, mapmgr.mapData.positions
  local pos, dir, vel = obj:getPosition(), obj:getDirectionVector(), obj:getVelocity()
  local a, b = mapmgr.findBestRoad(pos, dir)
  if not a or not b or not graph[a] or not graph[a][b] then return 'no road' end
  local pa, pb = positions[a], positions[b]
  local ex, ey = pb.x - pa.x, pb.y - pa.y
  local el = math.sqrt(ex * ex + ey * ey) + 1e-9
  local d = (ex * dir.x + ey * dir.y) / el
  if d < 0 then a, b, ex, ey, d = b, a, -ex, -ey, -d; pa, pb = positions[a], positions[b] end
  if d < 0.92 then return 'not along the road' end
  local e = graph[a][b]
  if e.oneWay and e.inNode ~= a then return 'wrong way' end

  local speed = math.abs(vel.x * dir.x + vel.y * dir.y)
  dropAll()
  flaggedAt, ended = nil, false
  addEdge(a, b)
  prevNode, curNode = a, b
  refine()
  idx = 1
  extend(speed)
  if n < 12 then return 'short road' end
  -- to the point on the line where the car is
  local best, bestD = 1, 1e18
  for i = 1, n do
    local dx, dy = pos.x - px[i], pos.y - py[i]
    local q = dx * dx + dy * dy
    if q < bestD then best, bestD = i, q end
  end
  idx = math.min(n - 3, best)
  extend(speed)
  if n - idx < 8 then return 'short road' end
  if ended and flaggedAt and (flaggedAt - idx) * C.STEP < math.max(C.REFUSE_JUNCTION_M, speed * (C.HANDOVER_S + 3)) then return 'junction' end
  frac = 0
  local lat = (pos.x - px[idx]) * nx[idx] + (pos.y - py[idx]) * ny[idx]
  if math.abs(lat) > half[idx] + 1 then return 'off the road' end

  -- the lane it is in (0: the right-hand one), and from there smoothly into its middle
  local m, w = mine[idx], wid[idx]
  laneK = clamp(math.floor((half[idx] - lat) / w), 0, m - 1)
  extra, passing, blendRate = 0, false, 0
  blendErr = 0
  blendErr = lat - laneOffset(idx)
  blendRate = math.abs(blendErr) / math.max(35, speed * 3)

  plan(speed)
  return nil
end

function M.acquire(ms)
  cap = tonumber(ms) or 0
  if active then return end
  local function no(why) notify(false, 'refused: ' .. why) end
  if os.clock() < refuseUntil then return end
  if ai.mode ~= 'traffic' or ai.updateGFX == update then return no('mode') end
  if not mapmgr.mapData or not mapmgr.mapData.graph then
    mapmgr.requestMap()
    return no('no map')
  end
  myLen, myWid = obj:getInitialLength(), obj:getInitialWidth()
  isLorry = myLen > 7
  latA = isLorry and C.LAT_LORRY or C.LAT_CAR
  wb = isLorry and myLen * 0.52 or myLen * 0.58
  local why = buildLine()
  if why then return no(why) end

  local vel, dir = obj:getVelocity(), obj:getDirectionVector()
  local speed = math.abs(vel.x * dir.x + vel.y * dir.y)
  steer, intg, lastAcc, lastV, lastDx, lastDy, latI = 0, 0, 0, speed, nil, nil, 0
  leadGap, leadV, profT, lookT, stuckT, blockedT = nil, 0, 0, 0, 0, 0
  plan(speed)
  stock = ai.updateGFX
  ai.updateGFX = update
  active = true
  notify(true, 'taken over')
end

function M.isActive() return active end

-- (should the stock AI's function be back - somebody set its mode, a reset - this driver is out of it)
function M.updateGFX()
  if active and ai.updateGFX ~= update then
    active, stock = false, nil
    setBlink(0)
    notify(false, 'taken back')
  end
end

function M.onReset()
  if active then release('reset') end
end

function M.onExtensionUnloaded()
  if active then release('unloaded') end
end

return M
