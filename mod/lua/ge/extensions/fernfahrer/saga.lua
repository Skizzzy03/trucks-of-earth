-- Trucks of Earth (2026-11-11): "Die Blaue Elise" - a story that runs through the career and ties its people together ("eine ausgeklügelte
-- Story, die alles sehr interessant macht"). Heinz Brandt, a legend among the old drivers, vanished in 1998 with his blue cab-over, the Elise.
-- The player hears of it at a rest area or from a mechanic, gives his granddaughter Ronja a lift, gets a strange call through Mira, meets
-- the old man himself at a rest area, and in the end stands in the barn where the Elise has waited for 27 years.
--   c = 0  the legend: told by an old driver at a rest area, or by the mechanic of the breakdown service, whichever comes first
--   c = 1  Ronja: the next hitchhiker at the roadside is her (crew.lua / encounters.lua), her story is the Elise's
--   c = 2  the call: after the next delivery Mira tells of an old man who asked for the driver
--   c = 3  Heinz: at a rest area he knocks at the window; the barn is near a village 20 to 60 km away (the navi goes there)
--   c = 4  the barn: stopped there, the finale. c = 5: told; the people mention it now and then.
-- State in the career's encounter state (st.saga). M.attach(st, ctx); M.tick(t) every second; M.step(key) from the scenes' fx.saga.
-- ctx: jobs(), km(), here() -> {lat, lon}, atRest() (stopped at a rest area for a while), stopped(), encActive(), encStart(key),
--      message(text, from), notify(text, ttl), villageNear(lat, lon, minM, maxM) -> {name, lat, lon}, navTo(lat, lon, name), save()
local M = {}
local st, X

M.FROM_MIRA = 'Mira · Disposition'

-- her story on the way, in three parts (crew.lua tells it as any hitchhiker's)
M.RONJA = {
  { say = 'Ich bin übrigens Ronja. Ronja Brandt. Mein Opa war Fernfahrer, Heinz Brandt. Vielleicht hast du mal von ihm gehört?', ch = {
    { t = '„Die Blaue Elise? Das war dein Opa?“', r = 'Du kennst die Geschichte! Ja. Er ist vor 27 Jahren verschwunden, mit dem Lkw. Ich war sechs. Er hat mir immer Pfefferminz mitgebracht.', m = 3 },
    { t = '„Sagt mir nichts.“', r = 'Macht nichts. Kaum einer erinnert sich noch. Er ist mit seinem blauen Lkw einfach verschwunden. Für mich war er ein Held.', m = 0 } } },
  { say = 'Letzte Woche kam ein Brief. Ohne Absender. Nur ein Foto: die Elise in einer Scheune, unter einer Plane. Und hinten drauf steht „Sie wartet“. In Opas Schrift.', ch = {
    { t = '„Dann lebt er vielleicht noch!“', r = 'Das glaube ich auch. Meine Mutter sagt, ich soll mir keine Hoffnungen machen. Aber die Schrift kenne ich. Die kenn ich von jedem Geburtstagsbrief.', m = 2 },
    { t = '„Das könnte auch ein schlechter Scherz sein.“', r = 'Könnte. Aber wer macht so einen Scherz? Nach 27 Jahren? Nein. Das war er.', m = 0 } } },
  { say = 'Ich klapper jetzt die Rastplätze ab, wo er früher Pause gemacht hat. Wenn du mal einen alten Mann mit Schiebermütze siehst, der Pfefferminz lutscht: Sag ihm, Ronja sucht ihn.', ch = {
    { t = '„Versprochen. Ich halte die Augen offen.“', r = 'Danke. Wirklich. Das bedeutet mir viel. Hier, nimm ein Pfefferminz. Für Opa, falls du ihn triffst.', m = 3 },
    { t = '„Viel Glück bei der Suche.“', r = 'Danke. Das brauche ich.', m = 1 } } },
}

-- the scenes at the window (encounters.lua plays them; %BARN% is the village of the barn)
M.SCENES = {
  saga_legende = { bed = 'warm', who = 'Alter Fahrer', face = 'trucker', start = 'a', mood = 2, n = {
    a = { say = 'N’Abend, Kollege. Sag mal, du kommst doch rum. Hast du mal von der Blauen Elise gehört?', react = 'think', ch = {
      { t = '„Nie gehört. Was ist das?“', to = 'b', mood = 1 }, { t = '„Keine Zeit für Seemannsgarn.“', to = 'kurz' } } },
    b = { say = 'Ein blauer Frontlenker, Baujahr 79. Heinz Brandt ist den gefahren, die Legende von der A1. Nie zu spät, nie ein Kratzer. 1998 stellt er die Elise auf einem Rastplatz ab, ruft seine kleine Enkelin an. Und dann ist er weg. Mit dem Lkw. Spurlos.', react = 'think', ch = {
      { t = '„Und keiner hat ihn je gefunden?“', to = 'c', mood = 1 }, { t = '„Bestimmt nach Spanien abgehauen.“', to = 'c' } } },
    c = { say = 'Manche sagen, man sieht die Elise nachts noch auf der Landstraße, ohne Licht. Ich glaub ja eher, der alte Heinz hatte seine Gründe. Wenn du mal eine Enkelin namens Ronja triffst: Die sucht ihn bis heute.', react = 'nod', fx = { saga = 'legend', xp = 30 } },
    kurz = { say = 'Wie du meinst. Aber merk dir den Namen: Brandt. Heinz Brandt. Die Geschichte ist noch nicht zu Ende.', react = 'shake', fx = { saga = 'legend' } },
  } },
  saga_heinz = { bed = 'warm', who = 'Alter Mann mit Schiebermütze', face = 'old', start = 'a', mood = 1, n = {
    a = { say = 'Entschuldigen Sie. Pfefferminz? … Sie sind der Fahrer, der das Mädchen mitgenommen hat. Ronja. Ich hab gesehen, wie sie bei Ihnen eingestiegen ist.', react = 'nervous', ch = {
      { t = '„Heinz? Heinz Brandt?“', to = 'b', mood = 2 }, { t = '„Wer will das wissen?“', to = 'b' } } },
    b = { say = 'Der bin ich. 1998 wollte mein Chef die Elise verschrotten und die Strecke an die Konkurrenz verkaufen. Da hab ich sie genommen und in der Scheune meines Bruders versteckt. Danach hab ich mich nicht mehr nach Hause getraut. Zu stolz, zu feige. Ich bin nach Norwegen, auf einen Kutter.', react = 'sad', ch = {
      { t = '„Ronja sucht Sie überall.“', to = 'c', mood = 1 }, { t = '„27 Jahre sind eine lange Zeit.“', to = 'c' } } },
    c = { say = 'Ich weiß. Der Brief war von mir. Ich schaff es nicht allein, ihr gegenüberzutreten. Die Scheune steht bei %BARN%. Kommen Sie dorthin? Ich sag Ronja Bescheid. Mit Ihnen dabei trau ich mich.', react = 'nervous', ch = {
      { t = '„Ich komme. Versprochen.“', to = 'ja', mood = 2 }, { t = '„Warum ausgerechnet ich?“', to = 'warum' } } },
    warum = { say = 'Weil Sie sie mitgenommen haben, als sie am Straßenrand stand. Das hätte nicht jeder gemacht. Das reicht mir.', react = 'nod', ch = { { t = '„Gut. Ich komme.“', to = 'ja' } } },
    ja = { say = 'Danke. Ich fahr voraus. Bei %BARN%, die alte Scheune am Feldweg. Sie werden sie erkennen.', react = 'laugh', fx = { saga = 'barn', xp = 50 } },
  } },
  saga_elise = { bed = 'warm', who = 'Ronja', face = 'hitch', start = 'a', mood = 3, knock = 1, n = {
    a = { nar = true, say = 'Vor der Scheune steht Ronja, daneben der alte Mann mit der Schiebermütze. Die beiden reden nicht, sie halten sich nur fest. Dann winkt Ronja dich heran.', react = 'laugh', ch = {
      { t = 'Aussteigen und hingehen', to = 'b', mood = 1 } } },
    b = { say = 'Du bist gekommen! Opa hat erzählt, dass du ihn gefunden hast. Komm, hilf uns mit dem Tor.', react = 'laugh', ch = { { t = 'Das Scheunentor aufziehen', to = 'c' } } },
    c = { nar = true, say = 'Das Tor quietscht. Unter einer staubigen Plane steht sie: blau, rund, mit Chromgrill. Die Blaue Elise. Heinz klettert ins Führerhaus, dreht den Schlüssel. Beim dritten Versuch springt der Motor an, und die ganze Scheune bebt.', react = 'laugh', ch = {
      { t = '„Sie lebt!“', to = 'd', mood = 1 }, { t = 'Nichts sagen, nur zuhören', to = 'd' } } },
    d = { say = 'Opa sagt, die Elise fährt keiner außer ihm. Aber er will, dass du das hier bekommst, für die Firma. Und eine Bitte hat er: Wenn du je eine Fuhre hast, die keiner fahren will, ruf ihn an. Er fährt sie. Mit Elise.', react = 'laugh', fx = { saga = 'done' }, ch = {
      { t = '„Abgemacht. Gute Fahrt, ihr zwei.“' } } },
  } },
}

function M.attach(state, ctx)
  st, X = state, ctx
  st.saga = st.saga or { c = 0 }
end
function M.stage() return st and st.saga and st.saga.c or 0 end

-- a mechanic's talk tells the legend instead, the first time (crew.lua)
M.MECH_TOPIC = { say = 'Sag mal, du bist doch viel unterwegs. Hast du je von der Blauen Elise gehört? Heinz Brandt, die Legende von der A1. 1998 mit seinem blauen Frontlenker verschwunden, spurlos. Seine Enkelin sucht ihn bis heute.', ch = {
  { t = '„Erzähl mehr!“', r = 'Mehr weiß keiner. Nur dass er nie zu spät war, nie einen Kratzer hatte, und eines Abends einfach weg war. Wenn du mal eine Ronja triffst, die nach ihm fragt: Die ist es.', m = 2 },
  { t = '„Klingt nach Seemannsgarn.“', r = 'Vielleicht. Aber jeder alte Fahrer kennt die Geschichte. Und jeder erzählt sie ein bisschen anders.', m = 0 } } }
function M.mechanicTopic() return M.stage() == 0 and M.MECH_TOPIC or nil end
-- the next hitchhiker is Ronja?
function M.wantRonja() return M.stage() == 1 end
-- (after it: a word about it now and then, from the people)
M.GOSSIP = { say = 'Hast du schon gehört? Die Blaue Elise ist wieder aufgetaucht! Der alte Heinz Brandt fährt sie wieder, mit seiner Enkelin auf dem Beifahrersitz. Angeblich hat ihnen ein Fernfahrer geholfen.', ch = {
  { t = '„Das war ich.“', r = 'Nee! Echt jetzt? Dann gib mir mal die Hand. Das erzähl ich heute Abend in der Kneipe.', m = 3 },
  { t = '„Schöne Geschichte.“', r = 'Oder? Manchmal gehen Geschichten gut aus. Selten, aber manchmal.', m = 1 } } }
function M.gossip() return M.stage() >= 5 and math.random() < 0.35 and M.GOSSIP or nil end

-- the scenes' fx.saga, and what the rides report
function M.step(key)
  local s = st and st.saga
  if not s then return end
  s.nextTry = nil                     -- (a new chapter: no waiting left over from the one before)
  if key == 'legend' and s.c == 0 then
    s.c, s.km1 = 1, X.km()
    X.notify('📖 Die Blaue Elise: Wer war Heinz Brandt? Halt die Augen offen nach einer Ronja.', 8)
  elseif key == 'ronja' and s.c <= 1 then
    s.c, s.jobs2 = 2, X.jobs()
    X.notify('📖 Die Blaue Elise: Ronja sucht ihren Opa. Vielleicht hört Mira etwas.', 8)
  elseif key == 'barn' and s.c == 3 then
    s.c = 4
    local b = s.barn
    if b then
      X.navTo(b.lat, b.lon, 'Scheune bei ' .. b.name)
      X.message('Ein alter Mann hat mir eben eine Adresse durchgegeben: eine Scheune bei ' .. b.name .. '. Ich hab sie dir ins Navi gelegt. Ist das die Geschichte, von der alle reden?', M.FROM_MIRA)
    end
  elseif key == 'done' and s.c == 4 then
    s.c = 5
    X.pay('Sonstiges', 3000, 'Dankeschön von Heinz Brandt')
    X.xp(1500)
    X.message('Ein Umschlag im Firmenbriefkasten: 3.000 €, ein Foto von Heinz und Ronja vor der Blauen Elise und eine Tüte Pfefferminz. Auf dem Foto steht: „Danke, Kollege.“', M.FROM_MIRA)
    X.notify('📖 Die Blaue Elise – Ende. +3.000 €, +1.500 XP', 10)
  end
  X.save()
end

-- every second
function M.tick(t)
  local s = st and st.saga
  if not s or s.c >= 5 or X.encActive() then return end
  -- the legend at a rest area, once the first loads are done
  if s.c == 0 then
    if X.jobs() >= 1 and X.atRest() and t > (s.nextTry or 0) then
      s.nextTry = t + 600
      X.encStart('saga_legende')
    end
  -- no Ronja at the roadside for a long time: she calls the office (the story must not stall)
  elseif s.c == 1 then
    if X.km() - (s.km1 or X.km()) > 250 then
      X.message('Eine junge Frau hat angerufen, Ronja Brandt. Sie sucht ihren Großvater, einen Fernfahrer, seit 1998 verschwunden. Sie hat gehört, dass du nach ihm gefragt hast. Sie hat ein Foto von seinem Lkw in einer Scheune bekommen, „Sie wartet“ steht drauf.', M.FROM_MIRA)
      M.step('ronja')
    end
  -- after the next delivery: the call
  elseif s.c == 2 then
    if X.jobs() > (s.jobs2 or 0) then
      s.c = 3
      X.message('Komischer Anruf heute. Ein älterer Herr hat nach dem Fahrer gefragt, „der das Mädchen mitgenommen hat“. Mehr wollte er nicht sagen. Nur: „Rastplatz. Pfefferminz.“ Dann hat er aufgelegt. Weißt du, was das soll?', M.FROM_MIRA)
      X.save()
    end
  -- Heinz at a rest area
  elseif s.c == 3 then
    if X.atRest() and t > (s.nextTry or 0) then
      s.nextTry = t + 300
      local p = X.here()
      if not s.barn and p then s.barn = X.villageNear(p.lat, p.lon, 20000, 60000) end
      if s.barn then X.encStart('saga_heinz') end
    end
  -- the barn
  elseif s.c == 4 then
    local b, p = s.barn, X.here()
    if b and p and X.stopped() and X.dist(p.lat, p.lon, b.lat, b.lon) < 350 and t > (s.nextTry or 0) then
      s.nextTry = t + 60
      X.encStart('saga_elise')
    end
  end
end

return M
