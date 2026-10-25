/* Orbit — sitio web.
   Una versión en JavaScript de la isla de Orbit: los mismos resortes, la misma forma
   con orejas cóncavas, la estela de luz y los mismos estados que la app de Mac. */
(() => {
  'use strict';

  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const f2 = (v) => Math.round(v * 100) / 100;
  const root = document.documentElement;

  // ---------------------------------------------------------------- Iconos

  const svg = (inner, size = 16, cls = '') =>
    `<svg class="ic ${cls}" viewBox="0 0 24 24" width="${size}" height="${size}" fill="currentColor" aria-hidden="true">${inner}</svg>`;
  const st = (d, w = 2) =>
    `<path d="${d}" fill="none" stroke="currentColor" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"/>`;

  function gearPath() {
    const n = 8, pts = [];
    const p = (r, a) => `${f2(12 + r * Math.cos(a))} ${f2(12 + r * Math.sin(a))}`;
    for (let i = 0; i < n; i++) {
      const a = (i / n) * Math.PI * 2, w = (Math.PI * 2) / n;
      pts.push(p(8.1, a - w * 0.34), p(10.6, a - w * 0.16), p(10.6, a + w * 0.16), p(8.1, a + w * 0.34));
    }
    return `<path fill-rule="evenodd" d="M${pts.join('L')}Z M15.3 12a3.3 3.3 0 1 0-6.6 0a3.3 3.3 0 1 0 6.6 0Z"/>`;
  }

  const forward = '<path d="M2.4 6.5v11c0 .7.8 1.1 1.3.7l7.6-5.5a.85.85 0 0 0 0-1.4L3.7 5.8c-.5-.4-1.3 0-1.3.7zm10 0v11c0 .7.8 1.1 1.3.7l7.6-5.5a.85.85 0 0 0 0-1.4l-7.6-5.5c-.5-.4-1.3 0-1.3.7z"/>';
  const bud = '<circle cx="8.2" cy="6.9" r="3.6"/><rect x="8.3" y="6.6" width="3" height="13.8" rx="1.5"/><circle cx="6.9" cy="6.3" r=".95" fill="#000"/>';
  const ICON = {
    note: '<circle cx="7.6" cy="17.4" r="2.7"/><circle cx="16.4" cy="15.4" r="2.7"/><path d="M8.8 17.4V6.2L19.6 3.8v11.6h-2.4V8.2L11.2 9.6v7.8z"/>',
    calendar: st('M6.5 5h11a3 3 0 0 1 3 3v9.5a3 3 0 0 1-3 3h-11a3 3 0 0 1-3-3V8a3 3 0 0 1 3-3z') + st('M3.5 10h17') + st('M8 3v3.5M16 3v3.5') +
      '<rect x="7" y="12.6" width="2.6" height="2.4" rx=".6"/><rect x="10.7" y="12.6" width="2.6" height="2.4" rx=".6"/><rect x="14.4" y="12.6" width="2.6" height="2.4" rx=".6"/><rect x="7" y="16.1" width="2.6" height="2.4" rx=".6"/><rect x="10.7" y="16.1" width="2.6" height="2.4" rx=".6"/>',
    tray: st('M4 13.5 6.2 6.3A2 2 0 0 1 8.1 5h7.8a2 2 0 0 1 1.9 1.3L20 13.5V18a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z') + st('M4 13.5h4.5l1 2h5l1-2H20'),
    trayDown: st('M4 14 5.6 9.2A2 2 0 0 1 7.5 8H8m8 0h.5a2 2 0 0 1 1.9 1.2L20 14v4a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z') + st('M4 14h4.5l1 2h5l1-2H20') + st('M12 2.5v9m-3.5-3.5L12 11.5l3.5-3.5'),
    gear: gearPath(),
    sun: '<circle cx="12" cy="12" r="4.3"/>' + st('M12 2.3v2.4M12 19.3v2.4M2.3 12h2.4M19.3 12h2.4M5.1 5.1l1.7 1.7M17.2 17.2l1.7 1.7M5.1 18.9l1.7-1.7M17.2 6.8l1.7-1.7', 2.2),
    bolt: '<path d="M13.6 1.8 4.8 13.4h6.1l-1.4 8.8 9.7-12.4h-6.3z"/>',
    airpods: bud + `<g transform="translate(24 0) scale(-1 1)">${bud}</g>`,
    lock: '<rect x="4.8" y="10.4" width="14.4" height="10.8" rx="2.8"/>' + st('M8 10.4V7.6a4 4 0 0 1 8 0v2.8', 2.4),
    unlock: '<rect x="4.8" y="10.4" width="14.4" height="10.8" rx="2.8"/>' + st('M8 10.4V7.6a4 4 0 0 1 7.7-1.5', 2.4),
    shuffle: st('M3 7h3.2c2.2 0 3.2 1.3 4.6 3.8l1.4 2.4c1.4 2.5 2.4 3.8 4.6 3.8H20') + st('M3 17h3.2c1.5 0 2.4-.6 3.3-1.8M13.5 8.8c.9-1.2 1.8-1.8 3.3-1.8H20') + st('M17.5 4.5 20 7l-2.5 2.5M17.5 14.5 20 17l-2.5 2.5'),
    repeat: st('M4 12V9.5A3.5 3.5 0 0 1 7.5 6H19') + st('M16.5 3.5 19 6l-2.5 2.5') + st('M20 12v2.5a3.5 3.5 0 0 1-3.5 3.5H5') + st('M7.5 20.5 5 18l2.5-2.5'),
    play: '<path d="M7.2 4.7v14.6c0 .78.86 1.25 1.52.83l11.3-7.3a1 1 0 0 0 0-1.66L8.72 3.87A1 1 0 0 0 7.2 4.7z"/>',
    pause: '<rect x="5.6" y="4.2" width="4.4" height="15.6" rx="1.4"/><rect x="14" y="4.2" width="4.4" height="15.6" rx="1.4"/>',
    forward,
    backward: `<g transform="translate(24 0) scale(-1 1)">${forward}</g>`,
    quote: st('M5 4.5h14A2.5 2.5 0 0 1 21.5 7v8a2.5 2.5 0 0 1-2.5 2.5h-6.5L8 21v-3.5H5A2.5 2.5 0 0 1 2.5 15V7A2.5 2.5 0 0 1 5 4.5z', 1.9) + '<circle cx="9" cy="11" r="1.5"/><circle cx="15" cy="11" r="1.5"/>',
    quoteOn: '<path d="M5 4.5h14A2.5 2.5 0 0 1 21.5 7v8a2.5 2.5 0 0 1-2.5 2.5h-6.5L8 21v-3.5H5A2.5 2.5 0 0 1 2.5 15V7A2.5 2.5 0 0 1 5 4.5z"/><circle cx="9" cy="11" r="1.5" fill="#000"/><circle cx="15" cy="11" r="1.5" fill="#000"/>',
    laptop: st('M5.5 5.5h13a1 1 0 0 1 1 1V16h-15V6.5a1 1 0 0 1 1-1z') + st('M2.5 18.5h19'),
    airdrop: '<circle cx="12" cy="12" r="2"/>' + st('M8.6 8.6a4.8 4.8 0 0 0 0 6.8M15.4 8.6a4.8 4.8 0 0 1 0 6.8M5.6 5.6a9 9 0 0 0 0 12.8M18.4 5.6a9 9 0 0 1 0 12.8'),
    trash: st('M4.5 7h15M9.5 4h5M6.5 7l1 12.6A1.6 1.6 0 0 0 9.1 21h5.8a1.6 1.6 0 0 0 1.6-1.4L17.5 7'),
    chevL: st('M15 5l-7 7 7 7', 2.8),
    chevR: st('M9 5l7 7-7 7', 2.8)
  };

  function speaker(level, muted) {
    const on = (t) => (muted ? 0.18 : level >= t ? 1 : 0.3);
    return svg(
      '<path d="M3.2 9.1h3.4L11.2 5v14l-4.6-4.1H3.2a.8.8 0 0 1-.8-.8V9.9a.8.8 0 0 1 .8-.8z"/>' +
      `<g opacity="${on(0.01)}">${st('M14.4 9.4a3.6 3.6 0 0 1 0 5.2', 2)}</g>` +
      `<g opacity="${on(0.34)}">${st('M16.9 7a7 7 0 0 1 0 10', 2)}</g>` +
      `<g opacity="${on(0.67)}">${st('M19.4 4.6a10.3 10.3 0 0 1 0 14.8', 2)}</g>`,
      15, 'spk');
  }

  let planetId = 0;
  function planet(size) {
    const id = 'pg' + (++planetId);
    return `<svg class="planet-svg" viewBox="-13 -13 26 26" width="${size}" height="${size}" aria-hidden="true">
      <defs><linearGradient id="${id}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#B985FF"/><stop offset="1" stop-color="#FF6B9E"/></linearGradient></defs>
      <g transform="rotate(-22)">
        <path d="M-12 0A12 4.1 0 0 1 12 0" fill="none" stroke="rgba(255,255,255,.72)" stroke-width="1.9" stroke-linecap="round"/>
        <circle class="moon back" r="2.2" fill="#fff"/>
        <circle r="6.8" fill="url(#${id})"/>
        <path d="M-12 0A12 4.1 0 0 0 12 0" fill="none" stroke="#fff" stroke-width="1.9" stroke-linecap="round"/>
        <circle class="moon front" r="2.2" fill="#fff"/>
      </g></svg>`;
  }

  // ---------------------------------------------------------------- Portadas inventadas

  const dataURI = (s) => 'data:image/svg+xml;utf8,' + encodeURIComponent(s);
  function coverSunset() {
    let stripes = '';
    for (let i = 0; i < 5; i++) {
      const h = 2.6 - 0.4 * i;
      const y = 70 - 2 - 4.5 * i - h;
      stripes += `<rect x="0" y="${f2(y)}" width="100" height="${f2(h)}" fill="#ED5590"/>`;
    }
    let grid = '';
    for (let i = -6; i <= 6; i++) grid += `<line x1="50" y1="70" x2="${50 + i * 16}" y2="100"/>`;
    for (let i = 1; i <= 5; i++) { const t = i / 5; const y = 70 + 30 * t * t; grid += `<line x1="0" y1="${f2(y)}" x2="100" y2="${f2(y)}"/>`; }
    return dataURI(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
      <defs><linearGradient id="s" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#170D45"/><stop offset=".6" stop-color="#8C2A9E"/><stop offset="1" stop-color="#FF5C8F"/></linearGradient>
      <linearGradient id="u" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFDC5C"/><stop offset="1" stop-color="#FF5F80"/></linearGradient></defs>
      <rect width="100" height="100" fill="url(#s)"/><circle cx="50" cy="54" r="28" fill="url(#u)"/>${stripes}
      <rect y="70" width="100" height="30" fill="#1A0833"/><g stroke="#FF66C0" stroke-width=".7" opacity=".9">${grid}</g></svg>`);
  }
  function coverOcean() {
    return dataURI(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
      <defs><linearGradient id="o" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#071438"/><stop offset=".55" stop-color="#174C8A"/><stop offset="1" stop-color="#3DC8F0"/></linearGradient></defs>
      <rect width="100" height="100" fill="url(#o)"/><circle cx="70" cy="28" r="12" fill="#EAF6FF"/><circle cx="66" cy="25" r="12" fill="#0E2A5C" opacity=".35"/>
      <path d="M0 64c12-6 22-6 34 0s22 6 34 0 22-6 32 0v36H0z" fill="#1E7FC0" opacity=".85"/>
      <path d="M0 74c12-6 22-6 34 0s22 6 34 0 22-6 32 0v26H0z" fill="#2CA6DE"/>
      <path d="M0 85c12-6 22-6 34 0s22 6 34 0 22-6 32 0v15H0z" fill="#7FE0FF"/></svg>`);
  }

  const TRACKS = [
    { title: 'Luz de Neón', artist: 'Aurora Vale', art: coverSunset(), accent: '#FF5C93', duration: 214,
      lyrics: [[58, 'Brillas aunque apague la ciudad'], [64, 'Giro a tu alrededor sin pensar'], [70, 'Somos luz de neón en la oscuridad'],
        [77, 'Y no quiero volver a aterrizar'], [84, 'Una órbita más, una vez más'], [91, 'Tu voz es la señal que sigo al regresar'],
        [98, 'Y en la noche te vuelvo a encontrar'], [105, '♪']] },
    { title: 'Marea Alta', artist: 'Los Satélites', art: coverOcean(), accent: '#45CFFF', duration: 187,
      lyrics: [[8, 'Sube la marea, sube la canción'], [14, 'Cada ola trae tu dirección'], [20, 'Bajo la luna nadie tiene prisa'],
        [26, 'Te sigo el paso con la brisa'], [32, '♪']] }
  ];

  const TINT = {
    charging: '#3FDC6E', full: '#3FDC6E', low: '#FF4D4D', unplugged: '#FFFFFF', airpods: '#5B8CFF',
    volume: '#FFFFFF', brightness: '#FFC857', lock: '#FFFFFF', unlock: '#3FDC6E', calendarAlert: '#FF8A3D',
    tray: '#5B8CFF', welcome: '#9B6BFF'
  };
  const WING = { volume: 84, brightness: 84, charging: 92, full: 92, low: 98, unplugged: 84, airpods: 52, lock: 40, unlock: 40, calendarAlert: 80, tray: 64, welcome: 74 };
  const EXTRA = { calendarAlert: 30, welcome: 30 };
  const PAGE_H = { music: 144, calendar: 160, tray: 130, drop: 130 };
  const STYLES = {
    orbit: { w: [0.42, 0.72], h: [0.52, 0.78], jelly: true },
    smooth: { w: [0.5, 1], h: [0.5, 1], jelly: false },
    snappy: { w: [0.26, 0.86], h: [0.28, 0.9], jelly: false }
  };

  // ---------------------------------------------------------------- Resortes

  class Spring {
    constructor(v) { this.v = v; this.t = v; this.vel = 0; this.r = 0.4; this.d = 0.8; }
    to(t, r, d) { this.t = t; this.r = r; this.d = d; }
    snap(v) { this.v = this.t = v; this.vel = 0; }
    step(dt) {
      if (this.v === this.t && this.vel === 0) return false;
      const k = Math.pow((2 * Math.PI) / this.r, 2);
      const c = (4 * Math.PI * this.d) / this.r;
      const n = Math.max(1, Math.ceil(dt / (1 / 240)));
      const h = dt / n;
      for (let i = 0; i < n; i++) {
        const a = -k * (this.v - this.t) - c * this.vel;
        this.vel += a * h;
        this.v += this.vel * h;
      }
      if (Math.abs(this.v - this.t) < 0.02 && Math.abs(this.vel) < 0.02) { this.v = this.t; this.vel = 0; }
      return true;
    }
  }

  // ---------------------------------------------------------------- Forma

  function bodyPath(W, H, ear, bottom, top) {
    if (W < 0.5 || H < 0.5) return '';
    const e = clamp(ear, 0, Math.min(W / 4, H / 2));
    const L = e, R = W - e, bw = R - L;
    const tc = clamp(top, 0, Math.min(bw / 2, H / 2));
    const b = clamp(bottom, 0, Math.min(bw / 2, Math.max(0, H - Math.max(e, tc))));
    if (e < 0.5 && tc > 0.5) {
      return `M${f2(L + tc)} 0H${f2(R - tc)}A${f2(tc)} ${f2(tc)} 0 0 1 ${f2(R)} ${f2(tc)}V${f2(H - b)}A${f2(b)} ${f2(b)} 0 0 1 ${f2(R - b)} ${f2(H)}H${f2(L + b)}A${f2(b)} ${f2(b)} 0 0 1 ${f2(L)} ${f2(H - b)}V${f2(tc)}A${f2(tc)} ${f2(tc)} 0 0 1 ${f2(L + tc)} 0Z`;
    }
    let d = 'M0 0';
    d += e > 0.5 ? `A${f2(e)} ${f2(e)} 0 0 1 ${f2(L)} ${f2(e)}` : `H${f2(L)}`;
    d += `V${f2(H - b)}A${f2(b)} ${f2(b)} 0 0 0 ${f2(L + b)} ${f2(H)}H${f2(R - b)}A${f2(b)} ${f2(b)} 0 0 0 ${f2(R)} ${f2(H - b)}V${f2(e)}`;
    if (e > 0.5) d += `A${f2(e)} ${f2(e)} 0 0 1 ${f2(W)} 0`;
    return d + 'Z';
  }

  function halfPath(W, H, ear, bottom, top) {
    if (W < 0.5 || H < 0.5) return '';
    const e = clamp(ear, 0, Math.min(W / 4, H / 2));
    const L = e, R = W - e, bw = R - L, mid = W / 2;
    const tc = clamp(top, 0, Math.min(bw / 2, H / 2));
    const b = clamp(bottom, 0, Math.min(bw / 2, Math.max(0, H - Math.max(e, tc))));
    let d;
    if (e < 0.5 && tc > 0.5) d = `M${f2(mid)} 0H${f2(L + tc)}A${f2(tc)} ${f2(tc)} 0 0 0 ${f2(L)} ${f2(tc)}`;
    else d = 'M0 0' + (e > 0.5 ? `A${f2(e)} ${f2(e)} 0 0 1 ${f2(L)} ${f2(e)}` : `H${f2(L)}`);
    return d + `V${f2(H - b)}A${f2(b)} ${f2(b)} 0 0 0 ${f2(L + b)} ${f2(H)}H${f2(mid)}`;
  }

  // ---------------------------------------------------------------- Música compartida

  const music = {
    index: 0,
    playing: true,
    elapsed: 70,
    get track() { return TRACKS[this.index]; },
    lyricIndex() {
      const lines = this.track.lyrics;
      let found = -1;
      for (let i = 0; i < lines.length; i++) if (lines[i][0] <= this.elapsed + 0.25) found = i;
      return found;
    }
  };
  const clock = (s) => { s = Math.max(0, Math.floor(s)); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`; };

  // ---------------------------------------------------------------- La isla

  class Island {
    constructor(el) {
      this.el = el;
      el.innerHTML = `
        <div class="island-scale"><div class="island-jelly">
          <div class="island-glow"></div>
          <svg class="island-shape"><path class="fill"/><path class="edge" opacity="0"/></svg>
          <div class="island-hit"></div>
          <div class="island-content"></div>
          <svg class="island-comet">
            <defs>
              <filter id="cb1" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="4"/></filter>
              <filter id="cb2" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation=".9"/></filter>
              <filter id="cb3" x="-100%" y="-400%" width="300%" height="900%"><feGaussianBlur stdDeviation="7"/></filter>
            </defs>
            <g class="cl"><path class="c1" pathLength="1" stroke-width="6" filter="url(#cb1)"/><path class="c2" pathLength="1" stroke-width="2.4" filter="url(#cb2)"/><path class="c3" pathLength="1" stroke-width="2" stroke="#fff"/></g>
            <g class="cr"><path class="c1" pathLength="1" stroke-width="6" filter="url(#cb1)"/><path class="c2" pathLength="1" stroke-width="2.4" filter="url(#cb2)"/><path class="c3" pathLength="1" stroke-width="2" stroke="#fff"/></g>
            <ellipse class="bg" filter="url(#cb3)"/><ellipse class="bc" fill="#fff" filter="url(#cb2)"/>
          </svg>
        </div></div>`;
      this.scaleEl = $('.island-scale', el);
      this.jellyEl = $('.island-jelly', el);
      this.glow = $('.island-glow', el);
      this.shape = $('.island-shape', el);
      this.fill = $('.fill', this.shape);
      this.edge = $('.edge', this.shape);
      this.hit = $('.island-hit', el);
      this.content = $('.island-content', el);
      this.cometSvg = $('.island-comet', el);
      this.cl = $$('.cl path', el);
      this.cr = $$('.cr path', el);
      this.crGroup = $('.cr', el);
      this.burstGlow = $('.bg', el);
      this.burstCore = $('.bc', el);
      for (const path of [...this.cl, ...this.cr]) { path.setAttribute('stroke-dasharray', '0 3'); path.setAttribute('opacity', 0); }

      this.metrics = { nw: 186, nh: 32, floating: false, virtual: false };
      this.style = 'orbit';
      this.speed = 1;
      this.cometOn = !reduced;
      this.glowOn = true;
      this.scale = 1;

      this.music = false;
      this.lyrics = false;
      this.expanded = false;
      this.page = 'music';
      this.drag = false;
      this.dropHot = null;
      this.transient = null;
      this.hidden = false;
      this.hover = false;
      this.user = false;
      this.userPage = 'music';
      this.trayItems = [['Atardecer.jpg', 'img'], ['Presentación.key', 'key'], ['Notas.txt', 'txt']];
      this.newTile = null;

      const L = this.layoutFor({ type: 'idle' });
      this.sp = {
        w: new Spring(L.w + 2 * L.ear), h: new Spring(L.h), ear: new Spring(L.ear), bot: new Spring(L.bottom),
        top: new Spring(L.top), inset: new Spring(0), jx: new Spring(1), jy: new Spring(1)
      };
      this.key = '';
      this.layer = null;
      this.comet = null;
      this.last = performance.now();
      this.live = { waves: [], prog: [], lyr: [], vol: null };
      this.listeners = new Set();

      this.bindPointer();
      requestAnimationFrame((t) => this.frame(t));
    }

    // --- Estado

    presentation() {
      if (this.user) return { type: 'expanded', page: this.drag ? 'drop' : this.userPage };
      if (this.drag) return { type: 'expanded', page: 'drop' };
      if (this.expanded) return { type: 'expanded', page: this.page };
      if (this.transient) return { type: 'transient', kind: this.transient };
      if (this.music) return { type: 'music' };
      return { type: this.hidden && !this.hover ? 'hidden' : 'idle' };
    }

    keyOf(p) {
      if (p.type === 'transient') return 't.' + p.kind.type;
      if (p.type === 'expanded') return 'x';
      return p.type;
    }

    layoutFor(p, noHover = false) {
      const { nw: n, nh: h, floating: fl } = this.metrics;
      const compact = (wing, extra = 0) => ({
        w: n + 2 * wing, h: h + extra, ear: fl ? 0 : 7,
        bottom: fl ? (extra ? 22 : h / 2) : (extra ? 20 : 12), top: fl ? (extra ? 22 : h / 2) : 0
      });
      let L;
      switch (p.type) {
        case 'hidden': L = { w: n * 0.62, h: 0, ear: 0, bottom: 0, top: 0 }; break;
        case 'idle': L = fl ? { w: n, h, ear: 0, bottom: h / 2, top: h / 2 } : { w: n, h, ear: this.metrics.virtual ? 5 : 0, bottom: 10, top: 0 }; break;
        case 'music': L = compact(Math.max(h + 8, 40)); break;
        case 'transient': L = compact(WING[p.kind.type] || 60, EXTRA[p.kind.type] || 0); break;
        default: L = { w: Math.max(n + 256, 452), h: h + PAGE_H[p.page], ear: fl ? 0 : 14, bottom: 32, top: fl ? 32 : 0 };
      }
      if (!noHover && this.hover && !this.user && p.type !== 'expanded' && p.type !== 'hidden') {
        L = { ...L, w: L.w + 18, h: L.h + 3, ear: fl ? L.ear : Math.max(L.ear, 7), bottom: fl ? L.bottom : Math.max(L.bottom, 12) };
      }
      return L;
    }

    reset() {
      this.music = false; this.lyrics = false; this.expanded = false; this.drag = false; this.dropHot = null;
      this.transient = null; this.hidden = false; this.page = 'music';
      clearTimeout(this.tTimer);
    }

    show(type, data = {}, duration = 2600) {
      const isNew = !this.transient || this.transient.type !== type;
      this.transient = { type, ...data };
      if (isNew && !this.expanded && !this.user) this.fireComet(data.tint || TINT[type] || '#fff');
      if (!isNew) this.refreshTransient();
      clearTimeout(this.tTimer);
      if (duration) this.tTimer = setTimeout(() => { this.transient = null; }, duration);
      this.emit();
    }

    clearTransient() { clearTimeout(this.tTimer); this.transient = null; }

    fireComet(color) {
      if (!this.cometOn) return;
      this.comet = { start: performance.now(), color };
      for (const p of [...this.cl, ...this.cr]) {
        if (!p.classList.contains('c3')) p.setAttribute('stroke', color);
      }
      this.burstGlow.setAttribute('fill', color);
    }

    jelly() {
      if (reduced || !STYLES[this.style].jelly) return;
      this.sp.jx.r = 0.42; this.sp.jx.d = 0.5; this.sp.jx.vel += 0.9;
      this.sp.jy.r = 0.42; this.sp.jy.d = 0.5; this.sp.jy.vel -= 0.9;
    }

    nextTrack(delta = 1) {
      music.index = (music.index + delta + TRACKS.length) % TRACKS.length;
      music.elapsed = music.index === 0 ? 62 : 6;
      const t = music.track;
      for (const box of $$('[data-art]')) {
        const old = box.querySelector('img:not(.flip-out)');
        const img = new Image();
        img.src = t.art; img.alt = '';
        img.className = reduced ? '' : 'flip-in';
        box.appendChild(img);
        if (old) {
          if (reduced) old.remove();
          else { old.classList.add('flip-out'); setTimeout(() => old.remove(), 220); }
        }
      }
      for (const n of $$('[data-title]')) n.textContent = t.title;
      for (const n of $$('[data-artist]')) n.textContent = t.artist;
      for (const n of $$('[data-lyrics]')) n.innerHTML = lyricLines(t);
      root.style.setProperty('--accent', t.accent);
      this.emit();
    }

    togglePlay() {
      music.playing = !music.playing;
      for (const b of $$('[data-act="play"]')) b.innerHTML = svg(music.playing ? ICON.pause : ICON.play, b.dataset.size || 24);
    }

    on(fn) { this.listeners.add(fn); }
    emit() { for (const fn of this.listeners) fn(this); }

    // --- Cursor real

    bindPointer() {
      let enterTimer = 0, leaveTimer = 0;
      const inside = (x, y) => {
        const L = this.currentOuter;
        if (!L) return false;
        const s = this.scale;
        const cx = innerWidth / 2;
        const pad = this.user ? 14 : 8;
        const w = L.w * s / 2 + pad;
        const top = 0, bottom = (L.h + L.inset) * s + (this.user ? 14 : 2);
        return Math.abs(x - cx) <= w && y >= top && y <= bottom;
      };
      addEventListener('pointermove', (e) => {
        if (e.pointerType === 'touch') return;
        const now = inside(e.clientX, e.clientY);
        if (now && !this.hover) {
          clearTimeout(leaveTimer);
          this.hover = true;
          document.dispatchEvent(new CustomEvent('island-hover'));
          enterTimer = setTimeout(() => {
            if (!this.hover) return;
            this.userPage = this.expanded ? this.page : (this.drag ? 'tray' : 'music');
            this.user = true;
          }, 120);
        } else if (!now && this.hover) {
          clearTimeout(enterTimer);
          this.hover = false;
          leaveTimer = setTimeout(() => { if (!this.hover) this.user = false; }, 220);
        }
      }, { passive: true });
      this.hit.addEventListener('click', () => {
        if (this.user) return;
        this.userPage = this.expanded ? this.page : 'music';
        this.user = true;
        document.dispatchEvent(new CustomEvent('island-hover'));
      });
      document.addEventListener('pointerdown', (e) => {
        if (e.pointerType === 'touch' && this.user && !this.el.contains(e.target)) this.user = false;
      });
    }

    // --- Contenido

    swap(p, key) {
      const old = this.layer;
      const L = this.layoutFor(p, true);
      const layer = document.createElement('div');
      layer.className = 'layer' + (reduced ? '' : ' pre');
      layer.style.width = L.w + 'px';
      layer.style.height = L.h + 'px';
      layer.innerHTML = this.render(p, L);
      this.content.appendChild(layer);
      this.layer = layer;
      this.bindLayer(layer, p);
      layer.addEventListener('click', (e) => this.onLayerClick(e));
      if (!reduced) requestAnimationFrame(() => requestAnimationFrame(() => layer.classList.remove('pre')));
      if (old) {
        old.classList.add('out');
        setTimeout(() => old.remove(), 200);
      }
      this.content.classList.toggle('interactive', p.type === 'expanded');
      if (key !== 'hidden' && this.key !== '') this.jelly();
      this.key = key;
      this.pageShown = p.type === 'expanded' ? p.page : null;
      this.lyricsShown = this.lyrics;
    }

    render(p, L) {
      const { nw, nh } = this.metrics;
      const wing = (L.w - nw) / 2;
      const wings = (l, r, extra = '') =>
        `<div class="wings" style="grid-template-columns:${wing}px ${nw}px ${wing}px;height:${nh}px">
          <div class="l">${l}</div><div class="c"></div><div class="r">${r}</div></div>${extra}`;
      const t = music.track;
      switch (p.type) {
        case 'hidden':
        case 'idle':
          return '';
        case 'music':
          return `<div class="wings" style="grid-template-columns:${wing}px ${nw}px ${wing}px;height:${nh}px">
            <div class="c" style="justify-self:center"><div class="art" data-art style="width:${nh - 12}px;height:${nh - 12}px;border-radius:6px;overflow:hidden;box-shadow:0 0 10px color-mix(in oklab,var(--accent) 45%,transparent)"><img src="${t.art}" alt=""></div></div>
            <div></div>
            <div class="c" style="justify-self:center">${wave(4, 17, 13, 2.6)}</div></div>`;
        case 'transient':
          return this.renderTransient(p.kind, wings);
        default:
          return this.renderExpanded(p.page, L);
      }
    }

    renderTransient(k, wings) {
      const num = (v) => `<span class="num" data-vnum style="width:24px;text-align:right">${Math.round(v * 100)}</span>`;
      const level = (v) => `<div class="lvl" style="width:36px"><b data-vbar style="width:${v * 100}%"></b></div>${num(v)}`;
      const batt = (lvl, color, charging) =>
        `<div class="batt" style="--c:${color}"><div class="shell"><b style="width:${Math.max(2.5, 21.5 * lvl / 100)}px"></b>${charging ? svg(ICON.bolt, 9) : ''}</div><div class="tip"></div></div>`;
      switch (k.type) {
        case 'volume': return wings(`<span data-vicon>${speaker(k.level, k.muted)}</span>`, level(k.muted ? 0 : k.level));
        case 'brightness': return wings(`<span style="color:var(--gold)">${svg(ICON.sun, 15)}</span>`, level(k.level));
        case 'charging': return wings('<span class="lbl">Cargando</span>', `<span class="num" style="color:var(--green)">${k.level}%</span>${batt(k.level, 'var(--green)', true)}`);
        case 'full': return wings('<span class="lbl">Cargado</span>', `<span class="num" style="color:var(--green)">100%</span>${batt(100, 'var(--green)', false)}`);
        case 'low': return wings('<span class="lbl" style="color:var(--red)">Batería baja</span>', `<span class="num" style="color:var(--red)">${k.level}%</span>${batt(k.level, 'var(--red)', false)}`);
        case 'airpods': {
          const c = 45.24, v = k.battery / 100;
          return wings(`<span class="bounce">${svg(ICON.airpods, 18)}</span>`,
            `<svg class="ring" viewBox="0 0 18 18" width="17" height="17"><circle class="track" cx="9" cy="9" r="7.2"/><circle class="val" data-ring="${f2(c * (1 - v))}" cx="9" cy="9" r="7.2" stroke="${k.battery < 20 ? 'var(--red)' : 'var(--green)'}" stroke-dasharray="${c}" stroke-dashoffset="${c}"/></svg>`);
        }
        case 'lock': return wings(svg(ICON.lock, 14), '');
        case 'unlock': return wings(`<span style="color:var(--green)">${svg(ICON.unlock, 14)}</span>`, '');
        case 'calendarAlert': return wings(`<span style="color:var(--blue)">${svg(ICON.calendar, 15)}</span>`, `<span class="lbl">en ${k.minutes} min</span>`,
          `<div class="sub" style="height:24px;line-height:22px">${k.title}</div>`);
        case 'tray': return wings(svg(ICON.trayDown, 15), `<span class="lbl">+${k.count}</span>`);
        case 'welcome': return wings(planet(19), '<span class="lbl">Hola</span>', '<div class="sub" style="height:24px;line-height:22px;color:rgba(255,255,255,.66)">Pasa el cursor por aquí</div>');
        default: return wings('', '');
      }
    }

    renderExpanded(page, L) {
      const { nw, nh } = this.metrics;
      const side = (L.w - nw) / 2;
      const pages = ['music', 'calendar', 'tray'];
      const active = page === 'drop' ? -1 : pages.indexOf(page);
      const tabs = pages.map((pg) => `<button class="tab${pg === page ? ' on' : ''}" data-page="${pg}" aria-label="${pg}">${svg(ICON[pg === 'music' ? 'note' : pg], 12)}</button>`).join('');
      const head = `<div class="hdr" style="height:${nh}px;--i:0" data-s>
          <div style="width:${side}px"><div class="tabs"><span class="pill" style="transform:translateX(${Math.max(0, active) * 32}px);opacity:${active < 0 ? 0 : 1}"></span>${tabs}</div></div>
          <div class="hdr-r" style="width:${side - 14}px;justify-content:flex-end">
            <span class="num" style="font-size:11px">80%</span>
            <div class="batt" style="--c:var(--green)"><div class="shell" style="width:21px;height:10.5px"><b style="width:13.6px"></b>${svg(ICON.bolt, 8)}</div><div class="tip"></div></div>
            <button class="ibtn sm" aria-label="Ajustes">${svg(ICON.gear, 12)}</button>
          </div></div>`;
      return head + `<div class="page-host">${this.renderPage(page, L)}</div>`;
    }

    renderPage(page, L) {
      const t = music.track;
      if (page === 'music') {
        const info = this.lyrics
          ? `<div class="lyr" data-s style="--i:1"><div class="lyr-col" data-lyrics>${lyricLines(t)}</div></div>`
          : `<div class="xm-info" data-s style="--i:1">
              <div class="art" data-art><img src="${t.art}" alt=""></div>
              <div class="xm-text"><div class="xm-title" data-title>${t.title}</div><div class="xm-artist" data-artist>${t.artist}</div></div>
              ${wave(5, 28, 22, 3)}
            </div>`;
        return `<div class="xm">${info}
          <div class="prog" data-s style="--i:2" data-prog><span class="t1"></span><div class="bar"><b></b></div><span class="t2"></span></div>
          <div class="ctrls" data-s style="--i:3">
            <button class="ibtn ${this.lyrics ? 'accent' : 'dim'}" data-act="lyrics" aria-label="Letra">${svg(this.lyrics ? ICON.quoteOn : ICON.quote, 15)}</button>
            <div class="mid-group">
              <button class="ibtn dim" aria-label="Aleatorio">${svg(ICON.shuffle, 14)}</button>
              <button class="ibtn mid" data-act="prev" aria-label="Anterior">${svg(ICON.backward, 19)}</button>
              <button class="ibtn big" data-act="play" data-size="24" aria-label="Reproducir o pausar">${svg(music.playing ? ICON.pause : ICON.play, 24)}</button>
              <button class="ibtn mid" data-act="next" aria-label="Siguiente">${svg(ICON.forward, 19)}</button>
              <button class="ibtn dim" aria-label="Repetir">${svg(ICON.repeat, 14)}</button>
            </div>
            <button class="ibtn dim" aria-label="Salida de audio">${svg(ICON.laptop, 15)}</button>
          </div></div>`;
      }
      if (page === 'calendar') return renderCalendar();
      if (page === 'tray') {
        const tiles = this.trayItems.map(([name, kind], i) =>
          `<div class="tile${this.newTile === name ? ' new' : ''}" data-s style="--i:${i + 2}"><div class="doc ${kind}"><b>${name.split('.').pop().toUpperCase()}</b></div><span>${name}</span></div>`).join('');
        return `<div class="tr"><div class="tr-head" data-s style="--i:1"><span>${this.trayItems.length} en la bandeja</span>
          <div><button class="ibtn sm" aria-label="AirDrop">${svg(ICON.airdrop, 13)}</button><button class="ibtn sm" aria-label="Vaciar">${svg(ICON.trash, 13)}</button></div></div>
          <div class="tr-tiles">${tiles}</div></div>`;
      }
      // Zonas para soltar
      return `<div class="zones">
        <div class="zone${this.dropHot === 'tray' ? ' hot' : ''}" data-zone="tray" style="--c:var(--blue);--i:1" data-s>${svg(ICON.trayDown, 24)}Guardar en la bandeja</div>
        <div class="zone${this.dropHot === 'air' ? ' hot' : ''}" data-zone="air" style="--c:#9B6BFF;--i:2" data-s>${svg(ICON.airdrop, 24)}AirDrop</div></div>`;
    }

    bindLayer(layer, p) {
      this.live.waves = $$('.wave', layer).concat(this.live.waves.filter((w) => w.isConnected && !this.content.contains(w)));
      this.live.prog = $$('[data-prog]');
      this.live.lyr = $$('[data-lyrics]');
      this.live.vol = p.type === 'transient' ? { bar: $('[data-vbar]', layer), num: $('[data-vnum]', layer), icon: $('[data-vicon]', layer) } : null;
      const ring = $('[data-ring]', layer);
      if (ring) setTimeout(() => ring.setAttribute('stroke-dashoffset', ring.dataset.ring), 30);
    }

    onLayerClick(e) {
      const btn = e.target.closest('button');
      if (!btn) return;
      if (btn.dataset.page) { this.setPage(btn.dataset.page); return; }
      const act = btn.dataset.act;
      if (act === 'play') this.togglePlay();
      if (act === 'next') this.nextTrack(1);
      if (act === 'prev') this.nextTrack(-1);
      if (act === 'lyrics') { this.lyrics = !this.lyrics; this.repaintPage(); }
    }

    snapTo(p) {
      const L = this.layoutFor(p, true);
      this.sp.w.snap(L.w + 2 * L.ear); this.sp.h.snap(L.h); this.sp.ear.snap(L.ear);
      this.sp.bot.snap(L.bottom); this.sp.top.snap(L.top);
      this.dirty = true;
    }

    setPage(page) {
      if (this.user) this.userPage = page; else this.page = page;
    }

    repaintPage() {
      const host = this.layer && $('.page-host', this.layer);
      if (!host) return;
      const p = this.presentation();
      if (p.type !== 'expanded') return;
      const L = this.layoutFor(p, true);
      const next = document.createElement('div');
      next.className = 'page-host';
      next.innerHTML = this.renderPage(p.page, L);
      host.replaceWith(next);
      this.pageShown = p.page;
      this.lyricsShown = this.lyrics;
      this.layer.style.height = L.h + 'px';
      const tabsEl = $('.tabs', this.layer);
      if (tabsEl) {
        const pages = ['music', 'calendar', 'tray'];
        const i = pages.indexOf(p.page);
        $('.pill', tabsEl).style.transform = `translateX(${Math.max(0, i) * 32}px)`;
        $('.pill', tabsEl).style.opacity = i < 0 ? 0 : 1;
        for (const b of $$('.tab', tabsEl)) b.classList.toggle('on', b.dataset.page === p.page);
      }
      this.bindLayer(this.layer, p);
    }

    refreshTransient() {
      const k = this.transient;
      const v = this.live.vol;
      if (!k || !v) return;
      if (k.type === 'volume' || k.type === 'brightness') {
        const level = k.muted ? 0 : k.level;
        if (v.bar) v.bar.style.width = level * 100 + '%';
        if (v.num) v.num.textContent = Math.round(level * 100);
        if (v.icon && k.type === 'volume') v.icon.innerHTML = speaker(k.level, k.muted);
      }
    }

    // --- Cuadro a cuadro

    frame(now) {
      const dt = clamp((now - this.last) / 1000, 0, 0.05);
      this.last = now;
      const s = this.scale;
      const p = this.presentation();
      const key = this.keyOf(p);
      if (key !== this.key) this.swap(p, key);
      else if (p.type === 'expanded' && (p.page !== this.pageShown || this.lyrics !== this.lyricsShown)) this.repaintPage();

      const L = this.layoutFor(p);
      const style = STYLES[reduced ? 'smooth' : this.style];
      const k = 1 / this.speed;
      const W = L.w + 2 * L.ear;
      this.sp.w.to(W, style.w[0] * k, style.w[1]);
      this.sp.ear.to(L.ear, style.w[0] * k, style.w[1]);
      this.sp.top.to(L.top, style.w[0] * k, style.w[1]);
      this.sp.h.to(L.h, style.h[0] * k, style.h[1]);
      this.sp.bot.to(L.bottom, style.h[0] * k, style.h[1]);
      this.sp.inset.to(this.metrics.floating ? 6 : 0, 0.4, 0.8);
      let moving = false;
      for (const sp of Object.values(this.sp)) moving = sp.step(dt) || moving;

      const w = Math.max(0, this.sp.w.v), h = Math.max(0, this.sp.h.v), ear = Math.max(0, this.sp.ear.v);
      const bot = Math.max(0, this.sp.bot.v), top = Math.max(0, this.sp.top.v), inset = this.sp.inset.v;
      this.currentOuter = { w, h, inset };

      if (moving || this.comet || !this.drawn || this.dirty) {
        this.drawn = true; this.dirty = false;
        this.scaleEl.style.transform = `scale(${s})`;
        this.jellyEl.style.transform = `scale(${f2(this.sp.jx.v * 1000) / 1000}, ${f2(this.sp.jy.v * 1000) / 1000})`;
        const x = -w / 2;
        for (const node of [this.shape, this.cometSvg]) {
          node.setAttribute('width', Math.max(1, w));
          node.setAttribute('height', Math.max(1, h + 20));
          node.style.transform = `translate(${f2(x)}px, ${f2(inset)}px)`;
        }
        this.fill.setAttribute('d', bodyPath(w, h, ear, bot, top));
        const half = halfPath(w, h, ear, bot, top);
        this.edge.setAttribute('d', half + ' ' + mirrorPath(half, w));
        this.edge.setAttribute('opacity', p.type === 'expanded' ? 1 : 0);
        const bw = Math.max(0, w - 2 * ear);
        Object.assign(this.content.style, {
          width: bw + 'px', height: h + 'px',
          transform: `translate(${f2(-bw / 2)}px, ${f2(inset)}px)`,
          borderRadius: top > 0.5 && ear < 0.5 ? `${top}px ${top}px ${bot}px ${bot}px` : `0 0 ${bot}px ${bot}px`
        });
        Object.assign(this.hit.style, { width: w + 'px', height: h + 'px', transform: `translate(${f2(x)}px, ${f2(inset)}px)` });
        Object.assign(this.glow.style, {
          width: w * 0.94 + 'px', height: h * 0.92 + 'px',
          transform: `translate(${f2(-w * 0.47)}px, ${f2(inset + (p.type === 'expanded' ? 12 : 5))}px)`,
          borderRadius: `${top}px ${top}px ${bot}px ${bot}px`
        });
        this.crGroup.setAttribute('transform', `translate(${f2(w)} 0) scale(-1 1)`);
        for (const path of [...this.cl, ...this.cr]) path.setAttribute('d', half);
        if (this.comet) this.drawComet(now, w, h);
      }

      this.updateGlow(p);
      this.tickMusic(dt, now);
      tickPlanets(now);
      requestAnimationFrame((t) => this.frame(t));
    }

    updateGlow(p) {
      let color = 'transparent', op = 0;
      if (this.glowOn) {
        if (p.type === 'music') { color = music.track.accent; op = music.playing ? 0.42 : 0.14; }
        else if (p.type === 'expanded' && p.page === 'music') { color = music.track.accent; op = 0.46; }
        else if (p.type === 'transient') {
          const t = p.kind.type;
          color = p.kind.tint || TINT[t] || '#fff';
          op = ['charging', 'full', 'low', 'airpods', 'calendarAlert', 'welcome', 'unlock', 'tray'].includes(t) ? 0.4 : 0;
        }
      }
      const key = color + op + p.type;
      if (key !== this.glowKey) {
        this.glowKey = key;
        this.glow.style.backgroundColor = color;
        this.glow.style.opacity = op;
        this.glow.style.filter = `blur(${p.type === 'expanded' ? 30 : 15}px)`;
      }
    }

    drawComet(now, w, h) {
      const t = (now - this.comet.start) / 1000;
      if (t > 1.4) {
        this.comet = null;
        for (const path of [...this.cl, ...this.cr]) { path.setAttribute('stroke-dasharray', '0 3'); path.setAttribute('opacity', 0); }
        this.burstGlow.setAttribute('rx', 0); this.burstCore.setAttribute('rx', 0);
        return;
      }
      const ease = (x) => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);
      const phase = ease(clamp(t / 0.95, 0, 1)) * 1.3;
      const opacity = t < 0.95 ? 1 : clamp(1 - (t - 0.95) / 0.35, 0, 1);
      const lens = [0.36, 0.2, 0.06];
      const alphas = [0.35, 0.85, 1];
      const paths = [this.cl, this.cr];
      for (const group of paths) {
        group.forEach((path, i) => {
          path.setAttribute('stroke-dasharray', `${lens[i]} 3`);
          path.setAttribute('stroke-dashoffset', f2(lens[i] - phase));
          path.setAttribute('opacity', alphas[i] * opacity);
        });
      }
      const b = clamp((t - 0.72) / 0.6, 0, 1);
      const eb = 1 - Math.pow(1 - b, 3);
      const fade = b > 0 && b < 1 ? Math.sin(b * Math.PI) : 0;
      for (const [el, rx, ry, a] of [[this.burstGlow, 15 + 60 * eb, 3 + 2 * eb, 1], [this.burstCore, 4 + 25 * eb, 1, 1]]) {
        el.setAttribute('cx', f2(w / 2)); el.setAttribute('cy', f2(h + 2));
        el.setAttribute('rx', f2(rx)); el.setAttribute('ry', f2(ry));
        el.setAttribute('opacity', f2(fade * a));
      }
    }

    tickMusic(dt, now) {
      if (music.playing) {
        music.elapsed += dt;
        const lines = music.track.lyrics;
        const end = lines[lines.length - 1][0] + 4;
        if (music.elapsed > end) music.elapsed = lines[0][0] - 2;
      }
      const time = now / 1000;
      this.live.waves = this.live.waves.filter((w) => w.isConnected);
      for (const wv of this.live.waves) {
        const bars = wv.children;
        for (let i = 0; i < bars.length; i++) {
          const lvl = music.playing ? amplitude(i, time) : 0.2;
          bars[i].style.transform = `scaleY(${f2(lvl)})`;
        }
      }
      const second = Math.floor(music.elapsed);
      for (const pr of this.live.prog) {
        if (!pr.isConnected) continue;
        const d = music.track.duration;
        pr.querySelector('b').style.width = (music.elapsed / d) * 100 + '%';
        if (pr.dataset.sec !== String(second) || pr.dataset.track !== String(music.index)) {
          pr.dataset.sec = second; pr.dataset.track = music.index;
          pr.querySelector('.t1').textContent = clock(music.elapsed);
          pr.querySelector('.t2').textContent = '-' + clock(d - music.elapsed);
        }
      }
      const li = music.lyricIndex();
      for (const col of this.live.lyr) {
        if (!col.isConnected) continue;
        const key = li + ':' + music.index;
        if (col.dataset.key === key) continue;
        col.dataset.key = key;
        const lineH = col.firstElementChild ? col.firstElementChild.offsetHeight || 21 : 21;
        const boxH = col.parentElement.offsetHeight || 62;
        col.style.transform = `translateY(${f2(boxH / 2 - lineH / 2 - Math.max(0, li) * lineH)}px)`;
        [...col.children].forEach((p, i) => p.classList.toggle('on', i === li));
      }
    }
  }

  function mirrorPath(d, w) {
    // Refleja un camino en horizontal (x -> w - x), invirtiendo los arcos.
    return d.replace(/([MHVLA])([^MHVLAZ]*)/g, (m, cmd, args) => {
      const n = args.trim().split(/[\s,]+/).filter(Boolean).map(Number);
      if (cmd === 'H') return 'H' + f2(w - n[0]);
      if (cmd === 'V') return 'V' + n[0];
      if (cmd === 'M' || cmd === 'L') return cmd + f2(w - n[0]) + ' ' + n[1];
      if (cmd === 'A') return `A${n[0]} ${n[1]} ${n[2]} ${n[3]} ${n[4] ? 0 : 1} ${f2(w - n[5])} ${n[6]}`;
      return m;
    });
  }

  function amplitude(i, t) {
    const a = Math.sin(t * (5.1 + i * 1.9) + i * 1.3) * 0.5 + 0.5;
    const b = Math.sin(t * (2.3 + i * 0.7) + i * 2.9) * 0.5 + 0.5;
    const c = Math.sin(t * (11 - i) + i * 0.7) * 0.5 + 0.5;
    return 0.18 + 0.82 * (a * 0.55 + b * 0.3 + c * 0.15);
  }

  function wave(n, w, h, bw) {
    const bar = `<i style="width:${bw}px"></i>`;
    return `<div class="wave" style="width:${w}px;height:${h}px">${bar.repeat(n)}</div>`;
  }

  function lyricLines(t) {
    return t.lyrics.map(([, text]) => `<p>${text}</p>`).join('');
  }

  function tickPlanets(now) {
    const a = reduced ? 0.9 : now / 1000 * 2.2;
    const x = f2(12 * Math.cos(a)), y = f2(4.1 * Math.sin(a));
    const front = Math.sin(a) > 0;
    for (const svgEl of document.getElementsByClassName('planet-svg')) {
      const [back, fr] = svgEl.querySelectorAll('.moon');
      for (const m of [back, fr]) { m.setAttribute('cx', x); m.setAttribute('cy', y); }
      back.style.display = front ? 'none' : '';
      fr.style.display = front ? '' : 'none';
    }
  }

  // ---------------------------------------------------------------- Calendario

  const MONTHS = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
  const DAYS = ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado'];
  const DAYS_SHORT = ['DOM', 'LUN', 'MAR', 'MIÉ', 'JUE', 'VIE', 'SÁB'];

  function renderCalendar() {
    const now = new Date();
    const y = now.getFullYear(), m = now.getMonth();
    const first = new Date(y, m, 1);
    const lead = (first.getDay() + 6) % 7; // lunes primero
    const count = new Date(y, m + 1, 0).getDate();
    const rows = Math.ceil((lead + count) / 7);
    let cells = '';
    for (let i = 0; i < rows * 7; i++) {
      const d = new Date(y, m, 1 - lead + i);
      const cls = d.getMonth() !== m ? 'out' : (d.getDate() === now.getDate() ? 'today' : '');
      cells += `<span class="${cls}">${d.getDate()}</span>`;
      if (i % 7 === 6 && i < rows * 7 - 1) cells += '</div><div class="cal-row">';
    }
    return `<div class="cal">
      <div class="cal-day" data-s style="--i:1">
        <div class="cal-wd">${DAYS_SHORT[now.getDay()]}</div>
        <div class="cal-num">${now.getDate()}</div>
        <div class="cal-ev" style="--c:var(--blue)"><i></i><div><b>Diseño de la app</b><span>10:00 – 11:00</span></div></div>
        <div class="cal-ev" style="--c:var(--green)"><i></i><div><b>Almuerzo con Ana</b><span>13:30 – 14:30</span></div></div>
        <div class="cal-more">y 1 más</div>
      </div>
      <div class="cal-grid" data-s style="--i:2">
        <div class="cal-head">${MONTHS[m][0].toUpperCase() + MONTHS[m].slice(1)} de ${y}<span>${svg(ICON.chevL, 9)}${svg(ICON.chevR, 9)}</span></div>
        <div class="cal-row wk"><span>L</span><span>M</span><span>X</span><span>J</span><span>V</span><span>S</span><span>D</span></div>
        <div class="cal-row">${cells}</div>
      </div></div>`;
  }

  // ---------------------------------------------------------------- Arranque

  const island = new Island($('#island'));
  root.style.setProperty('--accent', music.track.accent);

  function rescale() {
    const s = clamp(innerWidth / 1280, 0.62, 1.3);
    island.scale = s;
    island.dirty = true;
    root.style.setProperty('--s', s);
  }
  rescale();
  addEventListener('resize', rescale);

  for (const el of $$('[data-planet]')) el.innerHTML = planet(18);

  // Reloj de la barra de menús y de la pantalla bloqueada
  function tickClock() {
    const d = new Date();
    const hm = `${d.getHours()}:${String(d.getMinutes()).padStart(2, '0')}`;
    const wd = DAYS[d.getDay()].slice(0, 3);
    for (const el of $$('[data-clock]')) el.textContent = `${wd} ${d.getDate()} ${MONTHS[d.getMonth()].slice(0, 3)} ${hm}`;
    for (const el of $$('[data-time]')) el.textContent = hm;
    for (const el of $$('[data-date]')) el.textContent = `${DAYS[d.getDay()][0].toUpperCase() + DAYS[d.getDay()].slice(1)}, ${d.getDate()} de ${MONTHS[d.getMonth()]}`;
  }
  tickClock();
  setInterval(tickClock, 10000);

  // Tarjeta de la pantalla bloqueada
  const lockcard = $('[data-lockcard]');
  if (lockcard) {
    const t = music.track;
    lockcard.innerHTML = `<div class="lc"><div class="lc-bg" style="background-image:url('${t.art}')" data-lcbg></div><div class="lc-in">
      <div class="lc-top"><div class="art" data-art><img src="${t.art}" alt=""></div>
        <div style="flex:1;min-width:0"><div class="lc-title" data-title>${t.title}</div><div class="lc-artist" data-artist>${t.artist}</div></div>
        ${wave(5, 28, 24, 3)}</div>
      <div class="prog" data-prog><span class="t1"></span><div class="bar"><b></b></div><span class="t2"></span></div>
      <div class="ctrls">
        <button class="ibtn dim" aria-label="Aleatorio">${svg(ICON.shuffle, 15)}</button>
        <button class="ibtn mid" data-act="prev" aria-label="Anterior">${svg(ICON.backward, 21)}</button>
        <button class="ibtn big" data-act="play" data-size="28" aria-label="Reproducir o pausar" style="width:50px;height:50px">${svg(ICON.pause, 28)}</button>
        <button class="ibtn mid" data-act="next" aria-label="Siguiente">${svg(ICON.forward, 21)}</button>
        <button class="ibtn dim" aria-label="Repetir">${svg(ICON.repeat, 15)}</button>
      </div>
      <div class="lyr"><div class="lyr-col" data-lyrics>${lyricLines(t)}</div></div>
    </div></div>`;
    island.live.waves.push(...$$('.wave', lockcard));
    lockcard.addEventListener('click', (e) => {
      const act = e.target.closest('button')?.dataset.act;
      if (act === 'play') island.togglePlay();
      if (act === 'next') island.nextTrack(1);
      if (act === 'prev') island.nextTrack(-1);
    });
    island.on(() => { const bg = $('[data-lcbg]'); if (bg) bg.style.backgroundImage = `url('${music.track.art}')`; });
  }
  const refreshLive = () => {
    island.live.prog = $$('[data-prog]');
    island.live.lyr = $$('[data-lyrics]');
  };
  refreshLive();
  island.on(refreshLive);

  // ---------------------------------------------------------------- Escenas

  const cursor = $('#cursor');
  async function flyCursor(from, to, ms = 900) {
    if (reduced) return;
    cursor.style.opacity = 1;
    const anim = cursor.animate([
      { transform: `translate(${from[0]}px, ${from[1]}px)` },
      { transform: `translate(${to[0]}px, ${to[1]}px)` }
    ], { duration: ms, easing: 'cubic-bezier(.45,0,.2,1)', fill: 'forwards' });
    await anim.finished.catch(() => {});
  }
  function hideCursor() { cursor.style.opacity = 0; }
  const islandBottom = () => (island.metrics.nh + 2) * island.scale;
  const setTint = (c) => root.style.setProperty('--tint', c);

  let token = 0;
  let current = null;
  const ctx = (my) => ({
    alive: () => my === token,
    wait: async (ms) => { await sleep(ms); return my === token; }
  });

  const tickerItems = $$('[data-ticker] li');
  const markTicker = (k) => tickerItems.forEach((li) => li.classList.toggle('on', li.dataset.k === k));

  let introDone = false;
  const scenes = {
    async hero(c) {
      setTint('#7a5cff');
      if (!introDone && !reduced) {
        island.hidden = true;
        island.snapTo({ type: 'hidden' });
        if (!(await c.wait(650))) return;
        island.hidden = false;
        introDone = true;
      }
      introDone = true;
      island.show('welcome', {}, null);
    },
    async idle() { setTint('#6a4ce0'); },
    async music(c) {
      setTint(music.track.accent);
      island.music = true;
      while (c.alive()) {
        if (!(await c.wait(1500))) return;
        if (!reduced) {
          const from = [innerWidth * 0.62, innerHeight * 0.7];
          const to = [innerWidth / 2 + 10, islandBottom() - 6];
          await flyCursor(from, to, 1000);
          if (!c.alive()) return;
        }
        island.hover = true;
        await c.wait(140);
        island.expanded = true; island.page = 'music';
        if (!(await c.wait(2300))) return;
        island.nextTrack(1);
        setTint(music.track.accent);
        if (!(await c.wait(2600))) return;
        island.hover = false; island.expanded = false;
        if (!reduced) await flyCursor([innerWidth / 2 + 10, islandBottom() - 6], [innerWidth * 0.7, innerHeight * 0.75], 800);
        hideCursor();
        if (!(await c.wait(1800))) return;
      }
    },
    async lyrics() {
      setTint('#C04CFF');
      if (music.index !== 0) island.nextTrack(1);
      island.music = true; island.lyrics = true; island.page = 'music'; island.expanded = true;
    },
    async alerts(c) {
      const steps = [
        ['charging', async () => { island.show('charging', { level: 80 }, 2500); return c.wait(3000); }],
        ['airpods', async () => { island.show('airpods', { battery: 85 }, 2500); return c.wait(3000); }],
        ['volume', async () => {
          for (let v = 0.25; v <= 0.76; v += 0.0625) { island.show('volume', { level: v, muted: false }, 1400); if (!(await c.wait(150))) return false; }
          return c.wait(1900);
        }],
        ['brightness', async () => {
          for (let v = 0.75; v >= 0.36; v -= 0.0625) { island.show('brightness', { level: v }, 1400); if (!(await c.wait(150))) return false; }
          return c.wait(1900);
        }],
        ['low', async () => { island.show('low', { level: 15 }, 2500); return c.wait(3000); }]
      ];
      while (c.alive()) {
        for (const [k, run] of steps) {
          markTicker(k);
          setTint(TINT[k] === '#FFFFFF' ? '#B9A8FF' : TINT[k]);
          if (!(await run())) return;
        }
      }
    },
    async calendar(c) {
      setTint('#FF8A3D');
      while (c.alive()) {
        island.page = 'calendar'; island.expanded = true;
        if (!(await c.wait(4200))) return;
        island.expanded = false;
        if (!(await c.wait(700))) return;
        island.show('calendarAlert', { title: 'Diseño de la app', minutes: 5 }, 3000);
        if (!(await c.wait(4000))) return;
      }
    },
    async tray(c) {
      setTint('#5B8CFF');
      const file = $('[data-file]');
      while (c.alive()) {
        island.trayItems = [['Atardecer.jpg', 'img'], ['Presentación.key', 'key'], ['Notas.txt', 'txt']];
        island.newTile = null;
        if (!(await c.wait(900))) return;
        const r = file.getBoundingClientRect();
        const doc = file.querySelector('.doc');
        const flyer = document.createElement('div');
        flyer.className = 'flyer';
        flyer.innerHTML = doc.outerHTML + cursor.innerHTML;
        flyer.querySelector('svg').style.cssText = 'position:absolute;left:34px;top:40px';
        document.body.appendChild(flyer);
        file.classList.add('lifted');
        const from = `translate(${r.left + r.width / 2 - 27}px, ${r.top}px)`;
        const to = `translate(${innerWidth / 2 - 110 * island.scale - 27}px, ${92 * island.scale - 33}px) scale(.8)`;
        const anim = flyer.animate([{ transform: from }, { transform: to }], { duration: reduced ? 1 : 1500, easing: 'cubic-bezier(.4,0,.2,1)', fill: 'forwards' });
        setTimeout(() => { if (c.alive()) island.drag = true; }, 500);
        setTimeout(() => { if (c.alive()) { island.dropHot = 'tray'; island.repaintPage(); } }, 1250);
        await anim.finished.catch(() => {});
        if (!c.alive()) { flyer.remove(); file.classList.remove('lifted'); return; }
        flyer.animate([{ opacity: 1, transform: to }, { opacity: 0, transform: to + ' scale(.3)' }], { duration: 260, fill: 'forwards' });
        await sleep(240);
        flyer.remove();
        island.trayItems = [['Contrato.pdf', 'pdf'], ...island.trayItems];
        island.newTile = 'Contrato.pdf';
        island.dropHot = null; island.drag = false;
        island.page = 'tray'; island.expanded = true;
        if (!(await c.wait(2800))) { file.classList.remove('lifted'); return; }
        island.expanded = false;
        file.classList.remove('lifted');
        if (!(await c.wait(1600))) return;
      }
    },
    async lock(c) {
      setTint('#7A5CFF');
      island.show('lock', {}, null);
    },
    async nonotch() {
      setTint('#5B8CFF');
      applyVirtual(virtualChoice);
      island.music = true;
    },
    async play() { setTint('#9B6BFF'); },
    async tune() { setTint(music.track.accent); island.music = true; },
    async install(c) {
      setTint('#7a5cff');
      const sec = $('#instalar');
      sec.classList.add('live');
      c.onExit = () => sec.classList.remove('live');
    }
  };

  let currentCtx = null;
  function activate(name) {
    if (current === name) return;
    if (currentCtx && currentCtx.onExit) currentCtx.onExit();
    hideCursor();
    for (const f of $$('.flyer')) f.remove();
    for (const f of $$('.file.lifted')) f.classList.remove('lifted');
    const leavingLock = current === 'lock';
    current = name;
    const my = ++token;
    island.reset();
    if (leavingLock) island.show('unlock', {}, 1300);
    if (name !== 'nonotch' && (island.metrics.floating || island.metrics.virtual)) applyVirtual('real');
    markTicker(null);
    currentCtx = ctx(my);
    scenes[name]?.(currentCtx);
  }

  const sections = $$('[data-scene]');
  const io = new IntersectionObserver((entries) => {
    for (const e of entries) if (e.isIntersecting) activate(e.target.dataset.scene);
  }, { rootMargin: '-48% 0px -48% 0px' });
  sections.forEach((s) => io.observe(s));

  // Pista del inicio
  const hint = $('[data-hint]');
  document.addEventListener('island-hover', () => hint?.classList.add('gone'), { once: true });

  // ---------------------------------------------------------------- Sin notch

  let virtualChoice = 'notch';
  function applyVirtual(kind) {
    island.metrics = { nw: kind === 'floating' ? 168 : (kind === 'real' ? 186 : 190), nh: 32, floating: kind === 'floating', virtual: kind === 'notch' };
    island.dirty = true;
    island.key = '';
  }
  for (const b of $$('[data-virtual]')) {
    b.addEventListener('click', () => {
      virtualChoice = b.dataset.virtual;
      $$('[data-virtual]').forEach((x) => x.setAttribute('aria-pressed', String(x === b)));
      applyVirtual(virtualChoice);
      island.fireComet('#5B8CFF');
    });
  }

  // ---------------------------------------------------------------- Pruébalo

  const tries = {
    charging: () => island.show('charging', { level: 80 }),
    airpods: () => island.show('airpods', { battery: 85 }),
    low: () => island.show('low', { level: 15 }),
    lock: async () => { island.show('lock', {}, null); await sleep(1500); island.show('unlock', {}, 1300); },
    calendarAlert: () => island.show('calendarAlert', { title: 'Diseño de la app', minutes: 5 }, 3200),
    music: () => { island.music = !island.music; if (island.music) island.fireComet(music.track.accent); },
    expand: async () => { island.page = 'music'; island.expanded = true; await sleep(3200); if (current === 'play') island.expanded = false; },
    tray: async () => { island.page = 'tray'; island.expanded = true; await sleep(3200); if (current === 'play') island.expanded = false; }
  };
  for (const b of $$('[data-try]')) b.addEventListener('click', () => { island.expanded = false; tries[b.dataset.try](); });

  const vol = $('[data-volume]'), volOut = $('[data-volume-out]');
  vol?.addEventListener('input', () => {
    volOut.textContent = vol.value;
    island.expanded = false;
    island.show('volume', { level: vol.value / 100, muted: vol.value === '0' }, 1500);
  });

  const curve = $('[data-curve]');
  function drawCurve() {
    if (!curve) return;
    const g = curve.getContext('2d');
    const W = curve.width, H = curve.height;
    g.clearRect(0, 0, W, H);
    g.strokeStyle = 'rgba(255,255,255,.08)'; g.lineWidth = 1;
    for (let i = 1; i < 6; i++) { g.beginPath(); g.moveTo((W * i) / 6, 0); g.lineTo((W * i) / 6, H); g.stroke(); }
    const y = (v) => H - 24 - v * (H - 60);
    g.setLineDash([5, 5]); g.strokeStyle = 'rgba(255,255,255,.25)';
    g.beginPath(); g.moveTo(0, y(1)); g.lineTo(W, y(1)); g.stroke(); g.setLineDash([]);
    const st = STYLES[island.style];
    const k = 1 / island.speed;
    for (const [params, color] of [[st.w, '#FF5C93'], [st.h, '#5B8CFF']]) {
      const sp = new Spring(0);
      sp.to(1, params[0] * k, params[1]);
      g.strokeStyle = color; g.lineWidth = 3; g.lineCap = 'round';
      g.beginPath();
      const steps = 240, dur = 1.4;
      for (let i = 0; i <= steps; i++) {
        if (i) sp.step(dur / steps);
        const px = (i / steps) * W;
        if (i === 0) g.moveTo(px, y(sp.v)); else g.lineTo(px, y(sp.v));
      }
      g.stroke();
    }
    g.fillStyle = 'rgba(255,255,255,.4)'; g.font = '12px -apple-system, system-ui, sans-serif';
    g.fillText('0 s', 6, H - 6); g.fillText('1,4 s', W - 36, H - 6);
  }
  drawCurve();

  for (const b of $$('[data-style]')) {
    b.addEventListener('click', () => {
      island.style = b.dataset.style;
      $$('[data-style]').forEach((x) => x.setAttribute('aria-pressed', String(x === b)));
      drawCurve();
      island.show('charging', { level: 80 }, 2000);
    });
  }
  const speed = $('[data-speed]'), speedOut = $('[data-speed-out]');
  speed?.addEventListener('input', () => { island.speed = speed.value / 100; speedOut.textContent = speed.value + '%'; drawCurve(); });
  $('[data-comet]')?.addEventListener('change', (e) => { island.cometOn = e.target.checked; });
  $('[data-glow]')?.addEventListener('change', (e) => { island.glowOn = e.target.checked; });
})();
