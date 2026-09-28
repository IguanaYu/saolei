"""Build the small interaction FX sheets without rebuilding terrain or UI."""

from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent
FX = ROOT / "runtime" / "fx"
FX.mkdir(parents=True, exist_ok=True)
# Match the native-pixel palette in build_runtime.py. This script intentionally
# stays independent so regenerating interaction FX cannot rewrite terrain.
BRASS = (156, 113, 55)
RED = (224, 65, 60)
STEEL = (111, 121, 132)
INK = (12, 16, 23)
TEXT = (242, 227, 197)
GOLD_HI = (250, 205, 107)
CYAN = (54, 205, 228)


def build_flag_sheet() -> None:
    # The last frame is the actual static flag, so handoff to Cell cannot jump.
    rest = Image.open(ROOT / "runtime" / "tiles" / "special_flag.png").convert("RGBA")
    if rest.size != (28, 28):
        raise ValueError("special_flag.png must be 28x28")

    def cloth_pose(points, highlight):
        frame = rest.copy()
        draw = ImageDraw.Draw(frame)
        draw.rectangle((10, 4, 25, 17), fill=(0, 0, 0, 0))
        draw.polygon(points, fill=(*RED, 255))
        draw.line(highlight, fill=(255, 144, 104, 255))
        return frame

    frames = (
        cloth_pose(((10, 5), (20, 8), (17, 10), (21, 14), (10, 14)),
                   (10, 5, 19, 8)),  # impact: cloth folds toward the pole
        cloth_pose(((10, 5), (24, 6), (19, 11), (24, 13), (10, 14)),
                   (10, 5, 23, 6)),  # rebound: cloth swings outward
        rest,
    )
    sheet = Image.new("RGBA", (84, 28))
    for index, frame in enumerate(frames):
        sheet.alpha_composite(frame, (index * 28, 0))
    sheet.save(FX / "flag_plant_sheet.png")


def build_dust_sheet() -> None:
    # Three 16x12 puffs. Place each frame at (1, 16) relative to the tile's
    # upper left, or (-13, 2) in the current center-origin Cell scene.
    colors = ((*STEEL, 230), (165, 168, 158, 180), (*BRASS, 160))
    shapes = (
        (((4, 7, 6, 9), 0), ((7, 6, 9, 8), 1), ((10, 7, 12, 9), 0)),
        (((1, 6, 4, 8), 0), ((5, 4, 7, 6), 1), ((8, 7, 9, 8), 2),
         ((11, 5, 14, 7), 0)),
        (((0, 4, 2, 5), 1), ((4, 2, 5, 3), 2), ((10, 3, 11, 4), 2),
         ((14, 4, 15, 5), 1)),
    )
    sheet = Image.new("RGBA", (48, 12))
    for index, boxes in enumerate(shapes):
        frame = Image.new("RGBA", (16, 12))
        draw = ImageDraw.Draw(frame)
        for box, color_index in boxes:
            draw.rectangle(box, fill=colors[color_index])
        sheet.alpha_composite(frame, (index * 16, 0))
    sheet.save(FX / "flag_dust_sheet.png")


def build_cursors() -> None:
    # Hardware cursors stay small and crisp. Click hotspots are documented in
    # README.md; changing a graphic must not silently move its hotspot.
    arrow = Image.new("RGBA", (24, 24))
    draw = ImageDraw.Draw(arrow)
    draw.polygon(((1, 1), (1, 19), (5, 15), (8, 22), (12, 20),
                  (9, 14), (16, 14)), fill=(*INK, 255))
    draw.polygon(((3, 4), (3, 15), (6, 12), (9, 19), (10, 18),
                  (7, 12), (12, 12)), fill=(*TEXT, 255))
    draw.line((4, 5, 4, 11), fill=(*GOLD_HI, 255))
    arrow.save(FX / "cursor_arrow.png")

    board = Image.new("RGBA", (24, 24))
    draw = ImageDraw.Draw(board)
    for segment in ((2, 12, 5, 12), (19, 12, 22, 12),
                    (12, 2, 12, 5), (12, 19, 12, 22)):
        draw.line(segment, fill=(*INK, 255), width=3)
        draw.line(segment, fill=(*TEXT, 255), width=1)
    draw.point((12, 12), fill=(*GOLD_HI, 255))
    board.save(FX / "cursor_board.png")

    placing = arrow.copy()
    draw = ImageDraw.Draw(placing)
    draw.rectangle((14, 14, 22, 22), fill=(*INK, 255))
    draw.rectangle((15, 15, 21, 21), outline=(*BRASS, 255))
    draw.rectangle((17, 17, 19, 19), fill=(*CYAN, 255))
    placing.save(FX / "cursor_placing.png")


def build_target_overlays() -> None:
    # Open-center corner brackets preserve numbers and underlying tile art.
    def target(color, state):
        tile = Image.new("RGBA", (28, 28))
        draw = ImageDraw.Draw(tile)
        for x, dx in ((2, 1), (25, -1)):
            for y, dy in ((2, 1), (25, -1)):
                draw.line((x, y + 4 * dy, x, y, x + 4 * dx, y),
                          fill=(*INK, 220), width=3)
                draw.line((x, y + 4 * dy, x, y, x + 4 * dx, y),
                          fill=(*color, 220), width=1)
        if state == "valid":
            draw.line((18, 7, 20, 9, 24, 5), fill=(*INK, 255), width=3)
            draw.line((18, 7, 20, 9, 24, 5), fill=(*CYAN, 255), width=1)
        elif state == "invalid":
            draw.line((19, 5, 24, 10), fill=(*INK, 255), width=3)
            draw.line((24, 5, 19, 10), fill=(*INK, 255), width=3)
            draw.line((19, 5, 24, 10), fill=(*RED, 255))
            draw.line((24, 5, 19, 10), fill=(*RED, 255))
        return tile

    target(STEEL, "hover").save(FX / "tile_hover.png")
    target(CYAN, "valid").save(FX / "tile_place_valid.png")
    target(RED, "invalid").save(FX / "tile_place_invalid.png")


def build_small_fx() -> None:
    # White silhouette masks: modulate each fragment to the current wall theme.
    shards = Image.new("RGBA", (24, 8))
    silhouettes = (
        ((1, 2), (5, 1), (6, 4), (3, 6), (1, 5)),
        ((2, 1), (6, 3), (4, 6), (1, 5)),
        ((1, 3), (4, 1), (6, 2), (5, 5), (2, 6)),
    )
    for index, points in enumerate(silhouettes):
        frame = Image.new("RGBA", (8, 8))
        ImageDraw.Draw(frame).polygon(points, fill=(255, 255, 255, 255))
        shards.alpha_composite(frame, (index * 8, 0))
    shards.save(FX / "rock_shards_mask_sheet.png")

    glint = Image.new("RGBA", (36, 12))
    for index in range(3):
        frame = Image.new("RGBA", (12, 12))
        draw = ImageDraw.Draw(frame)
        if index == 0:
            draw.rectangle((5, 5, 6, 6), fill=(*GOLD_HI, 255))
        elif index == 1:
            draw.line((5, 1, 5, 10), fill=(*BRASS, 255))
            draw.line((1, 5, 10, 5), fill=(*BRASS, 255))
            draw.line((5, 2, 5, 9), fill=(*GOLD_HI, 255))
            draw.line((2, 5, 9, 5), fill=(*GOLD_HI, 255))
            draw.rectangle((4, 4, 6, 6), fill=(*TEXT, 255))
        else:
            for x, y in ((5, 2), (2, 5), (9, 5), (5, 9)):
                draw.point((x, y), fill=(*GOLD_HI, 190))
            draw.rectangle((5, 5, 6, 6), fill=(*GOLD_HI, 200))
        glint.alpha_composite(frame, (index * 12, 0))
    glint.save(FX / "gold_glint_sheet.png")


if __name__ == "__main__":
    build_flag_sheet()
    build_dust_sheet()
    build_cursors()
    build_target_overlays()
    build_small_fx()
    print(f"Built {len(list(FX.glob('*.png')))} interaction assets in {FX}")
