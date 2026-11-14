-- Trucks of Earth (2026-11-11): the people one meets again ("vielleicht trifft man auch ab und zu die gleichen wieder und man erinnert sich").
-- The breakdown service: six mechanics of their own, each with a manner, a way of talking and things to talk about while the kettle of
-- coffee in the van cools. Each region has its own (by a grid of half degrees), so who breaks down round here meets the same one again,
-- and he remembers: what it was last time, where, how often. The hitchhikers one has given a lift are remembered too: now and then one of
-- them stands at the road again and carries on where she left off (passenger.lua: AGAIN, SEQUEL).
-- The memory lives in the career's encounter state (st.people); data and pure functions only. fernfahrer/crew.lua and encounters.lua use it.
local M = {}

M.FAULT = { tire = 'der geplatzte Reifen', radiator = 'der Kühler', hose = 'der Ladeluftschlauch', oil = 'das Öl', recover = 'der Unfall' }

-- a topic: { say, ch = { { t (the driver), r (the reply), m (how he takes it) } } }
M.MECHANICS = {
  { key = 'kalle', name = 'Kalle', club = 'Pannendienst Ruhr', seed = 1201,
    hello = 'Glück auf! Kalle, Pannendienst. Na, was hat er denn, der Gute?',
    again = 'Ach nee, du schon wieder! Letztes Mal war’s %LAST% bei %PLACE%. Was ist es diesmal?',
    often = 'Wir sehen uns ja öfter als ich meine Schwiegermutter. Das ist jetzt das %N%. Mal. Erzähl.',
    topics = {
      { say = 'Weißt du, was das Schönste an meinem Job ist? Die Leute sind immer froh, mich zu sehen. Als Zahnarzt hättest du das nicht.', ch = {
        { t = '„Als Pannenhelfer bist du der Held am Straßenrand.“', r = 'Genau so! Ich lass mir demnächst ein Cape machen. Orange, passend zur Jacke.', m = 2 },
        { t = '„Und wenn’s regnet?“', r = 'Dann bin ich ein nasser Held. Aber immer noch ein Held.', m = 1 } } },
      { say = 'Ich hab mal einen Lkw abgeschleppt, da war die ganze Ladung Gartenzwerge. Dreitausend Stück. Die haben mich die ganze Fahrt angeguckt.', ch = {
        { t = '„Gruselig.“', r = 'Und wie! Einer fehlte am Ende. Ich sag nix. Aber in meinem Garten steht seitdem einer mit Angel.', m = 2 },
        { t = '„Und, was war kaputt?“', r = 'Kupplung. Langweilig. Die Zwerge waren das Spannende.', m = 0 } } },
      { say = 'Mein Vater war auch schon Pannenhelfer. Der hat noch mit dem Käfer Starthilfe gegeben, bei minus zwanzig, mit Thermoskanne und Pfeife.', ch = {
        { t = '„Und du bist in seine Fußstapfen getreten.“', r = 'Mehr oder weniger. Die Pfeife hab ich weggelassen. Die Thermoskanne nicht.', m = 2 },
        { t = '„Früher war alles einfacher.“', r = 'Früher war alles kälter. Einfacher? Glaub ich nicht.', m = 0 } } },
    },
    fix = 'So, fertig. Und jetzt fahr ihn schön warm, nicht gleich wieder volle Pulle.',
    recover = 'Fahrbereit isser. Mehr nicht. Ab in die Werkstatt damit, versprochen?' },
  { key = 'svenja', name = 'Svenja', club = 'Straßenhilfe Nord', seed = 2417,
    hello = 'Moin. Svenja, Straßenhilfe. Und bevor du fragst: Ja, ich kann das wirklich. Was ist los?',
    again = 'Na sieh mal an. Damals war’s %LAST% bei %PLACE%, ich erinnere mich. Du hast mir einen Kaffee versprochen. Was ist diesmal?',
    often = 'Das %N%. Mal. Langsam glaube ich, du machst das mit Absicht. Was hast du kaputt gemacht?',
    topics = {
      { say = 'Die Hälfte der Leute fragt, ob nicht noch ein Kollege kommt. Die andere Hälfte erklärt mir, wie ein Reifen funktioniert.', ch = {
        { t = '„Ich hab nichts gesagt.“', r = 'Eben. Deswegen mag ich dich. Du kriegst auch das gute Werkzeug.', m = 2 },
        { t = '„Und wie reagierst du?“', r = 'Ich lächle und wechsle den Reifen in vier Minuten. Das erklärt sich dann von selbst.', m = 1 } } },
      { say = 'Ich schraube seit ich zwölf bin. Mein erstes Projekt war ein Mofa, das ich aus drei kaputten zusammengebaut hab. Lief sogar.', ch = {
        { t = '„Hast du es noch?“', r = 'Im Schuppen meiner Mutter. Sie will es seit zehn Jahren loswerden. Keine Chance.', m = 2 },
        { t = '„Ich kann nicht mal Fahrradreifen flicken.“', r = 'Kannst du lernen. Komm vorbei, ich bring’s dir bei. Kostet einen Kaffee. Den du mir eh schuldest.', m = 1 } } },
      { say = 'Nachts auf der Autobahn ist es manchmal fast schön. Blinklicht, Nebel, und irgendwo singt ein Lkw-Fahrer schief zum Radio.', ch = {
        { t = '„Das war ich nicht.“', r = 'Sicher nicht. Du hast bestimmt eine wunderschöne Stimme.', m = 1 },
        { t = '„Klingt einsam.“', r = 'Ein bisschen. Aber ich mag das. Und dann ruft wieder einer an, und es geht weiter.', m = 1 } } },
    },
    fix = 'Fertig. Und diesmal pfleg ihn, ja? Ich hab auch noch andere Kunden.',
    recover = 'Er fährt. Aber bitte direkt in die Werkstatt, das ist nur geflickt.' },
  { key = 'tobi', name = 'Tobi', club = 'Pannendienst', seed = 3380,
    hello = 'Hallo! Ich bin Tobi, ich bin, ähm, neu dabei. Aber ich hab die Prüfung bestanden! Mit zwei. Was ist kaputt?',
    again = 'Oh, Sie sind das! Mit %LAST% bei %PLACE%! Das war mein dritter Einsatz überhaupt. Was ist es heute?',
    often = 'Sie schon wieder! Das %N%. Mal! Mein Chef sagt schon, Sie sind mein Stammkunde.',
    topics = {
      { say = 'Darf ich Sie was fragen? Wie lange fahren Sie schon Lkw? Ich überlege, ob ich den Führerschein noch mache.', ch = {
        { t = '„Mach das. Bester Job der Welt.“', r = 'Echt? Okay. Dann frag ich nächste Woche bei der Fahrschule. Danke!', m = 2 },
        { t = '„Überleg dir das gut. Viel allein, wenig Schlaf.“', r = 'Hm. Aber Sie sehen ganz zufrieden aus. Meistens.', m = 0 } } },
      { say = 'Mein Ausbilder sagt immer, man soll mit dem Fahrzeug reden. Ich weiß nicht, ob er das ernst meint.', ch = {
        { t = '„Er meint das ernst. Meiner hört zu.“', r = 'Wirklich? Okay. Dann sag ich ihm gleich, dass er tapfer war.', m = 2 },
        { t = '„Er veräppelt dich.“', r = 'Hab ich mir gedacht. Aber ich mach’s trotzdem. Schadet ja nicht.', m = 1 } } },
      { say = 'Ich hab heute schon drei Einsätze gehabt. Einer hatte nur kein Benzin mehr. Der war richtig sauer, als ich das gesagt hab.', ch = {
        { t = '„Auf dich oder auf sich?“', r = 'Auf mich! Als ob ich das Benzin getrunken hätte.', m = 2 },
        { t = '„Passiert den Besten.“', r = 'Sagen Sie das ihm. Er hatte einen Porsche.', m = 1 } } },
    },
    fix = 'Fertig! Glaub ich. Doch, fertig. Sie können los. Gute Fahrt!',
    recover = 'Also, er fährt. Aber mein Chef würde sagen: Werkstatt, und zwar heute noch.' },
  { key = 'jens', name = 'Jens', club = 'Lkw-Notdienst', seed = 4021,
    hello = 'Tach. Jens, Lkw-Notdienst. Schönes Gerät hast du da. Was fehlt ihm?',
    again = 'Hab ich doch gewusst, dass ich die Kiste kenne. Damals %LAST% bei %PLACE%, oder? Was ist diesmal?',
    often = 'Das %N%. Mal. Ich kenne deinen Lkw bald besser als meinen eigenen. Erzähl.',
    topics = {
      { say = 'Ich hab zuhause einen alten Rundhauber stehen, Baujahr 1971. Jeden Sonntag schraub ich dran. Meine Frau nennt ihn „die Zweitfrau“.', ch = {
        { t = '„Fährt er noch?“', r = 'Fahren ist übertrieben. Er rollt. Bergab. Aber er klingt herrlich.', m = 2 },
        { t = '„Deine Frau hat recht.“', r = 'Hat sie immer. Sag’s ihr bloß nicht.', m = 1 } } },
      { say = 'Die neuen Lkw haben mehr Computer als die Raumfähre. Früher hast du mit Hammer und Gefühl alles hinbekommen.', ch = {
        { t = '„Und heute mit Laptop.“', r = 'Heute mit Laptop und Gebet. Meistens reicht das Gebet.', m = 2 },
        { t = '„Dafür verbrauchen sie weniger.“', r = 'Stimmt schon. Und sie riechen nicht mehr nach Diesel. Schade eigentlich.', m = 0 } } },
      { say = 'Kennst du die Geschichten von früher? Fahrer, die drei Tage durchgefahren sind, mit nichts als Kaffee und Kassetten?', ch = {
        { t = '„Die gibt’s heute nicht mehr.“', r = 'Zum Glück. Die Hälfte davon ist nicht alt geworden. Aber erzählen konnten die.', m = 1 },
        { t = '„Erzähl mal eine.“', r = 'Ein andermal, wenn wir mehr Zeit haben. Die Guten brauchen Zeit.', m = 1 } } },
    },
    fix = 'Fertig. Der läuft wieder wie ein Uhrwerk. Pass auf ihn auf.',
    recover = 'Fahrbereit, mehr ist hier draußen nicht drin. Lass das ordentlich machen.' },
  { key = 'olli', name = 'Olli', club = 'Pannendienst Süd', seed = 5155,
    hello = 'Servus, Olli vom Pannendienst. Ganz ruhig, ich bin ja jetzt da. Was ist passiert?',
    again = 'Servus! Wir kennen uns doch. Damals %LAST% bei %PLACE%. Das Leben ist ein Kreis. Was ist diesmal?',
    often = 'Das %N%. Mal. Weißt du, ich glaube nicht an Zufälle. Was ist es heute?',
    topics = {
      { say = 'Am Wochenende geh ich angeln. Ich fang fast nie was. Aber darum geht’s auch nicht, oder?', ch = {
        { t = '„Worum geht’s dann?“', r = 'Ums Warten. Wer warten kann, ist nie in Eile. Und wer nie in Eile ist, hat seltener Pannen.', m = 2 },
        { t = '„Doch, ein Fisch wäre schon schön.“', r = 'Ja, gut. Ein Fisch wäre schön. Erwischt.', m = 1 } } },
      { say = 'Die meisten Pannen passieren, wenn die Leute es eilig haben. Das ist keine Statistik, das ist Erfahrung.', ch = {
        { t = '„Ich hab’s immer eilig.“', r = 'Siehst du. Vielleicht hat dein Lkw dich hier angehalten, damit du mal durchatmest.', m = 1 },
        { t = '„Klingt weise.“', r = 'Hab ich von meiner Oma. Die ist nie Lkw gefahren, aber sie wusste alles.', m = 2 } } },
      { say = 'Hörst du das? Die Lerche da drüben. Die singt jeden Morgen genau hier. Ich halt hier oft an, nur deswegen.', ch = {
        { t = '„Ich höre nur die Autobahn.“', r = 'Dann hör nochmal hin. Unter dem Rauschen. Da ist sie.', m = 1 },
        { t = '„Schön.“', r = 'Ja. Man muss die schönen Sachen sammeln, dazwischen.', m = 2 } } },
    },
    fix = 'Erledigt. Fahr mit Ruhe, dann fährt er auch mit Ruhe.',
    recover = 'Er bringt dich in eine Werkstatt. Das ist das Wichtigste. Alles andere kommt dann.' },
  { key = 'basti', name = 'Basti', club = 'Straßenwacht', seed = 6290,
    hello = 'Yo! Basti, Straßenwacht. Ich mach die Mucke kurz leiser. Was ist kaputt?',
    again = 'Ey, dich kenn ich! Damals %LAST% bei %PLACE%, da lief gerade das beste Solo des Jahres. Was ist diesmal?',
    often = 'Alter, das %N%. Mal! Ich schreib bald einen Song über dich. Was ist los?',
    topics = {
      { say = 'Ich spiel am Wochenende Schlagzeug in einer Band. Wir heißen „Kardanwelle“. Wir sind laut, aber nicht gut.', ch = {
        { t = '„Laut ist das Wichtigste.“', r = 'Genau das sag ich auch immer! Komm mal vorbei. Ohrstöpsel mitbringen.', m = 2 },
        { t = '„Dann übt mehr.“', r = 'Üben ist was für Leute, die gut werden wollen. Wir wollen nur Spaß.', m = 0 } } },
      { say = 'Was hörst du so im Lkw? Lass mich raten. Schlager. Nein! Hörbücher. Krimis.', ch = {
        { t = '„Metal. Ganz laut.“', r = 'Nein! Echt? Ich wusste, dass ich dich mag. Ab jetzt bist du mein Lieblingskunde.', m = 3 },
        { t = '„Radio, was gerade läuft.“', r = 'Auch okay. Hauptsache nicht Stille. Stille ist was für Leute ohne Lkw.', m = 1 } } },
      { say = 'Einmal hab ich nachts einen Reifen gewechselt, und die ganze Zeit hat ein Fuchs zugeguckt. Ganz ruhig, drei Meter weg. Als wär er der Chef.', ch = {
        { t = '„Hat er was gesagt?“', r = 'Nur mit den Augen. Ich glaube, er war zufrieden mit meiner Arbeit.', m = 2 },
        { t = '„Füchse sind neugierig.“', r = 'Der war mehr als neugierig. Der hatte einen Plan.', m = 1 } } },
    },
    fix = 'Fertig, Digga. Und jetzt lass ihn wieder röhren.',
    recover = 'Er rollt. Aber bring ihn bitte in die Werkstatt, sonst weint er.' },
}
M.BY_KEY = {}
for _, m in ipairs(M.MECHANICS) do M.BY_KEY[m.key] = m end

local function mem(st)
  st.people = st.people or {}
  local p = st.people
  p.mech = p.mech or {}
  p.hitch = p.hitch or {}
  return p
end
M.mem = mem

-- the region's own mechanic (a grid of half degrees), now and then another; nil lat: anyone
function M.pickMechanic(st, lat, lon)
  local n = #M.MECHANICS
  local i
  if lat and lon and math.random() < 0.75 then
    local k = math.floor(lat * 2) * 7919 + math.floor(lon * 2) * 104729
    i = (math.abs(k) % n) + 1
  else
    i = math.random(n)
  end
  local m = M.MECHANICS[i]
  return m, mem(st).mech[m.key]
end

-- the greeting: first time, again, or quite often
function M.greeting(st, m)
  local r = mem(st).mech[m.key]
  if not r or (r.n or 0) == 0 then return m.hello end
  local line = (r.n >= 2) and m.often or m.again
  return (line:gsub('%%LAST%%', M.FAULT[r.last] or 'die Panne'):gsub('%%PLACE%%', r.place or 'der Autobahn'):gsub('%%N%%', tostring((r.n or 0) + 1)))
end
-- a topic he has not talked about with this driver yet (round again when all are told)
function M.topic(st, m)
  local r = mem(st).mech[m.key] or {}
  local told = r.told or {}
  local free = {}
  for i = 1, #m.topics do if not told[tostring(i)] then free[#free + 1] = i end end
  if #free == 0 then free = {}; for i = 1, #m.topics do free[#free + 1] = i end; told = {} end
  local i = free[math.random(#free)]
  return m.topics[i], i
end
-- after the visit: what it was, where, how often; which topic was told; how it went
function M.noteMechanic(st, m, kind, place, topicIdx, mood)
  local p = mem(st)
  local r = p.mech[m.key] or { n = 0, told = {}, mood = 0 }
  r.n = (r.n or 0) + 1
  r.last, r.place = kind, place
  r.told = r.told or {}
  if topicIdx then r.told[tostring(topicIdx)] = true end
  r.mood = math.max(-4, math.min(6, (r.mood or 0) + (mood or 0)))
  p.mech[m.key] = r
  return r
end

-- the hitchhikers: remembered when they get out (only one who parted on good terms comes again)
function M.noteHitch(st, h, km, place)
  if not h or not h.name then return end
  local p = mem(st)
  local r = p.hitch[h.name] or { rides = 0 }
  r.rides = (r.rides or 0) + 1
  r.story, r.seed, r.mood, r.km, r.place = h.story, h.seed, h.mood or 0, km, place
  r.sequel = r.sequel or (h.sequel and true) or nil
  p.hitch[h.name] = r
end
-- now and then one of them again: one who liked the ride, at least 80 km later. Returns name, record
function M.knownHitch(st, km, chance)
  local p = mem(st)
  if math.random() >= (chance or 0.3) then return nil end
  local list = {}
  for name, r in pairs(p.hitch) do
    if (r.mood or 0) >= 1 and (km or 0) - (r.km or 0) >= 80 and (r.rides or 0) < 4 then list[#list + 1] = name end
  end
  if #list == 0 then return nil end
  local name = list[math.random(#list)]
  return name, p.hitch[name]
end

return M
