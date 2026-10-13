"""只读像素验收：先输出实际 bbox / alpha / 帧差，再断言边界与锚点。"""
from pathlib import Path
import json
from PIL import Image
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
reports = []
for kind, folder, size in [("overload", "robots", 24), ("builder", "enemies", 22), ("special_ore", "facilities", 48)]:
    source = ROOT / f"visual_v2/runtime/ch02_v1/{folder}/{kind}_sheet.png"
    image = Image.open(source).convert("RGBA")
    pixels = np.asarray(image)
    frames = [pixels[:, i * size:(i + 1) * size] for i in range(3)]
    bounds = []
    for frame in frames:
        y, x = np.nonzero(frame[:, :, 3])
        bounds.append([int(x.min()), int(y.min()), int(x.max()) + 1, int(y.max()) + 1])
    alpha = sorted(int(v) for v in np.unique(pixels[:, :, 3]))
    report = {"kind": kind, "sheet": list(image.size), "bbox": bounds, "alpha": alpha,
              "changed_pixels": [int(np.any(frames[i] != frames[0], axis=2).sum()) for i in [1, 2]],
              "bottom_row_opaque": [int((f[-1, :, 3] > 0).sum()) for f in frames]}
    print(json.dumps(report))
    assert image.size == (size * 3, size)
    assert alpha == [0, 255]
    assert all(0 < b[0] < b[2] < size and 0 < b[1] < b[3] < size for b in bounds), "sprite clipped against a frame boundary"
    assert len({b[3] for b in bounds}) == 1, "feet baseline differs"
    reports.append(report)
dest = ROOT / "tmp/ch02_asset_pixel_report.json"
dest.parent.mkdir(exist_ok=True)
dest.write_text(json.dumps(reports, indent=2) + "\n", encoding="utf-8")
print("PASS: transparent frame margins, common baseline and binary alpha")
