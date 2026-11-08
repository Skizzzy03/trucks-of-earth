// Builds street names and settlements for the Trucks of Earth (police reports: "auf der Ahauser Straße (L 572)
// in Alstätte") from OpenStreetMap (Overpass API) – BeamNG.Earth's road data has no names.
// Usage: node build_streets.js <outDir> <s> <w> <n> <e>
// Output: <outDir>/streets_<lat>_<lon>.json per 0.1° tile = { v: 1, names: [...], pts: [[lat*1e5, lon*1e5, nameIdx], ...] }
//         (points every ~40 m along each named road), <outDir>/settlements.json = { v: 1, list: [[name, kind, lat, lon], ...] }
// Resumable (<outDir>/_done.json). One request at a time with a pause (a shared public service).
// Data © OpenStreetMap contributors, ODbL.

const fs = require("fs")
const path = require("path")

const ENDPOINT = "https://overpass-api.de/api/interpreter"
const UA = "fernfahrer-karriere-beamng-mod/1.0 (one-off data build)"
const PAUSE_MS = 3000
const BOX = 0.25          // request boxes
const TILE = 0.1          // output tiles
const STEP_M = 40
const HW = "motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|motorway_link|trunk_link|primary_link|secondary_link"

const [outDir, s, w, n, e] = process.argv.slice(2)
if (!outDir || !e) { console.log("usage: node build_streets.js <outDir> <s> <w> <n> <e>"); process.exit(1) }
fs.mkdirSync(outDir, { recursive: true })
const donePath = path.join(outDir, "_done.json")
const done = fs.existsSync(donePath) ? JSON.parse(fs.readFileSync(donePath, "utf8")) : {}

async function overpass(query, tries = 5) {
  for (let i = 1; i <= tries; i++) {
    try {
      const res = await fetch(ENDPOINT, { method: "POST", headers: { "User-Agent": UA, "Content-Type": "application/x-www-form-urlencoded" },
        body: "data=" + encodeURIComponent(query) })
      if (res.status === 200) return await res.json()
      console.log(`  HTTP ${res.status}, retry ${i}`)
    } catch (err) { console.log(`  ${err.message}, retry ${i}`) }
    await new Promise(r => setTimeout(r, PAUSE_MS * 4 * i))
  }
  throw new Error("Overpass failed")
}

function hav(a1, o1, a2, o2) {
  const r = Math.PI / 180, dp = (a2 - a1) * r, dl = (o2 - o1) * r
  const x = Math.sin(dp / 2) ** 2 + Math.cos(a1 * r) * Math.cos(a2 * r) * Math.sin(dl / 2) ** 2
  return 2 * 6371000 * Math.asin(Math.min(1, Math.sqrt(x)))
}

const tiles = {}          // key -> { names: [], index: {}, pts: [] }
const tileKey = (lat, lon) => (Math.floor(lat / TILE) * TILE).toFixed(1) + "_" + (Math.floor(lon / TILE) * TILE).toFixed(1)
function tileOf(key) {
  if (!tiles[key]) {
    const f = path.join(outDir, "streets_" + key + ".json")
    const t = { names: [], index: {}, pts: [] }
    if (fs.existsSync(f)) {
      const d = JSON.parse(fs.readFileSync(f, "utf8"))
      t.names = d.names; t.pts = d.pts
      d.names.forEach((nm, i) => { t.index[nm] = i })
    }
    tiles[key] = t
  }
  return tiles[key]
}
function addPoint(lat, lon, label) {
  const t = tileOf(tileKey(lat, lon))
  let i = t.index[label]
  if (i === undefined) { i = t.names.length; t.names.push(label); t.index[label] = i }
  t.pts.push([Math.round(lat * 1e5), Math.round(lon * 1e5), i])
}
function saveTiles() {
  for (const [key, t] of Object.entries(tiles)) {
    fs.writeFileSync(path.join(outDir, "streets_" + key + ".json"), JSON.stringify({ v: 1, names: t.names, pts: t.pts }))
  }
}

function labelOf(tags) {
  const ref = tags.ref ? tags.ref.replace(/^([ABLKS])\s*(\d)/, "$1 $2").split(";")[0] : null
  if (tags.name && ref) return `${tags.name} (${ref})`
  return tags.name || ref
}

async function main() {
  const S = +s, W = +w, N = +n, E = +e
  // settlements (one request for the whole box: few nodes)
  const sKey = `settlements:${S},${W},${N},${E}`
  if (!done[sKey]) {
    console.log("settlements …")
    const q = `[out:json][timeout:180];node["place"~"^(city|town|village|hamlet|suburb|quarter)$"]["name"](${S},${W},${N},${E});out;`
    const d = await overpass(q)
    const list = d.elements.map(x => [x.tags.name, x.tags.place, +x.lat.toFixed(5), +x.lon.toFixed(5)])
    const f = path.join(outDir, "settlements.json")
    const old = fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, "utf8")).list : []
    const seen = new Set(old.map(x => x[0] + "|" + x[2] + "|" + x[3]))
    for (const x of list) if (!seen.has(x[0] + "|" + x[2] + "|" + x[3])) old.push(x)
    fs.writeFileSync(f, JSON.stringify({ v: 1, list: old }))
    done[sKey] = true
    fs.writeFileSync(donePath, JSON.stringify(done))
    console.log(`  ${list.length} settlements`)
    await new Promise(r => setTimeout(r, PAUSE_MS))
  }
  const boxes = []
  for (let a = S; a < N - 1e-9; a += BOX) for (let o = W; o < E - 1e-9; o += BOX) boxes.push([a, o])
  let k = 0
  for (const [a, o] of boxes) {
    k++
    const key = a.toFixed(2) + "/" + o.toFixed(2)
    if (done[key]) continue
    const bb = `${a},${o},${(a + BOX).toFixed(4)},${(o + BOX).toFixed(4)}`
    const q = `[out:json][timeout:180];(way["highway"~"^(${HW})$"]["name"](${bb});way["highway"~"^(motorway|trunk|primary|secondary|tertiary)$"]["ref"](${bb}););out tags geom;`
    try {
      const d = await overpass(q)
      let ways = 0, pts = 0
      for (const x of d.elements) {
        const label = labelOf(x.tags || {})
        if (!label || !x.geometry) continue
        ways++
        let acc = STEP_M
        for (let i = 0; i < x.geometry.length; i++) {
          const g = x.geometry[i]
          if (i > 0) acc += hav(x.geometry[i - 1].lat, x.geometry[i - 1].lon, g.lat, g.lon)
          // (only points inside this box: neighbouring boxes add their own)
          if (acc >= STEP_M && g.lat >= a && g.lat < a + BOX && g.lon >= o && g.lon < o + BOX) { addPoint(g.lat, g.lon, label); pts++; acc = 0 }
        }
      }
      saveTiles()
      done[key] = true
      fs.writeFileSync(donePath, JSON.stringify(done))
      console.log(`[${k}/${boxes.length}] ${key}: ${ways} ways, ${pts} points`)
    } catch (err) {
      console.log(`[${k}/${boxes.length}] ${key}: skipped (${err.message})`)
    }
    await new Promise(r => setTimeout(r, PAUSE_MS))
  }
  console.log("done")
}
main()
