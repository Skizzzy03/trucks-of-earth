<template>
  <!-- The title screen (main menu > More > Trucks of Earth): continue a career, start a new one, delete one; the
       mode's mods. career.lua uiCareers / startCareer / newCareer / deleteCareer / ensureMods. Behind it the road at
       the time of day of the computer's clock, a truck going by; the menu works with the mouse and with ↑ ↓ Enter Esc. -->
  <div class="ffc" :class="[sky, { leaving }]" @keydown="key" tabindex="-1" ref="rootEl">
    <div class="scene" :style="{ transformOrigin: zoomOrigin }">
      <div class="sky"></div>
      <div class="sun"></div>
      <svg class="hills h1" viewBox="0 0 1600 200" preserveAspectRatio="none"><path d="M0 200 V120 Q 160 60 320 110 T 640 95 T 960 120 T 1280 80 T 1600 115 V200 Z" /></svg>
      <svg class="hills h2" viewBox="0 0 1600 200" preserveAspectRatio="none"><path d="M0 200 V140 Q 200 100 420 135 T 820 125 T 1220 140 T 1600 120 V200 Z" /></svg>
      <div class="tarmac"><div class="dash"></div></div>
      <svg class="truck" viewBox="0 0 300 90">
        <rect x="6" y="14" width="196" height="56" rx="2" fill="#e9edf2" /><rect x="6" y="56" width="196" height="6" fill="#f5a623" />
        <path d="M206 30 L250 30 Q262 30 266 42 L272 60 L272 70 L206 70 Z" fill="#1d3a6e" />
        <path d="M232 36 L252 36 Q258 36 261 44 L264 52 L232 52 Z" fill="#9cc3e6" />
        <g fill="#1b1f25"><circle cx="40" cy="74" r="10" /><circle cx="64" cy="74" r="10" /><circle cx="88" cy="74" r="10" /><circle cx="222" cy="74" r="10" /><circle cx="256" cy="74" r="10" /></g>
        <circle cx="270" cy="62" r="3" fill="#ffe7a0" class="lamp" />
      </svg>
      <div class="shade"></div>
    </div>

    <div class="left">
      <div class="brand">
        <svg class="emblem" viewBox="0 0 64 64">
          <circle cx="32" cy="32" r="30" fill="#f5a623" />
          <path d="M14 40 V26 Q14 22 18 22 H36 V40 Z M38 28 H46 L51 34 V40 H38 Z" fill="#15100a" />
          <circle cx="22" cy="42" r="4" fill="#15100a" /><circle cx="44" cy="42" r="4" fill="#15100a" />
        </svg>
        <div class="logo">TRUCKS<span>OF EARTH</span></div>
      </div>
      <div class="tag">Deine Spedition auf echten Straßen – BeamNG.drive × BeamNG.Earth</div>
      <div class="menu">
        <a v-for="(m, i) in menu" :key="m.id" class="item" :class="{ primary: m.primary, busy: busy && m.busy, sel: sel === i }"
           @mouseenter="hover(i)" @click="pick(i)">
          <b>{{ m.label }}</b><small>{{ m.sub }}</small>
        </a>
      </div>
      <div v-if="data && !data.earth" class="err">BeamNG.Earth ist nicht installiert – der Spielmodus braucht die Mod.</div>
      <div class="keys"><span>↑ ↓</span> wählen <span>Enter</span> bestätigen <span>Esc</span> zurück</div>
    </div>

    <div class="right">
      <template v-if="!showMods">
        <h3>Karrieren</h3>
        <div v-if="!careers.length" class="empty">Noch keine Karriere – starte mit „Neue Karriere“.</div>
        <div v-for="c in careers" :key="c.id" class="career" :class="{ busy }" @mouseenter="sound('hover')" @click="start(c)">
          <div class="mark">{{ initials(c.company) }}</div>
          <div class="main">
            <b>{{ c.company || "Noch nicht gegründet" }}</b>
            <small>{{ c.home ? c.home + " · " : "" }}Level {{ c.level || 1 }} · {{ c.jobs || 0 }} Lieferungen · {{ Math.round(c.km || 0) }} km</small>
            <small v-if="c.job" class="job">🚛 {{ c.job.cargo }}{{ c.job.to ? " nach " + c.job.to : "" }}</small>
            <small>{{ gameDay(c) }}Zuletzt gespielt {{ when(c.lastPlayed) }}</small>
          </div>
          <div class="money">{{ money(c.money || 0) }}</div>
          <button class="del" :class="{ sure: confirm === c.id }" @click.stop="del(c)">{{ confirm === c.id ? "Wirklich löschen?" : "Löschen" }}</button>
        </div>
      </template>
      <template v-else>
        <h3>Mods für den Spielmodus</h3>
        <div class="muted" v-if="switched.length">Gerade eingeschaltet: {{ switched.join(", ") }}</div>
        <div v-for="m in mods" :key="m.id" class="mod" :class="{ off: !m.installed }">
          <span class="st" :class="{ on: m.active }"></span><b>{{ m.name }}</b><span>{{ m.why }}{{ m.installed ? "" : " · nicht installiert" }}</span>
          <button v-if="m.optional && m.installed" class="del opt" :class="{ sure: m.on }" @click="toggleOpt(m)">{{ m.on ? "An" : "Aus" }}</button>
        </div>
      </template>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, nextTick } from "vue"
import { call, navigate, money, toArray } from "./ffBridge.js"
import { sound } from "./ffSound.js"
import { showCurtain, hideCurtain } from "./ffCurtain.js"

const rootEl = ref(null)
const data = ref(null)
const busy = ref(false)
const confirm = ref(null)
const showMods = ref(false)
const switched = ref([])
const sel = ref(0)
const careers = computed(() => toArray(data.value && data.value.careers))
const mods = computed(() => toArray(data.value && data.value.mods))
const installedMods = computed(() => mods.value.filter(m => m.installed).length)
const activeMods = computed(() => mods.value.filter(m => m.active).length)
// (the sky: the computer's time of day)
const sky = computed(() => { const h = new Date().getHours(); return h >= 21 || h < 6 ? "night" : h < 8 || h >= 19 ? "dusk" : "day" })

const menu = computed(() => {
  const list = []
  const c = careers.value[0]
  if (c) list.push({ id: "continue", primary: true, busy: true, label: "Weiterspielen", sub: (c.company || "Karriere") + " · " + when(c.lastPlayed) })
  list.push({ id: "new", busy: true, label: "Neue Karriere", sub: "Hof wählen, Firma gründen" })
  list.push({ id: "mods", label: showMods.value ? "Karrieren" : "Mods", sub: showMods.value ? "zurück zur Liste" : activeMods.value + " von " + installedMods.value + " aktiv" })
  list.push({ id: "back", label: "Zurück", sub: "zum Hauptmenü" })
  return list
})

function refresh() { call("uiCareers", r => { data.value = r }) }
function when(t) {
  if (!t) return "–"
  const d = new Date(t * 1000)
  return d.toLocaleDateString("de-DE") + " " + String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0")
}
const DAYS = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]
function gameDay(c) {
  if (c.clock === undefined || c.clock === null) return ""
  const h = Math.floor(c.clock) % 24, m = Math.floor((c.clock % 1) * 60)
  return DAYS[((c.day || 1) - 1) % 7] + " " + String(h).padStart(2, "0") + ":" + String(m).padStart(2, "0") + " im Spiel · "
}
const initials = n => (n || "–").split(/\s+/).filter(Boolean).slice(0, 2).map(w => w[0].toUpperCase()).join("")
// "Weiterspielen": the menu wipes away to the left, the scene zooms onto the truck, then the loading curtain takes
// over with the same road (ffCurtain.js) – over BeamNG's own loading screen too – until the world is ready
const leaving = ref(false)
const zoomOrigin = ref("50% 70%")
function start(c) {
  if (busy.value) return
  busy.value = true
  sound("done")
  const truck = rootEl.value && rootEl.value.querySelector(".truck")
  if (truck && rootEl.value) {
    const b = truck.getBoundingClientRect(), r = rootEl.value.getBoundingClientRect()
    const x = Math.max(10, Math.min(90, ((b.left + b.width / 2 - r.left) / r.width) * 100))
    const y = Math.max(10, Math.min(95, ((b.top + b.height / 2 - r.top) / r.height) * 100))
    zoomOrigin.value = x + "% " + y + "%"
  }
  leaving.value = true
  setTimeout(() => {
    showCurtain({ sky: sky.value, title: c.company || "Weiterfahrt", sub: c.job ? "Auftrag läuft · " + c.job.cargo + (c.job.to ? " nach " + c.job.to : "") : (c.home ? "Hof " + c.home : "") })
    call("startCareer", c.id, r => { if (!r || !r.ok) { busy.value = false; leaving.value = false; hideCurtain() } })
  }, 1050)
}
function create() {
  if (busy.value) return
  busy.value = true
  sound("done")
  call("newCareer", r => { if (!r || !r.ok) busy.value = false })
}
function del(c) {
  sound("click")
  if (confirm.value !== c.id) { confirm.value = c.id; return }
  confirm.value = null
  call("deleteCareer", c.id, () => refresh())
}
function back() { sound("back"); navigate("menu") }
function toggleOpt(m) { sound("click"); call("setModOption", m.key, !m.on, r => { switched.value = toArray(r && r.switched); refresh() }) }

function hover(i) { if (sel.value !== i) { sel.value = i; sound("hover") } }
function pick(i) {
  const m = menu.value[i]
  if (!m) return
  if (m.id === "continue") start(careers.value[0])
  else if (m.id === "new") create()
  else if (m.id === "mods") { sound("click"); showMods.value = !showMods.value }
  else if (m.id === "back") back()
}
function key(e) {
  const n = menu.value.length
  if (e.key === "ArrowDown") { sel.value = (sel.value + 1) % n; sound("hover"); e.preventDefault() }
  else if (e.key === "ArrowUp") { sel.value = (sel.value + n - 1) % n; sound("hover"); e.preventDefault() }
  else if (e.key === "Enter") { pick(sel.value); e.preventDefault() }
  else if (e.key === "Escape") { if (showMods.value) { showMods.value = false; sound("back") } else back() }
}

onMounted(() => {
  sound("open")
  call("ensureMods", r => { switched.value = toArray(r && r.switched); refresh() })
  nextTick(() => rootEl.value && rootEl.value.focus())
})
</script>

<style scoped>
.ffc { position: absolute; inset: 0; display: flex; color: #e9edf2; font-family: inherit; outline: none; overflow: hidden; background: #0b1622; }
/* the scene behind */
.scene { position: absolute; inset: 0; z-index: 0; }
.sky { position: absolute; inset: 0 0 26% 0; background: linear-gradient(180deg, #5d9fd6 0%, #a9d1ee 60%, #e6f1f8 100%); }
.dusk .sky { background: linear-gradient(180deg, #2b3c6b 0%, #c4677a 58%, #f4b26b 100%); }
.night .sky { background: linear-gradient(180deg, #050b18 0%, #13284a 60%, #2b4a72 100%); }
.sun { position: absolute; right: 18%; top: 14%; width: 110px; height: 110px; border-radius: 50%; background: radial-gradient(circle, #fff6d5 0%, #ffd77a 55%, rgba(255,215,122,0) 72%); }
.dusk .sun { top: 46%; background: radial-gradient(circle, #ffe2b0 0%, #ff9d4d 55%, rgba(255,157,77,0) 72%); }
.night .sun { width: 70px; height: 70px; background: radial-gradient(circle, #f4f6ff 0%, #c9d3ef 50%, rgba(201,211,239,0) 70%); }
.hills { position: absolute; left: 0; width: 100%; }
.hills.h1 { bottom: 26%; height: 22%; fill: #5f8a74; } .hills.h2 { bottom: 25%; height: 16%; fill: #4b7a50; }
.dusk .hills.h1 { fill: #4a4f6d; } .dusk .hills.h2 { fill: #3a4a45; }
.night .hills.h1 { fill: #18223a; } .night .hills.h2 { fill: #142318; }
.tarmac { position: absolute; left: 0; right: 0; bottom: 0; height: 26%; background: #3a3f46; overflow: hidden; }
.night .tarmac { background: #17191d; }
.dash { position: absolute; left: 0; width: 200%; top: 44%; height: 6px; background: repeating-linear-gradient(90deg, #e9edf2 0 70px, transparent 70px 160px); animation: ffcDash 1.4s linear infinite; opacity: .85; will-change: transform; }
@keyframes ffcDash { to { transform: translateX(-160px); } }
.truck { position: absolute; bottom: 21%; width: 26vw; max-width: 380px; left: 0; animation: ffcDrive 26s linear infinite; will-change: transform; }
@keyframes ffcDrive { 0% { transform: translateX(-30vw); } 100% { transform: translateX(105vw); } }
.truck .lamp { opacity: 0; } .night .truck .lamp, .dusk .truck .lamp { opacity: 1; filter: drop-shadow(0 0 6px #ffe7a0); }
.shade { position: absolute; inset: 0; background: linear-gradient(90deg, rgba(8,10,13,.96) 0%, rgba(8,10,13,.86) 40%, rgba(8,10,13,.45) 75%, rgba(8,10,13,.3) 100%); }
/* the menu */
.left, .right { position: relative; z-index: 1; }
.left { width: 44%; max-width: 640px; padding: 9vh 5vw 5vh; display: flex; flex-direction: column; animation: ffcIn .6s ease-out; }
@keyframes ffcIn { from { opacity: 0; transform: translateX(-20px); } to { opacity: 1; transform: none; } }
.brand { display: flex; align-items: center; gap: 18px; }
.emblem { width: 76px; height: 76px; flex: none; filter: drop-shadow(0 6px 18px rgba(245,166,35,.35)); }
.logo { font-size: 52px; font-weight: 900; letter-spacing: .04em; line-height: .95; }
.logo span { display: block; color: #f5a623; font-size: 30px; letter-spacing: .32em; margin-top: 8px; }
.tag { margin-top: 16px; color: #8b95a3; font-size: 14px; }
.menu { margin-top: 6vh; display: flex; flex-direction: column; gap: 6px; max-width: 420px; }
.item { display: block; padding: 13px 18px; border-left: 3px solid transparent; background: rgba(255,255,255,.04); cursor: pointer; transition: background .12s, border-color .12s, transform .12s; }
.item.sel { background: rgba(255,255,255,.09); border-left-color: #f5a623; transform: translateX(4px); }
.item.primary { background: #f5a623; color: #15100a; } .item.primary small { color: #3b2a0c; }
.item.primary.sel { filter: brightness(1.08); border-left-color: #fff; }
.item b { display: block; font-size: 17px; letter-spacing: .02em; } .item small { display: block; font-size: 12px; color: #8b95a3; margin-top: 2px; }
.item.busy, .career.busy { opacity: .5; pointer-events: none; }
.err { margin-top: 18px; color: #ff8a80; font-size: 13px; }
.keys { margin-top: auto; padding-top: 20px; font-size: 11.5px; color: #6f7a88; }
.keys span { display: inline-block; background: #1a1f27; border: 1px solid #2a313b; border-radius: 3px; padding: 0 6px; margin: 0 4px 0 10px; color: #cfd6de; font-weight: 700; }
.keys span:first-child { margin-left: 0; }
.right { flex: 1; padding: 9vh 5vw 6vh 2vw; overflow-y: auto; animation: ffcIn2 .7s ease-out; }
@keyframes ffcIn2 { from { opacity: 0; transform: translateY(14px); } to { opacity: 1; transform: none; } }
h3 { margin: 0 0 14px; font-size: 11px; letter-spacing: .16em; text-transform: uppercase; color: #cfd6de; }
.empty, .muted { color: #8b95a3; font-size: 13px; margin-bottom: 10px; }
.career { display: flex; align-items: center; gap: 14px; padding: 14px 16px; margin-bottom: 8px; background: rgba(18,22,28,.9); border: 1px solid #222832; border-radius: 6px; cursor: pointer; transition: border-color .12s, transform .12s; }
.career:hover { border-color: #f5a623; transform: translateX(-3px); }
.mark { width: 42px; height: 42px; flex: none; border-radius: 6px; background: #1f252e; color: #f5a623; font-weight: 900; display: flex; align-items: center; justify-content: center; }
.main { flex: 1; min-width: 0; } .main b { display: block; font-size: 15px; } .main small { display: block; font-size: 12px; color: #8b95a3; margin-top: 2px; }
.main small.job { color: #cfd6de; }
.money { font-weight: 800; color: #2fbf71; white-space: nowrap; }
.del { background: transparent; border: 1px solid #2f3742; color: #8b95a3; border-radius: 4px; padding: 5px 10px; cursor: pointer; font-size: 12px; }
.del:hover, .del.sure { border-color: #d9483b; color: #ff8a80; }
.mod { display: flex; gap: 10px; align-items: baseline; padding: 7px 0; border-bottom: 1px solid #1d232c; font-size: 13px; }
.mod .st { width: 8px; height: 8px; border-radius: 50%; background: #5b6470; flex: none; } .mod .st.on { background: #2fbf71; }
.mod span:nth-of-type(2) { color: #8b95a3; flex: 1; } .mod.off { opacity: .5; }
.del.opt { margin-left: auto; flex: none; } .del.opt.sure { border-color: #2fbf71; color: #a6efc0; }
/* "Weiterspielen": everything wipes to the left, the scene zooms onto the truck (it stops where it is) */
.left, .right { transition: transform .75s cubic-bezier(.6, 0, .3, 1), opacity .6s ease; }
.leaving .left { transform: translateX(-110vw); opacity: 0; }
.leaving .right { transform: translateX(-110vw); opacity: 0; transition-delay: .08s; }
.scene { transition: transform 1.1s cubic-bezier(.5, 0, .2, 1); }
.leaving .scene { transform: scale(1.7); }
.shade { transition: opacity .7s ease; }
.leaving .shade { opacity: 0; }
.leaving .truck { animation-play-state: paused; }
.leaving .dash { animation-duration: .8s; }
</style>
