# -*- coding: utf-8 -*-
import urllib.request
import numpy as np
from PIL import Image

URL = ("https://maas-log-prod.cn-wlcb.ufileos.com/anthropic/"
       "0a999cd8-aca6-4464-aa5f-17d8ce006a3c/"
       "28f02c37ca51e7732acefb8c4c5a816c.png"
       "?UCloudPublicKey=TOKEN_e15ba47a-d098-4fbd-9afc-a0dcf0e4e621"
       "&Expires=1786693936&Signature=U9KvDgMLBHzM2quaVWlTGNMWebE=")
FN = "tmp/shot_annotated.png"
urllib.request.urlretrieve(URL, FN)

arr = np.array(Image.open(FN).convert("RGB")).astype(int)
H, W, _ = arr.shape
print(f"图 {W}x{H}")

R, G, B = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]
# 用户标注：高饱和红 / 高饱和蓝
red_mask = (R > 150) & (G < 100) & (B < 100) & (R - np.maximum(G, B) > 80)
blue_mask = (B > 130) & (R < 100) & (G < 110) & (B - np.maximum(R, G) > 60)

print(f"红色像素: {int(red_mask.sum())}  蓝色像素: {int(blue_mask.sum())}")

def bboxes(mask, name):
    ys, xs = np.where(mask)
    if len(xs) == 0:
        print(f"{name}: 无")
        return
    print(f"{name}: x[{xs.min()},{xs.max()}] y[{ys.min()},{ys.max()}] 共{len(xs)}px")
    # 聚类：按连通性粗分（间距>15 视为不同标注）
    order = np.argsort(xs)
    xs_s, ys_s = xs[order], ys[order]
    # 简单按 x 分组
    groups = []
    cur = [0]
    for i in range(1, len(xs_s)):
        if xs_s[i] - xs_s[i-1] > 25:
            groups.append(cur); cur = [i]
        else:
            cur.append(i)
    groups.append(cur)
    for g in groups:
        gx = xs_s[g]; gy = ys_s[g]
        print(f"   标注组: x[{gx.min()},{gx.max()}] y[{gy.min()},{gy.max()}] 中心=({int((gx.min()+gx.max())/2)},{int((gy.min()+gy.max())/2)}) {len(g)}px")

bboxes(red_mask, "红色标注")
bboxes(blue_mask, "蓝色标注")
