"""Build the V2 pixel-art runtime pack from the approved drawn source art.

The large menu background and robot/emblem source images are generated art.
Small repeating textures and exact game symbols are drawn at native pixel size.
Only writes inside visual_v2/runtime.
"""

from pathlib import Path
import math
import random

import numpy as np
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent
OUT = ROOT / "runtime"
SOURCE = ROOT / "source"
for folder in ("tiles", "robots", "ui", "ui/icons", "branding", "backgrounds"):
    (OUT / folder).mkdir(parents=True, exist_ok=True)

INK = (12, 16, 23)
DEEP = (20, 23, 31)
PANEL = (27, 29, 35)
SLATE = (57, 63, 73)
STEEL = (111, 121, 132)
BRASS = (156, 113, 55)
GOLD = (214, 159, 75)
GOLD_HI = (250, 205, 107)
CYAN = (54, 205, 228)
AMBER = (255, 177, 44)
RED = (224, 65, 60)
VIOLET = (174, 86, 242)
TEXT = (242, 227, 197)


def save(image, path):
    image.save(OUT / path)


def periodic_noise(size, grid, seed):
    rng = np.random.default_rng(seed)
    values = rng.random((grid, grid))
    coords = np.arange(size) * grid / size
    base = np.floor(coords).astype(int)
    frac = coords - base
    frac = frac * frac * (3 - 2 * frac)
    x0, y0 = np.meshgrid(base, base)
    fx, fy = np.meshgrid(frac, frac)
    x1, y1 = (x0 + 1) % grid, (y0 + 1) % grid
    a = values[y0 % grid, x0 % grid] * (1 - fx) + values[y0 % grid, x1] * fx
    b = values[y1, x0 % grid] * (1 - fx) + values[y1, x1] * fx
    return a * (1 - fy) + b * fy


def terrain(size, lo, hi, seed, kind):
    layers = ((7, 0.48), (15, 0.27), (31, 0.16), (61, 0.09))
    n = sum(periodic_noise(size, g, seed + i * 97) * amp
            for i, (g, amp) in enumerate(layers))
    ys = np.arange(size)[:, None]
    xs = np.arange(size)[None, :]
    if kind == "wall":
        # Uneven strata are periodic over the whole atlas and do not mark cells.
        warped_y = ys + (periodic_noise(size, 7, seed + 401) - 0.5) * 22
        strata = np.sin(warped_y * 2 * math.pi * 11 / size)
        n = n * 0.82 + (strata + 1) * 0.055
        n += np.sin((xs + ys * 0.21) * 2 * math.pi * 4 / size) * 0.025
    elif kind == "floor":
        n = n * 0.52 + 0.15
    else:
        n = n * 0.55 + 0.08
    n = np.clip(np.round(n * 10) / 10, 0, 1)
    low, high = np.array(lo), np.array(hi)
    rgb = low[None, None, :] + n[:, :, None] * (high - low)[None, None, :]
    return Image.fromarray(np.uint8(np.clip(rgb, 0, 255)), "RGB")


THEMES = {
    "V2": ((39, 43, 53), (91, 93, 98), (43, 34, 28), (70, 52, 37), AMBER),
    "V2C": ((32, 45, 63), (76, 105, 124), (27, 40, 53), (48, 70, 83), CYAN),
    "V2M": ((36, 48, 42), (82, 108, 81), (32, 43, 34), (54, 73, 49), (118, 211, 119)),
    "V2R": ((59, 48, 43), (129, 104, 79), (45, 37, 30), (77, 60, 42), GOLD_HI),
}


def make_terrain():
    for i, (name, colors) in enumerate(THEMES.items()):
        wlo, whi, flo, fhi, accent = colors
        save(terrain(336, wlo, whi, 610 + i * 200, "wall"), f"tiles/wall_{name}.png")
        save(terrain(336, flo, fhi, 711 + i * 200, "floor"), f"tiles/floor_{name}.png")
        deco = Image.new("RGBA", (112, 56))
        d = ImageDraw.Draw(deco)
        rng = random.Random(530 + i)
        for k in range(8):
            ox, oy = (k % 4) * 28, (k // 4) * 28
            if k % 4 == 0:
                d.line([(ox + 7, oy + 5), (ox + 12, oy + 10), (ox + 9, oy + 17),
                        (ox + 16, oy + 23)], fill=(*INK, 190), width=1)
                d.line([(ox + 12, oy + 10), (ox + 20, oy + 8)], fill=(*STEEL, 120))
            elif k % 4 == 1:
                for _ in range(5):
                    x, y = ox + rng.randrange(5, 23), oy + rng.randrange(5, 22)
                    d.rectangle((x, y, x + 2, y + 2), fill=(*accent, 170))
                    d.point((x, y), fill=(*TEXT, 210))
            elif k % 4 == 2:
                d.ellipse((ox + 6, oy + 8, ox + 17, oy + 16), fill=(*SLATE, 160))
                d.line((ox + 7, oy + 8, ox + 13, oy + 7), fill=(*STEEL, 150))
            else:
                for j in range(3):
                    x = ox + 7 + j * 5
                    d.line((x, oy + 6 + j, x + 2, oy + 15 + j), fill=(*accent, 140))
        save(deco, f"tiles/deco_{name}_sheet.png")
    save(terrain(336, (13, 17, 25), (28, 32, 42), 833, "background"), "tiles/cave_bg.png")


def make_edges_and_frame():
    for side in "TBLR":
        horizontal = side in "TB"
        size = (28, 4) if horizontal else (4, 28)
        im = Image.new("RGBA", size)
        d = ImageDraw.Draw(im)
        rng = random.Random(110 + ord(side))
        for p in range(28):
            notch = rng.choice((0, 0, 1))
            if horizontal:
                yy = 0 if side == "T" else 3
                d.point((p, yy), fill=(*INK, 255))
                d.point((p, 1 + notch if side == "T" else 2 - notch), fill=(*GOLD, 115))
            else:
                xx = 0 if side == "L" else 3
                d.point((xx, p), fill=(*INK, 255))
                d.point((1 + notch if side == "L" else 2 - notch, p), fill=(*GOLD, 115))
        save(im, f"tiles/wall_edge_{side}.png")

    def frame(w, h, side):
        im = Image.new("RGBA", (w, h), (*DEEP, 255))
        d = ImageDraw.Draw(im)
        if side in "TB":
            d.rectangle((0, 0, w - 1, h - 1), fill=(*INK, 255))
            y = 1 if side == "T" else h - 5
            d.rectangle((0, y, w - 1, y + 3), fill=(*BRASS, 255))
            d.line((0, y, w - 1, y), fill=(*GOLD_HI, 255))
            d.line((0, y + 4, w - 1, y + 4), fill=(*SLATE, 255))
            d.rectangle((12, y + 1, 15, y + 3), fill=(*STEEL, 255))
            d.point((13, y + 2), fill=(*CYAN, 255))
        else:
            d.rectangle((0, 0, w - 1, h - 1), fill=(*INK, 255))
            x = 1 if side == "L" else w - 5
            d.rectangle((x, 0, x + 3, h - 1), fill=(*BRASS, 255))
            d.line((x, 0, x, h - 1), fill=(*GOLD_HI, 255))
            d.line((x + 4, 0, x + 4, h - 1), fill=(*SLATE, 255))
            d.rectangle((x + 1, 12, x + 3, 15), fill=(*STEEL, 255))
            d.point((x + 2, 13), fill=(*CYAN, 255))
        return im

    for side in "TB":
        save(frame(28, 20, side), f"tiles/frame_{side}.png")
    for side in "LR":
        save(frame(20, 28, side), f"tiles/frame_{side}.png")
    for side in ("TL", "TR", "BL", "BR"):
        im = Image.new("RGBA", (20, 20), (*INK, 255))
        d = ImageDraw.Draw(im)
        d.rectangle((1, 1, 18, 18), outline=(*BRASS, 255), width=3)
        d.line((2, 2, 17, 2), fill=(*GOLD_HI, 255))
        d.rectangle((7, 7, 12, 12), fill=(*STEEL, 255))
        d.rectangle((9, 9, 10, 10), fill=(*CYAN, 255))
        save(im, f"tiles/frame_{side}.png")


def make_specials_and_props():
    def canvas():
        im = Image.new("RGBA", (28, 28))
        return im, ImageDraw.Draw(im)

    im, d = canvas()
    d.rectangle((3, 19, 24, 25), fill=(*INK, 255), outline=(*BRASS, 255))
    d.rectangle((5, 10, 22, 21), fill=(*SLATE, 255), outline=(*GOLD, 255))
    d.rectangle((8, 13, 19, 18), fill=(*DEEP, 255))
    d.rectangle((11, 14, 16, 17), fill=(*CYAN, 255))
    d.rectangle((12, 5, 15, 9), fill=(*STEEL, 255))
    d.point((13, 5), fill=(*CYAN, 255))
    save(im, "tiles/special_base.png")

    im, d = canvas()
    d.line((8, 5, 8, 23), fill=(*GOLD_HI, 255), width=2)
    d.polygon(((10, 5), (23, 7), (18, 11), (23, 15), (10, 14)), fill=(*RED, 255))
    d.line((10, 5, 22, 7), fill=(255, 144, 104, 255))
    d.rectangle((5, 23, 13, 25), fill=(*BRASS, 255))
    save(im, "tiles/special_flag.png")

    im, d = canvas()
    d.polygon(((5, 18), (9, 9), (15, 12), (19, 5), (24, 18), (17, 23), (9, 22)),
              fill=(*BRASS, 255), outline=(*INK, 255))
    for box in ((9, 10, 14, 16), (16, 7, 21, 15), (14, 17, 20, 22)):
        d.rectangle(box, fill=(*AMBER, 255))
    d.point((11, 10), fill=(*TEXT, 255))
    d.point((17, 7), fill=(*TEXT, 255))
    save(im, "tiles/special_vein.png")

    im, d = canvas()
    d.polygon(((3, 5), (12, 9), (24, 4), (17, 16), (22, 24), (10, 20), (4, 25)),
              fill=(*DEEP, 255), outline=(*RED, 255))
    d.line((12, 9, 10, 20), fill=(*RED, 255), width=2)
    d.line((17, 16, 10, 20), fill=(*AMBER, 255))
    save(im, "tiles/special_collapse.png")

    # Eight perimeter props in the 4x2, 28px atlas expected by CaveEnv.
    sheet = Image.new("RGBA", (112, 56))
    for i in range(8):
        tile, d = canvas()
        if i == 0:  # hanging lantern
            d.line((14, 0, 14, 7), fill=(*BRASS, 255), width=2)
            d.rectangle((9, 8, 19, 20), fill=(*BRASS, 255), outline=(*INK, 255))
            d.rectangle((11, 10, 17, 18), fill=(*AMBER, 255))
        elif i == 1:  # ore cart
            d.rectangle((4, 10, 23, 20), fill=(*SLATE, 255), outline=(*GOLD, 255))
            d.ellipse((6, 19, 11, 24), fill=(*INK, 255), outline=(*STEEL, 255))
            d.ellipse((17, 19, 22, 24), fill=(*INK, 255), outline=(*STEEL, 255))
            d.polygon(((8, 10), (10, 4), (17, 6), (20, 10)), fill=(*AMBER, 255))
        elif i == 2:  # signal beacon
            d.rectangle((10, 11, 17, 25), fill=(*SLATE, 255), outline=(*BRASS, 255))
            d.rectangle((11, 5, 16, 13), fill=(*CYAN, 255))
        elif i == 3:  # red crystal
            d.polygon(((10, 22), (7, 10), (13, 3), (20, 11), (18, 23)), fill=(*RED, 255))
            d.line((13, 4, 13, 20), fill=(255, 143, 114, 255))
        elif i == 4:  # crate
            d.rectangle((5, 7, 22, 23), fill=(*BRASS, 255), outline=(*INK, 255))
            d.line((7, 9, 20, 21), fill=(*GOLD_HI, 255))
            d.line((20, 9, 7, 21), fill=(*INK, 255))
        elif i == 5:  # rocks
            d.ellipse((3, 15, 16, 23), fill=(*SLATE, 255))
            d.ellipse((11, 9, 25, 22), fill=(*STEEL, 255))
        elif i == 6:  # pickaxe
            d.line((7, 22, 20, 5), fill=(*BRASS, 255), width=3)
            d.arc((5, 1, 22, 13), 180, 355, fill=(*STEEL, 255), width=3)
        else:  # cave fungi
            for x, y in ((7, 15), (15, 12), (21, 18)):
                d.line((x, y, x, 24), fill=(*STEEL, 255))
                d.ellipse((x - 3, y - 3, x + 3, y), fill=(*VIOLET, 255))
        sheet.alpha_composite(tile, ((i % 4) * 28, (i // 4) * 28))
    save(sheet, "tiles/deco_outer_sheet.png")


def cropped_source(name, box_size):
    source = Image.open(SOURCE / name).convert("RGBA")
    alpha = source.getchannel("A")
    bbox = alpha.point(lambda a: 255 if a > 30 else 0).getbbox()
    if bbox is None:
        raise ValueError(f"No alpha subject in {name}")
    subject = source.crop(bbox)
    w, h = subject.size
    scale = min(box_size / w, box_size / h)
    target = (max(1, round(w * scale)), max(1, round(h * scale)))
    # Source art is already pixelated; box sampling preserves its visible mass.
    subject = subject.resize(target, Image.Resampling.BOX)
    a = subject.getchannel("A").point(lambda value: 255 if value >= 110 else 0)
    subject.putalpha(a)
    result = Image.new("RGBA", (box_size + 2, box_size + 2))
    result.alpha_composite(subject, ((result.width - target[0]) // 2,
                                     (result.height - target[1]) // 2))
    return result


def make_robots_and_branding():
    for kind in ("opener", "marker", "detector", "miner"):
        icon = cropped_source(f"robot_{kind}.png", 22)
        save(icon, f"robots/robot_{kind}_idle.png")
        moving = icon.copy()
        d = ImageDraw.Draw(moving)
        accent = {"opener": CYAN, "marker": RED, "detector": VIOLET, "miner": AMBER}[kind]
        d.point((6, 21), fill=(*accent, 255))
        d.point((17, 21), fill=(*accent, 255))
        save(moving, f"robots/robot_{kind}_move.png")
        save(icon, f"ui/icons/icon_robot_{kind}.png")
    save(cropped_source("menu_emblem.png", 94).resize((128, 128), Image.Resampling.NEAREST),
         "branding/menu_emblem.png")


def make_ui():
    im = Image.new("RGBA", (48, 48), (*PANEL, 255))
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, 47, 47), outline=(*INK, 255), width=2)
    d.rectangle((2, 2, 45, 45), outline=(*BRASS, 255), width=2)
    d.line((4, 4, 43, 4), fill=(*GOLD_HI, 255))
    d.line((4, 43, 43, 43), fill=(*SLATE, 255))
    for x, y in ((8, 8), (39, 8), (8, 39), (39, 39)):
        d.rectangle((x - 2, y - 2, x + 2, y + 2), fill=(*STEEL, 255))
        d.point((x, y), fill=(*CYAN, 255))
    save(im, "ui/panel_metal.png")

    button_specs = {
        "normal": (40, 42, 48, BRASS),
        "hover": (56, 61, 68, GOLD_HI),
        "pressed": (31, 33, 38, GOLD),
        "disabled": (32, 34, 38, SLATE),
    }
    for name, (*fill, edge) in button_specs.items():
        im = Image.new("RGBA", (44, 32), (*fill, 255))
        d = ImageDraw.Draw(im)
        d.rectangle((0, 0, 43, 31), outline=(*INK, 255), width=2)
        d.rectangle((2, 2, 41, 29), outline=(*edge, 255), width=2)
        if name != "disabled":
            d.line((5, 4, 38, 4), fill=(*GOLD_HI, 255))
            for x in (6, 37):
                for y in (7, 24):
                    d.point((x, y), fill=(*CYAN, 255))
        else:
            d.line((5, 4, 38, 4), fill=(*SLATE, 255))
        save(im, f"ui/btn_{name}.png")

    def icon(name, draw):
        im = Image.new("RGBA", (12, 12))
        d = ImageDraw.Draw(im)
        draw(d)
        save(im.resize((24, 24), Image.Resampling.NEAREST), f"ui/icons/icon_{name}.png")

    icon("coin", lambda d: (d.ellipse((1, 1, 10, 10), fill=(*AMBER, 255), outline=(*BRASS, 255)),
                            d.ellipse((3, 3, 8, 8), outline=(*GOLD_HI, 255))))
    icon("ore", lambda d: (d.polygon(((5, 0), (10, 4), (8, 10), (2, 11), (0, 5)),
                                     fill=(*CYAN, 255), outline=(*STEEL, 255)),
                           d.point((4, 3), fill=(*TEXT, 255))))
    icon("star", lambda d: d.polygon(((5, 0), (7, 4), (11, 4), (8, 7), (9, 11),
                                      (5, 9), (1, 11), (2, 7), (0, 4), (4, 4)),
                                     fill=(*GOLD_HI, 255), outline=(*BRASS, 255)))

    def heart(draw, full):
        c = RED if full else SLATE
        draw.ellipse((1, 2, 5, 6), fill=(*c, 255))
        draw.ellipse((6, 2, 10, 6), fill=(*c, 255))
        draw.polygon(((1, 5), (10, 5), (5, 11)), fill=(*c, 255))
        if full:
            draw.point((3, 3), fill=(255, 170, 156, 255))

    icon("heart", lambda d: heart(d, True))
    icon("heart_empty", lambda d: heart(d, False))
    icon("clock", lambda d: (d.ellipse((1, 1, 10, 10), outline=(*GOLD_HI, 255), width=2),
                             d.line((5, 3, 5, 6, 8, 7), fill=(*CYAN, 255))))

    def base(d):
        d.rectangle((1, 5, 10, 10), fill=(*SLATE, 255), outline=(*BRASS, 255))
        d.rectangle((3, 7, 8, 9), fill=(*CYAN, 255))
        d.rectangle((5, 1, 6, 4), fill=(*STEEL, 255))

    icon("base", base)

    def drone(d):
        d.rectangle((4, 4, 7, 7), fill=(*STEEL, 255))
        d.point((5, 5), fill=(*CYAN, 255))
        d.line((1, 3, 10, 3), fill=(*BRASS, 255), width=2)
        d.rectangle((0, 2, 2, 4), outline=(*SLATE, 255))
        d.rectangle((9, 2, 11, 4), outline=(*SLATE, 255))

    icon("drone", drone)
    icon("upgrade", lambda d: d.polygon(((5, 0), (10, 6), (7, 6), (7, 11),
                                         (3, 11), (3, 6), (0, 6)),
                                        fill=(*GOLD_HI, 255), outline=(*BRASS, 255)))


if __name__ == "__main__":
    # Keep the high-resolution cutaway beside the other generated source art.
    save(Image.open(SOURCE / "mine_cutaway.png").convert("RGB"),
         "backgrounds/mine_cutaway.png")
    make_terrain()
    make_edges_and_frame()
    make_specials_and_props()
    make_robots_and_branding()
    make_ui()
    print(f"Built {len(list(OUT.rglob('*.png')))} PNG assets in {OUT}")
