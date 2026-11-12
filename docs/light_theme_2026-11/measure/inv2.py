import re,os,sys,json,math,collections
ROOT='.'
UI='Packages/LightPlanUI/Sources/LightPlanUI'
SRC=[UI,'Packages/LightPlanUI/Sources/LightPlanMapCanvas','LightPlanWidget','Packages/LightPlanCore/Sources','Packages/LightPlanDomain/Sources','App-iOS']
pal=open(UI+'/Theme/Palette.swift').read()
tok={}
for m in re.finditer(r'public var (\w+): Color \{ dark \? Color\(hex: 0x(\w{6})(?:, alpha: ([\d.]+))?\) : Color\(hex: 0x(\w{6})(?:, alpha: ([\d.]+))?\) \}',pal):
    tok[m[1]]=(m[2].upper(),float(m[3] or 1),m[4].upper(),float(m[5] or 1))
def lin(c):
    c/=255; return c/12.92 if c<=0.04045 else ((c+0.055)/1.055)**2.4
def rgb(h): return tuple(int(h[i:i+2],16) for i in (0,2,4))
def L(h): r,g,b=[lin(x) for x in rgb(h)]; return 0.2126*r+0.7152*g+0.0722*b
def cr(a,b): la,lb=L(a),L(b); return (max(la,lb)+0.05)/(min(la,lb)+0.05)
def lab(h):
    r,g,b=[lin(x) for x in rgb(h)]
    X=(0.4124*r+0.3576*g+0.1805*b)/0.95047; Y=0.2126*r+0.7152*g+0.0722*b; Z=(0.0193*r+0.1192*g+0.9505*b)/1.08883
    f=lambda t: t**(1/3) if t>0.008856 else 7.787*t+16/116
    return 116*f(Y)-16, 500*(f(X)-f(Y)), 200*(f(Y)-f(Z))
def chroma(h): _,a,b=lab(h); return math.hypot(a,b)
def de2000(h1,h2):
    L1,a1,b1=lab(h1);L2,a2,b2=lab(h2)
    C1=math.hypot(a1,b1);C2=math.hypot(a2,b2);Cb=(C1+C2)/2
    G=0.5*(1-math.sqrt(Cb**7/(Cb**7+25**7)))
    a1p,a2p=(1+G)*a1,(1+G)*a2;C1p,C2p=math.hypot(a1p,b1),math.hypot(a2p,b2)
    h1p=math.degrees(math.atan2(b1,a1p))%360;h2p=math.degrees(math.atan2(b2,a2p))%360
    dL=L2-L1;dC=C2p-C1p
    dh=h2p-h1p
    if C1p*C2p==0: dh=0
    elif dh>180: dh-=360
    elif dh<-180: dh+=360
    dH=2*math.sqrt(C1p*C2p)*math.sin(math.radians(dh/2))
    Lb=(L1+L2)/2;Cbp=(C1p+C2p)/2
    if C1p*C2p==0: hb=h1p+h2p
    elif abs(h1p-h2p)>180: hb=(h1p+h2p+360)/2
    else: hb=(h1p+h2p)/2
    T=1-0.17*math.cos(math.radians(hb-30))+0.24*math.cos(math.radians(2*hb))+0.32*math.cos(math.radians(3*hb+6))-0.2*math.cos(math.radians(4*hb-63))
    Sl=1+0.015*(Lb-50)**2/math.sqrt(20+(Lb-50)**2);Sc=1+0.045*Cbp;Sh=1+0.015*Cbp*T
    Rt=-2*math.sqrt(Cbp**7/(Cbp**7+25**7))*math.sin(math.radians(60*math.exp(-((hb-275)/25)**2)))
    return math.sqrt((dL/Sl)**2+(dC/Sc)**2+(dH/Sh)**2+Rt*(dC/Sc)*(dH/Sh))
files=[]
for s in SRC:
    for dp,dn,fn in os.walk(s):
        if '.build' in dp: continue
        for f in fn:
            if f.endswith(('.swift','.metal')): files.append(os.path.join(dp,f))
def area(p):
    p=p.replace(UI+'/','')
    if p.startswith('Screens/'): return p.split('/')[1]
    if p.startswith('LightPlanWidget'): return 'Widget'
    if 'LightPlanCore' in p or 'LightPlanDomain' in p: return 'Core'
    return p.split('/')[0]
text={f:open(f,encoding='utf-8').read() for f in files}
# token uses
uses=collections.defaultdict(lambda: collections.Counter())
for f,t in text.items():
    if f.endswith('/Theme/Palette.swift'): continue
    for m in re.finditer(r'(?:\bpal|\bpalette|\bPalette\([^()]*\)|\bink|\bbrass|\bmoon|\bp)\.(\w+)\b',t):
        if m[1] in tok: uses[m[1]][area(f)]+=1
res={'tokens':{},'inline':[],'near':[]}
for n,(d,da,l,la) in tok.items():
    res['tokens'][n]=dict(dark=d,da=da,light=l,la=la,chroma=round(max(chroma(d),chroma(l)),1),
        uses=dict(uses[n]),total=sum(uses[n].values()),
        cW=round(cr(l,'FFFFFF'),2),cP=round(cr(l,'FAF8F3'),2),cB=round(cr(l,'EDE9E1'),2),cD=round(cr(d,'17150F'),2))
# inline literals
for f,t in text.items():
    if f.endswith('/Theme/Palette.swift'): continue
    for i,line in enumerate(t.split('\n'),1):
        for m in re.finditer(r'0x([0-9A-Fa-f]{6})\b',line):
            res['inline'].append(dict(f=f.replace(UI+'/',''),line=i,hex=m[1].upper(),src=line.strip()[:150]))
        for m in re.finditer(r'(?:SkyColor|RGB|Rgb)\((\d+), ?(\d+), ?(\d+)\)',line):
            h='%02X%02X%02X'%tuple(int(x) for x in m.groups())
            res['inline'].append(dict(f=f.replace(UI+'/',''),line=i,hex=h,src=line.strip()[:150]))
        for m in re.finditer(r'Color\((?:\.sRGB, )?red: ?([\d.]+), green: ?([\d.]+), blue: ?([\d.]+)',line):
            h='%02X%02X%02X'%tuple(round(float(x)*255) for x in m.groups())
            res['inline'].append(dict(f=f.replace(UI+'/',''),line=i,hex=h,src=line.strip()[:150]))
        for m in re.finditer(r'(?:Color\.|\(\.|: \.)(orange|red|green|yellow|blue|mint|cyan|teal|pink|purple|indigo)\b',line):
            res['inline'].append(dict(f=f.replace(UI+'/',''),line=i,hex='sys:'+m[1],src=line.strip()[:150]))
json.dump(res,open(sys.argv[1],'w'),ensure_ascii=False,indent=0)
print(len(tok),'tokens',len(res['inline']),'inline')
