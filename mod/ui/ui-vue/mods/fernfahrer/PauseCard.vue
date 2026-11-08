<template>
  <!-- The pause menu's Mods tab: the company at a glance and the way into the office. -->
  <div class="ff-pause">
    <template v-if="st && st.mode && st.company">
      <div class="name">🚛 {{ st.company.name }}</div>
      <div class="sub">{{ money(st.money) }} · {{ st.stats.jobs }} Lieferungen{{ st.job ? " · Auftrag: " + st.job.cargoName : "" }}</div>
      <div class="btns">
        <button class="btn primary" @click="navigate('fernfahrerOffice')">Büro öffnen</button>
      </div>
    </template>
    <template v-else>
      <div class="name">🚛 Trucks of Earth</div>
      <div class="sub">Starte den Spielmodus im Hauptmenü unter „Mehr“.</div>
    </template>
  </div>
</template>

<script setup>
import { ref, onMounted } from "vue"
import { call, navigate, money } from "./ffBridge.js"

const st = ref(null)
onMounted(() => call("uiState", s => { st.value = s }))
</script>

<style scoped>
.ff-pause { padding: 16px; color: #eef1f5; }
.name { font-size: 18px; font-weight: 800; }
.sub { font-size: 13px; color: #9aa4b2; margin-top: 4px; }
.btns { margin-top: 12px; display: flex; gap: 8px; }
.btn { padding: 8px 15px; font-size: 13.5px; font-weight: 700; color: #1a1205; background: #ffb12e; border: 0; border-radius: 7px; cursor: pointer; }
</style>
