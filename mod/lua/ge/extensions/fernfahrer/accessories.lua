-- Trucks of Earth: accessories for the cab. Bought in the office's online shop, delivered to the yard, fitted in the workshop (FernfahrerGarage.vue).
-- They are objects of our own held to the rigid nodes of the truck's cab, every frame: no part of the vehicle is touched, so it works on every truck,
-- those of other mods too. What hangs swings with the truck's motion, the dog nods, the cat waves. The positions are starting points; each cab is a little
-- different, so every piece can be moved by hand and stays where it was put, per truck.
-- M.attach(save table), M.render(vehicle, dt), and the views for the UI.
local M = {}
M.DIR = '/levels/beamng_earth/art/shapes/ffa/ff_acc_'
M.DELIVERY_S = 150          -- (real seconds from the order to the parcel at the yard)
M.NUDGE_MAX = 0.6

-- f: towards the windscreen, r: to the driver's right, u: up, from the driver's eyes
local MIRROR = { f = 0.72, r = 0.55, u = 0.3 }
-- (2026-11-09) what hangs is tied to the lower part of the ceiling right behind the windscreen; only the disco ball hangs from the roof, on a long thread, further back
local HEADER_F, HEADER_U, THREAD = 0.78, 0.46, 0.14
local function dash(r, f, u) return { f = f or 0.92, r = r, u = u or -0.46 } end
M.CATS = { { key = 'hang', name = 'Am Spiegel' }, { key = 'dash', name = 'Armaturenbrett' }, { key = 'cab', name = 'Scheibe & Kabine' }, { key = 'gadget', name = 'Geräte mit Funktion' }, { key = 'dirty', name = 'Unter der Ladentheke' } }
M.ITEMS = {
  { id = 'duft_tanne', name = 'Duftbaum Waldfrisch', cat = 'hang', price = 6, text = 'Tanne, der Klassiker. Schaukelt in jeder Kurve mit.', at = MIRROR, swing = 0.34 },
  { id = 'duft_kirsch', name = 'Duftbaum Kirsche', cat = 'hang', price = 6, text = 'Süß, rot und ein bisschen zu stark.', at = MIRROR, swing = 0.34 },
  { id = 'duft_vanille', name = 'Duftbaum Vanille', cat = 'hang', price = 6, text = 'Riecht nach Kuchen auf der A2.', at = MIRROR, swing = 0.34 },
  { id = 'wuerfel', name = 'Plüschwürfel', cat = 'hang', price = 19, text = 'Das Paar für den Spiegel. Muss einfach sein.', at = { f = 0.72, r = 0.72, u = 0.3 }, swing = 0.2 },
  { id = 'hufeisen', name = 'Glückshufeisen', cat = 'hang', price = 14, text = 'Für die Touren ohne Blitzer.', at = { f = 0.72, r = 0.38, u = 0.3 }, swing = 0.22 },
  { id = 'kette', name = 'Holzperlenkette', cat = 'hang', price = 12, text = 'Vom Flohmarkt in Rimini.', at = { f = 0.72, r = 0.46, u = 0.3 }, swing = 0.3 },
  { id = 'funkmikro', name = 'Funkgerät-Mikro', cat = 'hang', price = 35, text = 'Am Spiralkabel, immer griffbereit.', at = { f = 0.62, r = 0.36, u = -0.02 }, swing = 0.16 },
  { id = 'wackelhund', name = 'Wackelhund', cat = 'dash', price = 29, text = 'Nickt dir zu, egal wie schlecht du fährst.', at = dash(0.42), head = { shape = 'wackelhund_kopf', u = 0.095, y = 0.0, nod = true } },
  { id = 'glueckskatze', name = 'Winkekatze', cat = 'dash', price = 24, text = 'Winkt das Geld in die Kasse.', at = dash(0.62), arm = { shape = 'glueckskatze_arm', r = 0.043, f = -0.012, u = 0.075 } },
  { id = 'minitruck', name = 'Modell-Sattelzug', cat = 'dash', price = 39, text = 'Dein Lkw, nur in klein.', at = dash(0.78) },
  { id = 'kompass', name = 'Kugelkompass', cat = 'dash', price = 22, text = 'Wenn das Navi mal wieder Pause macht.', at = dash(0.26) },
  { id = 'tasse', name = 'Kaffeebecher', cat = 'dash', price = 9, text = 'Blau, unzerstörbar, nie ganz leer.', at = dash(0.95, 0.84) },
  { id = 'thermos', name = 'Thermoskanne', cat = 'dash', price = 18, text = 'Hält den Kaffee bis zur Grenze heiß.', at = dash(1.08, 0.8) },
  { id = 'fotorahmen', name = 'Familienfoto', cat = 'dash', price = 15, text = 'Damit du weißt, wofür du fährst.', at = dash(0.34) },
  { id = 'uhr', name = 'Analoguhr', cat = 'dash', price = 27, text = 'Chrom, tickt leise.', at = dash(0.5) },
  { id = 'chefschild', name = 'Leuchtschild CHEF', cat = 'dash', price = 49, text = 'Leuchtet orange. Damit es alle wissen.', at = dash(0.56, 1.02, -0.42) },
  { id = 'teddy', name = 'Teddy', cat = 'dash', price = 21, text = 'Sitzt, schweigt, hört zu.', at = dash(0.88) },
  { id = 'gartenzwerg', name = 'Gartenzwerg', cat = 'dash', price = 17, text = 'Der Beifahrer, der nie meckert.', at = dash(1.0) },
  { id = 'kaktus', name = 'Kaktus', cat = 'dash', price = 11, text = 'Die einzige Pflanze, die Lkw-Leben aushält.', at = dash(0.7) },
  { id = 'tischflagge', name = 'Tischflagge', cat = 'dash', price = 8, text = 'Kleine Fahne für das Armaturenbrett.', at = dash(0.18) },
  { id = 'gardine_rot', name = 'Gardine Rot mit Fransen', cat = 'cab', price = 59, text = 'Die echte Fernfahrer-Gardine oben an der Scheibe.', at = { f = 0.86, r = 0.55, u = 0.47 } },
  { id = 'gardine_blau', name = 'Gardine Blau mit Fransen', cat = 'cab', price = 59, text = 'Dasselbe, aber ruhiger.', at = { f = 0.86, r = 0.55, u = 0.47 } },
  { id = 'wimpelkette', name = 'Wimpelkette', cat = 'cab', price = 16, text = 'Quer durch die Kabine, immer etwas Feier.', at = { f = 0.5, r = 0.55, u = 0.46 } },
  { id = 'bilderrahmen', name = 'Bilderrahmen', cat = 'cab', price = 39, text = 'Für die Kabinenwand. Das Foto suchst du dir aus deiner BeamNG-Galerie aus.', at = { f = 0.05, r = 0, u = 0.12 }, wall = true, pic = 'bild' },
  { id = 'ledleiste', name = 'LED-Leiste Blau', cat = 'cab', price = 69, text = 'Stimmungslicht über dem Armaturenbrett.', at = { f = 0.86, r = 0.55, u = -0.2 } },
  -- (2026-11-09) things that do something: a button each in the cab's panel on the HUD once fitted
  { id = 'popcorn', name = 'Popcornmaschine', cat = 'gadget', price = 89, text = 'Anklicken: Es knallt, es duftet, die Müdigkeit geht etwas zurück.', at = dash(0.84), gadget = { icon = '🍿', label = 'Popcorn', run = 14, cool = 300 } },
  { id = 'display', name = 'Radio-Display', cat = 'gadget', price = 129, text = 'Zeigt, was im Radio läuft. Anklicken wechselt zu Uhr oder Tempo.', at = dash(0.44, 0.95, -0.43), gadget = { icon = '📟', label = 'Display', toggle = true } },
  { id = 'kaffeem', name = 'Kaffeemaschine', cat = 'gadget', price = 74, text = 'Anklicken: frischer Kaffee in deiner Kabine, alle paar Minuten.', at = dash(1.06, 0.84), gadget = { icon = '☕', label = 'Brühen', run = 9, cool = 240 } },
  { id = 'venti', name = 'Tischventilator', cat = 'gadget', price = 34, text = 'An: Die Flügel drehen sich und du wirst langsamer müde.', at = dash(0.28), head = { shape = 'venti_rad', u = 0.17, y = 0.04, spin = 34, axis = 'f' }, gadget = { icon = '🌀', label = 'Lüfter', toggle = true } },
  { id = 'knopf', name = 'Der rote Knopf', cat = 'gadget', price = 19, text = 'Was er macht? Drück ihn.', at = dash(0.6, 0.86), gadget = { icon = '🔴', label = 'Knopf', sound = { 'gag_furz', 'gag_muh', 'gag_tusch', 'gag_applaus' }, cool = 1 } },
  { id = 'disko', name = 'Diskokugel', cat = 'gadget', price = 59, text = 'An: Sie dreht sich und die Kabine leuchtet bunt.', at = { f = 0.5, r = 0.55, u = 0.34 }, roof = true, swing = 0.7, head = { shape = 'disko_k', u = -0.09, y = 0, spin = 2.2, axis = 'u' }, gadget = { icon = '🪩', label = 'Disko', toggle = true } },
  -- (2026-11-09) under the counter
  { id = 'joints', name = 'Zwei Joints am Faden', cat = 'dirty', price = 14, text = 'Reine Deko, Herr Wachtmeister. Ehrlich.', at = { f = 0.72, r = 0.6, u = 0.3 }, swing = 0.17 },
  { id = 'hanfbaum', name = 'Duftbaum Hanfblatt', cat = 'dirty', price = 7, text = 'Duftrichtung: Klassenfahrt 2003.', at = { f = 0.72, r = 0.5, u = 0.3 }, swing = 0.3 },
  { id = 'handsch', name = 'Plüsch-Handschellen', cat = 'dirty', price = 18, text = 'Für lange Nächte auf dem Autohof. Frag nicht.', at = { f = 0.72, r = 0.68, u = 0.3 }, swing = 0.13 },
  { id = 'bh', name = 'Spitzen-BH', cat = 'dirty', price = 25, text = 'Hing schon im Lkw, als du ihn gekauft hast.', at = { f = 0.72, r = 0.42, u = 0.3 }, swing = 0.15 },
  { id = 'unterhose', name = 'Glücksunterhose', cat = 'dirty', price = 5, text = 'Seit 2011 ungewaschen. Hat noch nie versagt.', at = { f = 0.72, r = 0.76, u = 0.3 }, swing = 0.2 },
  { id = 'totenkopf', name = 'Totenkopf', cat = 'dirty', price = 23, text = 'Mit roten Augen, die leuchten. Für die Nachtschicht.', at = { f = 0.72, r = 0.34, u = 0.3 }, swing = 0.16 },
  { id = 'knoblauch', name = 'Knoblauchzopf', cat = 'dirty', price = 9, text = 'Gegen Vampire und Disponenten.', at = { f = 0.72, r = 0.84, u = 0.3 }, swing = 0.26 },
  { id = 'teddyhigh', name = 'Teddy Kiffer', cat = 'dirty', price = 33, text = 'Rote Augen, Tüte in der Pfote. Hat die Ruhe weg.', at = dash(0.8) },
  { id = 'alien', name = 'Ali der Beifahrer', cat = 'dirty', price = 29, text = 'Kam wegen der Menschheit, blieb wegen des Grases.', at = dash(0.32) },
  { id = 'bong', name = 'Zierglas', cat = 'dirty', price = 45, text = 'Für Blumen. Sehr kleine Blumen.', at = dash(1.02, 0.84) },
  { id = 'ascher', name = 'Voller Aschenbecher', cat = 'dirty', price = 8, text = 'Einer glimmt noch. Riecht auch im Shop schon.', at = dash(0.2, 0.82) },
  { id = 'flasche', name = 'Apfelschorle', cat = 'dirty', price = 3, text = 'Der nächste Rastplatz war zu weit. Nicht trinken.', at = dash(1.12, 0.8) },
  { id = 'zwergfinger', name = 'Stinkefinger-Zwerg', cat = 'dirty', price = 22, text = 'Grüßt alle, die rechts überholen.', at = dash(0.62) },
  { id = 'hula', name = 'Hula-Tänzerin', cat = 'dirty', price = 31, text = 'Die Hüften kennen jedes Schlagloch.', at = dash(0.46), head = { shape = 'hula_oben', u = 0.075, y = 0.0, sway = true } },
  { id = 'banane', name = 'Wackelbanane', cat = 'dirty', price = 16, text = 'Federt bei jeder Bodenwelle. Mehr sagen wir nicht.', at = dash(0.56), head = { shape = 'banane_ob', u = 0.074, y = 0.0, wobble = true } },
  { id = 'dosen', name = 'Dosenpyramide', cat = 'dirty', price = 12, text = 'Alle leer. Der Beweis eines guten Abends.', at = dash(0.92, 0.84) },
  { id = 'schwein', name = 'Sparschwein Bußgeld', cat = 'dirty', price = 15, text = 'Füllt sich schneller, als du denkst.', at = dash(0.72) },
  { id = 'ente', name = 'Coole Ente', cat = 'dirty', price = 13, text = 'Sonnenbrille auf, keine Fragen.', at = dash(0.38) },
  { id = 'keinbock', name = 'Leuchtschild KEIN BOCK', cat = 'dirty', price = 39, text = 'Sagt dem Disponenten alles.', at = dash(0.66, 1.02, -0.42) },
  { id = 'pizza', name = 'Pizzakarton vom Dienstag', cat = 'dirty', price = 6, text = 'Wir verkaufen ihn wie gefunden.', at = dash(0.86, 0.82) },
  { id = 'schimmel', name = 'Tasse mit Eigenleben', cat = 'dirty', price = 7, text = 'Seit März nicht gespült. Hat jetzt einen Namen.', at = dash(0.98, 0.84) },
  { id = 'aluhut', name = 'Aluhut', cat = 'dirty', price = 11, text = 'Schützt vor Blitzern. Sagt jedenfalls der Verkäufer.', at = dash(0.24) },
}
local BY = {}
for _, it in ipairs(M.ITEMS) do BY[it.id] = it end
M.BY = BY

local st, built, builtSig = nil, {}, nil
local builtVeh, swing = nil, {}
local lastVel, n = nil, 0
local eyeAt = 0
local inDriver, ctx, G, spinA, disco = false, nil, {}, {}, nil
function M.setCtx(c) ctx = c end
-- what can be pressed in this truck, for the cab's panel on the HUD
function M.hudGadgets(truck)
  if not truck or not truck.acc then return nil end
  local out, t = {}, os.clock()
  for _, it in ipairs(M.ITEMS) do
    if it.gadget and truck.acc[it.id] then
      local g = G[it.id] or {}
      out[#out + 1] = { id = it.id, icon = it.gadget.icon, label = it.gadget.label, on = (g.on or (g.runTo and t < g.runTo)) and true or nil, wait = (g.coolTo and t < g.coolTo and not (g.runTo and t < g.runTo)) and math.ceil(g.coolTo - t) or nil }
    end
  end
  return #out > 0 and out or nil
end
function M.fanOn() return G.venti and G.venti.on or false end
local DISPLAY = { 'radio', 'uhr', 'tempo', false }
function M.use(truck, id)
  local it = BY[id]
  if not it or not it.gadget or not truck or not truck.acc or not truck.acc[id] or not ctx then return end
  local g, t, d = G[id] or {}, os.clock(), it.gadget
  G[id] = g
  if id == 'display' then
    g.i = ((g.i or 4) % #DISPLAY) + 1
    g.on = DISPLAY[g.i] and true or false
    return
  end
  if d.toggle then g.on = not g.on; if id == 'venti' and g.on then ctx.notify('🌀 Der Lüfter läuft. Du wirst langsamer müde.', 4) end; return end
  if g.coolTo and t < g.coolTo then ctx.notify(string.format('%s Geht in %d s wieder.', d.icon, math.ceil(g.coolTo - t)), 3); return end
  if d.sound then ctx.play(d.sound[math.random(#d.sound)], 1); g.coolTo = t + d.cool; return end
  g.runTo, g.coolTo, g.done = t + d.run, t + d.cool, false
  ctx.play(id == 'popcorn' and 'gad_popcorn' or 'gad_kaffee', 0.9)
end
local function gadgetTick()
  local t = os.clock()
  for id, g in pairs(G) do
    if g.runTo and t >= g.runTo and not g.done then
      g.done = true
      if ctx and id == 'popcorn' then ctx.tired(-0.08); ctx.notify('🍿 Popcorn fertig. Schmeckt nach Kino, die Müdigkeit geht etwas zurück.', 6)
      elseif ctx and id == 'kaffeem' then ctx.cab('coffee', 1); ctx.notify('☕ Frischer Kaffee steht bereit. Du findest ihn in der Kabine.', 6) end
    end
  end
end
local function discoOff() if disco then pcall(function() disco:delete() end); disco = nil end end

function M.attach(t)
  st = t
  st.inv, st.orders, st.eyeFix = st.inv or {}, st.orders or {}, st.eyeFix or {}
  st.eye = nil
end

-- deliveries --------------------------------------------------------------------------------------------------------
-- (at the yard when it arrives: said once; true when something came)
function M.tick()
  if not st or #st.orders == 0 then return nil end
  local got
  for i = #st.orders, 1, -1 do
    local o = st.orders[i]
    if os.time() >= o.at then
      st.inv[o.id] = (st.inv[o.id] or 0) + 1
      got = BY[o.id] and BY[o.id].name or o.id
      table.remove(st.orders, i)
    end
  end
  return got
end
-- (2026-11-10: 1:30 to 2:00 minutes, not 2:30)
function M.order(id) local it = BY[id]; if it then st.orders[#st.orders + 1] = { id = id, at = os.time() + 90 + math.random(0, 30) } end; return it end

-- views -------------------------------------------------------------------------------------------------------------
-- (2026-11-09: in the loaner only what can simply be hung up; it goes back to the hirer as it came)
function M.allowed(truck, it) return not (truck and truck.loaner) or (it.swing and not it.roof and true or false) end
local function card(it, truck)
  local fitted = truck and truck.acc and truck.acc[it.id]
  return { id = it.id, name = it.name, cat = it.cat, price = it.price, text = it.text, thumb = '/ui/ui-vue/mods/fernfahrer/acc/' .. it.id .. '.jpg',
    stock = st.inv[it.id] or 0, fitted = fitted and true or nil, locked = (not M.allowed(truck, it)) or nil }
end
function M.shopView(truck)
  local list, onWay = {}, {}
  for _, it in ipairs(M.ITEMS) do list[#list + 1] = card(it, truck) end
  for _, o in ipairs(st.orders) do
    local it = BY[o.id]
    if it then onWay[#onWay + 1] = { id = o.id, name = it.name, left = math.max(0, o.at - os.time()) } end
  end
  return { cats = M.CATS, items = list, onWay = onWay, delivery = M.DELIVERY_S }
end
function M.garageView(truck)
  local list = {}
  for _, it in ipairs(M.ITEMS) do
    local c = card(it, truck)
    if c.fitted then local a = truck.acc[it.id]; c.adj = { f = a.f or 0, r = a.r or 0, u = a.u or 0, l = a.l or 0, y = math.floor(math.deg(a.yaw or 0) + 0.5) }; c.dash = M.isDash(it) or nil; c.hung = M.hung(it) or nil; c.pic = it.pic and true or nil; c.photo = a.photo end
    list[#list + 1] = c
  end
  return { cats = M.CATS, items = list, truck = truck and ((truck.brand or '') .. ' ' .. (truck.modelName or '')) or nil, loaner = truck and truck.loaner or nil }
end

function M.fit(truck, id)
  if not truck or not BY[id] then return false end
  truck.acc = truck.acc or {}
  if truck.acc[id] or (st.inv[id] or 0) < 1 or not M.allowed(truck, BY[id]) then return false end
  st.inv[id] = st.inv[id] - 1
  -- (a truck's dashboard is one surface: what was placed there last says where the next one goes)
  local a, it, base = { f = 0, r = 0, u = 0 }, BY[id], truck.accBase
  if base and M.isDash(it) then a.f, a.u = base.f - it.at.f, base.u - it.at.u end
  if id == 'venti' then a.yaw = M.faceYaw(it, a) end
  if it.wall then a.yaw = -math.pi / 2 * (M.last and M.last.flip or 1) end
  truck.acc[id] = a
  builtSig = nil
  return true
end
function M.unfit(truck, id)
  if not truck or not truck.acc or not truck.acc[id] then return false end
  truck.acc[id] = nil
  st.inv[id] = (st.inv[id] or 0) + 1
  builtSig = nil
  return true
end
function M.isDash(it) return it and not it.swing and it.at.u < 0 and it.at.u > -0.6 and it.id ~= 'funkmikro' and it.id ~= 'ledleiste' end
-- (this piece's height and depth for everything on the dashboard)
function M.alignDash(truck, id)
  local a, it = truck and truck.acc and truck.acc[id], BY[id]
  if not a or not M.isDash(it) then return end
  local f0, u0 = it.at.f + (a.f or 0), it.at.u + (a.u or 0)
  truck.accBase = { f = f0, u = u0 }
  for o, b in pairs(truck.acc) do if o ~= id and M.isDash(BY[o]) then b.f, b.u = f0 - BY[o].at.f, u0 - BY[o].at.u end end
end
-- (the angle that turns a thing on the dashboard to the driver: seen from it the driver is back and to the side)
function M.faceYaw(it, a)
  local flip = M.last and M.last.flip or 1
  return math.atan2(-(it.at.r * flip + (a.r or 0)), math.max(0.1, it.at.f + (a.f or 0)))
end
function M.face(truck, id)
  local a, it = truck and truck.acc and truck.acc[id], BY[id]
  if a and it then a.yaw = M.faceYaw(it, a) end
end
function M.nudge(truck, id, axis, d)
  local a = truck and truck.acc and truck.acc[id]
  if not a then return end
  if axis == 'y' then a.yaw = ((a.yaw or 0) + math.rad(tonumber(d) or 0) + math.pi) % (2 * math.pi) - math.pi; return end
  if axis == 'l' then a.l = math.max(-0.6, math.min(0.6, (a.l or 0) + (tonumber(d) or 0))); return end
  if axis ~= 'f' and axis ~= 'r' and axis ~= 'u' then return end
  a[axis] = math.max(-M.NUDGE_MAX, math.min(M.NUDGE_MAX, (a[axis] or 0) + (tonumber(d) or 0)))
  if M.isDash(BY[id]) then truck.accBase = { f = BY[id].at.f + (a.f or 0), u = BY[id].at.u + (a.u or 0) } end
end
-- (2026-11-09) the picture frame: any photo of the game's screenshot folder
M.PHOTO_EMPTY = 'levels/beamng_earth/art/shapes/ffa/ff_foto_leer.png'
function M.photos()
  local all = {}
  for _, ext in ipairs({ '*.png', '*.jpg' }) do
    local ok, list = pcall(function() return FS:findFiles('/screenshots/', ext, -1, true, false) end)
    if ok and list then for _, f in ipairs(list) do all[#all + 1] = { f = f, t = (FS:stat(f) or {}).modtime or 0 } end end
  end
  table.sort(all, function(a, b) if a.t ~= b.t then return a.t > b.t end; return a.f > b.f end)
  local out = {}
  for i = 1, math.min(40, #all) do out[i] = all[i].f end
  return out
end
function M.choosePhoto(truck, file)
  local a = truck and truck.acc and truck.acc.bilderrahmen
  if a and type(file) == 'string' and file:sub(1, 13) == '/screenshots/' and FS:fileExists(file) then a.photo = file end
end
local function showPhoto(file)
  local want = file or false
  if M.photoNow == want then return end
  local mat = scenetree.findObject('ff_acc_foto')
  if not mat then return end
  M.photoNow = want
  local path = (file and FS:fileExists(file)) and file or M.PHOTO_EMPTY
  pcall(function() mat:setField('baseColorMap', 0, path); mat:reload() end)
end
-- (for the pictures of the cab: what is fitted, and where it is now)
function M.spots() local out = {}; for id, b in pairs(built) do if b.lastP then out[#out + 1] = id end end; return out end
function M.spotOf(id) local b = built[id]; return b and b.lastP end
-- (taking a truck off the fleet: what is in it goes back on the shelf)
function M.strip(truck)
  if not truck or not truck.acc then return end
  for id in pairs(truck.acc) do st.inv[id] = (st.inv[id] or 0) + 1 end
  truck.acc = nil
end

-- in the cab --------------------------------------------------------------------------------------------------------
local function clear()
  for _, b in pairs(built) do
    for _, o in ipairs(b.objs) do pcall(function() o:delete() end) end
  end
  built, builtVeh, builtSig, swing = {}, nil, nil, {}
  M.frame = nil
  discoOff()
  if M.popLight then pcall(function() M.popLight:delete() end); M.popLight = nil end
end
M.clear = clear

local function make(shape)
  local o = createObject('TSStatic')
  if not o then return nil end
  o.useInstanceRenderData = false
  o:setField('shapeName', 0, M.DIR .. shape .. '.dae')
  o:setField('collisionType', 0, 'None')
  o:setField('decalType', 0, 'None')
  -- (2026-11-09: as the game's own traffic lights do with what moves: without it FSR and TAA smear a thing that travels with the camera, it was seen double in curves)
  o:setField('dynamic', 0, 'true')
  o.canSave = false
  n = n + 1
  o:registerObject('ff_acc_' .. n)
  return o
end

-- (2026-11-09) a truck has no mirror in the middle of the windscreen: what hangs goes on a thread from the roof, over the middle of the cab
function M.hung(it) return it.roof or (it.swing and it.at.u > 0.2) end
local function signature(truck)
  local s = {}
  for id in pairs(truck.acc or {}) do s[#s + 1] = id end
  table.sort(s)
  return table.concat(s, ',')
end
local function rot(v, axis, a)
  local c, s = math.cos(a), math.sin(a)
  return v * c + axis:cross(v) * s + axis * axis:dot(v) * (1 - c)
end
-- (2026-11-09) The cab rides on its own springs above the frame, and the camera's node is a soft one: it leans with the driver when the truck brakes or accelerates. Whatever was held by
-- it swayed about in the cab. Now the average of many rigid nodes of the cab carries everything: the same points of the cab, and nothing that moves on its own in them.
local SOFT = { 'door', 'seat', 'mirror', 'wiper', 'steer', 'pedal', 'hood', 'driver', 'head', 'dsh', 'shift', 'window', 'hatch', 'antenna', 'visor', 'bullbar', 'light' }
local function isRigid(nd)
  local s = tostring(nd.name or ''):lower()
  if type(nd.group) == 'table' then for _, x in pairs(nd.group) do s = s .. ' ' .. tostring(x):lower() end elseif nd.group then s = s .. ' ' .. tostring(nd.group):lower() end
  for _, b in ipairs(SOFT) do if s:find(b, 1, true) then return false end end
  return true
end
local function restMean(nodes, list)
  local x, y, z = 0, 0, 0
  for i = 1, #list do local p = nodes[list[i]].pos; x, y, z = x + p.x, y + p.y, z + p.z end
  return vec3(x / #list, y / #list, z / #list)
end
local function liveMean(veh, list)
  local x, y, z = 0, 0, 0
  for i = 1, #list do local a, b, c = veh:getNodeAbsPositionXYZ(list[i]); x, y, z = x + a, y + b, z + c end
  return vec3(x / #list, y / #list, z / #list)
end
local function axes(front, back, right, left)
  local e1 = (front - back):normalized()
  local e3 = e1:cross(right - left):normalized()
  return e1, e3:cross(e1), e3
end
-- (2026-11-09: a crash tears nodes off; the average of them then went elsewhere and everything in the cab with it. Nodes that have moved against the cab are left out from then on, until the truck is whole again.)
function M.forgetFrame() M.frame, M.dropped, M.A0orig = nil, nil, nil end
local function buildFrame(veh, camNode)
  local vid = veh:getID()
  if M.frameVeh ~= vid then M.frameVeh, M.dropped, M.A0orig = vid, nil, nil end
  M.frame = { veh = vid, node = camNode }
  local ok, data = pcall(function() return core_vehicle_manager.getVehicleData(vid) end)
  local nodes = ok and data and data.vdata and data.vdata.nodes
  local c0 = nodes and nodes[camNode] and nodes[camNode].pos
  if not c0 then return end
  -- (in the vehicle's own coordinates, at rest: forward is -y, right is -x)
  local list = {}
  for cid, nd in pairs(nodes) do
    if type(cid) == 'number' and cid ~= camNode and nd.pos and isRigid(nd) and not (M.dropped and M.dropped[cid]) then
      local f, r, u = c0.y - nd.pos.y, c0.x - nd.pos.x, nd.pos.z - c0.z
      local h = math.sqrt(f * f + r * r)
      if h > 0.2 and h < 1.8 and u > -0.75 and u < 1.5 then list[#list + 1] = { cid = cid, f = f, r = r, u = u } end
    end
  end
  if #list < 12 then return end
  table.sort(list, function(a, b) return a.cid < b.cid end)
  local pick, stepN = {}, math.max(1, math.floor(#list / 48))
  for i = 1, #list, stepN do pick[#pick + 1] = list[i] end
  local function split(key)
    local v = {}
    for i, e in ipairs(pick) do v[i] = e[key] end
    table.sort(v)
    local mid, hi, lo = v[math.ceil(#v / 2)], {}, {}
    for _, e in ipairs(pick) do if e[key] > mid then hi[#hi + 1] = e.cid else lo[#lo + 1] = e.cid end end
    return hi, lo
  end
  local front, back = split('f')
  local right, left = split('r')
  if #front < 3 or #back < 3 or #right < 3 or #left < 3 then return end
  local all = {}
  for i, e in ipairs(pick) do all[i] = e.cid end
  local fc, bc, rc, lc, A0 = restMean(nodes, front), restMean(nodes, back), restMean(nodes, right), restMean(nodes, left), restMean(nodes, all)
  if (fc - bc):length() < 0.35 or (rc - lc):length() < 0.5 then return end
  local e1, e2, e3 = axes(fc, bc, rc, lc)
  local F0, R0, U0 = vec3(0, -1, 0), vec3(-1, 0, 0), vec3(0, 0, 1)
  local fr = M.frame
  fr.front, fr.back, fr.right, fr.left, fr.all = front, back, right, left, all
  fr.F, fr.R, fr.U = { F0:dot(e1), F0:dot(e2), F0:dot(e3) }, { R0:dot(e1), R0:dot(e2), R0:dot(e3) }, { U0:dot(e1), U0:dot(e2), U0:dot(e3) }
  local toCam = vec3(c0.x, c0.y, c0.z) - A0
  fr.cam = { f = toCam:dot(F0), r = toCam:dot(R0), u = toCam:dot(U0) }
  fr.rd = {}
  for _, e in ipairs(pick) do fr.rd[e.cid] = math.sqrt(e.f * e.f + e.r * e.r + e.u * e.u) end
  -- (the anchor stays where it was first, whichever nodes are left: seen from it everything was placed)
  M.A0orig = M.A0orig or A0
  local shift = M.A0orig - A0
  fr.off = { f = shift:dot(F0), r = shift:dot(R0), u = shift:dot(U0) }
  fr.cam.f, fr.cam.r, fr.cam.u = fr.cam.f - fr.off.f, fr.cam.r - fr.off.r, fr.cam.u - fr.off.u
  M.camRest = fr.cam
  -- (2026-11-10) the vehicle's middle line (x = 0 at rest) against the same point: the passenger's seat is the driver's camera node mirrored over it
  fr.midR = A0.x - fr.off.r
  -- (where the roof and the middle of this cab are, against the same point)
  local minR, maxR, topU = 1e9, -1e9, -1e9
  for _, e in ipairs(list) do
    if math.abs(e.f) < 1.3 then minR, maxR, topU = math.min(minR, e.r), math.max(maxR, e.r), math.max(topU, e.u) end
  end
  if maxR - minR > 1 and topU > 0.15 then
    local ar, au = c0.x - A0.x, A0.z - c0.z
    fr.centerR, fr.roofU = (minR + maxR) / 2 - ar, topU - au - 0.04
    fr.wallR, fr.wallL = maxR - ar - 0.1, minR - ar + 0.1
    fr.centerR, fr.roofU, fr.wallR, fr.wallL = fr.centerR - fr.off.r, fr.roofU - fr.off.u, fr.wallR - fr.off.r, fr.wallL - fr.off.r
  end
end
local function cabBasis(veh, camNode, F, R, U)
  local fr = M.frame
  if not fr or fr.veh ~= veh:getID() or fr.node ~= camNode then buildFrame(veh, camNode); fr = M.frame end
  if not fr.all then return F, R, U, nil end
  local tc = os.clock()
  if tc - (fr.checkT or 0) > 0.4 then
    fr.checkT = tc
    local cx, cy, cz, bad = veh:getNodeAbsPositionXYZ(camNode)
    for _, cid in ipairs(fr.all) do
      local x, y, z = veh:getNodeAbsPositionXYZ(cid)
      if math.abs(math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2 + (z - cz) ^ 2) - fr.rd[cid]) > 0.3 then M.dropped = M.dropped or {}; M.dropped[cid] = true; bad = true end
    end
    if bad then
      buildFrame(veh, camNode)
      fr = M.frame
      if not fr.all then return F, R, U, nil end
    end
  end
  local e1, e2, e3 = axes(liveMean(veh, fr.front), liveMean(veh, fr.back), liveMean(veh, fr.right), liveMean(veh, fr.left))
  local f, r, u = fr.F, fr.R, fr.U
  local Fa, Ra, Ua = e1 * f[1] + e2 * f[2] + e3 * f[3], e1 * r[1] + e2 * r[2] + e3 * r[3], e1 * u[1] + e2 * u[2] + e3 * u[3]
  return Fa, Ra, Ua, liveMean(veh, fr.all) + Fa * fr.off.f + Ra * fr.off.r + Ua * fr.off.u
end
local function place(o, p, dir, up)
  local q = quatFromDir(dir, up)
  o:setPosRot(p.x, p.y, p.z, q.x, q.y, q.z, q.w)
end

-- (2026-11-10) the passenger (fernfahrer/crew.lua) is held to the cab like everything in it - "sie springt die ganze Zeit hin und her": set apart from it, a
-- frame late and from the vehicle's position, she jumped about. M.rider: her figure; with it the cab's frame is worked out even without any accessories.
M.rider = nil
function M.render(veh, truck, dt)
  gadgetTick()
  if not veh or not truck or not truck.acc or next(truck.acc) == nil then
    if next(built) then clear() end
    if not (veh and M.rider) then return end
    truck = { model = (truck and truck.model) or 'truck', acc = {} }
  end
  local id = veh:getID()
  local sig = signature(truck)
  if id ~= builtVeh or sig ~= builtSig then
    clear()
    for iid in pairs(truck.acc) do
      local it = BY[iid]
      if it then
        local b = { it = it, objs = {} }
        local o = make(it.id)
        if o then b.body = o; b.objs[#b.objs + 1] = o end
        if it.head then b.head = make(it.head.shape); if b.head then b.objs[#b.objs + 1] = b.head end end
        if it.arm then b.arm = make(it.arm.shape); if b.arm then b.objs[#b.objs + 1] = b.arm end end
        if it.pic then b.pic = make(it.pic); if b.pic then b.objs[#b.objs + 1] = b.pic end end
        if M.hung(it) then b.thread = make('faden'); if b.thread then b.objs[#b.objs + 1] = b.thread end end
        if iid == 'popcorn' then b.kern = {}; for i = 1, 6 do local k = make('popcorn_k'); if k then b.kern[i] = k; b.objs[#b.objs + 1] = k end end end
        if iid == 'kaffeem' then b.stream = make('kaffee_strahl'); if b.stream then b.objs[#b.objs + 1] = b.stream end end
        built[iid] = b
      end
    end
    builtVeh, builtSig = id, sig
  end
  -- (the game's camera data can be gone for a moment, after a crash for instance: the node it had before)
  local camNode, rhd = core_camera.getDriverData(veh)
  if camNode then M.camNodeLast, M.rhdLast = camNode, rhd else camNode, rhd = M.camNodeLast, M.rhdLast end
  if not camNode then return end
  local F, U = vec3(veh:getDirectionVector()), vec3(veh:getDirectionVectorUp())
  local R = F:cross(U):normalized()
  U = R:cross(F):normalized()
  local anchor0
  F, R, U, anchor0 = cabBasis(veh, camNode, F, R, U)
  local node = anchor0
  if not node then
    node = vec3(veh:getNodeAbsPositionXYZ(camNode))
    local c = M.camRest
    if c then node = node - F * c.f - R * c.r - U * c.u end
  end
  -- (2026-11-09: the eyes were read from the camera every moment, so all of it followed the driver's head and, in the workshop, the workshop's camera. Now once per truck: standing, in the
  -- driver's seat. After that nothing the camera does moves anything in the cab.)
  local eyeKey = tostring(truck.model) .. ((anchor0 or M.camRest) and '' or '#')
  local eyes = st.eyeFix[eyeKey]
  local now_ = os.clock()
  if now_ - eyeAt > 0.5 then
    eyeAt = now_
    local ok, name = pcall(core_camera.getActiveCamName, 0)
    name = ok and tostring(name or '') or ''
    inDriver = name == 'onboard.driver' or name == 'driver'
    if not eyes and inDriver and not M.noLearn and not M.inGarage and vec3(veh:getVelocity()):length() < 0.4 then
      local d = vec3(core_camera.getPosition()) - node
      if d:length() < 2.2 then
        eyes = { f = d:dot(F), r = d:dot(R), u = d:dot(U) }
        st.eyeFix[eyeKey] = eyes
      end
    end
  end
  if not eyes then
    local c = M.frame and M.frame.cam
    eyes = c and { f = c.f, r = c.r, u = c.u } or { f = 0, r = 0, u = 0 }
    if M.inGarage then st.eyeFix[eyeKey] = eyes end
  end
  local eye = node + F * eyes.f + R * eyes.r + U * eyes.u
  local flip = rhd and -1 or 1
  M.last = { eye = eye, F = F, R = R, U = U, flip = flip }
  if M.rider then
    -- (the seat beside the driver: the driver's place mirrored over the middle of the cab, a little back, sitting 0.74 below the eyes)
    -- (2026-11-10, 2nd: from the eyes learned from the camera she sat off the seat - the camera can be moved. The driver's camera node of the vehicle itself, mirrored over the
    -- vehicle's middle line, as at the start, only held by the cab's frame)
    local fr = M.frame or {}
    local p
    if fr.cam and fr.midR then
      p = node + F * (fr.cam.f - 0.12) + R * (2 * fr.midR - fr.cam.r) + U * (fr.cam.u - 0.74)
    else
      local mid = fr.centerR or (eyes.r + 0.62 * flip)
      p = node + F * (eyes.f - 0.12) + R * (mid + (mid - eyes.r)) + U * (eyes.u - 0.74)
    end
    pcall(place, M.rider, p, F, U)
    M.riderT = os.clock()
  end
  -- the truck's own acceleration, for what hangs
  local vel = vec3(veh:getVelocity())
  local ax, af = 0, 0
  if lastVel and dt > 0.0005 then
    local a = (vel - lastVel) * (1 / dt)
    ax, af = a:dot(R), a:dot(F)
  end
  lastVel = vel
  local t = os.clock()
  for iid, b in pairs(built) do
    local a, it = truck.acc[iid], b.it
    if a and b.body then
      local p = eye + F * (it.at.f + (a.f or 0)) + R * (it.at.r * flip + (a.r or 0)) + U * (it.at.u + (a.u or 0))
      -- (turned on the spot: what belongs to the piece turns with it)
      if it.wall then
        -- (on the wall of the cab on the passenger's side, found from the cab's own points)
        local fr = M.frame or {}
        local wall = (flip > 0 and fr.wallR or fr.wallL) or (eyes.r + 1.75 * flip)
        p = node + F * (eyes.f + it.at.f + (a.f or 0)) + R * (wall + (a.r or 0)) + U * (eyes.u + it.at.u + (a.u or 0))
        showPhoto(a.photo)
      end
      local yaw = a.yaw or 0
      local Fw, Rw = F, R
      if yaw ~= 0 then Fw, Rw = rot(F, U, yaw), rot(R, U, yaw) end
      local dir, up = -Fw, U
      if M.hung(it) then
        -- tied on behind the windscreen, the disco ball up at the roof; the piece moves with where it is tied, "thread" is the length alone
        local fr = M.frame or {}
        local mid = fr.centerR or (eyes.r + 0.6 * flip)
        local roofU = fr.roofU or (eyes.u + 0.62)
        local tieF, tieU, len
        if it.roof then tieF, tieU, len = eyes.f + it.at.f, roofU, math.max(0.12, math.min(1.1, roofU - eyes.u - 0.16 + (a.l or 0)))
        else tieF, tieU, len = eyes.f + HEADER_F, eyes.u + HEADER_U, math.max(0.03, math.min(0.6, THREAD + (a.l or 0))) end
        local anchor = node + F * (tieF + (a.f or 0)) + R * (mid + (it.at.r - 0.55) * 0.55 * flip + (a.r or 0)) + U * (tieU + (a.u or 0))
        local down, s = U * -1, nil
        if it.swing then
          s = swing[iid] or { x = 0, y = 0, vx = 0, vy = 0 }
          -- (2026-11-09: the long thread of the disco ball swings slower and further than the short ones at the windscreen)
          local k, h = 9.8 / math.max(0.25, len), math.min(dt, 0.033)
          local damp, gain, limit = it.roof and 1.5 or 4, it.roof and 1.0 or 0.4, it.roof and 0.5 or 0.3
          s.vx = s.vx + (-k * s.x - damp * s.vx + gain * ax / math.max(0.25, len)) * h
          s.vy = s.vy + (-k * s.y - damp * s.vy + gain * af / math.max(0.25, len)) * h
          s.x = math.max(-limit, math.min(limit, s.x + s.vx * h))
          s.y = math.max(-limit, math.min(limit, s.y + s.vy * h))
          swing[iid] = s
          up = rot(rot(U, F, s.x), R, -s.y)
          dir = rot(rot(-F, F, s.x), R, -s.y)
          down = up * -1
        end
        if yaw ~= 0 then dir = rot(dir, up, yaw) end
        p = anchor + down * len
        if b.thread then
          place(b.thread, anchor, dir, up)
          if math.abs((b.threadL or 0) - len) > 0.004 then b.threadL = len; pcall(function() b.thread:setScale(vec3(1, 1, len)) end) end
        end
      elseif it.swing then
        -- a pendulum: pulled by the truck's acceleration, damped
        local s = swing[iid] or { x = 0, y = 0, vx = 0, vy = 0 }
        local k = 9.8 / it.swing
        local h = math.min(dt, 0.033)
        s.vx = s.vx + (-k * s.x - 1.6 * s.vx + ax / it.swing) * h
        s.vy = s.vy + (-k * s.y - 1.6 * s.vy + af / it.swing) * h
        s.x = math.max(-0.9, math.min(0.9, s.x + s.vx * h))
        s.y = math.max(-0.9, math.min(0.9, s.y + s.vy * h))
        swing[iid] = s
        up = rot(rot(U, F, s.x), R, -s.y)
        dir = rot(rot(-Fw, F, s.x), R, -s.y)
      end
      place(b.body, p, dir, up)
      if b.pic then place(b.pic, p, dir, up) end
      b.lastP = p
      if M.sel == iid and debugDrawer then
        -- (in the workshop: a frame on the plane it stands on, and its centre)
        pcall(function()
          local col, s = ColorF(1, 0.7, 0.1, 1), 0.075
          local c1, c2, c3, c4 = p + F * s + R * s, p + F * s - R * s, p - F * s - R * s, p - F * s + R * s
          debugDrawer:drawLine(c1, c2, col); debugDrawer:drawLine(c2, c3, col); debugDrawer:drawLine(c3, c4, col); debugDrawer:drawLine(c4, c1, col)
          debugDrawer:drawSphere(p, 0.006, col)
        end)
      end
      if b.head then
        local amp = 0.16 + math.min(0.3, vel:length() * 0.006)
        local q = p + (M.hung(it) and up or U) * it.head.u
        if it.head.spin then
          -- (the fan's blades, the disco ball: only while switched on)
          if G[iid] and G[iid].on then spinA[iid] = ((spinA[iid] or 0) + it.head.spin * dt) % 6.2832 end
          local a2 = spinA[iid] or 0
          q = q - Fw * (it.head.y or 0)
          if it.head.axis == 'f' then place(b.head, q, -Fw, rot(U, Fw, a2)) else place(b.head, q, rot(dir, up, a2), up) end
        elseif it.head.sway then
          -- (the hips: side to side, more the harder the truck moves)
          local a2 = math.sin(t * 6.5) * math.min(0.5, 0.14 + math.abs(ax) * 0.09 + vel:length() * 0.008)
          place(b.head, q, -Fw, rot(U, Fw, a2))
        elseif it.head.wobble then
          local a2, a3 = math.sin(t * 11) * amp * 0.8, math.sin(t * 8.3) * amp * 0.5
          place(b.head, q, rot(-Fw, Rw, a3), rot(rot(U, Fw, a2), Rw, a3))
        else
          local nod = math.sin(t * 7.5) * amp
          place(b.head, q, rot(-Fw, Rw, nod), rot(U, Rw, nod))
        end
      end
      if b.stream then
        -- (2026-11-10) brewing: a thin stream into the cup and the machine humming, a little shaking with it
        local g = G[iid]
        local running = g and g.runTo and t < g.runTo
        local shake = running and math.sin(t * 55) * 0.0012 or 0
        place(b.stream, p + U * (running and 0 or -3) + Rw * shake, -Fw, U)
      end
      if iid == 'popcorn' then
        -- (2026-11-10) the popcorn machine glows warm while it pops
        local g = G[iid]
        local running = g and g.runTo and t < g.runTo
        if running and not M.popLight then
          M.popLight = createObject('PointLight')
          if M.popLight then M.popLight.canSave = false; pcall(function() M.popLight.radius = 0.9; M.popLight:setField('brightness', 0, '1.2'); M.popLight:setField('castShadows', 0, '0'); M.popLight:setField('color', 0, '1 0.62 0.25 1') end); M.popLight:registerObject('ff_poplight') end
        elseif not running and M.popLight then pcall(function() M.popLight:delete() end); M.popLight = nil end
        if M.popLight then pcall(function() M.popLight:setPosition(p + U * 0.12) end) end
      end
      if b.kern then
        local g = G[iid]
        local running = g and g.runTo and t < g.runTo
        for i, k in ipairs(b.kern) do
          local h = running and (0.085 + math.abs(math.sin(t * (7 + i * 1.3) + i * 2)) * 0.075) or 0.082
          place(k, p + U * h + Rw * (math.cos(i * 2.4) * 0.03) - Fw * (0.03 + math.sin(i * 1.7) * 0.02), -Fw, rot(U, Fw, running and t * (4 + i) or i))
        end
      end
      if iid == 'disko' then
        local on = G.disko and G.disko.on
        if on and not disco then
          disco = createObject('PointLight')
          if disco then disco.canSave = false; pcall(function() disco.radius = 2.6; disco:setField('brightness', 0, '1.8'); disco:setField('castShadows', 0, '0') end); n = n + 1; disco:registerObject('ff_acc_disco' .. n) end
        elseif not on then discoOff() end
        if disco then
          local h = t * 1.4
          pcall(function() disco:setField('color', 0, string.format('%.2f %.2f %.2f 1', 0.5 + 0.5 * math.sin(h), 0.5 + 0.5 * math.sin(h + 2.1), 0.5 + 0.5 * math.sin(h + 4.2))); disco:setPosition(p - U * 0.15 + R * math.cos(t * 2) * 0.4 - F * (0.35 + math.sin(t * 2) * 0.3)) end)
        end
      end
      if iid == 'display' and G.display and G.display.on and inDriver and ctx and debugDrawer then
        local m = DISPLAY[G.display.i]
        local line = m == 'radio' and ctx.radioLine() or (m == 'uhr' and ctx.clock() or string.format('%d km/h', math.floor(vel:length() * 3.6 + 0.5)))
        pcall(function() debugDrawer:drawTextAdvanced(p + U * 0.06 - F * 0.03, String(tostring(line)), ColorF(0.45, 0.92, 1, 1), true, false, ColorI(6, 12, 20, 235)) end)
      end
      if b.arm then
        local wave = 0.25 + math.sin(t * 5) * 0.45
        local q = p + Rw * (it.arm.r * flip) + Fw * it.arm.f + U * it.arm.u
        place(b.arm, q, -Fw, rot(U, Fw, wave))
      end
    end
  end
end

-- the workshop's views: the driver's seat, from the side (to see whether it stands on the surface), from above; always aimed at the piece chosen
function M.garageCam(mode)
  local L = M.last
  if not L then return nil end
  local b = M.sel and built[M.sel]
  local p = (b and b.lastP) or (L.eye + L.F * 0.85 + L.R * (0.4 * L.flip) - L.U * 0.42)
  local pos, up = L.eye, L.U
  if mode == 'seite' then pos = p + L.R * 0.42 + L.U * 0.015 - L.F * 0.03
  elseif mode == 'oben' then pos, up = p + L.U * 0.42 - L.F * 0.1, L.F end
  return { pos = pos, dir = (p + L.U * 0.03 - pos):normalized(), up = up, fov = mode == 'fahrer' and 62 or 46 }
end
function M.reset() clear(); lastVel = nil end
return M
