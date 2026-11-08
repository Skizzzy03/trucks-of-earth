// The company yard of fernfahrer/yard.lua as one COLLADA shape + its materials: a concrete yard 48 x 48 m with a ramp
// up from the road, a fence with the gate open, a hall the truck and its trailer drive into (18 x 26 m, open front,
// 5.6 m clear), an office building with windows, door and a pitched roof, truck bays, lamps, a container, pallets.
// Local frame (as the yard is placed): origin at the middle of the yard's front edge on its top surface, +x along the
// road, +y into the yard, +z up; metres. Everything is drawn and collides (TSStatic "Visible Mesh").
// node tools/build_yard.js <out dir>   (→ <out>/ff_yard.dae, <out>/yard.materials.json)
const fs = require('fs'), path = require('path')
const out = process.argv[2]
if (!out) { console.log('usage: node build_yard.js <out dir>'); process.exit(1) }
fs.mkdirSync(out, { recursive: true })

const tris = {}
function tri(mat, a, b, c) {
  const u = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], v = [c[0] - a[0], c[1] - a[1], c[2] - a[2]]
  const n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]
  const l = Math.hypot(...n) || 1
  ;(tris[mat] = tris[mat] || []).push([a, b, c, n.map(x => x / l)])
}
const quad = (mat, a, b, c, d) => { tri(mat, a, b, c); tri(mat, a, c, d) }    // (counter-clockwise from outside)
// an axis-aligned box, all six faces outward
function box(mat, x0, y0, z0, x1, y1, z1, opts = {}) {
  const v = (x, y, z) => [x ? x1 : x0, y ? y1 : y0, z ? z1 : z0]
  if (!opts.noBottom) quad(mat, v(0, 0, 0), v(0, 1, 0), v(1, 1, 0), v(1, 0, 0))
  quad(opts.top || mat, v(0, 0, 1), v(1, 0, 1), v(1, 1, 1), v(0, 1, 1))
  quad(mat, v(0, 0, 0), v(1, 0, 0), v(1, 0, 1), v(0, 0, 1))
  quad(mat, v(0, 1, 0), v(0, 1, 1), v(1, 1, 1), v(1, 1, 0))
  quad(mat, v(0, 0, 0), v(0, 0, 1), v(0, 1, 1), v(0, 1, 0))
  quad(mat, v(1, 0, 0), v(1, 1, 0), v(1, 1, 1), v(1, 0, 1))
}

// --- the yard surface: concrete, a skirt down into the ground, a ramp up from the road ---------------------------
const W = 24, D = 48
box('ff_yard_concrete', -W, 0, -3, W, D, 0, { noBottom: true })
// the ramp in front (the yard may stand a little above the road side): down to 1.4 m below over 5 m
quad('ff_yard_concrete', [-W, -5, -1.4], [W, -5, -1.4], [W, 0, 0], [-W, 0, 0])
tri('ff_yard_concrete', [-W, -5, -1.4], [-W, 0, 0], [-W, 0, -1.4]); tri('ff_yard_concrete', [W, -5, -1.4], [W, 0, -1.4], [W, 0, 0])
// joints in the concrete (thin dark lines every 6 m)
for (let x = -W + 6; x < W; x += 6) box('ff_yard_joint', x - 0.03, 0.2, 0, x + 0.03, D - 0.2, 0.008)
for (let y = 6; y < D; y += 6) box('ff_yard_joint', -W + 0.2, y - 0.03, 0, W - 0.2, y + 0.03, 0.008)

// --- the fence: posts every 4 m, three rails; the gate opening in front (x -9 .. 9), the sliding gate parked open --
function fenceRun(x0, y0, x1, y1) {
  const len = Math.hypot(x1 - x0, y1 - y0), n = Math.max(1, Math.round(len / 4))
  for (let i = 0; i <= n; i++) {
    const x = x0 + (x1 - x0) * i / n, y = y0 + (y1 - y0) * i / n
    box('ff_yard_fence', x - 0.06, y - 0.06, 0, x + 0.06, y + 0.06, 2.1)
  }
  const along = Math.abs(x1 - x0) > Math.abs(y1 - y0)
  for (const z of [0.25, 1.1, 1.95]) {
    if (along) box('ff_yard_fence', Math.min(x0, x1), y0 - 0.025, z - 0.04, Math.max(x0, x1), y0 + 0.025, z + 0.04)
    else box('ff_yard_fence', x0 - 0.025, Math.min(y0, y1), z - 0.04, x0 + 0.025, Math.max(y0, y1), z + 0.04)
  }
  // (the mesh between the rails: thin vertical bars every 0.5 m)
  const nb = Math.round(len / 0.5)
  for (let i = 1; i < nb; i++) {
    const x = x0 + (x1 - x0) * i / nb, y = y0 + (y1 - y0) * i / nb
    box('ff_yard_fence', x - 0.012, y - 0.012, 0.25, x + 0.012, y + 0.012, 1.95)
  }
}
const FY = 0.4
fenceRun(-W + 0.3, FY, -9, FY); fenceRun(9, FY, W - 0.3, FY)
fenceRun(-W + 0.3, FY, -W + 0.3, D - 0.3); fenceRun(W - 0.3, FY, W - 0.3, D - 0.3); fenceRun(-W + 0.3, D - 0.3, W - 0.3, D - 0.3)
// gate posts and the open sliding gate behind the right fence
box('ff_yard_post', -9.25, FY - 0.2, 0, -8.85, FY + 0.2, 2.6); box('ff_yard_post', 8.85, FY - 0.2, 0, 9.25, FY + 0.2, 2.6)
box('ff_yard_gate', 9.4, FY + 0.5, 0.15, 21, FY + 0.6, 0.3); box('ff_yard_gate', 9.4, FY + 0.5, 1.8, 21, FY + 0.6, 1.95)
for (let x = 9.5; x <= 21; x += 0.9) box('ff_yard_gate', x - 0.04, FY + 0.5, 0.15, x + 0.04, FY + 0.6, 1.95)

// --- the hall: x -22 .. -4, y 20 .. 46; open front; walls 6.5 m, ridge 8 m along y -------------------------------
const HX0 = -22, HX1 = -4, HY0 = 20, HY1 = 46, EAVE = 6.5, RIDGE = 8, T = 0.3
const HXM = (HX0 + HX1) / 2
box('ff_yard_wall', HX0, HY0, 0, HX0 + T, HY1, EAVE)               // left wall
box('ff_yard_wall', HX1 - T, HY0, 0, HX1, HY1, EAVE)               // right wall
box('ff_yard_wall', HX0, HY1 - T, 0, HX1, HY1, EAVE)               // back wall
box('ff_yard_wall', HX0, HY0, 5.6, HX1, HY0 + T, EAVE)             // the lintel over the open front
// the gables (front above the lintel, back)
for (const y of [HY0, HY1]) {
  const s = y === HY0 ? -1 : 1
  tri('ff_yard_wall', [HX0, y, EAVE], [HXM, y, RIDGE], [HX1, y, EAVE])
  tri('ff_yard_wall', [HX0, y, EAVE], [HX1, y, EAVE], [HXM, y, RIDGE])
  void s
}
// the roof (a little overhang), both sides of each plane
const OV = 0.6
function roofPlane(mat, a, b, c, d) { quad(mat, a, b, c, d); quad(mat, a, d, c, b) }
roofPlane('ff_yard_roof', [HX0 - OV, HY0 - OV, EAVE - 0.12], [HXM, HY0 - OV, RIDGE], [HXM, HY1 + OV, RIDGE], [HX0 - OV, HY1 + OV, EAVE - 0.12])
roofPlane('ff_yard_roof', [HXM, HY0 - OV, RIDGE], [HX1 + OV, HY0 - OV, EAVE - 0.12], [HX1 + OV, HY1 + OV, EAVE - 0.12], [HXM, HY1 + OV, RIDGE])
// the company stripe and a row of skylight windows on the side walls, the door frame posts
for (const x of [HX0 - 0.02, HX1 - T]) {
  box('ff_yard_stripe', x, HY0, 4.6, x + T + 0.02, HY1, 5.0)
  for (let y = HY0 + 1.5; y < HY1 - 2; y += 4) box('ff_yard_glass', x - 0.01, y, 3.2, x + T + 0.03, y + 2.6, 4.2)
}
box('ff_yard_stripe', HX0, HY0 - 0.05, 5.6, HX1, HY0 + 0.02, 6.0)
box('ff_yard_post', HX0, HY0, 0, HX0 + 0.5, HY0 + 0.5, 5.6); box('ff_yard_post', HX1 - 0.5, HY0, 0, HX1, HY0 + 0.5, 5.6)
// inside: a workbench and shelves along the back wall
box('ff_yard_metal', -20.5, 43, 0, -16, 45.5, 0.95); box('ff_yard_shelf', -14, 44.2, 0, -6, 45.6, 3.2)
for (const z of [0.9, 1.9, 2.9]) box('ff_yard_metal', -14, 44.1, z, -6, 45.7, z + 0.06)
// floor marking of the bay
box('ff_yard_line', HXM - 2.4, HY0 + 1, 0, HXM - 2.25, HY1 - 2, 0.01); box('ff_yard_line', HXM + 2.25, HY0 + 1, 0, HXM + 2.4, HY1 - 2, 0.01)

// --- the office: x 4 .. 18, y 30 .. 42; walls 3.4 m, ridge 6.2 m along x ------------------------------------------
const OX0 = 4, OX1 = 18, OY0 = 30, OY1 = 42, OH = 3.4, OR = 6.2, OYM = (OY0 + OY1) / 2
box('ff_yard_base', OX0 - 0.1, OY0 - 0.1, 0, OX1 + 0.1, OY1 + 0.1, 0.4)
box('ff_yard_house', OX0, OY0, 0.4, OX1, OY1, OH)
for (const x of [OX0, OX1]) { tri('ff_yard_house', [x, OY0, OH], [x, OYM, OR], [x, OY1, OH]); tri('ff_yard_house', [x, OY0, OH], [x, OY1, OH], [x, OYM, OR]) }
roofPlane('ff_yard_tiles', [OX0 - 0.5, OY0 - 0.6, OH - 0.15], [OX1 + 0.5, OY0 - 0.6, OH - 0.15], [OX1 + 0.5, OYM, OR], [OX0 - 0.5, OYM, OR])
roofPlane('ff_yard_tiles', [OX0 - 0.5, OYM, OR], [OX1 + 0.5, OYM, OR], [OX1 + 0.5, OY1 + 0.6, OH - 0.15], [OX0 - 0.5, OY1 + 0.6, OH - 0.15])
// windows (front and sides), the door with a canopy, the sign board, a chimney
for (const x of [5.2, 7.6, 13.8, 16.2]) {
  box('ff_yard_frame', x - 0.08, OY0 - 0.08, 1.12, x + 1.48, OY0 + 0.02, 2.48)
  box('ff_yard_glass', x, OY0 - 0.1, 1.2, x + 1.4, OY0 - 0.05, 2.4)
}
for (const y of [32, 36.5, 39.5]) for (const x of [OX0 - 0.1, OX1 + 0.05]) box('ff_yard_glass', x, y, 1.2, x + 0.05, y + 1.4, 2.4)
box('ff_yard_door', 10.4, OY0 - 0.08, 0.4, 11.6, OY0 + 0.02, 2.6)
box('ff_yard_metal', 9.8, OY0 - 1.4, 2.8, 12.2, OY0, 2.9)                                   // canopy
box('ff_yard_sign', 8.6, OY0 - 0.12, 2.95, 13.4, OY0 - 0.04, 3.3)                           // sign board
box('ff_yard_stripe', 8.6, OY0 - 0.14, 2.95, 13.4, OY0 - 0.1, 3.0)
box('ff_yard_base', 9.9, OY0 - 1.3, 0, 12.1, OY0, 0.4)                                       // step
box('ff_yard_brick', 15, 38, 4.5, 15.6, 38.6, 7)                                             // chimney

// --- truck bays (white lines), lamps, a container, pallet stacks ---------------------------------------------------
for (const x of [2, 7, 12, 17, 22]) box('ff_yard_line', x - 0.07, 4, 0, x + 0.07, 24, 0.012)
box('ff_yard_line', 2, 4, 0, 22, 4.14, 0.012)
for (const [x, y, arm] of [[-W + 1, 1.2, 1], [W - 1, 1.2, -1], [1, 27, 1], [-2.5, D - 1.2, 1]]) {
  box('ff_yard_metal', x - 0.1, y - 0.1, 0, x + 0.1, y + 0.1, 7)
  box('ff_yard_metal', Math.min(x, x + arm * 1.4), y - 0.06, 6.85, Math.max(x, x + arm * 1.4), y + 0.06, 7)
  box('ff_yard_lamp', x + arm * 1.4 - 0.35, y - 0.18, 6.7, x + arm * 1.4 + 0.35, y + 0.18, 6.85)
}
box('ff_yard_container', 19.8, 32, 0, 22.24, 38.06, 2.59)
for (let y = 32.3; y < 38; y += 0.5) box('ff_yard_container', 19.75, y, 0.1, 19.8, y + 0.2, 2.5)
for (const [x, y, h] of [[-2.6, 21, 3], [-1.2, 21, 2], [-2.6, 22, 1], [0, 26, 2]]) {
  for (let k = 0; k < h; k++) {
    const z = k * 1.1
    box('ff_yard_wood', x, y, z, x + 1.2, y + 0.8, z + 0.14)
    box('ff_yard_carton', x + 0.05, y + 0.05, z + 0.14, x + 1.15, y + 0.75, z + 1.05)
  }
}

// --- out --------------------------------------------------------------------------------------------------------------
// (the joints and the painted lines in a shape of their own that does not collide: their few millimetres of edge burst
// the tyres, 2026-11-03)
const DECO = { ff_yard_joint: 1, ff_yard_line: 1 }
const f = x => (Math.abs(x) < 1e-9 ? 0 : +x.toFixed(4))
// (2026-11-07) the game's own tileable textures (assets/materials/tileable, always mounted) on the big surfaces: a box
// mapping by the face's normal – metres per texture repeat per material
const TEX = {
  ff_yard_concrete: { d: '/assets/materials/tileable/concrete/Concrete_large/concrete_large_d.dds', n: '/assets/materials/tileable/concrete/Concrete_large/concrete_large_n.dds', s: 8 },
  ff_yard_base: { d: '/assets/materials/tileable/concrete/si_concrete/si_concrete_d.dds', n: '/assets/materials/tileable/concrete/si_concrete/si_concrete_n.dds', s: 2.5 },
  ff_yard_wall: { d: '/assets/materials/tileable/metal/moderncorrugated_tin/eca_bld_moderncorrugated_tin_d.dds', n: '/assets/materials/tileable/metal/moderncorrugated_tin/eca_bld_moderncorrugated_tin_n.dds', s: 3 },
  ff_yard_roof: { d: '/assets/materials/tileable/metal/ind_tin_03/ut_corrugated_tin_V3_d.dds', n: '/assets/materials/tileable/metal/ind_tin_03/ut_corrugated_tin_V3_n.dds', s: 3 },
  ff_yard_container: { d: '/assets/materials/tileable/metal/moderncorrugated_tin/eca_bld_moderncorrugated_tin_d.dds', n: '/assets/materials/tileable/metal/moderncorrugated_tin/eca_bld_moderncorrugated_tin_n.dds', s: 1.2 },
  ff_yard_house: { d: '/assets/materials/tileable/plaster/gas_station_01_wall_plaster_01/wall_plaster_01_d.dds', s: 3 },
  ff_yard_brick: { d: '/assets/materials/tileable/brick/eca_bld_bricks_dark/eca_bld_bricks_dark_d.dds', s: 1.5 },
}
function uvOf(p, n, m) {
  const s = (TEX[m] && TEX[m].s) || 1
  const ax = Math.abs(n[0]), ay = Math.abs(n[1]), az = Math.abs(n[2])
  if (az >= ax && az >= ay) return [p[0] / s, p[1] / s]
  if (ax >= ay) return [p[1] / s, p[2] / s]
  return [p[0] / s, p[2] / s]
}
function writeShape(name, mats) {
const g = name + '2-g'
const verts = [], norms = [], uvs = []
const groups = mats.map(m => {
  const idx = []
  for (const [a, b, c, n] of tris[m]) for (const p of [a, b, c]) { idx.push(verts.length); verts.push(p); norms.push(n); uvs.push(uvOf(p, n, m)) }
  return { m, idx }
})
const flat = a => a.map(p => p.map(f).join(' ')).join(' ')
const dae = `<?xml version="1.0" encoding="utf-8"?>
<COLLADA xmlns="http://www.collada.org/2005/11/COLLADASchema" version="1.4.1">
<asset><contributor><authoring_tool>fernfahrer_karriere tools/build_yard.js</authoring_tool></contributor>
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
<source id="${g}-uv"><float_array id="${g}-uv-a" count="${verts.length * 2}">${uvs.map(u => f(u[0]) + ' ' + f(u[1])).join(' ')}</float_array><technique_common><accessor source="#${g}-uv-a" count="${verts.length}" stride="2"><param name="S" type="float"/><param name="T" type="float"/></accessor></technique_common></source>
<vertices id="${g}-v"><input semantic="POSITION" source="#${g}-p"/></vertices>
${groups.map(t => `<triangles count="${t.idx.length / 3}" material="${t.m}-mat"><input semantic="VERTEX" source="#${g}-v" offset="0"/><input semantic="NORMAL" source="#${g}-n" offset="0"/><input semantic="TEXCOORD" source="#${g}-uv" offset="0" set="0"/><p>${t.idx.join(' ')}</p></triangles>`).join('\n')}
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
fs.writeFileSync(path.join(out, name + '.dae'), dae)
return verts.length / 3
}
const all = Object.keys(tris)
const nSolid = writeShape('ff_yard', all.filter(m => !DECO[m]))
const nDeco = writeShape('ff_yard_deco', all.filter(m => DECO[m]))

const MAT = {
  ff_yard_concrete: { c: [0.5, 0.5, 0.48], rough: 0.85 }, ff_yard_joint: { c: [0.24, 0.24, 0.23], rough: 0.9 },
  ff_yard_fence: { c: [0.12, 0.25, 0.16], rough: 0.5, metal: 0.4 }, ff_yard_post: { c: [0.3, 0.32, 0.34], rough: 0.5, metal: 0.6 },
  ff_yard_gate: { c: [0.55, 0.57, 0.6], rough: 0.4, metal: 0.8 },
  ff_yard_wall: { c: [0.72, 0.74, 0.75], rough: 0.5, metal: 0.3 }, ff_yard_roof: { c: [0.16, 0.18, 0.2], rough: 0.55, metal: 0.4 },
  ff_yard_stripe: { c: [0.96, 0.6, 0.1], rough: 0.5 }, ff_yard_glass: { c: [0.08, 0.13, 0.18], rough: 0.08, metal: 0.6 },
  ff_yard_metal: { c: [0.45, 0.47, 0.5], rough: 0.4, metal: 0.8 }, ff_yard_shelf: { c: [0.15, 0.3, 0.55], rough: 0.5, metal: 0.4 },
  ff_yard_line: { c: [0.92, 0.92, 0.88], rough: 0.7 }, ff_yard_base: { c: [0.38, 0.37, 0.35], rough: 0.9 },
  ff_yard_house: { c: [0.88, 0.84, 0.74], rough: 0.9 }, ff_yard_tiles: { c: [0.52, 0.16, 0.1], rough: 0.8 },
  ff_yard_frame: { c: [0.93, 0.93, 0.93], rough: 0.6 }, ff_yard_door: { c: [0.32, 0.2, 0.12], rough: 0.7 },
  ff_yard_sign: { c: [0.08, 0.1, 0.13], rough: 0.5 }, ff_yard_brick: { c: [0.45, 0.2, 0.14], rough: 0.9 },
  ff_yard_lamp: { c: [1, 0.92, 0.75], rough: 0.4, glow: [1, 0.85, 0.6] },
  ff_yard_container: { c: [0.55, 0.1, 0.08], rough: 0.6, metal: 0.5, tint: [0.75, 0.18, 0.14] }, ff_yard_wood: { c: [0.55, 0.42, 0.26], rough: 0.9 },
  ff_yard_carton: { c: [0.66, 0.5, 0.32], rough: 0.95 },
}
const mj = {}
for (const [n, d] of Object.entries(MAT)) {
  const s = { baseColorFactor: [...d.c, 1], roughnessFactor: d.rough, metallicFactor: d.metal || 0 }
  if (d.glow) { s.emissiveFactor = d.glow; s.glow = true }
  // (textured: the texture's own colour, lightly tinted – the colour factor multiplies it)
  const tx = TEX[n]
  if (tx) {
    s.baseColorMap = tx.d
    if (tx.n) s.normalMap = tx.n
    s.baseColorFactor = d.tint ? [...d.tint, 1] : [1, 1, 1, 1]
  }
  mj[n] = { name: n, mapTo: n, class: 'Material', version: 1.5, Stages: [s, {}, {}, {}], castShadows: true }
}
fs.writeFileSync(path.join(out, 'yard.materials.json'), JSON.stringify(mj, null, 2))
console.log('yard:', nSolid, 'triangles solid,', nDeco, 'decoration (no collision) →', out)
