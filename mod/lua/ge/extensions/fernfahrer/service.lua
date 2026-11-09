-- Trucks of Earth: what goes wrong on the road by itself, who comes to help, and who pays (2026-11-08).
--  * Breakdowns out of nowhere, a few per thousand kilometres: a burst tyre, the radiator (the engine overheats – stop!), a
--    burst boost hose (limp home), an oil leak. The vehicle side is wear.lua (M.fail).
--  * The breakdown service is called, starts from wherever it is and really drives up behind the truck (accidents.lua:
--    the responders' way), works for a while, then the truck is whole again and it drives off.
--  * The club: a membership (none / Basis / Plus / Premium) decides what a call-out costs and how long it takes; points for
--    each day and each clean delivery, spent on rewards; a status that grows.
--  * The insurance: third party (always), partial cover or fully comprehensive, the excess, the no-claims class.
-- M.attach(api) once; M.tick(dt) every frame; M.request(), M.act(id, arg), M.view(), M.hud(), M.quote(cost), M.commit(q).

local M = {}
local accidents = require('fernfahrer/accidents')

local api
function M.attach(a) api = a end
local function now() return os.clock() end
local function round(x, s) s = s or 1; return math.floor(x / s + 0.5) * s end

M.NAME, M.SHORT = 'Deutscher Truck-Club', 'DTC'
M.INSURER = 'Landstraßen-Assekuranz'

M.TIERS = {
  [0] = { id = 0, name = 'Kein Mitglied', perDay = 0, fee = 480, parts = 0, wait = 80, mult = 0,
    lines = { 'Einsatz immer zum vollen Preis', 'Längste Wartezeit', 'Keine Punkte' } },
  [1] = { id = 1, name = 'Basis', perDay = 6, fee = 180, parts = 0, wait = 40, mult = 1,
    lines = { 'Pannendienst für 180 €', 'Kürzere Wartezeit', 'Punkte sammeln' } },
  [2] = { id = 2, name = 'Plus', perDay = 14, fee = 0, parts = 0.5, wait = 18, mult = 2,
    lines = { 'Pannendienst frei', 'Teile zur Hälfte', 'Doppelte Punkte' } },
  [3] = { id = 3, name = 'Premium', perDay = 26, fee = 0, parts = 1, wait = 5, mult = 3,
    lines = { 'Pannendienst und Teile frei', 'Sofort unterwegs', 'Dreifache Punkte' } },
}
M.STATUS = { { 0, 'Bronze' }, { 300, 'Silber' }, { 900, 'Gold' }, { 2000, 'Platin' } }
M.REWARDS = {
  { id = 'diesel', cost = 180, icon = '⛽', name = 'Diesel-Gutschein', sub = '100 € aufs Firmenkonto' },
  { id = 'shop', cost = 250, icon = '🔧', name = 'Werkstatt-Gutschein', sub = '150 € bei der nächsten Reparatur' },
  { id = 'coffee', cost = 60, icon = '☕', name = 'Kaffee-Paket', sub = '4 Kaffee to go in die Kabine' },
  { id = 'sfsafe', cost = 600, icon = '🛡', name = 'Rabattretter', sub = 'Der nächste Schaden kostet keine SF-Klasse' },
}
M.PLANS = {
  { id = 'haft', name = 'Haftpflicht', base = 18, sub = 'Der Schaden der anderen',
    lines = { { true, 'Schäden an anderen Fahrzeugen' }, { false, 'Pannen-Teile' }, { false, 'Eigener Unfallschaden' } } },
  { id = 'teil', name = 'Teilkasko', base = 34, sub = 'Dazu Pech am eigenen LKW',
    lines = { { true, 'Schäden an anderen Fahrzeugen' }, { true, 'Pannen-Teile (150 € Selbstbeteiligung)' }, { false, 'Eigener Unfallschaden' } } },
  { id = 'voll', name = 'Vollkasko', base = 62, sub = 'Auch dein eigener Schaden',
    lines = { { true, 'Schäden an anderen Fahrzeugen' }, { true, 'Pannen-Teile (150 € Selbstbeteiligung)' }, { true, 'Eigener Unfallschaden, auch selbst verschuldet' } } },
}
M.PLAN_RANK = { haft = 1, teil = 2, voll = 3 }
M.SB_OPTS = { { 1000, 0.8 }, { 500, 1 }, { 150, 1.25 } }
M.SF_MAX, M.SF_DAYS = 12, 7

-- what can go wrong: its look, what the part costs, how long the work takes (s)
M.FAIL = {
  tire = { w = 42, icon = '💥', title = 'Reifenplatzer', text = 'Ein Reifen ist geplatzt. Vorsichtig rechts ran und den Pannendienst rufen.', part = 260, work = 34 },
  radiator = { w = 22, icon = '🌡', title = 'Kühler defekt', text = 'Kühlwasser läuft aus, der Motor wird heiß. Sofort anhalten, sonst ist er hin.', part = 640, work = 55 },
  hose = { w = 21, icon = '⚙', title = 'Ladeluftschlauch geplatzt', text = 'Der Motor läuft nur noch im Notlauf. Bis zum nächsten sicheren Platz, dann den Pannendienst rufen.', part = 180, work = 30 },
  oil = { w = 15, icon = '🛢', title = 'Ölverlust', text = 'Der Öldruck fällt. Anhalten, bevor der Motor Schaden nimmt.', part = 220, work = 40 },
  recover = { icon = '🛠', title = 'Pannenhilfe', text = 'Der Pannendienst richtet das Fahrzeug wieder her.', part = 0, work = 42 },
}
M.RATE_KM, M.MIN_GAP_KM = 380, 90        -- (on average one per RATE km after the gap, so about one in 470 km)
M.CANCEL_FEE, M.AWAY_M = 60, 80

local st = { km = 0 }                    -- the session: fail = { kind }, svc = the call running

local function S() return api.S() end
local function club()
  local s = S()
  if type(s.club) ~= 'table' then s.club = { tier = 0, pts = 0, life = 0, rescues = 0, voucher = 0, km = 0, no = math.random(1000000, 9999999) } end
  return s.club
end
local function ins()
  local s = S()
  if type(s.ins) ~= 'table' then s.ins = { plan = 'haft', sb = 500, sf = 2, clean = 0, history = {} } end
  return s.ins
end
local function tier() return M.TIERS[club().tier] or M.TIERS[0] end
local function planOf(id) for _, p in ipairs(M.PLANS) do if p.id == id then return p end end return M.PLANS[1] end
local function sbFactor(sb) for _, o in ipairs(M.SB_OPTS) do if o[1] == sb then return o[2] end end return 1 end
local function sfFactor(sf) return math.max(0.5, 1.25 - 0.06 * (sf or 0)) end

function M.premium(planId, sb, sf)
  local def = api.def() or {}
  local value = math.max(0.7, math.min(1.5, (def.price or 80000) / 80000))
  local f = planId == 'voll' and sbFactor(sb) or 1
  return round(planOf(planId).base * value * sfFactor(sf) * f)
end

local function note(kind, title, amount, covered, text)
  local i = ins()
  table.insert(i.history, 1, { k = kind, title = title, a = amount, c = covered, x = text, d = S().dayNo or 1, t = os.time() })
  i.history[31] = nil
end

local function sfDown(n, why)
  local i, c = ins(), club()
  if (c.sfSafe or 0) > 0 then
    c.sfSafe = c.sfSafe - 1
    api.notify('🛡 Rabattretter eingelöst: deine SF-Klasse bleibt.', 6)
    return
  end
  local was = i.sf
  i.sf = math.max(0, i.sf - n)
  i.clean = 0
  if i.sf ~= was then api.message(string.format('%s: Schadenfreiheitsklasse von SF %d auf SF %d (%s).', M.INSURER, was, i.sf, why), 'Versicherung') end
end

-- --- once per game day: premiums, points, the no-claims class -------------------------------------------------------
local function daily()
  local s, c, i = S(), club(), ins()
  local day = s.dayNo or 1
  if not i.lastDay then i.lastDay = day; return end
  if day <= i.lastDay then return end
  local n = math.min(30, day - i.lastDay)
  i.lastDay = day
  if i.next then i.plan = i.next; i.next = nil; api.notify('🛡 Dein neuer Versicherungsschutz gilt ab heute: ' .. planOf(i.plan).name .. '.', 6) end
  local pr = M.premium(i.plan, i.sb, i.sf) * n
  api.pay('Versicherung', -pr, string.format('%s (%d Tag%s)', planOf(i.plan).name, n, n == 1 and '' or 'e'))
  local t = tier()
  if t.perDay > 0 then
    local fee = t.perDay * n
    if s.money < fee then
      c.tier = 0
      api.notify('Dein Club-Beitrag konnte nicht abgebucht werden – die Mitgliedschaft ruht.', 8)
    else
      api.pay('Club', -fee, string.format('%s %s (%d Tag%s)', M.SHORT, t.name, n, n == 1 and '' or 'e'))
      local add = 5 * t.mult * n
      c.pts, c.life = c.pts + add, c.life + add
    end
  end
  i.clean = (i.clean or 0) + n
  while i.clean >= M.SF_DAYS and i.sf < M.SF_MAX do
    i.clean = i.clean - M.SF_DAYS
    i.sf = i.sf + 1
    api.message(string.format('%s: ohne Schaden gefahren – jetzt SF %d, der Beitrag sinkt.', M.INSURER, i.sf), 'Versicherung')
  end
  api.save()
end

-- --- the accident report (accidents.lua) ------------------------------------------------------------------------------
M.THIRD = { ['leichter Sachschaden'] = 900, ['erheblicher Sachschaden'] = 2600, ['schwerer Unfall'] = 7500 }
M.REGRESS_MAX = 5000
function M.onReport(doc)
  local i = ins()
  local void = doc.fled or (doc.bac and doc.bac >= 0.5) or (doc.thc and doc.thc >= 3.5) or false
  i.open = { fault = doc.fault, case = doc.case, void = void or nil, plan = i.plan, t = os.time() }
  local others, peds = doc.others or 0, doc.pedestrians or 0
  if others == 0 and peds == 0 then return end
  local mine = doc.fault == 'Fahrer (du)'
  local share = doc.fault and doc.fault:find('Teilschuld') and 0.5 or (mine and 1 or 0)
  if share <= 0 then
    note('opp', 'Unfall ' .. tostring(doc.case), 0, 0, 'Der Unfallgegner trägt die Schuld. Deine Reparatur zahlt seine Versicherung.')
    return
  end
  local amount = round(((M.THIRD[doc.severity] or 2600) * math.max(1, others) + peds * 6000) * share, 10)
  note('haft', 'Fremdschaden ' .. tostring(doc.case), amount, amount, 'Die Haftpflicht reguliert den Schaden der anderen.')
  sfDown(share >= 1 and 2 or 1, 'Haftpflichtschaden')
  if void then
    local r = math.min(M.REGRESS_MAX, amount)
    api.pay('Versicherung', -r, 'Regress: ' .. tostring(doc.case))
    note('regress', 'Regress ' .. tostring(doc.case), r, 0, doc.fled and 'Unfallflucht: die Versicherung holt sich Geld zurück.' or 'Fahren unter Einfluss: die Versicherung holt sich Geld zurück.')
    api.notify(string.format('🛡 Regress der Versicherung: %s', api.money(-r)), 8)
  end
  api.save()
end

-- what a repair costs the company
function M.quote(cost)
  local i, c = ins(), club()
  local o = i.open
  local plan = o and o.plan or i.plan
  local covered, kind, text = 0, nil, nil
  if cost > 0 then
    if o and o.fault == 'Unfallgegner' then
      covered, kind, text = cost, 'opp', 'zahlt die Versicherung des Unfallgegners'
    elseif o and o.fault and o.fault:find('Teilschuld') then
      covered, kind, text = round(cost * 0.5, 10), 'share', 'zur Hälfte von der Gegenseite'
      if plan == 'voll' and not o.void then
        local rest = cost - covered
        local k = math.max(0, rest - i.sb)
        if k > 0 then covered, kind, text = covered + k, 'voll', string.format('Gegenseite und Vollkasko (SB %d €)', i.sb) end
      end
    elseif plan == 'voll' and not (o and o.void) then
      local k = math.max(0, cost - i.sb)
      if k > 0 then covered, kind, text = k, 'voll', string.format('Vollkasko (SB %d €)', i.sb) end
    end
  end
  local voucher = math.min(c.voucher or 0, cost - covered)
  return { gross = cost, covered = covered, voucher = voucher, pay = cost - covered - voucher, kind = kind, text = text }
end
function M.commit(q)
  local i, c = ins(), club()
  if q.voucher and q.voucher > 0 then c.voucher = c.voucher - q.voucher end
  if q.covered > 0 then
    note(q.kind or 'voll', 'Reparatur', q.gross, q.covered, q.text)
    if q.kind == 'voll' then sfDown(1, 'Kaskoschaden') end
  end
  i.open = nil
end

function M.onDelivery(clean)
  local c, t = club(), tier()
  if t.mult == 0 then return end
  local add = (clean and 15 or 10) * t.mult
  c.pts, c.life = c.pts + add, c.life + add
end

-- --- the breakdowns --------------------------------------------------------------------------------------------------
local function pickFail()
  local sum = 0
  for _, f in pairs(M.FAIL) do sum = sum + (f.w or 0) end
  local r = math.random() * sum
  local keys = { 'tire', 'radiator', 'hose', 'oil' }
  for _, k in ipairs(keys) do r = r - M.FAIL[k].w; if r <= 0 then return k end end
  return 'tire'
end
function M.fail(kind)
  if st.fail or st.svc or not M.FAIL[kind] then return false end
  local v = api.truck()
  if not v then return false end
  v:queueLuaCommand(string.format('extensions.load("fernfahrer_wear") if fernfahrer_wear then fernfahrer_wear.fail(%q) end', kind))
  st.fail = { kind = kind, t = now() }
  if api.onFail then pcall(api.onFail, kind) end
  club().km = 0
  local f = M.FAIL[kind]
  api.notify(f.icon .. ' ' .. f.title .. '! ' .. f.text, 10)
  api.message(f.text, 'Bordcomputer')
  log('I', 'fernfahrer', 'breakdown: ' .. kind)
  return true
end
-- (the office's "Ereignis testen")
function M.forceFail(kind)
  if kind == 'any' then kind = pickFail() end
  if st.fail or st.svc then api.notify('Es läuft schon eine Panne.', 4); return end
  M.fail(kind)
end
function M.onTemp(water, oil)
  st.water, st.oil = water, oil
  local t = now()
  if ((water or 0) > 112 or (oil or 0) > 135) and t - (st.hotT or -99) > 40 then
    st.hotT = t
    api.notify(string.format('🌡 Motor überhitzt (%d °C)! Sofort anhalten!', math.floor(math.max(water or 0, oil or 0))), 7)
  end
end

-- --- the call ----------------------------------------------------------------------------------------------------------
local function priceOf(kind)
  local t, i = tier(), ins()
  local f = M.FAIL[kind] or M.FAIL.recover
  local part = f.part * (1 - t.parts)
  local cover = 0
  if part > 150 and (i.plan == 'teil' or i.plan == 'voll') and kind ~= 'recover' then cover = part - 150 end
  local fee = api.loaner() and math.min(t.fee, 150) or t.fee
  return fee, round(part - cover, 10), cover
end
function M.request()
  if st.svc then api.notify('Der Pannendienst ist schon unterwegs.', 4); return end
  local v = api.truck()
  if not v then return end
  if api.speed(v) > 3 then api.notify('Erst anhalten, dann den Pannendienst rufen.', 4); return end
  local kind = st.fail and st.fail.kind or 'recover'
  local fee, part, cover = priceOf(kind)
  local total = fee + part
  if api.money() < total then api.notify('Der Pannendienst kostet ' .. api.moneyText(total) .. ' – nicht genug Geld.', 6); return end
  local t = tier()
  st.svc = { stage = 'wait', at = now() + t.wait, kind = kind, fee = fee, part = part, cover = cover, total = total, pos = vec3(v:getPosition()), tries = 0 }
  local mins = t.wait < 10 and 'gleich' or string.format('in etwa %d Sekunden', t.wait)
  api.notify(string.format('📞 %s: Der Pannendienst fährt %s los. Bleib beim Fahrzeug.', M.SHORT, mins), 7)
  api.message(string.format('Einsatz angenommen: %s. Kosten für dich: %s.', (M.FAIL[kind] or M.FAIL.recover).title, total > 0 and api.moneyText(total) or 'keine'), M.SHORT .. ' Leitstelle')
end
local function finish()
  local s = st.svc
  local c = club()
  st.svc, st.fail, st.water, st.oil = nil, nil, nil, nil
  api.repair(s.total, (M.FAIL[s.kind] or M.FAIL.recover).title, function()
    c.rescues = (c.rescues or 0) + 1
    if s.cover > 0 then note('teil', 'Panne: ' .. (M.FAIL[s.kind] or M.FAIL.recover).title, s.part + s.cover, s.cover, 'Kasko übernimmt die Teile (SB 150 €).') end
    api.notify(string.format('🛠 Repariert%s. Gute Fahrt!', s.total > 0 and (' · ' .. api.moneyText(-s.total)) or ' – auf Kosten des Clubs'), 7)
    accidents.serviceLeave()
    api.save()
  end)
end

function M.tick(dt)
  if not api or not S() then return end
  local t = now()
  if t - (st.dayT or 0) > 4 then st.dayT = t; pcall(daily) end
  accidents.serviceTick(api.actx, dt)
  local v = api.truck()
  -- the road wears on
  if v and not st.fail and not st.svc and api.canFail() and S().settings.breakdowns ~= false then
    local sp = api.speed(v)
    if sp > 8 then
      st.km = st.km + sp * dt / 1000
      if st.km >= 1 then
        local c = club()
        c.km = (c.km or 0) + 1
        st.km = st.km - 1
        if c.km > M.MIN_GAP_KM and math.random() < 1 / M.RATE_KM then M.fail(pickFail()) end
      end
    end
  end
  local s = st.svc
  if not s then return end
  if not v then return end
  local away = vec3(v:getPosition()):distance(s.pos)
  if away > M.AWAY_M then
    accidents.serviceCancel()
    st.svc = nil
    api.pay('Pannendienst', -M.CANCEL_FEE, 'Anfahrt storniert')
    api.notify(string.format('Einsatz abgebrochen, du bist weggefahren · %s', api.moneyText(-M.CANCEL_FEE)), 6)
    return
  end
  if s.stage == 'wait' and t >= s.at then
    if accidents.serviceStart(api.actx) then
      s.stage = 'coming'
    else
      s.tries = s.tries + 1
      s.at = t + 4
      -- (no car to be had: he comes on foot, so to speak)
      if s.tries >= 6 then s.stage, s.t0, s.dur = 'work', t, (M.FAIL[s.kind] or M.FAIL.recover).work end
    end
  elseif s.stage == 'coming' then
    local state = accidents.serviceState()
    if state == 'there' or state == nil then
      s.stage, s.t0, s.dur = 'work', t, (M.FAIL[s.kind] or M.FAIL.recover).work
      api.message('Bin da, schaue es mir an. Das dauert einen Moment.', M.SHORT .. ' Pannenhelfer')
    end
  elseif s.stage == 'work' and t - s.t0 >= s.dur then
    finish()
  end
end

function M.hud()
  local out = {}
  if st.fail and not st.svc then
    local f = M.FAIL[st.fail.kind]
    out.breakdown = { icon = f.icon, title = f.title, text = f.text, water = st.water and math.floor(st.water) or nil }
  end
  local s = st.svc
  if s then
    local f = M.FAIL[s.kind] or M.FAIL.recover
    local x = { title = f.title, cost = s.total }
    if s.stage == 'wait' then
      x.text, x.left = 'Pannendienst alarmiert', math.max(0, math.ceil(s.at - now()))
    elseif s.stage == 'coming' then
      local _, d = accidents.serviceState()
      x.text, x.dist = 'Pannendienst kommt', d and math.floor(d / 10 + 0.5) * 10 or nil
    else
      x.text = 'Pannenhelfer arbeitet'
      x.pct = math.min(100, math.floor((now() - s.t0) / s.dur * 100))
      x.left = math.max(0, math.ceil(s.dur - (now() - s.t0)))
    end
    out.service = x
  end
  return out
end

-- --- the office --------------------------------------------------------------------------------------------------------
function M.view()
  local c, i = club(), ins()
  local cur, nxt = M.STATUS[1], nil
  for k, x in ipairs(M.STATUS) do if c.life >= x[1] then cur = x; nxt = M.STATUS[k + 1] end end
  local tiers = {}
  for k = 0, 3 do local t = M.TIERS[k]; tiers[#tiers + 1] = { id = t.id, name = t.name, perDay = t.perDay, lines = t.lines } end
  local plans = {}
  for _, p in ipairs(M.PLANS) do
    plans[#plans + 1] = { id = p.id, name = p.name, sub = p.sub, lines = p.lines, perDay = M.premium(p.id, i.sb, i.sf) }
  end
  local rewards = {}
  for _, r in ipairs(M.REWARDS) do rewards[#rewards + 1] = { id = r.id, cost = r.cost, icon = r.icon, name = r.name, sub = r.sub, can = c.pts >= r.cost } end
  local sbs = {}
  for _, o in ipairs(M.SB_OPTS) do sbs[#sbs + 1] = { v = o[1], perDay = M.premium('voll', o[1], i.sf) } end
  return {
    name = M.NAME, short = M.SHORT, insurer = M.INSURER,
    tier = c.tier, tiers = tiers, pts = c.pts, life = c.life, no = c.no, rescues = c.rescues or 0, voucher = c.voucher or 0, sfSafe = c.sfSafe or 0,
    status = cur[2], nextStatus = nxt and nxt[2] or nil, nextAt = nxt and nxt[1] or nil,
    statusPct = nxt and math.floor((c.life - cur[1]) / (nxt[1] - cur[1]) * 100) or 100,
    rewards = rewards, plan = i.plan, nextPlan = i.next, plans = plans, sb = i.sb, sbs = sbs, sf = i.sf, sfMax = M.SF_MAX,
    sfPct = math.floor(sfFactor(i.sf) * 100 + 0.5), cleanDays = i.clean or 0, sfDays = M.SF_DAYS,
    open = i.open and { case = i.open.case, fault = i.open.fault, void = i.open.void } or nil,
    history = i.history, perDay = M.premium(i.plan, i.sb, i.sf) + (M.TIERS[c.tier] or M.TIERS[0]).perDay,
  }
end
function M.act(id, arg)
  local c, i = club(), ins()
  if id == 'tier' then
    local n = tonumber(arg)
    if not M.TIERS[n] or n == c.tier then return end
    c.tier = n
    api.notify(n == 0 and 'Du bist aus dem Club ausgetreten.' or string.format('🟡 Willkommen im %s: Mitgliedschaft %s.', M.NAME, M.TIERS[n].name), 6)
  elseif id == 'plan' then
    if not M.PLAN_RANK[arg] or arg == i.plan and not i.next then return end
    -- (more cover only from tomorrow: no comprehensive cover for the dent that is already there)
    if M.PLAN_RANK[arg] > M.PLAN_RANK[i.plan] then
      i.next = arg
      api.notify('🛡 ' .. planOf(arg).name .. ' gilt ab dem nächsten Tag.', 6)
    else
      i.plan, i.next = arg, nil
      api.notify('🛡 Dein Schutz ist jetzt ' .. planOf(arg).name .. '.', 6)
    end
  elseif id == 'sb' then
    local n = tonumber(arg)
    for _, o in ipairs(M.SB_OPTS) do if o[1] == n then i.sb = n end end
  elseif id == 'reward' then
    for _, r in ipairs(M.REWARDS) do
      if r.id == arg then
        if c.pts < r.cost then api.notify('Dafür fehlen dir noch Punkte.', 4); return end
        c.pts = c.pts - r.cost
        if r.id == 'diesel' then api.pay('Club', 100, 'Diesel-Gutschein')
        elseif r.id == 'shop' then c.voucher = (c.voucher or 0) + 150
        elseif r.id == 'sfsafe' then c.sfSafe = (c.sfSafe or 0) + 1
        elseif r.id == 'coffee' then local inv = api.inv(); inv.coffee = math.min(api.invMax('coffee'), (inv.coffee or 0) + 4) end
        api.notify(r.icon .. ' ' .. r.name .. ' eingelöst.', 5)
      end
    end
  end
  api.save()
end

function M.reset() st = { km = 0 } end

return M
