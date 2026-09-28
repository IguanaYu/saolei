# -*- coding: utf-8 -*-
"""岩石墙体 sheet 最终版（方案F）：第一张AI大块面图 + 逐块亮度归一 + 分位阈值4档cel映射
分布：缝8% / 暗12% / 主体60% / 受光19%；色阶=规格三色+深缝档，各向灰偏20%。
产物 assets/tiles/rock_wall_sheet.png（6x6 x 80px）。验收见 print。"""
import numpy as np, random
from PIL import Image
def lum(c): return 0.299*c[...,0]+0.587*c[...,1]+0.114*c[...,2]
floor = np.array(Image.open("assets/tiles/floor_bricks_sheet.png").convert("RGB")).astype(float)
floor_lum = lum(floor).mean()
src = np.array(Image.open("tmp/rock_wall_raw.png").convert("RGB")).astype(float)
H,W,_ = src.shape
N=6; TILE=80
crop_w, crop_h = int(W*0.82), int(H*0.88)
bw, bh = crop_w//N, crop_h//N
target = floor_lum*0.77
def mix(c,w):
    g=0.299*c[0]+0.587*c[1]+0.114*c[2]; return c*(1-w)+g*w
P0=mix(np.array([30,24,18],float),0.2)
P1=mix(np.array([74,56,38],float),0.2)
P2=mix(np.array([107,81,56],float),0.2); P2 = P2 + (mix(np.array([138,106,74],float),0.2)-P2)*0.30
P3=mix(np.array([138,106,74],float),0.2)
pal = np.stack([P0,P1,P2,P3])
blocks=[]
for r in range(N):
    for c in range(N):
        b = src[r*bh:(r+1)*bh, c*bw:(c+1)*bw].copy()
        m = lum(b).mean()
        b = np.clip(b*(target/max(m,1)),0,255)
        L = lum(b)
        t1,t2,t3 = np.percentile(L,[8,20,81])
        idx=np.zeros(L.shape,dtype=int)
        idx[L>=t1]=1; idx[L>=t2]=2; idx[L>=t3]=3
        im = Image.fromarray(pal[idx].astype(np.uint8)).resize((TILE,TILE), Image.NEAREST)
        blocks.append(np.array(im).astype(float))
sheet=np.zeros((N*TILE,N*TILE,3))
for i,b in enumerate(blocks):
    r,c=divmod(i,N); sheet[r*TILE:(r+1)*TILE,c*TILE:(c+1)*TILE]=b
Image.fromarray(sheet.astype(np.uint8)).save("assets/tiles/rock_wall_sheet.png")
bl=[lum(b) for b in blocks]; allb=np.stack(bl); means=np.array([b.mean() for b in bl])
sats=[((b.max(axis=2)-b.min(axis=2))/np.maximum(b.max(axis=2),1)).mean() for b in blocks]
fmx,fmn=floor.max(axis=2),floor.min(axis=2); fsat=((fmx-fmn)/np.maximum(fmx,1)).mean()
print("亮度比=%.1f%%(70-85) 极差=%.1f%%(≤5) 亮面=%.1f%%(<20) 饱和度比=%.0f%%(≤70)"%(
 allb.mean()/floor_lum*100,(means.max()-means.min())/means.mean()*100,(allb>105).mean()*100,np.mean(sats)/fsat*100))
