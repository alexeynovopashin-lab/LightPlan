#!/usr/bin/env python3
"""Кадры слоя «Млечный Путь» из Gaia (шаг 29.8в.19) в симуляторе: ночь, город, сумерки, день, «Как в тёмном месте»,
вид на ядро, Лебедь, Южный Крест. Сцены и запуск — `Tools/ar_milkyway.py` (его `launch()`), камера синтетическая.

    python3 Tools/mw_gaia_frames.py OUT [имя,имя@подложка,...] [--sim <udid>] [--width 440] [--extra "<аргументы запуска>"]

Без списка — все восемь. `--sim` — другой симулятор (SE 3), по умолчанию симулятор ветки. Рядом с полным снимком
`<имя>/native.png` пишется уменьшенный `<имя>.jpg`; строка на кадр: видимость, причина, источник, звёзды, мс CPU/GPU.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ar_milkyway as A  # noqa: E402
from PIL import Image  # noqa: E402

SOCHI = A.SOCHI
TOMSK = (56.4977, 84.9744, 'Asia/Tomsk')
SYDNEY = (-33.87, 151.21, 'Australia/Sydney')
DARK = ['-lightplan.native.sunar.milkyWayDark', 'YES']
SCENES = {
    # имя: место, момент (UTC), наводка (l, b) или 'best', крен, дополнительно
    'night':  (SOCHI, '2026-08-15T19:30:00Z', (0, 0), 0, {'backdrop': 'night'}),
    'city':   (SOCHI, '2026-08-15T19:30:00Z', (0, 0), 0, {'glow': 12, 'backdrop': 'night'}),
    'dusk':   (SOCHI, '2026-08-15T17:55:00Z', (0, 0), 0, {'backdrop': 'night'}),
    'day':    (SOCHI, '2026-08-15T14:27:00Z', 'best', 0, {'backdrop': 'sky'}),
    'dark':   (SOCHI, '2026-08-15T14:27:00Z', 'best', 0, {'backdrop': 'sky', 'args': DARK}),
    'core':   (SYDNEY, '2026-06-15T12:00:00Z', (0, 0), 0, {'backdrop': 'black'}),
    'cygnus': (TOMSK, '2026-09-10T15:00:00Z', (80, 0), 0, {'backdrop': 'black'}),
    'crux':   (SYDNEY, '2026-04-15T12:00:00Z', (303, 0), 0, {'backdrop': 'black'}),
}


def main():
    out = sys.argv[1]
    names = sys.argv[2].split(',') if len(sys.argv) > 2 and not sys.argv[2].startswith('--') else list(SCENES)
    A.OUT = out
    sim = A.arg('--sim') or A.udid()
    width = int(A.arg('--width', '440'))
    extra_args = (A.arg('--extra') or '').split()
    os.makedirs(out, exist_ok=True)
    for spec in names:
        name, _, bd = spec.partition('@')
        place, moment, aim, roll, ex = SCENES[name]
        ex = dict(ex)
        if bd:
            ex['backdrop'] = bd
        ex['args'] = list(ex.get('args', [])) + extra_args
        tag = name + ('@' + bd if bd else '')
        nodes, png, pose = A.launch(sim, tag, place, moment, aim, roll, None, None, ex)
        t = nodes.get('ar.milkyWay', {}).get('text', '')
        i = t.find(' m=')
        print(tag, (t[:i] if i > 0 else t[:200]).strip(), t[t.find(' src='):].strip() if ' src=' in t else '',
              'pose=%.1f,%.1f' % pose, flush=True)
        img = Image.open(png).convert('RGB')
        img.resize((width, round(img.height * width / img.width))).save(os.path.join(out, tag + '.jpg'), quality=85)


if __name__ == '__main__':
    main()
