-- Trucks of Earth: the police after a load without papers (career.lua L.pursuitStart). Never more than two patrol cars at once; when one is wrecked, stuck, left far behind or
-- has been at it long enough, one of at most three more may come. When they are all gone and the truck is still free, it got away. If the truck stands still with a patrol car at
-- it, it is over. BeamNG's own AI does the chasing (ai.setMode("chase")); the cars come out of the same pool as the patrol cars of the road scenes.
-- M.start(api), M.tick(t), M.active(), M.hud(), M.stop()
local M = {}
local pool = require('fernfahrer/pool')
local accidents = require('fernfahrer/accidents')

M.AT_ONCE, M.FIRST, M.RESERVE = 2, 2, 3
M.DUTY_S = { 150, 230 }       -- (how long one car keeps at it)
M.LOST_M, M.LOST_S = 1100, 15 -- (this far behind for this long: it has lost the truck)
M.WRECK_DMG = 9000            -- (the game's damage figure: this car drives no more)
M.BUST_M, M.BUST_S = 32, 5    -- (the truck standing, a patrol car this near, this long)

local P

local function flat(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end
local function chaseCmd(target)
  return string.format('controller.setFreeze(0) electrics.set_lightbar_signal(2) ai.setTargetObjectID(%d) ai.setMode("chase") ai.setSpeedMode("off") ai.setAggression(0.75) ai.driveInLane("off") ai.setAvoidCars("on")', target)
end
local OFF_CMD = 'ai.setMode("disabled") electrics.set_lightbar_signal(0)'

function M.active() return P ~= nil end
function M.start(api)
  if P then return end
  P = { api = api, cars = {}, first = M.FIRST, reserve = M.RESERVE, spawnAt = 0, still = 0, tickT = 0, fails = 0 }
end

local function drop(c)
  pcall(pool.give, c.id)
end
function M.stop()
  if not P then return end
  for _, c in ipairs(P.cars) do drop(c) end
  P = nil
end

local function spawnOne(v, t)
  local pos, dir
  for _, d in ipairs({ 300, 230, 170, 120 }) do
    pos, dir = accidents.behind(d)
    if pos then break end
  end
  if not pos then
    dir = vec3(v:getDirectionVector())
    dir.z = 0
    if dir:length() < 0.1 then return false end
    dir = dir:normalized()
    pos = vec3(v:getPosition()) - dir * 140
  end
  local id = pool.take('police', pos + vec3(0, 0, 0.4), dir)
  if not id or not getObjectByID(id) then return false end
  pcall(P.api.protect, id)
  table.insert(P.cars, { id = id, t0 = t, duty = M.DUTY_S[1] + math.random() * (M.DUTY_S[2] - M.DUTY_S[1]), kickAt = t + 0.3, farT = 0, stuckT = 0 })
  return true
end

function M.tick(t)
  if not P or t - P.tickT < 0.4 then return end
  local dt = P.tickT > 0 and math.min(2, t - P.tickT) or 0.4
  P.tickT = t
  local api = P.api
  local v = api.veh()
  if not v then M.stop(); return end
  local me = vec3(v:getPosition())
  -- (taken somewhere else, by the map of BeamNG.Earth for instance: there is nobody to follow any more, and no credit for it either)
  if P.last and flat(me, P.last) > 500 then M.stop(); api.gone(); return end
  P.last = me
  local target = v:getID()
  local active, nearest = 0, nil
  for i = #P.cars, 1, -1 do
    local c = P.cars[i]
    local ov, ob = getObjectByID(c.id), map and map.objects and map.objects[c.id]
    if not ov then table.remove(P.cars, i)
    else
      local at = vec3(ov:getPosition())
      local d = flat(at, me)
      local sp = vec3(ov:getVelocity()):length()
      if c.out then
        if d > 160 then drop(c); table.remove(P.cars, i) end
      else
        -- (an order to a car just woken up gets lost: again until it moves)
        if t >= c.kickAt and (sp < 2 or t - c.t0 < 1.5) and t - c.t0 < 14 then c.kickAt = t + 1.5; ov:queueLuaCommand(chaseCmd(target)) end
        c.farT = d > M.LOST_M and c.farT + dt or 0
        c.stuckT = (sp < 1 and d > 60 and t - c.t0 > 14) and c.stuckT + dt or 0
        local why = (ob and (ob.damage or 0) > M.WRECK_DMG and 'wreck') or (c.farT > M.LOST_S and 'lost') or (c.stuckT > 15 and 'lost') or (t - c.t0 > c.duty and 'duty') or nil
        if why then
          c.out = why
          ov:queueLuaCommand(OFF_CMD)
          api.note(why)
        else
          active = active + 1
          if not nearest or d < nearest then nearest = d end
        end
      end
    end
  end
  -- caught: the truck stands, a patrol car at it
  if nearest and nearest < M.BUST_M and vec3(v:getVelocity()):length() < 2.2 then
    P.still = P.still + dt
    if P.still >= M.BUST_S then M.stop(); api.busted(); return end
  else P.still = 0 end
  -- more to come?
  if active < M.AT_ONCE and P.first + P.reserve > 0 and t >= P.spawnAt then
    if spawnOne(v, t) then
      active = active + 1
      if P.first > 0 then P.first = P.first - 1; P.spawnAt = t + 4 else P.reserve = P.reserve - 1; P.spawnAt = t + 16 end
      P.fails = 0
    else
      -- (the pool allows one new car in 20 s; no road or no car for a long time counts as one that did not come)
      P.spawnAt, P.fails = t + 5, P.fails + 1
      if P.fails >= 14 then
        P.fails = 0
        if P.first > 0 then P.first = P.first - 1 else P.reserve = P.reserve - 1 end
      end
    end
  end
  if active == 0 and P.first + P.reserve == 0 then M.stop(); api.escaped(); return end
  P.active, P.nearest = active, nearest
end

function M.hud()
  if not P then return nil end
  local left = P.first + P.reserve
  return { text = '🚨 Polizei hinter dir', title = (P.active or 0) .. (P.active == 1 and ' Streife' or ' Streifen') .. (left > 0 and (' · noch ' .. left .. ' in Reserve') or ' · keine Reserve mehr'), dist = P.nearest and math.floor(P.nearest + 0.5) or nil }
end

return M
