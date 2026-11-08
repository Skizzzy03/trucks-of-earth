// Builds the Trucks of Earth map data for a whole region from OpenStreetMap (Overpass API), 2026-11-05:
//  - places (depots, shops, fuel, rest areas …) per 1-degree tile:  <out>/places/<lat>_<lon>.json  { v, places: [[type, name, lat, lon, detail]] }
//  - towns (city, town, village, suburb) per 1-degree tile:         <out>/towns/<lat>_<lon>.json   { v, list: [[name, kind, lat, lon]] }
// Usage: node build_world.js <outDir> <s> <w> <n> <e>   (run again with a bigger box later: finished cells are skipped)
// Several public Overpass servers are used side by side, one request at a time each, with a pause between.
// Data © OpenStreetMap contributors, ODbL.

const fs = require("fs")
const path = require("path")

const ENDPOINTS = ["https://maps.mail.ru/osm/tools/overpass/api/interpreter", "https://overpass-api.de/api/interpreter"]
const UA = "fernfahrer-karriere-beamng-mod/1.1 (one-off data build)"
const PAUSE_MS = 2500

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
const CELL = 0.1
const NAMES = { rest: "Rastplatz", fuel: "Tankstelle", post: "Paketzentrum", dairy: "Molkerei", timber: "Sägewerk", workshop: "LKW-Werkstatt",
  truckdealer: "Nutzfahrzeuge", industry: "Gewerbegebiet", logistics: "Logistik" }
const GROUPS = [
  ["supermarket", "hardware", "furniture", "drinks", "fuel", "workshop", "truckdealer", "cardealer"],
  ["logistics", "post", "industry", "port"],
  ["dairy", "timber", "building", "farm", "viewpoint", "rest"],
]

const classify = t => { for (const k of ORDER) if (CATS[k].m(t)) return k; return null }
function nameOf(type, t) {
  let n = t.name || t.brand || t.operator || NAMES[type] || type
  if (type === "fuel" && t.brand && t.name && !t.name.includes(t.brand)) n = t.brand + " " + t.name
  if (type === "industry" && !/gewerbe|industrie|park|hafen|gebiet|zone|industr/i.test(n)) n = "Gewerbegebiet " + n
  return n.slice(0, 60)
}
const detailOf = t => [t["addr:street"] && (t["addr:street"] + (t["addr:housenumber"] ? " " + t["addr:housenumber"] : "")), t["addr:city"] || t["addr:place"]].filter(Boolean).join(", ")
const tileKey = (lat, lon) => `${Math.floor(lat)}_${Math.floor(lon)}`

async function overpass(endpoint, query) {
  for (let i = 1; i <= 3; i++) {
    try {
      const ctl = new AbortController(), timer = setTimeout(() => ctl.abort(), 200000)
      const res = await fetch(endpoint, { method: "POST", signal: ctl.signal, headers: { "User-Agent": UA, "Content-Type": "application/x-www-form-urlencoded" }, body: "data=" + encodeURIComponent(query) })
      clearTimeout(timer)
      if (res.status === 200) return await res.json()
      console.log(`  ${new URL(endpoint).host} HTTP ${res.status}`)
    } catch (e) { console.log(`  ${new URL(endpoint).host} ${e.name}`) }
    await new Promise(r => setTimeout(r, PAUSE_MS * 6 * i))
  }
  throw new Error("Overpass failed")
}

// the tiles are written by one place only (this process), queued per file
const tileCache = {}
function loadJson(f, def) { try { return JSON.parse(fs.readFileSync(f, "utf8")) } catch (e) { return def } }
function storePlaces(dir, elements) {
  const touched = {}, counts = {}
  let kept = 0
  for (const el of elements) {
    const t = el.tags || {}
    const lat = el.lat ?? (el.center && el.center.lat), lon = el.lon ?? (el.center && el.center.lon)
    if (lat === undefined || lon === undefined) continue
    const type = classify(t)
    if (!type) continue
    const cell = `${type}:${Math.floor(lat / CELL)}:${Math.floor(lon / CELL)}`
    if ((counts[cell] = (counts[cell] || 0) + 1) > (CATS[type].cap || 4)) continue
    const key = tileKey(lat, lon), f = path.join(dir, key + ".json")
    const tile = tileCache[f] || (tileCache[f] = loadJson(f, { v: 1, places: [] }))
    const r5 = x => Math.round(x * 1e5) / 1e5
    if (tile.places.some(p => p[0] === type && Math.abs(p[2] - lat) < 0.0015 && Math.abs(p[3] - lon) < 0.0022)) continue
    tile.places.push([type, nameOf(type, t), r5(lat), r5(lon), detailOf(t)])
    touched[f] = tile
    kept++
  }
  for (const [f, tile] of Object.entries(touched)) fs.writeFileSync(f, JSON.stringify(tile))
  return kept
}
function storeTowns(dir, elements) {
  const touched = {}
  for (const x of elements) {
    if (!x.tags || !x.tags.name) continue
    const f = path.join(dir, tileKey(x.lat, x.lon) + ".json")
    const tile = tileCache[f] || (tileCache[f] = loadJson(f, { v: 1, list: [] }))
    const name = x.tags["name:de"] || x.tags.name
    if (tile.list.some(s => s[0] === name && Math.abs(s[2] - x.lat) < 0.001)) continue
    tile.list.push([name.slice(0, 50), x.tags.place, +x.lat.toFixed(5), +x.lon.toFixed(5)])
    touched[f] = tile
  }
  for (const [f, tile] of Object.entries(touched)) fs.writeFileSync(f, JSON.stringify(tile))
  return Object.keys(touched).length
}

async function main() {
  const [outDir, s, w, n, e] = process.argv.slice(2)
  const S = +s, W = +w, N = +n, E = +e
  const pDir = path.join(outDir, "places"), tDir = path.join(outDir, "towns")
  fs.mkdirSync(pDir, { recursive: true }); fs.mkdirSync(tDir, { recursive: true })
  const doneFile = path.join(outDir, "_done.json")
  const done = loadJson(doneFile, {})
  const jobs = []
  // towns: one request per degree tile (nodes only – quick)
  if (process.env.TOWNS) for (let la = Math.floor(S); la < N - 1e-9; la++) for (let lo = Math.floor(W); lo < E - 1e-9; lo++)
    jobs.push({ key: `towns:${la}/${lo}`, q: `[out:json][timeout:120];node["place"~"^(city|town|village|suburb)$"]["name"](${la},${lo},${la + 1},${lo + 1});out;`, towns: true })
  // places: half-degree cells, three groups of types each
  const CS = +(process.env.CELL || 0.25)
  for (let la = S; la < N - 1e-9; la += CS) for (let lo = W; lo < E - 1e-9; lo += CS) for (const g of GROUPS) {
    const box = [+la.toFixed(2), +lo.toFixed(2), +(la + CS).toFixed(2), +(lo + CS).toFixed(2)]
    const parts = []
    for (const k of g) for (const st of CATS[k].q) parts.push(`${st}(${box.join(",")});`)
    jobs.push({ key: `p${CS}:${la.toFixed(2)}/${lo.toFixed(2)}|${g[0]}`, q: `[out:json][timeout:150];(${parts.join("")});out center tags qt;` })
  }
  const todo = jobs.filter(j => !done[j.key])
  console.log(`${jobs.length} jobs, ${todo.length} to do, ${ENDPOINTS.length} servers`)
  let next = 0, ok = 0, failed = 0, places = 0
  const t0 = Date.now()
  async function worker(endpoint) {
    while (next < todo.length) {
      const j = todo[next++]
      try {
        const d = await overpass(endpoint, j.q)
        if (j.towns) storeTowns(tDir, d.elements || []); else places += storePlaces(pDir, d.elements || [])
        done[j.key] = true
        fs.writeFileSync(doneFile, JSON.stringify(done))
        ok++
      } catch (err) { failed++ }
      if ((ok + failed) % 20 === 0) {
        const el = (Date.now() - t0) / 1000, rate = (ok + failed) / el
        console.log(`${ok + failed}/${todo.length} (${failed} failed), ${places} places, ~${Math.round((todo.length - ok - failed) / Math.max(rate, 1e-3) / 60)} min left`)
      }
      await new Promise(r => setTimeout(r, PAUSE_MS))
    }
  }
  await Promise.all(ENDPOINTS.map(worker))
  console.log(`done: ${ok} ok, ${failed} failed (run again to retry), ${places} places added`)
}
main().catch(e => { console.error(e); process.exit(1) })
