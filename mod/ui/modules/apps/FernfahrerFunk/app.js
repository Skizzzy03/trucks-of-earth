// Trucks of Earth HUD: the dispatcher's radio messages (career.lua story / message), shown for a few seconds.
angular.module('beamng.apps')
.directive('fernfahrerFunk', [function () {
  return {
    template:
      '<div class="bngApp fff" style="width:100%;height:100%;background:transparent;box-shadow:none;overflow:visible;">' +
      '<style>' +
      '.fff .t{border-left:3px solid #f5a623;padding:9px 14px;background:rgba(14,17,22,.88);border-radius:0 4px 4px 0;color:#eef1f5;font-size:13.5px;line-height:1.4;font-family:inherit;box-shadow:0 6px 24px rgba(0,0,0,.35);animation:fffIn .4s ease-out}' +
      '.fff .f{color:#f5a623;font-weight:800;font-size:10.5px;letter-spacing:.12em;margin-bottom:2px}' +
      '@keyframes fffIn{from{opacity:0;transform:translateY(-8px)}to{opacity:1;transform:none}}' +
      '</style>' +
      '<div class="t" ng-if="h.mode && h.toast" ng-attr-data-id="{{ h.toast.id }}"><div class="f">FUNK · {{ h.toast.from }}</div>{{ h.toast.text }}</div>' +
      '</div>',
    replace: true,
    link: function (scope) {
      'use strict'
      scope.h = { mode: false }
      scope.$on('FernfahrerHud', function (e, data) { scope.$evalAsync(function () { scope.h = data || { mode: false } }) })
    }
  }
}]);
