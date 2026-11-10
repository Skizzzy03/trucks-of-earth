-- Trucks of Earth (2026-11-10): what the hitchhiker talks about on the way. Each ride she has one story of her own, told in three parts
-- between other things (a question, something outside, a snack), so no two rides are the same. Data only; fernfahrer/crew.lua plays it.
-- A topic: { say, ch = { { t (the driver's answer), r (her reply), m (mood) } } }. %CARGO% in a text: what the truck carries.
local M = {}

M.NAMES = { 'Lea', 'Mia', 'Jana', 'Svenja', 'Kim', 'Nele', 'Paula', 'Merle', 'Ronja', 'Fenja', 'Ida', 'Lotte' }

M.STORIES = {
  { -- the night out
    { say = 'Ich hab seit gestern Abend nicht geschlafen. Erst Geburtstag, dann Club, dann irgendeine Afterhour in einer Garage. Frag nicht, wessen Garage.', ch = {
      { t = '„Wessen Garage?“', r = 'Hab ich doch gesagt, frag nicht! Keine Ahnung. Da stand ein Boot drin. Und eine Discokugel. Und ein Typ, der Opa genannt wurde, aber höchstens 25 war.', m = 2 },
      { t = '„Klingt nach einer langen Nacht.“', r = 'Lang ist gar kein Ausdruck. Ich glaub, ich hab um sechs mit einem Briefträger getanzt.', m = 1 } } },
    { say = 'Ich riech bestimmt nach Nebelmaschine und Jägermeister. Sorry. Darf ich das Fenster einen Spalt aufmachen?', ch = {
      { t = '„Mach ruhig, ich riech eh nur noch Diesel.“', r = 'Sie kurbelt das Fenster runter, hält das Gesicht in den Wind und schreit kurz „Jaaa!“ in die Landschaft. Danach geht’s ihr sichtlich besser.', m = 2 },
      { t = '„Lass zu, sonst zieht’s.“', r = 'Okay, Opa. Ich meine, okay, Chef.', m = -1 } } },
    { say = 'Weißt du, was das Beste an so Nächten ist? Am Ende sitzt man mit Fremden irgendwo und erzählt sich Sachen, die man sonst keinem erzählt.', ch = {
      { t = '„So wie jetzt hier.“', r = 'Genau so. Du bist mein Afterhour-Ersatz. Nur ohne Discokugel. Wobei, du könntest eine aufhängen.', m = 2 },
      { t = '„Ich geh lieber früh schlafen.“', r = 'Langweiler. Aber ein ausgeschlafener Langweiler, der mich mitnimmt. Das zählt.', m = 0 } } },
  },
  { -- the smoker
    { say = 'Stört’s dich, wenn ich rauche? Ich mach auch das Fenster auf. Versprochen, ich ascher nicht auf deinen Sitz.', ch = {
      { t = '„Fenster auf und los.“', r = 'Sie zündet sich eine an, bläst den Rauch genau gegen den Fahrtwind, und er kommt komplett zurück in die Kabine. Ihr müsst beide husten und lachen.', m = 2 },
      { t = '„Nicht in meinem Lkw.“', r = 'Okay, okay. Dann kau ich halt auf der Zigarette rum. Ist eh gesünder.', m = -1 } } },
    { say = 'Ich will eigentlich aufhören. Seit drei Jahren. Jeden Montag. Montag ist irgendwie nie der richtige Tag.', ch = {
      { t = '„Dienstag ist auch ein schöner Tag.“', r = 'Dienstag! Warum ist da noch keiner drauf gekommen? Ab Dienstag rauch ich nicht mehr. Wahrscheinlich.', m = 2 },
      { t = '„Dann hör halt einfach auf.“', r = 'Sagt sich so leicht. Hast du schon mal einfach aufgehört? Mit irgendwas?', m = 0 } } },
    { say = 'Hier, ich lass dir die Schachtel da. Wenn ich sie behalte, werd ich am Dienstag schwach.', ch = {
      { t = '„Danke, ich heb sie für dich auf.“', r = 'Du bist ein Held. Ein Held mit Zigaretten. Ruf mich nicht an, wenn ich am Dienstag frage.', m = 2, fx = 'cig' },
      { t = '„Wirf sie lieber weg.“', r = 'Sie wirft die Schachtel in den Mülleimer der nächsten Raststätte. Dann holt sie sie wieder raus. Dann wirft sie sie wieder rein. Fortschritt.', m = 1 } } },
  },
  { -- the open-air rave
    { say = 'Heute Nacht ist ein Rave im Wald. Ganz geheim, die Koordinaten kriegt man erst zwei Stunden vorher. Ich hab sie schon. Willst du sie hören?', ch = {
      { t = '„Erzähl!“', r = 'Nein, war ein Witz, ist geheim! Aber da ist ein See, ein Soundsystem auf einem Traktor und ein DJ, der nur mit Schallplatten von seinem Vater auflegt.', m = 2 },
      { t = '„Wald und laute Musik? Die armen Rehe.“', r = 'Die Rehe kommen jedes Jahr! Letztes Jahr stand eins direkt vor der Box. Hat gar nicht schlecht getanzt.', m = 1 } } },
    { say = 'Ich hab Glitzer im Rucksack. Jede Menge. Darf ich dir ein bisschen auf die Wangen machen? Nur zum Testen.', ch = {
      { t = '„Na gut. Aber nur ein bisschen.“', r = 'Sie tupft dir Glitzer ins Gesicht. Viel mehr als ein bisschen. Den kriegst du die nächsten drei Wochen nicht mehr ab. Im Spiegel sieht’s ehrlich gesagt ziemlich gut aus.', m = 3 },
      { t = '„Ich muss morgen zur Kontrolle.“', r = 'Haha, stell dir das Gesicht vom Polizisten vor. Okay, kein Glitzer. Für dich.', m = 0 } } },
    { say = 'Wenn ich da bin, tanz ich bis die Sonne aufgeht. Und dann noch ein bisschen. Und dann such ich mir jemanden, der mich wieder mitnimmt.', ch = {
      { t = '„Ich hab dann bestimmt Pause in der Nähe.“', r = 'Echt? Dann halt Ausschau nach dem einzigen Mädchen mit Glitzer im Gesicht. Also nach allen.', m = 2 },
      { t = '„Pass auf dich auf da.“', r = 'Mach ich. Ich hab Wasser dabei, Ohrstöpsel und eine Freundin, die immer nüchtern bleibt. Die ist der Boss.', m = 1 } } },
  },
  { -- her sister
    { say = 'Meine Schwester weiß gar nicht, dass ich komme. Wir haben seit zwei Jahren nicht miteinander geredet.', ch = {
      { t = '„Warum nicht?“', r = 'Wegen eines Pferdes. Also eigentlich wegen eines Mannes, der ein Pferd hatte. Lange Geschichte.', m = 1 },
      { t = '„Klingt nach Ärger.“', r = 'Kann sein. Aber ich hab Kuchen dabei. Kuchen hilft immer.', m = 0 } } },
    { say = 'Ich überlege die ganze Zeit, was ich ihr sage. Nur „Hallo“ ist zu wenig, oder?', ch = {
      { t = '„Sag ihr einfach, dass sie dir fehlt.“', r = 'Hm. Das ist eigentlich ziemlich gut. Darf ich das klauen?', m = 2 },
      { t = '„Lass den Kuchen sprechen.“', r = 'Ha! Der Kuchen ist allerdings schon halb gegessen. Nervennahrung.', m = 1 } } },
    { say = 'Ich glaub, ich bin bereit. Danke fürs Zuhören. Fremde sind manchmal die besten Zuhörer.', ch = {
      { t = '„Das wird schon.“', r = 'Ja. Wird es.', m = 1 },
      { t = '„Erzähl mir irgendwann, wie’s gelaufen ist.“', r = 'Ich schick dir eine Postkarte. An „den netten Lkw-Fahrer“. Kommt bestimmt an.', m = 2 } } },
  },
  { -- the festival
    { say = 'Ich komme gerade von einem Festival. Drei Tage Regen, zwei Stunden Schlaf, ein Gummistiefel weniger.', ch = {
      { t = '„Und, hat’s sich gelohnt?“', r = 'Absolut. Die beste Band hat im Schlamm gespielt, weil die Bühne abgesoffen ist. Legendär.', m = 1 },
      { t = '„Nur einer? Wo ist der andere?“', r = 'Steckt irgendwo vor der Hauptbühne. Ich glaube, er hat jetzt da ein neues Leben.', m = 1 } } },
    { say = 'Weißt du, was das Schönste war? Nachts um vier haben hundert Leute zusammen ein Kinderlied gesungen. Wildfremde Leute.', ch = {
      { t = '„Welches denn?“', r = '„Alle meine Entchen“. In drei Tonarten gleichzeitig. Es war furchtbar und wunderschön.', m = 2 },
      { t = '„Klingt eher anstrengend.“', r = 'Du warst halt nicht dabei. Man muss das gefühlt haben.', m = -1 } } },
    { say = 'Nächstes Jahr fahr ich wieder hin. Mit zwei Gummistiefeln. Willst du mit?', ch = {
      { t = '„Nur, wenn ich den Lkw als Bühne kriege.“', r = 'Deal! Ich sag den Veranstaltern Bescheid. Die nehmen bestimmt alles.', m = 2 },
      { t = '„Ich bin zu alt für Schlamm.“', r = 'Für Schlamm ist niemand zu alt. Nur zu sauber.', m = 0 } } },
  },
  { -- the job interview
    { say = 'Ich hab morgen ein Vorstellungsgespräch. Im Zoo. Als Tierpflegerin bei den Pinguinen.', ch = {
      { t = '„Wie cool ist das denn!“', r = 'Oder? Ich hab schon geübt, wie ein Pinguin zu gucken. Damit sie mich als eine von ihnen sehen.', m = 2 },
      { t = '„Riecht das nicht nach Fisch?“', r = 'Den ganzen Tag. Aber Pinguine verurteilen dich nie. Anders als Menschen.', m = 0 } } },
    { say = 'Was meinst du, was fragen die bei so einem Gespräch? „Wo sehen Sie sich in fünf Jahren?“ Im Eiswasser, schätze ich.', ch = {
      { t = '„Sag ihnen, du liebst Kälte.“', r = 'Gute Idee. Ich hab mal im Februar die Heizung ausgelassen, um Geld zu sparen. Das zählt bestimmt.', m = 1 },
      { t = '„Erzähl einfach von dir.“', r = 'Okay. Ich hatte als Kind ein Kuscheltier-Pinguin namens Herbert. Das muss reichen.', m = 1 } } },
    { say = 'Wenn ich den Job kriege, darfst du die Pinguine umsonst besuchen. Versprochen.', ch = {
      { t = '„Dann drück ich dir die Daumen.“', r = 'Danke. Und ich grüße Herbert von dir. Den echten Herbert, falls es da einen gibt.', m = 2 },
      { t = '„Ich nehm lieber die Eisbären.“', r = 'Verräter. Aber gut, ich frag mal nach.', m = 0 } } },
  },
  { -- across Europe
    { say = 'Ich trampe seit drei Monaten. Angefangen in Lissabon. Jetzt geht’s nach Hause.', ch = {
      { t = '„Drei Monate? Respekt.“', r = 'Danke. Meine Mutter hält mich für verrückt. Mein Vater hat mir heimlich Geld zugesteckt.', m = 1 },
      { t = '„Ist das nicht gefährlich?“', r = 'Manchmal. Aber die meisten sind nett. So wie du. Glaube ich. Bist du nett?', m = 0 } } },
    { say = 'Ich sammle Geschichten von allen, die mich mitnehmen. Ein Portugiese hat mir erzählt, wie er einen Hai gefangen hat. Mit der Hand. Erzählst du mir auch eine?', ch = {
      { t = 'Von der verrücktesten Ladung erzählen', r = 'Nein! Echt jetzt? Das kommt ganz oben in mein Heft. Gleich neben den Hai.', m = 2 },
      { t = '„Bei mir passiert nichts Spannendes.“', r = 'Das sagen alle. Und dann erzählen sie von dem Tag, an dem ihr Lkw im Schnee stecken blieb.', m = 0 } } },
    { say = 'Das Komische am Reisen ist: Je weiter man fährt, desto mehr freut man sich auf zu Hause.', ch = {
      { t = '„Das kenne ich gut.“', r = 'Klar. Du bist ja auch immer unterwegs. Wo ist eigentlich dein Zuhause?', m = 1 },
      { t = '„Ich bin lieber unterwegs.“', r = 'Vielleicht ist der Lkw dein Zuhause. Mit Kaffeemaschine und allem.', m = 1 } } },
  },
  { -- the student
    { say = 'Ich studiere Physik. Wusstest du, dass ein Lkw im Windschatten bis zu einem Drittel weniger Diesel braucht?', ch = {
      { t = '„Klar, deshalb fahren wir ja Kolonne.“', r = 'Siehst du, du bist eigentlich ein Physiker. Nur mit Lenkrad.', m = 2 },
      { t = '„Und wozu braucht man das?“', r = 'Um coole Fakten im Lkw zu erzählen. Und für meine Prüfung am Montag.', m = 0 } } },
    { say = 'Meine Prüfung ist über Reibung. Ich verstehe alles, nur nicht, warum mein Professor nie lacht.', ch = {
      { t = '„Vielleicht zu viel Reibung?“', r = 'Haha! Den Witz erzähl ich ihm. Wenn ich durchfalle, ist es deine Schuld.', m = 2 },
      { t = '„Professoren lachen nie.“', r = 'Doch. Einmal. Als jemand die Tafel umgeworfen hat.', m = 1 } } },
    { say = 'Weißt du was? Wenn ich fertig bin, rechne ich aus, wie viel Kaffee ein Fernfahrer pro Kilometer braucht.', ch = {
      { t = '„Zu viel. Das kann ich dir gleich sagen.“', r = 'Empirische Daten. Wunderbar. Ich schreib dich als Quelle rein.', m = 2 },
      { t = '„Mach lieber was Sinnvolles.“', r = 'Das ist sinnvoll! Für die Wissenschaft und für alle Raststätten.', m = 0 } } },
  },
  { -- the band
    { say = 'Ich spiele Bass in einer Punkband. Wir haben heute Abend einen Auftritt. Leider ist unser Bus ohne mich losgefahren.', ch = {
      { t = '„Ohne die Bassistin? Frech.“', r = 'Ganz genau! Ich hab ihnen schon zwölf wütende Sprachnachrichten geschickt.', m = 1 },
      { t = '„Vielleicht merken die’s gar nicht.“', r = 'Beim Punk merkt man das tatsächlich nicht so schnell. Trotzdem.', m = 0 } } },
    { say = 'Unser bekanntestes Lied heißt „Autobahnkreuz“. Es hat drei Akkorde und ganz viel Geschrei.', ch = {
      { t = '„Sing mal!“', r = 'Sie trommelt auf das Armaturenbrett und brüllt den Refrain. Es ist laut. Es ist schief. Du musst lachen.', m = 2 },
      { t = '„Klingt nach meinem Feierabendverkehr.“', r = 'Genau davon handelt es! Du verstehst Punk besser als die meisten.', m = 1 } } },
    { say = 'Gerade hat der Schlagzeuger geschrieben. Die haben gemerkt, dass ich fehle. Sie warten auf mich.', ch = {
      { t = '„Na also. Rock on.“', r = 'Rock on! Wenn wir mal berühmt sind, kriegst du Freikarten. Erste Reihe.', m = 2 },
      { t = '„Hat ja lange gedauert.“', r = 'Drei Stunden. Für Punker ist das schnell.', m = 1 } } },
  },
}

M.SMALL = {
  { say = 'Hast du eigentlich ein Bier im Lkw? Für mich, nicht für dich. Du fährst ja.', ch = {
    { t = '„Im Kühlschrank ist eins.“', r = 'Sie macht es auf, nimmt einen Schluck und sagt „Prost auf den besten Chauffeur der Autobahn“. Du bleibst natürlich beim Kaffee.', m = 2 },
    { t = '„Nicht im Lkw.“', r = 'Okay, Herr Verkehrsminister. Dann eben Wasser. Langweiliges Wasser.', m = -1 } } },
  { say = 'Ich hab noch was vom Festival übrig. Selbst gedreht, wenn du verstehst. Ich lass es dir für den Feierabend da, nicht für unterwegs.', ch = {
    { t = '„Für den Feierabend? Na gut.“', r = 'Sie legt es ins Handschuhfach. „Aber erst, wenn der Motor aus ist. Versprochen?“ Versprochen.', m = 2, fx = 'joint' },
    { t = '„Nimm das lieber wieder mit.“', r = 'Auch gut. Mehr für den Rave. Du bist echt der Vernünftigste, den ich diese Woche getroffen hab.', m = 0 } } },
  { say = 'Mein Kopf brummt. Ich glaub, der letzte Shot war einer zu viel. Oder die letzten fünf.', ch = {
    { t = 'Eine Flasche Wasser rüberreichen', r = 'Du bist ein Engel. Ein Lkw-Engel. Sie trinkt die halbe Flasche auf einmal und lehnt den Kopf an die Scheibe.', m = 2 },
    { t = '„Selbst schuld.“', r = 'Ja, danke. Das hilft mir jetzt total.', m = -1 } } },
  { say = 'Kennst du das Gefühl, wenn man auf einer Party merkt, dass man der einzige ist, der den Text vom Lied kann? Ich bin immer die.', ch = {
    { t = '„Und dann singst du laut mit?“', r = 'Natürlich! Mit Mikrofon-Faust und allem. Willst du eine Kostprobe? Zu spät, sie singt schon.', m = 2 },
    { t = '„Ich kann keinen einzigen Text.“', r = 'Dann summst du halt. Summen kann jeder.', m = 0 } } },
  { say = 'Letzte Woche hab ich auf einer Hausparty den Rauchmelder mit einer Wunderkerze ausgelöst. Die Feuerwehr kam. Die haben dann mitgefeiert.', ch = {
    { t = '„Die Feuerwehr hat mitgefeiert?“', r = 'Zwei Lieder lang! Dann kam der Einsatzleiter. Der hat nicht mitgefeiert.', m = 2 },
    { t = '„Das hätte schiefgehen können.“', r = 'Ist es ja auch. Ein bisschen. Die Gardine hat jetzt ein Loch.', m = 0 } } },
  { say = 'Was hast du eigentlich geladen?', ch = {
    { t = '„%CARGO%.“', r = 'Ernsthaft? Ich hab gedacht, das wären mindestens Goldbarren. Aber gut, auch schön.', m = 1 },
    { t = '„Geheim.“', r = 'Oh. Jetzt bin ich neugierig. Und ein kleines bisschen nervös.', m = 0 } } },
  { say = 'Wie lange fährst du eigentlich schon Lkw?', ch = {
    { t = '„Gefühlt schon immer.“', r = 'Das merkt man. Du fährst so ruhig. Mein letzter Fahrer hat beim Schalten geflucht.', m = 1 },
    { t = '„Noch nicht so lange.“', r = 'Echt? Dafür machst du das echt gut. Ich hätte schon drei Leitpfosten mitgenommen.', m = 1 } } },
  { say = 'Darf ich das Radio ein bisschen lauter machen? Ich liebe dieses Lied.', ch = {
    { t = '„Klar, dreh auf.“', r = 'Sie dreht auf und singt den Refrain mit. Ziemlich falsch, aber mit voller Überzeugung.', m = 2 },
    { t = '„Lieber nicht, ich muss mich konzentrieren.“', r = 'Okay, okay. Ich summe dann nur. Ganz leise.', m = -1 } } },
  { say = 'Schau mal, da vorne die Kühe. Glaubst du, Kühe wissen, dass sie in Deutschland wohnen?', ch = {
    { t = '„Bestimmt. Die muhen auf Hochdeutsch.“', r = 'Haha! Und die bayerischen auf Bayerisch. Das erklärt einiges.', m = 2 },
    { t = '„Das sind Kühe. Die wissen gar nichts.“', r = 'Sag das nicht so laut. Die gucken schon.', m = 0 } } },
  { say = 'Ich hab noch zwei Brötchen im Rucksack. Willst du eins? Ist mit Käse. Glaube ich.', ch = {
    { t = '„Gerne, danke!“', r = 'Hier. Ist doch Käse. Und ein bisschen Rucksack. Guten Appetit.', m = 2, fx = 'snack' },
    { t = '„Danke, ich hab keinen Hunger.“', r = 'Mehr für mich. Ich hab seit heute früh nichts gegessen.', m = 0 } } },
  { say = 'Fährst du eigentlich gern nachts? Ich stell mir das total schön vor. Alles leer und die Lichter.', ch = {
    { t = '„Nachts ist es am schönsten.“', r = 'Wusste ich’s doch. Nur du, die Straße und ein Kaffee. Klingt nach einem Film.', m = 1 },
    { t = '„Nachts ist man nur müde.“', r = 'Okay, das zerstört den Film ein bisschen.', m = 0 } } },
  { say = 'Der Typ im Auto neben uns hat gerade in der Nase gebohrt. Mit voller Hingabe.', ch = {
    { t = '„Von hier oben sieht man alles.“', r = 'Das ist ja wie ein Hochsitz! Ich will auch einen Lkw.', m = 2 },
    { t = '„Guck nicht so hin.“', r = 'Zu spät. Das Bild krieg ich nie wieder aus dem Kopf.', m = 1 } } },
  { say = 'Hast du eigentlich Familie, die auf dich wartet?', ch = {
    { t = '„Ja, die vermisse ich unterwegs oft.“', r = 'Das glaub ich. Ruf sie heute Abend mal an. Die freuen sich bestimmt.', m = 1 },
    { t = '„Mein Lkw ist meine Familie.“', r = 'Dann grüß ihn von mir. Er ist sehr bequem.', m = 1 } } },
  { say = 'Ich mach mal kurz die Augen zu, okay? Weck mich, wenn was Spannendes passiert.', ch = {
    { t = '„Schlaf ruhig.“', r = 'Nach zwei Minuten schläft sie tief und fest, den Kopf an der Scheibe. Sie schnarcht ein bisschen.', m = 1 },
    { t = '„Hier passiert ständig was Spannendes.“', r = 'Wirklich? Okay, dann bleib ich wach. Zeig mir was Spannendes.', m = 0 } } },
  { say = 'Wenn du nicht Lkw fahren würdest, was würdest du dann machen?', ch = {
    { t = '„Bäcker. Wegen der Brötchen.“', r = 'Gute Wahl. Dann hätten wir jetzt frische Brötchen statt Rucksack-Brötchen.', m = 2 },
    { t = '„Nichts anderes. Das ist mein Ding.“', r = 'Schön, wenn man sein Ding gefunden hat. Ich suche meins noch.', m = 1 } } },
  { say = 'Wie viele Kilometer fährst du eigentlich so am Tag?', ch = {
    { t = '„Kommt drauf an. Manchmal 600.“', r = '600! Ich schaffe an guten Tagen 200. Mit Daumen.', m = 1 },
    { t = '„So viele, wie der Fahrtenschreiber erlaubt.“', r = 'Ah, der Fahrtenschreiber. Der heimliche Chef in jedem Lkw.', m = 1 } } },
  { say = 'Was ist das Komischste, was du je unterwegs gesehen hast?', ch = {
    { t = '„Einen Mann, der seinen Rasen auf dem Seitenstreifen gemäht hat.“', r = 'Nein! Auf dem Seitenstreifen? Wo hat er denn den Rasen hergehabt?', m = 2 },
    { t = '„Eine Anhalterin mit nur einem Gummistiefel.“', r = 'Hey! Das war ich nicht. Glaube ich.', m = 1 } } },
  { say = 'Draußen sieht es nach Regen aus. Ich hab natürlich keine Jacke dabei.', ch = {
    { t = '„Du kannst meine alte haben.“', r = 'Wirklich? Danke! Die riecht ein bisschen nach Diesel, aber das ist irgendwie gemütlich.', m = 2 },
    { t = '„Dann hoffen wir mal auf Sonne.“', r = 'Hoffen ist mein Spezialgebiet.', m = 0 } } },
  { say = 'Kannst du mir einen Tipp geben, wie man an der Raststätte am besten jemanden findet, der einen mitnimmt?', ch = {
    { t = '„Freundlich fragen und nicht nach Currywurst riechen.“', r = 'Das mit der Currywurst wird schwer. Aber ich geb mein Bestes.', m = 2 },
    { t = '„Lieber den Zug nehmen.“', r = 'Zug kann jeder. Trampen ist ein Abenteuer.', m = -1 } } },
}

-- what she says when she gets out, after a ride she liked or did not
M.BYE_GOOD = { 'Danke für die Fahrt. Das war die schönste seit Wochen.', 'Pass auf dich auf, ja? Und fahr nicht zu viele Nächte durch.', 'Wenn ich mal berühmt bin, erzähl ich allen von dir.' }
-- (2026-11-10) and when it was neither: she always says goodbye
M.BYE_OK = { 'So, hier steig ich aus. Danke fürs Mitnehmen, mach’s gut!', 'Tschüss! Und gute Fahrt noch, ja?', 'Danke dir! Vielleicht sieht man sich mal wieder an einer Raststätte.', 'Ciao! Und grüß deinen Lkw von mir.' }
M.BYE_BAD = { 'Na ja. Danke fürs Mitnehmen.', 'Danke. Du redest nicht gern, oder?', 'Okay. Ciao.' }

return M
