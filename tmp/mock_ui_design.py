#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
UI 视觉稿：5 屏（HUD / 商店 / 升级 / 结算 / 主菜单），矿洞木石风格。

设计语言（对齐已定稿的洞窟视觉体系）：
  面板  = 深棕木石 9-slice：深底 + 木质边框 + 四角铆钉 + 内阴影线
  按钮  = 木板按钮：木色渐变 + 2px 边 + 钉子；选中=金边，禁用=去饱和+红价
  图标  = 12px 像素图标（金币/矿石/星/心/时钟/机器人4种）
  字体  = mock 用雅黑代演示；正式版用 Fusion Pixel 12px（免费商用）
输出：tmp/mock_ui_design.png
"""
import os
import random
from PIL import Image, ImageDraw, ImageFont

import gen_assets_pack2 as pk2

TMP = pk2.TMP
OUT_DIR = pk2.OUT_DIR

SW, SH = 1280, 720

# ---- 调色板 ----
PANEL_BG = (40, 31, 22)
PANEL_BG2 = (54, 43, 30)
BORDER_WOOD = (112, 83, 50)
BORDER_HI = (156, 121, 76)
TEXT = (242, 230, 202)
TEXT_DIM = (178, 160, 128)
GOLD = (255, 209, 102)
RED = (226, 80, 64)
GREEN = (116, 204, 116)
BLUE = (108, 164, 255)
WOOD_BTN = (126, 92, 54)
WOOD_BTN_HI = (158, 120, 72)
SHADOW = (24, 18, 12)

FONT = lambda s: ImageFont.truetype(pk2.FONT_PATH, s)


# ---------------- 9-slice 风格面板 ----------------

def panel(d, x0, y0, x1, y1, rivets=True, bg=PANEL_BG, border=BORDER_WOOD):
    d.rectangle([x0 + 2, y0 + 2, x1 + 1, y1 + 1], fill=SHADOW)          # 投影
    d.rectangle([x0, y0, x1 - 2, y1 - 2], fill=border)                  # 边框
    d.rectangle([x0 + 2, y0 + 2, x1 - 4, y1 - 4], fill=bg)              # 底
    d.line([(x0 + 2, y1 - 5), (x1 - 4, y1 - 5)], fill=(30, 23, 16))     # 内阴影
    d.line([(x0 + 2, y0 + 2), (x1 - 4, y0 + 2)], fill=BORDER_HI)        # 顶部高光
    if rivets:
        for rx, ry in [(x0 + 6, y0 + 6), (x1 - 9, y0 + 6), (x0 + 6, y1 - 9), (x1 - 9, y1 - 9)]:
            d.ellipse([rx - 1, ry - 1, rx + 1, ry + 1], fill=(168, 158, 140))
            d.point((rx, ry), fill=(220, 214, 200))


def button(d, x0, y0, x1, y1, label, state="normal", font_size=16, sub=None):
    if state == "disabled":
        fill1, fill2, bd = (70, 62, 52), (58, 51, 43), (86, 76, 62)
        tcol = (150, 140, 124)
    elif state == "selected":
        fill1, fill2, bd = WOOD_BTN_HI, WOOD_BTN, GOLD
        tcol = TEXT
    else:
        fill1, fill2, bd = WOOD_BTN, (104, 75, 43), BORDER_HI
        tcol = TEXT
    d.rectangle([x0 + 2, y0 + 3, x1 + 1, y1 + 1], fill=SHADOW)
    d.rectangle([x0, y0, x1 - 2, y1 - 2], fill=bd)
    d.rectangle([x0 + 2, y0 + 2, x1 - 4, y1 - 5], fill=fill1)
    d.rectangle([x0 + 2, y0 + 2, x1 - 4, y0 + (y1 - y0) // 2 - 2], fill=fill2)
    for rx, ry in [(x0 + 5, y0 + 5), (x1 - 8, y0 + 5), (x0 + 5, y1 - 8), (x1 - 8, y1 - 8)]:
        d.point((rx, ry), fill=(196, 176, 140))
    f = FONT(font_size)
    bbox = d.textbbox((0, 0), label, font=f)
    tw = bbox[2] - bbox[0]
    tx = x0 + (x1 - x0 - tw) // 2 - bbox[0]
    if sub:
        d.text((tx, y0 + 8), label, font=f, fill=tcol)
        f2 = FONT(13)
        sc = RED if state == "disabled" else GOLD
        bbox2 = d.textbbox((0, 0), sub, font=f2)
        tw2 = bbox2[2] - bbox2[0]
        d.text((x0 + (x1 - x0 - tw2) // 2 - bbox2[0], y1 - 24), sub, font=f2, fill=sc)
    else:
        bbox = d.textbbox((0, 0), label, font=f)
        th = bbox[3] - bbox[1]
        d.text((tx, y0 + (y1 - y0 - th) // 2 - bbox[1]), label, font=f, fill=tcol)


# ---------------- 12px 像素图标 ----------------

def icon_coin(d, x, y):
    d.ellipse([x + 1, y + 1, x + 10, y + 10], fill=(255, 209, 102), outline=(158, 108, 30))
    d.ellipse([x + 3, y + 3, x + 8, y + 8], outline=(255, 240, 180))
    d.point((x + 5, y + 6), fill=(158, 108, 30))


def icon_ore(d, x, y):
    d.polygon([(x + 5, y + 1), (x + 10, y + 5), (x + 5, y + 10), (x + 1, y + 5)],
              fill=(120, 220, 190), outline=(40, 120, 100))
    d.point((x + 5, y + 4), fill=(230, 255, 245))


def icon_star(d, x, y):
    d.polygon([(x + 5, y), (x + 6, y + 4), (x + 10, y + 4), (x + 7, y + 7), (x + 8, y + 11),
               (x + 5, y + 8), (x + 2, y + 11), (x + 3, y + 7), (x, y + 4), (x + 4, y + 4)],
              fill=(255, 226, 120), outline=(170, 120, 30))


def icon_heart(d, x, y, full=True):
    c = (226, 80, 64) if full else (90, 70, 60)
    o = (130, 30, 24) if full else (60, 48, 42)
    d.ellipse([x + 1, y + 2, x + 5, y + 6], fill=c, outline=o)
    d.ellipse([x + 6, y + 2, x + 10, y + 6], fill=c, outline=o)
    d.polygon([(x + 1, y + 5), (x + 10, y + 5), (x + 5, y + 10)], fill=c)
    if full:
        d.point((x + 3, y + 3), fill=(255, 160, 150))


def icon_clock(d, x, y, warn=False):
    c = GOLD if warn else (200, 210, 220)
    d.ellipse([x + 1, y + 1, x + 10, y + 10], outline=c, width=2)
    d.line([(x + 5, y + 3), (x + 5, y + 6)], fill=c)
    d.line([(x + 5, y + 6), (x + 8, y + 7)], fill=c)


def robot_icon(d, x, y, kind):
    """机器人 12px 头像：身体色 + 功能符号"""
    body = {"opener": (232, 148, 60), "marker": (226, 80, 64),
            "detector": (116, 204, 116), "miner": (150, 110, 70)}[kind]
    d.rectangle([x + 2, y + 3, x + 9, y + 10], fill=body, outline=(50, 40, 34))
    d.rectangle([x + 3, y + 5, x + 4, y + 6], fill=(30, 30, 30))
    d.rectangle([x + 7, y + 5, x + 8, y + 6], fill=(30, 30, 30))
    if kind == "opener":
        d.polygon([(x + 4, y + 1), (x + 7, y + 1), (x + 5, y + 3)], fill=(200, 200, 210))
    elif kind == "marker":
        d.line([(x + 5, y), (x + 5, y + 3)], fill=(120, 84, 48))
        d.polygon([(x + 6, y), (x + 9, y + 1), (x + 6, y + 2)], fill=(255, 204, 82))
    elif kind == "detector":
        d.arc([x + 3, y, x + 8, y + 5], 200, 340, fill=(220, 255, 220))
    else:
        d.rectangle([x + 4, y + 1, x + 8, y + 3], fill=(110, 78, 50), outline=(60, 42, 28))


# ---------------- 游戏背景（复用素材） ----------------

def game_backdrop():
    bg = pk2.tile_texture(Image.open(os.path.join(OUT_DIR, "cave_bg.png")).convert("RGB"), SW, SH).convert("RGBA")
    layout = pk2.build_layout()
    deco = Image.open(os.path.join(OUT_DIR, "deco_sheet.png")).convert("RGBA")
    wall = Image.open(os.path.join(OUT_DIR, "wall_C1.png")).convert("RGB")
    floor = Image.open(os.path.join(OUT_DIR, "floor_dark.png")).convert("RGB")
    scene = pk2.render_scene(wall, floor, layout, deco, seed=512)
    MW, MH = scene.size  # 560x336
    mx, my = (SW - MW) // 2, (SH - MH) // 2 + 18
    # 外围道具
    rng = random.Random(66)
    props = Image.open(os.path.join(OUT_DIR, "deco_outer_sheet.png")).convert("RGBA")
    for _ in range(14):
        px_, py_ = rng.randrange(0, SW - 28), rng.randrange(0, SH - 28)
        if mx - 30 <= px_ <= mx + MW and my - 30 <= py_ <= my + MH:
            continue
        i = rng.randrange(8)
        piece = props.crop(((i % 4) * 28, (i // 4) * 28, (i % 4) * 28 + 28, (i // 4) * 28 + 28))
        bg.paste(piece, (px_, py_), piece)
    # 边框
    fT = Image.open(os.path.join(OUT_DIR, "frame_T.png"))
    fB = Image.open(os.path.join(OUT_DIR, "frame_B.png"))
    fL = Image.open(os.path.join(OUT_DIR, "frame_L.png"))
    fR = Image.open(os.path.join(OUT_DIR, "frame_R.png"))
    bg.paste(fT.crop((0, 0, MW, 20)), (mx, my - 20), fT.crop((0, 0, MW, 20)))
    bg.paste(fB.crop((0, 0, MW, 20)), (mx, my + MH), fB.crop((0, 0, MW, 20)))
    bg.paste(fL.crop((0, 0, 20, MH)), (mx - 20, my), fL.crop((0, 0, 20, MH)))
    bg.paste(fR.crop((0, 0, 20, MH)), (mx + MW, my), fR.crop((0, 0, 20, MH)))
    for q, cx, cy in (("TL", mx - 20, my - 20), ("TR", mx + MW, my - 20),
                      ("BL", mx - 20, my + MH), ("BR", mx + MW, my + MH)):
        c = Image.open(os.path.join(OUT_DIR, f"frame_{q}.png"))
        bg.paste(c, (cx, cy), c)
    bg.paste(scene, (mx, my))
    return bg.convert("RGB"), (mx, my, MW, MH)


def text(d, xy, s, size, col=TEXT, anchor="la"):
    d.text(xy, s, font=FONT(size), fill=col, anchor=anchor)


# ---------------- 5 屏 ----------------

def screen_hud(base):
    img = base.copy()
    d = ImageDraw.Draw(img)
    # 左上资源组
    panel(d, 16, 14, 320, 62)
    icon_coin(d, 30, 26); text(d, (48, 26), "128", 20, GOLD)
    icon_ore(d, 118, 26); text(d, (136, 26), "34", 20, TEXT)
    icon_star(d, 206, 26); text(d, (224, 26), "1250", 20, TEXT)
    # 右上 命+时间
    panel(d, SW - 260, 14, SW - 16, 62)
    for i in range(3):
        icon_heart(d, SW - 246 + i * 18, 26, full=(i < 2))
    icon_clock(d, SW - 180, 26, warn=True); text(d, (SW - 164, 22), "0:42", 22, RED)
    # 顶部中间目标横幅
    panel(d, SW // 2 - 210, 14, SW // 2 + 210, 62, rivets=False, bg=(50, 38, 24))
    text(d, (SW // 2, 26), "目标：翻开 40 格", 18, GOLD, anchor="ma")
    text(d, (SW // 2, 46), "23 / 40", 16, TEXT_DIM, anchor="ma")
    return img


def screen_shop(base):
    img = base.copy()
    d = ImageDraw.Draw(img)
    # 底部商店栏
    x0, y0, x1, y1 = SW // 2 - 520, SH - 118, SW // 2 + 520, SH - 16
    panel(d, x0, y0, x1, y1)
    cards = [
        ("opener", "开墙型", "¥50", "1", "normal"),
        ("marker", "标雷型", "¥50", "2", "normal"),
        ("detector", "检测型", "¥80", "3", "disabled"),
        ("miner", "矿工型", "¥60", "4", "normal"),
    ]
    cx = x0 + 24
    for kind, name, price, key, state in cards:
        button(d, cx, y0 + 20, cx + 150, y1 - 18, name, state=state, font_size=17, sub=price)
        robot_icon(d, cx + 10, y0 + 30, kind)
        # 键位角标
        panel(d, cx + 118, y0 + 26, cx + 144, y0 + 50, rivets=False, bg=(30, 24, 17))
        text(d, (cx + 131, y0 + 30), key, 15, GOLD, anchor="ma")
        cx += 166
    button(d, cx, y0 + 20, cx + 130, y1 - 18, "建基地", font_size=16, sub="¥80")
    cx += 146
    button(d, cx, y0 + 20, cx + 130, y1 - 18, "无人机", font_size=16, sub="¥100")
    cx += 146
    button(d, cx, y0 + 20, x1 - 24, y1 - 18, "升级", state="selected", font_size=18, sub="4 项可升")
    return img


def screen_upgrade(base):
    img = base.copy()
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = SW // 2 - 280, 90, SW // 2 + 280, 640
    panel(d, x0, y0, x1, y1)
    text(d, ((x0 + x1) // 2, y0 + 20), "局内升级", 24, GOLD, anchor="ma")
    d.line([(x0 + 30, y0 + 58), (x1 - 30, y0 + 58)], fill=BORDER_WOOD, width=2)
    rows = [
        ("opener", "开墙型·速度", "◆◆◇◇", "2.0s → 1.2s", "¥300", "normal"),
        ("marker", "标雷型·速度", "◆◇◇◇", "3.0s → 2.4s", "¥200", "normal"),
        ("miner", "矿工型·载量", "◆◆◆◇", "3 → 4", "¥450", "normal"),
        ("detector", "检测型·范围", "◇◇◇◇", "1 → 2 格", "¥800", "disabled"),
    ]
    ry = y0 + 78
    for kind, name, pips, eff, price, state in rows:
        robot_icon(d, x0 + 34, ry + 10, kind)
        text(d, (x0 + 60, ry + 8), name, 18)
        text(d, (x0 + 60, ry + 36), eff, 14, TEXT_DIM)
        text(d, (x0 + 250, ry + 12), pips, 20, GOLD)
        button(d, x1 - 190, ry + 4, x1 - 34, ry + 52, "升级" if state == "normal" else "钱不够",
               state=state, font_size=15, sub=price if state == "normal" else None)
        ry += 76
    d.line([(x0 + 30, ry + 4), (x1 - 30, ry + 4)], fill=(30, 24, 17), width=2)
    text(d, ((x0 + x1) // 2, ry + 16), "ESC 关闭 · 快捷键 U", 14, TEXT_DIM, anchor="ma")
    return img


def screen_results(base):
    img = base.copy()
    d = ImageDraw.Draw(img)
    # 暗化背景
    ov = Image.new("RGBA", img.size, (10, 8, 6, 150))
    img = Image.alpha_composite(img.convert("RGBA"), ov).convert("RGB")
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = SW // 2 - 250, 110, SW // 2 + 250, 610
    panel(d, x0, y0, x1, y1)
    text(d, ((x0 + x1) // 2, y0 + 28), "矿场完成！", 34, GOLD, anchor="ma")
    icon_star(d, (x0 + x1) // 2 - 60, y0 + 80)
    icon_star(d, (x0 + x1) // 2 - 6, y0 + 74)
    icon_star(d, (x0 + x1) // 2 + 48, y0 + 80)
    rows = [("开格积分", "+820"), ("标雷积分", "+150"), ("矿石结算", "+34 × 5"),
            ("剩余时间", "+12:08"), ("命数加成", "x1.5")]
    ry = y0 + 130
    for k, v in rows:
        text(d, (x0 + 60, ry), k, 17, TEXT_DIM)
        text(d, (x1 - 60, ry), v, 17, TEXT, anchor="ra")
        ry += 34
    d.line([(x0 + 40, ry + 6), (x1 - 40, ry + 6)], fill=BORDER_WOOD, width=2)
    text(d, (x0 + 60, ry + 18), "最终积分", 20, GOLD)
    text(d, (x1 - 60, ry + 16), "4820", 26, GOLD, anchor="ra")
    button(d, x0 + 60, y1 - 92, x0 + 220, y1 - 36, "再来一局", font_size=17)
    button(d, x1 - 220, y1 - 92, x1 - 60, y1 - 36, "选关", font_size=17)
    return img


def screen_menu(base):
    img = base.copy()
    d = ImageDraw.Draw(img)
    # 标题
    tx, ty = SW // 2, 150
    d.rectangle([tx - 190, ty - 6, tx + 190, ty + 78], fill=(24, 18, 12))
    d.rectangle([tx - 186, ty - 2, tx + 186, ty + 74], fill=PANEL_BG2)
    d.rectangle([tx - 186, ty - 2, tx + 186, ty + 6], fill=BORDER_HI)
    text(d, (tx, ty + 10), "扫雷挖矿", 52, GOLD, anchor="ma")
    # 镐子图标两侧
    for sx in (tx - 150, tx + 130):
        d.rectangle([sx + 4, ty + 18, sx + 7, ty + 56], fill=(140, 100, 60))
        d.arc([sx - 8, ty + 10, sx + 20, ty + 40], 200, 340, fill=(190, 196, 205), width=3)
    text(d, (tx, ty + 96), "—— 指挥机器人，挖穿雷区矿洞 ——", 18, TEXT_DIM, anchor="ma")
    # 主按钮列
    by = 340
    for label, i in [("开始挖矿", 0), ("章节选择", 1), ("设置", 2), ("退出", 3)]:
        w = 260
        button(d, tx - w // 2, by, tx + w // 2, by + 56, label, font_size=19,
               state="selected" if i == 0 else "normal")
        by += 70
    # 右上矿石总资产
    panel(d, SW - 240, 14, SW - 16, 62)
    icon_ore(d, SW - 226, 26); text(d, (SW - 208, 24), "总矿石 1286", 18)
    text(d, (24, SH - 40), "v0.2 · M1 开发中", 14, TEXT_DIM)
    return img


def main():
    base, _ = game_backdrop()
    font_title = FONT(20)
    TITLE_H, GAP = 36, 8
    screens = [
        ("① HUD 顶栏：左资源 / 右命数时间 / 中目标横幅（图标代替文字标签）", screen_hud),
        ("② 商店底栏：机器人卡片（头像+价格+键位角标）·禁用态=钱不够；选中态=金边", screen_shop),
        ("③ 局内升级：头像+等级菱格◆+效果预览+价格按钮（Dome Keeper 式高可读行）", screen_upgrade),
        ("④ 结算：暗化背景+星级+分项积分滚动+大按钮", screen_results),
        ("⑤ 主菜单：镐标 LOGO+木按钮列+右上局外资产", screen_menu),
    ]
    total_h = sum(SH + TITLE_H + GAP for _ in screens) + GAP
    canvas = Image.new("RGB", (SW + GAP * 2, total_h), (24, 22, 20))
    y = GAP
    for title, fn in screens:
        td = ImageDraw.Draw(canvas)
        canvas.paste(fn(base), (GAP, y + TITLE_H))
        td.rectangle([GAP, y, GAP + SW - 1, y + TITLE_H - 2], fill=(46, 42, 38))
        td.text((GAP + 12, y + 6), title, font=font_title, fill=(240, 232, 216))
        y += SH + TITLE_H + GAP
    out = os.path.join(TMP, "mock_ui_design.png")
    canvas.save(out)
    print("saved", out, canvas.size)


if __name__ == "__main__":
    main()
