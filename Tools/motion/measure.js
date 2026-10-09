/* Числа по кадрам видео симулятора (29.2в). Кадры — серые байты области (`frames.swift`); события движения
   находятся по разности соседних кадров, дальше у каждого сценария своя мера: смещение при скольжении
   (месяц, неделя), доля пути по проекции на «конец минус начало» (сводка, веер), прозрачность и сдвиг по
   регрессии (вкладка), яркость кольца во времени (дыхание). Кривая подбирается из четырёх: E1 беты
   cubic-bezier(0.25,1,0.4,1), ease-out, ease-in-out, линейная. */
const fs = require('fs');

function readFrames(bin) {
  const buf = fs.readFileSync(bin);
  const nl = buf.indexOf(10);
  const head = JSON.parse(buf.slice(0, nl).toString());
  const { w, h, n } = head;
  const ts = new Float64Array(n), data = [];
  let o = nl + 1;
  for (let i = 0; i < n; i++) {
    ts[i] = buf.readDoubleLE(o); o += 8;
    data.push(new Uint8Array(buf.buffer, buf.byteOffset + o, w * h)); o += w * h;
  }
  return { w, h, n, ts, data };
}

/* ---------- кривые ---------- */
function bezier(x1, y1, x2, y2) {
  const cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx;
  const cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
  return x => {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    let t = x;
    for (let i = 0; i < 12; i++) {
      const e = ((ax * t + bx) * t + cx) * t - x;
      const d = (3 * ax * t + 2 * bx) * t + cx;
      if (Math.abs(e) < 1e-6 || Math.abs(d) < 1e-6) break;
      t -= e / d;
    }
    return ((ay * t + by) * t + cy) * t;
  };
}
const CURVES = {
  E1: bezier(0.25, 1, 0.4, 1),
  'ease-out': bezier(0, 0, 0.58, 1),
  'ease-in-out': bezier(0.42, 0, 0.58, 1),
  linear: x => Math.min(1, Math.max(0, x)),
};

/* Лучшая кривая и длительность по ряду (t, p): p(t) = curve((t − t0) / D), до t0 — 0, после t0 + D — 1. */
function fitCurve(ts, ps, onset, only) {
  const best = {};
  for (const [name, c] of Object.entries(CURVES)) {
    if (only && !only.includes(name)) continue;
    let b = { rms: Infinity };
    for (let D = 0.04; D <= 1.2; D += 0.01) {
      for (let t0 = onset - 0.05; t0 <= onset + 0.03; t0 += 0.004) {
        let s = 0;
        for (let i = 0; i < ts.length; i++) { const e = (ps[i] - c((ts[i] - t0) / D)); s += e * e; }
        const rms = Math.sqrt(s / ts.length);
        if (rms < b.rms) b = { rms, D, t0 };
      }
    }
    best[name] = b;
  }
  const name = Object.keys(best).sort((a, b) => best[a].rms - best[b].rms)[0];
  return { name, ...best[name], all: best };
}

/* ---------- события ---------- */
function meanAbs(a, b) { let s = 0; for (let i = 0; i < a.length; i++) s += Math.abs(a[i] - b[i]); return s / a.length; }

function events(fr, count, eps = 0.1) {
  const d = [0];
  for (let i = 1; i < fr.n; i++) d.push(meanAbs(fr.data[i], fr.data[i - 1]));
  const act = [];
  for (let i = 1; i < fr.n; i++) if (d[i] > eps) act.push(i);
  const cl = [];
  for (const i of act) {
    const last = cl[cl.length - 1];
    if (last && fr.ts[i] - fr.ts[last.i1] < 0.25) last.i1 = i; else cl.push({ i0: i, i1: i });
  }
  return { list: cl.slice(-count), list0: cl, d, all: cl.length };
}

const r3 = v => Math.round(v * 1000) / 1000;
const ms = v => Math.round(v * 1000);

/* Общая часть: кадры события, доля пути по проекции, подбор кривой. */
function progress(fr, ev) {
  const a = Math.max(0, ev.i0 - 1), b = Math.min(fr.n - 1, ev.i1 + 1);
  const S = fr.data[a], E = fr.data[b];
  let den = 0; for (let i = 0; i < S.length; i++) { const d = E[i] - S[i]; den += d * d; }
  const idx = [], ps = [];
  for (let k = a; k <= b; k++) {
    let num = 0; const f = fr.data[k];
    for (let i = 0; i < S.length; i++) num += (f[i] - S[i]) * (E[i] - S[i]);
    idx.push(k); ps.push(den ? num / den : 0);
  }
  return { a, b, idx, ps, den };
}

/* Ряд кадров события и доля пути p(t) → строка с числами. */
function summarize(fr, idx, ps, lines, label, expect) {
  const ts = idx.map(k => fr.ts[k] - fr.ts[idx[0]]);
  const onset = ts[Math.max(0, ps.findIndex(p => p > 0.02) - 1)];
  const inPath = ps.filter(p => p > 0.02 && p < 0.98).length;
  const t98 = (() => { const k = ps.findIndex((p, i) => i > 0 && p >= 0.98); return k < 0 ? ts[ts.length - 1] : ts[k]; })();
  const fit = fitCurve(ts, ps, onset);
  const e1 = fit.all.E1;
  lines.push(`${label}: кадров в пути ${inPath}, от начала до 98 % ${ms(t98 - onset)} мс; лучшая кривая ${fit.name} D=${ms(fit.D)} мс (rms ${r3(fit.rms)}); E1 при D=${ms(e1.D)} мс rms ${r3(e1.rms)}`);
  return { inPath, total: t98 - onset, fit, e1 };
}

/* ---------- скольжение (месяц, неделя) ---------- */
function sad(a, b) { let s = 0; for (let i = 0; i < a.length; i++) s += Math.abs(a[i] - b[i]); return s; }

function predict(S, E, w, h, s, sgn, out) {
  for (let y = 0; y < h; y++) {
    const r = y * w;
    for (let x = 0; x < w; x++) {
      let v;
      if (sgn > 0) v = x + s < w ? S[r + x + s] : E[r + x + s - w];
      else v = x - s >= 0 ? S[r + x - s] : E[r + x - s + w];
      out[r + x] = v;
    }
  }
}

function bestShift(f, S, E, w, h, sgn) {
  const P = new Uint8Array(w * h);
  let best = { s: 0, e: Infinity };
  const tryS = s => { predict(S, E, w, h, s, sgn, P); const e = sad(f, P); if (e < best.e) best = { s, e }; };
  for (let s = 0; s <= w; s += 6) tryS(Math.min(s, w - 1));
  const c = best.s;
  for (let s = Math.max(0, c - 6); s <= Math.min(w - 1, c + 6); s++) tryS(s);
  if (best.s >= w - 1) { predict(S, E, w, h, 0, sgn, P); const e = sad(f, P); if (e <= best.e) best = { s: w, e }; }   // s = w — это конец
  return best;
}

function slide(fr, evs, lines, dirs) {
  const out = [];
  evs.forEach((ev, n) => {
    const a = Math.max(0, ev.i0 - 1), b = Math.min(fr.n - 1, ev.i1 + 1);
    const S = fr.data[a], E = fr.data[b];
    const base = sad(S, E) || 1;
    // Кадр — это начало, конец, скольжение (сдвиг подходит) или иное (смесь, прыжок).
    const run = sgn => {
      const rows = [];
      for (let k = a; k <= b; k++) {
        const f = fr.data[k], toS = sad(f, S) / base, toE = sad(f, E) / base;
        const r = bestShift(f, S, E, fr.w, fr.h, sgn);
        rows.push({ k, toS, toE, s: r.s, e: r.e / base });
      }
      return rows;
    };
    const cls = r => (r.toS < 0.02 ? 'S' : r.toE < 0.02 ? 'E' : r.e < 0.35 && r.s > 0 && r.s < fr.w ? 'slide' : 'other');
    const pos = run(1), neg = run(-1);
    const score = rows => rows.reduce((t, r) => t + Math.min(r.e, r.toS, r.toE), 0);
    const rows = score(pos) <= score(neg) ? pos : neg, sgn = rows === pos ? 1 : -1;
    const kinds = rows.map(cls);
    const idx = rows.map(r => r.k);
    const ps = rows.map((r, i) => kinds[i] === 'S' ? 0 : kinds[i] === 'E' ? 1 : kinds[i] === 'slide' ? r.s / fr.w : 1 - r.toE / (r.toS + r.toE || 1));
    const nSlide = kinds.filter(k => k === 'slide').length, nOther = kinds.filter(k => k === 'other').length;
    const ghost = Math.max(0, ...rows.filter((_, i) => kinds[i] === 'slide').map(r => r.e));
    const label = `шаг ${n + 1} (ждём: новое ${dirs[n] > 0 ? 'справа' : 'слева'})`;
    const ts = idx.map(k => fr.ts[k] - fr.ts[idx[0]]);
    const dts = ts.slice(1).map((t, i) => t - ts[i]).filter(d => d > 0).sort((x, y) => x - y);
    const sm = summarize(fr, idx, ps, lines, `${label}; скольжение в ${nSlide} кадрах, «иное» (смесь/прыжок) в ${nOther}` + (nSlide ? `; новое едет ${sgn > 0 ? 'справа' : 'слева'}; остаток подгонки ${r3(ghost)}` : ''));
    const peak = Math.max(0, ...rows.filter((_, i) => kinds[i] === 'slide').map(r => r.s));
    lines.push(`  смещение, pt по кадрам: ${rows.map((r, i) => kinds[i] === 'S' ? 'нач' : kinds[i] === 'E' ? 'кон' : kinds[i] === 'slide' ? Math.round(r.s) : 'иное').join(' ')}; кадров между событиями ${dts.length ? ms(dts[Math.floor(dts.length / 2)]) + ' мс (медиана)' : '—'}`);
    out.push({ sgn, ghost, peak, w: fr.w, nSlide, nOther, inPath: nSlide, ...sm, inPath2: sm.inPath, want: dirs[n] > 0 ? 1 : -1 });
  });
  return out;
}

/* ---------- вкладка: прозрачность и сдвиг по регрессии ---------- */
function rise(fr, ev) {
  const a = Math.max(0, ev.i0 - 1), b = Math.min(fr.n - 1, ev.i1 + 1);
  const E = fr.data[b], w = fr.w, h = fr.h;
  const idx = [], A = [], DY = [];
  for (let k = a; k <= b; k++) {
    const f = fr.data[k];
    let best = { err: Infinity };
    for (let dy = 0; dy <= 12; dy++) {
      // f ≈ u + a·E(y − dy): двухпараметровая регрессия по пикселям
      let n = 0, sx = 0, sy = 0, sxx = 0, sxy = 0, syy = 0;
      for (let y = dy; y < h; y++) {
        for (let x = 0; x < w; x += 2) {
          const e = E[(y - dy) * w + x], v = f[y * w + x];
          n++; sx += e; sy += v; sxx += e * e; sxy += e * v; syy += v * v;
        }
      }
      const den = n * sxx - sx * sx;
      const al = den ? (n * sxy - sx * sy) / den : 0, u = (sy - al * sx) / n;
      const err = syy - 2 * al * sxy - 2 * u * sy + al * al * sxx + 2 * al * u * sx + n * u * u;
      if (err < best.err) best = { err, al, dy };
    }
    idx.push(k); A.push(best.al); DY.push(best.dy);
  }
  return { idx, A, DY };
}

/* ---------- сценарии ---------- */
const SPEC = {
  month: {
    scope: 'month', trig: 3,
    region: nodes => { const c = nodes.cal; return { rect: [c.x, c.y, c.w, 240] }; },
  },
  week: {
    scope: 'week', trig: 3,
    region: nodes => { const c = nodes.week; return { rect: [0, c.y, 440, 300] }; },
  },
  bar: {
    scope: 'month', trig: 2,
    region: nodes => { const c = nodes['dp.bar']; return { rect: [0, Math.max(0, c.y - 30), 440, 90] }; },
  },
  fan: {
    scope: 'month', trig: 2,
    region: nodes => { const c = nodes['plan.scope']; return { rect: [0, c.y, 330, 44 + 8 + 210] }; },
  },
  tab: {
    scope: 'month', trig: 4,
    region: () => ({ rect: [0, 70, 440, 730] }),
  },
  ring: {
    scope: 'month', trig: 0, now: process.env.LP_RING_NOW || '2026-10-26T13:00:00+07:00',   // позже сида: сдачи октября уже просрочены
    region: (nodes, log) => {
      const m = /lit ([\d,]+)/.exec(log);
      if (!m) throw new Error('в сиде нет просроченных сдач в этом месяце (нечему дышать)');
      const day = m[1].split(',')[0], c = nodes[`cal.n.${day}-0`];
      if (!c) throw new Error('нет рамки числа ' + day);
      return { rect: [c.x, c.y + (c.h - 26), 26, 26], day };   // рамка узла включает отступ сверху 5 pt
    },
  },
};

function analyze(name, r, opt) {
  const fr = r.fr, lines = [], res = { red: 0, name, lines };
  const spec = SPEC[name];
  const bad = (cond, msg) => { if (!cond) { res.red++; lines.push('КРАСНОЕ: ' + msg); } };
  lines.push(`кадров ${fr.n}, область ${fr.w}×${fr.h} pt, длина ${r3(fr.ts[fr.n - 1])} с, ${r3(fr.n / fr.ts[fr.n - 1])} кадр/с`);
  const still = /start still=true/.test(r.log);
  lines.push(`уменьшение движения у приложения: ${still ? 'включено' : 'выключено'}`);
  if (opt.still !== still) lines.push(`ВНИМАНИЕ: просили ${opt.still ? 'включить' : 'выключить'} уменьшение движения, приложение видит иное`);

  if (name === 'ring') return ring(fr, r, lines, res, bad, opt);

  const ev = events(fr, spec.trig);
  lines.push(`событий движения найдено ${ev.all}, берём последние ${ev.list.length}; все: ` + ev.list0.map(e => `${r3(fr.ts[e.i0])}–${r3(fr.ts[e.i1])} с`).join(', '));
  if (ev.list.length < spec.trig) { bad(false, 'движений меньше, чем запускал стенд'); return res; }

  if (name === 'month' || name === 'week') {
    const out = slide(fr, ev.list, lines, [1, -1, 1]);
    res.slide = out;
    if (opt.check) {
      out.forEach((o, n) => {
        const L = `шаг ${n + 1}`;
        if (opt.still) { bad(o.inPath === 0, `${L}: при уменьшении движения кадров в пути ${o.inPath}, нужно 0`); return; }
        bad(o.sgn === o.want, `${L}: направление ${o.sgn > 0 ? 'справа' : 'слева'}, ждали ${o.want > 0 ? 'справа' : 'слева'}`);
        bad(o.inPath >= 8, `${L}: кадров в пути ${o.inPath}, нужно ≥ 8`);
        bad(o.total >= 0.24 && o.total <= 0.36, `${L}: путь до 98 % ${ms(o.total)} мс, нужно 240–360`);
        bad(o.fit.D >= 0.26 && o.fit.D <= 0.36, `${L}: длительность ${ms(o.fit.D)} мс, нужно 260–360`);
        bad(o.e1.rms <= 0.06, `${L}: E1 rms ${r3(o.e1.rms)}, нужно ≤ 0,06`);
        bad(o.peak >= o.w - 2, `${L}: пик смещения ${Math.round(o.peak)} из ${o.w}`);
        bad(o.ghost <= 0.15, `${L}: «призрак» ${r3(o.ghost)}, нужно ≤ 0,15`);
      });
    }
    return res;
  }

  if (name === 'tab') {
    res.rise = [];
    ev.list.forEach((e, n) => {
      const q = rise(fr, e);
      const ts = q.idx.map(k => fr.ts[k] - fr.ts[q.idx[0]]);
      const onset = ts[Math.max(0, q.A.findIndex(p => p > 0.02) - 1)];
      const fit = fitCurve(ts, q.A.map(v => Math.min(1.2, Math.max(-0.2, v))), onset);
      const inPath = q.A.filter(p => p > 0.02 && p < 0.98).length;
      const dy0 = q.DY[Math.max(0, q.A.findIndex(p => p > 0.02))];
      lines.push(`вкладка ${n + 1} (${n % 2 ? 'в «Съёмки»' : 'в «Свет»'}): кадров в пути ${inPath}; прозрачность: ${q.A.map(v => r3(v)).join(' ')}`);
      lines.push(`  сдвиг вниз, pt: ${q.DY.join(' ')}; лучшая кривая прозрачности ${fit.name} D=${ms(fit.D)} мс (rms ${r3(fit.rms)}), E1 rms ${r3(fit.all.E1.rms)}`);
      res.rise.push({ n, inPath, fit, dy0, A: q.A, DY: q.DY, e1: fit.all.E1 });
    });
    if (opt.check) {
      res.rise.forEach(o => {
        const L = `вкладка ${o.n + 1}`;
        bad(o.inPath >= 8, `${L}: кадров в пути ${o.inPath}, нужно ≥ 8`);
        bad(o.e1.D >= 0.40 && o.e1.D <= 0.50 && o.e1.rms <= 0.08, `${L}: E1 D=${ms(o.e1.D)} мс rms ${r3(o.e1.rms)}, нужно D 400–500, rms ≤ 0,08`);
        bad(o.dy0 >= 6 && o.dy0 <= 9, `${L}: сдвиг в начале ${o.dy0} pt, нужно 6–9 (≈ 8)`);
        bad(Math.max(...o.DY.slice(-2)) === 0, `${L}: в конце сдвиг не вернулся в 0`);
      });
    }
    return res;
  }

  // bar, fan: доля пути и (для сводки) геометрия из журнала приложения
  res.prog = [];
  ev.list.forEach((e, n) => {
    const p = progress(fr, e);
    const label = name === 'bar' ? (n === 0 ? 'схлопывание' : 'раскрытие') : (n === 0 ? 'открытие веера' : 'закрытие веера');
    const sm = summarize(fr, p.idx, p.ps, lines, label);
    res.prog.push({ n, ...sm });
  });
  if (name === 'bar') bar(fr, r, lines, res, bad, opt);
  if (name === 'fan') fan(fr, ev.list[0], lines, res, bad, opt);
  return res;
}

/* Журнал приложения: `geo <имя> x y w h` по кадрам — геометрия сводки, пока она едет. */
function geoSeries(log, name, from, to) {
  const out = [];
  for (const l of log.split('\n')) {
    const m = new RegExp(`^(\\d+\\.\\d+) geo ${name.replace('.', '\\.')} (\\S+) (\\S+) (\\S+) (\\S+)`).exec(l);
    if (m) out.push({ t: +m[1], x: +m[2], y: +m[3], w: +m[4], h: +m[5] });
  }
  return out;
}
function marks(log) {
  const o = [];
  for (const l of log.split('\n')) { const m = /^(\d+\.\d+) motion \w+ (fold|fan|flip|tab)/.exec(l); if (m) o.push(+m[1]); }
  return o;
}

function bar(fr, r, lines, res, bad, opt) {
  const mk = marks(r.log);
  if (mk.length < 2) { lines.push('журнал приложения без отметок сводки'); return; }
  const out = [];
  mk.slice(0, 2).forEach((t0, n) => {
    const t1 = mk[n + 1] ?? t0 + 1.6;
    const g = geoSeries(r.log, 'dp.bar').filter(v => v.t >= t0 - 0.001 && v.t < t1);
    if (!g.length) { lines.push(`${n ? 'раскрытие' : 'схлопывание'}: в журнале нет рамок сводки (геометрия не менялась или узла нет)`); out.push({ n, frames: 0 }); return; }
    const w0 = g[0].w, wN = g[g.length - 1].w;
    const ws = g.map(v => Math.round(v.w));
    const tEnd = g[g.length - 1].t - t0;
    const inPath = g.filter(v => v.w > Math.min(w0, wN) + 1 && v.w < Math.max(w0, wN) - 1).length;
    lines.push(`${n ? 'раскрытие' : 'схлопывание'} (журнал, ширина .dp-bar): ${ws.length} записей, ширина ${Math.round(w0)} → ${Math.round(wN)} pt, последняя запись через ${ms(tEnd)} мс, промежуточных ${inPath}`);
    lines.push(`  ширина по записям: ${ws.join(' ')}`);
    out.push({ n, frames: g.length, inPath, w0, wN, tEnd });
  });
  res.bar = out;
  if (opt.check) {
    out.forEach(o => {
      const L = o.n ? 'раскрытие' : 'схлопывание';
      bad(o.inPath >= 6, `${L}: промежуточных значений ширины ${o.inPath}, нужно ≥ 6 (ширина должна ехать)`);
      bad(o.tEnd >= 0.40 && o.tEnd <= 0.55, `${L}: ширина едет ${ms(o.tEnd || 0)} мс, нужно 400–550`);
    });
    res.prog.forEach(o => bad(o.total >= 0.3 && o.total <= 0.62, `кадры: путь до 98 % ${ms(o.total)} мс, нужно 300–620`));
  }
}

/* Веер: рамка изменившихся точек в первых кадрах открытия — сжатие и сдвиг вверх. */
function fan(fr, ev, lines, res, bad, opt) {
  const a = Math.max(0, ev.i0 - 1), b = Math.min(fr.n - 1, ev.i1 + 1);
  const S = fr.data[a], E = fr.data[b], w = fr.w, h = fr.h;
  const box = f => {
    let mx = 0; const d = new Float32Array(w * h);
    for (let i = 0; i < d.length; i++) { d[i] = Math.abs(f[i] - S[i]); if (d[i] > mx) mx = d[i]; }
    const th = Math.max(6, mx * 0.5);
    let x0 = w, y0 = h, x1 = -1, y1 = -1;
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) if (d[y * w + x] >= th) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
    return x1 < 0 ? null : { x0, y0, x1, y1, w: x1 - x0 + 1, h: y1 - y0 + 1 };
  };
  const fin = box(E);
  const rows = [];
  for (let k = a + 1; k <= b; k++) {
    const q = box(fr.data[k]);
    if (!q || !fin) continue;
    rows.push({ t: fr.ts[k] - fr.ts[a + 1], sw: q.w / fin.w, sh: q.h / fin.h, top: q.y0 - fin.y0, left: q.x0 - fin.x0 });
  }
  lines.push(`рамка веера в конце: ${fin ? `${fin.w}×${fin.h} pt` : 'не найдена'}; по кадрам открытия (t мс: ширина/высота от конечной, сдвиг верха и левого края pt):`);
  lines.push('  ' + rows.slice(0, 10).map(q => `${ms(q.t)}: ${r3(q.sw)}/${r3(q.sh)} ${q.top >= 0 ? '+' : ''}${q.top},${q.left >= 0 ? '+' : ''}${q.left}`).join(' · '));
  res.fan = rows;
  const first = rows[0];
  if (opt.check && first) {
    bad(first.sw <= 0.97 && first.sw >= 0.92, `первый кадр: ширина ${r3(first.sw)} от конечной, нужно ≈ 0,94–0,96 (старт 0,94)`);
    bad(first.top <= -2, `первый кадр: верх выше конечного на ${-first.top} pt, нужно ≥ 2 (сдвиг −6 к нулю)`);
  }
}

/* Дыхание кольца: яркость кольца у края подложки (без цифры) во времени. */
function ring(fr, r, lines, res, bad, opt) {
  const w = fr.w, h = fr.h, cx = (w - 1) / 2, cy = (h - 1) / 2;
  const inRing = (x, y) => { const d = Math.hypot(x - cx, y - cy); return d >= 10 && d <= 12.5 && Math.abs(y - cy) > 4; };
  const outside = (x, y) => Math.hypot(x - cx, y - cy) > 14.5;
  const pix = (pred) => { const o = []; for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) if (pred(x, y)) o.push(y * w + x); return o; };
  const R = pix(inRing), O = pix(outside);
  const L = [], B = [];
  for (let k = 0; k < fr.n; k++) {
    let s = 0, b = 0; const f = fr.data[k];
    for (const i of R) s += f[i]; for (const i of O) b += f[i];
    L.push(s / R.length); B.push(b / O.length);
  }
  const d = L.map((v, i) => v - B[i]);
  // запуск приложения кончается к ~4,5 с видео (запись идёт с 2,5 с до запуска); дальше кольцо в покое или дышит
  const t1 = fr.ts[fr.n - 1], from = Math.max(0, fr.ts.findIndex(t => t >= 4.5));
  const seg = d.slice(from), ts = Array.from(fr.ts.slice(from));
  const hi = Math.max(...seg), lo = Math.min(...seg);
  const ratio = hi ? lo / hi : 1;
  // минимумы и максимумы по сглаженному ряду
  const sm = seg.map((_, i) => { let s = 0, n = 0; for (let j = Math.max(0, i - 6); j <= Math.min(seg.length - 1, i + 6); j++) { s += seg[j]; n++; } return s / n; });
  const mid = (hi + lo) / 2, cross = [];
  for (let i = 1; i < sm.length; i++) if ((sm[i - 1] - mid) * (sm[i] - mid) < 0 && sm[i] > sm[i - 1]) cross.push(ts[i]);
  const periods = cross.slice(1).map((t, i) => t - cross[i]);
  const period = periods.length ? periods.reduce((a, b) => a + b, 0) / periods.length : null;
  lines.push(`день ${r.region.day}: яркость кольца над фоном: макс ${r3(hi)}, мин ${r3(lo)}, отношение мин/макс ${r3(ratio)} (ждём 0,55); ход ${r3(hi - lo)} уровней серого; период ${period ? r3(period) + ' с' : 'не найден'} по ${cross.length} подъёмам (ждём 3,6)`);
  lines.push(`  окно ${r3(ts[0])}–${r3(ts[ts.length - 1])} с, ${seg.length} кадров; ряд раз в ~0,5 с: ` + seg.filter((_, i) => i % 15 === 0).map(v => r3(v)).join(' '));
  res.ring = { hi, lo, ratio, period, rises: cross.length };
  if (opt.check) {
    if (opt.still) { bad(hi - lo <= 1.5 || hi === 0, `при уменьшении движения яркость ходит на ${r3(hi - lo)}, нужно стоять`); return res; }
    bad(ratio >= 0.45 && ratio <= 0.65, `отношение мин/макс ${r3(ratio)}, нужно 0,45–0,65 (прозрачность 1 ↔ 0,55)`);
    bad(period && period >= 3.3 && period <= 3.9, `период ${period ? r3(period) : '—'} с, нужно 3,3–3,9`);
  }
  return res;
}

module.exports = { readFrames, SPEC, analyze, CURVES, fitCurve, bezier };
