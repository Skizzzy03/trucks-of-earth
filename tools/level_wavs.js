// The level of a folder of 16-bit mono WAV files: node level_wavs.js <dir>            prints the loudness (RMS, peak)
//                                                  node level_wavs.js <dir> <rms dB>   brings every file to that loudness
const fs = require('fs'), path = require('path')
const [dir, want] = process.argv.slice(2)
function data(b) { let p = 12; while (p + 8 < b.length) { const id = b.toString('latin1', p, p + 4), n = b.readUInt32LE(p + 4); if (id === 'data') return { at: p + 8, n: Math.min(n, b.length - p - 8) }; p += 8 + n + (n & 1) } throw new Error('no data') }
function rmsOf(b, d) { let s = 0, c = 0, pk = 0; for (let i = d.at; i + 1 < d.at + d.n; i += 2) { const x = b.readInt16LE(i) / 32768; if (Math.abs(x) > 0.02) { s += x * x; c++ } pk = Math.max(pk, Math.abs(x)) } return { rms: Math.sqrt(s / Math.max(1, c)), pk } }
let sum = 0, n = 0, maxPk = 0, minS = 1e9, maxS = 0, rate = 0
for (const f of fs.readdirSync(dir).filter(x => x.endsWith('.wav'))) {
  const file = path.join(dir, f), b = fs.readFileSync(file), d = data(b)
  rate = b.readUInt32LE(24)
  let r = rmsOf(b, d)
  if (want !== undefined) {
    // (a fourth argument "limit": as loud as asked, the peaks rounded off instead of holding the gain back)
    const limit = process.argv[4] === 'limit', T = 0.72
    const g = limit ? Math.pow(10, Number(want) / 20) / r.rms : Math.min(Math.pow(10, Number(want) / 20) / r.rms, 0.97 / r.pk)
    const shape = x => { const a = Math.abs(x); return a <= T ? x : Math.sign(x) * (T + (0.985 - T) * Math.tanh((a - T) / (0.985 - T))) }
    for (let i = d.at; i + 1 < d.at + d.n; i += 2) b.writeInt16LE(Math.round(shape(b.readInt16LE(i) / 32768 * g) * 32767), i)
    fs.writeFileSync(file, b); r = rmsOf(b, d)
  }
  sum += 20 * Math.log10(r.rms); n++; maxPk = Math.max(maxPk, r.pk)
  const s = d.n / 2 / rate; minS = Math.min(minS, s); maxS = Math.max(maxS, s)
}
console.log(`${n} Dateien, ${rate} Hz, RMS ${(sum / n).toFixed(1)} dB, Spitze ${maxPk.toFixed(2)}, Länge ${minS.toFixed(2)}-${maxS.toFixed(2)} s`)
