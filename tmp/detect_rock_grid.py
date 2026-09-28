# -*- coding: utf-8 -*-
"""岩石图网格检测：行/列亮度找暗带（裂缝），输出中间结果确认定位正确（AGENTS 守则）"""
import numpy as np
from PIL import Image

img = Image.open("tmp/rock_wall_16c.png").convert("RGB")
arr = np.array(img).astype(int)
H, W, _ = arr.shape
lum = 0.299 * arr[:, :, 0] + 0.587 * arr[:, :, 1] + 0.114 * arr[:, :, 2]

colmean = lum.mean(axis=0)  # 每列平均亮度
rowmean = lum.mean(axis=1)

# 等距网格搜索：N 条暗缝，使缝处亮度总和最小
def best_grid(m, n_min, n_max):
    best = None
    for n in range(n_min, n_max):
        for g0 in range(0, len(m) // n):
            step = (len(m) - g0) / n
            idx = [int(g0 + i * step) for i in range(1, n)]
            if any(x >= len(m) for x in idx):
                continue
            s = sum(m[x] for x in idx)
            if best is None or s < best[0]:
                best = (s, n, g0, step)
    return best

for name, m in (("列", colmean), ("行", rowmean)):
    b = best_grid(m, 4, 16)
    print(f"{name}: n={b[1]} g0={b[2]:.1f} step={b[3]:.1f} (块宽≈{b[3]:.1f}px) score={b[0]:.0f} 全局均值={m.mean():.1f}")

print(f"\n图尺寸 {W}x{H}, 整体亮度均值={lum.mean():.1f}")
# 亮度直方图概况
print(f"亮度 p10={np.percentile(lum,10):.0f} p50={np.percentile(lum,50):.0f} p90={np.percentile(lum,90):.0f} max={lum.max():.0f}")
