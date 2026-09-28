"""Render the native-size flag impact frames against the current V2 wall."""

from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SCALE = 8
TILE = 28
GAP = 14

wall = Image.open(ROOT / "runtime/tiles/wall_V2.png").convert("RGBA").crop((0, 0, TILE, TILE))
flags = Image.open(ROOT / "runtime/fx/flag_plant_sheet.png").convert("RGBA")
dust = Image.open(ROOT / "runtime/fx/flag_dust_sheet.png").convert("RGBA")

width = GAP + 3 * (TILE * SCALE + GAP)
height = TILE * SCALE + 52
preview = Image.new("RGB", (width, height), (20, 23, 31))
draw = ImageDraw.Draw(preview)

for index, title in enumerate(("IMPACT", "REBOUND", "REST")):
    tile = wall.copy()
    tile.alpha_composite(flags.crop((index * TILE, 0, (index + 1) * TILE, TILE)))
    tile.alpha_composite(dust.crop((index * 16, 0, (index + 1) * 16, 12)), (1, 16))
    x = GAP + index * (TILE * SCALE + GAP)
    preview.paste(tile.resize((TILE * SCALE, TILE * SCALE), Image.Resampling.NEAREST),
                  (x, GAP))
    draw.text((x, TILE * SCALE + GAP + 8), title, fill=(242, 227, 197))

output = Path(__file__).with_name("fx_preview.png")
preview.save(output)
print(output)
