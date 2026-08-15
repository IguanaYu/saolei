#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
方案 A（连体岩壁）与方案 B（碎石堆）的变体扩展 mock。

- 同一大局面（20x12 格）：程序生成雷区 → 开区数字真实合理；
  含基地(蓝B)、矿脉(金◆)、坍塌(红✸)、旗(⚑)
- 方案 A 4 个色调变体：暖灰棕 / 铁锈红棕 / 冷岩灰 / 砂黄（同一纹理结构，只换色板）
- 方案 B 4 个变体：暖棕土 / 红土 / 深湿土 / 浅沙土（泥土+碎石配色/密度）
- 输出：mock_A_variants.png、mock_B_variants.png（各竖排 4 面板）
"""
import os
import random
from PIL import Image, ImageDraw, ImageFont

TMP = os.path.dirname(os.path.abspath(__file__))
BRICK_SHEET_PATH = os.path.join(TMP, "..", "assets", "tiles", "floor_bricks_sheet.png")
FONT_PATH = "C:/Windows/Fonts/msyh.ttc"

CELL = 28
COLS, ROWS = 20, 12
W, H = COLS * CELL, ROWS * CELL
SCALE = 2
TITLE_H = 28
GAP = 6

WALL_TEX_SIZE = 672  # 24 格周期，覆盖 20 格面板无重复

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


# ---------------- 连体岩壁（方案 A） ----------------

def make_wall_texture(size, lo, hi, seed=42, crack_dots=1400):
    n = fbm(size, [6, 12, 24, 48], seed)
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        row = n[y]
        for x in range(size):
            v = row[x]
            px[x, y] = (int(lerp(lo[0], hi[0], v)), int(lerp(lo[1], hi[1], v)), int(lerp(lo[2], hi[2], v)))
    rng = random.Random(seed + 9)
    for _ in range(crack_dots):
        x, y = rng.randrange(size), rng.randrange(size)
        r, g, b = px[x, y]
        px[x, y] = (max(0, r - 24), max(0, g - 24), max(0, b - 24))
    return img


def draw_cracked_edge(d, c, r, sides, rng):
    x0, y0 = c * CELL, r * CELL
    dark, lite = (24, 20, 17), (142, 128, 113)
    for s in sides:
        if s in ("T", "B"):
            y = y0 if s == "T" else y0 + CELL - 1
            dy = 1 if s == "T" else -1
            x = x0
            while x < x0 + CELL:
                seg = rng.randint(3, 7)
                xe = min(x + seg, x0 + CELL - 1)
                d.line([(x, y), (xe, y)], fill=dark, width=2)
                d.line([(x, y + dy * 3), (xe, y + dy * 3)], fill=lite, width=1)
                if rng.randint(0, 2) == 2:
                    d.line([(x, y), (x, y + dy * (2 + rng.randint(0, 3)))], fill=dark, width=1)
                x += seg
        else:
            x = x0 if s == "L" else x0 + CELL - 1
            dx = 1 if s == "L" else -1
            y = y0
            while y < y0 + CELL:
                seg = rng.randint(3, 7)
                ye = min(y + seg, y0 + CELL - 1)
                d.line([(x, y), (x, ye)], fill=dark, width=2)
                d.line([(x + dx * 3, y), (x + dx * 3, ye)], fill=lite, width=1)
                if rng.randint(0, 2) == 2:
                    d.line([(x, y), (x + dx * (2 + rng.randint(0, 3)), y)], fill=dark, width=1)
                y += seg


# ---------------- 局面（雷区真实数字） ----------------

def build_layout(seed=5):
    """返回 (open_set, mines, flags, vein, collapsed, base)。数字由邻雷数推出。"""
    rng = random.Random(seed)
    # 不规则开区：噪声阈值 + 中心偏置
    n = value_noise(max(COLS, ROWS) * 8, 24, seed + 77)  # 低频
    open_set = set()
    cx, cy = COLS / 2 - 1, ROWS / 2 - 1
    for r in range(ROWS):
        for c in range(COLS):
            v = n[(r * 8) % len(n)][(c * 8) % len(n)]
            dist = ((c - cx) / COLS) ** 2 + ((r - cy) / ROWS) ** 2
            if v - dist * 1.6 > 0.42:
                open_set.add((c, r))
    # 强制中心一块连通区（放基地）
    for c in range(7, 13):
        for r in range(4, 8):
            open_set.add((c, r))
    base = (10, 6)
    open_set.discard(base)
    collapsed = (11, 5)          # 基地旁一格坍塌（视为已开）
    open_set.discard(collapsed)
    vein = (13, 8)               # 矿脉在开区内
    open_set.discard(vein)
    # 雷只放在未开格
    closed = [(c, r) for c in range(COLS) for r in range(ROWS) if (c, r) not in open_set]
    mines = set(rng.sample(closed, 30))
    # 旗：挑 2 个靠近开区的雷
    near = [m for m in mines if any((m[0] + dc, m[1] + dr) in open_set for dc in (-1, 0, 1) for dr in (-1, 0, 1))]
    flags = set(rng.sample(near, min(2, len(near))))
    return open_set, mines, flags, vein, collapsed, base


def adjacent_mines(c, r, mines):
    return sum(1 for dc in (-1, 0, 1) for dr in (-1, 0, 1)
               if (dc or dr) and (c + dc, r + dr) in mines)


def edge_sides(c, r, open_like):
    sides = []
    for dc, dr, s in ((0, -1, "T"), (0, 1, "B"), (-1, 0, "L"), (1, 0, "R")):
        nc, nr = c + dc, r + dr
        if not (0 <= nc < COLS and 0 <= nr < ROWS) or (nc, nr) in open_like:
            sides.append(s)
    return sides


# ---------------- 已开层 ----------------

NUM_COLORS = {
    1: (51, 102, 255), 2: (0, 153, 51), 3: (230, 26, 26), 4: (128, 40, 178),
    5: (150, 84, 26), 6: (0, 153, 179), 7: (30, 30, 30), 8: (120, 120, 120),
}


def paint_opened(img, layout, brick_sheet, rng):
    open_set, mines, flags, vein, collapsed, base = layout
    open_like = open_set | {vein, collapsed, base}
    bs = Image.open(brick_sheet).convert("RGB")
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT_PATH, 15)
    for r in range(ROWS):
        for c in range(COLS):
            if (c, r) not in open_like or (c, r) in flags:
                continue
            x0, y0 = c * CELL, r * CELL
            if (c, r) == base:
                d.rectangle([x0, y0, x0 + CELL - 1, y0 + CELL - 1], fill=(38, 89, 192))
            elif (c, r) == vein:
                d.rectangle([x0, y0, x0 + CELL - 1, y0 + CELL - 1], fill=(168, 130, 40))
            elif (c, r) == collapsed:
                d.rectangle([x0, y0, x0 + CELL - 1, y0 + CELL - 1], fill=(102, 13, 13))
            else:
                col, row = rng.randint(0, 11), rng.randint(0, 11)
                blk = bs.crop((col * 80, row * 80, (col + 1) * 80, (row + 1) * 80)).resize((CELL, CELL), Image.NEAREST)
                img.paste(blk, (x0, y0))
    # 数字（开区内非特殊格）
    for (c, r) in open_set:
        n = adjacent_mines(c, r, mines)
        if n == 0:
            continue
        x0, y0 = c * CELL, r * CELL
        txt = str(n)
        bbox = d.textbbox((0, 0), txt, font=font)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        tx = x0 + (CELL - tw) // 2 - bbox[0]
        ty = y0 + (CELL - th) // 2 - bbox[1]
        d.text((tx + 1, ty + 1), txt, font=font, fill=(250, 244, 230))
        d.text((tx, ty), txt, font=font, fill=NUM_COLORS[n])
    # 图标格：基地/矿脉/坍塌/旗
    def icon(cell, ch, fill, shadow):
        x0, y0 = cell[0] * CELL, cell[1] * CELL
        bbox = d.textbbox((0, 0), ch, font=font)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        tx = x0 + (CELL - tw) // 2 - bbox[0]
        ty = y0 + (CELL - th) // 2 - bbox[1]
        d.text((tx + 1, ty + 1), ch, font=font, fill=shadow)
        d.text((tx, ty), ch, font=font, fill=fill)

    icon(base, "B", (255, 255, 255), (10, 24, 60))
    icon(vein, "◆", (255, 217, 102), (60, 40, 10))
    icon(collapsed, "✸", (255, 120, 120), (40, 5, 5))
    for f in flags:
        icon(f, "⚑", (255, 204, 51), (40, 30, 8))


# ---------------- 面板构建 ----------------

A_VARIANTS = [
    ("A1 暖灰棕（默认·暖色矿洞风）", (48, 43, 40), (125, 113, 101)),
    ("A2 铁锈红棕（铁矿层感）", (54, 38, 32), (138, 100, 78)),
    ("A3 冷岩灰（深层冷静感）", (44, 46, 50), (116, 122, 128)),
    ("A4 砂黄（浅层沙岩感）", (58, 49, 34), (140, 122, 86)),
]

B_VARIANTS = [
    ("B1 暖棕土+灰石（默认）", (74, 55, 36), (128, 98, 62), [(104, 94, 84), (88, 79, 70), (120, 108, 95)], 3),
    ("B2 红土+棕石（红土矿区）", (94, 52, 36), (146, 88, 58), [(112, 84, 66), (96, 70, 54), (128, 100, 78)], 3),
    ("B3 深湿土+灰石（深层湿暗）", (52, 44, 38), (96, 82, 66), [(96, 88, 80), (78, 71, 64), (108, 100, 90)], 4),
    ("B4 浅沙土+米石（浅层干燥）", (108, 90, 58), (158, 136, 94), [(150, 138, 118), (132, 120, 102), (166, 152, 130)], 2),
]


def build_panel_A(lo, hi, wall_tex, layout, brick_sheet, seed=100):
    img = Image.new("RGB", (W, H))
    img.paste(wall_tex.crop((0, 0, W, H)), (0, 0))
    d = ImageDraw.Draw(img)
    rng = random.Random(seed)
    open_set, mines, flags, vein, collapsed, base = layout
    open_like = open_set | {vein, collapsed, base}
    # 开区边缘凹陷阴影
    shade = Image.new("L", (W, H), 0)
    sd = ImageDraw.Draw(shade)
    for r in range(ROWS):
        for c in range(COLS):
            if (c, r) in open_like:
                continue
            x0, y0 = c * CELL, r * CELL
            for s in edge_sides(c, r, open_like):
                if s == "T":
                    sd.rectangle([x0, y0, x0 + CELL - 1, y0 + 4], fill=60)
                elif s == "B":
                    sd.rectangle([x0, y0 + CELL - 5, x0 + CELL - 1, y0 + CELL - 1], fill=80)
                elif s == "L":
                    sd.rectangle([x0, y0, x0 + 4, y0 + CELL - 1], fill=60)
                else:
                    sd.rectangle([x0 + CELL - 5, y0, x0 + CELL - 1, y0 + CELL - 1], fill=80)
    black = Image.new("RGB", (W, H), (16, 13, 11))
    img.paste(black, (0, 0), shade)
    # 碎裂描边
    for r in range(ROWS):
        for c in range(COLS):
            if (c, r) in open_like:
                continue
            sides = edge_sides(c, r, open_like)
            if sides:
                draw_cracked_edge(d, c, r, sides, rng)
    # 岩壁散碎石（低频，不形成每格模式）
    for r in range(ROWS):
        for c in range(COLS):
            if (c, r) in open_like or rng.random() >= 0.18:
                continue
            cx = c * CELL + rng.randint(3, CELL - 4)
            cy = r * CELL + rng.randint(3, CELL - 4)
            rw, rh = rng.randint(2, 4), rng.randint(2, 3)
            tone = rng.choice([(int(lerp(lo[0], hi[0], 1.0)) + 12,) * 3, (int(lo[0] * 0.9),) * 3]) if False else \
                rng.choice([(min(255, hi[0] + 10), min(255, hi[1] + 8), min(255, hi[2] + 8)),
                            (int(lo[0] * 0.92), int(lo[1] * 0.92), int(lo[2] * 0.92))])
            d.ellipse([cx - rw, cy - rh, cx + rw, cy + rh], fill=tone)
    paint_opened(img, layout, brick_sheet, random.Random(3))
    return img


def build_panel_B(soil_lo, soil_hi, stone_tones, stones_per, layout, brick_sheet, seed=200):
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    rng = random.Random(seed)
    open_set, mines, flags, vein, collapsed, base = layout
    open_like = open_set | {vein, collapsed, base}
    # 泥土底（跨格连续的颗粒感）
    n = fbm(672, [48, 96], seed + 5)
    px = img.load()
    for y in range(H):
        row = n[y % 672]
        for x in range(W):
            v = row[x % 672]
            j = 0.9 + 0.2 * v
            px[x, y] = (int(lerp(soil_lo[0], soil_hi[0], v) * j),
                        int(lerp(soil_lo[1], soil_hi[1], v) * j),
                        int(lerp(soil_lo[2], soil_hi[2], v) * j))
    # 未开格散碎石
    for r in range(ROWS):
        for c in range(COLS):
            if (c, r) in open_like:
                continue
            for _ in range(rng.randint(max(1, stones_per - 1), stones_per + 1)):
                cx = c * CELL + rng.randint(4, CELL - 5)
                cy = r * CELL + rng.randint(4, CELL - 5)
                rw, rh = rng.randint(2, 5), rng.randint(2, 4)
                tone = rng.choice(stone_tones)
                d.ellipse([cx - rw, cy - rh, cx + rw, cy + rh], fill=tone, outline=(int(tone[0] * 0.55), int(tone[1] * 0.55), int(tone[2] * 0.55)))
                d.point((cx - rw + 1, cy - rh + 1), fill=(min(255, tone[0] + 40), min(255, tone[1] + 40), min(255, tone[2] + 40)))
    paint_opened(img, layout, brick_sheet, random.Random(3))
    return img


def stack(panels, out_path):
    font_title = ImageFont.truetype(FONT_PATH, 17)
    panel_h = H * SCALE + TITLE_H * SCALE
    total_w = W * SCALE + GAP * 2
    total_h = (panel_h + GAP) * len(panels) + GAP
    canvas = Image.new("RGB", (total_w, total_h), (24, 22, 20))
    y = GAP
    for title, pil in panels:
        td = ImageDraw.Draw(canvas)
        canvas.paste(pil.resize((W * SCALE, H * SCALE), Image.NEAREST), (GAP, y + TITLE_H * SCALE))
        td.rectangle([GAP, y, GAP + W * SCALE - 1, y + TITLE_H * SCALE - 2], fill=(46, 42, 38))
        td.text((GAP + 10, y + 3 * SCALE), title, font=font_title, fill=(240, 232, 216))
        y += panel_h + GAP
    canvas.save(out_path)
    print("saved", out_path, canvas.size)


def main():
    layout = build_layout(seed=5)
    brick_sheet = BRICK_SHEET_PATH

    a_panels = []
    for i, (title, lo, hi) in enumerate(A_VARIANTS):
        wall = make_wall_texture(WALL_TEX_SIZE, lo, hi, seed=42 + i * 1000 if i else 42)
        a_panels.append((title, build_panel_A(lo, hi, wall, layout, brick_sheet)))
    stack(a_panels, os.path.join(TMP, "mock_A_variants.png"))

    b_panels = []
    for i, (title, slo, shi, tones, sp) in enumerate(B_VARIANTS):
        b_panels.append((title, build_panel_B(slo, shi, tones, sp, layout, brick_sheet, seed=200 + i)))
    stack(b_panels, os.path.join(TMP, "mock_B_variants.png"))


if __name__ == "__main__":
    main()
