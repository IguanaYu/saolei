from pathlib import Path
import json
import numpy as np
from PIL import Image

root = Path(__file__).parent

def independent_peaks(values, start, threshold):
    hits = np.flatnonzero(values >= threshold) + start
    groups = []
    for hit in hits:
        if not groups or hit > groups[-1][-1] + 1:
            groups.append([int(hit)])
        else:
            groups[-1].append(int(hit))
    return [[group[0], group[-1], int(values[np.array(group) - start].max())]
            for group in groups]

# Regions are anchored to observed controls, not an assumed equal grid.
for filename, label, roi, vertical_threshold, horizontal_threshold in [
    ('25-upgrade-level3-five-rows-fullscreen.jpg', 'panel', (450, 160, 1015, 665), 250, 350),
    ('25-upgrade-level3-five-rows-fullscreen.jpg', 'purchase_buttons', (825, 220, 1000, 500), 100, 110),
    ('25-upgrade-level3-five-rows-fullscreen.jpg', 'close_button', (465, 580, 1000, 645), 25, 350),
    ('24-upgrade-level3-five-rows-1024.jpg', 'panel', (140, 112, 445, 385), 150, 200),
    ('24-upgrade-level3-five-rows-1024.jpg', 'purchase_buttons', (342, 151, 436, 300), 55, 60),
    ('24-upgrade-level3-five-rows-1024.jpg', 'close_button', (150, 337, 435, 372), 14, 160),
    ('26-esc-closes-upgrade.jpg', 'board_bottom', (465, 585, 1000, 628), 15, 350),
    ('26-esc-closes-upgrade.jpg', 'shop_top', (450, 635, 1020, 710), 35, 350),
    ('31-level4-layout-1280.jpg', 'board_bottom', (185, 420, 550, 451), 12, 220),
    ('31-level4-layout-1280.jpg', 'shop_top', (40, 450, 695, 505), 25, 350),
    ('34-level4-fullscreen-reprojection.jpg', 'board_bottom', (465, 585, 1000, 628), 15, 350),
    ('34-level4-fullscreen-reprojection.jpg', 'shop_top', (245, 635, 1215, 710), 35, 550),
]:
    pixels = np.asarray(Image.open(root / filename).convert('RGB')).astype(int)
    x0, y0, x1, y1 = roi
    crop = pixels[y0:y1, x0:x1]
    mask = ((crop[:, :, 0] > 130) & (crop[:, :, 1] > 95)
            & (crop[:, :, 2] < 150)
            & ((crop[:, :, 0] - crop[:, :, 2]) > 45))
    hpeaks = independent_peaks(mask.sum(1), y0, horizontal_threshold)
    spans = []
    for peak_start, peak_end, count in hpeaks:
        columns = np.flatnonzero(mask[peak_start-y0:peak_end-y0+1].any(axis=0))
        spans.append({'y': [peak_start, peak_end], 'x': [int(columns[0]+x0), int(columns[-1]+x0)]})
    print(json.dumps({'file': filename, 'object': label, 'image_size': [pixels.shape[1], pixels.shape[0]],
                     'roi': roi,
                     'vertical_peak_ranges': independent_peaks(mask.sum(0), x0, vertical_threshold),
                     'horizontal_peak_ranges': hpeaks, 'horizontal_line_spans': spans},
                    ensure_ascii=False))
