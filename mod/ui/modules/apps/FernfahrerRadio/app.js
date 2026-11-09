// Trucks of Earth HUD: the cab radio as a car radio without a display (2026-11-04). The volume knob turns with
// the mouse wheel (or dragged up/down), a click on it switches the radio on/off; the tuning knob changes the station
// (wheel or click on its halves); the rocker picks the source; the keys under it seek or drive Spotify. What plays
// is in the knobs' tooltips and comes as a short message in the game. The radio helper (tools/radio) plays it;
// career.lua radioTick tells it how (cab, outside, on foot). Data: 'FernfahrerHud'.radio.
angular.module('beamng.apps')
.directive('fernfahrerRadio', [function () {
  var css =
    '.ffr{font-family:inherit;color:#d7dce2;user-select:none}' +
    // the faceplate: dark brushed metal, a chamfered edge, four screws
    '.ffr .pl{position:relative;height:84px;margin-top:4px;border-radius:9px;padding:0 12px;display:flex;align-items:center;gap:12px;' +
      'background:linear-gradient(180deg,#2a2f36 0%,#1b1f25 48%,#15181d 100%);' +
      'box-shadow:inset 0 1px 0 rgba(255,255,255,.12),inset 0 -2px 0 rgba(0,0,0,.5),0 8px 24px rgba(0,0,0,.45);border:1px solid #0c0e11}' +
    '.ffr .pl:before{content:"";position:absolute;inset:0;border-radius:9px;pointer-events:none;opacity:.35;' +
      'background:repeating-linear-gradient(90deg,rgba(255,255,255,.035) 0 1px,transparent 1px 3px)}' +
    '.ffr .sc{position:absolute;width:6px;height:6px;border-radius:50%;background:radial-gradient(circle at 35% 35%,#8a9099,#3a3f46 70%);box-shadow:0 0 0 1px #0b0d10}' +
    '.ffr .sc:after{content:"";position:absolute;left:1px;right:1px;top:2.5px;height:1px;background:#1a1d22;transform:rotate(35deg)}' +
    // a knob: knurled rim, a cap, the pointer; the arc of dots shows the volume
    '.ffr .kn{position:relative;flex:none;cursor:ns-resize}' +
    '.ffr .rim{position:absolute;border-radius:50%;background:repeating-conic-gradient(#3b414a 0 4deg,#1c2026 4deg 8deg);' +
      'box-shadow:0 3px 7px rgba(0,0,0,.6),inset 0 0 0 1px rgba(0,0,0,.6)}' +
    '.ffr .cap{position:absolute;border-radius:50%;background:radial-gradient(circle at 40% 32%,#4b525c,#262b32 60%,#1a1e23);' +
      'box-shadow:inset 0 1px 1px rgba(255,255,255,.15),0 1px 2px rgba(0,0,0,.6)}' +
    '.ffr .ptr{position:absolute;left:50%;top:0;bottom:50%;width:0;transform-origin:50% 100%}' +
    '.ffr .ptr i{position:absolute;left:-1.5px;top:6px;width:3px;height:11px;border-radius:2px;background:#f5a623;box-shadow:0 0 6px rgba(245,166,35,.7)}' +
    '.ffr .off .ptr i{background:#59606a;box-shadow:none}' +
    '.ffr .dot{position:absolute;width:3px;height:3px;border-radius:50%;background:#2c3138}' +
    '.ffr .dot.on{background:#f5a623;box-shadow:0 0 4px #f5a623}' +
    '.ffr .lbl{position:absolute;left:0;right:0;text-align:center;font:800 7.5px Arial,sans-serif;letter-spacing:1.4px;color:#6f7782}' +
    // the middle: the source rocker and the keys
    '.ffr .mid{flex:1;display:flex;flex-direction:column;gap:6px;align-items:stretch}' +
    '.ffr .src{display:flex;border-radius:5px;overflow:hidden;box-shadow:0 2px 4px rgba(0,0,0,.5),inset 0 0 0 1px #0b0d10}' +
    '.ffr .src a{flex:1;position:relative;padding:5px 0 4px;text-align:center;cursor:pointer;font:800 8.5px Arial,sans-serif;letter-spacing:.8px;color:#8b939e;' +
      'background:linear-gradient(180deg,#30353d,#22262c);border-right:1px solid #111418}' +
    '.ffr .src a:last-child{border-right:0}.ffr .src a:hover{color:#d7dce2}' +
    '.ffr .src a.sel{background:linear-gradient(180deg,#1d2126,#262b31);color:#e8ecf0;box-shadow:inset 0 2px 3px rgba(0,0,0,.6)}' +
    '.ffr .src a i{position:absolute;left:50%;top:2px;margin-left:-6px;width:12px;height:2px;border-radius:1px;background:#2c3138}' +
    '.ffr .src a.sel i{background:#3ad38b;box-shadow:0 0 5px #3ad38b}' +
    '.ffr .mid{position:relative}.ffr .srcbtn a{flex:1;letter-spacing:.6px}.ffr .srcbtn .sl{color:#6f7782;margin-right:3px}' +
    '.ffr .srcmenu{position:absolute;left:50%;width:240px;transform:translateX(-50%);bottom:calc(100% + 8px);z-index:5;border-radius:6px;overflow:hidden;' +
      'background:linear-gradient(180deg,#2a2f36,#1b1f25);box-shadow:0 8px 20px rgba(0,0,0,.6),inset 0 0 0 1px #0b0d10}' +
    '.ffr .srcmenu a{display:flex;align-items:baseline;gap:6px;padding:6px 9px;cursor:pointer;border-top:1px solid #111418;color:#c2c8cf}' +
    '.ffr .srcmenu a:first-child{border-top:0}.ffr .srcmenu a:hover{background:#30363e}' +
    '.ffr .srcmenu a.sel{box-shadow:inset 3px 0 0 #3ad38b;color:#fff}' +
    '.ffr .srcmenu b{font:800 9px Arial,sans-serif;letter-spacing:.8px;width:52px}.ffr .srcmenu small{flex:1;font-size:9.5px;color:#8b939e}' +
    '.ffr .srcmenu em{font-style:normal;font-size:9px;color:#3ad38b}' +
    '.ffr .keys{display:flex;gap:5px}.ffr .keys a.off{opacity:.3;pointer-events:none}' +
    '.ffr .keys a{flex:1;height:22px;line-height:22px;text-align:center;border-radius:4px;cursor:pointer;font-size:11px;color:#c2c8cf;' +
      'background:linear-gradient(180deg,#343a42,#23272d);box-shadow:0 2px 3px rgba(0,0,0,.55),inset 0 1px 0 rgba(255,255,255,.08)}' +
    '.ffr .keys a:hover{color:#fff}.ffr .keys a:active{transform:translateY(1px);box-shadow:0 1px 1px rgba(0,0,0,.6)}' +
    '.ffr .led{position:absolute;right:12px;top:7px;width:5px;height:5px;border-radius:50%;background:#3a1512}' +
    '.ffr .led.ok{background:#3ad38b;box-shadow:0 0 6px #3ad38b}.ffr .led.wait{background:#ffb12e;box-shadow:0 0 6px #ffb12e;animation:ffrB 1s steps(2) infinite}' +
    '.ffr .led.bad{background:#ff5b4e;box-shadow:0 0 6px #ff5b4e}' +
    '@keyframes ffrB{50%{opacity:.3}}' +
    // the EQ key and the panel folding out under the faceplate
    '.ffr .pl,.ffr .eqp{pointer-events:auto}.ffr .pl{z-index:2;flex:none}.ffr .eqp{flex:none}' +
    '.ffr .keys a.eqk{flex:none;width:30px;font:800 8.5px Arial,sans-serif;letter-spacing:.6px;position:relative}' +
    '.ffr .keys a.eqk.on{color:#f5a623}.ffr .keys a.eqk.on:after{content:"";position:absolute;left:50%;bottom:2px;margin-left:-5px;width:10px;height:2px;border-radius:1px;background:#f5a623;box-shadow:0 0 4px #f5a623}' +
    '.ffr .eqp{position:relative;margin:0 18px -6px;height:0;overflow:hidden;border-radius:9px 9px 0 0;transition:height .28s ease;' +
      'background:linear-gradient(0deg,#121519,#1a1e24);box-shadow:inset 0 -6px 8px -4px rgba(0,0,0,.8),0 -6px 18px rgba(0,0,0,.35);border:1px solid #0c0e11;border-bottom:0}' +
    '.ffr .eqp.open{height:86px}' +
    '.ffr .eqp .row{position:absolute;left:0;right:0;top:12px;display:flex;justify-content:space-around;align-items:flex-start}' +
    '.ffr .eqp .kn{cursor:ns-resize}.ffr .eqp .lbl{bottom:-13px}' +
    '.ffr .eqp .db{position:absolute;left:0;right:0;bottom:-24px;text-align:center;font:700 8px Consolas,monospace;color:#8b939e}' +
    '.ffr .eqp .dot.mid{background:#59606a}' +
    // the list of stations (2026-11-08): over the faceplate, tabs, a star for each
    '.stlwrap{position:fixed;z-index:2147481000;pointer-events:none}' +
    '.ffr .stl{position:relative;width:520px;pointer-events:auto;border-radius:9px;overflow:hidden;font:12px Arial,sans-serif;color:#d7dce2;' +
      'background:linear-gradient(180deg,#2a2f36,#191d22);box-shadow:0 12px 30px rgba(0,0,0,.6),inset 0 1px 0 rgba(255,255,255,.1);border:1px solid #0c0e11}' +
    '.ffr .stl .hd{display:flex;align-items:center;gap:2px;padding:7px 8px 0;border-bottom:1px solid #111418}' +
    '.ffr .stl .hd a{padding:5px 10px 7px;font-weight:800;font-size:10.5px;letter-spacing:.6px;color:#8b939e;cursor:pointer;border-bottom:2px solid transparent}' +
    '.ffr .stl .hd a:hover{color:#d7dce2}.ffr .stl .hd a.on{color:#fff;border-bottom-color:#f5a623}.ffr .stl .hd .x{margin-left:auto;font-size:13px;padding:2px 7px 6px}' +
    '.ffr .stl .ls{overflow-y:auto;padding:3px 0;display:grid;grid-template-columns:1fr 1fr;align-content:start}' +
    '.ffr .stl .ls::-webkit-scrollbar{width:6px}.ffr .stl .ls::-webkit-scrollbar-thumb{background:#3b414a;border-radius:3px}' +
    '.ffr .stl .it{display:flex;align-items:center;gap:7px;padding:5px 10px 5px 6px;cursor:pointer;min-width:0}.ffr .stl .it:hover{background:#30363e}' +
    '.ffr .stl .it.cur{box-shadow:inset 3px 0 0 #3ad38b;background:rgba(58,211,139,.08)}' +
    '.ffr .stl .star{flex:none;width:20px;text-align:center;font-size:14px;line-height:16px;color:#59606a}.ffr .stl .star:hover{color:#ffd27a}.ffr .stl .star.on{color:#f5a623}' +
    '.ffr .stl .nm{font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.ffr .stl .it.cur .nm{color:#fff}' +
    '.ffr .stl small{margin-left:auto;padding-left:6px;flex:0 1 auto;min-width:0;font-size:10px;color:#8b939e;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}' +
    '.ffr .stl .emp{grid-column:1/3;padding:18px 16px;text-align:center;color:#8b939e;line-height:1.5}' +
    '.ffr .stl .ft{display:flex;align-items:center;gap:7px;padding:7px 10px;border-top:1px solid #111418;font-size:11px;color:#aab2bc}.ffr .stl .ft a{display:flex;align-items:center;gap:7px;cursor:pointer}.ffr .stl .ft a:hover{color:#fff}' +
    '.ffr .stl .ft i{width:24px;height:13px;border-radius:7px;background:#3b414a;position:relative;transition:background .15s}.ffr .stl .ft i:after{content:"";position:absolute;left:2px;top:2px;width:9px;height:9px;border-radius:50%;background:#aab2bc;transition:left .15s}' +
    '.ffr .stl .ft a.on i{background:#3ad38b}.ffr .stl .ft a.on i:after{left:13px;background:#fff}.ffr .stl .ft span{margin-left:auto;color:#6f7782}'
  // the volume arc: 11 dots from -135° to +135°
  var DOTS = []
  for (var i = 0; i <= 10; i++) { DOTS.push(-135 + i * 27) }
  return {
    template:
      '<div class="bngApp ffr" ng-show="h.mode && h.radio" style="width:100%;height:100%;background:transparent;box-shadow:none;pointer-events:none;overflow:visible;display:flex;flex-direction:column-reverse;">' +
      '<div class="pl" ng-class="{off: !r.on}">' +
        '<span class="sc" style="left:5px;top:5px"></span><span class="sc" style="right:5px;top:5px"></span>' +
        '<span class="sc" style="left:5px;bottom:5px"></span><span class="sc" style="right:5px;bottom:5px"></span>' +
        '<span class="led" ng-class="ledClass()" title="{{ statusTip() }}"></span>' +
        // the volume knob
        '<div class="kn vol" style="width:68px;height:68px" title="{{ volTip() }}">' +
          '<span ng-repeat="a in DOTS" class="dot" ng-class="{on: r.on && $index <= Math.round((r.vol || 0) * 10)}" ' +
            'ng-style="{left: (34 + 32 * Math.sin(a * Math.PI / 180) - 1.5) + \'px\', top: (34 - 32 * Math.cos(a * Math.PI / 180) - 1.5) + \'px\'}"></span>' +
          '<span class="rim" style="left:8px;top:8px;width:52px;height:52px"></span>' +
          '<span class="cap" style="left:14px;top:14px;width:40px;height:40px" ng-click="power()">' +
            '<span class="ptr" ng-style="{transform: \'rotate(\' + (-135 + (r.vol || 0) * 270) + \'deg)\'}"><i></i></span></span>' +
          '<span class="lbl" style="bottom:-9px">VOL · PUSH</span>' +
        '</div>' +
        // the middle
        '<div class="mid">' +
          // the source: one button, a click opens the list (picked by hand only – 2026-11-04)
          '<div class="src srcbtn"><a class="sel" ng-click="toggleSrc()" title="Quelle wählen"><i></i><span class="sl">QUELLE</span> {{ srcLabel() }} ▾</a></div>' +
          '<div class="srcmenu" ng-if="srcOpen">' +
            '<a ng-repeat="s in SRC" ng-class="{sel: r.src === s.k}" ng-click="pickSrc(s.k)" title="{{ s.tip }}">' +
              '<b>{{ s.l }}</b><small>{{ s.sub }}</small><em ng-if="s.k === \'video\' && r.videoOn">● läuft</em></a>' +
          '</div>' +
          '<div class="keys" ng-if="r.src !== \'spotify\'"><a ng-click="cmd(\'stprev\')" title="Sender zurück" ng-class="{off: r.src === \'video\'}">◂◂</a><a ng-click="cmd(\'stnext\')" title="Sender vor" ng-class="{off: r.src === \'video\'}">▸▸</a>' +
            '<a class="eqk" ng-if="r.src === \'radio\'" ng-class="{on: listOpen}" ng-click="toggleList()" title="Senderliste und Favoriten">☰</a>' +
            '<a class="eqk" ng-class="{on: eqOpen}" ng-click="toggleEq()" title="Klangregelung: Tiefen, Mitten, Höhen">EQ</a></div>' +
          '<div class="keys" ng-if="r.src === \'spotify\'"><a ng-click="cmd(\'prev\')" title="Vorheriger Titel">⏮</a><a ng-click="cmd(\'play\')" title="Play / Pause">⏯</a><a ng-click="cmd(\'next\')" title="Nächster Titel">⏭</a>' +
            '<a class="eqk" ng-class="{on: eqOpen}" ng-click="toggleEq()" title="Klangregelung (bei Spotify ohne Wirkung: dort regelt der Helfer nur die Lautstärke)">EQ</a></div>' +
        '</div>' +
        // the tuning knob
        '<div class="kn tune" style="width:52px;height:52px" title="{{ tuneTip() }}">' +
          '<span class="rim" style="left:2px;top:2px;width:48px;height:48px"></span>' +
          '<span class="cap" style="left:8px;top:8px;width:36px;height:36px">' +
            '<span class="ptr" ng-style="{transform: \'rotate(\' + tuneAngle + \'deg)\'}"><i style="background:#cfd6de;box-shadow:none;height:9px;top:5px"></i></span></span>' +
          '<span class="lbl" style="bottom:-15px">TUNE</span>' +
        '</div>' +
        '<div class="ffr stlwrap" ng-style="listPos"><div class="stl" ng-if="listOpen && list && h.mode">' +
          '<div class="hd"><a ng-repeat="t in LISTTABS" ng-class="{on: listTab === t.k}" ng-click="setListTab(t.k)">{{ t.l }}</a><a class="x" ng-click="toggleList()" title="Schließen">✕</a></div>' +
          '<div class="ls" ng-style="{\'max-height\': lsMax + \'px\'}">' +
            '<div class="it" ng-repeat="s in visibleStations() track by s.i" ng-class="{cur: s.i === list.cur}" ng-click="pickStation(s)">' +
              '<span class="star" ng-class="{on: s.f}" ng-click="toggleFav(s, $event)" title="{{ s.f ? \'Aus den Favoriten nehmen\' : \'Als Favorit merken\' }}">{{ s.f ? \'★\' : \'☆\' }}</span>' +
              '<span class="nm">{{ s.n }}</span><small>{{ s.r || \'\' }}</small></div>' +
            '<div class="emp" ng-if="!visibleStations().length">Noch keine Favoriten.<br>Tipp auf den Stern neben einem Sender.</div>' +
          '</div>' +
          '<div class="ft"><a ng-class="{on: list.regional}" ng-click="toggleRegional()" title="Im neuen Bundesland automatisch auf den Sender von dort wechseln"><i></i>Regionalsender automatisch</a>' +
            '<span ng-if="list.favs > 1">Knopf: nur Favoriten</span></div>' +
        '</div></div>' +
      '</div>' +
      // the equalizer: three knobs, 0 at the top, ±12 dB to either side; wheel, drag, double-click = 0
      '<div class="eqp" ng-class="{open: eqOpen}"><div class="row">' +
        '<div ng-repeat="b in BANDS" class="kn eqk-{{ b.k }}" data-band="{{ b.k }}" style="width:46px;height:46px" title="{{ b.l }}: Mausrad drehen, ziehen; Doppelklick = Mitte">' +
          '<span ng-repeat="a in EQDOTS" class="dot" ng-class="{on: eqLit(b.k, $index), mid: $index === 6}" ' +
            'ng-style="{left: (23 + 22 * Math.sin(a * Math.PI / 180) - 1.5) + \'px\', top: (23 - 22 * Math.cos(a * Math.PI / 180) - 1.5) + \'px\'}"></span>' +
          '<span class="rim" style="left:6px;top:6px;width:34px;height:34px"></span>' +
          '<span class="cap" style="left:11px;top:11px;width:24px;height:24px">' +
            '<span class="ptr" ng-style="{transform: \'rotate(\' + (eqVal(b.k) * 11.25) + \'deg)\'}"><i style="height:7px;top:3px;width:2px;left:-1px"></i></span></span>' +
          '<span class="lbl">{{ b.l }}</span><span class="db">{{ dbText(b.k) }}</span>' +
        '</div>' +
      '</div></div>' +
      '<style>' + css + '</style>' +
      '</div>',
    replace: true,
    link: function (scope, el) {
      'use strict'
      scope.h = { mode: false }
      scope.r = {}
      scope.Math = Math
      scope.DOTS = DOTS
      scope.tuneAngle = 0
      scope.SRC = [
        { k: 'radio', l: 'RADIO', sub: 'Internetsender', tip: 'Internetradio – mit Autolautsprecher-Klang, nichts einzurichten' },
        { k: 'spotify', l: 'SPOTIFY', sub: 'Lautstärke & Tasten', tip: 'Spotify normal laufen lassen – Lautstärke innen/außen/zu Fuß, Tasten hier' },
        { k: 'video', l: 'VIDEO', sub: 'Ton des Videoplayers 📺', tip: 'Der Ton des Videos aus dem Videoplayer – synchron zum Bild' },
        { k: 'line', l: 'LINE', sub: 'Steam Streaming Speakers', tip: 'Ausgabe „Steam Streaming Speakers“ mit Klangfilter' }
      ]
      scope.srcOpen = false
      scope.toggleSrc = function () { scope.srcOpen = !scope.srcOpen }
      scope.pickSrc = function (k) { scope.srcOpen = false; scope.source(k) }
      scope.srcLabel = function () { var r = scope.r || {}; for (var i = 0; i < scope.SRC.length; i++) { if (scope.SRC[i].k === r.src) { return scope.SRC[i].l } } return 'RADIO' }
      function lua(s) { bngApi.engineLua('if fernfahrer_career then ' + s + ' end') }
      var volLocalUntil = 0
      scope.$on('FernfahrerHud', function (ev, data) {
        scope.$evalAsync(function () {
          scope.h = data || { mode: false }
          var r = (data && data.radio) || {}
          // (the knob just turned here: its value stays until the game has it)
          if (Date.now() < volLocalUntil && scope.r) { r.vol = scope.r.vol }
          scope.r = r
        })
      })
      scope.ledClass = function () {
        var r = scope.r || {}, i = r.info || {}
        if (!r.on) { return '' }
        if (!r.helper) { return 'bad' }
        if (r.src === 'radio') { return i.ok ? 'ok' : 'wait' }
        if (r.src === 'spotify') { return i.title ? 'ok' : 'wait' }
        return r.music ? 'ok' : 'wait'
      }
      scope.statusTip = function () {
        var r = scope.r || {}, i = r.info || {}
        if (!r.helper) { return 'Fernfahrer-Radio starten (eigener Download auf der GitHub-Seite der Mod)' }
        return i.status || ''
      }
      scope.volTip = function () { var r = scope.r || {}; return 'Lautstärke ' + Math.round((r.vol || 0) * 100) + ' % – Mausrad drehen, klicken: an/aus' }
      scope.tuneTip = function () {
        var r = scope.r || {}, i = r.info || {}
        if (r.src === 'spotify') { return i.title ? '♪ ' + i.title : 'Spotify' }
        if (r.src === 'video') { return (i.live ? '● LIVE – ' : '📺 ') + (i.status || 'Ton des Videoplayers') }
        return (r.station || 'Radio') + (r.favs > 1 ? ' – Mausrad: nächster Favorit' : ' – Mausrad: Sender wechseln')
      }
      scope.power = function () { var on = !(scope.r && scope.r.on); scope.r.on = on; lua('fernfahrer_career.setOption("radioOn", ' + (on ? 'true' : 'false') + ')') }
      scope.source = function (k) { scope.r.src = k; scope.r.on = true; lua('fernfahrer_career.setOption("radioSrc", ' + JSON.stringify(k) + ')') }
      scope.cmd = function (c) {
        if (c === 'stnext') { scope.tuneAngle += 24 } else if (c === 'stprev') { scope.tuneAngle -= 24 }
        lua('fernfahrer_career.radioCmd(' + JSON.stringify(c) + ')')
      }
      // --- the list of stations and the favourites (2026-11-08) ---
      scope.LISTTABS = [{ k: 'fav', l: 'FAVORITEN' }, { k: 'reg', l: 'REGIONAL' }, { k: 'all', l: 'ALLE' }]
      scope.listOpen = false
      scope.listTab = 'all'
      scope.list = null
      function listCall(expr, firstOpen) {
        bngApi.engineLua('fernfahrer_career and fernfahrer_career.' + expr + ' or nil', function (d) {
          scope.$evalAsync(function () {
            if (!d) { return }
            d.list = Array.isArray(d.list) ? d.list : Object.keys(d.list || {}).map(function (k) { return d.list[k] })
            scope.list = d
            if (firstOpen) { scope.listTab = d.favs > 0 ? 'fav' : 'all' }
          })
        })
      }
      scope.toggleList = function () {
        scope.listOpen = !scope.listOpen
        if (scope.listOpen) {
          scope.eqOpen = false; scope.srcOpen = false
          // (over the page, above the faceplate, as tall as the screen allows: inside the app's frame it was cut off)
          var r = el[0].querySelector('.pl').getBoundingClientRect()
          scope.listPos = { left: Math.max(8, r.left) + 'px', bottom: (window.innerHeight - r.top + 10) + 'px' }
          scope.lsMax = Math.max(220, Math.min(620, r.top - 130))
          listCall('radioList()', true)
        }
      }
      scope.setListTab = function (k) { scope.listTab = k }
      var visCache = [], visKey = ''
      scope.visibleStations = function () {
        var l = scope.list
        if (!l) { return [] }
        var key = scope.listTab + '|' + l.list.map(function (s) { return s.i + (s.f ? 'f' : '') }).join(',')
        if (key === visKey) { return visCache }
        var a = l.list.filter(function (s) { return scope.listTab === 'all' || (scope.listTab === 'fav' ? s.f : s.r) })
        if (scope.listTab !== 'all') { a.sort(function (x, y) { return (x.r || x.n).localeCompare(y.r || y.n, 'de') }) }
        visKey = key; visCache = a
        return a
      }
      scope.pickStation = function (s) { scope.tuneAngle += 24; if (scope.list) { scope.list.cur = s.i } listCall('radioPick(' + s.i + ')') }
      scope.toggleFav = function (s, e) { if (e) { e.stopPropagation() } s.f = !s.f; visKey = ''; listCall('radioFav(' + s.i + ')') }
      scope.toggleRegional = function () {
        var on = !(scope.list && scope.list.regional)
        if (scope.list) { scope.list.regional = on }
        lua('fernfahrer_career.setOption("radioRegional", ' + (on ? 'true' : 'false') + ')')
      }
      // (the list lives on the page itself: an app's frame cuts off what reaches out of it, and the other apps' frames take the mouse)
      var listWrap = el[0].querySelector('.stlwrap')
      document.body.appendChild(listWrap)
      scope.$on('$destroy', function () { if (listWrap.parentNode) { listWrap.parentNode.removeChild(listWrap) } })
      // (the wheel scrolls the list and does nothing else: the knobs, the camera)
      listWrap.addEventListener('wheel', function (e) { e.stopPropagation() })
      function setVol(v) {
        v = Math.round(Math.max(0, Math.min(1, v)) * 100) / 100
        if (scope.r.vol === v) { return }
        scope.r.vol = v
        volLocalUntil = Date.now() + 600
        lua('fernfahrer_career.setOption("radioVol", ' + v + ')')
      }
      // the volume knob: the wheel (5 % a notch), or held and dragged up/down
      var vol = el[0].querySelector('.vol'), tune = el[0].querySelector('.tune')
      vol.addEventListener('wheel', function (e) {
        e.preventDefault(); e.stopPropagation()
        scope.$evalAsync(function () { setVol((scope.r.vol || 0) + (e.deltaY < 0 ? 0.05 : -0.05)) })
      }, { passive: false })
      var drag = null
      vol.addEventListener('mousedown', function (e) { if (e.button === 0) { drag = { y: e.clientY, v: scope.r.vol || 0, moved: false } } })
      function onMove(e) {
        if (!drag) { return }
        var dy = drag.y - e.clientY, d = drag
        if (Math.abs(dy) > 3) { d.moved = true }
        if (d.moved) { scope.$evalAsync(function () { setVol(d.v + dy / 150) }) }
      }
      function onUp() { if (drag && drag.moved) { vol.dataset.dragged = '1'; setTimeout(function () { vol.dataset.dragged = '' }, 50) } drag = null }
      window.addEventListener('mousemove', onMove)
      window.addEventListener('mouseup', onUp)
      scope.$on('$destroy', function () { window.removeEventListener('mousemove', onMove); window.removeEventListener('mouseup', onUp) })
      // (a drag that ends on the cap is no click)
      vol.addEventListener('click', function (e) { if (vol.dataset.dragged === '1') { e.stopPropagation(); e.preventDefault() } }, true)
      // --- the equalizer: bass, mid, treble in whole dB (−12..+12), sent as setOption radioEqB/M/T ---
      scope.eqOpen = false
      scope.toggleEq = function () { scope.eqOpen = !scope.eqOpen; if (scope.eqOpen) { scope.listOpen = false } }
      scope.BANDS = [{ k: 'b', l: 'BASS' }, { k: 'm', l: 'MID' }, { k: 't', l: 'TREBLE' }]
      scope.EQDOTS = []
      for (var di = 0; di <= 12; di++) { scope.EQDOTS.push(-135 + di * 22.5) }
      var eqLocal = {}, eqLocalUntil = 0
      scope.eqVal = function (k) {
        if (Date.now() < eqLocalUntil && eqLocal[k] !== undefined) { return eqLocal[k] }
        var e = (scope.r && scope.r.eq) || {}
        return e[k] || 0
      }
      scope.eqLit = function (k, i) {
        var v = scope.eqVal(k) * 11.25, a = -135 + i * 22.5
        return (v > 0 && a > 0 && a <= v + 0.1) || (v < 0 && a < 0 && a >= v - 0.1)
      }
      scope.dbText = function (k) { var v = scope.eqVal(k); return (v > 0 ? '+' : '') + v + ' dB' }
      var KEY = { b: 'radioEqB', m: 'radioEqM', t: 'radioEqT' }
      function setEq(k, v) {
        v = Math.max(-12, Math.min(12, Math.round(v)))
        if (scope.eqVal(k) === v && Date.now() < eqLocalUntil) { return }
        ['b', 'm', 't'].forEach(function (x) { if (eqLocal[x] === undefined || Date.now() >= eqLocalUntil) { eqLocal[x] = scope.eqVal(x) } })
        eqLocal[k] = v
        eqLocalUntil = Date.now() + 800
        if (scope.r) { scope.r.eq = scope.r.eq || {}; scope.r.eq[k] = v }
        lua('fernfahrer_career.setOption("' + KEY[k] + '", ' + v + ')')
      }
      var eqp = el[0].querySelector('.eqp')
      function bandOf(e) { var n = e.target; while (n && n !== eqp) { if (n.dataset && n.dataset.band) { return n.dataset.band } n = n.parentNode } return null }
      eqp.addEventListener('wheel', function (e) {
        var k = bandOf(e); if (!k) { return }
        e.preventDefault(); e.stopPropagation()
        scope.$evalAsync(function () { setEq(k, scope.eqVal(k) + (e.deltaY < 0 ? 1 : -1)) })
      }, { passive: false })
      eqp.addEventListener('dblclick', function (e) { var k = bandOf(e); if (k) { scope.$evalAsync(function () { setEq(k, 0) }) } })
      var eqDrag = null
      eqp.addEventListener('mousedown', function (e) { var k = bandOf(e); if (k && e.button === 0) { eqDrag = { k: k, y: e.clientY, v: scope.eqVal(k) } } })
      function onEqMove(e) { if (!eqDrag) { return } var d = eqDrag, dy = d.y - e.clientY; if (Math.abs(dy) > 3) { scope.$evalAsync(function () { setEq(d.k, d.v + dy / 8) }) } }
      function onEqUp() { eqDrag = null }
      window.addEventListener('mousemove', onEqMove)
      window.addEventListener('mouseup', onEqUp)
      scope.$on('$destroy', function () { window.removeEventListener('mousemove', onEqMove); window.removeEventListener('mouseup', onEqUp) })

      // the tuning knob: the wheel steps the stations (or the songs), a click on its left/right half too
      var lastTune = 0
      tune.addEventListener('wheel', function (e) {
        e.preventDefault(); e.stopPropagation()
        var t = Date.now()
        if (t - lastTune < 140) { return }
        lastTune = t
        var up = e.deltaY < 0, sp = scope.r.src === 'spotify'
        scope.$evalAsync(function () { scope.cmd(sp ? (up ? 'next' : 'prev') : (up ? 'stnext' : 'stprev')) })
      }, { passive: false })
      tune.addEventListener('click', function (e) {
        var b = tune.getBoundingClientRect(), right = e.clientX > b.left + b.width / 2, sp = scope.r.src === 'spotify'
        scope.$evalAsync(function () { scope.cmd(sp ? (right ? 'next' : 'prev') : (right ? 'stnext' : 'stprev')) })
      })
    }
  }
}]);
