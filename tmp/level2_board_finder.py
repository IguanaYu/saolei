# -*- coding: utf-8 -*-
"""第二关盘面搜索器：对齐设计文档 v1.2 §7 验收标准
条件（全部满足才算 pass）：
  1. 全程 2 条基础规则可解（不猜、不停摆、不需子集推理）
  2. 密度 24/196 ≈ 12.2%（构造保证）
  3. 预开（含洪水）∈ [69,88] 格（35-45%）
  4. 开局（预开后）≥5 个秒推级可动作目标（可推旗 + 放旗后规则 1 可开格）
  5. 至少一次 ≥6 格连锁展开（机器人高光）
  6. 最后打开的格子距基地 ≥3 格（切比雪夫距离）
与 L1 的差异：预开区形状/尺寸/基地位置都是搜索维度（L1 固定 5×5 + 5 个基点位）。
"""
import random, sys

W = H = 14
MINES = 24
PREOPEN_LO, PREOPEN_HI = 69, 88   # 196 格的 35-45%
TARGETS_MIN = 5
FLOOD_MIN = 6
FINAL_DIST_MIN = 3

SHAPES = [("sq", 2), ("sq", 3), ("disk", 3)]          # 5x5 / 7x7 / 圆盘r3(~29格)
BASES = [(x, y) for x in range(3, 11, 2) for y in range(3, 11, 2)]  # 16 个基点位

NB = {}
for x in range(W):
    for y in range(H):
        NB[(x, y)] = [(x+dx, y+dy) for dx in (-1,0,1) for dy in (-1,0,1)
                      if (dx or dy) and 0 <= x+dx < W and 0 <= y+dy < H]

def gen(seed, base, shape):
    rnd = random.Random(seed)
    kind, r = shape
    if kind == "sq":
        zone = {(x, y) for x in range(base[0]-r, base[0]+r+1)
                        for y in range(base[1]-r, base[1]+r+1)
                if 0 <= x < W and 0 <= y < H}
    else:  # disk
        zone = {(x, y) for x in range(W) for y in range(H)
                if (x-base[0])**2 + (y-base[1])**2 <= r*r + r}
    rest = [(x, y) for x in range(W) for y in range(H) if (x, y) not in zone]
    mines = set(rnd.sample(rest, MINES))
    num = {c: sum(1 for n in NB[c] if n in mines)
           for c in zone | set(rest)}
    return zone, mines, num

def flood(opened, start, mines, num):
    """从 start 洪水展开，返回本次新开格数（不数已在 opened 里的）"""
    if start in mines or start in opened:
        return 0
    opened.add(start)
    cnt = 1
    if num[start] == 0:
        stack = [start]
        while stack:
            for n in NB[stack.pop()]:
                if n not in opened and n not in mines:
                    opened.add(n); cnt += 1
                    if num[n] == 0:
                        stack.append(n)
    return cnt

def rule_targets(opened, flagged, mines, num):
    to_flag, to_open = set(), set()
    for c in opened:
        k = num[c]
        if k:
            fl = 0; un = []
            for n in NB[c]:
                if n in flagged: fl += 1
                elif n not in opened: un.append(n)
            if not un:
                continue
            if fl == k:
                to_open.update(un)
            elif len(un) + fl == k:
                to_flag.update(un)
    return to_flag - flagged, to_open

def simulate(seed, base, shape):
    """分阶段早退：预开区间 → 秒推目标数 → 全程可解（贵）。全部通过返回统计 dict。"""
    zone, mines, num = gen(seed, base, shape)
    # 预开：安全区 + 从区域内 0 数字格向外洪水
    opened = set(zone)
    for c in zone:
        if num[c] == 0:
            for n in NB[c]:
                flood(opened, n, mines, num)
    preopen = len(opened)
    if not (PREOPEN_LO <= preopen <= PREOPEN_HI):
        return None

    # 开局秒推级目标：单数字可推旗 + 放齐这些旗后的规则 1 可开格
    init_fl = set()
    for c in opened:
        k = num[c]
        if k:
            un = [n for n in NB[c] if n not in opened]
            if len(un) == k:
                init_fl.update(un)
    _, opens1 = rule_targets(opened, init_fl, mines, num)
    if len(init_fl) + len(opens1) < TARGETS_MIN:
        return None

    # ---- 全程推演（机器人 + 玩家收尾统一：贪心两规则）----
    flagged = set()
    max_flood = 0
    order_opened = []
    total_safe = W*H - MINES
    while len(opened) < total_safe or len(flagged) < MINES:
        tf, to = rule_targets(opened, flagged, mines, num)
        if tf:
            flagged.add(min(tf))
        elif to:
            t = min(to)
            k = flood(opened, t, mines, num)
            max_flood = max(max_flood, k)
            order_opened.append(t)
        else:
            return None  # 2 条规则推不动 → 弃
    final_dist = max(abs(order_opened[-1][0]-base[0]), abs(order_opened[-1][1]-base[1]))
    return dict(seed=seed, base=base, shape=shape, mines=mines, num=num,
                preopen=preopen, init_fl=init_fl, opens1=len(opens1),
                max_flood=max_flood, final_dist=final_dist,
                flags=len(flagged)-len(init_fl), opens=len(order_opened))

def checks(r):
    return {
        "solvable": True,
        "preopen_69_88": PREOPEN_LO <= r["preopen"] <= PREOPEN_HI,
        "targets_ge5": len(r["init_fl"]) + r["opens1"] >= TARGETS_MIN,
        "flood_ge6": r["max_flood"] >= FLOOD_MIN,
        "final_dist_3": r["final_dist"] >= FINAL_DIST_MIN,
    }

def gdscript_snippet(r):
    zone, mines, num = gen(r["seed"], r["base"], r["shape"])
    opened = set(zone)
    for c in zone:
        if num[c] == 0:
            for n in NB[c]:
                flood(opened, n, mines, num)
    ms = ", ".join(f"Vector2i({m[0]}, {m[1]})" for m in sorted(r["mines"]))
    ps = ", ".join(f"Vector2i({c[0]}, {c[1]})" for c in sorted(opened))
    return (f'const L2 := {{\n'
            f'\t"mines": [{ms}],\n'
            f'\t"preopen": [{ps}],\n'
            f'\t"base": Vector2i({r["base"][0]}, {r["base"][1]}),\n'
            f'}}')

MAX_SEED = 2000
stats = {"cheap": 0, "solved": 0, "pass": 0}
found = None
for seed in range(1, MAX_SEED + 1):
    for base in BASES:
        for shape in SHAPES:
            r = simulate(seed, base, shape)
            if r is None:
                continue
            stats["solved"] += 1
            c = checks(r)
            if all(c.values()):
                stats["pass"] += 1
                if found is None:
                    found = r
    if seed % 100 == 0:
        print(f"seed {seed}: {stats}", flush=True)
    if found:
        break

if not found:
    print("NO PASS", stats); sys.exit(1)

r = found
c = checks(r)
print(f"\n=== seed {r['seed']} base={r['base']} shape={r['shape']} ===")
print(f"预开 {r['preopen']} 格 | 开局可推旗 {len(r['init_fl'])} + 可开 {r['opens1']} = {len(r['init_fl'])+r['opens1']} 个秒推目标")
print(f"最大连锁 {r['max_flood']} 格 | 推演动作 标{r['flags']+len(r['init_fl'])}+开{r['opens']} | 收尾格距基地 {r['final_dist']}")
print("验收:", " ".join(f"{k}={'PASS' if v else 'FAIL'}" for k, v in c.items()))
print("统计:", stats)
zone, mines, num = gen(r["seed"], r["base"], r["shape"])
opened = set(zone)
for cc0 in zone:
    if num[cc0] == 0:
        for n in NB[cc0]:
            flood(opened, n, mines, num)
print("\n   " + " ".join(str(x % 10) for x in range(W)))
for y in range(H):
    row = []
    for x in range(W):
        cc = (x, y)
        if cc == r["base"]: row.append("B")
        elif cc in r["mines"]: row.append("x" if cc in r["init_fl"] else "X")
        elif cc in opened: row.append(str(num[cc]) if num[cc] else ".")
        else: row.append("#")
    print(f"{y:2d} " + " ".join(row))
print("x/X=雷(小写=开局即可推) #=未开 B=基地 .=已开空 数字=已开数字格")
print("\n---- GDScript ----")
print(gdscript_snippet(r))
