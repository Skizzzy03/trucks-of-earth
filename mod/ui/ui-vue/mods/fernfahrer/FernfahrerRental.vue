<template>
  <!-- The rental desk at an airport (career.lua uiRental, rentalTake): after a flight the driver is on foot and picks a car here. -->
  <div class="ffr">
    <div class="panel">
      <header>
        <div>
          <div class="eyebrow">Mietwagen-Schalter</div>
          <h1>{{ data ? data.desk : "Flughafen" }}</h1>
          <p>Such dir ein Auto aus. Der Preis gilt für die ganze Miete.</p>
        </div>
        <div class="bal"><small>Konto</small><b>{{ data ? money(data.money) : "" }}</b></div>
      </header>
      <div v-if="error" class="err">{{ error }}</div>
      <div class="body">
        <div v-if="data && !groups.length" class="empty">Gerade sind keine Autos da. Versuch es gleich noch einmal.</div>
        <section v-for="g in groups" :key="g.name">
          <h2>{{ g.name }}</h2>
          <div class="grid">
            <article v-for="o in g.list" :key="o.i" :class="{ poor: data.money < o.rate }">
              <div class="pic"><img v-if="o.preview" :src="o.preview" loading="lazy" @error="e => e.target.style.visibility = 'hidden'" /></div>
              <div class="info">
                <b>{{ o.brand }} {{ o.modelName }}</b>
                <span class="sub">{{ o.configName }}</span>
                <span class="facts"><i v-if="o.power">{{ Math.round(o.power) }} PS</i><i v-if="o.drivetrain">{{ o.drivetrain }}</i></span>
                <div class="foot">
                  <strong>{{ money(o.rate) }}</strong>
                  <button :disabled="busy || data.money < o.rate" @click="take(o)">{{ data.money < o.rate ? "Zu teuer" : "Mieten" }}</button>
                </div>
              </div>
            </article>
          </div>
        </section>
      </div>
      <footer>
        <span>Kein passendes Auto oder zu wenig Geld? Im Fuhrpark bringt dich „Zum Hof“ zurück.</span>
        <button class="ghost" @click="close">Später entscheiden</button>
      </footer>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from "vue"
import { call, navigate, money, toArray } from "./ffBridge.js"

const data = ref(null), busy = ref(false), error = ref("")
const groups = computed(() => {
  const out = []
  for (const o of toArray(data.value && data.value.offers)) {
    let g = out.find(x => x.name === o.class)
    if (!g) { g = { name: o.class, list: [] }; out.push(g) }
    g.list.push(o)
  }
  return out
})
function load() { call("uiRental", d => { if (d) data.value = d }) }
// (the catalogue of the cars may still be building: once more shortly)
onMounted(() => { load(); setTimeout(() => { if (!groups.value.length) load() }, 1500) })
function take(o) {
  busy.value = true; error.value = ""
  call("rentalTake", o.i, r => {
    busy.value = false
    if (r && r.ok) navigate("play")
    else error.value = (r && r.error) || "Das hat nicht geklappt."
  })
}
function close() { navigate("play") }
</script>

<style scoped>
.ffr { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; padding: 3vh 3vw; color: #e9edf2; font-family: inherit;
  background: radial-gradient(ellipse at 50% 30%, rgba(14,18,24,.72), rgba(5,7,10,.92)); pointer-events: auto; }
.panel { width: min(1180px, 100%); max-height: 94vh; display: flex; flex-direction: column; background: #151a21; border: 1px solid #2a313b; border-radius: 14px; box-shadow: 0 30px 80px rgba(0,0,0,.6); overflow: hidden; }
header { display: flex; justify-content: space-between; align-items: flex-end; gap: 20px; padding: 22px 28px 16px; border-bottom: 1px solid #252c36; }
.eyebrow { font-size: 11px; font-weight: 800; letter-spacing: .2em; text-transform: uppercase; color: #f5a623; }
h1 { margin: 3px 0 2px; font-size: 26px; font-weight: 900; }
header p { margin: 0; font-size: 13.5px; color: #8b95a3; }
.bal { text-align: right; flex: none; } .bal small { display: block; font-size: 10.5px; letter-spacing: .14em; text-transform: uppercase; color: #8b95a3; } .bal b { font-size: 21px; font-variant-numeric: tabular-nums; }
.err { padding: 9px 28px; background: #3a1c1a; color: #ffb4ab; font-size: 13.5px; }
.body { flex: 1; min-height: 0; overflow-y: auto; padding: 8px 28px 20px; }
.empty { padding: 50px 0; text-align: center; color: #8b95a3; }
h2 { margin: 16px 0 9px; font-size: 12px; font-weight: 800; letter-spacing: .14em; text-transform: uppercase; color: #8b95a3; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(255px, 1fr)); gap: 12px; }
article { background: #1c222b; border: 1px solid #2a313b; border-radius: 10px; overflow: hidden; display: flex; flex-direction: column; transition: border-color .15s, transform .15s; }
article:hover { border-color: #f5a623; transform: translateY(-2px); }
article.poor { opacity: .55; } article.poor:hover { border-color: #2a313b; transform: none; }
.pic { height: 142px; background: linear-gradient(180deg, #2a313b, #161b22); display: flex; align-items: center; justify-content: center; }
.pic img { max-width: 100%; max-height: 100%; object-fit: contain; }
.info { padding: 11px 13px 13px; display: flex; flex-direction: column; gap: 2px; flex: 1; }
.info b { font-size: 15px; font-weight: 800; }
.sub { font-size: 12.5px; color: #8b95a3; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.facts { display: flex; gap: 10px; font-size: 12px; color: #aeb7c3; min-height: 17px; } .facts i { font-style: normal; }
.foot { display: flex; align-items: center; justify-content: space-between; margin-top: auto; padding-top: 9px; }
.foot strong { font-size: 18px; font-weight: 900; color: #f5a623; font-variant-numeric: tabular-nums; }
button { border: 0; border-radius: 6px; padding: 7px 16px; font: inherit; font-size: 13.5px; font-weight: 800; background: #f5a623; color: #15100a; cursor: pointer; }
button:hover:not(:disabled) { background: #ffbd4f; } button:disabled { background: #2f3742; color: #7d8794; cursor: default; }
footer { display: flex; align-items: center; justify-content: space-between; gap: 16px; padding: 12px 28px; border-top: 1px solid #252c36; font-size: 12.5px; color: #8b95a3; }
button.ghost { flex: none; background: #252c36; color: #e9edf2; } button.ghost:hover { background: #303846; }
</style>
