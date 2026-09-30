"""Build native-size transparent pixel sprites for the L4/L5 2D game.

All artwork below is drawn at its final pixel resolution with hard edges.
Run with: python visual_v2/build_l4_l5_sprites.py
"""

from pathlib import Path
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent / "runtime"
for folder in ("boss", "enemies", "robots", "tiles/overlays", "ui/icons", "fx"):
    (ROOT / folder).mkdir(parents=True, exist_ok=True)

INK = (10, 14, 21, 255)
DEEP = (27, 29, 40, 255)
ROCK = (49, 45, 64, 255)
ROCK_HI = (87, 79, 106, 255)
STEEL = (111, 124, 137, 255)
BRASS = (163, 113, 55, 255)
GOLD = (238, 180, 86, 255)
PALE = (249, 226, 173, 255)
CYAN = (55, 210, 221, 255)
RED = (225, 75, 56, 255)
PURPLE = (147, 92, 177, 255)
GREEN = (80, 178, 112, 255)


def canvas(size):
    im = Image.new("RGBA", size, (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def save(im, path):
    im.save(ROOT / path)


def r(d, box, color):
    d.rectangle(box, fill=color)


def p(d, points, color):
    d.polygon(points, fill=color)


def boss(phase, pose):
    """70x32 design pixels, exported with nearest-neighbor 2x scale."""
    im, d = canvas((70, 32))
    shade = [(51, 42, 67, 255), (67, 51, 69, 255), (83, 43, 62, 255)][phase - 1]
    ridge = [(94, 77, 111, 255), (126, 91, 103, 255), (155, 72, 85, 255)][phase - 1]
    eye = GOLD if phase < 3 else RED
    # Far arms and back. Both hands reach down to the board frame.
    p(d, [(7, 25), (9, 16), (15, 12), (21, 15), (20, 28), (14, 31), (7, 30)], INK)
    p(d, [(63, 25), (61, 16), (55, 12), (49, 15), (50, 28), (56, 31), (63, 30)], INK)
    p(d, [(8, 25), (11, 17), (16, 15), (19, 18), (18, 29), (11, 29)], shade)
    p(d, [(62, 25), (59, 17), (54, 15), (51, 18), (52, 29), (59, 29)], shade)
    # Wide dark silhouette, crown, side plates.
    p(d, [(15, 25), (17, 15), (23, 8), (32, 5), (41, 5), (49, 9),
          (55, 18), (54, 28), (46, 31), (24, 31)], INK)
    p(d, [(18, 25), (21, 15), (27, 10), (37, 8), (46, 12),
          (52, 22), (50, 28), (44, 30), (24, 29)], shade)
    p(d, [(21, 17), (26, 11), (33, 9), (31, 18), (24, 22)], ridge)
    p(d, [(39, 9), (45, 12), (50, 18), (48, 22), (40, 16)], ridge)
    # Tooth-rock crest, six readable ivory shapes.
    for x, y, h in [(21, 11, 5), (28, 8, 6), (35, 6, 7), (42, 8, 6), (49, 12, 5)]:
        p(d, [(x - 2, y + h), (x, y), (x + 2, y + h)], INK)
        p(d, [(x - 1, y + h - 1), (x, y + 1), (x + 1, y + h - 1)], PALE)
    # Face opening and pointed teeth.
    r(d, (27, 19, 43, 29), INK)
    r(d, (29, 21, 41, 27), (55, 24, 35, 255))
    for x in (29, 33, 37, 41):
        p(d, [(x, 20), (x + 1, 20), (x, 24)], PALE)
    for x in (31, 36, 40):
        p(d, [(x, 28), (x + 1, 28), (x + 1, 25)], PALE)
    r(d, (26, 17, 30, 18), eye)
    r(d, (40, 17, 44, 18), eye)
    r(d, (27, 17, 28, 17), PALE)
    r(d, (41, 17, 42, 17), PALE)
    # Gripping claws establish contact with board edge.
    for x in (6, 10, 14, 18, 50, 54, 58, 62):
        p(d, [(x, 27), (x + 3, 27), (x + 2, 31), (x, 31)], INK)
        r(d, (x + 1, 29, x + 2, 30), PALE)
    if phase >= 2:
        d.line([(22, 19), (27, 15), (32, 17), (36, 13)], fill=(238, 121, 86, 255), width=1)
        d.line([(46, 22), (42, 25), (40, 29)], fill=(238, 121, 86, 255), width=1)
    if phase == 3:
        r(d, (24, 14, 25, 15), RED)
        r(d, (46, 16, 47, 18), RED)
        r(d, (33, 10, 35, 11), RED)
    if pose == "claw":
        p(d, [(8, 24), (7, 11), (12, 3), (18, 5), (21, 15), (17, 22)], INK)
        p(d, [(9, 21), (10, 10), (13, 5), (17, 7), (19, 17)], ridge)
        for x in (10, 14, 18):
            p(d, [(x, 7), (x + 1, 1), (x + 3, 8)], PALE)
    elif pose == "inhale":
        for x in (25, 33, 42):
            r(d, (x, 5, x + 3, 7), RED)
            r(d, (x + 1, 4, x + 2, 4), GOLD)
        r(d, (29, 22, 41, 30), (85, 32, 41, 255))
    elif pose == "growl":
        r(d, (27, 20, 43, 31), INK)
        r(d, (30, 23, 40, 30), (95, 32, 43, 255))
        for x in (29, 33, 37, 41):
            p(d, [(x, 21), (x + 2, 21), (x + 1, 25)], PALE)
    elif pose == "staggered":
        d.line([(25, 16), (31, 20)], fill=PALE, width=1)
        d.line([(39, 20), (45, 16)], fill=PALE, width=1)
        d.line([(34, 4), (32, 10), (38, 14), (35, 19)], fill=RED, width=2)
    elif pose == "crawl":
        r(d, (4, 28, 11, 30), shade)
        r(d, (59, 28, 66, 30), shade)
        d.line([(20, 26), (17, 23), (13, 26)], fill=ridge, width=3)
    elif pose == "fall":
        # Release hands, bare the mouth; Godot performs the falling motion.
        r(d, (5, 27, 20, 31), (0, 0, 0, 0))
        r(d, (50, 27, 65, 31), (0, 0, 0, 0))
        d.line([(9, 23), (15, 13)], fill=ridge, width=3)
        d.line([(61, 23), (55, 13)], fill=ridge, width=3)
    return im.resize((140, 64), Image.Resampling.NEAREST)


def make_boss():
    poses = ("idle", "claw", "inhale", "growl", "staggered", "crawl", "fall")
    sheet = Image.new("RGBA", (140 * len(poses), 64 * 3))
    for phase in (1, 2, 3):
        for col, pose in enumerate(poses):
            im = boss(phase, pose)
            save(im, f"boss/beast_p{phase}_{pose}.png")
            sheet.alpha_composite(im, (col * 140, (phase - 1) * 64))
    save(sheet, "boss/beast_sheet.png")


def bomb_sprite(kind):
    im, d = canvas((28, 28))
    if kind == "shadow":
        d.ellipse((4, 15, 23, 23), fill=(7, 10, 14, 155))
        d.ellipse((8, 17, 19, 21), outline=(243, 177, 76, 220), width=2)
        p(d, [(12, 6), (16, 6), (16, 12), (19, 12), (14, 17), (9, 12), (12, 12)], GOLD)
        return im
    if kind.startswith("explosion"):
        n = int(kind[-1])
        radius = (5, 8, 11, 7)[n]
        d.ellipse((14-radius, 14-radius, 14+radius, 14+radius), fill=(155, 48, 34, 235))
        d.ellipse((17-radius, 17-radius, 11+radius, 11+radius), fill=GOLD)
        inner = max(2, radius // 2)
        d.ellipse((14-inner, 14-inner, 14+inner, 14+inner), fill=PALE)
        for x, y in ((2, 6), (23, 4), (3, 22), (22, 24)):
            r(d, (x, y, x+2, y+2), RED if n < 2 else BRASS)
        return im
    d.ellipse((4, 7, 23, 25), fill=INK)
    d.ellipse((6, 9, 21, 23), fill=(42, 47, 57, 255))
    p(d, [(8, 12), (12, 9), (18, 10), (16, 13)], STEEL)
    r(d, (11, 7, 16, 9), BRASS)
    r(d, (13, 3, 15, 7), (93, 82, 69, 255))
    if kind == "fuse_0":
        r(d, (13, 1, 16, 3), GOLD)
        r(d, (16, 0, 18, 1), PALE)
    elif kind == "fuse_1":
        p(d, [(15, 1), (17, 0), (18, 3), (16, 5), (13, 3)], RED)
        r(d, (16, 1, 17, 2), PALE)
    else:
        d.line([(6, 22), (3, 17), (2, 17)], fill=GOLD, width=2)
    return im


def make_bomb():
    for name in ("shadow", "fuse_0", "fuse_1", "deflect", "explosion0", "explosion1", "explosion2", "explosion3"):
        save(bomb_sprite(name), f"boss/bomb_{name}.png")


def tentacle_sprite(kind):
    im, d = canvas((28, 28))
    if kind == "root":
        d.ellipse((3, 3, 24, 24), fill=INK)
        d.ellipse((5, 5, 22, 22), fill=(65, 37, 81, 255))
        p(d, [(7, 14), (13, 7), (21, 11), (19, 20), (11, 22)], PURPLE)
        r(d, (11, 11, 16, 16), PALE)
        r(d, (12, 12, 15, 15), GOLD)
    elif kind == "tip":
        p(d, [(1, 8), (12, 5), (21, 9), (26, 14), (18, 18), (9, 20), (1, 19)], INK)
        p(d, [(1, 10), (12, 7), (19, 10), (23, 14), (16, 16), (1, 17)], PURPLE)
        p(d, [(24, 10), (27, 14), (22, 17)], PALE)
    else:
        p(d, [(0, 8), (8, 5), (19, 6), (28, 9), (28, 19), (18, 21), (7, 19), (0, 18)], INK)
        p(d, [(0, 10), (9, 7), (19, 8), (28, 11), (28, 17), (17, 18), (7, 17), (0, 16)], PURPLE)
        for x in (5, 14, 23):
            d.line([(x, 9), (x + 3, 13), (x, 17)], fill=(72, 41, 87, 255), width=2)
        if kind == "broken":
            r(d, (12, 5, 16, 22), (0, 0, 0, 0))
            r(d, (13, 7, 15, 9), PALE)
    return im


def fire_sprite(state):
    im, d = canvas((28, 28))
    d.ellipse((2, 21, 25, 26), fill=(79, 27, 21, 180))
    height = 4 if state == "low" else (0 if state == "0" else 2)
    p(d, [(3, 23), (5, 13+height), (9, 17), (11, 6+height), (16, 13),
          (20, 8+height), (24, 20), (23, 24)], (183, 56, 32, 235))
    p(d, [(7, 23), (9, 17+height), (12, 19), (14, 11+height),
          (18, 17), (20, 13+height), (22, 23)], GOLD)
    p(d, [(12, 22), (14, 17+height), (16, 22)], PALE)
    return im


def blob(name, frame):
    im, d = canvas((22, 22))
    if name == "web":
        p(d, [(11, 7), (3, 1+frame), (1, 7), (6, 11), (2, 17), (9, 15),
              (11, 20), (13, 15), (20, 17), (16, 11), (21, 7), (19, 1+frame)], INK)
        p(d, [(11, 9), (4, 3+frame), (3, 7), (9, 13), (11, 18), (13, 13), (19, 7), (18, 3+frame)], (100, 111, 145, 255))
        r(d, (8, 9, 9, 10), CYAN)
        r(d, (13, 9, 14, 10), CYAN)
    elif name == "lock":
        d.ellipse((2, 8+frame, 19, 19), fill=INK)
        d.ellipse((4, 9+frame, 17, 17), fill=(98, 69, 134, 255))
        for x in (6, 11, 15):
            p(d, [(x-2, 10), (x, 3-frame), (x+2, 10)], (178, 137, 210, 255))
        r(d, (9, 11, 12, 12), PALE)
    elif name == "slow" or name == "slime":
        col = (46, 144, 146, 255) if name == "slow" else (67, 168, 105, 255)
        d.ellipse((2, 8+frame, 19, 20), fill=INK)
        d.ellipse((3, 7+frame, 18, 18), fill=col)
        p(d, [(5, 10+frame), (8, 6+frame), (14, 5+frame), (17, 9+frame), (11, 10+frame)], (130, 217, 192, 255))
        r(d, (7, 12+frame, 8, 13+frame), INK)
        r(d, (14, 12+frame, 15, 13+frame), INK)
        r(d, (5, 17, 7, 18), col)
        r(d, (16, 17, 19, 18), col)
    return im


def nest(state):
    im, d = canvas((28, 28))
    p(d, [(1, 23), (5, 8), (10, 4), (17, 5), (24, 12), (27, 24)], INK)
    p(d, [(4, 22), (7, 10), (11, 7), (17, 8), (23, 14), (24, 23)], ROCK)
    p(d, [(8, 21), (11, 11), (17, 10), (21, 17), (19, 24), (10, 24)], INK)
    p(d, [(11, 21), (13, 13), (17, 13), (19, 19), (17, 23)], (95, 54, 133, 255))
    r(d, (13, 16, 16, 18), CYAN if state == 0 else RED)
    d.line([(3, 14), (8, 11), (11, 5)], fill=ROCK_HI, width=2)
    if state > 0:
        d.line([(6, 7), (11, 12), (8, 19)], fill=GOLD, width=1)
        d.line([(22, 11), (19, 16), (22, 23)], fill=GOLD, width=1)
    if state == 2:
        d.line([(4, 4), (7, 1)], fill=ROCK_HI, width=2)
        d.line([(22, 5), (25, 2)], fill=ROCK_HI, width=2)
    return im


def guard(frame):
    im, d = canvas((24, 24))
    r(d, (4, 17, 19, 21), INK)
    r(d, (5, 18, 18, 20), (47, 60, 69, 255))
    for x in (5, 15):
        r(d, (x, 20, x+3, 22), STEEL)
    p(d, [(4, 16), (5, 8), (9, 5), (17, 5), (20, 9), (20, 17)], INK)
    p(d, [(6, 15), (7, 8), (10, 7), (17, 7), (18, 10), (18, 16)], (56, 112, 119, 255))
    r(d, (8, 10, 16, 13), (18, 33, 43, 255))
    r(d, (10, 11, 14, 12), CYAN)
    r(d, (11, 2, 13, 6), BRASS)
    r(d, (10, 1, 14, 3), GOLD if frame == 0 else RED)
    r(d, (2, 12, 5, 15), STEEL)
    r(d, (19, 12, 22, 15), STEEL)
    r(d, (2, 16, 7, 17), GOLD)
    if frame:
        r(d, (4, 21, 7, 23), (0, 0, 0, 0))
        r(d, (15, 20, 19, 21), GOLD)
    return im


def overlay(kind):
    im, d = canvas((28, 28))
    if kind == "lock":
        d.arc((7, 3, 20, 18), 185, 355, fill=INK, width=4)
        d.arc((8, 4, 19, 17), 185, 355, fill=PALE, width=2)
        r(d, (6, 13, 22, 24), INK)
        r(d, (8, 14, 20, 22), (125, 92, 133, 255))
        r(d, (12, 16, 15, 20), PALE)
    elif kind == "web":
        for a, b in [((2, 3), (25, 23)), ((25, 3), (2, 23)), ((14, 1), (14, 26)), ((1, 14), (26, 14))]:
            d.line([a, b], fill=(171, 178, 196, 230), width=2)
        for box in ((5, 5, 22, 22), (9, 9, 18, 18)):
            d.ellipse(box, outline=(95, 108, 137, 240), width=2)
        d.ellipse((11, 11, 16, 16), fill=(36, 40, 57, 245))
    elif kind.startswith("slime"):
        d.ellipse((3, 17, 24, 25), fill=(28, 100, 101, 170))
        d.ellipse((6, 15, 19, 23), fill=(52, 176, 150, 160))
        d.ellipse((7, 16, 10, 17), fill=(152, 238, 199, 210))
        d.ellipse((19, 13, 23, 17), fill=(51, 161, 146, 190))
        if kind == "slime_wall":
            d.ellipse((4, 10, 9, 15), fill=(57, 167, 149, 170))
    elif kind == "confirmed":
        p(d, [(14, 3), (23, 14), (14, 24), (5, 14)], INK)
        p(d, [(14, 5), (21, 14), (14, 22), (7, 14)], GOLD)
        r(d, (12, 11, 15, 16), INK)
    return im


def tooth():
    im, d = canvas((16, 16))
    p(d, [(4, 2), (7, 4), (9, 4), (12, 2), (14, 5), (12, 10),
          (11, 15), (8, 11), (5, 15), (4, 10), (2, 5)], INK)
    p(d, [(4, 3), (7, 5), (9, 5), (12, 3), (12, 7), (10, 12),
          (8, 9), (6, 12), (4, 8)], PALE)
    r(d, (5, 5, 6, 6), (255, 250, 218, 255))
    return im


def chain_link():
    im, d = canvas((12, 12))
    d.ellipse((1, 1, 7, 8), outline=INK, width=2)
    d.ellipse((4, 3, 10, 10), outline=INK, width=2)
    d.arc((1, 1, 7, 8), 30, 250, fill=GOLD, width=2)
    d.arc((4, 3, 10, 10), 210, 390, fill=PALE, width=2)
    return im


def probe():
    im, d = canvas((24, 24))
    d.ellipse((2, 17, 21, 22), outline=(52, 193, 218, 200), width=2)
    p(d, [(8, 5), (16, 5), (19, 15), (12, 18), (5, 15)], INK)
    p(d, [(9, 7), (15, 7), (17, 14), (12, 16), (7, 14)], STEEL)
    r(d, (10, 9, 14, 12), CYAN)
    r(d, (11, 2, 13, 5), GOLD)
    return im


def make_all():
    make_boss()
    make_bomb()
    for kind in ("root", "middle", "tip", "broken"):
        save(tentacle_sprite(kind), f"boss/tentacle_{kind}.png")
    for state in ("0", "1", "low"):
        save(fire_sprite(state), f"tiles/overlays/fire_{state}.png")
    for name in ("web", "lock", "slow", "slime"):
        for frame in (0, 1):
            save(blob(name, frame), f"enemies/{name}_{frame}.png")
    for state in range(3):
        save(nest(state), f"enemies/nest_{state}.png")
    for frame, name in enumerate(("idle", "move")):
        save(guard(frame), f"robots/robot_guard_{name}.png")
    save(guard(0), "ui/icons/icon_robot_guard.png")
    for kind in ("lock", "web", "slime_wall", "slime_floor", "confirmed"):
        save(overlay(kind), f"tiles/overlays/{kind}.png")
    save(tooth(), "fx/tooth.png")
    save(chain_link(), "fx/chain_link.png")
    save(tooth(), "ui/icons/icon_tooth.png")
    save(probe(), "ui/icons/icon_probe.png")


def make_review_sheet():
    out = Path(__file__).resolve().parent / "review" / "l4_l5_sprite_sheet.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet = Image.new("RGBA", (1120, 700), (19, 22, 31, 255))
    d = ImageDraw.Draw(sheet)
    d.text((12, 7), "L5 BOSS - 3 PHASES x 7 POSES", fill=PALE)
    boss_sheet = Image.open(ROOT / "boss/beast_sheet.png")
    sheet.alpha_composite(boss_sheet, (12, 30))
    rows = [
        ("BOMB", "boss", ["bomb_shadow", "bomb_fuse_0", "bomb_fuse_1", "bomb_deflect", "bomb_explosion0", "bomb_explosion1", "bomb_explosion2", "bomb_explosion3"]),
        ("TENTACLE", "boss", ["tentacle_root", "tentacle_middle", "tentacle_tip", "tentacle_broken"]),
        ("ENEMIES", "enemies", ["web_0", "web_1", "lock_0", "lock_1", "slow_0", "slow_1", "slime_0", "slime_1", "nest_0", "nest_1", "nest_2"]),
        ("OVERLAYS", "tiles/overlays", ["lock", "web", "slime_wall", "slime_floor", "confirmed", "fire_0", "fire_1", "fire_low"]),
    ]
    yy = 252
    for title, folder, names in rows:
        d.text((13, yy), title, fill=GOLD)
        for i, name in enumerate(names):
            src = Image.open(ROOT / folder / f"{name}.png")
            tile = src.resize((src.width * 2, src.height * 2), Image.Resampling.NEAREST)
            x = 138 + i * 86
            sheet.alpha_composite(tile, (x, yy - 5))
            d.text((x, yy + 56), name.replace("bomb_", "").replace("tentacle_", ""), fill=STEEL)
        yy += 88
    for x, file, label in [(27, "robots/robot_guard_idle.png", "GUARD"),
                           (145, "fx/tooth.png", "TOOTH"),
                           (251, "ui/icons/icon_probe.png", "PROBE"),
                           (357, "fx/chain_link.png", "CHAIN")]:
        src = Image.open(ROOT / file)
        tile = src.resize((src.width * 2, src.height * 2), Image.Resampling.NEAREST)
        sheet.alpha_composite(tile, (x, 660 - tile.height))
        d.text((x + 52, 635), label, fill=PALE)
    sheet.convert("RGB").save(out)


if __name__ == "__main__":
    make_all()
    make_review_sheet()
