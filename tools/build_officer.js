// A police officer standing beside the cab (the rest-area check, career.lua L.restCheck*), made from lofted rings: node build_officer.js <mod folder>
// Writes levels/beamng_earth/art/shapes/fernfahrer/props/ff_officer.dae and adds its materials to props.materials.json. +Y is the way he faces.
const fs = require('fs'), path = require('path')
const dir = path.join(process.argv[2], 'levels/beamng_earth/art/shapes/fernfahrer/props')
const SIDES = 12
const parts = {}                     // material -> { p: [], n: [] }
function add(mat, a, b, c, na, nb, nc) {
  const m = parts[mat] = parts[mat] || { p: [], n: [] }
  m.p.push(...a, ...b, ...c); m.n.push(...na, ...nb, ...nc)
}
const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
const norm = a => { const l = Math.hypot(...a) || 1; return [a[0] / l, a[1] / l, a[2] / l] }
// rings: [cx, cy, cz, rx, ry] from bottom to top; closed at both ends
function loft(mat, rings) {
  const ring = r => { const o = []; for (let i = 0; i < SIDES; i++) { const t = i / SIDES * 2 * Math.PI; o.push([r[0] + Math.cos(t) * r[3], r[1] + Math.sin(t) * r[4], r[2]]) } return o }
  const R = rings.map(ring)
  const out = (k, i) => norm([Math.cos(i / SIDES * 2 * Math.PI) / (rings[k][3] || 1), Math.sin(i / SIDES * 2 * Math.PI) / (rings[k][4] || 1), 0])
  for (let k = 0; k + 1 < R.length; k++) for (let i = 0; i < SIDES; i++) {
    const j = (i + 1) % SIDES
    add(mat, R[k][i], R[k][j], R[k + 1][j], out(k, i), out(k, j), out(k + 1, j))
    add(mat, R[k][i], R[k + 1][j], R[k + 1][i], out(k, i), out(k + 1, j), out(k + 1, i))
  }
  const fan = (k, up) => { const r = rings[k], c = [r[0], r[1], r[2]], n = [0, 0, up]; for (let i = 0; i < SIDES; i++) { const j = (i + 1) % SIDES; up > 0 ? add(mat, c, R[k][i], R[k][j], n, n, n) : add(mat, c, R[k][j], R[k][i], n, n, n) } }
  fan(0, -1); fan(R.length - 1, 1)
}
function box(mat, x0, x1, y0, y1, z0, z1) {
  const v = (x, y, z) => [x, y, z]
  const q = (a, b, c, d, n) => { add(mat, a, b, c, n, n, n); add(mat, a, c, d, n, n, n) }
  q(v(x0, y0, z1), v(x1, y0, z1), v(x1, y1, z1), v(x0, y1, z1), [0, 0, 1]); q(v(x0, y1, z0), v(x1, y1, z0), v(x1, y0, z0), v(x0, y0, z0), [0, 0, -1])
  q(v(x0, y0, z0), v(x1, y0, z0), v(x1, y0, z1), v(x0, y0, z1), [0, -1, 0]); q(v(x1, y1, z0), v(x0, y1, z0), v(x0, y1, z1), v(x1, y1, z1), [0, 1, 0])
  q(v(x1, y0, z0), v(x1, y1, z0), v(x1, y1, z1), v(x1, y0, z1), [1, 0, 0]); q(v(x0, y1, z0), v(x0, y0, z0), v(x0, y0, z1), v(x0, y1, z1), [-1, 0, 0])
}
for (const s of [-1, 1]) {
  const x = s * 0.105
  loft('ff_off_black', [[x, 0.04, 0, 0.055, 0.135], [x, 0.04, 0.05, 0.055, 0.13], [x, 0.0, 0.1, 0.055, 0.08]])       // boot
  loft('ff_off_navy', [[x, 0, 0.08, 0.06, 0.07], [x, 0, 0.5, 0.068, 0.075], [x * 1.02, 0, 0.92, 0.095, 0.105]])        // leg
  loft('ff_off_navy', [[s * 0.255, 0.02, 1.08, 0.04, 0.045], [s * 0.27, 0.01, 1.3, 0.05, 0.055], [s * 0.225, 0, 1.47, 0.065, 0.07]]) // upper arm
  loft('ff_off_yellow', [[s * 0.262, 0.015, 1.2, 0.0525, 0.0575], [s * 0.266, 0.012, 1.25, 0.0535, 0.0585]])           // reflective band
}
// the right arm hangs, the left holds a clipboard in front
loft('ff_off_navy', [[-0.255, 0.02, 0.86, 0.035, 0.04], [-0.255, 0.02, 1.08, 0.042, 0.047]])
loft('ff_off_skin', [[-0.255, 0.02, 0.76, 0.035, 0.04], [-0.255, 0.02, 0.86, 0.036, 0.042]])
loft('ff_off_navy', [[0.235, 0.26, 1.0, 0.035, 0.035], [0.255, 0.02, 1.08, 0.042, 0.047]])
loft('ff_off_skin', [[0.2, 0.34, 1.0, 0.035, 0.038], [0.235, 0.26, 1.0, 0.036, 0.038]])
box('ff_off_black', 0.02, 0.26, 0.3, 0.32, 0.93, 1.25); box('ff_off_white', 0.035, 0.245, 0.32, 0.325, 0.945, 1.23)
loft('ff_off_black', [[0, 0, 0.9, 0.2, 0.14], [0, 0, 0.97, 0.205, 0.145]])                                           // belt
box('ff_off_black', 0.17, 0.26, -0.07, 0.08, 0.8, 0.97)                                                              // holster
loft('ff_off_navy', [[0, 0, 0.97, 0.195, 0.135], [0, 0, 1.2, 0.2, 0.135], [0, 0, 1.42, 0.23, 0.135], [0, 0, 1.5, 0.15, 0.09]])  // torso
loft('ff_off_yellow', [[0, 0, 1.2, 0.207, 0.142], [0, 0, 1.26, 0.209, 0.142]])
box('ff_off_white', -0.16, 0.16, 0.135, 0.139, 1.3, 1.39)                                                             // POLIZEI patch
loft('ff_off_skin', [[0, 0, 1.48, 0.06, 0.06], [0, 0, 1.57, 0.055, 0.055]])                                          // neck
loft('ff_off_skin', [[0, 0.01, 1.54, 0.05, 0.06], [0, 0.015, 1.6, 0.082, 0.098], [0, 0.015, 1.68, 0.09, 0.103], [0, 0.01, 1.74, 0.08, 0.09], [0, 0.005, 1.78, 0.045, 0.05]]) // head
loft('ff_off_skin', [[0, 0.11, 1.635, 0.012, 0.014], [0, 0.125, 1.665, 0.012, 0.012], [0, 0.112, 1.69, 0.008, 0.006]])  // nose
loft('ff_off_navy', [[0, 0.005, 1.745, 0.1, 0.112], [0, 0, 1.79, 0.112, 0.126], [0, -0.005, 1.83, 0.125, 0.14], [0, -0.01, 1.845, 0.07, 0.08]]) // cap
loft('ff_off_white', [[0, 0.005, 1.74, 0.102, 0.114], [0, 0.005, 1.765, 0.105, 0.118]])
loft('ff_off_black', [[0, 0.135, 1.735, 0.09, 0.055], [0, 0.135, 1.75, 0.09, 0.05]])                                 // peak

const name = 'ff_officer2', g = name + '-g'
let tris = 0, offset = 0
const allP = [], allN = [], groups = []
for (const [mat, m] of Object.entries(parts)) {
  const count = m.p.length / 3
  allP.push(...m.p); allN.push(...m.n)
  const idx = []; for (let i = 0; i < count; i++) idx.push(offset + i)
  groups.push(`<triangles material="${mat}-mat" count="${count / 3}"><input semantic="VERTEX" source="#${g}-v" offset="0"/><input semantic="NORMAL" source="#${g}-n" offset="0"/><p>${idx.join(' ')}</p></triangles>`)
  offset += count; tris += count / 3
}
const num = a => a.map(v => +v.toFixed(4)).join(' ')
const mats = Object.keys(parts)
const dae = `<?xml version="1.0" encoding="utf-8"?>
<COLLADA xmlns="http://www.collada.org/2005/11/COLLADASchema" version="1.4.1">
<asset><contributor><authoring_tool>fernfahrer_karriere tools/build_officer.js</authoring_tool></contributor>
<unit meter="1" name="meter"/><up_axis>Z_UP</up_axis></asset>
<library_effects>
${mats.map(m => `<effect id="${m}-fx"><profile_COMMON><technique sid="common"><lambert><diffuse><color>0.8 0.8 0.8 1</color></diffuse></lambert></technique></profile_COMMON></effect>`).join('\n')}
</library_effects>
<library_materials>
${mats.map(m => `<material id="${m}-mat" name="${m}"><instance_effect url="#${m}-fx"/></material>`).join('\n')}
</library_materials>
<library_geometries>
<geometry id="${g}"><mesh>
<source id="${g}-p"><float_array id="${g}-p-a" count="${allP.length}">${num(allP)}</float_array><technique_common><accessor source="#${g}-p-a" count="${allP.length / 3}" stride="3"><param name="X" type="float"/><param name="Y" type="float"/><param name="Z" type="float"/></accessor></technique_common></source>
<source id="${g}-n"><float_array id="${g}-n-a" count="${allN.length}">${num(allN)}</float_array><technique_common><accessor source="#${g}-n-a" count="${allN.length / 3}" stride="3"><param name="X" type="float"/><param name="Y" type="float"/><param name="Z" type="float"/></accessor></technique_common></source>
<vertices id="${g}-v"><input semantic="POSITION" source="#${g}-p"/></vertices>
${groups.join('\n')}
</mesh></geometry>
</library_geometries>
<library_visual_scenes><visual_scene id="scene" name="scene">
<node id="base00" name="base00"><node id="start01" name="start01">
<node id="${name}" name="${name}"><instance_geometry url="#${g}"><bind_material><technique_common>${mats.map(m => `<instance_material symbol="${m}-mat" target="#${m}-mat"/>`).join('')}</technique_common></bind_material></instance_geometry></node>
</node></node>
</visual_scene></library_visual_scenes>
<scene><instance_visual_scene url="#scene"/></scene>
</COLLADA>
`
fs.writeFileSync(path.join(dir, 'ff_officer.dae'), dae)
const mfile = path.join(dir, 'props.materials.json'), M = JSON.parse(fs.readFileSync(mfile, 'utf8'))
const COL = { ff_off_navy: [[0.035, 0.06, 0.13, 1], 0.7, 0], ff_off_yellow: [[0.95, 0.75, 0.05, 1], 0.45, 0], ff_off_skin: [[0.75, 0.53, 0.42, 1], 0.6, 0], ff_off_black: [[0.015, 0.015, 0.018, 1], 0.45, 0], ff_off_white: [[0.82, 0.84, 0.86, 1], 0.55, 0] }
for (const [k, [c, r, m]] of Object.entries(COL)) M[k] = { name: k, mapTo: k, class: 'Material', version: 1.5, Stages: [{ baseColorFactor: c, roughnessFactor: r, metallicFactor: m }, {}, {}, {}], castShadows: true }
fs.writeFileSync(mfile, JSON.stringify(M, null, 2))
console.log(`ff_officer.dae: ${tris} Dreiecke, ${mats.length} Materialien`)
