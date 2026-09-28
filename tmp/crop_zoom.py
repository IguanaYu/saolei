# -*- coding: utf-8 -*-
import numpy as np
from PIL import Image

img = Image.open("tmp/shot_annotated.png").convert("RGB")
arr = np.array(img).astype(int)

# 抹掉红蓝标注（置为邻域色）避免干扰视觉判断
R, G, B = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]
red = (R > 140) & (G < 110) & (B < 110) & (R - np.maximum(G, B) > 60)
blue = (B > 120) & (R < 110) & (G < 120) & (B - np.maximum(R, G) > 50)
mark = red | blue
arr2 = arr.copy()
if mark.any():
    # 用上方邻域像素替代标注
    shifted = np.roll(arr, -3, axis=0)
    arr2[mark] = shifted[mark]
img2 = Image.fromarray(arr2.clip(0, 255).astype(np.uint8))

# 裁剪关键区域并放大3倍
crops = {
    "A_最右列区":  (585, 180, 700, 620),   # x[585,700] y[180,620] 含最右列
    "B_最下行区":  (243, 510, 681, 625),   # x[243,681] y[510,625] 含最下行
    "C_中间对照":  (385, 385, 500, 500),   # 网格中部普通格子
}
tiles = []
for name, box in crops.items():
    c = img2.crop(box)
    c3 = c.resize((c.width * 3, c.height * 3), Image.NEAREST)
    c3.save(f"tmp/crop_{name}.png")
    print(f"{name}: box={box} -> tmp/crop_{name}.png ({c3.width}x{c3.height})")

# 数值剖面：最右区域每列平均亮度，看 620-674 是连续纹理还是格子边界
region = arr2[200:580, 580:700]  # 网格中部行、最右几列
prof = region.mean(axis=(0, 2))
print("\n最右区域每列平均亮度 (x=580..699):")
for i in range(0, 120, 4):
    x = 580 + i
    bar = "#" * int(prof[i] / 4)
    print(f"  x={x}: {prof[i]:5.1f} {bar}")
