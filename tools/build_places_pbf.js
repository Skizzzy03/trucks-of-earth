// Builds the Trucks of Earth place data from an OpenStreetMap extract (.osm.pbf, e.g. from download.geofabrik.de): the same
// places as build_places.js, without any online service.
// Usage: node build_places_pbf.js <outDir> <file.osm.pbf>     (no real company names: FF_NO_NAMES=1)
// Three runs over the file: nodes, ways and relations that are places; the ways of those relations; the nodes those ways start on.
// Data (c) OpenStreetMap contributors, ODbL.

const fs = require("fs")
const path = require("path")
const zlib = require("zlib")
const { CATS, ORDER, CELL, classify, nameOf, detailOf, tileKey, loadTile } = require("./build_places.js")

// the Overpass statements of build_places.js as tests: which kind of element, which tags
const RULES = []
for (const k of ORDER) for (const q of CATS[k].q) {
  const kind = q.slice(0, q.indexOf("["))
  const conds = [...q.matchAll(/\["([^"]+)"(?:(=|~)"([^"]*)")?\]/g)].map(m => ({ k: m[1], op: m[2], v: m[2] === "~" ? new RegExp(m[3]) : m[3] }))
  RULES.push({ kind, conds })
}
const COND = new Map()         // key -> what its value must be (any of these), the first look at an element
for (const r of RULES) for (const c of r.conds) if (c.k !== "name") { if (!COND.has(c.k)) COND.set(c.k, []); COND.get(c.k).push(c) }
const KEEP = ["name", "brand", "operator", "addr:street", "addr:housenumber", "addr:city", "addr:place"]
function slim(t) { const o = {}; for (const k of KEEP) if (t[k] !== undefined) o[k] = t[k]; return o }
function wanted(kind, t) {
  for (const r of RULES) {
    if (r.kind !== "nwr" && r.kind !== kind) continue
    if (r.conds.every(c => t[c.k] !== undefined && (!c.op || (c.op === "=" ? t[c.k] === c.v : c.v.test(t[c.k]))))) return true
  }
  return false
}

// --- protobuf, only what the format needs ---
function varint(b, st) {       // (safe up to 2^53: OSM ids and lengths are below that)
  let r = 0, m = 1, c
  do { c = b[st.p++]; r += (c & 127) * m; m *= 128 } while (c >= 128)
  return r
}
const zz = v => (v % 2 === 1 ? -(v + 1) / 2 : v / 2)
function fields(b, s, e, fn) {
  const st = { p: s }
  while (st.p < e) {
    const key = varint(b, st), f = Math.floor(key / 8), w = key % 8
    if (w === 0) fn(f, 0, varint(b, st))
    else if (w === 2) { const l = varint(b, st); fn(f, 2, st.p, st.p + l); st.p += l }
    else if (w === 1) { fn(f, 1, st.p); st.p += 8 }
    else if (w === 5) { fn(f, 5, st.p); st.p += 4 }
    else throw new Error("protobuf wire type " + w)
  }
}
function packed(b, s, e, out, delta) {      // zigzag deltas or plain varints into an array
  const st = { p: s }
  let n = 0, v = 0
  while (st.p < e) {
    const x = varint(b, st)
    if (delta) { v += zz(x); out[n++] = v } else out[n++] = x
  }
  return n
}

// the file: [4 byte length][BlobHeader][Blob] ...
function eachBlock(file, onBlock) {
  const fd = fs.openSync(file, "r"), size = fs.fstatSync(fd).size
  let pos = 0, head = Buffer.alloc(65536), n = 0
  const lenB = Buffer.alloc(4)
  while (pos < size) {
    fs.readSync(fd, lenB, 0, 4, pos); pos += 4
    const hl = lenB.readUInt32BE(0)
    if (hl > head.length) head = Buffer.alloc(hl)
    fs.readSync(fd, head, 0, hl, pos); pos += hl
    let type = "", dataSize = 0
    fields(head, 0, hl, (f, w, a, b) => { if (f === 1) type = head.toString("latin1", a, b); else if (f === 3) dataSize = a })
    const blob = Buffer.allocUnsafe(dataSize)
    fs.readSync(fd, blob, 0, dataSize, pos); pos += dataSize
    if (type !== "OSMData") continue
    let raw, zs, ze
    fields(blob, 0, dataSize, (f, w, a, b) => { if (f === 1) raw = [a, b]; else if (f === 3) { zs = a; ze = b } })
    const data = raw ? blob.subarray(raw[0], raw[1]) : zlib.inflateSync(blob.subarray(zs, ze))
    onBlock(data)
    if (++n % 2000 === 0) process.stdout.write(`  ${(pos / size * 100).toFixed(0)} %\n`)
  }
  fs.closeSync(fd)
}

const lat0 = 1e-9, ids = new Float64Array(9000), lats = new Float64Array(9000), lons = new Float64Array(9000), kv = new Float64Array(4000000)
const ks = new Float64Array(20000), vs = new Float64Array(20000)
function parseBlock(d, h) {
  let strs = null, gran = 100, latOff = 0, lonOff = 0
  const groups = []
  fields(d, 0, d.length, (f, w, a, b) => {
    if (f === 1) { strs = []; fields(d, a, b, (g, gw, s, e) => { if (g === 1) strs.push([s, e]) }) }
    else if (f === 2) groups.push([a, b])
    else if (f === 17) gran = a
    else if (f === 19) latOff = a
    else if (f === 20) lonOff = a
  })
  const str = i => d.toString("utf8", strs[i][0], strs[i][1])
  // (a tag that can make an element a place, remembered per block: building=yes and highway=crossing are skipped at once)
  let hot = null
  const memo = new Map()
  const isHot = i => { if (!hot) { hot = new Uint8Array(strs.length); strs.forEach((s, x) => { if (COND.has(d.toString("latin1", s[0], s[1]))) hot[x] = 1 }) } return hot[i] === 1 }
  const pairHot = (k, v) => {
    if (!isHot(k)) return false
    const m = k * 4294967296 + v
    let r = memo.get(m)
    if (r === undefined) { const val = str(v); r = COND.get(str(k)).some(c => !c.op || (c.op === "=" ? val === c.v : c.v.test(val))); memo.set(m, r) }
    return r
  }
  const anyHot = n => { for (let i = 0; i < n; i++) if (pairHot(ks[i], vs[i])) return true; return false }
  const tagsOf = n => { const t = {}; for (let i = 0; i < n; i++) t[str(ks[i])] = str(vs[i]); return t }
  const coord = (raw, off) => (off + gran * raw) * lat0
  for (const [gs, ge] of groups) fields(d, gs, ge, (f, w, a, b) => {
    if (f === 2 && (h.node || h.nodeId)) {            // DenseNodes
      let idR, laR, loR, kvR
      fields(d, a, b, (g, gw, s, e) => { if (g === 1) idR = [s, e]; else if (g === 8) laR = [s, e]; else if (g === 9) loR = [s, e]; else if (g === 10) kvR = [s, e] })
      if (!idR) return
      const n = packed(d, idR[0], idR[1], ids, true)
      if (h.nodeId) {
        let any = false
        for (let i = 0; i < n; i++) if (h.nodeId.has(ids[i])) { any = true; break }
        if (!any) return
        packed(d, laR[0], laR[1], lats, true); packed(d, loR[0], loR[1], lons, true)
        for (let i = 0; i < n; i++) if (h.nodeId.has(ids[i])) h.nodeId.set(ids[i], [coord(lats[i], latOff), coord(lons[i], lonOff)])
      }
      if (h.node && kvR) {
        const m = packed(d, kvR[0], kvR[1], kv, false)
        let i = 0, got = false
        for (i = 0; i < m; i++) {
          if (kv[i] === 0) continue
          if (pairHot(kv[i], kv[i + 1])) { got = true; break }
          i++
        }
        if (!got) return
        packed(d, laR[0], laR[1], lats, true); packed(d, loR[0], loR[1], lons, true)
        i = 0
        let node = 0, start = 0, hit = false
        while (i < m) {
          if (kv[i] === 0) {
            if (hit) {
              const t = {}                   // (all of this node's tags)
              for (let j = start; j < i; j += 2) t[str(kv[j])] = str(kv[j + 1])
              h.node(t, coord(lats[node], latOff), coord(lons[node], lonOff))
            }
            hit = false; node++; i++; start = i
            continue
          }
          if (!hit && pairHot(kv[i], kv[i + 1])) hit = true
          i += 2
        }
      }
    } else if (f === 3 && (h.way || h.wayRefs)) {     // Way
      let id = 0, kR, vR, rR
      fields(d, a, b, (g, gw, s, e) => { if (g === 1) id = s; else if (g === 2) kR = [s, e]; else if (g === 3) vR = [s, e]; else if (g === 8) rR = [s, e] })
      if (h.wayRefs && h.wayRefs.has(id) && rR) {
        const refs = []; packed(d, rR[0], rR[1], refs, true); h.wayRefs.set(id, refs[0])
      }
      if (!h.way || !kR) return
      const k = packed(d, kR[0], kR[1], ks, false)
      packed(d, vR[0], vR[1], vs, false)
      if (!anyHot(k)) return
      const refs = []; if (rR) packed(d, rR[0], rR[1], refs, true)
      h.way(tagsOf(k), refs)
    } else if (f === 4 && h.rel) {                    // Relation
      let kR, vR, mR, tR
      fields(d, a, b, (g, gw, s, e) => { if (g === 2) kR = [s, e]; else if (g === 3) vR = [s, e]; else if (g === 9) mR = [s, e]; else if (g === 10) tR = [s, e] })
      if (!kR || !mR) return
      const k = packed(d, kR[0], kR[1], ks, false)
      packed(d, vR[0], vR[1], vs, false)
      if (!anyHot(k)) return
      const mem = [], ty = []; packed(d, mR[0], mR[1], mem, true); if (tR) packed(d, tR[0], tR[1], ty, false)
      h.rel(tagsOf(k), mem[ty.indexOf(1)])
    }
  })
}

// --- the places, as build_places.js store() but with its limits over the whole file ---
function main() {
  const [outDir, file] = process.argv.slice(2)
  if (!outDir || !file) { console.log("node build_places_pbf.js <outDir> <file.osm.pbf>"); process.exit(1) }
  fs.mkdirSync(outDir, { recursive: true })
  const t0 = Date.now()
  const found = []        // { t, type, lat?, lon?, refs? }
  const refNodes = new Map(), relWays = new Map()
  eachBlock(file, d => parseBlock(d, {
    node(t, lat, lon) { if (wanted("node", t)) { const type = classify(t); if (type) found.push({ t: slim(t), type, lat, lon }) } },
    way(t, refs) {
      if (!wanted("way", t) || !refs.length) return
      const type = classify(t); if (!type) return
      const r = [refs[0], refs[refs.length >> 1]]         // (two points of the outline: their middle is near enough)
      r.forEach(x => refNodes.set(x, null))
      found.push({ t: slim(t), type, refs: r })
    },
    rel(t, way) {
      if (!wanted("relation", t) || way === undefined) return
      const type = classify(t); if (!type) return
      relWays.set(way, null)
      found.push({ t: slim(t), type, relWay: way })
    },
  }))
  console.log(`run 1: ${found.length} places, ${relWays.size} relations, ${((Date.now() - t0) / 1000).toFixed(0)} s`)
  if (relWays.size) eachBlock(file, d => parseBlock(d, { wayRefs: relWays }))
  for (const f of found) if (f.relWay !== undefined) {
    const r = relWays.get(f.relWay)
    if (r != null) { f.refs = [r]; refNodes.set(r, null) }
  }
  console.log(`run 2 done, ${refNodes.size} nodes to look up, ${((Date.now() - t0) / 1000).toFixed(0)} s`)
  if (refNodes.size) eachBlock(file, d => parseBlock(d, { nodeId: refNodes }))

  // the limits per cell count what the tiles already hold
  const tiles = {}, counts = {}
  const tileOf = key => {
    if (!tiles[key]) {
      tiles[key] = loadTile(outDir, key)
      for (const p of tiles[key].places) {
        const c = `${p[0]}:${Math.floor(p[2] / CELL)}:${Math.floor(p[3] / CELL)}`
        counts[c] = (counts[c] || 0) + 1
      }
    }
    return tiles[key]
  }
  const r6 = x => Math.round(x * 1e5) / 1e5
  let kept = 0, noPos = 0
  for (const f of found) {
    let lat = f.lat, lon = f.lon
    if (lat === undefined) {
      const pts = (f.refs || []).map(x => refNodes.get(x)).filter(Boolean)
      if (!pts.length) { noPos++; continue }
      lat = pts.reduce((s, p) => s + p[0], 0) / pts.length
      lon = pts.reduce((s, p) => s + p[1], 0) / pts.length
    }
    const tile = tileOf(tileKey(lat, lon))
    const cell = `${f.type}:${Math.floor(lat / CELL)}:${Math.floor(lon / CELL)}`
    if ((counts[cell] || 0) >= (CATS[f.type].cap || 4)) continue
    if (tile.places.some(p => p[0] === f.type && Math.abs(p[2] - lat) < 0.0015 && Math.abs(p[3] - lon) < 0.0022)) continue
    counts[cell] = (counts[cell] || 0) + 1
    tile.places.push([f.type, nameOf(f.type, f.t), r6(lat), r6(lon), detailOf(f.t)])
    kept++
  }
  for (const [key, tile] of Object.entries(tiles)) fs.writeFileSync(path.join(outDir, key + ".json"), JSON.stringify(tile))
  console.log(`done: ${kept} places added to ${Object.keys(tiles).length} tiles, ${noPos} without a position, ${((Date.now() - t0) / 1000).toFixed(0)} s`)
}

main()
