"""Show the small cursor and interaction assets at 8x nearest-neighbor scale."""

from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
FX = ROOT / "runtime" / "fx"
SCALE = 8
TILE = 28
PAD = 14
CARD_W = TILE * SCALE + PAD
CARD_H = TILE * SCALE + 38

wall = Image.open(ROOT / "runtime/tiles/wall_V2.png").convert("RGBA").crop((0, 0, 28, 28))
floor = Image.open(ROOT / "runtime/tiles/floor_V2.png").convert("RGBA").crop((0, 0, 28, 28))
dark = Image.new("RGBA", (28, 28), (27, 29, 35, 255))


def asset(name):
    return Image.open(FX / name).convert("RGBA")


def card(background, graphic, offset=(0, 0)):
    tile = background.copy()
    tile.alpha_composite(graphic, offset)
    return tile.resize((TILE * SCALE, TILE * SCALE), Image.Resampling.NEAREST)


shards = asset("rock_shards_mask_sheet.png")
shard_tile = wall.copy()
for index, at in enumerate(((2, 4), (10, 11), (19, 5))):
    shape = shards.crop((index * 8, 0, (index + 1) * 8, 8))
    # Preview color only; the native sheet remains white for runtime tinting.
    tint = Image.new("RGBA", (8, 8), (153, 155, 158, 255))
    tint.putalpha(shape.getchannel("A"))
    shard_tile.alpha_composite(tint, at)

glint = asset("gold_glint_sheet.png")
items = (
    ("CURSOR ARROW", card(dark, asset("cursor_arrow.png"), (2, 2))),
    ("CURSOR BOARD", card(wall, asset("cursor_board.png"), (2, 2))),
    ("CURSOR PLACE", card(dark, asset("cursor_placing.png"), (2, 2))),
    ("TILE HOVER", card(wall, asset("tile_hover.png"))),
    ("PLACE VALID", card(floor, asset("tile_place_valid.png"))),
    ("PLACE INVALID", card(wall, asset("tile_place_invalid.png"))),
    ("ROCK SHARDS", shard_tile.resize((TILE * SCALE, TILE * SCALE), Image.Resampling.NEAREST)),
    ("GOLD GLINT", card(dark, glint.crop((12, 0, 24, 12)), (8, 8))),
)

preview = Image.new("RGB", (PAD + 4 * CARD_W, PAD + 2 * CARD_H), (20, 23, 31))
draw = ImageDraw.Draw(preview)
for index, (name, picture) in enumerate(items):
    x = PAD + (index % 4) * CARD_W
    y = PAD + (index // 4) * CARD_H
    preview.paste(picture, (x, y))
    draw.text((x, y + TILE * SCALE + 8), name, fill=(242, 227, 197))

output = Path(__file__).with_name("interaction_fx_preview.png")
preview.save(output)
print(output)
