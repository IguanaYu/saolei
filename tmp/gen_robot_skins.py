#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
机器人皮肤设计稿：4 型 × (待机/移动) 2 帧。

设计语言与 assets/ui/icons/icon_robot_* 同族（图标=脸，皮肤=全身）：
  底盘履带 + 船体(倒角+铆钉+面板线) + 发光眼罩 + 顶部功能件
  opener 橙: 前部锥形钻头(2帧条纹旋转)   marker 红: 顶部旗杆红旗(2帧摆动)
  detector 绿: 顶部雷达碟(2帧偏转)       miner 棕: 前部翻斗+矿石(2帧矿石跳动)

12x12 设计 → 2x NEAREST 输出 24x24（与图标同像素密度，游戏内 1:1）
预览：tmp/mock_robot_skins.png（放大特写 + 上机画面 + 行走序列）
"""
import os
import random
from PIL import Image, ImageDraw, ImageFont

import gen_assets_pack2 as pk2

TMP = pk2.TMP
OUT_DIR = os.path.join(TMP, "..", "assets", "robots")
os.makedirs(OUT_DIR, exist_ok=True)

BODIES = {
    "opener": ((232, 148, 60), (196, 116, 44)),
    "marker": ((226, 80, 64), (182, 58, 46)),
    "detector": ((116, 204, 116), (86, 164, 88)),
    "miner": ((150, 110, 70), (116, 82, 50)),
}
OUTLINE = (46, 38, 32)
TRACK = (62, 60, 64)
WHEEL = (96, 100, 108)
METAL = (188, 194, 204)
METAL_D = (120, 126, 136)
GLOW = (255, 250, 210)


def base_chassis(d, kind, frame):
    """船体+履带+眼罩。frame: 0=idle 1=move(履带偏移)"""
    body, body_dk = BODIES[kind]
    # 履带
    d.rectangle([2, 10, 9, 11], fill=TRACK)
    # 车轮
    wxs = [3, 6, 8] if frame == 0 else [2, 5, 8]
    for wx in wxs:
        d.rectangle([wx, 10, wx, 11], fill=WHEEL)
    # 船体（倒角）
    d.rectangle([2, 3, 9, 9], fill=body, outline=OUTLINE)
    d.point((3, 3), fill=tuple(min(255, c + 30) for c in body))   # 顶部高光
    d.point((8, 9), fill=body_dk)                                  # 底部暗角
    d.point((2, 9), fill=body_dk)
    # 眼罩
    d.rectangle([3, 5, 8, 6], fill=(30, 28, 26))
    # 发光眼
    ex = 4 if frame == 0 else 5
    d.point((ex, 5), fill=GLOW)
    d.point((ex + 3, 5), fill=GLOW)
    # 铆钉
    d.point((3, 9), fill=(210, 200, 180))
    d.point((8, 9), fill=(210, 200, 180))
    return body, body_dk


def part_opener(d, frame):
    """前部锥形钻头：条纹两帧旋转"""
    d.polygon([(0, 8), (2, 6), (2, 10)], fill=METAL, outline=METAL_D)
    d.rectangle([2, 6, 3, 10], fill=METAL_D)
    # 旋转条纹
    if frame == 0:
        d.point((2, 7), fill=(230, 236, 244)); d.point((3, 9), fill=(230, 236, 244))
    else:
        d.point((2, 9), fill=(230, 236, 244)); d.point((3, 7), fill=(230, 236, 244))


def part_marker(d, frame):
    """顶部旗杆红旗：两帧摆动"""
    d.line([(6, 0), (6, 3)], fill=(120, 84, 48))
    if frame == 0:
        d.polygon([(7, 0), (10, 1), (7, 2)], fill=(255, 204, 82), outline=(180, 130, 30))
    else:
        d.polygon([(7, 1), (10, 2), (7, 3)], fill=(255, 204, 82), outline=(180, 130, 30))


def part_detector(d, frame):
    """顶部雷达碟：两帧偏转"""
    if frame == 0:
        d.arc([3, 0, 9, 4], 180, 360, fill=(220, 255, 220), width=2)
        d.line([(6, 1), (8, 0)], fill=GLOW)
    else:
        d.arc([3, 1, 9, 5], 180, 360, fill=(220, 255, 220), width=2)
        d.line([(6, 2), (8, 1)], fill=GLOW)
    d.point((6, 3), fill=METAL_D)


def part_miner(d, frame):
    """前部翻斗+矿石：两帧矿石跳动"""
    d.rectangle([0, 7, 1, 10], fill=(110, 78, 50), outline=(60, 42, 28))
    oy = 7 if frame == 0 else 6
    d.point((0, oy), fill=(120, 220, 190))
    d.point((1, oy + 1), fill=(255, 209, 102))


PARTS = {"opener": part_opener, "marker": part_marker,
         "detector": part_detector, "miner": part_miner}


def gen_skin(kind, frame):
    img = Image.new("RGBA", (12, 12), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if frame == 1:
        # 移动帧整体上跳 1px（弹跳感）：画布内直接整体上移实现——先画在 12x13 再裁
        img2 = Image.new("RGBA", (12, 13), (0, 0, 0, 0))
        d2 = ImageDraw.Draw(img2)
        base_chassis(d2, kind, 1)
        PARTS[kind](d2, 1)
        img = img2.crop((0, 0, 12, 12))
    else:
        base_chassis(d, kind, 0)
        PARTS[kind](d, 0)
    out = img.resize((24, 24), Image.NEAREST)
    name = f"robot_{kind}_{'idle' if frame == 0 else 'move'}.png"
    out.save(os.path.join(OUT_DIR, name))
    return out


def main():
    skins = {}
    for kind in ("opener", "marker", "detector", "miner"):
        skins[(kind, 0)] = gen_skin(kind, 0)
        skins[(kind, 1)] = gen_skin(kind, 1)
    print("saved 8 skins ->", OUT_DIR)

    # ---------- 预览 ----------
    font_t = ImageFont.truetype(pk2.FONT_PATH, 18)
    font_s = ImageFont.truetype(pk2.FONT_PATH, 14)
    TITLE_H, GAP = 30, 8
    W = 760

    # 面板1：特写（4x=96px） idle+move 并排
    p1 = Image.new("RGB", (W, 240), (34, 30, 26))
    d = ImageDraw.Draw(p1)
    names = {"opener": "开墙型", "marker": "标雷型", "detector": "检测型", "miner": "矿工型"}
    for i, kind in enumerate(("opener", "marker", "detector", "miner")):
        x = 20 + i * 185
        d.text((x + 8, 12), f"{names[kind]}", font=font_s, fill=(240, 232, 216))
        big0 = skins[(kind, 0)].resize((96, 96), Image.NEAREST)
        big1 = skins[(kind, 1)].resize((96, 96), Image.NEAREST)
        p1.paste(big0, (x + 8, 44), big0)
        p1.paste(big1, (x + 100, 44), big1)
        d.text((x + 8, 148), "待机", font=font_s, fill=(178, 160, 128))
        d.text((x + 100, 148), "移动", font=font_s, fill=(178, 160, 128))
        # 底色小样（游戏内 24px 实际大小）
        d.rectangle([x + 8, 180, x + 40, 212], outline=(80, 72, 62))
        p1.paste(skins[(kind, 0)], (x + 12, 184), skins[(kind, 0)])
        d.text((x + 50, 184), "← 游戏内实际尺寸", font=font_s, fill=(140, 130, 114))

    # 面板2：上机画面（复用场面，机器人在洞底上）
    layout = pk2.build_layout()
    deco = Image.open(os.path.join(pk2.OUT_DIR, "deco_sheet.png")).convert("RGBA")
    wall = Image.open(os.path.join(pk2.OUT_DIR, "wall_C1.png")).convert("RGB")
    floor = Image.open(os.path.join(pk2.OUT_DIR, "floor_dark.png")).convert("RGB")
    scene = pk2.render_scene(wall, floor, layout, deco).convert("RGBA")
    # 开区格子里放机器人（idle 集中 + 一列 move 表现行走）
    open_cells = sorted(layout[0])
    spots = open_cells[3:7] + open_cells[10:13]
    for idx, (c, r) in enumerate(spots):
        kind = ("opener", "marker", "detector", "miner", "opener", "marker", "detector")[idx % 7]
        frame = 0 if idx < 4 else 1
        skin = skins[(kind, frame)]
        # 脚下投影
        sd = ImageDraw.Draw(scene)
        px_, py_ = c * 28, r * 28
        sd.ellipse([px_ + 6, py_ + 22, px_ + 21, py_ + 26], fill=(20, 15, 10, 120))
        scene.paste(skin, (px_ + 2, py_ + 2), skin)
    p2 = scene.convert("RGB").resize((560 * 1, 336), Image.NEAREST)
    p2 = p2.resize((W - 16, int((W - 16) * 336 / 560)), Image.NEAREST)

    # 面板3：行走序列（8 帧交替）
    p3 = Image.new("RGB", (W, 130), (34, 30, 26))
    d3 = ImageDraw.Draw(p3)
    d3.text((12, 8), "行走动画序列（帧交替 0.18s + 弹跳）：", font=font_s, fill=(240, 232, 216))
    for i in range(8):
        kind = ("opener", "marker", "detector", "miner")[i % 4]
        big = skins[(kind, i // 4)].resize((72, 72), Image.NEAREST)
        p3.paste(big, (20 + i * 92, 40), big)

    panels = [("① 皮肤特写：4 型 × 待机/移动（4x 放大 + 实际尺寸）", p1),
              ("② 上机效果：机器人在洞底上（右下 3 台为移动帧）", p2),
              ("③ 动画帧序列", p3)]
    total_h = sum(p.height + TITLE_H + GAP for _, p in panels) + GAP
    canvas = Image.new("RGB", (W + GAP * 2, total_h), (24, 22, 20))
    y = GAP
    for title, pil in panels:
        td = ImageDraw.Draw(canvas)
        canvas.paste(pil, (GAP, y + TITLE_H))
        td.rectangle([GAP, y, GAP + pil.width - 1, y + TITLE_H - 2], fill=(46, 42, 38))
        td.text((GAP + 10, y + 4), title, font=font_t, fill=(240, 232, 216))
        y += pil.height + TITLE_H + GAP
    out = os.path.join(TMP, "mock_robot_skins.png")
    canvas.save(out)
    print("saved", out, canvas.size)


if __name__ == "__main__":
    main()
