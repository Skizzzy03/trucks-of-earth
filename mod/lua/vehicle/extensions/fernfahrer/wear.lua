-- Trucks of Earth: what happens in the vehicle itself (2026-11-08). Loaded by the career (fernfahrer_wear);
-- M.set{ pull, drift, noCruise, turbo, overload } says what applies now:
--   pull      a steering offset (-1…1, negative: left) – a bent axle on a used truck
--   drift     amplitude of a slow wandering of the steering – too many beers
--   noCruise  the cruise control will not stay on – a joint
--   turbo     a worn turbo: less power, smoke under load
--   overload  1 = normal; heavier loads heat the tyres faster
-- Hot brakes heat the tyres beside them; a tyre that has been cooking too long bursts (beamstate.deflateTire, as the
-- game's own fires do). The brake temperatures are the game's (wheels.lua: real energy from braking); once a second the
-- hottest goes to the career, which warns.

local M = {}

local cfg = {}
local t, sendT, smokeT, stateT = 0, 0, 0, 0
local heat = {}              -- wheel index -> accumulated heat of the tyre (0 … 1: bursts)
local popped = {}

M.HOT_C, M.BURST_S = 430, 42  -- (above this the tyre heats; at 200 °C more it takes BURST_S seconds, less when overloaded)

function M.set(c)
  cfg = c or {}
end

-- (the career's look at the road, five times a second: a steering correction, leave-the-lane, the gap to the car ahead)
local as = { t = -1 }
local accSet, accLast, brakeOwned, beepT = nil, nil, false, 0
local brakeNow, accBusy, lkaNow = 0, false, 0
local ACC_DEC = 0.6           -- (m/s²: how gently the speed comes down to that of the one ahead)
local function setBusy(b)
  if b == accBusy then return end
  accBusy = b
  obj:queueGameEngineLua('if fernfahrer_career then fernfahrer_career.onAccState(' .. tostring(b) .. ') end')
end
function M.assist(steer, beep, gap, lead)
  as.t, as.steer, as.beep, as.gap, as.lead = t, steer, beep, gap, lead
end
local function signalling()
  local e = electrics.values
  return (e.signal_left_input or 0) > 0 or (e.signal_right_input or 0) > 0 or (e.signal_L or 0) > 0 or (e.signal_R or 0) > 0
end
local function releaseBrake()
  if brakeOwned then electrics.values.brakeOverride = nil; brakeOwned = false end
  brakeNow = 0
end
local function acc(dt)
  local cc = extensions.cruiseControl
  if not cc or not cc.getConfiguration or not electrics.values.cruiseControlActive then accSet, accLast = nil, nil; releaseBrake(); setBusy(false); return end
  local c = cc.getConfiguration()
  -- (the driver changed the set speed: that is the one to come back to)
  if accSet == nil or (accLast and math.abs(c.targetSpeed - accLast) > 0.2) then accSet = c.targetSpeed end
  local v = electrics.values.wheelspeed or 0
  local fresh = t - as.t < 0.8
  local gap, lead = fresh and as.gap, fresh and as.lead
  local want = accSet
  local brake, need = 0, 0
  -- (2026-11-09: it sees 250 m ahead, but only what has to happen is done: the truck stays at its speed until letting off the throttle is just enough to arrive at the normal gap at
  -- the speed of the one ahead. Same speed ahead: nothing at all until the gap is reached. The brake only when letting off is not enough, eased on.)
  if gap then
    lead = math.max(0, lead)
    local desired = math.max(14, v * 1.9)
    local room = gap - desired
    if room > 0 then want = math.min(accSet, math.sqrt(lead * lead + 2 * ACC_DEC * room))
    else want = math.max(0, math.min(accSet, lead + room * 0.2)) end
    if v > lead + 0.3 then
      need = (v * v - lead * lead) / (2 * math.max(room + desired * 0.25, 3))
      if need > 1.0 then brake = math.min(0.7, (need - 0.8) * 0.16) end
    end
  end
  if brake > brakeNow then brakeNow = math.min(brake, brakeNow + dt * (need > 2 and 1.2 or 0.25))
  else brakeNow = math.max(brake, brakeNow - dt * 0.6) end
  if accBusy then if want > math.min(accSet, v) - 0.3 and brakeNow < 0.01 then setBusy(false) end
  elseif want < math.min(accSet, v) - 0.7 or brakeNow > 0.02 then setBusy(true) end
  -- (too slow for the cruise control: it lets go, the driver takes over)
  if want < cc.minimumSpeed and v < cc.minimumSpeed + 0.5 then
    cc.setEnabled(false)
    releaseBrake()
    setBusy(false)
    obj:queueGameEngineLua('if fernfahrer_career then fernfahrer_career.onAccOff() end')
    return
  end
  want = math.max(want, cc.minimumSpeed)
  if math.abs(want - c.targetSpeed) > 0.15 then
    cc.setSpeed(want)
    accLast = want
  elseif not accLast then accLast = c.targetSpeed end
  if brakeNow > 0.01 then electrics.values.brakeOverride = brakeNow; brakeOwned = true
  elseif brakeOwned then electrics.values.brakeOverride = nil; brakeOwned = false end
end

local function engine()
  return powertrain and powertrain.getDevice and powertrain.getDevice('mainEngine') or nil
end

local function thermals(dt)
  local data = v and v.data and v.data.wheels
  local th = electrics.values.wheelThermals
  if not data or not th then return end
  local maxT = 0
  local burst = false
  for i, w in pairs(data) do
    local d = th[w.name]
    local b = d and d.brakeSurfaceTemperature
    if b then
      if b > maxT then maxT = b end
      local h = heat[i] or 0
      if b > M.HOT_C then
        h = h + dt * ((b - M.HOT_C) / 200) * (cfg.overload or 1) / M.BURST_S
      else
        h = math.max(0, h - dt / 90)                    -- (cooling off: a minute and a half)
      end
      heat[i] = h
      if h >= 1 and not popped[i] then
        -- (not to the second: the worn tyre goes when it goes)
        if math.random() < dt * 0.25 then
          popped[i] = true
          beamstate.deflateTire(i)
          burst = true
          if sounds and sounds.playSoundOnceFollowNode and w.node1 then
            pcall(sounds.playSoundOnceFollowNode, 'event:>Vehicle>Failures>tire_burst', w.node1, 1)
          end
        end
      end
    end
  end
  return maxT, burst
end

-- (2026-11-08) a breakdown out of nowhere (service.lua): 'tire', 'radiator', 'hose' (limp home), 'oil'
local failed, tempT = nil, 0
function M.fail(kind)
  local e = engine()
  local th = e and e.thermals
  if (kind == 'radiator' and not (th and th.applyDeformGroupDamageRadiator)) or (kind == 'oil' and not (th and th.applyDeformGroupDamageOilRadiator)) then kind = 'hose' end
  failed = kind
  if kind == 'radiator' then e:applyDeformGroupDamage(0.12, 'radiator')
  elseif kind == 'oil' then e:applyDeformGroupDamage(0.6, 'oilRadiator')
  elseif kind == 'tire' and v and v.data and v.data.wheels then
    local list = {}
    for i in pairs(v.data.wheels) do if not popped[i] then list[#list + 1] = i end end
    if #list > 0 then
      local i = list[math.random(#list)]
      popped[i] = true
      beamstate.deflateTire(i)
      local w = v.data.wheels[i]
      if sounds and sounds.playSoundOnceFollowNode and w and w.node1 then
        pcall(sounds.playSoundOnceFollowNode, 'event:>Vehicle>Failures>tire_burst', w.node1, 1)
      end
    end
  end
end

-- (2026-11-10) the game's cruise control lets go at the slightest touch of the brake, and gives no throttle while throttle or
-- clutch are a hair above 0 - a wheel's pedals at rest often read just that (0.01 ... 0.04). Its frame is wrapped: what is
-- below a small dead zone counts as 0 for it. When it switches itself off, what the pedals said goes to the log.
-- (2026-11-10, 2nd: the log had it let go at 0.08 and 0.15 of brake - a foot resting on the pedal, not braking. Now a brake counts from 0.22 at once, or from
-- 0.08 when it is held for 0.4 s: a real touch of the brake still lets go at once, as in any lorry)
local PED = { brake = 0.08, brakeNow = 0.22, brakeHold = 0.4, throttle = 0.06, clutch = 0.15 }
local ccWhy, noCruiseSaid, brakeT, refusedT = nil, false, 0, -100
local function wrapCruise()
  local cc = extensions.cruiseControl
  if not cc or cc.__ffWrapped or type(cc.updateGFX) ~= 'function' or not input then return end
  local orig = cc.updateGFX
  cc.updateGFX = function(dt)
    local b, th, c = input.brake, input.throttle, input.clutch
    if (b or 0) >= PED.brake then brakeT = brakeT + (dt or 0) else brakeT = 0 end
    if (b or 0) < PED.brakeNow and brakeT < PED.brakeHold then input.brake = 0 end
    if (th or 0) < PED.throttle then input.throttle = 0 end
    if (c or 0) < PED.clutch then input.clutch = 0 end
    local was = electrics.values.cruiseControlActive
    local ok, err = pcall(orig, dt)
    input.brake, input.throttle, input.clutch = b, th, c
    if was and not electrics.values.cruiseControlActive then
      ccWhy = string.format('brake %.2f, throttle %.2f, clutch %.2f, crash brake %s', b or 0, th or 0, c or 0, tostring(electrics.values.postCrashBrakeTriggered or false))
    end
    if not ok then error(err) end
  end
  cc.__ffWrapped = true
  if extensions.hookUpdate then extensions.hookUpdate('updateGFX') end
end

local function updateGFX(dt)
  t = t + dt
  wrapCruise()
  if ccWhy then
    obj:queueGameEngineLua('log("I", "fernfahrer.cruise", ' .. string.format('%q', 'cruise control let go by the game: ' .. ccWhy) .. ')')
    ccWhy = nil
  end
  if failed == 'radiator' or failed == 'oil' then
    tempT = tempT + dt
    if tempT > 2 then
      tempT = 0
      obj:queueGameEngineLua(string.format('if fernfahrer_career and fernfahrer_career.onEngineTemp then fernfahrer_career.onEngineTemp(%.0f, %.0f) end',
        electrics.values.watertemp or 0, electrics.values.oiltemp or 0))
    end
  end
  -- the steering: read by hydros right after this hook
  local s = electrics.values.steering_input
  if s then
    local off = (cfg.pull or 0)
    if cfg.drift and cfg.drift > 0 then
      off = off + cfg.drift * (math.sin(t * 0.43) * 0.6 + math.sin(t * 0.97 + 1.3) * 0.4)
    end
    -- the lane keeper: only while the driver is not steering himself and not signalling. (2026-11-09: the correction came five times a second and went straight onto the steering, the wheel
    -- jumped. Now it is only a value to move towards, slowly, and it fades out the same way.)
    local lkaWant = 0
    if t - as.t < 0.6 and as.steer and as.steer ~= 0 and math.abs(s) < 0.15 and (electrics.values.wheelspeed or 0) > 16 and not signalling() then lkaWant = as.steer end
    local lkaStep = (lkaWant - lkaNow) * math.min(1, dt * 2.5)
    lkaNow = lkaNow + math.max(-dt * 0.05, math.min(dt * 0.05, lkaStep))
    off = off + lkaNow
    if off ~= 0 and (electrics.values.wheelspeed or 0) > 2 then
      electrics.values.steering_input = math.max(-1, math.min(1, s + off))
    end
  end
  pcall(acc, dt)
  -- the lane warner
  if as.beep and t - as.t < 0.6 and (electrics.values.wheelspeed or 0) > 15 and not signalling() and t - beepT > 6 then
    beepT = t
    obj:queueGameEngineLua('if fernfahrer_career then fernfahrer_career.onLaneBeep() end')
  end
  -- the cruise control refuses
  if cfg.noCruise and electrics.values.cruiseControlActive and extensions.cruiseControl and extensions.cruiseControl.setEnabled then
    extensions.cruiseControl.setEnabled(false)
    if not noCruiseSaid then noCruiseSaid = true; obj:queueGameEngineLua('log("I", "fernfahrer.cruise", "cruise control off: high")') end
    -- (2026-11-10: said, every time it is tried: it looked like a fault)
    if t - refusedT > 12 then refusedT = t; obj:queueGameEngineLua('if fernfahrer_career and fernfahrer_career.onCruiseRefused then fernfahrer_career.onCruiseRefused() end') end
  end
  -- the worn turbo
  stateT = stateT + dt
  if stateT > 0.5 then
    stateT = 0
    local e = engine()
    if e and cfg.turbo then
      if e.outputTorqueState and e.outputTorqueState > 0.8 then e.outputTorqueState = 0.8 end
    end
    -- (2026-11-09: the engine overhauled: the idle steady again, the kilometres stay)
    if e and cfg.smooth and e.wearIdleAVReadErrorRangeCoef and e.wearIdleAVReadErrorRangeCoef > 1.5 then e.wearIdleAVReadErrorRangeCoef = 1.5 end
    if e and failed == 'hose' and e.outputTorqueState and e.outputTorqueState > 0.42 then e.outputTorqueState = 0.42 end
  end
  if cfg.turbo then
    local e = engine()
    local load = electrics.values.throttle or 0
    if e and e.engineBlockNodes and e.engineBlockNodes[2] and load > 0.55 and (electrics.values.rpm or 0) > 900 then
      smokeT = smokeT + dt
      if smokeT > 0.12 then
        smokeT = 0
        local r = math.random() * 2
        obj:addParticleByNodesRelative(e.engineBlockNodes[2], e.engineBlockNodes[1], r, 43, 0, 1)
        obj:addParticleByNodesRelative(e.engineBlockNodes[2], e.engineBlockNodes[1], -r, 39, 0, 1)
      end
    end
  end
  -- the brakes and tyres, once a second
  sendT = sendT + dt
  if sendT >= 1 then
    local maxT, burst = thermals(sendT)
    sendT = 0
    if maxT then
      obj:queueGameEngineLua(string.format('if fernfahrer_career and fernfahrer_career.onWheelState then fernfahrer_career.onWheelState(%d, %.0f, %s) end',
        obj:getID(), maxT, tostring(burst or false)))
    end
  end
end

local function onReset()
  heat, popped = {}, {}
  failed, tempT = nil, 0
  accSet, accLast = nil, nil
  releaseBrake()
  setBusy(false)
  lkaNow = 0
end

M.updateGFX = updateGFX
M.onReset = onReset

return M
