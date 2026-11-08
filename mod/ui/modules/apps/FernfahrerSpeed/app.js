// Trucks of Earth HUD: speed and the posted speed limit (BeamNG.Earth road graph, OSM maxspeed) as a road sign.
angular.module('beamng.apps')
.directive('fernfahrerSpeed', [function () {
  return {
    template:
      '<div class="bngApp ffs" ng-show="h.mode" style="width:100%;height:100%;background:transparent;box-shadow:none;">' +
      '<style>' +
      '.ffs .c{display:flex;align-items:center;gap:12px;height:100%;padding:8px 12px;background:rgba(14,17,22,.82);border:1px solid rgba(255,255,255,.09);border-radius:12px;color:#eef1f5;font-family:inherit;box-sizing:border-box}' +
      '.ffs .sign{flex:none;width:72px;height:72px;border-radius:50%;background:#fff;border:8px solid #d3201f;box-sizing:border-box;display:flex;align-items:center;justify-content:center;color:#111;font-weight:800;font-size:26px;letter-spacing:-1px;font-family:Arial,Helvetica,sans-serif}' +
      '.ffs .sign.none{border-color:#6f7a88;color:#6f7a88;font-size:20px;background:#e8ebee}' +
      '.ffs .sp{display:flex;flex-direction:column;line-height:1}.ffs .sp b{font-size:44px;font-variant-numeric:tabular-nums;font-weight:800}' +
      '.ffs .sp span{font-size:11px;color:#9aa4b2;text-transform:uppercase;letter-spacing:1px;margin-top:3px}' +
      '.ffs .over b{color:#ff6b5e;animation:ffsBlink .8s steps(2) infinite}@keyframes ffsBlink{50%{opacity:.35}}' +
      '</style>' +
      '<div class="c">' +
        '<div class="sign" ng-class="{none: !h.limit}">{{ h.limit || \'–\' }}</div>' +
        '<div class="sp" ng-class="{over: over()}"><b>{{ speed() }}</b><span>km/h{{ h.limit ? \'\' : \' · kein Limit bekannt\' }}</span></div>' +
      '</div></div>',
    replace: true,
    link: function (scope) {
      'use strict'
      scope.h = { mode: false }
      scope.ws = null
      var streams = ['electrics']                 // the vehicle's own speed (as the stock speedometers read it)
      StreamsManager.add(streams)
      scope.$on('$destroy', function () { StreamsManager.remove(streams) })
      scope.$on('streamsUpdate', function (e, data) {
        if (data && data.electrics) { scope.$evalAsync(function () { scope.ws = data.electrics.wheelspeed }) }
      })
      scope.speed = function () { return Math.round(Math.abs(scope.ws !== null && scope.ws !== undefined ? scope.ws * 3.6 : (scope.h.speed || 0))) }
      scope.over = function () { return scope.h.speedWarn && scope.h.limit && (scope.h.speed || 0) > scope.h.limit + 3 }
      scope.$on('FernfahrerHud', function (e, data) { scope.$evalAsync(function () { scope.h = data || { mode: false } }) })
    }
  }
}]);
