// Trucks of Earth HUD: the cruise control (the vehicle's own extensions.cruiseControl), 2026-11-08. SET holds the
// speed driven now, RES goes back to the last set speed, -10 -5 +5 +10 change it, OFF lets go. The state comes from the
// game's 'CruiseControlState'; below it the driver assistance bought in the workshop, each switchable.
angular.module('beamng.apps')
.directive('fernfahrerTempomat', [function () {
  var css =
    '.fftm{font-family:inherit;color:#eef1f5;height:100%;display:flex;flex-direction:column;justify-content:flex-end;pointer-events:none}' +
    '.fftm .ab{align-self:center;padding:0 4px;border-radius:3px;background:#d6322b;color:#fff;font-size:8.5px;letter-spacing:.3px;line-height:13px}' +
    '.fftm .c{pointer-events:auto;background:rgba(14,17,22,.9);border:1px solid rgba(255,255,255,.1);border-radius:6px;padding:5px 7px;box-shadow:0 6px 22px rgba(0,0,0,.35)}' +
    '.fftm .hd{display:flex;align-items:baseline;gap:6px;font-size:10px;font-weight:800;letter-spacing:.6px;color:#9aa4b2;text-transform:uppercase}' +
    '.fftm .v{margin-left:auto;font:800 16px Consolas,monospace;color:#6f7a88;letter-spacing:0;text-transform:none}.fftm .v small{font-size:10px;font-weight:700;margin-left:3px}' +
    '.fftm .v.on{color:#7fe3a4}' +
    '.fftm .r{display:flex;gap:3px;margin-top:3px}' +
    '.fftm .r a{flex:1;text-align:center;padding:3px 0;border-radius:4px;background:#1f2630;color:#cfd6de;cursor:pointer;font:800 10.5px Consolas,monospace}' +
    '.fftm .r a:hover{background:#2a3340;color:#fff}.fftm .r a.go{background:#2fbf71;color:#08210f}.fftm .r a.go:hover{background:#3ad38b}.fftm .r a.off{opacity:.4;cursor:default}' +
    '.fftm .as{display:flex;gap:3px;margin-top:3px}' +
    '.fftm .as a{flex:1;text-align:center;padding:1px 0;border-radius:4px;background:#1a1f27;color:#6f7a88;cursor:pointer;font-size:12px;border:1px solid transparent}' +
    '.fftm .as a.on{color:#fff;border-color:#2fbf71;background:#19301f}'
  return {
    template:
      '<div class="bngApp fftm" ng-show="h.mode" style="background:transparent;box-shadow:none;">' +
      '<style>' + css + '</style>' +
      '<div class="c">' +
        '<div class="hd">Tempomat<span class="ab" ng-show="h.accBusy" title="Die Abstandsautomatik regelt gerade">Abstand</span><span class="v" ng-class="{on: on}">{{ on ? shown() : "–" }}<small>km/h</small></span></div>' +
        '<div class="r"><a class="" ng-class="{go: !on}" ng-click="set()" title="Aktuelle Geschwindigkeit halten">SET</a>' +
          '<a ng-class="{off: !last}" ng-click="res()" title="Letzte Geschwindigkeit wieder aufnehmen">RES</a>' +
          '<a ng-class="{off: !on}" ng-click="off()" title="Tempomat aus">AUS</a></div>' +
        '<div class="r"><a ng-click="step(-10)">−10</a><a ng-click="step(-5)">−5</a><a ng-click="step(5)">+5</a><a ng-click="step(10)">+10</a></div>' +
        '<div class="as" ng-if="h.assist"><a ng-repeat="k in order" ng-if="h.assist[k]" ng-class="{on: h.assist[k].on}" ng-click="toggle(k)" title="{{ h.assist[k].name }} an/aus">{{ h.assist[k].icon }}</a></div>' +
      '</div></div>',
    replace: true,
    link: function (scope, el) {
      'use strict'
      // (2026-11-09: red and blinking while the distance control holds the truck back. Set by hand: CSS animations stand still in the game's browser)
      var blink = false, blinkT = setInterval(function () {
        blink = !blink
        var c = el[0].querySelector('.ab'), card = el[0].querySelector('.c')
        if (c) { c.style.opacity = blink ? '1' : '.25' }
        if (card) { card.style.borderColor = (scope.h && scope.h.accBusy && blink) ? '#ff4a3d' : '' }
      }, 380)
      scope.$on('$destroy', function () { clearInterval(blinkT) })
      // (the frame in the layout has room for the row of driver assistance; the content stands at its bottom)
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
      scope.on = false
      scope.last = null
      scope.target = 0                     // m/s
      scope.order = ['acc', 'lka', 'ldw']
      var LOAD = 'extensions.load("cruiseControl") '
      function veh(cmd) { bngApi.activeObjectLua(LOAD + cmd) }
      scope.shown = function () { return Math.round(scope.target * 3.6) }
      scope.set = function () { veh('extensions.cruiseControl.holdCurrentSpeed()') }
      scope.res = function () { if (scope.last) { veh('extensions.cruiseControl.setSpeed(' + scope.last + ')') } }
      scope.off = function () { veh('extensions.cruiseControl.setEnabled(false)') }
      scope.step = function (d) {
        // (from the set speed when it is on, else from the speed driven; on a round number)
        var base = scope.on ? scope.target * 3.6 : (scope.h.speed || 0)
        var kmh = Math.max(30, Math.round(base / 5) * 5 + d)
        veh('extensions.cruiseControl.setSpeed(' + (kmh / 3.6).toFixed(3) + ')')
      }
      scope.toggle = function (k) { bngApi.engineLua('if fernfahrer_career then fernfahrer_career.assistToggle(' + JSON.stringify(k) + ') end') }
      scope.$on('CruiseControlState', function (e, s) {
        scope.$evalAsync(function () {
          if (!s) { return }
          scope.on = !!s.isEnabled
          if (s.targetSpeed) { scope.target = s.targetSpeed; if (s.isEnabled) { scope.last = s.targetSpeed } }
        })
      })
      scope.$on('FernfahrerHud', function (e, data) { scope.$evalAsync(function () { scope.h = data || { mode: false } }) })
      // (the state once a second: a vehicle changed, the brake let it go)
      var t = setInterval(function () { if (scope.h && scope.h.mode) { veh('extensions.cruiseControl.requestState()') } }, 1000)
      scope.$on('$destroy', function () { clearInterval(t) })
    }
  }
}]);
