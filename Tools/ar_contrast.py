#!/usr/bin/env python3
"""Шаги 29.8в.4 и 29.8в.9б: контраст текста нижней панели и значков кнопок AR на сплошных подложках.

Панель и кнопки — системное стекло `.glassEffect`: его цвет не лежит в константах, поэтому контраст считается по
снимку симулятора. Фон — сплошной (`-LPSunARBackdrop`, отладка), без камеры.

Подложки: white (белое небо), sky (голубое небо), asphalt (асфальт), night (ночное небо); для панели ещё gray и
black из 29.8в.4 (`--backdrops`). Вид стекла кнопок — `-LPSunARButtonGlass` (`--variants a,b,c`; пусто = как в
сборке). Для каждой кнопки (рамки из отчёта приложения, `-LPShotReport`):

  * значок / подпись. Область — рамка, втянутая на 8 pt (на 4 pt у стрелки за краем): кромка стекла в неё не
    попадает. Фон — медиана яркости области; чернила — перцентиль 99 (светлые чернила) или 1 (тёмные), с той
    стороны, куда пиксели уходят дальше от медианы. Контраст WCAG: (L1 + 0,05) / (L2 + 0,05). Цель ≥ 3 : 1
    (элементы интерфейса, WCAG 1.4.11).
  * «стекло, а не плашка»: яркость области кнопки против яркости подложки рядом. Кнопка темнее подложки больше
    чем в 5 раз (`--max-dim`, по умолчанию 0,2: яркость кнопки не ниже 0,2 от подложки) — это тёмная плашка, а не
    стекло. Прежний вид 29.8в.4 (`black70`) даёт 0,11 / 0,05 / 0,09 на белом, голубом и асфальте; системное
    стекло само темнеет на средних тонах, но не ниже 0,23 (замер 29.8в.9б).

    python3 Tools/ar_contrast.py [--app <.app>] [--variants regular,clear.s] [--backdrops white,sky,asphalt,night]
                                 [--min 3] [--max-dim 0.2] [--appearance dark|light] [--out DIR] [--detail]
Код 1, если контраст ниже цели или кнопка темнее порога. Текст панели (`ar.time`, `ar.note`, `ar.sunPos`) — цель 4,5 : 1,
как в 29.8в.4, мерится по прежнему правилу (самый светлый пиксель рамки против медианы).
"""
import json, os, re, subprocess, sys, tempfile, time
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FX = os.path.join(ROOT, 'Fixtures', 'shots')
BUNDLE = 'Novopashin.LightPlan'
PANEL = ['ar.time', 'ar.note', 'ar.sunPos']
# Кнопки с кромкой стекла: значок внутри рамки. Стрелка за краем — отдельно (узкий отступ).
BUTTONS = ['ar.back', 'ar.follow', 'ar.calibrate', 'ar.heading', 'ar.layers']
POINTER = 'ar.pointer.sun'
NOW = 'now'


def sh(*a, **k):
    return subprocess.run(a, check=True, capture_output=True, text=True, **k).stdout


def sim_udid():
    name = subprocess.run(['node', os.path.join(ROOT, 'Tools', 'sim.js')], capture_output=True, text=True, cwd=ROOT).stdout
    m = re.search(r'([0-9A-F]{8}-[0-9A-F-]{27})', name)
    if not m:
        sys.exit('нет симулятора ветки: make sims')
    return m.group(1)


def lum(c):
    def ch(v):
        v /= 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * ch(c[0]) + 0.7152 * ch(c[1]) + 0.0722 * ch(c[2])


def contrast(l1, l2):
    hi, lo = max(l1, l2), min(l1, l2)
    return (hi + 0.05) / (lo + 0.05)


def crop_lums(img, frame, scale, inset):
    x, y, w, h = frame['x'] + inset, frame['y'] + inset, frame['w'] - 2 * inset, frame['h'] - 2 * inset
    x, y, w, h = [int(round(v * scale)) for v in (x, y, w, h)]
    box = img.crop((x, y, x + max(w, 1), y + max(h, 1))).convert('RGB')
    return sorted(lum(p) for p in box.getdata())


def pct(ls, q):
    return ls[min(len(ls) - 1, max(0, int(round(q * (len(ls) - 1)))))]


def measure_panel(img, frame, scale):
    """Правило 29.8в.4: самый светлый пиксель рамки против медианы."""
    ls = crop_lums(img, frame, scale, 0)
    return contrast(ls[-1], ls[len(ls) // 2]) if ls else None


def measure_button(img, frame, scale, inset, backdrop_lum):
    """(контраст значка, яркость кнопки / яркость подложки)."""
    ls = crop_lums(img, frame, scale, inset)
    if not ls:
        return None
    bg = ls[len(ls) // 2]
    hi, lo = pct(ls, 0.99), pct(ls, 0.01)
    ink = hi if (hi - bg) >= (bg - lo) else lo
    return contrast(ink, bg), bg / max(backdrop_lum, 1e-4)


def backdrop_luminance(img):
    """Яркость подложки: медиана полосы от 28 % до 56 % высоты — выше кнопки, ниже панель, дуга тонкая."""
    w, h = img.size
    box = img.crop((0, int(h * 0.28), w, int(h * 0.56))).convert('RGB')
    ls = sorted(lum(p) for p in list(box.getdata())[::7])
    return ls[len(ls) // 2]


def run_case(udid, backdrop, variant, out, extra):
    tag = '%s_%s' % (variant or 'build', backdrop)
    report = os.path.join(out, tag + '.json')
    png = os.path.join(out, tag + '.png')
    if os.path.exists(report):
        os.remove(report)
    subprocess.run(['xcrun', 'simctl', 'terminate', udid, BUNDLE], capture_output=True)
    args = ['-AppleLanguages', '(ru)', '-AppleLocale', 'ru_RU',
            '-LPShotNow', '2026-10-20T21:00:00+07:00', '-LPShotZone', 'Asia/Tomsk', '-LPShotSeed', FX + '/seed.json',
            '-LPShotForecast', FX + '/forecast_barnaul.json', '-LPShotAir', FX + '/air_barnaul.json',
            '-LPShotName', FX + '/place_barnaul.json', '-LPShotScreen', 'map', '-LPShotReportDelay', '5',
            '-lightplan.native.sunar.calibrationSeen', 'YES', '-lightplan.native.sunar.moon', 'NO',
            '-lightplan.native.sunar.milkyWay', 'NO',
            # Выбранный момент на 3 часа раньше «сейчас»: кнопка «Сейчас» в таймбаре на экране.
            '-LPSunAR', '1', '-LPSunARMoment', '2026-10-20T11:00:00Z', '-LPSunARPose', '183,18,0',
            '-LPSunARPhone', '56.4977,84.9744,Asia/Tomsk', '-LPSunARBackdrop', backdrop, '-LPShotReport', report]
    if variant:
        args += ['-LPSunARButtonGlass', variant]
    sh('xcrun', 'simctl', 'launch', udid, BUNDLE, *args, *extra)
    for _ in range(240):
        if os.path.exists(report):
            break
        time.sleep(0.25)
    else:
        sys.exit('нет рамок: ' + tag)
    # Системное стекло подстраивается под подложку не сразу (замер 29.8в.9б: на белом оно начинает тёмным и за ~3 с
    # светлеет), поэтому снимок берётся, когда полоса кнопок два кадра подряд (через 1 с) не меняется.
    time.sleep(2.5)
    prev = None
    for _ in range(8):
        sh('xcrun', 'simctl', 'io', udid, 'screenshot', '--type=png', png)
        img = Image.open(png)
        strip = img.crop((0, int(img.size[1] * 0.03), img.size[0], int(img.size[1] * 0.2))).convert('L').resize((60, 20))
        cur = list(strip.getdata())
        if prev is not None and max(abs(a - b) for a, b in zip(cur, prev)) <= 2:
            break
        prev = cur
        time.sleep(1.0)
    else:
        print('!! стекло не успокоилось: ' + tag, file=sys.stderr)
    data = json.load(open(report))
    img = Image.open(png)
    return data['nodes'], img.size[0] / data['size'][0], img


def opt(name, default=None):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


def main():
    out = opt('--out') or tempfile.mkdtemp(prefix='lp-ar-contrast-')
    os.makedirs(out, exist_ok=True)
    minimum = float(opt('--min', 3.0))
    max_dim = float(opt('--max-dim', 0.2))
    backdrops = opt('--backdrops', 'white,sky,asphalt,night').split(',')
    variants = opt('--variants', '').split(',') if opt('--variants') is not None else ['']
    extra = opt('--extra', '').split() if opt('--extra') else []
    detail = '--detail' in sys.argv
    udid = sim_udid()
    subprocess.run(['xcrun', 'simctl', 'boot', udid], capture_output=True)
    subprocess.run(['xcrun', 'simctl', 'ui', udid, 'appearance', opt('--appearance', 'dark')], capture_output=True)
    if opt('--app'):
        sh('xcrun', 'simctl', 'install', udid, opt('--app'))
    table, red = {}, False
    worst_panel = 99.0
    for variant in variants:
        for backdrop in backdrops:
            nodes, scale, img = run_case(udid, backdrop, variant, out, extra)
            back = backdrop_luminance(img)
            cells = {}
            for name in PANEL:
                if name in nodes:
                    r = measure_panel(img, nodes[name], scale)
                    if r:
                        worst_panel = min(worst_panel, r)
            for name in BUTTONS + [POINTER, NOW]:
                if name not in nodes:
                    continue
                inset = 4 if name == POINTER else 0 if name == NOW else 8
                if name == NOW:
                    ls = crop_lums(img, nodes[name], scale, 0)
                    # «Сейчас» — текст без стеклянной кромки: светлее/темнее медианы так же, самый дальний перцентиль.
                    bg = ls[len(ls) // 2]
                    hi, lo = pct(ls, 0.99), pct(ls, 0.01)
                    ink = hi if (hi - bg) >= (bg - lo) else lo
                    cells[name] = (contrast(ink, bg), None)
                else:
                    r = measure_button(img, nodes[name], scale, inset, back)
                    if r:
                        cells[name] = r
            table[(variant, backdrop)] = (cells, back)
    # Таблица: вариант × подложка → худший значок кнопок (без «Сейчас», он без своего стекла) и самая тёмная кнопка.
    print('вариант стекла × подложка → худший контраст значка / самая тёмная кнопка (яркость кнопки к подложке)')
    print('%-18s' % 'вариант' + ''.join('%-24s' % b for b in backdrops))
    for variant in variants:
        row = '%-18s' % (variant or 'как в сборке')
        for backdrop in backdrops:
            cells, back = table[(variant, backdrop)]
            glass = {k: v for k, v in cells.items() if k != NOW and v[1] is not None}
            if not glass:
                row += '%-24s' % 'нет кнопок'
                continue
            worst = min(v[0] for v in glass.values())
            dim = min(v[1] for v in glass.values())
            bad = worst < minimum or dim < max_dim
            red = red or bad
            row += '%-24s' % ('%.2f:1 / %.2f%s' % (worst, dim, ' ✗' if bad else ''))
        print(row)
        if detail:
            for backdrop in backdrops:
                cells, back = table[(variant, backdrop)]
                print('   %-8s подложка L=%.3f' % (backdrop, back) + ''.join(
                    '  %s %.2f:1%s' % (k.replace('ar.', ''), v[0], '' if v[1] is None else '/%.2f' % v[1]) for k, v in cells.items()))
    print('худший у текста панели: %.2f : 1 (цель ≥ 4,5)' % worst_panel)
    red = red or worst_panel < 4.5
    # «Сейчас» — мелкий текст в таймбаре на стекле (29.8в.10: латунь brassDeep давала 3,26 и 4,01): цель тоже 4,5.
    worst_now = min((cells[NOW][0] for cells, _ in table.values() if NOW in cells), default=99)
    print('«Сейчас»: %.2f : 1 (цель ≥ 4,5)' % worst_now)
    red = red or worst_now < 4.5
    print('цель кнопок: значок ≥ %.1f : 1, кнопка не темнее %.2f подложки; → %s' % (minimum, max_dim, out))
    sys.exit(1 if red else 0)


main()
