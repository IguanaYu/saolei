# -*- coding: utf-8 -*-
import numpy as np
from PIL import Image

FN = "tmp/shot_measure.png"
arr = np.array(Image.open(FN).convert("RGB"))
H, W, _ = arr.shape
print(f"== 图片尺寸: {W} x {H} ==")

ai = arr.astype(int)
# 水平/垂直方向颜色差
hdiff = np.abs(np.diff(ai, axis=1)).sum(axis=2)   # (H, W-1) 每个 x 与 x-1 的差
vdiff = np.abs(np.diff(ai, axis=0)).sum(axis=2)   # (H-1, W) 每个 y 与 y-1 的差

# 每行有多少处水平突变 / 每列有多少处垂直突变（网格区会很高）
row_tr = (hdiff > 40).sum(axis=1)   # 长度 H
col_tr = (vdiff > 40).sum(axis=0)   # 长度 W

# 找网格 y 范围：row_tr 大的连续段
thr_y = max(row_tr.max() * 0.4, 30)
grid_rows = row_tr > thr_y
ys = np.where(grid_rows)[0]
# 取最大连续段
def longest_run(mask):
    idx = np.where(mask)[0]
    if len(idx) == 0:
        return None
    # 分段
    breaks = np.where(np.diff(idx) > 5)[0]
    starts = [idx[0]] + [idx[b + 1] for b in breaks]
    ends = [idx[b] for b in breaks] + [idx[-1]]
    best = max(range(len(starts)), key=lambda i: ends[i] - starts[i])
    return starts[best], ends[best]

gy = longest_run(grid_rows)
thr_x = max(col_tr.max() * 0.4, 30)
grid_cols = col_tr > thr_x
gx = longest_run(grid_cols)

print(f"row_transition 峰值={row_tr.max()}, 阈值={thr_y:.0f} -> 网格 y: {gy}")
print(f"col_transition 峰值={col_tr.max()}, 阈值={thr_x:.0f} -> 网格 x: {gx}")

if gy and gx:
    gt, gb = gy
    gl, gr = gx
    print(f"\n== 网格区域: L={gl} R={gr} T={gt} B={gb}")
    print(f"== 网格像素: {gr-gl+1} x {gb-gt+1}  宽高比={ (gr-gl+1)/(gb-gt+1):.4f}")
    print(f"   16列期望={ (gr-gl+1)/16:.2f}px  16行期望={ (gb-gt+1)/16:.2f}px")

    def cell_sizes(diff, g0, g1, axis):
        # 只取网格范围内的差分
        seg = diff[g0 + 1:g1 + 1]
        pos = np.arange(g0 + 1, g1 + 1)
        expect = (g1 - g0) / 16
        edges = [g0]
        for k in range(1, 17):
            lo = max(g0 + int((k - 0.55) * expect), edges[-1] + int(expect * 0.5))
            hi = min(g0 + int((k + 0.15) * expect), g1)
            if lo > hi:
                lo = edges[-1] + int(expect * 0.5); hi = g1
            mask = (pos >= lo) & (pos <= hi)
            cand = pos[mask]
            if len(cand) == 0:
                best = g0 + int(round(k * expect))
            else:
                vals = seg[mask]
                best = int(cand[np.argmax(vals)])
            edges.append(best)
        edges[-1] = g1
        return np.diff(edges)

    cw = cell_sizes(hdiff.sum(axis=0) if False else
                    np.abs(np.diff(ai, axis=1)).sum(axis=0), gl, gr, "列")
    # 注意 hdiff shape (H, W-1)，沿行求和 -> 每个x的列方向强度
    coldiff_sum = hdiff.sum(axis=0)   # 长度 W-1, 索引 x=g0+1..g1-1 对应位置
    rowdiff_sum = vdiff.sum(axis=1)   # 长度 H-1

    cw = cell_sizes(coldiff_sum, gl, gr, "列")
    rh = cell_sizes(rowdiff_sum, gt, gb, "行")

    print(f"\n== 列宽（16格）==")
    print("   ", list(int(x) for x in cw))
    print(f"   第1={cw[0]}  第8={cw[7]}  最末={cw[-1]}  | 最末-第1={cw[-1]-cw[0]}  最末-第8={cw[-1]-cw[7]}")
    print(f"   min={cw.min()} max={cw.max()} 极差={cw.max()-cw.min()}")

    print(f"\n== 行高（16格）==")
    print("   ", list(int(x) for x in rh))
    print(f"   第1={rh[0]}  第8={rh[7]}  最末={rh[-1]}  | 最末-第1={rh[-1]-rh[0]}  最末-第8={rh[-1]-rh[7]}")
    print(f"   min={rh.min()} max={rh.max()} 极差={rh.max()-rh.min()}")
else:
    print("未能定位网格，dump row/col transition 供调试")
    print("row_tr:", row_tr[::20])
    print("col_tr:", col_tr[::20])
