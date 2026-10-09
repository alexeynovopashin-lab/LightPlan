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

/* Лучшая t0 при заданной длительности D: rms каждой кривой на ожидаемых числах беты. */
function fixedFit(ts, ps, onset, D) {
  const out = {};
  for (const [name, c] of Object.entries(CURVES)) {
    let b = Infinity;
    for (let t0 = onset - 0.05; t0 <= onset + 0.03; t0 += 0.004) {
      let s = 0;
      for (let i = 0; i < ts.length; i++) { const e = ps[i] - c((ts[i] - t0) / D); s += e * e; }
      b = Math.min(b, Math.sqrt(s / ts.length));
    }
    out[name] = b;
  }
  return out;
}

/* Ряд кадров события и доля пути p(t) → строка с числами; `expectD` — длительность беты в секундах. */
function summarize(fr, idx, ps, lines, label, expectD) {
  const ts = idx.map(k => fr.ts[k] - fr.ts[idx[0]]);
  const onset = ts[Math.max(0, ps.findIndex(p => p > 0.02) - 1)];
  const inPath = ps.filter(p => p > 0.02 && p < 0.98).length;
  const at = q => { const k = ps.findIndex((p, i) => i > 0 && p >= q); return k < 0 ? ts[ts.length - 1] - onset : ts[k] - onset; };
  const t50 = at(0.5), t90 = at(0.9), total = at(0.98);
  const fit = fitCurve(ts, ps, onset);
  const fixed = expectD ? fixedFit(ts, ps, onset, expectD) : null;
  lines.push(`${label}: кадров в пути ${inPath}; доля пути 50 % за ${ms(t50)} мс, 90 % за ${ms(t90)} мс, 98 % за ${ms(total)} мс; свободный подбор ${fit.name} D=${ms(fit.D)} мс (rms ${r3(fit.rms)})`
    + (fixed ? `; при D=${ms(expectD)} мс rms: ${Object.entries(fixed).map(([k, v]) => `${k} ${r3(v)}`).join(', ')}` : ''));
  return { inPath, total, t50, t90, fit, e1: fit.all.E1, fixed };
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

/* Цена каждого сдвига 0…w для кадра (строки через одну: быстрее, числа те же). */
function shiftCosts(f, S, E, w, h, sgn) {
  const c = new Float64Array(w + 1);
  for (let sh = 0; sh <= w; sh++) {
    let e = 0;
    for (let y = 0; y < h; y += 2) {
      const r = y * w;
      for (let x = 0; x < w; x++) {
        let v;
        if (sgn > 0) v = x + sh < w ? S[r + x + sh] : E[r + x + sh - w];
        else v = x - sh >= 0 ? S[r + x - sh] : E[r + x - sh + w];
        e += Math.abs(f[r + x] - v);
      }
    }
    c[sh] = e * 2;
  }
  return c;
}

/* Сдвиг по кадрам не убывает (страница едет в одну сторону): путь с наименьшей суммой цен. Узор цифр повторяется
   через колонку, и поодиночке кадры путаются на кратные сдвиги — монотонность это снимает. */
function monotonePath(costs) {
  const n = costs.length, m = costs[0].length;
  const best = costs.map(c => Float64Array.from(c)), from = costs.map(() => new Int32Array(m));
  for (let k = 1; k < n; k++) {
    let run = Infinity, at = 0;
    for (let sh = 0; sh < m; sh++) {
      if (best[k - 1][sh] < run) { run = best[k - 1][sh]; at = sh; }
      best[k][sh] += run; from[k][sh] = at;
    }
  }
  let sh = 0, e = Infinity;
  for (let i = 0; i < m; i++) if (best[n - 1][i] < e) { e = best[n - 1][i]; sh = i; }
  const path = new Array(n);
  for (let k = n - 1; k >= 0; k--) { path[k] = sh; sh = from[k][sh]; }
  return path;
}

function slide(fr, evs, lines, dirs) {
  const out = [], ends = [];
  evs.forEach((ev, n) => {
    const a = Math.max(0, ev.i0 - 1), b = Math.min(fr.n - 1, ev.i1 + 1);
    const S = fr.data[a], E = fr.data[b];
    const base = sad(S, E) || 1;
    // Кадр — это начало, конец, скольжение (сдвиг подходит) или иное (смесь, прыжок).
    const run = sgn => {
      const costs = [], pre = [];
      for (let k = a; k <= b; k++) {
        const f = fr.data[k], toS = sad(f, S) / base, toE = sad(f, E) / base;
        // Смесь: S + α(E − S) с лучшим α; скольжение засчитываем, только если сдвиг подходит заметно лучше смеси.
        let num = 0, den = 0; for (let i = 0; i < f.length; i++) { const d = E[i] - S[i]; num += (f[i] - S[i]) * d; den += d * d; }
        const al = Math.min(1, Math.max(0, den ? num / den : 0)); let eb = 0;
        for (let i = 0; i < f.length; i++) eb += Math.abs(f[i] - (S[i] + al * (E[i] - S[i])));
        costs.push(shiftCosts(f, S, E, fr.w, fr.h, sgn)); pre.push({ k, toS, toE, eb: eb / base, al });
      }
      const path = monotonePath(costs);
      return pre.map((r, i) => ({ ...r, s: path[i], e: costs[i][path[i]] / base }));
    };
    const cls = r => (r.toS < 0.02 ? 'S' : r.toE < 0.02 ? 'E' : r.e < 0.85 * r.eb && r.s > 0 && r.s < fr.w ? 'slide' : 'other');
    const pos = run(1), neg = run(-1);
    const score = rows => rows.reduce((t, r) => t + r.e, 0);
    const rows = score(pos) <= score(neg) ? pos : neg, sgn = rows === pos ? 1 : -1;
    const kinds = rows.map(cls);
    const idx = rows.map(r => r.k);
    // До первого и после последнего скольжения «иное» — это своё движение на месте (подсветка строки): в путь не берём.
    const first = kinds.indexOf('slide'), last = kinds.lastIndexOf('slide');
    if (first >= 0) kinds.forEach((k, i) => { if (k === 'other' && i < first) kinds[i] = 'S'; else if (k === 'other' && i > last) kinds[i] = 'E'; });
    const ps = rows.map((r, i) => kinds[i] === 'S' ? 0 : kinds[i] === 'E' ? 1 : kinds[i] === 'slide' ? r.s / fr.w : r.al);
    const nSlide = kinds.filter(k => k === 'slide').length, nOther = kinds.filter(k => k === 'other').length;
    const ghost = Math.max(0, ...rows.filter((_, i) => kinds[i] === 'slide').map(r => r.e));
    const label = `шаг ${n + 1} (ждём: новое ${dirs[n] > 0 ? 'справа' : 'слева'})`;
    const ts = idx.map(k => fr.ts[k] - fr.ts[idx[0]]);
    const dts = ts.slice(1).map((t, i) => t - ts[i]).filter(d => d > 0).sort((x, y) => x - y);
    const sm = summarize(fr, idx, ps, lines, `${label}; скольжение в ${nSlide} кадрах, «иное» (смесь/прыжок) в ${nOther}` + (nSlide ? `; новое едет ${sgn > 0 ? 'справа' : 'слева'}` : ''), 0.3);
    const peak = Math.max(0, ...rows.filter((_, i) => kinds[i] === 'slide').map(r => r.s));
    lines.push(`  смещение, pt по кадрам: ${rows.map((r, i) => kinds[i] === 'S' ? 'нач' : kinds[i] === 'E' ? 'кон' : kinds[i] === 'slide' ? Math.round(r.s) : 'иное').join(' ')}; кадров между событиями ${dts.length ? ms(dts[Math.floor(dts.length / 2)]) + ' мс (медиана)' : '—'}`);
    ends.push({ S, E, base });
    out.push({ sgn, ghost, peak, w: fr.w, nSlide, nOther, inPath: nSlide, ...sm, inPath2: sm.inPath, want: dirs[n] > 0 ? 1 : -1 });
  });
  // «Призрак»: следов прежнего месяца после остановки нет — тот же месяц в покое после разных шагов совпадает точка в точку.
  if (ends.length === 3) {
    // Покой одного месяца после разных шагов ложится с долей пункта разницы (подпись «↺ сегодня» под шапкой
    // появляется и уходит), поэтому сравнение грубое — средние по квадратам 8 × 8 pt: след прежнего месяца
    // (целые цифры) в такой сетке виден, сдвиг на долю пункта — нет.
    const pool = f => { const o = []; for (let y = 0; y + 8 <= fr.h; y += 8) for (let x = 0; x + 8 <= fr.w; x += 8) { let t = 0; for (let j = 0; j < 8; j++) for (let i = 0; i < 8; i++) t += f[(y + j) * fr.w + x + i]; o.push(t / 64); } return o; };
    const strong = (a, b) => { const A = pool(a), B = pool(b); let t = 0; for (let i = 0; i < A.length; i++) t += Math.abs(A[i] - B[i]); return t; };
    const ref = strong(ends[0].S, ends[0].E) || 1;
    const g1 = strong(ends[0].E, ends[2].E) / ref, g2 = strong(ends[0].S, ends[1].E) / ref;
    lines.push(`покой после шагов: тот же месяц после 1-го и 3-го шага расходится на ${r3(g1)} (доля от разницы двух месяцев в сетке 8 × 8 pt), исходный и после возврата — на ${r3(g2)}`);
    out.ghosts = [g1, g2];
  }
  return out;
}


/* Журнал приложения: отметки стенда и доля пути `pose <имя> p` на каждом кадре. */
function markTimes(log) {
  const o = [];
  for (const l of log.split('\n')) { const m = /^(\d+\.\d+) motion \w+ (fold|fan|flip|tab)/.exec(l); if (m) o.push(+m[1]); }
  return o;
}
function poseRuns(log, name, marks, lastLen = 1.6) {
  const rows = [];
  for (const l of log.split('\n')) { const m = new RegExp(`^(\\d+\\.\\d+) pose ${name} (\\S+)`).exec(l); if (m) rows.push({ t: +m[1], p: +m[2] }); }
  return marks.map((t0, i) => {
    const t1 = marks[i + 1] ?? t0 + lastLen;
    return rows.filter(r => r.t >= t0 - 0.001 && r.t < t1).filter(r => r.p > 0.0001 && r.p < 0.9999).map(r => ({ t: r.t - t0, p: r.p }));
  });
}
/* Ряд (t, p) из журнала → число: куда идёт (вверх или вниз), подбор кривой, ширина пути. */
function runStats(run, lines, label, expectD) {
  if (run.length < 3) { lines.push(`${label}: в журнале ${run.length} промежуточных значений — движения нет`); return { n: run.length }; }
  const up = run[run.length - 1].p > run[0].p;
  const q = run.map(r => (up ? r.p : 1 - r.p));
  const ts = run.map(r => r.t);
  const onset = ts[0];
  const fit = fitCurve(ts, q, onset);
  const fixed = fixedFit(ts, q, onset, expectD);
  const span = ts[ts.length - 1] - ts[0];
  lines.push(`${label}: ${run.length} кадров с промежуточной долей пути за ${ms(span)} мс, первая ${r3(run[0].p)}; свободный подбор ${fit.name} D=${ms(fit.D)} мс (rms ${r3(fit.rms)}); при D=${ms(expectD)} мс rms: ${Object.entries(fixed).map(([k, v]) => `${k} ${r3(v)}`).join(', ')}`);
  return { n: run.length, span, first: run[0].p, fit, fixed, up };
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
  tabs: {
    scope: 'month', trig: 12,
    region: () => ({ rect: [0, 62, 440, 56] }),   // верх экрана под часами: шапка вкладки (город/дата/погода «Света», кнопки «Съёмок»)
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
        bad(o.t90 >= 0.09 && o.t90 <= 0.16, `${L}: 90 % пути за ${ms(o.t90)} мс, нужно 90–160 (E1 0,3 с даёт ≈ 120)`);
        bad(o.total >= 0.14 && o.total <= 0.24, `${L}: 98 % пути за ${ms(o.total)} мс, нужно 140–240 (E1 0,3 с даёт ≈ 180)`);
        bad(o.fixed.E1 <= 0.10 && o.fixed.E1 <= Math.min(o.fixed.linear, o.fixed['ease-in-out']), `${L}: при D=300 E1 rms ${r3(o.fixed.E1)} (линейная ${r3(o.fixed.linear)}, ease-in-out ${r3(o.fixed['ease-in-out'])}), нужно ≤ 0,10 и лучше остальных`);
        bad(o.peak >= o.w - 2, `${L}: пик смещения ${Math.round(o.peak)} из ${o.w}`);
      });
      (out.ghosts || []).forEach((g, i) => bad(g <= 0.15, `покой ${i + 1}: следы прежнего месяца ${r3(g)}, нужно ≤ 0,15`));
    }
    return res;
  }

  if (name === 'tabs') {
    // Шапка не мигает: энергия полосы (отклонение пикселей от медианы кадра) ни на одном кадре перехода не падает
    // ниже доли `DIP` от меньшей из энергий покоя до и после (пустой фон = 0, шапка = заметно больше).
    const energy = f => {
      const s = Array.from(f).sort((a, b) => a - b), med = s[s.length >> 1];
      let t = 0; for (let i = 0; i < f.length; i++) t += Math.abs(f[i] - med);
      return t / f.length;
    };
    const e = fr.data.map(energy);
    res.tabs = ev.list.map((x, n) => {
      const a = Math.max(0, x.i0 - 1), b = Math.min(fr.n - 1, x.i1 + 1);
      let lo = Infinity, at = a; for (let k = a; k <= b; k++) if (e[k] < lo) { lo = e[k]; at = k; }
      const rest = Math.min(e[a], e[b]);
      let dark = 0; for (let k = a; k <= b; k++) if (rest > 0 && e[k] < 0.6 * rest) dark++;
      return { n, from: e[a], to: e[b], min: lo, ratio: rest > 0 ? lo / rest : 1, frames: b - a + 1, at: at - a, dark, darkMs: dark * 1000 / (fr.n / fr.ts[fr.n - 1]) };
    });
    res.tabs.forEach(o => lines.push(`переход ${o.n + 1}: энергия шапки до ${r3(o.from)}, после ${r3(o.to)}, минимум в пути ${r3(o.min)} (кадр ${o.at} из ${o.frames}), доля от меньшей ${r3(o.ratio)}; кадров темнее 0,6 покоя: ${o.dark} (≈ ${ms(o.darkMs / 1000)} мс)`));
    if (opt.check) res.tabs.forEach(o => bad(o.ratio >= 0.6, `переход ${o.n + 1}: шапка проваливается до ${r3(o.ratio)} от покоя, нужно ≥ 0,6`));
    return res;
  }

  if (name === 'tab') {
    // Числа — из журнала (доля пути на каждом кадре, как её отдал SwiftUI); кадры видео подтверждают, что экран вообще двигался.
    const runs = poseRuns(r.log, 'rise', markTimes(r.log).slice(0, 4));
    res.rise = runs.map((run, n) => {
      const st = runStats(run, lines, `вкладка ${n + 1} (${n % 2 ? 'в «Съёмки»' : 'в «Свет»'})`, 0.45);
      if (st.n >= 3) lines.push(`  сдвиг на первом кадре: ${r3(8 * (1 - st.first))} pt из 8; на видео кадров движения ${ev.list[n] ? ev.list[n].i1 - ev.list[n].i0 + 1 : 0}`);
      return { n, ...st };
    });
    if (opt.check) {
      res.rise.forEach(o => {
        const L = `вкладка ${o.n + 1}`;
        bad(o.n >= 10, `${L}: кадров с промежуточной долей пути ${o.n}, нужно ≥ 10`);
        if (o.n < 3) return;
        bad(o.fixed.E1 <= 0.03 && o.fixed.E1 <= o.fixed.linear, `${L}: при D=450 E1 rms ${r3(o.fixed.E1)}, нужно ≤ 0,03 и лучше линейной`);
        bad(o.span >= 0.3 && o.span <= 0.5, `${L}: путь ${ms(o.span)} мс, нужно 300–500`);
        bad((8 * (1 - o.first)) >= 6, `${L}: сдвиг на первом кадре ${r3(8 * (1 - o.first))} pt, нужно ≥ 6`);
      });
      ev.list.forEach((e, n) => bad(e.i1 - e.i0 >= 8, `вкладка ${n + 1}: на видео кадров движения ${e.i1 - e.i0 + 1}, нужно ≥ 9`));
    }
    return res;
  }

  // bar, fan: кадры видео — только «двигалось ли»; числа — из журнала приложения
  res.prog = ev.list.map((e, n) => ({ n, frames: e.i1 - e.i0 + 1 }));
  lines.push('кадров движения на видео: ' + res.prog.map(o => o.frames).join(', '));
  if (name === 'bar') bar(fr, r, lines, res, bad, opt);
  if (name === 'fan') fan(fr, r, lines, res, bad, opt);
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
    const label = n ? 'раскрытие' : 'схлопывание';
    if (g.length < 3) { lines.push(`${label}: в журнале ${g.length} рамок сводки — ширина не ехала`); out.push({ n, frames: g.length, inPath: 0 }); return; }
    const w0 = n ? 40 : g[0].w, wN = n ? g[g.length - 1].w : 40;   // старт и конец известны: полная ширина 392 и ручка 40
    const full = 392, shut = 40;
    const up = n === 1;
    const q = g.map(v => Math.min(1, Math.max(0, up ? (v.w - shut) / (full - shut) : (full - v.w) / (full - shut))));
    const ts = g.map(v => v.t - t0);
    const mid = q.map((v, i) => [v, i]).filter(([v]) => v > 0.02 && v < 0.98);
    const fit = fitCurve(ts, q, ts[0]);
    const fixed = fixedFit(ts, q, ts[0], 0.45);
    const t98 = (() => { const k = q.findIndex(v => v >= 0.98); return k < 0 ? ts[ts.length - 1] : ts[k]; })();
    lines.push(`${label} (журнал, ширина .dp-bar): ${g.length} записей, ширина ${Math.round(g[0].w)} → ${Math.round(g[g.length - 1].w)} pt, промежуточных ${mid.length}, 98 % пути на ${ms(t98)} мс от нажатия; подбор ${fit.name} D=${ms(fit.D)} мс; при D=450 мс rms: ${Object.entries(fixed).map(([k, v]) => `${k} ${r3(v)}`).join(', ')}`);
    lines.push(`  ширина по записям: ${g.map(v => Math.round(v.w)).join(' ')}; высота ${Math.round(g[0].h)} → ${Math.round(g[g.length - 1].h)}`);
    out.push({ n, frames: g.length, inPath: mid.length, t98, fixed, fit });
  });
  res.bar = out;
  if (opt.check) {
    out.forEach(o => {
      const L = o.n ? 'раскрытие' : 'схлопывание';
      if (opt.still) { bad(o.inPath === 0, `${L}: при уменьшении движения промежуточных значений ширины ${o.inPath}, нужно 0`); return; }
      bad(o.inPath >= 6, `${L}: промежуточных значений ширины ${o.inPath}, нужно ≥ 6 (ширина должна ехать)`);
      if (!o.fixed) return;
      bad(o.fixed.E1 <= 0.05 && o.fixed.E1 <= o.fixed.linear, `${L}: при D=450 E1 rms ${r3(o.fixed.E1)} (линейная ${r3(o.fixed.linear)}), нужно ≤ 0,05 и лучше линейной`);
      bad(o.fit.name === 'E1' && o.fit.D >= 0.38 && o.fit.D <= 0.52, `${L}: подбор ${o.fit.name} D=${ms(o.fit.D)} мс, нужно E1 и 380–520`);
    });
  }
}

/* Веер: доля пути `scopeIn` из журнала (ease-out 0,16 с) и поза на первом кадре из чисел беты. */
function fan(fr, r, lines, res, bad, opt) {
  const runs = poseRuns(r.log, 'scopeIn', markTimes(r.log).slice(0, 2), 0.8);
  const open = runStats(runs[0], lines, 'открытие веера', 0.16);
  runStats(runs[1], lines, 'закрытие веера', 0.16);
  res.fan = { open };
  if (open.n >= 3) {
    const sc = 0.94 + 0.06 * open.first, dy = -10 * (1 - sc) - 6 * (1 - open.first);
    lines.push(`  поза на первом кадре: масштаб ${r3(sc)}, сдвиг вверх ${r3(-dy)} pt (старт беты: 0,94 и 6 pt)`);
  }
  if (opt.check) {
    bad(open.n >= 3, `веер: в журнале ${open.n} кадров движения`);
    if (open.n >= 3) {
      bad(open.fixed['ease-out'] <= 0.05 && open.fixed['ease-out'] <= open.fixed.E1, `веер: при D=160 ease-out rms ${r3(open.fixed['ease-out'])} (E1 ${r3(open.fixed.E1)}), нужно ≤ 0,05 и лучше E1`);
      bad(open.span >= 0.1 && open.span <= 0.2, `веер: путь ${ms(open.span)} мс, нужно 100–200`);
    }
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
  // Подложка светлее фона в тёмной теме и темнее в светлой: берём размах по модулю (мин — это слабейший вдох).
  const sign = seg.reduce((a, v) => a + v, 0) < 0 ? -1 : 1, mag = seg.map(v => v * sign);
  const hi = Math.max(...mag), lo = Math.min(...mag);
  const ratio = hi ? lo / hi : 1;
  // минимумы и максимумы по сглаженному ряду
  const sm = seg.map((_, i) => { let s = 0, n = 0; for (let j = Math.max(0, i - 6); j <= Math.min(seg.length - 1, i + 6); j++) { s += mag[j]; n++; } return s / n; });
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
