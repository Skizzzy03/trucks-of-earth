// The driving school's short films, drawn on a small canvas: no video files, next to no load, and only the one being watched runs.
// clips[i].draw(ctx, t, W, H): t in seconds; W, H the logical size (640 x 360); after clips[i].len the film starts again.
// One look for all of them, the game's own: dusk colours, dark glass panels with an amber edge, the title in the corner, a running bar along the bottom.
const OK = "#3ad38b", AMBER = "#ffb12e", BAD = "#ff5b4d", BLUE = "#4d9bff", GLASS = "rgba(12,16,22,.84)"
const clamp = (x, a, b) => Math.min(b, Math.max(a, x)), ramp = (t, a, b) => clamp((t - a) / (b - a), 0, 1), ease = x => x * x * (3 - 2 * x)
const font = (w, s) => `${w} ${s}px FFWave,Noto Sans,Segoe UI,sans-serif`
const hash = i => { const s = Math.sin(i * 127.1) * 43758.5453; return s - Math.floor(s) }

function rr(c, x, y, w, h, r) { c.beginPath(); c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r); c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath() }
const SKIES = {
  dusk: { sky: ["#23395c", "#8a6a7c", "#f2a765"], hill: ["#6d5f76", "#46455c", "#2d3241"], tree: "#1b2329", ground: ["#2b3524", "#1a2118"], sun: ["#ffe2a6", 470, 150, 34], road: "#2c3138", line: "#d9dee4" },
  day: { sky: ["#3f76ad", "#8fb9d8", "#e6dfc9"], hill: ["#7f9bab", "#5f7f7f", "#47674f"], tree: "#2c4a2e", ground: ["#4d6e38", "#31482a"], sun: ["#fff3cf", 520, 70, 26], road: "#3a4048", line: "#e6eaee" },
  night: { sky: ["#060a15", "#0e1a31", "#22324f"], hill: ["#1c2a40", "#141f31", "#0d1623"], tree: "#090f18", ground: ["#10171a", "#090e11"], moon: 1, road: "#1b1f25", line: "#a7afb9" },
}
// the world seen from the side, moving by "s" metres of scroll: sky, three layers of hills, trees, a guard rail, the road, the verge
function world(c, W, H, gy, s, name) {
  const P = SKIES[name || "dusk"], g = c.createLinearGradient(0, 0, 0, gy)
  g.addColorStop(0, P.sky[0]); g.addColorStop(0.62, P.sky[1]); g.addColorStop(1, P.sky[2]); c.fillStyle = g; c.fillRect(-60, -60, W + 120, gy + 70)
  if (P.moon) { for (let i = 0; i < 46; i++) { c.fillStyle = `rgba(255,255,255,${0.3 + hash(i) * 0.6})`; c.fillRect(hash(i + 50) * W, hash(i + 90) * gy * 0.72, 1.6, 1.6) } c.fillStyle = "#e7ecf5"; c.beginPath(); c.arc(508, 62, 22, 0, 7); c.fill(); c.fillStyle = P.sky[0]; c.beginPath(); c.arc(517, 57, 19, 0, 7); c.fill() }
  if (P.sun) { const [col, x, y, r] = P.sun, h = c.createRadialGradient(x, y, 2, x, y, r * 5); h.addColorStop(0, "rgba(255,226,166,.75)"); h.addColorStop(1, "rgba(255,226,166,0)"); c.fillStyle = h; c.fillRect(-60, -60, W + 120, gy + 70); c.fillStyle = col; c.beginPath(); c.arc(x, y, r, 0, 7); c.fill() }
  P.hill.forEach((col, k) => {
    const par = [0.06, 0.13, 0.26][k], base = gy - [78, 52, 26][k], A = [34, 24, 15][k]
    c.fillStyle = col; c.beginPath(); c.moveTo(-60, gy + 2)
    for (let x = -60; x <= W + 60; x += 14) { const u = x + s * par; c.lineTo(x, base - A * Math.sin(u * 0.009 + k * 2) - A * 0.45 * Math.sin(u * 0.023 + k)) }
    c.lineTo(W + 60, gy + 2); c.fill()
  })
  c.fillStyle = P.tree; const step = 34, first = Math.floor((s * 0.55 - 80) / step)
  for (let i = first; i * step - s * 0.55 < W + 80; i++) { const x = i * step - s * 0.55, h = 26 + hash(i) * 34, w = 11 + hash(i + 7) * 8; c.beginPath(); c.moveTo(x - w, gy); c.lineTo(x, gy - h); c.lineTo(x + w, gy); c.fill() }
  const road = c.createLinearGradient(0, gy, 0, H + 60); road.addColorStop(0, P.ground[0]); road.addColorStop(1, P.ground[1]); c.fillStyle = road; c.fillRect(-60, gy, W + 120, H + 60 - gy)
  c.fillStyle = P.road; c.fillRect(-60, gy + 6, W + 120, 30); c.fillStyle = "rgba(255,255,255,.08)"; c.fillRect(-60, gy + 6, W + 120, 1.5)
  c.strokeStyle = P.line; c.lineWidth = 2; c.setLineDash([24, 44]); c.lineDashOffset = s; c.beginPath(); c.moveTo(-60, gy + 21); c.lineTo(W + 60, gy + 21); c.stroke(); c.setLineDash([])
  c.fillStyle = "#8d949c"; c.fillRect(-60, gy - 7, W + 120, 3); const po = 68, f2 = Math.floor((s - 80) / po); for (let i = f2; i * po - s < W + 80; i++) c.fillRect(i * po - s, gy - 7, 3, 13)
}
function wheel(c, x, y, r, spin, hot, flat) {
  c.save(); c.translate(x, y)
  if (hot > 0.15) { const h = c.createRadialGradient(0, 0, r * 0.3, 0, 0, r * 2); h.addColorStop(0, `rgba(255,${130 - 70 * hot},30,${0.75 * hot})`); h.addColorStop(1, "rgba(255,80,20,0)"); c.fillStyle = h; c.beginPath(); c.arc(0, 0, r * 2, 0, 7); c.fill() }
  c.scale(1, flat ? 0.66 : 1); if (flat) c.translate(0, r * 0.26)
  c.beginPath(); c.arc(0, 0, r, 0, 7); c.fillStyle = "#101317"; c.fill(); c.strokeStyle = "#2a2f36"; c.lineWidth = Math.max(1, r * 0.1); c.beginPath(); c.arc(0, 0, r * 0.84, 0, 7); c.stroke()
  c.rotate(spin); c.beginPath(); c.arc(0, 0, r * 0.56, 0, 7); c.fillStyle = hot > 0.4 ? `rgb(${140 + 110 * hot},${90 + 30 * hot},48)` : "#a4adb6"; c.fill(); c.fillStyle = "#3a424b"
  for (let k = 0; k < 8; k++) { c.rotate(0.7854); c.beginPath(); c.arc(r * 0.38, 0, r * 0.06, 0, 7); c.fill() } c.beginPath(); c.arc(0, 0, r * 0.16, 0, 7); c.fill(); c.restore()
}
// a semi seen from the side, facing right; (x, y): the road under the cab's front
function truck(c, x, y, o) {
  o = o || {}; const s = o.spin || 0, h = o.hot || 0, col = o.color || "#c8362e", dark = o.dark || "#7d1d17", night = o.night
  c.save(); c.translate(x, y); c.rotate(o.tilt || 0)
  c.fillStyle = "rgba(0,0,0,.34)"; c.beginPath(); c.ellipse(o.noTrailer ? -42 : -136, 1, o.noTrailer ? 66 : 158, 5, 0, 0, 7); c.fill()
  if (!o.noTrailer) {
    const b = c.createLinearGradient(0, -100, 0, -28); b.addColorStop(0, "#f7f8fa"); b.addColorStop(1, "#c7ccd3"); c.fillStyle = b; rr(c, -282, -102, 198, 74, 3); c.fill()
    c.strokeStyle = "rgba(60,70,84,.16)"; c.lineWidth = 1; for (let i = 1; i < 12; i++) { c.beginPath(); c.moveTo(-282 + i * 16.5, -100); c.lineTo(-282 + i * 16.5, -30); c.stroke() }
    c.fillStyle = col; c.fillRect(-282, -45, 198, 7); c.fillStyle = "#c9d2db"; c.font = font(900, 16); c.textAlign = "left"; c.fillStyle = "rgba(40,50,62,.55)"; c.fillText("TRUCKS OF EARTH", -256, -62)
    c.fillStyle = "#2d343d"; c.fillRect(-278, -28, 190, 6); c.fillRect(-246, -22, 76, 4); c.fillStyle = "#1a1e24"; rr(c, -258, -32, 72, 10, 3); c.fill()
    wheel(c, -246, -13, 13.5, s, h, o.flat); wheel(c, -216, -13, 13.5, s, h); wheel(c, -186, -13, 13.5, s, h)
    c.fillStyle = o.brake ? "#ff3b30" : "#8d1f1a"; c.fillRect(-284, -32, 4, 8); if (o.brake) { const g = c.createRadialGradient(-284, -28, 1, -284, -28, 26); g.addColorStop(0, "rgba(255,60,48,.75)"); g.addColorStop(1, "rgba(255,60,48,0)"); c.fillStyle = g; c.fillRect(-312, -56, 56, 56) }
  }
  c.fillStyle = "#2d343d"; c.fillRect(-104, -30, 100, 8); c.fillStyle = "#50575f"; c.fillRect(-92, -36, 30, 6)
  c.fillStyle = "#6c747e"; c.fillRect(-58, -112, 4, 40)
  const cb = c.createLinearGradient(0, -106, 0, -22); cb.addColorStop(0, col); cb.addColorStop(1, dark); c.fillStyle = cb; rr(c, -54, -104, 54, 82, 6); c.fill()
  c.fillStyle = dark; c.beginPath(); c.moveTo(-54, -104); c.lineTo(-50, -118); c.lineTo(-12, -118); c.lineTo(-6, -104); c.fill()
  const gl = c.createLinearGradient(-30, -94, -2, -62); gl.addColorStop(0, "#d4ecf7"); gl.addColorStop(1, "#58809a"); c.fillStyle = gl; c.beginPath(); c.moveTo(-30, -96); c.lineTo(-4, -96); c.lineTo(-2, -66); c.lineTo(-30, -66); c.fill()
  c.strokeStyle = "rgba(0,0,0,.28)"; c.lineWidth = 1.2; rr(c, -48, -92, 20, 58, 3); c.stroke(); c.fillStyle = "#16191e"; c.fillRect(-34, -76, 6, 2)
  c.fillStyle = "#16191e"; c.fillRect(2, -94, 3, 20); rr(c, 1, -96, 7, 15, 2); c.fill()
  c.fillStyle = "#23282f"; c.fillRect(-54, -34, 56, 12); c.fillStyle = "#3d454e"; c.fillRect(-40, -30, 12, 3)
  c.fillStyle = "#ffe9a8"; c.fillRect(-3, -36, 5, 8)
  if (night || o.beam) { const g = c.createLinearGradient(0, 0, 150, 0); g.addColorStop(0, "rgba(255,233,168,.42)"); g.addColorStop(1, "rgba(255,233,168,0)"); c.fillStyle = g; c.beginPath(); c.moveTo(2, -34); c.lineTo(150, -46); c.lineTo(150, 4); c.lineTo(2, -28); c.fill() }
  wheel(c, -24, -13, 13.5, s, o.noTrailer ? 0 : 0); wheel(c, -84, -13, 13.5, s, h * 0.6)
  c.restore()
}
function car(c, x, y, col, spin, brake) {
  c.fillStyle = "rgba(0,0,0,.3)"; c.beginPath(); c.ellipse(x, y + 1, 52, 4, 0, 0, 7); c.fill()
  const b = c.createLinearGradient(0, y - 44, 0, y - 10); b.addColorStop(0, col); b.addColorStop(1, "#0f2a4e"); c.fillStyle = b; rr(c, x - 50, y - 32, 100, 22, 8); c.fill(); c.beginPath(); c.moveTo(x - 34, y - 31); c.lineTo(x - 20, y - 52); c.lineTo(x + 18, y - 52); c.lineTo(x + 36, y - 31); c.fill()
  c.fillStyle = "#bfe0f4"; c.beginPath(); c.moveTo(x - 27, y - 33); c.lineTo(x - 17, y - 48); c.lineTo(x - 2, y - 48); c.lineTo(x - 2, y - 33); c.fill(); c.beginPath(); c.moveTo(x + 2, y - 33); c.lineTo(x + 2, y - 48); c.lineTo(x + 16, y - 48); c.lineTo(x + 28, y - 33); c.fill()
  wheel(c, x - 30, y - 11, 11, spin); wheel(c, x + 30, y - 11, 11, spin)
  c.fillStyle = brake ? "#ff3b30" : "#8d1f1a"; c.fillRect(x - 52, y - 28, 5, 9); if (brake) { const g = c.createRadialGradient(x - 52, y - 24, 1, x - 52, y - 24, 30); g.addColorStop(0, "rgba(255,60,48,.8)"); g.addColorStop(1, "rgba(255,60,48,0)"); c.fillStyle = g; c.fillRect(x - 84, y - 54, 62, 60) }
}
// --- the film's frame: the title top left, the corners darkened, a running bar; captions in dark glass that slide in
function chrome(c, W, H, clip, t) {
  const v = c.createRadialGradient(W / 2, H / 2, H * 0.45, W / 2, H / 2, W * 0.72); v.addColorStop(0, "rgba(4,7,12,0)"); v.addColorStop(1, "rgba(4,7,12,.55)"); c.fillStyle = v; c.fillRect(0, 0, W, H)
  c.font = font(800, 11); const label = "FAHRSCHULE", w = c.measureText(label).width + 26; c.fillStyle = GLASS; rr(c, 14, 13, w, 22, 5); c.fill(); c.fillStyle = AMBER; c.fillRect(14, 13, 3.5, 22); c.fillStyle = "#fff"; c.textAlign = "left"; c.fillText(label, 26, 28)
  c.fillStyle = "rgba(255,255,255,.14)"; c.fillRect(0, H - 3, W, 3); c.fillStyle = AMBER; c.fillRect(0, H - 3, W * t / clip.len, 3)
}
function panel(c, x, y, w, h, col) { c.fillStyle = GLASS; rr(c, x, y, w, h, 8); c.fill(); c.strokeStyle = "rgba(255,255,255,.09)"; c.lineWidth = 1; rr(c, x + 0.5, y + 0.5, w - 1, h - 1, 8); c.stroke(); if (col) { c.fillStyle = col; c.fillRect(x, y + 7, 3.5, h - 14) } }
function beats(c, W, H, t, list) {
  for (const b of list) {
    if (t < b[0] || t >= b[1]) continue
    const e = ease(Math.min(ramp(t, b[0], b[0] + 0.35), 1 - ramp(t, b[1] - 0.25, b[1]))), col = b[4] || AMBER
    c.save(); c.globalAlpha = e; c.translate(0, (1 - e) * 12); c.font = font(800, 20); const w = Math.max(c.measureText(b[2]).width, (c.font = font(500, 13.5), c.measureText(b[3]).width)) + 40
    panel(c, 18, H - 78, Math.min(w, W - 36), 60, col); c.textAlign = "left"; c.fillStyle = "#fff"; c.font = font(800, 20); c.fillText(b[2], 34, H - 50); c.fillStyle = "#c9d3de"; c.font = font(500, 13.5); c.fillText(b[3], 34, H - 29); c.restore()
  }
}
function meter(c, x, y, w, v, label, col, value) { panel(c, x, y, w, 46, col); c.fillStyle = "#aeb7c3"; c.font = font(800, 10.5); c.textAlign = "left"; c.fillText(label, x + 13, y + 16); c.fillStyle = "#fff"; c.font = font(900, 13); c.textAlign = "right"; c.fillText(value || "", x + w - 11, y + 16); c.fillStyle = "#262d37"; rr(c, x + 13, y + 26, w - 25, 9, 4); c.fill(); c.fillStyle = col; rr(c, x + 13, y + 26, Math.max(7, (w - 25) * v), 9, 4); c.fill() }
// a round close-up with a line to what it shows
function lens(c, x, y, r, fx, fy, col, draw) {
  c.strokeStyle = col; c.lineWidth = 1.6; c.beginPath(); c.moveTo(fx, fy); c.lineTo(x, y); c.stroke(); c.fillStyle = col; c.beginPath(); c.arc(fx, fy, 3.2, 0, 7); c.fill()
  c.save(); c.beginPath(); c.arc(x, y, r, 0, 7); c.clip(); c.fillStyle = "#12171e"; c.fillRect(x - r, y - r, 2 * r, 2 * r); c.translate(x, y); draw(); c.restore()
  c.strokeStyle = col; c.lineWidth = 3; c.beginPath(); c.arc(x, y, r, 0, 7); c.stroke()
}
function fade(c, W, H, a) { if (a > 0) { c.fillStyle = `rgba(4,7,12,${a})`; c.fillRect(0, 0, W, H) } }

export const clips = [
  { id: "bremsen", title: "Bergab: Bremsen schonen", text: "Dauerndes Bremsen macht die Bremsen heiß, dann lassen sie nach und Reifen können platzen. Schalte runter und lass den Motor bremsen.", len: 12,
    draw(c, t, W, H) {
      const good = t > 8, heat = good ? 0.16 + 0.05 * Math.sin(t) : ramp(t, 0.5, 5.2), burst = t >= 5.2 && t < 8, stop = ramp(t, 5.2, 7.4), v = good ? 120 : 210 - stop * 190, x = 452, y = 228
      const s = good ? (t - 8) * v : (t < 5.2 ? t * v : 5.2 * 210 + (t - 5.2) * 120 * (1 - stop * 0.8))
      c.save(); c.translate(W / 2, H / 2); c.rotate(0.085); c.scale(1.18, 1.18); c.translate(-W / 2, -H / 2 - 6)
      world(c, W, H, 228, s, "dusk")
      const shake = burst && stop < 1 ? Math.sin(t * 60) * 1.6 * (1 - stop) : 0
      if (!good && heat > 0.45) for (let k = 0; k < 9; k++) { const q = (t * 1.5 + k / 9) % 1; c.beginPath(); c.arc(x - 216 - q * 120, y - 8 - q * 48, 5 + q * 19, 0, 7); c.fillStyle = `rgba(150,150,155,${0.34 * (1 - q)})`; c.fill() }
      truck(c, x + shake, y + 6, { spin: -s * 0.07, hot: heat, flat: burst, brake: !good, beam: true })
      if (burst && t < 5.75) { const b = ramp(t, 5.2, 5.75); c.save(); c.translate(x - 246, y - 8); c.globalAlpha = 1 - b; for (let k = 0; k < 12; k++) { c.rotate(0.5236); c.fillStyle = k % 2 ? "#ffd166" : BAD; c.beginPath(); c.moveTo(0, 0); c.lineTo(8, 22 + 76 * b); c.lineTo(-8, 22 + 76 * b); c.fill() } c.restore() }
      c.restore()
      if (burst && t < 6.5) { c.save(); c.textAlign = "center"; c.font = font(900, 58); c.lineWidth = 8; c.strokeStyle = "rgba(10,12,18,.8)"; c.globalAlpha = 1 - ramp(t, 5.9, 6.5); c.strokeText("KNALL!", W / 2, 130); c.fillStyle = "#fff"; c.fillText("KNALL!", W / 2, 130); c.restore() }
      meter(c, W - 226, 14, 210, heat, "BREMSTEMPERATUR", heat > 0.7 ? BAD : heat > 0.4 ? AMBER : OK, Math.round(90 + heat * 470) + " °C")
      if (good) { panel(c, W - 226, 68, 210, 44, OK); c.textAlign = "left"; c.fillStyle = "#aeb7c3"; c.font = font(800, 10.5); c.fillText("GANG", W - 212, 86); const g = t < 9 ? 8 : t < 9.7 ? 7 : t < 10.4 ? 6 : 5; c.fillStyle = "#fff"; c.font = font(900, 21); c.fillText(String(g), W - 212, 106); c.fillStyle = OK; c.font = font(800, 14); c.fillText("Motorbremse an", W - 180, 98) }
      if (!good && t < 5.2 && t > 1.5) { const r = 54, hk = heat; lens(c, 92, 118, r, 150, 262, hk > 0.7 ? BAD : AMBER, () => { wheel(c, 0, 0, 42, -t * 9, hk); c.fillStyle = `rgb(${90 + 165 * hk},${90 + 20 * hk},${80 - 40 * hk})`; rr(c, -9, -34, 18, 26, 3); c.fill() }) }
      beats(c, W, H, t, [[0.2, 5.2, "Lange bergab nur auf der Bremse …", "Die Temperatur steigt und steigt."], [5.2, 7.9, "Reifen geplatzt!", "Überhitzte Bremsen zerstören die Reifen.", BAD], [8.2, 12, "Besser: Runterschalten", "Der Motor bremst, die Bremse bleibt kühl.", OK]])
      fade(c, W, H, Math.max(1 - ramp(t, 8, 8.5), 0) * (t >= 8 ? 1 : 0) + ramp(t, 7.5, 8) * (t < 8 ? 1 : 0)); chrome(c, W, H, this, t)
    } },
  { id: "lenkzeit", title: "Lenkzeit und Pause", text: "Nach 4,5 Stunden Fahrt sind 45 Minuten Pause Pflicht. Der Fahrtenschreiber zählt mit, die Polizei liest ihn aus.", len: 10,
    draw(c, t, W, H) {
      const pause = t > 5.4, a = ease(ramp(t, 0.3, 4.9)), br = ease(ramp(t, 5.9, 9)), s = pause ? 4.9 * 190 : t * 190, x = 470, y = 238
      world(c, W, H, 238, s, pause ? "night" : "dusk")
      if (pause) { c.save(); c.translate(150, 238); c.fillStyle = "#6d7680"; c.fillRect(-3, -96, 6, 96); c.fillStyle = "#1f62c4"; rr(c, -30, -150, 60, 60, 7); c.fill(); c.fillStyle = "#fff"; c.font = font(900, 46); c.textAlign = "center"; c.fillText("P", 0, -103); c.restore() }
      truck(c, x, y + 6, { spin: -s * 0.07, night: pause, beam: !pause })
      if (pause) { c.textAlign = "left"; for (let k = 0; k < 3; k++) { const q = (t * 0.55 + k / 3) % 1; c.fillStyle = `rgba(255,255,255,${(1 - q) * 0.9})`; c.font = font(900, 13 + q * 12); c.fillText("Z", x - 18 + q * 30, y - 124 - q * 60) } }
      const cx = 118, cy = 118, r = 62; panel(c, cx - 88, cy - 88 + 18, 176, 176, pause ? OK : AMBER)
      const px = cx, py = cy + 18; c.lineCap = "round"; c.lineWidth = 11; c.strokeStyle = "#2a323d"; c.beginPath(); c.arc(px, py, r, 0, 7); c.stroke()
      c.strokeStyle = pause ? OK : (a > 0.86 ? BAD : AMBER); c.beginPath(); c.arc(px, py, r, -1.5708, -1.5708 + 6.283 * (pause ? br : a)); c.stroke(); c.lineCap = "butt"; c.textAlign = "center"; c.fillStyle = "#fff"; c.font = font(900, 31)
      if (!pause) { const m = Math.round(a * 270); c.fillText(`${Math.floor(m / 60)}:${String(m % 60).padStart(2, "0")}`, px, py + 9); c.font = font(800, 10.5); c.fillStyle = "#aeb7c3"; c.fillText("LENKZEIT", px, py + 26) } else { c.fillText(`${Math.round(br * 45)} min`, px, py + 9); c.font = font(800, 10.5); c.fillStyle = OK; c.fillText("PAUSE", px, py + 26) }
      if (!pause && a > 0.86 && Math.floor(t * 4) % 2) { c.fillStyle = BAD; c.font = font(900, 13); c.textAlign = "center"; c.fillText("PAUSE FÄLLIG", px, cy + 110) }
      beats(c, W, H, t, [[0.2, 5.2, "4:30 Stunden am Steuer", "Dann ist Schluss, der Fahrtenschreiber zählt mit."], [5.6, 10, "45 Minuten Pause", "Am Rastplatz anhalten, dann geht es weiter.", OK]])
      fade(c, W, H, t > 4.9 && t <= 5.4 ? ramp(t, 4.9, 5.4) : t > 5.4 && t < 5.9 ? 1 - ramp(t, 5.4, 5.9) : 0); chrome(c, W, H, this, t)
    } },
  { id: "kuppeln", title: "Auflieger ankuppeln", text: "Rückwärts unter den Auflieger setzen und anhalten. Nach ein bis zwei Sekunden rastet er ein; sonst Taste L.", len: 9,
    draw(c, t, W, H) {
      const back = ease(ramp(t, 0.4, 4)), lock = t > 4.7, y = 244, tx = 590 - back * 145, trailerEnd = 330
      world(c, W, H, 238, 0, "day")
      c.save(); c.translate(trailerEnd + 15, y); const b = c.createLinearGradient(0, -106, 0, -30); b.addColorStop(0, "#f7f8fa"); b.addColorStop(1, "#c7ccd3"); c.fillStyle = b; rr(c, -222, -106, 198, 74, 3); c.fill(); c.fillStyle = "#c8362e"; c.fillRect(-222, -49, 198, 7); c.fillStyle = "#2d343d"; c.fillRect(-218, -32, 190, 6); wheel(c, -186, -13, 13.5, 0, 0); wheel(c, -156, -13, 13.5, 0, 0); wheel(c, -126, -13, 13.5, 0, 0)
      const legs = lock ? 1 - ease(ramp(t, 5.3, 6.6)) : 1; c.fillStyle = "#6b7480"; c.fillRect(-58, -32, 5, 8 + legs * 24); c.fillStyle = "#3a424b"; c.fillRect(-62, -24 + legs * 22, 13, 3); c.fillStyle = "#b9c1ca"; c.fillRect(-36, -26, 8, 11); c.restore()
      truck(c, tx, y, { noTrailer: true, spin: back * 9 })
      const kp = trailerEnd + 15 - 32, near = tx - 92
      if (t > 1.2) lens(c, 512, 96, 66, kp + 2, y - 22, lock ? OK : AMBER, () => {
        const off = (near - kp) * 2.1, k = lock ? 0 : clamp(off, 0, 200)
        c.fillStyle = "#c7ccd3"; c.fillRect(-90, -60, 180, 22); c.fillStyle = "#2d343d"; c.fillRect(-90, -40, 180, 8); c.fillStyle = "#9aa4ae"; rr(c, -9, -32, 18, 26, 3); c.fill(); c.fillRect(-13, -14, 26, 5)
        c.fillStyle = "#3a424b"; c.save(); c.translate(k, 0); rr(c, -50, 10, 100, 13, 3); c.fill(); c.fillStyle = "#59626d"; c.beginPath(); c.moveTo(-30, 10); c.lineTo(-12, 4); c.lineTo(12, 4); c.lineTo(30, 10); c.fill(); c.fillStyle = lock ? OK : "#23282f"; c.fillRect(-7, 3, 14, 10); c.fillStyle = "#2d343d"; c.fillRect(-60, 23, 150, 10); c.restore()
        if (lock) { const q = ramp(t, 4.7, 5.2); c.strokeStyle = OK; c.lineWidth = 3; c.globalAlpha = 1 - q; c.beginPath(); c.arc(0, 0, 18 + q * 44, 0, 7); c.stroke(); c.globalAlpha = 1 }
      })
      if (lock) { const q = ease(ramp(t, 4.7, 5.1)); c.save(); c.globalAlpha = q; c.font = font(900, 30); c.textAlign = "center"; c.lineWidth = 6; c.strokeStyle = "rgba(10,14,20,.75)"; c.strokeText("KLICK", 512, 192); c.fillStyle = OK; c.fillText("KLICK", 512, 192); c.restore() }
      beats(c, W, H, t, [[0.2, 4.7, "Langsam rückwärts", "Gerade unter den Auflieger setzen und anhalten."], [4.9, 9, "Eingerastet", "Kommt nichts: Taste L oder der Knopf unten.", OK]]); chrome(c, W, H, this, t)
    } },
  { id: "abstand", title: "Abstand halten", text: "Ein voller Lkw braucht einen sehr langen Bremsweg. Halte mindestens 50 Meter Abstand zum Vordermann.", len: 10,
    draw(c, t, W, H) {
      const brake = t > 4, closing = ease(ramp(t, 4, 7.2)), cx = 578, tx = 230 + closing * 232, y = 244, s = brake ? 4 * 230 + (t - 4) * 110 : t * 230
      world(c, W, H, 238, s, "dusk")
      car(c, cx, y - 2, "#3478c9", -s * 0.09, brake); truck(c, tx, y, { spin: -s * 0.07, brake, beam: true })
      const gap = cx - 52 - tx, gm = Math.round(gap / 6), col = gm > 30 ? OK : gm > 15 ? AMBER : BAD
      c.strokeStyle = col; c.lineWidth = 3; c.beginPath(); c.moveTo(tx + 8, 138); c.lineTo(cx - 54, 138); c.moveTo(tx + 8, 130); c.lineTo(tx + 8, 146); c.moveTo(cx - 54, 130); c.lineTo(cx - 54, 146); c.stroke()
      const mx = (tx + cx - 46) / 2; panel(c, mx - 40, 102, 80, 28); c.fillStyle = col; c.font = font(900, 19); c.textAlign = "center"; c.fillText(`${gm} m`, mx, 123)
      if (gm <= 15 && Math.floor(t * 6) % 2) { c.fillStyle = "rgba(255,91,77,.13)"; c.fillRect(0, 0, W, H) }
      beats(c, W, H, t, [[0.2, 4, "Genug Abstand", "So reicht der Bremsweg auch mit voller Ladung.", OK], [4.2, 10, "Zu dicht!", "Bremst der Vordermann, wird es sehr eng.", BAD]]); chrome(c, W, H, this, t)
    } },
  { id: "panne", title: "Panne? Pannendienst rufen", text: "Sicher anhalten, Pannendienst über das Handy im HUD rufen und warten. Er kommt angefahren und repariert vor Ort.", len: 10,
    draw(c, t, W, H) {
      const y = 244, arrive = ease(ramp(t, 3.6, 6.8)), fixed = t > 8.2, x2 = -80 + arrive * 200
      world(c, W, H, 238, 0, "dusk")
      truck(c, 520, y, { flat: !fixed, beam: fixed }); const blink = Math.floor(t * 3) % 2
      if (blink && !fixed) for (const [X, Y] of [[517, y - 32], [236, y - 28]]) { const g = c.createRadialGradient(X, Y, 1, X, Y, 26); g.addColorStop(0, "rgba(255,177,46,.95)"); g.addColorStop(1, "rgba(255,177,46,0)"); c.fillStyle = g; c.fillRect(X - 26, Y - 26, 52, 52) }
      const tr = ease(ramp(t, 0.5, 1.3)); if (tr > 0) { c.save(); c.translate(184, y); c.scale(tr, tr); c.strokeStyle = BAD; c.lineWidth = 5; c.lineJoin = "round"; c.beginPath(); c.moveTo(-14, -2); c.lineTo(0, -28); c.lineTo(14, -2); c.closePath(); c.stroke(); c.restore() }
      if (t > 3.6) { truck(c, x2, y, { noTrailer: true, color: "#e6a21f", dark: "#8d6012", spin: t * 7 * (1 - arrive), beam: true }); const on = Math.floor(t * 6) % 2; c.fillStyle = on ? "#ffcf5c" : "#7a5512"; c.fillRect(x2 - 44, y - 122, 26, 6); if (on) { const X = x2 - 31, Y = y - 120, g = c.createRadialGradient(X, Y, 1, X, Y, 42); g.addColorStop(0, "rgba(255,190,70,.8)"); g.addColorStop(1, "rgba(255,190,70,0)"); c.fillStyle = g; c.fillRect(X - 42, Y - 42, 84, 84) } }
      if (t > 6.9 && t < 8.2) for (let k = 0; k < 7; k++) { const q = (t * 3 + k / 7) % 1, a = hash(k) * 3.1; c.fillStyle = `rgba(255,216,120,${1 - q})`; c.fillRect(274 + Math.cos(a) * q * 34, y - 14 - Math.sin(a) * q * 34, 2.6, 2.6) }
      if (t > 0.6 && t < 3.6) { const p = ease(ramp(t, 0.7, 1.2)) * (1 - ramp(t, 3.3, 3.6)); c.save(); c.translate(92, 138 + (1 - p) * 20); c.globalAlpha = p; c.fillStyle = "#0c1016"; rr(c, -48, -78, 96, 158, 13); c.fill(); c.fillStyle = "#1b2736"; rr(c, -41, -68, 82, 136, 6); c.fill(); c.fillStyle = "#fff"; c.font = font(800, 11); c.textAlign = "center"; c.fillText("Pannendienst", 0, -44); const r = 19 + Math.sin(t * 9) * 2; c.fillStyle = OK; c.beginPath(); c.arc(0, 8, r, 0, 7); c.fill(); c.strokeStyle = "#fff"; c.lineWidth = 5; c.lineCap = "round"; c.beginPath(); c.arc(0, 8, 9, 0.5, 2.6); c.stroke(); c.lineCap = "butt"; c.fillStyle = "#aeb7c3"; c.font = font(500, 10); c.fillText("Wird gerufen …", 0, 50); c.restore() }
      if (fixed) { const q = ease(ramp(t, 8.2, 8.6)); c.save(); c.globalAlpha = q; panel(c, 248, 100, 144, 40, OK); c.fillStyle = OK; c.font = font(900, 21); c.textAlign = "center"; c.fillText("Repariert", 320, 128); c.restore() }
      beats(c, W, H, t, [[0.2, 3.5, "Sicher anhalten und anrufen", "Warnblinker an, das Handy findest du im HUD."], [3.7, 8.1, "Der Pannendienst fährt zu dir", "Bleib beim Fahrzeug."], [8.3, 10, "Und weiter geht's", "Mit Club-Mitgliedschaft günstiger.", OK]]); chrome(c, W, H, this, t)
    } },
  { id: "tanken", title: "Rechtzeitig tanken", text: "Plane Tankstopps ein. Auf der Karte im Büro findest du alle Tankstellen, auch die von BeamNG.Earth.", len: 8,
    draw(c, t, W, H) {
      const fill = ease(ramp(t, 2, 6.2)), level = 0.08 + fill * 0.9, y = 244, px = 372
      world(c, W, H, 238, 0, "night")
      const roof = c.createLinearGradient(0, 56, 0, 78); roof.addColorStop(0, "#e9edf2"); roof.addColorStop(1, "#aab3bd"); c.fillStyle = "#49525c"; c.fillRect(190, 78, 10, y - 78); c.fillRect(568, 78, 10, y - 78); c.fillStyle = roof; c.fillRect(150, 56, 470, 22); c.fillStyle = AMBER; c.fillRect(150, 73, 470, 5)
      const li = c.createLinearGradient(0, 78, 0, y); li.addColorStop(0, "rgba(255,240,205,.38)"); li.addColorStop(1, "rgba(255,240,205,0)"); c.fillStyle = li; c.beginPath(); c.moveTo(170, 78); c.lineTo(600, 78); c.lineTo(640, y); c.lineTo(130, y); c.fill()
      truck(c, 588, y, { night: false })
      const p = c.createLinearGradient(px - 26, 0, px + 26, 0); p.addColorStop(0, "#d6dde4"); p.addColorStop(1, "#8d97a2"); c.fillStyle = p; rr(c, px - 25, y - 132, 50, 132, 5); c.fill(); c.fillStyle = "#c8362e"; c.fillRect(px - 25, y - 132, 50, 13); c.fillStyle = "#0c1016"; rr(c, px - 19, y - 112, 38, 28, 3); c.fill(); c.fillStyle = "#6ff0a4"; c.font = font(800, 13); c.textAlign = "center"; c.fillText(`${Math.round(level * 600)} l`, px, y - 93)
      c.strokeStyle = "#14181d"; c.lineWidth = 3.5; c.beginPath(); c.moveTo(px + 25, y - 76); c.bezierCurveTo(px + 66, y - 8, px + 96, y - 8, 504, y - 46); c.stroke(); c.fillStyle = "#22272e"; c.fillRect(498, y - 54, 14, 12)
      meter(c, 18, 44, 230, level, "TANK", level < 0.25 ? BAD : level < 0.5 ? AMBER : OK, Math.round(level * 100) + " %")
      if (t > 2) { panel(c, 18, 96, 230, 44); c.fillStyle = "#aeb7c3"; c.font = font(800, 10.5); c.textAlign = "left"; c.fillText("BETRAG", 32, 113); c.fillStyle = "#fff"; c.font = font(900, 18); c.textAlign = "right"; c.fillText((level * 600 * 1.62).toFixed(2).replace(".", ",") + " €", 234, 128) }
      beats(c, W, H, t, [[0.2, 2.2, "Der Tank wird leer", "Warte nicht bis zum letzten Tropfen.", BAD], [2.4, 8, "Volltanken", "Am Hof mit eigener Tanksäule günstiger.", OK]]); chrome(c, W, H, this, t)
    } },
]

// plays one clip on a canvas; returns the function that stops it
export function play(canvas, clip) {
  const c = canvas.getContext("2d"), W = 640, H = 360
  let raf = 0, t0 = performance.now(), last = 0
  function frame(now) {
    raf = requestAnimationFrame(frame)
    if (now - last < 33) return             // (30 frames a second are plenty)
    last = now
    c.setTransform(canvas.width / W, 0, 0, canvas.height / H, 0, 0)
    clip.draw(c, ((now - t0) / 1000) % clip.len, W, H)
  }
  raf = requestAnimationFrame(frame)
  return () => cancelAnimationFrame(raf)
}
// a still of a clip (its most telling moment) for the list
export function still(canvas, clip, at) {
  const c = canvas.getContext("2d")
  c.setTransform(canvas.width / 640, 0, 0, canvas.height / 360, 0, 0)
  clip.draw(c, at === undefined ? ({ bremsen: 3.6, lenkzeit: 3.6, kuppeln: 6, abstand: 6.6, panne: 5.6, tanken: 4.2 })[clip.id] || 2 : at, 640, 360)
}
