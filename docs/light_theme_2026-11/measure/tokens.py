import re,sys,json,colorsys
web=open(sys.argv[1],encoding='utf-8').read().split('\n')
def block(start):
    out={};i=start
    while '}' not in web[i]:
        for m in re.finditer(r'--([a-z0-9-]+)\s*:\s*([^;]+);',web[i]): out[m.group(1)]=m.group(2).strip()
        i+=1
    return out
root=block(1308); light=block(1388)
def parse(v):
    v=v.strip().lower()
    m=re.match(r'#([0-9a-f]{6})$',v)
    if m: h=int(m.group(1),16); return ((h>>16)&255,(h>>8)&255,h&255,1.0)
    m=re.match(r'rgba?\(([^)]*)\)',v)
    if m:
        p=[float(x) for x in re.split(r'[ ,/]+',m.group(1).strip()) if x]
        return (p[0],p[1],p[2],p[3] if len(p)>3 else 1.0)
    return None
pal=open(sys.argv[2],encoding='utf-8').read()
nat={}
for m in re.finditer(r'public var (\w+): Color \{ dark \? Color\(hex: 0x([0-9A-F]{6})(?:, alpha: ([0-9.]+))?\) : Color\(hex: 0x([0-9A-F]{6})(?:, alpha: ([0-9.]+))?\) \}',pal):
    n,dh,da,lh,la=m.groups()
    f=lambda h,a:(int(h[:2],16),int(h[2:4],16),int(h[4:],16),float(a) if a else 1.0)
    nat[n]=(f(dh,da),f(lh,la))
def camel(k): 
    p=k.split('-'); return p[0]+''.join(x[:1].upper()+x[1:] for x in p[1:])
def lin(c): c/=255; return c/12.92 if c<=0.04045 else ((c+0.055)/1.055)**2.4
def Y(rgb): return 0.2126*lin(rgb[0])+0.7152*lin(rgb[1])+0.0722*lin(rgb[2])
def Lstar(rgb):
    y=Y(rgb); return 116*(y**(1/3) if y>0.008856 else (7.787*y+16/116))-16
def hue(rgb):
    h,l,s=colorsys.rgb_to_hls(*[x/255 for x in rgb]); return h*360,s
rows=[]
for k,dv in root.items():
    n=camel(k); d=parse(dv); l=parse(light.get(k,dv)) if k in light else d
    if d is None: continue
    shared = k not in light or parse(light[k])==d
    if shared: how='shared'
    elif d[3]<1 or l[3]<1:
        dw=Y(d[:3])>0.5; lw=Y(l[:3])>0.5
        if dw and lw: how='same-sign (white both)'
        elif not dw and not lw: how='same-sign (dark both)'
        elif dw and not lw: how='SIGN FLIP white->dark'
        else: how='SIGN FLIP dark->white'
    else:
        Ld,Ll=Lstar(d[:3]),Lstar(l[:3])
        how='mirror L* (%.0f→%.0f)'%(Ld,Ll) if abs((100-Ld)-Ll)<=8 else 'separate L* (%.0f→%.0f)'%(Ld,Ll)
    nv=nat.get(n); drift=''
    if nv:
        if nv[0][:3]!=tuple(int(x) for x in d[:3]) or abs(nv[0][3]-d[3])>0.001 or nv[1][:3]!=tuple(int(x) for x in l[:3]) or abs(nv[1][3]-l[3])>0.001: drift='DRIFT'
    else: drift='not in native'
    rows.append((k,n,dv,light.get(k,'='),how,drift))
for r in rows: print(' | '.join(r))
print('native-only:',[n for n in nat if n not in [camel(k) for k in root]])
