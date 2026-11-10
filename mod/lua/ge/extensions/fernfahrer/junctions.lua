-- Trucks of Earth: the junction control room (Beta, with our own driver, lua/vehicle/extensions/fernfahrer/driver.lua; 2026-11-10).
-- A car of ours that needs the junction ahead asks here, and waits at the line until it has the go. Whoever does not cross anybody's
-- way goes together; whoever would, goes in the order of the road's priority, and on equal roads right before left. Vehicles that do not
-- ask (the player, cars BeamNG's AI is driving, cars going straight along the main road) are seen as they come.
-- Bearings: radians, from the junction towards where the road goes.

local M = {}
M.C = {
  TICK_S = 0.15,
  ASK_LIFE_S = 1.2,        -- no further asking for this long: it has gone
  HOLD_S = 20,             -- a go lapses after this long at the latest
  CLEAR_M = 14,            -- gone this far from the junction, driving away from it: through
  SCAN_M = 140,
  INSIDE_M = 11,
  ETA_LOW_S = 5.5,         -- side road, left turn: a vehicle with priority this close in time is waited for
  ETA_HIGH_S = 3.5,
  IMPATIENT_S = 12,        -- waited this long: no more waiting for others who are only waiting too
}
local C = M.C
local J = {}
local tickT = 0
M.stats = { go = 0 }

local function norm(a) a = a % (2 * math.pi); return a end
local function diff(a, b) local d = math.abs(norm(a - b)); return d > math.pi and 2 * math.pi - d or d end
local function between(x, a, b) return norm(x - a) < norm(b - a) end

-- two ways through a junction: do they meet? (from a1 to b1, from a2 to b2)
local function conflict(a1, b1, a2, b2)
  if diff(a1, a2) < 0.5 then return false end           -- (the same way in: one behind the other, the driver keeps its distance)
  if diff(b1, b2) < 0.5 then return true end            -- (the same way out)
  -- (on the rim of the junction: cars keep right, so a way in lies a little anticlockwise of its road's bearing, a way out a little clockwise)
  local d = 0.35
  local i1, o1, i2, o2 = a1 + d, b1 - d, a2 + d, b2 - d
  return between(i2, i1, o1) ~= between(o2, i1, o1)
end
M.conflict = conflict

-- is bearing b on the right-hand side of a car coming in from bearing a? (angles counted anticlockwise)
local function fromRight(a, b) local d = norm(b - a); return d > math.pi * 0.25 and d < math.pi * 0.75 end
M.fromRight = fromRight

function M.ask(id, node, x, y, inB, outB, rank, eq, mainA, mainB, eta, t)
  t = t or os.clock()
  local j = J[node]
  if not j then j = { x = x, y = y, r = {} }; J[node] = j end
  local r = j.r[id]
  if not r then r = { id = id, first = t, go = false }; j.r[id] = r end
  r.inB, r.outB, r.rank, r.eq, r.mainA, r.mainB, r.eta, r.t = inB, outB, rank, eq and true or false, mainA, mainB, eta or 9, t
  return r.go
end

function M.done(id, node) local j = J[node]; if j then j.r[id] = nil; if not next(j.r) then J[node] = nil end end end

function M.reset() J = {} end

-- does anybody who is not asking have the right to go first?
local function outsider(j, r, node, objects, playerId, trailerId)
  local limit = r.rank >= 2 and C.ETA_HIGH_S or C.ETA_LOW_S
  for id, o in pairs(objects) do
    if id ~= r.id and not j.r[id] and o.pos and o.vel then
      local dx, dy = o.pos.x - j.x, o.pos.y - j.y
      local d = math.sqrt(dx * dx + dy * dy)
      if d < C.SCAN_M and d > 0.1 then
        local speed = math.sqrt(o.vel.x * o.vel.x + o.vel.y * o.vel.y)
        if d < C.INSIDE_M then
          -- in the junction now, going where it is going
          if speed > 0.8 then
            local out = math.atan2(o.vel.y, o.vel.x)
            if conflict(r.inB, r.outB, out + math.pi, out) then return true, id end
          end
        else
          local closing = -(o.vel.x * dx + o.vel.y * dy) / d
          if closing > 2 and d / closing < limit then
            local a = math.atan2(dy, dx)
            if conflict(r.inB, r.outB, a, a + math.pi) then
              local player = id == playerId or id == trailerId
              local onMain = (r.mainA and diff(a, r.mainA) < 0.6) or (r.mainB and diff(a, r.mainB) < 0.6)
              if player or onMain or (r.eq and fromRight(r.inB, a)) then return true, id end
            end
          end
        end
      end
    end
  end
  return false
end

local function first(a, b)
  if a.rank ~= b.rank then return a.rank > b.rank end
  if a.eq and b.eq then
    if fromRight(a.inB, b.inB) then return false end
    if fromRight(b.inB, a.inB) then return true end
  end
  return a.first < b.first
end

-- objects: map.objects; sendGo(id, node)
function M.tick(t, objects, playerId, trailerId, sendGo)
  if t - tickT < C.TICK_S then return end
  tickT = t
  for node, j in pairs(J) do
    for id, r in pairs(j.r) do
      local o = objects[id]
      local gone = not o or not o.pos
      if not gone and r.go then
        local dx, dy = o.pos.x - j.x, o.pos.y - j.y
        local d = math.sqrt(dx * dx + dy * dy)
        if d > C.CLEAR_M and o.vel and o.vel.x * dx + o.vel.y * dy > 0 then gone = true end
        if t - (r.goT or t) > C.HOLD_S then gone = true end
      end
      if gone or (not r.go and t - r.t > C.ASK_LIFE_S) then j.r[id] = nil end
    end
    if not next(j.r) then
      J[node] = nil
    else
      local waiting = {}
      for _, r in pairs(j.r) do
        if r.go then sendGo(r.id, node) else waiting[#waiting + 1] = r end
      end
      table.sort(waiting, first)
      local blocked = {}
      for _, r in ipairs(waiting) do
        local ok = true
        for _, g in pairs(j.r) do
          if g.go and conflict(r.inB, r.outB, g.inB, g.outB) then ok = false; break end
        end
        if ok and t - r.first < C.IMPATIENT_S then
          for _, b in ipairs(blocked) do
            if conflict(r.inB, r.outB, b.inB, b.outB) then ok = false; break end
          end
        end
        if ok and r.rank < 3 and outsider(j, r, node, objects, playerId, trailerId) then ok = false end
        if ok then
          r.go, r.goT = true, t
          M.stats.go = M.stats.go + 1
          sendGo(r.id, node)
        else
          blocked[#blocked + 1] = r
        end
      end
    end
  end
end

function M.count()
  local n, w = 0, 0
  for _, j in pairs(J) do n = n + 1; for _, r in pairs(j.r) do if not r.go then w = w + 1 end end end
  return n, w
end

return M
