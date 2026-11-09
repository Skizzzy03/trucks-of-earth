// Builds the Trucks of Earth place data from OpenStreetMap (Overpass API), so the game needs no online search.
// Usage: node build_places.js <outDir> region <s> <w> <n> <e>   (1-degree tiles inside the box)
//        node build_places.js <outDir> cities <cities.lua>       (the long-haul cities, ~13 km around each)
// Output: <outDir>/<lat>_<lon>.json = { v: 1, places: [[type, name, lat, lon, detail], ...] } per 1-degree tile,
// merged with what is already there. One request at a time with a pause between (a shared public service).
// Data © OpenStreetMap contributors, ODbL.

const fs = require("fs")
const path = require("path")

// (2026-11-08: the main server answered 502 or ran into its timeouts under load: the next one is tried)
const ENDPOINTS = (process.env.FF_ENDPOINTS || "https://maps.mail.ru/osm/tools/overpass/api/interpreter,https://overpass-api.de/api/interpreter").split(",")
const UA = "fernfahrer-karriere-beamng-mod/1.0 (one-off data build)"
const PAUSE_MS = 4000

// the Overpass statements per place type (BBOX is replaced) and how a returned element is recognised again
const CATS = {
  logistics: { q: ['nwr["industrial"~"^(warehouse|logistics|distributor)$"]["name"]', 'nwr["office"="logistics"]["name"]', 'nwr["shop"="wholesale"]["name"]', 'way["building"="warehouse"]["name"]'],
    m: t => /^(warehouse|logistics|distributor)$/.test(t.industrial || "") || t.office === "logistics" || t.shop === "wholesale" || t.building === "warehouse" },
  post: { q: ['nwr["amenity"="post_depot"]'], m: t => t.amenity === "post_depot" },
  supermarket: { q: ['nwr["shop"="supermarket"]["name"]'], m: t => t.shop === "supermarket", cap: 2 },
  hardware: { q: ['nwr["shop"~"^(doityourself|hardware)$"]["name"]'], m: t => /^(doityourself|hardware)$/.test(t.shop || "") },
  furniture: { q: ['nwr["shop"="furniture"]["name"]'], m: t => t.shop === "furniture", cap: 2 },
  industry: { q: ['way["landuse"="industrial"]["name"]', 'relation["landuse"="industrial"]["name"]'], m: t => t.landuse === "industrial" },
  drinks: { q: ['nwr["craft"="brewery"]["name"]', 'nwr["industrial"="brewery"]["name"]', 'nwr["shop"="beverages"]["name"]'],
    m: t => t.craft === "brewery" || t.industrial === "brewery" || t.shop === "beverages", cap: 2 },
  dairy: { q: ['nwr["industrial"="dairy"]', 'nwr["craft"="cheese_maker"]["name"]'], m: t => t.industrial === "dairy" || t.craft === "cheese_maker" },
  timber: { q: ['nwr["craft"="sawmill"]', 'nwr["industrial"="sawmill"]', 'nwr["shop"="trade"]["trade"~"timber|wood"]["name"]'],
    m: t => t.craft === "sawmill" || t.industrial === "sawmill" || (t.shop === "trade" && /timber|wood/.test(t.trade || "")) },
  building: { q: ['nwr["shop"="trade"]["trade"~"building_materials|builder"]["name"]'], m: t => t.shop === "trade" && /building_materials|builder/.test(t.trade || "") },
  farm: { q: ['nwr["shop"="agrarian"]["name"]'], m: t => t.shop === "agrarian" },
  port: { q: ['nwr["landuse"="port"]["name"]', 'nwr["industrial"="port"]["name"]'], m: t => t.landuse === "port" || t.industrial === "port" },
  fuel: { q: ['nwr["amenity"="fuel"]'], m: t => t.amenity === "fuel", cap: 2 },
  workshop: { q: ['nwr["shop"="truck_repair"]', 'nwr["shop"="car_repair"]["name"~"LKW|Lkw|Nutzfahrzeug|Truck"]'],
    m: t => t.shop === "truck_repair" || (t.shop === "car_repair" && /LKW|Lkw|Nutzfahrzeug|Truck/.test(t.name || "")) },
  truckdealer: { q: ['nwr["shop"="truck"]', 'nwr["shop"="car"]["name"~"Truck|LKW|Nutzfahrzeug|Trucks"]'],
    m: t => t.shop === "truck" || (t.shop === "car" && /Truck|LKW|Nutzfahrzeug/.test(t.name || "")) },
  cardealer: { q: ['nwr["shop"="car"]["name"]'], m: t => t.shop === "car" && !/Truck|LKW|Nutzfahrzeug/.test(t.name || ""), cap: 2 },
  viewpoint: { q: ['nwr["tourism"="viewpoint"]["name"]'], m: t => t.tourism === "viewpoint", cap: 2 },
  rest: { q: ['nwr["highway"="rest_area"]', 'nwr["highway"="services"]', 'nwr["amenity"="parking"]["hgv"~"^(designated|yes)$"]'],
    m: t => t.highway === "rest_area" || t.highway === "services" || (t.amenity === "parking" && /^(designated|yes)$/.test(t.hgv || "")), cap: 3 },
}
const ORDER = Object.keys(CATS)
const CELL = 0.1          // degrees: at most `cap` (default 4) places of a type per cell

const NAMES = { rest: "Rastplatz", fuel: "Tankstelle", post: "Paketzentrum", dairy: "Molkerei", timber: "Sägewerk", workshop: "LKW-Werkstatt",
  truckdealer: "Nutzfahrzeuge", industry: "Gewerbegebiet", logistics: "Logistik" }

function classify(tags) {
  for (const k of ORDER) if (CATS[k].m(tags)) return k
  return null
}

function nameOf(type, t) {
  if (process.env.FF_NO_NAMES) return ""        // (no real company names in the shipped data: names.lua makes them up in the game)
  let n = t.name || t.brand || t.operator || NAMES[type] || type
  if (type === "fuel" && t.brand && t.name && !t.name.includes(t.brand)) n = t.brand + " " + t.name
  if (type === "industry" && !/gewerbe|industrie|park|hafen|gebiet/i.test(n)) n = "Gewerbegebiet " + n
  return n.slice(0, 60)
}

function detailOf(t) {
  const parts = [t["addr:street"] && (t["addr:street"] + (t["addr:housenumber"] ? " " + t["addr:housenumber"] : "")), t["addr:city"] || t["addr:place"]]
  return parts.filter(Boolean).join(", ")
}

async function overpass(query, tries = 4) {
  for (let i = 1; i <= tries; i++) {
    try {
      const res = await fetch(ENDPOINTS[(i - 1) % ENDPOINTS.length], { method: "POST", headers: { "User-Agent": UA, "Content-Type": "application/x-www-form-urlencoded" },
        body: "data=" + encodeURIComponent(query) })
      if (res.status === 200) {
        const j = await res.json()
        // (a query that ran out of time still answers 200, with no elements and a remark: it does not count as done)
        if (!j.remark || !/error|timed out|out of memory/i.test(j.remark)) return j
        console.log(`  ${String(j.remark).slice(0, 80)}, retry ${i}`)
      } else console.log(`  HTTP ${res.status}, retry ${i}`)
    } catch (e) {
      console.log(`  ${e.message}, retry ${i}`)
    }
    await new Promise(r => setTimeout(r, PAUSE_MS * 4 * i))
  }
  throw new Error("Overpass failed")
}

// small requests (one group of types over a half-degree box): a whole degree with every type timed out (502/504)
const GROUPS = [
  ["supermarket", "hardware", "furniture", "drinks"],
  ["fuel", "workshop", "truckdealer", "cardealer"],
  ["logistics", "post"],
  ["industry", "port"],
  ["dairy", "timber", "building", "farm", "viewpoint"],
  ["rest"],
]

function boxQuery(boxes, types) {
  const parts = []
  for (const k of types) for (const s of CATS[k].q) for (const b of boxes) parts.push(`${s}(${b.join(",")});`)
  return `[out:json][timeout:${process.env.FF_TIMEOUT || 90}];(${parts.join("")});out center tags qt;`
}

function tileKey(lat, lon) { return `${Math.floor(lat)}_${Math.floor(lon)}` }

function loadTile(outDir, key) {
  const f = path.join(outDir, key + ".json")
  try { return JSON.parse(fs.readFileSync(f, "utf8")) } catch (e) { return { v: 1, places: [] } }
}

function store(outDir, elements) {
  const tiles = {}, counts = {}
  let kept = 0
  for (const el of elements) {
    const t = el.tags || {}
    const lat = el.lat ?? (el.center && el.center.lat), lon = el.lon ?? (el.center && el.center.lon)
    if (lat === undefined || lon === undefined) continue
    const type = classify(t)
    if (!type) continue
    const cell = `${type}:${Math.floor(lat / CELL)}:${Math.floor(lon / CELL)}`
    if ((counts[cell] = (counts[cell] || 0) + 1) > (CATS[type].cap || 4)) continue
    const key = tileKey(lat, lon)
    const tile = tiles[key] || (tiles[key] = loadTile(outDir, key))
    const r6 = x => Math.round(x * 1e5) / 1e5
    if (tile.places.some(p => p[0] === type && Math.abs(p[2] - lat) < 0.0015 && Math.abs(p[3] - lon) < 0.0022)) continue
    tile.places.push([type, nameOf(type, t), r6(lat), r6(lon), detailOf(t)])
    kept++
  }
  for (const [key, tile] of Object.entries(tiles)) fs.writeFileSync(path.join(outDir, key + ".json"), JSON.stringify(tile))
  return kept
}

async function main() {
  const [outDir, mode, ...a] = process.argv.slice(2)
  fs.mkdirSync(outDir, { recursive: true })
  const areas = []
  if (mode === "region") {
    const [s, w, n, e] = a.map(Number)
    for (let la = s; la < n - 1e-9; la += 0.5)
      for (let lo = w; lo < e - 1e-9; lo += 0.5)
        areas.push({ label: `${la.toFixed(1)}/${lo.toFixed(1)}`, boxes: [[la, lo, Math.min(la + 0.5, n), Math.min(lo + 0.5, e)]] })
  } else if (mode === "europe") {
    // Germany first in 2-degree blocks with every type; then Europe outwards in 4-degree blocks with the network's types
    for (let la = 47; la < 55; la += 2) for (let lo = 5; lo < 15; lo += 2)
      areas.push({ label: `D${la}/${lo}`, boxes: [[la, lo, la + 2, lo + 2]] })
    const B = 4, blocks = []
    const NET = [["fuel", "workshop", "truckdealer"], ["rest"], ["logistics", "post", "port"], ["industry"]]
    for (let la = 36; la < 72; la += B) for (let lo = -12; lo < 40; lo += B) {
      const dx = (lo + B / 2 - 10) * Math.cos((la + B / 2) * Math.PI / 180), dy = la + B / 2 - 51
      blocks.push({ la, lo, d: dx * dx + dy * dy })
    }
    blocks.sort((a, b) => a.d - b.d)
    for (const b of blocks) areas.push({ label: `E${b.la}/${b.lo}`, boxes: [[b.la, b.lo, b.la + B, b.lo + B]], groups: NET })
  } else if (mode === "cities") {
    const src = fs.readFileSync(a[0], "utf8")
    const cities = [...src.matchAll(/\{ '([^']+)', ([\d.]+), ([\d.]+) \}/g)].map(m => [m[1], +m[2], +m[3]])
    for (let i = 0; i < cities.length; i += 3) {
      const group = cities.slice(i, i + 3)
      areas.push({ label: group.map(c => c[0]).join(", "), boxes: group.map(c => [c[1] - 0.1, c[2] - 0.15, c[1] + 0.1, c[2] + 0.15]) })
    }
  }
  // resumable: finished requests are remembered in _done.json
  const doneFile = process.env.FF_DONE || path.join(outDir, "_done.json")   // (FF_DONE: outside the folder that ships)
  let done = {}
  try { done = JSON.parse(fs.readFileSync(doneFile, "utf8")) } catch (e) { /* first run */ }
  const jobs = []
  for (const ar of areas) for (const g of ar.groups || GROUPS) jobs.push({ key: ar.label + "|" + g.join(","), label: `${ar.label} · ${g.join(",")}`, boxes: ar.boxes, types: g })
  let total = 0, failed = 0
  for (const [i, j] of jobs.entries()) {
    if (done[j.key]) continue
    const t0 = Date.now()
    process.stdout.write(`[${i + 1}/${jobs.length}] ${j.label} ... `)
    try {
      const data = await overpass(boxQuery(j.boxes, j.types), 3)
      const kept = store(outDir, data.elements || [])
      total += kept
      done[j.key] = true
      fs.writeFileSync(doneFile, JSON.stringify(done))
      console.log(`${(data.elements || []).length} elements, ${kept} kept, ${((Date.now() - t0) / 1000).toFixed(0)} s`)
    } catch (e) {
      failed++
      console.log("skipped (" + e.message + ")")
    }
    await new Promise(r => setTimeout(r, PAUSE_MS))
  }
  console.log(`done: ${total} places, ${failed} requests failed (run again to retry them)`)
}

if (require.main === module) main().catch(e => { console.error(e); process.exit(1) })
module.exports = { CATS, ORDER, CELL, classify, nameOf, detailOf, tileKey, loadTile }   // (build_places_pbf.js)
