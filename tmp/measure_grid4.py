# -*- coding: utf-8 -*-
import numpy as np
from PIL import Image

arr = np.array(Image.open("tmp/shot_measure.png").convert("RGB")).astype(int)
H, W, _ = arr.shape
coldiff = np.abs(np.diff(arr, axis=1)).sum(axis=(0, 2))   # 长度 W-1
rowdiff = np.abs(np.diff(arr, axis=0)).sum(axis=(1, 2))   # 长度 H-1


def best_grid(diff1d, lo_range, hi_range):
    """搜索使 15 条等距边界强度之和最大的 [gl,gr]"""
    best = None
    for gl in range(lo_range[0], lo_range[1]):
        for gr in range(hi_range[0], hi_range[1]):
            span = gr - gl
            if span < 350 or span > 520:
                continue
            s = 0
            for i in range(1, 16):
                x = gl + i * span // 16
                if 0 <= x < len(diff1d):
                    s += diff1d[x]
            if best is None or s > best[0]:
                best = (s, gl, gr)
    return best


def real_cell_sizes(diff1d, gl, gr, n=16):
    """在最优等距网格上，每条边界在 ±0.4*step 邻域找真实峰，得每格实际尺寸"""
    step = (gr - gl) / n
    edges = [gl]
    for i in range(1, n):
        center = gl + i * step
        lo = int(center - step * 0.4)
        hi = int(center + step * 0.4)
        lo = max(lo, edges[-1] + int(step * 0.3))
        hi = min(hi, len(diff1d) - 1)
        seg = diff1d[lo:hi + 1]
        peak = lo + int(np.argmax(seg))
        edges.append(peak)
    edges.append(gr)
    return np.diff(edges)


print(f"图 {W}x{H}\n")
bc = best_grid(coldiff, (255, 295), (650, 710))
br = best_grid(rowdiff, (185, 220), (605, 645))
print(f"列最优边界: gl={bc[1]} gr={bc[2]} 跨度={bc[2]-bc[1]} score={bc[0]}")
print(f"行最优边界: gt={br[1]} gb={br[2]} 跨度={br[2]-br[1]} score={br[0]}")
print(f"宽高比={(bc[2]-bc[1])/(br[2]-br[1]):.4f}\n")

cw = real_cell_sizes(coldiff, bc[1], bc[2])
rh = real_cell_sizes(rowdiff, br[1], br[2])

print(f"16列宽: {[int(x) for x in cw]}  总和={int(cw.sum())}")
print(f"   平均={cw.mean():.1f}  第1={cw[0]}  第8={cw[7]}  最末(16)={cw[-1]}")
print(f"   最末-平均={cw[-1]-cw.mean():+.1f}  最末-第1={cw[-1]-cw[0]:+d}  最末-第8={cw[-1]-cw[7]:+d}")
print(f"   极差={cw.max()-cw.min()} (min={cw.min()} max={cw.max()})\n")

print(f"16行高: {[int(x) for x in rh]}  总和={int(rh.sum())}")
print(f"   平均={rh.mean():.1f}  第1={rh[0]}  第8={rh[7]}  最末(16)={rh[-1]}")
print(f"   最末-平均={rh[-1]-rh.mean():+.1f}  最末-第1={rh[-1]-rh[0]:+d}  最末-第8={rh[-1]-rh[7]:+d}")
print(f"   极差={rh.max()-rh.min()} (min={rh.min()} max={rh.max()})")
