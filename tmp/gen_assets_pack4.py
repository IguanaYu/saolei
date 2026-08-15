#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
素材包 4：地图外围"洞窟环境"三件套。

输出（assets/tiles/）：
  cave_bg.png            洞窟背景纹理（336 无缝，超暗低对比，铺满地图外全屏）
  frame_T/B/L/R.png      地图边框岩体条（336×20 / 20×336，RGBA，锯齿断面朝地图；
                          沿长度方向可平铺/裁剪；中性暗岩色配所有风格）
  frame_TL/TR/BL/BR.png  边框四角（20×20，双锯齿）
  deco_outer_sheet.png   外围矿洞道具 4x2（28×28 透明底）：矿灯/木支架/骷髅/链条/
                          大晶簇/警示牌/矿车/落石堆
预览（tmp/mock_outer_env.png）：
  面板1 现状：纯色底 + 地图    面板2 洞窟环境包：cave_bg + 边框 + 道具
  面板3 道具特写（放大）
"""
import os
import random
from PIL import Image, ImageDraw, ImageFont

import gen_assets_pack2 as pk2

TMP = pk2.TMP
OUT_DIR = pk2.OUT_DIR
SIZE = 336
TH = 20  # 边框条厚度


# ---------------- 洞窟背景 ----------------

def gen_cave_bg():
    img = pk2.noise_img(SIZE, [12, 24, 48], 4242, (15, 12, 10), (36, 30, 25))
    px = img.load()
    rng = random.Random(4243)
    for _ in range(500):  # 极暗碎屑
        x, y = rng.randrange(SIZE), rng.randrange(SIZE)
        r, g, b = px[x, y]
        px[x, y] = (max(0, r - 8), max(0, g - 8), max(0, b - 8))
    d = ImageDraw.Draw(img)
    for _ in range(14):  # 远处微弱晶光（极稀疏）
        x, y = rng.randrange(SIZE), rng.randrange(SIZE)
        c = rng.choice([(70, 90, 130), (90, 70, 120), (80, 110, 90)])
        d.point((x, y), fill=c)
    img.save(os.path.join(OUT_DIR, "cave_bg.png"))
    print("saved cave_bg")


# ---------------- 边框岩体条 ----------------

def jagged_edge(n, e_lo, e_hi, seed):
    """闭合随机走位锯齿：返回长度 n 的边线数组，首尾相等（可平铺）。"""
    rng = random.Random(seed)
    edge = []
    e = rng.randint(e_lo, e_hi)
    e0 = e
    x = 0
    while x < n:
        seg = rng.randint(3, 7)
        e = max(e_lo, min(e_hi, e + rng.choice([-2, -1, -1, 1, 1, 2])))
        edge.extend([e] * seg)
        x += seg
    edge = edge[:n]
    # 线性纠偏让首尾闭合（平铺无缝）
    drift = edge[-1] - e0
    for i in range(n):
        edge[i] -= drift * i // n
    edge[-1] = e0
    return edge


def make_frame_strip(orient, side, seed):
    """orient: H(横条 336×20)/V(竖条 20×336)；side: T/B/L/R 表示锯齿朝向。"""
    rock = pk2.noise_img(SIZE, [12, 24, 48], seed, (26, 21, 17), (58, 49, 40))
    rng = random.Random(seed + 1)
    if orient == "H":
        w, h = SIZE, TH
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        rpx = rock.load()
        px = img.load()
        edge = jagged_edge(w, 12, 19, seed + 2)
        inner_sign = 1 if side == "T" else -1  # T: 岩体在上半，锯齿缘在下边界
        base = 0 if side == "T" else TH - 1
        for x in range(w):
            e = edge[x]
            for y in range(h):
                if side == "T" and y <= e:
                    px[x, y] = rpx[x, y] + (255,)
                elif side == "B" and y >= TH - 1 - e:
                    px[x, y] = rpx[x, y] + (255,)
        d = ImageDraw.Draw(img)
        dark, lite = (14, 11, 9, 235), (96, 84, 70, 150)
        for x in range(w):
            e = edge[x]
            yy = e if side == "T" else TH - 1 - e
            d.point((x, yy), fill=dark)
            if x % 2 == 0:
                d.point((x, yy - inner_sign), fill=dark)
            d.point((x, yy - inner_sign * 3), fill=lite)
        # 外缘压暗渐变融入背景
        for y in range(h):
            k = 1.0 - 0.55 * (y / max(1, h - 1)) if side == "T" else 1.0 - 0.55 * ((h - 1 - y) / max(1, h - 1))
            for x in range(w):
                r, g, b, a = px[x, y]
                if a:
                    px[x, y] = (int(r * k), int(g * k), int(b * k), a)
    else:
        w, h = TH, SIZE
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        rpx = rock.load()
        px = img.load()
        edge = jagged_edge(h, 12, 19, seed + 2)
        for y in range(h):
            e = edge[y]
            for x in range(w):
                if side == "L" and x <= e:
                    px[x, y] = rpx[x, y] + (255,)
                elif side == "R" and x >= TH - 1 - e:
                    px[x, y] = rpx[x, y] + (255,)
        d = ImageDraw.Draw(img)
        dark, lite = (14, 11, 9, 235), (96, 84, 70, 150)
        for y in range(h):
            e = edge[y]
            xx = e if side == "L" else TH - 1 - e
            d.point((xx, y), fill=dark)
            if y % 2 == 0:
                d.point((xx - (1 if side == "L" else -1), y), fill=dark)
            d.point((xx + (3 if side == "L" else -3), y), fill=lite)
        for x in range(w):
            k = 1.0 - 0.55 * (x / max(1, w - 1)) if side == "L" else 1.0 - 0.55 * ((w - 1 - x) / max(1, w - 1))
            for y in range(h):
                r, g, b, a = px[x, y]
                if a:
                    px[x, y] = (int(r * k), int(g * k), int(b * k), a)
    return img


def make_frame_corner(quadrant, seed):
    """四角块：双锯齿（横缘+竖缘）。quadrant: TL/TR/BL/BR"""
    rock = pk2.noise_img(TH, [6, 12], seed, (26, 21, 17), (58, 49, 40))
    img = Image.new("RGBA", (TH, TH), (0, 0, 0, 0))
    rpx = rock.load()
    px = img.load()
    rng = random.Random(seed + 3)
    # 横向锯齿缘（对 T 或 B）与纵向锯齿缘（对 L 或 R），取 max/min 包络
    h_edge = jagged_edge(TH, 8, 13, seed + 4)
    v_edge = jagged_edge(TH, 8, 13, seed + 5)
    for x in range(TH):
        for y in range(TH):
            if quadrant == "TL":
                inside = y <= h_edge[x] or x <= v_edge[y]
            elif quadrant == "TR":
                inside = y <= h_edge[TH - 1 - x] or x >= TH - 1 - v_edge[TH - 1 - y]
            elif quadrant == "BL":
                inside = y >= TH - 1 - h_edge[x] or x <= v_edge[y]
            else:  # BR
                inside = y >= TH - 1 - h_edge[TH - 1 - x] or x >= TH - 1 - v_edge[TH - 1 - y]
            if inside:
                px[x, y] = rpx[x, y] + (255,)
    d = ImageDraw.Draw(img)
    dark = (14, 11, 9, 235)
    for x in range(TH):
        for y in range(TH):
            if not px[x, y][3]:
                continue
            nb_out = False
            for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < TH and 0 <= ny < TH and not px[nx, ny][3]:
                    nb_out = True
                    break
                if not (0 <= nx < TH and 0 <= ny < TH):
                    nb_out = True  # 图外视为外侧
                    break
            if nb_out:
                d.point((x, y), fill=dark)
    return img


def gen_frames():
    make_frame_strip("H", "T", 6001).save(os.path.join(OUT_DIR, "frame_T.png"))
    make_frame_strip("H", "B", 6002).save(os.path.join(OUT_DIR, "frame_B.png"))
    make_frame_strip("V", "L", 6003).save(os.path.join(OUT_DIR, "frame_L.png"))
    make_frame_strip("V", "R", 6004).save(os.path.join(OUT_DIR, "frame_R.png"))
    for q, s in (("TL", 6101), ("TR", 6102), ("BL", 6103), ("BR", 6104)):
        make_frame_corner(q, s).save(os.path.join(OUT_DIR, f"frame_{q}.png"))
    print("saved frame_T/B/L/R + corners")


# ---------------- 外围道具 ----------------

def prop_lantern(d, ox, oy):
    # 挂钩+链+灯体+暖光晕
    d.arc([ox + 11, oy + 2, ox + 17, oy + 8], 180, 360, fill=(110, 100, 90))
    d.line([(ox + 14, oy + 8), (ox + 14, oy + 11)], fill=(110, 100, 90))
    d.rectangle([ox + 10, oy + 11, ox + 18, oy + 19], fill=(70, 62, 52), outline=(40, 34, 28))
    d.rectangle([ox + 12, oy + 13, ox + 16, oy + 17], fill=(255, 196, 90))
    d.point((ox + 14, oy + 15), fill=(255, 240, 180))
    for dx, dy in ((9, 14), (19, 14), (14, 9), (14, 20)):
        d.point((ox + dx, oy + dy), fill=(200, 140, 60))


def prop_support(d, ox, oy):
    # 木支架：两立柱一横梁
    wood, wood_d = (96, 68, 40), (60, 42, 24)
    d.rectangle([ox + 5, oy + 6, ox + 8, oy + 24], fill=wood, outline=wood_d)
    d.rectangle([ox + 19, oy + 6, ox + 22, oy + 24], fill=wood, outline=wood_d)
    d.rectangle([ox + 3, oy + 3, ox + 24, oy + 7], fill=wood, outline=wood_d)
    d.line([(ox + 3, oy + 3), (ox + 24, oy + 3)], fill=(130, 96, 60))


def prop_skull(d, ox, oy):
    # 骷髅头
    bone, hole = (218, 210, 190), (40, 34, 30)
    d.ellipse([ox + 8, oy + 8, ox + 20, oy + 19], fill=bone, outline=(150, 142, 124))
    d.rectangle([ox + 10, oy + 19, ox + 18, oy + 23], fill=bone)
    d.ellipse([ox + 10, oy + 11, ox + 13, oy + 14], fill=hole)
    d.ellipse([ox + 15, oy + 11, ox + 18, oy + 14], fill=hole)
    d.line([(ox + 12, oy + 20), (ox + 12, oy + 23)], fill=hole)
    d.line([(ox + 16, oy + 20), (ox + 16, oy + 23)], fill=hole)


def prop_chain(d, ox, oy):
    # 垂挂链条
    link = (128, 118, 104)
    y = oy + 2
    x = ox + 14
    while y < oy + 24:
        d.ellipse([x - 2, y, x + 2, y + 4], outline=link)
        y += 4
        x += random.choice([-1, 0, 1])


def prop_big_crystal(d, ox, oy):
    # 大晶簇（比岩壁装饰件大、亮）
    for cx, h, w, col, edge in [(10, 16, 3, (96, 168, 250), (40, 88, 170)),
                                 (17, 11, 2, (126, 192, 255), (52, 104, 190)),
                                 (21, 7, 1, (150, 208, 255), (60, 116, 200))]:
        d.polygon([(ox + cx - w, oy + 24), (ox + cx, oy + 24 - h), (ox + cx + w, oy + 24)],
                  fill=col, outline=edge)
        d.line([(ox + cx, oy + 24 - h), (ox + cx, oy + 24 - h + 5)], fill=(230, 244, 255))


def prop_sign(d, ox, oy):
    # 警示牌：木桩+牌面+!
    d.rectangle([ox + 13, oy + 12, ox + 15, oy + 24], fill=(96, 68, 40))
    d.polygon([(ox + 6, oy + 4), (ox + 22, oy + 4), (ox + 20, oy + 13), (ox + 8, oy + 13)],
              fill=(150, 108, 62), outline=(80, 56, 32))
    d.line([(ox + 14, oy + 6), (ox + 14, oy + 9)], fill=(60, 30, 20))
    d.point((ox + 14, oy + 11), fill=(60, 30, 20))


def prop_cart(d, ox, oy):
    # 破矿车：车斗+轮
    d.polygon([(ox + 5, oy + 10), (ox + 23, oy + 10), (ox + 21, oy + 20), (ox + 7, oy + 20)],
              fill=(110, 74, 48), outline=(58, 38, 24))
    d.line([(ox + 5, oy + 10), (ox + 8, oy + 6)], fill=(58, 38, 24))
    d.line([(ox + 23, oy + 10), (ox + 20, oy + 6)], fill=(58, 38, 24))
    for wx in (10, 18):
        d.ellipse([ox + wx - 2, oy + 20, ox + wx + 2, oy + 24], fill=(70, 66, 60), outline=(40, 38, 34))
    d.rectangle([ox + 8, oy + 8, ox + 20, oy + 10], fill=(88, 60, 38))


def prop_rubble(d, ox, oy):
    # 落石堆（大）
    d.ellipse([ox + 4, oy + 15, ox + 14, oy + 24], fill=(88, 78, 68))
    d.ellipse([ox + 13, oy + 18, ox + 24, oy + 25], fill=(76, 67, 58))
    d.ellipse([ox + 9, oy + 8, ox + 18, oy + 17], fill=(102, 91, 79))
    d.point((ox + 11, oy + 10), fill=(130, 118, 102))
    d.point((ox + 6, oy + 17), fill=(118, 106, 92))


OUTER_PROPS = [prop_lantern, prop_support, prop_skull, prop_chain,
               prop_big_crystal, prop_sign, prop_cart, prop_rubble]
PROP_NAMES = ["矿灯", "木支架", "骷髅", "链条", "大晶簇", "警示牌", "矿车", "落石堆"]


def gen_outer_props():
    img = Image.new("RGBA", (28 * 4, 28 * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    random.seed(77)
    for i, fn in enumerate(OUTER_PROPS):
        fn(d, (i % 4) * 28, (i // 4) * 28)
    img.save(os.path.join(OUT_DIR, "deco_outer_sheet.png"))
    print("saved deco_outer_sheet")


# ---------------- 预览 ----------------

def build_preview():
    layout = pk2.build_layout()
    deco_tex = Image.open(os.path.join(OUT_DIR, "deco_sheet.png")).convert("RGBA")
    wall = Image.open(os.path.join(OUT_DIR, "wall_C1.png")).convert("RGB")
    floor = Image.open(os.path.join(OUT_DIR, "floor_dark.png")).convert("RGB")
    scene = pk2.render_scene(wall, floor, layout, deco_tex)  # 560x336
    MW, MH = scene.size
    MARGIN = 110
    CW, CH = MW + MARGIN * 2, MH + MARGIN * 2

    font_title = ImageFont.truetype(pk2.FONT_PATH, 18)
    TITLE_H = 30
    GAP = 6

    panels = []

    # 面板1：现状纯色底
    p1 = Image.new("RGB", (CW, CH), (26, 21, 16))
    p1.paste(scene, (MARGIN, MARGIN))
    panels.append(("现状：纯色背景 + 裸地图", p1))

    # 面板2：洞窟环境
    cave = Image.open(os.path.join(OUT_DIR, "cave_bg.png")).convert("RGB")
    p2 = pk2.tile_texture(cave, CW, CH).convert("RGBA")
    # 外围道具（避开边框带和地图）
    rng = random.Random(88)
    props = Image.open(os.path.join(OUT_DIR, "deco_outer_sheet.png")).convert("RGBA")
    for _ in range(16):
        px_ = rng.randrange(0, CW - 28)
        py_ = rng.randrange(0, CH - 28)
        in_frame = (MARGIN - 30 <= px_ <= MW + MARGIN + 10 and MARGIN - 30 <= py_ <= MH + MARGIN + 10)
        if MARGIN - 26 <= px_ <= MARGIN + MW and MARGIN - 26 <= py_ <= MARGIN + MH:
            continue  # 不压地图和边框带
        i = rng.randrange(8)
        piece = props.crop(((i % 4) * 28, (i // 4) * 28, (i % 4) * 28 + 28, (i // 4) * 28 + 28))
        p2.paste(piece, (px_, py_), piece)
    # 边框条（贴地图四边，长度裁剪）
    fT = Image.open(os.path.join(OUT_DIR, "frame_T.png"))
    fB = Image.open(os.path.join(OUT_DIR, "frame_B.png"))
    fL = Image.open(os.path.join(OUT_DIR, "frame_L.png"))
    fR = Image.open(os.path.join(OUT_DIR, "frame_R.png"))
    # 横条按宽裁剪（纹理 x 向无缝）
    p2.paste(fT.crop((0, 0, MW, 20)), (MARGIN, MARGIN - 20), fT.crop((0, 0, MW, 20)))
    p2.paste(fB.crop((0, 0, MW, 20)), (MARGIN, MARGIN + MH), fB.crop((0, 0, MW, 20)))
    p2.paste(fL.crop((0, 0, 20, MH)), (MARGIN - 20, MARGIN), fL.crop((0, 0, 20, MH)))
    p2.paste(fR.crop((0, 0, 20, MH)), (MARGIN + MW, MARGIN), fR.crop((0, 0, 20, MH)))
    for q, cx, cy in (("TL", MARGIN - 20, MARGIN - 20), ("TR", MARGIN + MW, MARGIN - 20),
                      ("BL", MARGIN - 20, MARGIN + MH), ("BR", MARGIN + MW, MARGIN + MH)):
        c = Image.open(os.path.join(OUT_DIR, f"frame_{q}.png"))
        p2.paste(c, (cx, cy), c)
    p2.paste(scene, (MARGIN, MARGIN))
    panels.append(("洞窟环境包：cave_bg + 边框岩体 + 外围道具", p2.convert("RGB")))

    # 面板3：道具特写
    sw = 112
    strip = Image.new("RGB", (sw * 8 + 8, 132), (30, 26, 22))
    sd = ImageDraw.Draw(strip)
    for i, fn in enumerate(OUTER_PROPS):
        x = 4 + i * sw
        piece = props.crop(((i % 4) * 28, (i // 4) * 28, (i % 4) * 28 + 28, (i // 4) * 28 + 28))
        big = piece.resize((112, 112), Image.NEAREST)
        strip.paste(big, (x, 4), big)
        sd.text((x + 4, 116), PROP_NAMES[i], font=ImageFont.truetype(pk2.FONT_PATH, 14), fill=(235, 228, 210))
    strip = strip.resize((strip.width * 2, strip.height * 2), Image.NEAREST)
    panels.append(("外围道具特写（放大）", strip))

    # 拼合（竖排）
    total_w = max(p.width for _, p in panels) + GAP * 2
    total_h = sum(p.height + TITLE_H + GAP for _, p in panels) + GAP
    canvas = Image.new("RGB", (total_w, total_h), (24, 22, 20))
    y = GAP
    for title, pil in panels:
        td = ImageDraw.Draw(canvas)
        canvas.paste(pil, (GAP, y + TITLE_H))
        td.rectangle([GAP, y, GAP + pil.width - 1, y + TITLE_H - 2], fill=(46, 42, 38))
        td.text((GAP + 10, y + 4), title, font=font_title, fill=(240, 232, 216))
        y += pil.height + TITLE_H + GAP
    out = os.path.join(TMP, "mock_outer_env.png")
    canvas.save(out)
    print("saved", out, canvas.size)


if __name__ == "__main__":
    gen_cave_bg()
    gen_frames()
    gen_outer_props()
    build_preview()
