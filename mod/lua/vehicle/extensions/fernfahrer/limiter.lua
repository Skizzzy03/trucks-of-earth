-- Trucks of Earth: the truck's speed limiter (EU trucks: 90 km/h), 2026-11-05. Loaded into the truck by the
-- career (fernfahrer_limiter); M.set(kmh, stockOff) sets it, M.set(nil) takes it off. Over the limit the gas pedal is
-- eased off (electrics.values.throttleOverride, which the vehicle controller reads before the pedal); a cruise control
-- set higher is pulled down to it. Braking, steering and everything else stay the player's.
-- stockOff (2026-11-07): the truck's own limiter lifted as well – the European tractors carry one in their ECU part
-- (vehicleController.topSpeedLimit, 25 m/s on the Percheron). Done with the controller's temporary limit, set to
-- "none" (-1) and switched on – the same as the part "Speed Limiter Delete", without a respawn; again after a reset,
-- which switches the temporary limit off.

local M = {}

local limit = nil        -- m/s, or nil: off
local owned = false      -- (the override is ours – cleared again when no longer needed)
local stockOff = false   -- the vehicle's own limiter lifted
local stockT = 0

local function release()
  if owned then electrics.values.throttleOverride = nil; owned = false end
end

local function vc()
  local c = controller and controller.mainController
  if c and c.setTopSpeedLimitTemporary and c.setTopSpeedLimitTemporaryActive then return c end
  return nil
end

local function applyStock()
  local c = vc()
  if not c then return end
  if stockOff then
    c.setTopSpeedLimitTemporary(-1)
    c.setTopSpeedLimitTemporaryActive(true)
  else
    c.setTopSpeedLimitTemporaryActive(false)
  end
end

-- (2026-11-07) the tank's size for the career: the stock tank holds 900 l and more – a day's regional tours used a
-- tenth of it. factor 0.5: half the stock size (the workshop's "Großer Tank" puts it back to 1). The fuel tanks'
-- capacity is set in their storage (fuelTank.lua: capacity, energyCapacity – plain values); fuel over it goes.
local tankFactor = nil
local tankT = 0
local function applyTank()
  if not tankFactor or not energyStorage or not energyStorage.getStorages then return end
  for _, s in pairs(energyStorage.getStorages() or {}) do
    local jb = type(s) == 'table' and s.jbeamData
    if s.type == 'fuelTank' and jb and jb.fuelCapacity and s.fuelLiquidDensity and s.energyDensity then
      local cap = jb.fuelCapacity * tankFactor
      if math.abs((s.capacity or 0) - cap) > 0.01 then
        s.capacity = cap
        s.startingCapacity = math.min(jb.startingFuelCapacity or cap, cap)
        s.energyCapacity = cap * s.fuelLiquidDensity * s.energyDensity
        s.brokenLeakRate = cap / 60
        if (s.storedEnergy or 0) > s.energyCapacity then s.storedEnergy = s.energyCapacity end
      end
    end
  end
end
function M.setTank(f)
  tankFactor = tonumber(f)
  applyTank()
end

function M.set(kmh, lift)
  kmh = tonumber(kmh)
  limit = kmh and kmh > 0 and kmh / 3.6 or nil
  if not limit then release() end
  local was = stockOff
  stockOff = lift and true or false
  if stockOff or was then applyStock() end
end

local function updateGFX(dt)
  -- (the lift kept on: a reset or the game's own cruise control may switch the temporary limit off)
  if stockOff then
    stockT = stockT + dt
    if stockT > 1 then stockT = 0; applyStock() end
  end
  if tankFactor then
    tankT = tankT + dt
    if tankT > 2 then tankT = 0; applyTank() end
  end
  if not limit then return end
  local v = electrics.values.wheelspeed or 0
  -- (a cruise control above the limit: down to it)
  if electrics.values.cruiseControlActive and (electrics.values.cruiseControlTarget or 0) > limit + 0.1 then
    local cc = extensions.cruiseControl
    if cc and cc.setSpeed then cc.setSpeed(limit) end
  end
  if electrics.values.cruiseControlActive then release(); return end
  local pedal = math.min(math.max(input.throttle or 0, 0), 1)
  -- (from 1 km/h under the limit the allowed throttle falls away to nothing 1 km/h over it)
  local allowed = math.min(1, math.max(0, (limit + 0.28 - v) / 0.56))
  if pedal > allowed then
    electrics.values.throttleOverride = allowed
    owned = true
  else
    release()
  end
end

local function onReset()
  release()
  if stockOff then applyStock() end
  applyTank()
end

M.updateGFX = updateGFX
M.onReset = onReset
M.onExtensionUnloaded = release

return M
