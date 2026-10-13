"""Measure frozen Godot screenshots produced by ui_a_layout_review --mask-only.

Run from the project root: python visual_v2/review/check_ui_a_mask.py
Requires Pillow and numpy. Does not modify images or game data.
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image


folder = Path(__file__).resolve().parents[2] / "tmp"
bounds = json.loads((folder / "ui_a_mask_bounds.json").read_text())
print("MEASURED BOUNDS", bounds)


def pixels(name):
    return np.asarray(Image.open(folder / f"ui_a_mask_{name}.png").convert("RGB"))


background = pixels("background")
clipped = pixels("enabled")
unclipped = pixels("disabled")
width, height = bounds["image"]
view_width, view_height = bounds["viewport"]
area = np.array(bounds["area"]) * np.array(
    [width / view_width, height / view_height, width / view_width, height / view_height]
)
x1, y1, x2, y2 = np.round(area).astype(int)
inside = np.zeros((height, width), dtype=bool)
inside[y1:y2, x1:x2] = True
print("PIXEL RECT", tuple(int(v) for v in (x1, y1, x2, y2)))

outside_counts = {}
for name, frame in [("clipped", clipped), ("unclipped", unclipped)]:
    diff = np.any(frame != background, axis=2)
    yy, xx = np.nonzero(diff)
    box = (int(xx.min()), int(yy.min()), int(xx.max()) + 1, int(yy.max()) + 1)
    outside_counts[name] = int(np.sum(diff & ~inside))
    print(name, "changed_bbox", box, "inside", int(np.sum(diff & inside)),
          "outside", outside_counts[name])

assert outside_counts["clipped"] == 0, "Clipped world draws outside board window"
assert outside_counts["unclipped"] > 0, "Raw control should expose outside pixels"
print("PIXEL MASK PASS")
