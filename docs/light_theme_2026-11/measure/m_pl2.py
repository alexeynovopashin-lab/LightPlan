import sys,json,os
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from m2 import *
B=sys.argv[1]
def pr(th,lab,f,g,extra=''):
    print(f'  {lab}: {hexs(f)} на {hexs(g)} → {cr(f,g):.3f}:1, ΔL* {Lstar(f)-Lstar(g):+.1f} {extra}')
for th in ['dark','light']:
    print('##',th)
    img=load(f'{B}/planner-week-{th}/native.png'); n=json.load(open(f'{B}/planner-week-{th}/native.json'))['nodes']
    page=fill(img,430,150,8,20)
    x,y,w,h=node(n,'wk.0'); f=fill(img,90,y+12,40,10); pr(th,'неделя: «свободно»-плашка / фон',f,page)
    x,y,w,h=node(n,'wk.3'); f=fill(img,150,y+30,40,8); pr(th,'неделя: строка со съёмкой / фон',f,page)
    # shadow below wk.3 plate
    sd=shadow_depth(img,(84,y+8,320,h-16),page); pr(th,'неделя: тень под строкой (самое тёмное ≤10 pt ниже)',sd,page)
    print('  ',text(img,(90,node(n,'wk.0')[1]+10,80,14),label='«свободно»'))
    print('  ',text(img,(300,node(n,'wk.0')[1]+34,110,14),label='«золотой час 18:41»'))
    print('  ',text(img,(28,node(n,'wk.0')[1]+4,40,22),label='число 21 (будний)'))
    img=load(f'{B}/planner-day5-{th}/native.png'); n=json.load(open(f'{B}/planner-day5-{th}/native.json'))['nodes']
    page=fill(img,200,300,20,10)
    x,y,w,h=node(n,'ev.0'); f=fill(img,x+100,y+30,40,8); pr(th,'день: блок съёмки / лента',f,page)
    print('  ',text(img,(x+20,y+4,100,18),label='имя в блоке «Олег Дан»'))
    print('  ',text(img,(x+20,y+22,100,14),label='время в блоке'))
    print('  ',text(img,(20,n['slot.5']['y'] if 'slot.5' in n else 340,40,14),label='час на шкале'))
    x,y,w,h=node(n,'dd.5'); f=fill(img,x+w/2-6,y+h/2-14,12,10); pr(th,'выбранный день 26 (кружок) / фон',f,fill(img,x+2,y+2,4,4))
