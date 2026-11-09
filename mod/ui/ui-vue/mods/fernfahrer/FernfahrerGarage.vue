<template>
  <!-- The workshop for the cab (career.lua uiGarage, accessories.lua): the driver's view stays free on the left, what is fitted appears in the cab at once. -->
  <div class="ffg">
    <aside class="panel">
      <header>
        <div class="eyebrow">Eigene Werkstatt</div>
        <h1>Kabine einrichten</h1>
        <p v-if="data && data.truck">{{ data.truck }}</p>
        <p v-if="data && data.loaner" class="ln">Im Leih-Lkw kannst du Dinge aufhängen. Alles andere geht erst im eigenen Lkw.</p>
      </header>
      <div v-if="data && data.error" class="note">{{ data.error }}</div>
      <template v-else-if="data">
        <nav class="tabs"><a v-for="c in cats" :key="c.key" :class="{ on: cat === c.key }" @click="cat = c.key">{{ c.name }}</a></nav>
        <div class="list">
          <article v-for="it in shown" :key="it.id" :class="{ on: sel === it.id, off: it.locked || (!it.fitted && !it.stock) }" @click="sel = it.id">
            <img :src="it.thumb" @error="e => e.target.style.visibility = 'hidden'" />
            <div class="tx"><b>{{ it.name }}</b><span>{{ it.locked ? 'Nur im eigenen Lkw' : it.fitted ? 'Eingebaut' : it.stock ? it.stock + ' im Regal' : 'Im Online-Shop bestellen' }}</span></div>
            <button v-if="it.fitted" class="ghost" @click.stop="act('garageRemove', it.id)">Raus</button>
            <button v-else-if="it.stock && !it.locked" @click.stop="act('garageFit', it.id)">Einbauen</button>
          </article>
        </div>
        <section v-if="cur && cur.fitted" class="adj">
          <h2>{{ cur.name }} einstellen</h2>
          <div class="steps"><span>Ansicht</span><a v-for="v in VIEWS" :key="v.k" :class="{ on: view === v.k }" @click="setView(v.k)">{{ v.l }}</a></div>
          <div class="steps"><span>Schritt</span><a v-for="s in STEPS" :key="s" :class="{ on: step === s }" @click="step = s">{{ String(s * 100).replace('.', ',') }} cm</a></div>
          <div v-for="a in axes" :key="a.k" class="row">
            <span>{{ a.l }}</span>
            <button @pointerdown="hold(a.k, -1)" @pointerup="release" @pointerleave="release">{{ a.m }}</button>
            <em>{{ shownAdj(a.k) }}</em>
            <button @pointerdown="hold(a.k, 1)" @pointerup="release" @pointerleave="release">{{ a.p }}</button>
          </div>
          <button v-if="!cur.hung" class="align" @click="act('garageFace', cur.id)">Zum Fahrer drehen</button>
          <button v-if="cur.dash" class="align" @click="act('garageAlign', cur.id)">Höhe und Tiefe für alles auf dem Armaturenbrett übernehmen</button>
        </section>
        <section v-if="cur && cur.fitted && cur.pic" class="adj pics">
          <h2>Foto auswählen</h2>
          <div class="pg"><img v-for="f in photos" :key="f" :src="f" loading="lazy" :class="{ on: cur.photo === f }" @click="choose(f)" /></div>
          <p v-if="!photos.length">Noch keine Fotos in der BeamNG-Galerie. Mach an einem Aussichtspunkt eins.</p>
        </section>
      </template>
      <footer><button class="done" @click="leave">Fertig</button></footer>
    </aside>
  </div>
</template>

<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from "vue"
import { call, navigate, toArray } from "./ffBridge.js"
const STEPS = [0.005, 0.01, 0.05]
const VIEWS = [{ k: "fahrer", l: "Fahrersitz" }, { k: "seite", l: "Seite" }, { k: "oben", l: "Oben" }]
const view = ref("fahrer")
function setView(v) { view.value = v; call("garageView", v) }
const step = ref(0.01)
const AXES = [{ k: "f", l: "Vor / zurück", m: "◀", p: "▶" }, { k: "r", l: "Links / rechts", m: "◀", p: "▶" }, { k: "u", l: "Höhe", m: "▼", p: "▲" }]
const THREAD = { k: "l", l: "Fadenlänge", m: "−", p: "+" }, TURN = { k: "y", l: "Drehen", m: "↺", p: "↻" }
const TURN_STEP = { 0.005: 2, 0.01: 5, 0.05: 15 }
const data = ref(null), cat = ref("hang"), sel = ref(null)
const cats = computed(() => toArray(data.value && data.value.cats))
const items = computed(() => toArray(data.value && data.value.items))
const shown = computed(() => items.value.filter(i => i.cat === cat.value).sort((a, b) => (b.fitted ? 2 : b.stock ? 1 : 0) - (a.fitted ? 2 : a.stock ? 1 : 0)))
const cur = computed(() => items.value.find(i => i.id === sel.value))
const axes = computed(() => cur.value && cur.value.hung ? [...AXES, THREAD, TURN] : [...AXES, TURN])
function shownAdj(k) {
  const x = (cur.value && cur.value.adj && cur.value.adj[k]) || 0
  if (k === "y") return x + " °"
  return (x > 0 ? "+" : "") + (x * 100).toFixed(1).replace(".", ",") + " cm"
}
watch(sel, id => call("garageSelect", id || ""))
function load() { call("uiGarage", r => { data.value = r || {} }) }
function act(fn, id) { sel.value = id; call(fn, id, r => { data.value = r || data.value }) }
function nudge(axis, d) { call("garageNudge", sel.value, axis, d, r => { data.value = r || data.value }) }
let holdT = 0, holdN = 0
function release() { clearTimeout(holdT); holdT = 0 }
function hold(axis, sign) { release(); holdN = 0; (function go() { nudge(axis, sign * (axis === "y" ? TURN_STEP[step.value] : step.value)); holdN++; holdT = setTimeout(go, holdN === 1 ? 380 : 90) })() }
const photos = ref([])
watch(() => cur.value && cur.value.pic && cur.value.id, on => { if (on) call("garagePhotos", r => { photos.value = toArray(r) }) })
function choose(f) { call("garagePhoto", f, r => { data.value = r || data.value }) }
function leave() { navigate("play") }
onMounted(() => { call("garageOpen", () => load()) })
onUnmounted(() => { release(); call("garageClose") })
</script>

<style scoped>
.ffg { position: absolute; inset: 0; display: flex; justify-content: flex-start; color: #eef1f5; font-family: "Noto Sans", sans-serif; pointer-events: none; }
.panel { pointer-events: auto; width: 410px; height: 100%; box-sizing: border-box; display: flex; flex-direction: column; background: rgba(13, 17, 23, .93); border-right: 3px solid #ffb12e; }
header { padding: 18px 20px 10px; } .eyebrow { font-size: 11px; font-weight: 800; letter-spacing: .16em; text-transform: uppercase; color: #ffb12e; }
h1 { margin: 2px 0 0; font-size: 24px; } header p { margin: 2px 0 0; color: #aeb7c3; font-size: 13px; } header p.ln { margin-top: 6px; color: #ffc964; }
.note { margin: 12px 20px; padding: 12px; background: #2a1a12; border-radius: 6px; font-size: 14px; }
.steps { display: flex; align-items: center; gap: 6px; margin-bottom: 6px; font-size: 12.5px; color: #8b95a3; } .steps span { flex: 1; } .steps a { padding: 4px 9px; border-radius: 5px; background: #2a313b; color: #dbe2ea; font-weight: 800; cursor: pointer; } .steps a.on { background: #ffb12e; color: #1a1205; } .align { width: 100%; margin-top: 9px; background: #2a313b; color: #fff; }
.tabs { display: flex; flex-wrap: wrap; gap: 4px; padding: 0 20px 10px; } .tabs a { flex: 1 1 28%; text-align: center; padding: 7px 4px; font-size: 12.5px; font-weight: 700; border-radius: 5px; background: #1a2029; color: #aeb7c3; cursor: pointer; } .tabs a.on { background: #ffb12e; color: #1a1205; }
.list { flex: 1; min-height: 0; overflow-y: auto; padding: 0 20px; display: flex; flex-direction: column; gap: 6px; }
article { display: flex; align-items: center; gap: 10px; padding: 6px; border-radius: 7px; background: #161b22; border: 1px solid #252c36; cursor: pointer; } article:hover { border-color: #4d5a6b; } article.on { border-color: #ffb12e; } article.off { opacity: .55; }
article img { flex: none; width: 58px; height: 58px; border-radius: 5px; object-fit: cover; background: #232a34; } .tx { flex: 1; min-width: 0; display: flex; flex-direction: column; } .tx b { font-size: 14px; } .tx span { font-size: 12px; color: #8b95a3; }
button { border: 0; padding: 7px 12px; font: inherit; font-size: 12.5px; font-weight: 800; border-radius: 5px; background: #ffb12e; color: #1a1205; cursor: pointer; } button:hover { background: #ffc65c; } button.ghost { background: #2a313b; color: #dbe2ea; }
.adj { padding: 12px 20px; border-top: 1px solid #252c36; } .adj h2 { margin: 0 0 8px; font-size: 14px; } .row { display: grid; grid-template-columns: 1fr 34px 66px 34px; align-items: center; gap: 6px; margin-top: 5px; font-size: 13px; color: #c9d3de; } .row button { padding: 5px 0; background: #2a313b; color: #fff; } .row button:hover { background: #3a4554; } .row em { text-align: center; font-style: normal; font-weight: 700; }
.pg { display: grid; grid-template-columns: repeat(4, 1fr); gap: 5px; max-height: 150px; overflow-y: auto; } .pg img { width: 100%; aspect-ratio: 16 / 9; object-fit: cover; border-radius: 4px; border: 2px solid transparent; cursor: pointer; background: #232a34; } .pg img.on { border-color: #ffb12e; } .pics p { margin: 0; font-size: 12.5px; color: #8b95a3; }
footer { padding: 12px 20px 18px; } .done { width: 100%; padding: 12px 0; font-size: 15px; }
</style>
