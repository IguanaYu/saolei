# -*- coding: utf-8 -*-
import numpy as np
from PIL import Image

def analyze(path, name):
    arr = np.array(Image.open(path).convert("RGB")).astype(int)
    H, W, _ = arr.shape
    print(f"=== {name} {W}x{H} ===")
    coldiff = np.abs(np.diff(arr, axis=1)).sum(axis=(0, 2))
    rowdiff = np.abs(np.diff(arr, axis=0)).sum(axis=(1, 2))

    # 找网格右边界：从右向左找第一个非黑列
    colsum = arr.sum(axis=2).mean(axis=0)
    right_edge = W - 1
    for x in range(W - 1, 0, -1):
        if colsum[x] > 45:  # 非全黑
            right_edge = x
            break
    # 网格底边
    rowsum = arr.sum(axis=2).mean(axis=1)
    bottom_edge = H - 1
    for y in range(H - 1, 0, -1):
        if rowsum[y] > 45:
            bottom_edge = y
            break
    print(f"非黑右边界 x={right_edge}  底边 y={bottom_edge}")

    # 左边界/上边界
    left_edge = 0
    for x in range(W):
        if colsum[x] > 45:
            left_edge = x; break
    top_edge = 0
    for y in range(H):
        if rowsum[y] > 45:
            top_edge = y; break
    print(f"非黑左边界 x={left_edge}  上边 y={top_edge}")
    gw = right_edge - left_edge + 1
    gh = bottom_edge - top_edge + 1
    print(f"网格像素: {gw} x {gh}  宽高比={gw/gh:.4f}  每格(16均分): {gw/16:.2f} x {gh/16:.2f}")

    # 最右区域精细剖面：right_edge-70 .. right_edge
    print(f"\n最右 {min(70,right_edge)}px 的列颜色差剖面（每2px）:")
    lo = max(left_edge, right_edge - 70)
    for x in range(lo, right_edge, 2):
        v = coldiff[x] if x < len(coldiff) else 0
        bar = "#" * min(int(v / 200), 60)
        print(f"  x={x}: {int(v):6d} {bar}")
    return (left_edge, right_edge, top_edge, bottom_edge)

analyze("tmp/shot_measure.png", "第一张截图(未标注)")
print()
analyze("tmp/shot_annotated.png", "第二张截图(红蓝标注)")
