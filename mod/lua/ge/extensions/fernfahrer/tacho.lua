-- Trucks of Earth: the tachograph, run like a real digital one (DTCO) on a game clock SCALE times faster than
-- real time. EU rules (Regulation (EC) 561/2006), simplified:
--  * activities: driving (set by the tachograph itself as soon as the truck moves), other work, availability, break /
--    rest. When the truck stops the tachograph goes to OTHER WORK on its own – standing at a red light is not a break
--    (it was counted as one, 2026-11-03). A break counts only when the driver sets it (the bed button).
--  * after 4.5 h of driving a break of 45 min, or split: first at least 15 min, later at least 30 min.
--  * daily driving 9 h, twice a week 10 h; then a daily rest: 11 h (reduced 9 h). A rest of 24 h or more is a
--    weekly rest (resets the week and the 10 h extensions).
--  * weekly driving at most 56 h.
-- Breaking a rule is recorded and costs a fine at the next police check. State lives in the save (S.tacho).

local M = {}

M.SCALE = 10                 -- game seconds per real second
M.DRIVE_MAX = 4.5 * 3600
M.BREAK = 45 * 60
M.SPLIT1, M.SPLIT2 = 15 * 60, 30 * 60
M.DAY_MAX, M.DAY_EXT = 9 * 3600, 10 * 3600
M.EXT_PER_WEEK = 2
M.DAILY_REST, M.DAILY_REST_RED = 11 * 3600, 9 * 3600
M.WEEKLY_REST = 24 * 3600
M.WEEK_MAX = 56 * 3600
M.FORTNIGHT_MAX = 90 * 3600  -- (two weeks in a row together)
M.RED_PER_WEEK = 3           -- (reduced daily rests of 9 h between two weekly rests)
M.MOVING = 1.5               -- m/s
M.LOG_KEEP = 48 * 3600       -- (game seconds of activity kept for the chart)

M.NAMES = { drive = 'Lenken', work = 'Arbeit', avail = 'Bereitschaft', rest = 'Pause / Ruhe' }

function M.new()
  return { act = 'work', drive = 0, day = 0, week = 0, rest = 0, restRun = 0, split = false, ext = 0, dayLimit = M.DAY_MAX,
    work = 0, clock = 0, log = {}, violations = {}, warned = {} }
end

local function hm(s)
  s = math.max(0, math.floor(s / 60))
  return string.format('%d:%02d', math.floor(s / 60), s % 60)
end
M.hm = hm

-- (older saves: the fields this version keeps)
local function fix(T)
  T.act = M.NAMES[T.act] and T.act or 'work'
  T.drive, T.day, T.week, T.rest = T.drive or 0, T.day or 0, T.week or 0, T.rest or 0
  T.restRun, T.ext, T.work, T.clock = T.restRun or 0, T.ext or 0, T.work or 0, T.clock or 0
  T.dayLimit = T.dayLimit or M.DAY_MAX
  T.log, T.violations, T.warned = T.log or {}, T.violations or {}, T.warned or {}
end

-- the activity record: one segment per change, the same activity runs on
local function record(T, act, g)
  local last = T.log[#T.log]
  if last and last.a == act then last.d = last.d + g
  else T.log[#T.log + 1] = { a = act, s = T.clock, d = g } end
  T.clock = T.clock + g
  while #T.log > 1 and T.log[1].s + T.log[1].d < T.clock - M.LOG_KEEP do table.remove(T.log, 1) end
  if #T.log > 400 then table.remove(T.log, 1) end
end

local function violation(T, amount, reason, notify)
  table.insert(T.violations, { amount = amount, reason = reason })
  T.vtotal = (T.vtotal or 0) + 1          -- (all ever: a tour's count is the difference, police checks clear the list)
  if notify then notify('Fahrtenschreiber: ' .. reason .. ' – bei einer Kontrolle droht ein Bußgeld.', 8) end
end

-- (2026-11-05) the second part of a split break: what is left of the 45 minutes after the first part – its real
-- minutes count (44 min standing, then on: 15 min more, not another 30) – at least SPLIT1
function M.secondPart(T)
  return math.max(M.SPLIT1, M.BREAK - (T.splitFirst or M.SPLIT1))
end
M.AUTO_REST_S = 120          -- (tachograph seconds standing still, then the standing counts as a break by itself)

-- a rest that has run `T.restRun` so far: what it is worth (applied as the thresholds are passed, once each)
local function restProgress(T, notify, story)
  local r, w = T.restRun, T.warned
  if r >= M.WEEKLY_REST and not w.restWeek then
    w.restWeek = true
    -- (the week just ended stays counted for the two-week limit; the reduced rests start again)
    T.prevWeek, T.week, T.ext, T.red, w.fortnight = T.week, 0, 0, 0, nil
    if notify then notify('Wöchentliche Ruhezeit erreicht – Wochenlenkzeit und 10-h-Tage zurückgesetzt.', 7) end
  end
  if r >= M.DAILY_REST_RED and not w.restDay then
    w.restDay = true
    T.day, T.drive, T.split, T.work, T.dayLimit = 0, 0, false, 0, M.DAY_MAX
    w.drive30, w.drive, w.day, w.drive2 = nil, nil, nil, nil
    if notify then notify(r >= M.DAILY_REST and 'Tägliche Ruhezeit (11 h) – neuer Tag.' or 'Verkürzte tägliche Ruhezeit (9 h) – neuer Tag.', 7) end
    if story then story('firstRest') end
  end
  if not w.restBreak and (r >= M.BREAK or (T.split and r >= M.secondPart(T))) then
    w.restBreak = true
    if T.drive > 0 then
      T.drive, T.split = 0, false
      w.drive30, w.drive, w.drive2 = nil, nil, nil
      if notify then notify('Pause gültig – volle Lenkzeit (4:30) verfügbar.', 6) end
    end
  end
end

-- the end of a rest (the driver set another activity, or drove off): a first part of a split break is kept
local function endRest(T, notify)
  if T.restRun >= M.SPLIT1 and T.restRun < M.BREAK and not T.split and not T.warned.restBreak then
    T.split, T.splitFirst = true, T.restRun
    if notify then
      notify(string.format('Pause %d min gezählt – noch %d min Pause, dann ist die Lenkzeit wieder voll.',
        math.floor(T.restRun / 60), math.ceil(M.secondPart(T) / 60)), 7)
    end
  end
  -- a daily rest under 11 h is a reduced one: at most 3 between two weekly rests
  if T.warned.restDay and not T.warned.restWeek and T.restRun < M.DAILY_REST then
    T.red = (T.red or 0) + 1
    if T.red > M.RED_PER_WEEK then
      violation(T, 110, string.format('Tägliche Ruhezeit zu oft verkürzt (%d× unter 11 h seit der Wochenruhe, erlaubt 3×)', T.red), notify)
    elseif notify then
      notify(string.format('Verkürzte Tagesruhe gezählt: %d von 3 bis zur nächsten Wochenruhe.', T.red), 6)
    end
  end
  T.restRun = 0
  T.warned.restBreak, T.warned.restDay, T.warned.restWeek = nil, nil, nil
end

function M.update(T, dtSim, speed, notify, story)
  if not T then return end
  fix(T)
  local g = dtSim * M.SCALE
  if g <= 0 then return end
  local w = T.warned
  if speed > M.MOVING then
    if T.act ~= 'drive' then
      if T.act == 'rest' then endRest(T, notify) end
      T.act = 'drive'
    end
    T.drive, T.day, T.week, T.work = T.drive + g, T.day + g, T.week + g, T.work + g
    local left = M.DRIVE_MAX - T.drive
    if left < 30 * 60 and not w.drive30 then
      w.drive30 = true
      if notify then notify('Fahrtenschreiber: noch 30 min Lenkzeit – Pause einplanen: anhalten und am Fahrtenschreiber „Pause“ drücken.', 8) end
      if story then story('tachoBreak') end
    end
    if left < 0 and not w.drive then
      w.drive = true
      violation(T, 90, 'Lenkzeit überschritten (über 4,5 h ohne gültige Pause)', notify)
    end
    if left < -3600 and not w.drive2 then
      w.drive2 = true
      violation(T, 150, 'Lenkzeit um mehr als 1 h überschritten', notify)
    end
    -- the day: 9 h, a 10 h day when one of the week's two is left
    if T.day > T.dayLimit and not w.day then
      if T.dayLimit < M.DAY_EXT and T.ext < M.EXT_PER_WEEK then
        T.ext, T.dayLimit = T.ext + 1, M.DAY_EXT
        if notify then notify(string.format('Tageslenkzeit auf 10 h verlängert (%d von 2 diese Woche).', T.ext), 7) end
      else
        w.day = true
        violation(T, 150, string.format('Tageslenkzeit überschritten (über %d h)', math.floor(T.dayLimit / 3600)), notify)
      end
    end
    if T.week > M.WEEK_MAX and not w.week then
      w.week = true
      violation(T, 300, 'Wochenlenkzeit überschritten (über 56 h)', notify)
    end
    if T.week + (T.prevWeek or 0) > M.FORTNIGHT_MAX and not w.fortnight then
      w.fortnight = true
      violation(T, 300, 'Doppelwoche überschritten (über 90 h Lenkzeit in zwei Wochen)', notify)
    end
    record(T, 'drive', g)
  else
    -- standing: the truck stopped after driving → other work; a break only by the driver's own button (2026-11-07:
    -- the automatic break after two minutes is gone again – the player wants to set it himself)
    if T.act == 'drive' then T.act = 'work' end
    if T.act == 'rest' then
      T.restRun = T.restRun + g
      T.rest = T.restRun
      restProgress(T, notify, story)
    else
      T.rest = 0
      if T.act == 'work' then T.work = T.work + g end
    end
    record(T, T.act, g)
  end
end

-- the driver's buttons (only while standing): other work, availability, break / rest
function M.setActivity(T, act, speed)
  if not T or not M.NAMES[act] or act == 'drive' then return false, 'Lenken stellt der Fahrtenschreiber selbst ein.' end
  fix(T)
  if (speed or 0) > M.MOVING then return false, 'Während der Fahrt nicht möglich – erst anhalten.' end
  if T.act == act then return true end
  if T.act == 'rest' then endRest(T) end    -- (no notify here: setActivity has none; the count still goes on)
  T.act = act
  if act == 'rest' then T.restRun = 0; T.rest = 0 end
  return true
end

-- time passing in one go with the driver resting (sleep, a ferry crossing): a rest of that length
function M.restFor(T, seconds, notify, story)
  if not T then return end
  fix(T)
  if T.act ~= 'rest' then T.act = 'rest'; T.restRun = 0 end
  T.restRun = T.restRun + seconds
  T.rest = T.restRun
  record(T, 'rest', seconds)
  restProgress(T, notify, story)
end

-- the daily rest (the "sleep" of Euro Truck Simulator): hours of rest in one go; the tachograph then stands on rest
function M.rest(T, hours)
  if not T then return end
  M.restFor(T, (hours or 11) * 3600)
end

-- a police check: the recorded violations, then cleared
function M.takeViolations(T)
  local v = T and T.violations or {}
  if T then T.violations = {} end
  return v
end

function M.view(T)
  if not T then return nil end
  fix(T)
  local breakNeed = T.split and M.secondPart(T) or M.BREAK
  local v = {
    act = T.act, actName = M.NAMES[T.act],
    driveLeft = M.DRIVE_MAX - T.drive, dayLeft = T.dayLimit - T.day, weekLeft = M.WEEK_MAX - T.week,
    dayLimit = T.dayLimit, ext = T.ext, extLeft = M.EXT_PER_WEEK - T.ext, split = T.split or nil,
    rest = T.restRun, breakNeed = breakNeed, resting = T.act == 'rest' or nil, violations = #T.violations,
    driveText = hm(math.max(0, M.DRIVE_MAX - T.drive)), dayText = hm(math.max(0, T.dayLimit - T.day)),
    weekText = hm(math.max(0, M.WEEK_MAX - T.week)), drivenText = hm(T.drive), dayDrivenText = hm(T.day),
    weekDrivenText = hm(T.week), workText = hm(T.work), restText = hm(T.restRun), breakText = hm(breakNeed),
    over = T.drive > M.DRIVE_MAX or T.day > T.dayLimit or nil,
    redLeft = math.max(0, M.RED_PER_WEEK - (T.red or 0)),
    fortnightText = hm(math.max(0, M.FORTNIGHT_MAX - T.week - (T.prevWeek or 0))),
  }
  -- the rest running: what it will be worth
  if T.act == 'rest' then
    local r = T.restRun
    if r < breakNeed and T.drive > 0 then v.restGoal, v.restGoalText = breakNeed, 'gültige Pause'
    elseif r < M.DAILY_REST_RED then v.restGoal, v.restGoalText = M.DAILY_REST_RED, 'Tagesruhe (9 h)'
    elseif r < M.DAILY_REST then v.restGoal, v.restGoalText = M.DAILY_REST, 'Tagesruhe (11 h)'
    elseif r < M.WEEKLY_REST then v.restGoal, v.restGoalText = M.WEEKLY_REST, 'Wochenruhe (24 h)' end
    v.restGoalLeft = v.restGoal and hm(v.restGoal - r) or nil
  end
  -- the last 24 h as a bar (like the printout): segments with their share of the day
  local from = T.clock - 24 * 3600
  local segs = {}
  for _, s in ipairs(T.log) do
    local a, b = math.max(s.s, from), s.s + s.d
    if b > a then segs[#segs + 1] = { a = s.a, x = (a - from) / (24 * 3600), w = (b - a) / (24 * 3600) } end
  end
  v.chart = segs
  -- the current activity's time
  local last = T.log[#T.log]
  v.actText = last and last.a == T.act and hm(last.d) or '0:00'
  return v
end

return M
