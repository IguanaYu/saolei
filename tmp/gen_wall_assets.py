#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成游戏内岩壁/洞底素材（接 mock_AB_variants 的定稿画法）→ assets/tiles/

输出：
  wall_A1..A4.png  连体岩壁无缝纹理（336×336 = 12 格周期，torus 噪声天然无缝）
  wall_B1..B4.png  碎石泥土无缝纹理（泥土 fbm + 均匀随机碎石，画椭圆时 9 宫格 wrap 复制保证无缝）
  floor_dark.png   已开格暗色洞底（岩壁同族色板、更暗更平，数字可读性优先）
  wall_edge_T/B/L/R.png  边缘碎裂条（28×4 / 4×28，RGBA 透明底，深裂缝+亮棱）
"""
import os
import random
from PIL import Image, ImageDraw

TMP = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(TMP, "..", "assets", "tiles")
os.makedirs(OUT_DIR, exist_ok=True)

SIZE = 336  # 12 格 × 28px


# ---------------- 噪声 ----------------

def smooth(t):
    return t * t * (3 - 2 * t)


def value_noise(size, grid, seed):
    rng = random.Random(seed)
    vals = [[rng.random() for _ in range(grid)] for _ in range(grid)]
    cell = size / grid
    out = [[0.0] * size for _ in range(size)]
    for y in range(size):
        for x in range(size):
            gx, gy = x / cell, y / cell
            x0, y0 = int(gx) % grid, int(gy) % grid
            x1, y1 = (x0 + 1) % grid, (y0 + 1) % grid
            fx, fy = smooth(gx - int(gx)), smooth(gy - int(gy))
            top = vals[y0][x0] * (1 - fx) + vals[y0][x1] * fx
            bot = vals[y1][x0] * (1 - fx) + vals[y1][x1] * fx
            out[y][x] = top * (1 - fy) + bot * fy
    return out


def fbm(size, grids, seed):
    acc = [[0.0] * size for _ in range(size)]
    total = 0.0
    for i, g in enumerate(grids):
        layer = value_noise(size, g, seed + i * 131)
        amp = 1.0 / (i + 1)
        total += amp
        for y in range(size):
            ra, rl = acc[y], layer[y]
            for x in range(size):
                ra[x] += rl[x] * amp
    for y in range(size):
        for x in range(size):
            acc[y][x] /= total
    return acc


def lerp(a, b, t):
    return a + (b - a) * t


# ---------------- A 系：连体岩壁 ----------------

A_STYLES = [
    ("A1", (48, 43, 40), (125, 113, 101), 42),
    ("A2", (54, 38, 32), (138, 100, 78), 1042),
    ("A3", (44, 46, 50), (116, 122, 128), 2042),
    ("A4", (58, 49, 34), (140, 122, 86), 3042),
]


def gen_wall_A(name, lo, hi, seed):
    n = fbm(SIZE, [6, 12, 24, 48], seed)
    img = Image.new("RGB", (SIZE, SIZE))
    px = img.load()
    for y in range(SIZE):
        row = n[y]
        for x in range(SIZE):
            v = row[x]
            px[x, y] = (int(lerp(lo[0], hi[0], v)), int(lerp(lo[1], hi[1], v)), int(lerp(lo[2], hi[2], v)))
    rng = random.Random(seed + 9)
    for _ in range(1400):
        x, y = rng.randrange(SIZE), rng.randrange(SIZE)
        r, g, b = px[x, y]
        px[x, y] = (max(0, r - 24), max(0, g - 24), max(0, b - 24))
    img.save(os.path.join(OUT_DIR, f"wall_{name}.png"))
    print("saved wall_" + name)


# ---------------- B 系：泥土 + 碎石 ----------------

B_STYLES = [
    ("B1", (74, 55, 36), (128, 98, 62), [(104, 94, 84), (88, 79, 70), (120, 108, 95)], 3),
    ("B2", (94, 52, 36), (146, 88, 58), [(112, 84, 66), (96, 70, 54), (128, 100, 78)], 3),
    ("B3", (52, 44, 38), (96, 82, 66), [(96, 88, 80), (78, 71, 64), (108, 100, 90)], 4),
    ("B4", (108, 90, 58), (158, 136, 94), [(150, 138, 118), (132, 120, 102), (166, 152, 130)], 2),
]


def gen_wall_B(name, soil_lo, soil_hi, tones, density, seed):
    rng = random.Random(seed)
    n = fbm(SIZE, [48, 96], seed + 5)
    img = Image.new("RGB", (SIZE, SIZE))
    px = img.load()
    for y in range(SIZE):
        row = n[y]
        for x in range(SIZE):
            v = row[x]
            j = 0.9 + 0.2 * v
            px[x, y] = (int(lerp(soil_lo[0], soil_hi[0], v) * j),
                        int(lerp(soil_lo[1], soil_hi[1], v) * j),
                        int(lerp(soil_lo[2], soil_hi[2], v) * j))
    d = ImageDraw.Draw(img)
    cells = (SIZE // 28) ** 2
    total_stones = int(cells * density)
    for _ in range(total_stones):
        cx, cy = rng.randrange(SIZE), rng.randrange(SIZE)
        rw, rh = rng.randint(2, 5), rng.randint(2, 4)
        tone = rng.choice(tones)
        outline = (int(tone[0] * 0.55), int(tone[1] * 0.55), int(tone[2] * 0.55))
        hl = (min(255, tone[0] + 40), min(255, tone[1] + 40), min(255, tone[2] + 40))
        # 9 宫格 wrap 复制 → 跨周期边界无缝
        for oy in (-SIZE, 0, SIZE):
            for ox in (-SIZE, 0, SIZE):
                x, y = cx + ox, cy + oy
                d.ellipse([x - rw, y - rh, x + rw, y + rh], fill=tone, outline=outline)
                d.point((x - rw + 1, y - rh + 1), fill=hl)
    img.save(os.path.join(OUT_DIR, f"wall_{name}.png"))
    print("saved wall_" + name)


# ---------------- 洞底（已开格） ----------------

def gen_floor_dark():
    n = fbm(SIZE, [24, 48], 77)
    lo, hi = (40, 35, 26), (74, 64, 46)
    img = Image.new("RGB", (SIZE, SIZE))
    px = img.load()
    for y in range(SIZE):
        row = n[y]
        for x in range(SIZE):
            v = row[x]
            px[x, y] = (int(lerp(lo[0], hi[0], v)), int(lerp(lo[1], hi[1], v)), int(lerp(lo[2], hi[2], v)))
    rng = random.Random(78)
    for _ in range(420):  # 亮沙粒
        x, y = rng.randrange(SIZE), rng.randrange(SIZE)
        r, g, b = px[x, y]
        px[x, y] = (min(255, r + 26), min(255, g + 24), min(255, b + 18))
    for _ in range(260):  # 暗点
        x, y = rng.randrange(SIZE), rng.randrange(SIZE)
        r, g, b = px[x, y]
        px[x, y] = (max(0, r - 14), max(0, g - 14), max(0, b - 14))
    img.save(os.path.join(OUT_DIR, "floor_dark.png"))
    print("saved floor_dark")


# ---------------- 边缘碎裂条 ----------------

def gen_edges():
    rng = random.Random(9)
    dark, lite = (22, 18, 15, 215), (146, 132, 117, 185)

    def strip(w, h, orient, side):
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        if orient == "H":  # T 或 B，沿 x 走
            y_dark = 0 if side == "T" else h - 2
            y_lite = 3 if side == "T" else 0
            x = 0
            while x < w:
                seg = rng.randint(3, 7)
                xe = min(x + seg, w - 1)
                th = 2 if rng.randint(0, 3) else 3
                d.line([(x, y_dark), (xe, y_dark)], fill=dark, width=th)
                d.line([(x, y_lite), (xe, y_lite)], fill=lite, width=1)
                x += seg
        else:  # L 或 R，沿 y 走
            x_dark = 0 if side == "L" else w - 2
            x_lite = 3 if side == "L" else 0
            y = 0
            while y < h:
                seg = rng.randint(3, 7)
                ye = min(y + seg, h - 1)
                th = 2 if rng.randint(0, 3) else 3
                d.line([(x_dark, y), (x_dark, ye)], fill=dark, width=th)
                d.line([(x_lite, y), (x_lite, ye)], fill=lite, width=1)
                y += seg
        return img

    strip(28, 4, "H", "T").save(os.path.join(OUT_DIR, "wall_edge_T.png"))
    strip(28, 4, "H", "B").save(os.path.join(OUT_DIR, "wall_edge_B.png"))
    strip(4, 28, "V", "L").save(os.path.join(OUT_DIR, "wall_edge_L.png"))
    strip(4, 28, "V", "R").save(os.path.join(OUT_DIR, "wall_edge_R.png"))
    print("saved wall_edge_T/B/L/R")


if __name__ == "__main__":
    for name, lo, hi, seed in A_STYLES:
        gen_wall_A(name, lo, hi, seed)
    for name, slo, shi, tones, dens in B_STYLES:
        gen_wall_B(name, slo, shi, tones, dens, seed=200 + int(name[1]))
    gen_floor_dark()
    gen_edges()
