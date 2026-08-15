#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
素材包 2：C 系混合岩壁 + 洞底变体 + 特殊格贴图 + 岩壁装饰散件。

输出（assets/tiles/）：
  wall_C1..C4.png   C 系混合岩壁（连体 fbm 岩壁 + 均匀散碎石，336 无缝）
  floor_cool.png    冷灰洞底（配 A3/C3）
  floor_red.png     红棕洞底（配 A2/B2/C2）
  special_vein.png      矿脉格：暗岩底 + 金色晶簇（不透明 28x28）
  special_collapse.png  坍塌格：暗底 + 放射红裂纹（不透明 28x28）
  special_base.png      基地格：深蓝金属底座（不透明 28x28）
  special_flag.png      像素小旗（透明底 28x28，叠在岩壁上）
  deco_sheet.png    装饰散件 4x2 格（透明底 112x56，每件 28x28）
预览（tmp/mock_assets_pack2.png）：C 系大局面 x4 + 洞底对比 + 素材特写
"""
import os
import random
from PIL import Image, ImageDraw, ImageFont

TMP = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(TMP, "..", "assets", "tiles")
FONT_PATH = "C:/Windows/Fonts/msyh.ttc"
SIZE = 336
CELL = 28


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


def noise_img(size, grids, seed, lo, hi, jitter=None):
    n = fbm(size, grids, seed)
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        row = n[y]
        for x in range(size):
            v = row[x]
            j = 1.0
            if jitter:
                j = jitter[0] + (jitter[1] - jitter[0]) * v
            px[x, y] = (int(lerp(lo[0], hi[0], v) * j),
                        int(lerp(lo[1], hi[1], v) * j),
                        int(lerp(lo[2], hi[2], v) * j))
    return img


# ---------------- C 系：连体岩壁 + 均匀散碎石 ----------------

C_STYLES = [
    ("C1", (48, 43, 40), (125, 113, 101), 5042),   # 暖灰棕
    ("C2", (54, 38, 32), (138, 100, 78), 6042),    # 铁锈红棕
    ("C3", (44, 46, 50), (116, 122, 128), 7042),   # 冷岩灰
    ("C4", (58, 49, 34), (140, 122, 86), 8042),    # 砂黄
]


def gen_wall_C(name, lo, hi, seed):
    img = noise_img(SIZE, [6, 12, 24, 48], seed, lo, hi)
    px = img.load()
    rng = random.Random(seed + 9)
    for _ in range(1400):  # 裂纹暗点
        x, y = rng.randrange(SIZE), rng.randrange(SIZE)
        r, g, b = px[x, y]
        px[x, y] = (max(0, r - 24), max(0, g - 24), max(0, b - 24))
    d = ImageDraw.Draw(img)
    lite = (min(255, hi[0] + 14), min(255, hi[1] + 12), min(255, hi[2] + 10))
    dark = (int(lo[0] * 0.88), int(lo[1] * 0.88), int(lo[2] * 0.88))
    for _ in range(120):  # 均匀散碎石（非逐格，避免网格模式）
        cx, cy = rng.randrange(SIZE), rng.randrange(SIZE)
        rw, rh = rng.randint(2, 4), rng.randint(2, 3)
        tone = rng.choice([lite, dark])
        for oy in (-SIZE, 0, SIZE):
            for ox in (-SIZE, 0, SIZE):
                d.ellipse([cx + ox - rw, cy + oy - rh, cx + ox + rw, cy + oy + rh], fill=tone)
    img.save(os.path.join(OUT_DIR, f"wall_{name}.png"))
    print("saved wall_" + name)


# ---------------- 洞底变体 ----------------

def gen_floor(name, lo, hi, seed):
    img = noise_img(SIZE, [24, 48], seed, lo, hi)
    px = img.load()
    rng = random.Random(seed + 1)
    for _ in range(420):
        x, y = rng.randrange(SIZE), rng.randrange(SIZE)
        r, g, b = px[x, y]
        px[x, y] = (min(255, r + 24), min(255, g + 22), min(255, b + 16))
    for _ in range(260):
        x, y = rng.randrange(SIZE), rng.randrange(SIZE)
        r, g, b = px[x, y]
        px[x, y] = (max(0, r - 14), max(0, g - 14), max(0, b - 14))
    img.save(os.path.join(OUT_DIR, f"{name}.png"))
    print("saved " + name)


# ---------------- 特殊格贴图 ----------------

def gen_special_vein():
    img = noise_img(CELL, [6, 12], 91, (38, 34, 30), (78, 70, 62)).convert("RGBA")
    d = ImageDraw.Draw(img)
    rng = random.Random(92)
    gold, gold_d, hl = (255, 209, 102), (158, 108, 30), (255, 245, 200)
    spots = [(8, 9), (17, 7), (13, 17), (20, 16), (6, 19)]
    for i, (cx, cy) in enumerate(spots):
        s = 3 if i % 2 == 0 else 2
        d.polygon([(cx, cy - s), (cx + s, cy), (cx, cy + s), (cx - s, cy)], fill=gold, outline=gold_d)
        d.point((cx, cy - s + 1), fill=hl)
    img.save(os.path.join(OUT_DIR, "special_vein.png"))
    print("saved special_vein")


def gen_special_collapse():
    img = noise_img(CELL, [8, 16], 93, (26, 18, 15), (58, 42, 34)).convert("RGBA")
    d = ImageDraw.Draw(img)
    rng = random.Random(94)
    cx, cy = 14, 14
    d.ellipse([cx - 7, cy - 7, cx + 7, cy + 7], fill=(96, 26, 22))
    d.ellipse([cx - 4, cy - 4, cx + 4, cy + 4], fill=(140, 40, 32))
    for _ in range(7):  # 放射裂纹
        ang = rng.uniform(0, 6.28)
        x, y = float(cx), float(cy)
        for _step in range(4):
            nx = x + (rng.uniform(2, 5)) * -(-1.0)  # placeholder replaced below
            import math
            nx = x + rng.uniform(2.2, 4.5) * math.cos(ang + rng.uniform(-0.5, 0.5))
            ny = y + rng.uniform(2.2, 4.5) * math.sin(ang + rng.uniform(-0.5, 0.5))
            d.line([(x, y), (nx, ny)], fill=(52, 10, 8), width=1)
            x, y = nx, ny
    for _ in range(5):  # 掉落碎石
        sx, sy = rng.randint(3, 24), rng.randint(3, 24)
        r = rng.randint(1, 2)
        d.ellipse([sx - r, sy - r, sx + r, sy + r], fill=(70, 52, 42))
    img.save(os.path.join(OUT_DIR, "special_collapse.png"))
    print("saved special_collapse")


def gen_special_base():
    img = Image.new("RGBA", (CELL, CELL), (26, 44, 84, 255))
    d = ImageDraw.Draw(img)
    d.rectangle([1, 1, 26, 26], fill=(34, 62, 118))
    d.rectangle([3, 3, 24, 24], fill=(52, 96, 172))
    d.rectangle([5, 5, 22, 22], fill=(40, 76, 140))
    # 中心核心
    d.ellipse([9, 9, 18, 18], fill=(120, 190, 255))
    d.ellipse([11, 11, 16, 16], fill=(210, 240, 255))
    # 四角铆钉
    for rx, ry in [(4, 4), (23, 4), (4, 23), (23, 23)]:
        d.ellipse([rx - 1, ry - 1, rx + 1, ry + 1], fill=(150, 170, 200))
        d.point((rx, ry), fill=(220, 232, 250))
    # 顶部高光线
    d.line([(3, 3), (24, 3)], fill=(90, 140, 210))
    img.save(os.path.join(OUT_DIR, "special_base.png"))
    print("saved special_base")


def gen_special_flag():
    img = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # 杆
    d.line([(13, 6), (13, 22)], fill=(120, 84, 48), width=2)
    d.point((13, 6), fill=(170, 130, 80))
    # 旗面（红，带波动缺口）
    d.polygon([(14, 6), (23, 8), (20, 11), (23, 14), (14, 13)], fill=(224, 58, 48))
    d.polygon([(14, 6), (18, 7), (14, 10)], fill=(255, 120, 100))
    # 底部小石堆
    d.ellipse([8, 21, 13, 24], fill=(96, 86, 76))
    d.ellipse([14, 22, 19, 25], fill=(110, 99, 88))
    img.save(os.path.join(OUT_DIR, "special_flag.png"))
    print("saved special_flag")


# ---------------- 装饰散件 sheet（4x2 格，透明底） ----------------

def deco_crystal(d, ox, oy):
    for cx, h, w, col, edge in [(13, 10, 2, (108, 176, 255), (48, 92, 176)),
                                 (8, 6, 1, (88, 150, 230), (40, 80, 160)),
                                 (18, 7, 1, (128, 190, 255), (56, 104, 190))]:
        d.polygon([(ox + cx - w, oy + 22), (ox + cx, oy + 22 - h), (ox + cx + w, oy + 22)],
                  fill=col, outline=edge)
        d.point((ox + cx, oy + 22 - h + 2), fill=(230, 245, 255))


def deco_mushroom(d, ox, oy):
    # 两只蘑菇
    for mx, s in [(10, 1), (18, 2)]:
        base_y = oy + 22
        d.rectangle([ox + mx - 1, base_y - 4 * s // 2 - 2, ox + mx + 1, base_y], fill=(150, 120, 84))
        d.ellipse([ox + mx - 4 * s, base_y - 4 * s - 3, ox + mx + 4 * s, base_y - 3], fill=(74, 150, 78))
        d.point((ox + mx - 1, base_y - 4 * s - 1), fill=(160, 220, 160))


def deco_rock_pile(d, ox, oy):
    d.ellipse([ox + 6, oy + 17, ox + 13, oy + 23], fill=(104, 94, 84))
    d.ellipse([ox + 14, oy + 19, ox + 21, oy + 24], fill=(92, 82, 73))
    d.ellipse([ox + 10, oy + 12, ox + 17, oy + 18], fill=(118, 106, 94))
    d.point((ox + 11, oy + 13), fill=(150, 138, 122))


def deco_gold(d, ox, oy):
    for gx, gy in [(9, 14), (14, 11), (18, 16), (12, 19)]:
        d.point((gx + ox, gy + oy), fill=(255, 209, 102))
        d.point((gx + ox + 1, gy + oy), fill=(200, 150, 50))
        d.point((gx + ox, gy + oy + 1), fill=(200, 150, 50))


def deco_roots(d, ox, oy):
    for sx in (7, 14, 20):
        y = oy
        x = ox + sx
        while y < oy + 14 + (sx % 3) * 3:
            d.point((x, y), fill=(96, 74, 50))
            y += 1
            if y % 4 == 0:
                x += random.choice([-1, 0, 1])
        d.point((x, y), fill=(70, 54, 36))


def deco_web(d, ox, oy):
    web = (235, 235, 235, 150)
    for r in (4, 8, 12):
        d.arc([ox, oy, ox + r * 2, oy + r * 2], 0, 90, fill=web)
    for ang_line in [(0, 0, 12, 12), (0, 0, 12, 4), (0, 0, 4, 12)]:
        d.line([ox + ang_line[0], oy + ang_line[1], ox + ang_line[2], oy + ang_line[3]], fill=web)


def deco_torch(d, ox, oy):
    d.line([(ox + 13, oy + 9), (ox + 13, oy + 23)], fill=(122, 82, 46), width=2)
    d.ellipse([ox + 10, oy + 3, ox + 16, oy + 10], fill=(240, 140, 40))
    d.ellipse([ox + 11, oy + 5, ox + 15, oy + 9], fill=(255, 210, 80))
    d.point((ox + 13, oy + 6), fill=(255, 250, 200))


def deco_moss(d, ox, oy):
    m = (74, 128, 66, 200), (92, 150, 78, 190)
    d.ellipse([ox + 5, oy + 19, ox + 14, oy + 24], fill=m[0])
    d.ellipse([ox + 15, oy + 21, ox + 22, oy + 25], fill=m[1])
    d.point((ox + 8, oy + 20), fill=(140, 200, 120))


DECOS = [deco_crystal, deco_mushroom, deco_rock_pile, deco_gold,
         deco_roots, deco_web, deco_torch, deco_moss]
DECO_NAMES = ["蓝晶簇", "蘑菇", "石堆", "金矿露头", "垂根须", "蛛网", "火把", "苔藓"]


def gen_deco_sheet():
    img = Image.new("RGBA", (CELL * 4, CELL * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i, fn in enumerate(DECOS):
        ox, oy = (i % 4) * CELL, (i // 4) * CELL
        fn(d, ox, oy)
    img.save(os.path.join(OUT_DIR, "deco_sheet.png"))
    print("saved deco_sheet")


# ---------------- 预览图 ----------------
# 复用素材包 1 的局面结构：开区 blob + 雷区数字 + 旗/矿脉/坍塌/基地

PREV_COLS, PREV_ROWS = 20, 12


def build_layout(seed=5):
    rng = random.Random(seed)
    n = value_noise(max(PREV_COLS, PREV_ROWS) * 8, 24, seed + 77)
    open_set = set()
    cx, cy = PREV_COLS / 2 - 1, PREV_ROWS / 2 - 1
    for r in range(PREV_ROWS):
        for c in range(PREV_COLS):
            v = n[(r * 8) % len(n)][(c * 8) % len(n)]
            dist = ((c - cx) / PREV_COLS) ** 2 + ((r - cy) / PREV_ROWS) ** 2
            if v - dist * 1.6 > 0.42:
                open_set.add((c, r))
    for c in range(7, 13):
        for r in range(4, 8):
            open_set.add((c, r))
    base = (10, 6)
    open_set.discard(base)
    collapsed = (11, 5)
    open_set.discard(collapsed)
    vein = (13, 8)
    open_set.discard(vein)
    closed = [(c, r) for c in range(PREV_COLS) for r in range(PREV_ROWS) if (c, r) not in open_set]
    mines = set(rng.sample(closed, 30))
    near = [m for m in mines if any((m[0] + dc, m[1] + dr) in open_set for dc in (-1, 0, 1) for dr in (-1, 0, 1))]
    flags = set(rng.sample(near, min(2, len(near))))
    return open_set, mines, flags, vein, collapsed, base


def tile_texture(tex, w, h):
    out = Image.new("RGB", (w, h))
    tw, th = tex.size
    for y in range(0, h, th):
        for x in range(0, w, tw):
            out.paste(tex, (x, y))
    return out


def render_scene(wall_tex, floor_tex, layout, deco_tex, deco_rate=0.12, seed=300):
    Wp, Hp = PREV_COLS * CELL, PREV_ROWS * CELL
    img = tile_texture(wall_tex, Wp, Hp).convert("RGBA")
    d = ImageDraw.Draw(img)
    rng = random.Random(seed)
    open_set, mines, flags, vein, collapsed, base = layout
    open_like = open_set | {vein, collapsed, base}

    # 洞底（随机取块）+ 数字
    font = ImageFont.truetype(FONT_PATH, 15)
    for (c, r) in open_set:
        x0, y0 = c * CELL, r * CELL
        col, row = rng.randint(0, 11), rng.randint(0, 11)
        blk = floor_tex.crop((col * 28, row * 28, (col + 1) * 28, (row + 1) * 28))
        img.paste(blk, (x0, y0))
    for (c, r) in open_set:
        n = sum(1 for dc in (-1, 0, 1) for dr in (-1, 0, 1)
                if (dc or dr) and (c + dc, r + dr) in mines)
        if n == 0:
            continue
        colors = {1: (51,102,255),2:(0,153,51),3:(230,26,26),4:(128,40,178),5:(150,84,26),6:(0,153,179),7:(30,30,30),8:(120,120,120)}
        x0, y0 = c * CELL, r * CELL
        txt = str(n)
        bbox = d.textbbox((0, 0), txt, font=font)
        tw, th = bbox[2]-bbox[0], bbox[3]-bbox[1]
        d.text((x0+(CELL-tw)//2-bbox[0]+1, y0+(CELL-th)//2-bbox[1]+1), txt, font=font, fill=(250,244,230))
        d.text((x0+(CELL-tw)//2-bbox[0], y0+(CELL-th)//2-bbox[1]), txt, font=font, fill=colors[n])

    # 特殊格贴图
    for cell, fname in [(vein, "special_vein.png"), (collapsed, "special_collapse.png"), (base, "special_base.png")]:
        sp = Image.open(os.path.join(OUT_DIR, fname)).convert("RGBA")
        img.paste(sp, (cell[0]*CELL, cell[1]*CELL), sp)
    # 旗贴图
    for f in flags:
        sp = Image.open(os.path.join(OUT_DIR, "special_flag.png")).convert("RGBA")
        img.paste(sp, (f[0]*CELL, f[1]*CELL), sp)

    # 岩壁装饰散件
    for r in range(PREV_ROWS):
        for c in range(PREV_COLS):
            if (c, r) in open_like or (c, r) in flags:
                continue
            if rng.random() < deco_rate:
                i = rng.randrange(8)
                piece = deco_tex.crop(((i % 4) * CELL, (i // 4) * CELL, (i % 4) * CELL + CELL, (i // 4) * CELL + CELL))
                img.paste(piece, (c * CELL, r * CELL), piece)

    # 挖开边缘碎裂（素材包1同款简化）
    dark, lite = (24, 20, 17, 235), (142, 128, 113, 200)
    for r in range(PREV_ROWS):
        for c in range(PREV_COLS):
            if (c, r) in open_like:
                continue
            x0, y0 = c * CELL, r * CELL
            for dc, dr, s in ((0,-1,"T"),(0,1,"B"),(-1,0,"L"),(1,0,"R")):
                nc, nr = c+dc, r+dr
                if 0 <= nc < PREV_COLS and 0 <= nr < PREV_ROWS and (nc, nr) not in open_like:
                    continue
                if s in ("T", "B"):
                    y = y0 if s == "T" else y0 + CELL - 1
                    dy = 1 if s == "T" else -1
                    x = x0
                    while x < x0 + CELL:
                        seg = rng.randint(3, 7)
                        xe = min(x + seg, x0 + CELL - 1)
                        d.line([(x, y), (xe, y)], fill=dark, width=2)
                        d.line([(x, y+dy*3), (xe, y+dy*3)], fill=lite, width=1)
                        x += seg
                else:
                    x = x0 if s == "L" else x0 + CELL - 1
                    dx = 1 if s == "L" else -1
                    y = y0
                    while y < y0 + CELL:
                        seg = rng.randint(3, 7)
                        ye = min(y + seg, y0 + CELL - 1)
                        d.line([(x, y), (x, ye)], fill=dark, width=2)
                        d.line([(x+dx*3, y), (x+dx*3, ye)], fill=lite, width=1)
                        y += seg
    return img.convert("RGB")


def build_preview():
    layout = build_layout()
    font_title = ImageFont.truetype(FONT_PATH, 17)
    font_small = ImageFont.truetype(FONT_PATH, 14)
    SCALE = 2
    Wp, Hp = PREV_COLS * CELL * SCALE, PREV_ROWS * CELL * SCALE
    TITLE_H = 30
    GAP = 6
    panels = []
    deco_tex = Image.open(os.path.join(OUT_DIR, "deco_sheet.png")).convert("RGBA")
    for name, _lo, _hi, _seed in C_STYLES:
        wall = Image.open(os.path.join(OUT_DIR, f"wall_{name}.png")).convert("RGB")
        floor = Image.open(os.path.join(OUT_DIR, "floor_dark.png")).convert("RGB")
        titles = {"C1": "C1 暖灰棕·混合（岩壁+碎石）", "C2": "C2 铁锈红棕·混合",
                  "C3": "C3 冷岩灰·混合", "C4": "C4 砂黄·混合"}
        scene = render_scene(wall, floor, layout, deco_tex).resize((Wp, Hp), Image.NEAREST)
        panels.append((titles[name], scene))
    # 洞底对比（C1 岩壁 + 三种洞底）
    wall = Image.open(os.path.join(OUT_DIR, "wall_C1.png")).convert("RGB")
    for fname, tname in [("floor_dark.png", "洞底：暗沙（现用）"),
                         ("floor_cool.png", "洞底：冷灰（配 A3/C3）"),
                         ("floor_red.png", "洞底：红棕（配 A2/B2/C2）")]:
        floor = Image.open(os.path.join(OUT_DIR, fname)).convert("RGB")
        scene = render_scene(wall, floor, layout, deco_tex).resize((Wp, Hp), Image.NEAREST)
        panels.append((tname, scene))
    # 素材特写条
    sw = 112
    strip = Image.new("RGB", (sw * 13, 132), (52, 48, 44))
    sd = ImageDraw.Draw(strip)
    items = [("special_vein.png", "矿脉"), ("special_collapse.png", "坍塌"), ("special_base.png", "基地"),
             ("special_flag.png", "旗")] + [(f"deco_{i}", DECO_NAMES[i]) for i in range(8)]
    for i, (fname, label) in enumerate(items):
        x = 4 + i * sw
        if fname.startswith("deco_"):
            idx = int(fname.split("_")[1])
            piece = deco_tex.crop(((idx % 4) * CELL, (idx // 4) * CELL, (idx % 4) * CELL + CELL, (idx // 4) * CELL + CELL))
        else:
            piece = Image.open(os.path.join(OUT_DIR, fname)).convert("RGBA")
        big = piece.resize((112, 112), Image.NEAREST)
        strip.paste(big, (x, 4), big)
        sd.text((x + 4, 116), label, font=font_small, fill=(235, 228, 210))
    strip = strip.resize((strip.width * 2, strip.height * 2), Image.NEAREST)
    panels.append(("特殊格贴图 + 装饰散件（放大特写）", strip))

    # 拼合
    total_w = panels[0][1].width + GAP * 2
    total_h = sum(p.height + TITLE_H + GAP for _, p in panels) + GAP
    canvas = Image.new("RGB", (total_w, total_h), (24, 22, 20))
    y = GAP
    for title, pil in panels:
        td = ImageDraw.Draw(canvas)
        canvas.paste(pil, (GAP, y + TITLE_H))
        td.rectangle([GAP, y, GAP + pil.width - 1, y + TITLE_H - 2], fill=(46, 42, 38))
        td.text((GAP + 10, y + 4), title, font=font_title, fill=(240, 232, 216))
        y += pil.height + TITLE_H + GAP
    out = os.path.join(TMP, "mock_assets_pack2.png")
    canvas.save(out)
    print("saved", out, canvas.size)


if __name__ == "__main__":
    for name, lo, hi, seed in C_STYLES:
        gen_wall_C(name, lo, hi, seed)
    gen_floor("floor_cool", (36, 38, 42), (66, 70, 76), 171)
    gen_floor("floor_red", (46, 32, 26), (88, 62, 46), 271)
    gen_special_vein()
    gen_special_collapse()
    gen_special_base()
    gen_special_flag()
    gen_deco_sheet()
    build_preview()
