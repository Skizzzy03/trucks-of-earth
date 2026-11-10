# Änderungen

## 1.0.3

> **Zum Verkehr:** Der Verkehr ist viel klüger geworden, aber perfekt bekomme ich ihn nicht hin. Es kann weiterhin vorkommen, dass ein Auto komisch fährt, zögert oder sich falsch einordnet. Bitte habt dafür etwas Nachsicht. Wenn euch etwas auffällt, schickt gern ein [Issue](https://github.com/Skizzzy03/trucks-of-earth/issues) mit Ort und Uhrzeit, das hilft beim Verbessern.

### Neu

- **Kluger Verkehr:** Auf Autobahnen und Schnellstraßen wechseln die Autos die Spur, überholen links und fahren danach wieder rechts. Jeder Fahrer hat sein eigenes Tempo, Verkehrs-Lkw halten sich an die Lkw-Regeln (Autobahn 80, Landstraße 60). Fädelst du ein oder blinkst du, wird Platz gemacht.
- **Die Autos sprechen sich ab:** Lücken beim Spurwechsel werden reserviert, ein blockiertes Auto wird reingelassen, und bremst die Spitze einer Kolonne, gehen die Hinteren früh vom Gas. Ab und zu ist ein Raser unterwegs, der knapp einschert, mit Absicht und selten.
- **Tagesrhythmus und Staus:** Nachts wenig Verkehr, im Berufsverkehr viel. Auf der Autobahn gibt es Staus mit Verkehrsfunk, Warnblinkern am Stauende und Stop-and-go.
- **Eigene Fahr-KI (Beta, in den Einstellungen):** Unsere eigene Fahr-KI lenkt und bremst die Autos, hält an Ampeln und Stoppschildern, und an Kreuzungen vergibt eine Zentrale die Durchfahrt (Hauptstraße vor Seitenstraße, rechts vor links). Bei großen Kreuzungen und Problemen übernimmt wieder BeamNG.
- **Underground im Büro:** eigener Reiter mit Ruf-Stufen vom Neuling bis zur Legende. Jede Stufe bringt mehr Lohn und heißere Ware, viel davon über die Häfen. Kontakte lassen sich anrufen, Aufträge direkt annehmen.
- **Zustand der Bauteile:** Die Werkstatt zeigt für Motor, Antrieb, Fahrwerk und Karosserie eine Skala in Prozent.
- **Parkplätze als Ziel:** Routenberater und Büro führen zum nächsten Parkplatz.
- **Begegnungen am Straßenrand:** Wer abseits der Autobahn auf Pause steht, bekommt auch dort Besuch.
- **Der Pannenhelfer kommt wirklich:** Er steigt neben seinem Wagen aus, kommt an deine Tür und fragt, was los ist. Deine Antwort bestimmt, wie lange er sucht. Dann geht er zum Reifen oder zum Motor, arbeitet, läuft zurück und fährt los.
- **Anhalter am Straßenrand:** Auf Landstraßen steht manchmal jemand mit dem Daumen raus, ohne lange Vorwarnung. Halt an, dann kommt sie zur Beifahrertür. Wer mitfährt, sitzt sichtbar neben dir in der Kabine, bis sie aussteigt.
- **Die Beifahrerin erzählt:** Jede Mitfahrerin hat ihren Namen und ihre eigene Geschichte, die sie dir in drei Teilen erzählt. Dazwischen Smalltalk über Ladung, Musik, Partys, Festivals und Kühe. Manchmal lässt sie Zigaretten oder etwas für den Feierabend da. Deine Antworten bestimmen ihre Laune und damit, wie sie sich am Ende bedankt und verabschiedet. Im Routenberater zeigt ein Balken, wie weit sie noch mitfährt.
- **Mehr los auf dem Rastplatz:** fünf neue Begegnungen, vom Lkw-Fotografen über Festivalleute mit Plattfuß-Bus bis zum Imbisswirt kurz vor Feierabend.
- **Polizeikontrolle auf dem Rastplatz:** Die Polizei wartet schon mit Streifenwagen, Blaulicht, zwei Beamten und einer blauen Fläche, in der du anhältst.
- **Automatikgetriebe:** Händler und Fuhrpark zeigen, ob ein Lkw Automatik oder Schaltgetriebe hat. In der Werkstatt lässt sich ein Automatikgetriebe einbauen, wo es für das Modell eines gibt.

### Verbessert

- Der Verkehr fährt auf der Hauptstraße durch, statt an Seitenstraßen zu bremsen, und biegt seltener ab
- Auch hinter dir ist wieder Verkehr unterwegs
- Online-Shop liefert in 1:30 bis 2 Minuten
- Kaffeemaschine brummt und brüht sichtbar, die Tasse steht richtig herum; die Popcornmaschine ist lauter und leuchtet beim Poppen
- Das Radio geht kurz nach dem Abstellen des Motors aus und mit dem Motor wieder an
- Die Werkstatt-Szene ist nicht mehr verschwommen
- Autos fahren mittig in ihrer Spur statt Richtung Straßenmitte
- Die Person an der Tür steht auf Fensterhöhe und ist durch die Scheibe zu sehen
- Abends ist mehr los: Der Berufsverkehr von 16 bis 19 Uhr ist die vollste Zeit des Tages
- Verkehrs-Lkw fahren auf schmaleren Straßen nicht mehr Richtung Mittellinie
- Die Abstandsautomatik folgt der Kurve und bremst nicht mehr für Autos am Straßenrand
- Einstellungen in Gruppen sortiert, die eigene Fahr-KI steht groß ganz oben; nach dem Start gibt es einen Hinweis darauf
- Die Fremd-Mod „Realistic AI Traffic Behaviors“ wird nicht mehr angeboten und ausgeschaltet
- Das Büro läuft flüssiger: die langen Listen werden nur noch geschickt, wenn sich etwas geändert hat
- Der Hof lässt sich nicht mehr mitten in Städten setzen; ein Hof von früher in der Stadt zieht ins nächste Gewerbegebiet

### Behoben

- Lkw mit Schaltgetriebe konnten nach dem Laden oder einer Reise abstürzen („Fahrzeug konnte nicht geladen werden“)
- Im Fahrtenschreiber ließ sich nichts anklicken
- Der Tempomat ging mit einem Lenkrad sofort wieder aus oder gab kein Gas (leichtes Pedalrauschen oder ein auf der Bremse ruhender Fuß); bleibt er wegen eines Joints aus, wird das jetzt gesagt
- Falschfahrer auf Richtungsfahrbahnen werden erkannt und richtig herum hinter dir wieder eingesetzt
- An der Ampel fuhr der Verkehr hinter dir nach ein paar Sekunden um den wartenden Lkw herum und es kam zu Auffahrunfällen
- Der Hof wurde zwischen Häuser gebaut, wenn die Gebäude beim Ankommen noch nicht geladen waren
- Der Pannendienst änderte nichts am Zustand: Nach einem Unfall gibt es jetzt eine Notreparatur, die die Hälfte der Schäden behebt und den Lkw fahrbereit macht
- Nach dem Einbau eines Automatikgetriebes war die Lackierung weg
- Ein instand gesetzter Motor wurde immer wieder als reparaturbedürftig angeboten
- Unter Rauscheinfluss verschmierten Kabinenteile und die Routenlinie
- Verkehr fuhr mittig auf der Linie, schlenkerte im Gegenverkehr nach rechts und bremste grundlos
- Autos kamen von der Fahrbahn ab, abgebrochene Überholvorgänge scherten zu früh und riskant ein

## 1.0.2

### Neu

- **Ganz Europa:** rund 330.000 Orte in 39 Ländern, die Karte im Büro zeigt jetzt den ganzen Kontinent. Andere Teile der Welt werden noch nicht unterstützt.
- **Underground:** dunkle Häfen, Waldlager und verlassene Fabriken auf der Karte, mit Fracht ohne Papiere in drei Risikostufen. An Tankstellen gibt es diese Aufträge nicht mehr.
- **Polizeiverfolgung:** Wirst du mit heißer Ware erwischt oder haust du bei einer Kontrolle ab, kommen höchstens zwei Streifen gleichzeitig hinter dir her, bis zu drei rücken nach. Häng sie ab oder lass dich stellen.
- **Begegnungen am Rastplatz:** Es klopft an der Tür. Zwölf Szenen, und nicht jeder meint es gut mit dir.
- **Online-Shop:** über 50 Teile für die Kabine mit Warenkorb und Lieferung an den Hof, dazu Geräte mit echter Funktion wie Popcornmaschine, Lüfter, Radio-Display und Diskokugel.
- **Kabine einrichten:** Teile verschieben und drehen, drei Kameraansichten, Bilderrahmen mit eigenem Foto aus der BeamNG-Galerie. Auch im Leih-Lkw lässt sich alles aufhängen, was hängt.
- **Werkstatt:** Komplettreparatur oder einzelne Bauteile, mit Szene in der Werkhalle. Der Kilometerstand bleibt.
- **Aussichtspunkte:** Hinweis unterwegs, Foto auf Knopfdruck, Fotomodus vor Ort.
- **Fotomodus im Autodrive:** Serie von Kabine, Einbauten und Fahrt, von nah und von weit weg (in den Einstellungen).
- **Fahrschule:** kurze Erklärfilme im Büro.
- **Stimmungsmusik:** leise, selbst komponiert, passend zur Situation.
- **Mimik:** Polizisten und Fremde zeigen, wie das Gespräch gerade läuft.
- **Handbremse:** geht in den Menüs im Kreis von selbst rein und danach wieder raus.

### Verbessert

- Abstandsautomatik greift erst ein, wenn es nötig ist, bremst sanft und blinkt rot, statt zu piepen
- Spurhalter lenkt ruhig, der Spurwarner piept leiser
- Gegenverkehr bremst nicht mehr, nur weil du nah an der Mitte fährst
- HUD rechts neu geordnet, auch mit vielen Achsen und Geräten wird nichts abgeschnitten
- Händler zeigen ihre Preisklasse, mehr Auswahl und unterschiedlicher Bestand
- Reparaturen kosten jetzt, was sie kosten: Die BeamNG-Reset- und Fahrzeugmenüs sind in der Karriere gesperrt, per Entwicklermodus in den Einstellungen wieder einschaltbar

### Behoben

- Schaden ist nach einem Teleport wieder genau derselbe
- Figuren in der Kabine rutschen nicht mehr mit dem Kopf oder beim Bremsen, auch nach einem Unfall bleiben sie an ihrem Platz
- Doppelbilder von Kabinenteilen in Kurven mit FSR und TAA
- Neue Karriere: Ladebildschirm hing bis zu anderthalb Minuten, der Lkw stand neben dem Hof
- Hinweis beim Teleport zum Hof, während er geladen wird
- Absturz der Mod im Verkehr durch ein gelöschtes Fahrzeug

## 1.0.1

### Neu

- **Mietwagen nach dem Flug:** Am Zielflughafen bist du zu Fuß unterwegs und kannst vor Ort einen Mietwagen wählen, von teuer bis günstig und mit Fotos. Dein Lkw bleibt, wo er steht.
- **Cinematic-Modus im Autodrive:** Außenkamera-Fahrten von hinten, von der Seite, von vorn, vom Straßenrand, von oben, an den Rädern und im Kreis. Start über den Knopf neben Autodrive oder Strg+Umschalt+C.
- **Viel mehr Orte:** rund 54.000 zusätzliche Tankstellen, Rastplätze und Firmenstandorte in Deutschland, Österreich und der Schweiz.
- **Bundesland und Land** werden mit Flagge auf der Karte und als Einblendung beim Wechsel angezeigt.
- **Radio:** Favoriten und eine neue Senderliste, die alle Sender auf einmal zeigt.
- **Einfahrt zum Hof** von der Straße aus.

### Verbessert

- Autotransporter und die geladenen Autos neu gebaut, mit Achsen, Reifen, Gurten und Keilen
- Navi-Ansagen deutlich lauter, Hinweise in klaren Stufen: 600 m, 200 m, jetzt
- HUD neu geordnet: Fahrtenschreiber und Kabine tiefer, Antrieb direkt auf dem Tempomat. Die Anordnung wird beim ersten Start einmal neu gesetzt.
- Verkehr überholt seltener, nur noch mit viel freier Gegenspur, nicht in Kurven und nicht auf schmalen Straßen
- Sportliche Fahrer im Verkehr fahren ruhiger durch Kurven

### Behoben

- Ladebildschirm ging bei einer neuen Karriere nicht weg, Hofauswahl und Tutorial fehlten
- Ladebildschirme verschwanden teils, bevor die Welt fertig war
- Absturz der Mod beim Warten auf die Welt von BeamNG.Earth
- Virtuelle Spiegel gingen nicht
- Radio lief bei einer neuen Karriere gleich los
- Autos fuhren auf Richtungsfahrbahnen zum Überholen in die Leitplanke
- Autos brachen Überholmanöver ständig ab und fuhren dabei auf der Mittellinie
- Autos fuhren an roten Ampeln außen um die wartende Schlange herum
- Antrieb-Anzeige war oben abgeschnitten, Senderliste war abgeschnitten und unvollständig

### Bekannt

- Die Verkehrs-KI wird weiter abgestimmt. Wenn dir noch Autos auf der falschen Seite auffallen, freue ich mich über ein Issue mit der `beamng.log`.
- Hof-Upgrades werden weiterhin noch nicht unterstützt, auch wenn sie im Spiel angezeigt werden.

## 1.0.0

Erste öffentliche Version.

- Karriere mit Spedition, Aufträgen, Fuhrpark, Finanzen und Statistik auf BeamNG.Earth
- Fahrtenschreiber, Müdigkeit, Kabine, Polizeikontrollen
- Ereignisse auf der Straße, Verkehr mit Überholen und Rücksicht, Unfälle mit Bericht
- Zufallspannen, Pannendienst, Club und Versicherung
- Internetradio mit Regionalsendern, Spotify-Steuerung, Videoplayer
- Handbuch im Spiel, deutsche Navi-Ansagen, Lademusik

Bekannt: Hof-Upgrades werden in dieser Version noch nicht unterstützt, auch wenn sie im Spiel angezeigt werden.
