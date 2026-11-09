<template>
  <!-- The career's start: welcome, the home yard on the map, the company's name (career.lua uiSetup). -->
  <div class="ff-setup">
    <div class="card" :class="{ wide: step === 1 }">
      <div class="steps">
        <span v-for="(s, i) in STEPS" :key="s" :class="{ on: i === step, done: i < step }">{{ i + 1 }}. {{ s }}</span>
      </div>

      <!-- 1 welcome -->
      <div v-if="step === 0" class="pane welcome">
        <div class="hero">
          <div class="logo">EK</div>
          <div>
            <div class="title">Willkommen bei der Trucks of Earth</div>
            <div class="sub">BeamNG.drive × BeamNG.Earth – deine eigene Spedition, auf echten Straßen.</div>
          </div>
        </div>
        <div class="cols">
          <div>
            <div class="h">So geht's</div>
            <ul>
              <li><b>Hof wählen:</b> Klick auf der Karte deinen Startort an – zum Beispiel dein Zuhause.</li>
              <li><b>Firma gründen:</b> Gib deiner Spedition einen Namen.</li>
              <li><b>Firmennetz:</b> Supermärkte, Baumärkte, Gewerbegebiete & Co. rund um deinen Hof werden zu Lade- und Abladestellen.</li>
            </ul>
          </div>
          <div>
            <div class="h">Unterwegs</div>
            <ul>
              <li><b>Strg+Umschalt+F</b> öffnet dein Büro: Frachtbörse, Fuhrpark, Händler, Bank.</li>
              <li>Das GPS führt dich zur Ladestelle und zum Kunden. Dort abkuppeln (<b>L</b>) und abladen.</li>
              <li>Anfangs fährst du Schnellaufträge mit Leih-LKW – später mit deinem eigenen.</li>
            </ul>
          </div>
        </div>
        <div class="server" :class="{ ok: st && st.connected, bad: st && !st.connected }">
          <span class="dot"></span>
          <span v-if="!st">Verbinde …</span>
          <span v-else-if="st.connected">BeamNG.Earth ist bereit.</span>
          <span v-else>BeamNG.Earth-Server noch nicht verbunden – Kartenbilder und Ortssuche brauchen ihn.</span>
        </div>
      </div>

      <!-- 2 home -->
      <div v-if="step === 1" class="pane home">
        <div class="bar">
          <input v-model="query" class="input" placeholder="Ort oder Adresse suchen, z. B. »Bocholt« oder deine Straße …"
                 @focus="typing(true)" @blur="typing(false)" @keydown.enter.stop.prevent="search" @keydown.stop />
          <button class="btn" @click="search">Suchen</button>
          <button class="btn" :disabled="!st || !st.player" @click="useHere">Meine Position</button>
        </div>
        <div v-if="results.length" class="results">
          <div v-for="(r, i) in results" :key="i" class="result" @click="pickResult(r)">
            <b>{{ r.name }}</b> <span>{{ r.detail }}</span>
          </div>
        </div>
        <div v-if="searchMsg" class="msg">{{ searchMsg }}</div>
        <FfMap ref="mapRef" class="map" :center="startCenter" :zoom="startZoom" :markers="markers" @pick="pick" />
        <div class="picked">
          <template v-if="home">Hof: <b>{{ homeName || "Gewählter Ort" }}</b> · {{ home.lat.toFixed(5) }}, {{ home.lon.toFixed(5) }}</template>
          <template v-else>Klick auf die Karte, um deinen Hof zu setzen.</template>
        </div>
      </div>

      <!-- 3 company -->
      <div v-if="step === 2" class="pane company">
        <label>Firmenname
          <input v-model="company" class="input" maxlength="40" placeholder="z. B. Nordlicht Logistik"
                 @focus="typing(true)" @blur="typing(false)" @keydown.stop />
        </label>
        <label>Dein Name (Fahrer)
          <input v-model="driver" class="input" maxlength="30" placeholder="z. B. Alex"
                 @focus="typing(true)" @blur="typing(false)" @keydown.stop />
        </label>
        <label>Name des Hofs
          <input v-model="homeName" class="input" maxlength="60" placeholder="z. B. Hof Bocholt"
                 @focus="typing(true)" @blur="typing(false)" @keydown.stop />
        </label>
        <!-- the start money: easy / medium / hard (2026-11-05) -->
        <div class="diff-h">Schwierigkeit · Startkapital</div>
        <div class="diff">
          <button v-for="d in DIFFS" :key="d.k" class="dopt" :class="{ on: diff === d.k }" @click="diff = d.k">
            <b>{{ d.l }}</b><span>{{ d.money.toLocaleString("de-DE") }} €</span><small>{{ d.sub }}</small>
          </button>
        </div>
        <div class="preview">
          <div class="plate">{{ company || "Deine Spedition" }}</div>
          <div class="sub">Startkapital {{ diffMoney.toLocaleString("de-DE") }} € · Leih-LKW für Schnellaufträge · Hof: {{ homeName || "–" }}</div>
        </div>
      </div>

      <!-- 4 go -->
      <div v-if="step === 3" class="pane go">
        <div class="title">{{ company }}</div>
        <div class="sub">Hof „{{ homeName || "Firmenhof" }}“ · {{ home && home.lat.toFixed(4) }}, {{ home && home.lon.toFixed(4) }}</div>
        <p>Nach dem Gründen wirst du mit deinem Leih-LKW zum Hof gebracht. Mira aus der Disposition sucht in der Zwischenzeit
          Firmen in der Umgebung – das dauert etwa eine Minute. Danach steht die Frachtbörse im Büro (<b>Strg+Umschalt+F</b>) bereit.</p>
        <div v-if="error" class="msg bad">{{ error }}</div>
      </div>

      <div class="nav">
        <button class="btn ghost" v-if="step > 0" @click="step--">Zurück</button>
        <span class="grow"></span>
        <button class="btn primary" v-if="step < 3" :disabled="!canNext" @click="step++">Weiter</button>
        <button class="btn primary" v-else :disabled="busy" @click="found">Firma gründen</button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from "vue"
import FfMap from "./FfMap.vue"
import { engineLua, call, navigate, typing, toArray } from "./ffBridge.js"

const STEPS = ["Willkommen", "Hof wählen", "Firma", "Los geht's"]
const step = ref(0)
const st = ref(null)
const mapRef = ref(null)
const query = ref(""), results = ref([]), searchMsg = ref("")
const home = ref(null), homeName = ref("")
const company = ref(""), driver = ref("")
const busy = ref(false), error = ref("")
const DIFFS = [
  { k: "easy", l: "Leicht", money: 100000, sub: "Viel Spielraum für den ersten eigenen LKW" },
  { k: "medium", l: "Mittel", money: 50000, sub: "Gut gepolstert starten" },
  { k: "hard", l: "Schwer", money: 10000, sub: "Klein anfangen, hocharbeiten" },
]
const diff = ref("medium")
const diffMoney = computed(() => (DIFFS.find(d => d.k === diff.value) || DIFFS[1]).money)

const startCenter = computed(() => (st.value && st.value.player) || { lat: 51.16, lon: 10.45 })
const startZoom = computed(() => (st.value && st.value.player ? 12 : 6))
const markers = computed(() => {
  const out = []
  if (st.value && st.value.player) out.push({ ...st.value.player, kind: "player", label: "Du bist hier" })
  if (home.value) out.push({ ...home.value, kind: "home", icon: "🏠", label: "Dein Hof" })
  return out
})
const canNext = computed(() => (step.value === 1 ? !!home.value : step.value === 2 ? company.value.trim().length > 0 : true))

function pick(p) { home.value = { lat: p.lat, lon: p.lon } }
function pickResult(r) {
  const lat = Number(r.lat), lon = Number(r.lon)
  home.value = { lat, lon }
  if (!homeName.value) homeName.value = r.name || ""
  results.value = []
  mapRef.value && mapRef.value.flyTo(lat, lon, 15)
}
function useHere() {
  if (!st.value || !st.value.player) return
  const p = st.value.player
  home.value = { lat: p.lat, lon: p.lon }
  mapRef.value && mapRef.value.flyTo(p.lat, p.lon, 15)
}

// the BeamNG.Earth geocoder (settings.lua uiGeocode / uiGeocodeResult: send, then poll)
let searchTimer = null
function search() {
  const q = query.value.trim()
  if (!q) return
  searchMsg.value = "Suche …"
  results.value = []
  engineLua(`beamngEarth_settings and beamngEarth_settings.uiGeocode and beamngEarth_settings.uiGeocode(${JSON.stringify(q)}) or nil`, r => {
    if (!r || r.error || !r.id) { searchMsg.value = (r && r.error) || "Ortssuche nicht verfügbar"; return }
    let tries = 0
    const poll = () => engineLua(`beamngEarth_settings.uiGeocodeResult(${r.id})`, res => {
      if (!res) { if (++tries < 40) searchTimer = setTimeout(poll, 250); else searchMsg.value = "Keine Antwort"; return }
      const list = toArray(res.results)
      results.value = list.slice(0, 8)
      searchMsg.value = res.error ? res.error : list.length ? "" : "Nichts gefunden"
      if (list.length === 1) pickResult(list[0])
    })
    poll()
  })
}

function found() {
  busy.value = true
  error.value = ""
  call("uiSetup", { company: company.value.trim(), driver: driver.value.trim(), homeName: homeName.value.trim(),
                    lat: home.value.lat, lon: home.value.lon, difficulty: diff.value }, r => {
    busy.value = false
    // (the loading screen of the drive to the yard – it goes on to the road once the world is there)
    // (career.lua has opened it itself: a second navigate broke the router's transition, 2026-11-08)
    if (r && r.ok) { if (!r.travel) navigate("play") }
    else error.value = (r && r.error) || "Das hat nicht geklappt."
  })
}

let timer = null
function refresh() { call("uiState", s => { if (s) st.value = s }) }
onMounted(() => { refresh(); timer = setInterval(refresh, 1500) })
onUnmounted(() => { clearInterval(timer); clearTimeout(searchTimer); typing(false) })
</script>

<style scoped>
.ff-setup { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center;
  background: radial-gradient(ellipse at 30% 20%, rgba(255,177,46,.18), transparent 60%), rgba(8,10,14,.82);
  color: #eef1f5; font-family: inherit; }
.card { width: min(860px, 94vw); max-height: 92vh; display: flex; flex-direction: column; padding: 22px 26px;
  background: rgba(16,19,25,.97); border: 1px solid rgba(255,255,255,.12); border-radius: 14px; box-shadow: 0 20px 70px rgba(0,0,0,.6); }
.card.wide { width: min(1200px, 96vw); height: 90vh; }
.steps { display: flex; gap: 18px; margin-bottom: 16px; font-size: 13px; color: #6f7a88; font-weight: 700; }
.steps .on { color: #ffb12e; } .steps .done { color: #9aa4b2; }
.pane { flex: 1; min-height: 0; display: flex; flex-direction: column; }
.hero { display: flex; gap: 18px; align-items: center; margin-bottom: 18px; }
.logo { font-size: 22px; font-weight: 900; color: #15100a; background: #f5a623 !important; width: 72px; height: 72px; display: flex; align-items: center; justify-content: center;
  background: rgba(255,177,46,.14); border-radius: 18px; }
.title { font-size: 28px; font-weight: 800; }
.sub { color: #9aa4b2; font-size: 14px; margin-top: 3px; }
.cols { display: grid; grid-template-columns: 1fr 1fr; gap: 26px; }
.h { font-size: 12px; text-transform: uppercase; letter-spacing: .08em; color: #ffb12e; font-weight: 800; margin-bottom: 6px; }
ul { margin: 0; padding-left: 18px; font-size: 14px; line-height: 1.55; }
.server { display: flex; align-items: center; gap: 10px; margin-top: 18px; padding: 9px 12px; border-radius: 8px; background: rgba(255,255,255,.05); font-size: 13.5px; }
.server .dot { width: 10px; height: 10px; border-radius: 50%; background: #8a949e; }
.server.ok .dot { background: #4fd18b; } .server.bad { background: rgba(255,107,94,.12); } .server.bad .dot { background: #ff6b5e; }
.bar { display: flex; gap: 8px; margin-bottom: 8px; }
.input { flex: 1; padding: 9px 12px; font-size: 14px; color: #eef1f5; background: rgba(255,255,255,.07);
  border: 1px solid rgba(255,255,255,.18); border-radius: 7px; outline: none; }
.input:focus { border-color: #ffb12e; }
.results { max-height: 160px; overflow-y: auto; margin-bottom: 8px; border: 1px solid rgba(255,255,255,.1); border-radius: 7px; }
.result { padding: 7px 12px; font-size: 13px; cursor: pointer; border-bottom: 1px solid rgba(255,255,255,.06); }
.result:hover { background: rgba(255,177,46,.15); }
.result span { color: #9aa4b2; margin-left: 6px; }
.map { flex: 1; min-height: 300px; border-radius: 10px; }
.picked { margin-top: 8px; font-size: 14px; color: #cfd6de; }
.company label { display: flex; flex-direction: column; gap: 6px; font-size: 13px; color: #9aa4b2; font-weight: 700; margin-bottom: 14px; }
.diff-h { font-size: 13px; color: #9aa4b2; font-weight: 700; margin: 2px 0 8px; }
.diff { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; margin-bottom: 14px; }
.dopt { display: flex; flex-direction: column; align-items: flex-start; gap: 3px; padding: 12px 14px; text-align: left; cursor: pointer;
  background: rgba(255,255,255,.05); border: 1px solid rgba(255,255,255,.14); border-radius: 10px; color: #eef1f5; font-family: inherit;
  transition: border-color .15s, background .15s, transform .15s; }
.dopt:hover { border-color: rgba(255,177,46,.6); transform: translateY(-1px); }
.dopt.on { border-color: #ffb12e; background: rgba(255,177,46,.12); box-shadow: 0 0 0 1px #ffb12e inset; }
.dopt b { font-size: 15px; } .dopt span { font-size: 18px; font-weight: 900; color: #ffb12e; font-variant-numeric: tabular-nums; }
.dopt small { font-size: 11.5px; color: #9aa4b2; }
.preview { margin-top: 6px; padding: 16px; border-radius: 10px; background: linear-gradient(135deg, rgba(255,177,46,.18), rgba(255,177,46,.04));
  border: 1px solid rgba(255,177,46,.35); }
.plate { font-size: 24px; font-weight: 800; letter-spacing: .02em; }
.go p { font-size: 14.5px; line-height: 1.55; color: #cfd6de; }
.msg { font-size: 13px; color: #9aa4b2; margin-bottom: 6px; } .msg.bad { color: #ff6b5e; }
.nav { display: flex; gap: 10px; margin-top: 16px; } .grow { flex: 1; }
.btn { padding: 9px 18px; font-size: 14px; font-weight: 700; color: #eef1f5; background: rgba(255,255,255,.08);
  border: 1px solid rgba(255,255,255,.2); border-radius: 7px; cursor: pointer; white-space: nowrap; }
.btn:hover { background: rgba(255,255,255,.15); }
.btn.primary { background: #ffb12e; border-color: #ffb12e; color: #1a1205; }
.btn.primary:hover { filter: brightness(1.08); }
.btn.ghost { background: transparent; }
.btn:disabled { opacity: .4; pointer-events: none; }
</style>
