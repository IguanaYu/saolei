#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
UI 主题素材：9-slice 面板/按钮 + 24px 图标 → assets/ui/

  panel_wood.png      48x48  9-slice(边12px)：深棕底+木边+四角铆钉+内阴影+顶高光
  btn_normal/hover/pressed/disabled.png  44x32 9-slice(边10px)：木板+钉子
  icons/icon_*.png    24x24（12px 设计 2x NEAREST 放大，游戏内 1:1 显示）
输出目录：assets/ui/ 与 assets/ui/icons/
"""
import os
from PIL import Image, ImageDraw

TMP = os.path.dirname(os.path.abspath(__file__))
UI_DIR = os.path.join(TMP, "..", "assets", "ui")
ICON_DIR = os.path.join(UI_DIR, "icons")
os.makedirs(ICON_DIR, exist_ok=True)

PANEL_BG = (40, 31, 22)
BORDER_WOOD = (112, 83, 50)
BORDER_HI = (156, 121, 76)
SHADOW = (24, 18, 12)
WOOD = (126, 92, 54)
WOOD_HI = (158, 120, 72)
WOOD_DK = (104, 75, 43)
NAIL = (196, 176, 140)


def gen_panel():
    S, B = 48, 12
    img = Image.new("RGBA", (S, S))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, S - 1, S - 1], fill=BORDER_WOOD)
    d.rectangle([2, 2, S - 3, S - 3], fill=PANEL_BG)
    d.line([(2, 2), (S - 3, 2)], fill=BORDER_HI)            # 顶高光
    d.line([(2, S - 3), (S - 3, S - 3)], fill=(30, 23, 16))  # 底内阴影
    d.line([(2, 2), (2, S - 3)], fill=(48, 37, 26))
    for rx, ry in [(6, 6), (S - 7, 6), (6, S - 7), (S - 7, S - 7)]:
        d.ellipse([rx - 2, ry - 2, rx + 2, ry + 2], fill=(60, 50, 40))
        d.ellipse([rx - 1, ry - 1, rx + 1, ry + 1], fill=(168, 158, 140))
        d.point((rx, ry), fill=(222, 216, 202))
    img.save(os.path.join(UI_DIR, "panel_wood.png"))
    print("saved panel_wood")


def gen_button(name, fill1, fill2, border, nail=NAIL, disabled=False):
    W, H, B = 44, 32, 10
    img = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W - 1, H - 1], fill=border)
    d.rectangle([2, 2, W - 3, H - 3], fill=fill1)
    d.rectangle([2, 2, W - 3, H // 2 - 1], fill=fill2)
    d.line([(2, 2), (W - 3, 2)], fill=tuple(min(255, c + 26) for c in fill2))
    if not disabled:
        for rx, ry in [(5, 5), (W - 6, 5), (5, H - 6), (W - 6, H - 6)]:
            d.point((rx, ry), fill=nail)
    img.save(os.path.join(UI_DIR, f"{name}.png"))
    print("saved", name)


# ---------------- 12px 图标（2x 输出 24px） ----------------

def canvas12():
    img = Image.new("RGBA", (12, 12), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def save12(img, name):
    img.resize((24, 24), Image.NEAREST).save(os.path.join(ICON_DIR, f"{name}.png"))
    print("saved icon", name)


def icon_coin():
    img, d = canvas12()
    d.ellipse([1, 1, 10, 10], fill=(255, 209, 102), outline=(158, 108, 30))
    d.ellipse([3, 3, 8, 8], outline=(255, 240, 180))
    d.point((5, 6), fill=(158, 108, 30))
    save12(img, "icon_coin")


def icon_ore():
    img, d = canvas12()
    d.polygon([(5, 1), (10, 5), (5, 10), (1, 5)], fill=(120, 220, 190), outline=(40, 120, 100))
    d.point((5, 4), fill=(230, 255, 245))
    save12(img, "icon_ore")


def icon_star():
    img, d = canvas12()
    d.polygon([(5, 0), (6, 4), (10, 4), (7, 7), (8, 11), (5, 8), (2, 11), (3, 7), (0, 4), (4, 4)],
              fill=(255, 226, 120), outline=(170, 120, 30))
    save12(img, "icon_star")


def icon_heart(full=True):
    img, d = canvas12()
    c = (226, 80, 64) if full else (96, 74, 62)
    o = (130, 30, 24) if full else (62, 50, 44)
    d.ellipse([1, 2, 5, 6], fill=c, outline=o)
    d.ellipse([6, 2, 10, 6], fill=c, outline=o)
    d.polygon([(1, 5), (10, 5), (5, 10)], fill=c)
    if full:
        d.point((3, 3), fill=(255, 160, 150))
    save12(img, "icon_heart" if full else "icon_heart_empty")


def icon_clock():
    img, d = canvas12()
    d.ellipse([1, 1, 10, 10], outline=(255, 209, 102), width=2)
    d.line([(5, 3), (5, 6)], fill=(255, 209, 102))
    d.line([(5, 6), (8, 7)], fill=(255, 209, 102))
    save12(img, "icon_clock")


def icon_robot(kind):
    img, d = canvas12()
    body = {"opener": (232, 148, 60), "marker": (226, 80, 64),
            "detector": (116, 204, 116), "miner": (150, 110, 70)}[kind]
    d.rectangle([2, 3, 9, 10], fill=body, outline=(50, 40, 34))
    d.rectangle([3, 5, 4, 6], fill=(30, 30, 30))
    d.rectangle([7, 5, 8, 6], fill=(30, 30, 30))
    if kind == "opener":
        d.polygon([(4, 1), (7, 1), (5, 3)], fill=(200, 200, 210))
    elif kind == "marker":
        d.line([(5, 0), (5, 3)], fill=(120, 84, 48))
        d.polygon([(6, 0), (9, 1), (6, 2)], fill=(255, 204, 82))
    elif kind == "detector":
        d.arc([3, 0, 8, 5], 200, 340, fill=(220, 255, 220))
    else:
        d.rectangle([4, 1, 8, 3], fill=(110, 78, 50), outline=(60, 42, 28))
    save12(img, f"icon_robot_{kind}")


def icon_base():
    img, d = canvas12()
    d.rectangle([1, 2, 10, 10], fill=(52, 96, 172), outline=(26, 44, 84))
    d.rectangle([3, 4, 8, 8], fill=(40, 76, 140))
    d.ellipse([4, 4, 7, 7], fill=(120, 190, 255))
    for rx, ry in [(2, 3), (9, 3), (2, 9), (9, 9)]:
        d.point((rx, ry), fill=(220, 232, 250))
    save12(img, "icon_base")


def icon_drone():
    img, d = canvas12()
    d.ellipse([4, 4, 8, 8], fill=(150, 160, 175), outline=(80, 86, 96))
    d.line([(2, 3), (10, 3)], fill=(110, 118, 130), width=2)
    d.ellipse([1, 2, 3, 4], outline=(110, 118, 130))
    d.ellipse([9, 2, 11, 4], outline=(110, 118, 130))
    d.point((6, 6), fill=(120, 190, 255))
    save12(img, "icon_drone")


def icon_upgrade():
    img, d = canvas12()
    d.polygon([(5, 1), (9, 6), (7, 6), (7, 10), (3, 10), (3, 6), (1, 6)],
              fill=(255, 209, 102), outline=(158, 108, 30))
    save12(img, "icon_upgrade")


if __name__ == "__main__":
    gen_panel()
    gen_button("btn_normal", WOOD, WOOD_HI, BORDER_HI)
    gen_button("btn_hover", WOOD_HI, tuple(min(255, c + 14) for c in WOOD_HI), (196, 158, 106))
    gen_button("btn_pressed", WOOD_DK, WOOD, BORDER_WOOD)
    gen_button("btn_disabled", (70, 62, 52), (58, 51, 43), (86, 76, 62), nail=(120, 110, 96), disabled=True)
    icon_coin(); icon_ore(); icon_star()
    icon_heart(True); icon_heart(False)
    icon_clock()
    for k in ("opener", "marker", "detector", "miner"):
        icon_robot(k)
    icon_base(); icon_drone(); icon_upgrade()
