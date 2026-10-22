#!/usr/bin/env python3
"""Числа к аудиту высот: по рамкам узлов (`native.json` из run.js) на каждую модель и сцену.

  python3 Tools/audit_heights/analyze.py <out> [--sheets]

По каждой паре «сцена × модель» печатает (точки окна, 0 = верх экрана):
  bar     — верх панели вкладок (`tabbar`), если она на экране; иначе «-» (слой поверх вкладок);
  under   — узлы, которых панель закрывает целиком или частично (у узла нет прокрутки, видно только по рамкам);
  wide    — узлы шире окна по горизонтали (x < 0 или x + w > ширины);
  low     — самый нижний узел внутри окна: его низ и зазор до панели (или до низа окна, если панели нет);
  nodes   — сколько узлов отдал экран.
`--sheets` кладёт `<out>/_sheets/<сцена>.png` — модели рядом, чтобы глазом сравнить раскладки.
Это измерение рамок, а не вердикт: узел в прокручиваемом списке может быть под панелью «по рамке» и достижим прокруткой.
Вердикт по каждой строке — в REPORT.md, после просмотра снимка."""
import json, os, sys

MODELS = ['ASE3', 'A15P', 'A17P', 'A15PM', 'A17PM']
SIZE = {'ASE3': (375, 667), 'A15P': (393, 852), 'A17P': (402, 874), 'A15PM': (430, 932), 'A17PM': (440, 956)}


def load(out, model, scene):
    p = os.path.join(out, model, scene, 'native.json')
    if not os.path.exists(p):
        return None
    return json.load(open(p))


def metrics(d):
    nodes = d['nodes']
    w = d['size'][0]
    h = d['size'][1] + d['safe'][0] + d['safe'][1]
    bar = nodes.get('tabbar')
    top = bar['y'] if bar else None
    under, wide = [], []
    low = None
    for k, r in nodes.items():
        if k == 'tabbar' or k.startswith('tabbar.') or k.startswith('tab.'):
            continue
        if r['x'] < -0.5 or r['x'] + r['w'] > w + 0.5:
            if r['y'] < h and r['y'] + r['h'] > 0:
                wide.append(k)
        if r['y'] >= h or r['y'] + r['h'] <= 0 or r['h'] <= 0:
            continue
        if top is not None and r['y'] + r['h'] > top + 0.5 and r['y'] < h:
            under.append(k)
        bottom = min(r['y'] + r['h'], h)
        if low is None or bottom > low[1]:
            low = (k, bottom)
    return dict(bar=top, under=under, wide=wide, low=low, n=len(nodes), w=w, h=h)


def main():
    out = sys.argv[1]
    scenes = sorted({s[:-5] if s.endswith('-dark') else s for m in MODELS if os.path.isdir(os.path.join(out, m))
                     for s in os.listdir(os.path.join(out, m)) if not s.startswith('_')} )
    print('| сцена | модель | окно | панель сверху | узлов | нижний узел (низ) | зазор | под панелью | шире окна |')
    print('|---|---|---|---|---|---|---|---|---|')
    for sc in scenes:
        for m in MODELS:
            d = load(out, m, sc + '-dark')
            if not d:
                print(f'| {sc} | {m} | | нет рамок | | | | | |')
                continue
            x = metrics(d)
            floor = x['bar'] if x['bar'] is not None else x['h']
            low = x['low']
            gap = f'{floor - low[1]:.0f}' if low else '-'
            print(f"| {sc} | {m} | {x['w']:.0f}×{x['h']:.0f} | {('%.0f' % x['bar']) if x['bar'] is not None else '-'} | {x['n']} | "
                  f"{(low[0] + ' ' + format(low[1], '.0f')) if low else '-'} | {gap} | {', '.join(x['under'][:4]) or '-'}"
                  f"{'…' if len(x['under']) > 4 else ''} | {', '.join(x['wide'][:3]) or '-'} |")
    if '--sheets' in sys.argv:
        from PIL import Image, ImageDraw
        os.makedirs(os.path.join(out, '_sheets'), exist_ok=True)
        for sc in scenes:
            ims = []
            for m in MODELS:
                p = os.path.join(out, m, sc + '-dark', 'native.png')
                if os.path.exists(p):
                    ims.append((m, Image.open(p).convert('RGB')))
            if not ims:
                continue
            # масштаб по точкам: 1 pt = 0,8 px, чтобы модели были в одном масштабе
            tiles = []
            for m, im in ims:
                pw, ph = SIZE[m]
                tiles.append((m, im.resize((int(pw * 0.8), int(ph * 0.8)))))
            Hs = max(t.height for _, t in tiles)
            sheet = Image.new('RGB', (sum(t.width for _, t in tiles) + 8 * len(tiles), Hs + 14), (90, 90, 90))
            x0 = 0
            dr = ImageDraw.Draw(sheet)
            for m, t in tiles:
                sheet.paste(t, (x0, 14)); dr.text((x0 + 2, 1), m, fill=(255, 255, 255)); x0 += t.width + 8
            sheet.save(os.path.join(out, '_sheets', sc + '.png'))


main()
