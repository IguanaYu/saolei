"""Export image_gen micro-animation sheets to native PNGs and review images.

This is asset preparation: split cells, register their fixed lower body,
resize all frames with one shared nearest-neighbor transform, preserve alpha.
Artwork is supplied by image_gen; this script does not draw character pixels.
"""

from pathlib import Path
import json
import shutil

import numpy as np
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "visual_v2/source/micro_anim_v1"
OUTPUT = ROOT / "visual_v2/runtime/micro_animations/v1"
REVIEW = ROOT / "visual_v2/review"
NAMES = {
    "opener": ("开凿 · 钻头轻转", [0, 1, 2], [300, 300, 300]),
    "marker": ("标旗 · 小旗轻摆", [0, 1, 0, 2, 0], [1400, 250, 250, 250, 850]),
    "detector": ("探测 · 亮点扫描", [0, 1, 2, 1], [450, 450, 450, 450]),
    "miner": ("矿工 · 钻机轻转", [0, 1, 2], [350, 350, 350]),
    "guard": ("保安 · 灯光交替", [0, 1], [600, 600]),
    "web": ("织网虫 · 附肢轻动", [0, 1, 2], [500, 400, 600]),
    "lock": ("锁匠虫 · 锁齿起伏", [0, 1, 2], [700, 400, 700]),
    "slow": ("减速虫 · 慢蠕动", [0, 1, 2], [1000, 500, 900]),
    "slime": ("史莱姆 · 轻呼吸", [0, 1, 2], [700, 400, 700]),
}


def opaque_bbox(im):
    ys, xs = np.where(np.asarray(im)[:, :, 3] >= 128)
    if not len(xs):
        raise ValueError("Empty generated frame")
    return tuple(map(int, (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)))


def body_anchor(im, floor_y):
    alpha = np.asarray(im)[:, :, 3]
    ys, xs = np.where((alpha >= 128) & (np.indices(alpha.shape)[0] >= floor_y))
    return ((float(xs.min()) + float(xs.max()) + 1) / 2, int(ys.max()) + 1)


def export_entry(entry):
    name = entry["name"]
    stored = ROOT / entry["generated_copy"]
    if not stored.exists():
        stored.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(entry["source"], stored)
    source = Image.open(stored).convert("RGBA")
    native_size = entry["native_size"]
    cells = [source.crop((round(i * source.width / 3), 0,
                          round((i + 1) * source.width / 3), source.height))
             for i in range(3)]
    initial_bounds = [opaque_bbox(cell) for cell in cells]
    # Use the fixed lower-body region as a registration anchor. Do not
    # normalize each full silhouette: its top deliberately moves.
    floor_y = round(initial_bounds[0][1] +
                    (initial_bounds[0][3] - initial_bounds[0][1]) * 0.72)
    anchors = [body_anchor(cell, floor_y) for cell in cells]
    registered = []
    offsets = []
    for cell, anchor in zip(cells, anchors):
        dx = round(anchors[0][0] - anchor[0])
        dy = anchors[0][1] - anchor[1]
        offsets.append((dx, dy))
        aligned = Image.new("RGBA", cells[0].size)
        aligned.alpha_composite(cell, (dx, dy))
        registered.append(aligned)
    bounds = [opaque_bbox(im) for im in registered]
    crop = (min(b[0] for b in bounds), min(b[1] for b in bounds),
            max(b[2] for b in bounds), max(b[3] for b in bounds))
    original = Image.open(ROOT / entry["reference"]).convert("RGBA")
    ref = opaque_bbox(original)
    # AI reference sheets vary in aspect ratio. Use the original footprint,
    # with ONE shared transform per role, so breathing is not normalized away.
    resized = (ref[2] - ref[0], ref[3] - ref[1])
    origin = (round((ref[0] + ref[2] - resized[0]) / 2), ref[3] - resized[1])
    frames = []
    dest = OUTPUT / entry["kind"]
    dest.mkdir(parents=True, exist_ok=True)
    for i, aligned in enumerate(registered):
        frame = Image.new("RGBA", (native_size, native_size))
        piece = aligned.crop(crop).resize(resized, Image.Resampling.NEAREST)
        frame.alpha_composite(piece, origin)
        frame.save(dest / f"{name}_{i}.png")
        frames.append(frame)
    sheet = Image.new("RGBA", (native_size * 3, native_size))
    for i, frame in enumerate(frames):
        sheet.alpha_composite(frame, (i * native_size, 0))
    sheet.save(dest / f"{name}_sheet.png")
    title, sequence, durations = NAMES[name]
    metrics = {
        "name": name, "raw_size": source.size, "raw_opaque_bboxes": initial_bounds,
        "registration_offsets": offsets, "shared_crop": crop,
        "resize": resized, "origin": origin, "frame_size": [native_size] * 2,
        "alpha_bboxes": [frame.getbbox() for frame in frames],
        "opaque_bboxes": [opaque_bbox(frame) for frame in frames],
        "changed_pixels_vs_frame0": [int(np.any(np.asarray(frame) !=
                                      np.asarray(frames[0]), axis=2).sum())
                                      for frame in frames],
        "alpha_range": [int(np.asarray(frames[0])[:, :, 3].min()),
                        int(np.asarray(frames[0])[:, :, 3].max())],
        "sheet": (dest / f"{name}_sheet.png").relative_to(ROOT).as_posix(),
        "frames": [(dest / f"{name}_{i}.png").relative_to(ROOT).as_posix()
                   for i in range(3)],
        "sequence": sequence, "durations_ms": durations,
    }
    print(json.dumps(metrics, ensure_ascii=False))
    return frames, original, metrics


def font(size):
    return ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", size)


def preview_cell(canvas, frames, index, position, title, native):
    x, y = position
    draw = ImageDraw.Draw(canvas)
    draw.text((x + 18, y + 12), title, fill="#e8d7b8", font=font(21))
    draw.text((x + 18, y + 43), f"{native}×{native} · 6倍预览", fill="#a79374", font=font(15))
    im = frames[index].resize((native * 6, native * 6), Image.Resampling.NEAREST)
    canvas.alpha_composite(im, (x + (288 - im.width) // 2, y + 75))


def chosen_frame(name, elapsed):
    _, sequence, durations = NAMES[name]
    cursor = elapsed % sum(durations)
    for index, duration in zip(sequence, durations):
        if cursor < duration:
            return index
        cursor -= duration
    return sequence[0]


def main():
    data = json.loads((SOURCE / "generation_manifest.json").read_text("utf-8"))
    exports = {e["name"]: export_entry(e) for e in data["entries"]}
    REVIEW.mkdir(exist_ok=True)
    header = 72
    animated = []
    for t in range(0, 6000, 100):
        canvas = Image.new("RGBA", (864, header + 3 * 245), "#201b17")
        draw = ImageDraw.Draw(canvas)
        draw.text((20, 14), "机器人与敌人 · 一个角色一个小循环", fill="#f0d6a5", font=font(24))
        draw.text((20, 46), "动画帧候选图 / 只做局部变化", fill="#b49e7e", font=font(16))
        for i, (name, (frames, original, metrics)) in enumerate(exports.items()):
            preview_cell(canvas, frames, chosen_frame(name, t + i * 137),
                         ((i % 3) * 288, header + (i // 3) * 245),
                         NAMES[name][0], original.width)
        animated.append(canvas.convert("RGB"))
    animated[0].save(REVIEW / "micro_anim_v1_preview.png")
    animated[0].save(REVIEW / "micro_anim_v1_preview.gif", save_all=True,
                     append_images=animated[1:], duration=100, loop=0, disposal=2)
    # One static contact sheet includes the original alongside every exported
    # frame, so changes in the generated candidates are easy to assess.
    comparison = Image.new("RGBA", (940, 80 + 9 * 195), "#201b17")
    draw = ImageDraw.Draw(comparison)
    for i, label in enumerate(("现有原图", "动画帧 0", "动画帧 1", "动画帧 2")):
        draw.text((175 + 185 * i, 18), label, fill="#f0d6a5", font=font(22))
    for row, (name, (frames, original, metrics)) in enumerate(exports.items()):
        y = 80 + row * 195
        draw.text((15, y + 50), NAMES[name][0].split(" · ")[0], fill="#e8d7b8", font=font(21))
        for col, im in enumerate([original] + frames):
            up = im.resize((im.width * 7, im.height * 7), Image.Resampling.NEAREST)
            comparison.alpha_composite(up, (160 + 185 * col, y))
    comparison.convert("RGB").save(REVIEW / "micro_anim_v1_frames.png")
    (OUTPUT / "manifest.json").write_text(json.dumps({
        "version": 1, "status": "micro animation asset pack v1",
        "entries": [item[2] for item in exports.values()]
    }, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
