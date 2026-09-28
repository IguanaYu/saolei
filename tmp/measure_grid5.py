# -*- coding: utf-8 -*-
import numpy as np
from PIL import Image

arr = np.array(Image.open("tmp/shot_measure.png").convert("RGB")).astype(int)
H, W, _ = arr.shape
coldiff = np.abs(np.diff(arr, axis=1)).sum(axis=(0, 2))   # 长度 W-1
rowdiff = np.abs(np.diff(arr, axis=0)).sum(axis=(1, 2))   # 长度 H-1


def best_grid(diff1d, g0_range, span_range):
    """二维搜索 (起点g0, 跨度span)，使 15 条等距边界强度之和最大"""
    best = None
    for span in range(span_range[0], span_range[1]):
        for g0 in range(g0_range[0], g0_range[1]):
            s = 0
            for i in range(1, 16):
                x = g0 + i * span // 16
                if 0 <= x < len(diff1d):
                    s += diff1d[x]
            if best is None or s > best[0]:
                best = (s, g0, g0 + span)
    return best


def real_cell_sizes(diff1d, g0, g1, n=16):
    step = (g1 - g0) / n
    edges = [g0]
    for i in range(1, n):
        center = g0 + i * step
        lo = max(int(center - step * 0.4), edges[-1] + int(step * 0.3))
        hi = min(int(center + step * 0.4), len(diff1d) - 1)
        seg = diff1d[lo:hi + 1]
        edges.append(lo + int(np.argmax(seg)))
    edges.append(g1)
    return np.diff(edges)


print(f"图 {W}x{H}\n")
bc = best_grid(coldiff, (255, 305), (360, 460))
br = best_grid(rowdiff, (180, 270), (360, 460))
print(f"列: g0={bc[1]} g1={bc[2]} 跨度={bc[2]-bc[1]} score={bc[0]}")
print(f"行: g0={br[1]} g1={br[2]} 跨度={br[2]-br[1]} score={br[0]}")
print(f"宽高比={(bc[2]-bc[1])/(br[2]-br[1]):.4f}\n")

cw = real_cell_sizes(coldiff, bc[1], bc[2])
rh = real_cell_sizes(rowdiff, br[1], br[2])

print(f"16列宽: {[int(x) for x in cw]}")
print(f"   平均={cw.mean():.1f} 第1={cw[0]} 第8={cw[7]} 最末={cw[-1]} | 最末-平均={cw[-1]-cw.mean():+.1f} 最末-第8={cw[-1]-cw[7]:+d} 极差={cw.max()-cw.min()}\n")

print(f"16行高: {[int(x) for x in rh]}")
print(f"   平均={rh.mean():.1f} 第1={rh[0]} 第8={rh[7]} 最末={rh[-1]} | 最末-平均={rh[-1]-rh.mean():+.1f} 最末-第8={rh[-1]-rh[7]:+d} 极差={rh.max()-rh.min()}\n")

print(f"=== 对照 ===")
print(f"最右列宽={int(cw[-1])}px  最下行高={int(rh[-1])}px")
print(f"中间列宽={int(cw[7])}px  中间行高={int(rh[7])}px")
print(f"最右列相对中间: {(cw[-1]/cw[7]-1)*100:+.1f}%")
print(f"最下行相对中间: {(rh[-1]/rh[7]-1)*100:+.1f}%")
