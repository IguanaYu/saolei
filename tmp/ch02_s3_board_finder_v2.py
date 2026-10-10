# -*- coding: utf-8 -*-
"""第二章 2-3「特殊矿石」盘面搜索器 v2（改版 2026-10-10）：只搜雷位；
预开/加固墙/矿石两处手工布置。替代 v1 折光版（tmp/ch02_s3_board_finder.py 归档）。

对齐 改版提案-2026-10-10 §4 + 实施计划 WP3：
  1. 14×14 / 24 钻 / 预开恰 64（含基地 (1,7)）/ 加固墙 30 格 / 特殊矿石 2 处（附3 原型 2~3 取 2）
  2. 矿石：2×2 足迹全在预开安全格；束止于足迹（不穿透）；触发=束格踩足迹；
     爆发 3 随机互异八向 ×≤3 步（期望法：对 C(8,3)=56 组合取均值决策，
     实际结算用确定性组合序）——无限次可重复触发
  3. 教学线A：无钻石射线 ≥3 未开普通墙（沿 2-1 口径）；教学线B：一枪 ≥2 加固墙
  4. 矿石教学位：基地直射可达矿石 A（第 7 行直线）；首触期望收益 ≥2.0（正收益位）
  5. 足迹不切断预开区连通（基地可达前沿，base_can_reach_frontier 口径）
  6. 可达性：双规则 + 激光（含矿石重复触发）+ 筑墙工经济 ≥ 目标（目标=模拟分 ×0.88 取整 10）

墙层语义（总纲 §5.2）：未开格 hp=1 默认、加固 hp=3；开 hp=1 格=破墙即开；
零连开停在 hp>1 前；激光/机器人削层不开格。
beam_cells 与 GDScript LaserGeometry 逐 case 对拍（PY_TABLE 沿用导出表）。
"""
import itertools, random, sys
from collections import deque

W = H = 14
MINES = 24
BASE = (1, 7)
ACTIONS_BUDGET = 68          # 5 免费 + 210s/3s ≈ 68 发（矿石重复触发提高单发价值）
TARGET_RATIO = 0.88          # 模拟分 ×0.88 → 关卡目标分（v1: 283→250 同口径）
FLAGS_MIN = 10
SHATTER_MAX = 2
FLOOD_MIN = 5
ORE_EV_TEACH = 2.0           # 矿石 A 首触期望收益下限（教学位正收益）

# 预开区（恰 64 格，同 v1）：x∈[0,5]×y∈[4,10]=42 ∪ x=6,y∈[5,9]=5 ∪ 上/下沿 4
# ∪ 东扩列 (7,5..9)=5 ∪ 顶部 (2,3),(3,3) 与底部 (2,11),(3,11)=4 ∪ 东咬口 4
ZONE = ({(x, y) for x in range(0, 6) for y in range(4, 11)}
        | {(6, y) for y in range(5, 10)}
        | {(0, 3), (1, 3), (0, 11), (1, 11)}
        | {(7, y) for y in range(5, 10)}
        | {(2, 3), (3, 3), (2, 11), (3, 11)}
        | {(8, 6), (8, 7), (8, 8), (7, 4)})

# 特殊矿石 2 处（足迹 2×2，全在预开区内）：
# A=东带位（v1 折光驻点改造：基地第 7 行直射、东墙带 x9-11 正面）
# B=北带位（北区墙带 y2 正面、远离基地非平凡）
ORE_A = (7, 6)
ORE_B = (3, 4)
ORES = [ORE_A, ORE_B]


def foot(o):
    return {(o[0], o[1]), (o[0] + 1, o[1]), (o[0], o[1] + 1), (o[0] + 1, o[1] + 1)}


FEET = set().union(*[foot(o) for o in ORES])

# 加固墙 30 格（同 v1——矿石 A 吃东墙带、矿石 B 吃北横带，爆发面现成）
WALLS = ({(x, y) for x in range(9, 12) for y in range(5, 9)}   # A 东墙带 3x4=12（矿石 A 正面）
         | {(x, 12) for x in range(4, 10)}      # B 横带：南区 6
         | {(x, 2) for x in range(4, 8)}        # C 横带：北区 4（矿石 B 正面）
         | {(12, 4), (12, 5)}                   # D：右缘 2
         | {(10, 10), (11, 11)}                 # E：东南散点 2
         | {(12, 2), (13, 7), (13, 12), (9, 4)})  # F：远角长线 4

NB = {}
for x in range(W):
    for y in range(H):
        NB[(x, y)] = [(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)
                      if (dx or dy) and 0 <= x + dx < W and 0 <= y + dy < H]
ALL = {(x, y) for x in range(W) for y in range(H)}
DIRS8 = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]


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
}
for (f, t), want in PY_TABLE.items():
    got = beam_cells(f, t)
    assert got == want, "beam_cells 对拍失败 %s->%s\n got %s\nwant %s" % (f, t, got, want)
print("beam_cells 对拍 10/10 OK")

COMBOS = list(itertools.combinations(range(8), 3))  # 56 组互异八向（互异=两两 ≥45°>30°）


def burst_cells(origin, combo, hp, opened, flagged, mines):
    """一组三向的爆发格集（剔全部矿石足迹=不可破坏；界内）——静态收益可预筛"""
    out = []
    for di in combo:
        d = DIRS8[di]
        ex = origin[0] + (1 if d[0] > 0 else 0)
        ey = origin[1] + (1 if d[1] > 0 else 0)
        edge = (ex, ey)
        for c in beam_cells(edge, (edge[0] + d[0] * 3, edge[1] + d[1] * 3)):
            if c in FEET or c not in ALL or c in out:
                continue
            out.append(c)
    return out


def burst_value(cells, opened, flagged, mines, hp):
    v = 0.0
    for c in cells:
        if c in flagged or c in opened:
            continue
        if c in mines:
            v -= 4.0
        elif hp[c] > 1:
            v += 0.3
        else:
            v += 1.0
    return v


def ore_ev(origin, opened, flagged, mines, hp):
    """矿石期望收益（56 组合均值）——决策用；实际结算走确定性组合序"""
    total = 0.0
    for combo in COMBOS:
        total += burst_value(burst_cells(origin, combo, hp, opened, flagged, mines),
                             opened, flagged, mines, hp)
    return total / len(COMBOS)


def shot_cells(base, t, ore_counter, opened, flagged, mines, hp):
    """含矿石截停与爆发的完整束：主束遇足迹截停；命中矿石 → 确定性组合爆发格并入"""
    beam = []
    hit_ore = None
    for c in beam_cells(base, t):
        beam.append(c)
        for o in ORES:
            if c in foot(o):
                hit_ore = o
                break
        if hit_ore:
            break
    out = [c for c in beam if c in ALL]
    if hit_ore is not None:
        combo = COMBOS[(ore_counter * 7919 + 41) % len(COMBOS)]  # 确定性伪随机序
        out += [c for c in burst_cells(hit_ore, combo, hp, opened, flagged, mines)
                if c not in out]
    return out, hit_ore


def gen(seed):
    rnd = random.Random(seed)
    rest = sorted(ALL - ZONE)
    mines = set(rnd.sample(rest, MINES))
    num = {c: sum(1 for n in NB[c] if n in mines) for c in ALL}
    return mines, num


def flood(opened, start, mines, num, hp, max_flood):
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
                hp[c] -= 1
                progressed = True
            else:
                n, max_flood = flood(opened, c, mines, num, hp, max_flood)
                if n:
                    score += 1
                    progressed = True
        if not progressed and not tf:
            break
    return score, max_flood


def beam_value(t, opened, flagged, mines, hp, ore_count):
    """谨慎玩家的一发估值：直射束 + 命中矿石时的爆发期望（开格+1/削层+0.3/碎钻-4）"""
    v = 0.0
    hit_ore = None
    for c in beam_cells(BASE, t):
        for o in ORES:
            if c in foot(o):
                hit_ore = o
                break
        if hit_ore or c not in ALL:
            if c in ALL and c not in flagged and c not in opened:
                v += (-4.0 if c in mines else (0.3 if hp[c] > 1 else 1.0))
            break
        if c in flagged or c in opened:
            continue
        if c in mines:
            v -= 4.0
        elif hp[c] > 1:
            v += 0.3
        else:
            v += 1.0
    if hit_ore is not None:
        v += ore_ev(hit_ore, opened, flagged, mines, hp)
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
    ore_counter = 0

    tf0, to0 = rule_targets(opened, flagged, mines, num)
    init_flags, init_targets = len(tf0), len(tf0 | to0)
    teach_a = 0
    for t in ALL - {BASE}:
        beam = beam_cells(BASE, t)
        if any(c in mines for c in beam):
            continue
        teach_a = max(teach_a, sum(
            1 for c in beam if c not in opened and hp[c] == 1 and c not in FEET))
    teach_b = 0
    for t in ALL:
        if t == BASE:
            continue
        peels = sum(1 for c in beam_cells(BASE, t)
                    if c not in opened and c not in flagged and hp[c] > 1)
        teach_b = max(teach_b, peels)

    # 矿石教学位：基地第 7 行直射可达矿石 A 足迹；首触期望 ≥ ORE_EV_TEACH
    ore_a_direct = any(f in beam_cells(BASE, (13, 7)) for f in foot(ORE_A))
    ore_a_ev0 = ore_ev(ORE_A, opened, flagged, mines, hp)
    # 足迹连通性：预开区扣足迹后基地可达 ≥95%（base_can_reach_frontier 口径）
    reach = {BASE}
    dq = deque([BASE])
    while dq:
        for n in NB[dq.popleft()]:
            if n in ZONE and n not in FEET and n not in reach:
                reach.add(n)
                dq.append(n)
    zone_open = {c for c in ZONE if c not in FEET}
    connectivity = len(reach) >= len(zone_open) * 0.95

    while True:
        score, max_flood = robot_phase(opened, flagged, mines, num, hp, score, max_flood)
        if actions <= 0:
            break
        best_t, best_v = None, 0.0
        for t in ALL:
            if t == BASE:
                continue
            v = beam_value(t, opened, flagged, mines, hp, ore_counter)
            if v > best_v:
                best_v, best_t = v, t
        if best_t is None:
            break
        cells, hit = shot_cells(BASE, best_t, ore_counter, opened, flagged, mines, hp)
        if hit is not None:
            ore_counter += 1
        for c in cells:
            if c in FEET or c in flagged or c in opened:
                continue
            if c in mines:
                opened.add(c)
                score += 1
                shatters += 1
            elif hp[c] > 1:
                hp[c] -= 1
            else:
                n, max_flood = flood(opened, c, mines, num, hp, max_flood)
                score += 1
        actions -= 1
    score, max_flood = robot_phase(opened, flagged, mines, num, hp, score, max_flood)

    spawn_times = [12 + 25 * k for k in range(10) if 12 + 25 * k < 210 - 10]
    kills_affordable = min(len(spawn_times), ACTIONS_BUDGET // 2)
    kill_score = 10 * kills_affordable
    cover_score = kills_affordable
    total = score + kill_score + cover_score

    return dict(seed=seed, mines=mines, score=score, total=total,
                dynamic=kill_score + cover_score, kills=kills_affordable,
                ore_a_direct=ore_a_direct, ore_a_ev0=ore_a_ev0,
                connectivity=connectivity, ore_shots=ore_counter,
                flags=len(flagged), shatters=shatters, max_flood=max_flood,
                init_flags=init_flags, init_targets=init_targets,
                teach_a=teach_a, teach_b=teach_b)


def checks(r, target):
    return {
        "total_ge_target": r["total"] >= target,
        "static_ge180": r["score"] >= 180,
        "flags_ge10": r["flags"] >= FLAGS_MIN,
        "shatter_le2": r["shatters"] <= SHATTER_MAX,
        "flood_ge5": r["max_flood"] >= FLOOD_MIN,
        "init_flags_ge1": r["init_flags"] >= 1,
        "init_targets_ge2": r["init_targets"] >= 2,
        "teach_line_a": r["teach_a"] >= 3,
        "teach_line_b": r["teach_b"] >= 2,
        "ore_a_direct": r["ore_a_direct"],
        "ore_a_ev": r["ore_a_ev0"] >= ORE_EV_TEACH,
        "connectivity": r["connectivity"],
        "ore_used": r["ore_shots"] >= 2,
    }


def gdscript_snippet(r):
    ms = ", ".join(f"Vector2i({m[0]}, {m[1]})" for m in sorted(r["mines"]))
    ps = ", ".join(f"Vector2i({c[0]}, {c[1]})" for c in sorted(ZONE))
    ws = ", ".join(f"Vector2i({c[0]}, {c[1]})" for c in sorted(WALLS))
    os_ = ", ".join('{"origin": Vector2i(%d, %d)}' % o for o in ORES)
    return ("const CH2_S3 := {\n"
            f'\t"mines": [{ms}],\n'
            f'\t"preopen": [{ps}],\n'
            f'\t"base": Vector2i({BASE[0]}, {BASE[1]}),\n'
            f'\t"walls": [{ws}],\n'
            f'\t"ores": [{os_}],\n'
            "}")


assert len(ZONE) == 64, f"预开区 {len(ZONE)} 格 ≠ 64"
assert BASE in ZONE
for o in ORES:
    assert foot(o) <= ZONE, f"矿石 {o} 足迹须全在预开区"
assert not (WALLS & ZONE), "加固墙与预开区重叠"
assert len(WALLS) == 30, f"加固墙 {len(WALLS)} 格 ≠ 30"
assert len(ORES) == 2

MAX_SEED = 3000
MAX_PASS = 60
# 两段式：先按动态带下限筛一批（total≥255），再按中庸度挑（目标=模拟分 ×0.88）
PRE_TARGET = 255
passes = []
stats = {"pass": 0}
for seed in range(1, MAX_SEED + 1):
    r = simulate(seed)
    if all(checks(r, PRE_TARGET).values()):
        stats["pass"] += 1
        r["target"] = int(round(r["total"] * TARGET_RATIO / 10.0) * 10)
        r["cost"] = abs(r["score"] - 228) / 5.0 \
            + (0.0 if r["shatters"] == 0 else 4.0) \
            + (0.0 if 10 <= r["flags"] <= 16 else 3.0)
        passes.append(r)
    if seed % 100 == 0:
        print(f"seed {seed}: pass={stats['pass']}", flush=True)
    if len(passes) >= MAX_PASS:
        break

if not passes:
    near = sorted((simulate(s) for s in range(1, 201)),
                  key=lambda r: sum(checks(r, PRE_TARGET).values()), reverse=True)[:3]
    for r in near:
        print("NEAR", {k: v for k, v in r.items() if k not in ("mines",)},
              checks(r, PRE_TARGET))
    print("NO PASS", stats)
    sys.exit(1)

passes.sort(key=lambda r: r["cost"])
found = passes[0]
print("FOUND", {k: v for k, v in found.items() if k not in ("mines",)})
print(f"pass_total={len(passes)} best_cost={found['cost']:.2f}")
print(f"目标分建议：{found['target']}（模拟 total={found['total']} ×{TARGET_RATIO}）")
print()
print(gdscript_snippet(found))
