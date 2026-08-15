#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
未开格子（岩壁/墙体）视觉方案对比 mock。

5 个面板，同一局面，只换未开格画法：
  0. 现状对照 —— 每格一颗独立完整小石头（用户反馈"整齐摆放不好看"）
  1. 方案 A  —— 连体岩壁：跨格连续噪声纹理 + 挖开边缘碎裂描边（Dome Keeper 式）
  2. 方案 B  —— 碎石堆：泥土底 + 每格随机散碎石（微软扫雷冒险模式式）
  3. 方案 C  —— A+B 混合：连体岩壁 + 碎石散件 + 边缘凹陷阴影
  4. 方案 D  —— 纯色 + 明暗抖动（最小改动）

已开区域所有面板一致：真实 floor_bricks_sheet.png 随机地砖 + 数字 + 旗 + 矿脉。
"""
import os
import random
from PIL import Image, ImageDraw, ImageFont

TMP = os.path.dirname(os.path.abspath(__file__))
BRICK_SHEET_PATH = os.path.join(TMP, "..", "assets", "tiles", "floor_bricks_sheet.png")
OUT_PATH = os.path.join(TMP, "mock_rock_styles.png")

# ---- 几何 ----
CELL = 28            # 逻辑格像素（与游戏 cell_size 一致）
COLS, ROWS = 12, 8   # 面板格子数
W, H = COLS * CELL, ROWS * CELL
SCALE = 2            # 输出放大倍数（看清细节）
TITLE_H = 30         # 标题条高（SCALE 前）
GAP = 6              # 面板间距

FONT_PATH = "C:/Windows/Fonts/msyh.ttc"

# ---- 局面 ----
# 开区：c 1..6, r 1..4；数字摆在开区边缘；旗 (8,2)；矿脉 (3,6)
OPEN = {(c, r) for c in range(1, 7) for r in range(1, 5)}
NUMBERS = {(1, 4): ("1", (77, 138, 255)), (2, 4): ("2", (77, 204, 92)),
           (3, 4): ("1", (77, 138, 255)), (6, 2): ("2", (77, 204, 92)),
           (6, 3): ("3", (235, 59, 59)), (4, 1): ("1", (77, 138, 255))}
FLAG = (8, 2)
VEIN = (3, 6)


def in_open(c, r):
    if (c, r) == VEIN:
        return True
    return (c, r) in OPEN


# ---- 噪声（torus 无缝，源自 gen_tiles.py） ----
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
    """多层叠加的 torus 噪声，返回 size×size 的 0~1。"""
    acc = [[0.0] * size for _ in range(size)]
    total = 0.0
    for i, g in enumerate(grids):
        layer = value_noise(size, g, seed + i * 131)
        amp = 1.0 / (i + 1)
        total += amp
        for y in range(size):
            row_a, row_l = acc[y], layer[y]
            for x in range(size):
                row_a[x] += row_l[x] * amp
    for y in range(size):
        for x in range(size):
            acc[y][x] /= total
    return acc


def lerp(a, b, t):
    return a + (b - a) * t


# ---- 连体岩壁底纹（跨格连续的关键：整面板一张噪声图） ----
def make_wall_texture(w, h, seed=42):
    """生成 w×h 连续岩壁纹理（从 336×336 torus 图上取，保证游戏里 atlas 可行）。"""
    size = 336  # 12 格周期，与游戏 atlas 方案一致
    n = fbm(size, [6, 12, 24, 48], seed)
    lo, hi = (48, 43, 40), (125, 113, 101)
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            v = n[y][x]
            px[x, y] = tuple(int(lerp(lo[i], hi[i], v)) for i in range(3))
    # 撒少量暗色裂纹点
    rng = random.Random(seed + 9)
    for _ in range(600):
        x, y = rng.randrange(size), rng.randrange(size)
        dx = px[x, y]
        px[x, y] = tuple(max(0, c - 26) for c in dx)
    return img.crop((0, 0, w, h))


# ---- 各方案：未开格底图 ----

def paint_current(d, img, rng):
    """现状：每格一颗独立完整小石头，整齐居中排列。"""
    for r in range(ROWS):
        for c in range(COLS):
            if in_open(c, r):
                continue
            x0, y0 = c * CELL, r * CELL
            d.rectangle([x0, y0, x0 + CELL - 1, y0 + CELL - 1], fill=(38, 28, 20))
            # 一颗居中石头：椭圆 + 顶部高光 + 底部阴影
            cx, cy = x0 + CELL // 2 + rng.randint(-1, 1), y0 + CELL // 2 + rng.randint(-1, 1)
            rw, rh = 9 + rng.randint(0, 1), 7 + rng.randint(0, 1)
            d.ellipse([cx - rw, cy - rh, cx + rw, cy + rh], fill=(112, 101, 90), outline=(70, 62, 54))
            d.ellipse([cx - rw + 3, cy - rh + 2, cx - rw + 8, cy - rh + 5], fill=(150, 138, 122))
            d.ellipse([cx - rw + 2, cy + rh - 5, cx + rw - 3, cy + rh - 2], fill=(80, 71, 62))


def paint_A(d, img, rng, wall, overlay_shade=True):
    """方案 A：连体岩壁。整面连续纹理，格间无边界；仅挖开边缘画碎裂描边。"""
    img.paste(wall, (0, 0))
    # 未开格间的接缝完全不存在——这就是"连体"
    for r in range(ROWS):
        for c in range(COLS):
            if in_open(c, r):
                continue
            sides = edge_sides(c, r)
            if sides:
                draw_cracked_edge(d, c, r, sides, rng)


def paint_B(d, img, rng):
    """方案 B：碎石堆。泥土底 + 每格随机散 2-3 颗碎石。"""
    soil = Image.new("RGB", (W, H))
    sp = soil.load()
    rng2 = random.Random(7)
    for r in range(ROWS):
        for c in range(COLS):
            base = rng2.uniform(0, 1)
            for y in range(r * CELL, (r + 1) * CELL):
                for x in range(c * CELL, (c + 1) * CELL):
                    j = rng2.uniform(0.82, 1.0)
                    t = min(1.0, max(0.0, base * 0.4 + j * 0.6))
                    sp[x, y] = tuple(int(lerp((74, 55, 36)[i], (128, 98, 62)[i], t)) for i in range(3))
    img.paste(soil, (0, 0))
    # 散碎石
    for r in range(ROWS):
        for c in range(COLS):
            if in_open(c, r):
                continue
            for _ in range(rng.randint(2, 3)):
                cx = c * CELL + rng.randint(4, CELL - 5)
                cy = r * CELL + rng.randint(4, CELL - 5)
                rw, rh = rng.randint(2, 5), rng.randint(2, 4)
                tone = rng.choice([(104, 94, 84), (88, 79, 70), (120, 108, 95)])
                d.ellipse([cx - rw, cy - rh, cx + rw, cy + rh], fill=tone, outline=(58, 52, 46))
                d.point((cx - rw + 1, cy - rh + 1), fill=(150, 138, 122))


def paint_C(d, img, rng, wall):
    """方案 C：连体岩壁 + 碎石散件 + 开区边缘凹陷阴影。"""
    img.paste(wall, (0, 0))
    # 开区边缘的未开格：靠开区一侧压暗，做凹陷 ambient occlusion
    shade = Image.new("L", (W, H), 0)
    sd = ImageDraw.Draw(shade)
    for r in range(ROWS):
        for c in range(COLS):
            if in_open(c, r):
                continue
            x0, y0 = c * CELL, r * CELL
            for s in edge_sides(c, r):
                if s == "T":
                    sd.rectangle([x0, y0, x0 + CELL - 1, y0 + 5], fill=70)
                elif s == "B":
                    sd.rectangle([x0, y0 + CELL - 6, x0 + CELL - 1, y0 + CELL - 1], fill=90)
                elif s == "L":
                    sd.rectangle([x0, y0, x0 + 5, y0 + CELL - 1], fill=70)
                elif s == "R":
                    sd.rectangle([x0 + CELL - 6, y0, x0 + CELL - 1, y0 + CELL - 1], fill=90)
    black = Image.new("RGB", (W, H), (18, 14, 12))
    img.paste(black, (0, 0), shade)
    # 边缘碎裂描边
    for r in range(ROWS):
        for c in range(COLS):
            if in_open(c, r):
                continue
            sides = edge_sides(c, r)
            if sides:
                draw_cracked_edge(d, c, r, sides, rng)
    # 岩壁上散少量同色系碎石（打破均匀但不形成每格模式）
    for r in range(ROWS):
        for c in range(COLS):
            if in_open(c, r):
                continue
            if rng.random() < 0.30:
                cx = c * CELL + rng.randint(3, CELL - 4)
                cy = r * CELL + rng.randint(3, CELL - 4)
                rw, rh = rng.randint(2, 4), rng.randint(2, 3)
                tone = rng.choice([(132, 119, 105), (72, 64, 57)])
                d.ellipse([cx - rw, cy - rh, cx + rw, cy + rh], fill=tone)


def paint_D(d, img, rng):
    """方案 D：纯色 + 每格明暗抖动（最小改动）。"""
    import colorsys
    base = (64, 46, 28)
    for r in range(ROWS):
        for c in range(COLS):
            if in_open(c, r):
                continue
            h, l, s = colorsys.rgb_to_hls(*(v / 255 for v in base))
            l = max(0.0, min(1.0, l * rng.uniform(0.85, 1.15)))
            rgb = tuple(int(v * 255) for v in colorsys.hls_to_rgb(h, l, s))
            d.rectangle([c * CELL, r * CELL, (c + 1) * CELL - 1, (r + 1) * CELL - 1], fill=rgb)


# ---- 边缘工具 ----

def edge_sides(c, r):
    """未开格的哪些边贴着'开区或地图边界'——只有这些边画轮廓。"""
    sides = []
    for (dc, dr, s) in ((0, -1, "T"), (0, 1, "B"), (-1, 0, "L"), (1, 0, "R")):
        nc, nr = c + dc, r + dr
        if not (0 <= nc < COLS and 0 <= nr < ROWS) or in_open(nc, nr):
            sides.append(s)
    return sides


def draw_cracked_edge(d, c, r, sides, rng):
    """沿边画锯齿状碎裂线：深色裂缝 + 内侧亮棱。"""
    x0, y0 = c * CELL, r * CELL
    dark, lite = (26, 22, 19), (146, 132, 117)
    for s in sides:
        if s in ("T", "B"):
            y = y0 if s == "T" else y0 + CELL - 1
            dy = 1 if s == "T" else -1
            x = x0
            while x < x0 + CELL:
                seg = rng.randint(3, 7)
                jit = rng.randint(0, 2)
                d.line([(x, y), (min(x + seg, x0 + CELL - 1), y)], fill=dark, width=2)
                d.line([(x, y + dy * 3), (min(x + seg, x0 + CELL - 1), y + dy * 3)], fill=lite, width=1)
                if jit == 2:
                    d.line([(x, y), (x, y + dy * (2 + rng.randint(0, 3)))], fill=dark, width=1)
                x += seg
        else:
            x = x0 if s == "L" else x0 + CELL - 1
            dx = 1 if s == "L" else -1
            y = y0
            while y < y0 + CELL:
                seg = rng.randint(3, 7)
                jit = rng.randint(0, 2)
                d.line([(x, y), (x, min(y + seg, y0 + CELL - 1))], fill=dark, width=2)
                d.line([(x + dx * 3, y), (x + dx * 3, min(y + seg, y0 + CELL - 1))], fill=lite, width=1)
                if jit == 2:
                    d.line([(x, y), (x + dx * (2 + rng.randint(0, 3)), y)], fill=dark, width=1)
                y += seg


# ---- 已开层（所有面板一致，用真实地砖素材） ----

def paint_opened(img, brick_sheet):
    bs = Image.open(brick_sheet).convert("RGB")
    rng = random.Random(3)
    d = ImageDraw.Draw(img)
    for r in range(ROWS):
        for c in range(COLS):
            if not in_open(c, r):
                continue
            x0, y0 = c * CELL, r * CELL
            if (c, r) == VEIN:
                d.rectangle([x0, y0, x0 + CELL - 1, y0 + CELL - 1], fill=(168, 130, 40))
                continue
            col, row = rng.randint(0, 11), rng.randint(0, 11)
            blk = bs.crop((col * 80, row * 80, (col + 1) * 80, (row + 1) * 80)).resize((CELL, CELL), Image.NEAREST)
            img.paste(blk, (x0, y0))
    # 数字
    font = ImageFont.truetype(FONT_PATH, 15)
    for (c, r), (txt, color) in NUMBERS.items():
        x0, y0 = c * CELL, r * CELL
        bbox = d.textbbox((0, 0), txt, font=font)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        cx, cy = x0 + (CELL - tw) // 2 - bbox[0], y0 + (CELL - th) // 2 - bbox[1]
        d.text((cx + 1, cy + 1), txt, font=font, fill=(20, 14, 8))
        d.text((cx, cy), txt, font=font, fill=color)
    # 矿脉菱形
    font_v = ImageFont.truetype(FONT_PATH, 14)
    x0, y0 = VEIN[0] * CELL, VEIN[1] * CELL
    bbox = d.textbbox((0, 0), "◆", font=font_v)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    d.text((x0 + (CELL - tw) // 2 - bbox[0] + 1, y0 + (CELL - th) // 2 - bbox[1] + 1), "◆", font=font_v, fill=(60, 40, 10))
    d.text((x0 + (CELL - tw) // 2 - bbox[0], y0 + (CELL - th) // 2 - bbox[1]), "◆", font=font_v, fill=(255, 217, 102))


def paint_flag(img, style_img_for_base):
    """旗格：用该面板自己的未开底 + 旗。"""
    c, r = FLAG
    x0, y0 = c * CELL, r * CELL
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT_PATH, 14)
    bbox = d.textbbox((0, 0), "⚑", font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    d.text((x0 + (CELL - tw) // 2 - bbox[0] + 1, y0 + (CELL - th) // 2 - bbox[1] + 1), "⚑", font=font, fill=(40, 30, 8))
    d.text((x0 + (CELL - tw) // 2 - bbox[0], y0 + (CELL - th) // 2 - bbox[1]), "⚑", font=font, fill=(255, 204, 51))


# ---- 拼面板 ----

PANELS = [
    ("现状对照：每格一颗整齐小石头（你反馈不好看的）", "current"),
    ("方案A：连体岩壁——纹理跨格连续+挖开边缘碎裂（Dome Keeper式）", "A"),
    ("方案B：碎石堆——泥土底+随机散石（微软扫雷冒险模式式）", "B"),
    ("方案C：混合——连体岩壁+碎石+边缘凹陷阴影", "C"),
    ("方案D：纯色+明暗抖动（最小改动）", "D"),
]


def build_panel(kind, brick_sheet, wall):
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    rng = random.Random(100 if kind != "D" else 200)
    # 1) 未开底
    if kind == "current":
        paint_opened_under(img)  # 先铺开区，避免被岩壁盖掉
        paint_current(d, img, rng)
    elif kind == "A":
        paint_A(d, img, rng, wall)
    elif kind == "B":
        paint_B(d, img, rng)
    elif kind == "C":
        paint_C(d, img, rng, wall)
    else:
        paint_D(d, img, rng)
    # 2) 开区地砖/数字/矿脉（盖在底上）
    paint_opened(img, brick_sheet)
    # 3) 旗（画在该面板未开底之上）
    paint_flag(img, img)
    return img.resize((W * SCALE, H * SCALE), Image.NEAREST)


def paint_opened_under(img):
    pass  # 开区由 paint_opened 统一处理，占位


def main():
    brick_sheet = BRICK_SHEET_PATH
    wall = make_wall_texture(W, H, seed=42)
    font_title = ImageFont.truetype(FONT_PATH, 18)

    panel_h = H * SCALE + TITLE_H * SCALE
    total_w = W * SCALE + GAP * 2
    total_h = (panel_h + GAP) * len(PANELS) + GAP
    canvas = Image.new("RGB", (total_w, total_h), (24, 22, 20))

    y = GAP
    for title, kind in PANELS:
        td = ImageDraw.Draw(canvas)
        panel = build_panel(kind, brick_sheet, wall)
        canvas.paste(panel, (GAP, y + TITLE_H * SCALE))
        td.rectangle([GAP, y, GAP + W * SCALE - 1, y + TITLE_H * SCALE - 2], fill=(46, 42, 38))
        td.text((GAP + 10, y + 4 * SCALE - 2), title, font=font_title, fill=(240, 232, 216))
        y += panel_h + GAP

    canvas.save(OUT_PATH)
    print("saved", OUT_PATH, canvas.size)


if __name__ == "__main__":
    main()
