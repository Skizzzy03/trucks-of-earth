# Installation

## Das brauchst du

- **BeamNG.drive 0.40** unter Windows
- **[BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth)** ab Version 1.8. Ohne diese Mod startet die Karriere nicht, denn sie liefert die echte Welt.
- Eine **Internetverbindung** für BeamNG.Earth und das Radio

BeamNG.Earth ist ein eigenes Projekt und **nicht in diesem Download enthalten**. Lade es auf der [Seite des Projekts](https://github.com/TecnaGamer/BeamNG.Earth) herunter und richte es nach der Anleitung dort ein. Prüfe zuerst, ob BeamNG.Earth allein läuft, bevor du Trucks of Earth dazunimmst.

## Die Mod installieren

1. BeamNG.Earth wie oben beschrieben installieren.
2. Unter [Releases](../../../releases/latest) die Datei `trucks_of_earth.zip` herunterladen.
3. Mit `Windows-Taste + R` das Ausführen-Fenster öffnen und das hier einfügen:
   ```
   %LOCALAPPDATA%\BeamNG\BeamNG.drive\current\mods
   ```
4. Die Zip in diesen Ordner legen. **Nicht entpacken.**
5. BeamNG.drive starten und unter **Mods** sowohl Trucks of Earth als auch BeamNG.Earth aktivieren.
6. Im Hauptmenü **Mehr → Trucks of Earth** öffnen und **Neue Karriere** wählen.

Beim ersten Start wählst du Firmenname und Standort deines Hofs. Danach führt dich das Handbuch durch alles Weitere.

## Zusatz-Mods

Pflicht ist nur BeamNG.Earth. Die Mods unten sind Empfehlungen, die wir selbst nutzen. Sie werden nicht mitgeliefert, die Links führen zu ihren eigenen Seiten. Was installiert ist, schaltet die Karriere beim Öffnen automatisch mit ein.

| Mod | Wofür |
|---|---|
| [Agent's Simplified Realistic Traffic Mod](https://www.beamng.com/threads/agents-simplified-realistic-traffic-mod-eu-jp-released.102034/) | Europäischer Verkehr. Ohne ihn fahren vereinfachte BeamNG-Autos. Im selben Forenbeitrag gibt es auch das Addon „Stock Groups“ mit den Fahrzeuggruppen |
| [Cherrier/Wentward Potent Lite](https://www.beamng.com/resources/37732/) | Europäische Frontlenker-Zugmaschine |
| [Bella's Semi Add-on](https://www.beamng.com/resources/29244/) | Mehr Teile für Zugmaschinen |
| [T-Series Drivetrain Expansion](https://www.beamng.com/resources/29462/) | Mehr Antriebe für die T-Series |
| [Extended T-Series Sleeper](https://www.beamng.com/resources/38075/) | Fernverkehrskabine |
| ['87-'98 Gavril MT-Series](https://www.beamng.com/resources/38126/) | Weitere Zugmaschinen beim Händler |
| [Truck Wheel Mod](https://www.beamng.com/resources/38079/) | Lkw-Räder |
| [Trailer ABS](https://www.beamng.com/resources/32937/) | ABS für Auflieger |
| [TA Trailer Expansion](https://www.beamng.com/resources/36780/) | Mehr Auflieger-Teile |
| [Fictional Delivery Companies Pack](https://www.beamng.com/resources/33100/) | Speditions-Lackierungen |
| [Reverse Camera](https://www.beamng.com/resources/35361/) | Rückfahrkamera. Im BeamNG-Repository als veraltet markiert |

**Probier ruhig aus, was du brauchst.** Mods, die du nicht willst, lässt du einfach weg oder deaktivierst sie und schaust, wie es dann läuft. Getestet haben wir vor allem mit allen Mods zusammen. Wenn ohne eine bestimmte Mod etwas nicht klappt, [sag uns gern Bescheid](../../../issues/new/choose).

## Radio-App (freiwillig)

Radio, Spotify-Steuerung und der Ton des Videoplayers laufen über eine kleine eigene App. Ohne sie funktioniert die Karriere normal, nur ohne Musik im Führerhaus.

1. Unter [Releases](../../../releases/latest) `Fernfahrer-Radio.zip` laden.
2. An einen beliebigen Ort entpacken, zum Beispiel in die Dokumente.
3. `Fernfahrer-Radio.exe` starten. Unten rechts erscheint ein Symbol im Infobereich.
4. BeamNG starten. Die Lampe am Radio im Spiel leuchtet grün, wenn Ton kommt.

Windows kann beim ersten Start warnen, weil die App nicht signiert ist. Dann auf **Weitere Informationen → Trotzdem ausführen** klicken. Der komplette Quelltext liegt im Ordner [radio-helper](../radio-helper), du kannst die App auch selbst bauen.

Für YouTube und Livestreams im Videoplayer lädt die App beim ersten Mal einmalig [yt-dlp](https://github.com/yt-dlp/yt-dlp) neben sich.

## Update

Die alte `trucks_of_earth.zip` durch die neue ersetzen. Deine Spielstände bleiben erhalten, sie liegen nicht in der Zip.

## Deinstallation

Die Zip aus dem `mods`-Ordner löschen. Wer auch die Spielstände entfernen will, löscht zusätzlich:

```
%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\settings\fernfahrer
```

Die Radio-App schließt du per Rechtsklick auf ihr Symbol und löschst dann ihren Ordner.
