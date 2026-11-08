// Builds the car transporter's load: low-poly new cars and wrecks, tied down on the EU flatbed semi trailer, as a part
// of that trailer (no extra vehicles, no extra physics – a flexbody on the deck's own nodes and six weight nodes).
// node tools/build_cars.js <mod dir>
// → <mod>/vehicles/eu_trailers/ff_cars.dae, ff_cars.materials.json, ff_cars.jbeam, ff_cars_new.pc, ff_wrecks.pc, info_*.json
const fs = require('fs'), path = require('path')
const mod = process.argv[2]
const out = path.join(mod, 'vehicles', 'eu_trailers')
fs.mkdirSync(out, { recursive: true })

let seed = 7
function rnd() { seed = (seed * 16807) % 2147483647; return (seed - 1) / 2147483646 }

function Mesh() { this.t = {} }
Mesh.prototype.tri = function (m, a, b, c) {
  const u = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], v = [c[0] - a[0], c[1] - a[1], c[2] - a[2]]
  let n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]
  const l = Math.hypot(n[0], n[1], n[2]); if (l < 1e-9) return
  n = n.map(x => x / l);
  (this.t[m] = this.t[m] || []).push({ p: [a, b, c], n })
}
Mesh.prototype.quad = function (m, a, b, c, d) { this.tri(m, a, b, c); this.tri(m, a, c, d) }
// a box between two corners
Mesh.prototype.box = function (m, x0, y0, z0, x1, y1, z1) {
  const P = (x, y, z) => [x, y, z]
  this.quad(m, P(x0, y0, z1), P(x1, y0, z1), P(x1, y1, z1), P(x0, y1, z1))     // top
  this.quad(m, P(x0, y1, z0), P(x1, y1, z0), P(x1, y0, z0), P(x0, y0, z0))     // bottom
  this.quad(m, P(x0, y0, z0), P(x1, y0, z0), P(x1, y0, z1), P(x0, y0, z1))     // front (-y)
  this.quad(m, P(x1, y1, z0), P(x0, y1, z0), P(x0, y1, z1), P(x1, y1, z1))     // rear
  this.quad(m, P(x1, y0, z0), P(x1, y1, z0), P(x1, y1, z1), P(x1, y0, z1))     // +x
  this.quad(m, P(x0, y1, z0), P(x0, y0, z0), P(x0, y0, z1), P(x0, y1, z1))     // -x
}
// a wheel: across x at (x, y), standing on z=0
Mesh.prototype.wheel = function (x, y, r, w) {
  const N = 14, xo = x + (x > 0 ? w / 2 : -w / 2), xi = x - (x > 0 ? w / 2 : -w / 2)
  const c = i => { const a = i / N * Math.PI * 2; return [y + Math.cos(a) * r, r + Math.sin(a) * r] }
  for (let i = 0; i < N; i++) {
    const [y0, z0] = c(i), [y1, z1] = c(i + 1)
    if (x > 0) this.quad('ff_tire', [xo, y0, z0], [xo, y1, z1], [xi, y1, z1], [xi, y0, z0])
    else this.quad('ff_tire', [xo, y1, z1], [xo, y0, z0], [xi, y0, z0], [xi, y1, z1])
    const rr = r * 0.62, a0 = i / N * Math.PI * 2, a1 = (i + 1) / N * Math.PI * 2
    const P = (a, q) => [xo, y + Math.cos(a) * q, r + Math.sin(a) * q]
    if (x > 0) { this.tri('ff_rim', [xo, y, r], P(a0, rr), P(a1, rr)); this.quad('ff_tire', P(a0, rr), P(a0, r), P(a1, r), P(a1, rr)) }
    else { this.tri('ff_rim', [xo, y, r], P(a1, rr), P(a0, rr)); this.quad('ff_tire', P(a1, rr), P(a1, r), P(a0, r), P(a0, rr)) }
  }
}

// A car: stations along y (front is -y): [y, half width, z bottom, z top]; the greenhouse: [y, half width, z base, z top]
const SHAPES = {
  sedan: { L: 4.3, wb: 2.65, body: [[-2.15, .72, .34, .62], [-2.1, .82, .26, .74], [-1.2, .89, .22, .86], [-.55, .9, .22, .92], [1.2, .9, .22, .94], [1.85, .86, .26, .92], [2.15, .74, .36, .82]],
    glass: [[-.62, .82, .9, .92], [.05, .72, .92, 1.38], [.95, .72, .93, 1.36], [1.62, .8, .92, .96]] },
  hatch: { L: 4.0, wb: 2.5, body: [[-2.0, .72, .34, .64], [-1.95, .8, .26, .76], [-1.2, .86, .22, .88], [-.6, .87, .22, .94], [1.45, .87, .22, .98], [1.9, .8, .3, .96], [2.0, .74, .38, .92]],
    glass: [[-.66, .79, .92, .94], [.0, .7, .94, 1.42], [1.5, .68, .96, 1.4], [1.92, .74, .94, .98]] },
  suv: { L: 4.4, wb: 2.75, body: [[-2.2, .78, .42, .78], [-2.14, .88, .34, .94], [-1.25, .94, .3, 1.08], [-.6, .95, .3, 1.12], [1.5, .95, .3, 1.14], [2.1, .9, .36, 1.1], [2.2, .82, .46, 1.04]],
    glass: [[-.66, .86, 1.1, 1.12], [.0, .78, 1.12, 1.68], [1.65, .76, 1.14, 1.66], [2.08, .82, 1.1, 1.14]] },
}

function carInto(m, shapeKey, paint, wreck) {
  const s = SHAPES[shapeKey]
  const j = (v, a) => wreck ? v + (rnd() - 0.5) * a : v
  // the wreck: its front pushed in
  const body = s.body.map(([y, w, z0, z1], i) => {
    if (wreck && i <= 2) { const k = (3 - i) / 3; y += 0.5 * k; z1 -= 0.14 * k; w -= 0.05 * k }
    return [y, j(w, .08), z0, j(z1, .12)]
  })
  const side = (a, b, sgn, mat) => {
    const x = (w) => sgn * w
    const A = [x(a[1]), a[0], a[2]], B = [x(b[1]), b[0], b[2]], C = [x(b[1]), b[0], b[3]], D = [x(a[1]), a[0], a[3]]
    if (sgn > 0) m.quad(mat, A, B, C, D); else m.quad(mat, B, A, D, C)
  }
  for (let i = 0; i + 1 < body.length; i++) {
    const a = body[i], b = body[i + 1]
    side(a, b, 1, paint); side(a, b, -1, paint)
    m.quad(paint, [-a[1], a[0], a[3]], [a[1], a[0], a[3]], [b[1], b[0], b[3]], [-b[1], b[0], b[3]])          // hood / boot
    m.quad('ff_under', [a[1], a[0], a[2]], [-a[1], a[0], a[2]], [-b[1], b[0], b[2]], [b[1], b[0], b[2]])
  }
  // the two ends
  const f = body[0], r = body[body.length - 1]
  m.quad(paint, [-f[1], f[0], f[2]], [f[1], f[0], f[2]], [f[1], f[0], f[3]], [-f[1], f[0], f[3]])
  m.quad(paint, [r[1], r[0], r[2]], [-r[1], r[0], r[2]], [-r[1], r[0], r[3]], [r[1], r[0], r[3]])
  // the greenhouse
  const g = s.glass.map(([y, w, z0, z1]) => [wreck ? y + (y < 0 ? .12 : 0) : y, j(w, .05), z0, j(z1, .1)])
  const glassMat = wreck ? 'ff_glass_broken' : 'ff_glass'
  for (let i = 0; i + 1 < g.length; i++) {
    const a = g[i], b = g[i + 1], roof = i === 1
    side(a, b, 1, glassMat); side(a, b, -1, glassMat)
    m.quad(roof ? paint : glassMat, [-a[1], a[0], a[3]], [a[1], a[0], a[3]], [b[1], b[0], b[3]], [-b[1], b[0], b[3]])
  }
  // pillars and the door lines (paint strips over the glass; a dark line down the door)
  const pillar = (y) => { for (const sg of [1, -1]) m.box(paint, sg > 0 ? g[1][1] - .02 : -g[1][1] - .02, y - .05, g[1][2], sg > 0 ? g[1][1] + .03 : -g[1][1] + .03, y + .05, g[1][3]) }
  pillar(g[1][0] + .03); pillar((g[1][0] + g[2][0]) / 2); pillar(g[2][0] - .03)
  const y0 = -s.wb / 2 - .05, y1 = s.wb / 2 + .05
  const wheels = [[.8, y0], [-.8, y0], [.8, y1], [-.8, y1]]
  wheels.forEach(([x, y], i) => {
    if (wreck && i === 1) return                                   // (one wheel gone: the wreck sits on its hub)
    m.wheel(x, y, wreck ? .29 : .32, .21)
    // the strap over the tyre, to the deck
    const r = .33, sx = x - .05, wx = x + .05
    m.box('ff_strap', sx, y - .03, r * 2 - .01, wx, y + .03, r * 2 + .02)
    m.box('ff_strap', sx, y - r - .05, 0, wx, y - r + .01, r * 1.5)
    m.box('ff_strap', sx, y + r - .01, 0, wx, y + r + .05, r * 1.5)
  })
  // the lights
  const lamp = (mat, x0, y0_, z0, x1, y1_, z1) => m.box(mat, x0, y0_, z0, x1, y1_, z1)
  if (!wreck) {
    const fy = body[0][0], ry = body[body.length - 1][0], fz = body[0][3], rz = body[body.length - 1][3]
    lamp('ff_lamp', -.68, fy - .02, fz - .16, -.36, fy + .05, fz - .03); lamp('ff_lamp', .36, fy - .02, fz - .16, .68, fy + .05, fz - .03)
    lamp('ff_rear', -.72, ry - .05, rz - .18, -.32, ry + .02, rz - .04); lamp('ff_rear', .32, ry - .05, rz - .18, .72, ry + .02, rz - .04)
  }
}

const MATS = {
  ff_paint_red: [.62, .07, .08, .3, .4], ff_paint_blue: [.06, .17, .46, .3, .4], ff_paint_silver: [.62, .63, .66, .3, .7],
  ff_paint_white: [.86, .86, .87, .35, .1], ff_paint_black: [.03, .03, .035, .3, .3], ff_paint_green: [.1, .3, .19, .35, .3],
  ff_rust_a: [.33, .17, .09, .9, .1], ff_rust_b: [.28, .27, .25, .85, .2], ff_rust_c: [.42, .36, .2, .85, .1],
  ff_glass: [.04, .06, .08, .08, .3], ff_glass_broken: [.02, .02, .02, .9, 0], ff_tire: [.025, .025, .025, .9, 0],
  ff_rim: [.55, .56, .58, .3, .8], ff_under: [.02, .02, .02, .9, 0], ff_lamp: [.92, .92, .86, .15, .3], ff_rear: [.6, .03, .03, .2, .2],
  ff_strap: [.92, .55, .05, .8, 0],
}
const CARS = {
  ff_new_a: ['sedan', 'ff_paint_silver'], ff_new_b: ['hatch', 'ff_paint_red'], ff_new_c: ['suv', 'ff_paint_blue'],
  ff_new_d: ['sedan', 'ff_paint_black'], ff_new_e: ['hatch', 'ff_paint_white'], ff_new_f: ['suv', 'ff_paint_green'],
  ff_wreck_a: ['sedan', 'ff_rust_a', true], ff_wreck_b: ['hatch', 'ff_rust_b', true], ff_wreck_c: ['suv', 'ff_rust_c', true],
}

const fmt = x => (Math.round(x * 10000) / 10000).toString()
function geometry(name, m) {
  const pos = [], nor = [], uv = [], tris = []
  let v = 0
  for (const mat of Object.keys(m.t)) {
    const ps = []
    for (const t of m.t[mat]) {
      for (const p of t.p) { pos.push(p.map(fmt).join(' ')); nor.push(t.n.map(fmt).join(' ')); uv.push(fmt(p[1] * .1) + ' ' + fmt(p[2] * .1)); ps.push(v, v, v); v++ }
    }
    tris.push(`<triangles material="${mat}-material" count="${m.t[mat].length}"><input semantic="VERTEX" source="#${name}-mesh-vertices" offset="0"/><input semantic="NORMAL" source="#${name}-mesh-normals" offset="1"/><input semantic="TEXCOORD" source="#${name}-mesh-map" offset="2" set="0"/><p>${ps.join(' ')}</p></triangles>`)
  }
  const src = (id, arr, stride, params) => `<source id="${id}"><float_array id="${id}-array" count="${arr.length * stride}">${arr.join(' ')}</float_array><technique_common><accessor source="#${id}-array" count="${arr.length}" stride="${stride}">${params.map(p => `<param name="${p}" type="float"/>`).join('')}</accessor></technique_common></source>`
  return `<geometry id="${name}-mesh" name="${name}"><mesh>${src(name + '-mesh-positions', pos, 3, ['X', 'Y', 'Z'])}${src(name + '-mesh-normals', nor, 3, ['X', 'Y', 'Z'])}${src(name + '-mesh-map', uv, 2, ['S', 'T'])}<vertices id="${name}-mesh-vertices"><input semantic="POSITION" source="#${name}-mesh-positions"/></vertices>${tris.join('')}</mesh></geometry>`
}
const geos = [], nodes = []
let triCount = 0
for (const [name, [shape, paint, wreck]] of Object.entries(CARS)) {
  const m = new Mesh()
  carInto(m, shape, paint, !!wreck)
  geos.push(geometry(name, m))
  Object.values(m.t).forEach(a => triCount += a.length)
  const bind = Object.keys(m.t).map(k => `<instance_material symbol="${k}-material" target="#${k}-material"><bind_vertex_input semantic="UVChannel_1" input_semantic="TEXCOORD" input_set="0"/></instance_material>`).join('')
  nodes.push(`<node id="${name}" name="${name}" type="NODE"><matrix sid="transform">1 0 0 0 0 1 0 0 0 0 1 0 0 0 0 1</matrix><instance_geometry url="#${name}-mesh" name="${name}"><bind_material><technique_common>${bind}</technique_common></bind_material></instance_geometry></node>`)
}
const fx = Object.keys(MATS).map(k => `<effect id="${k}-effect"><profile_COMMON><technique sid="common"><lambert><diffuse><color sid="diffuse">${MATS[k].slice(0, 3).join(' ')} 1</color></diffuse></lambert></technique></profile_COMMON></effect>`).join('')
const lib = Object.keys(MATS).map(k => `<material id="${k}-material" name="${k}"><instance_effect url="#${k}-effect"/></material>`).join('')
fs.writeFileSync(path.join(out, 'ff_cars.dae'), `<?xml version="1.0" encoding="utf-8"?>
<COLLADA xmlns="http://www.collada.org/2005/11/COLLADASchema" version="1.4.1">
<asset><unit name="meter" meter="1"/><up_axis>Z_UP</up_axis></asset>
<library_effects>${fx}</library_effects>
<library_materials>${lib}</library_materials>
<library_geometries>${geos.join('\n')}</library_geometries>
<library_visual_scenes><visual_scene id="Scene" name="Scene">${nodes.join('\n')}</visual_scene></library_visual_scenes>
<scene><instance_visual_scene url="#Scene"/></scene>
</COLLADA>
`)

// the materials
const matJson = {}
for (const [k, [r, g, b, rough, metal]] of Object.entries(MATS)) {
  matJson[k] = { name: k, mapTo: k, class: 'Material', version: 1.5, Stages: [{ baseColorFactor: [r, g, b, 1], roughnessFactor: rough, metallicFactor: metal }, {}, {}, {}],
    ...(k === 'ff_lamp' || k === 'ff_rear' ? {} : {}) }
}
fs.writeFileSync(path.join(out, 'ff_cars.materials.json'), JSON.stringify(matJson, null, 2))

// the parts: three cars on the deck (z 1.319; y from -2.29 to 11.31, the front is -y). Each car is a small rigid body of
// its own (8 nodes), tied down to the deck: its straps are a break group, so when the load is lost (career.lua: not
// secured, driven too hard) the car really comes off the trailer.
const DECK_Z = 1.319, Y = [0.1, 4.55, 9.0]
const STATION = [-2.287, -0.55, 0.9, 2.06, 3.618, 5.094, 6.7, 8.179, 9.626, 11.309]     // fb1..fb10 (l/r)
function nearestStations(y) { return STATION.map((s, i) => [Math.abs(s - y), i + 1]).sort((a, b) => a[0] - b[0]).slice(0, 2).map(a => a[1]) }
function pod(i, kg) {
  const y = Y[i], ids = [], nodes = [], beams = [], straps = []
  const X = [0.7, -0.7], DY = [-1.7, 1.7], Z = [DECK_Z + 0.05, DECK_Z + 1.0]
  const name = (a, b, c) => `ff${i}${a ? 'r' : 'l'}${b ? 'b' : 'f'}${c ? 't' : 'u'}`
  for (const c of [0, 1]) for (const b of [0, 1]) for (const a of [0, 1]) {
    const id = name(a, b, c); ids.push(id)
    nodes.push(`["${id}", ${X[a]}, ${(y + DY[b]).toFixed(3)}, ${Z[c].toFixed(3)}],`)
  }
  for (let m = 0; m < ids.length; m++) for (let n = m + 1; n < ids.length; n++) beams.push(`["${ids[m]}", "${ids[n]}"],`)
  for (const b of [0, 1]) for (const a of [0, 1]) {
    const id = name(a, b, 0), side = a ? 'r' : 'l', other = a ? 'l' : 'r'
    const [s1, s2] = nearestStations(y + DY[b])
    for (const n of [`fb${s1}${side}`, `fb${s2}${side}`, `fb${s1}${other}`, `fb${s1 + 10}${side}`]) straps.push(`["${id}", "${n}"],`)
  }
  return { nodes, beams, straps, group: `ff_car${i}`, weight: Math.round(kg / 8) }
}
const part = (key, name, cars, kg) => {
  const pods = cars.map((_, i) => pod(i, kg / 3))
  const flex = cars.map((n, i) => `["${n}", ["${pods[i].group}"], [], {"pos":{"x":0,"y":${Y[i]},"z":${DECK_Z}}, "rot":{"x":0,"y":0,"z":0}, "scale":{"x":1,"y":1,"z":1}}],`).join('\n      ')
  const nodeBlock = pods.map(p => `{"group": "${p.group}"}, {"nodeWeight": ${p.weight}},\n      ${p.nodes.join('\n      ')}`).join('\n      ')
  const beamBlock = pods.map(p => p.beams.join('\n      ')).join('\n      ')
  const strapBlock = pods.map((p, i) => `{"breakGroup": "ff_strap_${i}"},\n      ${p.straps.join('\n      ')}`).join('\n      ')
  return `  "${key}": {
    "information": { "authors": "Trucks of Earth", "name": "${name}", "value": 0 },
    "slotType": "euTr_platform_load",
    "flexbodies": [
      ["mesh", "[group]:", "nonFlexMaterials"],
      ${flex}
    ],
    "nodes": [
      ["id", "posX", "posY", "posZ"],
      {"collision": true}, {"selfCollision": true}, {"frictionCoef": 0.5},
      ${nodeBlock}
      {"group": ""}, {"nodeWeight": 25}
    ],
    "beams": [
      ["id1:", "id2:"],
      {"beamType": "|NORMAL", "beamLongBound": 1.0, "beamShortBound": 1.0, "beamPrecompression": 1},
      {"beamSpring": 8001000, "beamDamp": 4000},
      {"beamDeform": "FLT_MAX", "beamStrength": "FLT_MAX"},
      {"breakGroup": ""},
      ${beamBlock}
      {"beamSpring": 4001000, "beamDamp": 4000},
      {"beamDeform": 900000, "beamStrength": 1400000},
      ${strapBlock}
      {"breakGroup": ""}
    ],
  }`
}
fs.writeFileSync(path.join(out, 'ff_cars.jbeam'), `// Trucks of Earth: the car transporter's load on the EU flatbed semi trailer (tools/build_cars.js)\n{\n${part('euTr_platform_load_ff_newcars', 'Drei Neuwagen', ['ff_new_a', 'ff_new_c', 'ff_new_b'], 4500)},\n${part('euTr_platform_load_ff_newcars2', 'Drei Neuwagen (b)', ['ff_new_f', 'ff_new_e', 'ff_new_d'], 4500)},\n${part('euTr_platform_load_ff_wrecks', 'Drei Autowracks', ['ff_wreck_a', 'ff_wreck_c', 'ff_wreck_b'], 3300)},\n}\n`)
console.log('cars:', Object.keys(CARS).length, 'triangles', triCount)