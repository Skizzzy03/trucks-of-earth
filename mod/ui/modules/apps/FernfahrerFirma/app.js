// Trucks of Earth HUD: the company bar (name, account, level).
angular.module('beamng.apps')
.directive('fernfahrerFirma', [function () {
  return {
    template:
      '<div class="bngApp fffi" ng-show="h.mode" style="width:100%;height:100%;background:transparent;box-shadow:none;">' +
      '<style>' +
      '.fffi .c{display:flex;align-items:center;gap:10px;padding:8px 12px;background:rgba(14,17,22,.82);border:1px solid rgba(255,255,255,.09);border-radius:6px;color:#eef1f5;font-family:inherit}' +
      '.fffi .n{font-weight:800;font-size:13px;color:#f5a623;text-transform:uppercase;letter-spacing:1px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:170px}' +
      '.fffi .t{font-size:13px;font-weight:700;color:#cfd6de;font-variant-numeric:tabular-nums}.fffi .m{margin-left:auto;font-size:16px;font-weight:800;font-variant-numeric:tabular-nums}' +
      '.fffi .l{background:#f5a623;color:#1a1205;font-weight:800;font-size:11px;border-radius:5px;padding:1px 6px}' +
      '.fffi .x{height:3px;background:rgba(255,255,255,.08);border-radius:2px;margin-top:4px;overflow:hidden}.fffi .x i{display:block;height:100%;background:#f5a623}' +
      '</style>' +
      '<div class="c"><span class="n">{{ h.company }}</span><span class="l">LV {{ h.level }}</span><span class="t" ng-if="h.clock">{{ h.clock }}</span><span class="m">{{ money(h.money) }}</span></div>' +
      '<div class="x"><i ng-style="{width: (xp() * 100) + \'%\'}"></i></div>' +
      '</div>',
    replace: true,
    link: function (scope) {
      'use strict'
      scope.h = { mode: false }
      scope.money = function (v) {
        if (v === undefined || v === null) { return '–' }
        return (v < 0 ? '−' : '') + Math.round(Math.abs(v)).toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.') + ' €'
      }
      scope.xp = function () {
        var h = scope.h
        if (!h || !(h.xpTo > h.xpFrom)) { return 0 }
        return Math.max(0, Math.min(1, (h.xp - h.xpFrom) / (h.xpTo - h.xpFrom)))
      }
      scope.$on('FernfahrerHud', function (e, data) { scope.$evalAsync(function () { scope.h = data || { mode: false } }) })
    }
  }
}]);
