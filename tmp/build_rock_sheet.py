# -*- coding: utf-8 -*-
"""岩石墙体 sheet v2：三色调色板重映射
每块按亮度分位映射到 暗缝/主体/受光 三色（规格 §1.1 色板），再整体去饱和，
保证：变体明度差≤5%、亮面<20%、饱和度≤地砖70%、亮度70-85%。
"""
import numpy as np
from PIL import Image

SRC = "tmp/rock_wall_16c.png"
OUT = "assets/tiles/rock_wall_sheet.png"
FLOOR = "assets/tiles/floor_bricks_sheet.png"
N, TILE = 6, 80          # 6x6 = 36 变体
DESAT = 0.30             # 向灰混合 30%，压饱和度

# 规格 §1.1 三色
PAL_DARK  = np.array([74, 56, 38], dtype=float)    # #4a3826
PAL_MAIN  = np.array([107, 81, 56], dtype=float)   # #6b5138
PAL_LIGHT = np.array([138, 106, 74], dtype=float)  # #8a6a4a

def lum(c):
    return 0.299*c[...,0] + 0.587*c[...,1] + 0.114*c[...,2]

def desat_color(c, w):
    g = 0.299*c[0] + 0.587*c[1] + 0.114*c[2]
    return c*(1-w) + g*w

PD, PM, PL = (desat_color(c, DESAT) for c in (PAL_DARK, PAL_MAIN, PAL_LIGHT))
# 主体略提亮，让整体亮度比进 70-85% 区间
PM = PM + (PL - PM) * 0.10

floor = np.array(Image.open(FLOOR).convert("RGB")).astype(float)
floor_lum = lum(floor).mean()
fmx, fmn = floor.max(axis=2), floor.min(axis=2)
floor_sat = ((fmx - fmn) / np.maximum(fmx, 1)).mean()

src = np.array(Image.open(SRC).convert("RGB")).astype(float)
H, W, _ = src.shape
# 避开右下水印
crop_w, crop_h = int(W*0.82), int(H*0.90)
bw, bh = crop_w // N, crop_h // N

# 分布权重：暗缝 12% / 主体 70% / 受光 18%（受光<20%）
P_DARK, P_LIGHT = 6, 12
blocks = []
for r in range(N):
    for c in range(N):
        b = src[r*bh:(r+1)*bh, c*bw:(c+1)*bw]
        L = lum(b).ravel()
        order = np.argsort(L, kind="stable")  # 秩排序：底部12%→暗，顶部18%→亮，tie-proof
        n = L.size
        ranks = np.empty(n, dtype=int)
        ranks[order] = np.arange(n)
        ranks = ranks.reshape(b.shape[:2])
        out = np.empty_like(b)
        out[ranks < int(n * P_DARK / 100)] = PD
        out[ranks >= int(n * (100 - P_LIGHT) / 100)] = PL
        mid = (ranks >= int(n * P_DARK / 100)) & (ranks < int(n * (100 - P_LIGHT) / 100))
        out[mid] = PM
        im = Image.fromarray(out.astype(np.uint8)).resize((TILE, TILE), Image.NEAREST)
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
ratio = allb.mean() / floor_lum * 100
frac_bright = ((allb > lum(PL)).mean()) * 100  # 亮于受光色的占比≈0，改统计受光色像素占比
light_px = 0
for b in blocks:
    m2 = np.all(np.abs(b - PL) < 2, axis=-1)
    light_px += m2.sum()
frac_bright = light_px / (N*N*TILE*TILE) * 100
sats = [((b.max(axis=2)-b.min(axis=2))/np.maximum(b.max(axis=2),1)).mean() for b in blocks]
stds = allb.std(axis=(1,2)) / means
print("=== 验收（要求 → 实测） ===")
print(f"[1] 亮度比:   70-85% → {ratio:.1f}%")
print(f"[2] 受光面占比: <20% → {frac_bright:.1f}%")
print(f"[3] 饱和度比: ≤70% → {np.mean(sats)/floor_sat*100:.0f}%  (岩石{np.mean(sats):.3f} / 地砖{floor_sat:.3f})")
print(f"[4] 变体明度极差: ≤5% → {(means.max()-means.min())/means.mean()*100:.1f}%")
print(f"[5] 块内明度对比(std/mean): 平均 {stds.mean()*100:.1f}%")
print(f"\nsaved {OUT}")
