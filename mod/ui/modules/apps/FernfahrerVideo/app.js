// Trucks of Earth HUD: a video window over the game (2026-11-04). A YouTube link (embedded player) or a direct
// video link (.mp4/.webm). The window is moved by its top bar, sized at the corner, tilted in 3D (to lie on the
// dashboard), made see-through, full screen, click-through; or the video goes to the truck's navigation screen
// (career.lua videoToScreen). The settings panel opens from the cockpit strip's 📺 (event 'ffVideoPanel') or the
// window's ⚙. Everything is kept in this browser (localStorage). The app covers the screen with pointer-events: none;
// only the window and the panel take the mouse.
angular.module('beamng.apps')
.directive('fernfahrerVideo', ['$sce', function ($sce) {
  var css =
    '.ffv{position:absolute;inset:0;pointer-events:none;font-family:inherit;color:#e9edf2}' +
    '.ffv .stage{position:absolute;inset:0;perspective:1400px}' +
    '.ffv .win{position:absolute;pointer-events:auto;background:#000;border-radius:8px;box-shadow:0 12px 40px rgba(0,0,0,.55);overflow:visible;transform-origin:50% 60%}' +
    '.ffv .win.full{inset:0 !important;width:auto !important;height:auto !important;border-radius:0;transform:none !important}' +
    '.ffv .win iframe,.ffv .win video{position:absolute;inset:0;width:100%;height:100%;border:0;border-radius:inherit;background:#000;object-fit:contain}' +
    '.ffv .win.through iframe,.ffv .win.through video{pointer-events:none}' +
    '.ffv .bar{position:absolute;left:0;right:0;top:-26px;height:24px;display:flex;align-items:center;gap:4px;padding:0 6px;border-radius:6px 6px 0 0;' +
      'background:rgba(14,17,22,.88);cursor:move;opacity:0;transition:opacity .2s;font-size:11px;user-select:none}' +
    '.ffv .win:hover .bar,.ffv .win.drag .bar{opacity:1}.ffv .win.full .bar{top:0;border-radius:0;z-index:2}' +
    '.ffv .bar b{flex:1;font-weight:700;color:#cfd6de;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}' +
    '.ffv .bar a{cursor:pointer;padding:0 5px;color:#cfd6de}.ffv .bar a:hover{color:#f5a623}' +
    '.ffv .grip{position:absolute;right:-6px;bottom:-6px;width:16px;height:16px;cursor:nwse-resize;border-right:3px solid #f5a623;border-bottom:3px solid #f5a623;opacity:0;transition:opacity .2s}' +
    '.ffv .win:hover .grip{opacity:.9}.ffv .win.full .grip{display:none}' +
    '.ffv .pnl{position:absolute;left:56px;top:140px;width:290px;pointer-events:auto;background:rgba(14,17,22,.95);border:1px solid rgba(255,255,255,.12);' +
      'border-radius:8px;padding:10px 12px;box-shadow:0 10px 30px rgba(0,0,0,.45);font-size:12px}' +
    '.ffv .pnl .hd{display:flex;align-items:center;font-size:10.5px;font-weight:800;letter-spacing:1px;color:#9aa4b2;text-transform:uppercase;margin-bottom:8px}' +
    '.ffv .pnl .hd a{margin-left:auto;cursor:pointer;font-size:14px;color:#8b95a3}' +
    '.ffv .pnl input[type=text]{width:100%;box-sizing:border-box;background:#0d1015;border:1px solid #2f3742;color:#e9edf2;border-radius:5px;padding:6px 8px;font-size:12px}' +
    '.ffv .pnl .row{display:flex;gap:5px;margin-top:6px}' +
    '.ffv .pnl .btn{flex:1;background:#1f252e;border:1px solid #2f3742;color:#e9edf2;border-radius:5px;padding:5px;font-size:11.5px;font-weight:700;cursor:pointer}' +
    '.ffv .pnl .btn:hover{border-color:#f5a623}.ffv .pnl .btn.on{background:#f5a623;color:#15100a;border-color:#f5a623}' +
    '.ffv .pnl .sl{display:grid;grid-template-columns:86px 1fr 38px;align-items:center;gap:6px;margin-top:6px}' +
    '.ffv .pnl .sl span:last-child{text-align:right;font:700 11px Consolas,monospace;color:#cfd6de}' +
    '.ffv .win .wait{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:8px;color:#cfd6de;font-size:12.5px;text-align:center;padding:12px}' +
    '.ffv .win .wait b{width:46px;height:46px;border-radius:50%;background:#c4302b;color:#fff;display:flex;align-items:center;justify-content:center;font-size:18px;animation:ffvP 1.2s ease-in-out infinite}' +
    '@keyframes ffvP{50%{opacity:.45}}' +
    '.ffv .win .badge{position:absolute;left:8px;top:8px;padding:1px 6px;border-radius:4px;background:#c4302b;color:#fff;font:700 10.5px sans-serif;font-style:normal;pointer-events:none;letter-spacing:.5px}' +
    '.ffv .pnl .mut{margin-top:8px;color:#8b95a3;font-size:11px;line-height:1.35}.ffv .pnl .msg{margin-top:6px;color:#a6efc0}.ffv .pnl .msg.bad{color:#ff8a80}'
  return {
    template:
      '<div class="ffv" ng-show="h.mode">' +
      '<style>' + css + '</style>' +
      '<div class="stage">' +
        // (the window or the truck's screen – never both: on the screen the window is gone)
        '<div class="win" ng-if="cfg.src && cfg.show && out === \'window\'" ng-class="{full: cfg.full, through: cfg.through, drag: dragging}" ng-style="winStyle()">' +
          '<div class="bar"><b>{{ title() }}</b>' +
            '<a ng-click="cfg.full = !cfg.full; keep()" title="Vollbild an/aus">{{ cfg.full ? "▢" : "⛶" }}</a>' +
            '<a ng-click="togglePanel()" title="Einstellungen">⚙</a>' +
            '<a ng-click="cfg.show = false; keep()" title="Ausblenden">✕</a></div>' +
          // (YouTube: its embedded player refuses the game's local:// pages – "Error 153"; the radio helper fetches the
          // video with yt-dlp into the game's temp folder and it plays from there, the sound from the helper)
          '<video ng-if="kind() === \'yt\' && ytFile()" ng-src="{{ ytFileUrl() }}" autoplay controls playsinline muted></video>' +
          '<div class="wait" ng-if="kind() === \'yt\' && !ytFile()"><b>▶</b><span>{{ ytWait() }}</span></div>' +
          '<video ng-if="kind() === \'file\'" ng-src="{{ fileUrl() }}" autoplay loop controls playsinline muted></video>' +
          // (a livestream – Twitch, YouTube live, .m3u8: the helper is its client and serves it here; hls.js plays it)
          '<video class="lv" ng-if="kind() === \'live\' && liveUrl() && !liveBad" autoplay controls playsinline muted></video>' +
          '<div class="wait" ng-if="kind() === \'live\' && (!liveUrl() || liveBad)"><b>●</b><span>{{ liveWait() }}</span></div>' +
          '<i class="badge" ng-if="kind() === \'live\' && liveUrl() && !liveBad">● LIVE</i>' +
          '<div class="grip"></div>' +
        '</div>' +
      '</div>' +
      '<div class="pnl" ng-if="panel">' +
        '<div class="hd">📺 Video <a ng-click="togglePanel(false)" title="Schließen">×</a></div>' +
        '<input type="text" ng-model="ui.url" placeholder="YouTube-, Twitch- oder Video-Link (.mp4/.m3u8)" ng-keydown="$event.keyCode === 13 && play()" ng-focus="typing(true)" ng-blur="typing(false)" />' +
        '<div class="row"><button class="btn on" ng-click="play()">▶ Abspielen</button><button class="btn" ng-click="stop()">■ Stopp</button></div>' +
        '<div class="row"><button class="btn" ng-class="{on: cfg.full}" ng-click="cfg.full = !cfg.full; keep()">Vollbild</button>' +
          '<button class="btn" ng-class="{on: cfg.through}" ng-click="cfg.through = !cfg.through; keep()" title="Klicks gehen durch das Video hindurch">Durchklickbar</button></div>' +
        '<div class="sl"><span>Deckkraft</span><input type="range" min="0.15" max="1" step="0.05" ng-model="cfg.opacity" ng-change="keep()" /><span>{{ pct(cfg.opacity) }}</span></div>' +
        '<div class="sl"><span>Kippen (vor)</span><input type="range" min="-70" max="70" step="1" ng-model="cfg.rx" ng-change="keep()" /><span>{{ cfg.rx }}°</span></div>' +
        '<div class="sl"><span>Drehen (seitl.)</span><input type="range" min="-70" max="70" step="1" ng-model="cfg.ry" ng-change="keep()" /><span>{{ cfg.ry }}°</span></div>' +
        '<div class="sl"><span>Neigen</span><input type="range" min="-45" max="45" step="1" ng-model="cfg.rz" ng-change="keep()" /><span>{{ cfg.rz }}°</span></div>' +
        '<div class="row"><button class="btn" ng-click="reset3d()">3D zurücksetzen</button>' +
          '<button class="btn" ng-if="out === \'window\'" ng-click="toScreen()" title="Auf das Navi-Display im LKW – das Fenster geht dann weg">🚛 Aufs Fahrzeug-Display</button>' +
          '<button class="btn on" ng-if="out === \'screen\'" ng-click="toWindow()" title="Wieder im Fenster – das Display zeigt wieder die Karte">🪟 Zurück ins Fenster</button></div>' +
        '<div class="row" ng-if="out === \'screen\'"><button class="btn" ng-click="screenPlay()">{{ sc.playing ? "❚❚ Pause" : "▶ Weiter" }} (Display)</button>' +
          '<button class="btn" ng-if="canSeek" ng-click="screenJump(-10)">« 10 s</button><button class="btn" ng-if="canSeek" ng-click="screenJump(10)">10 s »</button></div>' +
        '<div class="msg" ng-if="msg" ng-class="{bad: msgBad}">{{ msg }}</div>' +
        '<div class="msg bad" ng-if="cfg.src && h.radio && h.radio.src !== \'video\'">🔇 Ton: am Radio unter QUELLE „VIDEO“ wählen.</div>' +
        '<div class="mut">Fenster an der oberen Leiste ziehen, unten rechts in der Größe ändern. Mit „Kippen“ und „Drehen“ lässt es sich schräg aufs Armaturenbrett legen. ' +
          'Videos laufen beim nächsten Mal dort weiter, wo du aufgehört hast. Livestreams (Twitch, YouTube live) laufen immer live.</div>' +
      '</div>' +
      '</div>',
    replace: true,
    link: function (scope, el) {
      'use strict'
      scope.h = { mode: false }
      scope.panel = false
      scope.togglePanel = function (on) { scope.panel = on === undefined ? !scope.panel : on }
      scope.ui = { url: '' }
      var DEF = { src: '', show: true, x: 360, y: 120, w: 480, h: 270, opacity: 1, rx: 0, ry: 0, rz: 0, full: false, through: false }
      function load() { try { return Object.assign({}, DEF, JSON.parse(window.localStorage.getItem('ffVideoCfg') || '{}')) } catch (e) { return Object.assign({}, DEF) } }
      scope.cfg = load()
      scope.ui.url = scope.cfg.src
      scope.keep = function () { try { window.localStorage.setItem('ffVideoCfg', JSON.stringify(scope.cfg)) } catch (e) {} }
      scope.pct = function (x) { return Math.round((+x || 0) * 100) + ' %' }
      scope.typing = function (on) { bngApi.engineLua('if setCEFTyping then setCEFTyping(' + (on ? 'true' : 'false') + ') end') }
      // the link: a YouTube video (watch, youtu.be, shorts, embed, live) or a file
      function ytId(u) {
        var m = (u || '').match(/(?:youtu\.be\/|youtube\.com\/(?:watch\?(?:.*&)?v=|shorts\/|embed\/|live\/))([\w-]{11})/)
        return m ? m[1] : (/^[\w-]{11}$/.test(u || '') ? u : null)
      }
      // a livestream by its link (the same rule as the helper's): .m3u8, a Twitch channel (not its videos or clips),
      // YouTube's /live/… or @channel/live – and any YouTube video the helper found to be live
      function isLiveLink(u) {
        u = (u || '').toLowerCase()
        if (u.indexOf('.m3u8') >= 0) { return true }
        if (u.indexOf('twitch.tv/') >= 0 && u.indexOf('/videos/') < 0 && u.indexOf('/clip') < 0) { return true }
        return u.indexOf('youtube.com/live/') >= 0 || (u.indexOf('youtube.com/@') >= 0 && u.indexOf('/live') >= 0)
      }
      scope.kind = function () {
        var s = scope.cfg.src
        if (!s) { return '' }
        var i = info()
        if (isLiveLink(s) || (i.liveFor === s && i.live)) { return 'live' }
        return ytId(s) ? 'yt' : 'file'
      }
      var fileCache = {}
      scope.fileUrl = function () {
        var s = scope.cfg.src
        if (!fileCache[s]) { fileCache[s] = $sce.trustAsResourceUrl(s) }
        return fileCache[s]
      }
      // the helper's copy of a YouTube video (the HUD's radio.info: video = its path, videoFor = the link it is for)
      function info() { return (scope.h && scope.h.radio && scope.h.radio.info) || {} }
      scope.ytFile = function () { var i = info(); return i.video && i.videoFor === scope.cfg.src ? i.video : null }
      var ytFileCache = {}
      scope.ytFileUrl = function () {
        var f = scope.ytFile()
        if (!ytFileCache[f]) { ytFileCache[f] = $sce.trustAsResourceUrl('/' + f.replace(/^\//, '')) }
        return ytFileCache[f]
      }
      scope.ytWait = function () {
        var r = (scope.h && scope.h.radio) || {}, i = info()
        if (!r.helper) { return 'YouTube braucht die Fernfahrer-Radio-App – bitte starten (eigener Download auf der GitHub-Seite der Mod).' }
        if (i.videoFor === scope.cfg.src && i.videoMB > 0.01) { return 'Video wird geladen … ' + i.videoMB.toFixed(1).replace('.', ',') + ' MB' }
        return (i.status && /yt-dlp|YouTube|Video|Live/.test(i.status)) ? i.status : 'Video wird vorbereitet …'
      }
      // --- livestreams: the helper's local copy of the stream (http://127.0.0.1:47811/live.m3u8), played by hls.js ---
      scope.liveUrl = function () { var i = info(); return i.live && i.liveFor === scope.cfg.src ? i.live : null }
      scope.liveBad = ''
      scope.liveWait = function () {
        if (scope.liveBad) { return scope.liveBad }
        var r = (scope.h && scope.h.radio) || {}, i = info()
        if (!r.helper) { return 'Livestreams brauchen die Fernfahrer-Radio-App – bitte starten (eigener Download auf der GitHub-Seite der Mod).' }
        if (r.src !== 'video') { return 'Am Radio unter QUELLE „VIDEO“ wählen – dann holt der Helfer den Stream.' }
        return (i.liveFor === scope.cfg.src && i.status) ? i.status : 'Livestream wird gesucht …'
      }
      var HLS_JS = '/ui/modules/apps/FernfahrerVideo/hls.min.js', hlsLoading = false
      function needHls(cb) {
        if (window.Hls) { cb(); return }
        if (hlsLoading) { return }
        hlsLoading = true
        var s = document.createElement('script')
        s.src = HLS_JS
        s.onload = function () { hlsLoading = false; cb() }
        s.onerror = function () { hlsLoading = false; scope.$evalAsync(function () { scope.liveBad = 'hls.js fehlt (Mod-Dateien unvollständig).' }) }
        document.head.appendChild(s)
      }
      var hl = { hls: null, el: null, url: null }
      function liveDrop() { if (hl.hls) { try { hl.hls.destroy() } catch (e) {} } hl = { hls: null, el: null, url: null } }
      // (called twice a second: the window's live video joined to the stream – a new element or link, a new player)
      function liveAttach() {
        var lv = el[0].querySelector('.ffv .win video.lv'), url = scope.liveUrl()
        if (!lv || !url) { if (hl.hls) { liveDrop() } return }
        if (hl.el === lv && hl.url === url) { return }
        needHls(function () {
          var H = window.Hls
          if (!H || !H.isSupported() || !(window.MediaSource && MediaSource.isTypeSupported('video/mp4; codecs="avc1.4d401f"'))) {
            scope.$evalAsync(function () { scope.liveBad = 'Das Bild dieses Streams (H.264) kann das Spiel nicht zeigen – der Ton läuft trotzdem über das Radio.' })
            return
          }
          liveDrop()
          var h = new H({ liveSyncDurationCount: 3, maxBufferLength: 20, backBufferLength: 10, enableWorker: true })
          hl = { hls: h, el: lv, url: url }
          h.loadSource(url)
          h.attachMedia(lv)
          h.on(H.Events.MANIFEST_PARSED, function () { lv.play().catch(function () {}) })
          // (a hiccup: once more from the live edge in 3 s)
          h.on(H.Events.ERROR, function (ev, d) { if (d && d.fatal && hl.hls === h) { setTimeout(function () { if (hl.hls === h) { liveDrop() } }, 3000) } })
        })
      }
      // where the live picture is: its clock (Unix seconds, from the segments' #EXT-X-PROGRAM-DATE-TIME) – the helper's
      // sound follows it; without that clock 0 (the sound then runs on its own at the live edge)
      function liveClock() {
        var d = hl.hls && hl.hls.playingDate
        return d && d.getTime ? d.getTime() / 1000 : 0
      }
      // --- where each video was left (2026-11-04): per link, in this browser; a new start goes on from there ---
      var POS_KEY = 'ffVideoPos'
      function posAll() { try { return JSON.parse(window.localStorage.getItem(POS_KEY) || '{}') || {} } catch (e) { return {} } }
      function posGet(u) { var p = posAll()[u]; return p && p.t > 0 ? p.t : 0 }
      var posSavedAt = 0
      function posPut(u, t, dur) {
        if (!u || scope.kind() === 'live') { return }
        var all = posAll()
        // (near the end, or barely begun: from the start next time)
        if (t < 5 || (dur > 0 && dur - t < 8)) { delete all[u] } else { all[u] = { t: Math.round(t * 10) / 10, at: Date.now() } }
        var keys = Object.keys(all)
        if (keys.length > 40) { keys.sort(function (a, b) { return all[a].at - all[b].at }); for (var i = 0; i < keys.length - 40; i++) { delete all[keys[i]] } }
        try { window.localStorage.setItem(POS_KEY, JSON.stringify(all)) } catch (e) {}
      }
      scope.title = function () {
        var k = scope.kind(), s = scope.cfg.src || ''
        if (k === 'live') { var m = s.match(/twitch\.tv\/([\w]+)/i); return 'LIVE · ' + (m ? 'Twitch · ' + m[1] : (/youtu\.?be/i.test(s) ? 'YouTube' + ((s.match(/@([\w.-]+)/) || [])[1] ? ' · ' + s.match(/@([\w.-]+)/)[1] : '') : s.replace(/^https?:\/\//, '').split('/')[0])) }
        return k === 'yt' ? 'YouTube · ' + ytId(s) : s.split('/').pop()
      }
      scope.winStyle = function () {
        var c = scope.cfg
        return { left: c.x + 'px', top: c.y + 'px', width: c.w + 'px', height: c.h + 'px', opacity: c.opacity,
          transform: 'rotateX(' + c.rx + 'deg) rotateY(' + c.ry + 'deg) rotateZ(' + c.rz + 'deg)' }
      }
      // where the video is: 'window' (this app) or 'screen' (the truck's navigation screen) – one at a time.
      // On the screen this app keeps the clock (sc): the screen's video and the helper's sound both follow it.
      scope.out = 'window'
      scope.sc = { t0: 0, at: Date.now(), playing: true }
      function scNow() { var s = scope.sc; return s.t0 + (s.playing ? (Date.now() - s.at) / 1000 : 0) }
      var pendingSeek = null
      function winVideo() { return el[0].querySelector('.ffv .win video') }
      function screenSync() {
        bngApi.engineLua('if fernfahrer_career and fernfahrer_career.videoScreenSync then fernfahrer_career.videoScreenSync(' +
          scNow().toFixed(2) + ',' + (scope.sc.playing ? 'true' : 'false') + ') end')
      }
      function leaveScreen() {
        if (scope.out !== 'screen') { return }
        bngApi.engineLua('if fernfahrer_career then fernfahrer_career.videoScreenOff() end')
        scope.out = 'window'
      }
      scope.play = function () {
        var u = (scope.ui.url || '').trim()
        if (!u) { return }
        leaveScreen()                                  // (playing again: in the window, the screen back to its map)
        scope.cfg.src = u; scope.cfg.show = true; scope.keep()
        scope.msg = scope.kind() === 'yt' ? 'YouTube wird geladen …' : 'Video wird geladen …'; scope.msgBad = false
      }
      scope.stop = function () { leaveScreen(); scope.cfg.src = ''; scope.keep(); scope.msg = '' }
      scope.reset3d = function () { scope.cfg.rx = 0; scope.cfg.ry = 0; scope.cfg.rz = 0; scope.keep() }
      scope.toScreen = function () {
        var u = (scope.ui.url || scope.cfg.src || '').trim()
        if (!u) { scope.msg = 'Erst einen Link eingeben.'; scope.msgBad = true; return }
        if (scope.cfg.src !== u) { scope.ui.url = u; scope.play() }
        // (a livestream: the screen plays the helper's copy at its live edge – no clock to keep)
        if (scope.kind() === 'live') {
          var lu = scope.liveUrl()
          if (!lu) { scope.msg = 'Livestream lädt noch – gleich noch einmal drücken.'; scope.msgBad = true; return }
          bngApi.engineLua('fernfahrer_career and fernfahrer_career.videoToScreen(' + JSON.stringify(lu) + ',-1) or nil', function (r) {
            scope.$evalAsync(function () {
              scope.msg = (r && r.msg) || 'Kein Fahrzeug-Display gefunden.'; scope.msgBad = !(r && r.ok)
              if (r && r.ok) { scope.out = 'screen'; scope.canSeek = false; scope.sc = { t0: 0, at: Date.now(), playing: true, live: true }; liveDrop() }
            })
          })
          return
        }
        // (YouTube: the screen shows the helper's copy too – it has to be there first)
        if (ytId(u)) {
          var f = scope.ytFile()
          if (!f) { scope.msg = 'Video lädt noch – gleich noch einmal drücken.'; scope.msgBad = true; return }
          u = '/' + f.replace(/^\//, '')
        }
        // (on from where the window is – if the file can be jumped in at all; if not, the screen starts at 0 and the
        // clock with it, so picture and sound stay together)
        var wv = winVideo()
        var canSeek = !!(wv && wv.seekable && wv.seekable.length && wv.seekable.end(0) > 1)
        scope.canSeek = canSeek
        var t0 = wv && canSeek ? (wv.currentTime || 0) : 0
        bngApi.engineLua('fernfahrer_career and fernfahrer_career.videoToScreen(' + JSON.stringify(u) + ',' + t0.toFixed(2) + ') or nil', function (r) {
          scope.$evalAsync(function () {
            scope.msg = (r && r.msg) || 'Kein Fahrzeug-Display gefunden.'; scope.msgBad = !(r && r.ok)
            if (r && r.ok) { scope.out = 'screen'; scope.sc = { t0: t0, at: Date.now(), playing: true } }
          })
        })
      }
      scope.toWindow = function () {
        var t = scNow(), live = scope.sc.live
        leaveScreen()
        scope.cfg.show = true; scope.keep()
        pendingSeek = live ? null : t                  // (the window goes on where the screen was)
        scope.msg = ''
      }
      scope.screenPlay = function () {
        var t = scNow()
        scope.sc = { t0: t, at: Date.now(), playing: !scope.sc.playing, live: scope.sc.live }
        screenSync()
      }
      scope.screenJump = function (d) {
        scope.sc = { t0: Math.max(0, scNow() + d), at: Date.now(), playing: scope.sc.playing }
        screenSync()
      }
      // --- the sound: the picture plays muted; twice a second the game is told where it is (career.lua videoState →
      // the radio helper plays the sound, through the car speakers) ---
      var lastSent = null, syncAt = 0
      function report() {
        var c = scope.cfg, state = null, k = scope.kind()
        var winOn = c.src && c.show && scope.out === 'window'
        if (winOn && k === 'live') { liveAttach() } else if (hl.hls) { liveDrop() }
        var wv0 = winOn && k !== 'live' && winVideo()
        if (wv0 && wv0.readyState >= 1 && !wv0.__ffPlaced) {
          // (a new video element ready: back in the window on from where the screen was – else from where this video
          // was left the last time)
          wv0.__ffPlaced = true
          var at = pendingSeek !== null ? pendingSeek : posGet(c.src)
          pendingSeek = null
          if (at > 0 && (!wv0.duration || at < wv0.duration - 2)) { try { wv0.currentTime = at } catch (e) {} }
        }
        if (scope.out === 'screen' && c.src) {
          // (on the truck's screen: this app's clock – the screen follows it every 2 s, the sound twice a second; a
          // livestream there runs at its live edge, the sound too: t 0)
          state = { url: c.src, t: scope.sc.live ? 0 : scNow(), playing: scope.sc.playing }
          if (Date.now() - syncAt > 2000) { syncAt = Date.now(); if (scope.sc.live) { bngApi.engineLua('if fernfahrer_career and fernfahrer_career.videoScreenSync then fernfahrer_career.videoScreenSync(-1,' + (scope.sc.playing ? 'true' : 'false') + ') end') } else { screenSync() } }
        } else if (winOn && k === 'live') {
          // (the stream not there yet: the link only, not running – so the helper fetches it)
          var lv = el[0].querySelector('.ffv .win video.lv')
          if (lv && hl.hls) { lv.muted = true; state = { url: c.src, t: liveClock(), playing: !lv.paused && !lv.ended } }
          // (no picture possible here: the sound alone, at the live edge)
          else { state = { url: c.src, t: 0, playing: !!scope.liveBad } }
        } else if (winOn && k === 'yt') {
          // (the helper's copy playing: its time; still loading: the link only, not running – so the helper fetches it)
          var yv = winVideo()
          if (yv) { yv.muted = true; state = { url: c.src, t: yv.currentTime || 0, playing: !yv.paused && !yv.ended } }
          else { state = { url: c.src, t: 0, playing: false } }
        } else if (winOn && k === 'file') {
          var v = winVideo()
          if (v) { v.muted = true; state = { url: c.src, t: v.currentTime || 0, playing: !v.paused && !v.ended } }
        }
        // (where it is, kept every 3 s and when it stops – only once the video has really begun there)
        if (state && k !== 'live' && Date.now() - posSavedAt > 3000) {
          var pv = winOn ? winVideo() : null
          if (scope.out === 'screen' || (pv && pv.__ffPlaced && pv.readyState >= 1)) { posSavedAt = Date.now(); posPut(c.src, state.t, pv ? pv.duration : 0) }
        }
        if (!state && lastSent === null) { return }
        lastSent = state
        bngApi.engineLua('if fernfahrer_career and fernfahrer_career.videoState then fernfahrer_career.videoState(' +
          (state ? 'jsonDecode(' + JSON.stringify(JSON.stringify(state)) + ')' : 'nil') + ') end')
      }
      var reportTimer = setInterval(report, 500)
      // (a new link: no old live player, no old complaint)
      scope.$watch('cfg.src', function () { liveDrop(); scope.liveBad = '' })
      // the window kept on the screen (another resolution, a smaller game window): at least its bar reachable
      function fitWin() {
        var c = scope.cfg, W = window.innerWidth, H = window.innerHeight
        if (!(W > 400 && H > 300)) { return }          // (the UI not laid out yet: nothing to go by)
        var w = Math.min(c.w, W), h = Math.min(c.h, H - 26)
        var x = Math.min(Math.max(c.x, 0), W - w), y = Math.min(Math.max(c.y, 26), H - h)
        if (w !== c.w || h !== c.h || x !== c.x || y !== c.y) { c.w = w; c.h = h; c.x = x; c.y = y; scope.keep() }
      }
      fitWin()
      function onResize() { scope.$evalAsync(fitWin) }
      window.addEventListener('resize', onResize)
      // the cockpit strip's 📺: the panel open/closed; with a video hidden it shows again
      function onPanel() { scope.$evalAsync(function () { scope.panel = !scope.panel; if (scope.panel && scope.cfg.src) { scope.cfg.show = true; scope.keep() } }) }
      window.addEventListener('ffVideoPanel', onPanel)
      // moving by the bar, sizing by the corner (in screen pixels; the 3D turn is about its middle)
      var drag = null
      function onDown(e) {
        if (e.button !== 0 || scope.cfg.full) { return }
        var bar = e.target.closest && e.target.closest('.ffv .bar'), grip = e.target.closest && e.target.closest('.ffv .grip')
        if (bar && !e.target.closest('a')) { drag = { mode: 'move', x: e.clientX, y: e.clientY, c: Object.assign({}, scope.cfg) } }
        else if (grip) { drag = { mode: 'size', x: e.clientX, y: e.clientY, c: Object.assign({}, scope.cfg) } }
        if (drag) { e.preventDefault(); scope.$evalAsync(function () { scope.dragging = true }) }
      }
      function onMove(e) {
        if (!drag) { return }
        var d = drag, dx = e.clientX - d.x, dy = e.clientY - d.y, c = scope.cfg
        scope.$evalAsync(function () {
          if (d.mode === 'move') { c.x = Math.round(d.c.x + dx); c.y = Math.round(Math.max(26, d.c.y + dy)) }
          else { c.w = Math.round(Math.max(160, d.c.w + dx)); c.h = Math.round(Math.max(90, d.c.h + dy)) }
        })
      }
      function onUp() { if (drag) { drag = null; scope.$evalAsync(function () { scope.dragging = false; scope.keep() }) } }
      el[0].addEventListener('mousedown', onDown, true)
      window.addEventListener('mousemove', onMove)
      window.addEventListener('mouseup', onUp)
      scope.$on('$destroy', function () {
        window.removeEventListener('ffVideoPanel', onPanel); window.removeEventListener('mousemove', onMove); window.removeEventListener('mouseup', onUp)
        window.removeEventListener('resize', onResize); clearInterval(reportTimer); liveDrop()
        // (the game's UI going away – a reload, the menu: where the video was, kept once more)
        var v = winVideo(); if (v && v.__ffPlaced && scope.kind() !== 'live') { posPut(scope.cfg.src, v.currentTime || 0, v.duration) }
      })
      scope.$on('FernfahrerHud', function (ev, data) { scope.$evalAsync(function () { scope.h = data || { mode: false } }) })
    }
  }
}]);
