-- Trucks of Earth: people at the rest area. The truck has stood for a moment, someone knocks, the head turns to the driver's door and a talk begins: the same
-- window as the officer's (FernfahrerSzene 'FernfahrerCop'), the same face that shows the mood. What the face says counts: a good mood raises every chance taken.
-- Each scene is data: n = { id = { say, nar, who, mood (change), react, fx, ch = { { t, sub, to, roll = { p, win, lose }, mood, fx, cost, need } } } }; a node without ch ends the talk.
-- %ROB% in a text: what a robber wants from this driver. M.attach(save table, ctx), M.pick(), M.start(key), M.answer(i), M.tick(moving), M.kmTick(km), M.contraband(found).
local M = {}
M.COOLDOWN_KM = { 12, 35 }
M.CHANCE = 0.6
M.SHAPE = '/levels/beamng_earth/art/shapes/ffa/ff_npc_'
local X, st, E

local BYE = 'Weiterfahren'
M.ORDER = { 'fremder', 'kollege', 'tramper', 'diesel', 'paket', 'opa', 'panne', 'schlitzer', 'uhr', 'dealer', 'huetchen', 'aluhut' }
M.SC = {
  fremder = { bed = 'rast', knock = 2, who = 'Fremder', face = 'hoodie', start = 'a', n = {
    a = { say = 'Hallo, Fremder.', react = 'think', ch = {
      { t = '„Hallo. Kann ich dir helfen?“', to = 'b', mood = 1 },
      { t = '„Wer will das wissen?“', to = 'b', mood = -1 },
      { t = 'Scheibe wortlos hochfahren', roll = { 0.55, 'weg', 'klopf' } } } },
    klopf = { say = 'Hey. Ich rede mit dir. Das ist unhöflich.', mood = -1, react = 'threat', ch = {
      { t = 'Scheibe wieder runter', to = 'b' }, { t = 'Hand auf die Hupe', roll = { 0.65, 'flieht', 'raub' } } } },
    weg = { nar = true, say = 'Er bleibt noch einen Moment stehen, starrt dich durch die Scheibe an und geht dann langsam zum nächsten Lkw. Komischer Typ.', react = 'sneer', fx = { xp = 10 } },
    b = { say = 'Schöner Lkw. Ganz allein unterwegs, hm? Hast du mal Feuer?', react = 'sneer', ch = {
      { t = 'Feuerzeug rausreichen', roll = { 0.55, 'nett', 'raub' } },
      { t = '„Ich rauche nicht.“', roll = { 0.6, 'nett2', 'raub' } },
      { t = 'Hand auf die Hupe', sub = 'laut werden, bevor etwas passiert', roll = { 0.7, 'flieht', 'raub' } } } },
    nett = { bed = 'warm', say = 'Danke, Mann. Ich bin Rolf. Ich pendle seit drei Wochen zwischen zwei Rastplätzen. Frag nicht. Hier, das hat mir Glück gebracht. Mir nicht, aber vielleicht dir.', who = 'Rolf', mood = 3, react = 'laugh', fx = { xp = 25, give = 'hufeisen', note = '🧲 Rolf hat dir ein Glückshufeisen geschenkt. Es liegt bei deinem Zubehör.' } },
    nett2 = { say = 'Schlau. Macht eh nur krank. Mach’s gut, Großer.', mood = 2, react = 'nod', fx = { xp = 15 } },
    raub = { bed = 'droh', say = 'Okay, hör gut zu. Portemonnaie. Durch den Spalt. Jetzt.', mood = -4, react = 'threat', ch = {
      { t = 'Geld rausgeben', sub = '%ROB% sind weg, aber dir passiert nichts', to = 'gezahlt', fx = { rob = 1, why = 'Überfall auf dem Rastplatz' } },
      { t = '„Der CB-Funk ist offen. Alle hören gerade mit.“', sub = 'bluffen', roll = { 0.72, 'flieht', 'scheibe' } },
      { t = 'Volle Hupe, Fernlicht, Warnblinker', roll = { 0.82, 'flieht', 'scheibe' } } } },
    gezahlt = { nar = true, say = 'Er greift sich das Geld, tritt einmal gegen deinen Reifen und verschwindet zwischen den Lastern. Deine Hände zittern noch ein bisschen.', mood = -1, react = 'sneer', fx = { tired = -0.15 } },
    flieht = { nar = true, say = 'Er zuckt zusammen, schaut sich um und rennt los. Zwei Fahrer steigen aus und schauen, was los ist. Noch mal gut gegangen.', react = 'shock', fx = { xp = 60 } },
    scheibe = { nar = true, say = 'Ein Schlag mit dem Schraubenschlüssel, Glas splittert. Er langt durch das Fenster, greift dein Geld und ist weg. Die Scheibe kostet extra.', react = 'threat', fx = { rob = 1.7, why = 'Überfall: Bargeld und Seitenscheibe' } },
  } },
  kollege = { bed = 'warm', who = 'Kollege', face = 'trucker', start = 'a', mood = 2, n = {
    a = { say = 'Moin! Ich hab Kaffee übrig, frisch aus der Kanne. Magst du einen?', react = 'nod', ch = {
      { t = '„Immer her damit.“', to = 'kaffee', mood = 1 }, { t = '„Danke, ich muss gleich weiter.“', to = 'eilig' } } },
    kaffee = { say = 'Pass auf, was ich gehört habe: Die blitzen neuerdings an jeder zweiten Baustelle, und die Kollegen von der Kontrolle lesen jetzt alles aus. Halt deine Pausen ein, sonst wird’s teuer.', react = 'think', fx = { tired = -0.25, xp = 25, note = '☕ Der Kaffee tut gut. Du bist wacher.' }, ch = {
      { t = '„Wie läuft’s bei dir?“', to = 'jammer', mood = 1 }, { t = '„Danke dir. Gute Fahrt!“' } } },
    jammer = { say = 'Ach. Disponent ruft nachts an, Frau will die Scheidung, Kupplung rutscht. Aber der Kaffee ist gut. Man muss das Positive sehen.', react = 'laugh', fx = { xp = 15 } },
    eilig = { say = 'Immer dieser Stress. Na dann, Gute Fahrt und Kopf hoch.', react = 'nod' },
  } },
  tramper = { bed = 'warm', who = 'Anhalterin', face = 'hitch', start = 'a', mood = 1, n = {
    a = { say = 'Hi! Sorry, ich stehe hier seit vier Stunden. Nimmst du mich ein Stück mit? Ich zahl auch was dazu.', react = 'nervous', ch = {
      { t = '„Steig ein.“', sub = 'sie fährt ein Stück mit', to = 'rein', fx = { hitch = true } },
      { t = '„Wohin soll’s denn gehen?“', to = 'wohin', mood = 1 },
      { t = '„Ich darf niemanden mitnehmen, sorry.“', to = 'nein', mood = -1 } } },
    wohin = { say = 'Egal, Hauptsache weg von diesem Rastplatz. Hier riecht alles nach Currywurst und schlechten Entscheidungen.', react = 'laugh', ch = {
      { t = '„Na gut, steig ein.“', to = 'rein', fx = { hitch = true } }, { t = '„Tut mir leid, heute nicht.“', to = 'nein' } } },
    rein = { nar = true, say = 'Sie wirft den Rucksack in die Kabine und legt die Füße aufs Armaturenbrett. Das kann ja was werden.', mood = 2, react = 'laugh' },
    nein = { say = 'Schon gut. Trotzdem gute Fahrt.', react = 'sad' },
  } },
  diesel = { bed = 'komisch', who = 'Mann mit Kanister', face = 'shady', start = 'a', n = {
    a = { say = 'Psst, Chef. 200 Liter Diesel, halber Preis. Ist sozusagen vom Laster gefallen.', react = 'wink', ch = {
      { t = '„Her damit.“', sub = 'kostet 180 €', cost = 180, roll = { 0.62, 'gut', 'schlecht' }, fx = { pay = -180, cat = 'Diesel', why = 'Diesel vom Parkplatz' } },
      { t = '„Ist der auch sauber?“', to = 'sauber', mood = 1 },
      { t = '„Kein Interesse.“', to = 'nein', mood = -1 } } },
    sauber = { say = 'Sauber? Der ist so sauber wie meine Weste, mein Freund. Schau nicht so. Ich mach dir 150.', react = 'sneer', ch = {
      { t = '„Na gut, 150.“', sub = 'kostet 150 €', cost = 150, roll = { 0.62, 'gut', 'schlecht' }, fx = { pay = -150, cat = 'Diesel', why = 'Diesel vom Parkplatz' } },
      { t = '„Lass mal gut sein.“', to = 'nein' } } },
    gut = { nar = true, say = 'Er pumpt die Kanister in deinen Tank und ist weg, bevor du Danke sagen kannst. Der Motor läuft rund.', mood = 2, react = 'laugh', fx = { diesel = 200, note = '⛽ 200 Liter im Tank. Hat gepasst.' } },
    schlecht = { nar = true, say = 'Der Tank ist voll, aber das Zeug riecht nach Heizöl und altem Frittenfett. Nach ein paar Minuten ruckelt der Motor.', mood = -2, react = 'sneer', fx = { diesel = 200, fail = 'hose', note = '⚠ Das war kein guter Diesel. Der Motor geht in den Notlauf.' } },
    nein = { say = 'Dein Pech. Beim nächsten Mal zahlst du wieder voll.', react = 'sneer' },
  } },
  paket = { bed = 'rast', who = 'Mann im Anzug', face = 'shady', start = 'a', n = {
    a = { say = 'Sie fahren doch weiter? Ein kleines Päckchen, wird unterwegs abgeholt. 900 € bar. Nicht reinschauen, keine Fragen.', react = 'think', ch = {
      { t = '„Her damit.“', sub = '900 € sofort, aber bei einer Kontrolle wird es sehr teuer', to = 'ja', fx = { pay = 900, cat = 'Sonstiges', why = 'Kurierfahrt ohne Fragen', pack = true } },
      { t = '„Was ist da drin?“', to = 'was', mood = -1 },
      { t = '„Vergessen Sie’s.“', to = 'nein' } } },
    was = { say = 'Keine Fragen, sagte ich. Das Angebot gilt jetzt noch genau zehn Sekunden.', react = 'threat', ch = {
      { t = '„Na gut.“', sub = '900 € sofort, aber bei einer Kontrolle wird es sehr teuer', to = 'ja', fx = { pay = 900, cat = 'Sonstiges', why = 'Kurierfahrt ohne Fragen', pack = true } },
      { t = '„Nein danke.“', to = 'nein' } } },
    ja = { say = 'Kluger Mann. Unter den Sitz damit. Sie werden angerufen.', mood = 3, react = 'wink' },
    nein = { nar = true, say = 'Er mustert dich, schließt das Sakko und geht ohne ein Wort zu seinem Wagen. Kein Kennzeichen zu erkennen.', mood = -1, react = 'sneer' },
  } },
  opa = { bed = 'warm', who = 'Alter Fahrer', face = 'old', start = 'a', mood = 2, n = {
    a = { say = 'Na, Jungspund? Weißt du, 1974 sind wir noch ohne Servolenkung über den Brenner. Im Schneesturm. Bergauf. In beide Richtungen.', react = 'laugh', ch = {
      { t = '„Erzähl mal.“', sub = 'dauert, aber man lernt was', to = 'erzaehl', mood = 1 },
      { t = '„Bergauf in beide Richtungen?“', to = 'zweifel', mood = -1 },
      { t = '„Ich muss leider los.“', to = 'los' } } },
    erzaehl = { say = 'Nie auf der Bremse den Berg runter, Junge. Runterschalten. Und nimm das hier. Hat mich vierzig Jahre begleitet, und ich hab nur einen Finger verloren.', mood = 2, react = 'nod', fx = { xp = 90, give = 'kette', note = '📿 Der Alte hat dir seine Perlenkette geschenkt. Sie liegt bei deinem Zubehör.' } },
    zweifel = { say = 'Werd nicht frech! Ihr mit euren Tempomaten. Früher war der Tempomat ein Ziegelstein.', react = 'shake', fx = { xp = 10 } },
    los = { say = 'Immer eilig. Das steht dann mal auf eurem Grabstein: Er war pünktlich.', react = 'shake' },
  } },
  panne = { bed = 'rast', who = 'Autofahrerin', face = 'woman', start = 'a', mood = 0, n = {
    a = { say = 'Entschuldigung! Mein Auto springt nicht mehr an und ich komme nicht weiter. Haben Sie vielleicht ein Starthilfekabel?', react = 'nervous', ch = {
      { t = 'Kabel holen und helfen', roll = { 0.82, 'danke', 'trick' }, mood = 2 },
      { t = 'Ihr 40 € für den Abschlepper geben', cost = 40, to = 'geld', fx = { pay = -40, cat = 'Sonstiges', why = 'Geld für eine Fremde' } },
      { t = '„Der Pannendienst ist schneller.“', to = 'nein', mood = -1 } } },
    danke = { nar = true, say = 'Zwei Minuten später läuft ihr Motor. Sie drückt dir einen Fünfziger in die Hand und lässt sich nicht davon abbringen.', mood = 3, react = 'laugh', fx = { pay = 50, cat = 'Sonstiges', why = 'Dankeschön für Starthilfe', xp = 80 } },
    trick = { nar = true, say = 'Während du am Kabel hantierst, sitzt jemand anderes kurz in deiner Kabine. Das Auto springt natürlich sofort an. Und dein Bargeld fehlt.', mood = -3, react = 'sneer', fx = { rob = 0.6, why = 'Trickdiebstahl auf dem Rastplatz' } },
    geld = { say = 'Vielen, vielen Dank! Sie sind ein Engel.', mood = 2, react = 'laugh', fx = { xp = 40, msg = 'Zwei Rastplätze weiter erzählt dir ein Kollege von einer Frau mit Autopanne, die seit Monaten sehr gut davon lebt.' } },
    nein = { say = 'Ja. Natürlich. Danke auch.', react = 'sad' },
  } },
  schlitzer = { bed = 'droh', knock = 2, who = 'Kollege', face = 'trucker', start = 'a', need = 'trailer', mood = -1, n = {
    a = { say = 'Eh! Da schleichen zwei Typen um deinen Auflieger. Einer hat ein Messer, der schlitzt dir gleich die Plane auf!', react = 'nervous', ch = {
      { t = 'Raus und hinrennen', roll = { 0.58, 'vertrieben', 'pruegel' } },
      { t = 'Polizei rufen und im Lkw bleiben', roll = { 0.7, 'polizei', 'zuspaet' }, mood = 1 },
      { t = 'Hupen und Licht an', roll = { 0.62, 'vertrieben2', 'zuspaet' } } } },
    vertrieben = { nar = true, say = 'Du brüllst quer über den Parkplatz. Sie lassen alles fallen und rennen zum Transporter. Die Ladung ist komplett.', mood = 4, react = 'laugh', fx = { xp = 130 } },
    vertrieben2 = { nar = true, say = 'Der halbe Rasthof wacht auf. Die beiden hauen ab. Die Plane hat nur einen kleinen Schnitt.', mood = 3, react = 'nod', fx = { xp = 70 } },
    pruegel = { nar = true, say = 'Der Zweite steht hinter dem Auflieger. Ein Schlag, und du sitzt auf dem Asphalt. Sie nehmen ein paar Paletten mit, und der Arzt will auch noch Geld.', mood = -3, react = 'shock', fx = { pay = -220, cat = 'Sonstiges', why = 'Arztkosten nach Überfall', freight = 0.8, note = '📦 Ein Teil der Ladung ist weg. Der Auftrag bringt weniger.' } },
    polizei = { nar = true, say = 'Ein Streifenwagen rollt mit Blaulicht auf den Platz. Die beiden werden direkt am Transporter festgenommen. Dein Name steht lobend im Bericht.', mood = 3, react = 'laugh', fx = { xp = 100 } },
    zuspaet = { nar = true, say = 'Bis sich etwas tut, sind sie längst weg. Mit einem Teil deiner Ladung.', mood = -2, react = 'sad', fx = { freight = 0.75, note = '📦 Ein Teil der Ladung ist weg. Der Auftrag bringt weniger.' } },
  } },
  uhr = { bed = 'komisch', who = 'Verkäufer', face = 'shady', start = 'a', n = {
    a = { say = 'Mein Freund! Echte Schweizer Uhr, nur heute. Chronolax Imperial, 150 Euro. Original! Fast.', react = 'wink', ch = {
      { t = '„Her damit.“', sub = 'kostet 150 €', cost = 150, roll = { 0.08, 'echt', 'fake' }, fx = { pay = -150, cat = 'Sonstiges', why = 'Uhr vom Rastplatz' } },
      { t = '„60 und keinen Cent mehr.“', to = 'handeln', mood = 1 },
      { t = '„Warum steht da Chronolax?“', to = 'rollax' } } },
    handeln = { say = '60?! Meine Kinder müssen hungern! 80, und ich lege eine Sonnenbrille drauf.', react = 'shock', ch = {
      { t = '„Abgemacht.“', sub = 'kostet 80 €', cost = 80, roll = { 0.08, 'echt', 'fake' }, fx = { pay = -80, cat = 'Sonstiges', why = 'Uhr vom Rastplatz' } },
      { t = '„Vergiss es.“', to = 'nein' } } },
    rollax = { say = 'Das ist die Exportversion. Die ist sogar seltener. Sehr selten. Eigentlich nur hier.', react = 'nervous', ch = {
      { t = '„Na gut, ich nehme sie.“', sub = 'kostet 150 €', cost = 150, roll = { 0.08, 'echt', 'fake' }, fx = { pay = -150, cat = 'Sonstiges', why = 'Uhr vom Rastplatz' } },
      { t = '„Tschüss.“', to = 'nein' } } },
    echt = { nar = true, say = 'Du gehst damit zum Pfandleiher im nächsten Ort. Der Mann wird blass. Das Ding ist echt und vermutlich geklaut. Er gibt dir trotzdem 2.400 €.', mood = -2, react = 'shock', fx = { pay = 2400, cat = 'Sonstiges', why = 'Uhr verkauft', xp = 40 } },
    fake = { nar = true, say = 'Zwanzig Minuten später bleiben die Zeiger stehen. Kurz danach fällt die Krone ab. Dein Handgelenk ist jetzt grün.', mood = 3, react = 'laugh' },
    nein = { say = 'Du bereust das. Morgen kostet sie 300.', react = 'sneer' },
  } },
  dealer = { bed = 'komisch', who = 'Typ mit Mütze', face = 'stoned', start = 'a', mood = 2, n = {
    a = { say = 'Boah, Bruder, voll der große Lkw. Brauchst du was zum Runterkommen? Zwei Tüten, 30 Euro. Beste Qualität. Glaub ich.', react = 'laugh', ch = {
      { t = '„Gib her.“', sub = 'kostet 30 €', cost = 30, roll = { 0.7, 'ware', 'oregano' }, fx = { pay = -30, cat = 'Sonstiges', why = 'Einkauf auf dem Rastplatz' } },
      { t = '„Bist du wirklich Dealer?“', to = 'zivil', mood = -1 },
      { t = '„Nein danke, ich fahre noch.“', to = 'nein' } } },
    zivil = { say = 'Äh. Klar. Also. Was heißt Dealer. Willst du was kaufen, ja oder nein? Für die Akten. Äh. Für mich.', react = 'nervous', ch = {
      { t = '„Ja, her damit.“', sub = 'kostet 30 €', cost = 30, roll = { 0.35, 'ware', 'zivilbeamter' }, fx = { pay = -30, cat = 'Sonstiges', why = 'Einkauf auf dem Rastplatz' } },
      { t = '„Nein. Schönen Dienst noch.“', to = 'erwischt', mood = 1 } } },
    ware = { nar = true, say = 'Er drückt dir zwei krumme Tüten in die Hand, starrt lange deinen Außenspiegel an und sagt: „Der hat Augen, Mann.“ Dann geht er.', mood = 2, react = 'laugh', fx = { cab = 'joint', n = 2, note = '🌿 Zwei Joints liegen jetzt in der Kabine.' } },
    oregano = { nar = true, say = 'Du riechst daran. Das ist Oregano. Eindeutig Oregano. Immerhin Bio. Pizza wäre jetzt gut.', mood = 3, react = 'laugh' },
    zivilbeamter = { bed = 'polizei', who = 'Zivilpolizist', say = 'So. Dann hätten wir das. Kriminalpolizei, die Mütze ist nur geliehen. Das wird jetzt teuer, Herr Fahrer.', mood = -3, react = 'threat', fx = { fine = 600, why = 'Ankauf von Betäubungsmitteln auf dem Rastplatz' } },
    erwischt = { say = 'Mist. Woran hast du es gemerkt? Die Mütze, oder? Ich hab denen gesagt, die Mütze ist zu viel.', react = 'sad', fx = { xp = 40 } },
    nein = { say = 'Voll vernünftig, Bruder. Voll. Ich steh hier auch nur.', react = 'nod' },
  } },
  huetchen = { bed = 'komisch', who = 'Spieler', face = 'shady', start = 'a', mood = 1, n = {
    a = { say = 'Ein kleines Spiel gegen die Langeweile? Drei Becher, eine Kugel. 50 Euro Einsatz, 150 zurück. Ganz einfach. Na?', react = 'wink', ch = {
      { t = '„Na gut, ich spiele.“', sub = 'Einsatz 50 €', cost = 50, to = 'becher', fx = { pay = -50, cat = 'Sonstiges', why = 'Hütchenspiel' } },
      { t = '„Ich bin doch nicht blöd.“', to = 'nein', mood = -1 } } },
    becher = { say = 'Rechts, links, Mitte, rechts, oben, unten. Na? Wo ist die Kugel, mein Freund?', react = 'sneer', ch = {
      { t = 'Linker Becher', roll = { 0.2, 'sieg', 'verlust' } }, { t = 'Mittlerer Becher', roll = { 0.2, 'sieg', 'verlust' } }, { t = 'Rechter Becher', roll = { 0.2, 'sieg', 'verlust' } } } },
    sieg = { say = 'Das ... das gibt’s doch gar nicht. Hier. Und jetzt verschwinde, bevor ich mich ärgere.', mood = -3, react = 'shock', fx = { pay = 150, cat = 'Sonstiges', why = 'Hütchenspiel gewonnen', xp = 30 } },
    verlust = { say = 'Ohhh, knapp daneben! Noch eine Runde? Beim nächsten Mal ganz bestimmt.', mood = 2, react = 'laugh', ch = {
      { t = '„Noch mal.“', sub = 'Einsatz 50 €', cost = 50, to = 'becher', fx = { pay = -50, cat = 'Sonstiges', why = 'Hütchenspiel' } },
      { t = '„Mir reicht’s.“', to = 'nein' } } },
    nein = { say = 'Schade. Du hattest so ein ehrliches Gesicht.', react = 'sneer' },
  } },
  aluhut = { bed = 'komisch', who = 'Mann mit Aluhut', face = 'nerd', start = 'a', mood = 1, n = {
    a = { say = 'Sie fahren viel, ja? Dann ist es Ihnen sicher auch aufgefallen: Es gibt gar keine Rastplätze. Das sind Kulissen. Die stellen die nachts um.', react = 'think', ch = {
      { t = '„Und wer stellt die um?“', to = 'wer', mood = 2 },
      { t = '„Gehen Sie bitte weg.“', to = 'weg', mood = -1 } } },
    wer = { say = 'Die Autobahnmeisterei! Warum sonst fahren die immer so langsam? Die messen uns. Hier, setzen Sie den auf. Schützt vor Blitzern. Und vor dem Finanzamt.', mood = 2, react = 'nervous', fx = { xp = 25, give = 'aluhut', note = '🛸 Du hast einen Aluhut bekommen. Er liegt bei deinem Zubehör.' } },
    weg = { say = 'Das sagen die alle. Bis die Möwen kommen. Die Möwen sind nicht echt, wissen Sie.', react = 'shake' },
  } },
}

function M.attach(t, ctx) st, X = t, ctx; st.seen = st.seen or {} end
function M.active() return E ~= nil end
function M.nextKm() return st and st.nextKm end
function M.setNext(km) st.nextKm = km + M.COOLDOWN_KM[1] + math.random() * (M.COOLDOWN_KM[2] - M.COOLDOWN_KM[1]) end

local function allowed(sc) return sc.need ~= 'trailer' or (X.job() and X.hasTrailer()) end
-- (not one of the last few again)
function M.pick()
  local list = {}
  for _, k in ipairs(M.ORDER) do
    local recent = false
    for _, s in ipairs(st.seen) do if s == k then recent = true end end
    if not recent and allowed(M.SC[k]) then list[#list + 1] = k end
  end
  if #list == 0 then st.seen = {}; return 'kollege' end
  return list[math.random(#list)]
end
-- (the test in the settings: one after the other, so each can be seen)
function M.nextForTest()
  for _ = 1, #M.ORDER do
    st.testI = ((st.testI or 0) % #M.ORDER) + 1
    local k = M.ORDER[st.testI]
    if allowed(M.SC[k]) then return k end
  end
  return 'kollege'
end

local function robSum() return math.max(60, math.min(450, math.floor(math.max(0, X.money()) * 0.04 / 10) * 10)) end
local function fill(s) return s and (s:gsub('%%ROB%%', X.fmt(E.rob))) or nil end
local function apply(fx)
  if not fx then return end
  if fx.rob then
    local a = math.min(math.max(0, X.money()), math.floor(E.rob * fx.rob / 10) * 10)
    if a > 0 then X.pay('Sonstiges', -a, fx.why or 'Überfall') end
    X.notify('💸 ' .. X.fmt(a) .. ' sind weg.', 7)
  end
  if fx.pay then X.pay(fx.cat or 'Sonstiges', fx.pay, fx.why or 'Rastplatz') end
  if fx.fine then E.fine = { fx.fine, fx.why } end
  if fx.xp then X.xp(fx.xp) end
  if fx.give then X.give(fx.give) end
  if fx.cab then X.cab(fx.cab, fx.n or 1) end
  if fx.tired then X.tired(fx.tired) end
  if fx.diesel then X.diesel(fx.diesel) end
  if fx.fail then E.fail = fx.fail end
  if fx.freight then X.freight(fx.freight) end
  if fx.note then E.notes = E.notes or {}; E.notes[#E.notes + 1] = fx.note end
  if fx.msg then E.msg = fx.msg end
  if fx.hitch then st.hitch = { km = X.km() + 15 + math.random() * 30 }; X.notify('🎒 Die Anhalterin fährt ein Stück mit.', 5) end
  if fx.pack then st.pack = { km = X.km() + 30 + math.random() * 40 } end
end
local function send()
  if not E or E.wait then return end
  X.trigger('FernfahrerCop', { id = E.id, who = E.who, face = E.sc.face, seed = E.seed, mood = E.mood, react = E.react, line = E.line, nar = E.nar, choices = E.list })
end
local function say(key)
  local n = E.sc.n[key]
  if not n then return M.finish() end
  E.mood = math.max(-4, math.min(4, E.mood + (n.mood or 0)))
  E.react, E.line, E.nar = n.react, fill(n.say), n.nar and true or nil
  if n.bed then X.bed(n.bed) end
  if n.who then E.who = n.who end
  apply(n.fx)
  E.list = {}
  for _, c in ipairs(n.ch or { { t = BYE } }) do
    if not c.cost or X.money() >= c.cost then
      E.list[#E.list + 1] = { t = c.t, sub = fill(c.sub), raw = c }
    end
  end
  if #E.list == 0 then E.list[1] = { t = BYE, raw = {} } end
  E.id = E.id + 1
  local out = {}
  for i, c in ipairs(E.list) do out[i] = { t = c.t, sub = c.sub } end
  E.raws, E.list = E.list, out
  send()
end

function M.start(key)
  local sc = M.SC[key]
  if E or not sc then return false end
  st.seen[#st.seen + 1] = key
  while #st.seen > 6 do table.remove(st.seen, 1) end
  -- (the music dies away, a moment of nothing, a knock on the left; only then the head turns, and someone is standing there)
  local c = os.clock()
  E = { key = key, sc = sc, id = 0, seed = math.random(1, 4000), mood = (sc.mood or 0) + math.random(-1, 1), rob = robSum(), who = sc.who, node = sc.start,
    knockAt = c + 1.6, lookAt = c + 3.3, wait = c + 4.6 }
  X.bed(false)
  X.stage(M.SHAPE .. sc.face .. '.dae')
  return true
end
function M.answer(i)
  if not E or E.wait then return end
  local c = E.raws and E.raws[tonumber(i) or 1]
  if not c then return end
  local r = c.raw
  E.mood = math.max(-4, math.min(4, E.mood + (r.mood or 0)))
  apply(r.fx)
  if r.roll then
    local p = math.max(0.04, math.min(0.96, r.roll[1] + E.mood * 0.07))
    return say(math.random() < p and r.roll[2] or r.roll[3])
  end
  if r.to then return say(r.to) end
  M.finish()
end
function M.finish()
  local e = E
  E = nil
  X.trigger('FernfahrerCop', { off = true })
  X.look(false)
  X.clean()
  if not e then return end
  for _, s in ipairs(e.notes or {}) do X.notify(s, 8) end
  if e.msg then X.message(e.msg, 'CB-Funk') end
  if e.fine then X.fine(e.fine[1], e.fine[2]) end
  if e.fail then X.fail(e.fail) end
  X.save()
end
-- every second: the camera has turned, and the HUD may have been rebuilt; driven off: the talk is over
function M.tick(moving)
  if not E then return end
  if moving then
    X.notify('Du lässt den Motor an und fährst einfach los.', 4)
    return M.finish()
  end
  local c = os.clock()
  if E.knockAt and c >= E.knockAt then E.knockAt = nil; X.knock(E.sc.knock) end
  if E.lookAt and c >= E.lookAt then E.lookAt = nil; X.look(true) end
  if E.wait then
    if c >= E.wait then E.wait = nil; X.bed(E.sc.bed); say(E.node); E.sent = c end
    return
  end
  if c - (E.sent or 0) >= 1 then E.sent = c; send() end
end
function M.reset() if E then M.finish() end end

-- what came along: the hitchhiker gets off, the parcel is fetched
function M.kmTick(km)
  if not st then return end
  if st.hitch and km >= st.hitch.km then
    st.hitch = nil
    local r = math.random()
    if r < 0.68 then
      X.pay('Sonstiges', 40, 'Anhalterin hat sich beteiligt'); X.xp(40)
      X.message('Sie steigt an der nächsten Ausfahrt aus, drückt dir 40 € in die Hand und malt einen Smiley auf die beschlagene Scheibe.', 'Anhalterin')
    elseif r < 0.88 then
      local a = math.min(math.max(0, X.money()), 120)
      if a > 0 then X.pay('Sonstiges', -a, 'Anhalterin') end
      X.message('Sie steigt aus und winkt noch. Erst später merkst du, dass ' .. X.fmt(a) .. ' aus der Ablage fehlen.', 'Anhalterin')
    else
      X.give('wimpelkette'); X.xp(40)
      X.message('Zum Abschied hängt sie dir eine Wimpelkette in die Kabine. Sie liegt bei deinem Zubehör.', 'Anhalterin')
    end
    X.save()
  end
  if st.pack and km >= st.pack.km then
    st.pack = nil
    X.message('Ein schwarzer Wagen blendet auf, jemand nimmt das Päckchen an sich und ist weg. Noch mal gut gegangen.', 'Unbekannt')
    X.save()
  end
end
-- at a check the parcel is found
function M.contraband(found)
  if st and st.pack then
    st.pack = nil
    found[#found + 1] = { kind = 'pack', amount = 3500, reason = 'Päckchen ohne Papiere und mit unklarem Inhalt im Führerhaus' }
  end
end
return M
