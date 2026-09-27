# -*- coding: utf-8 -*-
"""首关盘面搜索器 v3：对齐设计文档 §7 验收标准
条件（全部满足才算 pass）：
  1. 全程 2 条基础规则可解（不猜、不停摆）
  2. 开局可推旗数 ∈ [5,7]（"恰好5面左右"），每面由单个数字即可判定（构造保证）
  3. 预开（含洪水）∈ [45,55] 格
  4. 放好 5 面旗后存在规则 1 可开格（免费阶段有开格可做）
  5. 免费阶段之后（机器人+收尾统称后段）至少一次 ≥6 格连锁
  6. 最后一次开格动作的目标格距基地 ≥3 格（切比雪夫距离）
  7. 免费阶段收入 + 起始资金 75 ≥ 100（恰好够买 opener+marker）
"""
import random, sys

W = H = 10
MINES = 10
ZONE = 2  # 预开 5x5
START_GOLD = 75
TWO_ROBOTS = 100

NB = {}
for x in range(W):
    for y in range(H):
        NB[(x, y)] = [(x+dx, y+dy) for dx in (-1,0,1) for dy in (-1,0,1)
                      if (dx or dy) and 0 <= x+dx < W and 0 <= y+dy < H]

def gen(seed, base):
    rnd = random.Random(seed)
    zone = {(x, y) for x in range(base[0]-ZONE, base[0]+ZONE+1)
                    for y in range(base[1]-ZONE, base[1]+ZONE+1)
            if 0 <= x < W and 0 <= y < H}
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

def simulate(seed, base):
    zone, mines, num = gen(seed, base)
    # 关卡开局预开：5x5 区域 + 从区域内 0 数字格向外洪水
    opened = set(zone)
    for c in zone:
        if num[c] == 0:
            for n in NB[c]:
                flood(opened, n, mines, num)
    preopen = len(opened)

    # 开局即可推旗：单数字判定（未开邻格数 == 数字 → 全是雷）
    init_fl = set()
    for c in opened:
        k = num[c]
        if k:
            un = [n for n in NB[c] if n not in opened]
            if len(un) == k:
                init_fl.update(un)

    # ---- 免费阶段：放 5 面正确旗 + 最多 3 次开格（8 次点击兜底内）----
    flagged = set()
    free_money = 0
    for m in sorted(init_fl)[:5]:
        flagged.add(m); free_money += 5
    _, opens1 = rule_targets(opened, flagged, mines, num)
    early_floods = []
    for t in sorted(opens1)[:3]:
        k = flood(opened, t, mines, num)
        free_money += k
        early_floods.append(k)

    # ---- 后段（机器人 + 玩家收尾）----
    robot_max_flood = 0
    robot_flags = 0
    robot_opens = 0
    order_opened = []
    total_safe = W*H - MINES
    while len(opened) < total_safe or len(flagged) < MINES:
        tf, to = rule_targets(opened, flagged, mines, num)
        if tf:
            m = min(tf); flagged.add(m); robot_flags += 1
        elif to:
            t = min(to)
            k = flood(opened, t, mines, num)
            robot_max_flood = max(robot_max_flood, k)
            order_opened.append(t); robot_opens += 1
        else:
            return None  # 2 条规则推不动 → 弃
    tail_dist = max(max(abs(t[0]-base[0]), abs(t[1]-base[1])) for t in order_opened[-3:]) if order_opened else 0
    final_dist = max(abs(order_opened[-1][0]-base[0]), abs(order_opened[-1][1]-base[1])) if order_opened else 0
    return dict(seed=seed, base=base, mines=mines, num=num, preopen=preopen,
                init_fl=init_fl, free_money=free_money, early_floods=early_floods,
                robot_max_flood=robot_max_flood, robot_flags=robot_flags,
                robot_opens=robot_opens, tail=order_opened[-3:],
                tail_dist=tail_dist, final_dist=final_dist)

def checks(r):
    """返回 (通过与否, 各条件明细)"""
    return {
        "solvable": True,  # simulate 返回非 None 即可解
        "flags_5ish": 5 <= len(r["init_fl"]) <= 7,
        "preopen_45_55": 45 <= r["preopen"] <= 55,
        "opens_after_flags": sum(r["early_floods"]) > 0 or len(r["early_floods"]) > 0,
        "robot_flood_6": r["robot_max_flood"] >= 6,
        "final_dist_3": r["final_dist"] >= 3,
        "money_ok": START_GOLD + r["free_money"] >= TWO_ROBOTS,
    }

def gdscript_snippet(r):
    zone, mines, num = gen(r["seed"], r["base"])
    opened = set(zone)
    for c in zone:
        if num[c] == 0:
            for n in NB[c]:
                flood(opened, n, mines, num)
    ms = ", ".join(f"Vector2i({m[0]}, {m[1]})" for m in sorted(r["mines"]))
    ps = ", ".join(f"Vector2i({c[0]}, {c[1]})" for c in sorted(opened))
    return (f'const L1 := {{\n'
            f'\t"mines": [{ms}],\n'
            f'\t"preopen": [{ps}],\n'
            f'\t"base": Vector2i({r["base"][0]}, {r["base"][1]}),\n'
            f'}}')

bases = [(3,3),(4,4),(5,5),(4,5),(5,4)]
stats = {"solved":0,"pass":0}
found = None
for seed in range(1, 30001):
    for base in bases:
        r = simulate(seed, base)
        if r is None:
            continue
        stats["solved"] += 1
        c = checks(r)
        if all(c.values()):
            stats["pass"] += 1
            if found is None:
                found = r
    if seed % 3000 == 0:
        print(f"seed {seed}: {stats}", flush=True)
    if found:
        break

if not found:
    print("NO PASS", stats); sys.exit(1)

r = found
c = checks(r)
print(f"\n=== seed {r['seed']} base={r['base']} ===")
print(f"预开 {r['preopen']} 格 | 开局可推旗 {len(r['init_fl'])} | 免费阶段收入 {r['free_money']}（75+{r['free_money']}={75+r['free_money']}）")
print(f"免费早连锁 {r['early_floods']} | 后段最大连锁 {r['robot_max_flood']} | 后段动作 标{r['robot_flags']}+开{r['robot_opens']} | 收尾距离 {r['final_dist']}")
print("验收:", " ".join(f"{k}={'PASS' if v else 'FAIL'}" for k, v in c.items()))
print("统计:", stats)
zone, mines, num = gen(r["seed"], r["base"])
opened = set(zone)
for cc0 in zone:
    if num[cc0] == 0:
        for n in NB[cc0]:
            flood(opened, n, mines, num)
print("\n   0 1 2 3 4 5 6 7 8 9")
for y in range(H):
    row = []
    for x in range(W):
        cc = (x, y)
        if cc == r["base"]: row.append("B")
        elif cc in r["mines"]: row.append("x" if cc in r["init_fl"] else "X")
        elif cc in opened: row.append(str(num[cc]) if num[cc] else ".")
        else: row.append("#")
    print(f"{y}  " + " ".join(row))
print("x/X=雷(小写=开局即可推) #=未开 B=基地 .=已开空 数字=已开数字格")
print("\n---- GDScript ----")
print(gdscript_snippet(r))
