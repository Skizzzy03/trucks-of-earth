// Trucks of Earth HUD: the cab scene, full screen over the world, as seen from the driver's eyes (vices.lua
// starts it: 'FernfahrerScene' { kind, len, litAt, flameFrom, flameTo }, { puff = n }, { kind = false }).
//  cigarette / joint: the hand brings it to the lips, the other hand comes up with the lighter, click, the flame,
//                     the tip glows; smoke curls off the tip, a drag now and then (glow + a cloud breathed out);
//                     at the end the hand takes it away.
//  beer:              the hand brings the can up, the ring pull cracks open (a spray), up to the lips (the camera
//                     tips the head back meanwhile, vices.camOffset) and back down.
// Under the influence ('FernfahrerHud'.vices.fx): a vignette that breathes and a faint tint.
angular.module('beamng.apps')
.directive('fernfahrerSzene', [function () {
  var SVG =
    '<svg class="scn" viewBox="0 0 1920 1080" preserveAspectRatio="xMidYMax meet">' +
    '<defs>' +
      '<radialGradient id="ffzVig" cx="50%" cy="50%" r="75%"><stop offset="55%" stop-color="#000" stop-opacity="0"/><stop offset="100%" stop-color="#000" stop-opacity="1"/></radialGradient>' +
      '<radialGradient id="ffzGlow"><stop offset="0%" stop-color="#fff2b0"/><stop offset="35%" stop-color="#ff7a1a" stop-opacity=".9"/><stop offset="100%" stop-color="#ff4a00" stop-opacity="0"/></radialGradient>' +
      '<linearGradient id="ffzSkin" x1="0" y1="0" x2="1" y2="1"><stop offset="0%" stop-color="#e9b48f"/><stop offset="100%" stop-color="#b97a55"/></linearGradient>' +
      '<linearGradient id="ffzPaper" x1="0" y1="0" x2="1" y2="0"><stop offset="0%" stop-color="#cfcfc8"/><stop offset="45%" stop-color="#fbfbf6"/><stop offset="100%" stop-color="#bdbdb4"/></linearGradient>' +
      '<linearGradient id="ffzFilter" x1="0" y1="0" x2="1" y2="0"><stop offset="0%" stop-color="#a4602a"/><stop offset="45%" stop-color="#e09a52"/><stop offset="100%" stop-color="#94531f"/></linearGradient>' +
      '<linearGradient id="ffzCan" x1="0" y1="0" x2="1" y2="0"><stop offset="0%" stop-color="#06301a"/><stop offset="30%" stop-color="#1c8a4a"/><stop offset="55%" stop-color="#3fbf74"/><stop offset="100%" stop-color="#05301a"/></linearGradient>' +
      '<linearGradient id="ffzCanE" x1="0" y1="0" x2="1" y2="0"><stop offset="0%" stop-color="#0a1b4a"/><stop offset="30%" stop-color="#1d4fd0"/><stop offset="55%" stop-color="#4f8bff"/><stop offset="100%" stop-color="#0a1b4a"/></linearGradient>' +
      '<linearGradient id="ffzMetal" x1="0" y1="0" x2="1" y2="0"><stop offset="0%" stop-color="#8d9298"/><stop offset="50%" stop-color="#eef1f4"/><stop offset="100%" stop-color="#7c8187"/></linearGradient>' +
      '<linearGradient id="ffzLighter" x1="0" y1="0" x2="1" y2="0"><stop offset="0%" stop-color="#7a0a12"/><stop offset="50%" stop-color="#e2303c"/><stop offset="100%" stop-color="#6a0810"/></linearGradient>' +
      '<radialGradient id="ffzFlame" cx="50%" cy="75%" r="60%"><stop offset="0%" stop-color="#fffbe0"/><stop offset="40%" stop-color="#ffc24a"/><stop offset="80%" stop-color="#ff6a10" stop-opacity=".7"/><stop offset="100%" stop-color="#ff4000" stop-opacity="0"/></radialGradient>' +
      '<filter id="ffzBlur" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="14"/></filter>' +
      '<filter id="ffzSoft" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="2.2"/></filter>' +
    '</defs>' +
    '<g class="smoke" filter="url(#ffzBlur)"></g>' +
    // the cigarette / joint: origin at the lips (bottom centre), the tip up the screen
    '<g class="stick" style="display:none">' +
      '<path class="paper" fill="url(#ffzPaper)"/>' +
      '<path class="filt" fill="url(#ffzFilter)"/>' +
      '<path class="ash" fill="#6d6a66"/>' +
      '<circle class="glow" r="46" fill="url(#ffzGlow)" opacity="0"/>' +
      '<ellipse class="ember" rx="12" ry="6" fill="#ff5a12" opacity="0"/>' +
    '</g>' +
    // the right hand holding it (two fingers across the stick, the palm below right)
    '<g class="handR" style="display:none">' +
      '<ellipse cx="190" cy="40" rx="190" ry="120" fill="url(#ffzSkin)" transform="rotate(-25 190 40)"/>' +
      '<rect x="-30" y="-178" width="230" height="46" rx="23" fill="url(#ffzSkin)" transform="rotate(-12 0 -150)"/>' +
      '<rect x="-24" y="-128" width="240" height="50" rx="25" fill="url(#ffzSkin)" transform="rotate(-8 0 -100)"/>' +
      '<path d="M -14 -150 q 10 -6 22 0" stroke="#9a6243" stroke-width="3" fill="none" opacity=".5"/>' +
    '</g>' +
    // the left hand with the lighter: origin at the flame's foot
    '<g class="lighter" style="display:none">' +
      '<g class="flame" style="display:none"><path class="fl" d="M 0 0 C -22 -12 -20 -50 0 -92 C 20 -50 22 -12 0 0 Z" fill="url(#ffzFlame)"/>' +
        '<path d="M 0 0 C -7 -6 -7 -16 0 -24 C 7 -16 7 -6 0 0 Z" fill="#4a7bff" opacity=".8"/></g>' +
      '<circle class="spark" r="10" fill="#fff6b0" style="display:none"/>' +
      '<rect x="-34" y="2" width="68" height="34" rx="4" fill="url(#ffzMetal)"/>' +
      '<rect x="12" y="-10" width="20" height="14" rx="3" fill="#2a2a2a"/>' +
      '<rect x="-34" y="34" width="68" height="190" rx="10" fill="url(#ffzLighter)"/>' +
      '<ellipse cx="-70" cy="190" rx="120" ry="150" fill="url(#ffzSkin)" transform="rotate(20 -70 190)"/>' +
      '<rect x="-20" y="60" width="150" height="42" rx="21" fill="url(#ffzSkin)" transform="rotate(-28 10 80)"/>' +
    '</g>' +
    // the can: origin at its bottom centre
    '<g class="can" style="display:none">' +
      '<rect class="body" x="-110" y="-380" width="220" height="380" rx="18" fill="url(#ffzCan)"/>' +
      '<rect class="band" x="-110" y="-250" width="220" height="70" fill="#caa040" opacity=".85"/>' +
      '<text class="brand" x="0" y="-202" text-anchor="middle" font-size="44" font-weight="900" fill="#08321b" font-family="Georgia,serif">PILS</text>' +
      '<rect x="-110" y="-24" width="220" height="24" rx="10" fill="url(#ffzMetal)"/>' +
      '<path d="M -110 -380 L -96 -404 L 96 -404 L 110 -380 Z" fill="url(#ffzMetal)"/>' +
      '<ellipse class="lid" cx="0" cy="-404" rx="96" ry="22" fill="#d9dde1" stroke="#9aa0a6" stroke-width="5"/>' +
      '<ellipse class="hole" cx="0" cy="-398" rx="22" ry="8" fill="#1a1a1a" style="display:none"/>' +
      '<g class="tab"><ellipse cx="0" cy="-410" rx="26" ry="10" fill="none" stroke="#c3c8cd" stroke-width="7"/></g>' +
      '<g class="spray"></g>' +
      '<ellipse cx="120" cy="-120" rx="150" ry="190" fill="url(#ffzSkin)" transform="rotate(-10 120 -120)"/>' +
      '<rect x="-122" y="-250" width="150" height="48" rx="24" fill="url(#ffzSkin)" transform="rotate(-6 -50 -226)"/>' +
      '<rect x="-128" y="-190" width="160" height="50" rx="25" fill="url(#ffzSkin)" transform="rotate(-4 -50 -165)"/>' +
      '<rect x="-122" y="-132" width="150" height="48" rx="24" fill="url(#ffzSkin)" transform="rotate(-2 -50 -108)"/>' +
    '</g>' +
    // the coffee to go: a paper cup with its lid, origin at its bottom centre
    '<g class="cup" style="display:none">' +
      '<path d="M -128 -360 L -94 0 L 94 0 L 128 -360 Z" fill="url(#ffzPaper)"/>' +
      '<path d="M -117 -240 L -104 -110 L 104 -110 L 117 -240 Z" fill="#7a4a24"/>' +
      '<text x="0" y="-158" text-anchor="middle" font-size="42" font-weight="900" fill="#f4e7d2" font-family="Georgia,serif">KAFFEE</text>' +
      '<rect x="-140" y="-392" width="280" height="36" rx="14" fill="#2b2b2e"/>' +
      '<path d="M -116 -392 L -100 -424 L 100 -424 L 116 -392 Z" fill="#3a3a3e"/>' +
      '<ellipse cx="0" cy="-424" rx="100" ry="20" fill="#47474c"/>' +
      '<ellipse cx="46" cy="-424" rx="16" ry="6" fill="#111"/>' +
      '<ellipse cx="124" cy="-120" rx="150" ry="190" fill="url(#ffzSkin)" transform="rotate(-10 120 -120)"/>' +
      '<rect x="-132" y="-262" width="160" height="48" rx="24" fill="url(#ffzSkin)" transform="rotate(-6 -50 -226)"/>' +
      '<rect x="-128" y="-200" width="160" height="50" rx="25" fill="url(#ffzSkin)" transform="rotate(-4 -50 -165)"/>' +
      '<rect x="-122" y="-140" width="150" height="48" rx="24" fill="url(#ffzSkin)" transform="rotate(-2 -50 -108)"/>' +
    '</g>' +
    '</svg>'
  var css =
    // (fixed to the window, not the app's frame: BeamNG's layout gave the frame a margin, the scene was cut a few cm
    // on every side, 2026-11-03)
    // (left / top / size are set by fit(): the app frame sits moved and scaled by BeamNG's layout, 2026-11-03)
    '.ffz{position:fixed!important;margin:0!important;padding:0!important;pointer-events:none;overflow:hidden;z-index:0}' +
    // (never in the way of the mouse: looking around with the mouse must work everywhere over it)
    '.ffz,.ffz *{pointer-events:none!important}' +
    '.ffz .scn{position:absolute;left:0;top:0;width:100%;height:100%;pointer-events:none;overflow:visible}' +
    // (the vignette and the tint: the whole window, whatever its shape)
    '.ffz .vig{position:absolute;left:-4%;top:-4%;width:108%;height:108%;opacity:0;transition:opacity 4s;' +
      'background:radial-gradient(ellipse at center,rgba(0,0,0,0) 52%,rgba(0,0,0,.85) 100%)}' +
    '.ffz .vig.on{animation:ffzBreath 6s ease-in-out infinite}' +
    '@keyframes ffzBreath{0%,100%{transform:scale(1)}50%{transform:scale(1.05)}}' +
    '.ffz .tint{position:absolute;left:0;top:0;width:100%;height:100%;opacity:0;background:#ffb070;transition:opacity 4s}' +
    '.ffz .tint.thc{animation:ffzHue 9s linear infinite}' +
    // the stop prompt, low in the middle
    // (2026-11-05: glass panel; on the way the arrow turns to where the ring is, with the distance; inside: the key)
    '.ffz .stp{position:absolute;left:50%;bottom:19%;display:flex;align-items:center;gap:12px;background:linear-gradient(180deg,rgba(22,27,35,.86),rgba(12,15,20,.9));' +
      'backdrop-filter:blur(6px);border:1px solid rgba(255,255,255,.1);border-radius:16px;padding:9px 14px 9px 9px;color:#eef1f5;font-family:inherit;' +
      'box-shadow:0 14px 40px rgba(0,0,0,.45),inset 0 1px 0 rgba(255,255,255,.06);white-space:nowrap;opacity:0;transform:translate(-50%,14px) scale(.97);' +
      'transition:opacity .35s ease,transform .45s cubic-bezier(.2,.8,.2,1)}' +
    '.ffz .stp.show{opacity:1;transform:translate(-50%,0) scale(1)}' +
    '.ffz .stp .rg{position:relative;width:44px;height:44px;border-radius:12px;background:rgba(255,255,255,.04);display:flex;align-items:center;justify-content:center;font-size:19px;' +
      'box-shadow:inset 0 0 0 2px currentColor,0 0 18px -4px currentColor}' +
    '.ffz .stp .rg i{position:absolute;inset:-7px;transition:transform .5s cubic-bezier(.3,.7,.3,1)}' +
    '.ffz .stp .rg i:before{content:"";position:absolute;left:50%;top:-1px;margin-left:-7px;border:7px solid transparent;border-bottom:10px solid currentColor;border-top:0;filter:drop-shadow(0 0 4px currentColor)}' +
    '.ffz .stp.in .rg i{display:none}' +
    '.ffz .stp .tx b{display:block;font-size:14.5px;font-weight:800;letter-spacing:.01em}.ffz .stp .tx small{display:block;font-size:11.5px;color:#9aa4b2;margin-top:1px}' +
    '.ffz .stp .dst{font:800 17px/1 inherit;font-variant-numeric:tabular-nums;color:#fff;padding-left:12px;margin-left:2px;border-left:1px solid rgba(255,255,255,.12)}' +
    '.ffz .stp .dst small{font-size:11px;color:#9aa4b2;margin-left:2px}.ffz .stp.in .dst{display:none}' +
    '.ffz .stp .ky{background:#f5a623;color:#15100a;font-weight:900;font-size:13px;border-radius:7px;padding:5px 11px;margin-left:4px;box-shadow:0 2px 0 #a86c0c}' +
    '.ffz .stp.near .ky{display:none}.ffz .stp.in{animation:ffzPulse 1.8s ease-in-out infinite}' +
    '@keyframes ffzPulse{0%,100%{box-shadow:0 14px 40px rgba(0,0,0,.45)}50%{box-shadow:0 14px 40px rgba(0,0,0,.45),0 0 0 3px rgba(245,166,35,.32)}}' +
    // the game's own typeface (ui/common/LTWave) under our own name
    '@font-face{font-family:FFWave;font-weight:300;src:url(/ui/common/LTWave/LTWave-Light.otf)}' +
    '@font-face{font-family:FFWave;font-weight:500;src:url(/ui/common/LTWave/LTWave-Medium.otf)}' +
    '@font-face{font-family:FFWave;font-weight:700;src:url(/ui/common/LTWave/LTWave-Bold.otf)}' +
    '@font-face{font-family:FFWave;font-weight:900;src:url(/ui/common/LTWave/LTWave-Black.otf)}' +
    '.ffz .stp,.ffz .ttl,.ffz .twn{font-family:FFWave,"Noto Sans",sans-serif}' +
    // the title card of a new day (2026-11-05, redone): over a soft shade, the line grows, the words rise one by one
    '.ffz .ttl{position:absolute;left:0;right:0;top:22%;text-align:center;color:#fff;pointer-events:none}' +
    '.ffz .ttl:before{content:"";position:absolute;left:50%;top:50%;width:900px;height:420px;margin:-210px 0 0 -450px;background:radial-gradient(ellipse at center,rgba(5,8,12,.55),rgba(5,8,12,0) 70%);opacity:0;transition:opacity 1s}' +
    '.ffz .ttl.on:before{opacity:1}' +
    '.ffz .ttl > *{position:relative;opacity:0;transform:translateY(18px);transition:opacity .7s ease,transform .9s cubic-bezier(.2,.8,.2,1)}' +
    '.ffz .ttl.on > *{opacity:1;transform:none}' +
    '.ffz .ttl.on .c{transition-delay:.12s}.ffz .ttl.on .ln{transition-delay:.3s}.ffz .ttl.on .p{transition-delay:.42s}.ffz .ttl.on .co{transition-delay:.55s}' +
    '.ffz .ttl.out > *{opacity:0;transform:translateY(-10px);transition-delay:0s!important;transition-duration:.6s}' +
    '.ffz .ttl .d{font-size:14px;font-weight:700;letter-spacing:.42em;text-transform:uppercase;color:#f5b94a;text-shadow:0 2px 12px rgba(0,0,0,.6)}' +
    '.ffz .ttl .c{font-size:96px;font-weight:300;line-height:1;letter-spacing:.01em;margin-top:8px;font-variant-numeric:tabular-nums;text-shadow:0 4px 30px rgba(0,0,0,.55)}' +
    '.ffz .ttl .ln{width:0;height:2px;margin:16px auto 14px;background:linear-gradient(90deg,transparent,#f5a623,transparent);transition:width 1s cubic-bezier(.2,.8,.2,1) .3s,opacity .7s}' +
    '.ffz .ttl.on .ln{width:280px}' +
    '.ffz .ttl .p{font-size:26px;font-weight:700;text-shadow:0 2px 16px rgba(0,0,0,.6)}' +
    '.ffz .ttl .co{font-size:12.5px;font-weight:500;letter-spacing:.3em;text-transform:uppercase;color:#cfd6de;margin-top:10px;text-shadow:0 2px 10px rgba(0,0,0,.6)}' +
    '.ffz .ttl .p:empty,.ffz .ttl .co:empty{display:none}' +
    // a town driven into: a banner sliding down at the top
    '.ffz .twn{position:absolute;left:50%;top:7%;min-width:280px;transform:translate(-50%,-24px);opacity:0;text-align:center;color:#fff;padding:12px 30px 14px;' +
      'background:linear-gradient(180deg,rgba(14,18,24,.82),rgba(14,18,24,.66));backdrop-filter:blur(6px);border-radius:14px;border:1px solid rgba(255,255,255,.08);' +
      'box-shadow:0 16px 40px rgba(0,0,0,.4);transition:opacity .5s ease,transform .7s cubic-bezier(.2,.8,.2,1)}' +
    '.ffz .twn.on{opacity:1;transform:translate(-50%,0)}' +
    '.ffz .twn .e{font-size:11px;font-weight:700;letter-spacing:.34em;text-transform:uppercase;color:#9aa4b2}' +
    '.ffz .twn.new .e{color:#5ee08f}' +
    '.ffz .twn .n{font-size:30px;font-weight:900;letter-spacing:.01em;margin-top:3px;line-height:1.1}' +
    '.ffz .twn .k{font-size:12px;font-weight:500;color:#aeb7c3;margin-top:3px}' +
    '.ffz .twn .bar{height:2px;margin:9px auto 0;width:0;background:currentColor;color:#9aa4b2;border-radius:2px}' +
    '.ffz .twn.new .bar{color:#5ee08f}.ffz .twn.on .bar{width:100%;transition:width 4.4s linear}' +
    '@keyframes ffzHue{0%{background:#7fd17a}33%{background:#9a86e0}66%{background:#e0b26a}100%{background:#7fd17a}}'
  return {
    template: '<div class="ffz" style="background:transparent;box-shadow:none;"><style>' + css + '</style><div class="tint"></div><div class="vig"></div>' + SVG +
      // the stop prompt (stops.lua: in the ring: Enter; near: drive into it) and the title card of a new day
      '<div class="stp" style="display:none"><span class="rg"><i></i><em></em></span><span class="tx"><b></b><small></small></span><span class="dst"></span><span class="ky">Enter</span></div>' +
      '<div class="ttl" style="display:none"><div class="d"></div><div class="c"></div><div class="ln"></div><div class="p"></div><div class="co"></div></div>' +
      '<div class="twn" style="display:none"><div class="e"></div><div class="n"></div><div class="k"></div><div class="bar"></div></div>' +
      '</div>',
    replace: true,
    link: function (scope, el) {
      'use strict'
      var root = el[0]
      var q = function (s) { return root.querySelector(s) }
      var NS = 'http://www.w3.org/2000/svg'
      var stick = q('.stick'), handR = q('.handR'), lighter = q('.lighter'), flame = q('.flame'), spark = q('.spark')
      var cup = q('.cup'), canBody = q('.can .body'), canBand = q('.can .band'), canBrand = q('.can .brand')
      var can = q('.can'), tab = q('.tab'), hole = q('.hole'), lid = q('.lid'), spray = q('.spray'), smoke = q('.smoke')
      var paper = q('.paper'), filt = q('.filt'), ash = q('.ash'), glow = q('.glow'), ember = q('.ember')
      var vig = q('.vig'), tint = q('.tint')
      var MOUTH = { x: 960, y: 1112 }

      // over the whole window: where the frame really is on screen (moved, scaled) is measured and undone
      function fit() {
        var W = window.innerWidth, H = window.innerHeight
        root.style.left = '0px'; root.style.top = '0px'; root.style.width = W + 'px'; root.style.height = H + 'px'
        var r = root.getBoundingClientRect()
        var sx = root.offsetWidth ? r.width / root.offsetWidth : 1, sy = root.offsetHeight ? r.height / root.offsetHeight : 1
        if (!(sx > 0.05)) { sx = 1 }
        if (!(sy > 0.05)) { sy = 1 }
        root.style.left = (-r.left / sx).toFixed(1) + 'px'
        root.style.top = (-r.top / sy).toFixed(1) + 'px'
        root.style.width = (W / sx).toFixed(1) + 'px'
        root.style.height = (H / sy).toFixed(1) + 'px'
      }
      fit()
      setTimeout(fit, 300)
      window.addEventListener('resize', fit)
      var fitTimer = setInterval(fit, 3000)          // (the layout may move the frame later: edit mode, reloads)

      // keyframes { t, x, y, r, s }: smooth in between
      function smooth(k) { return k * k * (3 - 2 * k) }
      function at(track, t) {
        if (t <= track[0].t) { return track[0] }
        for (var i = 0; i < track.length - 1; i++) {
          var a = track[i], b = track[i + 1]
          if (t <= b.t) {
            var k = smooth((t - a.t) / Math.max(1e-6, b.t - a.t))
            return { x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k, r: (a.r || 0) + ((b.r || 0) - (a.r || 0)) * k, s: (a.s || 1) + ((b.s || 1) - (a.s || 1)) * k }
          }
        }
        return track[track.length - 1]
      }
      function place(node, p, dx, dy) {
        node.setAttribute('transform', 'translate(' + (p.x + (dx || 0)).toFixed(1) + ' ' + (p.y + (dy || 0)).toFixed(1) + ') rotate(' + (p.r || 0).toFixed(2) + ') scale(' + (p.s || 1).toFixed(3) + ')')
      }
      function show(node, on) { node.style.display = on ? '' : 'none' }

      // the stick's outline for a burnt length: near end wide (close to the eyes), the tip narrower / the joint wider
      function stickShape(joint, burn) {
        var len = (joint ? 360 : 330) - burn * (joint ? 150 : 130)
        var w0 = joint ? 24 : 38, w1 = joint ? 36 : 13
        var fl = joint ? 70 : 105
        var wf = w0 + (w1 - w0) * (fl / len)
        filt.setAttribute('d', 'M ' + -w0 + ' 0 L ' + -wf + ' ' + -fl + ' L ' + wf + ' ' + -fl + ' L ' + w0 + ' 0 Z')
        filt.setAttribute('fill', joint ? '#d8c8a0' : 'url(#ffzFilter)')
        var top = joint ? 'Q 0 ' + (-len - 26) + ' ' + w1 * 0.4 + ' ' + (-len - 6) : ''
        paper.setAttribute('d', 'M ' + -wf + ' ' + -fl + ' L ' + -w1 + ' ' + -len + ' ' + (joint ? 'L ' + (-w1 * 0.4) + ' ' + (-len - 6) + ' ' + top : '') + ' L ' + w1 + ' ' + -len + ' L ' + wf + ' ' + -fl + ' Z')
        ash.setAttribute('d', 'M ' + -w1 + ' ' + -len + ' L ' + (-w1 * 0.9) + ' ' + (-len - 10) + ' L ' + (w1 * 0.9) + ' ' + (-len - 10) + ' L ' + w1 + ' ' + -len + ' Z')
        glow.setAttribute('cx', 0); glow.setAttribute('cy', -len - 6)
        ember.setAttribute('cx', 0); ember.setAttribute('cy', -len - 6); ember.setAttribute('rx', w1 * 0.95)
        return len + 6
      }

      // smoke puffs: { node, t0, life, x0, y0, dx, dy, r0, r1, a }
      var puffs = []
      function addSmoke(x, y, o) {
        var c = document.createElementNS(NS, 'circle')
        c.setAttribute('fill', o.color || '#d9dde2')
        smoke.appendChild(c)
        puffs.push({ node: c, t0: performance.now() / 1000, life: o.life, x0: x, y0: y, dx: o.dx, dy: o.dy, r0: o.r0, r1: o.r1, a: o.a })
      }
      function stepSmoke(now) {
        for (var i = puffs.length - 1; i >= 0; i--) {
          var p = puffs[i], k = (now - p.t0) / p.life
          if (k >= 1) { smoke.removeChild(p.node); puffs.splice(i, 1); continue }
          var e = 1 - Math.pow(1 - k, 2)
          p.node.setAttribute('cx', (p.x0 + p.dx * e + Math.sin(now * 1.3 + i) * 12 * k).toFixed(1))
          p.node.setAttribute('cy', (p.y0 + p.dy * e).toFixed(1))
          p.node.setAttribute('r', (p.r0 + (p.r1 - p.r0) * e).toFixed(1))
          p.node.setAttribute('opacity', (p.a * (k < 0.15 ? k / 0.15 : 1 - (k - 0.15) / 0.85)).toFixed(3))
        }
      }
      var drops = []
      function burst() {
        for (var i = 0; i < 16; i++) {
          var c = document.createElementNS(NS, 'circle')
          c.setAttribute('r', 3 + Math.random() * 5)
          c.setAttribute('fill', i % 3 ? '#f2e7b8' : '#ffffff')
          spray.appendChild(c)
          var a = -Math.PI / 2 + (Math.random() - 0.5) * 1.6
          drops.push({ node: c, t0: performance.now() / 1000, v: 260 + Math.random() * 260, a: a })
        }
      }
      function stepDrops(now) {
        for (var i = drops.length - 1; i >= 0; i--) {
          var d = drops[i], k = now - d.t0
          if (k > 0.7) { spray.removeChild(d.node); drops.splice(i, 1); continue }
          d.node.setAttribute('cx', (Math.cos(d.a) * d.v * k).toFixed(1))
          d.node.setAttribute('cy', (-398 + Math.sin(d.a) * d.v * k + 600 * k * k).toFixed(1))
          d.node.setAttribute('opacity', (1 - k / 0.7).toFixed(2))
        }
      }

      var S = null          // the scene running: { kind, len, litAt, flameFrom, flameTo, t0, puffAt, burst }
      var raf = null
      function frame() {
        raf = null
        var now = performance.now() / 1000
        stepSmoke(now); stepDrops(now)
        if (S) {
          var t = now - S.t0
          if (S.kind === 'beer' || S.kind === 'energy' || S.kind === 'coffee') { beerFrame(t) } else { smokeFrame(t, now) }
          if (t > S.len + 0.3) { stop() }
        }
        if (S || puffs.length || drops.length) { raf = requestAnimationFrame(frame) }
      }
      function kick() { if (!raf) { raf = requestAnimationFrame(frame) } }

      function smokeFrame(t, now) {
        var joint = S.kind === 'joint', L = S.len
        var sway = { x: Math.sin(now * 0.9) * 5, y: Math.sin(now * 0.6) * 4 }
        var stickT = [{ t: 0, x: MOUTH.x + 560, y: MOUTH.y + 420, r: 38, s: 0.85 }, { t: 0.9, x: MOUTH.x, y: MOUTH.y, r: 0, s: 1 },
          { t: L - 1.2, x: MOUTH.x, y: MOUTH.y, r: 0, s: 1 }, { t: L, x: MOUTH.x + 580, y: MOUTH.y + 460, r: 40, s: 0.85 }]
        var handT = [{ t: 0, x: MOUTH.x + 560, y: MOUTH.y + 420, r: 38, s: 0.85 }, { t: 0.9, x: MOUTH.x, y: MOUTH.y, r: 0, s: 1 },
          { t: 1.7, x: MOUTH.x + 620, y: MOUTH.y + 520, r: 25, s: 0.9 }, { t: L - 1.8, x: MOUTH.x + 620, y: MOUTH.y + 520, r: 25, s: 0.9 },
          { t: L - 1.2, x: MOUTH.x, y: MOUTH.y, r: 0, s: 1 }, { t: L, x: MOUTH.x + 580, y: MOUTH.y + 460, r: 40, s: 0.85 }]
        // a drag: the stick lifts a little, the tip glows
        var puff = 0
        if (S.puffAt) { var pk = now - S.puffAt; if (pk < 1.6) { puff = Math.sin(pk / 1.6 * Math.PI) } }
        var lit = t > S.litAt
        var burn = lit ? Math.min(1, (t - S.litAt) / Math.max(1, L - S.litAt - 1.5)) : 0
        var tipLen = stickShape(joint, burn)
        var sp = at(stickT, t)
        place(stick, sp, sway.x, sway.y - puff * 10)
        show(stick, true)
        var hp = at(handT, t)
        place(handR, hp, sway.x, sway.y)
        show(handR, true)
        glow.setAttribute('opacity', lit ? (0.45 + puff * 0.55 + Math.random() * 0.06).toFixed(2) : (t > S.flameFrom + 0.3 ? 0.35 : 0))
        glow.setAttribute('r', (40 + puff * 26).toFixed(0))
        ember.setAttribute('opacity', lit ? 0.95 : 0)
        ember.setAttribute('fill', puff > 0.3 ? '#ffb347' : '#ff5a12')
        // the tip on screen (the stick stands upright from the lips in its own frame)
        var tip = { x: sp.x + sway.x, y: sp.y + sway.y - puff * 10 - tipLen * (sp.s || 1) }
        // the lighter: up under the tip, the flame, away
        if (t < 3.7) {
          var lt = [{ t: 0.6, x: MOUTH.x - 520, y: MOUTH.y + 380, r: -18 }, { t: 1.4, x: tip.x + 4, y: tip.y + 86, r: -4 },
            { t: 2.9, x: tip.x + 4, y: tip.y + 86, r: -4 }, { t: 3.6, x: MOUTH.x - 560, y: MOUTH.y + 400, r: -18 }]
          if (t >= 0.6) { place(lighter, at(lt, t)); show(lighter, true) } else { show(lighter, false) }
          var fl = t > S.flameFrom && t < S.flameTo
          show(flame, fl)
          if (fl) { flame.setAttribute('transform', 'scale(' + (0.9 + Math.random() * 0.15).toFixed(2) + ' ' + (0.85 + Math.random() * 0.3).toFixed(2) + ') rotate(' + ((Math.random() - 0.5) * 6).toFixed(1) + ')') }
          show(spark, t > 1.48 && t < 1.6)
          if (t > 1.48 && t < 1.6) { spark.setAttribute('cx', (Math.random() - 0.5) * 20); spark.setAttribute('cy', -8 - Math.random() * 10) }
        } else { show(lighter, false) }
        // smoke off the tip, more for a joint
        if (lit && t < L - 1.2 && now - (S.wisp || 0) > (joint ? 0.22 : 0.33)) {
          S.wisp = now
          addSmoke(tip.x, tip.y - 10, { life: 3.2, dx: (Math.random() - 0.3) * 120, dy: -300 - Math.random() * 120, r0: 6, r1: joint ? 46 : 34, a: joint ? 0.32 : 0.24 })
        }
        // breathed out after the drag
        if (S.puffAt && !S.exhaled && now - S.puffAt > 1.7) {
          S.exhaled = true
          for (var i = 0; i < 4; i++) {
            addSmoke(MOUTH.x + (Math.random() - 0.5) * 120, 1040, { life: 3.6, dx: (Math.random() - 0.5) * 420, dy: -380 - Math.random() * 200,
              r0: 60, r1: 260 + Math.random() * 140, a: joint ? 0.5 : 0.38, color: joint ? '#d8dccf' : '#d9dde2' })
          }
        }
      }

      function beerFrame(t) {
        var canT = [{ t: 0, x: 1420, y: 1560, r: 12, s: 1 }, { t: 0.9, x: 1190, y: 960, r: 4, s: 1 }, { t: 1.6, x: 1190, y: 960, r: 4, s: 1 },
          { t: 2.4, x: 1010, y: 1330, r: -26, s: 2.15 }, { t: 3.5, x: 1000, y: 1350, r: -32, s: 2.2 },
          { t: 4.3, x: 1190, y: 960, r: 4, s: 1 }, { t: 5.1, x: 1420, y: 1560, r: 12, s: 1 }]
        var p = at(canT, t)
        // (the cup has nothing to open: it only comes up and goes back)
        if (S.kind === 'coffee') { place(cup, p, 0, 0); show(cup, true); return }
        var shake = (t > 1.02 && t < 1.32) ? Math.sin((t - 1.02) * 70) * 5 : 0
        place(can, p, shake, 0)
        show(can, true)
        // tipped towards the face: more of the lid is seen
        var tip = Math.max(0, Math.min(1, (p.s - 1) / 1.15))
        lid.setAttribute('ry', (22 + tip * 46).toFixed(1))
        hole.setAttribute('ry', (8 + tip * 14).toFixed(1))
        var open = t > 1.05
        show(hole, open)
        tab.setAttribute('transform', open ? 'translate(0 -410) rotate(-62) translate(0 410)' : '')
        if (open && !S.burst) { S.burst = true; burst() }
      }

      function hideAll() { show(stick, false); show(handR, false); show(lighter, false); show(can, false); show(cup, false) }
      function dressCan(energy) {
        canBody.setAttribute('fill', energy ? 'url(#ffzCanE)' : 'url(#ffzCan)')
        canBand.setAttribute('fill', energy ? '#e8f04a' : '#caa040')
        canBrand.textContent = energy ? 'ENERGY' : 'PILS'
        canBrand.setAttribute('fill', energy ? '#10205a' : '#08321b')
      }
      function stop() { S = null; hideAll() }

      scope.$on('FernfahrerScene', function (ev, d) {
        if (!d) { return }
        if (d.puff) { if (S) { S.puffAt = performance.now() / 1000; S.exhaled = false } return }
        if (!d.kind) { stop(); return }
        hideAll()
        dressCan(d.kind === 'energy')
        S = { kind: d.kind, len: d.len || 5, litAt: d.litAt || 2.1, flameFrom: d.flameFrom || 1.55, flameTo: d.flameTo || 2.85, t0: performance.now() / 1000 }
        kick()
      })
      // the stop prompt
      var stp = q('.stp'), stpKey = ''
      var RING = { green: '#3ad38b', orange: '#ff9a1f', red: '#ff5b4d', blue: '#4d9bff', violet: '#b07bff', yellow: '#ffd23a', cyan: '#33e6f2' }
      // (the arrow: its angle followed the short way round, so it never spins a whole turn)
      var arrowDeg = 0, stpHide = null
      function showStop(s) {
        var on = !!(s && (s.inside || s.dist < 220))
        var dist = s && !s.inside ? (s.dist < 100 ? Math.round(s.dist / 5) * 5 : Math.round(s.dist / 10) * 10) : 0
        var key = on ? [s.name, s.inside ? 1 : 0, dist, Math.round((s.rel || 0) / 4)].join('|') : ''
        if (key === stpKey) { return }
        stpKey = key
        if (!on) {
          stp.classList.remove('show')
          clearTimeout(stpHide); stpHide = setTimeout(function () { if (!stp.classList.contains('show')) { stp.style.display = 'none' } }, 460)
          return
        }
        clearTimeout(stpHide)
        if (stp.style.display === 'none') { stp.style.display = ''; void stp.offsetWidth }
        stp.className = 'stp show ' + (s.inside ? 'in' : 'near')
        var rg = stp.querySelector('.rg')
        rg.style.color = RING[s.color] || '#f5a623'
        rg.querySelector('em').textContent = s.icon || ''
        if (typeof s.rel === 'number') {
          var d = s.rel - arrowDeg
          d = ((d + 540) % 360) - 180
          arrowDeg += d
          rg.querySelector('i').style.transform = 'rotate(' + arrowDeg.toFixed(1) + 'deg)'
        }
        stp.querySelector('b').textContent = s.inside ? (s.hint || s.name) : s.name
        var side = typeof s.rel === 'number' ? (Math.abs(s.rel) < 25 ? 'geradeaus' : Math.abs(s.rel) > 145 ? 'hinter dir' : (s.rel > 0 ? 'rechts' : 'links')) : ''
        stp.querySelector('small').textContent = s.inside ? 'Anhalten und Enter drücken' : ((s.typeName || 'In den leuchtenden Kreis fahren') + (side ? ' · ' + side : ''))
        stp.querySelector('.dst').innerHTML = s.inside ? '' : dist + '<small>m</small>'
      }
      // the title card: a new day (after the start, after sleeping)
      var ttl = q('.ttl'), ttlTimer = null
      var ttlUntil = 0
      scope.$on('FernfahrerTitle', function (ev, d) {
        if (!d) { return }
        // (the eyebrow: "Ausgeschlafen · Mittwoch" – or the weekday alone; nothing missing shows as a stray dot)
        ttl.querySelector('.d').textContent = [d.text, d.day].filter(Boolean).join('  ·  ')
        ttl.querySelector('.c').textContent = d.clock || ''
        ttl.querySelector('.p').textContent = d.place || ''
        ttl.querySelector('.co').textContent = d.company || ''
        clearTimeout(ttlTimer)
        ttl.classList.remove('on', 'out')
        ttl.style.display = ''
        void ttl.offsetWidth
        ttl.classList.add('on')
        ttlUntil = Date.now() + 5600
        ttlTimer = setTimeout(function () {
          ttl.classList.add('out')
          ttlTimer = setTimeout(function () { ttl.classList.remove('on', 'out'); ttl.style.display = 'none' }, 700)
        }, 4800)
      })
      // a town driven into: the banner (after the title card, if one is up)
      var twn = q('.twn'), twnTimer = null
      function showTown(d) {
        var wait = ttlUntil - Date.now()
        if (wait > 0) { setTimeout(function () { showTown(d) }, wait + 200); return }
        twn.className = 'twn' + (d.first ? ' new' : '')
        twn.querySelector('.e').textContent = d.first ? 'Neuer Ort entdeckt' : 'Willkommen zurück in'
        twn.querySelector('.n').textContent = d.name || ''
        var KIND = { city: 'Stadt', town: 'Kleinstadt', village: 'Dorf', suburb: 'Stadtteil' }
        twn.querySelector('.k').textContent = (KIND[d.kind] || '') + (d.first && d.count ? '  ·  ' + d.count + '. entdeckter Ort' : '')
        clearTimeout(twnTimer)
        twn.style.display = ''
        void twn.offsetWidth
        twn.classList.add('on')
        twnTimer = setTimeout(function () {
          twn.classList.remove('on')
          twnTimer = setTimeout(function () { twn.style.display = 'none' }, 700)
        }, 4600)
      }
      scope.$on('FernfahrerTown', function (ev, d) { if (d && d.name) { showTown(d) } })
      // --- the sleep screen (2026-11-04): career.lua sleepFor → 'FernfahrerSleep' { on, hours, dur, label, fromH, toH,
      // dayFrom, dayTo, place, kind }. Over everything (on the page's body, not in the app's frame): a truck parked at
      // the edge of a wood under a sky that runs through the hours – stars, the moon, the dawn, the sun –, the clock
      // counting on, "Zzz" from the cab. Dark at first (career.lua passes the time then), at its end it fades and tells
      // the game (sleepDone) ---
      var SLEEP_CSS =
        '#ffSleep{position:fixed;left:0;top:0;width:100vw;height:100vh;z-index:2147483000;pointer-events:auto;background:#000;opacity:0;font-family:"Noto Sans",Segoe UI,sans-serif;color:#fff;overflow:hidden;cursor:default}' +
        '#ffSleep.on{opacity:1}#ffSleep canvas{position:absolute;left:0;top:0;width:100%;height:100%}' +
        '#ffSleep .hd{position:absolute;left:0;right:0;top:12%;text-align:center;text-shadow:0 3px 20px rgba(0,0,0,.6)}' +
        '#ffSleep .lb{font-size:14px;font-weight:800;letter-spacing:.42em;text-transform:uppercase;color:#f5a623}' +
        '#ffSleep .ck{font-size:min(15vh,128px);font-weight:900;line-height:1;margin-top:10px;font-variant-numeric:tabular-nums;letter-spacing:.02em}' +
        '#ffSleep .dy{font-size:20px;font-weight:700;margin-top:10px;color:#e8edf3}#ffSleep .pl{font-size:13px;letter-spacing:.18em;text-transform:uppercase;color:#c3ccd6;margin-top:8px}' +
        '#ffSleep .ft{position:absolute;left:50%;bottom:6%;transform:translateX(-50%);width:min(420px,70vw);text-align:center}' +
        '#ffSleep .bar{height:4px;border-radius:2px;background:rgba(255,255,255,.18);overflow:hidden}#ffSleep .bar i{display:block;height:100%;width:0;background:linear-gradient(90deg,#f5a623,#ffd27a);border-radius:2px}' +
        '#ffSleep .st{margin-top:10px;font-size:12.5px;letter-spacing:.12em;text-transform:uppercase;color:#d5dce4}'
      var zz = null
      function sleepEl() {
        if (zz) { return zz }
        // (an earlier copy of this app – the HUD rebuilt – left its screen and style: gone first)
        ;['ffSleep', 'ffSleepCss'].forEach(function (id) { var o = document.getElementById(id); if (o && o.parentNode) { o.parentNode.removeChild(o) } })
        var st = document.createElement('style'); st.id = 'ffSleepCss'; st.textContent = SLEEP_CSS; document.head.appendChild(st)
        var d = document.createElement('div'); d.id = 'ffSleep'; d.style.display = 'none'
        d.innerHTML = '<canvas></canvas><div class="hd"><div class="lb"></div><div class="ck"></div><div class="dy"></div><div class="pl"></div></div>' +
          '<div class="ft"><div class="bar"><i></i></div><div class="st"></div></div>'
        document.body.appendChild(d)
        zz = { el: d, cv: d.querySelector('canvas'), lb: d.querySelector('.lb'), ck: d.querySelector('.ck'), dy: d.querySelector('.dy'), pl: d.querySelector('.pl'), bar: d.querySelector('.bar i'), st: d.querySelector('.st'), run: null }
        // the stars and the trees: placed once (the same every night)
        var rnd = (function (s) { return function () { s = (s * 16807) % 2147483647; return s / 2147483647 } })(42)
        zz.stars = []; for (var i = 0; i < 170; i++) { zz.stars.push({ x: rnd(), y: rnd() * 0.62, r: 0.4 + rnd() * 1.3, p: rnd() * 6.28, s: 0.6 + rnd() * 2 }) }
        zz.trees = []; for (var k = 0; k < 46; k++) { zz.trees.push({ x: rnd() * 1.1 - 0.05, h: 0.09 + rnd() * 0.13, w: 0.022 + rnd() * 0.02, back: rnd() < 0.55 }) }
        zz.trees.sort(function (a, b) { return (b.back ? 1 : 0) - (a.back ? 1 : 0) })
        return zz
      }
      // the sky by the hour: [hour, top colour, horizon colour]
      var SKY = [[0, [3, 5, 14], [12, 18, 40]], [4.8, [5, 8, 22], [24, 26, 58]], [6, [36, 40, 92], [232, 128, 86]], [7.5, [72, 118, 184], [244, 196, 140]],
        [10, [58, 120, 200], [160, 204, 238]], [17, [58, 120, 200], [160, 204, 238]], [19, [58, 62, 124], [240, 136, 80]], [20.5, [20, 26, 62], [76, 46, 92]],
        [22, [5, 8, 26], [16, 22, 48]], [24, [3, 5, 14], [12, 18, 40]]]
      function skyAt(h) {
        h = ((h % 24) + 24) % 24
        for (var i = 0; i < SKY.length - 1; i++) {
          var a = SKY[i], b = SKY[i + 1]
          if (h >= a[0] && h <= b[0]) {
            var f = (h - a[0]) / (b[0] - a[0]), mix = function (x, y) { return [0, 1, 2].map(function (j) { return Math.round(x[j] + (y[j] - x[j]) * f) }) }
            return { top: mix(a[1], b[1]), hor: mix(a[2], b[2]) }
          }
        }
        return { top: SKY[0][1], hor: SKY[0][2] }
      }
      function rgb(c, k) { k = k === undefined ? 1 : k; return 'rgb(' + Math.round(c[0] * k) + ',' + Math.round(c[1] * k) + ',' + Math.round(c[2] * k) + ')' }
      function nightOf(h) { h = ((h % 24) + 24) % 24; return h < 5 || h > 21 ? 1 : h < 6.5 ? (6.5 - h) / 1.5 : h > 19.5 ? (h - 19.5) / 1.5 : 0 }
      function clk(h) { h = ((h % 24) + 24) % 24; var m = Math.floor(h * 60 + 1e-6); return ('0' + Math.floor(m / 60)).slice(-2) + ':' + ('0' + (m % 60)).slice(-2) }
      function ease(x) { x = Math.max(0, Math.min(1, x)); return x < 0.5 ? 2 * x * x : 1 - Math.pow(-2 * x + 2, 2) / 2 }
      function drawSleep(z, d, now) {
        var cv = z.cv, W = cv.width = window.innerWidth, H = cv.height = window.innerHeight, g = cv.getContext('2d')
        var el = (now - z.t0) / 1000, dur = d.dur || 7
        // (the hours run between 1.2 s and 1.4 s before the end)
        var f = ease((el - 1.2) / Math.max(1, dur - 2.6))
        var h = d.fromH + d.hours * f, sky = skyAt(h), night = nightOf(h), hor = H * 0.7
        var grd = g.createLinearGradient(0, 0, 0, hor)
        grd.addColorStop(0, rgb(sky.top)); grd.addColorStop(1, rgb(sky.hor))
        g.fillStyle = grd; g.fillRect(0, 0, W, hor + 2)
        // the stars
        if (night > 0.02) {
          for (var i = 0; i < z.stars.length; i++) {
            var s = z.stars[i], a = night * (0.55 + 0.45 * Math.sin(now / 1000 * s.s + s.p))
            g.fillStyle = 'rgba(255,255,240,' + a.toFixed(3) + ')'
            g.beginPath(); g.arc(s.x * W, s.y * H, s.r, 0, 6.283); g.fill()
          }
        }
        // the sun (6–20 h) and the moon (19–7 h) on their arcs
        var hh = ((h % 24) + 24) % 24
        function body(p, r, col, glow) {
          var x = W * (0.08 + 0.84 * p), y = hor - Math.sin(Math.PI * p) * H * 0.55
          var gl = g.createRadialGradient(x, y, r * 0.3, x, y, r * glow)
          gl.addColorStop(0, col.replace('A', '0.55')); gl.addColorStop(1, col.replace('A', '0'))
          g.fillStyle = gl; g.beginPath(); g.arc(x, y, r * glow, 0, 6.283); g.fill()
          g.fillStyle = col.replace('A', '1'); g.beginPath(); g.arc(x, y, r, 0, 6.283); g.fill()
          return { x: x, y: y }
        }
        if (hh > 5.6 && hh < 20.4) { body((hh - 5.6) / 14.8, Math.max(18, H * 0.035), hh < 8 || hh > 18 ? 'rgba(255,180,110,A)' : 'rgba(255,246,214,A)', 4) }
        var mp = ((hh - 19 + 24) % 24) / 12
        if (mp < 1) {
          // (a full moon with its grey seas)
          var mr = Math.max(14, H * 0.024), m = body(mp, mr, 'rgba(236,240,255,A)', 3.2)
          g.fillStyle = 'rgba(160,168,190,.45)'
          ;[[-0.3, -0.2, 0.28], [0.25, 0.1, 0.22], [-0.05, 0.38, 0.18]].forEach(function (c) { g.beginPath(); g.arc(m.x + c[0] * mr, m.y + c[1] * mr, c[2] * mr, 0, 6.283); g.fill() })
        }
        // the land: two rows of hills, the wood, the ground – dark against the sky
        var dark = 0.16 + (1 - night) * 0.22
        function hills(base, amp, k, ph, col) {
          g.fillStyle = col; g.beginPath(); g.moveTo(0, H)
          for (var x = 0; x <= W; x += 12) { g.lineTo(x, base - amp * (0.6 * Math.sin(x / W * k + ph) + 0.4 * Math.sin(x / W * k * 2.3 + ph * 1.7))) }
          g.lineTo(W, H); g.closePath(); g.fill()
        }
        hills(hor - H * 0.02, H * 0.05, 5, 1.3, rgb(sky.hor, dark * 1.25))
        hills(hor + H * 0.02, H * 0.035, 8, 0.4, rgb(sky.hor, dark * 0.9))
        var ground = hor + H * 0.06
        for (var t = 0; t < z.trees.length; t++) {
          var tr = z.trees[t], tx = tr.x * W, th = tr.h * H * (tr.back ? 0.75 : 1), tw = tr.w * H * (tr.back ? 0.75 : 1), ty = ground - (tr.back ? H * 0.02 : 0)
          g.fillStyle = rgb(sky.hor, tr.back ? dark * 0.75 : dark * 0.5)
          for (var lv = 0; lv < 3; lv++) {
            var yb = ty - th * lv * 0.28, ww = tw * (1 - lv * 0.25)
            g.beginPath(); g.moveTo(tx - ww, yb); g.lineTo(tx, yb - th * 0.5); g.lineTo(tx + ww, yb); g.closePath(); g.fill()
          }
        }
        g.fillStyle = rgb(sky.hor, dark * 0.35); g.fillRect(0, ground - 2, W, H - ground + 2)
        // the lamp of the parking place (on at night: its cone on the ground)
        var lx = W * 0.28, ly = ground - H * 0.2
        g.fillStyle = rgb(sky.hor, dark * 0.3); g.fillRect(lx - 3, ly, 6, ground - ly); g.fillRect(lx - 3, ly, 34, 5)
        if (night > 0.05) {
          var cone = g.createRadialGradient(lx + 30, ground, 4, lx + 30, ground, H * 0.22)
          cone.addColorStop(0, 'rgba(255,200,120,' + (0.35 * night) + ')'); cone.addColorStop(1, 'rgba(255,200,120,0)')
          g.fillStyle = cone; g.beginPath(); g.ellipse(lx + 30, ground, H * 0.22, H * 0.05, 0, 0, 6.283); g.fill()
          g.fillStyle = 'rgba(255,214,150,' + night + ')'; g.beginPath(); g.arc(lx + 30, ly + 6, 5, 0, 6.283); g.fill()
        }
        // the truck: trailer and cab, side on, parked; the curtains drawn (a faint warm glow only at first)
        var u = H * 0.0105, bx = W * 0.5 - 26 * u, by = ground
        var body2 = rgb(sky.hor, dark * 0.22)
        g.fillStyle = body2
        g.fillRect(bx, by - 15 * u, 36 * u, 12 * u)                                  // the trailer
        g.fillRect(bx + 37 * u, by - 14 * u, 13 * u, 11 * u)                         // the cab
        g.fillRect(bx + 37 * u, by - 16.5 * u, 9 * u, 3 * u)                         // the roof spoiler
        g.fillRect(bx, by - 4 * u, 50 * u, 1.6 * u)
        var lit = Math.max(0, 1 - el / 1.6) * night
        g.fillStyle = 'rgba(255,190,110,' + (0.15 + 0.6 * lit).toFixed(3) + ')'
        g.fillRect(bx + 44 * u, by - 12.5 * u, 5 * u, 3.6 * u)                       // the window
        g.fillStyle = rgb(sky.hor, dark * 0.1)
        ;[3, 9, 28, 33, 40.5, 47].forEach(function (wx) { g.beginPath(); g.arc(bx + wx * u, by - 2.2 * u, 2.1 * u, 0, 6.283); g.fill() })
        g.fillStyle = 'rgba(255,60,40,' + (0.35 + 0.25 * night) + ')'; g.fillRect(bx - 0.6 * u, by - 6 * u, 0.8 * u, 1.3 * u)
        // "Zzz" from the cab (sleeping) – a cup's steam for a break
        var t2 = now / 1000
        for (var n = 0; n < 3; n++) {
          var ph = ((t2 * 0.45 + n / 3) % 1)
          var zx = bx + 46 * u + ph * 7 * u + Math.sin(ph * 6 + n) * u, zy = by - 17 * u - ph * 12 * u
          g.globalAlpha = Math.sin(ph * Math.PI) * 0.9
          g.fillStyle = '#eef3ff'; g.font = '800 ' + Math.round((1.6 + ph * 1.6) * u) + 'px sans-serif'
          g.fillText(d.kind === 'pause' ? '☕' : 'z', zx, zy)
          if (d.kind === 'pause') { break }
        }
        g.globalAlpha = 1
        // the vignette
        var vg = g.createRadialGradient(W / 2, H * 0.55, H * 0.35, W / 2, H * 0.55, H)
        vg.addColorStop(0, 'rgba(0,0,0,0)'); vg.addColorStop(1, 'rgba(0,0,0,.55)')
        g.fillStyle = vg; g.fillRect(0, 0, W, H)
        // the words
        z.ck.textContent = clk(h)
        var dayNow = f < 0.5 ? d.dayFrom : d.dayTo
        z.dy.textContent = (dayNow || '') + (f >= 1 ? (d.kind === 'pause' ? ' · weiter geht’s' : ' · ausgeschlafen') : '')
        z.bar.style.width = (f * 100).toFixed(1) + '%'
        z.st.textContent = f >= 1 ? (d.kind === 'pause' ? 'Pause beendet – Lenkzeit wieder voll' : 'Ruhezeit erfüllt – neuer Tag') : (d.kind === 'pause' ? 'Pause läuft …' : 'Ruhezeit läuft … der Fahrtenschreiber zählt mit')
        return el
      }
      function sleepStart(d) {
        var z = sleepEl()
        // (the game says it again and again with the time so far: the one running goes on; one not yet here joins in
        // where it is – not when it is about over)
        if (z.run && z.run.key === d.key) { return }
        if (d.key && d.key === z.lastKey && !z.run) { return }
        if ((d.el || 0) > (d.dur || 7) - 1.2) { return }
        if (z.run) { clearTimeout(z.run.raf); clearTimeout(z.run.end) }
        z.lastKey = d.key
        z.lb.textContent = d.label || 'Ruhezeit'
        z.pl.textContent = d.place || ''
        z.el.style.display = ''
        z.t0 = performance.now() - (d.el || 0) * 1000
        void z.el.offsetWidth
        z.el.classList.add('on')
        var run = { raf: 0, end: 0, key: d.key }
        z.run = run
        // (the drawing: twice per frame budget at most – setTimeout keeps it going when the page is in the background)
        function frame() {
          if (z.run !== run) { return }
          var el = drawSleep(z, d, performance.now())
          // (the fade by the screen's own clock – in 0.9 s, out over the last 0.9 s)
          var dd = d.dur || 7
          z.el.style.opacity = Math.max(0, Math.min(1, el / 0.9, (dd + 0.05 - el) / 0.9)).toFixed(3)
          if (el >= (d.dur || 7) - 0.9 && !run.out) {
            run.out = true
            z.el.classList.remove('on')
            run.end = setTimeout(function () {
              if (z.run !== run) { return }
              z.el.style.display = 'none'; z.run = null
              bngApi.engineLua('if fernfahrer_career and fernfahrer_career.sleepDone then fernfahrer_career.sleepDone() end')
            }, 950)
          }
          if (!run.out || el < (d.dur || 7) + 0.2) { run.raf = setTimeout(frame, 33) }
        }
        frame()
      }
      function sleepStop() {
        if (!zz || !zz.run) { return }
        clearTimeout(zz.run.raf); clearTimeout(zz.run.end)
        zz.el.style.display = 'none'; zz.el.style.opacity = '0'; zz.run = null
      }
      scope.$on('FernfahrerSleep', function (ev, d) { if (d && d.on) { sleepStart(d) } else { sleepStop() } })

      // --- the introduction of a new career (2026-11-05): career.lua 'FernfahrerTutorial' { company, home, loaner, rules }.
      // Cards over the yard (on the page's body – it takes the mouse), the rings explained with their colours; at the
      // end straight into the office or a look round first (career.lua tutorialDone) ---
      var TUT_CSS =
        '#ffTut{position:fixed;inset:0;z-index:2147482000;display:flex;align-items:flex-end;justify-content:center;padding-bottom:9vh;pointer-events:auto;' +
          'background:radial-gradient(ellipse at 50% 80%,rgba(5,8,12,.15),rgba(5,8,12,.55));opacity:0;transition:opacity .5s ease;font-family:FFWave,"Noto Sans",sans-serif;color:#eef1f5}' +
        '#ffTut.on{opacity:1}' +
        '#ffTut .card{position:relative;display:grid;grid-template-columns:172px minmax(0,1fr);width:min(860px,94vw);background:linear-gradient(180deg,rgba(24,29,37,.96),rgba(14,17,22,.97));border:1px solid rgba(255,255,255,.1);border-radius:18px;' +
          'box-shadow:0 30px 80px rgba(0,0,0,.55),inset 0 1px 0 rgba(255,255,255,.06);padding:0;overflow:hidden;transform:translateY(24px);transition:transform .6s cubic-bezier(.2,.8,.2,1)}' +
        '#ffTut.on .card{transform:none}' +
        '#ffTut .side{padding:20px 10px;background:rgba(0,0,0,.24);border-right:1px solid rgba(255,255,255,.07);display:flex;flex-direction:column;gap:2px}' +
        '#ffTut .side .tt{font-size:10.5px;font-weight:700;letter-spacing:.24em;text-transform:uppercase;color:#8b95a3;padding:0 10px 10px}' +
        '#ffTut .side a{display:flex;align-items:center;gap:8px;padding:8px 10px;border-radius:8px;font-size:13px;font-weight:700;color:#aeb7c3;cursor:pointer;transition:background .15s,color .15s}' +
        '#ffTut .side a:hover{background:rgba(255,255,255,.05);color:#fff}#ffTut .side a.on{background:rgba(245,166,35,.16);color:#ffcf7d}' +
        '#ffTut .side a small{margin-left:auto;font-size:11px;font-weight:500;color:#6d7683}' +
        '#ffTut .main{display:flex;flex-direction:column;min-width:0;height:min(520px,76vh);padding:22px 24px 16px}' +
        '#ffTut .scroll{flex:1;min-height:0;overflow-x:hidden;overflow-y:auto;padding-right:4px}' +
        '#ffTut .rows{display:flex;flex-direction:column;gap:9px;margin:4px 0 10px}' +
        '#ffTut .li{display:flex;gap:11px;align-items:flex-start;font-size:14px;line-height:1.45;color:#cfd6de}#ffTut .li b{color:#fff}' +
        '#ffTut .li>i{flex:none;width:26px;height:26px;border-radius:8px;display:flex;align-items:center;justify-content:center;font-style:normal;font-size:14px;background:rgba(255,255,255,.06)}' +
        '#ffTut .li>span{padding-top:2px;min-width:0}' +
        '#ffTut .count{margin-right:auto;font-size:12px;color:#8b95a3;font-variant-numeric:tabular-nums}' +
        '#ffTut .prog{position:absolute;left:0;right:0;top:0;height:3px;background:rgba(255,255,255,.07)}#ffTut .prog i{display:block;height:100%;background:#f5a623;transition:width .3s}' +
        '#ffTut .stepbox{animation:ffTutIn .45s cubic-bezier(.2,.8,.2,1)}@keyframes ffTutIn{from{opacity:0;transform:translateX(18px)}to{opacity:1;transform:none}}' +
        '#ffTut .ey{font-size:11px;font-weight:700;letter-spacing:.3em;text-transform:uppercase;color:#f5b94a}' +
        '#ffTut h2{margin:6px 0 8px;font-size:25px;font-weight:900;letter-spacing:.005em;line-height:1.15}' +
        '#ffTut p{margin:0 0 8px;font-size:14px;line-height:1.55;color:#cfd6de}#ffTut p b{color:#fff}' +
        '#ffTut kbd{display:inline-block;padding:1px 7px;border-radius:5px;background:#2a313c;border:1px solid #3a4250;border-bottom-width:2px;font:700 12px Consolas,monospace;color:#fff}' +
        '#ffTut .ill{height:120px;margin:4px 0 12px;display:flex;align-items:center;justify-content:center;perspective:500px}' +
        '#ffTut .ring{width:150px;height:150px;border-radius:50%;transform:rotateX(64deg);border:5px solid #3ad38b;box-shadow:0 0 22px #3ad38b,inset 0 0 26px rgba(58,211,139,.45);' +
          'background:radial-gradient(circle,rgba(58,211,139,.16),rgba(58,211,139,.05) 70%);animation:ffTutRing 2.4s ease-in-out infinite;position:relative}' +
        '#ffTut .ring:after{content:"";position:absolute;inset:18px;border-radius:50%;border:2px solid rgba(58,211,139,.6)}' +
        '@keyframes ffTutRing{50%{box-shadow:0 0 34px #3ad38b,inset 0 0 36px rgba(58,211,139,.6)}}' +
        '#ffTut .truck{position:absolute;font-size:34px;animation:ffTutDrive 3.6s cubic-bezier(.5,0,.3,1) infinite}' +
        '@keyframes ffTutDrive{0%{transform:translateX(-150px);opacity:0}15%{opacity:1}55%,85%{transform:translateX(0);opacity:1}100%{transform:translateX(0);opacity:0}}' +
        '#ffTut .legend{display:grid;grid-template-columns:1fr 1fr;gap:6px 14px;margin:2px 0 10px}' +
        '#ffTut .legend div{display:flex;align-items:center;gap:9px;font-size:13px;color:#dfe5ec}' +
        '#ffTut .legend i{width:16px;height:16px;border-radius:50%;border:3px solid currentColor;box-shadow:0 0 8px currentColor;flex:none}' +
        '#ffTut .legend small{color:#8b95a3;font-size:11.5px}' +
        '#ffTut .ft{display:flex;align-items:center;gap:8px;margin-top:14px}' +
                '#ffTut button{font:800 13px FFWave,"Noto Sans",sans-serif;border-radius:9px;padding:9px 16px;cursor:pointer;border:1px solid #333b47;background:#1d232c;color:#e9edf2;transition:all .15s}' +
        '#ffTut button:hover{border-color:#f5a623}#ffTut button.pri{background:#f5a623;border-color:#f5a623;color:#15100a}#ffTut button.pri:hover{filter:brightness(1.08)}' +
        '#ffTut button.ghost{background:none;border-color:transparent;color:#8b95a3;padding:9px 8px}'
      var RINGS = [['#3ad38b', 'Grün', 'Rastplatz – schlafen, Pause'], ['#ff9a1f', 'Orange', 'Tankstelle – tanken'], ['#ff5b4d', 'Rot', 'Werkstatt – reparieren'],
        ['#ffd23a', 'Gelb', 'Dein Hof – Büro, Fahrzeug wechseln'], ['#33e6f2', 'Türkis', 'Firma – Fracht laden'], ['#4d9bff', 'Blau', 'Händler – LKW kaufen'],
        ['#b07bff', 'Violett', 'Hafen / Flughafen – reisen']]
      function tutKey(x) { return x.split('+').map(function (k) { return '<kbd>' + k + '</kbd>' }).join('+') }
      function tutRow(icon, html) { return '<div class="li"><i>' + icon + '</i><span>' + html + '</span></div>' }
      function tutRows(list) { return '<div class="rows">' + list.map(function (r) { return tutRow(r[0], r[1]) }).join('') + '</div>' }
      var HOT = 'Strg+Umschalt+'
      function tutSteps(d) {
        return [
          // --- the start ---
          { ch: 'Start', ey: 'Willkommen', h: 'Willkommen bei ' + (d.company || 'deiner Spedition') + '!',
            b: '<p>Du stehst auf <b>' + (d.home || 'deinem Hof') + '</b>. Von hier fährst du Aufträge in der echten Welt: Fracht abholen, pünktlich und heil abliefern, Geld verdienen. Später kaufst du eigene LKW und stellst Fahrer ein.</p>' +
              '<p>' + (d.loaner ? 'Für den Anfang leiht dir die Firma einen LKW. ' : '') + 'Dieses Handbuch erklärt alles der Reihe nach. Links springst du zu jedem Thema. Du findest es später wieder im Büro unter <b>Einstellungen → Einführung</b>.</p>' },
          { ch: 'Start', ey: 'Die leuchtenden Kreise', h: 'In die Kreise fährst du hinein',
            ill: '<div class="ring"></div><div class="truck">🚚</div>',
            b: '<p>Wo du etwas tun kannst, liegt ein <b>leuchtender Kreis</b> auf der Straße. Fahr hinein, halte an und drück ' + tutKey('Enter') + '. Dann öffnet sich das Menü des Ortes. Schon von Weitem zeigt dir ein Pfeil, wo er liegt.</p>' },
          { ch: 'Start', ey: 'Die Farben', h: 'Jede Farbe, ein Ort',
            b: '<div class="legend">' + RINGS.map(function (r) { return '<div style="color:' + r[0] + '"><i></i><span><b style="color:#fff">' + r[1] + '</b> <small>' + r[2] + '</small></span></div>' }).join('') + '</div>' +
              '<p>Schlafen kannst du an <b>grünen</b> Kreisen, an Tankstellen und auf deinem Hof. Auch Parkplätze haben einen grünen Kreis, wenn du langsam daran vorbeifährst. Bei Rastplätzen an beiden Fahrtrichtungen liegt der Kreis auf deiner Seite.</p>' },
          { ch: 'Start', ey: 'Die Tasten', h: 'Das solltest du dir merken',
            b: tutRows([['🏢', tutKey(HOT + 'F') + ' öffnet das <b>Büro</b>, überall.'], ['✋', tutKey(HOT + 'G') + ' ist die <b>Aktion</b> des Moments, zum Beispiel Ladung sichern.'],
              ['🧭', tutKey(HOT + 'N') + ' setzt das <b>Navi</b> auf deinen Auftrag.'], ['🤖', tutKey(HOT + 'A') + ' schaltet <b>Autodrive</b> ein und aus.'], ['🌉', tutKey(HOT + 'B') + ' hilft bei <b>Kartenfehlern</b>.'], ['🪞', tutKey(HOT + 'M') + ' blendet die <b>Spiegel</b> ein.'], ['⏎', tutKey('Enter') + ' öffnet das Menü im Kreis, ' + tutKey('L') + ' kuppelt von Hand.']]) },
          // --- the jobs ---
          { ch: 'Aufträge', ey: 'Der Ablauf', h: 'So läuft ein Auftrag',
            b: tutRows([['📦', 'Im Büro unter <b>Aufträge</b> nimmst du Fracht an.'], ['🚚', 'Zur Firma fahren und rückwärts an den <b>Auflieger</b>, dann ankuppeln.'], ['🪢', 'Offene Ladung und Stückgut: im Stand mit ' + tutKey(HOT + 'G') + ' <b>sichern</b>. Sonst kann sie unterwegs vom Auflieger fallen.'],
              ['🗺', 'Dem Navi folgen, in die <b>blaue Fläche</b> fahren, abkuppeln.'], ['⭐', 'Die Abrechnung gibt <b>Sterne</b>. Zu spät oder mit beschädigter Ladung gibt es weniger Geld.']]) },
          { ch: 'Aufträge', ey: 'Besondere Touren', h: 'Nicht jede Fracht ist gleich',
            b: tutRows([['☣', '<b>Gefahrgut (ADR):</b> Die Papiere packst du nur am Abholort ein, im Umkreis von 200 m. Ohne sie wird es bei einer Kontrolle teuer.'], ['🥛', '<b>Milchtour:</b> An Molkereien bekommst du einen Sammelwagen und fährst die Höfe in der Nähe ab.'],
              ['⚓', '<b>Fernverkehr:</b> Fähren, Autozug und Flüge buchst du im Büro unter Reisen.'], ['🕶', '<b>Schmuggel:</b> Manche Angebote laufen unter der Hand. Viel Geld, aber bei einer Kontrolle droht eine sehr hohe Strafe.']]) },
          // --- the screen ---
          { ch: 'Anzeigen', ey: 'Der Bildschirm', h: 'Was wo steht',
            b: tutRows([['🧭', '<b>Unten rechts:</b> Routenberater mit Karte, Route, Auftrag und Fahrzeug.'], ['📟', '<b>Darüber rechts:</b> Fahrtenschreiber, oben drauf die Kabine.'], ['⚙', '<b>Daneben:</b> Antrieb und Tempomat.'], ['📻', '<b>Unten links:</b> Radio, darüber die Minimap und die Schadensanzeige.'],
              ['🪞', '<b>Leiste links:</b> Spiegel, Sitz, Video und die Hilfen 🌉 🛣 ⛽.']]) + '<p>Mit der Maus schaust du dich um und klickst die Knöpfe an.</p>' },
          { ch: 'Anzeigen', ey: 'Der Routenberater', h: 'Dein Beifahrer',
            b: tutRows([['🔊', 'Das <b>Navi spricht</b>: Abbiegen, Kreisverkehr, Ziel. Den Ton schaltest du auf der Karte.'], ['⚠', 'Der <b>Streckenwarner</b> zeigt Blitzer, Baustellen und Pannen mit Signalton. Du schaltest ihn auf der Karte ein.'],
              ['🤖', '<b>Autodrive</b> fährt die Route selbst. Du kannst jederzeit übernehmen.'], ['⛽', 'Wird der Tank knapp, bietet er dir den Weg zur <b>nächsten Tankstelle</b> an.']]) },
          { ch: 'Anzeigen', ey: 'Antrieb und Tempomat', h: 'Technik im Griff',
            b: tutRows([['⚙', '<b>Antrieb:</b> zeigt den Gang. Klick auf eine Achse sperrt das Differential, wenn es geht. Hilft auf rutschigem Grund.'], ['🎚', '<b>Tempomat:</b> SET hält das Tempo, RES nimmt es wieder auf, AUS lässt los, −10 bis +10 ändert es.'],
              ['📡', '<b>Assistenten</b> kaufst du in der Werkstatt: Abstandsregeltempomat, Spurhalteassistent, Spurverlassenswarner. Am Tempomat schaltest du sie einzeln.']]) },
          // --- the driver ---
          { ch: 'Fahrer', ey: 'Fahrtenschreiber', h: 'Lenkzeit und Pausen',
            b: tutRows([['⏱', 'Die Uhr läuft <b>10× schneller</b>. Nach spätestens <b>4,5 Stunden</b> brauchst du <b>45 Minuten Pause</b>, das sind 4,5 echte Minuten.'], ['☕', 'Nur der <b>Pause</b>-Knopf zählt. Einfach nur stehen ist keine Pause.'], ['🛏', 'Nach etwa <b>9 Stunden</b> Lenkzeit brauchst du <b>Schlaf</b>.'],
              ['👮', 'Verstöße liest die Polizei bei Kontrollen aus. Das kostet.'], ['🚗', '<b>OUT</b> heißt Privatfahrt, dann zählt keine Lenkzeit. <b>EINFACH / PROFI</b> wechselt die Anzeige, das Buch-Symbol erklärt alles genau.']]) },
          { ch: 'Fahrer', ey: 'Müdigkeit', h: 'Wer müde fährt, fährt schlecht',
            b: tutRows([['😴', 'Solange du wach bist, steigt die <b>Müdigkeit</b>. Nach 16 Stunden ist sie voll, der Balken steht im Fahrtenschreiber.'], ['👁', 'Bist du sehr müde, <b>fallen dir kurz die Augen zu</b>.'], ['☕', '<b>Kaffee to go</b> nimmt 20 % weg, <b>Energydrink</b> 12 %. Du kaufst sie an der Tankstelle und trinkst sie in der Kabine.'], ['🛏', 'Richtig hilft nur <b>Schlaf</b>: 8 Stunden und du bist wieder fit. Pausen helfen ein wenig.']]) },
          { ch: 'Fahrer', ey: 'Die Kabine', h: 'Bier, Kippe, Joint, Kaffee, Energy',
            b: tutRows([['🛒', 'An der <b>Tankstelle</b> kaufst du Nachschub, die Zahl am Knopf zeigt den Vorrat. Ein Klick in der Kabine, und du trinkst oder rauchst.'], ['🍺', '<b>Alkohol:</b> Ab 0,5 ‰ kostet es 500 € und einen Monat Fahrverbot, nach einem Unfall reichen 0,3 ‰.'], ['🚬', 'Während einer <b>Zigarette</b> baut sich Alkohol viermal so schnell ab.'],
              ['🌿', '<b>Joint:</b> THC über 3,5 ng/ml ist strafbar und bleibt Stunden im Blut. Die Sicht wird träge, der Tempomat hält nicht.'], ['🚪', 'Joints gibt es nur <b>hinter manchen Tankstellen</b>. Der Typ dort will drei Treffer im grünen Feld sehen, sonst ist er eine Weile weg.']]) },
          { ch: 'Fahrer', ey: 'Das Radio', h: 'Musik im Führerhaus',
            b: '<p>Für den Ton muss die kleine <b>Fernfahrer-Radio</b>-App laufen. Sie ist ein eigener Download auf der GitHub-Seite der Mod. Die Lampe am Radio zeigt, ob sie läuft.</p>' +
              tutRows([['🎛', 'Linker Knopf: Mausrad für Lautstärke, Klick für an/aus. Rechter Knopf: Sender wechseln.'], ['🔀', '<b>Quelle:</b> Internetradio, Spotify, Ton des Videoplayers oder Line.'], ['🎚', '<b>EQ</b> klappt Bässe, Mitten und Höhen aus.'], ['📍', '<b>Regionalsender:</b> Im neuen Bundesland wechselt das Radio mit kurzem Rauschen auf den Sender von dort. In den Einstellungen abschaltbar.']]) },
          // --- the road ---
          { ch: 'Unterwegs', ey: 'Regeln', h: 'Was auf der Straße gilt',
            b: tutRows((d.rules ? [['🚦', 'Als LKW gilt: <b>80 km/h</b> auf der Autobahn, <b>60</b> auf Landstraßen. Der Begrenzer regelt bei 90.']] : []).concat([['📸', 'Teuer wird es an <b>Blitzern</b> und bei Lasermessungen. Bußgelder gehen vom Firmenkonto ab.'], ['👮', 'Bei einer <b>Polizeikontrolle</b> redest du selbst: Ehrlich ist meist billiger, Ausreden können klappen oder teurer werden.'], ['🔥', 'Bergab <b>Motorbremse</b> nutzen. Zu heiße Bremsen lassen Reifen platzen.']])) },
          { ch: 'Unterwegs', ey: 'Ereignisse', h: 'Die Straße lebt',
            b: tutRows([['🚧', '<b>Baustellen</b> mit Tempolimit, Ampeln und engen Durchfahrten.'], ['🚗', '<b>Pannenautos, Unfälle, verlorene Ladung</b>: langsam vorbei.'], ['🚨', '<b>Blaulicht von hinten</b>: Platz machen.'], ['🛢', '<b>Ölspur, Splitt, Schlaglöcher, Mähfahrzeuge, Schwertransporte</b> und ganz selten ein <b>Falschfahrer</b>.']]) + '<p>Es wechselt sich ab. Der <b>CB-Funk</b> plaudert zwischendurch, und das Wetter ist echt.</p>' },
          { ch: 'Unterwegs', ey: 'Tanken und Werkstatt', h: 'Der LKW will versorgt sein',
            b: tutRows([['⛽', 'Tanken im <b>orangen</b> Kreis. Leer liegen geblieben? Die Tankhilfe ⛽ bringt dich für 140 € plus Diesel auf 20 %.'], ['🔧', 'Reparieren im <b>roten</b> Kreis oder auf dem Hof. Vorher abkuppeln.'], ['🔍', '<b>Gebrauchte</b> können versteckte Mängel haben, zum Beispiel eine verzogene Achse. Der Werkstatt-Check findet sie.'], ['🛢', 'In der Werkstatt gibt es auch einen <b>großen Tank</b> und die Assistenten.']]) },
          { ch: 'Unterwegs', ey: 'Unfall', h: 'Wenn es gekracht hat',
            b: tutRows([['📞', 'Allein verunglückt? Das Telefon fragt, ob du die Polizei rufst. Sind andere beteiligt, kommt sie von selbst.'], ['🚓', 'Polizei und Rettungsdienst fahren von hinten heran. <b>Bleib da</b>, bis der Bericht fertig ist. Wegfahren ist Unfallflucht.'], ['📄', 'Bericht, Fotos und Dashcam findest du im Büro unter <b>Dokumente</b>. Dort steht auch, wer schuld ist.'], ['🛡', 'Wer zahlt, entscheidet deine <b>Versicherung</b>.']]) },
          // --- help and money ---
          { ch: 'Hilfe & Geld', ey: 'Panne', h: 'Wenn der LKW streikt',
            b: tutRows([['💥', 'Ohne deine Schuld kann ein <b>Reifen platzen</b>, der <b>Kühler</b> ausfallen, ein <b>Schlauch</b> reißen (Notlauf) oder <b>Öl</b> auslaufen.'], ['🌡', 'Beim Kühler wird der Motor heiß: <b>sofort anhalten</b>, sonst geht er kaputt.'], ['📞', 'Im Stand rufst du im Routenberater den <b>Pannendienst</b>. Der gelbe Transporter fährt von hinten heran und repariert.'], ['🚚', 'Bleib in der Nähe. Wenn du wegfährst, wird der Einsatz storniert.']]) },
          { ch: 'Hilfe & Geld', ey: 'Club', h: 'Deutscher Truck-Club',
            b: tutRows([['🟡', 'Im Büro unter <b>Club &amp; Versicherung</b> wählst du deinen Tarif: <b>Kein Mitglied</b> (480 € je Einsatz), <b>Basis</b> (180 €), <b>Plus</b> (Einsatz frei, Teile halb), <b>Premium</b> (alles frei).'], ['⏱', 'Je besser der Tarif, desto schneller kommt jemand.'], ['⭐', 'Mitglieder sammeln <b>Punkte</b> für jeden Tag und jede Lieferung, ohne Schaden mehr.'], ['🎁', 'Punkte löst du gegen <b>Prämien</b> ein: Gutscheine, Kaffee oder den Rabattretter.']]) },
          { ch: 'Hilfe & Geld', ey: 'Versicherung', h: 'Wer zahlt den Schaden?',
            b: tutRows([['🛡', '<b>Haftpflicht</b> ist Pflicht und zahlt nur den Schaden der anderen.'], ['🛠', '<b>Teilkasko</b> übernimmt zusätzlich Pannen-Teile (150 € Selbstbeteiligung).'], ['✅', '<b>Vollkasko</b> zahlt auch deinen eigenen Unfallschaden. Die Selbstbeteiligung wählst du: 150, 500 oder 1000 €.'], ['📉', 'Der <b>SF-Rabatt</b> steigt alle 7 Tage ohne Schaden. Jeder Schaden kostet Klassen.'], ['⚖', 'Ist der andere schuld, zahlt seine Versicherung. Bei <b>Alkohol, Drogen oder Flucht</b> zahlt die Kasko nicht, und es droht Regress.']]) },
          { ch: 'Hilfe & Geld', ey: 'Die Hilfen', h: 'Festgefahren? Karte kaputt?',
            b: tutRows([['🌉', '<b>Brücken-Hilfe</b> (' + tutKey(HOT + 'B') + '): Fehlt eine Brücke oder steht etwas auf der Straße, setzt sie dich weiter. Kostenlos, und <b>Schäden durch den Fehler werden repariert</b>.'], ['🛣', '<b>Zurück auf die Straße:</b> Setzt dich auf die nächste Straße. Kostenlos, aber <b>Schäden bleiben</b>.'], ['⛽', '<b>Tankhilfe:</b> Für alle, die ohne Diesel liegen bleiben.']]) },
          { ch: 'Hilfe & Geld', ey: 'Die Firma', h: 'Aus einem LKW wird eine Spedition',
            b: tutRows([['🚛', 'Im Büro: <b>Händler</b> für neue und gebrauchte LKW, <b>Fuhrpark</b> zum Wechseln und Reparieren.'], ['🧑‍✈️', '<b>Fahrer</b> einstellen: Sie fahren eigene Touren und bringen der Firma Geld.'], ['🏦', 'Unter <b>Finanzen</b> siehst du Einnahmen, Ausgaben und Bußgelder und nimmst Kredite auf.'], ['📊', 'Die <b>Statistik</b> zeigt entdeckte Orte, Kilometer, Routen und deine Fahrerwertung.']]) },
          { ch: 'Los', ey: 'Los geht’s', h: 'Dein erster Auftrag wartet',
            b: '<p>Dein erster Auftrag ist deine <b>Tutorial-Route</b>: Rechts erscheint bei jedem Schritt eine kleine Karte, die dir sagt, was zu tun ist, vom Annehmen im Büro über das Ankuppeln bis zum Abgeben beim Kunden.</p><p>Gute Fahrt!</p>', last: true },
        ]
      }
      var tut = null
      function tutClose(then_) {
        if (!tut) { return }
        var el = tut.el
        el.classList.remove('on')
        setTimeout(function () { if (el.parentNode) { el.parentNode.removeChild(el) } }, 520)
        tut = null
        bngApi.engineLua('if fernfahrer_career and fernfahrer_career.tutorialDone then fernfahrer_career.tutorialDone(' + JSON.stringify(then_ || '') + ') end')
      }
      function tutRender() {
        var s = tut.steps[tut.i], el = tut.el
        el.querySelector('.stepbox').outerHTML = '<div class="stepbox"><div class="ey">' + s.ey + '</div><h2>' + s.h + '</h2>' +
          (s.ill ? '<div class="ill">' + s.ill + '</div>' : '') + s.b + '</div>'
        el.querySelector('.count').textContent = 'Karte ' + (tut.i + 1) + ' von ' + tut.steps.length
        el.querySelector('.prog i').style.width = ((tut.i + 1) / tut.steps.length * 100).toFixed(1) + '%'
        el.querySelector('.scroll').scrollTop = 0
        var chs = el.querySelectorAll('.side a')
        for (var c = 0; c < chs.length; c++) { chs[c].className = chs[c].dataset.ch === s.ch ? 'on' : '' }
        el.querySelector('.back').style.visibility = tut.i > 0 ? 'visible' : 'hidden'
        el.querySelector('.next').textContent = s.last ? '🏢 Zum Büro' : 'Weiter →'
        el.querySelector('.alt').style.display = s.last ? '' : 'none'
        el.querySelector('.skip').style.display = s.last ? 'none' : ''
      }
      function tutOpen(d) {
        if (tut) { return }
        if (!document.getElementById('ffTutCss')) { var st = document.createElement('style'); st.id = 'ffTutCss'; st.textContent = TUT_CSS; document.head.appendChild(st) }
        var old = document.getElementById('ffTut'); if (old && old.parentNode) { old.parentNode.removeChild(old) }
        var el = document.createElement('div'); el.id = 'ffTut'
        var steps = tutSteps(d || {}), chapters = []
        steps.forEach(function (s, k) { var last = chapters[chapters.length - 1]; if (!last || last.n !== s.ch) { chapters.push({ n: s.ch, i: k, c: 1 }) } else { last.c++ } })
        el.innerHTML = '<div class="card"><div class="prog"><i></i></div><nav class="side"><div class="tt">Handbuch</div>' +
          chapters.map(function (c) { return '<a data-ch="' + c.n + '" data-i="' + c.i + '">' + c.n + '<small>' + c.c + '</small></a>' }).join('') + '</nav>' +
          '<div class="main"><div class="scroll"><div class="stepbox"></div></div><div class="ft"><div class="count"></div>' +
          '<button class="ghost skip">Überspringen</button><button class="back">← Zurück</button><button class="alt">Erst umsehen</button><button class="pri next">Weiter →</button></div></div></div>'
        document.body.appendChild(el)
        tut = { el: el, i: 0, steps: steps }
        Array.prototype.forEach.call(el.querySelectorAll('.side a'), function (a) { a.onclick = function () { tut.i = Number(a.dataset.i); tutRender() } })
        el.querySelector('.next').onclick = function () { if (tut.steps[tut.i].last) { tutClose('office') } else { tut.i++; tutRender() } }
        el.querySelector('.back').onclick = function () { if (tut.i > 0) { tut.i--; tutRender() } }
        el.querySelector('.skip').onclick = function () { tutClose('') }
        el.querySelector('.alt').onclick = function () { tutClose('') }
        tutRender()
        void el.offsetWidth
        el.classList.add('on')
      }
      scope.$on('FernfahrerTutorial', function (ev, d) { tutOpen(d) })
      // (the photo series, photos.lua: a card of the handbook, the handbook closed without counting as read, a tab of the stop menu)
      scope.$on('FernfahrerPhotoUi', function (ev, d) {
        if (!d) { return }
        if (d.stopTab && window.ffStopPick) { window.ffStopPick(d.stopTab) }
        if (!tut) { return }
        if (d.close) { var el = tut.el; tut = null; if (el.parentNode) { el.parentNode.removeChild(el) } return }
        if (typeof d.i === 'number') { tut.i = d.i; tutRender() }
      })

      // --- the tutorial's route, the first job (2026-11-05): career.lua 'FernfahrerTutHint' { stage, n, total, title,
      // text, keys, last, hidden } or { off }. A small card at the right, only it takes the mouse; folded to a tab ---
      var HINT_CSS =
        '#ffHint{position:fixed;right:22px;top:26%;z-index:2147481000;width:310px;font-family:FFWave,"Noto Sans",sans-serif;color:#eef1f5;pointer-events:none}' +
        '#ffHint .hc{pointer-events:auto;background:linear-gradient(180deg,rgba(24,29,37,.95),rgba(14,17,22,.95));border:1px solid rgba(255,255,255,.1);border-left:3px solid #f5a623;' +
          'border-radius:14px;padding:13px 15px 12px;box-shadow:0 18px 50px rgba(0,0,0,.45);transition:opacity .35s ease,transform .5s cubic-bezier(.2,.8,.2,1)}' +
        '#ffHint .hc.in{animation:ffHintIn .55s cubic-bezier(.2,.8,.2,1)}@keyframes ffHintIn{from{opacity:0;transform:translateX(30px)}}' +
        '#ffHint .ey{display:flex;align-items:center;gap:8px;font-size:10.5px;font-weight:700;letter-spacing:.24em;text-transform:uppercase;color:#f5b94a}' +
        '#ffHint .ey a{margin-left:auto;cursor:pointer;color:#8b95a3;font-size:15px;letter-spacing:0;padding:0 2px}#ffHint .ey a:hover{color:#fff}' +
        '#ffHint .bar{height:3px;border-radius:2px;background:#2a313c;margin:7px 0 9px;overflow:hidden}#ffHint .bar i{display:block;height:100%;background:#f5a623;transition:width .6s ease}' +
        '#ffHint h3{margin:0 0 5px;font-size:16px;font-weight:900}#ffHint p{margin:0;font-size:12.8px;line-height:1.5;color:#cfd6de}#ffHint p b{color:#fff}' +
        '#ffHint kbd{display:inline-block;margin-top:8px;padding:2px 8px;border-radius:5px;background:#2a313c;border:1px solid #3a4250;border-bottom-width:2px;font:700 11.5px Consolas,monospace}' +
        '#ffHint button{margin-top:10px;font:800 12.5px FFWave,"Noto Sans",sans-serif;border-radius:8px;padding:7px 14px;cursor:pointer;border:1px solid #f5a623;background:#f5a623;color:#15100a}' +
        '#ffHint .tab{pointer-events:auto;display:none;float:right;cursor:pointer;background:rgba(20,24,31,.92);border:1px solid rgba(255,255,255,.1);border-left:3px solid #f5a623;border-radius:10px;padding:7px 12px;font-size:12px;font-weight:800}' +
        '#ffHint.min .hc{display:none}#ffHint.min .tab{display:block}#ffHint.off{display:none}'
      var hint = null, hintStage = null
      function hintEl() {
        if (hint) { return hint }
        if (!document.getElementById('ffHintCss')) { var st = document.createElement('style'); st.id = 'ffHintCss'; st.textContent = HINT_CSS; document.head.appendChild(st) }
        var old = document.getElementById('ffHint'); if (old && old.parentNode) { old.parentNode.removeChild(old) }
        var el = document.createElement('div'); el.id = 'ffHint'; el.className = 'off'
        el.innerHTML = '<div class="hc"><div class="ey"><span class="st"></span><a class="mn" title="Einklappen">–</a><a class="x" title="Tutorial beenden">×</a></div>' +
          '<div class="bar"><i></i></div><h3></h3><p></p><kbd></kbd><button>Verstanden – los geht’s</button></div><div class="tab">🎓 Tutorial</div>'
        document.body.appendChild(el)
        el.querySelector('.mn').onclick = function () { el.classList.add('min') }
        el.querySelector('.tab').onclick = function () { el.classList.remove('min') }
        el.querySelector('.x').onclick = function () { el.className = 'off'; bngApi.engineLua('if fernfahrer_career and fernfahrer_career.tutorialSkip then fernfahrer_career.tutorialSkip() end') }
        el.querySelector('button').onclick = function () {
          el.className = 'off'
          // (the milk round's card: the button ends the round, 2026-11-08)
          if (el.ffCancel) { bngApi.engineLua('if fernfahrer_career then fernfahrer_career.' + el.ffCancel + '() end') }
        }
        hint = el
        return el
      }
      scope.$on('FernfahrerTutHint', function (ev, d) {
        if (!d) { return }
        var el = hintEl()
        if (d.off) { el.className = 'off'; hintStage = null; return }
        var isNew = d.stage !== hintStage
        hintStage = d.stage
        // (the same card for the milk round: its own heading, nothing to skip – 2026-11-08)
        el.querySelector('.st').textContent = d.ey || ('Tutorial · ' + d.n + '/' + d.total)
        el.querySelector('.x').style.display = d.ey ? 'none' : ''
        el.querySelector('.tab').textContent = d.ey ? '🥛 Milchtour' : '🎓 Tutorial'
        el.querySelector('.bar i').style.width = Math.round(d.n / d.total * 100) + '%'
        el.querySelector('h3').textContent = d.title || ''
        el.querySelector('p').innerHTML = d.text || ''
        var k = el.querySelector('kbd'); k.textContent = d.keys || ''; k.style.display = d.keys ? '' : 'none'
        var btn = el.querySelector('button')
        btn.style.display = (d.last || d.btn) ? '' : 'none'
        btn.textContent = d.btn || 'Verstanden – los geht’s'
        btn.style.background = d.btn ? '#2a313c' : ''
        btn.style.borderColor = d.btn ? '#4a5362' : ''
        btn.style.color = d.btn ? '#eef1f5' : ''
        el.ffCancel = d.cancel || null
        var min = el.classList.contains('min') && !isNew
        el.className = d.hidden ? 'off' : (min ? 'min' : '')
        if (isNew && !d.hidden) { var hc = el.querySelector('.hc'); hc.classList.remove('in'); void hc.offsetWidth; hc.classList.add('in') }
      })
      // --- the officer at the window (2026-11-08): career.lua 'FernfahrerCop' { id, line, choices = { { t, sub } }, tag }
      // or { off }; on the page's body, it takes the mouse ---
      var COP_CSS =
        '#ffCop{position:fixed;left:50%;bottom:9%;transform:translateX(-50%);z-index:2147481800;width:min(640px,92vw);font-family:FFWave,"Noto Sans",sans-serif;color:#eef1f5;pointer-events:auto;' +
          'background:linear-gradient(180deg,rgba(24,29,37,.97),rgba(14,17,22,.97));border:1px solid rgba(255,255,255,.12);border-top:3px solid #4d9bff;border-radius:14px;padding:15px 18px 14px;box-shadow:0 22px 60px rgba(0,0,0,.55)}' +
        '#ffCop.smuggle{border-top-color:#ff5b4d}' +
        '#ffCop .who{display:flex;gap:9px;align-items:center;font-size:11px;font-weight:800;letter-spacing:.18em;text-transform:uppercase;color:#7fb7f5}' +
        '#ffCop.smuggle .who{color:#ff8a7d}#ffCop .who span{font-size:22px;letter-spacing:0}' +
        '#ffCop .ln{font-size:17px;line-height:1.4;font-weight:700;margin:7px 0 12px}' +
        '#ffCop .ch{display:flex;flex-direction:column;gap:6px}' +
        '#ffCop button{all:unset;box-sizing:border-box;cursor:pointer;display:block;padding:9px 13px;border-radius:9px;background:#1f2630;border:1px solid #303846;font-size:14px;font-weight:700}' +
        '#ffCop button:hover{background:#2a3340;border-color:#4d9bff}#ffCop button small{display:block;font-size:11.5px;font-weight:500;color:#8b95a3;margin-top:1px}'
      var cop = null, copId = null
      scope.$on('FernfahrerCop', function (ev, d) {
        if (!d || d.off) { if (cop && cop.parentNode) { cop.parentNode.removeChild(cop) } cop = null; copId = null; return }
        if (!cop) {
          if (!document.getElementById('ffCopCss')) { var st = document.createElement('style'); st.id = 'ffCopCss'; st.textContent = COP_CSS; document.head.appendChild(st) }
          var old = document.getElementById('ffCop'); if (old && old.parentNode) { old.parentNode.removeChild(old) }
          cop = document.createElement('div'); cop.id = 'ffCop'
          cop.innerHTML = '<div class="who"><span>👮</span>Polizei</div><div class="ln"></div><div class="ch"></div>'
          document.body.appendChild(cop)
        }
        if (d.id === copId) { return }
        copId = d.id
        cop.className = d.tag === 'smuggle' ? 'smuggle' : ''
        cop.querySelector('.ln').textContent = d.line || ''
        var box = cop.querySelector('.ch'); box.innerHTML = ''
        ;(d.choices || []).forEach(function (c, i) {
          var b = document.createElement('button'); b.textContent = c.t
          if (c.sub) { var s = document.createElement('small'); s.textContent = c.sub; b.appendChild(s) }
          b.onclick = function () { bngApi.engineLua('if fernfahrer_career then fernfahrer_career.copAnswer(' + (i + 1) + ') end') }
          box.appendChild(b)
        })
      })
      // --- tired at the wheel (2026-11-08): the eyes close for a moment (career.lua 'FernfahrerBlink' { dur }). Two dark
      // lids over the whole screen, moved frame by frame (the pane's CSS transitions stand still) ---
      var lidT = null, lidB = null, lidRaf = 0
      function lids() {
        if (lidT) { return }
        var s = 'position:fixed;left:0;right:0;height:0;z-index:2147480000;pointer-events:none;background:#000;'
        lidT = document.createElement('div'); lidT.style.cssText = s + 'top:0;box-shadow:0 30px 60px 30px #000'
        lidB = document.createElement('div'); lidB.style.cssText = s + 'bottom:0;box-shadow:0 -30px 60px 30px #000'
        document.body.appendChild(lidT); document.body.appendChild(lidB)
      }
      scope.$on('FernfahrerBlink', function (ev, d) {
        lids()
        var dur = Math.max(0.3, (d && d.dur) || 0.5) * 1000, t0 = performance.now(), close = 260, open = 420
        cancelAnimationFrame(lidRaf)
        ;(function step(now) {
          var t = now - t0, k
          if (t < close) { k = t / close } else if (t < close + dur) { k = 1 } else if (t < close + dur + open) { k = 1 - (t - close - dur) / open } else { k = 0 }
          var h = Math.round(k * 54) + 'vh'
          lidT.style.height = h; lidB.style.height = h
          if (t < close + dur + open) { lidRaf = requestAnimationFrame(step) }
        })(t0)
      })
      // --- a crash alone (2026-11-05): the phone at the side – call the police or let it be (accidents.lua 'ask';
      // HUD accident.ask, seconds left). On the page's body: it takes the mouse ---
      var CALL_CSS =
        '#ffCall{position:fixed;right:22px;top:46%;z-index:2147481500;display:flex;align-items:center;gap:12px;padding:12px 14px;pointer-events:auto;' +
          'font-family:FFWave,"Noto Sans",sans-serif;color:#eef1f5;background:linear-gradient(180deg,rgba(24,29,37,.95),rgba(14,17,22,.95));' +
          'border:1px solid rgba(255,255,255,.1);border-radius:16px;box-shadow:0 18px 50px rgba(0,0,0,.45);animation:ffCallIn .5s cubic-bezier(.2,.8,.2,1)}' +
        '@keyframes ffCallIn{from{opacity:0;transform:translateX(40px)}}' +
        '#ffCall .ph{width:46px;height:46px;border-radius:50%;background:#2fbf71;display:flex;align-items:center;justify-content:center;font-size:22px;animation:ffCallRing 1.2s ease-in-out infinite}' +
        '@keyframes ffCallRing{0%,100%{transform:rotate(0)}10%{transform:rotate(-14deg)}20%{transform:rotate(14deg)}30%{transform:rotate(-10deg)}40%{transform:rotate(0)}}' +
        '#ffCall b{display:block;font-size:14.5px;font-weight:900}#ffCall small{display:block;font-size:11.5px;color:#9aa4b2;margin-top:2px;max-width:230px}' +
        '#ffCall .bt{display:flex;flex-direction:column;gap:5px;margin-left:4px}' +
        '#ffCall button{font:800 12px FFWave,"Noto Sans",sans-serif;border-radius:8px;padding:6px 12px;cursor:pointer;border:1px solid #2f3742;background:#1d232c;color:#e9edf2}' +
        '#ffCall button.y{background:#2fbf71;border-color:#2fbf71;color:#08210f}'
      var call = null
      function showCall(a) {
        if (!a || !a.ask) { if (call) { if (call.parentNode) { call.parentNode.removeChild(call) } call = null } return }
        if (!call) {
          if (!document.getElementById('ffCallCss')) { var st = document.createElement('style'); st.id = 'ffCallCss'; st.textContent = CALL_CSS; document.head.appendChild(st) }
          var old = document.getElementById('ffCall'); if (old && old.parentNode) { old.parentNode.removeChild(old) }
          call = document.createElement('div'); call.id = 'ffCall'
          call.innerHTML = '<div class="ph">📞</div><div><b>Unfall – Polizei rufen?</b><small></small></div>' +
            '<div class="bt"><button class="y">Anrufen</button><button class="n">Nein</button></div>'
          document.body.appendChild(call)
          call.querySelector('.y').onclick = function () { bngApi.engineLua('if fernfahrer_career then fernfahrer_career.callPolice() end'); showCall(null) }
          call.querySelector('.n').onclick = function () { bngApi.engineLua('if fernfahrer_career then fernfahrer_career.dismissCall() end'); showCall(null) }
        }
        call.querySelector('small').textContent = 'Nur du betroffen – ohne Anruf kein Bericht, keine Strafe · ' + (a.left || 0) + ' s'
      }
      // under the influence: the vignette and the tint
      var lastFx = -1
      scope.$on('FernfahrerHud', function (ev, h) {
        showStop(h && h.mode ? h.stop : null)
        showCall(h && h.mode ? h.accident : null)
        var v = h && h.vices
        var fx = v && v.fx ? Math.round(v.fx * 50) / 50 : 0
        var thc = v && v.thcShare ? v.thcShare : 0
        if (fx === lastFx) { return }
        lastFx = fx
        // (2026-11-08: drawn by the game now, career.lua L.fxDraw – over the whole page it took the mouse from the camera)
        vig.style.opacity = '0'
        vig.style.display = 'none'
        tint.style.opacity = '0'
        tint.style.display = 'none'
      })
      scope.$on('$destroy', function () {
        if (raf) { cancelAnimationFrame(raf) }
        clearInterval(fitTimer)
        sleepStop()
        // (the HUD rebuilt with the introduction open: closed without marking it done – it comes again)
        if (tut) { var te = tut.el; tut = null; if (te.parentNode) { te.parentNode.removeChild(te) } }
        window.removeEventListener('resize', fit)
      })
    }
  }
}]);
