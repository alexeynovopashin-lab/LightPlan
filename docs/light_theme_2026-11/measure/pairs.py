import re
pal=open('Packages/LightPlanUI/Sources/LightPlanUI/Theme/Palette.swift').read()
nat={}
for m in re.finditer(r'public var (\w+): Color \{ dark \? Color\(hex: 0x([0-9A-F]{6})(?:, alpha: ([0-9.]+))?\) : Color\(hex: 0x([0-9A-F]{6})(?:, alpha: ([0-9.]+))?\) \}',pal):
    n,dh,da,lh,la=m.groups(); f=lambda h,a:(int(h[:2],16),int(h[2:4],16),int(h[4:],16),float(a) if a else 1.0)
    nat[n]=(f(dh,da),f(lh,la))
def lin(c): c/=255; return c/12.92 if c<=0.04045 else ((c+0.055)/1.055)**2.4
def Y(c): return 0.2126*lin(c[0])+0.7152*lin(c[1])+0.0722*lin(c[2])
def over(fg,bg): a=fg[3]; return tuple(fg[i]*a+bg[i]*(1-a) for i in range(3))+(1.0,)
def cr(a,b): y1,y2=sorted([Y(a),Y(b)]); return (y2+0.05)/(y1+0.05)
def get(n,t):
    return nat[n][0 if t=='d' else 1]
grounds=['bg','surface','sheet','sheet2']
plates=['surface','sheet','sheet2','sheet3','sheet4','peek1','peek2','field','fieldPress','press','press2','segOn','badgeBg','warnBg','badBg','hatch','rail','overlay3','bar','bar2','fillA','fillB','overlay','sheetGlass','mapGlass','glassFill']
print('plate | on | dark | light')
for g in grounds:
  for p in plates:
    if p==g: continue
    r=[]
    for t in 'dl':
      bg=get(g,t); fg=get(p,t); c=over(fg,bg) if fg[3]<1 else fg
      r.append(cr(c,bg))
    print(f'{p} | {g} | {r[0]:.2f} | {r[1]:.2f}')
print('\ntext | on | dark | light')
for g in ['bg','surface','sheet','sheet2','field','press','warnBg','badBg']:
  for p in ['ink','ink2','ink3','ink4','ink5','ink6','ink7','ink8','brass','brassSoft','brassDeep','glyph','terra','terra2','badInk','warnInk','green','blue','toneGood']:
    r=[cr(get(p,t),get(g,t) if get(g,t)[3]==1 else over(get(g,t),get('bg',t))) for t in 'dl']
    print(f'{p} | {g} | {r[0]:.2f} | {r[1]:.2f}')
print('\nlines | on | dark | light')
for g in ['bg','surface','sheet','field']:
  for p in ['hair','hair2','hair3','hair4','hair5','hairline','edge','rail','rail5','stackEdge','inkA12','inkA22']:
    r=[]
    for t in 'dl':
      bg=get(g,t); fg=get(p,t); c=over(fg,bg) if fg[3]<1 else fg; r.append(cr(c,bg))
    print(f'{p} | {g} | {r[0]:.2f} | {r[1]:.2f}')
