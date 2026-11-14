# Änderungen

## 1.0.5 (14.11.2026)

Enthält auch alles aus 1.0.4, das nicht einzeln erschienen ist. Der virtuelle Verkehr und die eigene Fahr-KI lassen sich in den Einstellungen als Beta einschalten.

### Neu

- **Verkehrstest, vollautomatisch:** Mit Strg+Umschalt+V fährt der LKW 30 Minuten im Autodrive, in vier Szenen: Landstraße am Morgen und zur Mittagszeit, Autobahn im Feierabendverkehr mit Stau und bei Nacht. Uhrzeit und Routenart stellt der Test selbst um und setzt sie am Ende zurück. Die Mod misst dabei den Verkehr ringsum: Tempo, Abstände, Unfälle, Beinahe-Unfälle, Kreuzungen, Stöße in der Fahrbahn, Autos neben der Straße oder auf der Gegenspur, grundloses Stehen, Spurnutzung, Bildrate. Bei jedem Unfall zeichnet eine Black Box die 8 Sekunden davor auf. Die Messung landet in `settings/fernfahrer/lab` und hilft, die Verkehrs-KI zu verbessern.
- **Der Verkehr lernt aus Unfällen:** Kracht ein Auto bei hohem Tempo allein irgendwo hinein, merkt sich die Mod die Stelle, auch über das Spielende hinaus. Der Verkehr in dieser Richtung fährt dort künftig mit 60 km/h vorsichtiger. Bleibt es an der Stelle lange ruhig, wird sie wieder normal befahren. Hinter einem frischen Wrack bremst der Verkehr auf 30 km/h ab, statt hineinzufahren.
- **Staus mit Grund:** Der Verkehrsfunk sagt jetzt, warum es staut. Bei einem Unfall stehen an der Spitze des Staus zwei Autos schräg auf dem linken Fahrstreifen, mit Warnblinker, und der Verkehr fädelt rechts an ihnen vorbei. Sonst heißt es „hohes Verkehrsaufkommen“. Der Stau ist dichter, und die Autos, an denen du vorbei bist, rücken in die nächste Lücke vor dir statt ganz nach vorn. So bleibt die Schlange um dich herum voll. Für Staus stehen außerdem 28 zusätzliche Autos bereit. Im Stau rücken die Autos dicht auf, statt große Lücken zu lassen, und das Stop-and-go läuft als langsame Welle von vorn nach hinten durch die Schlange, wie auf der echten Autobahn. Damit sie nicht zu viel Leistung kosten, legt ein Sparmodus Stauautos weit vor oder hinter dir schlafen: KI aus, Handbremse an, und BeamNG rechnet ihre Physik dann kaum noch. Kommst du näher, wachen sie auf und rollen im Stop-and-go weiter.
- **Virtueller Verkehr (Probebetrieb, zunächst nur im Verkehrstest):** Autos außer Sicht sind keine BeamNG-Fahrzeuge mehr, sondern Punkte auf dem Straßennetz, die die Mod selbst fahren lässt: jedes in seinem Tempo, mit Abstand zum Vordermann, mit Abbiegen an Kreuzungen und Stehen im Stau. Kommt eines in Sichtweite (etwa 200 bis 300 m), wird an seiner Stelle ein echtes Auto eingesetzt, mit seinem Tempo. Dafür wird ein echtes Auto genommen, das weit weg oder weit hinter dir ist, und dort fährt es als virtuelles weiter. So bleibt der Verkehr, den du überholt hast, hinter dir, und es gibt so viel Verkehr, wie die Straßen tragen. Das eigene Neusetzen von BeamNG ist dabei abgeschaltet.
- **Virtueller Verkehr, zweite Fassung:** Er passt sich jetzt an, wie weit Earth die Straßen geladen hat. Vorher entstanden virtuelle Autos erst ab 700 m und fuhren dort sofort ans Ende des Netzes. Als Spenderauto zählt jetzt jedes echte Auto, das sich hinter dir entfernt, auch der Gegenverkehr. Neu: Virtuelle Autos wechseln auf mehrspurigen Straßen die Spur, überholen Langsamere und fahren danach wieder rechts. Eingesetzt wird nur, wo Boden ist.
- **Dichterer Verkehr und Stau:** Mit virtuellem Verkehr fahren doppelt so viele echte Autos um dich herum (sie werden ja nicht mehr weit weg gebraucht), dazu bis zu 90 statt 60 virtuelle. Im Stau stehen die Autos jetzt eine Wagenlänge und knapp 2 bis 3 m auseinander, der eigene Fahrer hält bei Schritttempo eine kürzere Zeitlücke, und nur die Autos direkt hinter dir bleiben hinter dir, die übrigen wandern nach vorn. Weiter vorn und hinten schläft der Stau (keine Kosten), virtuelle Autos im Stau bleiben virtuell.
- **Virtueller Verkehr: Autos kommen auch, wenn alle weit weg stehen** (im ersten Versuch blieb die Straße leer), und ist eine Zeit lang kein Auto in der Nähe, setzt BeamNG wieder selbst welche ein.
- **Kein leerer Verkehr mehr:** BeamNG.Earth löschte die Verkehrs- und Parkautos beim Einsetzen, weil es sie für weit entfernte eigene Autos hielt. Die Mod pausiert diese Funktion von Earth jetzt kurz, während Autos eingesetzt werden. Statt des Stadtbusses fahren Lkw oder Transporter mit.
- **Mehr Verkehr:** Neue Autos kamen bisher nur bei über 57 Bildern/s dazu, deshalb fuhren meist nur 4 bis 9 Autos. Jetzt reichen 45 Bilder/s, und neue Autos kommen nach und nach statt alle auf einmal.
- **Platzhalter-Autos:** Autos in der Ferne sind jetzt reine Modelle ohne Physik und kosten kaum Leistung. Erst unter etwa 55 m werden sie zu echten Autos mit Physik, und wer sich weiter als 110 m entfernt, wird wieder zum Platzhalter. So kann viel mehr Verkehr sichtbar sein.
- **Autobahn:** Unsichtbare Autos bremsen jetzt auch für Unfallstellen und werden nicht mehr direkt davor sichtbar. Sichtbar werden nur Autos, die auf dich zukommen oder die du einholst, und auf der Autobahn entstehen sie bevorzugt auf der Autobahn statt auf den Straßen daneben.
- **Abstände unterschiedlich:** Jeder Fahrer hält seinen eigenen Abstand, ruhige mehr, sportliche weniger.
- **Hindernisse lernen:** Fahren an einer Stelle mehrmals Autos langsam gegen etwas, weicht der Verkehr dort künftig aus.
- **Pulks:** Verkehr kommt oft als Gruppe von 2 bis 4 Autos, die dicht hintereinander fahren. Der vordere reagiert zuerst, die anderen folgen. Jedes Auto bleibt eigenständig und kann später abbiegen oder überholen.
- **Keine Autos mehr in der Luft:** Jedes eingesetzte Auto wird auf den echten Boden gesetzt.
- **Keine fallenden Autos in Serie mehr:** Ein weggenommenes Auto (gefallen, in ein anderes gesetzt, Wrack geräumt) kommt jetzt zuerst hinter den LKW, auf Straße, über die er gerade gefahren ist. Vorher landete es 300 bis 800 m voraus, oft im Stau und dort wieder ohne Boden; dasselbe Auto fiel bis zu 32-mal. Jedes frisch eingesetzte Auto wird außerdem mit einem Strahl nach unten geprüft und sofort verlegt, wenn darunter kein Boden ist.
- **Warnblinker am Stauende:** Wer mit Tempo auf stehenden Verkehr oder ein Wrack zufährt und hart bremsen muss, schaltet den Warnblinker ein und warnt so die Autos dahinter.
- **Schon losfahren:** Bleibt der Ladebildschirm länger als 30 Sekunden stehen, kannst du mit einem Knopf direkt losfahren.

### Verbessert

- Weniger Massenunfälle auf der Autobahn: Autos, die die Verkehrs-KI hinter den Spieler setzt, rollen jetzt mit Tempo los, statt in der Spur zu stehen. Abgesetzt werden sie nur dort, wo niemand von hinten heranfährt.
- Kein Schleichen mehr mit 30 km/h auf freier Autobahn: Wenn ein Auto Platz zum Einfädeln macht, einem Überholer ausweicht oder vom Fahrbahnrand zurücklenkt, nimmt es einmal etwas Gas weg, statt immer weiter abzubremsen.
- Brücken und Unterführungen: Ein Auto auf der Autobahn hält ein Auto in der Unterführung darunter nicht mehr für ein Hindernis in seiner Spur und macht deshalb keine Vollbremsung mehr.
- **Unfalldienst:** Ein verunglücktes Verkehrsauto schaltet die Warnblinker ein. Steht es länger als 25 Sekunden außer Sicht, wird es geräumt. Querstehende Wracks erkennt der Verkehr dahinter jetzt als Hindernis, und niemand wechselt mehr auf eine Spur, in der ein Wrack steht.
- Neu eingesetzte Autos rollen nicht mehr mit vollem Tempo auf eine stehende Schlange zu.
- **Verkehr nach Straße und Uhrzeit:** Auf der Autobahn ist mehr los, auf Landstraßen weniger, in der Stadt wie gewohnt. Die Menge gleicht sich über gut eine Minute an und nimmt auch nur noch Auto für Auto ab, statt dass mehrere auf einmal verschwinden. Nachts bleibt es ruhig, im Berufsverkehr wird es voll.
- **Flüssiger Verkehr:** Die Autos beschleunigen zügiger, etwa wie ein normaler Fahrer, statt nach jeder Kurve eine halbe Minute zu brauchen. Gelernte Gefahrenstellen bremsen nur noch auf 70 % des Limits (mindestens 60 km/h), statt auf der Autobahn grundlos auf 60 km/h. Auf der Landstraße fährt der Verkehr normal mit, ohne künstliche Langsamfahrer.
- **Autobahn bis zum Limit:** Die Autos fahren auf der Autobahn wieder bis 120 km/h und mehr. Bisher hielt sie kleines Zickzack im Straßennetz von BeamNG.Earth für eine Kurve und bremste sie auf etwa 110 km/h.
- **Kreisverkehre:** Im Kreisel fährt jetzt wieder die BeamNG-KI, statt dass sich Autos beim Einfahren gegenseitig rammen.
- Fährt dein LKW schräg oder quer auf die Straße, bremst der Verkehr für den ganzen Lastzug, nicht nur für dessen Mitte.
- **Der Verkehr fährt um Hindernisse herum:** Baustellen, verlorene Ladung, Unfallstellen und Wracks sperren jetzt erkennbar einen Teil der Fahrbahn. Die Sperre wird aus den aufgestellten Baken, Baggern und Kisten berechnet. Auf mehrspurigen Straßen wechseln die Autos rechtzeitig auf die freie Spur, im Reißverschluss, und halten notfalls davor an. Auf der Landstraße warten sie auf eine Lücke im Gegenverkehr und fahren dann mit Blinker vorsichtig vorbei, statt einfach durch die Baustelle zu fahren.
- Steht dein LKW hinter einem Wrack in seiner Spur, schleppt der Unfalldienst es nach kurzer Zeit ab, statt dass das Autodrive minutenlang wartet.
- Ein Stau entsteht jetzt entlang deiner Navi-Route, auch wenn das Straßennetz voraus nicht vollständig geladen ist.
- Ein beschädigtes Auto, das immer wieder aneckt, wird vom Unfalldienst geräumt, sobald du es nicht mehr siehst.
- **Überholen auf der Landstraße:** Hinter deinem LKW bildete sich eine lange Kolonne, weil die Autos ihn mit 60 auf einer 100er-Straße für „nicht langsam genug“ hielten. Sie haben nur die Zugmaschine gemessen, ohne Auflieger. Jetzt wird dein LKW immer als LKW behandelt und überholt, wenn Platz ist.
- Setzt BeamNG mehrere Autos auf einmal dicht hintereinander ab, bekommt ein schnelles Auto sofort das Tempo des langsamen davor, statt hineinzufahren.
- Verkehrstest: Die Autobahn-Szenen beginnen erst, wenn der LKW wirklich auf der Autobahn ist. Bis dahin fährt er hin, der Test dauert dann entsprechend länger.
- Die Verkehrs-KI sieht die Straße voraus jetzt vollständig. Manche Straßenstücke speichert BeamNG nur an einem Ende, und daran endete die Vorausschau bisher nach wenigen Metern. Das betraf vor allem Staus und Überholentscheidungen.
- Ein Stau entsteht jetzt auch, wenn BeamNG.Earth nur ein kurzes Stück Straße voraus geladen hat. Er beginnt dann näher und ist kürzer.
- **Eigener Fahrer bleibt länger dran:** Am Rand des von BeamNG.Earth geladenen Straßennetzes gibt er das Auto nicht mehr ab. Er wartet auf das nächste Stück Karte und fährt dann weiter. Bisher war das der häufigste Grund, warum Autos an die BeamNG-KI zurückgingen.
- **Stufen im Straßennetz:** Wo das Straßennetz von BeamNG.Earth auf einer schnellen Straße plötzlich steil ansteigt oder abfällt (meist eine Brückenfuge), fährt der Verkehr mit 70 km/h darüber, statt mit 100 km/h abzuheben. Spürt ein Auto dort einen heftigen Stoß, merkt sich die Mod die Stelle ebenfalls.
- Abbiegende Autos: Biegt ein Auto aus dem Gegenverkehr quer vor einem anderen ab, bremst der Verkehr jetzt rechtzeitig dafür.
- Ein Wrack, das nach einem Zusammenstoß noch in die Leitplanke rutscht, gilt nicht mehr als Gefahrenstelle der Straße.
- Gefahrenstellen werden auch gelernt, wenn beim Aufprall zufällig ein Auto daneben fährt und nur gestreift wird.
- **Rettungsgasse:** Steht der Verkehr im Stau auf einer mehrspurigen Straße, weichen die Autos auf der linken Spur nach links aus, alle anderen nach rechts. Löst sich der Stau auf, fahren sie wieder in der Mitte ihrer Spur.
- **Reißverschluss am Spurende:** Endet die eigene Spur, wechselt der Verkehr rechtzeitig hinüber. Ist kein Platz, bittet er um eine Lücke und bremst notfalls vor dem Ende ab. Vor Ausfahrten bleibt die rechte Spur davon unberührt.
- Im Stau werden Autos nur noch dort abgesetzt, wo von hinten niemand heranrollt.
- Notbremse für alle: Steht ein Auto in der Spur, bremst der Verkehr dahinter rechtzeitig, nicht nur vor deinem LKW.
- Der Verkehr wird seltener neu gesetzt: Autos bleiben länger sichtbar und tauchen weiter weg auf. Neu eingesetzte Autos auf schnellen Straßen sind gleich mit passendem Tempo unterwegs, statt mit 50 km/h auf der Autobahn zu schleichen.

### Behoben

- Autos, die BeamNG an Stellen absetzte, an denen der Boden von BeamNG.Earth noch nicht geladen war, fielen durch die Welt und lagen dann als Wracks im Weg. Das führte zu Massenkarambolagen. Solche Autos werden jetzt sofort weggenommen.
- Setzte BeamNG ein Auto direkt in ein anderes Auto oder in ein Wrack, kam es zu Kettenunfällen. Solche Autos werden sofort woanders hingesetzt. Sehr schnell fallende Autos (über 15 m/s nach unten) werden jetzt sicher weggenommen, vorher sahen sie für die Mod wie ein Sprung aus.
- Setzte BeamNG ein Auto mitten in einen Stau, fuhr es mit über 90 km/h in die stehende Schlange. Jetzt rollt es gleich mit dem Tempo des Staus.
- Neu eingesetzte Autos kurz vor einer Unfallstelle, Baustelle oder einem Stau fahren gleich mit dem Tempo, das dort gilt, statt mit voller Fahrt hineinzurasen.
- Im Verkehrstest regelt die Mod die Zahl der Autos nicht mehr nach der Bildrate herunter, damit der Test zeigt, was der volle Verkehr kostet.
- Vor einer Sperre, an der gewartet werden muss, bremst der Verkehr jetzt ganz bis zum Stillstand. Vorher kroch er mit Schritttempo weiter, bis in die Baustelle oder das Wrack hinein.
- Vor einem Wrack quer über alle Spuren hält der Verkehr an, statt immer wieder einen Spurwechsel auf eine Spur zu versuchen, die es nicht gibt.
- Auf Straßen mit einer Spur je Richtung fahren auch die Autos des eigenen Fahrers um Baustellen herum, statt hindurch.
- Beim Laden einer Karriere am Hof blieb der Ladebildschirm über zwei Minuten stehen, und der LKW war so lange eingefroren. Er wird jetzt richtig vor der Halle abgestellt.
- Abgestellte, unsichtbare Autos (Platzhalter an ihrer Stelle, oder Unfallautos an der Stau-Spitze) rollten manchmal unbemerkt weiter, mit bis zu 100 km/h mitten in den Verkehr. BeamNG stellt bei jedem Umsetzen den Normalbetrieb eines Verkehrsautos wieder her und hob so die Handbremse und den Stillstand sofort wieder auf. Solche Autos werden jetzt auch auf BeamNGs eigener Seite als nicht fahrend markiert, und ein unsichtbares Auto, das trotzdem rollt, wird sofort wieder angehalten.
- Wurden zwei Platzhalter im selben Augenblick zu echten Autos, prüfte die Mod den zweiten nicht gegen den ersten: beide erschienen zu dicht beieinander und krachten sofort zusammen. Jetzt wird auch auf frisch erschienene Autos im selben Schritt Rücksicht genommen, nach ihrer Länge.
- **Sanfteres Bremsen:** Die Notbremse des Verkehrs sprang bisher ohne Übergang von nichts auf den vollen Bremsdruck, auch bei ganz gewöhnlichem dichten Auffahren – das ließ die Reifen qualmen und die Sicht leiden, vor allem auf der Autobahn. Jetzt steigt und sinkt der Bremsdruck weich, wie bei einem echten Fahrer. Nur ein echter Beinahe-Unfall, bei dem keine Zeit zum Abwägen bleibt, greift weiterhin sofort voll durch. Dasselbe gilt jetzt auch für deinen eigenen Fahrer: Ziel-Beschleunigung und -Bremsung ändern sich in einem gleichmäßigen Rhythmus statt in Sprüngen, außer es drohte wirklich ein Aufprall.
- **Rollen lassen:** Dein eigener Fahrer tritt jetzt auch mal gar nichts – weder Gas noch Bremse –, wenn er sich nur ein kleines Stück an einen etwas langsameren Vordermann heranarbeitet, statt dafür ständig leicht zu bremsen.
- **Kein Gas-Vollbremse-Pendeln mehr um Unfallstellen:** Steuerte der Verkehr um ein Wrack oder eine Unfallstelle herum, bremste die Notbremse auf dasselbe stehende Auto noch einmal voll, obwohl das Ausweichen die Geschwindigkeit längst sanft herunterregelte. Das Auto gab dann wieder Gas, die Notbremse griff erneut – so ging es mehrmals, bis es endlich vorbei war. Jetzt lässt die Notbremse dem Ausweichen während eines laufenden Ausweichmanövers mehr Vorsprung und greift nur noch ein, wenn wirklich keine Zeit mehr bleibt.
- **Weniger sichtbarer Sprung beim Echtwerden:** Ein Platzhalter-Auto wurde bisher immer binnen einer festen Viertelsekunde auf sein Tempo gebracht, egal wie groß der Unterschied zum vorherigen Tempo des echten Autos war – bei großem Unterschied ein harter Ruck. Jetzt richtet sich die Zeit danach, wie groß die Differenz tatsächlich ist: ein kleiner Unterschied ist sofort weg, ein großer gleicht sich sanfter an.
- **Keine unsichtbaren Autos mehr auf der Straße:** Ein echtes Auto, dessen Platz ein Platzhalter übernimmt, wird jetzt dort, wo es ist, in BeamNGs eigenem Fahrzeug-Pool schlafen gelegt – so wie BeamNG seine Reservefahrzeuge ruhen lässt: keine Physik, keine Kollision, nicht gezeichnet, kostet nichts. Bisher wurde es nur unsichtbar gemacht und mit Handbremse gehalten, und alle wurden an dieselbe Stelle 450 m hinter den LKW gesetzt. Dort steckten sie ineinander, wurden auseinandergeschleudert und fuhren oder flogen unsichtbar, aber fest, mit 35 bis 55 km/h durch den Verkehr. Der Verkehr bremste für sie, und es krachte „aus dem Nichts“. Ein schlafendes Auto wird nur geweckt, wenn BeamNGs Grenze für aktive Autos noch Platz hat. Sonst schickt BeamNG dafür ein anderes Auto schlafen, womöglich eines, das man gerade sieht.
- **Verkehr auf deiner eigenen Straße:** Die Hälfte der neuen Autos außer Sicht entsteht jetzt auf der Straße, auf der du fährst: Gegenverkehr vor dir, Autos vor dir in deiner Richtung und Autos hinter dir, die dich einholen. Bisher entstanden sie irgendwo im Umkreis, meist auf Neben- und Ortsstraßen, und auf deiner Straße kam kaum eines an. Neue Autos außer Sicht kommen fast immer auf dich zu, statt wegzufahren und nach Sekunden am Ende der geladenen Karte zu verschwinden. Auf der Autobahn, wo es auf deiner Fahrbahn keinen Gegenverkehr gibt, kommen sie stattdessen von hinten. Ist deine Straße nicht weit geladen, entstehen sie am weitesten geladenen Punkt, mindestens 300 m entfernt. Schlafen gelegt wird außerdem nur noch ein Auto, das sich von dir entfernt. Eines, das auf dich zukommt oder das du einholst, bleibt echt.
- **Nie mehr leere Straßen:** Sind weniger als 6 echte Autos in 350 m Umkreis, wird ein ruhendes Auto auf deiner Straße eingesetzt, 150 bis 260 m entfernt, als Gegenverkehr oder von hinten. Earth lädt die Straße oft nur kurz, und vorher blieb es dann minutenlang leer.
- **Vorausschauen auf Stauenden:** Jedes Verkehrsauto sieht ein stehendes oder viel langsameres Auto in seiner Spur bis zu 220 m voraus und nimmt rechtzeitig sanft Tempo raus, mit etwa 1,8 m/s². Bisher sah es erst 55 m weit. Bei 100 km/h reicht das nicht, die Notbremse musste dann hart eingreifen.
- **Kein Ruckeln mehr beim Warten vor einer Sperre:** Wer vor einer Baustelle oder einem Unfall wartet, hält die Bremse jetzt gedrückt. Bisher ließ er los, sobald er stand, rollte wieder an und wurde erneut gebremst, minutenlang im Sekundentakt.
- **Echtwerden wieder zügig:** Ein Platzhalter, der echt wird, ist nach 0,2 Sekunden wieder auf seinem Tempo. Die längere Angleichzeit aus der letzten Version beruhte auf einer falschen Annahme: Ein versetztes Auto steht danach immer. Es war so über eine Sekunde lang zu langsam, und die Autos dahinter mussten hart bremsen.
- **Ein gerade versetztes Auto gilt kurz als „unbekannt“:** In den ersten Bildern nach dem Versetzen meldet das Spiel ein falsches Tempo, oft um die 100 km/h, obwohl das Auto steht. Darauf reagierten Notbremse und Tempo-Angleichung bisher sofort. Jetzt warten sie einen Augenblick, und auch das Verkehrslabor zählt in dieser Zeit keine harten Bremsungen.
- **Abgestellte Platzhalter-Spender kriechen nicht mehr los:** Ein unsichtbar abgestelltes Auto (Handbremse, KI aus) wurde nur einmal pro Sekunde geprüft – dazwischen kroch es durch Standgas oder ein leichtes Gefälle wieder auf 6 bis 8 km/h an, unsichtbar quer durch den Verkehr. Die Handbremse wird jetzt bei jedem Blick erneuert, nicht erst, wenn das Auto schon wieder zu schnell ist.

- **Keine Autos mehr, die nach einer Weile unsichtbar werden:** BeamNG blendet ein Verkehrsauto aus, sobald es weit genug weg ist, um es woanders neu einzusetzen, und blendet es dort wieder ein. Auf dem kurzen Straßennetz von BeamNG.Earth fand es diesen neuen Platz oft nicht. Das Auto blieb dann ausgeblendet und fuhr unsichtbar, aber fest, weiter. Mit virtuellem Verkehr, bei dem BeamNGs eigenes Neusetzen abgeschaltet ist, blieb es sogar für immer so. Jetzt wird ein solches Auto sofort wieder sichtbar, wenn es in der Nähe ist oder nicht neu gesetzt werden soll, und spätestens nach 4 Sekunden, wenn das Neusetzen nicht kommt.
- **Platzhalter fahren flüssig:** Ein Platzhalter blieb bisher am Ende jedes kurzen Straßenstücks stehen, bis er im nächsten Rechenschritt weitergeschoben wurde. Das sah aus wie Bild für Bild. An jedem Knoten drehte er sich außerdem in einem Ruck und sprang so um die Kurven. Jetzt kennt er die nächsten Straßenstücke, die er nehmen wird, und wird jedes Bild gleichmäßig weitergezeichnet, an jedem Knoten auf einem Bogen. Ein Platzhalter, der echt wird, erscheint genau dort, wo er gezeichnet war, auch mitten in der Kurve.
- **Keine Autos mehr durch Platzhalter hindurch:** Echte Autos sehen Platzhalter nicht. Ein Platzhalter achtete bisher nur auf echte Autos vor sich in seiner Spur. Kommt ihm jetzt ein echtes Fahrzeug in den nächsten 3 Sekunden in die Quere, ob von hinten, entgegen oder quer, wird er sofort zum echten Auto, und das echte achtet dann auf ihn. Geht das gerade nicht, bremst er, statt hindurchzufahren. Steckt trotzdem einmal einer mitten in ihm, wird er so lange nicht gezeichnet.
- **Begegnung auf schmalen Straßen:** Auf schmalen Straßen blieben sich entgegenkommende Autos voreinander stehen, oder BeamNGs KI bremste bis zum Stand und setzte dann zurück. Der eigene Fahrer hielt einen Entgegenkommenden auf seiner Linie für einen Vordermann. Jetzt fahren beide früh auf Schritttempo herunter, der eigene Fahrer weicht an den rechten Rand aus, notfalls ein Stück auf das Bankett, und sie fahren langsam aneinander vorbei. Je weniger Platz bleibt, desto langsamer. Für einen Entgegenkommenden, der dort wartet, wird nicht mehr notgebremst und nicht mehr angestanden.
- **Dein LKW fährt im Autodrive um Baustellen und Hindernisse herum:** Das Autodrive von BeamNG.Earth kennt Fahrzeuge, aber keine Baken, keine verlorene Ladung und keine gesperrte Fläche um ein Wrack. Jetzt sieht die Mod für den LKW dieselben Sperren wie für den Verkehr. Er weicht aus, wo Platz ist: auf der eigenen Seite, auf der Spur daneben oder über die Gegenspur, wenn nichts kommt. Sonst wartet er davor und fährt danach wieder in seine Spur.
- **Untergrenze auch auf kurzen Straßen:** Ist die geladene Straße zu kurz für 150 m, kommt das Auto von hinten näher heran, so weit die Straße reicht. Vorher griff die Untergrenze im letzten Test nur ein einziges Mal.
- Ein Platzhalter, der gerade echt geworden ist, löst keine Notbremse mehr aus (das Spiel meldet in den ersten Bildern ein unsinniges Tempo, bis über 9000 km/h).

- **Der eigene Fahrer lenkt öfter:** Er übernimmt ein Auto jetzt gleich eine halbe Sekunde nach dem Versetzen oder Echtwerden, statt bis zu 15 Sekunden zu warten. Er übernimmt auch Autos, die bis etwa 32 Grad schräg zur Straße stehen, richtet sie langsam aus und übernimmt dabei BeamNGs Lenkeinschlag. Kurze geladene Straßenstücke nimmt er ebenfalls. Nach einer Rückgabe an BeamNG fragt er schneller wieder nach.

- Übernahm der eigene Fahrer ein Auto, während die Verkehrs-KI dessen Tempogrenze gerade aufhob, fuhr er mit der alten Grenze weiter, auf der Autobahn teils mit 38 km/h. Er bekommt jetzt bei jeder Übernahme die Grenze, die gerade gilt.
- Platzhalter werden in der Nähe eines Wracks oder Unfalls nicht mehr echt, gleich in welcher Richtung das Wrack steht.

- **Autobahnauffahrten:** Auf der Auffahrt steht oft 30 oder 40, und der Verkehr fuhr dort lange Stücke nur so schnell. Jetzt erkennen die Autos, dass ihre Einbahnstrecke in eine Autobahn mündet, und beschleunigen so, dass sie an der Einmündung fast auf Autobahntempo sind. Kurven auf der Auffahrt fahren sie weiterhin langsam.

- **Platzhalter auch nach dem Neuladen der Welt:** Wurde die Welt neu geladen, etwa nach einer Fahrt per Ladebildschirm, verschwanden alle Platzhalter-Autos für den Rest der Sitzung. Sie werden jetzt automatisch neu angelegt. Außerdem sind Platzhalter jetzt im ganzen geladenen Umkreis zu sehen, und echte Autos werden erst ab 130 m statt 90 m wieder zu Platzhaltern.
- **Schmale Straßen:** Die Autos weichen bei Gegenverkehr weiter aufs Bankett aus und fahren dort im Schritttempo vorbei.
- **Kein Rückwärtsfahren aus dem Nichts mehr:** Setzt ein Verkehrsauto zurück, wird es in deiner Nähe angehalten, und der eigene Fahrer übernimmt. Außer Sicht wird es weggenommen.
- **Autodrive:** Das Ausweichen um eine Sperre endet jetzt, sobald die Route abbiegt, spätestens nach 25 Sekunden. Vorher fuhr der LKW teils lange auf der Gegenspur, und das Lenkrad zuckte hin und her.

- **Gleiches Auto, gleiche Farbe:** Jeder Platzhalter hat jetzt von Anfang an sein echtes Auto. Wird er echt, erscheint genau dieses Modell in seiner Farbe. Ein Auto, das zum Platzhalter wurde, kommt als dasselbe Auto zurück.
- **Kein Tempo-Sprung beim Echtwerden:** Ein Auto, das als Platzhalter-Spender geschlafen hat, wachte mit dem Tempo auf, mit dem es eingeschlafen war, und fuhr so in stehende Autos. Jetzt fährt es genau mit dem Tempo des Platzhalters weiter, auch mit 0 km/h.
- Ein gerade echt gewordenes Auto wird mindestens 20 Sekunden lang nicht wieder zum Platzhalter.
- **Kreuzungen:** Platzhalter fahren langsam an Kreuzungen heran und warten, wenn ein echtes Auto quer kommt.
- **Realistischere Verkehrsmenge:** Auf Landstraßen und kleinen Straßen ist weniger los, und der Verkehr kommt in längeren Wellen, mal ein paar Minuten mehr, mal weniger.
- **Stau wieder voll:** Mit virtuellem Verkehr fand der Stau kaum Autos, weil fast alle als Platzhalter-Spender schliefen. Jetzt weckt er sie.

- **Der eigene Fahrer fährt selbst um Unfälle und Baustellen herum:** Auf Straßen mit einer Spur je Richtung gab er das Auto vor einer Sperre bisher an BeamNGs KI ab, und die blieb oft einfach stehen. Jetzt wartet er selbst auf eine Lücke im Gegenverkehr, fährt vorbei und reiht sich wieder ein.
- Lkw im Verkehr biegen an sanften Abzweigen selbst ab. Nur an scharfen Ecken übernimmt noch BeamNG.

- **Vorfahrt auf der Landstraße:** Kreuzten sich außerorts zwei Straßen derselben Klasse, galt bisher rechts vor links. Jetzt ist dort die durchgehende Straße die Vorfahrtsstraße, wie es die Schilder außerorts fast immer sagen. Rechts vor links gilt nur noch bei gleichrangigen Straßen im Ort.

- **Keine auftauchenden und verschwindenden Autos mehr:** BeamNG weckte bei jeder Änderung der Verkehrsmenge alle schlafenden Platzhalter-Spender und schaffte es wegen eines Zeitfehlers nicht, sie sofort wieder schlafen zu legen. Dann standen bis zu 30 Autos kurz an Stellen, wo sie längst nicht mehr hingehörten. Schlafende Autos sind jetzt ganz aus BeamNGs Fahrzeug-Pool herausgenommen.
- Ein Platzhalter wartet jetzt auf ein echtes Auto seines Modells, statt als anderes Modell zu erscheinen, außer es eilt.

- **Stau ohne Massenkarambolage:** Autos, die für einen Stau aus dem Schlaf geholt wurden, wachten mit ihrem alten Tempo auf und rasten in die stehende Schlange. Sie stehen jetzt beim Einsetzen still.

- **Keine Angst mehr vor deinem LKW:** Entgegenkommende Autos auf der Landstraße wichen dir aufs Bankett aus und bremsten stark, obwohl genug Platz war. Jetzt machen sie das nur noch, wenn es wirklich eng wird. Auch das seitliche Wegschieben von BeamNGs Fahr-KI ist deutlich schwächer.

- **Keine mit Tempo eingesetzten Autos mehr im Stau:** Musste die Mod ein Auto wegnehmen (durch den Boden gefallen, rückwärts gefahren, Wrack geräumt), setzte BeamNG es oft mit Autobahntempo irgendwo voraus wieder ein, mitten in einen Stau oder vor ein Wrack. Mit virtuellem Verkehr schläft so ein Auto jetzt einfach ein und kommt später repariert als echtes Auto eines Platzhalters zurück.

- **Rückwärtsfahren aus dem Nichts, die eigentliche Ursache:** BeamNGs Automatikgetriebe nimmt das Bremspedal eines stehenden Autos als Wunsch, rückwärts zu fahren. Im Rückwärtsgang ist das Pedal dann Gas. Hielt die Mod ein Auto vor einer Sperre oder im Stau mit dem Bremspedal fest, kroch es deshalb rückwärts. Stehende Autos werden jetzt mit der Handbremse gehalten.
- **Mehr passende Modelle:** Ein Platzhalter sucht sich schon aus der Ferne das echte Auto aus, das er einmal wird, und nimmt dessen Modell und Farbe an, solange er noch weit weg ist.

- **Stau ohne Raser:** Autos, die der Stau an ihren Platz setzt, auch die überholten, die er nach vorn bringt, behielten ihr altes Tempo und fuhren mit bis zu 100 km/h in die Schlange. Sie starten jetzt im Schritttempo.

- Platzhalter werden nicht mehr zu dicht an langen Fahrzeugen echt. Die Mod rechnete bisher jedes echte Fahrzeug als 4,6 m lang, auch deinen Lastzug.
- Kommt ein echtes Auto von hinten auf einen Platzhalter zu, wird der jetzt früh genug echt, statt erst direkt vor ihm.

## 1.0.4 (nicht einzeln erschienen, in 1.0.5 enthalten)

### Neu

- **Die Blaue Elise:** Eine Geschichte zieht sich durch die Karriere. Ein alter Fahrer oder der Pannenhelfer erzählt von Heinz Brandt, der 1998 mit seinem blauen Lkw spurlos verschwand. Du nimmst seine Enkelin Ronja mit, Mira bekommt einen seltsamen Anruf, und auf einem Rastplatz klopft ein alter Mann mit Schiebermütze an dein Fenster. Am Ende stehst du in der Scheune, in der die Elise seit 27 Jahren wartet.
- **Bekannte Gesichter:** Sechs Pannenhelfer mit eigenem Charakter, von Kalle aus dem Ruhrpott bis Basti, dem Schlagzeuger. Jede Gegend hat ihren eigenen, der sich erinnert, was beim letzten Mal kaputt war und wo. Vor der Arbeit erzählen sie noch etwas.
- **Anhalterinnen kommen wieder:** Wer gut mit dir ausgekommen ist, steht später vielleicht wieder am Straßenrand, erkennt dich und erzählt, wie ihre Geschichte weiterging.
- **Landroute:** Im Routenberater und in den Einstellungen lässt sich zwischen Autobahn und Landstraße wählen. Mit Landstraße führt das Navi von Ort zu Ort über Land.
- **Rastplätze und Parkplätze finden:** Die Mod kennt jetzt deutlich mehr Rastplätze und merkt sich zusätzlich jeden Parkplatz, den BeamNG.Earth beim Fahren baut. Parkplätze direkt an der Autobahn zählen als Rastplatz. Alle stehen auf der Karte im Büro und im Routenberater (grün R = Rastplatz, blau P = Parkplatz).
- **Klick auf die Karte:** Im Büro öffnet ein Klick auf einen Ort eine kleine Karte mit „Navi dorthin“ und „+ Route“. Im Routenberater startet ein Klick auf eine Markierung direkt das Navi.
- **Rastplatz-Ankündigung:** Auf der Autobahn sagt dir eine Meldung, wenn in den nächsten 2,5 km ein Rastplatz kommt, und erinnert dich daran, wenn du müde bist.
- **Autodrive-Schutz:** Schaden aus dem Autodrive zählt nicht. Zustand, Werkstattrechnung und Ladung bleiben, wie sie waren, und es gibt keinen Unfallbericht. Steht der LKW nach einem Rempler still, ist er an Ort und Stelle wieder heil.

### Verbessert

- Der Ring zum Schlafen liegt auf einem echten Stellplatz im Parkplatz statt auf der Straße daneben
- Fließender Verkehr auf der Autobahn: Die Fahr-KI bremst nicht mehr für kleine Knicke im Straßennetz, nicht mehr für das Tempolimit der Abfahrt nebenan und nicht mehr für Autos auf der Gegenfahrbahn
- Ein Auto auf der Nebenspur gilt für die Fahr-KI nicht mehr als Vordermann
- In Europa gibt es beim Händler nur europäische Lkw, in ihren verschiedenen Ausführungen, und die Aufträge kommen mit europäischen Aufliegern
- Die einfachen Verkehrsautos stehen nicht mehr zum Verkauf
- Der Pannendienst repariert den Kühler jetzt richtig, der Motor überhitzt danach nicht mehr
- Aussteigende Leute laufen auf dem Boden, statt in die Luft zu steigen
- Den Hof kannst du fast überall hinlegen: gesperrt ist nur noch der dicht bebaute Ortskern, nicht mehr das ganze Stadtgebiet

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
