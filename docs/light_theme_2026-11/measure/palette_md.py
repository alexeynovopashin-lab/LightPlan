"""Таблица «Палитра сейчас» из pal_rows.json (pal_table.py). Жирное — знак/текст ниже 3:1, курсив — ниже 4,5:1."""
import json,collections,os,sys
rows=json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'pal_rows.json')))
g=collections.OrderedDict()
for r in rows: g.setdefault(r['g'],[]).append(r)
for k,v in g.items():
    print(f'\n**{k}**\n')
    print('| цвет | тёмная | светлая | где: мест по коду | что значит для фотографа | тёмная на листе `#17150F` | светлая на белом / на бумаге |')
    print('|---|---|---|---|---|---|---|')
    for r in v:
        def mk(x):
            x=float(x); s=f'{x:.2f}'.replace('.',',')
            return f'**{s}**' if r['k']=='t' and x<3 else (f'*{s}*' if r['k']=='t' and x<4.5 else s)
        same=' (общий)' if r['d']==r['l'] else ''
        print(f"| {r['n']} | `#{r['d']}` | `#{r['l']}`{same} | {r['w']} | {r['m']} | {mk(r['cd'])} | {mk(r['cw'])} / {mk(r['cp'])} |")
