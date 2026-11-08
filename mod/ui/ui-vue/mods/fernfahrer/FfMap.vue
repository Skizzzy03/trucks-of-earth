<template>
  <!-- A small slippy map on BeamNG.Earth's map tiles (files its server writes to /temp/beamngEarth/maptiles/,
       asked for through beamngEarth_settings.mapTiles: the game's UI browser blocks http). Drag to pan, wheel to
       zoom, click to pick a spot (emits "pick"). -->
  <div ref="root" class="ff-map" @mousedown="down" @wheel.prevent="wheel">
    <img v-for="t in tiles" :key="t.key" class="tile" :class="{ overlay: t.overlay }" :src="t.src"
         :style="{ left: t.left + 'px', top: t.top + 'px' }" draggable="false" @error="e => e.target.style.visibility = 'hidden'" />
    <div v-for="(m, i) in placed" :key="'m' + i" class="marker" :class="m.kind"
         :style="{ left: m.x + 'px', top: m.y + 'px' }" :title="m.label">
      <span v-if="m.icon" class="ic">{{ m.icon }}</span>
    </div>
    <div v-if="!tilesOk" class="notice">Kartenbilder nicht verfügbar – läuft der BeamNG.Earth-Server? Suche und Klick funktionieren trotzdem.</div>
    <div class="zoom">
      <button @mousedown.stop @click.stop="zoomBy(1)">+</button>
      <button @mousedown.stop @click.stop="zoomBy(-1)">−</button>
    </div>
    <div class="credits">Karte: EOX / OpenStreetMap-Mitwirkende (über BeamNG.Earth)</div>
  </div>
</template>

<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from "vue"
import { engineLua } from "./ffBridge.js"

const props = defineProps({
  center: { type: Object, default: () => ({ lat: 51.16, lon: 10.45 }) },
  zoom: { type: Number, default: 6 },
  markers: { type: Array, default: () => [] },
  labels: { type: Boolean, default: true },
})
const emit = defineEmits(["pick", "view"])

const TILE = 256
const DIR = "/temp/beamngEarth/maptiles/"
const root = ref(null)
const w = ref(800), h = ref(600)
const view = ref({ lat: props.center.lat, lon: props.center.lon, z: props.zoom })
const ready = ref(new Set())
const tilesOk = ref(true)

function project(lat, lon, z) {
  const s = TILE * Math.pow(2, z)
  const phi = Math.max(-85.05, Math.min(85.05, lat)) * Math.PI / 180
  return { x: (lon + 180) / 360 * s, y: (1 - Math.log(Math.tan(phi) + 1 / Math.cos(phi)) / Math.PI) / 2 * s }
}
function unproject(x, y, z) {
  const s = TILE * Math.pow(2, z)
  const n = Math.PI - 2 * Math.PI * y / s
  return { lat: 180 / Math.PI * Math.atan(Math.sinh(n)), lon: ((x / s * 360 - 180) + 540) % 360 - 180 }
}
function toScreen(lat, lon) {
  const v = view.value
  const p = project(lat, lon, v.z), c = project(v.lat, v.lon, v.z)
  return { x: w.value / 2 + p.x - c.x, y: h.value / 2 + p.y - c.y }
}
function fromScreen(sx, sy) {
  const v = view.value
  const c = project(v.lat, v.lon, v.z)
  return unproject(c.x + sx - w.value / 2, c.y + sy - h.value / 2, v.z)
}

const wanted = computed(() => {
  const v = view.value
  const c = project(v.lat, v.lon, v.z)
  const left = c.x - w.value / 2, top = c.y - h.value / 2
  const n = 1 << v.z
  const out = []
  for (let ty = Math.floor(top / TILE); ty <= Math.floor((top + h.value) / TILE); ty++) {
    if (ty < 0 || ty >= n) continue
    for (let tx = Math.floor(left / TILE); tx <= Math.floor((left + w.value) / TILE); tx++) {
      out.push({ z: v.z, x: ((tx % n) + n) % n, y: ty, left: tx * TILE - left, top: ty * TILE - top })
    }
  }
  return out
})
const layers = computed(() => (props.labels ? ["map", "labels"] : ["map"]))
const tiles = computed(() => {
  const out = []
  for (const L of layers.value) {
    for (const t of wanted.value) {
      const k = `${L}/${t.z}/${t.x}/${t.y}`
      if (!ready.value.has(k)) continue
      out.push({ key: k + "@" + t.left, overlay: L === "labels", left: t.left, top: t.top,
                 src: `${DIR}${L}/${t.z}/${t.x}/${t.y}.${L === "labels" ? "png" : "jpg"}` })
    }
  }
  return out
})

let askTimer = null
function ask() {
  const missing = []
  for (const L of layers.value) for (const t of wanted.value) {
    if (!ready.value.has(`${L}/${t.z}/${t.x}/${t.y}`)) missing.push([t.z, t.x, t.y, L])
  }
  askTimer = setTimeout(ask, missing.length ? 300 : 1200)
  if (!missing.length) return
  const list = JSON.stringify(missing.slice(0, 96))
  engineLua(`beamngEarth_settings and beamngEarth_settings.mapTiles and beamngEarth_settings.mapTiles(jsonDecode('${list}')) or false`, r => {
    if (r === false) { tilesOk.value = false; return }
    const arr = Array.isArray(r) ? r : r && typeof r === "object" ? Object.values(r) : []
    if (!arr.length) return
    const next = new Set(ready.value)
    for (const k of arr) next.add(k)
    ready.value = next
    tilesOk.value = true
  })
}

// (thinned out: one marker per 26 px cell – thousands of places at a country's zoom; the special ones always)
const placed = computed(() => {
  const seen = new Set(), out = []
  for (const m of props.markers) {
    if (!m || !isFinite(m.lat) || !isFinite(m.lon)) continue
    const s = toScreen(m.lat, m.lon)
    if (s.x < -30 || s.y < -30 || s.x > w.value + 30 || s.y > h.value + 30) continue
    if (m.kind === "depot") {
      const cell = Math.floor(s.x / 26) + ":" + Math.floor(s.y / 26)
      if (seen.has(cell)) continue
      seen.add(cell)
    }
    out.push({ ...m, ...s })
  }
  return out
})

// drag / click
let drag = null
function down(e) {
  if (e.button !== 0) return
  drag = { x: e.clientX, y: e.clientY, moved: 0, start: { ...view.value } }
  window.addEventListener("mousemove", move)
  window.addEventListener("mouseup", up)
}
function move(e) {
  if (!drag) return
  const dx = e.clientX - drag.x, dy = e.clientY - drag.y
  drag.moved = Math.max(drag.moved, Math.abs(dx) + Math.abs(dy))
  const c = project(drag.start.lat, drag.start.lon, drag.start.z)
  const p = unproject(c.x - dx, c.y - dy, drag.start.z)
  view.value = { lat: p.lat, lon: p.lon, z: drag.start.z }
}
function up(e) {
  window.removeEventListener("mousemove", move)
  window.removeEventListener("mouseup", up)
  if (drag && drag.moved < 5 && e && e.clientX !== undefined) {
    const r = root.value.getBoundingClientRect()
    emit("pick", fromScreen(e.clientX - r.left, e.clientY - r.top))
  }
  drag = null
}
function zoomAt(dz, sx, sy) {
  const v = view.value
  const z = Math.max(3, Math.min(17, v.z + dz))
  if (z === v.z) return
  const at = fromScreen(sx, sy)
  const p = project(at.lat, at.lon, z)
  const c = unproject(p.x - (sx - w.value / 2), p.y - (sy - h.value / 2), z)
  view.value = { lat: c.lat, lon: c.lon, z }
}
function wheel(e) {
  const r = root.value.getBoundingClientRect()
  zoomAt(e.deltaY < 0 ? 1 : -1, e.clientX - r.left, e.clientY - r.top)
}
function zoomBy(dz) { zoomAt(dz, w.value / 2, h.value / 2) }

// the parent moves the view (a search hit, the player)
function flyTo(lat, lon, z) { view.value = { lat, lon, z: z || view.value.z } }
defineExpose({ flyTo })
watch(view, v => emit("view", v))

function measure() {
  if (!root.value) return
  const r = root.value.getBoundingClientRect()
  w.value = Math.max(100, r.width)
  h.value = Math.max(100, r.height)
}
let ro = null
onMounted(() => {
  measure()
  if (window.ResizeObserver) { ro = new ResizeObserver(measure); ro.observe(root.value) }
  ask()
})
onUnmounted(() => { clearTimeout(askTimer); if (ro) ro.disconnect(); up() })
</script>

<style scoped>
.ff-map { position: relative; overflow: hidden; background: #c9d3cf; cursor: grab; user-select: none; }
.ff-map:active { cursor: grabbing; }
.tile { position: absolute; width: 256px; height: 256px; pointer-events: none; }
.tile.overlay { z-index: 1; }
.marker { position: absolute; z-index: 2; transform: translate(-50%, -50%); pointer-events: auto;
  width: 14px; height: 14px; border-radius: 50%; background: #5fb4ff; border: 2px solid #fff; box-shadow: 0 1px 4px rgba(0,0,0,.5); }
.marker .ic { position: absolute; left: 50%; top: -20px; transform: translateX(-50%); font-size: 15px; text-shadow: 0 1px 3px #000; }
.marker.home { width: 22px; height: 22px; background: #ffb12e; border-width: 3px; z-index: 4; }
.marker.player { width: 16px; height: 16px; background: #4fd18b; z-index: 3; }
.marker.pickup { background: #ffb12e; } .marker.delivery { background: #ff6b5e; }
.marker.depot { width: 10px; height: 10px; background: #2c3e50; border-width: 1.5px; }
.marker.depot .ic { font-size: 12px; top: -16px; }
.notice { position: absolute; left: 12px; top: 12px; right: 70px; z-index: 5; background: rgba(14,17,22,.85); color: #eef1f5;
  padding: 8px 12px; border-radius: 6px; font-size: 13px; }
.zoom { position: absolute; right: 12px; top: 12px; z-index: 5; display: flex; flex-direction: column; gap: 4px; }
.zoom button { width: 34px; height: 34px; font-size: 20px; font-weight: 700; color: #eef1f5; background: rgba(14,17,22,.85);
  border: 1px solid rgba(255,255,255,.2); border-radius: 6px; cursor: pointer; }
.credits { position: absolute; right: 6px; bottom: 4px; z-index: 5; font-size: 10px; color: #222; background: rgba(255,255,255,.6);
  padding: 1px 5px; border-radius: 3px; }
</style>
