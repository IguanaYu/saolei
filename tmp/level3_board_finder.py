# -*- coding: utf-8 -*-
"""第三关盘面搜索器：对齐设计文档 v1.2 §7 验收标准（新断言模式——与 L1/L2"全程可解"的本质差异）

条件（全部满足才算 pass）：
  1. 模拟双规则推进直到无动作（遇歧义即停，不强求全解）：
     初始分 = 预开数 P（preopen_scores 口径，设计 v1.2）+ 推进分（开+1 / 标对+5）>= 300
  2. 过线（首次 >=300）时已标雷数 ∈ [28, 34]（70-85% × 40；下界防盘太简单，上界防"扫太多才够分"）
  3. 密度 40/256 = 15.6%（构造保证）
  4. 预开（含洪水）∈ [90, 115] 格（35-45%）
  5. 至少一次 >=6 格连锁展开
  6. 角部允许歧义：停摆时残余格（未开安全格+未标雷）全部在核心区之外——
     核心区 = 距盘中心切比雪夫 <= R_CORE 的区域，R_CORE 用扫描取该盘实际最大干净半径，断言 >= 4

推演口径：贪心两规则、可推旗优先（同 L2 工具；机器人 opener/marker 并行工作的保守近似）。
"""
import random, sys

W = H = 16
MINES = 40
PREOPEN_LO, PREOPEN_HI = 90, 115   # 256 格的 35-45%
SCORE_TARGET = 300                  # REACH_SCORE 目标（含预开起始分）
CROSS_FLAGS_LO, CROSS_FLAGS_HI = 28, 34
FLOOD_MIN = 6
R_CORE_MIN = 4                      # 11x11 中心区无歧义残余

SHAPES = [("sq", 2), ("sq", 3), ("disk", 3), ("disk", 4)]
BASES = [(x, y) for x in range(3, 13, 2) for y in range(3, 13, 2)]  # 25 个基点位
CENTER = (W // 2, H // 2)

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

def cheb_center(c):
    return max(abs(c[0]-CENTER[0]), abs(c[1]-CENTER[1]))

def simulate(seed, base, shape):
    """分阶段早退：预开区间 → 双规则推进到歧义停摆（统计过线时刻）→ 断言集"""
    zone, mines, num = gen(seed, base, shape)
    opened = set(zone)
    for c in zone:
        if num[c] == 0:
            for n in NB[c]:
                flood(opened, n, mines, num)
    preopen = len(opened)
    if not (PREOPEN_LO <= preopen <= PREOPEN_HI):
        return None

    # ---- 双规则推进，遇歧义即停（不再要求全解）----
    flagged = set()
    max_flood = 0
    score = preopen                       # 预开起始分（设计 v1.2 preopen_scores）
    crossed = False
    cross_flags = -1
    cross_opens = -1
    while True:
        tf, to = rule_targets(opened, flagged, mines, num)
        if tf:
            c = min(tf)
            flagged.add(c)
            score += 5
        elif to:
            t = min(to)
            k = flood(opened, t, mines, num)
            max_flood = max(max_flood, k)
            score += k
        else:
            break                          # 歧义停摆
        if not crossed and score >= SCORE_TARGET:
            crossed = True
            cross_flags = len(flagged)
            cross_opens = len(opened) - preopen
    if not crossed:
        return None                        # 歧义停摆仍未过线 → 盘不给力

    # ---- 歧义残余集中度：停摆时残余格全部在核心区之外 ----
    residual = ({c for c in opened0_all_safe(opened, mines)} - opened) | (mines - flagged)
    if not residual:
        r_core = max(CENTER)  # 全清（不应发生：断言 2 上界挡掉）
    else:
        r_core = min(cheb_center(c) for c in residual)
    return dict(seed=seed, base=base, shape=shape, mines=mines, num=num,
                preopen=preopen, score_final=score, crossed=crossed,
                cross_flags=cross_flags, cross_opens=cross_opens,
                max_flood=max_flood, r_core=r_core,
                residual=len(residual), flags=len(flagged), opens=len(opened)-preopen)

def opened0_all_safe(opened, mines):
    return {c for c in ALL if c not in mines}
ALL = {(x, y) for x in range(W) for y in range(H)}

def checks(r):
    return {
        "score_ge300_at_stop": r["crossed"],
        "cross_flags_28_34": CROSS_FLAGS_LO <= r["cross_flags"] <= CROSS_FLAGS_HI,
        "preopen_90_115": PREOPEN_LO <= r["preopen"] <= PREOPEN_HI,
        "flood_ge6": r["max_flood"] >= FLOOD_MIN,
        "core_clean_r4": r["r_core"] >= R_CORE_MIN,
    }

def regen_preopen(r):
    zone, mines, num = gen(r["seed"], r["base"], r["shape"])
    opened = set(zone)
    for c in zone:
        if num[c] == 0:
            for n in NB[c]:
                flood(opened, n, mines, num)
    return opened

def gdscript_snippet(r):
    opened = regen_preopen(r)
    ms = ", ".join(f"Vector2i({m[0]}, {m[1]})" for m in sorted(r["mines"]))
    ps = ", ".join(f"Vector2i({c[0]}, {c[1]})" for c in sorted(opened))
    return (f'const L3 := {{\n'
            f'\t"mines": [{ms}],\n'
            f'\t"preopen": [{ps}],\n'
            f'\t"base": Vector2i({r["base"][0]}, {r["base"][1]}),\n'
            f'}}')

MAX_SEED = 3000
MAX_PASS = 200   # 收集一批合格盘后挑最中庸的（|过线旗-31| + |预开-100|/10 最小）
stats = {"preopen": 0, "crossed": 0, "pass": 0}
passes = []
for seed in range(1, MAX_SEED + 1):
    for base in BASES:
        for shape in SHAPES:
            r = simulate(seed, base, shape)
            if r is None:
                stats["preopen"] += 1
                continue
            stats["crossed"] += 1
            c = checks(r)
            if all(c.values()):
                stats["pass"] += 1
                # 中庸度：旗数近 31 / 预开近 100；歧义残余 5-40 格（角部教训场景，§7.2）优先，
                # 残余 0（全程可解）或 >40（弃扫区过大）罚 5 分
                r["cost"] = abs(r["cross_flags"] - 31) + abs(r["preopen"] - 100) / 2.0 \
                        + (0.0 if 5 <= r["residual"] <= 40 else 5.0)
                passes.append(r)
    if seed % 50 == 0:
        print(f"seed {seed}: {stats}", flush=True)
    if len(passes) >= MAX_PASS:
        break

if not passes:
    print("NO PASS", stats); sys.exit(1)

passes.sort(key=lambda r: r["cost"])
found = passes[0]

r = found
c = checks(r)
print(f"\n=== seed {r['seed']} base={r['base']} shape={r['shape']} ===")
print(f"预开 {r['preopen']} 格（起始分） | 停摆总分 {r['score_final']}")
print(f"过线时刻：已标雷 {r['cross_flags']} 面 / 行动开格 {r['cross_opens']} | 最大连锁 {r['max_flood']} 格")
print(f"停摆残余 {r['residual']} 格，核心区干净半径 R={r['r_core']}（中心 {CENTER}）")
print("验收:", " ".join(f"{k}={'PASS' if v else 'FAIL'}" for k, v in c.items()))
print("统计:", stats)
opened = regen_preopen(r)
print("\n   " + " ".join(str(x % 10) for x in range(W)))
for y in range(H):
    row = []
    for x in range(W):
        cc = (x, y)
        if cc == r["base"]: row.append("B")
        elif cc in r["mines"]: row.append("X" if cc in r["mines"] else "x")
        elif cc in opened: row.append(str(r["num"][cc]) if r["num"][cc] else ".")
        else: row.append("#")
    print(f"{y:2d} " + " ".join(row))
print("X=雷 #=未开 B=基地 .=已开空 数字=已开数字格")
print("\n---- GDScript ----")
print(gdscript_snippet(r))
