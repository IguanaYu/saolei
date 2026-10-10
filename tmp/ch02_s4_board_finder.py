# -*- coding: utf-8 -*-
"""第二章 2-4「连爆节点」盘面搜索器：只搜雷位；预开/加固墙/节点两组/折光驻点手工布置

对齐 docs/active/玩法设计/第二章-激光矿场/2-4-连爆节点-设计文档.md §4 六断言：
  1. 第一组 3 座相邻节点（中心互在八邻）、基地可直射首发、周围以可确认安全的
     1 层普通墙为主（A 组爆炸盒内未开格全非雷且 hp=1——看清连爆顺序，教学爆炸零碎钻）
  2. 第二组近未开工作面、数字可推出需保护的钻石（B 组爆炸盒内未开格 ≥2 雷：
     先标记再引爆有真实取舍）
  3. 两组间不可一链贯通（几何 cheb ≥2 + 链展开模拟：只引 A 组永远烧不到 B 组）
  4. 至少一组邻近敌施工地面（B 组爆炸盒内 ≥3 个邻接未开格的已开边格）
  5. 节点全在预开安全格、不泄露未开格内容（布局常量断言；雷位只在未开格采样）
  6. 静态 304 < 320：≥16 分动态可得性验算（双规则+激光+连爆+筑墙工经济 ≥325）

墙层语义（总纲 §5.2）：未开格 hp=1 默认、加固 hp=3；开 hp=1 格=破墙即开；
零连开停在 hp>1 前；激光/机器人削层不开格。
连爆语义（总纲 §6.3）：束格命中未消耗节点→入队；队首 3×3 并入总命中集（同轮同格
至多一次）；范围内新节点续入队——节点一次性消耗。beam_cells 与 GDScript
LaserGeometry 逐 case 对拍（PY_TABLE 沿用 tmp/test_laser_geometry.gd 导出表）。
"""
import random, sys

W = H = 16
MINES = 32
BASE = (1, 7)
ACTIONS_BUDGET = 75          # 5 免费 + 210s/3s ≈ 75 发（连爆提高单发价值）
SCORE_TARGET = 325           # 320 目标 + 5 容错
FLAGS_MIN = 12
SHATTER_MAX = 2
FLOOD_MIN = 5

# 预开区（恰 80 格，含基地 (1,7) 与节点/折光驻点）：
# x∈[0,6]×y∈[3,11]=63 ∪ x=7,y∈[4,10]=7 ∪ x=8,y∈[6,8]=3 ∪ 沿口 6 ∪ (8,5)
ZONE = ({(x, y) for x in range(0, 7) for y in range(3, 12)}
        | {(7, y) for y in range(4, 11)}
        | {(8, y) for y in range(6, 9)}
        | {(0, 2), (2, 2), (3, 2), (0, 12), (2, 12), (3, 12)}
        | {(8, 5)})

# 连爆节点 6 座两组：A=教学组（基地直射可达、互八邻、周围普通墙）；
# B=工作面组（东缘未开面前、爆炸盒含雷、近施工地面）
NODES_A = {(5, 3), (6, 3), (6, 4)}
NODES_B = {(8, 6), (8, 8), (7, 10)}
NODES = NODES_A | NODES_B

# 折光预设驻点（预开区内、基地正东；宽束走廊可同时点燃 B 组两座）
REFRACTOR = (7, 7)

# 加固墙 42 格（与雷位独立布置——外壳不从钻石真值决定，总纲 §4.4）
WALLS = ({(x, y) for x in range(9, 12) for y in range(5, 10)}  # A 东墙带 3x5=15（B 组正面）
         | {(x, 2) for x in range(8, 12)}       # B 北横带 4（避开 A 教学爆炸盒）
         | {(x, 12) for x in range(4, 10)}      # C 南横带 6
         | {(12, y) for y in range(3, 7)}       # D 东北竖带 4
         | {(11, 10), (11, 11), (12, 12)}       # E 东南簇 3
         | {(13, y) for y in range(6, 9)}       # F 远东竖带 3
         | {(2, y) for y in range(13, 16)}      # G 西南竖带 3
         | {(5, 13), (7, 13), (9, 13)}          # H 南散点 3
         | {(0, 0)})                            # I 角部 1

# A 组教学爆炸盒（3×3 并集）内的未开格：全非雷且 hp=1（断言 1 的"可确认安全普通墙"）
def _blast_box(nodes):
    box = set()
    for (x, y) in nodes:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                c = (x + dx, y + dy)
                if 0 <= c[0] < W and 0 <= c[1] < H:
                    box.add(c)
    return box


A_BOX = _blast_box(NODES_A)
A_BOX_UNOPENED = A_BOX - ZONE
B_BOX = _blast_box(NODES_B)
B_BOX_UNOPENED = B_BOX - ZONE

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


def octant_dir(f, t):
    dx, dy = t[0] - f[0], t[1] - f[1]
    if dx == 0 and dy == 0:
        return (0, 0)
    sx, sy = (1 if dx > 0 else -1), (1 if dy > 0 else -1)
    ax, ay = abs(dx), abs(dy)
    if ay * 10000 <= ax * 4142:
        return (sx, 0)
    if ax * 10000 <= ay * 4142:
        return (0, sy)
    return (sx, sy)


def expand_chain(cells, consumed_nodes):
    """束格（主+副）→ 连爆链 BFS（与 GDScript compute_shot_geometry 同口径）：
    命中未消耗节点入队；队首 3×3 并入 cells（去重）；范围内新节点续入队。
    就地更新 consumed_nodes（节点一次性）；返回 (cells, 本轮触发节点)。"""
    queue = [n for n in NODES - consumed_nodes if n in cells]
    triggered = set(queue)
    order = []
    while queue:
        n = queue.pop(0)
        order.append(n)
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                b = (n[0] + dx, n[1] + dy)
                if b not in ALL:
                    continue
                if b not in cells:
                    cells.append(b)
                if b in NODES and b not in consumed_nodes and b not in triggered:
                    triggered.add(b)
                    queue.append(b)
    consumed_nodes.update(triggered)
    return cells, order


def shot_cells(base, t, consumed_nodes):
    """含折光接管 + 连爆链的完整命中集（束格与爆炸格合并成一个总命中集）"""
    beam = beam_cells(base, t)
    if REFRACTOR in beam and REFRACTOR not in consumed_nodes:
        i = beam.index(REFRACTOR)
        beam = beam[: i + 1]
        prev = beam[i - 1] if i >= 1 else base
        dir8 = octant_dir(prev, REFRACTOR)
        perp = (-dir8[1], dir8[0])
        for off in [(0, 0), perp, tuple(-x for x in perp)]:
            start = (REFRACTOR[0] + off[0], REFRACTOR[1] + off[1])
            line = beam_cells(start, (start[0] + dir8[0] * 6, start[1] + dir8[1] * 6))
            for c in line:
                if c not in beam:
                    beam.append(c)
    cells = [c for c in beam if c in ALL]
    return expand_chain(cells, consumed_nodes)


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


def beam_value(t, opened, flagged, mines, hp, consumed_nodes):
    """谨慎玩家的一发估值：开格 +1 / 削层 +0.3 / 误打钻石 -4（含折光接管与连爆链）；
    节点一次性——估值用副本消耗，不污染真实局"""
    cn = set(consumed_nodes)
    cells, _ = shot_cells(BASE, t, cn)
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
    consumed_nodes = set()

    tf0, to0 = rule_targets(opened, flagged, mines, num)
    init_flags, init_targets = len(tf0), len(tf0 | to0)

    # 断言 1：A 组爆炸盒内未开格全非雷（教学爆炸零碎钻、全 1 层普通墙由布局保证）
    a_box_clean = all(c not in mines for c in A_BOX_UNOPENED)
    # 断言 1：基地直射可达 A 组（布局保证，这里防御性复核）
    base_hits_a = any(beam_cells(BASE, t) and (NODES_A & set(beam_cells(BASE, t)))
                      for t in (ALL - {BASE}))
    # 断言 2：B 组爆炸盒内未开格 ≥2 雷（先标记再引爆的真实取舍）
    b_mines = sum(1 for c in B_BOX_UNOPENED if c in mines)
    # 断言 3：两组一链不贯通——只从 A 组展开，B 组节点不被消耗（几何 cheb≥2 布局保证+模拟复核）
    _cells, order_a = expand_chain(sorted(NODES_A), set())
    chain_sep = not (set(order_a) & NODES_B)

    # 教学线B：一枪 ≥2 块 3 层墙（东墙带直射/宽束走廊/连爆盒任一路径）
    teach_b = 0
    for t in ALL:
        if t == BASE:
            continue
        cn = set()
        cells, _ = shot_cells(BASE, t, cn)
        peels = sum(1 for c in cells if c not in opened and c not in flagged and hp[c] > 1)
        teach_b = max(teach_b, peels)

    # 主模拟：机器人免费 + 激光按预算（连爆节点随射击真实消耗）
    while True:
        score, max_flood = robot_phase(opened, flagged, mines, num, hp, score, max_flood)
        if actions <= 0:
            break
        best_t, best_v = None, 0.0
        for t in ALL:
            if t == BASE:
                continue
            v = beam_value(t, opened, flagged, mines, hp, consumed_nodes)
            if v > best_v:
                best_v, best_t = v, t
        if best_t is None:
            break
        cells, _order = shot_cells(BASE, best_t, consumed_nodes)
        for c in cells:
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
    score, max_flood = robot_phase(opened, flagged, mines, num, hp, score, max_flood)

    # 动态分（筑墙工经济，容量口径总纲 §8.3）：210s 内 12s 首出+25s 间隔；
    # 及时击杀路线每只 2 枪，击杀 +10；被杀前约造 1 块墙（拆 +1）
    spawn_times = [12 + 25 * k for k in range(10) if 12 + 25 * k < 210 - 10]
    actions_left = actions
    kills_affordable = min(len(spawn_times), actions_left // 2)
    kill_score = 10 * kills_affordable
    cover_score = kills_affordable
    total = score + kill_score + cover_score

    return dict(seed=seed, mines=mines, num=num, score=score, total=total,
                dynamic=kill_score + cover_score, kills=kills_affordable,
                a_box_clean=a_box_clean, base_hits_a=base_hits_a,
                b_mines=b_mines, chain_sep=chain_sep,
                nodes_left=len(NODES - consumed_nodes),
                flags=len(flagged),
                shatters=shatters, max_flood=max_flood, init_flags=init_flags,
                init_targets=init_targets, teach_b=teach_b,
                actions_used=ACTIONS_BUDGET - actions)


def checks(r):
    return {
        "total_ge325": r["total"] >= SCORE_TARGET,
        "static_ge240": r["score"] >= 240,  # 静态下限：动态只补 ≤85 分容错带
        "flags_ge12": r["flags"] >= FLAGS_MIN,
        "shatter_le2": r["shatters"] <= SHATTER_MAX,
        "flood_ge5": r["max_flood"] >= FLOOD_MIN,
        "init_flags_ge1": r["init_flags"] >= 1,
        "init_targets_ge2": r["init_targets"] >= 2,
        "teach_b_peels2": r["teach_b"] >= 2,
        "a_box_clean": r["a_box_clean"],
        "base_hits_a": r["base_hits_a"],
        "b_mines_ge2": r["b_mines"] >= 2,
        "chain_separated": r["chain_sep"],
    }


def gdscript_snippet(r):
    ms = ", ".join(f"Vector2i({m[0]}, {m[1]})" for m in sorted(r["mines"]))
    ps = ", ".join(f"Vector2i({c[0]}, {c[1]})" for c in sorted(ZONE))
    ws = ", ".join(f"Vector2i({c[0]}, {c[1]})" for c in sorted(WALLS))
    ns = ", ".join(f"Vector2i({c[0]}, {c[1]})" for c in sorted(NODES))
    return ("const CH2_S4 := {\n"
            f'\t"mines": [{ms}],\n'
            f'\t"preopen": [{ps}],\n'
            f'\t"base": Vector2i({BASE[0]}, {BASE[1]}),\n'
            f'\t"walls": [{ws}],\n'
            f'\t"refractor": Vector2i({REFRACTOR[0]}, {REFRACTOR[1]}),\n'
            f'\t"nodes": [{ns}],\n'
            "}")


# ---- 布局常量断言（断言 5：节点全在预开安全格；基础合法性）----
assert len(ZONE) == 80, f"预开区 {len(ZONE)} 格 ≠ 80"
assert BASE in ZONE
assert NODES <= ZONE, "节点必须在预开安全格上"
assert REFRACTOR in ZONE and REFRACTOR not in NODES and REFRACTOR != BASE
assert not (WALLS & ZONE), "加固墙与预开区重叠"
assert not (WALLS & NODES)
assert len(WALLS) == 42, f"加固墙 {len(WALLS)} 格 ≠ 42"
assert len(NODES) == 6
# 断言 1：A 组互在八邻（连通簇）
for a in NODES_A:
    assert any(max(abs(a[0]-b[0]), abs(a[1]-b[1])) == 1 for b in NODES_A if b != a), "A 组不互邻"
# 断言 3：两组 cheb ≥2（任何 A 节点不在任何 B 节点的 3×3 内）
for a in NODES_A:
    for b in NODES_B:
        assert max(abs(a[0]-b[0]), abs(a[1]-b[1])) >= 2, "A/B 组太近会一链贯通"
# 断言 4：B 组爆炸盒内 ≥3 个邻接未开格的已开边格（施工地面）
b_edge = sum(1 for c in (B_BOX & ZONE)
             if any(n not in ZONE for n in NB[c]))
assert b_edge >= 3, f"B 组近施工地面不足（{b_edge}）"
print(f"布局常量断言 OK：预开80 墙42 节点6 B边格{b_edge}")

MAX_SEED = 3000
MAX_PASS = 60
passes = []
stats = {"pass": 0}
for seed in range(1, MAX_SEED + 1):
    r = simulate(seed)
    if all(checks(r).values()):
        stats["pass"] += 1
        # 中庸度：总分贴近 330（有挑战不满溢）、碎钻 0 最好、旗 12-18
        r["cost"] = abs(r["total"] - 332) / 6.0 \
            + (0.0 if r["shatters"] == 0 else 4.0) \
            + (0.0 if 12 <= r["flags"] <= 18 else 3.0)
        passes.append(r)
    if seed % 100 == 0:
        print(f"seed {seed}: pass={stats['pass']}", flush=True)
    if len(passes) >= MAX_PASS:
        break

if not passes:
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
