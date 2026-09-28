# -*- coding: utf-8 -*-
"""方案M：代码绘制 chunky 岩石 sprite（跟形阴影，光左上）
产物 assets/tiles/rock_wall_sheet.png（4x2 = 8 变体，80px/块）
"""
import numpy as np, random
from PIL import Image, ImageDraw

T = 80
SS = 4  # 超采样画多边形 → NEAREST 降采样得阶梯边

FLOOR = np.array(Image.open("assets/tiles/floor_bricks_sheet.png").convert("RGB")).astype(float)
def lum(c):
    return 0.299*c[...,0] + 0.587*c[...,1] + 0.114*c[...,2]
FLOOR_LUM = lum(FLOOR).mean()

BG = np.array([40, 32, 25], float)    # 石缝
SH = np.array([32, 25, 19], float)    # 接触阴影（右下）
OL = np.array([24, 19, 15], float)    # 1px 轮廓
PD = np.array([76, 58, 40], float)    # 背光面 (lum≈60)
PM = np.array([122, 93, 64], float)   # 主体面 (lum≈97)
PL = np.array([146, 112, 78], float)  # 受光面 (lum≈114)
PK = np.array([168, 131, 92], float)  # 高光点 (lum≈130)

def gen(seed):
    rng = random.Random(seed)
    S = T * SS
    for _ in range(60):  # 重试到覆盖率 64-72%
        img = Image.new("L", (S, S), 0)
        d = ImageDraw.Draw(img)
        cx, cy = S/2, S/2 + S*0.02
        R = S * 0.50 * rng.uniform(0.97, 1.0)
        pts = []
        for a in sorted(rng.uniform(0, 2*np.pi) for _ in range(rng.randint(6, 8))):
            r = R * rng.uniform(0.88, 1.0)
            pts.append((cx + np.cos(a)*r, cy + np.sin(a)*r*0.9))
        d.polygon(pts, fill=1)
        mask = np.array(img.resize((T, T), Image.NEAREST)).astype(bool)
        if 0.64 <= mask.mean() <= 0.72:
            break
        img = Image.new("L", (S, S), 0)
        d = ImageDraw.Draw(img)
        cx, cy = S/2, S/2 + S*0.02
        R = S * 0.50 * rng.uniform(0.97, 1.0)
        pts = []
        for a in sorted(rng.uniform(0, 2*np.pi) for _ in range(rng.randint(6, 8))):
            r = R * rng.uniform(0.88, 1.0)
            pts.append((cx + np.cos(a)*r, cy + np.sin(a)*r*0.9))
        d.polygon(pts, fill=1)
        mask = np.array(img.resize((T, T), Image.NEAREST)).astype(bool)
        if 0.60 <= mask.mean() <= 0.75:
            break

    ys, xs = np.where(mask)
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    h, w = y1-y0+1, x1-x0+1
    NY, NX = np.meshgrid(
        (np.arange(y0, y1+1) - y0) / max(h-1, 1),
        (np.arange(x0, x1+1) - x0) / max(w-1, 1),
        indexing="ij",
    )

    # 1-2 条棱线分面
    faces = np.zeros((h, w), int)
    for _ in range(rng.randint(1, 2)):
        k = rng.uniform(0.35, 0.65)
        b = rng.uniform(-0.3, 0.3)
        if rng.random() < 0.5:
            faces += ((NX + b*NY) > k).astype(int)
        else:
            faces += ((NY + b*NX) > k).astype(int)

    light = 1.0 - (NX + NY)/2   # 左上=1 右下=0
    noise = np.asarray(Image.effect_noise((64, 64), seed % 9999).resize((w, h)), dtype=float)
    noise = (noise - noise.mean()) / (noise.std() + 1e-6)

    # 逐 tile 反推色阶：整格目标=地砖72%，按 coverage 解算岩面均值
    cov = mask.mean()
    BG_L = 0.299*BG[0] + 0.587*BG[1] + 0.114*BG[2]
    rock_t = (FLOOR_LUM*0.80 - (1-cov)*BG_L) / cov
    pd = PD * (rock_t*0.62 / lum(PD[None, None, :])[0, 0])
    pm = PM * (rock_t*1.00 / lum(PM[None, None, :])[0, 0])
    pl = PL * (rock_t*1.17 / lum(PL[None, None, :])[0, 0])
    pk = PK * (rock_t*1.33 / lum(PK[None, None, :])[0, 0])

    out = np.zeros((h, w, 3))
    for f in np.unique(faces):
        m = faces == f
        tone = light[m] + noise[m] * 0.08
        cols = np.zeros((tone.size, 3))
        cols[tone > 0.72] = pl
        cols[(tone > 0.35) & (tone <= 0.72)] = pm
        cols[tone <= 0.35] = pd
        out[m] = cols
    out[(light > 0.78) & (noise > 1.8)] = pk   # 少量高光点

    tile = np.empty((T, T, 3))
    tile[:] = BG
    # 接触阴影：石块外扩2px 且只在右下象限
    grown = mask.copy()
    for _ in range(2):
        grown |= np.roll(grown, 1, 0) | np.roll(grown, 1, 1)
    sh = grown & ~mask
    sh[:T//2 + 6] = False
    sh[:, :T//2 + 6] = False
    tile[sh] = SH
    sub = tile[y0:y1+1, x0:x1+1].copy()
    mbb = mask[y0:y1+1, x0:x1+1]
    sub[mbb] = out[mbb]  # bbox 内 out 与 mask 同形，逐像素取
    tile[y0:y1+1, x0:x1+1] = sub
    # 1px 轮廓：石块边界像素
    inner = np.roll(mask,1,0) & np.roll(mask,-1,0) & np.roll(mask,1,1) & np.roll(mask,-1,1)
    edge = mask & ~inner
    tile[edge] = OL
    return tile

def main():
    tiles = [gen(s*31 + 7) for s in range(8)]
    cn, rn = 4, 2
    sheet = np.zeros((rn*T, cn*T, 3))
    for i, t in enumerate(tiles):
        r, c = divmod(i, cn)
        sheet[r*T:(r+1)*T, c*T:(c+1)*T] = t
    Image.fromarray(sheet.astype(np.uint8)).save("assets/tiles/rock_wall_sheet.png")

    random.seed(3)
    canvas = Image.new("RGB", (10*T, 10*T))
    sa = sheet.astype(np.uint8)
    for r in range(10):
        for c in range(10):
            x, y = random.randrange(cn)*T, random.randrange(rn)*T
            canvas.paste(Image.fromarray(sa[y:y+T, x:x+T]), (c*T, r*T))
    canvas.resize((10*160, 10*160), Image.NEAREST).save("tmp/rock_tiled_M.png")

    bl = [lum(t) for t in tiles]
    allb = np.stack(bl)
    means = np.array([b.mean() for b in bl])
    sats = [((t.max(axis=2)-t.min(axis=2))/np.maximum(t.max(axis=2),1)).mean() for t in tiles]
    fmx, fmn = FLOOR.max(axis=2), FLOOR.min(axis=2)
    fsat = ((fmx-fmn)/np.maximum(fmx,1)).mean()
    print(f"M: 亮度比={allb.mean()/FLOOR_LUM*100:.1f}%(70-85) 极差={(means.max()-means.min())/means.mean()*100:.1f}%(≤5) "
          f"亮面={(allb>105).mean()*100:.1f}%(<20) 饱和度比={np.mean(sats)/fsat*100:.0f}%(≤70)")

if __name__ == "__main__":
    main()
