# -*- coding: utf-8 -*-
import numpy as np
from PIL import Image

arr = np.array(Image.open("tmp/shot_annotated.png").convert("RGB")).astype(int)

# 用户标注是红/蓝描边，先粗略抹掉它们对边界检测的干扰：
# 把"高饱和红/蓝"像素替换为邻域中值色，避免标注线本身产生假边界
R, G, B = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]
red = (R > 140) & (G < 110) & (B < 110) & (R - np.maximum(G, B) > 60)
blue = (B > 120) & (R < 110) & (G < 120) & (B - np.maximum(R, G) > 50)
mark = red | blue
print(f"标注像素: 红{int(red.sum())} 蓝{int(blue.sum())} -> 置为中值色以消除干扰")
med = np.median(arr.reshape(-1, 3), axis=0)
arr2 = arr.copy()
arr2[mark] = med.astype(int)

coldiff = np.abs(np.diff(arr2, axis=1)).sum(axis=(0, 2))   # 长度 W-1
rowdiff = np.abs(np.diff(arr2, axis=0)).sum(axis=(1, 2))   # 长度 H-1


def peaks(diff1d, lo, hi, min_dist=8, top=None):
    """独立局部极大检测，不预设等距"""
    seg = diff1d[lo:hi]
    # 平滑
    k = np.ones(3) / 3
    sm = np.convolve(seg, k, mode="same")
    med_v = np.median(sm)
    cand = []
    for i in range(2, len(sm) - 2):
        if sm[i] >= sm[i-1] and sm[i] >= sm[i+1] and sm[i] > med_v * 1.8:
            cand.append((lo + i, sm[i]))
    # 非极大值抑制
    cand.sort(key=lambda t: -t[1])
    keep = []
    for pos, v in cand:
        if all(abs(pos - p) >= min_dist for p, _ in keep):
            keep.append((pos, v))
    keep.sort()
    return keep


print("\n== 垂直边界（列边界）x位置 [265,700] ==")
pk = peaks(coldiff, 265, min(700, len(coldiff) - 1))
xs = [p for p, v in pk]
print("位置:", xs)
gaps = np.diff(xs)
print("间距:", [int(g) for g in gaps])
print(f"间距中位数={np.median(gaps):.1f}  最大间距={gaps.max()} @x={xs[int(np.argmax(gaps))]}->{xs[int(np.argmax(gaps))+1] if int(np.argmax(gaps))+1<len(xs) else '?'}")

print("\n== 水平边界（行边界）y位置 [170,625] ==")
pk2 = peaks(rowdiff, 170, min(625, len(rowdiff) - 1))
ys = [p for p, v in pk2]
print("位置:", ys)
gaps2 = np.diff(ys)
print("间距:", [int(g) for g in gaps2])
print(f"间距中位数={np.median(gaps2):.1f}  最大间距={gaps2.max()} @y={ys[int(np.argmax(gaps2))]}->{ys[int(np.argmax(gaps2))+1] if int(np.argmax(gaps2))+1<len(ys) else '?'}")

# 对照用户红框：x[243,681] y[180,609]
print(f"\n== 对照红框 bbox x[243,681] y[180,609] ==")
print(f"网格左边界(上一轮等距拟合)=274, 拟合右边界=657  | 红框右缘=681")
print(f"网格上边界=182, 拟合下边界=565  | 红框下缘=609")
