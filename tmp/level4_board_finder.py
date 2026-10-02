# -*- coding: utf-8 -*-
"""第四关盘面搜索器：v2.3 随机盘 → 固定图（2026-10-02 盲测反馈：单起点洪水 42% 概率预开 <15%）

条件（全部满足才算 pass）：
  1. 16x16 / 40 雷（15.6%，构造保证）
  2. 预开 = 单起点洪水的自然连通域（零核+数字边界，与 apply_random_board 同构）
  3. 预开格数 ∈ [50, 68]（安全格 216 的 23-31%：肉眼"一大片"，又不过度吃掉 160 格目标）
  4. 洪水起点位于中心区 [5,10]^2（开局区域居中，基地自放灵活、离盘边巢远）
  5. 预开区含数字边界格 >= 8（预置网要盖已开数字格 x3，留余量+开局推理目标）
  6. 预开区外仍有零格 >= 12（机器人中期连锁展开的口袋）
  7. 雷分布：四个 8x8 象限各 <= 13 颗（防角落堆雷导致的局部地狱）

挑选：多 seed 全条件通过后，取预开最接近 58、起点离中心最近的一张。
"""
import random

W = H = 16
MINES = 40
PREOPEN_LO, PREOPEN_HI = 50, 68
CENTER = (W // 2, H // 2)
START_MIN, START_MAX = 5, 10
DIGIT_MIN = 8
OUT_ZERO_MIN = 12
QUAD_MAX = 13

NB = {}
for x in range(W):
    for y in range(H):
        NB[(x, y)] = [(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)
                      if (dx or dy) and 0 <= x + dx < W and 0 <= y + dy < H]


def gen(seed):
    rnd = random.Random(seed)
    cells = [(x, y) for x in range(W) for y in range(H)]
    mines = set(rnd.sample(cells, MINES))
    num = {}
    for c in cells:
        if c in mines:
            continue
        num[c] = sum(n in mines for n in NB[c])
    return cells, mines, num


def flood(start, mines, num):
    opened = {start}
    queue = [start]
    while queue:
        c = queue.pop(0)
        if num.get(c, 0) != 0:
            continue
        for n in NB[c]:
            if n in opened or n in mines:
                continue
            opened.add(n)
            if num.get(n, 0) == 0:
                queue.append(n)
    return opened


def evaluate(seed):
    cells, mines, num = gen(seed)
    # 象限均衡
    quads = [0, 0, 0, 0]
    for mx, my in mines:
        quads[(my >= 8) * 2 + (mx >= 8)] += 1
    if max(quads) > QUAD_MAX:
        return None
    best = None
    for c in cells:
        if c in mines or num.get(c, 0) != 0:
            continue
        if not (START_MIN <= c[0] <= START_MAX and START_MIN <= c[1] <= START_MAX):
            continue
        opening = flood(c, mines, num)
        n = len(opening)
        if not (PREOPEN_LO <= n <= PREOPEN_HI):
            continue
        digits = sum(1 for o in opening if num.get(o, 0) > 0)
        if digits < DIGIT_MIN:
            continue
        out_zeros = sum(1 for c2 in cells if c2 not in mines and c2 not in opening
                        and num.get(c2, 0) == 0)
        if out_zeros < OUT_ZERO_MIN:
            continue
        center_dist = max(abs(c[0] - CENTER[0]), abs(c[1] - CENTER[1]))
        score = abs(n - 58) + center_dist  # 越小越好
        if best is None or score < best[0]:
            best = (score, seed, c, opening, mines, num, digits, out_zeros, quads)
    return best


def gdscript(cells):
    return ", ".join("Vector2i(%d, %d)" % c for c in cells)


candidates = []
for seed in range(1, 4000):
    r = evaluate(seed)
    if r:
        candidates.append(r)
        if len(candidates) >= 12:
            break

if not candidates:
    print("NO PASS")
    raise SystemExit(1)

candidates.sort(key=lambda r: r[0])
score, seed, start, opening, mines, num, digits, out_zeros, quads = candidates[0]

print("seed=%d start=%s score=%d" % (seed, start, score))
print("预开 %d 格（%.0f%% 安全格）/ 数字边界 %d / 区外零格 %d / 象限雷 %s"
      % (len(opening), 100.0 * len(opening) / (W * H - MINES), digits, out_zeros, quads))
print()
print("mines:")
print("\t" + gdscript(sorted(mines)) + ",")
print("preopen:")
print("\t" + gdscript(sorted(opening)) + ",")

# 验证回读：预开必须无雷且为单连通域
assert not (opening & mines)
seen = {start}
stack = [start]
while stack:
    c = stack.pop()
    for n in NB[c]:
        if n in opening and n not in seen:
            seen.add(n)
            stack.append(n)
assert seen == opening, "预开非单一连通域"
print()
print("回读自检：无雷✓ 单连通✓")
