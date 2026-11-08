// Trucks of Earth HUD: the working time. Two faces (the choice is kept in the browser's storage):
//  EINFACH (the default, 2026-11-08): in plain words how long one may still drive and what comes next, how tired the
//    driver is, one button for a break, one for sleeping – for players who never saw a tachograph.
//  PROFI: the digital tachograph as before (career.lua / tacho.lua via 'FernfahrerHud'.tacho): activity keys, the last
//    24 h as a bar. Standing it shows OTHER WORK until a button is pressed – only the bed counts as a break.
// The explanation opens in a window of its own on the page's body: inside the app's frame it was cut off.
angular.module('beamng.apps')
.directive('fernfahrerTacho', ['$sce', function ($sce) {
  // the tachograph's own symbols (as on the DTCO keys)
  var ICON = {
    drive: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2.4"/><circle cx="12" cy="12" r="2.4" fill="currentColor"/><path d="M3.5 11h6M14.5 11h6M12 14.4v6.2" stroke="currentColor" stroke-width="2.4"/></svg>',
    work: '<svg viewBox="0 0 24 24"><path d="M5 19l9-9M19 19l-9-9" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"/><path d="M11 4.5l4.5 4.5-2.2 2.2-4.5-4.5zM13 4.5l-4.5 4.5 2.2 2.2 4.5-4.5z" fill="currentColor"/></svg>',
    avail: '<svg viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.4"/><path d="M4 20L20 4" stroke="currentColor" stroke-width="2.4"/></svg>',
    rest: '<svg viewBox="0 0 24 24"><path d="M3 18V7M3 14h18v4M21 14v-2.5a2.5 2.5 0 0 0-2.5-2.5H11v5" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linejoin="round"/><circle cx="7" cy="11" r="2.2" fill="currentColor"/></svg>',
    book: '<svg viewBox="0 0 24 24"><path d="M4 5.5C6.5 4 9.5 4 12 5.5 14.5 4 17.5 4 20 5.5V19c-2.5-1.5-5.5-1.5-8 0-2.5-1.5-5.5-1.5-8 0z" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/><path d="M12 5.5V19" stroke="currentColor" stroke-width="2"/></svg>'
  }
  var COL = { drive: '#5fb4ff', work: '#ffb12e', avail: '#b48cff', rest: '#3ad38b' }
  var FAT = { 1: '#3ad38b', 2: '#ffd166', 3: '#ff9a3c', 4: '#ff5b4d' }
  var FULL_DRIVE = 16200                       // (4.5 h: a full stint between two breaks)
  var css =
    // (from its top: the cab app sits right on top of it, whichever face it shows – 2026-11-08)
    '.fft{font-family:inherit;color:#eef1f5;height:100%;display:flex;flex-direction:column;justify-content:flex-start;position:relative}' +
    '.fft .c{background:rgba(14,17,22,.9);border:1px solid rgba(255,255,255,.1);border-radius:6px;padding:7px 9px;box-shadow:0 6px 22px rgba(0,0,0,.35)}' +
    '.fft .hd{display:flex;align-items:center;gap:5px;font-size:10px;font-weight:800;letter-spacing:.6px;color:#9aa4b2;text-transform:uppercase;white-space:nowrap}' +
    '.fft .hd .v{background:#ff6b5e;color:#fff;border-radius:4px;padding:0 4px;letter-spacing:0;font-size:9.5px}' +
    '.fft .hd .bk{flex:0 0 auto;min-width:20px;height:20px;box-sizing:border-box;text-align:center;color:#cfd6de;cursor:pointer;border-radius:4px;padding:1px}.fft .hd .bk:hover,.fft .hd .bk.on{background:#2a313b;color:#fff}' +
    '.fft .hd .sp{margin-left:auto}.fft .hd .tx{font:800 10px/18px Consolas,monospace;padding:0 4px}' +
    '.fft .ic{display:inline-block;width:16px;height:16px;vertical-align:-3px}.fft .ic svg{width:100%;height:100%}' +
    '.fft .say{margin-top:6px;font-size:16px;font-weight:800;line-height:1.15}.fft .say.warn{color:#ffd166}.fft .say.bad{color:#ff6b5e}.fft .say.good{color:#7fe3a4}' +
    '.fft .sub{font-size:11.5px;color:#9aa4b2;margin-top:2px;line-height:1.25}' +
    '.fft .mt{display:flex;justify-content:space-between;font-size:10.5px;color:#9aa4b2;margin-top:7px}.fft .mt b{color:#eef1f5}' +
    '.fft .bigbar{height:7px;background:rgba(255,255,255,.1);border-radius:3px;overflow:hidden;margin-top:3px}.fft .bigbar i{display:block;height:100%}' +
    '.fft .acts{display:flex;gap:5px;margin-top:8px}' +
    '.fft .acts a{flex:1;text-align:center;padding:6px 2px;border-radius:5px;background:#1f2630;color:#eef1f5;cursor:pointer;font-size:12px;font-weight:800}' +
    '.fft .acts a:hover{background:#2a3340}.fft .acts a.off{opacity:.4;cursor:default}.fft .acts a.go{background:#2fbf71;color:#08210f}.fft .acts a.go:hover{background:#3ad38b}' +
    '.fft .lcd{margin-top:5px;background:#16231a;border:1px solid #23402b;border-radius:5px;padding:4px 7px;font:700 13px Consolas,monospace;color:#9cf29c}' +
    '.fft .lcd .l1,.fft .lcd .l2{display:flex;align-items:center;gap:6px;justify-content:space-between}' +
    '.fft .lcd .l2{font-size:11.5px;color:#7fcf8a;margin-top:2px}.fft .lcd .warn{color:#ffd166}.fft .lcd .bad{color:#ff6b5e}' +
    '.fft .chart{position:relative;height:8px;margin-top:5px;background:#1a1f27;border-radius:2px;overflow:hidden}' +
    '.fft .chart i{position:absolute;top:0;bottom:0}' +
    '.fft .keys{display:flex;gap:4px;margin-top:6px}' +
    '.fft .keys a{flex:1;display:flex;flex-direction:column;align-items:center;gap:1px;padding:3px 0 2px;border-radius:4px;background:#1a1f27;color:#9aa4b2;cursor:pointer;font-size:9.5px;font-weight:700}' +
    '.fft .keys a:hover{background:#232a34}.fft .keys a.on{color:#15100a}.fft .keys a.off{opacity:.4;cursor:default}' +
    '.fft .keys a .ic{width:17px;height:17px}' +
    '.fft .hint{margin-top:5px;font-size:10.5px;color:#ffd166;line-height:1.3}' +
    '.fft .bar{height:4px;background:rgba(255,255,255,.1);border-radius:2px;overflow:hidden;margin-top:4px}.fft .bar i{display:block;height:100%;background:#3ad38b}' +
    '.fft .row{display:flex;justify-content:space-between;font-size:11px;color:#9aa4b2;margin-top:3px}.fft .row b{color:#eef1f5}' +
    '.fft .btn{margin-top:6px;width:100%;background:#2fbf71;color:#08210f;border:0;border-radius:6px;padding:4px;font-size:11.5px;font-weight:800;cursor:pointer}'
  // the window with the explanation: on the body of the page
  var HELP_CSS =
    '#ffTachoHelp{position:fixed;inset:0;z-index:2147482000;display:none;align-items:center;justify-content:center;background:rgba(4,6,9,.55);pointer-events:auto;font-family:"Noto Sans",sans-serif}' +
    '#ffTachoHelp.on{display:flex}' +
    '#ffTachoHelp .w{width:min(620px,92vw);max-height:84vh;overflow:auto;background:#10141b;border:1px solid rgba(255,255,255,.14);border-radius:12px;padding:18px 22px;box-shadow:0 24px 70px rgba(0,0,0,.6);color:#cfd6de;font-size:13.5px;line-height:1.5}' +
    '#ffTachoHelp h3{margin:0 0 8px;font-size:18px;color:#fff;display:flex;align-items:center}#ffTachoHelp h3 a{margin-left:auto;cursor:pointer;color:#8b95a3;font-size:22px;font-weight:400}#ffTachoHelp h3 a:hover{color:#fff}' +
    '#ffTachoHelp h4{margin:14px 0 4px;font-size:11.5px;letter-spacing:1.4px;text-transform:uppercase;color:#f5a623}' +
    '#ffTachoHelp ul{margin:0;padding-left:18px}#ffTachoHelp li{margin:3px 0}#ffTachoHelp b{color:#fff}' +
    '#ffTachoHelp .big{background:#171c24;border-radius:8px;padding:10px 13px;font-size:14.5px}' +
    '#ffTachoHelp .me{display:grid;grid-template-columns:1fr auto;gap:2px 14px}#ffTachoHelp .me b{text-align:right}'
  var HELP_HTML =
    '<div class="w"><h3>So funktioniert die Fahrzeit<a class="x">×</a></h3>' +
    '<div class="big">Ein LKW-Fahrer darf nicht endlos fahren. Du musst nur auf <b>zwei Dinge</b> achten:<br>' +
      '<b>1.</b> Wenn die Anzeige „Jetzt Pause machen“ zeigt: anhalten und <b>Pause</b> drücken.<br>' +
      '<b>2.</b> Abends oder wenn du müde wirst: an einem Rastplatz, Autohof oder am Hof <b>schlafen</b>.</div>' +
    '<h4>Fahren und Pause</h4><ul>' +
      '<li>Nach spätestens <b>4 ½ Stunden Fahren</b> brauchst du <b>45 Minuten Pause</b>.</li>' +
      '<li>Die Spielzeit läuft 10× schneller: 45 Minuten Pause dauern nur <b>4 ½ echte Minuten</b>.</li>' +
      '<li>Nur der <b>Pause</b>-Knopf zählt. Einfach nur stehen (Ampel, Laden) ist keine Pause.</li>' +
      '<li>Losfahren beendet die Pause. Zu kurz? Dann läuft die Zeit nicht wieder voll.</li></ul>' +
    '<h4>Schlafen</h4><ul>' +
      '<li>Pro Tag darfst du etwa <b>9 Stunden</b> fahren, dann brauchst du <b>Schlaf</b> (9–11 Stunden).</li>' +
      '<li>Geschlafen wird in den leuchtenden Kreisen an Rastplatz, Autohof oder Hof: hinfahren, anhalten, Enter.</li></ul>' +
    '<h4>Müdigkeit</h4><ul>' +
      '<li>Der Balken zeigt, wie müde dein Fahrer ist. Er steigt, solange du wach bist.</li>' +
      '<li>Wird es zu viel, <b>fallen dir beim Fahren kurz die Augen zu</b>. Das kann gefährlich werden.</li>' +
      '<li>Hilft: Pause, Kaffee an der Tankstelle – und am besten Schlaf.</li></ul>' +
    '<h4>Was passiert, wenn ich es ignoriere?</h4><ul>' +
      '<li>Bei einer <b>Polizeikontrolle</b> werden Verstöße ausgelesen. Das kostet Bußgeld (90–300 €).</li>' +
      '<li>Bei Privatfahrten (<b>OUT</b>-Knopf) wird keine Fahrzeit gezählt.</li></ul>' +
    '<h4>Deine Werte</h4><div class="me"></div>' +
    '<h4>Für Profis – die Tasten im Profi-Modus</h4><ul>' +
      '<li><b>Lenken</b> stellt sich beim Rollen selbst ein. <b>Arbeit</b>: nach dem Anhalten automatisch. <b>Bereitschaft</b>: Warten, z. B. aufs Entladen. <b>Pause</b>: Pause oder Ruhezeit.</li>' +
      '<li>Pause geteilt: erst mind. 15, später mind. 30 Minuten – in dieser Reihenfolge.</li>' +
      '<li>Tageslenkzeit 9 h, zweimal pro Woche 10 h. Ruhezeit 11 h, dreimal verkürzt 9 h. Woche max. 56 h, zwei Wochen 90 h.</li>' +
      '<li>Der bunte Balken zeigt die letzten 24 Stunden: <span style="color:#5fb4ff">■</span> Lenken <span style="color:#ffb12e">■</span> Arbeit <span style="color:#b48cff">■</span> Bereitschaft <span style="color:#3ad38b">■</span> Pause.</li></ul>' +
    '</div>'
  return {
    template:
      '<div class="bngApp fft" ng-show="h.mode && t" style="background:transparent;box-shadow:none;">' +
      '<style>' + css + '</style>' +
      '<div class="c">' +
        '<div class="hd">{{ simple ? "Fahrzeit" : "Fahrtenschreiber" }} <span class="v" ng-if="t.violations" title="Verstöße – die Polizei liest sie bei der nächsten Kontrolle aus">⚠ {{ t.violations }}</span>' +
          '<span class="sp"></span>' +
          '<span class="bk tx" ng-click="toggle()" title="Zwischen einfacher Anzeige und echtem Fahrtenschreiber wechseln">{{ simple ? "PROFI" : "EINFACH" }}</span>' +
          '<span class="bk tx" ng-class="{on: h.privateDrive}" ng-click="lua(\'privateToggle\')" title="OUT – Privatfahrt ohne Auftrag: die Fahrzeit wird nicht gezählt">OUT</span>' +
          '<span class="bk" ng-click="help()" title="Erklärung – wie funktioniert das?">' + ICON.book + '</span></div>' +
        // --- the simple face ---
        '<div ng-if="simple">' +
          '<div class="say" ng-class="say().c">{{ say().a }}</div>' +
          '<div class="sub">{{ say().b }}</div>' +
          '<div ng-if="!h.privateDrive"><div class="mt"><span>Fahrzeit bis zur Pause</span><b>{{ t.driveText }}</b></div>' +
            '<div class="bigbar"><i ng-style="{width: drivePct() + \'%\', background: driveCol()}"></i></div></div>' +
          '<div ng-if="f"><div class="mt"><span>Müdigkeit · {{ f.text }}</span><b>{{ f.pct }} %</b></div>' +
            '<div class="bigbar"><i ng-style="{width: f.pct + \'%\', background: fatCol()}"></i></div></div>' +
          '<div ng-if="t.resting && t.restGoal"><div class="mt"><span>Pause läuft: {{ t.restText }}</span><span>{{ t.restGoalText }} in <b>{{ t.restGoalLeft }}</b></span></div>' +
            '<div class="bar"><i ng-style="{width: (t.rest / t.restGoal * 100) + \'%\'}"></i></div></div>' +
          '<div class="acts" ng-if="!h.privateDrive">' +
            '<a ng-class="{off: moving(), go: !moving() && needBreak() && t.act !== \'rest\'}" ng-click="pause()" title="Nur im Stehen">{{ t.act === \'rest\' ? "⏸ Pause beenden" : "☕ Pause machen" }}</a>' +
            '<a ng-class="{off: !h.canRest || moving(), go: h.canRest && !moving() && (f && f.level >= 3)}" ng-click="sleep()" title="An Rastplatz, Autohof oder Hof">🛏 Schlafen</a>' +
          '</div>' +
        '</div>' +
        // --- the tachograph ---
        '<div ng-if="!simple">' +
          '<div class="lcd" ng-if="h.privateDrive"><div class="l1"><span>OUT · Privatfahrt</span><span>—</span></div>' +
            '<div class="l2"><span>Lenkzeit wird nicht erfasst</span><span></span></div><div class="l2"><span>Mit einem Auftrag wieder an</span><span></span></div></div>' +
          '<div class="lcd" ng-if="!h.privateDrive">' +
            '<div class="l1"><span><span class="ic" ng-bind-html="icon(t.act)"></span> {{ t.actName }}</span><span>{{ t.actText }}</span></div>' +
            '<div class="l2"><span><span class="ic">' + ICON.drive + '</span> bis Pause</span><span ng-class="{warn: t.driveLeft < 1800, bad: t.driveLeft <= 0}">{{ t.driveText }}</span></div>' +
            '<div class="l2"><span>Heute noch</span><span ng-class="{warn: t.dayLeft < 3600, bad: t.dayLeft <= 0}">{{ t.dayText }}</span></div>' +
          '</div>' +
          '<div class="chart" title="Die letzten 24 Stunden"><i ng-repeat="s in t.chart" ng-style="{left: (s.x * 100) + \'%\', width: (s.w * 100) + \'%\', background: col(s.a)}"></i></div>' +
          '<div ng-if="f"><div class="mt"><span>Müdigkeit · {{ f.text }}</span><b>{{ f.pct }} %</b></div>' +
            '<div class="bar"><i ng-style="{width: f.pct + \'%\', background: fatCol()}"></i></div></div>' +
          '<div class="keys">' +
            '<a ng-style="t.act === \'drive\' ? {background: col(\'drive\')} : {}" ng-class="{on: t.act === \'drive\'}" title="Lenken – stellt sich beim Fahren selbst ein" style="cursor:default"><span class="ic">' + ICON.drive + '</span>Lenken</a>' +
            '<a ng-repeat="k in keys" ng-click="set(k.a)" ng-class="{on: t.act === k.a, off: moving()}" ng-style="t.act === k.a ? {background: col(k.a)} : {}" title="{{ k.tip }}"><span class="ic" ng-bind-html="icon(k.a)"></span>{{ k.l }}</a>' +
          '</div>' +
          '<div ng-if="t.resting && t.restGoal"><div class="row"><span>Pause {{ t.restText }}</span><span>{{ t.restGoalText }} in <b>{{ t.restGoalLeft }}</b></span></div>' +
            '<div class="bar"><i ng-style="{width: (t.rest / t.restGoal * 100) + \'%\'}"></i></div></div>' +
          '<div class="hint" ng-if="t.act === \'work\' && !moving() && t.driveLeft < 16200 && !h.privateDrive">Stehst du für eine Pause? <b>Pause</b> drücken – sonst zählt es als Arbeit.</div>' +
          '<button class="btn" ng-if="h.canRest && t.dayLeft < 30600" ng-click="lua(\'rest\')">Schlafen (11 h Ruhezeit)</button>' +
        '</div>' +
      '</div></div>',
    replace: true,
    link: function (scope) {
      'use strict'
      scope.h = { mode: false }
      scope.t = null
      scope.f = null
      var saved = null
      try { saved = localStorage.getItem('ffTachoSimple') } catch (e) {}
      scope.simple = saved !== '0'
      scope.toggle = function () {
        scope.simple = !scope.simple
        try { localStorage.setItem('ffTachoSimple', scope.simple ? '1' : '0') } catch (e) {}
      }
      scope.keys = [
        { a: 'work', l: 'Arbeit', tip: 'Andere Arbeit (Laden, Warten an der Ampel …) – keine Pause' },
        { a: 'avail', l: 'Bereit', tip: 'Bereitschaft (Warten auf die Entladung …)' },
        { a: 'rest', l: 'Pause', tip: 'Pause / Ruhezeit – nur das zählt als Pause' }
      ]
      // (the icons are fixed markup of this file)
      var trusted = {}
      scope.icon = function (a) { return trusted[a] || '' }
      scope.col = function (a) { return COL[a] || '#555' }
      scope.moving = function () { return (scope.h.speed || 0) > 5 }
      scope.lua = function (fn) { bngApi.engineLua('if fernfahrer_career then fernfahrer_career.' + fn + '() end') }
      scope.set = function (a) {
        if (scope.moving()) { return }
        bngApi.engineLua('if fernfahrer_career then fernfahrer_career.tachoSet(' + JSON.stringify(a) + ') end')
        if (scope.t) { scope.t.act = a; scope.t.actName = { work: 'Arbeit', avail: 'Bereitschaft', rest: 'Pause / Ruhe' }[a]; scope.t.actText = '0:00' }
      }
      // --- the simple face: the sentence, the bars, the two buttons ---
      scope.needBreak = function () { var t = scope.t; return !!t && t.driveLeft < 1800 }
      scope.say = function () {
        var t = scope.t, h = scope.h
        if (!t) { return { a: '', b: '' } }
        if (h.privateDrive) { return { a: 'Privatfahrt', b: 'Die Fahrzeit wird nicht gezählt. Mit einem Auftrag geht sie wieder an.', c: '' } }
        if (t.act === 'rest') { return { a: 'Pause läuft', b: t.restGoal ? 'Bleib stehen – Losfahren beendet die Pause.' : 'Losfahren beendet die Pause.', c: 'good' } }
        if (t.dayLeft <= 0) { return { a: 'Feierabend!', b: 'Für heute ist Schluss – such dir einen Rastplatz und schlaf.', c: 'bad' } }
        if (t.driveLeft <= 0) { return { a: 'Jetzt Pause machen!', b: 'Anhalten und auf „Pause machen“ drücken (45 Minuten).', c: 'bad' } }
        if (t.dayLeft <= t.driveLeft) { return { a: 'Noch ' + t.dayText + ' fahren', b: 'Danach ist Feierabend: schlafen an Rastplatz oder Hof.', c: t.dayLeft < 3600 ? 'warn' : '' } }
        return { a: 'Noch ' + t.driveText + ' fahren', b: 'Danach 45 Minuten Pause.', c: t.driveLeft < 1800 ? 'warn' : '' }
      }
      scope.drivePct = function () { var t = scope.t; return t ? Math.max(0, Math.min(100, t.driveLeft / FULL_DRIVE * 100)) : 0 }
      scope.driveCol = function () { var t = scope.t; return !t ? '#555' : (t.driveLeft <= 0 ? '#ff5b4d' : (t.driveLeft < 1800 ? '#ffd166' : '#5fb4ff')) }
      scope.fatCol = function () { return FAT[(scope.f && scope.f.level) || 1] }
      scope.pause = function () {
        if (scope.moving()) { return }
        scope.set(scope.t && scope.t.act === 'rest' ? 'work' : 'rest')
      }
      scope.sleep = function () { if (scope.h.canRest && !scope.moving()) { scope.lua('rest') } }
      // --- the explanation: a window on the page's body ---
      var win = null
      function fill() {
        if (!win || !win.classList.contains('on') || !scope.t) { return }
        var t = scope.t, rows = [
          ['Bis zur nächsten Pause', t.driveText], ['Heute noch fahren', t.dayText],
          ['Heute gefahren', t.dayDrivenText + ' von ' + (t.dayLimit / 3600) + ' h'], ['Diese Woche gefahren', t.weekDrivenText + ' von 56 h'],
          ['Müdigkeit', (scope.f ? scope.f.pct : 0) + ' %'], ['Verstöße (nicht kontrolliert)', t.violations || 0],
          ['Verlängerte 10-h-Tage übrig', t.extLeft + ' von 2'], ['Verkürzte Ruhezeiten übrig', t.redLeft + ' von 3']
        ]
        if (t.split) { rows.push(['Geteilte Pause', 'noch ' + t.breakText]) }
        win.querySelector('.me').innerHTML = rows.map(function (r) { return '<span>' + r[0] + '</span><b>' + r[1] + '</b>' }).join('')
      }
      function close() { if (win) { win.classList.remove('on') } }
      scope.help = function () {
        if (!win) {
          if (!document.getElementById('ffTachoHelpCss')) { var st = document.createElement('style'); st.id = 'ffTachoHelpCss'; st.textContent = HELP_CSS; document.head.appendChild(st) }
          var old = document.getElementById('ffTachoHelp'); if (old && old.parentNode) { old.parentNode.removeChild(old) }
          win = document.createElement('div'); win.id = 'ffTachoHelp'; win.innerHTML = HELP_HTML
          document.body.appendChild(win)
          win.querySelector('.x').onclick = close
          win.onclick = function (e) { if (e.target === win) { close() } }
        }
        win.classList.toggle('on')
        fill()
      }
      scope.$on('$destroy', function () { if (win && win.parentNode) { win.parentNode.removeChild(win) } win = null })
      scope.$on('FernfahrerHud', function (e, data) {
        scope.$evalAsync(function () { scope.h = data || { mode: false }; scope.t = scope.h.tacho || null; scope.f = scope.h.fatigue || null; fill() })
      })
      // (ng-bind-html: the icons are this file's own constants)
      for (var k in ICON) { trusted[k] = $sce.trustAsHtml(ICON[k]) }
    }
  }
}]);
