// The cab props of fernfahrer/vices.lua as COLLADA shapes + their materials: a beer can, a cigarette, a joint, a
// lighter and its flame. Simple lathed meshes in metres, Z up, built here (no textures: colours by material).
// node tools/build_props.js <out dir>   (â†’ <out>/ff_*.dae, <out>/props.materials.json)
const fs = require('fs'), path = require('path')
const out = process.argv[2]
if (!out) { console.log('usage: node build_props.js <out dir>'); process.exit(1) }
fs.mkdirSync(out, { recursive: true })

const SEG = 20
// a mesh: per material a list of triangles (each vertex [x,y,z], normal [x,y,z])
function Mesh() { this.tris = {} }
Mesh.prototype.tri = function (mat, a, b, c, na, nb, nc) {
  if (!na) {
    const u = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], v = [c[0] - a[0], c[1] - a[1], c[2] - a[2]]
    const n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]
    const l = Math.hypot(...n) || 1
    na = nb = nc = n.map(x => x / l)
  }
  (this.tris[mat] = this.tris[mat] || []).push([a, na], [b, nb], [c, nc])
}
// a lathed band around the axis `ax` ('y' or 'z'): from (r0 at h0) to (r1 at h1)
Mesh.prototype.band = function (mat, ax, h0, r0, h1, r1) {
  const P = (r, h, t) => ax === 'z' ? [r * Math.cos(t), r * Math.sin(t), h] : [r * Math.cos(t), h, r * Math.sin(t)]
  const slope = (r0 - r1) / ((h1 - h0) || 1e-6)
  const N = t => {
    const n = ax === 'z' ? [Math.cos(t), Math.sin(t), slope] : [Math.cos(t), slope, Math.sin(t)]
    const l = Math.hypot(...n); return n.map(x => x / l)
  }
  for (let i = 0; i < SEG; i++) {
    const t0 = i / SEG * Math.PI * 2, t1 = (i + 1) / SEG * Math.PI * 2
    const a = P(r0, h0, t0), b = P(r0, h0, t1), c = P(r1, h1, t1), d = P(r1, h1, t0)
    // outward winding (counter-clockwise seen from outside)
    if (ax === 'z') { this.tri(mat, a, b, c, N(t0), N(t1), N(t1)); this.tri(mat, a, c, d, N(t0), N(t1), N(t0)) }
    else { this.tri(mat, a, c, b, N(t0), N(t1), N(t1)); this.tri(mat, a, d, c, N(t0), N(t0), N(t1)) }
  }
}
// a disc closing the lathe at height h (facing +axis when up, else -axis)
Mesh.prototype.disc = function (mat, ax, h, r, up) {
  const P = t => ax === 'z' ? [r * Math.cos(t), r * Math.sin(t), h] : [r * Math.cos(t), h, r * Math.sin(t)]
  const c = ax === 'z' ? [0, 0, h] : [0, h, 0]
  for (let i = 0; i < SEG; i++) {
    const a = P(i / SEG * Math.PI * 2), b = P((i + 1) / SEG * Math.PI * 2)
    const ccwZ = up === (ax === 'z')
    if (ccwZ) this.tri(mat, c, a, b); else this.tri(mat, c, b, a)
  }
}
Mesh.prototype.box = function (mat, x0, y0, z0, x1, y1, z1) {
  const v = (x, y, z) => [x ? x1 : x0, y ? y1 : y0, z ? z1 : z0]
  const q = (a, b, c, d) => { this.tri(mat, a, b, c); this.tri(mat, a, c, d) }
  q(v(0, 0, 0), v(0, 1, 0), v(1, 1, 0), v(1, 0, 0)) // bottom
  q(v(0, 0, 1), v(1, 0, 1), v(1, 1, 1), v(0, 1, 1)) // top
  q(v(0, 0, 0), v(1, 0, 0), v(1, 0, 1), v(0, 0, 1)) // -y
  q(v(0, 1, 0), v(0, 1, 1), v(1, 1, 1), v(1, 1, 0)) // +y
  q(v(0, 0, 0), v(0, 0, 1), v(0, 1, 1), v(0, 1, 0)) // -x
  q(v(1, 0, 0), v(1, 1, 0), v(1, 1, 1), v(1, 0, 1)) // +x
}

const f = x => (Math.abs(x) < 1e-9 ? 0 : +x.toFixed(6))
function dae(name, mesh) {
  const mats = Object.keys(mesh.tris)
  const g = name + '2-g'
  const verts = [], norms = []
  const tris = mats.map(m => {
    const idx = []
    for (const [p, n] of mesh.tris[m]) { idx.push(verts.length); verts.push(p); norms.push(n) }
    return { m, idx }
  })
  const flat = a => a.map(p => p.map(f).join(' ')).join(' ')
  return `<?xml version="1.0" encoding="utf-8"?>
<COLLADA xmlns="http://www.collada.org/2005/11/COLLADASchema" version="1.4.1">
<asset><contributor><authoring_tool>fernfahrer_karriere tools/build_props.js</authoring_tool></contributor>
<unit meter="1" name="meter"/><up_axis>Z_UP</up_axis></asset>
<library_effects>
${mats.map(m => `<effect id="${m}-fx"><profile_COMMON><technique sid="common"><lambert><diffuse><color>0.8 0.8 0.8 1</color></diffuse></lambert></technique></profile_COMMON></effect>`).join('\n')}
</library_effects>
<library_materials>
${mats.map(m => `<material id="${m}-mat" name="${m}"><instance_effect url="#${m}-fx"/></material>`).join('\n')}
</library_materials>
<library_geometries>
<geometry id="${g}"><mesh>
<source id="${g}-p"><float_array id="${g}-p-a" count="${verts.length * 3}">${flat(verts)}</float_array><technique_common><accessor source="#${g}-p-a" count="${verts.length}" stride="3"><param name="X" type="float"/><param name="Y" type="float"/><param name="Z" type="float"/></accessor></technique_common></source>
<source id="${g}-n"><float_array id="${g}-n-a" count="${norms.length * 3}">${flat(norms)}</float_array><technique_common><accessor source="#${g}-n-a" count="${norms.length}" stride="3"><param name="X" type="float"/><param name="Y" type="float"/><param name="Z" type="float"/></accessor></technique_common></source>
<source id="${g}-uv"><float_array id="${g}-uv-a" count="${verts.length * 2}">${verts.map(() => '0 0').join(' ')}</float_array><technique_common><accessor source="#${g}-uv-a" count="${verts.length}" stride="2"><param name="S" type="float"/><param name="T" type="float"/></accessor></technique_common></source>
<vertices id="${g}-v"><input semantic="POSITION" source="#${g}-p"/></vertices>
${tris.map(t => `<triangles count="${t.idx.length / 3}" material="${t.m}-mat"><input semantic="VERTEX" source="#${g}-v" offset="0"/><input semantic="NORMAL" source="#${g}-n" offset="0"/><input semantic="TEXCOORD" source="#${g}-uv" offset="0" set="0"/><p>${t.idx.join(' ')}</p></triangles>`).join('\n')}
</mesh></geometry>
</library_geometries>
<library_visual_scenes><visual_scene id="scene" name="scene">
<node id="base00" name="base00"><node id="start01" name="start01">
<node id="${name}2" name="${name}2"><instance_geometry url="#${g}"><bind_material><technique_common>${mats.map(m => `<instance_material symbol="${m}-mat" target="#${m}-mat"/>`).join('')}</technique_common></bind_material></instance_geometry></node>
</node></node>
</visual_scene></library_visual_scenes>
<scene><instance_visual_scene url="#scene"/></scene>
</COLLADA>
`
}

// --- the shapes ---------------------------------------------------------------------------------------------------
const shapes = {}
{ // beer can 0.33 l: origin at the bottom centre, up +z
  const m = new Mesh(), R = 0.033
  m.disc('ff_can_metal', 'z', 0, 0.026, false)
  m.band('ff_can_metal', 'z', 0, 0.026, 0.008, R)
  m.band('ff_can_green', 'z', 0.008, R, 0.104, R)
  m.band('ff_can_label', 'z', 0.04, R + 0.0004, 0.07, R + 0.0004)  // (a gold band round the middle)
  m.band('ff_can_metal', 'z', 0.104, R, 0.114, 0.027)
  m.band('ff_can_metal', 'z', 0.114, 0.027, 0.116, 0.027)
  m.disc('ff_can_metal', 'z', 0.1155, 0.027, true)
  m.box('ff_can_tab', -0.006, -0.004, 0.1155, 0.006, 0.016, 0.1175)     // the ring pull
  m.box('ff_can_hole', -0.005, -0.019, 0.1157, 0.005, -0.006, 0.1162)   // the opening (dark)
  shapes.ff_beer = m
}
{ // cigarette: along +y from the mouth end (origin), 8.4 cm
  const m = new Mesh(), R = 0.0042
  m.disc('ff_cig_filter', 'y', 0, R, false)
  m.band('ff_cig_filter', 'y', 0, R, 0.022, R)
  m.band('ff_cig_paper', 'y', 0.022, R, 0.082, R)
  m.band('ff_ember', 'y', 0.082, R, 0.084, R * 0.92)
  m.disc('ff_ember', 'y', 0.084, R * 0.92, true)
  shapes.ff_cigarette = m
}
{ // joint: a cardboard tip, then the paper widening to the twisted end
  const m = new Mesh()
  m.disc('ff_joint_crutch', 'y', 0, 0.0036, false)
  m.band('ff_joint_crutch', 'y', 0, 0.0036, 0.016, 0.0038)
  m.band('ff_joint_paper', 'y', 0.016, 0.0038, 0.09, 0.0072)
  m.band('ff_joint_paper', 'y', 0.09, 0.0072, 0.096, 0.0062)
  m.band('ff_ember', 'y', 0.096, 0.0062, 0.098, 0.0055)
  m.disc('ff_ember', 'y', 0.098, 0.0055, true)
  shapes.ff_joint = m
}
{ // lighter: origin at the bottom centre, up +z
  const m = new Mesh()
  m.box('ff_lighter_red', -0.012, -0.006, 0, 0.012, 0.006, 0.062)
  m.box('ff_can_metal', -0.012, -0.0062, 0.062, 0.012, 0.0062, 0.074)
  m.box('ff_lighter_black', 0.004, -0.004, 0.074, 0.011, 0.004, 0.079)    // the wheel
  shapes.ff_lighter = m
}
{ // flame: origin at its foot, up +z
  const m = new Mesh()
  m.band('ff_flame', 'z', 0, 0.0015, 0.008, 0.0048)
  m.band('ff_flame', 'z', 0.008, 0.0048, 0.026, 0.0002)
  m.disc('ff_flame_blue', 'z', 0, 0.0015, false)
  shapes.ff_flame = m
}
// the stop rings (fernfahrer/stops.lua): a dashed glowing ring on the ground (radius 6 m) and a floating marker, one
// colour per kind of place
const RING_COLORS = { green: [0.2, 1, 0.45], orange: [1, 0.6, 0.12], red: [1, 0.25, 0.2], blue: [0.3, 0.6, 1],
  violet: [0.7, 0.4, 1], yellow: [1, 0.85, 0.2], cyan: [0.2, 0.9, 0.95] }
// road events (events.lua): a warning triangle on its stand (origin on the ground, the face towards -y: the traffic
// coming along +y sees it), a wooden crate and a pallet with cartons (lost cargo)
{
  const m = new Mesh(), H = 0.62, W = 0.7, T = 0.05
  const a = [-W / 2, 0, 0.08], b = [W / 2, 0, 0.08], c = [0, 0, 0.08 + H]
  // the red frame: three bars, front and back faces (two-sided by repeating reversed)
  const bar = (p, q) => {
    const d = [q[0] - p[0], 0, q[2] - p[2]], l = Math.hypot(d[0], d[2]), n = [-d[2] / l * T * 1.6, 0, d[0] / l * T * 1.6]
    const p1 = [p[0] + n[0], -0.01, p[2] + n[2]], q1 = [q[0] + n[0], -0.01, q[2] + n[2]]
    m.tri('ff_tri_red', p, q, q1); m.tri('ff_tri_red', p, q1, p1)
    m.tri('ff_tri_red', p, q1, q); m.tri('ff_tri_red', p, p1, q1)
  }
  bar(a, b); bar(b, c); bar(c, a)
  // the white face inside, and the stand behind
  const s = 0.6, ca = [a[0] * s, -0.005, 0.08 + 0.12], cb = [b[0] * s, -0.005, 0.08 + 0.12], cc = [0, -0.005, 0.08 + H * 0.78]
  m.tri('ff_tri_white', ca, cb, cc); m.tri('ff_tri_white', ca, cc, cb)
  m.box('ff_tri_metal', -0.3, 0, 0, 0.3, 0.35, 0.03)
  shapes.ff_triangle = m
}
{
  const m = new Mesh()
  m.box('ff_crate_wood', -0.55, -0.4, 0, 0.55, 0.4, 0.7)
  m.box('ff_crate_strap', -0.56, -0.08, -0.001, 0.56, 0.08, 0.701)
  shapes.ff_crate = m
  const p = new Mesh()
  p.box('ff_crate_wood', -0.6, -0.4, 0, 0.6, 0.4, 0.14)
  p.box('ff_carton', -0.55, -0.35, 0.14, 0.55, 0.35, 0.9)
  p.box('ff_carton', -0.3, -0.2, 0.9, 0.25, 0.25, 1.2)
  shapes.ff_pallet = p
}
// (2026-11-05, redesigned: a crisp solid rim, a softly lit floor, a light wall fading upwards, four chevrons pointing in;
// the marker with a thin beam of light down to the ring – all one colour per kind of place)
const RN = 72
const P3 = (r, a, z) => [r * Math.cos(a), r * Math.sin(a), z]
// a flat annulus from r0 to r1 at height z (both faces)
function annulus(m, mat, r0, r1, z, n = RN) {
  for (let i = 0; i < n; i++) {
    const a0 = i / n * Math.PI * 2, a1 = (i + 1) / n * Math.PI * 2
    m.tri(mat, P3(r0, a0, z), P3(r1, a0, z), P3(r1, a1, z)); m.tri(mat, P3(r0, a0, z), P3(r1, a1, z), P3(r0, a1, z))
  }
}
// a vertical wall of radius r from z0 to z1 (both faces: seen from inside and out)
function wall(m, mat, r, z0, z1, n = RN) {
  for (let i = 0; i < n; i++) {
    const a0 = i / n * Math.PI * 2, a1 = (i + 1) / n * Math.PI * 2
    const A = P3(r, a0, z0), B = P3(r, a1, z0), C = P3(r, a1, z1), D = P3(r, a0, z1)
    m.tri(mat, A, B, C); m.tri(mat, A, C, D); m.tri(mat, A, C, B); m.tri(mat, A, D, C)
  }
}
for (const c of Object.keys(RING_COLORS)) {
  const m = new Mesh(), rim = 'ff_ring_' + c, floor = 'ff_ringfloor_' + c, glowLo = 'ff_ringwall_' + c, glowHi = 'ff_ringwallhi_' + c
  annulus(m, rim, 5.85, 6.15, 0.07)               // the rim
  annulus(m, rim, 5.2, 5.28, 0.065)               // a thin inner line
  annulus(m, floor, 0.0, 5.85, 0.05, 48)          // the floor, lit faintly
  wall(m, glowLo, 6.0, 0.07, 0.45)                // the light wall: brighter low down …
  wall(m, glowHi, 6.0, 0.45, 1.25)                // … fading out above
  // four chevrons on the floor, pointing to the middle
  for (let k = 0; k < 4; k++) {
    const a = k * Math.PI / 2, ca = Math.cos(a), sa = Math.sin(a)
    const R = (x, y) => [x * ca - y * sa, x * sa + y * ca, 0.075]
    const tip = R(3.7, 0), l = R(4.6, 0.75), r = R(4.6, -0.75), li = R(4.25, 0.75), ri = R(4.25, -0.75), mid = R(3.35, 0)
    // a "V" pointing inwards: two thick strokes
    m.tri(rim, tip, l, li); m.tri(rim, tip, li, mid); m.tri(rim, tip, ri, r); m.tri(rim, tip, mid, ri)
    m.tri(rim, tip, li, l); m.tri(rim, tip, mid, li); m.tri(rim, tip, r, ri); m.tri(rim, tip, ri, mid)
  }
  shapes['ff_ring_' + c] = m
  // the marker: a faceted diamond (centre at the origin) and a beam of light from it to the ground
  const g = new Mesh(), top = [0, 0, 0.62], bot = [0, 0, -0.62], r = 0.38, F = 6
  const eq = [...Array(F).keys()].map(i => [r * Math.cos(i * Math.PI * 2 / F), r * Math.sin(i * Math.PI * 2 / F), 0])
  for (let i = 0; i < F; i++) {
    const a = eq[i], b = eq[(i + 1) % F]
    g.tri(rim, a, b, top); g.tri(rim, b, a, bot)
  }
  wall(g, glowHi, 0.07, -3.4, -0.6, 10)
  shapes['ff_gem_' + c] = g
}
for (const [n, m] of Object.entries(shapes)) fs.writeFileSync(path.join(out, n + '.dae'), dae(n, m))

// --- the materials ------------------------------------------------------------------------------------------------
const MAT = {
  ff_can_green: { c: [0.03, 0.26, 0.09], rough: 0.3, metal: 0.7 },
  ff_can_label: { c: [0.78, 0.6, 0.18], rough: 0.35, metal: 0.8 },
  ff_can_metal: { c: [0.72, 0.74, 0.76], rough: 0.3, metal: 0.9 },
  ff_can_tab: { c: [0.8, 0.82, 0.84], rough: 0.25, metal: 0.95 },
  ff_can_hole: { c: [0.03, 0.03, 0.03], rough: 0.8, metal: 0 },
  ff_cig_filter: { c: [0.78, 0.47, 0.18], rough: 0.7, metal: 0 },
  ff_cig_paper: { c: [0.93, 0.93, 0.9], rough: 0.8, metal: 0 },
  ff_joint_crutch: { c: [0.72, 0.62, 0.45], rough: 0.85, metal: 0 },
  ff_joint_paper: { c: [0.9, 0.87, 0.78], rough: 0.85, metal: 0 },
  ff_ember: { c: [0.9, 0.22, 0.03], rough: 0.9, metal: 0, glow: [1.0, 0.3, 0.05] },
  ff_lighter_red: { c: [0.6, 0.04, 0.05], rough: 0.4, metal: 0 },
  ff_lighter_black: { c: [0.05, 0.05, 0.05], rough: 0.5, metal: 0.4 },
  ff_flame: { c: [1.0, 0.62, 0.15], rough: 1, metal: 0, glow: [1.0, 0.55, 0.12] },
  ff_flame_blue: { c: [0.2, 0.35, 1.0], rough: 1, metal: 0, glow: [0.25, 0.4, 1.0] },
}
for (const [c, col] of Object.entries(RING_COLORS)) {
  MAT['ff_ring_' + c] = { c: col, rough: 0.6, metal: 0, glow: col }
  // (see-through, added light: the floor faint, the wall bright at the bottom and fading out above)
  MAT['ff_ringfloor_' + c] = { c: col, rough: 1, metal: 0, glow: col.map(x => x * 0.5), alpha: 0.13, add: true }
  MAT['ff_ringwall_' + c] = { c: col, rough: 1, metal: 0, glow: col, alpha: 0.42, add: true }
  MAT['ff_ringwallhi_' + c] = { c: col, rough: 1, metal: 0, glow: col.map(x => x * 0.7), alpha: 0.14, add: true }
}
Object.assign(MAT, {
  ff_tri_red: { c: [0.85, 0.05, 0.05], rough: 0.3, metal: 0, glow: [0.35, 0.02, 0.02] },
  ff_tri_white: { c: [0.92, 0.92, 0.9], rough: 0.6, metal: 0 },
  ff_tri_metal: { c: [0.3, 0.32, 0.34], rough: 0.5, metal: 0.7 },
  ff_crate_wood: { c: [0.56, 0.42, 0.26], rough: 0.9, metal: 0 },
  ff_crate_strap: { c: [0.15, 0.25, 0.6], rough: 0.5, metal: 0.3 },
  ff_carton: { c: [0.68, 0.52, 0.33], rough: 0.95, metal: 0 },
})
const mats = {}
for (const [n, d] of Object.entries(MAT)) {
  const st = { baseColorFactor: [...d.c, d.alpha !== undefined ? d.alpha : 1], roughnessFactor: d.rough, metallicFactor: d.metal }
  if (d.glow) { st.emissiveFactor = d.glow; st.glow = true }
  if (d.alpha !== undefined) st.opacityFactor = d.alpha
  mats[n] = { name: n, mapTo: n, class: 'Material', version: 1.5, Stages: [st, {}, {}, {}], castShadows: false }
  if (d.alpha !== undefined) Object.assign(mats[n], { translucent: true, translucentBlendOp: d.add ? 'AddAlpha' : 'LerpAlpha', translucentZWrite: false, doubleSided: true })
}
fs.writeFileSync(path.join(out, 'props.materials.json'), JSON.stringify(mats, null, 2))
console.log('props:', Object.keys(shapes).join(', '), 'â†’', out)
