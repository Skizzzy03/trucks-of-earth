<template>
  <!-- The company menu (Strg+Umschalt+F, the route advisor, the pause menu): a side bar in three sections – Drive
       (freight market, job, map), Company (overview, fleet & workshop, dealers, bank, messages), System (settings).
       Polls career.lua uiState; the dealers' stock comes from uiCatalog. -->
  <div class="ffo" :class="{ closing }" @keydown.esc="close" tabindex="-1" ref="rootEl">
    <div class="frame" v-if="st">
      <aside>
        <div class="brand">
          <div class="mark">{{ initials }}</div>
          <div><div class="cname">{{ st.company ? st.company.name : "Spedition" }}</div><div class="csub">{{ st.home ? st.home.name : "" }}</div></div>
        </div>
        <template v-for="g in NAV" :key="g.label">
          <div class="sect">{{ g.label }}</div>
          <a v-for="t in g.items" :key="t.id" class="nav" :class="{ on: tab === t.id }" @mouseenter="sound('hover')" @click="setTab(t.id)">
            <span class="ni">{{ t.icon }}</span>{{ t.label }}
            <span v-if="badge(t.id)" class="cnt">{{ badge(t.id) }}</span>
          </a>
        </template>
        <div class="grow"></div>
        <a class="nav" @click="close"><span class="ni">↩</span>Zurück zur Straße <span class="key">Esc</span></a>
      </aside>

      <section class="content">
        <header>
          <div><div class="title">{{ titleOf(tab) }}</div><div class="tsub">{{ SUBS[tab] }}</div></div>
          <div class="kpis">
            <div><span>Uhrzeit</span><b>{{ st.clock }}</b></div>
            <div><span>Konto</span><b :class="{ neg: st.money < 0 }">{{ money(st.money) }}</b></div>
            <div v-if="st.loan > 0"><span>Kredit</span><b class="neg">{{ money(st.loan) }}</b></div>
            <div><span>Level {{ st.level }}</span><div class="xp"><i :style="{ width: xpPct + '%' }"></i></div></div>
          </div>
        </header>
        <div v-if="st.near" class="here">Vor Ort: <b>{{ st.near.name }}</b> · {{ st.near.typeName }}</div>

        <main :key="tab" class="tabIn">
          <!-- the Zentrale: one tile per area with what matters there now -->
          <div v-if="tab === 'home'" class="hub">
            <div class="hello">
              <div><span class="day">{{ st.weekday }} · {{ st.clock }}</span><b>{{ greeting }}, {{ st.company && st.company.driver ? st.company.driver : "Chef" }}.</b></div>
              <div class="hint" v-if="st.near">Du bist bei <b>{{ st.near.name }}</b> · {{ st.near.typeName }}</div>
            </div>
            <div class="career-stats" v-if="st.stats">
              <span><b>{{ st.stats.jobs || 0 }}</b> Lieferungen</span><span><b>{{ Math.round(st.stats.km || 0).toLocaleString("de-DE") }}</b> km</span>
              <span><b>{{ money(st.stats.earned || 0) }}</b> verdient</span><span v-if="st.loaner">Leih-LKW · Schnellaufträge</span>
            </div>
            <div class="tiles">
              <a v-for="t in tiles" :key="t.id + t.title" class="tile" :class="{ alert: t.alert, wide: t.wide, info: !t.id }" :style="{ '--ac': t.color }"
                 @mouseenter="t.id && sound('hover')" @click="t.id && goTile(t)">
                <div class="th"><span class="ti">{{ t.icon }}</span><span class="tt">{{ t.title }}</span><span v-if="t.badge" class="tb">{{ t.badge }}</span></div>
                <div class="tv">{{ t.value }}</div>
                <div class="ts">{{ t.sub }}</div>
                <div v-if="t.bar !== undefined" class="tbar"><i :style="{ width: Math.round(t.bar * 100) + '%' }"></i></div>
              </a>
            </div>
          </div>

          <!-- freight market -->
          <div v-if="tab === 'market'" class="split">
            <div class="list">
              <!-- the job under way (was a page of its own) -->
              <div v-if="st.job" class="jobcard">
                <div class="jh"><span class="kick">Laufender Auftrag</span><span v-if="st.job.fragile" class="tag violet">Zerbrechlich</span><span class="grow"></span>
                  <b class="pos">{{ money(st.job.pay) }}</b></div>
                <div class="jt">{{ st.job.cargoName }} · {{ st.job.tons }} t</div>
                <div class="jr">{{ st.job.from }} → {{ st.job.to }}</div>
                <div class="instr">{{ st.job.text }}</div>
                <div class="jk">
                  <div><span>Bis zum Ziel</span><b>{{ dist(st.job.dist) }}</b></div>
                  <div><span>Fahrzeit</span><b>{{ duration(st.job.eta) }}</b></div>
                  <div><span>Frist</span><b :class="{ neg: st.job.timeLeft < 0 }">{{ duration(st.job.timeLeft) }}</b></div>
                  <div><span>Ladung</span><b :class="condClass(st.job.cond)">{{ Math.round(st.job.cond * 100) }} %</b></div>
                  <div><span>Auflieger</span><b>{{ st.job.hasTrailer ? (st.job.coupled ? "gekuppelt" : "abgekuppelt") : "–" }}</b></div>
                </div>
                <div class="row">
                  <button class="btn primary" @click="act('navToJob'); close()">Navi zum Auftrag</button>
                  <button class="btn" v-if="st.job.phase === 'needTrailer'" @click="act('requestNewTrailer')">Auflieger neu bereitstellen (−5 %)</button>
                  <span class="grow"></span>
                  <button class="btn primary" v-if="st.job.adr && !st.job.papers && st.job.papersHere" @click="act('packPapers')">📄 ADR-Papiere einpacken</button>
                  <span class="tag" v-if="st.job.adr && !st.job.papers && !st.job.papersHere">ADR-Papiere nur am Abholort{{ st.job.papersAway ? " · noch " + (st.job.papersAway > 2000 ? Math.round(st.job.papersAway / 1000) + " km" : st.job.papersAway + " m") : "" }}</span>
                  <span class="tag green" v-if="st.job.adr && st.job.papers">ADR-Papiere dabei</span>
                  <span class="tag red" v-if="st.job.smuggle">Illegale Fracht</span>
                  <span class="tag" v-if="st.job.needSecure">Ladung noch nicht gesichert</span>
                  <button class="btn danger" @click="act('cancelJob')">{{ st.job.phase === 'toPickup' ? "Stornieren (kostenlos)" : "Stornieren (10 % Strafe)" }}</button>
                </div>
              </div>
              <div class="bar">
                <div class="filters">
                  <a :class="{ on: kind === 'all' }" @click="kind = 'all'">Alle</a>
                  <a :class="{ on: kind === 'regional' }" @click="kind = 'regional'">Regional</a>
                  <a :class="{ on: kind === 'long' }" @click="kind = 'long'">Fernverkehr</a>
                </div>
                <span class="muted">{{ st.loaner ? "Leih-LKW · " + Math.round(st.companyShare * 100) + " % der Fracht" : "Eigener LKW · voller Frachtlohn" }}</span>
                <span class="grow"></span>
                <button class="btn" @click="act('refreshOffers')">Aktualisieren</button>
              </div>
              <div v-if="st.discover && st.discover.running" class="info">Firmen in der Umgebung werden geladen … {{ st.discover.done }} / {{ st.discover.total }}</div>
              <div v-if="st.activeDef && st.activeDef.kind === 'car'" class="info warn">Für Aufträge in einen LKW wechseln (Hof oder Logistik-Stützpunkt).</div>
              <table class="tbl" v-if="filteredOffers.length">
                <thead><tr><th>Fracht</th><th>Von → Nach</th><th class="r">Strecke</th><th class="r">Frist</th><th class="r">Lohn</th><th></th></tr></thead>
                <tbody>
                  <template v-for="o in filteredOffers" :key="o.id">
                  <tr :class="{ sel: sel && sel.id === o.id }" @click="sel = o">
                    <td><div class="ofr"><img v-if="trailerPic(o)" class="trl" :src="trailerPic(o)" loading="lazy" @error="e => e.target.style.visibility = 'hidden'" /><div><b>{{ o.cargoName }}</b><div class="muted trn">{{ trailerName(o) }}</div></div></div><div class="tags"><span v-if="o.adr" class="tag adr">ADR</span><span v-if="o.smuggle" class="tag red">Illegal</span><span class="tag">{{ o.tons }} t</span><span v-if="o.long" class="tag blue">Fernverkehr</span><span v-if="o.backhaul" class="tag green">Rückfracht</span><span v-if="o.urgent" class="tag red">Eilig</span><span v-if="o.fragile" class="tag violet">Zerbrechlich</span><span v-if="o.special" class="tag green">Stammtour</span></div><div v-if="o.note" class="tags" style="white-space:normal;color:#8b95a3;font-size:11px">{{ o.note }}</div></td>
                    <td class="ft"><div>{{ o.from.name }}</div><div class="muted">→ {{ o.to.name }}</div></td>
                    <td class="r">{{ o.distKm }} km<div class="muted">+{{ o.pickupKm }} km</div></td>
                    <td class="r">{{ duration(o.deadline) }}<div class="muted">noch {{ duration(o.expiresIn) }}</div></td>
                    <td class="r pay">{{ money(st.loaner ? Math.round(o.freight * st.companyShare) : o.freight) }}</td>
                    <td class="r"><button class="btn primary" :disabled="!!st.job" @click.stop="accept(o)">Annehmen</button></td>
                  </tr>
                  <!-- the request: the customer asks the company – once, another price may be named (2026-11-05) -->
                  <tr v-if="sel && sel.id === o.id" class="negrow">
                    <td colspan="6">
                      <div class="trlbig" v-if="trailerPic(o)"><img :src="trailerPic(o)" @error="e => e.target.style.display = 'none'" /><div><div class="kicker">Dein Auflieger</div><b>{{ trailerName(o) }}</b><div class="muted">{{ o.cargoName }} · {{ o.tons }} t{{ o.adr ? " · Gefahrgut (ADR)" : "" }}</div></div></div>
                      <div class="neg">
                        <span class="nq">📨 <b>{{ o.from.name }}</b> fragt an: {{ o.cargoName }} nach {{ o.to.name }}</span>
                        <span class="grow"></span>
                        <template v-if="!o.negotiated">
                          <span class="muted">Preis verhandeln:</span>
                          <a v-for="p in NEG" :key="p" class="chip" :class="{ on: negPct === p, up: p > 0 }" @click.stop="negPct = p">{{ p > 0 ? "+" : "" }}{{ Math.round(p * 100) }} %</a>
                          <b class="pay">{{ money((st.loaner ? st.companyShare : 1) * Math.round(o.freight * (1 + negPct) / 10) * 10) }}</b>
                          <button class="btn" :disabled="negPct === 0 || negBusy" @click.stop="negotiate(o)">Gegenangebot senden</button>
                        </template>
                        <span v-else class="muted">Verhandelt</span>
                      </div>
                      <div v-if="negMsg && negMsg.id === o.id" class="negmsg" :class="{ good: negMsg.accepted }">{{ negMsg.text }}</div>
                    </td>
                  </tr>
                  </template>
                </tbody>
              </table>
              <div v-else-if="!(st.discover && st.discover.running)" class="info">Gerade keine Angebote – gleich kommen neue rein.</div>
            </div>
            <FfMap class="map" :center="mapCenter" :zoom="10" :markers="marketMarkers" />
          </div>

          <!-- map -->
          <div v-if="tab === 'map'" class="split">
            <div class="list">
              <div class="filters wrap">
                <a :class="{ on: !filter }" @click="filter = null">Alle</a>
                <a v-for="t in types" :key="t.key" :class="{ on: filter === t.key, off: !t.count }" @click="filter = t.key">{{ t.name }} <span class="muted">{{ t.count }}</span></a>
              </div>
              <div class="row">
                <button class="btn" @click="act('navToHome'); close()">Navi: Hof</button>
                <button class="btn" @click="act('navToNearest', 'rest'); close()">Nächster Rastplatz</button>
                <button class="btn" @click="act('navToNearest', 'fuel'); close()">Nächste Tankstelle</button>
                <button class="btn" @click="act('navToNearest', 'workshop'); close()">Nächste Werkstatt</button>
              </div>
              <div class="row" title="Google Maps: Rechtsklick auf den Ort → Koordinaten kopieren, oder den Link aus der Adresszeile">
                <input v-model="goText" class="input" placeholder="Ziel: Koordinaten oder Google-Maps-Link einfügen" @focus="typing(true)" @blur="typing(false)" @keydown.stop @keyup.enter="goToText" />
                <button class="btn" @click="goToText">Navi hin</button>
                <button class="btn" @click="routeAddText" title="Als Stopp an die Route hängen">+ Route</button>
              </div>
              <div v-if="goMsg" class="muted" :class="{ bad: !goOk }">{{ goMsg }}</div>
              <!-- the route planner: stops in a row; the navi leads to one after the other -->
              <div class="routeplan">
                <div class="rph"><b>🧭 Routenplaner</b>
                  <span class="muted">{{ route.stops.length ? route.stops.length + " Stopps · ca. " + route.totalKm + " km" : "Stopps mit „+ Route“ hinzufügen" }}</span>
                  <button class="btn" @click="routeCall('routeAddHere')" title="Die aktuelle Position als Stopp">+ Hier</button></div>
                <div v-for="(s, i) in route.stops" :key="i + s.name" class="rps" :class="{ act: s.active, done: s.done }">
                  <span class="rpn">{{ i + 1 }}</span><span class="rpname">{{ s.name }}<small v-if="s.km"> · {{ String(s.km).replace(".", ",") }} km</small></span>
                  <a @click="routeCall('routeMove', i + 1, -1)" :class="{ off: i === 0 }" title="Nach oben">▲</a>
                  <a @click="routeCall('routeMove', i + 1, 1)" :class="{ off: i === route.stops.length - 1 }" title="Nach unten">▼</a>
                  <a @click="routeCall('routeRemove', i + 1)" title="Entfernen">✕</a>
                </div>
                <div class="row" v-if="route.stops.length">
                  <button v-if="!route.idx" class="btn primary" @click="routeCall('routeStart'); close()">Route starten</button>
                  <button v-else class="btn" @click="routeCall('routeStop')">Route beenden</button>
                  <button class="btn" @click="routeCall('routeClear')">Leeren</button>
                </div>
              </div>
              <table class="tbl">
                <tbody>
                  <tr v-for="p in filteredPlaces" :key="p.id" :class="{ sel: selPlace && selPlace.id === p.id }" @click="selPlace = p">
                    <td><span class="badge" :style="{ background: typeColor(p.type) }"></span><b>{{ p.name }}</b><span v-if="p.discovered" class="tag green">entdeckt</span><div class="muted">{{ p.typeName }}{{ p.detail ? " · " + p.detail : "" }}</div></td>
                    <td class="r">{{ dist(p.d) }}</td>
                    <td class="r"><button class="btn" @click.stop="act('navToPlace', p.id); close()">Navi</button>
                      <button class="btn" @click.stop="routeCall('routeAdd', p.lat, p.lon, p.name)" title="Als Stopp an die Route hängen">+</button></td>
                  </tr>
                </tbody>
              </table>
            </div>
            <FfMap class="map" :center="mapCenter" :zoom="11" :markers="placeMarkers" />
          </div>

          <!-- travel: ferries and flights -->
          <div v-if="tab === 'travel'">
            <template v-if="tr && tr.hub">
              <div class="bar"><b>{{ tr.hub.name }}</b><span class="muted">{{ tr.hub.kind === 'airport' ? "Flughafen" : (tr.hub.train ? "Autozug-Terminal" : "Fährhafen") }}</span></div>
              <div v-if="tr.hub.kind === 'ferry'" class="info">{{ tr.job ? "Der Auflieger fährt mit – er muss angekuppelt sein." : "Überfahrt mit deinem Fahrzeug." }}
                Die Zeit an Bord läuft auf der Uhr; ab 6 Stunden zählt sie als Ruhezeit, sonst als Pause.</div>
              <div v-else class="info">Du fliegst allein: Dein Fahrzeug bleibt hier. Am Ziel gehst du zu Fuß zum Mietwagen-Schalter und suchst dir dort ein Auto aus.
                Eigene Fahrzeuge holst du später über den Fuhrpark (Überführung).</div>
              <div v-if="tr.hub.kind === 'airport' && tr.job" class="info warn">Mit laufendem Auftrag geht kein Flug.</div>
              <table class="tbl">
                <thead><tr><th>Ziel</th><th>{{ tr.hub.kind === 'airport' ? "Strecke" : "Linie" }}</th><th class="r">Dauer</th><th class="r">Preis</th><th></th></tr></thead>
                <tbody><tr v-for="o in toArray(tr.options)" :key="o.idx">
                  <td><b>{{ o.to }}</b> <span class="tag">{{ o.cc }}</span><span v-if="o.iata" class="tag blue">{{ o.iata }}</span></td>
                  <td class="muted">{{ o.operator || (o.km.toLocaleString("de-DE") + " km") }}</td>
                  <td class="r">{{ hours(o.hours) }}</td>
                  <td class="r pay" :class="{ dim: st.money < o.price }">{{ money(o.price) }}</td>
                  <td class="r"><button class="btn primary" :disabled="st.money < o.price || (tr.hub.kind === 'airport' && tr.job)" @click="act('travel', o.idx)">{{ tr.hub.kind === 'airport' ? "Fliegen" : "Buchen" }}</button></td>
                </tr></tbody>
              </table>
            </template>
            <template v-else>
              <div class="info">Wo BeamNG.Earth keine Straße hat (Ärmelkanal, Nord- und Ostsee, Mittelmeer), bringen dich Fähren und der Eurotunnel hinüber – mit Auflieger.
                Für weite Strecken (z. B. nach Amerika) fliegst du und nimmst am Ziel einen Mietwagen. Fahr hin, dann buchst du hier.</div>
              <div class="cols">
                <div class="panel">
                  <h3>Fährhäfen &amp; Autozug</h3>
                  <table class="tbl"><tbody><tr v-for="h in toArray(tr && tr.ferries)" :key="h.id">
                    <td><b>{{ h.name }}</b> <span class="tag">{{ h.cc }}</span><span v-if="h.train" class="tag blue">Zug</span></td>
                    <td class="r">{{ dist(h.dist) }}</td>
                    <td class="r"><button class="btn" @click="act('navToHub', h.id); close()">Navi</button></td>
                  </tr></tbody></table>
                </div>
                <div class="panel">
                  <h3>Flughäfen</h3>
                  <table class="tbl"><tbody><tr v-for="h in toArray(tr && tr.airports)" :key="h.id">
                    <td><b>{{ h.name }}</b> <span class="tag blue">{{ h.iata }}</span></td>
                    <td class="r">{{ dist(h.dist) }}</td>
                    <td class="r"><button class="btn" @click="act('navToHub', h.id); close()">Navi</button></td>
                  </tr></tbody></table>
                </div>
              </div>
            </template>
          </div>

          <!-- fleet & workshop -->
          <div v-if="tab === 'fleet'">
            <!-- the yard's upgrades (2026-11-07): the company grows -->
            <div class="yardup">
              <div class="yh">🏗️ Dein Hof ausbauen</div>
              <div class="muted" style="margin:-4px 0 8px">Hinweis: Hof-Upgrades werden in dieser Version noch nicht unterstützt, auch wenn sie hier angezeigt werden.</div>
              <div class="ycards">
                <div v-for="u in toArray(st.yardUp)" :key="u.key" class="ycard" :class="{ owned: u.owned }">
                  <div class="yi">{{ u.icon }}</div>
                  <div class="yt"><b>{{ u.name }}</b><span>{{ u.text }}</span></div>
                  <div class="yb">
                    <span v-if="u.owned" class="tag green">Gebaut</span>
                    <button v-else class="btn primary" :disabled="st.money < u.price" @click="act('buyYardUpgrade', u.key)">{{ money(u.price) }}</button>
                  </div>
                </div>
              </div>
            </div>
            <div class="bar"><span class="muted">{{ st.transferFee > 0 ? "Fahrzeugwechsel hier: Überführung " + money(st.transferFee) : "Fahrzeugwechsel hier kostenlos" }}</span><span class="grow"></span>
              <button class="btn" @click="act('goHome', false); close()">Zum Hof (Teleport)</button></div>
            <table class="tbl">
              <thead><tr><th>Fahrzeug</th><th>Ausstattung</th><th class="r">km</th><th></th></tr></thead>
              <tbody>
                <tr :class="{ sel: st.active === 'loaner' }">
                  <td><b>Leih-LKW</b><div class="muted">{{ st.loaner && st.activeDef ? st.activeDef.brand + " " + st.activeDef.modelName : "wird gestellt" }}</div></td>
                  <td class="muted">Schnellaufträge · {{ Math.round(st.companyShare * 100) }} % der Fracht · Diesel frei</td><td class="r">–</td>
                  <td class="r"><button class="btn primary" @click="act('fetchVehicle', 'loaner'); close()">{{ st.active === 'loaner' ? "Holen" : "Wechseln" }}</button></td>
                </tr>
                <tr v-if="st.rental && st.activeDef" class="sel">
                  <td><b>Mietwagen</b><div class="muted">{{ st.activeDef.brand }} {{ st.activeDef.modelName }}</div></td>
                  <td class="muted">Vom Flughafen · Rückgabe bei jedem Fahrzeugwechsel</td><td class="r">–</td><td></td>
                </tr>
                <tr v-for="(t, i) in owned" :key="i" :class="{ sel: st.active === i + 1 }">
                  <td style="display:flex;gap:10px;align-items:center"><img v-if="t.preview" class="thumb" :src="t.preview" @error="e => e.target.style.visibility = 'hidden'" />
                    <div><b>{{ t.brand }} {{ t.modelName }}</b> <span v-if="t.eu" class="tag blue">EU</span><span v-if="t.used" class="tag">gebraucht gekauft</span><div class="muted">{{ t.kind === 'car' ? "Auto" : "LKW" }}</div></div></td>
                  <td class="muted">{{ t.configName }}{{ t.power ? " · " + t.power + " PS" : "" }}</td>
                  <td class="r">{{ Math.round(t.km || 0) }}</td>
                  <td class="r">
                    <template v-if="t.seized"><span class="tag red">Beschlagnahmt</span> <button class="btn primary" :disabled="st.money < seizeFee(t)" @click="act('redeemTruck', i + 1)">Auslösen {{ money(seizeFee(t)) }}</button></template>
                    <template v-else-if="t.driver"><span class="muted">🧑‍✈️ {{ t.driver.name }} fährt · {{ t.driver.tours || 0 }} Touren · {{ money(t.driver.earned || 0) }}</span> <button class="btn ghost" @click="act('fireDriver', i + 1)">Abziehen</button></template>
                    <template v-else>
                      <button class="btn primary" @click="act('fetchVehicle', i + 1); close()">{{ st.active === i + 1 ? "Holen" : "Wechseln" }}</button>
                      <button class="btn" v-if="t.kind !== 'car' && st.active !== i + 1 && st.canHire" :disabled="st.money < 1500" @click="act('hireDriver', i + 1)" title="Der LKW fährt im Hintergrund Touren: Einnahmen minus Lohn und Wartung">Fahrer einstellen 1.500 €</button>
                      <button class="btn ghost" @click="act('sellVehicle', i + 1)">Verkaufen {{ money(sellValue(t)) }}</button>
                    </template>
                  </td>
                </tr>
              </tbody>
            </table>
            <div class="panel wide" style="margin-top:14px">
              <h3>Werkstatt</h3>
              <template v-if="st.near && (st.near.action === 'repair' || st.near.action === 'home')">
                <div>{{ st.near.name }} · Reparatur {{ st.near.repairCost ? money(st.near.repairCost) : "kostenlos" }}</div>
                <button class="btn primary" @click="act('repair'); close()">Reparieren</button>
              </template>
              <template v-else><div class="muted">Reparieren geht in einer Werkstatt oder an deinem Hof.</div>
                <button class="btn" @click="act('navToNearest', 'workshop'); close()">Navi zur nächsten Werkstatt</button></template>
            </div>
          </div>

          <!-- dealers -->
          <div v-if="tab === 'dealer'">
            <template v-if="st.near && st.near.action === 'dealerTruck'">
              <div class="bar"><b>{{ st.near.name }}</b><span class="muted">Zugmaschinen{{ st.europe ? " · EU-Modelle zuerst" : "" }}</span>
                <span class="grow"></span>
                <div class="filters">
                  <a :class="{ on: dealerTab === 'new' }" @click="dealerTab = 'new'">Neu <span class="muted">{{ trucks.length }}</span></a>
                  <a :class="{ on: dealerTab === 'used' }" @click="dealerTab = 'used'">Gebraucht <span class="muted">{{ trucksUsed.length }}</span></a>
                </div></div>
              <div v-if="dealerTab === 'new' && !trucks.length" class="info">Lade Angebot …</div>
              <div v-if="dealerTab === 'used' && !trucksUsed.length" class="info">Gerade keine Gebrauchten – schau später wieder vorbei.</div>
              <div v-if="dealerTab === 'used' && trucksUsed.length" class="muted small" style="margin-bottom:8px">Gebrauchte wechseln mit der Zeit. Kilometerstand und Gebrauchsspuren kommen mit – der Preis ist entsprechend niedriger.</div>
              <div class="cards">
                <div v-for="t in (dealerTab === 'new' ? trucks : trucksUsed)" :key="t.usedId || t.idx" class="vcard">
                  <div class="pic"><img v-if="t.preview" :src="t.preview" loading="lazy" @error="e => e.target.style.visibility = 'hidden'" /><span v-if="t.eu" class="tag blue">EU</span><span v-if="t.used" class="tag used">Gebraucht</span></div>
                  <div class="vb">
                    <b>{{ t.brand }} {{ t.modelName }}</b>
                    <div class="muted">{{ t.configName }}</div>
                    <div class="specs"><span v-if="t.power">{{ t.power }} PS</span><span v-if="t.drivetrain">{{ t.drivetrain }}</span>
                      <template v-if="t.used"><span>{{ Math.round(t.km).toLocaleString("de-DE") }} km</span><span>{{ t.age }} {{ t.age === 1 ? "Jahr" : "Jahre" }}</span>
                        <span :class="t.condition >= 90 ? 'pos' : t.condition >= 80 ? 'warn' : 'neg'">Zustand {{ t.condition }} %</span></template></div>
                    <div v-if="t.marks" class="muted small">Leichte Gebrauchsspuren, kleine Dellen</div>
                    <div class="vfoot"><span class="pay" :class="{ dim: st.money < t.price }">{{ money(t.price) }}</span>
                      <span v-if="t.used && t.newPrice" class="muted small">neu {{ money(t.newPrice) }}</span>
                      <button class="btn primary" :disabled="st.money < t.price" @click="t.used ? buy('buyUsedTruck', t.usedId) : buy('buyTruck', t.idx)">Kaufen</button></div>
                  </div>
                </div>
              </div>
            </template>
            <template v-else-if="st.near && st.near.action === 'dealerCar'">
              <div class="bar"><b>{{ st.near.name }}</b><span class="muted">Autohaus</span><span class="grow"></span>
                <input v-model="carQuery" class="input" placeholder="Marke oder Modell" @focus="typing(true)" @blur="typing(false)" @keydown.stop /></div>
              <div v-if="!cars.length" class="info">Lade Angebot …</div>
              <div v-for="m in filteredCars" :key="m.idx" class="acc">
                <div class="acchead" @click="openModel = openModel === m.idx ? null : m.idx">
                  <img v-if="m.preview" class="thumb" :src="m.preview" loading="lazy" @error="e => e.target.style.visibility = 'hidden'" />
                  <b>{{ m.brand }} {{ m.modelName }}</b> <span v-if="m.eu" class="tag blue">EU</span>
                  <span class="grow"></span><span class="muted">{{ toArray(m.configs).length }} Ausstattungen · ab {{ money(m.minPrice) }}</span>
                </div>
                <div v-if="openModel === m.idx">
                  <div v-for="(c, ci) in toArray(m.configs)" :key="ci" class="cfg">
                    <img v-if="c.preview" class="thumb" :src="c.preview" loading="lazy" @error="e => e.target.style.visibility = 'hidden'" />
                    <span>{{ c.configName }}{{ c.power ? " · " + c.power + " PS" : "" }}</span>
                    <span class="pay" :class="{ dim: st.money < c.price }">{{ money(c.price) }}</span>
                    <button class="btn primary" :disabled="st.money < c.price" @click="buy('buyCar', m.idx, ci + 1)">Kaufen</button>
                  </div>
                </div>
              </div>
            </template>
            <template v-else>
              <div class="info">Fahrzeuge kaufst du vor Ort beim Händler. Wähle einen aus und lass dich hinnavigieren.</div>
              <table class="tbl"><tbody>
                <tr v-for="p in dealers" :key="p.id">
                  <td><span class="badge" :style="{ background: typeColor(p.type) }"></span><b>{{ p.name }}</b><div class="muted">{{ p.typeName }}{{ p.detail ? " · " + p.detail : "" }}</div></td>
                  <td class="r">{{ dist(p.d) }}</td>
                  <td class="r"><button class="btn" @click="act('navToPlace', p.id); close()">Navi</button></td>
                </tr>
              </tbody></table>
            </template>
          </div>

          <!-- finances: the books (career.lua L.pay → S.ledger) as graphs, the loan, the fines -->
          <div v-if="tab === 'bank'" class="fin">
            <div class="fk">
              <div class="kpi big"><span>Kontostand</span><b :class="{ neg: st.money < 0 }">{{ money(st.money) }}</b><small>{{ fin.trendText }}</small></div>
              <div class="kpi"><span>Einnahmen · 7 Tage</span><b class="pos">{{ money(fin.in7) }}</b></div>
              <div class="kpi"><span>Ausgaben · 7 Tage</span><b class="neg">{{ money(-fin.out7) }}</b></div>
              <div class="kpi"><span>Gewinn · 7 Tage</span><b :class="fin.in7 - fin.out7 >= 0 ? 'pos' : 'neg'">{{ signed(fin.in7 - fin.out7) }}</b></div>
            </div>

            <div class="fgrid">
              <div class="panel chart">
                <h3>Kontostand <span>letzte {{ fin.bal.n }} Buchungen</span></h3>
                <svg v-if="fin.bal.n > 1" viewBox="0 0 600 170" preserveAspectRatio="none" class="line">
                  <defs><linearGradient id="ffoBal" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffb12e" stop-opacity=".35" /><stop offset="1" stop-color="#ffb12e" stop-opacity="0" /></linearGradient></defs>
                  <line v-for="g in fin.bal.grid" :key="g.y" x1="0" x2="600" :y1="g.y" :y2="g.y" class="grid" />
                  <line v-if="fin.bal.zero !== null" x1="0" x2="600" :y1="fin.bal.zero" :y2="fin.bal.zero" class="zero" />
                  <path :d="fin.bal.area" fill="url(#ffoBal)" />
                  <path :d="fin.bal.path" class="stroke" />
                  <circle :cx="fin.bal.last[0]" :cy="fin.bal.last[1]" r="4" class="dot" />
                </svg>
                <div v-else class="empty">Noch zu wenige Buchungen – nach den ersten Fahrten erscheint hier der Verlauf.</div>
                <div class="axis" v-if="fin.bal.n > 1"><span>{{ money(fin.bal.min) }}</span><span>{{ money(fin.bal.max) }}</span></div>
              </div>

              <div class="panel chart">
                <h3>Einnahmen &amp; Ausgaben <span>pro Spieltag</span></h3>
                <svg v-if="fin.days.length" viewBox="0 0 600 170" class="bars">
                  <line x1="0" x2="600" y1="85" y2="85" class="zero" />
                  <g v-for="(d, i) in fin.days" :key="d.d">
                    <rect :x="i * fin.dayW + fin.dayW * 0.2" :y="85 - d.hi" :width="fin.dayW * 0.6" :height="d.hi" class="in" rx="2"><title>{{ d.name }}: +{{ money(d.inc) }}</title></rect>
                    <rect :x="i * fin.dayW + fin.dayW * 0.2" y="85" :width="fin.dayW * 0.6" :height="d.ho" class="out" rx="2"><title>{{ d.name }}: −{{ money(d.out) }}</title></rect>
                  </g>
                </svg>
                <div v-else class="empty">Noch keine Buchungen.</div>
                <div class="axis days" v-if="fin.days.length"><span v-for="d in fin.days" :key="d.d">{{ d.short }}</span></div>
              </div>

              <div class="panel">
                <h3>Ausgaben nach Art <span>gesamt</span></h3>
                <div v-if="!fin.cats.length" class="empty">Noch keine Ausgaben.</div>
                <div v-for="c in fin.cats" :key="c.c" class="cat">
                  <span class="cn"><i :style="{ background: c.color }"></i>{{ c.c }}</span>
                  <span class="cb"><i :style="{ width: c.pct + '%', background: c.color }"></i></span>
                  <span class="cv">{{ money(c.sum) }}</span><span class="cp">{{ Math.round(c.pct) }} %</span>
                </div>
              </div>

              <div class="panel">
                <h3>Kennzahlen</h3>
                <div class="kv"><span>Lieferungen</span><b>{{ st.stats.jobs || 0 }}</b></div>
                <div class="kv"><span>Gefahrene km</span><b>{{ Math.round(st.stats.km || 0).toLocaleString("de-DE") }}</b></div>
                <div class="kv"><span>Verdient (Fracht)</span><b class="pos">{{ money(st.stats.earned || 0) }}</b></div>
                <div class="kv"><span>Pro Lieferung</span><b>{{ st.stats.jobs ? money(st.stats.earned / st.stats.jobs) : "–" }}</b></div>
                <div class="kv"><span>Pro km</span><b>{{ st.stats.km ? (st.stats.earned / st.stats.km).toFixed(2).replace(".", ",") + " €" : "–" }}</b></div>
                <div class="kv"><span>Pünktlich</span><b>{{ st.stats.jobs ? Math.round((1 - (st.stats.late || 0) / st.stats.jobs) * 100) + " %" : "–" }}</b></div>
                <div class="kv" v-if="st.rating"><span>Ø Bewertung</span><b><span class="dstars"><i v-for="n in 5" :key="n" :class="{ on: n <= Math.round(st.rating.avg) }">★</i></span> {{ st.rating.avg.toFixed(1).replace(".", ",") }}</b></div>
                <div class="kv"><span>Bußgelder gesamt</span><b class="neg">{{ money(st.stats.fines || 0) }}</b></div>
              </div>
            </div>

            <div class="fgrid two">
              <div class="panel">
                <h3>Kredit</h3>
                <div class="kv"><span>Offen</span><b :class="{ neg: st.loan > 0 }">{{ money(st.loan) }}</b></div>
                <div class="kv"><span>Rahmen frei</span><b>{{ money(st.loanLimit - st.loan) }}</b></div>
                <div class="loanbar"><i :style="{ width: (st.loanLimit ? Math.min(100, st.loan / st.loanLimit * 100) : 0) + '%' }"></i></div>
                <div class="muted small">Einmalig {{ Math.round(st.loanRate * 100) }} % Zinsen · 20 % jeder Gutschrift tilgen automatisch · Diesel {{ st.fuelPrices.diesel.toFixed(2).replace(".", ",") }} €/l</div>
                <div class="row">
                  <button class="btn" @click="act('takeLoan', 10000)">+10.000 €</button>
                  <button class="btn" @click="act('takeLoan', 50000)">+50.000 €</button>
                  <span class="grow"></span>
                  <button class="btn primary" :disabled="st.loan <= 0" @click="act('repayLoan', 10000)">10.000 € tilgen</button>
                  <button class="btn" :disabled="st.loan <= 0" @click="act('repayLoan', st.loan)">Alles</button>
                </div>
              </div>
              <div class="panel">
                <h3>Bußgelder</h3>
                <div v-if="!toArray(st.fines).length" class="empty">Keine Strafzettel – weiter so.</div>
                <div v-for="(f, i) in toArray(st.fines).slice(0, 6)" :key="i" class="book"><span class="bt">{{ clock(f.t) }}</span><span class="bl">{{ f.reason }}</span><b class="neg">{{ money(-f.amount) }}</b></div>
              </div>
            </div>

            <div class="panel" style="margin-top:12px">
              <h3>Buchungen <span>neueste zuerst</span></h3>
              <div v-if="!fin.recent.length" class="empty">Noch keine Buchungen – ab jetzt wird alles mitgeschrieben.</div>
              <div v-for="(b, i) in fin.recent" :key="i" class="book">
                <span class="bt">{{ dayName(b.d) }} {{ hm(b.h) }}</span>
                <span class="chip" :style="{ borderColor: catColor(b.c), color: catColor(b.c) }">{{ b.c }}</span>
                <span class="bl">{{ b.l }}</span>
                <b :class="b.a < 0 ? 'neg' : 'pos'">{{ signed(b.a) }}</b>
                <span class="bb">{{ money(b.b) }}</span>
              </div>
            </div>
          </div>

          <!-- company documents: police accident reports -->
          <div v-if="tab === 'docs'" class="split">
            <div class="list">
              <div v-if="!docs.length" class="info">Noch keine Dokumente. Lieferscheine und Polizeiberichte landen hier.</div>
              <table class="tbl" v-else><tbody>
                <tr v-for="(d, i) in docs" :key="(d.case || '') + d.t + i" :class="{ sel: selDoc === d }" @click="selDoc = d" style="cursor:pointer">
                  <template v-if="d.kind === 'delivery'">
                    <td><b>{{ d.title }}</b><div class="muted">{{ new Date(d.t * 1000).toLocaleDateString("de-DE") }} · {{ d.clock }} Uhr · {{ d.cargoName }} · {{ d.from }} → {{ d.to }}</div></td>
                    <td class="r"><span class="dstars"><i v-for="n in 5" :key="n" :class="{ on: n <= Math.round(d.rating || 0) }">★</i></span></td>
                  </template>
                  <template v-else>
                    <td><b>{{ d.title }}</b> <span class="tag">{{ d.case }}</span><div class="muted">{{ new Date(d.t * 1000).toLocaleDateString("de-DE") }} · {{ d.clock }} Uhr · {{ d.road }}</div></td>
                    <td class="r"><span class="tag" :class="d.fault && d.fault.startsWith('Fahrer') ? 'red' : (d.fault && d.fault.startsWith('Unfall') ? 'green' : '')">{{ d.fault }}</span></td>
                  </template>
                </tr>
              </tbody></table>
            </div>
            <!-- a delivery note -->
            <div class="panel doc" v-if="selDoc && selDoc.kind === 'delivery'">
              <div class="dochead"><div><div class="dt">Lieferschein & Abrechnung</div><div class="t1">{{ selDoc.cargoName }}</div></div>
                <div class="stamp"><span class="dstars"><i v-for="n in 5" :key="n" :class="{ on: n <= Math.round(selDoc.rating || 0) }">★</i></span></div></div>
              <div class="kv"><span>Datum / Uhrzeit</span><b>{{ new Date(selDoc.t * 1000).toLocaleDateString("de-DE") }}, {{ selDoc.clock }} Uhr</b></div>
              <div class="kv"><span>Strecke</span><b>{{ selDoc.from }} → {{ selDoc.to }}{{ selDoc.km ? " · " + Math.round(selDoc.km) + " km" : "" }}</b></div>
              <div class="kv" v-for="s in toArray(selDoc.stars).map(toArray)" :key="s[0]"><span>{{ s[0] }}</span>
                <b><span class="dstars"><i v-for="n in 5" :key="n" :class="{ on: n <= s[1] }">★</i></span> {{ s[2] }}</b></div>
              <div class="kv" v-for="(l, i) in toArray(selDoc.lines).map(toArray)" :key="'l' + i"><span>{{ l[0] }}</span><b :class="{ neg: l[1] < 0 }">{{ signed(l[1]) }}</b></div>
              <div class="kv"><span>Gutschrift</span><b :class="selDoc.total < 0 ? 'neg' : 'pos'">{{ signed(selDoc.total) }}</b></div>
            </div>
            <div class="panel doc" v-if="selDoc && selDoc.kind !== 'delivery'">
              <div class="dochead"><div><div class="dt">Polizei · Verkehrsunfallanzeige</div><div class="t1">{{ selDoc.title }}</div></div><div class="stamp">{{ selDoc.case }}</div></div>
              <div class="kv"><span>Datum / Uhrzeit</span><b>{{ new Date(selDoc.t * 1000).toLocaleDateString("de-DE") }}, {{ selDoc.clock }} Uhr</b></div>
              <div class="kv"><span>Unfallort</span><b>{{ selDoc.road }}{{ selDoc.near ? " · " + selDoc.near : "" }}</b></div>
              <div class="kv"><span>Koordinaten</span><b>{{ selDoc.lat ? selDoc.lat.toFixed(5) + ", " + selDoc.lon.toFixed(5) : "–" }}</b></div>
              <div class="kv"><span>Beteiligte Fahrzeuge</span><b>{{ selDoc.vehicles }}{{ selDoc.trailerHit ? " + Auflieger beschädigt" : "" }}</b></div>
              <div class="kv"><span>Fahrzeug der Spedition</span><b>{{ selDoc.vehicle }}</b></div>
              <div class="kv"><span>Schwere</span><b>{{ selDoc.severity }}</b></div>
              <div class="kv"><span>Geschätzte Geschwindigkeit</span><b>{{ selDoc.speed }}{{ selDoc.limit ? " (erlaubt " + selDoc.limit + ")" : "" }}</b></div>
              <div class="kv" v-if="selDoc.pedestrians"><span>Fußgänger erfasst</span><b class="neg">{{ selDoc.pedestrians }} · {{ selDoc.pedState }}</b></div>
              <div class="kv" v-if="selDoc.bac"><span>Atemalkohol</span><b :class="{ neg: selDoc.bac >= 0.3 }">{{ String(selDoc.bac.toFixed(2)).replace('.', ',') }} ‰</b></div>
              <div class="kv" v-if="selDoc.thc"><span>Drogenvortest</span><b :class="{ neg: selDoc.thc >= 3.5 }">THC ca. {{ String(selDoc.thc.toFixed(1)).replace('.', ',') }} ng/ml</b></div>
              <div class="kv"><span>Verletzte</span><b>{{ selDoc.injured }}</b></div>
              <div class="kv"><span>Rettungsdienst</span><b>{{ selDoc.ambulance ? "vor Ort" : "nicht erforderlich" }}</b></div>
              <div class="kv"><span>Schuld</span><b :class="selDoc.fault && selDoc.fault.startsWith('Fahrer') ? 'neg' : ''">{{ selDoc.fault }}</b></div>
              <div class="kv"><span>Ursache</span><b>{{ selDoc.reason }}</b></div>
              <div class="kv" v-if="selDoc.fine"><span>Bußgeld</span><b class="neg">{{ money(selDoc.fine) }}</b></div>
              <div class="kv" v-if="selDoc.points"><span>Punkte in Flensburg</span><b>{{ selDoc.points }}</b></div>
              <p class="doctext">{{ selDoc.text }}</p>
              <!-- the scene photos (taken when the police stood there) -->
              <div v-if="toArray(selDoc.photos).length" class="evid">
                <div class="evh">Fotos von der Unfallstelle</div>
                <div class="photos">
                  <figure v-for="(p, i) in toArray(selDoc.photos)" :key="p.file" @click="bigPhoto = i">
                    <img :src="imgSrc(p.file)" alt="" @error="photoErr" /><figcaption>{{ i + 1 }} · {{ p.label }}</figcaption>
                  </figure>
                </div>
              </div>
              <div v-if="bigPhoto !== null && toArray(selDoc.photos)[bigPhoto]" class="lightbox" @click="bigPhoto = null">
                <img :src="imgSrc(toArray(selDoc.photos)[bigPhoto].file)" alt="" /><div>{{ toArray(selDoc.photos)[bigPhoto].label }} – klicken zum Schließen</div>
              </div>
              <div v-if="selDoc.legal || selDoc.verdict" class="legal">
                <div class="dt">Strafrechtliche Einordnung (Theorie)</div>
                <ul v-if="selDoc.legal"><li v-for="(l, i) in toArray(selDoc.legal)" :key="i">{{ l }}</li></ul>
                <div v-if="selDoc.verdict" class="verdict" :class="{ prison: selDoc.prison }">{{ selDoc.verdict }}</div>
                <div class="muted small">Nur eine spielerische Einschätzung, keine Rechtsauskunft.</div>
              </div>
              <div class="muted">Aufgenommen von {{ selDoc.officer }}</div>
            </div>
          </div>

          <!-- the driver's record -->
          <div v-if="tab === 'stats'">
            <div class="stiles">
              <div class="stile"><span>Entdeckte Orte</span><b>{{ sv.towns.length }}</b><small>{{ sv.deliv }} davon beliefert</small></div>
              <div class="stile"><span>Gefahren</span><b>{{ km0(sv.odo) }} km</b><small>{{ km0(sv.freight) }} km mit Fracht</small></div>
              <div class="stile"><span>Lieferungen</span><b>{{ sv.jobs }}</b><small>{{ sv.routes.length }} verschiedene Routen</small></div>
              <div class="stile"><span>Fahrerwertung</span><b v-if="sv.avg">{{ de1(sv.avg) }} <em class="dstars big"><i v-for="n in 5" :key="n" :class="{ on: n <= Math.round(sv.avg) }">★</i></em></b><b v-else>–</b><small>{{ driverTitle }}</small></div>
            </div>
            <div class="fgrid two">
              <div class="panel">
                <h3>Fahrerwertung <span>{{ sv.n }} bewertete Fahrten</span></h3>
                <div v-if="!sv.cats.length" class="empty">Nach der ersten Abrechnung steht hier, wie du fährst.</div>
                <div v-for="c in sv.cats" :key="c.name" class="cat">
                  <span class="cn">{{ c.name }}</span>
                  <span class="cb"><i :style="{ width: (c.avg / 5 * 100) + '%', background: c.avg >= 4 ? '#2fbf71' : (c.avg >= 2.5 ? '#ffc23d' : '#ff6b5e') }"></i></span>
                  <span class="cv">{{ de1(c.avg) }} ★</span>
                </div>
              </div>
              <div class="panel">
                <h3>Häufigste Routen <span>Ø Sterne</span></h3>
                <div v-if="!sv.routes.length" class="empty">Noch keine Lieferung abgeschlossen.</div>
                <div class="routes">
                  <div v-for="r in sv.routes" :key="r.from + r.to" class="route">
                    <div class="rn"><b>{{ r.from }}</b> → <b>{{ r.to }}</b></div>
                    <div class="muted">{{ r.n }}× {{ r.km ? "· " + Math.round(r.km) + " km" : "" }}{{ r.last ? " · zuletzt " + date0(r.last) : "" }}</div>
                    <span class="dstars" v-if="r.avg"><i v-for="n in 5" :key="n" :class="{ on: n <= Math.round(r.avg) }">★</i></span>
                  </div>
                </div>
              </div>
            </div>
            <div class="panel" style="margin-top:12px">
              <h3>Entdeckte Orte <span>{{ townList.length }} von {{ sv.towns.length }}</span></h3>
              <div class="row townbar">
                <input v-model="townQ" placeholder="Ort suchen …" />
                <span class="seg"><a v-for="o in TOWN_SORT" :key="o.v" :class="{ on: townSort === o.v }" @click="townSort = o.v">{{ o.l }}</a></span>
              </div>
              <div v-if="!townList.length" class="empty">{{ sv.towns.length ? "Kein Ort passt zur Suche." : "Fahr durch einen Ort, dann steht er hier." }}</div>
              <div class="towns">
                <div v-for="x in townList" :key="x.name" class="town">
                  <b>{{ x.name }}</b>
                  <span class="muted">{{ TOWN_KIND[x.k] || "Ort" }}{{ x.l ? " · " + date0(x.l) : "" }}</span>
                  <span class="tn">{{ x.n }}× da<template v-if="x.d"> · <em>{{ x.d }}× beliefert</em></template></span>
                </div>
              </div>
            </div>
          </div>

          <!-- the club and the insurance (2026-11-08) -->
          <div v-if="tab === 'club' && cv" class="clb">
            <section class="chero">
              <div class="ccard" :class="'lv' + cv.tier">
                <div class="cc-top"><span class="cc-logo">{{ cv.short }}</span><span class="cc-name">{{ cv.name }}</span><span class="cc-chip"></span></div>
                <div class="cc-tier">{{ cv.tiers[cv.tier].name }}</div>
                <div class="cc-no">Nr. {{ String(cv.no).replace(/(\d{3})(\d{4})/, "$1 $2") }}</div>
                <div class="cc-foot"><span><small>Inhaber</small>{{ st.company ? st.company.name : "Spedition" }}</span><span><small>Status</small>{{ cv.status }}</span><span><small>Einsätze</small>{{ cv.rescues }}</span></div>
              </div>
              <div class="cpts">
                <div class="ring" :style="{ '--p': cv.statusPct }"><div><b>{{ cv.pts }}</b><small>Punkte</small></div></div>
                <div class="cpts-t">
                  <h3>Status {{ cv.status }}</h3>
                  <p v-if="cv.nextStatus">Noch {{ Math.max(0, cv.nextAt - cv.life) }} Punkte bis <b>{{ cv.nextStatus }}</b>.</p><p v-else>Höchster Status erreicht.</p>
                  <p class="muted">{{ cv.tier ? "Punkte gibt es für jeden Tag und jede Lieferung. Ohne Schaden mehr." : "Mit einer Mitgliedschaft sammelst du Punkte." }}</p>
                  <div class="cchips"><span v-if="cv.voucher">🔧 {{ money(cv.voucher) }} Gutschein</span><span v-if="cv.sfSafe">🛡 {{ cv.sfSafe }}× Rabattretter</span></div>
                </div>
              </div>
              <div class="csum"><span>Alles zusammen</span><b>{{ money(cv.perDay) }}</b><small>pro Tag</small></div>
            </section>

            <h2 class="csec"><i>🟡</i> Mitgliedschaft <small>Was ein Einsatz kostet und wie schnell jemand kommt</small></h2>
            <div class="cgrid four">
              <button v-for="t in cv.tiers" :key="t.id" class="cplan" :class="{ on: cv.tier === t.id }" @click="act('clubAct', 'tier', t.id)">
                <span class="cp-badge" v-if="cv.tier === t.id">Dein Tarif</span>
                <b class="cp-name">{{ t.name }}</b>
                <span class="cp-price">{{ t.perDay ? money(t.perDay) : "0 €" }}<small> / Tag</small></span>
                <ul><li v-for="l in t.lines" :key="l">{{ l }}</li></ul>
              </button>
            </div>

            <h2 class="csec"><i>⭐</i> Prämien <small>Punkte einlösen</small></h2>
            <div class="cgrid four">
              <button v-for="r in cv.rewards" :key="r.id" class="crew" :disabled="!r.can" @click="act('clubAct', 'reward', r.id)">
                <span class="cr-i">{{ r.icon }}</span><b>{{ r.name }}</b><small>{{ r.sub }}</small><em>{{ r.cost }} Punkte</em>
              </button>
            </div>

            <h2 class="csec"><i>🛡</i> Versicherung <small>{{ cv.insurer }}</small></h2>
            <div class="csf">
              <div class="csf-l"><span>Schadenfreiheit</span><b>SF {{ cv.sf }}</b><small>Du zahlst {{ cv.sfPct }} % des Grundbeitrags</small></div>
              <div class="csf-m">
                <div class="csf-bar"><i v-for="n in cv.sfMax" :key="n" :class="{ on: n <= cv.sf }"></i></div>
                <small>Noch {{ Math.max(0, cv.sfDays - cv.cleanDays) }} Tage ohne Schaden bis zur nächsten Klasse</small>
              </div>
              <div class="csf-o" v-if="cv.open"><span>Offener Schaden</span><b>{{ cv.open.case }}</b><small>{{ cv.open.void ? "Kein Kaskoschutz: Alkohol, Drogen oder Flucht" : (cv.open.fault === "Unfallgegner" ? "Die Gegenseite zahlt deine Reparatur" : "Wird bei der nächsten Reparatur abgerechnet") }}</small></div>
            </div>
            <div class="cgrid three">
              <button v-for="p in cv.plans" :key="p.id" class="cplan ins" :class="{ on: cv.plan === p.id, next: cv.nextPlan === p.id }" @click="act('clubAct', 'plan', p.id)">
                <span class="cp-badge" v-if="cv.plan === p.id && !cv.nextPlan">Dein Schutz</span><span class="cp-badge soon" v-if="cv.nextPlan === p.id">Ab morgen</span>
                <b class="cp-name">{{ p.name }}</b><span class="cp-sub">{{ p.sub }}</span>
                <span class="cp-price">{{ money(p.perDay) }}<small> / Tag</small></span>
                <ul class="chk"><li v-for="l in p.lines" :key="l[1]" :class="{ no: !l[0] }">{{ l[1] }}</li></ul>
              </button>
            </div>
            <div class="csb" v-if="cv.plan === 'voll' || cv.nextPlan === 'voll'">
              <div><b>Selbstbeteiligung Vollkasko</b><div class="muted">So viel zahlst du je Schaden selbst. Mehr Eigenanteil, kleinerer Beitrag.</div></div>
              <div class="seg"><a v-for="o in cv.sbs" :key="o.v" :class="{ on: cv.sb === o.v }" @click="act('clubAct', 'sb', o.v)">{{ o.v }} € · {{ money(o.perDay) }}/Tag</a></div>
            </div>

            <div class="panel" style="margin-top:14px">
              <h3>Schadenakte <span>{{ toArray(cv.history).length }} Einträge</span></h3>
              <div v-if="!toArray(cv.history).length" class="empty">Noch kein Schaden. So soll es bleiben.</div>
              <div class="ctl">
                <div v-for="(h, i) in toArray(cv.history)" :key="i" class="ctl-i" :class="h.k">
                  <i></i>
                  <div class="grow"><b>{{ h.title }}</b><div class="muted">{{ h.x }}</div></div>
                  <div class="ctl-a"><b v-if="h.c">{{ money(h.c) }} übernommen</b><b v-else-if="h.a" class="neg">{{ money(-h.a) }}</b><small>Tag {{ h.d }}</small></div>
                </div>
              </div>
            </div>
          </div>

          <!-- messages -->
          <div v-if="tab === 'messages'" class="split">
            <div class="list">
              <div class="msg" v-for="(m, i) in toArray(st.log)" :key="i"><span>{{ clock(m.t) }} · {{ m.from }}</span>{{ m.text }}</div>
            </div>
            <div class="panel">
              <h3>Firmennetz</h3>
              <div class="kv"><span>Bekannte Orte</span><b>{{ places.length }}</b></div>
              <div class="kv"><span>Entdeckte Aussichtspunkte</span><b>{{ st.stats.discoveries || 0 }}</b></div>
              <div class="kv"><span>Gegründet</span><b>{{ st.company && st.company.founded ? new Date(st.company.founded * 1000).toLocaleDateString("de-DE") : "–" }}</b></div>
              <div class="row">
                <button class="btn" @click="act('moveHomeHere')">Hof hierher verlegen</button>
                <button class="btn" :disabled="st.discover && st.discover.running" @click="act('rediscover')">Netz neu laden</button>
              </div>
            </div>
          </div>

          <!-- settings -->
          <div v-if="tab === 'settings'">
            <div class="setting" v-for="s in SETTINGS" :key="s.key">
              <div class="grow"><b>{{ s.label }}</b><div class="muted">{{ s.hint }}</div>
                <!-- (a real select cannot open in the game's browser: its popup is never drawn) -->
                <div v-if="s.select && evOpen" class="evlist"><a v-for="o in s.opts" :key="String(o.v)" @click="act('setOption', s.key, o.v); evOpen = false">{{ o.l }}</a></div>
              </div>
              <button v-if="s.select" class="evsel" @click="evOpen = !evOpen">{{ evOpen ? "Zuklappen" : "Ereignis wählen" }} <i :class="{ up: evOpen }">▾</i></button>
              <div v-else class="seg"><a v-for="o in s.opts" :key="String(o.v)" :class="{ on: st.settings[s.key] === o.v || (st.settings[s.key] === undefined && o.def) }" @click="act('setOption', s.key, o.v)">{{ o.l }}</a></div>
            </div>
            <div class="setting" v-if="st.weather">
              <div><b>Wetter – Status</b><div class="muted">{{ st.weather }}</div></div>
            </div>
            <div class="setting">
              <div><b>Verkehr – Status</b><div class="muted">{{ st.traffic ? st.traffic.active + " / " + st.traffic.max + " Fahrzeuge · " + st.traffic.source : "aus / startet gleich" }}{{ st.fps ? " · " + st.fps + " FPS" : "" }}</div></div>
              <button class="btn" v-if="st.agentTool" @click="act('openAgentTrafficTool')">Agent Traffic Tool</button>
            </div>
            <div class="setting">
              <div><b>Frachtarten</b><div class="muted">Gefahrgut und Spezialtransporte folgen.</div></div>
              <div class="chips"><span v-for="c in toArray(st.cargo)" :key="c.key" class="tag" :class="{ dim: !c.enabled }">{{ c.name }}</span></div>
            </div>
            <div class="setting">
              <div><b>Spiel beenden</b><div class="muted">Zurück ins Hauptmenü. Gespeichert wird automatisch.</div></div>
              <button class="btn" @click="act('stopMode')">Hauptmenü</button>
            </div>
            <div class="setting">
              <div><b>Karriere zurücksetzen</b><div class="muted">Löscht Firma, Geld und Fuhrpark dieser Karriere.</div></div>
              <button class="btn danger" @click="confirmReset ? (act('resetCareer'), confirmReset = false) : (confirmReset = true)">{{ confirmReset ? "Wirklich löschen" : "Zurücksetzen" }}</button>
            </div>
          </div>
        </main>
      </section>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, watch, onMounted, onUnmounted, nextTick } from "vue"
import FfMap from "./FfMap.vue"
import { call, navigate, typing, money, signed, dist, duration, clock, toArray } from "./ffBridge.js"
import { sound } from "./ffSound.js"

// (one entry per area – the current job is on the Aufträge page, bank and fines are the Finanzen: no doubles)
const NAV = [
  { label: "Start", items: [{ id: "home", label: "Zentrale", icon: "🏠", sub: "Alles Wichtige auf einen Blick" }] },
  { label: "Fahren", items: [
    { id: "market", label: "Aufträge", icon: "📦", sub: "Laufender Auftrag und Frachtbörse" },
    { id: "map", label: "Karte & Orte", icon: "🗺", sub: "Tankstellen, Rastplätze, Kunden, Händler" },
    { id: "travel", label: "Reisen", icon: "⚓", sub: "Fähren, Autozug und Flüge" },
  ] },
  { label: "Firma", items: [
    { id: "fleet", label: "Fuhrpark & Werkstatt", icon: "🚛", sub: "Deine Fahrzeuge, wechseln, verkaufen, reparieren" },
    { id: "dealer", label: "Händler", icon: "🏷", sub: "Neue und gebrauchte Fahrzeuge" },
    { id: "bank", label: "Finanzen", icon: "📈", sub: "Kontostand, Einnahmen, Ausgaben, Kredit und Bußgelder" },
    { id: "club", label: "Club & Versicherung", icon: "🛡", sub: "Pannendienst, Punkte, Haftpflicht und Kasko" },
    { id: "docs", label: "Dokumente", icon: "📄", sub: "Lieferscheine und Polizeiberichte" },
    { id: "stats", label: "Statistik", icon: "📊", sub: "Entdeckte Orte, Kilometer, Routen und Fahrerwertung" },
    { id: "messages", label: "Nachrichten", icon: "💬", sub: "Funk von Mira und der Firma" },
  ] },
  { label: "System", items: [{ id: "settings", label: "Einstellungen", icon: "⚙", sub: "Spielmodus anpassen" }] },
]
const TITLES = Object.fromEntries(NAV.flatMap(g => g.items.map(i => [i.id, i.label])))
const SUBS = Object.fromEntries(NAV.flatMap(g => g.items.map(i => [i.id, i.sub])))
const SETTINGS = [
  { key: "intro", label: "Kamerafahrt am Tagesbeginn", hint: "Nach dem Laden am Hof fliegt die Kamera kurz über deinen Hof, dann geht es los. Enter überspringt sie.", opts: [{ v: true, l: "An", def: true }, { v: false, l: "Aus" }] },
  { key: "dayNight", label: "Tag-Nacht-Zyklus", hint: "Die Uhr läuft 10× schneller (wie der Fahrtenschreiber). Aus: echte Uhrzeit von BeamNG.Earth.", opts: [{ v: true, l: "An", def: true }, { v: false, l: "Aus" }] },
  { key: "traffic", label: "Verkehr", hint: "Passt sich automatisch an die Bildrate an.", opts: [{ v: "off", l: "Aus" }, { v: "low", l: "Wenig" }, { v: "auto", l: "Normal", def: true }, { v: "high", l: "Viel" }] },
  { key: "eventTest", select: true, label: "Ereignis testen", hint: "Zum Anschauen: das gewählte Ereignis kommt gleich auf deiner gesetzten Route, etwa 750 m voraus. Dafür muss eine Route aktiv sein.", opts: [
    { v: "roadworks:rand", l: "Fahrbahnrand" }, { v: "roadworks:ampel", l: "Ampel" }, { v: "roadworks:belag", l: "Belag" }, { v: "roadworks:wand", l: "Betonwand" },
    { v: "roadworks:kurz", l: "Tagesbaustelle" }, { v: "roadworks:kanal", l: "Kanal" }, { v: "roadworks:bruecke", l: "Brücke" }, { v: "roadworks:nacht", l: "Nacht" },
    { v: "radar", l: "Blitzer" }, { v: "laser", l: "Laser" }, { v: "control", l: "Kontrolle" }, { v: "breakdown", l: "Panne" }, { v: "cargo", l: "Ladung" },
    { v: "crash", l: "Unfall" }, { v: "oil", l: "Ölspur" }, { v: "grit", l: "Splitt" }, { v: "potholes", l: "Schlaglöcher" }, { v: "mowing", l: "Mähen" },
    { v: "siren", l: "Blaulicht" }, { v: "heavy", l: "Schwertransport" }, { v: "ghost", l: "Falschfahrer" },
    { v: "fail:tire", l: "Eigene Panne: Reifen" }, { v: "fail:radiator", l: "Eigene Panne: Kühler" }, { v: "fail:hose", l: "Eigene Panne: Notlauf" }, { v: "fail:oil", l: "Eigene Panne: Öl" } ] },
  { key: "breakdowns", label: "Pannen unterwegs", hint: "Hin und wieder platzt ein Reifen oder der Kühler gibt auf, auch wenn du nichts falsch gemacht hast. Dann hilft der Pannendienst.", opts: [{ v: true, l: "An", def: true }, { v: false, l: "Aus" }] },
  { key: "loadMusic", label: "Lademusik", hint: "Der Truck-Beat auf den Ladebildschirmen: beim Reinladen, zum Hof, auf Fähren und Flügen.", opts: [{ v: true, l: "An", def: true }, { v: false, l: "Aus" }] },
  { key: "radioRegional", label: "Regionalsender", hint: "Fährst du in ein anderes Bundesland, wechselt das Radio mit kurzem Rauschen auf den Sender von dort. Von Hand umschalten geht weiterhin.", opts: [{ v: true, l: "An", def: true }, { v: false, l: "Aus" }] },
  { key: "cb", label: "CB-Funk", hint: "Alle paar Minuten meldet sich ein anderer Fahrer auf dem Kanal. Steht wirklich etwas auf deiner Route, sagt er es dir.", opts: [{ v: true, l: "An", def: true }, { v: false, l: "Aus" }] },
  { key: "realWeather", label: "Echtes Wetter", hint: "Wolken, Regen, Nebel, Wind und Temperatur kommen von BeamNG.Earth – das tatsächliche Wetter dort, wo du gerade fährst. Die Uhrzeit bleibt die der Karriere. Aus: das Wetter stellst du im Spiel selbst ein.", opts: [{ v: true, l: "An", def: true }, { v: false, l: "Aus" }] },
  { key: "trafficCars", label: "Verkehrsfahrzeuge", hint: "Agent Traffic: die europäischen Verkehrsautos der Mod Agent Traffic (falls installiert – sonst automatisch BeamNG). BeamNG vereinfacht: die vereinfachten Autos des Spiels. Beide sparen Rechenleistung; Busse und LKW gibt es nicht vereinfacht – davon fährt höchstens einer.", opts: [{ v: "agent", l: "Agent Traffic", def: true }, { v: "simple", l: "BeamNG vereinfacht" }] },
  { key: "aiTraffic", label: "Zusatz-Mod „Realistic AI Traffic“", hint: "Nicht nötig fürs Überholen – das macht „Verkehr: Überholen & Rücksicht“. Diese fremde Beta-Mod gibt den Fahrern zusätzlich Persönlichkeiten, kann aber ruckeln, viel hupen und sich abgestellte Fahrzeuge greifen. Empfohlen: Aus. Wirkt nach Neustart.", opts: [{ v: false, l: "Aus (empfohlen)", def: true }, { v: true, l: "An (Beta)" }] },
  { key: "parked", label: "Geparkte Autos", hint: "Auf Parkplätzen und am Straßenrand in Ortsstraßen (nicht an Haupt- und Landstraßen).", opts: [{ v: "off", l: "Aus" }, { v: "low", l: "Wenig" }, { v: "auto", l: "Normal", def: true }, { v: "high", l: "Viel" }] },
  { key: "navVoice", label: "Navi-Ansagen", hint: "Abbiegehinweise mit Pfeil im Routenberater und als Sprache (deutsche Stimme). Den Ton schaltet auch der Lautsprecher-Knopf auf der Karte.", opts: [{ v: true, l: "An", def: true }, { v: false, l: "Aus" }] },
  { key: "perfMode", label: "Leistung", hint: "Maximale FPS: weniger Verkehr, keine geparkten Autos, Spiegel auf „Sparsam“. Ausgewogen: deine vorherigen Einstellungen.", opts: [{ v: "balanced", l: "Ausgewogen", def: true }, { v: "max", l: "Maximale FPS" }] },
  { key: "slowmo", label: "Unfall-Zeitlupe", hint: "Kracht es ab etwa 25 km/h, läuft der Aufprall kurz in Zeitlupe ab – mit dumpfem Schlag und Ohrenpfeifen. Aus: alles in Echtzeit.", opts: [{ v: true, l: "An", def: true }, { v: false, l: "Aus" }] },
  { key: "drugFx", label: "Rausch-Effekt", hint: "Nach Bier oder Joint schwankt die Sicht leicht, das Bild bekommt einen dunklen Rand und eine Färbung. Aus: kein Bildeffekt – Promille und THC zählen bei Kontrollen trotzdem.", opts: [{ v: true, l: "An", def: true }, { v: false, l: "Aus" }] },
  { key: "smartTraffic", label: "Verkehr: Überholen & Rücksicht", hint: "Autos überholen langsame LKW, wenn der Gegenverkehr es zulässt (brechen ab, wenn es eng wird), und bremsen vor Baustellen, Blitzern, Kontrollen und Unfällen. Hauptstraßen werden automatisch Vorfahrtsstraßen.", opts: [{ v: true, l: "An", def: true }, { v: false, l: "Aus" }] },
  { key: "accidents", label: "Unfälle & Polizei", hint: "Nach einem Unfall kommen Polizei (und Rettungsdienst) und nehmen einen Bericht auf.", opts: [{ v: true, l: "An", def: true }, { v: false, l: "Aus" }] },
  { key: "events", label: "Ereignisse", hint: "Baustellen, mobile Blitzer und Polizeikontrollen auf der Route.", opts: [{ v: true, l: "An", def: true }, { v: false, l: "Aus" }] },
  { key: "hitch", label: "Ankuppeln", hint: "Automatisch: rückwärts heranfahren und anhalten. Selbst: darunter setzen und L.", opts: [{ v: "auto", l: "Automatisch", def: true }, { v: "manual", l: "Selbst" }] },
  { key: "tutorial", label: "Einführung", hint: "Das Handbuch vom ersten Tag noch einmal zeigen: Aufträge, Fahrzeit, Müdigkeit, Kabine, Radio, Pannen, Club, Versicherung und alle Hilfen.", opts: [{ v: "again", l: "Noch einmal zeigen" }] },
  { key: "truckRules", label: "LKW-Tempo", hint: "Echte LKW-Regeln: Autobahn 80 km/h, Landstraße 60 km/h, in Orten das Schild – dazu der Tempobegrenzer bei 90 km/h (ausbauen lassen kann man ihn in der Werkstatt …). Strafen gibt es nur an echten Blitzern und bei Kontrollen. Aus: es gilt das Schild wie für Autos.", opts: [{ v: true, l: "An", def: true }, { v: false, l: "Aus" }] },
  { key: "speedWarn", label: "Tempo-Warnung", hint: "Der Tacho blinkt, wenn du zu schnell fährst.", opts: [{ v: true, l: "An", def: true }, { v: false, l: "Aus" }] },
]
const TYPE_COLORS = { fuel: "#ffb12e", rest: "#8fd14f", workshop: "#ff8a5e", truckdealer: "#5fb4ff", cardealer: "#5fb4ff",
  viewpoint: "#b86bff", logistics: "#cfd6de", post: "#ffd84a", supermarket: "#4fd18b", industry: "#9aa4b2", port: "#5fb4ff" }

const rootEl = ref(null)
const st = ref(null)
const tab = ref("home")
const evOpen = ref(false)
const townQ = ref(""), townSort = ref("recent")
const TOWN_KIND = { city: "Stadt", town: "Stadt", village: "Dorf" }
const TOWN_SORT = [{ v: "recent", l: "Zuletzt" }, { v: "visits", l: "Am häufigsten" }, { v: "name", l: "A–Z" }]
const sv = computed(() => {
  const v = (st.value && st.value.statsView) || {}
  return { towns: toArray(v.towns), routes: toArray(v.routes), cats: toArray(v.cats), avg: v.avg, n: v.n || 0, jobs: v.jobs || 0, odo: v.odo || 0, freight: v.freight || 0, deliv: v.deliv || 0 }
})
const townList = computed(() => {
  const q = townQ.value.trim().toLowerCase()
  const out = sv.value.towns.filter(x => !q || String(x.name).toLowerCase().includes(q))
  if (townSort.value === "name") out.sort((a, b) => String(a.name).localeCompare(String(b.name), "de"))
  else if (townSort.value === "visits") out.sort((a, b) => b.n - a.n || String(a.name).localeCompare(String(b.name), "de"))
  else out.sort((a, b) => (b.l || 0) - (a.l || 0) || b.n - a.n)
  return out
})
const cv = computed(() => {
  const v = st.value && st.value.clubView
  if (!v) return null
  return { ...v, tiers: toArray(v.tiers), plans: toArray(v.plans).map(p => ({ ...p, lines: toArray(p.lines).map(toArray) })), rewards: toArray(v.rewards), sbs: toArray(v.sbs) }
})
const driverTitle = computed(() => {
  const a = sv.value.avg
  if (!a) return "Noch keine bewertete Fahrt"
  return a >= 4.6 ? "Meisterfahrer" : a >= 4 ? "Profi" : a >= 3.2 ? "Solider Fahrer" : a >= 2.2 ? "Auf Bewährung" : "Fahrschule ruft an"
})
const km0 = x => Math.round(x || 0).toLocaleString("de-DE")
const de1 = x => Number(x || 0).toFixed(1).replace(".", ",")
const date0 = t => new Date(t * 1000).toLocaleDateString("de-DE")
const sel = ref(null), selPlace = ref(null), filter = ref(null), kind = ref("all")
const confirmReset = ref(false)
const trucks = ref([]), trucksUsed = ref([]), cars = ref([]), carQuery = ref(""), openModel = ref(null)
const dealerTab = ref("new")

const offers = computed(() => toArray(st.value && st.value.offers))
const filteredOffers = computed(() => offers.value.filter(o => kind.value === "all" || (kind.value === "long" ? o.long : !o.long)))
const owned = computed(() => toArray(st.value && st.value.owned))
const types = computed(() => toArray(st.value && st.value.types))
const here = computed(() => st.value && (st.value.player || st.value.home))
const initials = computed(() => {
  const n = (st.value && st.value.company && st.value.company.name) || "Spedition"
  return n.split(/\s+/).filter(Boolean).slice(0, 2).map(w => w[0].toUpperCase()).join("")
})
const xpPct = computed(() => (st.value && st.value.xpTo ? Math.min(100, Math.round(st.value.xp / st.value.xpTo * 100)) : 0))
function haversine(a, b) {
  if (!a || !b) return null
  const r = Math.PI / 180, dLat = (b.lat - a.lat) * r, dLon = (b.lon - a.lon) * r
  const x = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * r) * Math.cos(b.lat * r) * Math.sin(dLon / 2) ** 2
  return 2 * 6371000 * Math.asin(Math.min(1, Math.sqrt(x)))
}
const placesCache = ref([])
// a destination pasted (coordinates or a map link: BeamNG.Earth 1.8.1 reads Google Maps / OpenStreetMap links)
const goText = ref(""), goMsg = ref(""), goOk = ref(false)
// the route planner (career.lua route*): the answer is the route again, shown at once (and with the next poll)
const routeLocal = ref(null)
const route = computed(() => {
  const r = routeLocal.value || (st.value && st.value.route) || {}
  return { stops: toArray(r.stops), idx: r.idx, totalKm: r.totalKm || 0 }
})
function routeCall(fn, ...args) {
  call(fn, ...args, r => {
    const rt = r && (r.route || (r.stops !== undefined ? r : null))
    if (rt) routeLocal.value = rt
    if (r && r.msg) { goMsg.value = r.msg; goOk.value = !!r.ok }
    setTimeout(() => { routeLocal.value = null }, 1500)
  })
}
function routeAddText() {
  const t = goText.value.trim()
  if (!t) { goMsg.value = "Erst Koordinaten oder einen Link einfügen."; goOk.value = false; return }
  routeCall("routeAddText", t)
}
function goToText() {
  const t = goText.value.trim()
  if (!t) return
  call("navToText", t, r => { goOk.value = !!(r && r.ok); goMsg.value = (r && r.msg) || "" })
}
const selDoc = ref(null)
// the evidence of an accident report: the photos (a click: big)
const bigPhoto = ref(null)
watch(selDoc, () => { bigPhoto.value = null })
// (the game writes temp/... – the page loads it from the root: /temp/...)
const imgSrc = f => (!f ? "" : (f.startsWith("/") ? f : "/" + f))
function photoErr(e) { e.target.closest("figure").classList.add("missing") }
const docs = computed(() => toArray(st.value && st.value.documents))
const tr = computed(() => st.value && st.value.travel)
const hours = h => (h < 1 ? Math.round(h * 60) + " min" : (Math.round(h * 4) / 4).toLocaleString("de-DE") + " h")
const places = computed(() => placesCache.value.map(p => ({ ...p, d: haversine(here.value, p) })).sort((a, b) => (a.d || 0) - (b.d || 0)))
const filteredPlaces = computed(() => places.value.filter(p => !filter.value || p.type === filter.value).slice(0, 80))
const dealers = computed(() => places.value.filter(p => p.type === "truckdealer" || p.type === "cardealer"))
const filteredCars = computed(() => {
  const q = carQuery.value.trim().toLowerCase()
  return (q ? cars.value.filter(m => (m.brand + " " + m.modelName).toLowerCase().includes(q)) : cars.value).slice(0, 120)
})
const mapCenter = computed(() => here.value || { lat: 51.16, lon: 10.45 })
const homeMarker = () => (st.value && st.value.home ? [{ ...st.value.home, kind: "home", icon: "🏠", label: "Hof" }] : [])
const playerMarker = () => (st.value && st.value.player ? [{ ...st.value.player, kind: "player", label: "Du" }] : [])
const marketMarkers = computed(() => {
  const out = [...homeMarker(), ...playerMarker()]
  const o = sel.value
  if (o) {
    out.push({ lat: o.from.lat, lon: o.from.lon, kind: "pickup", label: "Laden: " + o.from.name })
    out.push({ lat: o.to.lat, lon: o.to.lon, kind: "delivery", label: "Abladen: " + o.to.name })
  }
  return out
})
// (2026-11-07: every known place on the map, not only the 80 nearest of the list – the map shows those in view and
// thins them out where they crowd)
const placeMarkers = computed(() => [
  ...places.value.filter(p => !filter.value || p.type === filter.value).map(p => ({ lat: p.lat, lon: p.lon, kind: selPlace.value && selPlace.value.id === p.id ? "pickup" : "depot", icon: p.icon, label: p.name })),
  ...homeMarker(), ...playerMarker()])

// the Zentrale's tiles: every area with what matters there right now
const greeting = computed(() => {
  const h = parseInt(((st.value && st.value.clock) || "12").split(":")[0], 10)
  return h < 5 ? "Gute Nacht" : h < 11 ? "Guten Morgen" : h < 18 ? "Guten Tag" : "Guten Abend"
})
const tiles = computed(() => {
  const s = st.value
  if (!s) return []
  const out = []
  const j = s.job
  out.push(j
    ? { id: "job", icon: "🚛", title: "Aktueller Auftrag", color: "#4fd18b", wide: true, value: j.cargoName + " → " + j.to,
        sub: j.text + (j.timeLeft !== undefined ? " · noch " + duration(j.timeLeft) : ""), bar: j.cond, alert: j.timeLeft < 0 }
    : { id: "market", icon: "📋", title: "Kein Auftrag", color: "#4fd18b", wide: true, value: "Neue Fracht suchen",
        sub: offers.value.length + " Angebote in der Frachtbörse" })
  const best = offers.value.reduce((m, o) => (!m || o.freight > m.freight ? o : m), null)
  const special = offers.value.find(o => o.special)
  out.push({ id: "market", icon: "📦", title: "Frachtbörse", color: "#ffb12e", value: offers.value.length + " Angebote",
    sub: special ? "Stammtour: " + special.from.name + " → " + special.to.name : best ? "Bestes: " + money(best.freight) + " · " + best.cargoName : "–",
    badge: special ? "Stammtour" : null })
  out.push({ id: "fleet", icon: "🔧", title: "Fuhrpark & Werkstatt", color: "#cfd6de",
    value: s.activeDef ? (s.activeDef.brand || "") + " " + (s.activeDef.modelName || "") : "–",
    sub: owned.value.length + " eigene Fahrzeuge" + (s.damage !== undefined && s.damage !== null ? " · Zustand " + Math.round((1 - s.damage) * 100) + " %" : ""),
    bar: s.damage !== undefined && s.damage !== null ? 1 - s.damage : undefined, alert: s.damage > 0.3 })
  out.push({ id: "bank", icon: "🏦", title: "Bank & Bußgelder", color: "#5fb4ff", value: money(s.money),
    sub: (s.loan > 0 ? "Kredit " + money(s.loan) : "kein Kredit") + (toArray(s.fines)[0] ? " · letztes Bußgeld " + money(toArray(s.fines)[0].amount) : ""),
    alert: s.money < 0 })
  if (s.tacho) {
    // (information only: breaks and sleep are taken at the stop rings and on the tachograph itself)
    out.push({ id: null, icon: "⏱", title: "Fahrtenschreiber", color: "#3ad38b", value: s.tacho.driveText + " bis Pause",
      sub: "heute noch " + s.tacho.dayText + (s.tacho.violations ? " · " + s.tacho.violations + " Verstoß" : "") + " · Pause/Schlafen: am Haltepunkt (Enter)",
      bar: Math.max(0, s.tacho.driveLeft / 16200), alert: s.tacho.driveLeft <= 0 || s.tacho.violations > 0 })
  }
  out.push({ id: "map", icon: "🗺", title: "Karte & Orte", color: "#5fb4ff", value: placesCache.value.length + " Orte bekannt",
    sub: s.near ? "Hier: " + s.near.name : "Tankstellen, Rastplätze, Kunden, Händler" })
  const tv = s.travel
  out.push({ id: "travel", icon: "⚓", title: "Reisen", color: "#7fd3ff", value: tv && tv.hub ? tv.hub.name : "Fähre & Flug",
    sub: tv && tv.hub ? "Abfahrten von hier" : (tv && toArray(tv.ferries)[0] ? "Nächster Hafen: " + toArray(tv.ferries)[0].name : "Häfen und Flughäfen"),
    badge: tv && tv.hub ? "hier" : null })
  out.push({ id: "dealer", icon: "🏷", title: "Händler", color: "#b48cff", value: s.near && /^dealer/.test(s.near.action) ? s.near.name : dealers.value.length + " Händler bekannt",
    sub: "Neue und gebrauchte LKW und Autos", badge: s.near && /^dealer/.test(s.near.action) ? "hier" : null })
  const d0 = docs.value[0]
  out.push({ id: "docs", icon: "📄", title: "Dokumente", color: "#cfd6de", value: docs.value.length + " Dokumente",
    sub: d0 ? d0.title + " · " + (d0.town || d0.road || "") : "Unfallberichte, Bescheide" })
  const m0 = toArray(s.log)[0]
  out.push({ id: "messages", icon: "💬", title: "Nachrichten", color: "#ffd84a", wide: true, value: m0 ? m0.from : "Keine Nachrichten",
    sub: m0 ? m0.text : "" })
  return out
})
function goTile(t) { sound("click"); setTab(t.id) }

// --- the Finanzen page: the books as graphs (career.lua S.ledger: { d day, h hour, c category, a amount, l text, b balance })
const CAT_COLORS = { Fracht: "#3ad38b", Entdeckung: "#7fd3ff", Fahrzeuge: "#b48cff", Diesel: "#ffb12e", "Maut & Verschleiß": "#ff8a5e",
  Werkstatt: "#ff5b4d", Reisen: "#5fb4ff", Bußgelder: "#ff6b8a", Überführung: "#9aa4b2", Vertragsstrafe: "#c46b3a", Kredit: "#6f7a88" }
const catColor = c => CAT_COLORS[c] || "#8b95a3"
const DAYS = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]
const dayName = d => DAYS[((d || 1) - 1) % 7].slice(0, 2) + "."
const hm = h => { h = h || 0; return String(Math.floor(h) % 24).padStart(2, "0") + ":" + String(Math.floor((h % 1) * 60)).padStart(2, "0") }
// (the loan moves money but is no income or expense: left out of the sums and the graphs of earnings)
const isFlow = b => b.c !== "Kredit"
const fin = computed(() => {
  const L = toArray(st.value && st.value.ledger).map(x => (Array.isArray(x) ? x : x))
  const today = (st.value && st.value.day) || 1
  const out = { in7: 0, out7: 0, cats: [], days: [], dayW: 60, recent: L.slice(-30).reverse(), trendText: "",
    bal: { n: 0, path: "", area: "", grid: [], zero: null, last: [0, 0], min: 0, max: 0 } }
  for (const b of L) {
    if (!isFlow(b) || b.d < today - 6) continue
    if (b.a > 0) out.in7 += b.a; else out.out7 += -b.a
  }
  // the balance: the last 60 bookings as a line (with the area below it)
  const B = L.slice(-60)
  if (B.length > 1) {
    const vals = B.map(b => b.b)
    let min = Math.min(...vals), max = Math.max(...vals)
    if (max - min < 1) { max += 1; min -= 1 }
    const pad = (max - min) * 0.08; min -= pad; max += pad
    const X = i => (i / (B.length - 1)) * 600, Y = v => 160 - ((v - min) / (max - min)) * 150
    const pts = B.map((b, i) => [X(i), Y(b.b)])
    out.bal = { n: B.length, min, max, last: pts[pts.length - 1],
      path: pts.map((p, i) => (i ? "L" : "M") + p[0].toFixed(1) + " " + p[1].toFixed(1)).join(" "),
      area: "M0 170 " + pts.map(p => "L" + p[0].toFixed(1) + " " + p[1].toFixed(1)).join(" ") + " L600 170 Z",
      grid: [0.25, 0.5, 0.75].map(k => ({ y: 10 + k * 150 })),
      zero: min < 0 && max > 0 ? Y(0) : null }
    const first = B[0].b, last = B[B.length - 1].b
    out.trendText = (last >= first ? "▲ " : "▼ ") + money(Math.abs(last - first)) + " seit " + B.length + " Buchungen"
  }
  // per game day: income up, expenses down (the last 10 days)
  const from = Math.max(1, today - 9), days = []
  for (let d = from; d <= today; d++) days.push({ d, inc: 0, out: 0 })
  for (const b of L) {
    if (!isFlow(b) || b.d < from) continue
    const x = days[b.d - from]
    if (!x) continue
    if (b.a > 0) x.inc += b.a; else x.out += -b.a
  }
  const peak = Math.max(1, ...days.map(x => Math.max(x.inc, x.out)))
  out.dayW = 600 / days.length
  out.days = L.length ? days.map(x => ({ ...x, hi: (x.inc / peak) * 78, ho: (x.out / peak) * 78, name: DAYS[(x.d - 1) % 7] + " (Tag " + x.d + ")", short: dayName(x.d) })) : []
  // the expenses by kind
  const sums = {}
  let total = 0
  for (const b of L) if (isFlow(b) && b.a < 0) { sums[b.c] = (sums[b.c] || 0) - b.a; total -= b.a }
  out.cats = Object.entries(sums).map(([c, sum]) => ({ c, sum, pct: total ? (sum / total) * 100 : 0, color: catColor(c) })).sort((a, b) => b.sum - a.sum)
  return out
})
const titleOf = id => TITLES[id] || ""
const typeColor = t => TYPE_COLORS[t] || "#6f7a88"
const sellValue = t => Math.round(t.price * Math.max(0.4, 0.75 - (t.km || 0) / 20000) / 100) * 100
const condClass = c => (c > 0.8 ? "pos" : c > 0.5 ? "warn" : "neg")
function badge(id) {
  if (!st.value) return null
  if (id === "market") return offers.value.length || null
  if (id === "job") return st.value.job ? "1" : null
  if (id === "dealer") return st.value.near && /^dealer/.test(st.value.near.action) ? "hier" : null
  if (id === "docs") return docs.value.length || null
  if (id === "travel") return st.value.travel && st.value.travel.hub ? "hier" : null
  return null
}

function loadCatalogs() {
  if (!st.value || !st.value.near) return
  if (st.value.near.action === "dealerTruck" && !trucks.value.length) {
    call("uiCatalog", "truck", r => {
      const eu = st.value && st.value.europe
      trucks.value = toArray(r).sort((a, b) => (eu && a.eu !== b.eu ? (a.eu ? -1 : 1) : a.price - b.price))
    })
  }
  if (st.value.near.action === "dealerTruck" && (!trucksUsed.value.length || usedStale)) {
    usedStale = false
    call("uiCatalog", "truckUsed", r => { trucksUsed.value = toArray(r) })
  }
  if (st.value.near.action === "dealerCar" && !cars.value.length) call("uiCatalog", "car", r => { cars.value = toArray(r) })
}
function setTab(t) {
  if (t === "overview") t = "home"                  // (the old overview page is the Zentrale now)
  if (t === "job") t = "market"                     // (the job is on the Aufträge page)
  if (t !== tab.value) sound("click")
  tab.value = t
  if (t === "dealer") loadCatalogs()
  if (t === "bank") refresh()                       // (the books come with the next state: at once)
}
// (the places only for the pages that list them: thousands, kept between polls)
// the trailer of an offer: its photo (the game's picture of that configuration) and name (2026-11-07)
function trailerPic(o) {
  const t = o && o.trailer
  if (!t || !t.model) return ""
  if (t.preview) return t.preview
  const c = String(t.config || "").replace(/^.*\//, "").replace(/\.pc$/, "")
  return "/vehicles/" + t.model + "/" + c + ".jpg"
}
function seizeFee(t) { return Math.round((t.price || 60000) * 0.25 / 100) * 100 }
function trailerName(o) { return (o && o.trailer && o.trailer.name) || "Auflieger" }
const PLACE_TABS = ["map", "dealer", "messages"]
function take(s) {
  if (!s) return
  if (s.places !== undefined && s.places !== null) placesCache.value = toArray(s.places)
  st.value = s
}
function refresh() {
  const need = PLACE_TABS.includes(tab.value) || !placesCache.value.length
  call("uiState", need, tab.value === "bank", s => { if (s) { take(s); if (tab.value === "dealer") loadCatalogs() } })
}
function act(fn, ...args) { call(fn, ...args, () => refresh()) }
let usedStale = false
function buy(fn, ...args) { if (fn === "buyUsedTruck") usedStale = true; call(fn, ...args, () => { refresh(); close() }) }
function accept(o) { call("acceptOffer", o.id, () => { refresh(); close() }) }
// the customer's request: a counter-offer (career.lua negotiate) – more is a risk, less is always taken
const NEG = [-0.1, -0.05, 0.05, 0.1, 0.2]
const negPct = ref(0), negBusy = ref(false), negMsg = ref(null)
function negotiate(o) {
  negBusy.value = true
  call("negotiate", o.id, negPct.value, r => {
    negBusy.value = false
    negMsg.value = { id: o.id, text: (r && r.msg) || "Keine Antwort.", accepted: r && r.accepted }
    sound(r && r.accepted ? "done" : "back")
    negPct.value = 0
    refresh()
  })
}
// (the glass goes first, then the page: the world comes back sharp at the same time)
const closing = ref(false)
function close() {
  if (closing.value) return
  closing.value = true
  sound("back")
  call("uiOfficeOpen", false)
  setTimeout(() => navigate("play"), 210)
}

let timer = null
onMounted(() => {
  call("uiOfficeOpen", true)
  call("uiOfficeReady", s => {
    if (s && !s.company) { navigate("fernfahrerSetup"); return }
    if (!s) return
    take(s)
    if (s.openTab) setTab(s.openTab)
    else if (s.near && /^dealer/.test(s.near.action)) setTab("dealer")
    else if (s.near && (s.near.action === "ferry" || s.near.action === "fly")) setTab("travel")
    else tab.value = "home"
  })
  sound("open")
  timer = setInterval(refresh, 1000)
  nextTick(() => rootEl.value && rootEl.value.focus())
})
onUnmounted(() => { clearInterval(timer); call("uiOfficeOpen", false); typing(false) })
</script>

<style scoped>
/* (2026-11-05: the game's own typeface; the office fades in, the frame rises; each tab slides in) */
@font-face { font-family: FFWave; font-weight: 300; src: url(/ui/common/LTWave/LTWave-Light.otf); }
@font-face { font-family: FFWave; font-weight: 500; src: url(/ui/common/LTWave/LTWave-Medium.otf); }
@font-face { font-family: FFWave; font-weight: 700; src: url(/ui/common/LTWave/LTWave-Bold.otf); }
@font-face { font-family: FFWave; font-weight: 900; src: url(/ui/common/LTWave/LTWave-Black.otf); }
.ffo { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; background: rgba(6,8,12,.78);
  color: #e9edf2; font-family: FFWave, 'Noto Sans', sans-serif; outline: none; animation: ffoFade .28s ease-out; }
@keyframes ffoFade { from { background: rgba(6,8,12,0); } }
.frame { animation: ffoRise .42s cubic-bezier(.2,.8,.2,1); }
@keyframes ffoRise { from { opacity: 0; transform: translateY(16px) scale(.985); } }
.tabIn { animation: ffoTab .32s cubic-bezier(.2,.8,.2,1); }
@keyframes ffoTab { from { opacity: 0; transform: translateX(10px); } }
.nav { transition: background .15s, color .15s, border-color .2s; }
.frame { width: min(1800px, 98vw); height: 93vh; display: flex; background: #12161c; border: 1px solid #252c36; border-radius: 14px;
  overflow: hidden; box-shadow: 0 24px 80px rgba(0,0,0,.6); }
aside { width: 250px; flex: none; display: flex; flex-direction: column; background: #0d1015; border-right: 1px solid #222832; padding: 16px 0; }
.brand { display: flex; gap: 10px; align-items: center; padding: 0 16px 16px; border-bottom: 1px solid #222832; margin-bottom: 8px; }
.mark { width: 40px; height: 40px; flex: none; border-radius: 4px; background: #ffb12e; color: #15100a; font-weight: 900; font-size: 13px;
  display: flex; align-items: center; justify-content: center; letter-spacing: .5px; }
.cname { font-weight: 800; font-size: 15px; } .csub { font-size: 11.5px; color: #8b95a3; }
.sect { padding: 14px 16px 6px; font-size: 10.5px; letter-spacing: .14em; text-transform: uppercase; color: #6f7a88; font-weight: 800; }
.nav { display: flex; align-items: center; gap: 10px; padding: 9px 16px; font-size: 13.5px; font-weight: 600; color: #b9c2cd; cursor: pointer;
  border-left: 3px solid transparent; }
.nav:hover { background: #161b22; color: #fff; }
.nav.on { background: #1a2029; color: #fff; border-left-color: #ffb12e; }
.nav .dot { width: 7px; height: 7px; border-radius: 50%; flex: none; }
.nav .cnt { margin-left: auto; font-size: 11px; background: #252c36; border-radius: 9px; padding: 0 7px; color: #cfd6de; }
.nav .key { margin-left: auto; font-size: 10.5px; color: #6f7a88; border: 1px solid #2c3440; border-radius: 3px; padding: 0 5px; }
.grow { flex: 1; }
.content { flex: 1; min-width: 0; display: flex; flex-direction: column; }
header { display: flex; align-items: center; gap: 24px; padding: 14px 22px; border-bottom: 1px solid #222832; }
.title { font-size: 20px; font-weight: 800; letter-spacing: .02em; }
.kpis { margin-left: auto; display: flex; gap: 26px; align-items: center; }
.kpis span { display: block; font-size: 10px; letter-spacing: .1em; text-transform: uppercase; color: #6f7a88; }
.kpis b { font-size: 17px; font-variant-numeric: tabular-nums; }
.xp { width: 110px; height: 4px; background: #252c36; border-radius: 2px; margin-top: 5px; overflow: hidden; } .xp i { display: block; height: 100%; background: #ffb12e; }
.here { padding: 7px 22px; font-size: 12.5px; background: #15241b; color: #bfe8cd; border-bottom: 1px solid #1f3a29; }
main { flex: 1; min-height: 0; overflow-y: auto; padding: 18px 22px; }
h3 { margin: 0 0 10px; font-size: 11px; letter-spacing: .12em; text-transform: uppercase; color: #8b95a3; }
.bar { display: flex; align-items: center; gap: 12px; margin-bottom: 12px; flex-wrap: wrap; }
.row { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; margin: 12px 0; }
.muted { color: #8b95a3; font-size: 12px; } .small { font-size: 11px; margin-top: 6px; }
.info { padding: 10px 12px; border-radius: 4px; background: #15202c; color: #c9dcf0; font-size: 13px; margin-bottom: 10px; border-left: 3px solid #5fb4ff; }
.info.warn { background: #2a2214; color: #f0dcb5; border-left-color: #ffb12e; }
.split { display: grid; grid-template-columns: minmax(0, 2fr) minmax(240px, 1fr); gap: 18px; height: 100%; }
.split .list { overflow-y: auto; overflow-x: hidden; min-height: 0; min-width: 0; padding-right: 4px; }
.split .tbl td.ft { overflow-wrap: anywhere; }
.evsel { background: #1a2029; color: #eef1f5; border: 1px solid #2c3440; border-radius: 4px; padding: 7px 12px; font: inherit; flex: none; cursor: pointer; transition: background .2s, border-color .2s; }
.evsel:hover { background: #232b37; border-color: #3b4656; }
.evsel i { display: inline-block; font-style: normal; margin-left: 4px; transition: transform .25s cubic-bezier(.16,1,.3,1); } .evsel i.up { transform: rotate(180deg); }
.evlist { display: grid; grid-template-columns: repeat(auto-fill, minmax(140px, 1fr)); gap: 6px; margin-top: 10px; animation: evin .28s cubic-bezier(.16,1,.3,1); }
.evlist a { padding: 7px 10px; border-radius: 4px; background: #1a2029; border: 1px solid #2c3440; cursor: pointer; font-size: 12.5px; transition: background .18s, border-color .18s, transform .18s; }
.evlist a:hover { background: #2a3442; border-color: #ffb12e; transform: translateY(-1px); }
@keyframes evin { from { opacity: 0; transform: translateY(-6px); } to { opacity: 1; transform: none; } }
/* the club and the insurance */
.clb { --gold: #ffc929; --gold2: #f09a12; }
.chero { display: grid; grid-template-columns: 380px minmax(0, 1fr) 170px; gap: 14px; align-items: stretch; }
.ccard { position: relative; aspect-ratio: 1.586; border-radius: 16px; padding: 18px 20px; display: flex; flex-direction: column; color: #1c1503; overflow: hidden; background: linear-gradient(135deg, #ffdb5c 0%, #ffc21f 46%, #ee9410 100%); box-shadow: 0 14px 34px rgba(0,0,0,.45), inset 0 1px 0 rgba(255,255,255,.55); }
.ccard::before { content: ""; position: absolute; right: -70px; top: -90px; width: 290px; height: 290px; border-radius: 50%; background: rgba(255,255,255,.2); }
.ccard::after { content: ""; position: absolute; left: -60px; bottom: -130px; width: 300px; height: 240px; border-radius: 50%; background: rgba(120,60,0,.14); }
.ccard.lv0 { background: linear-gradient(135deg, #59616e, #39404b 60%, #2a2f38); color: #eef1f5; }
.ccard.lv2 { background: linear-gradient(135deg, #f2f4f7 0%, #c9d0da 50%, #98a3b2 100%); color: #15181d; }
.ccard.lv3 { background: linear-gradient(135deg, #39312a 0%, #18140f 58%, #000 100%); color: #ffd98a; }
.ccard > * { position: relative; z-index: 1; }
.cc-top { display: flex; align-items: center; gap: 10px; }
.cc-logo { font-size: 23px; font-weight: 900; letter-spacing: .04em; font-style: italic; }
.cc-name { font-size: 11.5px; font-weight: 700; opacity: .8; }
.cc-chip { margin-left: auto; width: 40px; height: 30px; border-radius: 6px; background: linear-gradient(135deg, #f8e7a8, #c79a3a); box-shadow: inset 0 0 0 1px rgba(90,60,0,.45); }
.cc-tier { margin-top: auto; font-size: 31px; font-weight: 900; line-height: 1; letter-spacing: -.01em; }
.cc-no { margin-top: 5px; font: 700 15px Consolas, monospace; letter-spacing: .14em; opacity: .85; }
.cc-foot { display: flex; gap: 24px; margin-top: 12px; font-size: 13px; font-weight: 800; }
.cc-foot small { display: block; font-size: 9.5px; font-weight: 800; letter-spacing: .1em; text-transform: uppercase; opacity: .62; }
.cpts { display: flex; align-items: center; gap: 22px; padding: 18px 22px; background: linear-gradient(135deg, #1b212b, #141920); border: 1px solid #262e3a; border-radius: 16px; }
.ring { flex: none; width: 138px; height: 138px; border-radius: 50%; display: flex; align-items: center; justify-content: center; background: conic-gradient(var(--gold) calc(var(--p) * 1%), rgba(255,255,255,.09) 0); }
.ring > div { width: 112px; height: 112px; border-radius: 50%; background: #171c24; display: flex; flex-direction: column; align-items: center; justify-content: center; }
.ring b { font-size: 31px; font-weight: 900; line-height: 1; font-variant-numeric: tabular-nums; } .ring small { font-size: 11px; color: #8b95a3; margin-top: 3px; }
.cpts-t h3 { margin: 0 0 6px; font-size: 19px; font-weight: 800; } .cpts-t p { margin: 0 0 5px; font-size: 13.5px; }
.cchips { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 7px; } .cchips span { font-size: 11.5px; font-weight: 700; padding: 3px 9px; border-radius: 20px; background: rgba(255,201,41,.14); color: #ffd666; }
.csum { display: flex; flex-direction: column; justify-content: center; align-items: center; padding: 14px; text-align: center; background: #141920; border: 1px solid #262e3a; border-radius: 16px; }
.csum span { font-size: 11px; font-weight: 700; color: #8b95a3; text-transform: uppercase; letter-spacing: .05em; } .csum b { font-size: 27px; font-weight: 900; margin-top: 6px; } .csum small { font-size: 12px; color: #9aa4b2; }
.csec { display: flex; align-items: baseline; gap: 8px; margin: 24px 0 10px; font-size: 17px; font-weight: 800; } .csec i { font-style: normal; } .csec small { font-size: 12.5px; font-weight: 500; color: #8b95a3; }
.cgrid { display: grid; gap: 12px; } .cgrid.four { grid-template-columns: repeat(4, minmax(0, 1fr)); } .cgrid.three { grid-template-columns: repeat(3, minmax(0, 1fr)); }
.cplan { position: relative; display: flex; flex-direction: column; text-align: left; padding: 16px; font: inherit; color: #e9edf2; cursor: pointer; background: #161b22; border: 1px solid #262e3a; border-radius: 12px; transition: transform .16s cubic-bezier(.16,1,.3,1), border-color .16s, background .16s; }
.cplan:hover { transform: translateY(-3px); border-color: #4a5566; background: #1a2029; }
.cplan.on { border-color: var(--gold); background: linear-gradient(180deg, rgba(255,201,41,.13), #161b22 62%); box-shadow: 0 0 0 1px var(--gold); }
.cplan.next { border-color: #5aa8ff; }
.cp-badge { position: absolute; right: 12px; top: 12px; font-size: 10px; font-weight: 800; color: #1c1503; background: var(--gold); padding: 2px 8px; border-radius: 20px; } .cp-badge.soon { background: #5aa8ff; color: #08172b; }
.cp-name { font-size: 16.5px; font-weight: 800; } .cp-sub { font-size: 12px; color: #9aa4b2; margin-top: 2px; }
.cp-price { margin-top: 10px; font-size: 25px; font-weight: 900; font-variant-numeric: tabular-nums; } .cp-price small { font-size: 12px; font-weight: 600; color: #8b95a3; }
.cplan ul { list-style: none; margin: 11px 0 0; padding: 11px 0 0; border-top: 1px solid rgba(255,255,255,.08); display: flex; flex-direction: column; gap: 6px; font-size: 12.5px; color: #c6ced8; }
.cplan ul.chk li { position: relative; padding-left: 20px; } .cplan ul.chk li::before { content: "✓"; position: absolute; left: 0; font-weight: 900; color: #3ad38b; }
.cplan ul.chk li.no { color: #6d7683; } .cplan ul.chk li.no::before { content: "–"; color: #6d7683; }
.crew { display: flex; flex-direction: column; gap: 2px; text-align: left; padding: 14px; font: inherit; color: #e9edf2; cursor: pointer; background: #161b22; border: 1px solid #262e3a; border-radius: 12px; transition: transform .16s, border-color .16s; }
.crew:hover:not(:disabled) { transform: translateY(-3px); border-color: var(--gold); } .crew:disabled { opacity: .48; cursor: default; }
.cr-i { font-size: 24px; margin-bottom: 4px; } .crew b { font-size: 14px; } .crew small { font-size: 12px; color: #9aa4b2; min-height: 30px; } .crew em { font-style: normal; font-size: 12.5px; font-weight: 800; color: #ffd666; margin-top: 6px; }
.csf { display: flex; align-items: center; gap: 26px; padding: 14px 18px; margin-bottom: 12px; background: #141920; border: 1px solid #262e3a; border-radius: 12px; }
.csf-l, .csf-o { display: flex; flex-direction: column; } .csf-l span, .csf-o span { font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: .05em; color: #8b95a3; } .csf-l b { font-size: 25px; font-weight: 900; } .csf-o b { font-size: 15px; font-weight: 800; } .csf-l small, .csf-o small, .csf-m small { font-size: 12px; color: #9aa4b2; }
.csf-m { flex: 1; min-width: 0; } .csf-bar { display: flex; gap: 4px; margin-bottom: 6px; } .csf-bar i { flex: 1; height: 9px; border-radius: 3px; background: rgba(255,255,255,.08); } .csf-bar i.on { background: linear-gradient(90deg, #2fbf71, #6fe3a0); }
.csf-o { max-width: 260px; padding-left: 20px; border-left: 1px solid #2c3440; }
.csb { display: flex; align-items: center; justify-content: space-between; gap: 18px; padding: 13px 16px; margin-top: 12px; background: #161b22; border: 1px solid #262e3a; border-radius: 12px; }
.ctl { display: flex; flex-direction: column; } .ctl-i { display: flex; align-items: center; gap: 12px; padding: 10px 0; border-top: 1px solid rgba(255,255,255,.06); } .ctl-i:first-child { border-top: 0; }
.ctl-i > i { flex: none; width: 9px; height: 9px; border-radius: 50%; background: #5aa8ff; } .ctl-i.regress > i { background: #ff6b5e; } .ctl-i.opp > i { background: #3ad38b; } .ctl-i.voll > i { background: var(--gold); }
.ctl-a { text-align: right; flex: none; } .ctl-a b { display: block; font-size: 13.5px; color: #7fe3a4; } .ctl-a b.neg { color: #ff8a80; } .ctl-a small { font-size: 11.5px; color: #8b95a3; }
.stiles { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 12px; margin-bottom: 12px; }
.stile { background: rgba(26, 32, 41, .72); border: 1px solid rgba(255,255,255,.07); border-radius: 8px; padding: 12px 14px; display: flex; flex-direction: column; gap: 3px; }
.stile span { font-size: 11px; font-weight: 700; letter-spacing: .5px; text-transform: uppercase; color: #8b95a3; }
.stile b { font-size: 25px; font-weight: 800; line-height: 1.15; white-space: nowrap; }
.stile small { font-size: 12px; color: #9aa4b2; }
.stile em { font-style: normal; } .dstars.big i { font-size: 15px; }
.routes { max-height: 300px; overflow-y: auto; }
.route { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 1px 10px; padding: 7px 0; border-top: 1px solid rgba(255,255,255,.06); }
.route:first-child { border-top: 0; } .route .rn { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: 13px; }
.route .muted { grid-column: 1; } .route .dstars { grid-column: 2; grid-row: 1 / span 2; align-self: center; }
.townbar { align-items: center; gap: 10px; margin-bottom: 8px; }
.townbar input { flex: 1; min-width: 120px; background: #1a2029; color: #eef1f5; border: 1px solid #2c3440; border-radius: 4px; padding: 7px 10px; font: inherit; }
.towns { display: grid; grid-template-columns: repeat(auto-fill, minmax(210px, 1fr)); gap: 6px; max-height: 340px; overflow-y: auto; }
.town { display: flex; flex-direction: column; gap: 1px; padding: 8px 10px; border-radius: 6px; background: rgba(26, 32, 41, .6); border: 1px solid rgba(255,255,255,.05); }
.town b { font-size: 13.5px; } .town .tn { font-size: 12px; color: #cfd6de; } .town em { font-style: normal; color: #ffc23d; }
@media (max-width: 1100px) { .stiles { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
.map { border-radius: 4px; min-height: 380px; height: 100%; border: 1px solid #252c36; }
.tbl { width: 100%; border-collapse: collapse; font-size: 13px; }
/* the yard's upgrades (2026-11-07) */
.yardup { margin-bottom: 14px; }
.yardup .yh { font-size: 13px; font-weight: 800; letter-spacing: .04em; color: #ffcf7a; margin-bottom: 8px; }
.ycards { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; }
.ycard { display: flex; gap: 10px; align-items: center; padding: 11px 12px; border-radius: 12px; background: #161b22; border: 1px solid #252c36; transition: border-color .15s, transform .15s; }
.ycard:hover { border-color: #3a4352; transform: translateY(-1px); }
.ycard.owned { border-color: rgba(47,191,113,.45); background: linear-gradient(180deg, #15221b, #12181d); }
.ycard .yi { font-size: 24px; width: 34px; text-align: center; }
.ycard .yt { flex: 1; display: flex; flex-direction: column; gap: 3px; } .ycard .yt b { font-size: 13.5px; } .ycard .yt span { font-size: 11.5px; color: #9aa4b2; line-height: 1.35; }
/* the request's counter-offer row (2026-11-05) */
.negrow td { background: #151a21; border-top: 0; animation: ffoTab .25s ease-out; }
.neg { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; padding: 2px 0; }
.neg .nq { font-size: 12.5px; color: #cfd6de; }
.neg .chip { padding: 3px 9px; border-radius: 12px; background: #1d232c; border: 1px solid #2f3742; font-size: 11.5px; font-weight: 800; cursor: pointer; color: #cfd6de; }
.neg .chip.up { color: #ffcf7a; } .neg .chip.on { background: #ffb12e; border-color: #ffb12e; color: #15100a; }
.neg .pay { min-width: 80px; text-align: right; font-variant-numeric: tabular-nums; }
.negmsg { margin-top: 6px; font-size: 12.5px; color: #ff8a80; } .negmsg.good { color: #6fe3a1; }
.tbl th { text-align: left; font-size: 10.5px; letter-spacing: .1em; text-transform: uppercase; color: #6f7a88; font-weight: 700; padding: 6px 8px; border-bottom: 1px solid #252c36; }
.tbl td { padding: 9px 8px; border-bottom: 1px solid #1b2129; vertical-align: top; }
.tbl tr { cursor: default; } .tbl tbody tr:hover { background: #161b22; } .tbl tr.sel { background: #1d2530; }
.tbl .r { text-align: right; white-space: nowrap; }
.tbl .ft div:first-child { font-weight: 600; }
.tags { display: flex; gap: 4px; margin-top: 4px; flex-wrap: wrap; }
.tag { font-size: 10.5px; font-weight: 700; border-radius: 3px; padding: 1px 6px; background: #252c36; color: #b9c2cd; margin-left: 4px; }
.tags .tag { margin-left: 0; }
.tag.blue { background: #1c3550; color: #a9d2ff; } .tag.green { background: #183823; color: #a6efc0; } .tag.red { background: #4a1d1a; color: #ffb3aa; }
.tag.violet { background: #34204d; color: #d9b8ff; } .tag.dim { opacity: .45; }
.tag.adr { background: #ff8a1f; color: #1a0f00; font-weight: 900; }
.ofr { display: flex; align-items: center; gap: 9px; }
.trl { width: 56px; height: 36px; object-fit: cover; border-radius: 4px; background: #12161c; flex: none; }
.trn { font-size: 11px; max-width: 150px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.trlbig { display: flex; gap: 14px; align-items: center; margin-bottom: 8px; }
.trlbig img { width: 180px; height: 101px; object-fit: cover; border-radius: 8px; background: #12161c; border: 1px solid #262d38; }
.trlbig .kicker { font-size: 10.5px; letter-spacing: .14em; text-transform: uppercase; color: #f5a623; font-weight: 800; }
.trlbig b { font-size: 16px; }
.badge { display: inline-block; width: 9px; height: 9px; border-radius: 2px; margin-right: 8px; }
.pay { font-weight: 800; color: #4fd18b; } .pay.dim { color: #6f7a88; }
.panel { background: #161b22; border: 1px solid #222832; border-radius: 4px; padding: 14px 16px; }
.panel.wide { max-width: 980px; }
.panel .btn { margin-top: 10px; }
.cols { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 14px; margin-top: 14px; }
.grid4 { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 10px; margin: 8px 0 14px; }
.kpi { padding: 12px 14px; border-radius: 4px; background: #161b22; border: 1px solid #222832; }
.kpi span { display: block; font-size: 10px; letter-spacing: .1em; text-transform: uppercase; color: #6f7a88; }
.kpi b { font-size: 19px; font-variant-numeric: tabular-nums; }
.kv { display: flex; justify-content: space-between; padding: 5px 0; border-bottom: 1px solid #1d232c; font-size: 13px; }
.t1 { font-weight: 700; font-size: 14.5px; } .t2 { color: #b9c2cd; font-size: 12.5px; margin-top: 2px; }
.instr { margin-top: 8px; font-weight: 700; color: #ffb12e; } .instr.big { font-size: 16px; margin: 12px 0; }
.msg { padding: 8px 0 10px 12px; border-left: 2px solid #252c36; font-size: 13px; margin-bottom: 4px; }
.msg span { display: block; font-size: 11px; color: #5fb4ff; font-weight: 700; margin-bottom: 2px; }
.neg { color: #ff6b5e; } .pos { color: #4fd18b; } .warn { color: #ffb12e; }
.report { margin-bottom: 16px; padding: 14px 16px; border-radius: 4px; border: 1px solid #5a4417; background: #1e1a10; max-width: 640px; }
.report .rh { font-weight: 800; color: #ffb12e; margin-bottom: 8px; }
.report .line { display: flex; justify-content: space-between; font-size: 13.5px; padding: 2px 0; }
.report .sum { border-top: 1px solid #3a3322; margin: 6px 0 10px; padding-top: 6px; font-weight: 800; font-size: 16px; }
.filters { display: inline-flex; gap: 2px; background: #0d1015; border: 1px solid #252c36; border-radius: 4px; padding: 2px; }
.filters.wrap { display: flex; flex-wrap: wrap; margin-bottom: 8px; }
.filters a { padding: 5px 11px; font-size: 12.5px; font-weight: 700; color: #8b95a3; cursor: pointer; border-radius: 3px; }
.filters a.on { background: #ffb12e; color: #15100a; } .filters a.off { opacity: .45; }
.acc { border: 1px solid #222832; border-radius: 4px; margin-bottom: 6px; }
.acchead { display: flex; align-items: center; gap: 8px; padding: 9px 12px; cursor: pointer; } .acchead:hover { background: #161b22; }
.cfg { display: flex; align-items: center; gap: 12px; padding: 6px 12px 6px 26px; font-size: 13px; border-top: 1px solid #1b2129; }
.cfg span:first-child { flex: 1; }
.doc { background: #f3f1ea; color: #1d2026; border-color: #d8d4c8; }
.doc .kv { border-bottom-color: #ddd8cb; } .doc .kv span { color: #5c6170; } .doc .muted { color: #6a6f7c; }
.doc .neg { color: #b3261e; }
.dochead { display: flex; justify-content: space-between; align-items: flex-start; border-bottom: 2px solid #1d3a6e; padding-bottom: 8px; margin-bottom: 8px; }
.dochead .dt { font-size: 10.5px; letter-spacing: .14em; text-transform: uppercase; color: #1d3a6e; font-weight: 800; }
.stamp { border: 2px solid #1d3a6e; color: #1d3a6e; font-weight: 800; font-size: 12px; padding: 3px 8px; border-radius: 3px; transform: rotate(-3deg); }
.doctext { font-size: 13px; line-height: 1.5; margin: 12px 0 8px; }
.legal { border-top: 1px dashed #c9c3b3; margin: 8px 0 10px; padding-top: 8px; font-size: 12.5px; }
/* the route planner */
.routeplan { margin: 8px 0 10px; padding: 8px 10px; border: 1px solid #2a313b; border-radius: 6px; background: rgba(255,255,255,.03); }
.rph { display: flex; align-items: center; gap: 8px; margin-bottom: 4px; } .rph .muted { flex: 1; font-size: 12px; }
.rps { display: flex; align-items: center; gap: 6px; padding: 4px 2px; border-top: 1px solid #1d232c; font-size: 12.5px; }
.rps .rpn { width: 20px; height: 20px; border-radius: 50%; background: #2f3742; display: inline-flex; align-items: center; justify-content: center; font-size: 11px; font-weight: 800; flex: none; }
.rps.act .rpn { background: #f5a623; color: #15100a; } .rps.done { opacity: .5; } .rps.done .rpn { background: #2fbf71; color: #08210f; }
.rps .rpname { flex: 1; min-width: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; } .rps small { color: #8b95a3; }
.rps a { cursor: pointer; color: #8b95a3; padding: 0 4px; } .rps a:hover { color: #f5a623; } .rps a.off { opacity: .25; pointer-events: none; }
/* the evidence: photos pinned to the report, the dashcam as a small player */
.evid { border-top: 1px dashed #c9c3b3; margin: 8px 0 10px; padding-top: 8px; }
.evh { font-size: 11px; font-weight: 800; letter-spacing: .08em; text-transform: uppercase; margin-bottom: 6px; }
.evh .muted { text-transform: none; letter-spacing: 0; font-weight: 600; margin-left: 6px; }
.photos { display: grid; grid-template-columns: repeat(2, 1fr); gap: 8px; }
.photos figure { margin: 0; background: #fff; padding: 5px 5px 3px; box-shadow: 0 2px 6px rgba(0,0,0,.25); transform: rotate(-.6deg); cursor: zoom-in; }
.photos figure:nth-child(2n) { transform: rotate(.7deg); }
.photos img { display: block; width: 100%; aspect-ratio: 16 / 9; object-fit: cover; background: #2a2f36; }
.photos figcaption { font-size: 10.5px; color: #555; padding-top: 3px; }
.photos figure.missing img { visibility: hidden; } .photos figure.missing figcaption::after { content: " – Bild nicht gefunden"; color: #b33; }
.dash { position: relative; background: #000; border-radius: 4px; overflow: hidden; }
.dash img { display: block; width: 100%; aspect-ratio: 16 / 9; object-fit: cover; }
.dash .rec { position: absolute; left: 8px; top: 6px; font: 700 11px Consolas, monospace; color: #fff; text-shadow: 0 1px 2px #000; }
.dash .rec i { display: inline-block; width: 8px; height: 8px; border-radius: 50%; background: #e53935; margin-right: 5px; vertical-align: 0; }
.dash .dctl { display: flex; align-items: center; gap: 8px; padding: 6px 8px; background: #11151a; }
.dash .dctl input { flex: 1; }
.lightbox { position: fixed; inset: 0; z-index: 50; background: rgba(0,0,0,.85); display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 8px; color: #ddd; font-size: 12px; cursor: zoom-out; }
.lightbox img { max-width: 88vw; max-height: 80vh; box-shadow: 0 10px 40px rgba(0,0,0,.6); }
.legal .dt { font-size: 10.5px; letter-spacing: .14em; text-transform: uppercase; color: #1d3a6e; font-weight: 800; margin-bottom: 4px; }
.legal ul { margin: 4px 0 6px 18px; padding: 0; } .legal li { margin: 2px 0; }
.legal .verdict { font-weight: 700; } .legal .verdict.prison { color: #b3261e; }
.cards { display: grid; grid-template-columns: repeat(auto-fill, minmax(250px, 1fr)); gap: 12px; }
.vcard { background: #161b22; border: 1px solid #222832; border-radius: 6px; overflow: hidden; display: flex; flex-direction: column; }
.vcard:hover { border-color: #3a4554; }
.vcard .pic { position: relative; height: 140px; background: linear-gradient(180deg, #1d232c, #12161c); display: flex; align-items: center; justify-content: center; }
.vcard .pic img { max-width: 100%; max-height: 100%; object-fit: contain; }
.vcard .pic .tag { position: absolute; top: 8px; left: 8px; margin: 0; } .vcard .pic .tag.used { left: auto; right: 8px; background: #3a2a0c; color: #ffcf7a; }
.vcard .vb { padding: 10px 12px 12px; display: flex; flex-direction: column; gap: 4px; flex: 1; }
.vcard .vb b { font-size: 14px; }
.vcard .specs { display: flex; gap: 6px; flex-wrap: wrap; font-size: 11.5px; color: #b9c2cd; }
.vcard .specs span { background: #1f252e; border-radius: 3px; padding: 1px 6px; }
.vcard .vfoot { margin-top: auto; padding-top: 8px; display: flex; align-items: center; gap: 8px; }
.vcard .vfoot .btn { margin-left: auto; }
.thumb { width: 64px; height: 40px; object-fit: contain; border-radius: 3px; background: #12161c; flex: none; }
.setting { display: flex; align-items: center; justify-content: space-between; gap: 20px; padding: 14px 0; border-bottom: 1px solid #1d232c; }
.seg { display: inline-flex; flex-wrap: wrap; border: 1px solid #2c3440; border-radius: 4px; overflow: hidden; max-width: 60%; }
.seg a { padding: 7px 14px; font-size: 12.5px; font-weight: 700; color: #8b95a3; cursor: pointer; }
.seg a.on { background: #ffb12e; color: #15100a; }
.chips { display: flex; flex-wrap: wrap; gap: 4px; max-width: 60%; justify-content: flex-end; }
.input { padding: 7px 10px; font-size: 13px; color: #e9edf2; background: #0d1015; border: 1px solid #2c3440; border-radius: 4px; outline: none; width: 260px; }
.btn { padding: 7px 14px; font-size: 13px; font-weight: 700; color: #e9edf2; background: #1f252e; border: 1px solid #2f3742; border-radius: 4px; cursor: pointer; white-space: nowrap; }
.btn:hover { background: #28303b; }
.btn.primary { background: #ffb12e; border-color: #ffb12e; color: #15100a; } .btn.primary:hover { filter: brightness(1.07); }
.btn.ghost { background: transparent; } .btn.danger { border-color: #7a2b25; color: #ff8a80; }
.btn:disabled { opacity: .4; pointer-events: none; }
/* the Zentrale */
.hub { animation: hubIn .3s ease-out; }
@keyframes hubIn { from { opacity: 0; transform: translateY(8px); } to { opacity: 1; transform: none; } }
.hub .hello { display: flex; align-items: flex-end; justify-content: space-between; gap: 16px; margin-bottom: 14px; }
.hub .hello .day { display: block; font-size: 11px; letter-spacing: .16em; text-transform: uppercase; color: #f5a623; font-weight: 800; }
.hub .hello b { font-size: 22px; font-weight: 900; }
.hub .hello .hint { font-size: 12.5px; color: #8b95a3; } .hub .hello .hint b { font-size: 12.5px; color: #e9edf2; font-weight: 700; }
.tiles { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 10px; }
.tile { position: relative; display: block; min-height: 96px; padding: 12px 14px 12px 16px; background: #141920; border: 1px solid #232a34; border-radius: 8px;
  cursor: pointer; overflow: hidden; transition: border-color .12s, transform .12s, background .12s; }
.tile::before { content: ""; position: absolute; left: 0; top: 0; bottom: 0; width: 3px; background: var(--ac); }
.tile:hover { border-color: var(--ac); background: #19202a; transform: translateY(-2px); }
.tile.wide { grid-column: span 2; }
.tile.alert { border-color: #7a2b25; } .tile.alert .tv { color: #ff8a80; }
.tile.info { cursor: default; } .tile.info:hover { transform: none; border-color: #232a34; background: #141920; }
/* the cleaner frame: icons in the side bar, a line under the page title */
.nav .ni { width: 20px; text-align: center; font-size: 14px; flex: none; filter: saturate(.85); }
.nav.on .ni { filter: none; }
.tsub { font-size: 12px; color: #6f7a88; margin-top: 2px; }
/* the job under way on the Aufträge page */
.jobcard { background: linear-gradient(180deg, #17221b, #141a20); border: 1px solid #24402e; border-radius: 8px; padding: 12px 14px; margin-bottom: 14px; }
.jobcard .jh { display: flex; align-items: center; gap: 8px; }
.jobcard .kick { font-size: 10.5px; font-weight: 800; letter-spacing: .14em; text-transform: uppercase; color: #3ad38b; }
.jobcard .jh b { font-size: 16px; }
.jobcard .jt { font-size: 17px; font-weight: 800; margin-top: 4px; } .jobcard .jr { font-size: 12.5px; color: #8b95a3; }
.jobcard .instr { margin-top: 8px; }
.jobcard .jk { display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: 8px; margin-top: 10px; }
.jobcard .jk div { background: rgba(0,0,0,.18); border-radius: 5px; padding: 6px 9px; }
.jobcard .jk span { display: block; font-size: 10px; letter-spacing: .08em; text-transform: uppercase; color: #6f7a88; }
.jobcard .jk b { font-size: 14px; font-variant-numeric: tabular-nums; }
.jobcard .row { margin-top: 10px; display: flex; gap: 8px; align-items: center; }
/* finances */
.fin .fk { display: grid; grid-template-columns: 1.4fr 1fr 1fr 1fr; gap: 10px; margin-bottom: 12px; }
.fin .kpi.big b { font-size: 26px; } .fin .kpi small { display: block; font-size: 11.5px; color: #8b95a3; margin-top: 2px; }
.fgrid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; }
.fgrid.two { margin-top: 12px; }
.fin .panel { border-radius: 8px; }
.fin h3 span { letter-spacing: 0; text-transform: none; font-weight: 600; color: #5b6470; margin-left: 6px; }
.chart svg { width: 100%; height: 170px; display: block; }
.chart .grid { stroke: #222832; stroke-width: 1; } .chart .zero { stroke: #3a434f; stroke-width: 1; stroke-dasharray: 4 4; }
.chart .stroke { fill: none; stroke: #ffb12e; stroke-width: 2.4; vector-effect: non-scaling-stroke; stroke-linejoin: round; }
.chart .dot { fill: #ffb12e; stroke: #12161c; stroke-width: 2; }
.chart .in { fill: #3ad38b; } .chart .out { fill: #ff6b5e; opacity: .85; }
.chart .axis { display: flex; justify-content: space-between; font-size: 11px; color: #6f7a88; margin-top: 4px; font-variant-numeric: tabular-nums; }
.chart .axis.days span { flex: 1; text-align: center; }
.empty { color: #6f7a88; font-size: 12.5px; padding: 18px 0; text-align: center; }
.cat { display: grid; grid-template-columns: 150px 1fr 90px 40px; align-items: center; gap: 10px; padding: 5px 0; font-size: 12.5px; }
.cat .cn { display: flex; align-items: center; gap: 7px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.cat .cn i { width: 8px; height: 8px; border-radius: 2px; flex: none; }
.cat .cb { height: 7px; background: #1b2129; border-radius: 4px; overflow: hidden; } .cat .cb i { display: block; height: 100%; border-radius: 4px; }
.cat .cv { text-align: right; font-variant-numeric: tabular-nums; } .cat .cp { text-align: right; color: #6f7a88; }
.loanbar { height: 6px; background: #1b2129; border-radius: 3px; overflow: hidden; margin: 8px 0; } .loanbar i { display: block; height: 100%; background: #ff8a5e; }
.book { display: flex; align-items: center; gap: 10px; padding: 6px 0; border-bottom: 1px solid #1b2129; font-size: 12.5px; }
.book:last-child { border-bottom: 0; }
.book .bt { width: 70px; color: #6f7a88; font-variant-numeric: tabular-nums; flex: none; }
.book .chip { flex: none; font-size: 10.5px; font-weight: 700; border: 1px solid; border-radius: 10px; padding: 0 8px; }
.book .bl { flex: 1; min-width: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; color: #cfd6de; }
.book b { flex: none; font-variant-numeric: tabular-nums; }
.book .bb { flex: none; width: 90px; text-align: right; color: #6f7a88; font-variant-numeric: tabular-nums; }
.dstars i { font-style: normal; color: #2d343e; font-size: 13px; } .dstars i.on { color: #ffc23d; }
.career-stats { display: flex; flex-wrap: wrap; gap: 6px 18px; margin: -4px 0 12px; font-size: 12px; color: #8b95a3; }
.career-stats b { color: #e9edf2; font-weight: 800; }
.tile .th { display: flex; align-items: center; gap: 7px; font-size: 10.5px; font-weight: 800; letter-spacing: .1em; text-transform: uppercase; color: #9aa4b2; }
.tile .ti { font-size: 15px; letter-spacing: 0; }
.tile .tb { margin-left: auto; letter-spacing: 0; text-transform: none; font-size: 10px; background: var(--ac); color: #15100a; border-radius: 3px; padding: 1px 6px; }
.tile .tv { margin-top: 8px; font-size: 17px; font-weight: 800; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.tile .ts { margin-top: 3px; font-size: 12px; color: #8b95a3; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
.tile .tbar { position: absolute; left: 16px; right: 14px; bottom: 9px; height: 3px; background: rgba(255,255,255,.08); border-radius: 2px; overflow: hidden; }
.tile .tbar i { display: block; height: 100%; background: var(--ac); }
/* (2026-11-08) glass over the softened game world (career.lua L.menuBlurTick), one easing for everything */
.ffo { background: rgba(6, 9, 14, .34); animation: ffoFade .4s cubic-bezier(.16, 1, .3, 1); transition: background .22s ease, opacity .22s ease; }
@keyframes ffoFade { from { background: rgba(6, 9, 14, 0); } }
.frame { background: rgba(16, 20, 27, .82); border-color: rgba(255, 255, 255, .09); border-radius: 18px; box-shadow: 0 40px 120px rgba(0, 0, 0, .55), inset 0 1px 0 rgba(255, 255, 255, .05);
  animation: ffoRise .52s cubic-bezier(.16, 1, .3, 1); transition: transform .22s cubic-bezier(.4, 0, 1, 1), opacity .22s ease; will-change: transform, opacity; }
@keyframes ffoRise { from { opacity: 0; transform: translateY(26px) scale(.965); } }
aside { background: rgba(9, 12, 17, .55); border-right-color: rgba(255, 255, 255, .06); }
.ffo.closing { background: rgba(6, 9, 14, 0); }
.ffo.closing .frame { opacity: 0; transform: translateY(14px) scale(.98); }
.tabIn { animation: ffoTab .42s cubic-bezier(.16, 1, .3, 1); }
@keyframes ffoTab { from { opacity: 0; transform: translateY(10px); } }
.nav { transition: background .2s ease, color .2s ease, border-color .25s ease, padding-left .25s cubic-bezier(.16, 1, .3, 1); }
.nav:hover { padding-left: 20px; }
.nav.on { background: rgba(255, 177, 46, .1); }
.btn { transition: background .18s ease, border-color .18s ease, color .18s ease, transform .12s cubic-bezier(.16, 1, .3, 1), box-shadow .18s ease; }
.btn:hover:not(:disabled) { transform: translateY(-1px); box-shadow: 0 6px 16px rgba(0, 0, 0, .3); }
.btn:active:not(:disabled) { transform: translateY(0) scale(.98); }
.tbl tbody tr { transition: background .18s ease; }
.tbl tbody tr { animation: ffoRow .4s cubic-bezier(.16, 1, .3, 1) both; }
.tbl tbody tr:nth-child(2) { animation-delay: .03s; } .tbl tbody tr:nth-child(3) { animation-delay: .06s; } .tbl tbody tr:nth-child(4) { animation-delay: .09s; }
.tbl tbody tr:nth-child(5) { animation-delay: .12s; } .tbl tbody tr:nth-child(6) { animation-delay: .15s; } .tbl tbody tr:nth-child(7) { animation-delay: .18s; }
.tbl tbody tr:nth-child(n+8) { animation-delay: .2s; }
@keyframes ffoRow { from { opacity: 0; transform: translateY(6px); } }
.ycard { transition: border-color .2s ease, transform .2s cubic-bezier(.16, 1, .3, 1), box-shadow .2s ease; }
.ycard:hover { transform: translateY(-2px); box-shadow: 0 10px 24px rgba(0, 0, 0, .3); }
.setting { transition: background .2s ease; }
@media (prefers-reduced-motion: reduce) { .frame, .tabIn, .tbl tbody tr { animation: none; } }
</style>
