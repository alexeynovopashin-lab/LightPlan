import sys,json,os
sys.path.insert(0,os.path.dirname(__file__))
from meas import *
def node(n,k): v=n.get(k); return (v['x'],v['y'],v['w'],v['h']) if v else None
def shadow_depth(img,r,ground,side='bottom'):
    """darkest band luminance 0..10pt outside the plate edge vs ground: ratio and ΔL*"""
    x,y,w,h=r; best=None
    for d in range(1,31):
        yy = y+h+d/3 if side=='bottom' else y-d/3
        c=crop(img,x+w*0.3,yy,w*0.4,1/3)
        if not c.size: continue
        m=tuple(int(v) for v in np.median(c.reshape(-1,3),axis=0))
        if best is None or Y(m)<Y(best): best=m
    return best
def plate(img,r,inset=4,label=''):
    x,y,w,h=r
    f=fill(img,x+inset,y+inset,w-2*inset,h-2*inset)
    g=ring(img,x,y,w,h,gap=12,width=6)
    sd=shadow_depth(img,r,g)
    return dict(what=label,fill=hexs(f),ground=hexs(g),cr=round(cr(f,g),3),dL=round(Lstar(f)-Lstar(g),1),
                shadow=hexs(sd),shadow_cr=round(cr(sd,g),3),shadow_dL=round(Lstar(sd)-Lstar(g),1))
def text(img,r,bg=None,label='',pct=0.5):
    x,y,w,h=r
    b=bg or fill(img,x,y,w,h)
    i=ink(img,x,y,w,h,b,pct)
    return dict(what=label,ink=hexs(i),bg=hexs(b),cr=round(cr(i,b),2))
