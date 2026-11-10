// The mood music of the career, composed and played here note by note: nothing from anyone else in it. node build_mood.js <mod folder> [listening file]
// Writes art/sound/fernfahrer/mood/*.wav (22050 Hz, stereo, quiet on purpose) and, if asked, one file with a bit of each to listen to.
const fs = require('fs'), path = require('path')
const SR = 22050, TAU = Math.PI * 2
let seed = 1
const rnd = () => { seed = (seed * 16807) % 2147483647; return seed / 2147483647 }
const hz = m => 440 * Math.pow(2, (m - 69) / 12)
function Mix(sec) { const n = Math.ceil(sec * SR); return { n, sec, L: new Float32Array(n), R: new Float32Array(n), wL: new Float32Array(n), wR: new Float32Array(n) } }
function put(m, i, v, pan, send) { if (i < 0 || i >= m.n) return; const a = (pan + 1) * Math.PI / 4, l = Math.cos(a), r = Math.sin(a); m.L[i] += v * l; m.R[i] += v * r; if (send) { m.wL[i] += v * l * send; m.wR[i] += v * r * send } }
// a slow chord tone: two detuned voices with a few partials, a slow swell, a slight drift
function pad(m, note, t0, dur, amp, o) {
  o = o || {}; const f = hz(note), P = o.partials || [1, 0.42, 0.2, 0.09, 0.04], at = o.attack || 3, rel = o.release || 4, pan = o.pan || 0, send = o.send === undefined ? 0.5 : o.send, ph = rnd() * 6
  const i0 = Math.floor(t0 * SR), N = Math.floor((dur + rel) * SR)
  for (let k = 0; k < N; k++) {
    const t = k / SR; let e = t < at ? Math.sin(t / at * Math.PI / 2) : 1; if (t > dur) e *= Math.cos((t - dur) / rel * Math.PI / 2); if (e <= 0) continue
    const dr = Math.sin(t * 0.37 + ph) * 0.0018; let s = 0
    for (let p = 0; p < P.length; p++) { const n = p + 1; s += P[p] * (Math.sin(TAU * f * n * t * (1.0019 + dr)) + Math.sin(TAU * f * n * t * (0.9981 - dr) + ph)) }
    put(m, i0 + k, s * 0.5 * e * amp, pan + Math.sin(t * 0.23 + ph) * 0.18, send)
  }
}
// a felted piano note
function felt(m, note, t0, amp, o) {
  o = o || {}; const f = hz(note), tau = o.tau || 2.6, i0 = Math.floor(t0 * SR), N = Math.floor(tau * 3.2 * SR), pan = o.pan || 0, send = o.send === undefined ? 0.7 : o.send, P = [1, 0.34, 0.12, 0.05]
  for (let k = 0; k < N; k++) { const t = k / SR; let s = 0; for (let p = 0; p < 4; p++) s += P[p] * Math.exp(-t * (1 + p * 1.5) / tau) * Math.sin(TAU * f * (p + 1) * (1 + 0.0004 * p * p) * t); put(m, i0 + k, s * Math.min(1, t / 0.012) * amp * (k > N - 2000 ? (N - k) / 2000 : 1), pan, send) }
}
// a far-off music box
function box(m, note, t0, amp, o) {
  o = o || {}; const f = hz(note) * (1 + (o.detune || 0)), i0 = Math.floor(t0 * SR), N = Math.floor(3.6 * SR), pan = o.pan || 0, send = o.send === undefined ? 0.95 : o.send
  for (let k = 0; k < N; k++) { const t = k / SR, s = Math.exp(-t / 1.1) * Math.sin(TAU * f * t) + 0.3 * Math.exp(-t / 0.28) * Math.sin(TAU * f * 3.01 * t) + 0.12 * Math.exp(-t / 0.12) * Math.sin(TAU * f * 5.43 * t); put(m, i0 + k, s * Math.min(1, t / 0.003) * amp * (k > N - 1500 ? (N - k) / 1500 : 1), pan, send) }
}
// a plucked string (Karplus-Strong)
function pluck(m, note, t0, amp, o) {
  o = o || {}; const L = Math.max(4, Math.round(SR / hz(note))), b = new Float32Array(L), dur = o.dur || 2.4, i0 = Math.floor(t0 * SR), N = Math.floor(dur * SR), pan = o.pan || 0, send = o.send === undefined ? 0.35 : o.send, damp = o.damp || 0.996
  let prev = 0; for (let i = 0; i < L; i++) { const v = rnd() * 2 - 1; prev = prev * 0.55 + v * 0.45; b[i] = prev }
  let p = 0; for (let k = 0; k < N; k++) { const q = (p + 1) % L, v = b[p]; b[p] = damp * 0.5 * (b[p] + b[q]); p = q; put(m, i0 + k, v * amp * (k > N - 800 ? (N - k) / 800 : 1), pan, send) }
}
function bass(m, note, t0, dur, amp, o) { o = o || {}; const f = hz(note), i0 = Math.floor(t0 * SR), N = Math.floor(dur * SR); for (let k = 0; k < N; k++) { const t = k / SR, e = Math.min(1, t / 0.02) * Math.exp(-t / (dur * 0.4)) * (k > N - 400 ? (N - k) / 400 : 1); put(m, i0 + k, (Math.sin(TAU * f * t) + 0.28 * Math.sin(TAU * f * 2 * t)) * e * amp, 0, o.send || 0.12) } }
// a soft reed for the odd characters
function reed(m, note, t0, dur, amp, o) { o = o || {}; const f = hz(note), i0 = Math.floor(t0 * SR), N = Math.floor(dur * SR), pan = o.pan || 0; for (let k = 0; k < N; k++) { const t = k / SR, e = Math.min(1, t / 0.05) * Math.min(1, (dur - t) / 0.07), v = Math.sin(t * 34) * 0.003 * Math.min(1, t * 3); put(m, i0 + k, (Math.sin(TAU * f * (1 + v) * t) + 0.33 * Math.sin(TAU * 3 * f * (1 + v) * t) + 0.12 * Math.sin(TAU * 5 * f * (1 + v) * t)) * e * amp, pan, 0.4) } }
function wind(m, amp) { let a = 0, b = 0, c = 0, d = 0, g = 0.5, g2 = 0.5; for (let i = 0; i < m.n; i++) { const t = i / SR, k = 0.06 + 0.05 * (0.5 + 0.5 * Math.sin(t * 0.31 + 1)); a += (rnd() * 2 - 1 - a) * k; b += (a - b) * 0.2; c += (rnd() * 2 - 1 - c) * k; d += (c - d) * 0.2; g += (rnd() - 0.5) * 0.002; g = Math.min(1, Math.max(0.15, g)); g2 += (rnd() - 0.5) * 0.002; g2 = Math.min(1, Math.max(0.15, g2)); m.L[i] += b * g * amp * 4; m.R[i] += d * g2 * amp * 4 } }
function tick(m, t0, amp, pan) { const i0 = Math.floor(t0 * SR), N = 500; let lp = 0; for (let k = 0; k < N; k++) { lp += ((rnd() * 2 - 1) - lp) * 0.55; put(m, i0 + k, lp * Math.exp(-k / 90) * amp, pan || 0, 0.12) } }
// a plain stereo room: four feedback delays and two all-passes on each side
function reverb(m, room, level) {
  const run = (input, out, D) => {
    const comb = D.map(d => ({ b: new Float32Array(d), i: 0, lp: 0 })), ap = [[556, 0], [341, 0]].map(([d]) => ({ b: new Float32Array(Math.floor(d * SR / 44100)), i: 0 }))
    for (let n = 0; n < m.n; n++) {
      let s = 0; for (const c of comb) { const v = c.b[c.i]; c.lp += (v - c.lp) * 0.32; c.b[c.i] = input[n] + c.lp * room; c.i = (c.i + 1) % c.b.length; s += v }
      for (const a of ap) { const v = a.b[a.i], x = s + v * -0.5; a.b[a.i] = x; a.i = (a.i + 1) % a.b.length; s = v + x * 0.5 }
      out[n] += s * level
    }
  }
  run(m.wL, m.L, [1116, 1188, 1277, 1356].map(d => Math.floor(d * SR / 44100 * 2.1)))
  run(m.wR, m.R, [1139, 1211, 1300, 1379].map(d => Math.floor(d * SR / 44100 * 2.1)))
}
function finish(m, dir, name, rmsDb, fadeIn, fadeOut, lst) {
  let sum = 0, peak = 0
  for (let i = 0; i < m.n; i++) { sum += m.L[i] * m.L[i] + m.R[i] * m.R[i]; peak = Math.max(peak, Math.abs(m.L[i]), Math.abs(m.R[i])) }
  const rms = Math.sqrt(sum / (2 * m.n)), g = Math.min(Math.pow(10, rmsDb / 20) / rms, 0.71 / peak)
  const buf = Buffer.alloc(44 + m.n * 4); buf.write('RIFF', 0); buf.writeUInt32LE(36 + m.n * 4, 4); buf.write('WAVEfmt ', 8); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(2, 22); buf.writeUInt32LE(SR, 24); buf.writeUInt32LE(SR * 4, 28); buf.writeUInt16LE(4, 32); buf.writeUInt16LE(16, 34); buf.write('data', 36); buf.writeUInt32LE(m.n * 4, 40)
  const fi = Math.floor(fadeIn * SR), fo = Math.floor(fadeOut * SR)
  for (let i = 0; i < m.n; i++) { let e = 1; if (i < fi) e *= Math.sin(i / fi * Math.PI / 2); if (m.n - i < fo) e *= Math.sin((m.n - i) / fo * Math.PI / 2); m.L[i] *= g * e; m.R[i] *= g * e; buf.writeInt16LE(Math.round(Math.max(-1, Math.min(1, m.L[i])) * 32767), 44 + i * 4); buf.writeInt16LE(Math.round(Math.max(-1, Math.min(1, m.R[i])) * 32767), 46 + i * 4) }
  fs.writeFileSync(path.join(dir, name + '.wav'), buf)
  console.log(name.padEnd(12), m.sec + ' s', 'RMS', (20 * Math.log10(rms * g)).toFixed(1), 'dB, Spitze', (20 * Math.log10(peak * g)).toFixed(1), 'dB')
  if (lst) lst.push(m)
}
const chord = (m, notes, t, d, a, o) => notes.forEach((n, i) => pad(m, n, t, d, a, { pan: (i - (notes.length - 1) / 2) * 0.35, ...o }))

const W = {
  // the rest area: only just uneasy. A held low note, a chord that never quite settles, the wind, a music box somewhere far away
  rast1(dir, l) { seed = 11; const m = Mix(60); pad(m, 33, 0, 56, 0.34, { attack: 6, send: 0.25 }); pad(m, 40, 4, 48, 0.09, { attack: 8 }); pad(m, 46, 22, 16, 0.05, { attack: 7, release: 7 })
    ;[[[57, 60, 64], 2], [[53, 60, 65], 17], [[50, 57, 65], 32], [[52, 56, 59], 45]].forEach(([c, t]) => chord(m, c, t, 11, 0.055, { attack: 5, release: 6, partials: [1, 0.25, 0.08] }))
    wind(m, 0.022); const S = [69, 72, 71, 76, 77, 75]; let t = 6; while (t < 52) { const n = S[Math.floor(rnd() * S.length)], p = rnd() * 1.4 - 0.7; box(m, n, t, 0.05, { pan: p, detune: -0.004 }); if (rnd() < 0.5) box(m, n - (rnd() < 0.5 ? 1 : 3), t + 1.1, 0.036, { pan: p, detune: 0.004 }); t += 5 + rnd() * 5 }
    const i0 = 34 * SR; for (let k = 0, ph = 0; k < 5 * SR; k++) { const q = k / (5 * SR); ph += TAU * (62 - 15 * q) / SR; put(m, i0 + k, Math.sin(ph) * Math.sin(q * Math.PI) * 0.12, -0.3, 0.5) }
    reverb(m, 0.87, 0.2); finish(m, dir, 'rast1', -24, 3, 3.5, l) },
  rast2(dir, l) { seed = 29; const m = Mix(42); pad(m, 38, 0, 38, 0.3, { attack: 6, send: 0.25 }); pad(m, 45, 6, 30, 0.08, { attack: 7 }); pad(m, 87, 8, 10, 0.012, { attack: 5, release: 6, partials: [1], send: 1 }); pad(m, 86, 22, 12, 0.012, { attack: 5, release: 6, partials: [1], send: 1 })
    ;[[[50, 53, 57], 2], [[49, 53, 58], 16], [[50, 55, 58], 28]].forEach(([c, t]) => chord(m, c, t, 9, 0.05, { attack: 5, release: 6, partials: [1, 0.2] })); wind(m, 0.024)
    ;[[62, 7], [65, 10.5], [61, 17], [58, 23], [62, 30], [57, 33.5]].forEach(([n, t]) => felt(m, n, t, 0.07, { tau: 3.2, pan: rnd() - 0.5, send: 1 })); reverb(m, 0.88, 0.2); finish(m, dir, 'rast2', -24, 3, 3.5, l) },
  // someone means trouble: a slow heartbeat under a chord that grinds a little
  droh(dir, l) { seed = 41; const m = Mix(32); chord(m, [40, 41, 46], 0, 28, 0.08, { attack: 4, partials: [1, 0.5, 0.25, 0.1] }); pad(m, 28, 0, 28, 0.26, { attack: 3, send: 0.15 }); for (let t = 1, i = 0; t < 30; t += 1.15, i++) { bass(m, 31, t, 0.5, 0.32); bass(m, 31, t + 0.24, 0.42, 0.22) } reverb(m, 0.8, 0.14); finish(m, dir, 'droh', -24, 2, 3, l) },
  warm(dir, l) { seed = 53; const m = Mix(32), B = 60 / 70; [[48, 55, 60, 64, 67, 64], [45, 52, 57, 60, 64, 60], [41, 48, 53, 57, 60, 57], [43, 50, 55, 59, 62, 59]].forEach((a, b) => { for (let r = 0; r < 2; r++) a.forEach((n, i) => pluck(m, n, 0.6 + (b * 2 + r) * 4 * B * 0.75 + i * B * 0.5, 0.11, { pan: -0.35 + i * 0.14, dur: 2.6 })) }); [[60, 64, 67], [57, 60, 64], [53, 60, 65], [55, 59, 62]].forEach((c, i) => chord(m, c, i * 6 * B * 1, 5.5, 0.03, { attack: 1.6, release: 2.5, partials: [1, 0.2] })); reverb(m, 0.8, 0.12); finish(m, dir, 'warm', -24, 1.5, 3, l) },
  // the odd ones: tiptoeing, a little sly
  komisch(dir, l) { seed = 67; const m = Mix(28), S = 0.36, walk = [40, 47, 40, 47, 41, 48, 41, 48, 40, 47, 43, 47, 45, 44, 43, 42]; for (let k = 0; k < 4; k++) walk.forEach((n, i) => { const t = 0.8 + (k * 16 + i) * S * 0.92; if (t < 26.5) pluck(m, n, t, 0.2, { dur: 0.42, damp: 0.985, send: 0.15 }) })
    ;[[76, 0, 1], [75, 1, 1], [76, 2, 1], [72, 3, 2], [71, 6, 1], [69, 7, 1], [68, 8, 3], [71, 12, 1], [72, 13, 1], [74, 14, 1], [75, 15, 1], [76, 16, 2], [79, 19, 1], [78, 20, 1], [76, 21, 3], [72, 28, 1], [71, 29, 1], [69, 30, 2], [64, 33, 3], [76, 40, 1], [75, 41, 1], [76, 42, 1], [72, 43, 3], [71, 48, 1], [68, 49, 1], [69, 50, 4]].forEach(([n, b, d]) => { const t = 2.3 + b * S * 0.92; if (t < 25) reed(m, n, t, d * S * 0.82, 0.05, { pan: 0.25 }) }); reverb(m, 0.72, 0.1); finish(m, dir, 'komisch', -24, 1, 2.5, l) },
  polizei(dir, l) { seed = 73; const m = Mix(36), S = 60 / 92 / 2; chord(m, [38, 45], 0, 32, 0.12, { attack: 4, send: 0.2 }); [[[50, 53, 57], 1], [[50, 55, 58], 11], [[49, 52, 57], 21]].forEach(([c, t]) => chord(m, c, t, 8, 0.05, { attack: 3, release: 4, partials: [1, 0.3, 0.1] })); for (let t = 2, i = 0; t < 33; t += S, i++) { if (i % 2 === 0) tick(m, t, 0.035, 0.35); if (i % 8 === 0 || i % 8 === 3) bass(m, 26, t, 0.55, 0.2) } reverb(m, 0.74, 0.1); finish(m, dir, 'polizei', -25, 2.5, 3, l) },
  // driving, when the radio is off: open and calm by day, sparse by night
  fahrt_tag(dir, l) { seed = 83; const m = Mix(52), B = 60 / 66; [[[50, 57, 62, 66], 1], [[47, 54, 62, 66], 12], [[43, 50, 59, 62], 23], [[45, 52, 57, 64], 34]].forEach(([c, t]) => chord(m, c, t, 10, 0.05, { attack: 4, release: 5, partials: [1, 0.3, 0.1] })); [[69, 66, 62], [71, 69, 66], [67, 62, 59], [69, 64, 61]].forEach((a, s) => { for (let r = 0; r < 2; r++) a.forEach((n, i) => pluck(m, n, 3 + s * 11 + r * 5.3 + i * B, 0.075, { pan: -0.3 + i * 0.3, dur: 2.8, send: 0.6 })) }); reverb(m, 0.85, 0.16); finish(m, dir, 'fahrt_tag', -25, 5, 6, l) },
  fahrt_nacht(dir, l) { seed = 97; const m = Mix(52); [[[41, 56, 60, 63], 1], [[37, 56, 60, 65], 13], [[39, 55, 58, 63], 25], [[36, 55, 60, 63], 37]].forEach(([c, t]) => chord(m, c, t, 10, 0.05, { attack: 5, release: 5, partials: [1, 0.25] })); [[72, 4], [68, 7], [65, 9.5], [73, 16], [68, 19], [70, 28], [67, 31], [63, 34], [72, 40], [67, 43], [65, 45]].forEach(([n, t]) => felt(m, n, t, 0.085, { tau: 3.4, pan: rnd() * 0.9 - 0.45, send: 1 })); reverb(m, 0.89, 0.2); finish(m, dir, 'fahrt_nacht', -25, 5, 6, l) },
  // short ones
  ok_gut(dir, l) { seed = 101; const m = Mix(11), B = 0.42; [60, 64, 67, 72, 76].forEach((n, i) => felt(m, n, 0.3 + i * B, 0.12, { tau: 2.6, pan: -0.4 + i * 0.2 })); [[48, 60, 64, 67], 0.3].length; chord(m, [48, 55, 64, 67], 0.1, 3.4, 0.05, { attack: 0.8, release: 2 }); chord(m, [43, 55, 62, 71], 3.3, 1.6, 0.05, { attack: 0.5, release: 1 }); chord(m, [48, 60, 64, 72], 4.9, 2.6, 0.06, { attack: 0.5, release: 3 }); [79, 76, 72].forEach((n, i) => felt(m, n, 3.3 + i * 0.5, 0.1, { tau: 2.2, pan: 0.2 })); felt(m, 72, 4.95, 0.13, { tau: 3 }); felt(m, 84, 4.95, 0.05, { tau: 3, pan: 0.3 }); reverb(m, 0.82, 0.16); finish(m, dir, 'ok_gut', -22, 0.05, 2, l) },
  ok_mau(dir, l) { seed = 103; const m = Mix(9); chord(m, [45, 52, 60], 0, 3, 0.06, { attack: 0.8, release: 2.5 }); chord(m, [41, 53, 60], 3, 3, 0.06, { attack: 1, release: 2.5 }); [[69, 0.4], [67, 1.5], [64, 2.7], [65, 4], [60, 5.2]].forEach(([n, t]) => felt(m, n, t, 0.11, { tau: 2.4 })); reverb(m, 0.84, 0.16); finish(m, dir, 'ok_mau', -23, 0.05, 2, l) },
  morgen(dir, l) { seed = 107; const m = Mix(13); chord(m, [43, 50, 59, 62], 0, 5, 0.055, { attack: 2.4, release: 3 }); chord(m, [48, 55, 64, 71], 5, 5, 0.06, { attack: 2.2, release: 3 }); [[83, 2.4], [86, 3.1], [83, 5.2], [88, 6.2], [84, 7.4], [91, 8.3]].forEach(([n, t]) => box(m, n, t, 0.05, { pan: rnd() * 1.4 - 0.7, send: 0.8 })); reverb(m, 0.85, 0.16); finish(m, dir, 'morgen', -24, 1, 2.5, l) },
  panne(dir, l) { seed = 109; const m = Mix(11); chord(m, [38, 45, 53], 0, 7, 0.07, { attack: 1.5, release: 3 }); felt(m, 50, 0.6, 0.16, { tau: 3.2 }); felt(m, 49, 3.2, 0.14, { tau: 3.2 }); felt(m, 45, 5.8, 0.16, { tau: 3.6 }); for (let t = 0.5; t < 9; t += 0.72) tick(m, t, 0.05, 0.25); reverb(m, 0.82, 0.14); finish(m, dir, 'panne', -24, 0.1, 2, l) },
}
// a knuckle on the cab's door: only in the left channel, the right stays silent to the last sample
function knocks(dir, name, times, amp, l) {
  const m = Mix(times[times.length - 1] + 0.9); seed = 7
  const hit = (t0, a) => { const i0 = Math.floor(t0 * SR), M = [[92, 0.05, 1], [176, 0.04, 0.75], [338, 0.024, 0.55], [611, 0.012, 0.3], [1180, 0.005, 0.14]]; let lp = 0; for (let k = 0; k < 0.34 * SR; k++) { const t = k / SR; let s = 0; for (const [f, tau, g] of M) s += g * Math.exp(-t / tau) * Math.sin(TAU * f * t); lp += ((rnd() * 2 - 1) - lp) * 0.3; s += lp * Math.exp(-t / 0.006) * 0.6; const v = s * a; if (i0 + k < m.n) m.L[i0 + k] += v; for (const [d, g] of [[0.021, 0.3], [0.037, 0.2], [0.058, 0.12]]) { const q = i0 + k + Math.floor(d * SR); if (q < m.n) m.L[q] += v * g } } }
  times.forEach((t, i) => hit(0.03 + t, amp * (0.9 + rnd() * 0.15)))
  let peak = 0; for (let i = 0; i < m.n; i++) peak = Math.max(peak, Math.abs(m.L[i])); const g = 0.6 / peak; for (let i = 0; i < m.n; i++) { m.L[i] *= g; m.R[i] = 0 }
  const buf = Buffer.alloc(44 + m.n * 4); buf.write('RIFF', 0); buf.writeUInt32LE(36 + m.n * 4, 4); buf.write('WAVEfmt ', 8); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(2, 22); buf.writeUInt32LE(SR, 24); buf.writeUInt32LE(SR * 4, 28); buf.writeUInt16LE(4, 32); buf.writeUInt16LE(16, 34); buf.write('data', 36); buf.writeUInt32LE(m.n * 4, 40)
  for (let i = 0; i < m.n; i++) buf.writeInt16LE(Math.round(m.L[i] * 32767), 44 + i * 4)
  fs.writeFileSync(path.join(dir, name + '.wav'), buf); console.log(name.padEnd(12), m.sec.toFixed(2) + ' s, nur links'); if (l) l.push(m)
}

// the cab's gadgets and the red button
const GAD = {
  gad_popcorn(dir) { seed = 201; const m = Mix(14); for (let t = 0.8; t < 13; t += 0.05 + 0.5 * Math.pow(Math.abs(t - 7) / 7, 2) * (0.4 + rnd())) { const i0 = Math.floor(t * SR), a = (0.5 + rnd() * 0.5) * 0.3; let lp = 0; for (let k = 0; k < 900; k++) { lp += ((rnd() * 2 - 1) - lp) * 0.7; put(m, i0 + k, lp * Math.exp(-k / 130) * a, rnd() * 0.8 - 0.4, 0) } } wind(m, 0.012); { let ph = 0; for (let i = 0; i < m.n; i++) { const t = i / SR; ph += TAU * 98 / SR; put(m, i, (Math.sin(ph) * 0.05 + Math.sin(ph * 2) * 0.025) * Math.min(1, t / 0.4) * Math.min(1, (14 - t) / 0.6), 0, 0) } }
    finish(m, dir, 'gad_popcorn', -15, 0.2, 0.8) },
  // (2026-11-10: the machine's pump humming under the gurgling, and loud enough to be heard over the engine)
  gad_kaffee(dir) { seed = 203; const m = Mix(9); { let ph = 0, lp = 0; for (let i = 0; i < m.n; i++) { const t = i / SR, e = Math.min(1, t / 0.25) * Math.min(1, (8.6 - t) / 0.4); if (e <= 0) continue; ph += TAU * (50 + Math.sin(t * 3.1) * 1.5) / SR; lp += ((rnd() * 2 - 1) - lp) * 0.08; const buzz = Math.sign(Math.sin(ph)) * 0.35 + Math.sin(ph * 2) * 0.5 + Math.sin(ph * 3) * 0.25; put(m, i, (buzz * 0.18 + lp * 0.12) * e * (0.85 + 0.15 * Math.sin(t * 9)), 0, 0.05) } } for (let t = 0.3; t < 8.4; t += 0.05 + rnd() * 0.16) { const f0 = 170 + rnd() * 420, i0 = Math.floor(t * SR), N = Math.floor(0.09 * SR); for (let k = 0; k < N; k++) { const q = k / N; put(m, i0 + k, Math.sin(TAU * f0 * (1 + q * 0.6) * k / SR) * Math.sin(q * Math.PI) * 0.5, 0, 0.1) } } wind(m, 0.03); reverb(m, 0.5, 0.06); finish(m, dir, 'gad_kaffee', -15, 0.2, 0.6) },
  gad_werkstatt(dir) { seed = 213; const m = Mix(10.5)
    const clink = (t, f, a, p) => { const i0 = Math.floor(t * SR); for (let k = 0; k < 0.5 * SR; k++) { const q = k / SR; put(m, i0 + k, (Math.sin(TAU * f * q) + 0.6 * Math.sin(TAU * f * 2.76 * q) + 0.3 * Math.sin(TAU * f * 5.4 * q)) * Math.exp(-q / 0.09) * a, p, 0.35) } }
    const ratchet = (t, n, p) => { for (let i = 0; i < n; i++) { const i0 = Math.floor((t + i * 0.075) * SR); let lp = 0; for (let k = 0; k < 500; k++) { lp += ((rnd() * 2 - 1) - lp) * 0.75; put(m, i0 + k, lp * Math.exp(-k / 70) * 0.8, p, 0.25) } } }
    const impact = (t, dur, p) => { const i0 = Math.floor(t * SR), N = Math.floor(dur * SR); let ph = 0; for (let k = 0; k < N; k++) { const q = k / N, f = 95 + 40 * Math.min(1, q * 4); ph += TAU * f / SR; const g = 0.55 + 0.45 * Math.sign(Math.sin(ph * 0.5)); put(m, i0 + k, (((ph % TAU) / Math.PI - 1) * 0.55 + (rnd() - 0.5) * 0.3) * g * Math.min(1, q * 30) * Math.min(1, (1 - q) * 30) * 0.5, p, 0.2) } }
    ratchet(0.4, 12, -0.3); clink(1.6, 1250, 0.3, 0.4); impact(2.3, 1.1, 0.25); clink(3.7, 880, 0.35, -0.4); ratchet(4.2, 9, 0.35); clink(5.2, 1650, 0.22, 0.1); impact(5.8, 1.5, -0.2); clink(7.6, 1050, 0.3, 0.5); ratchet(8, 8, -0.1); clink(9.2, 1400, 0.3, 0); wind(m, 0.015); reverb(m, 0.72, 0.13); finish(m, dir, 'gad_werkstatt', -20, 0.1, 0.5) },
  gag_furz(dir) { seed = 205; const m = Mix(1.5); let ph = 0; for (let k = 0; k < 1.25 * SR; k++) { const t = k / SR, f = 92 - 26 * t + Math.sin(t * 62) * 22 + (rnd() - 0.5) * 34; ph += TAU * f / SR; const a = Math.min(1, t / 0.03) * Math.min(1, (1.25 - t) / 0.12) * (0.55 + 0.45 * Math.sin(t * 44)); put(m, k, ((ph % TAU) / Math.PI - 1) * a + (rnd() - 0.5) * 0.14 * a, 0, 0) } finish(m, dir, 'gag_furz', -14, 0.01, 0.05) },
  gag_muh(dir) { seed = 207; const m = Mix(2.3); for (let n = 1; n < 14; n++) { const g = Math.exp(-Math.pow((n * 130 - 420) / 300, 2)) + 0.5 * Math.exp(-Math.pow((n * 130 - 1050) / 260, 2)); for (let k = 0; k < 2.1 * SR; k++) { const t = k / SR, e = Math.min(1, t / 0.25) * Math.min(1, (2.1 - t) / 0.4), f = 118 + 26 * Math.sin(Math.min(1, t / 1.8) * Math.PI); put(m, k, Math.sin(TAU * f * n * t) * g * e * 0.3, 0, 0.1) } } reverb(m, 0.6, 0.05); finish(m, dir, 'gag_muh', -15, 0.01, 0.1) },
  gag_tusch(dir) { seed = 209; const m = Mix(2.4); [[60, 64, 67], [60, 64, 67], [65, 69, 72, 77]].forEach((c, i) => c.forEach(n => reed(m, n, [0.05, 0.28, 0.5][i], i < 2 ? 0.18 : 1.5, 0.2, { pan: 0 }))); reverb(m, 0.72, 0.1); finish(m, dir, 'gag_tusch', -16, 0.01, 0.2) },
  gag_applaus(dir) { seed = 211; const m = Mix(3.2); for (let n = 0; n < 340; n++) { const t = 0.1 + rnd() * 2.7, i0 = Math.floor(t * SR), a = (0.4 + rnd() * 0.6) * Math.min(1, t / 0.6) * Math.min(1, (3 - t) / 0.8), p = rnd() * 1.6 - 0.8; let lp = 0; for (let k = 0; k < 340; k++) { const v = rnd() * 2 - 1; lp += (v - lp) * 0.45; put(m, i0 + k, (v - lp) * Math.exp(-k / 70) * a, p, 0.25) } } reverb(m, 0.55, 0.06); finish(m, dir, 'gag_applaus', -17, 0.02, 0.2) },
}
const dir = path.join(process.argv[2], 'art/sound/fernfahrer/mood'); fs.mkdirSync(dir, { recursive: true })
const list = []
for (const name of Object.keys(W)) W[name](dir, list)
for (const name of Object.keys(GAD)) GAD[name](dir)
knocks(dir, 'klopf1', [0, 0.21], 1, list); knocks(dir, 'klopf2', [0, 0.15, 0.3, 0.78, 0.92], 1.2, list)
if (process.argv[3]) {   // a bit of each, one after the other
  const ORDER = list.map(m => m), each = 14, gap = Math.floor(0.8 * SR); let tot = 0; for (const m of ORDER) tot += Math.min(m.n, each * SR) + gap
  const buf = Buffer.alloc(44 + tot * 4); buf.write('RIFF', 0); buf.writeUInt32LE(36 + tot * 4, 4); buf.write('WAVEfmt ', 8); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(2, 22); buf.writeUInt32LE(SR, 24); buf.writeUInt32LE(SR * 4, 28); buf.writeUInt16LE(4, 32); buf.writeUInt16LE(16, 34); buf.write('data', 36); buf.writeUInt32LE(tot * 4, 40)
  let o = 44; for (const m of ORDER) { const n = Math.min(m.n, each * SR), fo = Math.floor(1.2 * SR); for (let i = 0; i < n; i++) { const e = n === m.n ? 1 : Math.min(1, (n - i) / fo); buf.writeInt16LE(Math.round(Math.max(-1, Math.min(1, m.L[i] * e)) * 32767), o); buf.writeInt16LE(Math.round(Math.max(-1, Math.min(1, m.R[i] * e)) * 32767), o + 2); o += 4 } o += gap * 4 }
  fs.writeFileSync(process.argv[3], buf)
}
