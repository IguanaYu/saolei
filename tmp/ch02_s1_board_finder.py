# -*- coding: utf-8 -*-
"""第二章 2-1「激光开矿」盘面搜索器：只搜雷位（预开区/加固墙手工布置，与雷独立）

对齐 docs/active/玩法设计/第二章-激光矿场/2-1-激光开矿-设计文档.md §3：
  1. 12×12 / 18 钻 / 预开恰 40（含基地 (1,6)）/ 加固墙 18 格（手工布局）
  2. 教学线A：存在一条无钻石射线，沿线 ≥3 格未开普通墙（点得越远开得越多 +
     可推理安全=线上无钻石可打碎；开格由激光完成而非 t0 推理，设计 §3 原意）
  3. 教学线B：存在一枪同时削到 ≥2 块 3 层墙的射线（计算校验）
  4. 可达性：机器人（双规则免费）+ 玩家激光（≤63 发动作预算）模拟 ≥145 分，
     其中正确标记 ≥9 枚（"140 不能只靠扫碎钻石过关"），碎钻 ≤2
  5. 零连开有戏：模拟中出现 ≥5 格连锁展开（机器人高光）
  6. 开局双规则可推旗 ≥1（标记教学线有素材）

墙层语义（总纲 §5.2）：未开格 hp=1 默认、加固 hp=3；开 hp=1 格=破墙即开；
零连开停在 hp>1 前；激光/机器人削层不开格。
beam_cells 与 GDScript LaserGeometry 逐 case 对拍（PY_TABLE 由 tmp/test_laser_geometry.gd 导出）。
"""
import random, sys

W = H = 12
MINES = 18
BASE = (1, 6)
ACTIONS_BUDGET = 63          # 5 免费 + 180s/3s ≈ 63 发
SCORE_TARGET = 145           # 140 目标 + 5 容错
FLAGS_MIN = 9
SHATTER_MAX = 2
FLOOD_MIN = 5

# 预开区（恰 40 格，含基地）：x∈[0,4]×y∈[4,9]=30 ∪ x=5,y∈[4,9]=6 ∪ 四角外延 4
ZONE = ({(x, y) for x in range(0, 5) for y in range(4, 10)}
        | {(5, y) for y in range(4, 10)}
        | {(0, 3), (1, 3), (0, 10), (1, 10)})

# 加固墙（18 格，与雷位独立布置——外壳不从钻石真值决定，总纲 §4.4）
WALLS = ({(6, y) for y in range(3, 8)}          # A 竖带：东区正面
         | {(x, 10) for x in range(5, 9)}       # B 横带：南区
         | {(4, 2), (5, 2), (6, 2)}             # C 簇：东北（45° 斜线一枪双削）
         | {(10, 3), (10, 4)}                   # D：右缘
         | {(9, 8), (10, 9)}                    # E：东南散点
         | {(11, 1), (11, 11)})                 # F：远角（长线价值）

NB = {}
for x in range(W):
    for y in range(H):
        NB[(x, y)] = [(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)
                      if (dx or dy) and 0 <= x + dx < W and 0 <= y + dy < H]
ALL = {(x, y) for x in range(W) for y in range(H)}


# ---- beam_cells：与 GDScript LaserGeometry 同算法（事件表 + 整数键合并同刻） ----
def beam_cells(f, t):
    if f == t:
        return []
    out = []
    dx, dy = t[0] - f[0], t[1] - f[1]
    ax, ay = abs(dx), abs(dy)
    sx, sy = (1 if dx > 0 else -1), (1 if dy > 0 else -1)
    events = []
    for i in range(1, ax + 1):
        events.append(((2 * i - 1) * ay, 0))
    for j in range(1, ay + 1):
        events.append(((2 * j - 1) * ax, 1))
    events.sort()
    cx, cy = f
    idx = 0
    while idx < len(events):
        key, kind = events[idx]
        if idx + 1 < len(events) and events[idx + 1][0] == key \
                and kind != events[idx + 1][1]:
            cx += sx; out.append((cx, cy))
            cy += sy; out.append((cx, cy))
            idx += 2
            continue
        if kind == 0:
            cx += sx
        else:
            cy += sy
        out.append((cx, cy))
        idx += 1
    return out


# 对拍表（tmp/test_laser_geometry.gd 的 PY_TABLE 输出；不一致=规则漂移，直接终止）
PY_TABLE = {
    ((0, 0), (3, 0)): [(1, 0), (2, 0), (3, 0)],
    ((0, 0), (0, 3)): [(0, 1), (0, 2), (0, 3)],
    ((0, 0), (3, 3)): [(1, 0), (1, 1), (2, 1), (2, 2), (3, 2), (3, 3)],
    ((0, 0), (3, 2)): [(1, 0), (1, 1), (2, 1), (2, 2), (3, 2)],
    ((0, 0), (2, 3)): [(0, 1), (1, 1), (1, 2), (2, 2), (2, 3)],
    ((0, 0), (4, 1)): [(1, 0), (2, 0), (2, 1), (3, 1), (4, 1)],
    ((0, 0), (3, 1)): [(1, 0), (2, 0), (2, 1), (3, 1)],
    ((1, 6), (11, 6)): [(x, 6) for x in range(2, 12)],
    ((1, 6), (9, 11)): [(2, 6), (2, 7), (3, 7), (3, 8), (4, 8), (5, 8), (5, 9),
                        (6, 9), (7, 9), (7, 10), (8, 10), (8, 11), (9, 11)],
    ((1, 6), (8, 0)): [(2, 6), (2, 5), (3, 5), (3, 4), (4, 4), (4, 3), (5, 3),
                       (5, 2), (6, 2), (6, 1), (7, 1), (7, 0), (8, 0)],
    ((2, 3), (10, 9)): [(3, 3), (3, 4), (4, 4), (4, 5), (5, 5), (5, 6), (6, 6),
                        (7, 6), (7, 7), (8, 7), (8, 8), (9, 8), (9, 9), (10, 9)],
    ((5, 5), (6, 5)): [(6, 5)],
}
for (f, t), want in PY_TABLE.items():
    got = beam_cells(f, t)
    assert got == want, "beam_cells 对拍失败 %s->%s\n got %s\nwant %s" % (f, t, got, want)
print("beam_cells 对拍 12/12 OK")


def gen(seed):
    rnd = random.Random(seed)
    rest = sorted(ALL - ZONE)
    mines = set(rnd.sample(rest, MINES))
    num = {c: sum(1 for n in NB[c] if n in mines) for c in ALL}
    return mines, num


def flood(opened, start, mines, num, hp, max_flood):
    """破墙开格 + 零连开（停在 hp>1 前）；返回 (本次开格数, 历史最大连锁)"""
    if start in mines or start in opened:
        return 0, max_flood
    opened.add(start)
    cnt = 1
    if num[start] == 0:
        stack = [start]
        while stack:
            for n in NB[stack.pop()]:
                if n in opened or n in mines or hp[n] > 1:
                    continue
                opened.add(n)
                cnt += 1
                if num[n] == 0:
                    stack.append(n)
    return cnt, max(max_flood, cnt)


def rule_targets(opened, flagged, mines, num):
    to_flag, to_open = set(), set()
    for c in opened:
        k = num[c]
        if not k:
            continue
        fl = 0
        un = []
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


def robot_phase(opened, flagged, mines, num, hp, score, max_flood):
    """双规则免费推进（opener 削层/开格 + marker 标旗）直到稳定"""
    while True:
        tf, to = rule_targets(opened, flagged, mines, num)
        if tf:
            for c in tf:
                flagged.add(c)
                score += 5
            continue
        progressed = False
        for c in list(to):
            if c in opened:
                continue
            if hp[c] > 1:
                hp[c] -= 1          # 开墙机器人削层（不加分）
                progressed = True
            else:
                n, max_flood = flood(opened, c, mines, num, hp, max_flood)
                if n:
                    score += 1
                    progressed = True
        if not progressed and not tf:
            break
    return score, max_flood


def beam_value(t, opened, flagged, mines, hp):
    """谨慎玩家的一发估值：开格 +1 / 削层 +0.3 / 误打钻石 -4（丢 5 旗分得 1 碎钻分）"""
    v = 0.0
    for c in beam_cells(BASE, t):
        if c in flagged or c in opened:
            continue
        if c in mines:
            v -= 4.0
        elif hp[c] > 1:
            v += 0.3
        else:
            v += 1.0
    return v


def simulate(seed):
    mines, num = gen(seed)
    opened = set(ZONE)
    flagged = set()
    hp = {c: (3 if c in WALLS else 1) for c in ALL}
    for c in ZONE:
        hp[c] = 0
    score = 0
    shatters = 0
    max_flood = 0
    actions = ACTIONS_BUDGET

    # 开局双规则快照（教学线断言用）
    tf0, to0 = rule_targets(opened, flagged, mines, num)
    init_flags, init_targets = len(tf0), len(tf0 | to0)
    # 教学线A：无钻石射线上 ≥3 格未开 1 层普通墙（激光教学线）
    teach_a = 0
    for t in ALL - {BASE}:
        beam = beam_cells(BASE, t)
        if any(c in mines for c in beam):
            continue  # 线上有钻石=不可推理安全
        teach_a = max(teach_a, sum(
            1 for c in beam if c not in opened and hp[c] == 1))
    # 教学线B：一枪 ≥2 块 3 层墙
    teach_b = 0
    for t in ALL:
        if t == BASE:
            continue
        peels = sum(1 for c in beam_cells(BASE, t)
                    if c not in opened and c not in flagged and hp[c] > 1)
        teach_b = max(teach_b, peels)

    # 主模拟：机器人免费 + 激光按预算
    while True:
        score, max_flood = robot_phase(opened, flagged, mines, num, hp, score, max_flood)
        if actions <= 0:
            break
        best_t, best_v = None, 0.0
        for t in ALL:
            if t == BASE:
                continue
            v = beam_value(t, opened, flagged, mines, hp)
            if v > best_v:
                best_v, best_t = v, t
        if best_t is None:
            break
        for c in beam_cells(BASE, best_t):
            if c in flagged or c in opened:
                continue
            if c in mines:
                opened.add(c)      # 碎钻=已处理（坍塌口径）
                score += 1
                shatters += 1
            elif hp[c] > 1:
                hp[c] -= 1
            else:
                n, max_flood = flood(opened, c, mines, num, hp, max_flood)
                score += 1
        actions -= 1
    # 最后一轮机器人收尾
    score, max_flood = robot_phase(opened, flagged, mines, num, hp, score, max_flood)

    return dict(seed=seed, mines=mines, num=num, score=score, flags=len(flagged),
                shatters=shatters, max_flood=max_flood, init_flags=init_flags,
                init_targets=init_targets, teach_a=teach_a, teach_b=teach_b,
                actions_used=ACTIONS_BUDGET - actions)


def checks(r):
    return {
        "score_ge145": r["score"] >= SCORE_TARGET,
        "flags_ge9": r["flags"] >= FLAGS_MIN,
        "shatter_le2": r["shatters"] <= SHATTER_MAX,
        "flood_ge5": r["max_flood"] >= FLOOD_MIN,
        "init_flags_ge1": r["init_flags"] >= 1,
        "init_targets_ge2": r["init_targets"] >= 2,
        "teach_line_a": r["teach_a"] >= 3,
        "teach_line_b": r["teach_b"] >= 2,
    }


def gdscript_snippet(r):
    ms = ", ".join(f"Vector2i({m[0]}, {m[1]})" for m in sorted(r["mines"]))
    ps = ", ".join(f"Vector2i({c[0]}, {c[1]})" for c in sorted(ZONE))
    ws = ", ".join(f"Vector2i({c[0]}, {c[1]})" for c in sorted(WALLS))
    return ("const CH2_S1 := {\n"
            f'\t"mines": [{ms}],\n'
            f'\t"preopen": [{ps}],\n'
            f'\t"base": Vector2i({BASE[0]}, {BASE[1]}),\n'
            f'\t"walls": [{ws}],\n'
            "}")


assert len(ZONE) == 40, f"预开区 {len(ZONE)} 格 ≠ 40"
assert BASE in ZONE
assert not (WALLS & ZONE), "加固墙与预开区重叠"
assert len(WALLS) == 18, f"加固墙 {len(WALLS)} 格 ≠ 18"

MAX_SEED = 3000
MAX_PASS = 60
passes = []
stats = {"pass": 0}
for seed in range(1, MAX_SEED + 1):
    r = simulate(seed)
    if all(checks(r).values()):
        stats["pass"] += 1
        # 中庸度：分在 145-165（有挑战不满溢）、碎钻 0 最好、旗 9-14
        r["cost"] = abs(r["score"] - 155) / 5.0 \
            + (0.0 if r["shatters"] == 0 else 4.0) \
            + (0.0 if 9 <= r["flags"] <= 14 else 3.0)
        passes.append(r)
    if seed % 100 == 0:
        print(f"seed {seed}: pass={stats['pass']}", flush=True)
    if len(passes) >= MAX_PASS:
        break

if not passes:
    # 诊断：打印最接近的一批
    near = sorted((simulate(s) for s in range(1, 201)),
                  key=lambda r: sum(checks(r).values()), reverse=True)[:3]
    for r in near:
        print("NEAR", {k: v for k, v in r.items() if k not in ("mines", "num")},
              checks(r))
    print("NO PASS", stats)
    sys.exit(1)

passes.sort(key=lambda r: r["cost"])
found = passes[0]
print("FOUND", {k: v for k, v in found.items() if k not in ("mines", "num")})
print(f"pass_total={len(passes)} best_cost={found['cost']:.2f}")
print()
print(gdscript_snippet(found))
