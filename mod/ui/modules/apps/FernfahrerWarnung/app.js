// Trucks of Earth HUD: road event warnings (events.lua via 'FernfahrerHud'): a warning sign for roadworks /
// speed camera / police check ahead with the distance and the zone's limit, a white flash when a camera fires, and
// the last fine.
angular.module('beamng.apps')
.directive('fernfahrerWarnung', [function () {
  var css =
    '.ffw{font-family:inherit;color:#eef1f5;pointer-events:none}' +
    // (the accident / roadworks box over the middle of the screen: never catches the mouse – looking around goes on)
    '.ffw,.ffw *{pointer-events:none!important}' +
    '.ffw .box{display:flex;align-items:center;gap:12px;background:rgba(14,17,22,.88);border:1px solid rgba(255,177,46,.5);border-radius:6px;padding:8px 14px;box-shadow:0 6px 24px rgba(0,0,0,.4);animation:ffwIn .35s ease-out}' +
    '.ffw .tri{flex:none;width:0;height:0;border-left:30px solid transparent;border-right:30px solid transparent;border-bottom:52px solid #d3201f;position:relative}' +
    '.ffw .tri:after{content:"";position:absolute;left:-22px;top:9px;border-left:22px solid transparent;border-right:22px solid transparent;border-bottom:38px solid #fff}' +
    '.ffw .tri span{position:absolute;left:-4px;top:19px;z-index:1;font:900 20px Arial,sans-serif;color:#111}' +
    '.ffw .lim{flex:none;width:52px;height:52px;border-radius:50%;background:#fff;border:6px solid #d3201f;box-sizing:border-box;display:flex;align-items:center;justify-content:center;color:#111;font:800 18px Arial,sans-serif}' +
    '.ffw .t{font-weight:800;font-size:15px}.ffw .s{font-size:12px;color:#9aa4b2}' +
    '.ffw .in{border-color:#ffb12e;background:rgba(60,40,6,.9)}' +
    '.ffw .fine{margin-top:6px;background:rgba(120,20,16,.92);border:1px solid #ff6b5e;border-radius:4px;padding:7px 12px;font-size:13px;font-weight:700}' +
    '.ffw .flash{position:fixed;inset:0;background:#fff;opacity:.85;animation:ffwFlash .9s ease-out forwards;z-index:9999}' +
    '.ffw .acc{margin-top:6px;border-color:rgba(70,140,255,.6)}' +
    '.ffw .blue{flex:none;width:18px;height:18px;border-radius:50%;background:#2f7bff;box-shadow:0 0 12px #2f7bff;animation:ffwBlue .5s steps(2) infinite}' +
    '@keyframes ffwBlue{50%{opacity:.25}}' +
    '@keyframes ffwIn{from{opacity:0;transform:translateY(-8px)}to{opacity:1;transform:none}}' +
    '@keyframes ffwFlash{from{opacity:.9}to{opacity:0}}'
  return {
    template:
      '<div class="bngApp ffw" ng-show="h.mode" style="width:100%;height:100%;background:transparent;box-shadow:none;overflow:visible;">' +
      '<style>' + css + '</style>' +
      '<div class="flash" ng-if="h.flash"></div>' +
      // (2026-11-05: only what asks something of the driver here – an emergency vehicle from behind, a police check;
      // roadworks, cameras, a broken-down car show in the route advisor's warner instead)
      '<div class="box" ng-if="h.event && (h.event.kind === \'siren\' || h.event.kind === \'control\')" ng-class="{in: h.event.inZone}">' +
        '<div class="tri" ng-if="h.event.kind !== \'siren\'"><span>!</span></div><div class="blue" ng-if="h.event.kind === \'siren\'"></div>' +
        '<div><div class="t">{{ h.event.title }}{{ h.event.inZone ? \'\' : \' in \' + dist(h.event.dist) }}</div>' +
        '<div class="s" ng-if="h.event.kind === \'roadworks\'">{{ h.event.inZone ? \'Du bist in der Baustelle\' : \'Tempo reduzieren\' }}{{ h.event.radar ? \' · Blitzer möglich\' : \'\' }}</div>' +
        '<div class="s" ng-if="h.event.kind === \'control\'">Rechts ranfahren und anhalten</div>' +
        '<div class="s" ng-if="h.event.kind === \'radar\'">Geschwindigkeit prüfen</div>' +
        '<div class="s" ng-if="h.event.sub">{{ h.event.sub }}</div></div>' +
        '<div class="lim" ng-if="h.event.limit">{{ h.event.limit }}</div>' +
      '</div>' +
      '<div class="box acc" ng-if="h.accident && !h.accident.ask"><div class="blue"></div><div><div class="t">Unfallstelle</div><div class="s">{{ h.accident.text }}</div></div></div>' +
      '<div class="fine" ng-if="h.lastFine">Bußgeld {{ money(h.lastFine.amount) }} · {{ h.lastFine.reason }}</div>' +
      '</div>',
    replace: true,
    link: function (scope) {
      'use strict'
      scope.h = { mode: false }
      scope.dist = function (m) { return m >= 1000 ? (m / 1000).toFixed(1).replace('.', ',') + ' km' : (Math.round(m / 50) * 50) + ' m' }
      scope.money = function (v) { return Math.round(v).toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.') + ' €' }
      scope.$on('FernfahrerHud', function (e, data) { scope.$evalAsync(function () { scope.h = data || { mode: false } }) })
    }
  }
}]);
