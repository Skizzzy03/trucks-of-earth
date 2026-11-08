// Trucks of Earth HUD: the drivetrain. Every differential of the player's vehicle (career.lua asks the vehicle's
// powertrain once a second and sends 'FernfahrerHud'.drive): open / locked, a click switches it (powertrain's own
// toggle). From the electrics stream: gear, parking brake, lights, hazard lights.
angular.module('beamng.apps')
.directive('fernfahrerAntrieb', [function () {
  var css =
    '.ffa{font-family:inherit;color:#eef1f5}' +
    '.ffa .c{background:rgba(14,17,22,.86);border:1px solid rgba(255,255,255,.1);border-radius:6px;padding:6px 8px;box-shadow:0 6px 22px rgba(0,0,0,.35)}' +
    '.ffa .hd{display:flex;align-items:center;gap:6px;font-size:10.5px;font-weight:800;letter-spacing:1px;color:#9aa4b2;text-transform:uppercase}' +
    '.ffa .gear{margin-left:auto;font:800 15px Consolas,monospace;color:#fff;background:#252c36;border-radius:4px;padding:0 7px;letter-spacing:0}' +
    '.ffa .d{display:flex;align-items:center;gap:5px;margin-top:4px;padding:3px 5px;border-radius:4px;background:#1a1f27;cursor:pointer;font-size:10.5px}' +
    '.ffa .d:hover{background:#232a34}.ffa .d.fix{cursor:default;opacity:.55}' +
    '.ffa .d .n{flex:1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}' +
    '.ffa .d .m{font-weight:800;font-size:10px;border-radius:3px;padding:1px 6px;background:#2a313b;color:#cfd6de}' +
    '.ffa .d .m.lk{background:#f5a623;color:#15100a}' +
    '.ffa .ind{display:flex;gap:4px;margin-top:6px}' +
    '.ffa .ind span{flex:1;text-align:center;font-size:10px;font-weight:800;border-radius:3px;padding:2px 0;background:#1a1f27;color:#5b6470}' +
    '.ffa .ind span.on{background:#3a2a0c;color:#ffb12e}.ffa .ind span.pb.on{background:#4a1d1a;color:#ff8a80}.ffa .ind span.lt.on{background:#14304a;color:#8fc8ff}' +
    '.ffa .mut{font-size:11px;color:#8b95a3;margin-top:5px}'
  return {
    template:
      '<div class="bngApp ffa" ng-show="h.mode" style="width:100%;height:100%;display:flex;flex-direction:column;justify-content:flex-end;background:transparent;box-shadow:none;">' +
      '<style>' + css + '</style>' +
      '<div class="c">' +
        '<div class="hd">Antrieb <span class="gear">{{ gear() }}</span></div>' +
        '<div ng-repeat="d in diffs() track by d.n" class="d" ng-class="{fix: !d.canSwitch}" ng-click="d.canSwitch && toggle(d.n)" title="{{ d.canSwitch ? \'Klicken zum Umschalten\' : \'nicht schaltbar\' }}">' +
          '<span class="n">{{ d.label }}</span><span class="m" ng-class="{lk: d.locked}">{{ d.modeText }}</span></div>' +
        '<div class="mut" ng-if="!diffs().length">Keine schaltbaren Differentiale.</div>' +
        '<div class="ind"><span class="pb" ng-class="{on: e.parkingbrake > 0.5}">P</span><span class="lt" ng-class="{on: e.lowbeam > 0.5}">Licht</span>' +
          '<span class="lt" ng-class="{on: e.highbeam > 0.5}">Fern</span><span ng-class="{on: e.hazard_enabled > 0.5}">Warn</span></div>' +
      '</div></div>',
    replace: true,
    link: function (scope) {
      'use strict'
      scope.h = { mode: false }
      scope.e = {}
      var MODES = { open: 'OFFEN', locked: 'GESPERRT', lsd: 'SPERRDIFF', viscous: 'VISKO', welded: 'VERSCHW.', dualClutch: 'KUPPLUNG', activeLock: 'AKTIV' }
      var NAMES = [
        [/interaxle|middle|center|centre|_m$|transfer/i, 'Längsdifferential'],
        [/rear|_r(_\d)?$/i, 'Hinterachse'],
        [/front|_f$/i, 'Vorderachse']
      ]
      function label(d) {
        for (var i = 0; i < NAMES.length; i++) { if (NAMES[i][0].test(d.n || '') || NAMES[i][0].test(d.u || '')) { return NAMES[i][1] + (/_(\d)$/.test(d.n) && d.n.match(/_(\d)$/)[1] !== '0' ? ' ' + (Number(d.n.match(/_(\d)$/)[1]) + 1) : '') } }
        return d.u || d.n
      }
      var list = []
      scope.diffs = function () { return list }
      function rebuild(drive) {
        var arr = drive && drive.diffs ? (Array.isArray(drive.diffs) ? drive.diffs : Object.keys(drive.diffs).map(function (k) { return drive.diffs[k] })) : []
        list = arr.map(function (d) {
          var modes = Array.isArray(d.a) ? d.a : (d.a ? Object.keys(d.a).map(function (k) { return d.a[k] }) : [])
          return { n: d.n, label: label(d), locked: d.m === 'locked' || d.m === 'welded', modeText: MODES[d.m] || String(d.m || '').toUpperCase(), canSwitch: modes.length > 1 }
        })
      }
      scope.gear = function () {
        var g = scope.e.gear
        if (g === undefined || g === null) { return '–' }
        if (typeof g === 'number') { return g === 0 ? 'N' : (g < 0 ? 'R' + (g < -1 ? -g : '') : String(g)) }
        return String(g)
      }
      scope.toggle = function (name) {
        bngApi.engineLua('if fernfahrer_career then fernfahrer_career.toggleDiff(' + JSON.stringify(name) + ') end')
      }
      var lastKey = ''
      var streams = ['electrics']
      StreamsManager.add(streams)
      scope.$on('$destroy', function () { StreamsManager.remove(streams) })
      scope.$on('streamsUpdate', function (ev, data) {
        var el = data && data.electrics
        if (!el) { return }
        // (only on a change: the stream comes every frame)
        var key = el.gear + '|' + el.parkingbrake + '|' + el.lowbeam + '|' + el.highbeam + '|' + el.hazard_enabled
        if (key === lastKey) { return }
        lastKey = key
        scope.$evalAsync(function () { scope.e = { gear: el.gear, parkingbrake: el.parkingbrake, lowbeam: el.lowbeam, highbeam: el.highbeam, hazard_enabled: el.hazard_enabled } })
      })
      scope.$on('FernfahrerHud', function (ev, data) { scope.$evalAsync(function () { scope.h = data || { mode: false }; rebuild(scope.h.drive) }) })
    }
  }
}]);
