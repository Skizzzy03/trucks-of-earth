-- Trucks of Earth: the dispatcher's radio messages. Each key is sent once per career ({company}, {driver} and the
-- caller's vars are filled in). Add-ons can add keys (fernfahrer_career.registerStory) and send them (.story).

local M = {}

M.FROM = 'Mira · Disposition'

M.TEXT = {
  founded = "Willkommen bei {company}, Chef! Ich bin Mira, deine Disposition. Bis wir einen eigenen LKW haben, fahren wir Schnellaufträge mit Leih-LKW. Ich erkunde gerade Firmen, Tankstellen, Werkstätten und Händler in der Gegend – schau gleich ins Büro (Strg+Umschalt+F).",
  welcomeBack = "Schön, dass du wieder da bist, {driver}. Dein Fahrzeug steht am Hof bereit.",
  network = "Ich habe {n} Orte rund um unseren Hof gefunden – Kunden, Tankstellen, Werkstätten und Händler. Die Frachtbörse ist voll!",
  networkPoor = "Bisher kenne ich erst {n} Firmen in der Gegend – die Ortssuche ist gerade überlastet. Ich frage in ein paar Minuten nochmal nach.",
  firstLongHaul = "Fernverkehr! Plan Tank- und Pausenstopps ein. Am Ziel suche ich dir gleich Rückfracht.",
  firstJob = "Erster Auftrag! Fahr zur Ladestelle und halt dort an, dann wird der Auflieger bereitgestellt. Ruhig fahren – die Ladung zählt.",
  firstDelivery = "Sauber abgeliefert! Das Geld ist auf dem Firmenkonto.",
  threeJobs = "Drei Touren, drei zufriedene Kunden. Es spricht sich herum, dass {company} zuverlässig ist.",
  ownTruckHint = "Mit einem eigenen LKW gehört uns der volle Frachtlohn. Fahr mal bei einem LKW-Händler vorbei – die Bank gibt uns Kredit.",
  ownTruck = "Unser erster eigener LKW! Ab jetzt zahlen wir Diesel und Werkstatt selbst, dafür gehört uns die ganze Fracht.",
  carBought = "Schicker Wagen! Damit kommst du schnell zu den Stützpunkten. Fahrzeugwechsel ist am Hof und an Logistik-Stützpunkten kostenlos.",
  tenJobs = "Zehn Lieferungen! Die ersten Stammkunden fragen direkt nach {company}.",
  late = "Das war zu spät, der Kunde hat sich beschwert. Plan die nächste Tour etwas großzügiger.",
  damaged = "Die Ladung hat einiges abbekommen. Der Kunde zieht uns das vom Lohn ab.",
  cargoHit = "Vorsicht, die Ladung hat gerade was abbekommen! Jeder Kratzer kostet uns Lohn.",
  lowFuel = "Der Tank wird knapp! Im Routenberater findest du die nächste Tankstelle.",
  firstFuel = "Vollgetankt. Tipp: Autohöfe an der Autobahn haben meistens die besten Plätze für den Zug.",
  firstRepair = "Die Werkstatt hat ganze Arbeit geleistet. Ein heiles Fahrzeug spart Ärger beim Kunden.",
  firstDiscovery = "Schöner Ausblick, oder? Für jeden neuen Aussichtspunkt gibt's Erfahrung – Mira mag Fotos!",
  firstRoadworks = "Baustelle voraus! Tempo runter – in Baustellen wird gern geblitzt, und die Bußgelder zahlen wir.",
  beerAtWheel = "Ein Bier während der Fahrt? Ab 0,5 Promille sind 500 € und ein Monat Fahrverbot fällig, mit einem Unfall reichen schon 0,3. Die Polizei pustet bei jeder Kontrolle – und mich fragt dann die Versicherung.",
  jointAtWheel = "Ernsthaft, im Führerhaus? Kiffen ist erlaubt, Fahren danach nicht: THC über 3,5 ng/ml kostet 500 € und den Lappen für einen Monat, und der Wert bleibt stundenlang drin. Mach lieber eine lange Pause.",
  firstFine = "Ein Bußgeld … Das geht vom Firmenkonto ab. Im Büro unter „Firma“ siehst du alle Strafzettel.",
  tachoBreak = "Denk an deine Lenkzeit! Spätestens nach 4,5 Stunden sind 45 Minuten Pause Pflicht – einfach anhalten, der Fahrtenschreiber zählt mit.",
  firstRest = "Gut ausgeruht geht's besser. Die Tageslenkzeit ist wieder voll.",
  roadside = "Die Pannenhilfe hat dich wieder flott gemacht. Fahr vorsichtig, das wird sonst teuer!",
  dealerHere ="Du bist beim Händler – öffne das Büro, dort siehst du das Angebot vor Ort.",
}

return M
