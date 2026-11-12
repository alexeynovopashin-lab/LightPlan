"""Contrast measurement helpers over a screenshot (3x). Usage as module."""
import numpy as np
from PIL import Image
SC=3
def load(p): return np.asarray(Image.open(p).convert('RGB')).astype(np.int32)
def lin(c):
    c=c/255.0; return np.where(c<=0.04045,c/12.92,((c+0.055)/1.055)**2.4)
def Y(rgb):
    rgb=np.asarray(rgb,dtype=float); l=lin(rgb); return 0.2126*l[...,0]+0.7152*l[...,1]+0.0722*l[...,2]
def cr(a,b):
    ya,yb=float(Y(a)),float(Y(b)); hi,lo=max(ya,yb),min(ya,yb); return (hi+0.05)/(lo+0.05)
def Lstar(rgb):
    y=float(Y(rgb)); return 116*(y**(1/3) if y>0.008856 else 7.787*y+16/116)-16
def crop(img,x,y,w,h):  # pt
    H,W,_=img.shape; x0,y0=max(0,int(x*SC)),max(0,int(y*SC)); x1,y1=min(W,int((x+w)*SC)),min(H,int((y+h)*SC))
    return img[y0:y1,x0:x1]
def mode(px):
    px=px.reshape(-1,3); q=(px//4)
    keys=q[:,0]*4096+q[:,1]*64+q[:,2]; vals,cnt=np.unique(keys,return_counts=True); k=vals[cnt.argmax()]
    sel=px[keys==k]; return tuple(int(v) for v in np.median(sel,axis=0))
def fill(img,x,y,w,h): return mode(crop(img,x,y,w,h))
def ring(img,x,y,w,h,gap=3,width=6):
    parts=[crop(img,x-gap-width,y,width,h),crop(img,x+w+gap,y,width,h),crop(img,x,y-gap-width,w,width),crop(img,x,y+h+gap,w,width)]
    parts=[p.reshape(-1,3) for p in parts if p.size]
    return mode(np.concatenate(parts)) if parts else None
def ink(img,x,y,w,h,bg=None,pct=1.0):
    """most contrasting glyph colour vs bg (percentile of contrast)."""
    px=crop(img,x,y,w,h).reshape(-1,3)
    if bg is None: bg=mode(px)
    yb=float(Y(bg)); ys=Y(px)
    if yb>0.3: idx=np.argsort(ys)[:max(1,int(len(ys)*pct/100))]
    else: idx=np.argsort(-ys)[:max(1,int(len(ys)*pct/100))]
    return tuple(int(v) for v in np.median(px[idx],axis=0))
def edge_profile(img,x,y,w,h,side='bottom',depth=12):
    """luminance (0-255 sRGB mean) line by line outward from a side, pt steps of 1/3."""
    out=[]
    for d in range(-depth,depth+1):
        if side=='bottom': r=crop(img,x+w*0.2,y+h+d/3,w*0.6,1/3)
        elif side=='top': r=crop(img,x+w*0.2,y-d/3,w*0.6,1/3)
        if r.size: out.append(int(r.reshape(-1,3).mean()))
    return out
def hexs(c): return '#%02X%02X%02X'%tuple(c)
