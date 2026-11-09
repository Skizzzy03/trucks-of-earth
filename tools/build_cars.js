// Builds the car transporter's load on the EU flatbed semi trailer (no extra vehicles: one flexbody per car on six weight nodes).
// The cars are lofted: a smooth body from side profiles and a row of cross-sections, glass, lamps, trim laid on that surface, real wheels,
// generated textures for tyres, webbing, lamps, grilles, rust. No model or texture of anyone else.
// node tools/build_cars.js <mod dir> [preview dir]
// -> <mod>/vehicles/eu_trailers/ff_cars.dae, ff_cars.materials.json, ff_cars.jbeam, ff_tex/*.png
const fs = require('fs'), path = require('path'), zlib = require('zlib')
const mod = process.argv[2], preview = process.argv[3]
const out = path.join(mod, 'vehicles', 'eu_trailers'), texOut = path.join(out, 'ff_tex')
fs.mkdirSync(texOut, { recursive: true })
const TEX = '/vehicles/eu_trailers/ff_tex/'

let seed = 7
function rnd() { seed = (seed * 16807) % 2147483647; return (seed - 1) / 2147483646 }
const lerp = (a, b, t) => a + (b - a) * t, clamp = (x, a, b) => Math.max(a, Math.min(b, x))
const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]], add = (a, b, k = 1) => [a[0] + b[0] * k, a[1] + b[1] * k, a[2] + b[2] * k]
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
const norm = a => { const l = Math.hypot(a[0], a[1], a[2]); return l < 1e-9 ? [0, 0, 1] : [a[0] / l, a[1] / l, a[2] / l] }

// --- the mesh: triangles per material, each corner with its own normal and texture coordinate ---
function Mesh() { this.t = {} }
Mesh.prototype.tri = function (m, a, b, c) { (this.t[m] = this.t[m] || []).push([a, b, c]) }
Mesh.prototype.quad = function (m, a, b, c, d) { this.tri(m, a, b, c); this.tri(m, a, c, d) }
const V = (p, n, uv) => ({ p, n, uv: uv || [p[1] * .25, p[2] * .25] })
// a flat-shaded box, turned about z by yaw (around its middle)
Mesh.prototype.box = function (m, x0, y0, z0, x1, y1, z1, deform) {
  const F = deform || (p => p)
  const face = (a, b, c, d) => { const A = F(a), B = F(b), C = F(c), D = F(d), n = norm(cross(sub(B, A), sub(C, A))); this.quad(m, V(A, n, [0, 0]), V(B, n, [1, 0]), V(C, n, [1, 1]), V(D, n, [0, 1])) }
  const P = (x, y, z) => [x, y, z]
  face(P(x0, y0, z1), P(x1, y0, z1), P(x1, y1, z1), P(x0, y1, z1)); face(P(x0, y1, z0), P(x1, y1, z0), P(x1, y0, z0), P(x0, y0, z0))
  face(P(x0, y0, z0), P(x1, y0, z0), P(x1, y0, z1), P(x0, y0, z1)); face(P(x1, y1, z0), P(x0, y1, z0), P(x0, y1, z1), P(x1, y1, z1))
  face(P(x1, y0, z0), P(x1, y1, z0), P(x1, y1, z1), P(x1, y0, z1)); face(P(x0, y1, z0), P(x0, y0, z0), P(x0, y0, z1), P(x0, y1, z1))
}

// a smooth curve through points [y, v] (monotone cubic: no overshoot between the keys)
function curve(keys) {
  const n = keys.length, x = keys.map(k => k[0]), y = keys.map(k => k[1]), d = [], m = new Array(n)
  for (let i = 0; i < n - 1; i++) d[i] = (y[i + 1] - y[i]) / (x[i + 1] - x[i])
  m[0] = d[0]; m[n - 1] = d[n - 2]
  for (let i = 1; i < n - 1; i++) m[i] = d[i - 1] * d[i] <= 0 ? 0 : 2 * d[i - 1] * d[i] / (d[i - 1] + d[i])
  return v => {
    if (v <= x[0]) return y[0]
    if (v >= x[n - 1]) return y[n - 1]
    let i = 0; while (v > x[i + 1]) i++
    const h = x[i + 1] - x[i], t = (v - x[i]) / h, t2 = t * t, t3 = t2 * t
    return (2 * t3 - 3 * t2 + 1) * y[i] + (t3 - 2 * t2 + t) * h * m[i] + (-2 * t3 + 3 * t2) * y[i + 1] + (t3 - t2) * h * m[i + 1]
  }
}

// --- the shapes: y from the nose (-) to the tail (+), heights over the deck ---
const SHAPES = {
  sedan: { L: 2.17, W: .885, wf: -1.34, wr: 1.33, r: .315, cowl: -.74, rf: -.08, rr: .86, rb: 1.46, bp: .26,
    top: [[-2.17, .62], [-2.1, .71], [-1.85, .79], [-1.2, .89], [-.74, .98], [-.08, 1.405], [.3, 1.445], [.86, 1.415], [1.46, 1.04], [1.86, 1.01], [2.12, .95], [2.17, .76]],
    belt: [[-2.17, .6], [-2.02, .73], [-1.3, .82], [-.7, .895], [.6, .94], [1.5, .985], [2.05, .975], [2.17, .76]],
    sill: [[-2.17, .4], [-1.98, .27], [-1.6, .225], [1.65, .225], [1.98, .29], [2.17, .42]], end: [.34, .3] },
  hatch: { L: 2.0, W: .865, wf: -1.26, wr: 1.27, r: .305, cowl: -.72, rf: -.1, rr: 1.28, rb: 1.86, bp: .32,
    top: [[-2.0, .63], [-1.94, .72], [-1.7, .8], [-1.15, .91], [-.72, 1.0], [-.1, 1.42], [.5, 1.46], [1.28, 1.42], [1.86, 1.05], [1.96, .98], [2.0, .78]],
    belt: [[-2.0, .61], [-1.86, .74], [-1.2, .84], [-.68, .91], [.8, .975], [1.75, 1.02], [1.96, .98], [2.0, .78]],
    sill: [[-2.0, .4], [-1.83, .28], [-1.5, .23], [1.6, .23], [1.86, .3], [2.0, .44]], end: [.36, .42] },
  suv: { L: 2.2, W: .935, wf: -1.38, wr: 1.38, r: .36, cowl: -.82, rf: -.14, rr: 1.46, rb: 2.02, bp: .36,
    top: [[-2.2, .78], [-2.13, .9], [-1.9, 1.0], [-1.3, 1.1], [-.82, 1.19], [-.14, 1.67], [.6, 1.71], [1.46, 1.68], [2.02, 1.24], [2.15, 1.15], [2.2, .93]],
    belt: [[-2.2, .76], [-2.06, .92], [-1.35, 1.03], [-.78, 1.11], [.9, 1.17], [1.9, 1.21], [2.13, 1.15], [2.2, .93]],
    sill: [[-2.2, .5], [-2.02, .36], [-1.65, .3], [1.75, .3], [2.02, .38], [2.2, .54]], end: [.4, .42] },
}
const CAB_ROW = 12, N_ROWS = 18        // (0: under the middle ... 8: beltline ... 12: edge of the roof ... 17: top in the middle)

function makeBody(s) {
  const top = curve(s.top), belt = curve(s.belt), sill = curve(s.sill)
  // the plan: rounded at both ends
  const plan = y => {
    const k = y < 0 ? clamp((y + s.L) / (s.L * .42), 0, 1) : clamp((s.L - y) / (s.L * .36), 0, 1), e = y < 0 ? s.end[0] : s.end[1]
    const round = Math.pow(1 - Math.pow(1 - k, 3.4), 1 / 2.6)
    return s.W * (e + (1 - e) * round)
  }
  // the stations: fine at the ends and around the wheels, and exactly on every edge of the glass
  const keys = new Set()
  for (let y = -s.L; y < s.L + 1e-6; y += .085) keys.add(+y.toFixed(3))
  for (let k = 0; k <= 8; k++) { const q = k / 8 * .22; keys.add(+(-s.L + q).toFixed(3)); keys.add(+(s.L - q).toFixed(3)) }
  for (const w of [s.wf, s.wr]) for (let a = -1; a <= 1.0001; a += 1 / 9) keys.add(+(w + (s.r + .055) * Math.sin(a * Math.PI / 2)).toFixed(3))
  const front = s.cowl + .2, rear = s.rb - .24
  for (const e of [s.cowl, s.rf, s.rr, s.rb, front, rear, s.bp - .05, s.bp + .05]) keys.add(+e.toFixed(3))
  const ys = [...keys].sort((a, b) => a - b).filter((v, i, a) => i === 0 || v - a[i - 1] > .012)
  const arch = y => {
    let z = 0
    for (const w of [s.wf, s.wr]) { const R = s.r + .055, d = Math.abs(y - w); if (d < R) z = Math.max(z, s.r + Math.sqrt(R * R - d * d)) }
    return z
  }
  const build = withArch => ys.map(y => {
    const b = belt(y), t = Math.max(top(y), b + .004), a0 = withArch ? arch(y) : 0, zs = Math.max(sill(y), a0), h = t - b
    let W = plan(y)
    for (const w of [s.wf, s.wr]) { const d = Math.abs(y - w); if (d < s.r + .16) W += .014 * Math.cos(d / (s.r + .16) * Math.PI / 2) }   // (the flare over the wheels)
    const rows = []
    const inner = Math.max(.1, W - .34)
    rows.push([0, y, Math.max(.16, sill(y) - .02)])                         // 0: under the middle
    rows.push([inner, y, a0 ? zs + .02 : Math.max(.16, sill(y) - .01)])      // 1: the floor's edge / inside the wheel arch
    rows.push([W - .05, y, zs])                                             // 2: the sill
    const z2 = zs + Math.min(.05, (b - zs) * .3)
    rows.push([W - .008, y, z2])                                            // 3
    for (let j = 4; j <= 8; j++) {                                          // 4..8: the side up to the belt, slightly barrelled
      const q = (j - 3) / 5
      rows.push([W - .05 * Math.pow(2 * q - 1, 2) * (1 - .4 * q) + .012, y, lerp(z2, b, q)])
    }
    // 9..12: the greenhouse's side, leaning in; on the bonnet and boot it folds flat
    const lean = clamp(h / .55, 0, 1) * .2
    const W8 = rows[8][0], side = q => [W8 - .012 - lean * q, y, b + h * q]
    rows.push(side(.05)); rows.push(side(.46)); rows.push(side(.82)); rows.push(side(.92))
    // 13..17: the top to the middle, crowned
    const edge = rows[12]
    for (let j = 13; j <= 17; j++) {
      const q = (j - 12) / 5
      rows.push([edge[0] * (1 - q), y, lerp(edge[2], t, Math.sin(q * Math.PI / 2))])
    }
    return rows
  })
  return { ys, grid: build(true), clean: build(false), s, plan, belt, top, sill, front, rear }
}

function normals(g) {
  const I = g.length, J = N_ROWS
  return g.map((row, i) => row.map((p, j) => {
    const a = g[Math.max(0, i - 1)][j], b = g[Math.min(I - 1, i + 1)][j], c = g[i][Math.max(0, j - 1)], d = g[i][Math.min(J - 1, j + 1)]
    const n = norm(cross(sub(b, a), sub(d, c)))
    return (j === 0 || j === J - 1) ? norm([0, n[1], n[2]]) : n
  }))
}

// --- value noise and damage, for the wrecks ---
function noise2(x, y, s) {
  const hash = (i, j) => { const v = Math.sin(i * 127.1 + j * 311.7 + s) * 43758.5453; return v - Math.floor(v) }
  const i = Math.floor(x), j = Math.floor(y), u = x - i, v = y - j, f = t => t * t * (3 - 2 * t)
  return lerp(lerp(hash(i, j), hash(i + 1, j), f(u)), lerp(hash(i, j + 1), hash(i + 1, j + 1), f(u)), f(v))
}
function crumple(s, sd) {
  return p => {
    const [x, y, z] = p
    const front = clamp((-y - (s.L - .95)) / .95, 0, 1), rear = sd > 1 ? clamp((y - (s.L - .55)) / .55, 0, 1) : 0
    const dent = (noise2(x * 3.1, y * 2.3 + z * 2, sd) - .5) * .11 + (noise2(x * 8, y * 7, sd + 3) - .5) * .03
    const nx = Math.sign(x) || 1
    return [x - nx * Math.abs(x) * front * .09 + nx * dent * (z < 1 ? 1 : .4), y + front * front * .42 - rear * rear * .24,
      z - front * .1 * clamp(z - .3, 0, 1) - (z > 1.1 ? .05 + dent * .9 : dent * .4)]
  }
}

// --- a body with everything on it ---
function carInto(m, shapeKey, paint, wreck, sd) {
  const b = makeBody(SHAPES[shapeKey]), s = b.s, F = wreck ? crumple(s, sd) : (p => p)
  const G = wreck ? b.grid.map(r => r.map(p => F(p))) : b.grid, I = G.length
  // (the sides' shading from the body without its wheel arches: the arch's squeezed rows made dark smears on the wings)
  const N0 = normals(G), N1 = normals(wreck ? b.clean.map(r => r.map(p => F(p))) : b.clean), NN = N0.map((row, i) => row.map((n, j) => j >= 3 ? N1[i][j] : n))
  const glass = wreck ? 'ff_glass_broken' : 'ff_glass'
  const mat = (i, j) => {
    const y0 = b.ys[i], y1 = b.ys[i + 1], c = (y0 + y1) / 2
    if (j < 2) return 'ff_under'
    if (j === 2) return wreck ? paint : 'ff_trim'                                 // (the sill in black)
    if ((j === 9 || j === 10) && c > b.front && c < b.rear && Math.abs(c - s.bp) > .05) return glass
    if (j === 11 && c > b.front && c < b.rear) return 'ff_trim'                   // (the rubber round the side glass)
    if (j === 9 - 1 && c > b.front && c < b.rear) return 'ff_chrome'
    if ((j === 9 || j === 10) && c > b.front && c < b.rear) return 'ff_trim'      // (the B pillar)
    if (j >= 13 && c > s.cowl && c < s.rf) return glass
    if (j >= 13 && c > s.rr && c < s.rb) return glass
    return paint
  }
  const uvOf = (i, j) => [b.ys[i] * .35, j * .09]
  for (const sgn of [1, -1]) {
    for (let i = 0; i < I - 1; i++) for (let j = 0; j < N_ROWS - 1; j++) {
      const P = (ii, jj) => { const p = G[ii][jj], n = NN[ii][jj]; return V(sgn > 0 ? p : [-p[0], p[1], p[2]], sgn > 0 ? n : [-n[0], n[1], n[2]], uvOf(ii, jj)) }
      const a = P(i, j), bb = P(i + 1, j), c = P(i + 1, j + 1), d = P(i, j + 1)
      if (sgn > 0) m.quad(mat(i, j), a, bb, c, d); else m.quad(mat(i, j), bb, a, d, c)
    }
  }
  // the ends closed
  for (const [i, dir] of [[0, -1], [I - 1, 1]]) {
    const n = norm([0, dir, 0]), c = [0, G[i][0][1] + dir * .004, (G[i][0][2] + G[i][N_ROWS - 1][2]) / 2]
    for (const sgn of [1, -1]) for (let j = 0; j < N_ROWS - 1; j++) {
      const q = p => V([sgn * p[0], p[1], p[2]], n), A = q(G[i][j]), B = q(G[i][j + 1]), C = V(c, n)
      if (sgn * dir > 0) m.tri(paint, A, C, B); else m.tri(paint, A, B, C)
    }
  }
  // --- things laid on the surface ---
  const rowsAt = y => {
    let i = 0; while (i < I - 2 && b.ys[i + 1] < y) i++
    const t = clamp((y - b.ys[i]) / (b.ys[i + 1] - b.ys[i]), 0, 1)
    return G[i].map((p, j) => ({ p: [lerp(p[0], G[i + 1][j][0], t), lerp(p[1], G[i + 1][j][1], t), lerp(p[2], G[i + 1][j][2], t)], n: norm([lerp(NN[i][j][0], NN[i + 1][j][0], t), lerp(NN[i][j][1], NN[i + 1][j][1], t), lerp(NN[i][j][2], NN[i + 1][j][2], t)]) }))
  }
  const at = (y, j) => { const r = rowsAt(y), a = Math.floor(clamp(j, 0, N_ROWS - 1.001)), t = j - a; return { p: r[a].p.map((v, k) => lerp(v, r[a + 1].p[k], t)), n: norm(r[a].n.map((v, k) => lerp(v, r[a + 1].n[k], t))) } }
  // a patch on the surface: y0..y1 along, j0..j1 across the rows; both sides unless one
  const patch = (mt, y0, y1, j0, j1, off, nu, nv, opt = {}) => {
    for (const sgn of [1, -1]) {
      const pt = (u, v) => {
        const q = at(lerp(y0, y1, u), lerp(j0, j1, v)), p = add(q.p, q.n, off)
        const uv = opt.flipU && sgn < 0 ? [1 - u, v] : [u, v]
        return V([sgn * p[0], p[1], p[2]], [sgn * q.n[0], q.n[1], q.n[2]], uv)
      }
      for (let a = 0; a < nu; a++) for (let c = 0; c < nv; c++) {
        const A = pt(a / nu, c / nv), B = pt((a + 1) / nu, c / nv), C = pt((a + 1) / nu, (c + 1) / nv), D = pt(a / nu, (c + 1) / nv)
        if (sgn > 0) m.quad(mt, A, B, C, D); else m.quad(mt, B, A, D, C)
      }
    }
  }
  // a piece on the nose or the tail, following the plan's curve: x0..x1 across, z0..z1 up
  const yAtPlan = (x, end) => {
    let lo = end < 0 ? -s.L : 0, hi = end < 0 ? 0 : s.L
    for (let k = 0; k < 24; k++) { const mid = (lo + hi) / 2, inside = b.plan(mid) > x; if (end < 0) { if (inside) hi = mid; else lo = mid } else { if (inside) lo = mid; else hi = mid } }
    return (lo + hi) / 2
  }
  const endPiece = (mt, end, x0, x1, z0, z1, off, nu, mirror = true) => {
    for (const sgn of mirror ? [1, -1] : [1]) {
      const pt = (u, v) => {
        const x = lerp(x0, x1, u), y = yAtPlan(Math.max(0, Math.abs(x) - .022), end), dx = .012   // (a little outside the curve: the body's side bulges past it)
        const y2 = yAtPlan(Math.abs(x) + dx, end), nn = norm([(x >= 0 ? 1 : -1) * Math.abs(y2 - y) * 1, end * dx, .04 * (v - .4)])
        const p = F([x, y + end * off, lerp(z0, z1, v)])
        return V([sgn * p[0], p[1], p[2]], [sgn * nn[0], nn[1], nn[2]], [sgn > 0 ? u : 1 - u, v])
      }
      for (let a = 0; a < nu; a++) {
        const A = pt(a / nu, 0), B = pt((a + 1) / nu, 0), C = pt((a + 1) / nu, 1), D = pt(a / nu, 1)
        if ((sgn > 0) === (end > 0)) m.quad(mt, A, B, C, D); else m.quad(mt, B, A, D, C)
      }
    }
  }
  const fb = b.belt(-s.L + .12), rb = b.belt(s.L - .12)
  // the front
  endPiece('ff_grille', -1, -.46, .46, fb - .17, fb - .025, .006, 14, false)
  endPiece('ff_chrome', -1, -.47, .47, fb - .01, fb + .004, .009, 12, false)
  endPiece('ff_grille', -1, -.56, .56, fb - .47, fb - .31, .006, 14, false)
  // (the lamps lie on the surface itself, round the corners)
  const yf0 = yAtPlan(.46, -1), yf1 = yAtPlan(.86, -1), yr0 = yAtPlan(.84, 1), yr1 = yAtPlan(.38, 1)
  patch(wreck ? 'ff_trim' : 'ff_lamp', yf0, yf1, 6.45, 7.95, .005, 12, 3, { flipU: true })
  endPiece('ff_chrome', -1, .62, .72, fb - .41, fb - .35, .009, 4)
  // the tail
  if (!wreck || shapeKey !== 'hatch') patch(wreck ? 'ff_trim' : 'ff_rear', yr0, yr1, 6.3, 7.95, .005, 12, 3, { flipU: true })
  endPiece('ff_trim', 1, -.75, .75, b.sill(s.L - .1) + .08, b.sill(s.L - .1) + .17, .008, 16, false)
  if (!wreck) {
    endPiece('ff_plate', -1, -.26, .26, fb - .33, fb - .22, .012, 6, false)
    endPiece('ff_plate', 1, -.26, .26, rb - .29, rb - .18, .012, 6, false)
    endPiece('ff_chrome', 1, .52, .6, b.sill(s.L - .1) + .02, b.sill(s.L - .1) + .07, .03, 3)
  }
  // shut lines of doors, bonnet and boot; handles; wipers
  const gap = (y) => patch('ff_gap', y - .0045, y + .0045, 2.6, 8.05, .0016, 1, 6)
  gap(s.cowl + .16); gap(s.bp); gap(b.rear - .04); if (shapeKey !== 'hatch') gap(s.bp + .96)
  // (the bonnet's and the boot's edges)
  patch('ff_gap', s.cowl - .05, s.cowl - .042, 13, 17, .0016, 1, 4)
  patch('ff_gap', -s.L + .34, -s.L + .348, 13, 17, .0016, 1, 4)
  patch('ff_gap', -s.L + .34, s.cowl - .05, 12.95, 13, .0016, 18, 1)
  if (shapeKey === 'sedan') patch('ff_gap', s.rb + .05, s.rb + .058, 13, 17, .0016, 1, 4)
  patch('ff_trim', b.front - .02, b.rear + .02, 4.15, 4.42, .004, 28, 1)                 // (the rubbing strip)
  for (const y of [s.bp - .16, b.rear - .2]) {
    const q = at(y, 7.2), p = F(q.p), w = .075
    for (const sg of [1, -1]) m.box(wreck ? paint : 'ff_chrome', sg * p[0] - .012 + sg * .012, p[1] - w, p[2] - .015, sg * p[0] + .012 + sg * .012, p[1] + w, p[2] + .015)
  }
  if (!wreck) for (const x of [-.34, .28]) {
    const y = s.cowl + .05, z = b.top(y) + .035
    for (let k = 0; k < 10; k++) { const a = k / 10 * .62, c = (k + 1) / 10 * .62, px = t => x - .28 + t; m.box('ff_trim', px(a), y + a * .04, z + a * .05, px(c), y + .014 + a * .04, z + .012 + a * .05) }
  }
  // the mirrors
  for (const sg of [1, -1]) {
    const q = at(s.cowl + .3, 8.2), p = F(q.p), x = sg * (p[0] + .09), y = p[1], z = p[2] + .06
    m.box('ff_trim', sg * p[0] - .03 + sg * .01, y - .03, z - .05, sg * p[0] + .03 + sg * .04, y + .03, z - .02)
    blob(m, paint, [x, y - .004, z + .01], .088, .05, .066)
    m.box('ff_mirror', x - .07, y + .039, z - .036, x + .07, y + .043, z + .056)
  }
  // the inside, seen through the glass
  const IZ = b.sill(0) + .1
  m.box('ff_interior', -.74, s.cowl + .05, IZ, .74, s.rb - .1, IZ + .22, F)
  m.box('ff_interior', -.76, s.cowl + .02, IZ + .2, .76, s.cowl + .42, b.belt(s.cowl + .2) - .02, F)
  for (const x of [-.4, .4]) for (const y of [s.bp - .22, s.bp + .68]) {
    if (y > s.rb - .3) continue
    blob(m, 'ff_seat', F([x, y + .03, IZ + .29]), .22, .25, .085)
    blob(m, 'ff_seat', F([x, y + .24, IZ + .58]), .2, .075, .32)
    blob(m, 'ff_seat', F([x, y + .22, IZ + .95]), .1, .06, .085)
  }
  // the wheels: one lost on a wreck
  const tx = s.W - .115
  const wheels = [[tx, s.wf], [-tx, s.wf], [tx, s.wr], [-tx, s.wr]]
  wheels.forEach(([x, y], i) => {
    if (wreck && i === 1) { m.box('ff_under', x - .1, y - .1, 0, x + .1, y + .1, .28); return }
    wheel(m, x, y, s.r, .215, shapeKey === 'suv' ? 6 : shapeKey === 'hatch' ? 8 : 10)
    tieDown(m, x, y, s.r)
  })
}

// an ellipsoid
function blob(m, mt, c, rx, ry, rz) {
  const N = 14, K = 8, P = (a, q) => { const n = [Math.cos(a) * Math.cos(q), Math.sin(a) * Math.cos(q), Math.sin(q)]; return V([c[0] + n[0] * rx, c[1] + n[1] * ry, c[2] + n[2] * rz], norm([n[0] / rx, n[1] / ry, n[2] / rz]), [a, q]) }
  for (let i = 0; i < N; i++) for (let k = 0; k < K; k++) {
    const a0 = i / N * Math.PI * 2, a1 = (i + 1) / N * Math.PI * 2, q0 = -Math.PI / 2 + k / K * Math.PI, q1 = -Math.PI / 2 + (k + 1) / K * Math.PI
    m.quad(mt, P(a0, q0), P(a1, q0), P(a1, q1), P(a0, q1))
  }
}

// --- wheel: a turned tyre, a barrel, spokes, a hub ---
function wheel(m, x, y, r, w, spokes) {
  const N = 40, sgn = x > 0 ? 1 : -1
  // a body of revolution around the axle: [offset across (+ outward), radius]
  const lathe = (mt, prof, uvf) => {
    for (let i = 0; i < N; i++) {
      const a0 = i / N * Math.PI * 2, a1 = (i + 1) / N * Math.PI * 2
      for (let k = 0; k + 1 < prof.length; k++) {
        const [o0, r0] = prof[k], [o1, r1] = prof[k + 1]
        const nr = (r1 - r0), no = -(o1 - o0), L = Math.hypot(nr, no) || 1
        const pt = (o, q, a) => V([x + sgn * o, y + Math.cos(a) * q, r + Math.sin(a) * q], norm([sgn * nr / L * -1, Math.cos(a) * no / L * -1, Math.sin(a) * no / L * -1]), uvf ? uvf(o, q, a) : [a, q])
        const A = pt(o0, r0, a0), B = pt(o0, r0, a1), C = pt(o1, r1, a1), D = pt(o1, r1, a0)
        if (sgn > 0) m.quad(mt, A, D, C, B); else m.quad(mt, A, B, C, D)
      }
    }
  }
  const h = w / 2, ri = r * .655
  const sideUV = (o, q, a) => [.5 + Math.cos(a) * q / (r * 2.04), .5 + Math.sin(a) * q / (r * 2.04)]
  const treadUV = (o, q, a) => [a / (Math.PI * 2) * 6, .5 + o / w]
  lathe('ff_tire_tread', [[h * .93, r - .004], [h * .55, r], [-h * .55, r], [-h * .93, r - .004]], treadUV)
  lathe('ff_tire_side', [[h * .93, r - .004], [h * 1.03, r - .04], [h * 1.04, r - .085], [h * .98, ri + .012], [h * .9, ri]], sideUV)
  lathe('ff_tire_side', [[-h * .9, ri], [-h * .98, ri + .012], [-h * 1.04, r - .085], [-h * 1.03, r - .04], [-h * .93, r - .004]], sideUV)
  // the rim's lip and barrel
  lathe('ff_rim', [[h * .9, ri], [h * .95, ri - .008], [h * .92, ri - .02]])
  lathe('ff_brake', [[h * .92, ri - .02], [h * .55, ri - .032], [-h * .9, ri - .032]])
  lathe('ff_under', [[-h * .6, ri - .03], [-h * .6, 0.001]])
  // the disc and spokes (outward face)
  const face = h * .6, hubR = ri * .28
  lathe('ff_brake', [[-.01, ri - .05], [-.01, ri * .34]])
  lathe('ff_rim', [[face + .02, 0.001], [face + .02, hubR * .5], [face + .005, hubR], [face - .015, hubR * 1.1]])
  const spoke = (a, wide) => {
    const c = Math.cos(a), si = Math.sin(a), tn = [-si, c]
    const P = (q, off, o) => [x + sgn * o, y + c * q + tn[0] * off, r + si * q + tn[1] * off]
    const r0 = hubR * .85, r1 = ri - .026, w0 = wide * 1.2, w1 = wide * .78
    const front0 = face + .012, front1 = h * .88, back = face - .03
    const face4 = (mt, a1, b1, c1, d1) => {
      const n = norm(cross(sub(b1, a1), sub(c1, a1))), n2 = sgn > 0 ? n : n
      const A = V(a1, n2), B = V(b1, n2), C = V(c1, n2), D = V(d1, n2)
      m.quad(mt, A, B, C, D)
    }
    const A = P(r0, -w0, front0), B = P(r1, -w1, front1), C = P(r1, w1, front1), D = P(r0, w0, front0)
    const a2 = P(r0, -w0, back), b2 = P(r1, -w1, front1 - .05), c2 = P(r1, w1, front1 - .05), d2 = P(r0, w0, back)
    if (sgn > 0) { face4('ff_rim', A, B, C, D); face4('ff_rim', a2, b2, B, A); face4('ff_rim', D, C, c2, d2) }
    else { face4('ff_rim', D, C, B, A); face4('ff_rim', A, B, b2, a2); face4('ff_rim', d2, c2, C, D) }
  }
  for (let i = 0; i < spokes; i++) spoke(i / spokes * Math.PI * 2 + .3, spokes > 6 ? .015 : .027)
  for (let i = 0; i < 5; i++) { const a = i / 5 * Math.PI * 2; m.box('ff_chrome', x + sgn * (face + .015) - .007, y + Math.cos(a) * hubR * .68 - .009, r + Math.sin(a) * hubR * .68 - .009, x + sgn * (face + .015) + .007, y + Math.cos(a) * hubR * .68 + .009, r + Math.sin(a) * hubR * .68 + .009) }
}

// --- the wheel strap: webbing over the tyre, to a hook at the deck; a chock before and behind ---
function tieDown(m, x, y, r) {
  const hw = .023, sgn = x > 0 ? 1 : -1, R = r + .007, a0 = -.42, a1 = Math.PI + .42, N = 18, cx = x - sgn * .02
  const pt = a => [y + Math.cos(a) * R, r + Math.sin(a) * R]
  for (let i = 0; i < N; i++) {
    const a = lerp(a0, a1, i / N), c = lerp(a0, a1, (i + 1) / N), [y0, z0] = pt(a), [y1, z1] = pt(c), n0 = [0, Math.cos(a), Math.sin(a)], n1 = [0, Math.cos(c), Math.sin(c)]
    const A = V([cx - hw, y0, z0], n0, [i, 0]), B = V([cx + hw, y0, z0], n0, [i, 1]), C = V([cx + hw, y1, z1], n1, [i + 1, 1]), D = V([cx - hw, y1, z1], n1, [i + 1, 0])
    m.quad('ff_strap', B, A, D, C)
  }
  for (const e of [a0, a1]) {
    const [y0, z0] = pt(e), d = e === a0 ? 1 : -1, y1 = y0 + d * .13
    const n = norm([0, (d > 0 ? 1 : -1) * z0, .13]), A = V([cx - hw, y0, z0], n, [0, 0]), B = V([cx + hw, y0, z0], n, [0, 1]), C = V([cx + hw, y1, .012], n, [2, 1]), D = V([cx - hw, y1, .012], n, [2, 0])
    if (d > 0) m.quad('ff_strap', A, B, C, D); else m.quad('ff_strap', B, A, D, C)
    m.box('ff_hook', cx - .018, y1 - .03, .0, cx + .018, y1 + .03, .03)
  }
  { const [ry, rz] = pt(a0); m.box('ff_hook', cx - .036, ry + .03, rz * .5 - .02, cx + .036, ry + .1, rz * .5 + .03) }   // (the ratchet, on the strap)
  // the chocks: wedges
  for (const d of [1, -1]) {
    const y0 = y + d * (r * .78), y1 = y + d * (r * 1.32), z = r * .46, wx = .1, cc = x
    const P = (a, b, c) => [cc + a, b, c]
    const top0 = P(-wx, y0, z), top1 = P(wx, y0, z), bot0 = P(-wx, y1, .006), bot1 = P(wx, y1, .006)
    const n = norm([0, d * z, y1 * d - y0 * d])
    const A = V(top0, n, [0, 0]), B = V(top1, n, [1, 0]), C = V(bot1, n, [1, 1]), D = V(bot0, n, [0, 1])
    if (d > 0) m.quad('ff_chock', A, B, C, D); else m.quad('ff_chock', B, A, D, C)
    for (const sx of [-wx, wx]) {
      const a = P(sx, y0, .006), b = P(sx, y1, .006), c = P(sx, y0, z), nn = [Math.sign(sx), 0, 0], q = (sx > 0) === (d > 0)
      if (q) m.tri('ff_chock', V(a, nn, [0, 0]), V(b, nn, [1, 0]), V(c, nn, [0, 1])); else m.tri('ff_chock', V(a, nn, [0, 0]), V(c, nn, [0, 1]), V(b, nn, [1, 0]))
    }
  }
}

// --- PNG and the textures ---
function crc32(buf) { let c, r = -1; for (let i = 0; i < buf.length; i++) { c = (r ^ buf[i]) & 255; for (let k = 0; k < 8; k++) c = c & 1 ? (c >>> 1) ^ 0xEDB88320 : c >>> 1; r = (r >>> 8) ^ c } return (r ^ -1) >>> 0 }
function png(file, w, h, fn) {
  const raw = Buffer.alloc((w * 4 + 1) * h)
  for (let y = 0, o = 0; y < h; y++) { raw[o++] = 0; for (let x = 0; x < w; x++) { const c = fn(x / w, y / h, x, y); for (let k = 0; k < 4; k++) raw[o++] = clamp(Math.round(k < 3 ? c[k] * 255 : (c[3] === undefined ? 1 : c[3]) * 255), 0, 255) } }
  const chunk = (t, d) => { const len = Buffer.alloc(4); len.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]), cr = Buffer.alloc(4); cr.writeUInt32BE(crc32(td)); return Buffer.concat([len, td, cr]) }
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6
  fs.writeFileSync(path.join(texOut, file), Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]))
}
function fbm(x, y, s, o = 5) { let v = 0, a = .5, f = 1; for (let i = 0; i < o; i++) { v += a * noise2(x * f, y * f, s + i * 7); a *= .5; f *= 2.03 } return v }
function normalPng(file, w, h, H, k) {
  const e = 1 / w, e2 = 1 / h
  png(file, w, h, (u, v) => {
    const dx = (H((u + e) % 1, v) - H((u - e + 1) % 1, v)) * k, dy = (H(u, (v + e2) % 1) - H(u, (v - e2 + 1) % 1)) * k
    const n = norm([-dx, dy, 1]); return [n[0] * .5 + .5, n[1] * .5 + .5, n[2] * .5 + .5, 1]
  })
}
function textures() {
  // the tread: four grooves round the tyre, sipes across
  const tread = (u, v) => {
    let h = .75 + .25 * noise2(u * 200, v * 200, 3) * .3
    for (const g of [.2, .4, .6, .8]) if (Math.abs(v - g) < .022) h = 0
    const blk = (u * 34 + (v * 5 | 0) * .5) % 1
    if (blk < .08 && v > .08 && v < .92) h = Math.min(h, .3)
    return h
  }
  png('tire_tread.color.png', 512, 512, (u, v) => { const h = tread(u, v), c = .055 + h * .05 + noise2(u * 120, v * 120, 2) * .018; return [c, c, c * 1.04] })
  normalPng('tire_tread.normal.png', 1024, 512, tread, 22)
  // the sidewall (planar on the tyre's side): rings, a band of fine ribs, rubber grain
  const ring = (u, v) => { const r = Math.hypot(u - .5, v - .5) * 2; let h = .5 + noise2(u * 300, v * 300, 9) * .05; if (r > .72 && r < .8) h += .06 * Math.sin(r * 900); if (Math.abs(r - .86) < .006 || Math.abs(r - .69) < .006) h += .2; return h }
  png('tire_side.color.png', 1024, 1024, (u, v) => { const r = Math.hypot(u - .5, v - .5) * 2, c = .075 + noise2(u * 240, v * 240, 5) * .022 + (r > .72 && r < .8 ? .02 : 0); return [c, c, c * 1.05] })
  normalPng('tire_side.normal.png', 1024, 1024, ring, 9)
  // rust and old paint: a grey-brown map, tinted per wreck
  const rustH = (u, v) => fbm(u * 9, v * 9, 11, 6)
  png('rust.color.png', 1024, 1024, (u, v) => {
    const n = fbm(u * 6, v * 6, 4, 6), blot = clamp((fbm(u * 3, v * 3, 21, 4) - .42) * 6, 0, 1), sc = fbm(u * 40, v * 3, 8, 3) > .72 ? .7 : 1
    const paint = [.34, .34, .34], rust = [.24 + n * .22, .12 + n * .09, .05 + n * .04]
    return [0, 1, 2].map(k => lerp(paint[k] * (.75 + n * .4), rust[k], blot) * sc)
  })
  normalPng('rust.normal.png', 1024, 1024, rustH, 5)
  // the strap's webbing
  const web = (u, v) => .5 + .22 * Math.sin(u * Math.PI * 2 * 44) * Math.sin(v * Math.PI * 2 * 16) + (v < .08 || v > .92 ? .22 : 0)
  png('strap.color.png', 512, 128, (u, v) => { const k = .84 + web(u, v) * .24 + (v < .08 || v > .92 ? -.08 : 0); return [.9 * k, .47 * k, .06 * k] })
  normalPng('strap.normal.png', 512, 128, web, 3)
  // the headlamp: two reflectors behind clear glass, a chrome surround, the indicator
  const lamp = (u, v) => {
    const refl = (cx, cy, r) => { const d = Math.hypot((u - cx) * 2.2, v - cy) / r; return d < 1 ? 1 - d : -1 }
    const a = refl(.3, .52, .42), b = refl(.68, .52, .36)
    const g = Math.max(a, b)
    if (u > .9) return [1, .55, .08]
    if (g < 0) return [.32, .34, .37]
    const rings = .75 + .25 * Math.sin(g * 46)
    return [.82 * rings + g * .25, .84 * rings + g * .25, .9 * rings + g * .22]
  }
  png('lamp.color.png', 512, 256, lamp)
  // the tail lamp: red lens with ribs, reversing light, indicator
  png('rear.color.png', 512, 256, (u, v) => {
    const rib = .8 + .2 * Math.sin(v * 110) * Math.sin(u * 70)
    if (u < .22) return [.86 * rib, .86 * rib, .84 * rib]
    if (u > .8) return [.82 * rib, .34 * rib, .04]
    return [.58 * rib, .02, .03]
  })
  normalPng('rear.normal.png', 512, 256, (u, v) => .5 + .25 * Math.sin(v * 110) * Math.sin(u * 70), 3)
  // the grille: a honeycomb
  const honey = (u, v) => { const a = u * 34, b = v * 10; const row = Math.floor(b), x = a + (row % 2) * .5; const fx = x - Math.floor(x), fy = b - row; return Math.min(Math.min(fx, 1 - fx) * 3.2, Math.min(fy, 1 - fy) * 4.5, 1) }
  png('grille.color.png', 1024, 256, (u, v) => { const h = honey(u, v), c = h > .35 ? .012 : .06; return [c, c, c * 1.1] })
  normalPng('grille.normal.png', 1024, 256, (u, v) => 1 - honey(u, v), 5)
  // a number plate: no real one – white, the blue band, made-up letters
  const FONT = { T: ['11111', '00100', '00100', '00100', '00100', '00100', '00100'], O: ['01110', '10001', '10001', '10001', '10001', '10001', '01110'], E: ['11111', '10000', '10000', '11110', '10000', '10000', '11111'], 2: ['01110', '10001', '00001', '00110', '01000', '10000', '11111'], 4: ['00010', '00110', '01010', '10010', '11111', '00010', '00010'] }
  const TXT = 'TOE 24'
  png('plate.color.png', 512, 128, (u, v) => {
    if (u < .08) return [.05, .2, .62]
    if (u > .985 || v < .04 || v > .96) return [.1, .1, .1]
    const cw = .138, x = (u - .13) / cw, ci = Math.floor(x), ch = FONT[TXT[ci]]
    if (ch) { const cx = Math.floor((x - ci) * 6.6), cy = Math.floor((v - .16) / .68 * 7); if (cx >= 0 && cx < 5 && cy >= 0 && cy < 7 && ch[cy][cx] === '1') return [.05, .05, .06] }
    return [.92, .92, .9]
  })
  // broken glass
  png('glass_broken.color.png', 512, 512, (u, v) => { const n = fbm(u * 14, v * 14, 31, 3); const crack = Math.abs(n - .5) < .005 || Math.abs(fbm(u * 7, v * 7, 15, 3) - .46) < .004; const c = crack ? .2 : .025; return [c, c * 1.05, c * 1.1, crack ? 1 : .7] })
  // a fine flake for the metallic paints
  normalPng('flake.normal.png', 512, 512, (u, v) => noise2(u * 240, v * 240, 40) * .6 + noise2(u * 70, v * 70, 41) * .4, .6)
}

// --- materials: [r, g, b, roughness, metal, extras] ---
const paint = (r, g, b, rough, metal) => [r, g, b, rough, metal, { clearCoat: 1, normalMap: 'flake.normal.png', cube: true, tile: true }]
const rustTint = (r, g, b) => [r, g, b, .86, .05, { map: 'rust.color.png', normalMap: 'rust.normal.png' }]
const MATS = {
  ff_paint_red: paint(.48, .025, .03, .28, .45), ff_paint_blue: paint(.03, .1, .36, .26, .75), ff_paint_silver: paint(.56, .57, .6, .3, .95),
  ff_paint_white: paint(.82, .82, .83, .3, .05), ff_paint_black: paint(.012, .012, .015, .22, .6), ff_paint_green: paint(.05, .19, .12, .26, .7),
  ff_rust_a: rustTint(.72, .5, .38), ff_rust_b: rustTint(.42, .55, .66), ff_rust_c: rustTint(.72, .7, .5),
  ff_glass: [.012, .018, .022, .04, .1, { glass: .85, cube: true }], ff_glass_broken: [1, 1, 1, .7, 0, { map: 'glass_broken.color.png', glass: .9 }],
  ff_tire_tread: [1, 1, 1, .92, 0, { map: 'tire_tread.color.png', normalMap: 'tire_tread.normal.png' }], ff_tire_side: [1, 1, 1, .78, 0, { map: 'tire_side.color.png', normalMap: 'tire_side.normal.png' }],
  ff_rim: [.62, .63, .66, .24, .95, { cube: true }], ff_brake: [.25, .25, .26, .5, .9], ff_under: [.012, .012, .014, .95, 0], ff_interior: [.03, .03, .032, .85, 0], ff_seat: [.05, .05, .055, .8, 0],
  ff_trim: [.018, .018, .02, .6, 0], ff_gap: [.003, .003, .003, .95, 0], ff_chrome: [.8, .8, .82, .1, 1, { cube: true }], ff_mirror: [.75, .78, .82, .03, 1, { cube: true }],
  ff_lamp: [1, 1, 1, .08, .4, { map: 'lamp.color.png', clearCoat: 1, cube: true }], ff_rear: [1, 1, 1, .12, .1, { map: 'rear.color.png', normalMap: 'rear.normal.png', clearCoat: 1, cube: true }],
  ff_grille: [1, 1, 1, .55, .2, { map: 'grille.color.png', normalMap: 'grille.normal.png' }], ff_plate: [1, 1, 1, .4, .1, { map: 'plate.color.png' }],
  ff_strap: [1, 1, 1, .85, 0, { map: 'strap.color.png', normalMap: 'strap.normal.png' }], ff_hook: [.2, .2, .22, .4, .9], ff_chock: [.5, .34, .025, .75, 0],
}
const CARS = {
  ff_new_a: ['sedan', 'ff_paint_silver'], ff_new_b: ['hatch', 'ff_paint_red'], ff_new_c: ['suv', 'ff_paint_blue'],
  ff_new_d: ['sedan', 'ff_paint_black'], ff_new_e: ['hatch', 'ff_paint_white'], ff_new_f: ['suv', 'ff_paint_green'],
  ff_wreck_a: ['sedan', 'ff_rust_a', 1], ff_wreck_b: ['hatch', 'ff_rust_b', 2], ff_wreck_c: ['suv', 'ff_rust_c', 3],
}

// --- Collada, with shared corners ---
const bad = {}
const f4 = x => (Math.round(x * 10000) / 10000).toString(), f3 = x => (Math.round(x * 1000) / 1000).toString()
function geometry(name, m) {
  const pos = [], nor = [], uv = [], tris = [], map = new Map()
  const idx = v => {
    if ([...v.p, ...v.n, ...v.uv].some(x => !Number.isFinite(x))) bad[name] = (bad[name] || 0) + 1, v.p = v.p.map(x => Number.isFinite(x) ? x : 0), v.n = v.n.map(x => Number.isFinite(x) ? x : 0), v.uv = v.uv.map(x => Number.isFinite(x) ? x : 0)
    const k = v.p.map(f4).join(' ') + '|' + v.n.map(f3).join(' ') + '|' + v.uv.map(f3).join(' ')
    let i = map.get(k)
    if (i === undefined) { i = pos.length; map.set(k, i); pos.push(v.p.map(f4).join(' ')); nor.push(v.n.map(f3).join(' ')); uv.push(v.uv.map(f3).join(' ')) }
    return i
  }
  for (const mat of Object.keys(m.t)) {
    const ps = []
    for (const t of m.t[mat]) for (const v of t) { const i = idx(v); ps.push(i, i, i) }
    tris.push(`<triangles material="${mat}-material" count="${m.t[mat].length}"><input semantic="VERTEX" source="#${name}-mesh-vertices" offset="0"/><input semantic="NORMAL" source="#${name}-mesh-normals" offset="1"/><input semantic="TEXCOORD" source="#${name}-mesh-map" offset="2" set="0"/><p>${ps.join(' ')}</p></triangles>`)
  }
  const src = (id, arr, stride, params) => `<source id="${id}"><float_array id="${id}-array" count="${arr.length * stride}">${arr.join(' ')}</float_array><technique_common><accessor source="#${id}-array" count="${arr.length}" stride="${stride}">${params.map(p => `<param name="${p}" type="float"/>`).join('')}</accessor></technique_common></source>`
  return `<geometry id="${name}-mesh" name="${name}"><mesh>${src(name + '-mesh-positions', pos, 3, ['X', 'Y', 'Z'])}${src(name + '-mesh-normals', nor, 3, ['X', 'Y', 'Z'])}${src(name + '-mesh-map', uv, 2, ['S', 'T'])}<vertices id="${name}-mesh-vertices"><input semantic="POSITION" source="#${name}-mesh-positions"/></vertices>${tris.join('')}</mesh></geometry>`
}
textures()
const geos = [], nodes = []
let triCount = 0
for (const [name, [shape, pt, wreck]] of Object.entries(CARS)) {
  const m = new Mesh()
  carInto(m, shape, pt, !!wreck, wreck || 0)
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
for (const [k, [r, g, b, rough, metal, x = {}]] of Object.entries(MATS)) {
  const st = { baseColorFactor: [r, g, b, 1], roughnessFactor: rough, metallicFactor: metal }
  if (x.map) st.baseColorMap = TEX + x.map
  if (x.normalMap) st.normalMap = TEX + x.normalMap
  if (x.clearCoat) { st.clearCoatFactor = x.clearCoat; st.clearCoatRoughnessFactor = .03 }
  if (x.glass) st.opacityFactor = x.glass
  const e = { name: k, mapTo: k, class: 'Material', version: 1.5, Stages: [st, {}, {}, {}] }
  if (x.cube) e.dynamicCubemap = true
  if (x.glass) { e.translucent = true; e.translucentBlendOp = 'PreMulAlpha'; e.translucentRecvShadows = true }
  matJson[k] = e
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
console.log('cars:', Object.keys(CARS).length, 'triangles', triCount, 'bad', JSON.stringify(bad))
if (preview) {
  fs.mkdirSync(path.join(preview, 'ff_tex'), { recursive: true })
  for (const f of ['ff_cars.dae', 'ff_cars.materials.json']) fs.copyFileSync(path.join(out, f), path.join(preview, f))
  for (const f of fs.readdirSync(texOut)) fs.copyFileSync(path.join(texOut, f), path.join(preview, 'ff_tex', f))
}
