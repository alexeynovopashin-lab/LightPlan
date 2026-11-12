import sys,json,os,glob
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from m2 import *
base=sys.argv[1]; pat=sys.argv[2] if len(sys.argv)>2 else 'light-*'
for d in sorted(glob.glob(f'{base}/{pat}')):
    if not os.path.exists(d+'/native.png'): continue
    img=load(d+'/native.png'); n=json.load(open(d+'/native.json'))['nodes']; g=lambda k: node(n,k)
    rows=[]
    page=fill(img,4,300,8,40)
    for k,lab in [('readout.time','время на куполе'),('readout.phase','фаза на куполе'),('readout.sense','смысл фазы'),('header.sub','шапка: область'),('header.date','шапка: дата'),('next.label','«до золотого часа»'),('next.value','отсчёт'),('tele.light','строка «Свет»'),('wx.cond','погода: слово')]:
        r=g(k)
        if r: rows.append(text(img,r,label=lab))
    a=g('action')
    if a:
        x,y,w,h=a; f=fill(img,x+60,y+8,w-120,h-16); gr=fill(img,x+w/2-20,y+h+8,40,6)
        left=fill(img,max(0,x-14),y+h/2-6,10,12)
        sd=shadow_depth(img,a,gr)
        rows.append(dict(what='кнопка «Запланировать» / фон под ней',fill=hexs(f),ground=hexs(gr),cr=round(cr(f,gr),3),dL=round(Lstar(f)-Lstar(gr),1),shadow=hexs(sd),left_of_button=hexs(left),left_cr=round(cr(left,page),3)))
    dm=g('dome')
    if dm:
        x,y,w,h=dm; sky=fill(img,x+w/2-30,y+h*0.55,60,10)
        rows.append(dict(what='небо купола (середина) / страница',fill=hexs(sky),ground=hexs(page),cr=round(cr(sky,page),2)))
    t=g('timebar')
    if t:
        x,y,w,h=t; f=fill(img,x+40,y+4,w-80,8); rows.append(dict(what='таймбар / страница',fill=hexs(f),ground=hexs(page),cr=round(cr(f,page),3)))
    tb=g('tabbar')
    if tb:
        x,y,w,h=tb; f=fill(img,x+100,y+h-14,60,8); rows.append(dict(what='панель вкладок / страница',fill=hexs(f),ground=hexs(page),cr=round(cr(f,page),3)))
        rows.append(text(img,g('tab.map.label'),label='подпись невыбранной вкладки'))
    print('##',os.path.basename(d),'page',hexs(page))
    for o in rows: print('  ',json.dumps(o,ensure_ascii=False))
