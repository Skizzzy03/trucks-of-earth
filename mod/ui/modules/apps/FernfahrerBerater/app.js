// Trucks of Earth HUD: the route advisor (as in the classic truck simulators). Top: speed (vehicle electrics stream), the
// road's speed limit sign, the game clock, fuel, condition. The next step of the job. Tabs: map (BeamNG.Earth's map
// tiles with the route, the player and the OpenStreetMap places around), route, job, vehicle. Bottom: the actions for
// where you are. Data: career.lua pushes 'FernfahrerHud'; map tiles come from beamngEarth_settings.mapTiles.
angular.module('beamng.apps')
.directive('fernfahrerBerater', [function () {
  // map marker per place type: letter and colour (a legend reads them off the same table)
  var MARK = {
    fuel: ['T', '#f5a623'], rest: ['R', '#7ac943'], workshop: ['W', '#ff7a45'], truckdealer: ['H', '#3d8bfd'],
    cardealer: ['A', '#3d8bfd'], viewpoint: ['S', '#a66bff'], logistics: ['L', '#8d99a6'], post: ['P', '#e8c63c'],
    supermarket: ['K', '#2fbf71'], hardware: ['K', '#2fbf71'], furniture: ['K', '#2fbf71'], industry: ['G', '#8d99a6'],
    drinks: ['K', '#2fbf71'], dairy: ['K', '#2fbf71'], timber: ['K', '#2fbf71'], building: ['K', '#2fbf71'],
    farm: ['K', '#2fbf71'], port: ['L', '#8d99a6'], ferry: ['F', '#1aa3c9'], airport: ['✈', '#1aa3c9']
  }
  var css =
    '.ffb{font-family:inherit;color:#e9edf2}' +
    '.ffb .c{height:100%;box-sizing:border-box;display:flex;flex-direction:column;background:rgba(15,18,23,.92);border:1px solid #2a313b;border-radius:6px;overflow:hidden;box-shadow:0 8px 28px rgba(0,0,0,.45)}' +
    '.ffb .top{display:flex;align-items:center;gap:12px;padding:7px 12px;border-bottom:1px solid #222832}' +
    '.ffb .sign{flex:none;width:48px;height:48px;border-radius:50%;background:#fff;border:6px solid #d3201f;box-sizing:border-box;display:flex;align-items:center;justify-content:center;color:#111;font:800 18px Arial,Helvetica,sans-serif;letter-spacing:-1px}' +
    '.ffb .sign.none{border-color:#5b6470;background:#d9dde2;color:#5b6470;font-size:15px}.ffb .sign.zone{box-shadow:0 0 0 3px #f5a623}' +
    '.ffb .spd{line-height:1}.ffb .spd b{font-size:34px;font-weight:800;font-variant-numeric:tabular-nums}.ffb .spd span{font-size:10px;color:#8b95a3;letter-spacing:1px;margin-left:3px}' +
    '.ffb .spd.over b{color:#ff6b5e;animation:ffbBlink .8s steps(2) infinite}@keyframes ffbBlink{50%{opacity:.35}}' +
    '.ffb .clk{font-size:15px;font-weight:700;color:#cfd6de;font-variant-numeric:tabular-nums;padding:2px 7px;border:1px solid #2a313b;border-radius:4px}.ffb .clk.n{color:#9fb8ff}' +
    '.ffb .gauges{margin-left:auto;display:flex;flex-direction:column;gap:5px;width:132px}' +
    '.ffb .g{font-size:10px;color:#8b95a3;display:flex;justify-content:space-between;text-transform:uppercase;letter-spacing:.06em}.ffb .g b{color:#e9edf2;font-size:11px;text-transform:none;letter-spacing:0}' +
    '.ffb .bar{height:4px;background:#252c36;border-radius:2px;overflow:hidden}.ffb .bar i{display:block;height:100%}' +
    '.ffb .step{padding:6px 12px;font-size:12.5px;font-weight:700;color:#15100a;background:#f5a623}' +
    '.ffb .step.ok{background:#2fbf71;color:#08210f}.ffb .step.bad{background:#d9483b;color:#fff}' +
    '.ffb .hitch{padding:6px 12px 7px;background:#16282a;border-top:1px solid #234044}.ffb .hitch .hl{display:flex;align-items:baseline;gap:6px;font-size:12.5px;font-weight:700;color:#e8f4f2}' +
    '.ffb .hitch .hl small{margin-left:auto;font-size:11.5px;font-weight:600;color:#8fc9c0}.ffb .hitch.ask .hl small{color:#ffcf5e}.ffb .hitch .bar{margin-top:5px}' +
    '.ffb .tabs{display:flex;background:#0d1015;border-bottom:1px solid #222832}' +
    '.ffb .tabs a{flex:1;text-align:center;padding:6px 2px;font-size:11px;font-weight:700;color:#8b95a3;cursor:pointer;border-bottom:2px solid transparent;text-transform:uppercase;letter-spacing:.06em}' +
    '.ffb .tabs a.on{color:#fff;border-bottom-color:#f5a623}' +
    '.ffb .body{flex:1;min-height:0;padding:8px 12px;overflow:hidden;position:relative}' +
    '.ffb .body.map{padding:0}' +
    '.ffb .mapbox{position:absolute;inset:0;overflow:hidden;background:#c9d0cb}' +
    '.ffb .tile{position:absolute;width:256px;height:256px}.ffb .tile.ov{z-index:1}' +
    '.ffb .mapbox.dark{background:#1b1f24}.ffb .mapbox.dark .tile{filter:invert(.92) hue-rotate(180deg) brightness(.82) contrast(.92) saturate(.6)}' +
    '.ffb svg.rt{position:absolute;left:0;top:0;z-index:2;overflow:visible}' +
    '.ffb .mk{position:absolute;z-index:3;transform:translate(-50%,-50%);width:15px;height:15px;border-radius:50%;border:1.5px solid #fff;color:#fff;font:800 9px/12px Arial,sans-serif;text-align:center;box-shadow:0 1px 3px rgba(0,0,0,.5)}' +
    '.ffb .mk.tg{width:18px;height:18px;line-height:15px;font-size:11px;background:#d9483b;z-index:4;border-radius:3px}.ffb .mk.hm{background:#15100a;color:#f5a623;border-color:#f5a623;border-radius:3px}' +
    '.ffb .me{position:absolute;z-index:5;left:50%;top:50%;width:0;height:0;margin-left:-8px;margin-top:-11px;border-left:8px solid transparent;border-right:8px solid transparent;border-bottom:22px solid #1f6feb;filter:drop-shadow(0 0 2px #fff)}' +
    '.ffb .mapctl{position:absolute;right:6px;top:6px;z-index:6;display:flex;flex-direction:column;gap:3px}' +
    '.ffb .mapctl a{width:22px;height:22px;line-height:22px;text-align:center;background:rgba(15,18,23,.88);border-radius:3px;cursor:pointer;font-weight:800}' +
    '.ffb .mapctl a.on{background:#f5a623;color:#15100a}.ffb .mapctl a.sm{font-size:10px}' +
    // (heading-up / tilted: the map layer turns and tips around the player)
    '.ffb .mapview{position:absolute;left:0;top:0;width:100%;height:100%;transition:transform .35s linear;will-change:transform}' +
    // where the truck is (2026-11-08): the country's letters, the town, the state
    '.ffb .loc{position:absolute;left:6px;top:6px;z-index:6;display:flex;align-items:center;gap:6px;max-width:calc(100% - 42px);box-sizing:border-box;height:22px;padding:0 10px 0 3px;border-radius:11px;background:rgba(15,18,23,.88);font-size:11px;font-weight:700;color:#e9edf2;white-space:nowrap;box-shadow:0 1px 4px rgba(0,0,0,.35)}' +
    '.ffb .loc .fl{flex:none;width:24px;height:16px;border-radius:2px;box-shadow:0 0 0 1px rgba(255,255,255,.35);background-color:#555}' +
    '.ffb .loc .cn{font-size:12px;font-weight:800;flex:none}' +
    '.ffb .loc .st{color:#aeb7c3;font-weight:500;overflow:hidden;text-overflow:ellipsis}' +
    '.ffb .legend{position:absolute;left:6px;top:32px;z-index:6;background:rgba(15,18,23,.85);border-radius:3px;padding:3px 6px;font-size:10px;color:#cfd6de;line-height:1.5}' +
    '.ffb .legend i{display:inline-block;width:8px;height:8px;border-radius:50%;margin:0 3px 0 6px}.ffb .legend i:first-child{margin-left:0}' +
    '.ffb .mapinfo{position:absolute;left:6px;bottom:6px;z-index:6;background:rgba(15,18,23,.88);border-radius:3px;padding:3px 8px;font-size:11px}' +
    '.ffb .t1{font-weight:700;font-size:13.5px;display:flex;gap:6px;align-items:center;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}' +
    '.ffb .t2{font-size:11.5px;color:#8b95a3;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:1px}' +
    '.ffb .kv{display:flex;gap:14px;margin-top:6px}.ffb .kv div span{display:block;font-size:9.5px;color:#8b95a3;text-transform:uppercase;letter-spacing:.06em}.ffb .kv div b{font-size:15px;font-variant-numeric:tabular-nums}' +
    '.ffb .late{color:#ff6b5e}.ffb .hit{animation:ffbHit .5s ease-in-out 3}@keyframes ffbHit{50%{background:rgba(217,72,59,.3)}}' +
    '.ffb .tag{font-size:9.5px;font-weight:700;border-radius:3px;padding:1px 5px;background:#252c36;color:#b9c2cd}.ffb .tag.frag{background:#34204d;color:#d9b8ff}' +
    '.ffb .near{padding:4px 12px;font-size:11.5px;background:#15241b;color:#bfe8cd;border-top:1px solid #1f3a29}' +
    '.ffb .acts{display:flex;gap:5px;padding:6px 10px;flex-wrap:wrap;border-top:1px solid #222832}' +
    '.ffb .btn{background:#1f252e;border:1px solid #2f3742;color:#e9edf2;border-radius:4px;padding:4px 9px;font-size:11.5px;font-weight:700;cursor:pointer;white-space:nowrap}' +
    '.ffb .btn:hover{background:#28303b}.ffb .btn.pri{background:#f5a623;color:#15100a;border-color:#f5a623}.ffb .btn.go{background:#2fbf71;color:#08210f;border-color:#2fbf71}' +
    '.ffb .mut{color:#8b95a3;font-size:11px}' +
    '.ffb .navcue{display:flex;align-items:center;gap:10px;padding:5px 12px;background:#123a5c;border-bottom:1px solid #1d4f7a}' +
    '.ffb .navcue .arr{font:900 26px/1 Arial,sans-serif;color:#fff;width:28px;text-align:center}' +
    '.ffb .navcue b{font-size:16px;font-variant-numeric:tabular-nums;min-width:56px}.ffb .navcue .nt{font-size:12.5px;font-weight:700;color:#cfe6ff}' +
    // the route warner (2026-11-05): the sign of what is ahead beside the speed, its distance under it
    '.ffb .warn{flex:none;display:flex;flex-direction:column;align-items:center;gap:2px;animation:ffbWarnIn .4s cubic-bezier(.2,.8,.2,1)}' +
    '@keyframes ffbWarnIn{from{opacity:0;transform:scale(.6)}}' +
    '.ffb .warn small{font:700 10px/1 inherit;color:#cfd6de;font-variant-numeric:tabular-nums}' +
    '.ffb .wtri{position:relative;width:40px;height:35px}.ffb .wtri:before{content:"";position:absolute;inset:0;background:#d3201f;clip-path:polygon(50% 0,100% 100%,0 100%)}' +
    '.ffb .wtri:after{content:"";position:absolute;left:6px;right:6px;top:9px;bottom:3px;background:#fff;clip-path:polygon(50% 0,100% 100%,0 100%)}' +
    '.ffb .wtri i{position:absolute;left:0;right:0;bottom:4px;z-index:1;text-align:center;font:900 13px/1 Arial,sans-serif;color:#111;font-style:normal}' +
    '.ffb .wcam{width:36px;height:36px;border-radius:5px;background:#1d5fc8;border:2px solid #fff;box-sizing:border-box;display:flex;align-items:center;justify-content:center;font-size:17px}' +
    '.ffb .mapctl a.off{opacity:.55}'
  return {
    template:
      '<div class="bngApp ffb" ng-show="h.mode" style="width:100%;height:100%;background:transparent;box-shadow:none;">' +
      '<style>' + css + '</style>' +
      '<div class="c">' +
        '<div class="top">' +
          '<div class="sign" ng-class="{none: !h.limit, zone: h.event && h.event.inZone}">{{ h.limit || \'–\' }}</div>' +
          '<div class="spd" ng-class="{over: over()}"><b>{{ speed() }}</b><span>KM/H</span></div>' +
          '<div class="clk" ng-class="{n: h.night}" ng-if="h.clock">{{ h.clock }}</div>' +
          '<div class="warn" ng-if="warnOn()" title="{{ h.event.title }}">' +
            '<div class="wcam" ng-if="h.event.kind === \'radar\' || h.event.kind === \'laser\'">📷</div>' +
            '<div class="wtri" ng-if="h.event.kind !== \'radar\' && h.event.kind !== \'laser\'"><i>{{ h.event.kind === \'roadworks\' ? \'🚧\' : \'!\' }}</i></div>' +
            '<small>{{ h.event.inZone ? \'jetzt\' : dist(h.event.dist) }}</small></div>' +
          '<div class="gauges">' +
            '<div><div class="g"><span>{{ fuelName() }}</span><b>{{ fuelText() }}</b></div><div class="bar"><i ng-style="{width: (fuelRatio()*100)+\'%\', background: fuelRatio() < .12 ? \'#d9483b\' : \'#f5a623\'}"></i></div></div>' +
            '<div><div class="g"><span>Zustand</span><b>{{ pct(1 - (h.damage||0)) }}</b></div><div class="bar"><i ng-style="{width: ((1-(h.damage||0))*100)+\'%\', background: (h.damage||0) > .3 ? \'#d9483b\' : \'#2fbf71\'}"></i></div></div>' +
          '</div>' +
        '</div>' +
        '<div class="step" ng-if="h.job" ng-class="{ok: h.job.phase === \'unloading\' || h.job.phase === \'atDelivery\', bad: h.job.routeError || h.job.phase === \'needTrailer\'}">' +
          '{{ h.job.text }}<span ng-if="h.job.trailerDist !== undefined"> · {{ dist(h.job.trailerDist) }}</span>' +
          '<span ng-if="h.job.spotDist !== undefined && h.job.phase === \'toDelivery\' && h.job.spotDist < 200"> · Fläche {{ dist(h.job.spotDist) }}</span></div>' +
        '<div class="hitch" ng-if="h.hitch" ng-class="{ask: h.hitch.ask}"><div class="hl">🎒 {{ h.hitch.name }} fährt mit' +
          '<small>{{ h.hitch.ask ? \'will raus – kurz anhalten\' : (\'steigt in ca. \' + (h.hitch.left < 1 ? \'1\' : (h.hitch.left | number:0)) + \' km aus\') }}</small></div>' +
          '<div class="bar"><i ng-style="{width: (h.hitch.pct*100)+\'%\', background: h.hitch.ask ? \'#ffb12e\' : \'#3fc1b0\'}"></i></div></div>' +
        '<div class="navcue" ng-if="h.nav && h.nav.dir && h.nav.dist < 900"><span class="arr">{{ arrow(h.nav.dir) }}</span>' +
          '<b>{{ h.nav.dir === \'end\' ? \'\' : dist(h.nav.dist) }}</b><span class="nt">{{ cueText(h.nav) }}</span></div>' +
        '<div class="tabs"><a ng-class="{on: tab===\'map\'}" ng-click="tab=\'map\'">Karte</a><a ng-class="{on: tab===\'route\'}" ng-click="tab=\'route\'">Route</a><a ng-class="{on: tab===\'job\'}" ng-click="tab=\'job\'">Auftrag</a><a ng-class="{on: tab===\'veh\'}" ng-click="tab=\'veh\'">Fahrzeug</a></div>' +
        '<div class="body" ng-class="{map: tab===\'map\'}">' +
          '<div class="mapbox" ng-show="tab===\'map\'" ng-class="{dark: isDark()}">' +
            '<div class="mapview" ng-style="viewStyle()">' +
            '<img ng-repeat="t in m.tiles track by t.k" class="tile" ng-class="{ov: t.ov}" ng-src="{{ t.src }}" ng-style="{left: t.x + \'px\', top: t.y + \'px\'}" />' +
            '<svg class="rt" ng-attr-width="{{ m.w }}" ng-attr-height="{{ m.h }}"><polyline ng-attr-points="{{ m.route }}" fill="none" stroke="#1f6feb" stroke-width="5" stroke-opacity=".8" stroke-linejoin="round" stroke-linecap="round"/></svg>' +
            '<div ng-repeat="p in m.places track by $index" class="mk" ng-style="{left: p.x + \'px\', top: p.y + \'px\', background: p.c, transform: mkT()}" title="{{ p.n }}">{{ p.l }}</div>' +
            '<div class="mk hm" ng-if="m.home" ng-style="{left: m.home.x + \'px\', top: m.home.y + \'px\', transform: mkT()}">H</div>' +
            '<div class="mk tg" ng-if="m.target" ng-style="{left: m.target.x + \'px\', top: m.target.y + \'px\', transform: mkT()}">Z</div>' +
            '</div>' +
            '<div class="me" ng-style="meStyle()"></div>' +
            '<div class="loc" ng-if="h.where" title="{{ h.where.state ? h.where.state + \', \' : \'\' }}{{ h.where.country }}"><span class="fl" ng-style="flag(h.where.code)"></span><span class="cn">{{ h.where.country }}</span><span class="st" ng-if="h.where.state || h.where.town || h.where.street">{{ [h.where.state, h.where.town, h.where.street].filter(ok).join(\' · \') }}</span></div>' +
            '<div class="legend" ng-if="showLegend"><i style="background:#ff8f1f"></i>Fracht<i style="background:#f5a623"></i>Tank<i style="background:#7ac943"></i>Rast<i style="background:#ff7a45"></i>Werkstatt<i style="background:#3d8bfd"></i>Händler<i style="background:#2fbf71"></i>Kunde</div>' +
            '<div class="mapctl"><a ng-click="zoom(1)">+</a><a ng-click="zoom(-1)">−</a><a ng-click="showLegend = !showLegend">?</a>' +
              '<a ng-click="toggleSound()" title="Navi-Ansagen an/aus" ng-class="{off: !h.navSound}">{{ h.navSound ? \'🔊\' : \'🔇\' }}</a>' +
              '<a ng-click="toggleWarn()" ng-class="{on: h.routeWarn}" title="{{ h.routeWarn ? \'Streckenwarner an (Blitzer, Baustellen, Pannen) – klicken: aus\' : \'Streckenwarner aus – klicken: Blitzer, Baustellen und Pannen werden mit Signalton angezeigt\' }}">⚠</a>' +
              '<a ng-click="toggleFollow()" ng-class="{on: m.follow}" title="{{ m.follow ? \'Karte dreht mit der Fahrtrichtung – klicken: Norden oben\' : \'Norden oben – klicken: Karte dreht mit der Fahrtrichtung\' }}">🧭</a>' +
              '<a class="sm" ng-click="toggleTilt()" ng-class="{on: m.tilt}" title="Schräge Ansicht nach vorn an/aus">3D</a>' +
              '<a ng-click="toggleNight()" ng-class="{on: m.night !== \'auto\'}" title="{{ nightTip() }}">{{ m.night === \'on\' ? \'🌙\' : (m.night === \'off\' ? \'☀\' : \'◐\') }}</a></div>' +
            '<div class="mapinfo" ng-if="h.nextFuel">Tankstelle: {{ h.nextFuel.name }} · {{ dist(h.nextFuel.dist) }}</div>' +
          '</div>' +
          '<div ng-if="tab===\'route\'">' +
            '<div class="t1">{{ h.navName || (h.job ? h.job.target : \'Kein Ziel\') }}</div>' +
            '<div class="t2" ng-if="h.discovering">Firmen in der Umgebung werden geladen … {{ h.discovering.done }}/{{ h.discovering.total }}</div>' +
            '<div class="t2" ng-if="!h.discovering && !h.job && !h.navName">Auftrag im Büro wählen oder ein Ziel setzen.</div>' +
            '<div class="t2" ng-if="h.event" style="color:#f5a623">{{ h.event.title }}{{ h.event.inZone ? \' – du bist drin\' : \' in \' + dist(h.event.dist) }}{{ h.event.limit ? \' · \' + h.event.limit + \' km/h\' : \'\' }}</div>' +
            '<div class="t2" ng-if="h.gps && h.gps.routeError" style="color:#ff6b5e">Keine Route gefunden</div>' +
            '<div class="kv">' +
              '<div><span>Entfernung</span><b>{{ dist(h.gps && h.gps.remaining !== undefined ? h.gps.remaining : (h.job ? h.job.dist : null)) }}</b></div>' +
              '<div><span>Ankunft in</span><b>{{ time(h.gps && h.gps.eta !== undefined ? h.gps.eta : (h.job ? h.job.eta : null)) }}</b></div>' +
              '<div ng-if="h.job"><span>Frist</span><b ng-class="{late: h.job.timeLeft < 0}">{{ time(h.job.timeLeft) }}</b></div>' +
              '<div ng-if="!h.job && h.homeDist !== undefined && h.homeDist !== null"><span>Hof</span><b>{{ dist(h.homeDist) }}</b></div>' +
            '</div>' +
            '<div style="margin-top:8px;display:flex;gap:5px;flex-wrap:wrap">' +
              '<button class="btn" ng-click="lua(\'navToNearest\', \'fuel\')">Tankstelle</button>' +
              '<button class="btn" ng-click="lua(\'navToNearest\', \'rest\')">Rastplatz</button>' +
              '<button class="btn" ng-click="lua(\'navToNearest\', \'parking\')">Parkplatz</button>' +
              '<button class="btn" ng-click="lua(\'navToNearest\', \'workshop\')">Werkstatt</button>' +
              '<button class="btn" ng-click="lua(\'navToHome\')">Hof</button>' +
              '<button class="btn" ng-if="h.job && h.job.needSecure" ng-click="lua(\'secureLoad\')" style="background:#ffb12e;color:#15100a">Ladung sichern</button>' +
              '<button class="btn" ng-if="h.job && h.job.papersHere" ng-click="lua(\'packPapers\')" style="background:#ffb12e;color:#15100a">ADR-Papiere einpacken</button>' +
              '<button class="btn" ng-if="h.job" ng-click="lua(\'navToJob\')">Auftrag</button>' +
            '</div>' +
          '</div>' +
          '<div ng-if="tab===\'job\'" ng-class="{hit: h.job && h.job.hit}">' +
            '<div ng-if="!h.job" class="t2">Kein Auftrag – Frachtbörse im Büro (Strg+Umschalt+F).</div>' +
            '<div ng-if="h.job">' +
              '<div class="t1">{{ h.job.cargoName }} <span class="tag">{{ h.job.tons }} t</span><span class="tag frag" ng-if="h.job.fragile">zerbrechlich</span><span style="margin-left:auto;color:#2fbf71">{{ money(h.job.pay) }}</span></div>' +
              '<div class="t2">{{ h.job.from }} → {{ h.job.to }}</div>' +
              '<div class="kv"><div><span>Ladung</span><b ng-style="{color: h.job.cond > .8 ? \'#2fbf71\' : (h.job.cond > .5 ? \'#f5a623\' : \'#ff6b5e\')}">{{ h.job.hasTrailer ? pct(h.job.cond) : \'–\' }}</b></div>' +
              '<div><span>Frist</span><b ng-class="{late: h.job.timeLeft < 0}">{{ time(h.job.timeLeft) }}</b></div>' +
              '<div><span>Ziel</span><b>{{ dist(h.job.dist) }}</b></div>' +
              '<div><span>Auflieger</span><b>{{ h.job.hasTrailer ? (h.job.coupled ? \'gekuppelt\' : \'frei\') : \'–\' }}</b></div></div>' +
              '<div class="bar" style="margin-top:6px" ng-if="h.job.unload !== undefined && h.job.unload !== null"><i ng-style="{width: (h.job.unload*100)+\'%\', background:\'#2fbf71\'}"></i></div>' +
            '</div>' +
          '</div>' +
          '<div ng-if="tab===\'veh\'">' +
            '<div class="t1">{{ h.vehicleName }} <span class="tag" ng-if="h.loaner">Leih-LKW</span></div>' +
            '<div class="kv">' +
              '<div><span>Tank</span><b>{{ fuelText() }}</b></div>' +
              '<div><span>Reichweite</span><b>{{ h.range ? dist(h.range) : \'–\' }}</b></div>' +
              '<div><span>Verbrauch</span><b>{{ h.fuel && h.fuel.per100 ? (h.fuel.per100.toFixed(0) + \' L/100\') : \'–\' }}</b></div>' +
            '</div>' +
            '<div class="t2" style="margin-top:6px" ng-if="h.tacho">Lenkzeit bis Pause {{ h.tacho.driveText }} · heute noch {{ h.tacho.dayText }}</div>' +
            '<button class="btn" style="margin-top:6px" ng-if="speed() < 3 && !h.service" ng-click="lua(\'roadside\')">Pannendienst rufen</button>' +
          '</div>' +
        '</div>' +
        // (2026-11-08) a breakdown, and the breakdown service on its way
        '<div ng-if="h.breakdown" style="margin-top:6px;padding:7px 9px;border-radius:6px;background:rgba(120,30,24,.55);border:1px solid rgba(255,107,94,.5);display:flex;align-items:center;gap:8px">' +
          '<span style="font-size:20px">{{ h.breakdown.icon }}</span>' +
          '<span style="flex:1;min-width:0"><b style="display:block;font-size:13px">{{ h.breakdown.title }}<span ng-if="h.breakdown.water"> · {{ h.breakdown.water }} °C</span></b><span style="font-size:11px;color:#ffd9d4">{{ speed() < 3 ? \'Der Pannendienst kommt zu dir.\' : \'Anhalten, dann Pannendienst rufen.\' }}</span></span>' +
          '<button class="btn go" ng-if="speed() < 3" ng-click="lua(\'roadside\')">Pannendienst rufen</button>' +
        '</div>' +
        '<div ng-if="h.service" style="margin-top:6px;padding:7px 9px;border-radius:6px;background:rgba(92,70,6,.6);border:1px solid rgba(255,202,40,.55)">' +
          '<div style="display:flex;align-items:baseline;gap:8px"><b style="font-size:13px;color:#ffd666">🟡 {{ h.service.text }}</b><span style="font-size:11px;color:#f1e3b0">{{ h.service.title }}</span>' +
            '<span style="margin-left:auto;font:800 12px Consolas,monospace;color:#fff">{{ h.service.dist !== undefined && h.service.dist !== null ? h.service.dist + \' m\' : (h.service.left !== undefined && h.service.left !== null ? h.service.left + \' s\' : \'\') }}</span></div>' +
          '<div ng-if="h.service.pct !== undefined && h.service.pct !== null" style="height:4px;margin-top:5px;border-radius:2px;background:rgba(255,255,255,.14);overflow:hidden"><i style="display:block;height:100%;background:#ffd666" ng-style="{width: h.service.pct + \'%\'}"></i></div>' +
        '</div>' +
        '<div class="near" ng-if="h.viewHint">🔭 <b>{{ h.viewHint.name }}</b> <span class="mut">· {{ h.viewHint.km }} {{ h.viewHint.where }}</span> <a ng-if="h.viewHint.canGo" style="cursor:pointer;color:#ffc964;font-weight:800;margin-left:6px" ng-click="lua(\'navToPlace\', h.viewHint.id)">Hinfahren ›</a></div>' +
        '<div class="near" ng-if="h.near">Vor Ort: <b>{{ h.near.name }}</b> <span class="mut">· {{ h.near.typeName }}</span></div>' +
        '<div class="acts">' +
          '<button class="btn pri" ng-click="lua(\'toggleOffice\')">Büro</button>' +
          // (BeamNG.Earth's autodrive along the route, on and off while driving – Strg+Umschalt+A)
          '<button class="btn" ng-class="{go: h.autodrive}" ng-click="lua(\'autodriveToggle\')" title="Autodrive: der LKW fährt die Navi-Route selbst (Strg+Umschalt+A)">🤖 {{ h.autodrive ? \'Autodrive an\' : \'Autodrive\' }}</button>' +
          '<button class="btn" ng-if="h.autodrive && h.photoSet" ng-class="{go: h.photoRun}" ng-click="lua(\'photoSeriesToggle\')" title="Fotos von der Kabine und deinen Einbauten, bis du sie beendest (Strg+Umschalt+C)">📷 Fotos</button>' +
          '<button class="btn go" ng-if="h.near && h.near.action===\'discover\'" ng-click="lua(\'viewPhoto\')" title="Ein Foto vom Lkw an diesem Aussichtspunkt">📷 Foto machen</button>' +
          '<button class="btn" ng-if="h.near && h.near.action===\'discover\'" ng-click="lua(\'photoMode\')" title="Der Fotomodus von BeamNG">Fotomodus</button>' +
          '<button class="btn" ng-if="h.autodrive" ng-class="{go: h.cine}" ng-click="lua(\'cineToggle\')" title="Kamerafahrten von außen, die Anzeigen werden ausgeblendet (Strg+Umschalt+C)">🎬 Cinematic</button>' +
          '<button class="btn go" ng-if="h.near && h.near.action===\'refuel\' && speed() < 3" ng-click="lua(\'refuel\')">Tanken</button>' +
          '<button class="btn go" ng-if="h.near && (h.near.action===\'repair\' || h.near.action===\'home\') && (h.damage||0) > .01" ng-click="lua(\'repair\')">Reparieren{{ h.near.repairCost ? \' \' + money(h.near.repairCost) : \'\' }}</button>' +
          '<button class="btn go" ng-if="h.near && (h.near.action===\'dealerTruck\' || h.near.action===\'dealerCar\')" ng-click="lua(\'toggleOffice\', \'dealer\')">Händler</button>' +
          '<button class="btn" ng-if="h.near && h.near.freeChange" ng-click="lua(\'toggleOffice\', \'fleet\')">Fahrzeug wechseln</button>' +
          '<button class="btn go" ng-if="h.near && h.near.action===\'ferry\'" ng-click="lua(\'toggleOffice\', \'travel\')">Überfahrt buchen</button>' +
          '<button class="btn go" ng-if="h.near && h.near.action===\'fly\'" ng-click="lua(\'toggleOffice\', \'travel\')">Flug buchen</button>' +
          '<button class="btn go" ng-if="h.job && (h.job.phase === \'toTrailer\' && h.job.trailerDist < 25 || h.job.phase === \'hitching\' && h.job.manualHitch)" ng-click="lua(\'hitchNow\')">Ankuppeln</button>' +
          '<button class="btn go" ng-if="h.job && h.job.phase === \'atDelivery\' && h.job.coupled" ng-click="lua(\'unhitchNow\')">Abkuppeln</button>' +
          '<button class="btn" ng-if="h.job && h.job.phase === \'needTrailer\'" ng-click="lua(\'requestNewTrailer\')">Auflieger neu</button>' +
          '<button class="btn" ng-if="h.job && h.navName && h.navName.indexOf(h.job.target) < 0 && !h.job.spot" ng-click="lua(\'navToJob\')">Navi Auftrag</button>' +
          '<button class="btn" ng-if="fuelRatio() < .25 && !(h.near && h.near.action===\'refuel\')" ng-click="lua(\'navToNearest\', \'fuel\')">Navi Tankstelle</button>' +
          '<button class="btn go" ng-if="fuelRatio() < .03 && speed() < 3 && !(h.near && h.near.action===\'refuel\')" ng-click="lua(\'fuelHelp\')" title="Anfahrt 140 € + Diesel – Tank auf 20 %">⛽ Tankhilfe rufen</button>' +
          '<button class="btn go" ng-if="h.canRest && h.tacho && h.tacho.dayLeft < 30600" ng-click="lua(\'rest\')">Schlafen</button>' +
          '<button class="btn" ng-if="h.stuck && speed() < 3 && !h.service && !h.breakdown" ng-click="lua(\'roadside\')">Pannendienst</button>' +
          '<span class="mut" ng-if="!h.inTruck && h.truckOk" style="align-self:center">Steig ein.</span>' +
          '<span class="mut" style="margin-left:auto;align-self:center;font-size:10px">Strg+Umschalt · F Büro · G Aktion · N Navi</span>' +
        '</div>' +
      '</div></div>',
    replace: true,
    link: function (scope, element) {
      'use strict'
      scope.h = { mode: false }
      scope.tab = 'map'
      // the flags of the country sign (2026-11-09): stripes as gradients, the rest as small pictures; emoji flags do not draw here
      var stripes = function (dir, list) {
        var w = 100 / list.length, s = list.map(function (c, i) { return c + ' ' + (i * w) + '% ' + ((i + 1) * w) + '%' }).join(',')
        return { background: 'linear-gradient(' + dir + ',' + s + ')' }
      }
      var H = function () { return stripes('to bottom', [].slice.call(arguments)) }, V = function () { return stripes('to right', [].slice.call(arguments)) }
      var svg = function (body) { return { background: 'center/cover no-repeat url("data:image/svg+xml,' + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 16">' + body + '</svg>') + '")' } }
      var nordic = function (bg, c, inner) { return svg('<rect width="24" height="16" fill="' + bg + '"/><path d="M0 8h24M9 0v16" stroke="' + c + '" stroke-width="' + (inner ? 5 : 3) + '"/>' + (inner ? '<path d="M0 8h24M9 0v16" stroke="' + inner + '" stroke-width="2.4"/>' : '')) }
      var FLAGS = {
        D: H('#000', '#d00', '#ffce00'), A: H('#ed2939', '#fff', '#ed2939'), NL: H('#ae1c28', '#fff', '#21468b'), B: V('#000', '#ffd90c', '#f31830'), L: H('#ea141d', '#fff', '#51adda'),
        F: V('#002654', '#fff', '#ed2939'), I: V('#009246', '#fff', '#ce2b37'), IRL: V('#169b62', '#fff', '#ff883e'), RO: V('#002b7f', '#fcd116', '#ce1126'), MD: V('#0046ae', '#ffd200', '#cc092f'),
        PL: H('#fff', '#dc143c'), FL: H('#002b7f', '#ce1126'), UA: H('#005bbb', '#ffd500'), H: H('#cd2a3e', '#fff', '#436f4d'), BG: H('#fff', '#00966e', '#d62612'), EST: H('#0072ce', '#000', '#fff'),
        LT: H('#fdb913', '#006a44', '#c1272d'), SLO: H('#fff', '#005da4', '#ed1c24'), HR: H('#f00', '#fff', '#171796'), SK: H('#fff', '#0b4ea2', '#ee1c25'), SRB: H('#c6363c', '#0c4076', '#fff'),
        E: H('#aa151b', '#f1bf00', '#f1bf00', '#aa151b'), LV: H('#9e3039', '#9e3039', '#fff', '#9e3039', '#9e3039'), BY: H('#c8313e', '#c8313e', '#4aa657'), P: V('#060', '#060', '#f00', '#f00', '#f00'),
        DK: nordic('#c60c30', '#fff'), S: nordic('#006aa7', '#fecc00'), FIN: nordic('#fff', '#003580'), N: nordic('#ef2b2d', '#fff', '#002868'), IS: nordic('#02529c', '#fff', '#dc1e35'),
        CH: svg('<rect width="24" height="16" fill="#d52b1e"/><path d="M12 3.5v9M7.5 8h9" stroke="#fff" stroke-width="3"/>'),
        CZ: svg('<rect width="24" height="8" fill="#fff"/><rect y="8" width="24" height="8" fill="#d7141a"/><path d="M0 0l12 8L0 16z" fill="#11457e"/>'),
        UK: svg('<rect width="24" height="16" fill="#012169"/><path d="M0 0l24 16M24 0L0 16" stroke="#fff" stroke-width="3"/><path d="M0 0l24 16M24 0L0 16" stroke="#c8102e" stroke-width="1.2"/><path d="M12 0v16M0 8h24" stroke="#fff" stroke-width="5"/><path d="M12 0v16M0 8h24" stroke="#c8102e" stroke-width="3"/>'),
        GR: svg('<rect width="24" height="16" fill="#0d5eaf"/><path d="M0 2.7h24M0 6.2h24M0 9.8h24M0 13.3h24" stroke="#fff" stroke-width="1.8"/><rect width="9" height="8.9" fill="#0d5eaf"/><path d="M4.5 0v8.9M0 4.4h9" stroke="#fff" stroke-width="1.8"/>'),
        BIH: svg('<rect width="24" height="16" fill="#002395"/><path d="M7 0h13v16z" fill="#fecb00"/>'),
        MNE: svg('<rect width="24" height="16" fill="#d4af37"/><rect x="1.2" y="1.2" width="21.6" height="13.6" fill="#c40308"/>'),
        AL: svg('<rect width="24" height="16" fill="#e41e20"/><path d="M12 3l3 3-1 5-2 2-2-2-1-5z" fill="#000"/>'),
        NMK: svg('<rect width="24" height="16" fill="#d20000"/><circle cx="12" cy="8" r="3" fill="#ffe600"/><path d="M12 8L0 0M12 8L24 0M12 8L0 16M12 8l12 8M12 8H0M12 8h12M12 8V0M12 8v8" stroke="#ffe600" stroke-width="1.6"/>'),
        RKS: svg('<rect width="24" height="16" fill="#244aa5"/><path d="M9 6l3-2 3 2-1 4h-4z" fill="#d0a650"/>'),
        TR: svg('<rect width="24" height="16" fill="#e30a17"/><circle cx="9.5" cy="8" r="4" fill="#fff"/><circle cx="10.6" cy="8" r="3.2" fill="#e30a17"/><circle cx="15" cy="8" r="1.2" fill="#fff"/>')
      }
      scope.flag = function (code) { return FLAGS[code] || {} }
      scope.ok = function (x) { return !!x }
      scope.showLegend = false
      scope.s = { speed: null, fuel: null }
      scope.m = { tiles: [], places: [], route: '', w: 400, h: 150, z: 14 }

      var streams = ['electrics']
      StreamsManager.add(streams)
      scope.$on('$destroy', function () { StreamsManager.remove(streams); clearInterval(tileTimer) })
      scope.$on('streamsUpdate', function (e, data) {
        var el = data && data.electrics
        if (!el) { return }
        scope.$evalAsync(function () {
          scope.s.speed = el.wheelspeed !== undefined ? el.wheelspeed : el.airspeed
          scope.s.fuel = el.fuel
        })
      })
      scope.lua = function (fn, arg) {
        bngApi.engineLua('if fernfahrer_career then fernfahrer_career.' + fn + '(' + (arg !== undefined ? JSON.stringify(arg) : '') + ') end')
      }

      // the minimap: from BeamNG.Earth's map tiles
      var TILE = 256, DIR = '/temp/beamngEarth/maptiles/'
      var ready = {}
      var mapData = { places: [], route: [] }   // 'FernfahrerMap', twice a second
      var arr = function (x) { return Array.isArray(x) ? x : (x && typeof x === 'object' ? Object.keys(x).map(function (k) { return x[k] }) : []) }
      scope.$on('FernfahrerMap', function (e, d) { mapData = { places: arr(d && d.places), route: arr(d && d.route) } })
      function project(lat, lon, z) {
        var s = TILE * Math.pow(2, z), phi = Math.max(-85, Math.min(85, lat)) * Math.PI / 180
        return { x: (lon + 180) / 360 * s, y: (1 - Math.log(Math.tan(phi) + 1 / Math.cos(phi)) / Math.PI) / 2 * s }
      }
      function size() {
        var box = element[0].querySelector('.mapbox')
        if (box && box.clientWidth > 10) { scope.m.w = box.clientWidth; scope.m.h = box.clientHeight }
      }
      // north up (the player in the middle) or turning with the truck (🧭: the player lower down, more road ahead) and
      // tipped forward (3D); remembered in this browser
      var store = function (k, v) { try { if (v === undefined) { return window.localStorage.getItem(k) } window.localStorage.setItem(k, v) } catch (e) { return null } }
      scope.m.follow = store('ffbMapFollow') === '1'
      scope.m.tilt = store('ffbMapTilt') === '1'
      scope.m.rot = 0
      var lastHead = null
      function anchorY() { return scope.m.follow ? (scope.m.tilt ? 0.8 : 0.66) : (scope.m.tilt ? 0.7 : 0.5) }
      scope.toggleFollow = function () { scope.m.follow = !scope.m.follow; store('ffbMapFollow', scope.m.follow ? '1' : '0'); buildMap() }
      // night mode (2026-11-04: the white map glared at night): the tiles turned dark (inverted, the hue turned back, a
      // little dimmer) – the route, the markers and the arrow keep their colours. auto: at night by the game's clock
      scope.m.night = store('ffbMapNight') || 'auto'
      scope.isDark = function () { return scope.m.night === 'on' || (scope.m.night === 'auto' && !!scope.h.night) }
      // the route warner: on/off (career.lua routeWarn); a new warning with a short two-tone chime
      scope.toggleWarn = function () {
        var on = !scope.h.routeWarn
        scope.h.routeWarn = on
        bngApi.engineLua('if fernfahrer_career then fernfahrer_career.setOption("routeWarn", ' + (on ? 'true' : 'false') + ') end')
        if (on) { chime() }                            // (so it is heard what the warner sounds like)
      }
      scope.warnOn = function () { var e = scope.h && scope.h.event; return !!(scope.h && scope.h.routeWarn && e && e.kind !== 'siren' && e.kind !== 'control') }
      var warnKey = null, actx = null
      function chime() {
        try {
          actx = actx || new (window.AudioContext || window.webkitAudioContext)()
          var t0 = actx.currentTime;
          [[880, 0], [1320, 0.16]].forEach(function (n) {
            var o = actx.createOscillator(), g = actx.createGain()
            o.type = 'sine'; o.frequency.value = n[0]
            g.gain.setValueAtTime(0, t0 + n[1]); g.gain.linearRampToValueAtTime(0.18, t0 + n[1] + 0.02); g.gain.exponentialRampToValueAtTime(0.001, t0 + n[1] + 0.32)
            o.connect(g); g.connect(actx.destination); o.start(t0 + n[1]); o.stop(t0 + n[1] + 0.35)
          })
        } catch (e) {}
      }
      function warnCheck() {
        var k = scope.warnOn() ? scope.h.event.kind + '|' + scope.h.event.title : null
        if (k && k !== warnKey) { chime() }
        warnKey = k
      }
      scope.toggleNight = function () {
        scope.m.night = scope.m.night === 'auto' ? 'on' : (scope.m.night === 'on' ? 'off' : 'auto')
        store('ffbMapNight', scope.m.night)
      }
      scope.nightTip = function () {
        return scope.m.night === 'on' ? 'Nachtkarte immer an – klicken: immer hell' : (scope.m.night === 'off' ? 'Karte immer hell – klicken: automatisch' : 'Nachtkarte automatisch bei Dunkelheit – klicken: immer an')
      }
      scope.toggleTilt = function () { scope.m.tilt = !scope.m.tilt; store('ffbMapTilt', scope.m.tilt ? '1' : '0'); buildMap() }
      scope.viewStyle = function () {
        var m = scope.m
        if (!m.follow && !m.tilt) { return {} }
        var tf = (m.tilt ? 'perspective(' + Math.round(m.h * 1.6) + 'px) rotateX(52deg) ' : '') + (m.follow ? 'rotate(' + (-m.rot).toFixed(1) + 'deg)' : '')
        return { transform: tf, 'transform-origin': (m.w / 2) + 'px ' + Math.round(m.h * anchorY()) + 'px' }
      }
      scope.meStyle = function () {
        var m = scope.m
        return { left: (m.w / 2) + 'px', top: Math.round(m.h * anchorY()) + 'px',
          transform: 'rotate(' + (m.follow ? 0 : (scope.h.heading || 0)) + 'deg)' + (m.tilt ? ' scaleY(.8)' : '') }
      }
      // (the markers stay upright when the map turns)
      scope.mkT = function () { return scope.m.follow ? 'translate(-50%,-50%) rotate(' + scope.m.rot.toFixed(1) + 'deg)' : 'translate(-50%,-50%)' }
      // the heading as one running number: 359° → 1° is +2°, not a turn back the long way round
      function trackHeading(hd) {
        if (typeof hd !== 'number') { return }
        if (lastHead === null) { scope.m.rot = hd } else { scope.m.rot += ((hd - lastHead + 540) % 360) - 180 }
        lastHead = hd
      }
      function buildMap() {
        var h = scope.h, m = scope.m
        if (!h || !h.player) { return }
        size()
        var z = m.z, c = project(h.player.lat, h.player.lon, z)
        var ay = anchorY()
        var left = c.x - m.w / 2, top = c.y - m.h * ay, n = Math.pow(2, z)
        // turned or tipped: the tiles reach past the box (its corners turn in; the far side comes into view)
        var big = Math.max(m.w, m.h)
        var padX = m.follow ? big * 0.8 : (m.tilt ? m.w * 0.6 : 0)
        var padT = m.tilt ? m.h * 2.2 : (m.follow ? big * 0.8 : 0)
        var padB = m.follow ? big * 0.6 : 0
        var tiles = [], want = []
        for (var ty = Math.floor((top - padT) / TILE); ty <= Math.floor((top + m.h + padB) / TILE); ty++) {
          for (var tx = Math.floor((left - padX) / TILE); tx <= Math.floor((left + m.w + padX) / TILE); tx++) {
            var x = ((tx % n) + n) % n
            var layers = ['map', 'labels']
            for (var li = 0; li < layers.length; li++) {
              var L = layers[li], key = L + '/' + z + '/' + x + '/' + ty
              if (ready[key]) {
                tiles.push({ k: key, ov: L === 'labels', x: tx * TILE - left, y: ty * TILE - top,
                  src: DIR + L + '/' + z + '/' + x + '/' + ty + (L === 'labels' ? '.png' : '.jpg') })
              } else {
                want.push([z, x, ty, L])
              }
            }
          }
        }
        m.tiles = tiles
        m.want = want
        function scr(lat, lon) { var p = project(lat, lon, z); return { x: p.x - left, y: p.y - top } }
        var places = []
        var list = mapData.places || []
        for (var i = 0; i < list.length; i++) {
          var p = scr(list[i].lat, list[i].lon)
          var mk = MARK[list[i].t] || ['·', '#8d99a6']
          // (a company with loads waiting: orange, the number of trailers on it)
          if (list[i].t === 'freight') { mk = [String(list[i].j || ''), '#ff8f1f'] }
          if (p.x > -10 - padX && p.y > -10 - padT && p.x < m.w + 10 + padX && p.y < m.h + 10 + padB) {
            places.push({ x: p.x, y: p.y, l: mk[0], c: mk[1], n: list[i].t === 'freight' ? list[i].n + ' – ' + list[i].j + ' Fracht(en) abholbereit' : list[i].n })
          }
        }
        m.places = places
        var pts = []
        var rl = mapData.route || []
        for (var j = 0; j < rl.length; j++) { var q = scr(rl[j][0], rl[j][1]); pts.push(q.x.toFixed(0) + ',' + q.y.toFixed(0)) }
        m.route = pts.join(' ')
        m.home = h.home ? scr(h.home.lat, h.home.lon) : null
        m.target = h.job && h.job.targetPos ? scr(h.job.targetPos.lat, h.job.targetPos.lon) : null
      }
      var tileTimer = setInterval(function () {
        var want = scope.m.want
        if (!want || !want.length || scope.tab !== 'map') { return }
        var list = JSON.stringify(want.slice(0, 24))
        bngApi.engineLua('beamngEarth_settings and beamngEarth_settings.mapTiles and beamngEarth_settings.mapTiles(jsonDecode(\'' + list + '\')) or {}', function (r) {
          var arr = Array.isArray(r) ? r : (r && typeof r === 'object' ? Object.keys(r).map(function (k) { return r[k] }) : [])
          if (!arr.length) { return }
          scope.$evalAsync(function () { arr.forEach(function (k) { ready[k] = true }); buildMap() })
        })
      }, 1000)
      scope.zoom = function (d) { scope.m.z = Math.max(12, Math.min(17, scope.m.z + d)); buildMap() }

      scope.speed = function () {
        var v = scope.s.speed !== null && scope.s.speed !== undefined ? scope.s.speed * 3.6 : (scope.h.speed || 0)
        return Math.round(Math.abs(v))
      }
      scope.over = function () { return scope.h.speedWarn && scope.h.limit && scope.speed() > scope.h.limit + 3 }
      scope.fuelRatio = function () {
        if (scope.h.fuel && scope.h.fuel.ratio !== undefined) { return scope.h.fuel.ratio }
        return scope.s.fuel !== null && scope.s.fuel !== undefined ? scope.s.fuel : 1
      }
      scope.fuelName = function () { return scope.h.fuel ? scope.h.fuel.name : 'Tank' }
      scope.fuelText = function () {
        var f = scope.h.fuel
        if (f) { return Math.round(f.amount) + ' / ' + Math.round(f.capacity) + ' ' + f.unit }
        return scope.pct(scope.fuelRatio())
      }
      scope.money = function (v) {
        if (v === undefined || v === null) { return '–' }
        return (v < 0 ? '−' : '') + Math.round(Math.abs(v)).toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.') + ' €'
      }
      scope.dist = function (m) {
        if (m === undefined || m === null) { return '–' }
        return m >= 1000 ? (m / 1000).toFixed(m >= 10000 ? 0 : 1).replace('.', ',') + ' km' : Math.round(m) + ' m'
      }
      scope.time = function (s) {
        if (s === undefined || s === null) { return '–' }
        var neg = s < 0; s = Math.abs(Math.round(s))
        var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60)
        return (neg ? '−' : '') + (h > 0 ? h + ' h ' + ('0' + m).slice(-2) : m + ' min')
      }
      scope.pct = function (f) { return Math.round((f || 0) * 100) + ' %' }
      // the next turn: arrow, text
      var ARROWS = { right: '↱', left: '↰', slightRight: '↗', slightLeft: '↖', uturn: '⤺', end: '⚑', straight: '↑' }
      scope.arrow = function (d) { return ARROWS[d] || '↑' }
      scope.cueText = function (n) {
        if (n.text) { return n.text.replace(/^In \d+ Metern /, '') }
        return { right: 'rechts abbiegen', left: 'links abbiegen', slightRight: 'halb rechts', slightLeft: 'halb links', uturn: 'wenden', end: 'Ziel' }[n.dir] || ''
      }
      // (the announcements are spoken by the game itself: career.lua navSay plays recorded phrases – the UI's
      // browser has no speech voices, it stayed silent, 2026-11-03)
      scope.toggleSound = function () {
        var on = !(scope.h && scope.h.navSound)
        bngApi.engineLua('if fernfahrer_career then fernfahrer_career.setOption("navSound", ' + (on ? 'true' : 'false') + ')' +
          (on ? '; fernfahrer_career.navSay("on")' : '') + ' end')
        if (scope.h) { scope.h.navSound = on }
      }
      scope.$on('FernfahrerHud', function (e, data) {
        scope.$evalAsync(function () {
          scope.h = data || { mode: false }
          trackHeading(scope.h.heading)
          warnCheck()
          if (scope.h.job && scope.h.job.hit) { scope.tab = 'job' }
          if (scope.tab === 'map') { buildMap() }
        })
      })
    }
  }
}]);
