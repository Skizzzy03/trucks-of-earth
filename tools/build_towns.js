// Builds the Trucks of Earth town tiles from GeoNames country dumps (2026-11-05):
//   node build_towns.js <geonamesDir with CC.txt files> <outDir> [s w n e]
// Output: <outDir>/<lat>_<lon>.json = { v: 1, list: [[name, kind, lat, lon, population]] } per 1-degree tile.
// kind from the population: city ≥ 100 000, town ≥ 10 000, else village (GeoNames P/PPL* places; districts PPLX left out).
// Data © GeoNames (geonames.org), CC BY 4.0.
const fs = require("fs"), path = require("path"), readline = require("readline")
const [dir, out, s = 45.5, w = 2.0, n = 57.8, e = 19.5] = process.argv.slice(2)
fs.mkdirSync(out, { recursive: true })
const CODES = new Set(["PPL", "PPLA", "PPLA2", "PPLA3", "PPLA4", "PPLA5", "PPLC", "PPLS", "PPLF", "PPLG", "PPLL", "PPLR", "PPLX"])
const tiles = {}
let kept = 0
async function readFile(f) {
  const rl = readline.createInterface({ input: fs.createReadStream(f, "utf8"), crlfDelay: Infinity })
  for await (const line of rl) {
    const c = line.split("\t")
    if (c[6] !== "P" || !CODES.has(c[7])) continue
    const lat = +c[4], lon = +c[5], pop = +c[14] || 0
    if (lat < +s || lat > +n || lon < +w || lon > +e) continue
    // (districts of a city, PPLX: "suburb" – the generated companies spread over a big city by them)
    const kind = c[7] === "PPLX" ? "suburb" : pop >= 100000 ? "city" : pop >= 10000 ? "town" : "village"
    const key = `${Math.floor(lat)}_${Math.floor(lon)}`
    const t = tiles[key] || (tiles[key] = [])
    t.push([c[1].slice(0, 50), kind, +lat.toFixed(5), +lon.toFixed(5), pop])
    kept++
  }
}
;(async () => {
  for (const f of fs.readdirSync(dir).filter(x => /^[A-Z]{2}\.txt$/.test(x))) { await readFile(path.join(dir, f)); console.log(f, kept) }
  let files = 0, bytes = 0
  for (const [k, list] of Object.entries(tiles)) {
    // (two entries of one name within 1 km: the bigger kept)
    list.sort((a, b) => b[4] - a[4])
    const keep = []
    for (const x of list) if (!keep.some(y => y[0] === x[0] && Math.abs(y[2] - x[2]) < 0.01 && Math.abs(y[3] - x[3]) < 0.015)) keep.push(x)
    const txt = JSON.stringify({ v: 1, list: keep })
    fs.writeFileSync(path.join(out, k + ".json"), txt)
    files++; bytes += txt.length
  }
  console.log(`${kept} places in ${files} tiles, ${(bytes / 1048576).toFixed(1)} MB`)
})()
