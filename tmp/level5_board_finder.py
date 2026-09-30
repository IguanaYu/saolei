# -*- coding: utf-8 -*-
"""第五关盘面搜索器：对齐设计文档 v1.0 §9 验收标准（Boss 关·固定盘）

条件（全部满足才算 pass）：
  1. 全程双规则可解（L1/L2 同款断言）：推进到无动作时 无残余——
     全部安全格已开 且 全部 20 颗雷已标（「拔完 20 颗牙不依赖猜雷」）
  2. 密度 20/196 = 10.2%（构造保证）
  3. 预开（含洪水）∈ [59, 78] 格（196 格的 30-40%）
  4. 开局（预开后首轮双规则）秒推级可动作目标 ≥5 个，其中可推旗 ≥1 面
     （牙数尽早动起来 + 5 次免费操作有活干）
  5. 推进过程中至少一次 ≥6 格连锁展开（机器人高光）
  6. Boss 入口区无雷（设计 §9.6/9.7）：第一行中段 x∈[4,9] 共 6 格 + 最右列 x=13 全列，
     招式入口与雷位不混淆
  7. 雷不进预开区（构造保证，同 L1-L3）

推演口径：贪心两规则、可推旗优先（同 L2/L3 工具；机器人并行工作的保守近似）。
"""
import random, sys

W = H = 14
MINES = 20
PREOPEN_LO, PREOPEN_HI = 59, 78   # 196 格的 30-40%
INIT_ACTIONS_MIN = 5              # 开局秒推目标数下界
INIT_FLAGS_MAX = 5                # 开局可推旗上界（防 5 次免费连点秒过 P1 门槛）
FLOOD_MIN = 6                     # ≥6 格连锁
BOSS_TOP_X = range(4, 10)         # 第一行中段（上侧 Boss 入口）
BOSS_RIGHT_X = W - 1              # 最右列（P3 换位后入口）
# 预开区永不触碰第一行（烘焙规则）：上边缘整行留墙——史莱姆入场即有墙可爬（P1 编排）

SHAPES = [("sq", 3), ("disk", 4), ("disk", 5)]
CENTERS = [(x, y) for x in range(3, 11, 2) for y in range(3, 11, 2)]

NB = {}
for x in range(W):
    for y in range(H):
        NB[(x, y)] = [(x+dx, y+dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)
                      if (dx or dy) and 0 <= x+dx < W and 0 <= y+dy < H]
ALL = {(x, y) for x in range(W) for y in range(H)}


def gen(seed, center, shape):
    rnd = random.Random(seed)
    kind, r = shape
    if kind == "sq":
        zone = {(x, y) for x in range(center[0]-r, center[0]+r+1)
                        for y in range(center[1]-r, center[1]+r+1)
                if 0 <= x < W and 0 <= y < H}
    else:
        zone = {(x, y) for x in range(W) for y in range(H)
                if (x-center[0])**2 + (y-center[1])**2 <= r*r + r}
    # Boss 入口区并入禁区
    forbidden = zone | {(x, 0) for x in BOSS_TOP_X} | {(BOSS_RIGHT_X, y) for y in range(H)}
    rest = [(x, y) for x in range(W) for y in range(H) if (x, y) not in forbidden]
    mines = set(rnd.sample(rest, MINES))
    num = {c: sum(1 for n in NB[c] if n in mines) for c in ALL}
    return zone, mines, num


def flood(opened, start, mines, num):
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
        if not k:
            continue
        fl = 0; un = []
        for n in NB[c]:
            if n in flagged:
                fl += 1
            elif n not in opened:
                un.append(n)
        if not un:
            continue
        if fl == k:
            to_open.update(un)
        elif len(un) + fl == k:
            to_flag.update(un)
    return to_flag - flagged, to_open


def simulate(seed, center, shape):
    zone, mines, num = gen(seed, center, shape)
    opened = set(zone)
    for c in zone:
        if num[c] == 0:
            for n in NB[c]:
                flood(opened, n, mines, num)
    opened = {c for c in opened if c[1] != 0}   # 第一行永不预开：上边缘整行留墙
    preopen = len(opened)
    if not (PREOPEN_LO <= preopen <= PREOPEN_HI):
        return None

    flagged = set()
    max_flood = 0
    init_actions = init_flags = -1
    while True:
        tf, to = rule_targets(opened, flagged, mines, num)
        if init_actions < 0:
            init_actions, init_flags = len(tf) + len(to), len(tf)
        if tf:
            flagged.add(min(tf))
        elif to:
            max_flood = max(max_flood, flood(opened, min(to), mines, num))
        else:
            break
    residual_safe = {c for c in ALL if c not in mines} - opened
    residual_mines = mines - flagged
    return dict(seed=seed, center=center, shape=shape, mines=mines, num=num,
                preopen=preopen, init_actions=init_actions, init_flags=init_flags,
                max_flood=max_flood, flags=len(flagged), opens=len(opened) - preopen,
                residual=len(residual_safe) + len(residual_mines))


def checks(r):
    return {
        "fully_solvable": r["residual"] == 0,
        "preopen_59_78": PREOPEN_LO <= r["preopen"] <= PREOPEN_HI,
        "init_actions_ge5": r["init_actions"] >= INIT_ACTIONS_MIN,
        "init_flags_1_5": 1 <= r["init_flags"] <= INIT_FLAGS_MAX,
        "flood_ge6": r["max_flood"] >= FLOOD_MIN,
    }


def regen_preopen(r):
    zone, mines, num = gen(r["seed"], r["center"], r["shape"])
    opened = set(zone)
    for c in zone:
        if num[c] == 0:
            for n in NB[c]:
                flood(opened, n, mines, num)
    return {c for c in opened if c[1] != 0}   # 与 simulate 同口径：第一行留墙


def gdscript_snippet(r):
    opened = regen_preopen(r)
    ms = ", ".join(f"Vector2i({m[0]}, {m[1]})" for m in sorted(r["mines"]))
    ps = ", ".join(f"Vector2i({c[0]}, {c[1]})" for c in sorted(opened))
    return (f'const L5 := {{\n'
            f'\t"mines": [{ms}],\n'
            f'\t"preopen": [{ps}],\n'
            f'}}   # base 玩家自放：level_database 里 fixed_base=(-1,-1)')


MAX_SEED = 3000
MAX_PASS = 100
stats = {"preopen": 0, "pass": 0}
passes = []
for seed in range(1, MAX_SEED + 1):
    for center in CENTERS:
        for shape in SHAPES:
            r = simulate(seed, center, shape)
            if r is None:
                stats["preopen"] += 1
                continue
            c = checks(r)
            if all(c.values()):
                stats["pass"] += 1
                # 中庸度：预开近中值 68；开局可推旗 2-4 面最理想（牙数早动但不秒拔太多）
                r["cost"] = abs(r["preopen"] - 68) / 2.0 \
                        + (0.0 if 2 <= r["init_flags"] <= 4 else 3.0) \
                        + abs(r["init_actions"] - 7)
                passes.append(r)
    if seed % 50 == 0:
        print(f"seed {seed}: {stats}", flush=True)
    if len(passes) >= MAX_PASS:
        break

if not passes:
    print("NO PASS", stats); sys.exit(1)

passes.sort(key=lambda r: r["cost"])
found = passes[0]
print("FOUND", {k: v for k, v in found.items() if k not in ("mines", "num")})
print(f"pass_total={len(passes)} best_cost={found['cost']:.2f}")
print()
print(gdscript_snippet(found))
