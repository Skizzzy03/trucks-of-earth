<template>
  <!-- The menu of a stop (career.lua uiStop / stopDo): opened with Enter standing in the glowing ring of a rest area,
       a fuel stop, a workshop, a dealer, a port or the yard. Left what the place offers, right resting: a 45 min
       break anywhere, the daily and weekly rests where one may sleep – with the time it will be afterwards. -->
  <div class="ffs" @click.self="back">
    <div class="card" v-if="v && !v.none">
      <div class="head">
        <div class="ring" :class="v.place.color"><span>{{ v.place.icon }}</span></div>
        <div class="title">
          <div class="kicker">{{ v.place.typeName }}</div>
          <div class="name">{{ v.place.name }}</div>
        </div>
        <div class="stats">
          <div><span>Konto</span><b>{{ v.moneyText }}</b></div>
          <div v-if="tankPct !== null"><span>Tank</span><b :class="{ low: tankPct < 25 }">{{ tankPct }} %</b></div>
          <div v-if="v.fatigue"><span>Müdigkeit</span><b :class="{ low: v.fatigue.pct >= 70 }">{{ v.fatigue.pct }} %</b></div>
          <div class="clk"><span>{{ v.weekday }}</span><b>{{ v.clock }}</b></div>
        </div>
      </div>

      <div class="body">
        <!-- the areas of this place: one at a time, so that a fuel station is not one long list -->
        <nav class="rail">
          <a v-for="t in tabs" :key="t.id" :class="[{ on: tab === t.id }, t.id]" @mouseenter="hov" @click="pick(t.id)">
            <i>{{ t.icon }}</i><span><b>{{ t.label }}</b><small>{{ t.sub }}</small></span>
          </a>
        </nav>

        <section class="pane" :key="tab">
          <!-- filling up -->
          <template v-if="tab === 'fuel' && fuelAct">
            <h2>Tanken</h2>
            <div class="hero">
              <div class="gauge" :class="{ low: tankPct !== null && tankPct < 25 }"><i :style="{ width: (tankPct || 0) + '%' }"></i></div>
              <div class="hero-t"><b>{{ tankPct !== null ? tankPct + ' % im Tank' : 'Tank' }}</b><small>{{ fuelAct.disabled ? 'Der Tank ist voll.' : 'Du bezahlst, was reingeht.' }}</small></div>
              <button class="cta" :disabled="fuelAct.disabled" @mouseenter="hov" @click="run('refuel')">⛽ Volltanken</button>
            </div>
          </template>

          <!-- the shop -->
          <template v-if="tab === 'shop'">
            <h2>Shop <small>Alles kommt in die Kabine</small></h2>
            <div class="cabin">
              <span v-for="c in CABIN" :key="c.k" :class="{ none: !(inv[c.k] || 0) }"><i>{{ c.i }}</i><b>{{ inv[c.k] || 0 }}</b><small>{{ c.l }}</small></span>
            </div>
            <template v-for="s in shopSections" :key="s.t">
              <h3>{{ s.t }}</h3>
              <div class="tiles">
                <button v-for="a in s.items" :key="a.id" class="tile" :disabled="a.disabled" @mouseenter="hov" @click="run(a.id)">
                  <span class="t-ic">{{ a.icon }}</span>
                  <b>{{ a.shop.name }}</b>
                  <small>{{ a.shop.why || a.shop.sub }}</small>
                  <span class="t-ft"><em>{{ a.shop.price }}</em><u v-if="a.shop.have !== undefined && a.shop.have !== null">{{ a.shop.have }} dabei</u></span>
                </button>
              </div>
            </template>
          </template>

          <!-- behind the building -->
          <template v-if="tab === 'shady'">
            <h2>Hinterhof <small>Hier fragt keiner nach einer Quittung</small></h2>
            <button v-if="backTry" class="door" :disabled="backTry.disabled" @mouseenter="hov" @click="run('back:try')">
              <span>🚶</span><div><b>{{ backTry.label }}</b><small>{{ backTry.sub }}</small></div><em>Hingehen</em>
            </button>
            <template v-if="shadyGoods.length">
              <h3>Ware</h3>
              <div class="tiles">
                <button v-for="a in shadyGoods" :key="a.id" class="tile dark" :disabled="a.disabled" @mouseenter="hov" @click="run(a.id)">
                  <span class="t-ic">{{ a.icon }}</span><b>{{ a.shop.name }}</b><small>{{ a.shop.why || a.shop.sub }}</small>
                  <span class="t-ft"><em>{{ a.shop.price }}</em><u v-if="a.shop.have !== undefined && a.shop.have !== null">{{ a.shop.have }} dabei</u></span>
                </button>
              </div>
            </template>
            <template v-if="shadyJobs.length">
              <h3>Fracht ohne Papiere</h3>
              <button v-for="a in shadyJobs" :key="a.id" class="row warn" :disabled="a.disabled" @mouseenter="hov" @click="run(a.id)">
                <span class="r-ic">{{ a.icon }}</span><span class="r-tx"><b>{{ a.label }}</b><small>{{ parts(a).text }}</small></span><em v-if="parts(a).price">{{ parts(a).price }}</em>
              </button>
            </template>
          </template>

          <!-- the workshop -->
          <template v-if="tab === 'work'">
            <h2>Werkstatt</h2>
            <div class="hero" v-if="repairAct">
              <span class="hero-ic">🔧</span>
              <div class="hero-t"><b>{{ repairAct.disabled ? 'Keine Schäden' : 'Reparatur' }}</b><small>{{ repairAct.disabled ? 'Dein LKW ist in Ordnung.' : repairAct.sub }}</small></div>
              <button class="cta" :disabled="repairAct.disabled" @mouseenter="hov" @click="run('repair')">Reparieren</button>
            </div>
            <template v-for="s in workSections" :key="s.t">
              <h3>{{ s.t }}</h3>
              <button v-for="a in s.items" :key="a.id" class="row" :class="{ warn: a.warn }" :disabled="a.disabled" @mouseenter="hov" @click="run(a.id)">
                <span class="r-ic">{{ a.icon }}</span><span class="r-tx"><b>{{ a.label }}</b><small>{{ parts(a).text }}</small></span><em v-if="parts(a).price">{{ parts(a).price }}</em>
              </button>
            </template>
          </template>

          <!-- loads, the milk round -->
          <template v-if="tab === 'jobs'">
            <h2>Fracht <small>{{ jobs.length === 1 ? '1 Angebot' : jobs.length + ' Angebote' }}</small></h2>
            <button v-for="a in jobs" :key="a.id" class="row job" :class="{ warn: a.warn }" :disabled="a.disabled" @mouseenter="hov" @click="run(a.id)">
              <span class="r-ic">{{ a.icon }}</span><span class="r-tx"><b>{{ a.label }}</b><small>{{ parts(a).text }}</small></span><em v-if="parts(a).price">{{ parts(a).price }}</em>
            </button>
          </template>

          <!-- going on from here -->
          <template v-if="tab === 'place'">
            <h2>{{ v.place.typeName }}</h2>
            <button v-for="a in placeActs" :key="a.id" class="row" :disabled="a.disabled" @mouseenter="hov" @click="run(a.id)">
              <span class="r-ic">{{ a.icon }}</span><span class="r-tx"><b>{{ a.label }}</b><small>{{ a.sub }}</small></span><em class="go">→</em>
            </button>
          </template>

          <!-- resting -->
          <template v-if="tab === 'rest'">
            <h2>Ausruhen</h2>
            <div class="meters">
              <div v-if="v.tacho"><span>Bis zur Pause</span><b>{{ v.tacho.driveText }}</b></div>
              <div v-if="v.tacho"><span>Heute noch</span><b>{{ v.tacho.dayText }}</b></div>
              <div v-if="v.fatigue" class="fat"><span>Müdigkeit · {{ v.fatigue.text }}</span><p><i :class="{ hot: v.fatigue.pct >= 70 }" :style="{ width: v.fatigue.pct + '%' }"></i></p></div>
            </div>
            <template v-for="s in restSections" :key="s.t">
              <h3>{{ s.t }}</h3>
              <button v-for="o in s.items" :key="o.h" class="row rest" :class="{ best: o.best }" :disabled="o.disabled" @mouseenter="hov" @click="sleep(o.h)">
                <span class="r-ic">{{ o.h < 6 ? '☕' : '🛏' }}</span>
                <span class="r-tx"><b>{{ o.label }}<u v-if="o.best">Empfohlen</u></b><small>{{ o.disabled ? 'Schlafen nur an Rastplatz, Autohof, Hof oder Stützpunkt' : o.sub }}</small></span>
                <em>bis {{ o.after }}</em>
              </button>
            </template>
            <p class="note">Die Zeit läuft weiter, Lieferfristen auch.</p>
          </template>
        </section>
      </div>

      <div class="foot"><button class="back" @click="back">Weiterfahren</button></div>
    </div>
    <div class="card none" v-else-if="v && v.none">
      <div class="name">Hier gibt es nichts zu tun.</div>
      <button class="back" @click="back">Weiterfahren</button>
    </div>
    <!-- a load's page before taking it (2026-11-07) -->
    <div class="game" v-if="detail">
      <div class="gcard ofd">
        <div class="kicker">Frachtauftrag</div>
        <div class="gtitle">{{ detail.icon }} {{ detail.cargo }}</div>
        <img v-if="detail.trailerPic" class="trp" :src="detail.trailerPic" @error="e => e.target.style.display = 'none'" />
        <div class="trname">{{ detail.trailerName }}</div>
        <div class="kvs">
          <div><span>Von</span><b>{{ detail.from }}</b></div>
          <div><span>Nach</span><b>{{ detail.to }}<small v-if="detail.toCity"> · {{ detail.toCity }}</small></b></div>
          <div><span>Strecke</span><b>{{ Math.round(detail.distKm || 0) }} km</b></div>
          <div><span>Ladung</span><b>{{ detail.tons }} t</b></div>
          <div><span>Lieferfrist</span><b>{{ dur(detail.deadline) }}</b></div>
          <div><span>Lohn</span><b class="pay">{{ detail.pay }}</b></div>
        </div>
        <div class="tagsx">
          <span v-if="detail.adr" class="tg adr">ADR – Gefahrgut</span>
          <span v-if="detail.smuggle" class="tg red">Illegal: Bei Kontrolle droht Beschlagnahme</span>
          <span v-if="detail.secure" class="tg">Ladung vor der Fahrt sichern</span>
          <span v-if="detail.long" class="tg">Fernverkehr</span>
          <span v-if="detail.urgent" class="tg red">Eilig</span>
          <span v-if="detail.fragile" class="tg violet">Zerbrechlich</span>
          <span v-if="detail.expiresIn" class="tg dim">Angebot noch {{ dur(detail.expiresIn) }}</span>
        </div>
        <div class="btns">
          <button class="back ghost" @click="detail = null">Zurück</button>
          <button class="back" @click="takeDetail">Auftrag annehmen</button>
        </div>
      </div>
    </div>
    <!-- the back door's minigame (2026-11-07): the man round the corner wants to see a steady hand – stop the
         needle in the green three times, the green narrower each time and the needle faster -->
    <div class="game" v-if="game" @mousedown.left="hit">
      <div class="gcard">
        <div class="kicker">Hinter der Tankstelle</div>
        <div class="gtitle">{{ game.done ? (game.ok ? '„Passt. Komm mit.“' : '„Vergiss es.“') : '„Zeig mal, dass du kein Bulle bist …“' }}</div>
        <p class="gtext" v-if="!game.done">Klick irgendwo (oder Leertaste), wenn der Zeiger im grünen Feld steht – {{ 3 - game.hits }}× noch.</p>
        <p class="gtext" v-else>{{ game.ok ? 'Er nickt und zeigt dir, was er dabei hat.' : 'Er schaut sich um und verschwindet.' }}</p>
        <div class="bar">
          <div class="zone" :style="{ left: game.z0 + '%', width: game.zw + '%' }"></div>
          <div class="needle" :class="{ miss: game.miss }" :style="{ left: game.pos + '%' }"></div>
        </div>
        <div class="dots"><span v-for="i in 3" :key="i" :class="{ on: i <= game.hits }"></span></div>
        <button class="back" v-if="game.done" @mousedown.stop @click="endGame">{{ game.ok ? 'Zum Angebot' : 'Zurück' }}</button>
        <button class="back ghost" v-else @mousedown.stop @click="quitGame">Lieber nicht</button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from "vue"
import { call, navigate, toArray } from "./ffBridge.js"
import { sound } from "./ffSound.js"

const v = ref(null)
const actions = computed(() => toArray(v.value && v.value.actions))
const rest = computed(() => toArray(v.value && v.value.rest))

// --- the areas of a place (2026-11-08): what the place offers, sorted; one area shown at a time ---
function groupOf(a) {
  const id = a.id
  if (id === "refuel") return "fuel"
  if (id.indexOf("buy:") === 0) return a.shop && a.shop.back ? "shady" : "shop"
  if (id === "back:try") return "shady"
  if (id.indexOf("take:") === 0) return a.offer && a.offer.smuggle ? "shady" : "jobs"
  if (id === "milktour" || id === "milktour:end") return "jobs"
  if (id === "repair" || id === "diag" || id === "tank:big" || /^(fix|assist|limiter):/.test(id)) return "work"
  return "place"
}
const byGroup = computed(() => { const g = {}; actions.value.forEach(a => { const k = groupOf(a); (g[k] = g[k] || []).push(a) }); return g })
const TABS = [
  { id: "fuel", icon: "⛽", label: "Tanken", sub: "Diesel" },
  { id: "shop", icon: "🛒", label: "Shop", sub: "Kaffee, Bier, Zigaretten" },
  { id: "work", icon: "🔧", label: "Werkstatt", sub: "Reparatur, Einbauten" },
  { id: "jobs", icon: "📦", label: "Fracht", sub: "Angebote hier" },
  { id: "place", icon: "🧭", label: "Vor Ort", sub: "Weiter von hier" },
  { id: "shady", icon: "🚶", label: "Hinterhof", sub: "Unter der Hand" },
  { id: "rest", icon: "🛏", label: "Ausruhen", sub: "Pause und Schlaf" },
]
const tabs = computed(() => TABS.filter(t => t.id === "rest" || byGroup.value[t.id]))
const chosen = ref(null)
const FIRST = { refuel: "fuel", sleep: "rest", repair: "work", home: "place", freight: "jobs", dealerTruck: "place", dealerCar: "place", ferry: "place", fly: "place" }
const tab = computed(() => {
  const list = tabs.value
  if (chosen.value && list.some(t => t.id === chosen.value)) return chosen.value
  const f = v.value && v.value.place && FIRST[v.value.place.action]
  return list.some(t => t.id === f) ? f : (list[0] ? list[0].id : "rest")
})
function pick(id) { if (id !== tab.value) sound("click"); chosen.value = id }
const find = id => actions.value.find(a => a.id === id) || null
const fuelAct = computed(() => find("refuel"))
const repairAct = computed(() => find("repair"))
const backTry = computed(() => find("back:try"))
const tankPct = computed(() => { const a = fuelAct.value; return a && typeof a.ratio === "number" ? Math.round(a.ratio * 100) : null })
const inv = computed(() => (v.value && v.value.inv) || {})
const CABIN = [{ k: "coffee", i: "☕", l: "Kaffee" }, { k: "energy", i: "🥤", l: "Energy" }, { k: "beer", i: "🍺", l: "Bier" }, { k: "cigarette", i: "🚬", l: "Zigaretten" }, { k: "joint", i: "🌿", l: "Joints" }]
function section(t, list) { return list.length ? [{ t, items: list }] : [] }
const shopSections = computed(() => {
  const all = byGroup.value.shop || [], of = (...k) => all.filter(a => a.shop && k.includes(a.shop.kind))
  return [...section("Wach bleiben", of("coffee", "energy")), ...section("Bier und Zigaretten", of("beer", "cigarette"))]
})
const shadyGoods = computed(() => (byGroup.value.shady || []).filter(a => a.shop))
const shadyJobs = computed(() => (byGroup.value.shady || []).filter(a => a.offer))
const workSections = computed(() => {
  const all = (byGroup.value.work || []).filter(a => a.id !== "repair")
  return [...section("Mängel", all.filter(a => a.id === "diag" || a.id.indexOf("fix:") === 0)),
    ...section("Einbauten", all.filter(a => a.id === "tank:big" || a.id.indexOf("assist:") === 0)),
    ...section("Begrenzer", all.filter(a => a.id.indexOf("limiter:") === 0))]
})
const jobs = computed(() => byGroup.value.jobs || [])
const placeActs = computed(() => byGroup.value.place || [])
const restSections = computed(() => [...section("Kurz anhalten", rest.value.filter(o => o.h < 6)),
  ...section("Tagesruhe", rest.value.filter(o => o.h >= 6 && o.h < 20)), ...section("Wochenruhe", rest.value.filter(o => o.h >= 20))])
// "6.800 € · hält Abstand" → the price at the side, the words under the name
function parts(a) { const m = /^([^·]*€[^·]*?)\s*·\s*(.*)$/.exec(a.sub || ""); return m ? { price: m[1].trim(), text: m[2] } : { price: null, text: a.sub } }

function load() { call("uiStop", r => { v.value = r || { none: true } }) }
// a load at this company: first its page (where to, how far, the trailer), then take it (2026-11-07)
const detail = ref(null)
function dur(s) {
  if (!s && s !== 0) return "–"
  const m = Math.round(s / 60), h = Math.floor(m / 60)
  return h > 0 ? h + " h " + String(m % 60).padStart(2, "0") + " min" : m + " min"
}
function takeDetail() { const d = detail.value; detail.value = null; if (d) { sound("done"); call("stopDo", d.id) } }
function run(id) {
  if (id === "back:try") { startGame(); return }
  if (id.indexOf("take:") === 0) {
    const a = actions.value.find(x => x.id === id)
    if (a && a.offer) { sound("click"); detail.value = { id, ...a.offer }; return }
  }
  sound("click"); call("stopDo", id)
  if (id === "repair" || id.indexOf("buy:") === 0 || id === "tank:big") setTimeout(load, 300)
}

// --- the back door's minigame ---
const game = ref(null)
let raf = 0, lastT = 0
function newZone(g) {
  // (2026-11-08: the last round had a window of 90 ms and the click only counted on letting go – hardly to be hit)
  g.zw = [28, 21, 15][g.hits] || 15
  g.z0 = 8 + Math.random() * (84 - g.zw)
  g.speed = [50, 66, 84][g.hits] || 84                // (% of the bar per second)
}
function startGame() {
  sound("click")
  const g = { hits: 0, pos: 0, dir: 1, done: false, ok: false, miss: false }
  newZone(g)
  game.value = g
  lastT = performance.now()
  cancelAnimationFrame(raf)
  raf = requestAnimationFrame(tick)
}
function tick(t) {
  const g = game.value
  if (!g || g.done) return
  const dt = Math.min(0.05, (t - lastT) / 1000); lastT = t
  g.pos += g.dir * g.speed * dt
  if (g.pos >= 100) { g.pos = 100; g.dir = -1 }
  if (g.pos <= 0) { g.pos = 0; g.dir = 1 }
  raf = requestAnimationFrame(tick)
}
function hit() {
  const g = game.value
  if (!g || g.done) return
  // (judged where the needle was seen when the button went down: the game's browser shows it about 60 ms late)
  const seen = g.pos - g.dir * g.speed * 0.06
  if (seen >= g.z0 - 1 && seen <= g.z0 + g.zw + 1) {
    g.hits++
    sound("done")
    if (g.hits >= 3) { g.done = true; g.ok = true; call("stopDo", "back:result", true); setTimeout(load, 300) }
    else newZone(g)
  } else {
    g.miss = true; g.done = true; g.ok = false
    sound("back")
    call("stopDo", "back:result", false)
    setTimeout(load, 300)
  }
}
function quitGame() { cancelAnimationFrame(raf); game.value = null; sound("back") }
function endGame() { cancelAnimationFrame(raf); game.value = null }
function key(e) { if (game.value && !game.value.done && (e.code === "Space" || e.key === " ")) { e.preventDefault(); hit() } }
function sleep(h) { sound("done"); call("stopDo", "sleep", h) }
function back() { sound("back"); navigate("play") }
function hov() { sound("hover") }

let timer = null
onMounted(() => { window.ffStopPick = pick; sound("open"); call("uiStopOpen", true); load(); timer = setInterval(load, 2000); window.addEventListener("keydown", key) })
onUnmounted(() => { call("uiStopOpen", false); if (timer) clearInterval(timer); cancelAnimationFrame(raf); window.removeEventListener("keydown", key) })
</script>

<style scoped>
.ffs { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; color: #eef1f5;
  background: radial-gradient(ellipse at center, rgba(5, 8, 12, .12) 0%, rgba(5, 8, 12, .5) 100%); font-family: FFWave, 'Noto Sans', sans-serif; animation: ffsFade .25s ease-out; }
@keyframes ffsFade { from { opacity: 0; } }
@font-face { font-family: FFWave; font-weight: 500; src: url(/ui/common/LTWave/LTWave-Medium.otf); }
@font-face { font-family: FFWave; font-weight: 700; src: url(/ui/common/LTWave/LTWave-Bold.otf); }
@font-face { font-family: FFWave; font-weight: 900; src: url(/ui/common/LTWave/LTWave-Black.otf); }
.card { width: min(1040px, 94vw); background: linear-gradient(180deg, rgba(20, 25, 33, .95), rgba(11, 14, 19, .96)); border: 1px solid rgba(255, 255, 255, .11); border-radius: 18px;
  box-shadow: 0 30px 90px rgba(0, 0, 0, .6), inset 0 1px 0 rgba(255,255,255,.05); padding: 18px 20px 14px; animation: ffsIn .5s cubic-bezier(.16,1,.3,1); }
.card.none { width: auto; display: flex; gap: 18px; align-items: center; }
@keyframes ffsIn { from { transform: translateY(14px) scale(.98); opacity: 0; } to { transform: none; opacity: 1; } }
.head { display: flex; align-items: center; gap: 14px; padding-bottom: 14px; border-bottom: 1px solid #222832; }
.ring { width: 54px; height: 54px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 24px;
  border: 4px dashed currentColor; box-shadow: 0 0 18px currentColor, inset 0 0 12px currentColor; }
.ring span { filter: none; }
.ring.green { color: #3ad38b; } .ring.orange { color: #ff9a1f; } .ring.red { color: #ff5b4d; } .ring.blue { color: #4d9bff; }
.ring.violet { color: #b07bff; } .ring.yellow { color: #ffd23a; } .ring.cyan { color: #33e6f2; }
.title { flex: 1; min-width: 0; }
.kicker { font-size: 11px; letter-spacing: .16em; text-transform: uppercase; color: #f5a623; font-weight: 800; }
.name { font-size: 22px; font-weight: 900; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.stats { display: flex; gap: 8px; }
.stats > div { min-width: 74px; padding: 6px 12px; border-radius: 10px; background: rgba(255,255,255,.045); text-align: right; }
.stats span { display: block; font-size: 10.5px; font-weight: 700; letter-spacing: .04em; color: #8b95a3; white-space: nowrap; }
.stats b { display: block; font-size: 16px; font-weight: 800; white-space: nowrap; font-variant-numeric: tabular-nums; } .stats b.low { color: #ff8a7d; }
.stats .clk b { font-family: Consolas, monospace; }

.body { display: grid; grid-template-columns: 196px minmax(0, 1fr); gap: 16px; margin-top: 14px; height: min(500px, 66vh); }
.rail { display: flex; flex-direction: column; gap: 4px; overflow-y: auto; }
.rail a { display: flex; align-items: center; gap: 10px; padding: 9px 10px; border-radius: 10px; cursor: pointer; border: 1px solid transparent; transition: background .14s, border-color .14s; }
.rail a:hover { background: rgba(255,255,255,.05); }
.rail a.on { background: rgba(245,166,35,.13); border-color: rgba(245,166,35,.48); }
.rail a.shady.on { background: rgba(176,123,255,.13); border-color: rgba(176,123,255,.5); }
.rail i { flex: none; width: 32px; height: 32px; border-radius: 9px; background: rgba(255,255,255,.06); display: flex; align-items: center; justify-content: center; font-size: 16px; font-style: normal; }
.rail span { min-width: 0; } .rail b { display: block; font-size: 14px; font-weight: 800; } .rail small { display: block; font-size: 11px; color: #8b95a3; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }

.pane { min-width: 0; overflow-y: auto; padding: 2px 8px 6px 2px; animation: ffsPane .28s cubic-bezier(.16,1,.3,1); }
@keyframes ffsPane { from { opacity: 0; transform: translateY(6px); } }
.pane::-webkit-scrollbar, .rail::-webkit-scrollbar { width: 6px; } .pane::-webkit-scrollbar-thumb, .rail::-webkit-scrollbar-thumb { background: rgba(255,255,255,.14); border-radius: 3px; }
.pane h2 { margin: 0 0 10px; font-size: 19px; font-weight: 900; } .pane h2 small { margin-left: 8px; font-size: 12.5px; font-weight: 500; color: #8b95a3; }
.pane h3 { margin: 15px 0 7px; font-size: 11px; font-weight: 800; letter-spacing: .12em; text-transform: uppercase; color: #9aa4b2; }
.pane button { font: inherit; color: inherit; }
.pane button:disabled { opacity: .46; cursor: default; }

.hero { display: flex; align-items: center; gap: 16px; padding: 16px 18px; border-radius: 13px; background: linear-gradient(135deg, #202733, #171c24); border: 1px solid #2b3340; }
.hero-ic { font-size: 28px; } .hero-t { flex: 1; min-width: 0; } .hero-t b { display: block; font-size: 17px; font-weight: 800; } .hero-t small { font-size: 12.5px; color: #9aa4b2; }
.gauge { flex: 0 0 210px; height: 16px; border-radius: 8px; background: rgba(255,255,255,.08); overflow: hidden; } .gauge i { display: block; height: 100%; border-radius: 8px; background: linear-gradient(90deg, #f5a623, #ffd27a); }
.gauge.low i { background: linear-gradient(90deg, #ff5b4d, #ff9a7a); }
.cta { flex: none; border: 0; border-radius: 10px; padding: 11px 20px; background: #f5a623; color: #15100a !important; font-weight: 800 !important; cursor: pointer; transition: filter .14s, transform .1s; }
.cta:hover:not(:disabled) { filter: brightness(1.1); } .cta:active:not(:disabled) { transform: scale(.98); }

.cabin { display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: 6px; padding: 8px; border-radius: 12px; background: rgba(255,255,255,.035); }
.cabin span { display: grid; grid-template-columns: auto 1fr; align-items: center; column-gap: 7px; padding: 4px 8px; } .cabin span.none { opacity: .42; }
.cabin i { grid-row: span 2; font-size: 18px; font-style: normal; } .cabin b { font-size: 15px; font-weight: 800; line-height: 1.1; } .cabin small { font-size: 10.5px; color: #8b95a3; }
.tiles { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 9px; }
.tile { position: relative; display: flex; flex-direction: column; text-align: left; padding: 12px 13px; min-height: 124px; border-radius: 12px; cursor: pointer; background: #181e27; border: 1px solid #272f3b; transition: transform .14s cubic-bezier(.16,1,.3,1), border-color .14s, background .14s; }
.tile:hover:not(:disabled) { transform: translateY(-2px); border-color: #f5a623; background: #1e2530; }
.tile:active:not(:disabled) { transform: scale(.98); }
.tile.dark { background: #1b1727; border-color: #352c4b; } .tile.dark:hover:not(:disabled) { border-color: #b07bff; background: #221c32; }
.t-ic { font-size: 24px; line-height: 1; margin-bottom: 6px; } .tile b { font-size: 14px; font-weight: 800; } .tile small { font-size: 11.5px; color: #8b95a3; line-height: 1.3; }
.t-ft { display: flex; align-items: baseline; justify-content: space-between; margin-top: auto; padding-top: 8px; }
.t-ft em { font-style: normal; font-size: 15px; font-weight: 900; color: #ffc964; } .t-ft u { text-decoration: none; font-size: 11px; color: #8b95a3; }
.door { display: flex; align-items: center; gap: 14px; width: 100%; text-align: left; padding: 15px 16px; border-radius: 13px; cursor: pointer; background: linear-gradient(135deg, #271f3b, #171423); border: 1px solid #40345c; transition: border-color .14s, transform .14s; }
.door:hover:not(:disabled) { border-color: #b07bff; transform: translateY(-1px); } .door > span { font-size: 28px; } .door > div { flex: 1; min-width: 0; } .door b { display: block; font-size: 16px; font-weight: 800; } .door small { font-size: 12.5px; color: #a79dbd; }
.door em { font-style: normal; font-size: 13px; font-weight: 800; color: #d9b8ff; }
.row { display: flex; align-items: center; gap: 12px; width: 100%; text-align: left; padding: 10px 13px; margin-bottom: 6px; border-radius: 11px; cursor: pointer; background: #181e27; border: 1px solid #272f3b; transition: background .14s, border-color .14s, transform .08s; }
.row:hover:not(:disabled) { background: #1f2631; border-color: #f5a623; } .row:active:not(:disabled) { transform: scale(.995); }
.row.warn { border-color: rgba(255, 91, 77, .32); } .row.warn:hover:not(:disabled) { border-color: #ff5b4d; }
.r-ic { flex: none; width: 28px; text-align: center; font-size: 20px; } .r-tx { flex: 1; min-width: 0; } .r-tx b { display: block; font-size: 14px; font-weight: 800; } .r-tx small { display: block; font-size: 12px; color: #8b95a3; }
.row em { flex: none; font-style: normal; font-size: 13.5px; font-weight: 800; color: #ffc964; font-variant-numeric: tabular-nums; } .row em.go { color: #8b95a3; }
.row.rest em { font: 700 12.5px Consolas, monospace; color: #cfd6de; padding: 3px 8px; border-radius: 5px; background: #252c37; }
.row.rest.best { border-color: #2e6b47; background: linear-gradient(90deg, rgba(47,191,113,.11), #181e27 60%); } .row.rest.best:hover:not(:disabled) { border-color: #3ad38b; } .row.rest.best em { background: #1c3a28; color: #9cf2b6; }
.r-tx u { margin-left: 8px; text-decoration: none; font-size: 10.5px; font-weight: 800; padding: 1px 7px; border-radius: 20px; background: #1c3a28; color: #9cf2b6; }
.meters { display: flex; gap: 8px; } .meters > div { padding: 8px 12px; border-radius: 10px; background: rgba(255,255,255,.045); } .meters span { display: block; font-size: 11px; color: #8b95a3; } .meters b { font-size: 16px; font-weight: 800; }
.meters .fat { flex: 1; } .meters p { height: 7px; margin: 7px 0 0; border-radius: 4px; background: rgba(255,255,255,.09); overflow: hidden; } .meters p i { display: block; height: 100%; background: #3ad38b; } .meters p i.hot { background: #ff6b5e; }
.note { margin: 10px 0 0; font-size: 12px; color: #7d8794; }
.foot { display: flex; align-items: center; justify-content: flex-end; margin-top: 12px; padding-top: 11px; border-top: 1px solid #222832; }
.game { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; background: rgba(4, 6, 9, .72); z-index: 5; }
.gcard { width: min(520px, 90vw); background: #10141b; border: 1px solid #2a3240; border-radius: 14px; padding: 18px 22px; text-align: center;
  box-shadow: 0 24px 70px rgba(0, 0, 0, .6); animation: ffsIn .3s cubic-bezier(.2,.8,.2,1); }
.gtitle { font-size: 21px; font-weight: 900; margin: 4px 0 6px; }
.gtext { font-size: 13px; color: #9aa4b2; margin: 0 0 14px; }
.bar { position: relative; height: 34px; border-radius: 8px; background: #1b212b; border: 1px solid #2c3542; cursor: pointer; overflow: hidden; }
.zone { position: absolute; top: 0; bottom: 0; background: linear-gradient(#3ad38b, #1f9e62); opacity: .85; }
.needle { position: absolute; top: -2px; bottom: -2px; width: 4px; margin-left: -2px; background: #f5a623; box-shadow: 0 0 10px #f5a623; }
.needle.miss { background: #ff5b4d; box-shadow: 0 0 10px #ff5b4d; }
.dots { display: flex; justify-content: center; gap: 8px; margin: 12px 0 14px; }
.dots span { width: 12px; height: 12px; border-radius: 50%; background: #2a3240; }
.dots span.on { background: #3ad38b; box-shadow: 0 0 8px #3ad38b; }
.ofd { text-align: left; width: min(560px, 92vw); }
.trp { width: 100%; height: 190px; object-fit: cover; border-radius: 10px; background: #12161c; border: 1px solid #262d38; margin: 8px 0 4px; }
.trname { font-size: 12.5px; color: #9aa4b2; margin-bottom: 10px; }
.kvs { display: grid; grid-template-columns: 1fr 1fr; gap: 6px 18px; }
.kvs div { display: flex; flex-direction: column; } .kvs span { font-size: 10.5px; letter-spacing: .1em; text-transform: uppercase; color: #7d8794; font-weight: 800; }
.kvs b { font-size: 14.5px; } .kvs small { color: #8b95a3; font-weight: 600; } .kvs .pay { color: #7fdc8a; font-size: 17px; }
.tagsx { display: flex; flex-wrap: wrap; gap: 6px; margin: 12px 0 14px; }
.tg { font-size: 11px; font-weight: 800; padding: 3px 8px; border-radius: 4px; background: #232a34; color: #cfd6de; }
.tg.adr { background: #ff8a1f; color: #1a0f00; } .tg.red { background: #4a1d1a; color: #ffb3a8; } .tg.violet { background: #34204d; color: #d9b8ff; } .tg.dim { opacity: .7; }
.btns { display: flex; justify-content: flex-end; gap: 8px; }
.back.ghost { background: transparent; color: #9aa4b2; border: 1px solid #2c3542; }
.back { background: #f5a623; color: #15100a; border: 0; border-radius: 6px; padding: 7px 18px; font-weight: 800; cursor: pointer; font: inherit; font-weight: 800; }
</style>
