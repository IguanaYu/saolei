# -*- coding: utf-8 -*-
"""第二关经济模拟器：验证设计文档 §8.3 双路线 90s 可行（门槛 <80s 留 10s 余量）
模型对齐 robot.gd / pathfinding.gd / solver.gd：
  - 机器人每 speed_interval 秒一 tick；tick 内清失效目标→锁最近确定目标→已邻接则作业、否则走 1 格（4 向 BFS，只在已开格上走）
  - 目标锁定互斥（locked 字典，自己锁的自己能用）；升级即时改 tick 间隔
  - opener 开格（含洪水连锁，每格 +1 钱）；marker 标对旗（+5 钱）
  - 玩家：开局 5 次免 CD（按 0.5s/击节奏），之后 3s CD；瞬发动作，挑离机器人最远的确定目标（开格优先）
经济对齐 game_state.gd：起始 300；机器人价 50/100/200（各类型独立）；升级 50/70/100 双轨；速度档 2.0/1.6/1.3/1.0
盘面 = FixedBoards.L2（tmp/level2_board_finder.py 烘焙，seed=1 base=(3,7)）
"""
import sys
from collections import deque

W = H = 14
MINES = {(0,0),(0,2),(0,3),(1,0),(2,2),(3,3),(3,12),(4,2),(4,13),(5,12),(7,4),(7,9),
         (8,2),(8,5),(10,6),(10,8),(11,5),(11,9),(11,10),(12,1),(12,5),(12,7),(13,7),(13,12)}
BASE = (3, 7)
PREOPEN = set()
_px = [0,4,0,5,0,6,0,7,0,8,0,9,0,10,0,11,0,12,0,13,1,4,1,5,1,6,1,7,1,8,1,9,1,10,1,11,1,12,1,13,
       2,4,2,5,2,6,2,7,2,8,2,9,2,10,2,11,2,12,2,13,3,4,3,5,3,6,3,7,3,8,3,9,3,10,3,11,
       4,3,4,4,4,5,4,6,4,7,4,8,4,9,4,10,4,11,5,3,5,4,5,5,5,6,5,7,5,8,5,9,5,10,5,11,
       6,3,6,4,6,5,6,6,6,7,6,8,6,9,6,10,6,11,7,5,7,6,7,7,7,8,8,6,8,7,8,8,9,6,9,7,9,8]
for i in range(0, len(_px), 2):
    PREOPEN.add((_px[i], _px[i+1]))

NB = {}
for x in range(W):
    for y in range(H):
        NB[(x, y)] = [(x+dx, y+dy) for dx in (-1,0,1) for dy in (-1,0,1)
                      if (dx or dy) and 0 <= x+dx < W and 0 <= y+dy < H]
NUM = {c: sum(1 for n in NB[c] if n in MINES) for c in NB}

SPEED_LEVELS = [2.0, 1.6, 1.3, 1.0]
UPGRADE_PRICES = [50, 70, 100]
ROBOT_PRICES = [50, 100, 200]   # 各类型独立 50*2^n
START_GOLD = 100
FREE_CLICKS = 5
PLAYER_CD = 3.0
SAFE_TOTAL = W*H - len(MINES)   # 172

def flood(opened, start):
    if start in MINES or start in opened:
        return 0
    opened.add(start); cnt = 1
    if NUM[start] == 0:
        stack = [start]
        while stack:
            for n in NB[stack.pop()]:
                if n not in opened and n not in MINES:
                    opened.add(n); cnt += 1
                    if NUM[n] == 0:
                        stack.append(n)
    return cnt

def rule_targets(opened, flagged):
    to_flag, to_open = set(), set()
    for c in opened:
        k = NUM[c]
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

def bfs_dists(opened, src):
    """4 向 BFS，只在已开格上走；返回 {cell: 步数}"""
    dist = {src: 0}
    q = deque([src])
    while q:
        c = q.popleft()
        for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
            n = (c[0]+dx, c[1]+dy)
            if 0 <= n[0] < W and 0 <= n[1] < H and n in opened and n not in dist:
                dist[n] = dist[c] + 1
                q.append(n)
    return dist

class Robot:
    def __init__(self, rtype, home, rid):
        self.rtype = rtype; self.coord = home; self.timer = 0.0
        self.target = None; self.rid = rid
    def interval(self, lv):
        return SPEED_LEVELS[min(lv, len(SPEED_LEVELS)-1)]
    def nearest_work(self, dist, t):
        """dist（BFS 自本机）下 t 的最近作业位；返回 (成本, 作业格) 或 None"""
        best, bcell = None, None
        for c in NB[t]:
            if c in dist and (best is None or dist[c] < best):
                best, bcell = dist[c], c
        if best is None:
            return None
        return best, bcell
    def tick(self, opened, flagged, locked, stats, levels):
        # 1. 清失效目标（对齐 robot.gd do_tick 步骤 1）
        if self.target is not None and (self.target in opened or self.target in flagged):
            locked.pop(self.target, None)
            self.target = None
        # 2. 无目标 → 两规则扫描 + 锁最近可达目标
        if self.target is None:
            tf, to = rule_targets(opened, flagged)
            cands = to if self.rtype == "opener" else tf
            cands = [c for c in cands if locked.get(c) is None or locked[c] is self]
            if not cands:
                return
            dist = bfs_dists(opened, self.coord)
            best, bc = None, None
            for c in cands:
                nw = self.nearest_work(dist, c)
                if nw is not None and (bc is None or nw[0] < bc):
                    best, bc = c, nw[0]
            if best is None:
                return
            self.target = best
            locked[best] = self
        # 3. 邻接作业 / 走一格
        dist = bfs_dists(opened, self.coord)
        nw = self.nearest_work(dist, self.target)
        if nw is None:
            return  # 目标暂时被隔断，等区域打通
        w, work = nw
        if w == 0:
            t = self.target
            locked.pop(t, None); self.target = None
            if self.rtype == "opener":
                k = flood(opened, t)
                stats["money"] += k; stats["income"] += k
                stats["robot_opens"] += k; stats["open_score"] += k
            else:
                flagged.add(t)
                stats["money"] += 5; stats["income"] += 5
                stats["robot_flags"] += 1; stats["flag_score"] += 5
        else:
            # 从作业位沿 dist 递减回溯，取 dist==1 的格作为本 tick 的下一步
            cur = work
            while dist[cur] > 1:
                for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
                    n = (cur[0]+dx, cur[1]+dy)
                    if n in dist and dist[n] == dist[cur] - 1:
                        cur = n
                        break
            self.coord = cur

class Sim:
    def __init__(self, route):
        self.route = route
        self.opened = set(PREOPEN)
        self.flagged = set()
        self.locked = {}
        self.robots = []
        self.levels = {"opener": 0, "marker": 0}
        self.counts = {"opener": 0, "marker": 0}
        self.stats = {"money": START_GOLD, "income": 0, "spent": 0,
                      "robot_opens": 0, "robot_flags": 0,
                      "player_opens": 0, "player_flags": 0, "chords": 0,
                      "open_score": 0, "flag_score": 0}
        self.timeline = []
        self.free_left = FREE_CLICKS
        self.player_timer = 0.5   # 首击在 0.5s（读盘反应）
        self.next_rid = 0
        # 开局赠送一对（计数照常抬价格阶梯，不扣钱）
        for rt in ("opener", "marker"):
            self.counts[rt] += 1
            self.robots.append(Robot(rt, BASE, self.next_rid)); self.next_rid += 1

    def buy_robot(self, rtype, t):
        price = ROBOT_PRICES[self.counts[rtype]]
        assert self.stats["money"] >= price
        self.stats["money"] -= price; self.stats["spent"] += price
        self.counts[rtype] += 1
        self.robots.append(Robot(rtype, BASE, self.next_rid)); self.next_rid += 1
        self.timeline.append((round(t,1), f"buy {rtype} #{self.counts[rtype]} -{price}"))

    def buy_upgrade(self, rtype, t):
        lv = self.levels[rtype]
        price = UPGRADE_PRICES[lv]
        assert self.stats["money"] >= price
        self.stats["money"] -= price; self.stats["spent"] += price
        self.levels[rtype] = lv + 1
        self.timeline.append((round(t,1), f"upgrade {rtype} Lv{lv+1} -{price}"))

    def policy(self, t):
        """路线购物脚本：每次只买一件，循环调用至买不动"""
        m = self.stats["money"]
        if self.route == "A":  # 升级优先：双轨尽量买满（初始一对为赠送）
            plan = [
                ("up", "opener", 50), ("up", "marker", 50),
                ("up", "opener", 70), ("up", "marker", 70),
                ("up", "opener", 100), ("up", "marker", 100)]
        else:  # B：加机器人 + 双 Lv1（初始一对为赠送）
            plan = [
                ("up", "opener", 50), ("up", "marker", 50),
                ("robot", "opener", 100), ("robot", "marker", 100)]
        for kind, rtype, price in plan:
            if kind == "robot":
                if self.counts[rtype] < ROBOT_PRICES.index(price) + 1 and m >= price:
                    self.buy_robot(rtype, t); return True
            else:
                lv = self.levels[rtype]
                if lv < UPGRADE_PRICES.index(price) + 1 and m >= price:
                    self.buy_upgrade(rtype, t); return True
        return False

    def player_act(self, t):
        """玩家瞬发：①有 ≥2 格的和弦位优先和弦（真实能力，设计 §3 和弦吃 1 次 CD）
        ②否则挑未被机器人锁定的确定目标，开格优先，取离机器人最远的 ③否则标旗"""
        # 和弦：已开数字格 c 且周围旗数==数字且有未开邻格 → 未开邻格全开
        best_chord, best_un = None, 0
        for c in self.opened:
            k = NUM[c]
            if not k:
                continue
            un = [n for n in NB[c] if n not in self.opened and n not in self.flagged]
            if not un:
                continue
            fl = sum(1 for n in NB[c] if n in self.flagged)
            if fl == k and len(un) > best_un:
                best_chord, best_un = c, len(un)
        if best_chord is not None and best_un >= 2:
            got = 0
            for n in NB[best_chord]:
                if n not in self.opened and n not in self.flagged:
                    got += flood(self.opened, n)
            self.stats["money"] += got; self.stats["income"] += got
            self.stats["player_opens"] += got; self.stats["open_score"] += got
            self.stats["chords"] += 1
            return True
        tf, to = rule_targets(self.opened, self.flagged)
        pool = [(c, "open") for c in to if self.locked.get(c) is None] or \
               [(c, "flag") for c in tf if self.locked.get(c) is None]
        if not pool:
            return False
        def far(c):
            return min(max(abs(c[0]-r.coord[0]), abs(c[1]-r.coord[1]))
                       for r in self.robots) if self.robots else 0
        c, act = max(pool, key=lambda p: (p[1] == "open", far(p[0])))
        if act == "open":
            k = flood(self.opened, c)
            self.stats["money"] += k; self.stats["income"] += k
            self.stats["player_opens"] += k; self.stats["open_score"] += k
        else:
            self.flagged.add(c)
            self.stats["money"] += 5; self.stats["income"] += 5
            self.stats["player_flags"] += 1; self.stats["flag_score"] += 5
        return True

    def run(self, dt=0.05, tmax=120.0):
        t = 0.0
        while len(self.opened) < SAFE_TOTAL and t < tmax:
            while self.policy(t):
                pass
            # 玩家节奏
            self.player_timer -= dt
            if self.player_timer <= 0:
                if self.free_left > 0:
                    if self.player_act(t):
                        self.free_left -= 1
                        self.player_timer = 0.5
                    else:
                        self.player_timer = 0.2
                else:
                    if self.player_act(t):
                        self.player_timer = PLAYER_CD
                    else:
                        self.player_timer = 0.3
            # 机器人 tick（升级即时生效：每帧重读档位）
            for r in self.robots:
                r.timer += dt
                iv = r.interval(self.levels[r.rtype])
                while r.timer >= iv and len(self.opened) < SAFE_TOTAL:
                    r.timer -= iv
                    r.tick(self.opened, self.flagged, self.locked, self.stats, self.levels)
                    iv = r.interval(self.levels[r.rtype])
            t += dt
        return t

# ---- 静态算术断言（理论口径）----
assert SAFE_TOTAL * 1 + len(MINES) * 5 == 292, "理论全清收入 292"
# 实局口径：预开 75 格不给奖励 → 局内收入上限 217；起始 100 + 赠送一对
inrun = (SAFE_TOTAL - len(PREOPEN)) * 1 + len(MINES) * 5

for route, label in (("A", "A 全升级满+2台"), ("B", "B 各2台+双Lv1")):
    s = Sim(route)
    t = s.run()
    st = s.stats
    ok = t < 80.0 and len(s.opened) == SAFE_TOTAL
    print(f"=== 路线{label} ===")
    print(f"清完: {'是' if len(s.opened)==SAFE_TOTAL else '否 '+str(len(s.opened))+'/'+str(SAFE_TOTAL)}  用时 {t:.1f}s  (门槛 <80s: {'PASS' if ok else 'FAIL'})")
    print(f"机器人 opener×{s.counts['opener']} marker×{s.counts['marker']}  升级 {s.levels}")
    print(f"动作: 机器人开 {st['robot_opens']} 格/标 {st['robot_flags']} 旗 | 玩家开 {st['player_opens']} 格/标 {st['player_flags']} 旗")
    print(f"钱: 收入 {st['income']} (局内理论上限 {inrun}) | 花费 {st['spent']} | 终余 {st['money']}")
    print("购物时间线:", "; ".join(f"{tt}s {ev}" for tt, ev in s.timeline))
    print()
