from pathlib import Path
from PIL import Image
import numpy as np
import json

ROOT = Path(__file__).parent

def peaks(values, start, threshold):
    hits = np.flatnonzero(values >= threshold) + start
    groups = []
    for p in hits:
        if not groups or p > groups[-1][-1] + 1:
            groups.append([int(p)])
        else:
            groups[-1].append(int(p))
    return [[g[0], g[-1], int(values[np.array(g)-start].max())] for g in groups]

for filename, roi in [
    ('17-upgrade-fullscreen-overflow.png', (450, 220, 1050, 595)),
    ('20-level3-upgrade-carries-over-and-overflows.png', (450, 220, 1050, 690)),
    ('21-level3-board-shop-overlap.png', (460, 600, 1000, 735)),
    ('03-settings-large-still-clipped.png', (160, 500, 565, 579)),
]:
    a = np.asarray(Image.open(ROOT / filename).convert('RGB')).astype(int)
    x0,y0,x1,y1 = roi
    crop=a[y0:y1,x0:x1]
    mask=(crop[:,:,0]>130)&(crop[:,:,1]>95)&(crop[:,:,2]<140)&((crop[:,:,0]-crop[:,:,2])>45)
    print(json.dumps({'file':filename,'image_size':[a.shape[1],a.shape[0]], 'roi':roi,
        'gold_vertical_peak_ranges':peaks(mask.sum(axis=0),x0,35),
        'gold_horizontal_peak_ranges':peaks(mask.sum(axis=1),y0,150)},ensure_ascii=False))
