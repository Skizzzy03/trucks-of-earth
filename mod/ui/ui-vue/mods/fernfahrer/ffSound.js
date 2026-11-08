// Trucks of Earth: the menus' sounds, one set for every screen of the mode (title screen, stop menu, loading
// screen): short, quiet, made with Web Audio – nothing to load. sound("hover" | "click" | "back" | "open" | "done")

let ac = null
function ctx() {
  try {
    if (!ac) ac = new (window.AudioContext || window.webkitAudioContext)()
    if (ac.state === "suspended") ac.resume()
  } catch (e) { ac = null }
  return ac
}

function tone(type, f0, f1, dur, vol, at = 0) {
  const a = ctx()
  if (!a) return
  const t0 = a.currentTime + at, o = a.createOscillator(), g = a.createGain()
  o.type = type
  o.frequency.setValueAtTime(f0, t0)
  o.frequency.exponentialRampToValueAtTime(f1, t0 + dur)
  g.gain.setValueAtTime(0.0001, t0)
  g.gain.linearRampToValueAtTime(vol, t0 + 0.006)
  g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur)
  o.connect(g); g.connect(a.destination)
  o.start(t0); o.stop(t0 + dur + 0.02)
}

function whoosh(dur, vol) {
  const a = ctx()
  if (!a) return
  const n = Math.floor(a.sampleRate * dur), buf = a.createBuffer(1, n, a.sampleRate), d = buf.getChannelData(0)
  for (let i = 0; i < n; i++) d[i] = (Math.random() * 2 - 1) * Math.sin(Math.PI * i / n)
  const s = a.createBufferSource(), f = a.createBiquadFilter(), g = a.createGain()
  s.buffer = buf; f.type = "bandpass"; f.Q.value = 0.9
  f.frequency.setValueAtTime(400, a.currentTime); f.frequency.exponentialRampToValueAtTime(2400, a.currentTime + dur)
  g.gain.value = vol
  s.connect(f); f.connect(g); g.connect(a.destination)
  s.start(); s.stop(a.currentTime + dur)
}

const SOUNDS = {
  hover: () => tone("sine", 1800, 1600, 0.04, 0.025),
  click: () => { tone("triangle", 660, 660, 0.07, 0.07); tone("triangle", 990, 990, 0.09, 0.06, 0.055) },
  back: () => { tone("triangle", 700, 700, 0.06, 0.06); tone("triangle", 470, 470, 0.08, 0.05, 0.05) },
  open: () => whoosh(0.28, 0.12),
  done: () => { tone("sine", 523, 523, 0.12, 0.06); tone("sine", 659, 659, 0.12, 0.06, 0.09); tone("sine", 784, 784, 0.2, 0.06, 0.18) },
}

let lastHover = 0
export function sound(name) {
  if (name === "hover") {                       // (not a rattle when the mouse sweeps over a list)
    const t = Date.now()
    if (t - lastHover < 70) return
    lastHover = t
  }
  try { SOUNDS[name] && SOUNDS[name]() } catch (e) { /* no audio */ }
}
