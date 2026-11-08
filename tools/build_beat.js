// The music of the loading screens, made from nothing but maths (no samples, nothing anyone else owns): a hard hip-hop beat
// in G minor at 92 BPM – 808 bass and heavy drums – played with truck sounds: the starter and the diesel, the air brake as
// the open hat, the indicator as a percussion tick, the air horn as the brass hook, a turbo whistle in the break, a
// gear change as a fill. 32 bars that loop without a seam. node tools/build_beat.js <out.wav>
const fs = require('fs')
const out = process.argv[2]
const SR = 44100, BPM = 92, BEAT = 60 / BPM, BAR = BEAT * 4, BARS = 32
const N = Math.round(BAR * BARS * SR)
let seed = 12345
function rnd() { seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 4294967296 }
const noise = () => rnd() * 2 - 1
const bus = () => ({ l: new Float32Array(N), r: new Float32Array(N) })
const B = { drums: bus(), bass: bus(), music: bus(), fx: bus(), send: bus() }
const TAU = Math.PI * 2
function put(b, i, v, pan) { i = ((i % N) + N) % N; const p = (pan + 1) * Math.PI / 4; b.l[i] += v * Math.cos(p); b.r[i] += v * Math.sin(p) }
const at = (bar, beat) => (bar - 1) * BAR + beat * BEAT
const midi = m => 440 * Math.pow(2, (m - 69) / 12)
const SW = 0.018                                              // (the swing of the off sixteenths, s)
const step = (bar, s) => at(bar, s / 4) + (s % 2 ? SW : 0)

function kick(t0, v = 1) {
  const len = Math.floor(0.34 * SR), s = Math.floor(t0 * SR); let ph = 0
  for (let i = 0; i < len; i++) {
    const t = i / SR, f = 50 + 150 * Math.exp(-t * 38); ph += TAU * f / SR
    const e = Math.exp(-t * 9), c = t < 0.006 ? noise() * 0.5 * (1 - t / 0.006) : 0
    put(B.drums, s + i, v * (Math.tanh(Math.sin(ph) * 2.2) * e * 0.95 + c), 0)
  }
}
function bass808(t0, f, dur, v = 1) {
  const len = Math.floor((dur + 0.08) * SR), s = Math.floor(t0 * SR); let ph = 0
  for (let i = 0; i < len; i++) {
    const t = i / SR, fr = f * (1 + 0.55 * Math.exp(-t * 34)); ph += TAU * fr / SR
    const e = Math.min(1, t / 0.004) * Math.exp(-t * 0.9) * Math.min(1, (dur + 0.08 - t) / 0.06)
    // (saturated: its harmonics are what small speakers can play)
    put(B.bass, s + i, v * Math.tanh(Math.sin(ph) * 3.2) * e * 0.62, 0)
  }
}
function snare(t0, v = 1) {
  const len = Math.floor(0.3 * SR), s = Math.floor(t0 * SR); let lp = 0, ph = 0
  for (let i = 0; i < len; i++) {
    const t = i / SR, n = noise(); lp += 0.32 * (n - lp); ph += TAU * (205 - 30 * Math.min(1, t * 20)) / SR
    // (three hands of a clap in front of the body)
    const clap = (t < 0.009 ? 1 : (t > 0.013 && t < 0.021 ? 0.8 : (t > 0.026 ? Math.exp(-(t - 0.026) * 24) : 0)))
    const x = (n - lp) * clap * 0.72 + Math.sin(ph) * Math.exp(-t * 26) * 0.42 + lp * Math.exp(-t * 18) * 0.3
    put(B.drums, s + i, x * v, 0); put(B.send, s + i, x * v * 0.34, 0)
  }
}
function hat(t0, v = 1, pan = 0.18, len_ = 0.05) {
  const len = Math.floor(len_ * SR), s = Math.floor(t0 * SR); let a = 0, b = 0
  for (let i = 0; i < len; i++) {
    const n = noise(); a += 0.7 * (n - a); b += 0.4 * (a - b)
    put(B.drums, s + i, (a - b) * Math.exp(-i / SR * (3.4 / len_)) * v * 0.5, pan)
  }
}
// the air brake: a hard hiss that falls away – the open hat of this beat
function airBrake(t0, v = 1, dur = 0.55) {
  const len = Math.floor(dur * SR), s = Math.floor(t0 * SR); let a = 0, b = 0, ph = 0
  for (let i = 0; i < len; i++) {
    const t = i / SR, k = t / dur, n = noise()
    a += (0.62 - 0.42 * k) * (n - a); b += 0.05 * (a - b)
    ph += TAU * (3100 - 1200 * k) / SR
    const e = Math.min(1, t / 0.006) * Math.pow(1 - k, 1.4)
    const x = ((a - b) * 0.8 + Math.sin(ph) * 0.05) * e * v
    put(B.fx, s + i, x * 0.72, -0.35 + 0.7 * k); put(B.send, s + i, x * 0.22, 0)
  }
}
// the indicator's relay: tick – tock
function tick(t0, hi, v = 1) {
  const len = Math.floor(0.03 * SR), s = Math.floor(t0 * SR)
  for (let i = 0; i < len; i++) {
    const t = i / SR, f = hi ? 2350 : 1720
    const x = (Math.sin(TAU * f * t) + 0.6 * Math.sin(TAU * f * 1.51 * t) + noise() * 0.5) * Math.exp(-t * 240) * v * 0.3
    put(B.fx, s + i, x, hi ? 0.34 : -0.34)
  }
}
// a gear going in: a dull clunk, for the fills
function clunk(t0, v = 1) {
  const len = Math.floor(0.12 * SR), s = Math.floor(t0 * SR); let a = 0
  for (let i = 0; i < len; i++) {
    const t = i / SR; a += 0.14 * (noise() - a)
    put(B.drums, s + i, (a * 2.6 * Math.exp(-t * 44) + Math.sin(TAU * 118 * t) * Math.exp(-t * 36) * 0.7) * v, -0.1)
  }
}
// the air horn: reedy, a little out of tune with itself, a short attack – the brass of the track
function horn(t0, notes, dur, v = 1, bright = 1) {
  const len = Math.floor((dur + 0.14) * SR), s = Math.floor(t0 * SR)
  notes.forEach((m, nIdx) => {
    const f0 = midi(m)
    ;[-5, 4, 11].forEach((c, vIdx) => {
      const f = f0 * Math.pow(2, c / 1200); let ph = rnd(), lp = 0
      const pan = (vIdx - 1) * 0.42 + (nIdx - 1) * 0.08
      for (let i = 0; i < len; i++) {
        const t = i / SR; ph += f * (1 + 0.004 * Math.sin(TAU * 5.3 * t)) / SR; ph -= Math.floor(ph)
        // (between a saw and a square: the reed)
        const w = (2 * ph - 1) * 0.55 + (ph < 0.42 ? 0.5 : -0.5)
        const cut = (0.1 + 0.2 * Math.exp(-t * 7)) * bright
        lp += cut * (w - lp)
        const e = Math.min(1, t / 0.012) * (0.72 + 0.28 * Math.exp(-t * 6)) * Math.min(1, Math.max(0, (dur + 0.14 - t) / 0.13))
        const x = lp * e * v * 0.115
        put(B.music, s + i, x, pan); put(B.send, s + i, x * 0.26, 0)
      }
    })
  })
}
// a dark pad under it
function pad(t0, notes, dur, v = 1) {
  const len = Math.floor(dur * SR), s = Math.floor(t0 * SR)
  notes.forEach((m, n) => {
    const f = midi(m); let ph1 = rnd(), ph2 = rnd(), lp = 0
    for (let i = 0; i < len; i++) {
      const t = i / SR; ph1 += f * 1.003 / SR; ph2 += f * 0.997 / SR; ph1 -= Math.floor(ph1); ph2 -= Math.floor(ph2)
      lp += 0.05 * ((ph1 + ph2) - 1 - lp)
      const e = Math.min(1, t / 0.4) * Math.min(1, (dur - t) / 0.45)
      put(B.music, s + i, lp * e * v * 0.1, n % 2 ? 0.5 : -0.5)
    }
  })
}
// the bell of the top line
function bell(t0, m, v = 1, pan = 0.25) {
  const len = Math.floor(0.95 * SR), s = Math.floor(t0 * SR), f = midi(m)
  for (let i = 0; i < len; i++) {
    const t = i / SR
    const x = Math.sin(TAU * f * t + 1.9 * Math.exp(-t * 7) * Math.sin(TAU * f * 3.01 * t)) * Math.exp(-t * 4.2) * v * 0.17
    put(B.music, s + i, x, pan); put(B.send, s + i, x * 0.5, 0)
  }
}
// the starter, turning over, then the diesel catches
function starter(t0) {
  const len = Math.floor(1.45 * SR), s = Math.floor(t0 * SR); let ph = 0, a = 0
  for (let i = 0; i < len; i++) {
    const t = i / SR, f = 9.5 + 7 * Math.min(1, t / 1.2); ph += f / SR
    a += 0.1 * (noise() - a)
    const chug = Math.pow(0.5 + 0.5 * Math.sin(TAU * ph), 3)
    const whine = Math.sin(TAU * (420 + 240 * Math.min(1, t)) * t) * 0.05
    const e = Math.min(1, t / 0.05) * Math.min(1, (1.45 - t) / 0.1)
    put(B.fx, s + i, (chug * (a * 2.2 + Math.sin(TAU * 62 * t) * 0.45) + whine) * e * 0.28, 0)
  }
}
// the diesel: firing pulses of a six-cylinder, felt rather than heard
function diesel(from, to, rpm, v) {
  const a = Math.floor(from * SR), b = Math.floor(to * SR); let ph = 0, lp = 0, wob = 0
  for (let i = a; i < b; i++) {
    const t = (i - a) / SR; wob += 0.0004 * (noise() - wob * 4)
    ph += (rpm / 60 * 3) * (1 + wob * 2) / SR; ph -= Math.floor(ph)
    const pulse = Math.exp(-ph * 7) * (1 + 0.3 * noise())
    lp += 0.09 * (pulse - lp)
    const e = Math.min(1, t / 0.15) * Math.min(1, ((b - a) / SR - t) / 0.25)
    put(B.fx, i, (lp - 0.14) * e * v, 0)
  }
}
function turbo(t0, dur, v = 1) {
  const len = Math.floor(dur * SR), s = Math.floor(t0 * SR); let ph = 0, a = 0
  for (let i = 0; i < len; i++) {
    const t = i / SR, k = t / dur; ph += TAU * (900 + 5200 * k * k) / SR; a += 0.3 * (noise() - a)
    const x = (Math.sin(ph) * 0.13 + a * 0.2 * k) * k * Math.min(1, (dur - t) / 0.03) * v
    put(B.fx, s + i, x, Math.sin(k * 9) * 0.5); put(B.send, s + i, x * 0.3, 0)
  }
}

// --- the song ---------------------------------------------------------------------------------------------------------
const G = 31, Eb = 27, D = 26                                    // (808 roots, midi: G1, D#1, D1)
const CH = [ { root: G, tri: [55, 58, 62] }, { root: G, tri: [55, 58, 62] }, { root: Eb, tri: [51, 55, 58] }, { root: D, tri: [50, 54, 57] } ]
const chordOf = bar => CH[(bar - 1) % 4]
// the 808's rhythm in sixteenths of a bar and its length in sixteenths
const BASS = [[0, 5], [6, 2], [8, 3], [11, 2], [14, 2]]
// the horn hook: [sixteenth, length in sixteenths]
const HOOK = [[0, 2], [3, 2], [6, 1], [8, 3], [12, 1], [14, 2]]
const TOP = [74, 70, 69, 67, 70, 69, 65, 62]

function drums(bar, opts = {}) {
  ;[[0, 1], [7, 0.7], [10, 0.95]].forEach(([s, v]) => kick(step(bar, s), v))
  if (bar % 4 === 0) kick(step(bar, 15), 0.7)
  if (!opts.noSnare) {
    snare(step(bar, 4), 1); snare(step(bar, 12), 1)
    if (bar % 8 === 0) { snare(step(bar, 14), 0.55); snare(step(bar, 15), 0.75) }
  }
  for (let s = 0; s < 16; s++) {
    if (s % 2 === 0 || opts.busy) hat(step(bar, s), s % 4 === 2 ? 1 : 0.62, 0.18)
    if (opts.busy && bar % 2 === 0 && s >= 12 && s % 2 === 1) { hat(step(bar, s) + BEAT / 12, 0.42, -0.18); hat(step(bar, s) + BEAT / 6, 0.42, 0.18) }
  }
  airBrake(step(bar, 2) + BEAT * 3, 0.55, 0.3)
}
function ticks(bar, v = 1) { for (let b = 0; b < 4; b++) { tick(at(bar, b + 0.5), true, v); tick(at(bar, b + 1), false, v) } }
function bass(bar) { const c = chordOf(bar); BASS.forEach(([s, l]) => bass808(step(bar, s), midi(c.root), l * BEAT / 4 * 1.05, 1)) }
function hook(bar, v = 1, bright = 1) { const c = chordOf(bar); HOOK.forEach(([s, l]) => horn(step(bar, s), c.tri, l * BEAT / 4 * 0.95, v, bright)) }
function top(bar) { [0, 3, 6, 8].forEach((s, k) => bell(step(bar, s), TOP[((bar - 1) % 2) * 4 + k], 1, k % 2 ? 0.3 : -0.3)) }
function padBars(bar, n = 1, v = 1) { const c = chordOf(bar); pad((bar - 1) * BAR, c.tri.map(m => m - 12), n * BAR + 0.3, v) }

// 1-4: the cab: the key, the diesel, the indicator, the first horn
// (2026-11-08: a calm start – the first version opened far too loud on a loading screen)
starter(0.05); diesel(1.5, BAR * 4, 760, 0.2)
airBrake(at(2, 1), 0.3, 0.75)
ticks(2, 0.4); ticks(3, 0.48); ticks(4, 0.55)
horn(step(3, 0), chordOf(1).tri, BEAT * 1.4, 0.34, 0.5); horn(step(3, 8), chordOf(1).tri, BEAT * 1.4, 0.34, 0.5)
hook(4, 0.4, 0.55)
for (let i = 1; i <= 4; i++) padBars(i, 1, 0.75)
kick(step(4, 14), 0.4); clunk(step(4, 15), 0.45)
turbo(at(4, 2), BEAT * 2, 0.3)
// 5-12: the beat
for (let b = 5; b <= 12; b++) { drums(b); bass(b); hook(b); padBars(b); if (b % 4 === 0) { clunk(step(b, 13), 0.9); airBrake(at(b, 3.5), 0.9, 0.42) } }
// 13-20: the top line on it, the hats busy
for (let b = 13; b <= 20; b++) { drums(b, { busy: true }); bass(b); hook(b, 0.82); top(b); padBars(b); if (b % 4 === 0) clunk(step(b, 13), 0.9) }
// 21-24: the break: the diesel under ticks and horn, the turbo spools up
diesel(at(21, 0), at(25, 0), 1050, 0.5)
for (let b = 21; b <= 24; b++) { ticks(b, 0.9); padBars(b, 1, 1.1); top(b); kick(step(b, 0), 0.95); if (b >= 23) hook(b, 0.7, 0.75) }
snare(step(24, 12), 0.7); snare(step(24, 14), 0.8); snare(step(24, 15), 0.95)
turbo(at(23, 0), BAR * 2 - 0.02, 1)
airBrake(at(24, 3.5), 1, 0.45)
// 25-32: all of it
for (let b = 25; b <= 32; b++) { drums(b, { busy: true }); bass(b); hook(b, 1, 1.15); top(b); padBars(b); ticks(b, 0.42); if (b % 4 === 0) clunk(step(b, 13), 1) }
airBrake(at(32, 3), 1, 0.9)

// --- the mix -----------------------------------------------------------------------------------------------------------
// a small room for the send (run round twice so its tail comes out at the start of the loop)
function reverb(b) {
  const taps = [1553, 1871, 2243, 2719], gains = [0.62, 0.6, 0.57, 0.55], l = new Float32Array(N), r = new Float32Array(N)
  taps.forEach((d, k) => {
    const yl = new Float32Array(N), yr = new Float32Array(N), dr = d + 37
    for (let pass = 0; pass < 2; pass++) for (let i = 0; i < N; i++) {
      yl[i] = b.l[i] + gains[k] * yl[(i - d + N) % N]
      yr[i] = b.r[i] + gains[k] * yr[(i - dr + N) % N]
    }
    for (let i = 0; i < N; i++) { l[i] += yl[i] / 4; r[i] += yr[i] / 4 }
  })
  return { l, r }
}
const rev = reverb(B.send)
// the kick presses the music and the bass down a little
const duck = new Float32Array(N); { let e = 0; for (let pass = 0; pass < 2; pass++) for (let i = 0; i < N; i++) { const x = Math.abs(B.drums.l[i]) > 0.5 ? 1 : 0; e = x > e ? x : e * 0.99975; duck[i] = e } }
const L = new Float32Array(N), R = new Float32Array(N)
for (let i = 0; i < N; i++) {
  const d = 1 - 0.42 * duck[i], d2 = 1 - 0.2 * duck[i]
  const l = B.drums.l[i] * 0.86 + B.bass.l[i] * d2 * 0.82 + B.music.l[i] * d * 1.05 + B.fx.l[i] * 0.85 + rev.l[i] * 0.7
  const r = B.drums.r[i] * 0.86 + B.bass.r[i] * d2 * 0.82 + B.music.r[i] * d * 1.05 + B.fx.r[i] * 0.85 + rev.r[i] * 0.7
  L[i] = Math.tanh(l * 1.15); R[i] = Math.tanh(r * 1.15)
}
// (below 24 Hz out – nothing there to hear, it only eats headroom; run round twice so it has settled at the start)
for (const ch of [L, R]) {
  const k = Math.exp(-TAU * 24 / SR); let x1 = 0, y1 = 0
  const y = new Float32Array(N)
  for (let pass = 0; pass < 2; pass++) for (let i = 0; i < N; i++) { y1 = k * (y1 + ch[i] - x1); x1 = ch[i]; y[i] = y1 }
  ch.set(y)
}
// (no click where the file starts and ends)
const FADE = Math.floor(0.012 * SR)
for (let i = 0; i < FADE; i++) { const f = i / FADE; L[i] *= f; R[i] *= f; L[N - 1 - i] *= f; R[N - 1 - i] *= f }
let peak = 0; for (let i = 0; i < N; i++) peak = Math.max(peak, Math.abs(L[i]), Math.abs(R[i]))
const g = 0.45 / peak                                          // (quiet in the file itself: it plays over a loading screen)
const pcm = Buffer.alloc(N * 4)
for (let i = 0; i < N; i++) { pcm.writeInt16LE(Math.round(L[i] * g * 32767), i * 4); pcm.writeInt16LE(Math.round(R[i] * g * 32767), i * 4 + 2) }
const h = Buffer.alloc(44); h.write('RIFF', 0); h.writeUInt32LE(36 + pcm.length, 4); h.write('WAVEfmt ', 8); h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(2, 22)
h.writeUInt32LE(SR, 24); h.writeUInt32LE(SR * 4, 28); h.writeUInt16LE(4, 32); h.writeUInt16LE(16, 34); h.write('data', 36); h.writeUInt32LE(pcm.length, 40)
fs.writeFileSync(out, Buffer.concat([h, pcm]))

// what can be checked without ears
const report = []
for (let b = 1; b <= BARS; b += 1) {
  const a = Math.floor((b - 1) * BAR * SR), z = Math.floor(b * BAR * SR); let s = 0, lo = 0, lp = 0
  for (let i = a; i < z; i += 2) { const x = (L[i] + R[i]) / 2 * g; s += x * x; lp += 0.0142 * (x - lp); lo += lp * lp }
  report.push((b + ':' + (10 * Math.log10(s / ((z - a) / 2) + 1e-9)).toFixed(0) + '/' + (10 * Math.log10(lo / ((z - a) / 2) + 1e-9)).toFixed(0)))
}
let dc = 0, clip = 0; for (let i = 0; i < N; i++) { dc += L[i] * g; if (Math.abs(L[i] * g) > 0.999) clip++ }
console.log(`${(N / SR).toFixed(1)} s, ${(pcm.length / 1048576).toFixed(1)} MB, raw peak ${peak.toFixed(2)}, dc ${(dc / N).toFixed(4)}, clipped ${clip}, seam jump ${Math.abs(L[0] - L[N - 1]).toFixed(3)}`)
console.log('bar:RMS dB/below 100 Hz dB  ' + report.join(' '))
