#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
素材包 3：10 套主题岩壁（D1-D10），每套 = 主题岩壁 + 配套洞底。

主题不只是换色板，各有专属细节层（wrap-safe，全部 336 无缝）：
  D1 深渊黑岩  近黑+紫微光      D2 冰川蓝岩  冷蓝+冰白高光斑
  D3 熔渣岩    暗岩+橙岩浆裂纹  D4 翡翠矿层  深绿+翠宝石点
  D5 紫晶洞    紫罗兰+晶光点    D6 白垩骨岩  米白+灰纹条带
  D7 沼泽湿泥  暗绿棕+湿亮斑    D8 焦黑煤层  黑+碳光条带
  D9 珊瑚暖窟  粉橙+珊瑚斑点    D10 星陨岩   深蓝黑+白星点

输出：assets/tiles/wall_D1..D10.png + floor_D1..D10.png
预览：tmp/mock_D_styles.png（2 列 10 面板，复用 pack2 的场面渲染）
"""
import os
import random
from PIL import Image, ImageDraw, ImageFont

import gen_assets_pack2 as pk2  # 复用噪声/场面渲染

TMP = pk2.TMP
OUT_DIR = pk2.OUT_DIR
SIZE = 336


# ---------------- 装饰层（全部 wrap-safe） ----------------

def nine(draw_fn, x, y):
    for oy in (-SIZE, 0, SIZE):
        for ox in (-SIZE, 0, SIZE):
            draw_fn(x + ox, y + oy)


def decor_sparks(d, rng, color, count, cross_ratio=0.08):
    """亮星点：1px 点，少量画十字星"""
    def draw(x, y):
        d.point((x, y), fill=color)
        if rng.random() < cross_ratio:
            for dx, dy in ((0, -1), (0, 1), (-1, 0), (1, 0)):
                d.point((x + dx, y + dy), fill=color)
    for _ in range(count):
        nine(draw, rng.randrange(SIZE), rng.randrange(SIZE))


def decor_spots(d, rng, color, count, r_lo, r_hi):
    """柔斑（椭圆）"""
    def draw(x, y):
        rw, rh = rng.randint(r_lo, r_hi), rng.randint(r_lo, r_hi)
        d.ellipse([x - rw, y - rh, x + rw, y + rh], fill=color)
    for _ in range(count):
        nine(draw, rng.randrange(SIZE), rng.randrange(SIZE))


def decor_lava_cracks(d, rng, count):
    """岩浆裂纹：先暗橙晕再亮橙芯"""
    glow, core = (168, 56, 18), (255, 140, 48)
    for _ in range(count):
        x, y = float(rng.randrange(SIZE)), float(rng.randrange(SIZE))
        ang = rng.uniform(0, 6.283)
        pts_g, pts_c = [(x, y)], [(x, y)]
        for _seg in range(rng.randint(3, 6)):
            import math
            ang += rng.uniform(-0.8, 0.8)
            x += rng.uniform(4, 9) * math.cos(ang)
            y += rng.uniform(4, 9) * math.sin(ang)
            pts_g.append((x, y))
            pts_c.append((x, y))
        for off in (-SIZE, 0, SIZE):
            d.line([(px + off, py + off) for px, py in pts_g], fill=glow, width=2)
            d.line([(px + off, py + off) for px, py in pts_c], fill=core, width=1)


def decor_stripes(d, rng, color, count):
    """断续水平条带（左右天然无缝，避开上下边界 6px）"""
    for _ in range(count):
        y = rng.randint(8, SIZE - 9)
        x = 0
        while x < SIZE:
            seg = rng.randint(20, 70)
            gap = rng.randint(6, 30)
            d.line([(x, y), (min(x + seg, SIZE - 1), y)], fill=color, width=1)
            x += seg + gap


def decor_rubble(d, rng, lite, dark, count):
    """碎石（C 系同款）"""
    def draw(x, y):
        rw, rh = rng.randint(2, 4), rng.randint(2, 3)
        tone = rng.choice([lite, dark])
        d.ellipse([x - rw, y - rh, x + rw, y + rh], fill=tone)
    for _ in range(count):
        nine(draw, rng.randrange(SIZE), rng.randrange(SIZE))


def decor_crack_dots(px, rng, count, delta):
    """暗色噪点（A 系同款）"""
    for _ in range(count):
        x, y = rng.randrange(SIZE), rng.randrange(SIZE)
        r, g, b = px[x, y]
        px[x, y] = (max(0, r + delta), max(0, g + delta), max(0, b + delta))


# ---------------- 10 套主题 ----------------
# (编号, 名, wall lo, wall hi, floor lo, floor hi, seed, 装饰函数列表)
def R(rgb, k):
    return tuple(int(c * k) for c in rgb)

THEMES = [
    ("D1", "深渊黑岩", (18, 16, 20), (64, 58, 66)),
    ("D2", "冰川蓝岩", (44, 64, 88), (150, 190, 220)),
    ("D3", "熔渣岩",   (34, 26, 24), (98, 74, 62)),
    ("D4", "翡翠矿层", (22, 44, 34), (96, 150, 110)),
    ("D5", "紫晶洞",   (40, 30, 58), (128, 100, 170)),
    ("D6", "白垩骨岩", (86, 82, 72), (190, 184, 168)),
    ("D7", "沼泽湿泥", (30, 36, 26), (92, 104, 70)),
    ("D8", "焦黑煤层", (14, 14, 16), (56, 54, 52)),
    ("D9", "珊瑚暖窟", (94, 54, 52), (210, 140, 120)),
    ("D10", "星陨岩",  (16, 18, 34), (58, 64, 96)),
]


def apply_theme_decor(name, img, seed):
    d = ImageDraw.Draw(img)
    px = img.load()
    rng = random.Random(seed + 7)
    lite = tuple(min(255, c + 14) for c in img.getpixel((5, 5)))
    dark = tuple(int(c * 0.86) for c in img.getpixel((200, 200)))
    decor_crack_dots(px, rng, 1300, -22)
    if name == "D1":
        decor_sparks(d, rng, (150, 110, 190), 26)
        decor_rubble(d, rng, lite, dark, 60)
    elif name == "D2":
        decor_spots(d, rng, (222, 240, 252), 34, 1, 3)
        decor_rubble(d, rng, lite, dark, 70)
    elif name == "D3":
        decor_lava_cracks(d, rng, 22)
        decor_rubble(d, rng, lite, dark, 60)
    elif name == "D4":
        decor_sparks(d, rng, (110, 230, 150), 34)
        decor_spots(d, rng, (60, 140, 96), 26, 1, 2)
        decor_rubble(d, rng, lite, dark, 50)
    elif name == "D5":
        decor_sparks(d, rng, (216, 180, 255), 40)
        decor_spots(d, rng, (92, 66, 140), 24, 1, 2)
        decor_rubble(d, rng, lite, dark, 50)
    elif name == "D6":
        decor_stripes(d, rng, (150, 144, 130), 16)
        decor_stripes(d, rng, (120, 114, 102), 12)
        decor_rubble(d, rng, lite, dark, 60)
    elif name == "D7":
        decor_spots(d, rng, (58, 82, 46), 30, 2, 4)
        decor_sparks(d, rng, (150, 190, 120), 22)
        decor_rubble(d, rng, lite, dark, 60)
    elif name == "D8":
        decor_stripes(d, rng, (92, 90, 88), 18)
        decor_sparks(d, rng, (170, 168, 164), 20)
        decor_rubble(d, rng, lite, dark, 40)
    elif name == "D9":
        decor_spots(d, rng, (246, 190, 170), 30, 1, 3)
        decor_spots(d, rng, (180, 100, 88), 22, 1, 2)
        decor_rubble(d, rng, lite, dark, 50)
    elif name == "D10":
        decor_sparks(d, rng, (235, 240, 255), 46, cross_ratio=0.3)
        decor_sparks(d, rng, (150, 170, 230), 30, cross_ratio=0.15)
        decor_rubble(d, rng, lite, dark, 50)


def gen_theme(name, title, wlo, whi, seed):
    img = pk2.noise_img(SIZE, [6, 12, 24, 48], seed, wlo, whi)
    apply_theme_decor(name, img, seed)
    img.save(os.path.join(OUT_DIR, f"wall_{name}.png"))
    # 配套洞底：色板压暗（lo*0.78, hi*0.56）→ 一定比岩壁暗
    flo, fhi = R(wlo, 0.78), R(whi, 0.56)
    floor = pk2.noise_img(SIZE, [24, 48], seed + 500, flo, fhi)
    fpx = floor.load()
    rng = random.Random(seed + 501)
    pk2_style_grains = None
    for _ in range(380):
        x, y = rng.randrange(SIZE), rng.randrange(SIZE)
        r, g, b = fpx[x, y]
        fpx[x, y] = (min(255, r + 20), min(255, g + 18), min(255, b + 14))
    for _ in range(240):
        x, y = rng.randrange(SIZE), rng.randrange(SIZE)
        r, g, b = fpx[x, y]
        fpx[x, y] = (max(0, r - 12), max(0, g - 12), max(0, b - 12))
    floor.save(os.path.join(OUT_DIR, f"floor_{name}.png"))
    print(f"saved wall_{name} ({title}) + floor_{name}")


def build_preview():
    layout = pk2.build_layout()
    deco_tex = Image.open(os.path.join(OUT_DIR, "deco_sheet.png")).convert("RGBA")
    font_title = ImageFont.truetype(pk2.FONT_PATH, 18)
    SCALE = 2
    Wp, Hp = pk2.PREV_COLS * pk2.CELL * SCALE, pk2.PREV_ROWS * pk2.CELL * SCALE
    TITLE_H = 32
    GAP = 6
    scenes = []
    for i, (name, title, wlo, whi) in enumerate(THEMES):
        wall = Image.open(os.path.join(OUT_DIR, f"wall_{name}.png")).convert("RGB")
        floor = Image.open(os.path.join(OUT_DIR, f"floor_{name}.png")).convert("RGB")
        scene = pk2.render_scene(wall, floor, layout, deco_tex, seed=400 + i).resize((Wp, Hp), Image.NEAREST)
        scenes.append((f"{name} {title}", scene))
    # 2 列布局（5 行 x 2 列）
    col_w = Wp + GAP
    total_w = col_w * 2 + GAP
    row_h = Hp + TITLE_H + GAP
    total_h = row_h * 5 + GAP
    canvas = Image.new("RGB", (total_w, total_h), (24, 22, 20))
    for i, (title, scene) in enumerate(scenes):
        col, row = i % 2, i // 2
        x = GAP + col * col_w
        y = GAP + row * row_h
        td = ImageDraw.Draw(canvas)
        canvas.paste(scene, (x, y + TITLE_H))
        td.rectangle([x, y, x + Wp - 1, y + TITLE_H - 2], fill=(46, 42, 38))
        td.text((x + 10, y + 4), title, font=font_title, fill=(240, 232, 216))
    out = os.path.join(TMP, "mock_D_styles.png")
    canvas.save(out)
    print("saved", out, canvas.size)


if __name__ == "__main__":
    for i, (name, title, wlo, whi) in enumerate(THEMES):
        gen_theme(name, title, wlo, whi, seed=9000 + i * 37)
    build_preview()
