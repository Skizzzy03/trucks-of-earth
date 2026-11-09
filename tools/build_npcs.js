// The people standing at the driver's door at a rest area (fernfahrer/encounters.lua), made from lofted rings: node build_npcs.js <mod folder>
// Writes levels/beamng_earth/art/shapes/ffa/ff_npc_<kind>.dae and npc.materials.json. +Y is the way they face.
const fs = require('fs'), path = require('path')
const dir = path.join(process.argv[2], 'levels/beamng_earth/art/shapes/ffa')
const SIDES = 12
let parts
function add(mat, a, b, c, na, nb, nc) { const m = parts[mat] = parts[mat] || { p: [], n: [] }; m.p.push(...a, ...b, ...c); m.n.push(...na, ...nb, ...nc) }
const norm = a => { const l = Math.hypot(...a) || 1; return [a[0] / l, a[1] / l, a[2] / l] }
function loft(mat, rings) {
  const ring = r => { const o = []; for (let i = 0; i < SIDES; i++) { const t = i / SIDES * 2 * Math.PI; o.push([r[0] + Math.cos(t) * r[3], r[1] + Math.sin(t) * r[4], r[2]]) } return o }
  const R = rings.map(ring)
  const out = (k, i) => norm([Math.cos(i / SIDES * 2 * Math.PI) / (rings[k][3] || 1), Math.sin(i / SIDES * 2 * Math.PI) / (rings[k][4] || 1), 0])
  for (let k = 0; k + 1 < R.length; k++) for (let i = 0; i < SIDES; i++) { const j = (i + 1) % SIDES; add(mat, R[k][i], R[k][j], R[k + 1][j], out(k, i), out(k, j), out(k + 1, j)); add(mat, R[k][i], R[k + 1][j], R[k + 1][i], out(k, i), out(k + 1, j), out(k + 1, i)) }
  const fan = (k, up) => { const r = rings[k], c = [r[0], r[1], r[2]], n = [0, 0, up]; for (let i = 0; i < SIDES; i++) { const j = (i + 1) % SIDES; up > 0 ? add(mat, c, R[k][i], R[k][j], n, n, n) : add(mat, c, R[k][j], R[k][i], n, n, n) } }
  fan(0, -1); fan(R.length - 1, 1)
}
const COL = { skin: [0.75, 0.53, 0.42], pale: [0.86, 0.66, 0.54], tan: [0.55, 0.36, 0.25], dark: [0.34, 0.2, 0.12], black: [0.02, 0.02, 0.024], charcoal: [0.06, 0.065, 0.08], jeans: [0.06, 0.1, 0.22], red: [0.34, 0.05, 0.04], teal: [0.08, 0.3, 0.27], olive: [0.18, 0.2, 0.09], green: [0.1, 0.28, 0.08], yellow: [0.82, 0.58, 0.04], grey: [0.26, 0.26, 0.24], blue: [0.05, 0.2, 0.32], silver: [0.7, 0.72, 0.76], brown: [0.2, 0.11, 0.05], blond: [0.48, 0.3, 0.12], rust: [0.5, 0.15, 0.06], white: [0.8, 0.8, 0.78] }
function person(o) {
  for (const s of [-1, 1]) {
    const x = s * 0.105
    loft(o.shoe || 'black', [[x, 0.04, 0, 0.055, 0.13], [x, 0.04, 0.05, 0.055, 0.125], [x, 0, 0.1, 0.055, 0.08]])
    loft(o.legs, [[x, 0, 0.08, 0.06, 0.07], [x, 0, 0.5, 0.068, 0.075], [x * 1.02, 0, 0.92, 0.095, 0.105]])
    loft(o.top, [[s * 0.255, 0.02, 1.08, 0.04, 0.045], [s * 0.27, 0.01, 1.3, 0.05, 0.055], [s * 0.225, 0, 1.47, 0.065, 0.07]])
    loft(o.top, [[s * 0.255, 0.03, 0.86, 0.035, 0.04], [s * 0.255, 0.02, 1.08, 0.042, 0.047]])
    loft(o.skin, [[s * 0.255, 0.035, 0.76, 0.035, 0.04], [s * 0.255, 0.03, 0.86, 0.036, 0.042]])
  }
  loft(o.top, [[0, 0, 0.9, 0.2, 0.14], [0, 0, 1.2, 0.2, 0.135], [0, 0, 1.42, 0.23, 0.135], [0, 0, 1.5, 0.15, 0.09]])
  if (o.band) loft(o.band, [[0, 0, 1.18, 0.207, 0.142], [0, 0, 1.24, 0.209, 0.144]])
  loft(o.skin, [[0, 0, 1.48, 0.06, 0.06], [0, 0, 1.57, 0.055, 0.055]])
  loft(o.skin, [[0, 0.01, 1.54, 0.05, 0.06], [0, 0.015, 1.6, 0.082, 0.098], [0, 0.015, 1.68, 0.09, 0.103], [0, 0.01, 1.74, 0.08, 0.09], [0, 0.005, 1.78, 0.045, 0.05]])
  loft(o.skin, [[0, 0.11, 1.635, 0.012, 0.014], [0, 0.125, 1.665, 0.012, 0.012], [0, 0.112, 1.69, 0.008, 0.006]])
  if (o.beard) loft(o.beard, [[0, 0.03, 1.545, 0.05, 0.06], [0, 0.03, 1.6, 0.088, 0.094], [0, 0.02, 1.635, 0.092, 0.095]])
  if (o.hair) loft(o.hair, [[0, -0.02, 1.66, 0.092, 0.1], [0, -0.01, 1.74, 0.092, 0.104], [0, -0.005, 1.795, 0.06, 0.07]])
  if (o.long) loft(o.long, [[0, -0.06, 1.34, 0.11, 0.05], [0, -0.05, 1.6, 0.105, 0.07], [0, -0.02, 1.74, 0.094, 0.105], [0, -0.005, 1.8, 0.06, 0.07]])
  if (o.hood) { loft(o.hood, [[0, -0.03, 1.48, 0.15, 0.13], [0, -0.03, 1.62, 0.115, 0.125], [0, -0.02, 1.76, 0.1, 0.112], [0, -0.01, 1.82, 0.06, 0.07]]) }
  if (o.beanie) loft(o.beanie, [[0, 0.005, 1.725, 0.095, 0.108], [0, 0, 1.8, 0.09, 0.1], [0, -0.005, 1.85, 0.04, 0.05]])
  if (o.cap) { loft(o.cap, [[0, 0.005, 1.74, 0.096, 0.108], [0, 0, 1.81, 0.09, 0.1], [0, -0.005, 1.84, 0.05, 0.06]]); loft(o.cap, [[0, 0.14, 1.738, 0.085, 0.06], [0, 0.14, 1.748, 0.085, 0.056]]) }
  if (o.flat) { loft(o.flat, [[0, 0.01, 1.745, 0.1, 0.112], [0, 0.015, 1.79, 0.115, 0.135], [0, 0.01, 1.815, 0.07, 0.09]]) }
  if (o.foil) loft('silver', [[0, 0, 1.745, 0.1, 0.112], [0, 0, 2.02, 0.006, 0.006]])
  if (o.wild) for (const [x, y] of [[-0.09, 0], [0.09, 0], [-0.05, -0.08], [0.05, -0.08]]) loft(o.wild, [[x, y, 1.72, 0.04, 0.04], [x * 1.5, y * 1.5, 1.83, 0.006, 0.006]])
}
const KIND = {
  hoodie: { top: 'charcoal', legs: 'black', skin: 'skin', hood: 'charcoal' },
  trucker: { top: 'red', legs: 'jeans', skin: 'skin', beard: 'brown', cap: 'blue', shoe: 'brown' },
  old: { top: 'olive', legs: 'grey', skin: 'pale', flat: 'grey', hair: 'white', shoe: 'brown' },
  woman: { top: 'yellow', band: 'silver', legs: 'jeans', skin: 'pale', long: 'brown', shoe: 'white' },
  hitch: { top: 'teal', legs: 'jeans', skin: 'pale', long: 'blond', beanie: 'rust', shoe: 'brown' },
  shady: { top: 'charcoal', legs: 'charcoal', skin: 'tan', hair: 'black', beard: 'black' },
  stoned: { top: 'green', legs: 'grey', skin: 'dark', long: 'brown', beanie: 'yellow', shoe: 'white' },
  nerd: { top: 'grey', legs: 'olive', skin: 'pale', hair: 'grey', wild: 'white', foil: true },
}
const num = a => a.map(v => +v.toFixed(4)).join(' ')
let total = 0
for (const [kind, o] of Object.entries(KIND)) {
  parts = {}; person(o)
  const name = 'ff_npc_' + kind + '2', g = name + '-g', P = [], N = [], T = [], mats = Object.keys(parts); let off = 0
  for (const m of mats) { const c = parts[m].p.length / 3; P.push(...parts[m].p); N.push(...parts[m].n); const idx = []; for (let i = 0; i < c; i++) idx.push(off + i); T.push(`<triangles material="ff_npc_${m}-mat" count="${c / 3}"><input semantic="VERTEX" source="#${g}-v" offset="0"/><input semantic="NORMAL" source="#${g}-n" offset="0"/><p>${idx.join(' ')}</p></triangles>`); off += c; total += c / 3 }
  fs.writeFileSync(path.join(dir, 'ff_npc_' + kind + '.dae'), `<?xml version="1.0" encoding="utf-8"?>
<COLLADA xmlns="http://www.collada.org/2005/11/COLLADASchema" version="1.4.1">
<asset><contributor><authoring_tool>fernfahrer_karriere tools/build_npcs.js</authoring_tool></contributor>
<unit meter="1" name="meter"/><up_axis>Z_UP</up_axis></asset>
<library_effects>
${mats.map(m => `<effect id="ff_npc_${m}-fx"><profile_COMMON><technique sid="common"><lambert><diffuse><color>0.8 0.8 0.8 1</color></diffuse></lambert></technique></profile_COMMON></effect>`).join('\n')}
</library_effects>
<library_materials>
${mats.map(m => `<material id="ff_npc_${m}-mat" name="ff_npc_${m}"><instance_effect url="#ff_npc_${m}-fx"/></material>`).join('\n')}
</library_materials>
<library_geometries>
<geometry id="${g}"><mesh>
<source id="${g}-p"><float_array id="${g}-p-a" count="${P.length}">${num(P)}</float_array><technique_common><accessor source="#${g}-p-a" count="${P.length / 3}" stride="3"><param name="X" type="float"/><param name="Y" type="float"/><param name="Z" type="float"/></accessor></technique_common></source>
<source id="${g}-n"><float_array id="${g}-n-a" count="${N.length}">${num(N)}</float_array><technique_common><accessor source="#${g}-n-a" count="${N.length / 3}" stride="3"><param name="X" type="float"/><param name="Y" type="float"/><param name="Z" type="float"/></accessor></technique_common></source>
<vertices id="${g}-v"><input semantic="POSITION" source="#${g}-p"/></vertices>
${T.join('\n')}
</mesh></geometry>
</library_geometries>
<library_visual_scenes><visual_scene id="scene" name="scene">
<node id="base00" name="base00"><node id="start01" name="start01">
<node id="${name}" name="${name}"><instance_geometry url="#${g}"><bind_material><technique_common>${mats.map(m => `<instance_material symbol="ff_npc_${m}-mat" target="#ff_npc_${m}-mat"/>`).join('')}</technique_common></bind_material></instance_geometry></node>
</node></node>
</visual_scene></library_visual_scenes>
<scene><instance_visual_scene url="#scene"/></scene>
</COLLADA>
`)
}
const M = {}
for (const [k, c] of Object.entries(COL)) M['ff_npc_' + k] = { name: 'ff_npc_' + k, mapTo: 'ff_npc_' + k, class: 'Material', version: 1.5, Stages: [{ baseColorFactor: [...c, 1], roughnessFactor: 0.7, metallicFactor: 0 }, {}, {}, {}], castShadows: true }
fs.writeFileSync(path.join(dir, 'npc.materials.json'), JSON.stringify(M, null, 2))
console.log(`${Object.keys(KIND).length} Figuren, ${total} Dreiecke`)
