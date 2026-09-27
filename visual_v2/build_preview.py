"""Create a local review sheet for the V2 runtime art."""

from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
RUNTIME = ROOT / "runtime"
REVIEW = ROOT / "review"
REVIEW.mkdir(exist_ok=True)
canvas = Image.new("RGB", (1240, 900), (19, 23, 31))
draw = ImageDraw.Draw(canvas)


def place(path, x, y, w, h, label):
    image = Image.open(RUNTIME / path).convert("RGBA")
    image = image.resize((w, h), Image.Resampling.NEAREST)
    canvas.paste(image, (x, y), image)
    draw.text((x, y + h + 7), label, fill=(240, 224, 188))


for i, theme in enumerate(("V2", "V2C", "V2M", "V2R")):
    x = 20 + i * 305
    place(f"tiles/wall_{theme}.png", x, 35, 140, 140, f"{theme} rock")
    place(f"tiles/floor_{theme}.png", x + 150, 35, 140, 140, f"{theme} floor")
    place(f"tiles/deco_{theme}_sheet.png", x, 205, 280, 140, f"{theme} decor")

for i, kind in enumerate(("opener", "marker", "detector", "miner")):
    x = 40 + i * 185
    place(f"robots/robot_{kind}_idle.png", x, 420, 144, 144, kind)
    place(f"ui/icons/icon_robot_{kind}.png", x + 45, 610, 64, 64, "shop icon")

place("tiles/special_base.png", 830, 420, 84, 84, "base")
place("tiles/special_flag.png", 930, 420, 84, 84, "flag")
place("tiles/special_vein.png", 1030, 420, 84, 84, "vein")
place("tiles/special_collapse.png", 830, 540, 84, 84, "collapse")
place("ui/panel_metal.png", 930, 540, 144, 144, "panel 9-slice")
place("ui/btn_normal.png", 830, 720, 176, 128, "button 9-slice")

canvas.save(REVIEW / "runtime_sheet.png")
print(REVIEW / "runtime_sheet.png")
