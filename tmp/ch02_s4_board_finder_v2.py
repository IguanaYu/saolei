# -*- coding: utf-8 -*-
"""第二章 2-4「过载机器人」盘面搜索器 v2（改版 2026-10-10）：只搜雷位；
预开/加固墙手工布置（连爆节点与折光驻点退场，D5）。替代 v1（tmp/ch02_s4_board_finder.py 归档）。

对齐 改版提案-2026-10-10 §5 + 实施计划 WP5：
  1. 16×16 / 32 钻 / 预开恰 80（含基地 (1,7)）/ 加固墙 42 格（沿 v1 墙带=爆炸收益区）
  2. 过载模型：开局金 180 立即购入（100），此后每 OVERLOAD_PERIOD=3 发可用一次
     「过载射击」——束从基地穿过机器人工位（预开前沿格=低数字×靠墙偏好位），
     13 格爆炸（3×3+四正各1）并入选中束结算；无限次（拍板 #5/#7）
  3. 教学线A：无钻石射线 ≥3 未开普通墙；教学线B：一枪 ≥2 加固墙（沿 2-1 口径）
  4. 首爆教学位：存在前沿工位，束+13 格爆炸首打价值 ≥5.0（走位即提示的可见收益）
  5. 爆炸收益区：东墙带在多个前沿工位 3×3 射程内（≥3 个工位爆炸可削 ≥2 加固层）
  6. 可达性：双规则 + 激光（含过载射击）+ 筑墙工经济 ≥ 目标（目标=模拟分 ×0.93 取整 5；
     v1 口径 332→320）

墙层语义（总纲 §5.2）：未开格 hp=1 默认、加固 hp=3；开 hp=1 格=破墙即开；
零连开停在 hp>1 前；激光/机器人削层不开格。
beam_cells 与 GDScript LaserGeometry 逐 case 对拍（PY_TABLE 沿用导出表）。
"""
import random, sys
from collections import deque

W = H = 16
MINES = 32
BASE = (1, 7)
ACTIONS_BUDGET = 75          # 5 免费 + 210s/3s ≈ 75 发（过载提高单发价值）
TARGET_RATIO = 0.93          # v1 口径 332→320
FLAGS_MIN = 12
SHATTER_MAX = 2
FLOOD_MIN = 5
OVERLOAD_PERIOD = 3          # 每 3 发可用 1 次过载射击（步速 2.2s+停留 3 拍的保守折算）
OVERLOAD_PRICE = 100
START_GOLD = 180
FIRST_BLAST_VALUE = 5.0      # 首爆教学位价值下限

# 预开区（恰 80 格，同 v1 减去节点/折光特判——本版无节点，区不变）
ZONE = ({(x, y) for x in range(0, 7) for y in range(3, 12)}
        | {(7, y) for y in range(4, 11)}
        | {(8, y) for y in range(6, 9)}
        | {(0, 2), (2, 2), (3, 2), (0, 12), (2, 12), (3, 12)}
        | {(8, 5)})

# 加固墙 42 格（同 v1：东带 3×5 为过载爆炸正面）
WALLS = ({(x, y) for x in range(9, 12) for y in range(5, 10)}   # A 东墙带 3x5=15（过载正面）
         | {(x, 2) for x in range(8, 12)}       # B 北横带 4
         | {(x, 12) for x in range(4, 10)}      # C 南横带 6
         | {(12, y) for y in range(3, 7)}       # D 东北竖带 4
         | {(11, 10), (11, 11), (12, 12)}       # E 东南簇 3
         | {(13, y) for y in range(6, 9)}       # F 远东竖带 3
         | {(2, y) for y in range(13, 16)}      # G 西南竖带 3
         | {(5, 13), (7, 13), (9, 13)}          # H 南散点 3
         | {(0, 0)})                            # I 角部 1

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


def blast_cells(c):
    """过载爆炸 13 格：3×3 + 四正各延伸 1（界内）"""
    out = set()
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            out.add((c[0] + dx, c[1] + dy))
    for d in ((2, 0), (-2, 0), (0, 2), (0, -2)):
        out.add((c[0] + d[0], c[1] + d[1]))
    return {c for c in out if c in ALL}


def beam_stop_at(base, t):
    """过载机器人是唯一截停物（本关无折光无矿石）：返回束格（过载工位由调用方传入判定）"""
    return [c for c in beam_cells(base, t) if c in ALL]


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


def cells_value(cells, opened, flagged, mines, hp):
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


def frontier_cells(opened):
    """预开前沿工位：已开格且八邻含未开格（过载巡逻偏好「低数字×靠墙」的模拟口径）"""
    return [c for c in opened
            if c != BASE and any(n not in opened for n in NB[c])]


def overload_shot_value(station, opened, flagged, mines, hp):
    """过载射击估值：束（基地→工位截停）+ 工位 13 格爆炸（去重后合并估值）"""
    beam = beam_stop_at(BASE, station)
    if station not in beam:
        # 工位不在基地任一直线上时用最近直线近似——前沿工位绝大多数可直射
        best = min(((len(set(beam_cells(BASE, t)) & {station}), t)
                    for t in ALL - {BASE}), key=lambda p: -p[0])
        beam = beam_stop_at(BASE, best[1])
    beam_set = set(beam)
    beam_set &= {c for c in beam_set
                 if opened and (c in opened or c in blast_cells(station))}
    # 束止于工位：截到工位格
    if station in beam:
        i = beam.index(station)
        beam_set = set(beam[: i + 1])
    else:
        beam_set = set(beam)
    all_cells = beam_set | blast_cells(station)
    return cells_value(all_cells, opened, flagged, mines, hp)


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
    overload_ready = True if START_GOLD >= OVERLOAD_PRICE else False  # 开局立购
    overload_cooldown = 0
    overload_shots = 0

    tf0, to0 = rule_targets(opened, flagged, mines, num)
    init_flags, init_targets = len(tf0), len(tf0 | to0)
    teach_a = 0
    for t in ALL - {BASE}:
        beam = beam_cells(BASE, t)
        if any(c in mines for c in beam):
            continue
        teach_a = max(teach_a, sum(
            1 for c in beam if c not in opened and hp[c] == 1))
    teach_b = 0
    for t in ALL:
        if t == BASE:
            continue
        peels = sum(1 for c in beam_cells(BASE, t)
                    if c not in opened and c not in flagged and hp[c] > 1)
        teach_b = max(teach_b, peels)

    # 首爆教学位 + 爆炸收益区（东墙带在多工位射程内）
    fr = frontier_cells(opened)
    first_blast_v = max((overload_shot_value(c, opened, flagged, mines, hp)
                         for c in fr), default=0.0)
    east_stations = sum(
        1 for c in fr
        if sum(1 for b in blast_cells(c) if b not in opened and hp[b] > 1) >= 2)
    blast_zone = east_stations >= 3

    while True:
        score, max_flood = robot_phase(opened, flagged, mines, num, hp, score, max_flood)
        if actions <= 0:
            break
        best_t, best_v = None, 0.0
        for t in ALL:
            if t == BASE:
                continue
            v = cells_value(beam_stop_at(BASE, t), opened, flagged, mines, hp)
            if v > best_v:
                best_v, best_t = v, t
        if overload_ready:
            for c in frontier_cells(opened):
                v = overload_shot_value(c, opened, flagged, mines, hp)
                if v > best_v:
                    best_v, best_t = v, ["OVERLOAD", c]
        if best_t is None:
            break
        if isinstance(best_t, list):
            _, station = best_t
            beam = beam_stop_at(BASE, station)
            i = beam.index(station) if station in beam else len(beam) - 1
            cells = list(beam[: i + 1]) + [c for c in blast_cells(station)
                                           if c not in beam[: i + 1]]
            overload_shots += 1
            overload_ready = False
            overload_cooldown = OVERLOAD_PERIOD
        else:
            cells = beam_stop_at(BASE, best_t)
        for c in cells:
            if c in flagged or c in opened:
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
        if not overload_ready:
            overload_cooldown -= 1
            if overload_cooldown <= 0:
                overload_ready = True
    score, max_flood = robot_phase(opened, flagged, mines, num, hp, score, max_flood)

    spawn_times = [12 + 25 * k for k in range(10) if 12 + 25 * k < 210 - 10]
    kills_affordable = min(len(spawn_times), ACTIONS_BUDGET // 2)
    kill_score = 10 * kills_affordable
    cover_score = kills_affordable
    total = score + kill_score + cover_score

    return dict(seed=seed, mines=mines, score=score, total=total,
                dynamic=kill_score + cover_score, kills=kills_affordable,
                overload_shots=overload_shots, first_blast_v=first_blast_v,
                blast_zone=blast_zone,
                flags=len(flagged), shatters=shatters, max_flood=max_flood,
                init_flags=init_flags, init_targets=init_targets,
                teach_a=teach_a, teach_b=teach_b)


def checks(r, target):
    return {
        "total_ge_target": r["total"] >= target,
        "static_ge240": r["score"] >= 240,
        "flags_ge12": r["flags"] >= FLAGS_MIN,
        "shatter_le2": r["shatters"] <= SHATTER_MAX,
        "flood_ge5": r["max_flood"] >= FLOOD_MIN,
        "init_flags_ge1": r["init_flags"] >= 1,
        "init_targets_ge2": r["init_targets"] >= 2,
        "teach_line_a": r["teach_a"] >= 3,
        "teach_line_b": r["teach_b"] >= 2,
        "first_blast": r["first_blast_v"] >= FIRST_BLAST_VALUE,
        "blast_zone": r["blast_zone"],
        "overload_used": r["overload_shots"] >= 5,
    }


def gdscript_snippet(r):
    ms = ", ".join(f"Vector2i({m[0]}, {m[1]})" for m in sorted(r["mines"]))
    ps = ", ".join(f"Vector2i({c[0]}, {c[1]})" for c in sorted(ZONE))
    ws = ", ".join(f"Vector2i({c[0]}, {c[1]})" for c in sorted(WALLS))
    return ("const CH2_S4 := {\n"
            f'\t"mines": [{ms}],\n'
            f'\t"preopen": [{ps}],\n'
            f'\t"base": Vector2i({BASE[0]}, {BASE[1]}),\n'
            f'\t"walls": [{ws}],\n'
            "}")


assert len(ZONE) == 80, f"预开区 {len(ZONE)} 格 ≠ 80"
assert BASE in ZONE
assert not (WALLS & ZONE), "加固墙与预开区重叠"
assert len(WALLS) == 42, f"加固墙 {len(WALLS)} 格 ≠ 42"

MAX_SEED = 3000
MAX_PASS = 60
PRE_TARGET = 325
passes = []
stats = {"pass": 0}
for seed in range(1, MAX_SEED + 1):
    r = simulate(seed)
    if all(checks(r, PRE_TARGET).values()):
        stats["pass"] += 1
        r["target"] = int(round(r["total"] * TARGET_RATIO / 5.0) * 5)
        r["cost"] = abs(r["score"] - 320) / 5.0 \
            + (0.0 if r["shatters"] == 0 else 4.0) \
            + (0.0 if 14 <= r["flags"] <= 26 else 3.0)
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
