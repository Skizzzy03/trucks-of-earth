// Trucks of Earth HUD: mirrors and seat (as ETS2's in-cab adjustment) – a slim vertical strip at the screen's
// edge, a page folds out beside it: the mirrors (pick one, the arrows turn it, the view goes onto it) and the seat
// (forward/back, height, tilt, field of view). career.lua uiCab / cabMirror / cabSeat → cab.lua. Only the strip and
// the page catch the mouse: looking around with the mouse goes on everywhere else.
angular.module('beamng.apps')
.directive('fernfahrerCockpit', ['$interval', function ($interval) {
  var css =
    '.ffc{position:relative;width:100%;height:100%;pointer-events:none;font-family:inherit;color:#eef1f5}' +
    '.ffc .strip{position:absolute;left:0;top:0;display:flex;flex-direction:column;gap:4px;padding:6px 5px;background:rgba(14,17,22,.88);' +
      'border:1px solid rgba(255,255,255,.1);border-left:0;border-radius:0 8px 8px 0;box-shadow:0 6px 22px rgba(0,0,0,.35);pointer-events:auto}' +
    '.ffc .strip a{width:34px;height:34px;border-radius:6px;display:flex;align-items:center;justify-content:center;font-size:17px;cursor:pointer;color:#cfd6de}' +
    '.ffc .strip a:hover{background:#232a34}.ffc .strip a.on{background:#f5a623}' +
    // (the helps: a thin line above them, a short flash on the click)
    '.ffc .strip a.hlp:first-of-type{}.ffc .strip a.hlp{position:relative}.ffc .strip a.hlp:active{background:#2fbf71}' +
    '.ffc .strip a.hlp + a.hlp{margin-top:0}.ffc .strip a:nth-child(4){margin-top:6px;border-top:1px solid #2a313b;border-radius:0 0 6px 6px;padding-top:2px}' +
    '.ffc .pg{position:absolute;left:52px;top:0;width:250px;background:rgba(14,17,22,.94);border:1px solid rgba(255,255,255,.12);border-radius:8px;' +
      'padding:9px 11px;box-shadow:0 10px 30px rgba(0,0,0,.45);pointer-events:auto;animation:ffcIn .18s ease-out}' +
    '@keyframes ffcIn{from{opacity:0;transform:translateX(-6px)}to{opacity:1;transform:none}}' +
    '.ffc .hd{display:flex;align-items:center;font-size:10.5px;font-weight:800;letter-spacing:1px;color:#9aa4b2;text-transform:uppercase;margin-bottom:7px}' +
    '.ffc .hd a{margin-left:auto;cursor:pointer;color:#8b95a3;font-size:14px;letter-spacing:0}' +
    '.ffc .chips{display:flex;flex-wrap:wrap;gap:4px;margin-bottom:8px}' +
    '.ffc .chips a{font-size:11px;font-weight:700;padding:3px 8px;border-radius:10px;background:#1a1f27;color:#cfd6de;cursor:pointer}' +
    '.ffc .chips a.on{background:#f5a623;color:#15100a}' +
    '.ffc .pad{display:grid;grid-template-columns:repeat(3,38px);grid-template-rows:repeat(3,34px);gap:4px;justify-content:center;margin:4px 0 6px}' +
    '.ffc .pad a,.ffc .rw a{display:flex;align-items:center;justify-content:center;background:#1a1f27;border-radius:6px;cursor:pointer;font-weight:800;user-select:none}' +
    '.ffc .pad a:hover,.ffc .rw a:hover{background:#252c36}.ffc .pad a:active,.ffc .rw a:active{background:#f5a623;color:#15100a}' +
    '.ffc .val{text-align:center;font:700 11px Consolas,monospace;color:#9cf29c}' +
    '.ffc .mut{font-size:11px;color:#8b95a3;margin-top:6px;line-height:1.35}' +
    '.ffc .rw{display:grid;grid-template-columns:1fr 26px 62px 26px;align-items:center;gap:4px;margin:4px 0;font-size:12px}' +
    '.ffc .rw a{height:24px}.ffc .rw .v{text-align:center;font:700 11.5px Consolas,monospace;color:#cfd6de}' +
    '.ffc .btn{margin-top:8px;width:100%;background:#1f252e;border:1px solid #2f3742;color:#e9edf2;border-radius:5px;padding:5px;font-size:11.5px;font-weight:700;cursor:pointer}' +
    '.ffc .btn:hover{border-color:#f5a623}' +
    '.ffc .vm{margin:0 0 9px;padding-bottom:8px;border-bottom:1px solid #232a34}.ffc .vm a.off{opacity:.35}' +
    '.ffc .tg{height:24px;border-radius:6px;border:1px solid #2f3742;background:#1a1f27;color:#8b95a3;font:800 11px Consolas,monospace;cursor:pointer}' +
    '.ffc .tg.on{background:#1f3a2a;border-color:#3ad38b;color:#3ad38b}' +
    '.ffc .chips a.gear{margin-left:auto;padding:3px 7px;font-size:12px}' +
    '.ffc .vset{margin:-2px 0 9px;padding:6px 8px 8px;border-radius:6px;background:#11151b;border:1px solid #232a34}' +
    '.ffc .vset .btn{margin-top:4px}.ffc .btn.dim{opacity:.55}'
  return {
    template:
      '<div class="ffc" ng-show="h.mode">' +
      '<style>' + css + '</style>' +
      '<div class="strip">' +
        '<a ng-class="{on: page === \'mirror\'}" ng-click="open(\'mirror\')" title="Spiegel einstellen">🪞</a>' +
        '<a ng-class="{on: page === \'seat\'}" ng-click="open(\'seat\')" title="Sitz einstellen">💺</a>' +
        '<a ng-click="video()" title="Video: Video-Link oder Livestream abspielen">📺</a>' +
        // (2026-11-07: the helps act at once – one click, no page to confirm)
        '<a class="hlp" ng-click="rescue()" title="Kartenfehler: über eine fehlende Brücke, ein Haus oder einen Huppel auf der Straße – weiter auf der Route (kostenlos, Strg+Umschalt+B; mehrmals drücken: jeweils ein Stück weiter)">🌉</a>' +
        '<a class="hlp" ng-click="lua(\'roadBack\')" title="Zurück auf die Straße: festgefahren oder abgekommen – auf die nächste Straße gesetzt (kostenlos, Schäden bleiben)">🛣</a>' +
        '<a class="hlp" ng-click="lua(\'fuelHelp\')" title="Tankhilfe: liegen geblieben ohne Diesel – Tank auf 20 % (Anfahrt 140 € + Diesel)">⛽</a>' +
      '</div>' +
      // the mirrors
      '<div class="pg" ng-if="page === \'mirror\'">' +
        '<div class="hd">Spiegel <a ng-click="close()" title="Schließen">×</a></div>' +
        '<div class="rw vm"><span>Virtuelle Spiegel</span><a ng-click="mirSize(-20)" title="Kleiner" ng-class="{off: !c.virtual.on}">−</a>' +
          '<button class="tg" ng-class="{on: c.virtual.on}" ng-click="mirToggle()" title="Strg+Umschalt+M">{{ c.virtual.on ? \'AN\' : \'AUS\' }}</button>' +
          '<a ng-click="mirSize(20)" title="Größer" ng-class="{off: !c.virtual.on}">+</a></div>' +
        '<div class="chips" ng-if="c.virtual.on" title="Wie viel Leistung die eingeblendeten Spiegel kosten dürfen">' +
          '<a ng-repeat="q in QUAL" ng-class="{on: c.virtual.q === q.k}" ng-click="mirQuality(q.k)">{{ q.l }}</a>' +
          '<a class="gear" ng-class="{on: ui.gear}" ng-click="ui.gear = !ui.gear" title="Sichtfeld der eingeblendeten Spiegel einstellen">⚙</a></div>' +
        '<div class="vset" ng-if="c.virtual.on && ui.gear">' +
          '<div class="rw"><span>Sichtfeld</span><a ng-mousedown="hold(\'v\', \'hfov\', -2)" ng-mouseup="release()" ng-mouseleave="release()">−</a>' +
            '<span class="v">{{ Math.round(c.virtual.hfov) }}°</span><a ng-mousedown="hold(\'v\', \'hfov\', 2)" ng-mouseup="release()" ng-mouseleave="release()">+</a></div>' +
          '<div class="rw"><span>Nach außen</span><a ng-mousedown="hold(\'v\', \'yaw\', -1)" ng-mouseup="release()" ng-mouseleave="release()">−</a>' +
            '<span class="v">{{ Math.round(c.virtual.yaw) }}°</span><a ng-mousedown="hold(\'v\', \'yaw\', 1)" ng-mouseup="release()" ng-mouseleave="release()">+</a></div>' +
          '<div class="chips" title="Gespiegelt: seitenverkehrt wie ein echter Spiegel. Originalfarben: die Engine zeichnet das Bild selbst – Farben exakt wie die Welt, aber nicht seitenverkehrt.">' +
            '<a ng-class="{on: c.virtual.mode !== \'engine\'}" ng-click="c.virtual.mode !== \'engine\' || mirView(\'mode\', 0)">Gespiegelt</a>' +
            '<a ng-class="{on: c.virtual.mode === \'engine\'}" ng-click="c.virtual.mode === \'engine\' || mirView(\'mode\', 0)">Originalfarben</a></div>' +
          '<div class="rw" ng-if="c.virtual.mode !== \'engine\'"><span>Helligkeit</span><a ng-mousedown="hold(\'v\', \'bright\', -0.05)" ng-mouseup="release()" ng-mouseleave="release()">−</a>' +
            '<span class="v">{{ Math.round((c.virtual.bright || 0.85) * 100) }} %</span><a ng-mousedown="hold(\'v\', \'bright\', 0.05)" ng-mouseup="release()" ng-mouseleave="release()">+</a></div>' +
          '<button class="btn" ng-click="mirView(\'auto\', 0)" ng-class="{dim: c.virtual.auto}">{{ c.virtual.auto ? \'Automatisch eingestellt\' : \'Zurück auf automatisch\' }}</button>' +
          '<div class="mut">Mehr Sichtfeld = mehr Weitwinkel auf gleicher Fläche (Hauskanten beim Abbiegen). „Nach außen“ dreht den Blick vom Anhänger weg.</div>' +
        '</div>' +
        '<div class="mut" ng-if="!c.mirrors.length">Dieses Fahrzeug hat keine einstellbaren Spiegel (oder dynamische Spiegel sind in den Grafikeinstellungen aus).</div>' +
        '<div class="chips"><a ng-repeat="m in c.mirrors" ng-class="{on: sel === m.name}" ng-click="pick(m)">{{ m.label }}</a></div>' +
        '<div ng-if="cur()">' +
          '<div class="pad">' +
            '<span></span><a ng-mousedown="hold(\'m\', 0.5, 0)" ng-mouseup="release()" ng-mouseleave="release()" title="Nach oben">▲</a><span></span>' +
            '<a ng-mousedown="hold(\'m\', 0, 0.5)" ng-mouseup="release()" ng-mouseleave="release()" title="Nach links">◀</a>' +
            '<a ng-click="resetMirror()" title="Zurück auf gerade">⟲</a>' +
            '<a ng-mousedown="hold(\'m\', 0, -0.5)" ng-mouseup="release()" ng-mouseleave="release()" title="Nach rechts">▶</a>' +
            '<span></span><a ng-mousedown="hold(\'m\', -0.5, 0)" ng-mouseup="release()" ng-mouseleave="release()" title="Nach unten">▼</a><span></span>' +
          '</div>' +
          '<div class="val">hoch {{ de(cur().x) }}° · seitlich {{ de(cur().z) }}°</div>' +
        '</div>' +
        '<div class="mut">Gedrückt halten zum Verstellen. Die Sicht geht dabei auf den Spiegel; die Einstellung wird pro Fahrzeug gespeichert.</div>' +
      '</div>' +
      // the seat
      '<div class="pg" ng-if="page === \'seat\'">' +
        '<div class="hd">Sitz <a ng-click="close()" title="Schließen">×</a></div>' +
        '<div class="mut" ng-if="c.seat && !c.seat.ready">Erst einmal in die Fahrersicht wechseln – dann lässt sich der Sitz verstellen.</div>' +
        '<div class="rw"><span>Vor / zurück</span><a ng-mousedown="hold(\'s\', \'y\', 0.01)" ng-mouseup="release()" ng-mouseleave="release()">−</a>' +
          '<span class="v">{{ cm(c.seat.y) }}</span><a ng-mousedown="hold(\'s\', \'y\', -0.01)" ng-mouseup="release()" ng-mouseleave="release()">+</a></div>' +
        '<div class="rw"><span>Höhe</span><a ng-mousedown="hold(\'s\', \'z\', -0.01)" ng-mouseup="release()" ng-mouseleave="release()">−</a>' +
          '<span class="v">{{ cm(c.seat.z) }}</span><a ng-mousedown="hold(\'s\', \'z\', 0.01)" ng-mouseup="release()" ng-mouseleave="release()">+</a></div>' +
        '<div class="rw"><span>Neigung</span><a ng-mousedown="hold(\'s\', \'tilt\', -1)" ng-mouseup="release()" ng-mouseleave="release()">−</a>' +
          '<span class="v">{{ de(c.seat.tilt) }}°</span><a ng-mousedown="hold(\'s\', \'tilt\', 1)" ng-mouseup="release()" ng-mouseleave="release()">+</a></div>' +
        '<div class="rw"><span>Sichtfeld</span><a ng-mousedown="hold(\'s\', \'fov\', -1)" ng-mouseup="release()" ng-mouseleave="release()">−</a>' +
          '<span class="v">{{ c.seat.fov ? Math.round(c.seat.fov) + \'°\' : \'–\' }}</span><a ng-mousedown="hold(\'s\', \'fov\', 1)" ng-mouseup="release()" ng-mouseleave="release()">+</a></div>' +
        '<button class="btn" ng-click="seat(\'reset\', 0)">Zurücksetzen</button>' +
        '<div class="mut">Tipp aus ETS2: Sitz etwas zurück und Sichtfeld um 75–80°, dann sind beide Außenspiegel im Blick. Wird pro Fahrzeug gespeichert.</div>' +
      '</div>' +
      '</div>',
    replace: true,
    link: function (scope) {
      'use strict'
      scope.h = { mode: false }
      scope.c = { mirrors: [], seat: null }
      scope.page = null
      scope.sel = null
      scope.Math = Math
      scope.de = function (x) { return (Math.round((x || 0) * 10) / 10).toFixed(1).replace('.', ',') }
      scope.cm = function (m) { var v = Math.round((m || 0) * 100); return (v > 0 ? '+' : '') + v + ' cm' }
      function lua(s, cb) { bngApi.engineLua('fernfahrer_career and ' + s + ' or nil', cb) }
      function run(s) { bngApi.engineLua('if fernfahrer_career then ' + s + ' end') }
      function load() {
        lua('fernfahrer_career.uiCab()', function (v) {
          scope.$evalAsync(function () {
            v = v || {}
            var arr = function (x) { return Array.isArray(x) ? x : (x && typeof x === 'object' ? Object.keys(x).map(function (k) { return x[k] }) : []) }
            scope.c = { mirrors: arr(v.mirrors), seat: v.seat || null, inCab: v.inCab, virtual: v.virtual || { on: false } }
            if (!scope.sel && scope.c.mirrors.length) { scope.sel = scope.c.mirrors[0].name }
          })
        })
      }
      scope.cur = function () { for (var i = 0; i < scope.c.mirrors.length; i++) { if (scope.c.mirrors[i].name === scope.sel) { return scope.c.mirrors[i] } } return null }
      scope.open = function (p) {
        if (scope.page === p) { scope.close(); return }
        scope.page = p
        if (p === 'rescue') { return }
        run('fernfahrer_career.cabView()')                 // (the driver's view: the mirrors and the seat are seen from it)
        load()
      }
      scope.close = function () { if (scope.page === 'mirror') { run('fernfahrer_career.cabUnfocus()') } scope.page = null; scope.release() }
      scope.pick = function (m) { scope.sel = m.name; run('fernfahrer_career.cabMirror(' + JSON.stringify(m.name) + ', 0, 0)') }
      scope.resetMirror = function () { if (scope.sel) { run('fernfahrer_career.cabMirror(' + JSON.stringify(scope.sel) + ', 0, 0, true)'); setTimeout(load, 120) } }
      scope.mirToggle = function () { run('fernfahrer_career.mirrorsToggle()'); setTimeout(load, 150) }
      scope.QUAL = [{ k: 'eco', l: 'Sparsam' }, { k: 'normal', l: 'Normal' }, { k: 'high', l: 'Hoch' }]
      scope.mirQuality = function (k) { scope.c.virtual.q = k; run('fernfahrer_career.mirrorsQuality(' + JSON.stringify(k) + ')') }
      scope.mirSize = function (d) { if (scope.c.virtual && scope.c.virtual.on) { run('fernfahrer_career.mirrorsSize(' + d + ')') } }
      scope.seat = function (what, d) { run('fernfahrer_career.cabSeat(' + JSON.stringify(what) + ', ' + d + ')'); setTimeout(load, 120) }
      // held buttons repeat (5× a second after a short pause), so a long press turns smoothly
      var rep = null, first = null
      function step(kind, a, b) {
        if (kind === 'm' && scope.sel) { run('fernfahrer_career.cabMirror(' + JSON.stringify(scope.sel) + ', ' + a + ', ' + b + ')') }
        if (kind === 's') { run('fernfahrer_career.cabSeat(' + JSON.stringify(a) + ', ' + b + ')') }
        if (kind === 'v') { run('fernfahrer_career.mirrorsView(' + JSON.stringify(a) + ', ' + b + ')') }
        load()
      }
      scope.ui = { gear: false }
      // the 📺: the video app's panel (FernfahrerVideo) – one event, the app opens or closes it
      scope.video = function () { scope.close(); window.dispatchEvent(new CustomEvent('ffVideoPanel')) }
      scope.rescue = function () { scope.close(); bngApi.engineLua('if fernfahrer_career then fernfahrer_career.earthRescue() end') }
      scope.lua = function (fn) { scope.close(); bngApi.engineLua('if fernfahrer_career and fernfahrer_career.' + fn + ' then fernfahrer_career.' + fn + '() end') }
      scope.mirView = function (what, d) { run('fernfahrer_career.mirrorsView(' + JSON.stringify(what) + ', ' + d + ')'); setTimeout(load, 120) }
      scope.hold = function (kind, a, b) {
        scope.release()
        step(kind, a, b)
        first = setTimeout(function () { rep = setInterval(function () { step(kind, a, b) }, 110) }, 320)
      }
      scope.release = function () { if (first) { clearTimeout(first); first = null } if (rep) { clearInterval(rep); rep = null } }
      var poll = $interval(function () { if (scope.page) { load() } }, 1000)
      scope.$on('$destroy', function () { $interval.cancel(poll); scope.release() })
      scope.$on('FernfahrerHud', function (e, data) { scope.$evalAsync(function () { scope.h = data || { mode: false }; if (!scope.h.mode) { scope.page = null } }) })
    }
  }
}]);
