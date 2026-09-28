# -*- coding: utf-8 -*-
"""岩石墙体 sheet v3：轻校色（保纹理）
逐块亮度归一到目标 → 轻度压对比 → 轻度去饱和 → 量化 10 色。
不做三色重映射，保留 AI 原图块面裂纹质感。
"""
import numpy as np
from PIL import Image

SRC = "tmp/rock_wall2_16c.png"
OUT = "assets/tiles/rock_wall_sheet.png"
FLOOR = "assets/tiles/floor_bricks_sheet.png"
N, TILE = 6, 80
CONTRAST = 0.85   # 对比压缩系数（1=不压）
DESAT = 0.15      # 去饱和
NCOLORS = 10      # 最终量化色数

def lum(c):
    return 0.299*c[...,0] + 0.587*c[...,1] + 0.114*c[...,2]

floor = np.array(Image.open(FLOOR).convert("RGB")).astype(float)
floor_lum = lum(floor).mean()
fmx, fmn = floor.max(axis=2), floor.min(axis=2)
floor_sat = ((fmx - fmn) / np.maximum(fmx, 1)).mean()

src = np.array(Image.open(SRC).convert("RGB")).astype(float)
H, W, _ = src.shape
crop_w, crop_h = int(W*0.82), int(H*0.88)
bw, bh = crop_w // N, crop_h // N
target = floor_lum * 0.77

blocks = []
for r in range(N):
    for c in range(N):
        b = src[r*bh:(r+1)*bh, c*bw:(c+1)*bw].copy()
        m = lum(b).mean()
        b = np.clip(b * (target / max(m, 1)), 0, 255)          # 逐块亮度归一
        g = lum(b)[..., None]                                   # 压对比+去饱和
        b = target + (b - target) * CONTRAST
        g2 = (0.299*b[...,0:1] + 0.587*b[...,1:2] + 0.114*b[...,2:3])
        b = b * (1-DESAT) + g2 * DESAT
        im = Image.fromarray(np.clip(b,0,255).astype(np.uint8))
        im = im.resize((TILE, TILE), Image.NEAREST).quantize(colors=NCOLORS, method=Image.MEDIANCUT).convert("RGB")
        blocks.append(np.array(im).astype(float))

sheet = np.zeros((N*TILE, N*TILE, 3))
for i, b in enumerate(blocks):
    r, c = divmod(i, N)
    sheet[r*TILE:(r+1)*TILE, c*TILE:(c+1)*TILE] = b
Image.fromarray(sheet.astype(np.uint8)).save(OUT)

# ---- 验收 ----
bl = [lum(b) for b in blocks]
means = np.array([b.mean() for b in bl])
allb = np.stack(bl)
sats = [((b.max(axis=2)-b.min(axis=2))/np.maximum(b.max(axis=2),1)).mean() for b in blocks]
stds = allb.std(axis=(1,2)) / means
print("=== 验收（要求 → 实测） ===")
print(f"[1] 亮度比:      70-85% → {allb.mean()/floor_lum*100:.1f}%")
print(f"[2] 亮面占比(>105): <20% → {(allb>105).mean()*100:.1f}%")
print(f"[3] 饱和度比:    ≤70% → {np.mean(sats)/floor_sat*100:.0f}%")
print(f"[4] 变体明度极差: ≤5% → {(means.max()-means.min())/means.mean()*100:.1f}%")
print(f"[5] 块内对比(std/mean): 参考≤12% → 平均 {stds.mean()*100:.1f}%")

# 平铺预览
import random
random.seed(7)
canvas = Image.new("RGB", (8*TILE, 8*TILE))
for r in range(8):
    for c in range(8):
        x, y = random.randrange(N)*TILE, random.randrange(N)*TILE
        canvas.paste(Image.fromarray(sheet.astype(np.uint8)[y:y+TILE, x:x+TILE]), (c*TILE, r*TILE))
canvas.resize((8*TILE*2, 8*TILE*2), Image.NEAREST).save("tmp/rock_tiled_v3.png")
print("saved OUT + tmp/rock_tiled_v3.png")
