// Trucks of Earth: the UI's way to the Lua side (lua/ge/extensions/fernfahrer/career.lua) and shared formatting.

export function engineLua(script, cb) {
  if (window.bngApi && window.bngApi.engineLua) window.bngApi.engineLua(script, cb)
}

// a Lua literal for a JS value (strings, numbers, booleans, plain objects / arrays via jsonDecode)
export function luaValue(v) {
  if (v === null || v === undefined) return "nil"
  if (typeof v === "number") return isFinite(v) ? String(v) : "nil"
  if (typeof v === "boolean") return v ? "true" : "false"
  if (typeof v === "string") return JSON.stringify(v)
  const json = JSON.stringify(v).replace(/\\/g, "\\\\").replace(/'/g, "\\'")
  return `jsonDecode('${json}')`
}

// fernfahrer_career.<fn>(args...); cb gets the return value. (With a callback the game evaluates an expression,
// without one it runs a statement: "a and b() or nil" alone is a Lua syntax error there.)
export function call(fn, ...args) {
  const cb = typeof args[args.length - 1] === "function" ? args.pop() : undefined
  const a = args.map(luaValue).join(",")
  if (cb) engineLua(`fernfahrer_career and fernfahrer_career.${fn} and fernfahrer_career.${fn}(${a}) or nil`, cb)
  else engineLua(`if fernfahrer_career and fernfahrer_career.${fn} then fernfahrer_career.${fn}(${a}) end`)
}

export function navigate(route) {
  engineLua(`if ui_router and ui_router.navigate then ui_router.navigate(${JSON.stringify(route)}) else guihooks.trigger('ChangeState', {state = ${JSON.stringify(route)}}) end`)
}

// stops the game's key bindings while a text field has focus
export function typing(on) { engineLua(`if setCEFTyping then setCEFTyping(${on ? "true" : "false"}) end`) }

export function money(v) {
  if (v === undefined || v === null) return "–"
  const s = Math.round(Math.abs(v)).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ".")
  return (v < 0 ? "−" : "") + s + " €"
}
export const signed = v => (v > 0 ? "+" : "") + money(v)
export function dist(m) {
  if (m === undefined || m === null) return "–"
  return m >= 1000 ? (m / 1000).toFixed(m >= 10000 ? 0 : 1).replace(".", ",") + " km" : Math.round(m) + " m"
}
export function duration(s) {
  if (s === undefined || s === null) return "–"
  const neg = s < 0
  s = Math.abs(Math.round(s))
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60)
  return (neg ? "−" : "") + (h > 0 ? `${h} h ${String(m).padStart(2, "0")} min` : `${m} min`)
}
export const clock = t => {
  const d = new Date(t * 1000)
  return String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0")
}
export const toArray = v => (Array.isArray(v) ? v : v && typeof v === "object" ? Object.values(v) : [])
