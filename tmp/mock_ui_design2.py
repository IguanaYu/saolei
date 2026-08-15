#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
UI 视觉稿 第二批：对标小游戏标配查缺后的 9 个缺失页面。

P0 闭环：① 暂停页 ② 放弃确认 ③ 设置页 ④ 闪屏/加载
视觉化：⑤ 结算页 V2（大星级+新纪录+广告位预留）
留存组：⑥ 挖矿档案(统计) ⑦ 每日挑战 ⑧ 每日签到
引导：  ⑨ 新手引导（聚光遮罩）

复用 mock_ui_design.py 的矿洞木石风组件（panel/button/图标/字体）。
输出：tmp/mock_ui_design2.png
"""
import os
import sys
import math
import random
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mock_ui_design as m1

SW, SH = m1.SW, m1.SH
TEXT, TEXT_DIM = m1.TEXT, m1.TEXT_DIM
GOLD, RED, GREEN = m1.GOLD, m1.RED, m1.GREEN
BORDER_WOOD, BORDER_HI = m1.BORDER_WOOD, m1.BORDER_HI
PANEL_BG, PANEL_BG2, SHADOW = m1.PANEL_BG, m1.PANEL_BG2, m1.SHADOW
panel, button, text = m1.panel, m1.button, m1.text
icon_coin, icon_ore = m1.icon_coin, m1.icon_ore
icon_star, icon_heart, icon_clock = m1.icon_star, m1.icon_heart, m1.icon_clock


def dim(img, alpha=150):
    ov = Image.new("RGBA", img.size, (10, 8, 6, alpha))
    return Image.alpha_composite(img.convert("RGBA"), ov).convert("RGB")


# ---------------- 本批新增组件 ----------------

def button_danger(d, x0, y0, x1, y1, label, font_size=16):
    """红色危险按钮（放弃/清存档）"""
    fill1, fill2, bd = (156, 62, 50), (124, 46, 38), (94, 36, 30)
    d.rectangle([x0 + 2, y0 + 3, x1 + 1, y1 + 1], fill=SHADOW)
    d.rectangle([x0, y0, x1 - 2, y1 - 2], fill=bd)
    d.rectangle([x0 + 2, y0 + 2, x1 - 4, y1 - 5], fill=fill1)
    d.rectangle([x0 + 2, y0 + 2, x1 - 4, y0 + (y1 - y0) // 2 - 2], fill=fill2)
    f = m1.FONT(font_size)
    bbox = d.textbbox((0, 0), label, font=f)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    d.text((x0 + (x1 - x0 - tw) // 2 - bbox[0], y0 + (y1 - y0 - th) // 2 - bbox[1]),
           label, font=f, fill=(255, 224, 214))


def toggle(d, x, y, on=True):
    """开关：开=红轨+金钮在右；关=暗轨+钮在左"""
    w, h = 66, 30
    d.rectangle([x + 2, y + 2, x + w + 1, y + h + 1], fill=SHADOW)
    d.rectangle([x, y, x + w - 2, y + h - 2], fill=(168, 80, 64) if on else (60, 50, 40))
    d.rectangle([x + 2, y + 2, x + w - 4, y + h - 4], fill=(196, 96, 74) if on else (44, 36, 28))
    kx = x + w - 30 if on else x + 4
    d.rectangle([kx, y + 3, kx + 24, y + h - 6], fill=(242, 230, 202), outline=(120, 90, 60))
    label, col, lx = (("开", (255, 236, 210), x + 8) if on else ("关", (150, 140, 124), x + 34))
    text(d, (lx, y + 7), label, 12, col)


def slider(d, x, y, w, pct):
    """音量条：暗轨 + 金色填充 + 木钮"""
    h = 16
    d.rectangle([x, y, x + w, y + h], fill=(30, 24, 17), outline=BORDER_WOOD)
    fw = int((w - 4) * pct)
    d.rectangle([x + 2, y + 2, x + 2 + fw, y + h - 2], fill=GOLD)
    kx = x + 2 + fw
    d.rectangle([kx - 5, y - 5, kx + 5, y + h + 5], fill=PANEL_BG2, outline=BORDER_HI)


def big_star(d, cx, cy, r, fill, outline):
    pts = []
    for i in range(10):
        ang = -math.pi / 2 + i * math.pi / 5
        rad = r if i % 2 == 0 else r * 0.44
        pts.append((cx + rad * math.cos(ang), cy + rad * math.sin(ang)))
    d.polygon(pts, fill=fill, outline=outline)


def diamond(d, cx, cy, r, fill, outline):
    d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], fill=fill, outline=outline)


def checkmark(d, cx, cy, col):
    d.line([(cx - 6, cy), (cx - 1, cy + 5)], fill=col, width=3)
    d.line([(cx - 1, cy + 5), (cx + 8, cy - 7)], fill=col, width=3)


def dashed_rect(d, x0, y0, x1, y1, col, dash=12, gap=8, width=2):
    def line_h(ax, bx, ay):
        x = ax
        while x < bx:
            d.line([(x, ay), (min(x + dash, bx), ay)], fill=col, width=width)
            x += dash + gap

    def line_v(ay, by, ax):
        y = ay
        while y < by:
            d.line([(ax, y), (ax, min(y + dash, by))], fill=col, width=width)
            y += dash + gap

    line_h(x0, x1, y0)
    line_h(x0, x1, y1)
    line_v(y0, y1, x0)
    line_v(y0, y1, x1)


def hand_pointer(d, tip, ang_deg=-45):
    """像素手指：从 tip 沿 ang_deg 方向指出（-45=指向左上）"""
    a = math.radians(ang_deg)

    def rot(px, py):
        return (tip[0] + px * math.cos(a) - py * math.sin(a),
                tip[1] + px * math.sin(a) + py * math.cos(a))

    palm = [rot(-13, 2), rot(13, 2), rot(13, 32), rot(-13, 32)]
    finger = [rot(-5, -30), rot(5, -30), rot(6, 6), rot(-6, 6)]
    d.polygon(palm, fill=(246, 240, 228), outline=(70, 58, 46))
    d.polygon(finger, fill=(246, 240, 228), outline=(70, 58, 46))


def badge_new(d, x, y):
    panel(d, x, y, x + 96, y + 34, rivets=False, bg=(150, 60, 48))
    text(d, (x + 48, y + 8), "新纪录!", 12, (255, 224, 214), anchor="ma")


# ---------------- ① 暂停页 ----------------

def screen_pause(base):
    img = dim(base)
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = 400, 100, 880, 620
    panel(d, x0, y0, x1, y1)
    cx = (x0 + x1) // 2
    text(d, (cx, y0 + 26), "暂停", 36, GOLD, anchor="ma")
    text(d, (cx, y0 + 78), "第 2 章 · 水晶洞窟 · 第 3 关", 12, TEXT_DIM, anchor="ma")
    # 本局状态条
    sy = y0 + 108
    d.line([(x0 + 40, sy), (x1 - 40, sy)], fill=BORDER_WOOD, width=2)
    panel(d, x0 + 56, sy + 16, x1 - 56, sy + 64, rivets=False, bg=(50, 38, 24))
    icon_coin(d, x0 + 90, sy + 32); text(d, (x0 + 110, sy + 30), "128", 20, GOLD)
    icon_ore(d, x0 + 184, sy + 32); text(d, (x0 + 204, sy + 30), "34", 20, TEXT)
    for i in range(3):
        icon_heart(d, x0 + 272 + i * 20, sy + 32, full=(i < 2))
    icon_clock(d, x0 + 356, sy + 32); text(d, (x0 + 376, sy + 30), "8:24", 20, TEXT)
    # 按钮列
    by = sy + 92
    for label, st in [("继续挖掘", "selected"), ("重新开始", "normal"), ("设置", "normal")]:
        button(d, x0 + 90, by, x1 - 90, by + 56, label, state=st, font_size=19)
        by += 72
    button_danger(d, x0 + 90, by, x1 - 90, by + 56, "放弃本局", font_size=19)
    text(d, (cx, y1 - 26), "按 ESC 继续", 12, TEXT_DIM, anchor="ma")
    return img


# ---------------- ② 放弃确认框 ----------------

def screen_confirm(base):
    img = screen_pause(base)          # 底层是暂停页
    img = dim(img, 120)               # 再压一层更暗
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = 440, 250, 840, 470
    panel(d, x0, y0, x1, y1)
    cx = (x0 + x1) // 2
    text(d, (cx, y0 + 22), "放弃本局？", 36, GOLD, anchor="ma")
    text(d, (cx, y0 + 82), "本局积分与进度将清零", 12, TEXT_DIM, anchor="ma")
    text(d, (cx, y0 + 106), "已采集矿石可保留一半（+17）", 12, TEXT_DIM, anchor="ma")
    button(d, x0 + 36, y0 + 146, x0 + 186, y0 + 202, "继续挖掘", font_size=16)
    button_danger(d, x1 - 186, y0 + 146, x1 - 36, y0 + 202, "确认放弃", font_size=16)
    return img


# ---------------- ③ 设置页 ----------------

def screen_settings(base):
    img = dim(base)
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = 380, 84, 900, 636
    panel(d, x0, y0, x1, y1)
    cx = (x0 + x1) // 2
    text(d, (cx, y0 + 18), "设置", 36, GOLD, anchor="ma")
    d.line([(x0 + 36, y0 + 66), (x1 - 36, y0 + 66)], fill=BORDER_WOOD, width=2)

    def section(y, s):
        text(d, (x0 + 36, y), "◆ " + s, 12, TEXT_DIM)

    def row(y, label, on=None, pct=None):
        text(d, (x0 + 36, y + 6), label, 20, TEXT)
        if on is not None:
            toggle(d, x1 - 102, y, on=on)
        else:
            slider(d, x1 - 216, y + 7, 180, pct)

    section(y0 + 84, "声音")
    row(y0 + 110, "背景音乐", on=True)
    row(y0 + 162, "音效", on=True)
    row(y0 + 214, "音乐音量", pct=0.7)
    section(y0 + 274, "画面与操作")
    row(y0 + 300, "屏幕震动", on=False)
    row(y0 + 352, "全屏窗口", on=False)
    row(y0 + 404, "显示网格线", on=True)
    d.line([(x0 + 36, y0 + 456), (x1 - 36, y0 + 456)], fill=BORDER_WOOD, width=2)
    section(y0 + 472, "游戏")
    button(d, x0 + 36, y0 + 496, x0 + 250, y0 + 548, "重看新手教程", font_size=14)
    button_danger(d, x1 - 250, y0 + 496, x1 - 36, y0 + 548, "清除全部存档", font_size=14)
    text(d, (cx, y1 - 22), "* 音频系统尚未接入，声音开关为占位", 12, (150, 140, 124), anchor="ma")
    return img


# ---------------- ④ 闪屏 / 加载页 ----------------

def screen_splash():
    pk2 = m1.pk2
    bg = pk2.tile_texture(
        Image.open(os.path.join(m1.OUT_DIR, "cave_bg.png")).convert("RGB"), SW, SH).convert("RGBA")
    rng = random.Random(7)
    props = Image.open(os.path.join(m1.OUT_DIR, "deco_outer_sheet.png")).convert("RGBA")
    for _ in range(10):
        px_, py_ = rng.randrange(0, SW - 28), rng.randrange(140, SH - 28)
        i = rng.randrange(8)
        piece = props.crop(((i % 4) * 28, (i // 4) * 28, (i % 4) * 28 + 28, (i // 4) * 28 + 28))
        bg.paste(piece, (px_, py_), piece)
    img = bg.convert("RGB")
    d = ImageDraw.Draw(img)
    # LOGO（复用主菜单画法）
    tx, ty = SW // 2, 200
    d.rectangle([tx - 190, ty - 6, tx + 190, ty + 78], fill=(24, 18, 12))
    d.rectangle([tx - 186, ty - 2, tx + 186, ty + 74], fill=PANEL_BG2)
    d.rectangle([tx - 186, ty - 2, tx + 186, ty + 6], fill=BORDER_HI)
    text(d, (tx, ty + 10), "扫雷挖矿", 48, GOLD, anchor="ma")
    for sx in (tx - 150, tx + 130):
        d.rectangle([sx + 4, ty + 18, sx + 7, ty + 56], fill=(140, 100, 60))
        d.arc([sx - 8, ty + 10, sx + 20, ty + 40], 200, 340, fill=(190, 196, 205), width=3)
    text(d, (tx, ty + 96), "—— 指挥机器人，挖穿雷区矿洞 ——", 12, TEXT_DIM, anchor="ma")
    # 进度条
    bx0, bx1, by = tx - 220, tx + 220, 420
    panel(d, bx0 - 6, by - 6, bx1 + 6, by + 42, rivets=False, bg=(30, 24, 17))
    d.rectangle([bx0, by, bx1, by + 30], fill=(24, 18, 12), outline=BORDER_WOOD)
    fw = int((bx1 - bx0 - 4) * 0.62)
    d.rectangle([bx0 + 2, by + 2, bx0 + 2 + fw, by + 28], fill=GOLD)
    text(d, ((bx0 + bx1) // 2, by + 9), "正在加载矿洞… 62%", 12, (60, 44, 20), anchor="ma")
    text(d, (tx, by + 60), "首次进入需解压资源，稍安勿躁", 12, TEXT_DIM, anchor="ma")
    # 底部信息（小游戏平台标配元素）
    text(d, (SW // 2, SH - 66), "健康游戏忠告：适度挖矿益脑 · 沉迷雷区伤身", 12, (128, 116, 96), anchor="ma")
    text(d, (SW // 2, SH - 40), "v0.2 · Godot 4.6 · 单机开发版", 12, (128, 116, 96), anchor="ma")
    return img


# ---------------- ⑤ 结算页 V2（视觉化升级） ----------------

def screen_results_v2(base):
    img = dim(base, 155)
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = 360, 84, 920, 604
    panel(d, x0, y0, x1, y1)
    cx = (x0 + x1) // 2
    text(d, (cx - 30, y0 + 20), "矿场完成！", 36, GOLD, anchor="ma")
    badge_new(d, cx + 110, y0 + 24)
    # 大星级（中星弹出动画位 + 光环）
    syc = y0 + 132
    d.ellipse([cx - 52, syc - 58, cx + 52, syc + 44], outline=(255, 240, 180), width=2)
    big_star(d, cx - 92, syc, 32, (255, 226, 120), (170, 120, 30))
    big_star(d, cx, syc - 10, 40, (255, 226, 120), (170, 120, 30))
    big_star(d, cx + 92, syc, 32, (70, 60, 48), (50, 42, 34))
    text(d, (cx, syc + 56), "★ 完成目标 · ★ 剩余 2 心 · ☆ 剩余时间 > 60s", 12, TEXT_DIM, anchor="ma")
    # 分项奖励（图标化，滚动计数动画位）
    rows = [
        (icon_coin, "开格积分", "+820"),
        (icon_ore, "矿石结算", "×34 → +170"),
        (icon_clock, "剩余时间加成", "+260"),
        (icon_heart, "命数加成", "×1.5"),
    ]
    ry = y0 + 206
    for fn, k, v in rows:
        fn(d, x0 + 70, ry + 4)
        text(d, (x0 + 98, ry), k, 20, TEXT)
        text(d, (x1 - 70, ry), v, 20, TEXT, anchor="ra")
        ry += 38
    d.line([(x0 + 48, ry + 4), (x1 - 48, ry + 4)], fill=BORDER_WOOD, width=2)
    text(d, (x0 + 70, ry + 16), "最终积分", 20, GOLD)
    text(d, (x1 - 70, ry + 8), "4820", 36, GOLD, anchor="ra")
    # 三按钮
    button(d, x0 + 48, y1 - 96, x0 + 208, y1 - 40, "再来一局", state="selected", font_size=16)
    button(d, cx - 80, y1 - 96, cx + 80, y1 - 40, "选关", font_size=16)
    button(d, x1 - 208, y1 - 96, x1 - 48, y1 - 40, "分享成绩", font_size=16)
    # 广告位预留（腾讯规范建议位：结算页底部）
    dashed_rect(d, 320, 628, 960, 696, (150, 140, 124))
    text(d, (SW // 2, 652), "广告位预留 640 × 100 · 结算页底部", 12, (150, 140, 124), anchor="ma")
    return img


# ---------------- ⑥ 挖矿档案（统计页） ----------------

def screen_stats(base):
    img = dim(base)
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = 280, 84, 1000, 636
    panel(d, x0, y0, x1, y1)
    cx = (x0 + x1) // 2
    text(d, (cx, y0 + 18), "挖矿档案", 36, GOLD, anchor="ma")
    text(d, (cx, y0 + 68), "总游戏时长 6.4 小时 · 从 2026-08-01 开始挖矿", 12, TEXT_DIM, anchor="ma")
    # 顶部数据卡
    cards = [("87", "总局数", TEXT), ("76%", "胜率", TEXT), ("2:41", "最佳时间", GOLD), ("8", "最高连胜", TEXT)]
    cw, ch = 158, 84
    sx = cx - (4 * cw + 3 * 12) // 2
    for i, (v, k, col) in enumerate(cards):
        cxx = sx + i * (cw + 12)
        panel(d, cxx, y0 + 92, cxx + cw, y0 + 92 + ch, rivets=False, bg=(50, 38, 24))
        text(d, (cxx + cw // 2, y0 + 104), v, 24, col, anchor="ma")
        text(d, (cxx + cw // 2, y0 + 92 + 52), k, 12, TEXT_DIM, anchor="ma")
    # 12 章星数总览
    text(d, (x0 + 36, y0 + 196), "◆ 章节星数", 12, TEXT_DIM)
    stars = [12, 11, 9, 8, 6, 4, 2, 0, -1, -1, -1, -1]   # -1 = 未解锁
    sw_, sh_, sg = 100, 74, 10
    sx = cx - (6 * sw_ + 5 * sg) // 2
    for idx, st in enumerate(stars):
        col_i, row_i = idx % 6, idx // 6
        cxx = sx + col_i * (sw_ + sg)
        cyy = y0 + 220 + row_i * (sh_ + sg)
        locked = st < 0
        panel(d, cxx, cyy, cxx + sw_, cyy + sh_, rivets=False, bg=(34, 27, 19) if locked else (46, 35, 24))
        if locked:
            text(d, (cxx + sw_ // 2, cyy + 12), f"第{idx + 1}章", 12, (110, 100, 86), anchor="ma")
            text(d, (cxx + sw_ // 2, cyy + 40), "未解锁", 12, (110, 100, 86), anchor="ma")
        else:
            text(d, (cxx + sw_ // 2, cyy + 10), f"第{idx + 1}章", 12, TEXT, anchor="ma")
            text(d, (cxx + sw_ // 2, cyy + 32), f"★{st}/15", 12, GOLD, anchor="ma")
            d.rectangle([cxx + 12, cyy + 56, cxx + 88, cyy + 62], fill=(30, 24, 17))
            d.rectangle([cxx + 12, cyy + 56, cxx + 12 + int(76 * st / 15), cyy + 62], fill=GOLD)
    # 底部汇总
    d.line([(x0 + 36, y0 + 400), (x1 - 36, y0 + 400)], fill=BORDER_WOOD, width=2)
    text(d, (x0 + 60, y0 + 420), "总星数", 20, TEXT_DIM)
    text(d, (x0 + 160, y0 + 412), "128 / 180", 36, GOLD)
    text(d, (x1 - 60, y0 + 424), "完美通关（3★）9 关", 20, TEXT, anchor="ra")
    text(d, (cx, y1 - 24), "仅统计正式关卡 · 每日挑战成绩单列", 12, (150, 140, 124), anchor="ma")
    return img


# ---------------- ⑦ 每日挑战 ----------------

def screen_daily(base):
    img = dim(base)
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = 360, 90, 920, 630
    panel(d, x0, y0, x1, y1)
    cx = (x0 + x1) // 2
    text(d, (cx, y0 + 18), "每日挑战", 36, GOLD, anchor="ma")
    text(d, (cx, y0 + 68), "8 月 15 日 · 全球同图 · 第 227 期", 12, TEXT_DIM, anchor="ma")
    # 今日地图卡
    panel(d, 392, y0 + 92, 888, y0 + 184, rivets=False, bg=(50, 38, 24))
    text(d, (cx, y0 + 106), "今日矿场：水晶洞窟", 24, GOLD, anchor="ma")
    text(d, (cx, y0 + 148), "12 × 12 · 25 雷 · 无猜盘面（可纯逻辑解开）", 12, TEXT, anchor="ma")
    # 个人记录
    for px0, k, v, col in [(392, "今日最佳", "3:12", GOLD), (642, "历史最佳", "2:48", TEXT)]:
        panel(d, px0, y0 + 204, px0 + 226, y0 + 268, rivets=False, bg=(46, 35, 24))
        text(d, (px0 + 113, y0 + 214), k, 12, TEXT_DIM, anchor="ma")
        text(d, (px0 + 113, y0 + 234), v, 24, col, anchor="ma")
    # 本周徽章（一二三四五六日）
    text(d, (cx, y0 + 288), "◆ 本周徽章", 12, TEXT_DIM, anchor="ma")
    bx = cx - (7 * 60 + 6 * 12) // 2
    for i in range(7):
        sx = bx + i * 72
        sy = y0 + 308
        state = "earned" if i < 3 else ("today" if i == 3 else "future")
        if state == "today":
            panel(d, sx, sy, sx + 60, sy + 60, rivets=False, bg=(70, 52, 28))
            d.rectangle([sx, sy, sx + 59, sy + 59], outline=GOLD, width=2)
            diamond(d, sx + 30, sy + 24, 14, (255, 226, 120), (170, 120, 30))
            d.ellipse([sx + 14, sy + 8, sx + 46, sy + 40], outline=(255, 240, 180))
            d.rectangle([sx + 42, sy + 2, sx + 58, sy + 16], fill=RED)
            text(d, (sx + 50, sy + 3), "今", 12, (255, 224, 214), anchor="ma")
        elif state == "earned":
            panel(d, sx, sy, sx + 60, sy + 60, rivets=False, bg=(50, 38, 24))
            diamond(d, sx + 30, sy + 24, 14, (255, 226, 120), (170, 120, 30))
        else:
            panel(d, sx, sy, sx + 60, sy + 60, rivets=False, bg=(34, 27, 19))
            diamond(d, sx + 30, sy + 24, 14, (70, 60, 48), (50, 42, 34))
        wd = "一二三四五六日"[i]
        wcol = TEXT_DIM if state == "future" else TEXT
        text(d, (sx + 30, sy + 42), wd, 12, wcol, anchor="ma")
    text(d, (cx, y0 + 380), "本周徽章 3 / 5 · 集齐 5 枚 → 矿石宝箱 ×30", 12, TEXT_DIM, anchor="ma")
    text(d, (cx, y0 + 406), "距离明日刷新 07:42:13", 20, TEXT, anchor="ma")
    button(d, 500, y0 + 440, 780, y0 + 496, "开始今日挑战", state="selected", font_size=19)
    text(d, (cx, y1 - 24), "挑战独立于章节进度 · 失败不扣命 · 每日一次计徽章", 12, (150, 140, 124), anchor="ma")
    return img


# ---------------- ⑧ 每日签到 ----------------

def screen_signin(base):
    img = dim(base)
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = 300, 130, 980, 560
    panel(d, x0, y0, x1, y1)
    cx = (x0 + x1) // 2
    text(d, (cx - 90, y0 + 16), "矿工签到", 36, GOLD, anchor="ma")
    panel(d, x1 - 236, y0 + 24, x1 - 36, y0 + 58, rivets=False, bg=(70, 52, 28))
    text(d, (x1 - 136, y0 + 32), "已连签 3 天", 12, GOLD, anchor="ma")
    # 7 天奖励格
    days = [
        (icon_coin, "×50", "claimed"), (icon_coin, "×80", "claimed"),
        (icon_ore, "×10", "claimed"), (icon_ore, "×20", "today"),
        (icon_coin, "×150", "locked"), (icon_ore, "×40", "locked"),
        (icon_star, "金色皮肤", "special"),
    ]
    bx = cx - (7 * 84 + 6 * 8) // 2
    for i, (fn, reward, state) in enumerate(days):
        sx = bx + i * 92
        sy = y0 + 80
        bg = {"claimed": (34, 27, 19), "today": (70, 52, 28),
              "locked": (44, 35, 24), "special": (50, 38, 24)}[state]
        panel(d, sx, sy, sx + 84, sy + 150, rivets=False, bg=bg)
        if state == "today":
            d.rectangle([sx, sy, sx + 83, sy + 149], outline=GOLD, width=2)
        if state == "special":
            d.rectangle([sx, sy, sx + 83, sy + 149], outline=(196, 96, 74), width=2)
        text(d, (sx + 42, sy + 12), f"第{i + 1}天", 12,
             TEXT if state != "claimed" else (110, 100, 86), anchor="ma")
        fn(d, sx + 36, sy + 42)
        text(d, (sx + 42, sy + 62), reward, 12,
             GOLD if state in ("today", "special") else TEXT_DIM, anchor="ma")
        if state == "claimed":
            checkmark(d, sx + 62, sy + 26, GREEN)
            text(d, (sx + 42, sy + 118), "已领取", 12, (110, 100, 86), anchor="ma")
        elif state == "today":
            text(d, (sx + 42, sy + 116), "可领取", 12, GOLD, anchor="ma")
        elif state == "special":
            text(d, (sx + 42, sy + 116), "第 7 天大奖", 12, (255, 224, 214), anchor="ma")
        else:
            text(d, (sx + 42, sy + 118), "未达成", 12, (110, 100, 86), anchor="ma")
    text(d, (cx, y0 + 252), "连签 7 天额外解锁：机器人皮肤「金色矿工」", 12, TEXT_DIM, anchor="ma")
    button(d, 490, y0 + 288, 790, y0 + 344, "领取今日奖励", state="selected", font_size=19)
    text(d, (cx, y0 + 368), "中断签到将从第 1 天重新计数 · 奖励每日 5:00 刷新", 12, (150, 140, 124), anchor="ma")
    return img


# ---------------- ⑨ 新手引导 ----------------

def screen_tutorial():
    base, _ = m1.game_backdrop()
    img = m1.screen_shop(m1.screen_hud(base))   # 完整局内画面
    # 聚光遮罩：只亮「开墙型」按钮
    spot = (132, 610, 306, 698)
    bright = img.crop(spot)
    ov = Image.new("RGBA", img.size, (10, 8, 6, 175))
    img = Image.alpha_composite(img.convert("RGBA"), ov)
    img.paste(bright, spot[:2])
    img = img.convert("RGB")
    d = ImageDraw.Draw(img)
    dashed_rect(d, *spot, (255, 209, 102), dash=10, gap=6)
    # 指引气泡（左侧空区，尾巴指向聚光区）
    panel(d, 56, 320, 348, 466)
    text(d, (80, 340), "引导 2 / 6", 12, GOLD)
    text(d, (80, 366), "购买「开墙型」机器人", 20, TEXT)
    text(d, (80, 398), "它会在岩壁上凿出缺口", 20, TEXT)
    text(d, (80, 430), "让你指挥其他机器人进入矿脉", 12, TEXT_DIM)
    d.polygon([(150, 466), (186, 466), (206, 588), (166, 588)], fill=m1.BORDER_WOOD)
    d.polygon([(156, 466), (180, 466), (196, 576), (172, 576)], fill=PANEL_BG)
    # 手指指向按钮
    hand_pointer(d, (298, 648), ang_deg=-45)
    # 步骤 chip + 跳过
    panel(d, 16, 76, 170, 112, rivets=False, bg=(50, 38, 24))
    text(d, (93, 88), "新手引导", 12, TEXT, anchor="ma")
    panel(d, SW - 216, 76, SW - 20, 112, rivets=False, bg=(50, 38, 24))
    text(d, (SW - 118, 88), "跳过 ›", 12, GOLD, anchor="ma")
    return img


# ---------------- 组装输出 ----------------

def main():
    base, _ = m1.game_backdrop()
    screens = [
        ("① 暂停页：本局状态条 + 继续/重开/设置/放弃(红) —— 补上局内唯一出口", lambda: screen_pause(base)),
        ("② 放弃确认：二次确认防误触 · 「矿石保留一半」降低放弃挫败感", lambda: screen_confirm(base)),
        ("③ 设置页：开关+音量条 · 重看教程入口(官方要求) · 清存档放红色危险区", lambda: screen_settings(base)),
        ("④ 闪屏/加载：LOGO+进度条+版本号+健康忠告 —— 小游戏平台标配", screen_splash),
        ("⑤ 结算V2：大星级+弹出光环+新纪录角标+分项图标化 · 底部虚线=广告位预留", lambda: screen_results_v2(base)),
        ("⑥ 挖矿档案：总局数/胜率/最佳时间/连胜 + 12章星数总览(扫雷类标配统计页)", lambda: screen_stats(base)),
        ("⑦ 每日挑战：全球同图拼时间+无猜盘面 · 本周徽章集宝箱 · 刷新倒计时", lambda: screen_daily(base)),
        ("⑧ 矿工签到：7天递增+今日高亮可领 · 第7天皮肤大奖 · 断签重计提示", lambda: screen_signin(base)),
        ("⑨ 新手引导：聚光遮罩只亮目标按钮 + 指引气泡 + 2/6步骤 + 跳过入口", screen_tutorial),
    ]
    TITLE_H, GAP = 36, 8
    total_h = sum(SH + TITLE_H + GAP for _ in screens) + GAP
    canvas = Image.new("RGB", (SW + GAP * 2, total_h), (24, 22, 20))
    font_title = m1.FONT(24)
    y = GAP
    for title, fn in screens:
        td = ImageDraw.Draw(canvas)
        canvas.paste(fn(), (GAP, y + TITLE_H))
        td.rectangle([GAP, y, GAP + SW - 1, y + TITLE_H - 2], fill=(46, 42, 38))
        td.text((GAP + 12, y + 6), title, font=font_title, fill=(240, 232, 216))
        y += SH + TITLE_H + GAP
    out = os.path.join(m1.TMP, "mock_ui_design2.png")
    canvas.save(out)
    print("saved", out, canvas.size)


if __name__ == "__main__":
    main()
