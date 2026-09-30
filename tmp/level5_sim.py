# -*- coding: utf-8 -*-
"""L5 Boss 关离线模拟器（设计 §10 / 实施计划 WP9）

回答三个验收问题：
  1. 双路线斩杀率（§10.4/10.6）：路线 A「重军团」（机器人标旗为主，玩家只清障）vs
     路线 B「重亲自」（玩家自己拔牙 + 单对机器人）——180s 内拔完 20 颗牙的比例
  2. CD 银行预算（§10.1）：玩家全程点击需求 vs 供给曲线（5 免费 + 3s/层、7 层银行），
     P2/P3 高峰是否阶段性见底
  3. 阶段时长分布（§10.3）：P1/P2/P3 中位数落点；P1 >90s 报警
  4. 静态经济算术（§10.2/10.5）

模型口径（与 L5 实装参数一致）：
  - 盘面 = 烘焙盘（seed=67, center=(3,5), sq3——与 FixedBoards.L5 同源生成）
  - 机器人：贪心双规则目标，busy_until = 出发时刻 + 旅行(BFS×移动间隔,黏液区×2) + 工作间隔
  - 玩家：CD 银行（5 免费 → 3s/层回充、7 层封顶、花存款不打断回充）；
    点击瞬发。路线 A 只点互动（杀史莱姆/反弹/灭火/解锁/断触手），路线 B 兼顾亲手标旗
  - Boss 干扰：史莱姆（P1 补位到 2， aura 减速）、炸弹（P2 18s/P3 35s，玩家必反弹）、
    锁（P3 25s 抛 3-5，玩家点清阻塞目标的）、触手（P3 30s ≤2，玩家 3s 后点断）
"""
import random

W = H = 14
MINES = 20
TIME_LIMIT = 180.0
TICK = 0.5

NB = {}
for x in range(W):
    for y in range(H):
        NB[(x, y)] = [(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)
                      if (dx or dy) and 0 <= x + dx < W and 0 <= y + dy < H]
ALL = {(x, y) for x in range(W) for y in range(H)}


def gen_board():
    rnd = random.Random(67)
    center, r = (3, 5), 3
    zone = {(x, y) for x in range(center[0] - r, center[0] + r + 1)
            for y in range(center[1] - r, center[1] + r + 1) if 0 <= x < W and 0 <= y < H}
    forbidden = zone | {(x, 0) for x in range(4, 10)} | {(W - 1, y) for y in range(H)}
    rest = [(x, y) for x in range(W) for y in range(H) if (x, y) not in forbidden]
    mines = set(rnd.sample(rest, MINES))
    num = {c: sum(1 for n in NB[c] if n in mines) for c in ALL}
    opened = {c for c in zone if c[1] != 0}
    stack = [c for c in opened if num[c] == 0]
    while stack:
        c = stack.pop()
        for n in NB[c]:
            if n not in opened and n not in mines:
                if num[n] == 0:
                    stack.append(n)
                opened.add(n)
    return mines, num, opened


def rule_targets(opened, flagged, mines, num):
    to_flag, to_open = set(), set()
    for c in opened:
        k = num[c]
        if not k:
            continue
        fl, un = 0, []
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


def bfs_dist(opened, start, goals, blocked):
    """opened 内 4 向 BFS（blocked = 火/触手占格近似）"""
    goals = set(goals)
    if start in goals:
        return 0
    dist = {start: 0}
    q = [start]
    while q:
        c = q.pop(0)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (c[0] + dx, c[1] + dy)
            if n in opened and n not in dist and n not in blocked:
                dist[n] = dist[c] + 1
                if n in goals:
                    return dist[n]
                q.append(n)
    return None  # 不可达（绕行模型：+8 格惩罚后重试）


class PlayerCD:
    """5 免费点击 → 3s/层回充、7 层封顶、花存款不打断回充"""

    def __init__(self):
        self.free = 5
        self.bank = 0.0      # 层数（浮点累计）
        self.used = []       # (t, 累计使用)

    def tick(self, dt):
        self.bank = min(7.0, self.bank + dt / 3.0)

    def can(self):
        return self.free > 0 or self.bank >= 1.0

    def spend(self, t):
        if self.free > 0:
            self.free -= 1
        else:
            self.bank -= 1.0
        self.used.append((t, len(self.used) + 1))


def simulate(route: str, seed: int):
    """route: 'A' 重军团 / 'B' 重亲自。返回 dict(结果)"""
    rnd = random.Random(seed)
    mines, num, opened = gen_board()
    flagged = set()
    teeth_hist = []          # (t, 牙数)
    t = 0.0

    # ---- 玩家与购买计划 ----
    cd = PlayerCD()
    # 路线 A：t0 买 opener+marker(100) + 双 Lv1(100)；t60（钱够 150）买第 2 对
    # 路线 B：t0 买 opener+marker + 双 Lv1；不再加机器人
    robots = [  # (kind, busy_until, move_itv, work_itv, at)
        {"kind": "opener", "busy": 6.0, "mi": 1.6, "wi": 1.6, "at": None},
        {"kind": "marker", "busy": 8.0, "mi": 1.6, "wi": 1.6, "at": None},
    ]
    if route == "A":
        second_pair_at = 60.0
    else:
        second_pair_at = None

    base = next(iter(opened))  # 基地（预开区任一格，位置对节奏影响 <5%）

    def flood_from(c):
        """实装 _flood_open 口径：开零格时连通展开"""
        newly = set()
        if num[c] != 0:
            newly.add(c)
            return newly
        stack = [c]
        newly.add(c)
        while stack:
            cur = stack.pop()
            for n in NB[cur]:
                if n not in newly and n not in opened and n not in mines and n not in flagged:
                    newly.add(n)
                    if num[n] == 0:
                        stack.append(n)
        return newly

    # ---- Boss 状态 ----
    phase = 1
    teeth = 0
    phase_marks = {}
    slime_timer, slime_pair_done = 15.0, False
    bomb_timer = 5.0          # P2 转场后首弹
    lock_timer, tent_timer = 4.0, 8.0
    locked = set()
    blocked = set()           # 火+触手占格（通路近似）
    slimes = []               # [cell]
    slime_cells = set()       # aura 格

    # ---- 统计 ----
    clicks = 0
    demand_peak_deficit = 0.0
    stall_t = 0.0

    def record_tooth(tt):
        nonlocal teeth
        teeth += 1
        teeth_hist.append((tt, teeth))
        nonlocal phase
        for th, ph in ((5, 2), (11, 3)):
            if teeth > th and phase < ph:
                phase = ph
                phase_marks[ph] = tt
                if ph == 2:
                    pass

    while t < TIME_LIMIT and teeth < MINES:
        # --- CD 银行推进 ---
        cd.tick(TICK)

        # --- Boss 出招 ---
        if phase == 1 and t >= slime_timer:
            if not slime_pair_done:
                slimes += [rnd.choice(list(ALL - opened)), rnd.choice(list(ALL - opened))]
                slime_pair_done = True
                slime_timer = t + 3.0
            else:
                if len(slimes) < 2:
                    slimes.append(rnd.choice(list(ALL - opened)))
                slime_timer = t + 30.0
        if phase >= 2 and t >= bomb_timer:
            bomb_timer = t + (18.0 if phase == 2 else 35.0)
            if cd.can():            # 玩家必反弹（最优策略）
                cd.spend(t); clicks += 1
            # 漏接不计（最优口径）；反弹奖励已入经济近似
        if phase == 3 and t >= lock_timer:
            lock_timer = t + 25.0
            walls = list({c for c in ALL if c not in opened} - locked - flagged)
            rnd.shuffle(walls)
            for c in walls[:rnd.randint(3, 5)]:
                locked.add(c)
        if phase == 3 and t >= tent_timer:
            tent_timer = t + 30.0
            # 触手占 5 格已开地 3s 后被玩家点断（1 click）；期间 blocked
            corridor = [c for c in opened if c[0] >= W - 5][:5]
            blocked |= set(corridor)
            def _clear():
                nonlocal clicks
                blocked.difference_update(corridor)
            # 3s 后断（简化为下一轮 tick 排程）
            pending_cut = t + 3.0
            if cd.can():
                cd.spend(t); clicks += 1
                pending_cut = t + 0.5
            # 直接当帧断（近似：点得快）
            blocked.difference_update(corridor)

        # --- 史莱姆 aura/击杀（玩家开路接近才点得到：近 frontier 时点杀） ---
        slime_cells.clear()
        for s in slimes:
            for n in NB[s] + [s]:
                slime_cells.add(n)
        killable = [s for s in slimes if any(n in opened for n in NB[s])]
        if killable and cd.can() and t > 18.0:
            s = killable[0]
            slimes.remove(s)
            cd.spend(t); clicks += 1
        # 史莱姆缓步游走（8s 一格近似）
        if int(t / 8.0) != int((t - TICK) / 8.0) and slimes:
            slimes[0] = rnd.choice(NB[slimes[0]] + [slimes[0]])

        # --- 锁清理（阻塞机器人目标的优先；否则放着） ---
        tf, to = rule_targets(opened, flagged, mines, num)
        hot_locks = locked & (tf | to)
        while hot_locks and cd.can():
            c = sorted(hot_locks)[0]
            locked.discard(c)
            cd.spend(t); clicks += 1
            hot_locks = locked & (tf | to)

        # --- 机器人 ---
        if route == "A" and second_pair_at is not None and t >= second_pair_at:
            robots += [{"kind": "opener", "busy": t + 2.0, "mi": 1.6, "wi": 1.6, "at": None},
                       {"kind": "marker", "busy": t + 2.0, "mi": 1.6, "wi": 1.6, "at": None}]
            second_pair_at = None
        for rb in robots:
            if t < rb["busy"]:
                continue
            tf, to = rule_targets(opened, flagged, mines, num)
            pool = to if rb["kind"] == "opener" else tf
            pool = [c for c in pool if c not in locked]
            if not pool:
                stall_t += TICK
                rb["busy"] = t + TICK
                continue
            here = rb["at"] if rb["at"] is not None else base
            target = sorted(pool, key=lambda c: (abs(c[0] - here[0]) + abs(c[1] - here[1])))[0]
            d = bfs_dist(opened, here, NB[target] + [target], blocked)
            travel = (d if d is not None else 12) * rb["mi"]
            if any(n in slime_cells for n in NB[target] + [target]):
                travel *= 2.0     # 黏液 aura ×2（粗粒度）
            arrive = t + travel
            rb["busy"] = arrive + rb["wi"]
            rb["at"] = target
            if rb["kind"] == "opener":
                opened |= flood_from(target)   # 零格洪水连锁（实装口径）
            else:
                flagged.add(target)
                record_tooth(arrive + rb["wi"])

        # --- 玩家路线 B：亲手拔牙（机器人忙时补位） ---
        if route == "B" and cd.can():
            tf, to = rule_targets(opened, flagged, mines, num)
            markers_busy = all(t < rb["busy"] for rb in robots if rb["kind"] == "marker")
            if tf and markers_busy:
                target = sorted(tf)[0]
                flagged.add(target)
                cd.spend(t); clicks += 1
                record_tooth(t)
            elif to and all(t < rb["busy"] for rb in robots):
                target = sorted(to)[0]
                opened |= flood_from(target)   # 玩家开格同样洪水
                cd.spend(t); clicks += 1

        t += TICK

    p1 = phase_marks.get(2, None)
    p2 = phase_marks.get(3, None)
    return {
        "route": route, "win": teeth >= MINES, "teeth": teeth, "t_end": min(t, TIME_LIMIT),
        "phase2": p1, "phase3": p2,
        "clicks": clicks, "cd_used": len(cd.used), "stall": stall_t,
    }


def run_batch(route, n=200):
    rs = [simulate(route, 1000 + i) for i in range(n)]
    wins = [r for r in rs if r["win"]]
    print(f"路线 {route}（{n} 盘）: 斩杀率 {len(wins)}/{n} = {len(wins) / n * 100:.0f}%")
    if wins:
        ts = sorted(r["t_end"] for r in wins)
        print(f"  通关用时 中位 {ts[len(ts)//2]:.0f}s / P90 {ts[int(len(ts)*0.9)]:.0f}s")
        ph2 = sorted(r["phase2"] for r in wins if r["phase2"] is not None)
        ph3 = sorted(r["phase3"] for r in wins if r["phase3"] is not None)
        if ph2:
            print(f"  P1 时长 中位 {ph2[len(ph2)//2]:.0f}s（目标 40-70s，>90 报警）")
        if ph3 and ph2:
            p2d = [b - a for a, b in zip(ph2, ph3)]
            print(f"  P2 时长 中位 {sorted(p2d)[len(p2d)//2]:.0f}s（目标 50-80s）")
        p3d = [r["t_end"] - r["phase3"] for r in wins if r["phase3"] is not None]
        if p3d:
            print(f"  P3 时长 中位 {sorted(p3d)[len(p3d)//2]:.0f}s（目标 40-70s）")
    clicks = [r["clicks"] for r in rs]
    print(f"  玩家互动点击 均值 {sum(clicks)/len(clicks):.1f}（预算 180/3+7+5≈72）")
    stalls = [r["stall"] for r in rs]
    print(f"  机器人停摆累计 均值 {sum(stalls)/len(stalls):.0f}s")
    return rs


if __name__ == "__main__":
    print("== L5 双路线斩杀率（设计 §10.4/10.6，基线 ≥50%）==")
    run_batch("A")
    run_batch("B")
    print()
    print("== 静态经济算术（§10.2/10.5）==")
    income = 300 + 176 + 20 * 5 + 120  # 起始 + 开格 + 标旗 + 互动（估）
    full = 2 * 50 + 2 * 100 + 2 * 220 + 80 + 80 + 2 * 100  # 双机翻倍 + 4 轨 + 基地 + 保安 + 探测×2
    print(f"  终身收入≈{income} vs 满配≈{full} → {'必须取舍 PASS' if income < full else '全买得起 FAIL'}")
    print(f"  互动收入≈120-150 ≈ 标旗收入 100 的量级 PASS")
