// Trucks of Earth HUD: the cab. Three buttons – a beer, a cigarette, a joint (career.lua vice → vices.lua plays
// the scene in front of the driver's camera) – and what is in the blood ('FernfahrerHud'.vices: ‰, THC). The scene's
// sounds come as 'FernfahrerSound' and are made here (Web Audio: noise and tones, nothing to download).
angular.module('beamng.apps')
.directive('fernfahrerKabine', [function () {
  var css =
    '.ffk{font-family:inherit;color:#eef1f5}' +
    '.ffk .c{pointer-events:auto;background:rgba(14,17,22,.86);border:1px solid rgba(255,255,255,.1);border-radius:6px;padding:5px 7px;box-shadow:0 6px 22px rgba(0,0,0,.35)}' +
    '.ffk .hd{display:flex;align-items:center;gap:6px;font-size:10.5px;font-weight:800;letter-spacing:1px;color:#9aa4b2;text-transform:uppercase}' +
    '.ffk .hd .v{margin-left:auto;letter-spacing:0;text-transform:none;font:800 11px Consolas,monospace;color:#cfd6de}' +
    '.ffk .hd .v.warn{color:#ffb12e}.ffk .hd .v.bad{color:#ff6b5e}' +
    '.ffk .b{display:flex;flex-wrap:wrap;gap:4px;margin-top:4px}' +
    '.ffk .b a{flex:1 1 30px;min-width:30px;text-align:center;padding:3px 0;border-radius:4px;background:#1a1f27;cursor:pointer;font-size:9px;font-weight:700;color:#cfd6de;line-height:1.15;white-space:nowrap}' +
    '.ffk .b a i{display:block;font-style:normal;font-size:14px}' +
    '.ffk .b a b{font:800 10px Consolas,monospace;color:#9aa4b2;margin-left:2px}' +
    '.ffk .g a{flex:1 1 56px}' +
    '.ffk .b a:hover{background:#232a34}.ffk .b a.on{background:#3a2a0c;color:#ffb12e}.ffk .b a.off{opacity:.45;cursor:default}'
  return {
    template:
      '<div class="bngApp ffk" ng-show="h.mode" style="width:100%;height:100%;box-sizing:border-box;display:flex;flex-direction:column;justify-content:flex-end;background:transparent;box-shadow:none;pointer-events:none;">' +
      '<style>' + css + '</style>' +
      '<div class="c">' +
        '<div class="hd">Kabine <span class="v" ng-class="bacClass()" title="Blutalkohol">{{ bacText() }}</span>' +
          '<span class="v" ng-if="v.thc >= 0.5" ng-class="{bad: v.thc >= 3.5, warn: v.thc < 3.5}" title="THC im Blut (Grenzwert 3,5 ng/ml)">THC {{ thcText() }}</span></div>' +
        '<div class="b">' +
          '<a ng-click="go(\'beer\')" ng-class="{on: v.busy === \'beer\', off: (v.busy && v.busy !== \'beer\') || !n(\'beer\')}" title="Eine Dose Bier (0,33 l) – Nachschub an der Tankstelle"><i>🍺 <b>{{ n(\'beer\') }}</b></i>Bier</a>' +
          '<a ng-click="go(\'cigarette\')" ng-class="{on: v.busy === \'cigarette\', off: (v.busy && v.busy !== \'cigarette\') || !n(\'cigarette\')}" title="Eine Zigarette – Schachteln an der Tankstelle"><i>🚬 <b>{{ n(\'cigarette\') }}</b></i>Kippe</a>' +
          '<a ng-click="go(\'joint\')" ng-class="{on: v.busy === \'joint\', off: (v.busy && v.busy !== \'joint\') || !n(\'joint\')}" title="Ein Joint – THC bleibt stundenlang nachweisbar. Manche Tankstellen haben einen Hinterausgang …"><i>🌿 <b>{{ n(\'joint\') }}</b></i>Joint</a>' +
          '<a ng-click="go(\'coffee\')" ng-class="{on: v.busy === \'coffee\', off: (v.busy && v.busy !== \'coffee\') || !n(\'coffee\')}" title="Kaffee to go – macht wach (Müdigkeit −20 %). Nachschub an der Tankstelle"><i>☕ <b>{{ n(\'coffee\') }}</b></i>Kaffee</a>' +
          '<a ng-click="go(\'energy\')" ng-class="{on: v.busy === \'energy\', off: (v.busy && v.busy !== \'energy\') || !n(\'energy\')}" title="Energydrink – kurz wach (Müdigkeit −12 %). Nachschub an der Tankstelle"><i>🥤 <b>{{ n(\'energy\') }}</b></i>Energy</a>' +
        '</div>' +
        '<div class="b g" ng-if="h.gadgets && h.gadgets.length"><a ng-repeat="g in h.gadgets track by g.id" ng-click="gadget(g.id)" ng-class="{on: g.on, off: g.wait}" title="{{ g.label }}"><i>{{ g.icon }}</i>{{ g.wait ? g.wait + \' s\' : g.label }}</a></div>' +
      '</div></div>',
    replace: true,
    link: function (scope, el) {
      'use strict'
      // (the frame is the game's and takes the mouse; here it is much bigger than the card, and the view has to stay turnable through it)
      // (2026-11-10: at this moment the app is not in the page yet, there was no frame to find: the cab's took every click meant for the tachograph under it. Looked for until it is there)
      var freeFrame = function () {
        var host = el[0].parentElement
        while (host && !host.classList.contains('ui-app-host')) { host = host.parentElement }
        if (!host) { return false }
        for (var x = el[0].parentElement; x; x = x.parentElement) { x.style.pointerEvents = 'none'; if (x === host) { break } }
        return true
      }
      if (!freeFrame()) {
        var frameT = setInterval(function () { if (freeFrame()) { clearInterval(frameT) } }, 200)
        scope.$on('$destroy', function () { clearInterval(frameT) })
      }
      scope.h = { mode: false }
      scope.v = {}
      // (2026-11-09: stands right on the app below it, however high that one is at the moment; its own frame is high enough for all there can be, so nothing is cut off)
      var below = -1, stackT = setInterval(function () {
        var o = document.querySelector('.fft .c'), h = o && o.offsetHeight ? o.offsetHeight + 4 : 230
        if (h !== below) { below = h; el[0].style.paddingBottom = h + 'px' }
      }, 300)
      scope.$on('$destroy', function () { clearInterval(stackT) })
      var de = function (x, d) { return x.toFixed(d).replace('.', ',') }
      scope.bacText = function () { var b = scope.v.bac || 0; return de(b, 2) + ' ‰' + (scope.v.rising ? ' ↑' : '') }
      scope.bacClass = function () { var b = scope.v.bac || 0; return b >= 0.5 ? 'bad' : (b >= 0.1 ? 'warn' : '') }
      scope.thcText = function () { return de(scope.v.thc || 0, 1) }
      // (2026-11-07) what is in the cab: bought at fuel stations (career.lua L.inv)
      scope.n = function (k) { return (scope.h.inv && scope.h.inv[k]) || 0 }
      scope.go = function (kind) {
        if (scope.v.busy) { return }
        unlock()
        bngApi.engineLua('if fernfahrer_career then fernfahrer_career.vice(' + JSON.stringify(kind) + ') end')
      }
      scope.gadget = function (id) { bngApi.engineLua('if fernfahrer_career then fernfahrer_career.useGadget(' + JSON.stringify(id) + ') end') }
      scope.$on('FernfahrerHud', function (ev, data) {
        scope.$evalAsync(function () { scope.h = data || { mode: false }; scope.v = (data && data.vices) || {} })
      })
      // (the radio has its own app now: FernfahrerRadio)
      // --- the sounds ---------------------------------------------------------------------------------------------
      var ac = null
      function unlock() {
        try {
          if (!ac) { ac = new (window.AudioContext || window.webkitAudioContext)() }
          if (ac.state === 'suspended') { ac.resume() }
        } catch (e) { ac = null }
      }
      function noise(dur) {
        var len = Math.max(1, Math.floor(ac.sampleRate * dur)), buf = ac.createBuffer(1, len, ac.sampleRate), d = buf.getChannelData(0)
        for (var i = 0; i < len; i++) { d[i] = Math.random() * 2 - 1 }
        var s = ac.createBufferSource(); s.buffer = buf; return s
      }
      // a noise burst through a filter, with an envelope: [time, gain] points
      function hiss(type, freq, q, env, at) {
        var t0 = ac.currentTime + (at || 0), dur = env[env.length - 1][0]
        var s = noise(dur + 0.05), f = ac.createBiquadFilter(), g = ac.createGain()
        f.type = type; f.frequency.value = freq; f.Q.value = q || 0.8
        g.gain.setValueAtTime(0.0001, t0)
        env.forEach(function (p) { g.gain.linearRampToValueAtTime(p[1], t0 + p[0]) })
        s.connect(f); f.connect(g); g.connect(ac.destination)
        s.start(t0); s.stop(t0 + dur + 0.05)
        return f
      }
      function tone(type, f0, f1, dur, vol, at) {
        var t0 = ac.currentTime + (at || 0), o = ac.createOscillator(), g = ac.createGain()
        o.type = type; o.frequency.setValueAtTime(f0, t0); o.frequency.exponentialRampToValueAtTime(f1, t0 + dur)
        g.gain.setValueAtTime(vol, t0); g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur)
        o.connect(g); g.connect(ac.destination); o.start(t0); o.stop(t0 + dur + 0.02)
      }
      var SOUNDS = {
        // a crash (career.lua crashHit, with the slow motion): a dull thump through the body, then the ringing in the
        // ears – two close high tones beating against each other, swelling in and fading away over a few seconds
        tinnitus: function (d) {
          var k = Math.max(0.35, Math.min(1, (d && d.strength) || 0.6))
          tone('sine', 75, 32, 0.7, 0.55 * k)
          hiss('lowpass', 260, 0.7, [[0.01, 0.5 * k], [0.25, 0.2 * k], [0.9, 0.0001]])
          var t0 = ac.currentTime
          ;[[4120, 1], [4185, 0.6], [8240, 0.12]].forEach(function (p) {
            var o = ac.createOscillator(), g = ac.createGain()
            o.type = 'sine'; o.frequency.value = p[0]
            g.gain.setValueAtTime(0.0001, t0)
            g.gain.linearRampToValueAtTime(0.055 * k * p[1], t0 + 0.25)
            // (as long as the slow motion: loud while it is nearly still, a little softer in the rush, fading as
            // real time comes back – ~7 s)
            g.gain.setValueAtTime(0.055 * k * p[1], t0 + 1.4)
            g.gain.linearRampToValueAtTime(0.035 * k * p[1], t0 + 2.3)
            g.gain.linearRampToValueAtTime(0.05 * k * p[1], t0 + 2.8)
            g.gain.setValueAtTime(0.05 * k * p[1], t0 + 4.6)
            g.gain.exponentialRampToValueAtTime(0.0001, t0 + 7.2)
            o.connect(g); g.connect(ac.destination); o.start(t0); o.stop(t0 + 7.3)
          })
          hiss('bandpass', 6000, 3, [[0.3, 0.025 * k], [4.6, 0.02 * k], [6.8, 0.0001]])
        },
        // the ring pull: a metal click, then the gas out of the can
        pssst: function () {
          tone('square', 2400, 1800, 0.025, 0.05)
          var f = hiss('bandpass', 5200, 1.2, [[0.01, 0.5], [0.12, 0.32], [0.45, 0.0001]], 0.02)
          f.frequency.setValueAtTime(5200, ac.currentTime + 0.02); f.frequency.linearRampToValueAtTime(3600, ac.currentTime + 0.45)
        },
        // the lane warner (2026-11-08)
        lane: function () { tone('sine', 660, 620, 0.17, 0.02); tone('sine', 520, 490, 0.2, 0.017, 0.2) },
        // the CB radio's squelch: a burst of static, then a click (2026-11-08)
        cb: function () { hiss('bandpass', 2600, 0.8, [[0.02, 0.1], [0.3, 0.07], [0.5, 0.0001]]); tone('square', 900, 700, 0.03, 0.03, 0.5) },
        gulp: function () { tone('sine', 190, 90, 0.11, 0.35); tone('sine', 170, 80, 0.12, 0.3, 0.42) },
        // the lighter's wheel and the flame catching
        click: function () { hiss('highpass', 3000, 0.7, [[0.004, 0.6], [0.04, 0.0001]]); tone('triangle', 3400, 2600, 0.05, 0.06, 0.01) },
        flame: function () { hiss('lowpass', 700, 0.7, [[0.08, 0.28], [0.9, 0.18], [1.3, 0.0001]]) },
        // a drag (in) and the smoke out
        puff: function () {
          hiss('bandpass', 1300, 0.9, [[0.3, 0.12], [0.9, 0.0001]])
          hiss('bandpass', 700, 0.7, [[0.2, 0.16], [1.3, 0.0001]], 1.5)
        }
      }
      scope.$on('FernfahrerSound', function (ev, data) {
        var fn = data && SOUNDS[data.name]
        if (!fn) { return }
        unlock()
        if (!ac) { return }
        try { fn(data) } catch (e) {}
      })
    }
  }
}]);
