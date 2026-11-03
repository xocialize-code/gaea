// Gaea hero: a dotted world rising over a dot-grid sea, three profile moons in orbit,
// and media glyphs that float upward and give way to the pointer.
(() => {
  "use strict";

  const canvas = document.getElementById("hero-canvas");
  const stage = document.getElementById("hero-stage");
  if (!canvas || !stage) return;
  const hero = canvas.parentElement;
  const ctx = canvas.getContext("2d");
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

  let W = 0, H = 0, DPR = 1;
  let colors = null;
  let running = false, visible = true, raf = 0, last = 0, time = 0;
  let born = 0; // time the world began forming

  // ---------- Theme ----------
  function hexToRgb(value) {
    let h = value.trim().replace("#", "");
    if (h.length === 3) h = h.split("").map((c) => c + c).join("");
    const n = parseInt(h, 16);
    return Number.isNaN(n) ? [128, 128, 128] : [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  }
  function readColors() {
    const cs = getComputedStyle(document.documentElement);
    const get = (k) => hexToRgb(cs.getPropertyValue(k));
    colors = {
      bg: get("--bg"), ink: get("--ink"), dim: get("--ink-3"),
      sun: get("--sun"), sea: get("--sea"), leaf: get("--leaf"),
      light: cs.getPropertyValue("--scheme").trim() === "light",
    };
  }
  const rgba = (c, a) => `rgba(${c[0]},${c[1]},${c[2]},${a})`;

  // ---------- Pointer ----------
  const pointer = { x: -1e4, y: -1e4, nx: 0, ny: 0, sx: 0, sy: 0, inside: false };
  window.addEventListener("pointermove", (e) => {
    const r = hero.getBoundingClientRect();
    pointer.x = e.clientX - r.left;
    pointer.y = e.clientY - r.top;
    pointer.inside = pointer.y >= 0 && pointer.y <= r.height;
    pointer.nx = Math.max(-1, Math.min(1, (pointer.x / r.width) * 2 - 1));
    pointer.ny = Math.max(-1, Math.min(1, (pointer.y / r.height) * 2 - 1));
  }, { passive: true });
  hero.addEventListener("pointerleave", () => { pointer.inside = false; });

  // ---------- Noise for the continents ----------
  function hash3(x, y, z) {
    let h = (x * 374761393 + y * 668265263 + z * 2147483647) | 0;
    h = (h ^ (h >>> 13)) * 1274126177;
    h = h ^ (h >>> 16);
    return (h >>> 0) / 4294967295;
  }
  const smooth = (t) => t * t * (3 - 2 * t);
  function vnoise(x, y, z) {
    const xi = Math.floor(x), yi = Math.floor(y), zi = Math.floor(z);
    const xf = smooth(x - xi), yf = smooth(y - yi), zf = smooth(z - zi);
    let v = 0;
    for (let dz = 0; dz < 2; dz++) for (let dy = 0; dy < 2; dy++) for (let dx = 0; dx < 2; dx++) {
      const w = (dx ? xf : 1 - xf) * (dy ? yf : 1 - yf) * (dz ? zf : 1 - zf);
      v += w * hash3(xi + dx, yi + dy, zi + dz);
    }
    return v;
  }
  function fbm(x, y, z) {
    let v = 0, a = 0.5, f = 1;
    for (let i = 0; i < 5; i++) { v += a * vnoise(x * f + 11.3, y * f + 4.7, z * f + 7.1); f *= 2.03; a *= 0.5; }
    return v;
  }

  // ---------- The world ----------
  let globe = [];
  function buildGlobe(count) {
    const pts = [];
    const golden = Math.PI * (3 - Math.sqrt(5));
    for (let i = 0; i < count; i++) {
      const y = 1 - (i / (count - 1)) * 2;
      const r = Math.sqrt(1 - y * y);
      const th = golden * i;
      const x = Math.cos(th) * r, z = Math.sin(th) * r;
      const e = fbm(x * 1.6, y * 1.6, z * 1.6);
      const land = e > 0.53;
      pts.push({
        x, y, z, land, elev: land ? Math.min(1, (e - 0.53) / 0.16) : 0,
        lights: land && hash3(i, 7, 3) < 0.22,
        seed: hash3(i, 1, 9),
        sx: 0, sy: 0, // start point on the grid while the world forms
      });
    }
    return pts;
  }

  // ---------- Orbits ----------
  const ORBITS = [
    { key: "sun", r: 1.22, incl: 1.18, node: -0.32, speed: 0.21, phase: 0.4,
      ops: ["image.generate", "image.edit", "image.upscale", "image.matte", "image.decompose", "image.restore", "image.fill"] },
    { key: "sea", r: 1.38, incl: 1.36, node: 0.24, speed: 0.15, phase: 2.6,
      ops: ["audio.speak", "audio.compose", "audio.generate", "audio.edit_speech", "audio.design_voice"] },
    { key: "leaf", r: 1.56, incl: 1.27, node: -0.08, speed: 0.11, phase: 4.4,
      ops: ["video.generate", "video.extend", "video.retake", "video.upscale", "video.interpolate"] },
  ];
  ORBITS.forEach((o) => { o.lap = -1; o.op = o.ops[0]; });

  // ---------- Floating glyphs ----------
  const GLYPHS = ["frame", "wave", "film", "spark"];
  const GLYPH_COLOR = { frame: "sun", wave: "sea", film: "leaf", spark: "ink" };
  let glyphs = [];
  function buildGlyphs(n) {
    const list = [];
    for (let i = 0; i < n; i++) {
      const type = GLYPHS[i % GLYPHS.length];
      const d = 0.35 + Math.random() * 0.65;
      list.push({
        type, d,
        x: Math.random() * W, y: Math.random() * H,
        ox: 0, oy: 0, vx: 0, vy: 0,
        rise: 5 + 13 * d,
        sway: Math.random() * Math.PI * 2,
        rot: (Math.random() - 0.5) * 0.6,
        spin: (Math.random() - 0.5) * 0.12,
        size: 9 + 15 * d,
      });
    }
    return list;
  }

  // ---------- Layout ----------
  const L = { horizon: 0, f: 0, gx: 0, gy: 0, R: 0, zNear: 1, zFar: 5, rows: 34, cols: 0, xMax: 0 };
  let grid = [];
  function layout() {
    const rect = hero.getBoundingClientRect();
    W = Math.max(1, rect.width); H = Math.max(1, rect.height);
    DPR = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(W * DPR); canvas.height = Math.round(H * DPR);
    ctx.setTransform(DPR, 0, 0, DPR, 0, 0);

    const s = stage.getBoundingClientRect();
    const narrow = W < 960;
    L.R = narrow ? Math.min(s.width * 0.36, s.height * 0.36, 190) : Math.min(s.width * 0.42, s.height * 0.4, 270);
    L.gx = s.left - rect.left + s.width / 2;
    L.gy = s.top - rect.top + s.height * (narrow ? 0.44 : 0.46);
    L.horizon = Math.min(H - 120, L.gy + L.R * (narrow ? 0.5 : 0.38));
    const c = hero.querySelector(".hero-copy").getBoundingClientRect();
    L.copy = { x0: c.left - rect.left - 20, y0: c.top - rect.top - 20, x1: c.right - rect.left + 20, y1: c.bottom - rect.top + 20 };
    L.f = H - L.horizon + 24;
    L.xMax = ((W / 2) * L.zFar) / L.f * 1.08;
    L.cols = Math.round(Math.min(150, W / 11));
    L.rows = narrow ? 26 : 34;

    grid = [];
    for (let r = 0; r < L.rows; r++) {
      const z = L.zNear * Math.pow(L.zFar / L.zNear, r / (L.rows - 1));
      for (let c = 0; c <= L.cols; c++) {
        const X = -L.xMax + (2 * L.xMax * c) / L.cols;
        grid.push({ X, z });
      }
    }

    const count = narrow ? 1700 : 3400;
    if (globe.length !== count) globe = buildGlobe(count);
    // each point of the world starts as a dot on the sea
    globe.forEach((p, i) => {
      const g = grid[Math.floor(hash3(i, 3, 5) * grid.length)];
      const proj = project(g.X, 0, g.z);
      p.sx = proj ? proj[0] : L.gx; p.sy = proj ? proj[1] : H;
    });

    const nGlyphs = narrow ? 12 : 24;
    if (glyphs.length !== nGlyphs) glyphs = buildGlyphs(nGlyphs);
    else glyphs.forEach((g) => { g.x = Math.min(g.x, W); g.y = Math.min(g.y, H); });
  }

  function project(X, Y, z) {
    if (z <= 0.05) return null;
    return [W / 2 + (X * L.f) / z, L.horizon + ((1 - Y) * L.f) / z];
  }

  // Inverse of the floor projection: where on the sea the pointer is.
  function pointerOnSea() {
    if (!pointer.inside || pointer.y <= L.horizon + 2) return null;
    const z = L.f / (pointer.y - L.horizon);
    return { X: ((pointer.x - W / 2) * z) / L.f, z };
  }

  // ---------- Drawing helpers ----------
  // Batch dots by color and alpha so each frame issues a few dozen fills, not thousands.
  const LEVELS = 12;
  let buckets = {};
  function resetBuckets() { buckets = {}; }
  function dot(key, a, x, y, r) {
    if (a <= 0.01 || r <= 0) return;
    const lvl = Math.min(LEVELS - 1, Math.floor(a * LEVELS));
    const id = key + lvl;
    (buckets[id] || (buckets[id] = { key, a: (lvl + 0.5) / LEVELS, pts: [] })).pts.push(x, y, r);
  }
  function flush() {
    for (const id in buckets) {
      const b = buckets[id];
      ctx.fillStyle = rgba(colors[b.key], b.a);
      ctx.beginPath();
      const p = b.pts;
      for (let i = 0; i < p.length; i += 3) {
        ctx.moveTo(p[i] + p[i + 2], p[i + 1]);
        ctx.arc(p[i], p[i + 1], p[i + 2], 0, Math.PI * 2);
      }
      ctx.fill();
    }
  }

  const ease = (t) => (t <= 0 ? 0 : t >= 1 ? 1 : 1 - Math.pow(1 - t, 3));

  // ---------- Frame ----------
  function draw(dt) {
    ctx.clearRect(0, 0, W, H);
    resetBuckets();
    const t = time;
    const light = colors.light;
    const k = 1 - Math.exp(-dt * 3);
    pointer.sx += (pointer.nx - pointer.sx) * k;
    pointer.sy += (pointer.ny - pointer.sy) * k;

    // --- sea of dots ---
    const ps = pointerOnSea();
    for (let i = 0; i < grid.length; i++) {
      const g = grid[i];
      let Y = 0.055 * Math.sin(g.X * 0.9 + t * 0.7) * Math.cos(g.z * 1.4 - t * 0.55)
            + 0.03 * Math.sin((g.X + g.z) * 1.9 + t * 1.05);
      let lift = 0;
      if (ps) {
        const dx = g.X - ps.X, dz = (g.z - ps.z) * 1.6;
        const d2 = dx * dx + dz * dz;
        lift = Math.exp(-d2 / 0.18);
        Y += 0.22 * lift + 0.03 * Math.sin(Math.sqrt(d2) * 9 - t * 5) * Math.exp(-d2 / 0.9);
      }
      const p = project(g.X, Y, g.z);
      if (!p || p[0] < -4 || p[0] > W + 4 || p[1] > H + 4) continue;
      const depth = (g.z - L.zNear) / (L.zFar - L.zNear);
      const a = Math.pow(1 - depth, 0.7) * (light ? 0.5 : 0.42) + 0.05 + 0.2 * (Y + 0.05);
      const r = Math.max(0.55, 1.9 / g.z);
      dot(lift > 0.25 ? "sun" : "sea", Math.min(1, a + lift * 0.45), p[0], p[1], r);
    }

    // --- atmosphere ---
    const { gx, gy, R } = L;
    const glow = ctx.createRadialGradient(gx, gy, R * 0.96, gx, gy, R * 1.3);
    glow.addColorStop(0, rgba(colors.sea, light ? 0.08 : 0.11));
    glow.addColorStop(1, rgba(colors.sea, 0));
    ctx.fillStyle = glow;
    ctx.fillRect(gx - R * 1.4, gy - R * 1.4, R * 2.8, R * 2.8);

    // --- the world ---
    const yaw = t * 0.07 + pointer.sx * 0.45;
    const tilt = 0.32 + pointer.sy * 0.12;
    const cy = Math.cos(yaw), sy = Math.sin(yaw), ct = Math.cos(tilt), st = Math.sin(tilt);
    const Lx = -0.55, Ly = 0.5, Lz = 0.67; // sunlight from upper left
    const base = R / 170;
    const age = reduceMotion.matches ? 99 : t - born;
    const forming = age < 3.2;
    const fadeBelow = R * 0.24;

    for (let i = 0; i < globe.length; i++) {
      const p = globe[i];
      const x1 = p.x * cy + p.z * sy, z1 = -p.x * sy + p.z * cy;
      const y2 = p.y * ct - z1 * st, z2 = p.y * st + z1 * ct;
      let X = gx + x1 * R, Y = gy - y2 * R;

      let grow = 1;
      if (forming) {
        // the world rises out of the sea, south pole first
        const delay = 0.15 + (1 - (p.y + 1) / 2) * 1.2 + p.seed * 0.5;
        grow = ease((age - delay) / 1.3);
        if (grow <= 0) continue;
        X = p.sx + (X - p.sx) * grow;
        Y = p.sy + (Y - p.sy) * grow;
      }

      const below = Y - L.horizon;
      const sink = below > 0 ? Math.max(0, 1 - below / fadeBelow) : 1;
      if (sink <= 0) continue;

      if (z2 <= 0) {
        dot("dim", 0.12 * sink * grow, X, Y, base * 0.55);
        continue;
      }
      const lam = x1 * Lx + y2 * Ly + z2 * Lz;
      const day = Math.max(0, Math.min(1, (lam + 0.12) / 0.5));
      const rim = 0.45 + 0.55 * z2;
      if (p.land) {
        const a = (0.3 + 0.7 * day) * rim * sink * grow;
        dot(p.elev > 0.85 && day > 0.4 ? "sun" : "leaf", a, X, Y, base * (1.05 + 0.5 * p.elev));
        if (p.lights && day < 0.25) {
          const flicker = 0.75 + 0.25 * Math.sin(t * 2 + p.seed * 40);
          dot("sun", (0.85 - day * 3) * flicker * sink * grow, X, Y, base * 0.7);
        }
      } else {
        dot("sea", (0.14 + 0.46 * day) * rim * sink * grow, X, Y, base * 0.72);
      }
    }
    flush();
    resetBuckets();

    // --- orbits and their moons ---
    const labels = [];
    const ringAlpha = forming ? ease((age - 1.6) / 1.2) : 1;
    if (ringAlpha > 0) {
      for (const o of ORBITS) {
        const ci = Math.cos(o.incl), si = Math.sin(o.incl), cn = Math.cos(o.node), sn = Math.sin(o.node);
        const place = (th) => {
          let x = Math.cos(th) * o.r, y = 0, z = Math.sin(th) * o.r;
          let y1 = y * ci - z * si, z1 = y * si + z * ci; // inclination about X
          let x2 = x * cn - y1 * sn, y2 = x * sn + y1 * cn; // node about Z
          let y3 = y2 * ct - z1 * st, z3 = y2 * st + z1 * ct; // the view's tilt
          return [gx + x2 * R, gy - y3 * R, z3, x2, y3];
        };
        const hidden = (q) => q[2] < 0 && Math.hypot(q[3], q[4]) < 1;
        for (let s = 0; s < 120; s++) {
          const q = place((s / 120) * Math.PI * 2);
          if (hidden(q)) continue;
          const below = q[1] - L.horizon;
          const sink = below > 0 ? Math.max(0, 1 - below / fadeBelow) : 1;
          dot(o.key, (q[2] > 0 ? 0.6 : 0.22) * sink * ringAlpha, q[0], q[1], 0.9);
        }
        const th = o.phase + t * o.speed;
        const lap = Math.floor((th + Math.PI / 2) / (Math.PI * 2));
        if (lap !== o.lap) { o.lap = lap; o.op = o.ops[((lap % o.ops.length) + o.ops.length) % o.ops.length]; }
        const m = place(th);
        const below = m[1] - L.horizon;
        const sink = below > 0 ? Math.max(0, 1 - below / fadeBelow) : 1;
        const over = L.copy && m[0] > L.copy.x0 && m[0] < L.copy.x1 && m[1] > L.copy.y0 && m[1] < L.copy.y1;
        if (!hidden(m) && sink > 0) labels.push({ o, x: m[0], y: m[1], z: m[2], a: sink * ringAlpha * (over ? 0.25 : 1), over });
      }
    }
    flush();

    for (const l of labels) {
      const c = colors[l.o.key];
      const halo = ctx.createRadialGradient(l.x, l.y, 0, l.x, l.y, 16);
      halo.addColorStop(0, rgba(c, 0.45 * l.a));
      halo.addColorStop(1, rgba(c, 0));
      ctx.fillStyle = halo;
      ctx.fillRect(l.x - 16, l.y - 16, 32, 32);
      ctx.fillStyle = rgba(c, l.a);
      ctx.beginPath(); ctx.arc(l.x, l.y, 3.6, 0, Math.PI * 2); ctx.fill();
      if (l.z > -0.2 && !l.over) {
        ctx.font = '500 11px "Martian Mono", ui-monospace, Menlo, monospace';
        ctx.textBaseline = "middle";
        const tw = ctx.measureText(l.o.op).width;
        const right = l.x + 12 + tw < W - 8 || l.x - 12 - tw < 8;
        ctx.textAlign = right ? "left" : "right";
        ctx.fillStyle = rgba(colors.ink, 0.78 * l.a);
        ctx.fillText(l.o.op, l.x + (right ? 12 : -12), l.y);
      }
    }

    // --- floating glyphs ---
    for (const g of glyphs) {
      if (!reduceMotion.matches) {
        g.y -= g.rise * dt;
        g.sway += dt * 0.6;
        g.rot += g.spin * dt;
        if (g.y < -40) { g.y = H + 30; g.x = Math.random() * W; }
        // give way to the pointer, then spring home
        const gxp = g.x + g.ox + pointer.sx * -26 * g.d, gyp = g.y + g.oy + pointer.sy * -18 * g.d;
        const dx = gxp - pointer.x, dy = gyp - pointer.y, d = Math.hypot(dx, dy);
        if (pointer.inside && d < 150 && d > 0.1) {
          const push = (1 - d / 150) * 900 * g.d;
          g.vx += (dx / d) * push * dt; g.vy += (dy / d) * push * dt;
        }
        g.vx += -g.ox * 6 * dt; g.vy += -g.oy * 6 * dt;
        g.vx *= Math.exp(-dt * 4); g.vy *= Math.exp(-dt * 4);
        g.ox += g.vx * dt; g.oy += g.vy * dt;
      }
      const x = g.x + g.ox + Math.sin(g.sway) * 6 * g.d + pointer.sx * -26 * g.d;
      const y = g.y + g.oy + pointer.sy * -18 * g.d;
      drawGlyph(g, x, y);
    }
  }

  function drawGlyph(g, x, y) {
    const c = colors[GLYPH_COLOR[g.type]];
    const inCopy = L.copy && x > L.copy.x0 && x < L.copy.x1 && y > L.copy.y0 && y < L.copy.y1;
    const a = ((colors.light ? 0.32 : 0.26) + 0.3 * g.d) * (inCopy ? 0.35 : 1);
    const s = g.size;
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(g.rot);
    ctx.strokeStyle = rgba(c, a);
    ctx.fillStyle = rgba(c, a);
    ctx.lineWidth = 1.2;
    ctx.lineJoin = "round"; ctx.lineCap = "round";
    if (g.type === "frame") {
      const w = s, h = s * 0.78;
      roundRect(-w / 2, -h / 2, w, h, s * 0.14); ctx.stroke();
      ctx.beginPath(); ctx.arc(w * 0.18, -h * 0.12, s * 0.09, 0, Math.PI * 2); ctx.fill();
      ctx.beginPath(); ctx.moveTo(-w * 0.36, h * 0.3); ctx.quadraticCurveTo(-w * 0.1, -h * 0.05, w * 0.08, h * 0.16); ctx.quadraticCurveTo(w * 0.22, h * 0.06, w * 0.36, h * 0.3); ctx.stroke();
    } else if (g.type === "wave") {
      for (let i = 0; i < 5; i++) {
        const amp = 0.25 + 0.75 * Math.abs(Math.sin(time * 2.2 + i * 1.3 + g.sway));
        const bx = (i - 2) * s * 0.22, bh = s * 0.8 * amp;
        ctx.beginPath(); ctx.moveTo(bx, -bh / 2); ctx.lineTo(bx, bh / 2); ctx.stroke();
      }
    } else if (g.type === "film") {
      const w = s * 1.1, h = s * 0.74;
      roundRect(-w / 2, -h / 2, w, h, s * 0.08); ctx.stroke();
      for (let i = 0; i < 4; i++) {
        const px = -w / 2 + w * (0.16 + i * 0.23);
        ctx.fillRect(px - 1.1, -h / 2 + 2.2, 2.2, 2.2);
        ctx.fillRect(px - 1.1, h / 2 - 4.4, 2.2, 2.2);
      }
    } else {
      const r = s * 0.5, q = s * 0.12;
      ctx.beginPath();
      ctx.moveTo(0, -r); ctx.quadraticCurveTo(q, -q, r, 0); ctx.quadraticCurveTo(q, q, 0, r);
      ctx.quadraticCurveTo(-q, q, -r, 0); ctx.quadraticCurveTo(-q, -q, 0, -r);
      ctx.fill();
    }
    ctx.restore();
  }
  function roundRect(x, y, w, h, r) {
    ctx.beginPath();
    ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
  }

  // ---------- Loop ----------
  function frame(now) {
    raf = 0;
    const dt = Math.min(0.05, (now - last) / 1000 || 0.016);
    last = now;
    time += dt;
    draw(dt);
    if (running) raf = requestAnimationFrame(frame);
  }
  function start() {
    if (reduceMotion.matches) { running = false; draw(0); return; }
    if (running || !visible || document.hidden) return;
    running = true; last = performance.now();
    raf = requestAnimationFrame(frame);
  }
  function stop() { running = false; if (raf) cancelAnimationFrame(raf); raf = 0; }

  function boot() {
    readColors();
    layout();
    time = reduceMotion.matches ? 40 : 0;
    born = 0;
    if (reduceMotion.matches) draw(0); else start();
  }

  new IntersectionObserver((entries) => {
    visible = entries[0].isIntersecting;
    visible ? start() : stop();
  }).observe(hero);
  document.addEventListener("visibilitychange", () => (document.hidden ? stop() : start()));

  let resizeTimer = 0;
  new ResizeObserver(() => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => { layout(); if (!running) draw(0); }, 60);
  }).observe(hero);

  const retheme = () => { readColors(); if (!running) draw(0); };
  new MutationObserver(retheme).observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });
  window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", retheme);
  reduceMotion.addEventListener("change", () => { stop(); boot(); });

  if (document.fonts && document.fonts.ready) document.fonts.ready.then(() => { if (!running) draw(0); });
  boot();
})();
