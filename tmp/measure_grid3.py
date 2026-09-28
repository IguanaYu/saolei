# -*- coding: utf-8 -*-
import numpy as np
from PIL import Image

arr = np.array(Image.open("tmp/shot_measure.png").convert("RGB"))
H, W, _ = arr.shape
ai = arr.astype(int)
hdiff = np.abs(np.diff(ai, axis=1)).sum(axis=2)   # (H, W-1)
vdiff = np.abs(np.diff(ai, axis=0)).sum(axis=2)   # (H-1, W)

# 用强度总和（而非计数），更鲁棒
row_int = hdiff.sum(axis=1)    # 长度 H：每行的水平颜色总差
col_int = vdiff.sum(axis=0)    # 长度 W：每列的垂直颜色总差

print(f"图 {W}x{H}")
print(f"row_int: min={row_int.min()} max={row_int.max()} median={np.median(row_int):.0f} mean={row_int.mean():.0f}")
print(f"col_int: min={col_int.min()} max={col_int.max()} median={np.median(col_int):.0f} mean={col_int.mean():.0f}")

def find_plateau(intensity, name):
    # 找"显著高于背景"的最大连续段
    thr = np.median(intensity) * 0.5   # 网格高原(6000+) vs 背景(<2000) 的分界
    mask = intensity > thr
    idx = np.where(mask)[0]
    if len(idx) == 0:
        thr = np.median(intensity) * 0.4
        mask = intensity > thr
        idx = np.where(mask)[0]
    if len(idx) == 0:
        print(f"{name}: 找不到高原段, thr={thr:.0f}")
        # 打印分布采样
        for i in range(0, len(intensity), len(intensity)//20 if len(intensity)>20 else 1):
            print(f"  {name}[{i}]={intensity[i]:.0f}", end="")
        print()
        return None
    breaks = np.where(np.diff(idx) > 8)[0]
    starts = [idx[0]] + [idx[b+1] for b in breaks]
    ends = [idx[b] for b in breaks] + [idx[-1]]
    best = max(range(len(starts)), key=lambda i: ends[i]-starts[i])
    print(f"{name}: thr={thr:.0f} 高原段 #{best}: [{starts[best]}, {ends[best]}]  长度={ends[best]-starts[best]+1}")
    return starts[best], ends[best]

print("\n== 分布采样（每 ~35px 一次）==")
for i in range(0, H, 35):
    print(f"  y={i:3d} row_int={row_int[i]:6.0f} | x={i if i<W else W-1:3d} col_int={col_int[i if i<W else W-1]:6.0f}")

gy = find_plateau(row_int, "row")
gx = find_plateau(col_int, "col")

if gy and gx:
    gt, gb = gy; gl, gr = gx
    print(f"\n== 网格区域 L={gl} R={gr} T={gt} B={gb}  像素 {gr-gl+1}x{gb-gt+1} 宽高比={(gr-gl+1)/(gb-gt+1):.4f}")

    def cell_sizes(diff1d, g0, g1):
        seg = diff1d[g0+1:g1+1]
        pos = np.arange(g0+1, g1+1)
        expect = (g1-g0)/16
        edges=[g0]
        for k in range(1,17):
            lo=max(g0+int((k-0.5)*expect), edges[-1]+int(expect*0.45))
            hi=min(g0+int((k+0.1)*expect), g1)
            if lo>hi: lo=edges[-1]+int(expect*0.45); hi=g1
            m=(pos>=lo)&(pos<=hi); cand=pos[m]
            best = int(cand[np.argmax(seg[m])]) if len(cand) else g0+int(round(k*expect))
            edges.append(best)
        edges[-1]=g1
        return np.diff(edges)

    cw = cell_sizes(hdiff.sum(axis=0), gl, gr)   # 列方向强度，长度W-1
    rh = cell_sizes(vdiff.sum(axis=1), gt, gb)   # 行方向强度，长度H-1
    print(f"\n== 16 列宽 == {[int(x) for x in cw]}")
    print(f"   第1={cw[0]} 第8={cw[7]} 最末={cw[-1]} | 最末-第1={cw[-1]-cw[0]:+d} 最末-第8={cw[-1]-cw[7]:+d} 极差={cw.max()-cw.min()}")
    print(f"\n== 16 行高 == {[int(x) for x in rh]}")
    print(f"   第1={rh[0]} 第8={rh[7]} 最末={rh[-1]} | 最末-第1={rh[-1]-rh[0]:+d} 最末-第8={rh[-1]-rh[7]:+d} 极差={rh.max()-rh.min()}")
