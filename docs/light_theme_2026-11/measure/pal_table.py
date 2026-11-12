import json,sys,itertools,os
sys.argv=[sys.argv[0],'/dev/null']
src=open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'inv2.py')).read().split('files=[]')[0]
exec(src)  # lin, rgb, L, cr, lab, chroma, de2000
inv=json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'inv2.json')))
T=inv['tokens']
def u(n): return T[n]['total']
def areas(n): 
    a=sorted(T[n]['uses'].items(),key=lambda x:-x[1]); return ', '.join(f'{k} {v}' for k,v in a[:4])+(' …' if len(a)>4 else '')
# (group, name, dark, light, where/uses, meaning)  light None = same in both / not themed
R=[]
def tk(g,n,m,k='t'): R.append((g,f'`{n}`',T[n]['dark'],T[n]['light'],f'{u(n)}: {areas(n)}' if u(n) else '0 (не используется)',m,k))
def il(g,n,d,l,w,m,k='t'): R.append((g,n,d,l,w,m,k))
G='Латунь — главный акцент'
tk(G,'brass','кнопки, выбранное, ссылки, «сейчас», золотой час, телефон')
tk(G,'brassSoft','мягкая латунь: «ясно» в прогнозе, вторичные отметки')
tk(G,'brassDeep','выходные (`weekend`), латунь на светлом там, где нужна читаемость')
tk(G,'glyph','знак в карточке: в тёмной = `brass`, в светлой = `brassDeep`')
tk(G,'brassDark','кант латунных кнопок, баннер')
il(G,'вписано `#E2A44C`: 17 мест + прибор карты 4 + `MapRouteViews:410`','E2A44C','E2A44C','Form 7, Planner 3, Map 6, мудборд','латунь тёмной темы, оставленная и в светлой')
il(G,'`WidgetStyle.amber` (виджеты старого вида)','E2A44C','9A5F0A','Widget','своя ступень латуни, третья рядом с `brassSoft`/`brassDeep`')
il(G,'`MapInstrument.sunInk` (прибор карты)','E2A44C','8A5A18','Map','копия `glyph` числами')
il(G,'AR `nowTone` (панель AR всегда тёмная)','D9AC6B','D9AC6B','SunAR','«сейчас» в AR = `brassSoft` тёмной')
G='Нажатое и выбранное (заливки)'
for n,m in [('pressBrass','нажатая латунная кнопка, выбранный чип'),('pressWarm','тёплая плашка-просьба («Разрешить уведомления»)'),('segOn','выбранный сегмент'),('press','нажатие, выбранный чип'),('field','поле ввода')]: tk(G,n,m,'f')
G='Терракота — плохо, удалить, просрочено'
for n,m,k in [('terra','плохой свет, «просрочено», конфликт времени','t'),('terra2','«Удалить»','t'),('badInk','текст плохой новости','t'),('badBg','фон плохой новости','f')]: tk(G,n,m,k)
il(G,'вписано `#B9603D` (= `terra2` тёмной)','B9603D','B9603D','Moodboard 3 в обеих темах; Org 3 только в тёмной','«Удалить»')
il(G,'`PlannerDay` «просрочено», свечение плохого (числами)','C9663D','8A3F22','Planner, Card, статистика','= `terra` тёмной / `badInk` светлой')
il(G,'`RibbonView:321` метка в тёмной прорези','D0704A','C9663D','лента «Свет», «Графит»/«Окно»','«сейчас» в тёмной прорези')
G='Янтарь — предупреждение'
tk(G,'warnInk','текст предупреждения (карточка)')
tk(G,'warnBg','фон предупреждения','f')
il(G,'свечение `WarnGlow` (числами 226,164,76)','E2A44C','E2A44C','Form, Card: 0,32 в тёмной / 0,55 в светлой','свечение — по принципу общее','g')
G='Зелёный — хорошо'
tk(G,'green','хороший свет, «сдана», ок')
tk(G,'toneGood','«хорошо» на «Свете»; в светлой = `ink4`, серый')
il(G,'вписано `#A8B49B` (`PlannerLook:44`, `PlannerMonthView:67,281`)','A8B49B','A8B49B','месяц «Съёмок»','`green` тёмной, оставленный и в светлой')
G='Синий — холодный свет, заметки'
tk(G,'blue','синий час, заметки и бриф в карточке, дождь')
il(G,'вписано `#7C9CC4` (`PlannerLook:46`, `PlannerMonthView:67`, `MapInstrument:254`)','7C9CC4','7C9CC4','месяц, прибор карты','`blue` тёмной в обеих темах')
il(G,'`MapInstrument.moonInk` (прибор карты)','CFD6DE','3F6088','Map','луна: в тёмной = `moonLit`, в светлой = `blue`')
G='Луна, звёзды, Млечный Путь'
for n,m in [('moon','луна на куполе и «Свете»'),('moonLit','освещённая часть луны'),('moonDark','тень на луне')]: tk(G,n,m)
il(G,'вписано `#C6AAE8` (`MapScreenView:629`, `MapInstrument:375`)','C6AAE8','C6AAE8','«Карта»','Млечный Путь, сиреневый')
for n,h,m in [('AR `moonTint`','C9D6EA','луна'),('AR `constellationTone`','8FB0E8','созвездия'),('AR `milkyWayTone`','DCE6FF','полоса Млечного Пути'),('AR `coreTone`','FFEBC2','ядро'),('AR `starTone`','FFF3D6','звёзды'),('AR `planetTone`','F0C987','планеты'),('AR `sunFill`','FFC24D','солнечный диск')]:
    il(G,n,h,h,'SunAR, на тёмном небе',m,'s')
G='Небо и закат (модель света — физика, не тема)'
for n,h,m in [('`LightPalette.silver`','EFEAE0','солнце выше 40°'),('`LightPalette.amber`','D9AC6B','день, солнце 6–20°'),('`LightPalette.gold`','E2A44C','золотой час'),('`LightPalette.scarlet`','D8502F','закат, солнце 0…−1,8°'),('`LightPalette.pink`','C9698F','−1,8…−4°'),('`LightPalette.blue`','5B77A0','синий час −4…−6°'),('`LightPalette.deep`','3D5878','сумерки −6…−12°'),('`LightPalette.night`','687EA8','ночь'),
    ('`SkyPalette` zenith','383E52','прогноз заката: холодный верх'),('`SkyPalette` high','D67C94','розовые перистые'),('`SkyPalette` mid','E2744A','алые средние облака'),('`SkyPalette` horizon','F7C476','тёплая полоса у горизонта'),('`SkyPalette` dead','5C5C60','«свинец», цвета не будет')]:
    il(G,n,h,h,'лента «Свет», купол, «Подробно»' if n.endswith('silver`') or n.endswith('zenith') else 'то же',m,'s')
il(G,'купол днём: верх (у светлой — своя лестница)','152E4E','CFE1EB','купол `DomeSky:144`','небо','s')
il(G,'купол днём: низ','2A4E74','EBF1F0','купол','небо','s')
il(G,'купол −6°: верх','101C31','6282AB','купол `DomeSky:141`','сумерки','s')
G='Карта'
il(G,'холст под прибором','14110E','E8E3DA','`MapScreenView:111` (светлая вписана)','земля без тайлов','f')
il(G,'тайлы: фон (128 цветов на тему, стиль CARTO)','15191C','FBF8F3','`style_dark/light.json`','земля','f')
il(G,'тайлы: вода','24343A','B0D0D6','то же','вода','f')
il(G,'тайлы: главные дороги','4F3F33','FBDB98','то же','дороги','f')
il(G,'прибор: подписи градусов (вписано)','A89C86','A89C86','`MapInstrument:331`','= `ink3b` тёмной (токен не используется)')
il(G,'прибор: буква «С» (вписано)','E2A44C','E2A44C','`MapInstrument:199`','север латунью тёмной темы; на холсте светлой мерено 1,70')
il(G,'прибор: буквы «В», «Ю», «З» (вписано)','8A8478','8A8478','`MapInstrument:199`, `MapScreenView:631`','= `ink4` тёмной в обеих темах')
G='Виджеты `BraunWidget` (своя палитра)'
for n,d,l,m,k in [('фон','161616','E4E4E2','плашка виджета','f'),('текст','ECECEA','111111','время, имя','t'),('янтарь','F4B400','111111','центр часов: в светлой — чёрный','t'),('флажок','C8102E','AD0A15','красная метка Braun','t')]:
    il(G,n,d,l,'Widget (контраст на своём фоне — § 6.5)',m,'s')
rows=[]
for g,n,d,l,w,m,k in R:
    lv=l
    def cc(h,bg): return f'{cr(h,bg):.2f}'
    rows.append(dict(g=g,n=n,d=d,l=lv,w=w,m=m,k=k,cd=cc(d,'17150F'),cw=cc(lv,'FFFFFF'),cp=cc(lv,'FAF8F3')))
json.dump(rows,open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'pal_rows.json'),'w'),ensure_ascii=False)
# near duplicates among all colour values (light theme & dark theme separately), chroma>8
vals=collections.OrderedDict() if False else {}
import collections
pool=collections.defaultdict(set)
for n,v in T.items():
    if max(chroma(v['dark']),chroma(v['light']))>8 and v['da']==1:
        pool['dark'].add((v['dark'],n)); pool['light'].add((v['light'],n))
extra=[('E2A44C','#E2A44C вписано'),('A8B49B','#A8B49B вписано'),('7C9CC4','#7C9CC4 вписано'),('B9603D','#B9603D вписано'),('9E4722','#9E4722 вписано'),
       ('9A5F0A','WidgetStyle.amber'),('D9AC6B','LightPalette.amber'),('D8502F','LightPalette.scarlet'),('C9663D','PlannerDay просрочено'),('8A3F22','PlannerDay просрочено, светлая'),
       ('E2744A','SkyPalette.mid'),('F7C476','SkyPalette.horizon'),('FFC24D','AR sunFill'),('F0C987','AR planetTone'),('C6AAE8','сиреневый карты'),('5B77A0','LightPalette.blue'),
       ('8FB0E8','AR созвездия'),('C9D6EA','AR луна'),('D0704A','RibbonView метка')]
allv=list(pool['dark']|pool['light'])+extra
seen=set(); out=[]
for (h1,n1),(h2,n2) in itertools.combinations(allv,2):
    if h1==h2 and n1.split()[0]==n2.split()[0]: continue
    if chroma(h1)<8 or chroma(h2)<8: continue
    e=de2000(h1,h2)
    if e<6:
        k=tuple(sorted([(h1,n1),(h2,n2)]))
        if k in seen: continue
        seen.add(k); out.append((round(e,1),h1,n1,h2,n2))
for o in sorted(out): print(o)
