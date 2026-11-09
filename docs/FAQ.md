# Häufige Fragen und Fehlerhilfe

## Ich finde die Karriere nicht im Menü

Sie steht im Hauptmenü unter **Mehr → Trucks of Earth**. Prüfe unter **Mods**, ob Trucks of Earth aktiv ist. Liegt die Zip im richtigen Ordner und ist nicht entpackt? Wenn die Mod zweimal vorhanden ist, zum Beispiel als Zip und als Ordner unter `mods\unpacked`, entferne eine davon.

## „BeamNG.Earth ist nicht installiert“

Die Karriere läuft nur mit [BeamNG.Earth](https://github.com/TecnaGamer/BeamNG.Earth) ab Version 1.8. Installiere die Mod und aktiviere sie.

## Es gibt kaum Firmen in meiner Gegend

Firmen und Rastplätze sind für Deutschland und die Nachbarländer mitgeliefert. Anderswo sucht die Mod sie online, das klappt nicht immer vollständig. Wähle im Zweifel einen Hof in Deutschland.

## Das Radio bleibt still

Die [Radio-App](INSTALLATION.md#radio-app-freiwillig) muss laufen. Die Lampe am Radio verrät den Zustand:

- **Grün:** Ton läuft
- **Gelb:** Sender wird geladen
- **Rot:** Die App läuft nicht

## Windows warnt vor der Radio-App

Die App ist nicht signiert, deshalb kommt die Warnung. Klicke auf **Weitere Informationen → Trotzdem ausführen**, oder baue sie selbst aus dem Quelltext im Ordner [radio-helper](../radio-helper).

## Der Equalizer wirkt bei Spotify nicht

Bei der Quelle Spotify regelt die App nur die Lautstärke. Für den Equalizer stellst du Spotify in Windows auf die Ausgabe „Steam Streaming Speakers“ und wählst am Radio die Quelle **LINE**.

## Die Musik beim Laden ist zu laut oder zu leise

Sie richtet sich nach dem Regler für Oberflächen-Töne im Spiel. Abschalten kannst du sie im Büro unter **Einstellungen → Lademusik**.

## Mein Lkw steckt fest oder eine Brücke fehlt

Bei einem Kartenfehler hilft `Strg+Umschalt+B`. Sonst setzt dich 🛣 in der Leiste links zurück auf die Straße, Schäden bleiben dabei.

## Das Spiel ruckelt

Stelle im Büro unter **Einstellungen** die **Leistung** auf **Maximale FPS**, oder verringere Verkehr und geparkte Autos. Auch die virtuellen Spiegel kosten Leistung.

## Wo liegen meine Spielstände?

```
%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\settings\fernfahrer\careers
```

## Einen Fehler melden

1. Spiel beenden, ohne es neu zu starten. Beim nächsten Start wird das Protokoll überschrieben.
2. Diese Datei sichern:
   ```
   %LOCALAPPDATA%\BeamNG\BeamNG.drive\current\beamng.log
   ```
3. Ein [Issue](../../../issues/new/choose) öffnen, beschreiben, was passiert ist, und die Datei anhängen.

## Warum geht Reset nicht mehr?

In der Karriere sind Reset, Bergen, Neuladen und die Fahrzeugmenüs von BeamNG gesperrt, sonst wäre jede Reparatur umsonst. In den Einstellungen unter „Entwicklermodus: BeamNG-Reset“ schaltest du sie wieder ein.

## Warum nur Europa, wenn es Trucks of Earth heißt?

Aktuell gibt es Aufträge, Firmen und Orte nur für Europa. Der Rest der Welt wird noch nicht unterstützt.
