<template>
  <!-- The settlement card after a delivery (career.lua completeJob → uiReport): four ratings with stars (on time,
       cargo, driving style, tachograph), then the lines of the settlement and the total. Filed as a delivery note in
       the office's documents as well. -->
  <div class="ffr" @click.self="close">
    <div class="card" v-if="r">
      <div class="head">
        <div class="ic">{{ r.icon || "📦" }}</div>
        <div class="title">
          <div class="kicker">Lieferung abgeschlossen{{ r.clock ? " · " + r.clock + " Uhr" : "" }}</div>
          <div class="name">{{ r.cargoName }}</div>
          <div class="route">{{ r.from }} → {{ r.to }}{{ r.km ? " · " + Math.round(r.km) + " km" : "" }}</div>
        </div>
        <div class="overall" v-if="r.rating">
          <b>{{ String(Math.round(r.rating * 10) / 10).replace(".", ",") }}</b>
          <span class="stars big"><i v-for="n in 5" :key="n" :class="{ on: shown > 4 && n <= Math.round(r.rating) }">★</i></span>
        </div>
      </div>

      <div class="rates">
        <div v-for="(s, i) in stars" :key="s[0]" class="rate" :class="{ show: shown > i }">
          <span class="rn">{{ s[0] }}</span>
          <span class="stars"><i v-for="n in 5" :key="n" :class="{ on: n <= s[1] }">★</i></span>
          <span class="rt">{{ s[2] }}</span>
        </div>
      </div>

      <div class="lines">
        <div class="line" v-for="(l, i) in lines" :key="i"><span>{{ l[0] }}</span><span :class="{ neg: l[1] < 0, pos: l[1] > 0 && i > 0 }">{{ signed(l[1]) }}</span></div>
        <div class="line sum"><span>Gutschrift · +{{ r.xp }} XP</span><span :class="r.total < 0 ? 'neg' : 'pos'">{{ signed(r.total) }}</span></div>
      </div>

      <div class="foot">
        <span>Der Lieferschein liegt im Büro unter Dokumente.</span>
        <div class="btns">
          <button class="ghost" @click="market">Neue Fracht suchen</button>
          <button class="go" @click="close">Weiterfahren</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from "vue"
import { call, navigate, signed, toArray } from "./ffBridge.js"
import { sound } from "./ffSound.js"

const r = ref(null)
const shown = ref(0)                               // (the ratings appear one after the other)
const stars = computed(() => toArray(r.value && r.value.stars).map(toArray))
const lines = computed(() => toArray(r.value && r.value.lines).map(toArray))

function close() { sound("back"); navigate("play") }
function market() { sound("click"); call("toggleOffice", "market") }

let timer = null
onMounted(() => {
  call("uiReport", v => {
    r.value = v
    if (!v) { navigate("play"); return }
    sound("done")
    timer = setInterval(() => {
      shown.value++
      if (shown.value <= 4) sound("hover")
      if (shown.value > 5) clearInterval(timer)
    }, 380)
  })
})
onUnmounted(() => { if (timer) clearInterval(timer); call("dismissReport") })
</script>

<style scoped>
.ffr { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; color: #eef1f5;
  background: radial-gradient(ellipse at center, rgba(5, 8, 12, .4) 0%, rgba(5, 8, 12, .8) 100%); font-family: inherit; }
.card { width: min(640px, 92vw); background: rgba(12, 16, 22, .96); border: 1px solid rgba(255, 255, 255, .12); border-radius: 10px;
  box-shadow: 0 24px 70px rgba(0, 0, 0, .55); padding: 18px 22px; animation: ffrIn .3s ease-out; }
@keyframes ffrIn { from { transform: translateY(16px) scale(.98); opacity: 0; } to { transform: none; opacity: 1; } }
.head { display: flex; align-items: center; gap: 14px; padding-bottom: 14px; border-bottom: 1px solid #222832; }
.ic { width: 52px; height: 52px; border-radius: 10px; background: #1a2029; display: flex; align-items: center; justify-content: center; font-size: 26px; }
.title { flex: 1; min-width: 0; }
.kicker { font-size: 11px; letter-spacing: .16em; text-transform: uppercase; color: #3ad38b; font-weight: 800; }
.name { font-size: 21px; font-weight: 900; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.route { font-size: 12.5px; color: #8b95a3; }
.overall { text-align: right; } .overall b { display: block; font-size: 30px; font-weight: 900; line-height: 1; }
.stars i { font-style: normal; color: #2d343e; font-size: 15px; margin-left: 1px; transition: color .25s, text-shadow .25s; }
.stars i.on { color: #ffc23d; text-shadow: 0 0 8px rgba(255, 194, 61, .5); }
.stars.big i { font-size: 17px; }
.rates { margin-top: 12px; display: flex; flex-direction: column; gap: 6px; }
.rate { display: grid; grid-template-columns: 140px 100px 1fr; align-items: center; gap: 10px; padding: 6px 10px; background: #151a22; border-radius: 6px;
  opacity: 0; transform: translateX(-8px); transition: opacity .3s, transform .3s; }
.rate.show { opacity: 1; transform: none; }
.rate .rn { font-size: 13px; font-weight: 700; } .rate .rt { font-size: 12px; color: #8b95a3; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.lines { margin-top: 12px; padding-top: 10px; border-top: 1px solid #222832; }
.line { display: flex; justify-content: space-between; font-size: 13px; padding: 3px 0; color: #cfd6de; }
.line .neg { color: #ff8a80; } .line .pos { color: #7ee2a8; }
.line.sum { margin-top: 6px; padding-top: 8px; border-top: 1px dashed #2a313b; font-weight: 800; font-size: 15px; color: #fff; }
.foot { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-top: 14px; padding-top: 12px; border-top: 1px solid #222832; font-size: 12px; color: #8b95a3; }
.btns { display: flex; gap: 8px; }
.btns button { border-radius: 6px; padding: 7px 14px; font: inherit; font-weight: 800; cursor: pointer; }
.ghost { background: transparent; border: 1px solid #2f3742; color: #e9edf2; } .ghost:hover { border-color: #f5a623; }
.go { background: #f5a623; border: 0; color: #15100a; }
</style>
