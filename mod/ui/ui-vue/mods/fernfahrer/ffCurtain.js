// Trucks of Earth: the loading curtain after "Weiterspielen" (2026-11-04). The title screen wipes away and zooms
// onto its truck; this curtain takes over with the same road – the truck driving on, now and then trees going by in
// front – and stays over everything (BeamNG's own loading screen while the level loads, the career's world loading
// after it) until the career says the world is ready. A plain element on document.body: it outlives route changes.
// showCurtain({ sky, title, sub }), hideCurtain(); it polls career.lua uiTrip itself and goes when the world is in.
import { engineLua } from "./ffBridge.js"

const ID = "ffCurtain"
const MIN_S = 6            // (shown at least this long: no flash)
const MAX_S = 240          // (never stuck: gone after this however it stands)
const TIPS = [
  "Leuchtende Kreise an Rastplätzen, Tankstellen und am Hof: reinfahren, anhalten, Enter – das Menü des Ortes.",
  "Nach dem Anhalten steht der Fahrtenschreiber auf „Arbeit“. Als Pause zählt nur, was du mit 🛏 startest.",
  "Strg+Umschalt+M blendet die Spiegel ein – Sichtfeld und Helligkeit im 🪞-Menü unter ⚙.",
  "Am Radio: Mausrad auf dem linken Knopf ist die Lautstärke, auf dem rechten der Sender. EQ klappt die Klangregler aus.",
  "Nach einer Lieferung warten Anschlussfrachten bei Firmen im selben Ort – orange auf der Karte.",
  "Ab 0,5 Promille oder THC über 3,5 ng/ml wird jede Polizeikontrolle teuer.",
]

const CSS = `
#${ID}{position:fixed;inset:0;z-index:2147483000;overflow:hidden;background:#0b1622;color:#eef1f5;font-family:inherit;opacity:0;transition:opacity .45s ease;pointer-events:all}
#${ID}.on{opacity:1}#${ID}.out{opacity:0;transition:opacity .7s ease}
#${ID} .sky{position:absolute;inset:0 0 26% 0;background:linear-gradient(180deg,#5d9fd6 0%,#a9d1ee 60%,#e6f1f8 100%)}
#${ID}.dusk .sky{background:linear-gradient(180deg,#2b3c6b 0%,#c4677a 58%,#f4b26b 100%)}
#${ID}.night .sky{background:linear-gradient(180deg,#050b18 0%,#13284a 60%,#2b4a72 100%)}
#${ID} .sun{position:absolute;right:16%;top:12%;width:110px;height:110px;border-radius:50%;background:radial-gradient(circle,#fff6d5 0%,#ffd77a 55%,rgba(255,215,122,0) 72%)}
#${ID}.night .sun{width:70px;height:70px;background:radial-gradient(circle,#f4f6ff 0%,#c9d3ef 50%,rgba(201,211,239,0) 70%)}
#${ID} .hills{position:absolute;left:0;width:200%;height:24%;bottom:25%;animation:ffcuHill 60s linear infinite;will-change:transform}
#${ID} .hills.h2{height:17%;bottom:24%;animation-duration:34s}
#${ID} .hills path{fill:#5f8a74}#${ID} .hills.h2 path{fill:#4b7a50}
#${ID}.dusk .hills path{fill:#4a4f6d}#${ID}.dusk .hills.h2 path{fill:#3a4a45}
#${ID}.night .hills path{fill:#18223a}#${ID}.night .hills.h2 path{fill:#142318}
@keyframes ffcuHill{to{transform:translateX(-50%)}}
#${ID} .tarmac{position:absolute;left:0;right:0;bottom:0;height:26%;background:#3a3f46;overflow:hidden}
#${ID}.night .tarmac{background:#17191d}
#${ID} .dash{position:absolute;left:0;width:200%;top:44%;height:7px;background:repeating-linear-gradient(90deg,#e9edf2 0 90px,transparent 90px 200px);animation:ffcuDash .9s linear infinite;opacity:.85;will-change:transform}
@keyframes ffcuDash{to{transform:translateX(-200px)}}
#${ID} .truck{position:absolute;bottom:19%;width:44vw;max-width:680px;left:28%;animation:ffcuRumble .32s ease-in-out infinite;z-index:2}
@keyframes ffcuRumble{0%,100%{transform:translateY(0)}50%{transform:translateY(2px)}}
#${ID} .truck .lamp{opacity:0}#${ID}.night .truck .lamp,#${ID}.dusk .truck .lamp{opacity:1;filter:drop-shadow(0 0 8px #ffe7a0)}
#${ID} .tree{position:absolute;bottom:-4%;z-index:4;left:0;transform:translateX(110vw);opacity:.92;animation:ffcuTree 1.6s linear forwards;will-change:transform}
#${ID} .tree.far{z-index:1;bottom:22%;filter:none;animation-duration:7s}
@keyframes ffcuTree{from{transform:translateX(110vw)}to{transform:translateX(-40vw)}}
#${ID} .vig{position:absolute;inset:0;z-index:3;background:radial-gradient(ellipse at 50% 60%,rgba(0,0,0,0) 55%,rgba(0,0,0,.45) 100%)}
#${ID} .card{position:absolute;z-index:5;left:50%;top:7vh;transform:translateX(-50%);width:min(720px,90vw);background:rgba(12,16,22,.88);border:1px solid rgba(255,255,255,.12);border-radius:8px;padding:18px 24px;box-shadow:0 18px 50px rgba(0,0,0,.45)}
#${ID} .kick{font-size:11px;letter-spacing:.16em;text-transform:uppercase;color:#f5a623;font-weight:800}
#${ID} .ttl{font-size:22px;font-weight:900;margin:8px 0 2px}#${ID} .sub{font-size:12.5px;color:#8b95a3}
#${ID} .st{margin-top:10px;font-size:13px;font-weight:700;color:#a6efc0}
#${ID} .bar{margin-top:10px;height:3px;background:#252c36;border-radius:2px;overflow:hidden}
#${ID} .bar i{display:block;height:100%;width:30%;background:#f5a623;border-radius:2px;animation:ffcuBar 1.6s ease-in-out infinite}
@keyframes ffcuBar{0%{transform:translateX(-100%)}100%{transform:translateX(340%)}}
#${ID} .tip{margin-top:10px;padding-top:9px;border-top:1px solid rgba(255,255,255,.08);font-size:12.5px;color:#cfd6de;line-height:1.4}
#${ID} .tip b{color:#f5a623;font-size:10.5px;letter-spacing:.14em;text-transform:uppercase;margin-right:6px}
`

const TRUCK = `<svg class="truck" viewBox="0 0 300 90">
  <rect x="6" y="14" width="196" height="56" rx="2" fill="#e9edf2"/><rect x="6" y="56" width="196" height="6" fill="#f5a623"/>
  <path d="M206 30 L250 30 Q262 30 266 42 L272 60 L272 70 L206 70 Z" fill="#1d3a6e"/>
  <path d="M232 36 L252 36 Q258 36 261 44 L264 52 L232 52 Z" fill="#9cc3e6"/>
  <g fill="#1b1f25"><circle cx="40" cy="74" r="10"/><circle cx="64" cy="74" r="10"/><circle cx="88" cy="74" r="10"/><circle cx="222" cy="74" r="10"/><circle cx="256" cy="74" r="10"/></g>
  <g fill="#8d96a3"><circle cx="40" cy="74" r="4"/><circle cx="64" cy="74" r="4"/><circle cx="88" cy="74" r="4"/><circle cx="222" cy="74" r="4"/><circle cx="256" cy="74" r="4"/></g>
  <circle cx="270" cy="62" r="3" fill="#ffe7a0" class="lamp"/></svg>`
const HILL = `<svg class="hills" viewBox="0 0 3200 200" preserveAspectRatio="none"><path d="M0 200 V120 Q 160 60 320 110 T 640 95 T 960 120 T 1280 80 T 1600 115 T 1920 95 T 2240 120 T 2560 80 T 2880 110 T 3200 120 V200 Z"/></svg>
<svg class="hills h2" viewBox="0 0 3200 200" preserveAspectRatio="none"><path d="M0 200 V140 Q 200 100 420 135 T 820 125 T 1220 140 T 1600 130 T 2020 125 T 2420 140 T 2820 125 T 3200 140 V200 Z"/></svg>`

// a tree: a trunk and a crown of a few circles (big and blurred in front, small far back)
function treeSvg(night, h) {
  const g = night ? ["#0f1c14", "#13241a", "#0c1710"] : ["#2f5d3a", "#3b7046", "#27502f"]
  const trunk = night ? "#1a1410" : "#4a3524"
  return `<svg viewBox="0 0 100 160" style="height:${h}vh;width:auto"><rect x="44" y="90" width="12" height="70" fill="${trunk}"/>
    <circle cx="50" cy="60" r="38" fill="${g[0]}"/><circle cx="30" cy="80" r="26" fill="${g[1]}"/><circle cx="70" cy="78" r="28" fill="${g[2]}"/>
    <circle cx="52" cy="34" r="26" fill="${g[1]}"/></svg>`
}

let el = null, pollT = null, treeT = null, t0 = 0, seenActive = false, done = false

function skyNow() { const h = new Date().getHours(); return h >= 21 || h < 6 ? "night" : h < 8 || h >= 19 ? "dusk" : "day" }

function ensureStyle() {
  if (document.getElementById(ID + "Css")) return
  const s = document.createElement("style"); s.id = ID + "Css"; s.textContent = CSS
  document.head.appendChild(s)
}

function spawnTree() {
  if (!el) return
  const near = Math.random() < 0.55
  const d = document.createElement("div")
  d.className = "tree" + (near ? "" : " far")
  d.innerHTML = treeSvg(el.classList.contains("night"), near ? 70 + Math.random() * 30 : 12 + Math.random() * 8)
  el.appendChild(d)
  setTimeout(() => d.remove(), near ? 1800 : 7200)
  // (now and then: a few seconds apart, sometimes two close together)
  treeT = setTimeout(spawnTree, 1400 + Math.random() * 4200)
}

function status(text) { const s = el && el.querySelector(".st"); if (s) s.textContent = text }

function parts(l) {
  const p = []
  if (!l) return p
  if (l.ground) p.push("Gelände")
  if (l.roads) p.push("Straßen")
  if (l.buildings) p.push("Gebäude")
  if (l.trees) p.push("Bäume")
  return p
}

function poll() {
  const el2 = (Date.now() - t0) / 1000
  const tipEl = el && el.querySelector(".tip span")
  if (tipEl) tipEl.textContent = TIPS[Math.floor(el2 / 7) % TIPS.length]
  if (el2 > MAX_S) { hideCurtain(); return }
  engineLua("fernfahrer_career and fernfahrer_career.uiTrip and fernfahrer_career.uiTrip() or nil", r => {
    if (!el || done) return
    if (!r) { status(seenActive ? "Letzte Details …" : "Die Karte wird geladen …"); return }
    if (r.active) {
      seenActive = true
      const p = parts(r.loading)
      status(p.length ? p.join(", ") + " werden geladen …" : (r.loading && r.loading.settling ? "Letzte Details …" : "Zurück zu deiner letzten Position …"))
    } else if (seenActive && el2 >= MIN_S) {
      status("Alles bereit – gute Fahrt")
      hideCurtain()
    }
  })
}

export function showCurtain(opts) {
  opts = opts || {}
  ensureStyle()
  if (el) el.remove()
  done = false; seenActive = false; t0 = Date.now()
  el = document.createElement("div")
  el.id = ID
  el.className = opts.sky || skyNow()
  el.innerHTML = `<div class="sky"></div><div class="sun"></div>${HILL}<div class="tarmac"><div class="dash"></div></div>${TRUCK}<div class="vig"></div>
    <div class="card"><div class="kick">Karriere wird geladen</div><div class="ttl"></div><div class="sub"></div>
    <div class="st">Die Karte wird geladen …</div><div class="bar"><i></i></div><div class="tip"><b>Tipp</b><span></span></div></div>`
  el.querySelector(".ttl").textContent = opts.title || "Weiterfahrt"
  el.querySelector(".sub").textContent = opts.sub || ""
  document.body.appendChild(el)
  setTimeout(() => el && el.classList.add("on"), 30)     // (a timer, not a frame callback: those wait while hidden)
  clearTimeout(treeT); treeT = setTimeout(spawnTree, 900)
  clearInterval(pollT); pollT = setInterval(poll, 500)
  poll()
}

export function hideCurtain() {
  if (!el || done) return
  done = true
  clearInterval(pollT); pollT = null
  clearTimeout(treeT); treeT = null
  const e = el
  e.classList.add("out")
  setTimeout(() => { e.remove(); if (el === e) el = null }, 800)
}

export function curtainUp() { return !!el && !done }
