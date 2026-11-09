<template>
  <!-- The passage screen of a ferry crossing or a flight (career.lua travel): a ship on the waves or a plane above
       the clouds, the route, the time on board, while BeamNG.Earth moves the world to the other side. Polls uiTrip;
       back to the road once arrived (and shown for at least MIN_S). -->
  <div class="fft" :class="[kind, { night }]">
    <div class="sky"></div>
    <div class="sun"></div>
    <template v-if="kind === 'ferry'">
      <div class="ship-wrap"><svg class="ship" viewBox="0 0 420 140" preserveAspectRatio="xMidYMax meet">
        <path d="M20 92 L400 92 L372 126 L44 126 Z" fill="#e9edf2" />
        <path d="M44 126 L372 126 L366 133 L52 133 Z" fill="#b8252b" />
        <rect x="70" y="66" width="250" height="26" rx="2" fill="#f5f7fa" />
        <rect x="120" y="44" width="170" height="22" rx="2" fill="#f5f7fa" />
        <rect x="170" y="26" width="80" height="18" rx="2" fill="#f5f7fa" />
        <rect x="205" y="6" width="22" height="22" fill="#1d3a6e" />
        <g fill="#2c4f78"><rect v-for="i in 14" :key="'w' + i" :x="80 + i * 16" y="72" width="9" height="7" rx="1" /></g>
        <g fill="#2c4f78"><rect v-for="i in 9" :key="'u' + i" :x="130 + i * 16" y="50" width="9" height="7" rx="1" /></g>
        <rect x="290" y="78" width="70" height="14" fill="#f5a623" /><rect x="335" y="70" width="24" height="22" fill="#d9483b" />
      </svg></div>
      <svg class="waves w1" viewBox="0 0 1200 60" preserveAspectRatio="none"><path d="M0 30 Q 75 10 150 30 T 300 30 T 450 30 T 600 30 T 750 30 T 900 30 T 1050 30 T 1200 30 V60 H0 Z" /></svg>
      <svg class="waves w2" viewBox="0 0 1200 60" preserveAspectRatio="none"><path d="M0 30 Q 75 50 150 30 T 300 30 T 450 30 T 600 30 T 750 30 T 900 30 T 1050 30 T 1200 30 V60 H0 Z" /></svg>
    </template>
    <template v-else-if="kind === 'road'">
      <div class="hills"></div>
      <div class="tarmac"><div class="dash"></div></div>
      <svg class="truck" viewBox="0 0 300 90">
        <rect x="6" y="14" width="196" height="56" rx="2" fill="#e9edf2" />
        <rect x="6" y="62" width="196" height="8" fill="#b8252b" />
        <path d="M206 30 L250 30 Q262 30 266 42 L272 60 L272 70 L206 70 Z" fill="#1d3a6e" />
        <path d="M232 36 L252 36 Q258 36 261 44 L264 52 L232 52 Z" fill="#9cc3e6" />
        <rect x="200" y="62" width="10" height="6" fill="#30363f" />
        <g fill="#1b1f25"><circle cx="40" cy="74" r="10" /><circle cx="64" cy="74" r="10" /><circle cx="88" cy="74" r="10" />
          <circle cx="222" cy="74" r="10" /><circle cx="256" cy="74" r="10" /></g>
        <g fill="#8d96a3"><circle cx="40" cy="74" r="4" /><circle cx="64" cy="74" r="4" /><circle cx="88" cy="74" r="4" />
          <circle cx="222" cy="74" r="4" /><circle cx="256" cy="74" r="4" /></g>
      </svg>
    </template>
    <template v-else>
      <div class="cloud c1"></div><div class="cloud c2"></div><div class="cloud c3"></div><div class="cloud c4"></div>
      <svg class="plane" viewBox="0 0 200 80">
        <path d="M10 42 L150 36 Q178 35 190 40 Q178 45 150 44 L10 46 Z" fill="#f2f4f7" />
        <path d="M80 40 L120 4 L132 4 L108 40 Z" fill="#dfe4ea" /><path d="M80 44 L120 76 L132 76 L108 44 Z" fill="#c9d0d8" />
        <path d="M14 40 L26 18 L34 18 L30 40 Z" fill="#d9483b" />
        <g fill="#5a7da8"><circle v-for="i in 10" :key="'p' + i" :cx="50 + i * 9" cy="39" r="1.6" /></g>
      </svg>
    </template>

    <div class="card">
      <div class="kicker">{{ kindLabel }}{{ trip && trip.operator ? ' · ' + trip.operator : '' }}</div>
      <div v-if="kind === 'road'" class="resume">
        <b>{{ trip ? trip.to : '' }}</b>
        <span v-if="trip && trip.road">{{ trip.road }}</span>
        <span v-if="trip && trip.job">Auftrag läuft · Ziel {{ trip.job }}</span>
      </div>
      <div v-else class="route">
        <div><b>{{ trip ? (trip.fromCode || trip.from) : '' }}</b><span>{{ trip && trip.fromCode ? trip.from : '' }}</span></div>
        <div class="arc"><i :style="{ width: (progress * 100) + '%' }"></i><em>{{ kind === 'ferry' ? '⚓' : '✈' }}</em></div>
        <div><b>{{ trip ? (trip.toCode || trip.to) : '' }}</b><span>{{ trip && trip.toCode ? trip.to : '' }}</span></div>
      </div>
      <div class="facts">
        <span v-if="kind !== 'road'">{{ trip ? hours(trip.hours) : '' }} {{ kind === 'ferry' ? 'an Bord' : 'Flugzeit' }}</span>
        <span v-else-if="trip && trip.arrival">{{ trip.arrival }} Uhr</span>
        <span v-if="trip && trip.arrival && kind !== 'road'">Ankunft {{ trip.arrival }} Uhr</span>
        <span v-if="trip && trip.trailer">mit Auflieger</span>
        <span v-if="kind === 'fly'">Am Ziel zu Fuß zum Mietwagen</span>
      </div>
      <div class="status">{{ statusText }}</div>
      <div class="tip" v-if="kind === 'road'"><b>Tipp</b> {{ tip }}</div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from "vue"
import { call, navigate } from "./ffBridge.js"
import { sound } from "./ffSound.js"

const MIN_S = 7
const trip = ref(null)
const t0 = Date.now()
const elapsed = ref(0)
const arrived = ref(false)
const kind = computed(() => {
  const m = trip.value && trip.value.mode
  return m === "fly" || m === "road" ? m : "ferry"
})
const kindLabel = computed(() => kind.value === "road" ? (trip.value && trip.value.world ? "Karriere wird geladen" : "Weiterfahrt") : kind.value === "fly" ? "Flug" : (trip.value && trip.value.train ? "Autozug" : "Überfahrt"))
const night = computed(() => trip.value && trip.value.night)
const progress = computed(() => Math.min(1, elapsed.value / MIN_S * (arrived.value ? 1 : 0.85)))
const loading = ref(null), moving = ref(true)
const statusText = computed(() => {
  if (kind.value === "road") {
    if (arrived.value) return trip.value && trip.value.trailer ? "Alles bereit – der Auflieger wird angekuppelt" : "Alles bereit – gute Fahrt"
    const l = loading.value, parts = loadParts(l)
    if (l && l.yard) return "Einen Moment: Dein Hof wird geladen und dein Lkw abgestellt …"
    if (l && l.settling && !parts.length) return "Letzte Details …"
    if (parts.length) return parts.join(", ") + " werden geladen …"
    return trip.value && trip.value.world ? "Die Welt wird geladen …" : "Zurück zu deiner letzten Position …"
  }
  if (arrived.value) return kind.value === "ferry" ? "Angelegt – du fährst von Bord" : "Gelandet – der Mietwagen-Schalter ist gleich in der Nähe"
  // (there, the world still loading behind this screen)
  if (!moving.value && loading.value) {
    const l = loading.value, parts = loadParts(l)
    const lead = kind.value === "ferry" ? "Einfahrt in den Hafen – " : "Landeanflug – "
    return lead + (parts.length ? parts.join(", ") + " werden geladen …" : "letzte Details …")
  }
  const s = elapsed.value
  if (kind.value === "ferry") return s < 2 ? "Fahrzeug wird an Bord eingewiesen …" : s < 4.5 ? "Leinen los …" : "Auf See – der Hafen am Ziel wird geladen …"
  return s < 2 ? "Boarding …" : s < 4.5 ? "Start …" : "Über den Wolken – der Zielflughafen wird geladen …"
})
// (the loading screen's tips: one every 6 s, starting at a random one)
const TIPS = [
  "Leuchtende Kreise an Rastplätzen, Tankstellen, Werkstätten und am Hof: reinfahren, anhalten, Enter – dann öffnet sich das Menü des Ortes.",
  "Nach dem Anhalten steht der Fahrtenschreiber auf „Arbeit“. Als Pause zählt nur, was du mit 🛏 startest.",
  "Nach 4,5 h Lenkzeit sind 45 min Pause Pflicht – oder geteilt: erst 15, später 30 Minuten.",
  "Die Halle auf deinem Hof ist groß genug für Zugmaschine und Auflieger.",
  "Ab 0,5 Promille oder THC über 3,5 ng/ml wird jede Polizeikontrolle teuer.",
  "Die Karte im Routenberater kann mitdrehen (🧭) und schräg nach vorn schauen (3D).",
  "Bei der Polizeikontrolle in die blaue Fläche fahren und kurz anhalten.",
  "Strg+Umschalt+F öffnet das Büro – Aufträge, Fuhrpark, Bank und Dokumente.",
  "Ein Kaffee aus der Kabine nimmt 20 % Müdigkeit, richtig fit macht nur Schlaf.",
  "Fähren zählen als Pause: wer übersetzt, ruht gleichzeitig.",
]
const tipStart = Math.floor(Math.random() * TIPS.length)
const tip = computed(() => TIPS[(tipStart + Math.floor(elapsed.value / 6)) % TIPS.length])
function loadParts(l) {
  const parts = []
  if (!l) return parts
  if (l.ground) parts.push("Gelände")
  if (l.roads) parts.push("Straßen (" + l.roads + ")")
  if (l.buildings) parts.push("Gebäude")
  if (l.trees) parts.push("Bäume (" + l.trees + ")")
  return parts
}
const hours = h => (h < 1 ? Math.round(h * 60) + " min" : (Math.round(h * 4) / 4).toLocaleString("de-DE") + " h")

let timer = null
// (where to after the screen: the road – or, for a new career, its setup screen; career.lua uiTrip next)
let next = "play"
let leaving = false   // (false when the screen went by Esc: a new career still needs its setup screen, 2026-11-08)
function poll() {
  elapsed.value = (Date.now() - t0) / 1000
  // (never stuck: the first load once needed Esc, 2026-11-04)
  if (elapsed.value > 200 && timer) { clearInterval(timer); timer = null; leaving = true; navigate(next); return }
  call("uiTrip", r => {
    if (r && r.trip) trip.value = r.trip
    if (r) { loading.value = r.loading || null; moving.value = !!r.moving; next = r.next || "play" }
    if (r && !r.active) arrived.value = true
    if (arrived.value && elapsed.value >= MIN_S) { clearInterval(timer); timer = null; leaving = true; sound("done"); setTimeout(() => navigate(next), 600) }
  })
}
onMounted(() => { call("loadMusic", true); poll(); timer = setInterval(poll, 400) })
onUnmounted(() => {
  call("loadMusic", false)
  if (timer) clearInterval(timer)
  if (!leaving) setTimeout(() => call("uiTravelLeft"), 300)
})
</script>

<style scoped>
.fft { position: absolute; inset: 0; overflow: hidden; color: #eef1f5; font-family: inherit; background: #0b1622; }
.sky { position: absolute; inset: 0; background: linear-gradient(180deg, #5d9fd6 0%, #a9d1ee 55%, #e6f1f8 100%); }
.fft.night .sky { background: linear-gradient(180deg, #050b18 0%, #13284a 60%, #2b4a72 100%); }
.sun { position: absolute; right: 14%; top: 12%; width: 90px; height: 90px; border-radius: 50%; background: radial-gradient(circle, #fff6d5 0%, #ffd77a 55%, rgba(255,215,122,0) 72%); }
.fft.night .sun { background: radial-gradient(circle, #f4f6ff 0%, #c9d3ef 50%, rgba(201,211,239,0) 70%); width: 60px; height: 60px; }
/* ferry */
.fft.ferry .sky { bottom: 28%; }
.fft.ferry::after { content: ""; position: absolute; left: 0; right: 0; bottom: 0; height: 30%; background: linear-gradient(180deg, #1f5f8b, #0c2f4c); }
.fft.ferry.night::after { background: linear-gradient(180deg, #0f2a44, #050f1c); }
.ship-wrap { position: absolute; z-index: 2; bottom: 24%; left: 0; width: 38vw; max-width: 560px; animation: sail 16s linear forwards; will-change: transform; }
@keyframes sail { from { transform: translateX(-40vw); } to { transform: translateX(105vw); } }
@keyframes bob { 0%, 100% { transform: translateY(0) rotate(-0.4deg); } 50% { transform: translateY(6px) rotate(0.4deg); } }
.waves { position: absolute; z-index: 3; left: 0; width: 200%; height: 70px; fill: rgba(255,255,255,.12); }
.waves.w1 { bottom: 22%; animation: wave 7s linear infinite; }
.waves.w2 { bottom: 19%; fill: rgba(10,40,70,.55); animation: wave 11s linear infinite reverse; }
@keyframes wave { to { transform: translateX(-50%); } }
/* flight */
.cloud { position: absolute; z-index: 1; height: 60px; border-radius: 40px; left: 0; background: radial-gradient(ellipse at center, rgba(255,255,255,.9) 40%, rgba(255,255,255,0) 72%); animation: drift linear infinite; will-change: transform; }
.fft.night .cloud { background: rgba(160,180,215,.25); }
.cloud::before, .cloud::after { content: ""; position: absolute; background: inherit; border-radius: 50%; }
.cloud::before { width: 60%; height: 140%; left: 12%; top: -60%; } .cloud::after { width: 40%; height: 110%; right: 14%; top: -40%; }
.c1 { width: 260px; top: 62%; animation-duration: 9s; } .c2 { width: 180px; top: 74%; animation-duration: 6.5s; animation-delay: -3s; }
.c3 { width: 320px; top: 82%; animation-duration: 11s; animation-delay: -6s; } .c4 { width: 140px; top: 22%; animation-duration: 14s; animation-delay: -2s; }
@keyframes drift { from { transform: translateX(110vw); } to { transform: translateX(-40vw); } }
.plane { position: absolute; z-index: 2; width: 30vw; max-width: 420px; left: 34%; top: 34%; animation: fly 4s ease-in-out infinite; }
@keyframes fly { 0%, 100% { transform: translateY(0) rotate(-2deg); } 50% { transform: translateY(-14px) rotate(-1deg); } }
/* resume: a truck on the road */
.fft.road .sky { bottom: 30%; }
.hills { position: absolute; left: -10%; right: -10%; bottom: 28%; height: 18%; z-index: 1; background: #5f8a4e;
  border-radius: 50% 50% 0 0 / 100% 100% 0 0; }
.fft.road.night .hills { background: #1d2e22; }
.tarmac { position: absolute; left: 0; right: 0; bottom: 0; height: 30%; background: #3a3f46; z-index: 1; overflow: hidden; }
.fft.road.night .tarmac { background: #1c1f24; }
.dash { position: absolute; left: 0; width: 200%; top: 46%; height: 6px;
  background: repeating-linear-gradient(90deg, #e9edf2 0 70px, transparent 70px 160px); animation: dash 1.2s linear infinite; }
@keyframes dash { to { transform: translateX(-160px); } }
.truck { position: absolute; z-index: 2; width: 34vw; max-width: 480px; left: 30%; bottom: 24%; animation: rumble .35s ease-in-out infinite; }
@keyframes rumble { 0%, 100% { transform: translateY(0); } 50% { transform: translateY(1.5px); } }
.resume { margin: 10px 0 12px; }
.resume b { display: block; font-size: 22px; font-weight: 900; }
.resume span { display: block; font-size: 12.5px; color: #8b95a3; margin-top: 2px; }
/* the card */
.card { position: absolute; z-index: 5; left: 50%; bottom: 6vh; transform: translateX(-50%); width: min(720px, 90vw); background: rgba(12,16,22,.88);
  border: 1px solid rgba(255,255,255,.12); border-radius: 8px; padding: 18px 24px; box-shadow: 0 18px 50px rgba(0,0,0,.45); }
.kicker { font-size: 11px; letter-spacing: .16em; text-transform: uppercase; color: #f5a623; font-weight: 800; }
.route { display: flex; align-items: center; gap: 18px; margin: 10px 0 12px; }
.route > div:first-child, .route > div:last-child { flex: 0 0 auto; max-width: 34%; }
.route b { display: block; font-size: 22px; font-weight: 900; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.route span { display: block; font-size: 11.5px; color: #8b95a3; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.arc { flex: 1; height: 4px; background: #252c36; border-radius: 2px; position: relative; }
.arc i { position: absolute; left: 0; top: 0; bottom: 0; background: #f5a623; border-radius: 2px; transition: width .4s linear; }
.arc em { position: absolute; top: -13px; left: 50%; font-style: normal; font-size: 18px; transform: translateX(-50%); }
.facts { display: flex; gap: 18px; flex-wrap: wrap; font-size: 13px; color: #cfd6de; }
.status { margin-top: 10px; font-size: 13px; font-weight: 700; color: #a6efc0; }
.tip { margin-top: 10px; padding-top: 9px; border-top: 1px solid rgba(255,255,255,.08); font-size: 12.5px; color: #cfd6de; line-height: 1.4; }
.tip b { color: #f5a623; font-size: 10.5px; letter-spacing: .14em; text-transform: uppercase; margin-right: 6px; }
</style>
