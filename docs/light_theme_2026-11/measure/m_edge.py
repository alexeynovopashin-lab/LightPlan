"""Как плашка отделена от подложки: заливка (ΔL* середины к подложке), кант (самая светлая / тёмная линия ≤ 1,5 pt у края
против середины и подложки), тень (самая тёмная полоса ≤ 10 pt под нижним краем). Профиль — медиана по средним 40 % края, шаг 1/3 pt."""
import sys,os,json
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from m2 import *
B=sys.argv[1]
P=[('shots/planner-month-TH','подложка месяца',(20,155,400,298),'top'),
   ('shots/planner-week-TH','строка недели со съёмкой',(84,437,320,93),'top'),
   ('shots3/clients-all-TH','строка клиента',(24,174,392,64),'top'),
   ('shots2/m28-orgs-TH','строка организации',(24,123,391,61),'top'),
   ('shots2/m28-orgcard-TH','поле карточки организации',(24,161,392,48),'top'),
   ('shots2/m28-mbfolder-TH','плитка кадра мудборда',(37,293,176,174),'top'),
   ('shots2/settings-simple-TH','сегмент режима',(24,112,392,45),'top'),
   ('shots2/card-people-during-TH','лист карточки',(24,150,392,917),'left'),
   ('shots2/card-people-during-TH','плитка даты в карточке',(36,456,368,102),'top'),
   ('shots2/card-people-during-TH','плитка места в карточке',(36,638,368,78),'top'),
   ('shots3f/planner-form-portrait-TH','блок «Где снимаем» в форме',(24,962,392,128),'top'),
   ('shots3f/planner-form-portrait-TH','блок оплаты в форме',(24,1567,392,334),'top'),
   ('shots2/map-simple-TH-day-route','лист маршрута на карте',(17,691,403,176),'top'),
]
def _L(c): return Lstar(tuple(int(v) for v in np.median(c.reshape(-1,3),axis=0)))
def rowL(img,x,y,w):
    py=int(round(y*3)); return _L(img[py:py+1,int((x+w*0.3)*3):int((x+w*0.7)*3),:3])
def colL(img,x,y,h):
    px=int(round(x*3)); return _L(img[int((y+h*0.3)*3):int((y+h*0.7)*3),px:px+1,:3])
for d,lab,r,side in P:
    for th in ['dark','light']:
        p=os.path.join(B,d.replace('TH',th),'native.png')
        if not os.path.exists(p): print('нет',p); continue
        img=load(p); x,y,w,h=r
        if (y+h+12)*3>img.shape[0]: print('за кадром',lab,th); continue
        if side=='top':
            prof=[rowL(img,x,y+k/3,w) for k in range(-12,13)]   # −4 … +4 pt
            inner=rowL(img,x,y+min(h/2,14),w); outer=rowL(img,x,y-6,w)
        else:
            prof=[colL(img,x+k/3,y,h) for k in range(-12,13)]
            inner=colL(img,x+14,y,h); outer=colL(img,x-6,y,h)
        near=prof[7:17]  # −1.67 … +1.33 pt
        hi=max(near); lo=min(near)
        light_edge=hi-max(inner,outer); dark_edge=min(inner,outer)-lo
        g=fill(img,x+w*0.3,y-7,w*0.4,2) if side=='top' else fill(img,x-6,y+h/2,3,10)
        sd=shadow_depth(img,r,g); sdl=Lstar(sd)-Lstar(g)
        kind=[]
        if abs(inner-outer)>=1: kind.append(f'заливка {inner-outer:+.1f}')
        if light_edge>=1.5: kind.append(f'светлый кант +{light_edge:.1f}')
        if dark_edge>=1.5: kind.append(f'тёмный кант −{dark_edge:.1f}')
        if sdl<=-1.5: kind.append(f'тень {sdl:.1f}')
        print(json.dumps(dict(what=lab,theme=th,plate=round(inner,1),page=round(outer,1),fill_dL=round(inner-outer,1),
            light_edge=round(light_edge,1),dark_edge=round(dark_edge,1),shadow_dL=round(sdl,1),
            verdict=' + '.join(kind) or 'не отделена'),ensure_ascii=False))
