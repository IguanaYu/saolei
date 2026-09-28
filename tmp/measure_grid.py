# -*- coding: utf-8 -*-
import urllib.request
import numpy as np
from PIL import Image

URL = ("https://maas-log-prod.cn-wlcb.ufileos.com/anthropic/"
       "0a999cd8-aca6-4464-aa5f-17d8ce006a3c/"
       "e25a2d3f07609ad18a5c0d225c933c83.png"
       "?UCloudPublicKey=TOKEN_e15ba47a-d098-4fbd-9afc-a0dcf0e4e621"
       "&Expires=1786679940&Signature=GF6KhihcO4mg2mobJcQSnJwoAYI=")
FN = "tmp/shot_measure.png"
urllib.request.urlretrieve(URL, FN)

arr = np.array(Image.open(FN).convert("RGB"))
H, W, _ = arr.shape
print(f"== 图片尺寸: {W} x {H} ==")

# 网格外框：非纯黑像素的范围
nonblack = arr.sum(axis=2) > 30
cols_any = nonblack.any(axis=0)
rows_any = nonblack.any(axis=1)
xs = np.where(cols_any)[0]
ys = np.where(rows_any)[0]
gl, gr = int(xs[0]), int(xs[-1])
gt, gb = int(ys[0]), int(ys[-1])
gw = gr - gl + 1
gh = gb - gt + 1
print(f"== 网格外框: L={gl} R={gr} T={gt} B={gb}")
print(f"== 网格像素尺寸: {gw} x {gh}  (16列期望≈{gw/16:.2f}px/列, 16行期望≈{gh/16:.2f}px/行)")


def find_edges(diff, g0, g1, n_cells, axis_name):
    # diff[i] 是位置 (g0+1+i) 处与前一列/行的差异；只取网格内
    seg = diff[g0 + 1:g1 + 1]
    idx_local = np.arange(len(seg))
    pos = g0 + 1 + idx_local  # 实际坐标
    # 期望列宽
    span = g1 - g0
    expect = span / n_cells
    # 从左到右贪心找峰：每个期望边界附近 ±40% 范围取最大 diff
    edges = [g0]
    cursor = g0
    for k in range(1, n_cells + 1):
        lo = g0 + int((k - 0.6) * expect)
        hi = g0 + int((k + 0.2) * expect)
        lo = max(lo, cursor + int(expect * 0.5))
        hi = min(hi, g1)
        if lo > hi:
            lo = cursor + int(expect * 0.5)
        cand = pos[(pos >= lo) & (pos <= hi)]
        if len(cand) == 0:
            # 退化：直接用期望位置
            best = g0 + int(round(k * expect))
        else:
            vals = seg[(pos >= lo) & (pos <= hi)]
            best = int(cand[np.argmax(vals)])
        edges.append(best)
        cursor = best
    edges[-1] = g1  # 最右/下边界锁到外框
    widths = np.diff(edges)
    print(f"\n== {axis_name} 逐格尺寸（共{len(widths)}格）==")
    print("  ", list(widths))
    print(f"   第1格={widths[0]}  中间格(第8)={widths[7]}  最末格={widths[-1]}")
    print(f"   最末 - 第1 = {widths[-1]-widths[0]}   最末 - 中间 = {widths[-1]-widths[7]}")
    print(f"   最小={widths.min()} 最大={widths.max()} 极差={widths.max()-widths.min()}")
    return widths


coldiff = np.abs(np.diff(arr.astype(int), axis=1)).sum(axis=(0, 2))
rowdiff = np.abs(np.diff(arr.astype(int), axis=0)).sum(axis=(1, 2))

cw = find_edges(coldiff, gl, gr, 16, "列(宽度)")
rh = find_edges(rowdiff, gt, gb, 16, "行(高度)")
