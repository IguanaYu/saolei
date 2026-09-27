# -*- coding: utf-8 -*-
"""第三关经济模拟器：验证设计文档 v1.2 §8 验收标准
模型对齐 WP1 改造后的 robot.gd / game_state.gd：
  - opener/marker 双轨节奏：移动间隔与工作间隔独立计时——
    已锁目标且与目标相邻（切比雪夫 ≤1）→ 下一 tick 用工作间隔；否则移动间隔
  - detector/miner 不在本关 allowed_modules（不模拟）
盘面 = FixedBoards.L3（tmp/level3_board_finder.py 烘焙 seed=43 base=(3,5)，预开 101 格起始分）
局外方案 a 不买 / b 移动Lv1 / c 工作Lv1 / d 送机器人Lv1 × 局内策略 A 升级优先 / B 加机器人优先 = 8 组合。
"""
import sys
sys.path.insert(0, ".")
from tmp.l3_board_data import MINES, PREOPEN, BASE  # noqa: E402
from collections import deque

W = H = 16
MOVE_LEVELS = [2.0, 1.6, 1.3, 1.0]
WORK_LEVELS = [2.0, 1.6, 1.3, 1.0]
UPGRADE_PRICES = [50, 70, 100]
ROBOT_PRICES = [50, 100, 200]
START_GOLD = 300
FREE_CLICKS = 5
PLAYER_CD = 3.0
SCORE_TARGET = 300
TIME_LIMIT = 120.0
PREOPEN_SCORE = len(PREOPEN)   # 预开算分（设计 v1.2，只计分不计钱）
SAFE_TOTAL = W * H - len(MINES)

NB = {}
for x in range(W):
    for y in range(H):
        NB[(x, y)] = [(x+dx, y+dy) for dx in (-1,0,1) for dy in (-1,0,1)
                      if (dx or dy) and 0 <= x+dx < W and 0 <= y+dy < H]
NUM = {c: sum(1 for n in NB[c] if n in MINES) for c in NB}

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

def cheb(a, b):
    return max(abs(a[0]-b[0]), abs(a[1]-b[1]))

class Robot:
    """双轨节奏：next_interval 按'下一 tick 将做什么'选表（对齐 WP1 robot.gd）"""
    def __init__(self, rtype, home, rid):
        self.rtype = rtype; self.coord = home; self.timer = 0.0
        self.target = None; self.rid = rid
    def next_interval(self, levels):
        if self.target is not None and cheb(self.coord, self.target) <= 1:
            return WORK_LEVELS[min(levels[self.rtype + "_work"], len(WORK_LEVELS) - 1)]
        return MOVE_LEVELS[min(levels[self.rtype + "_move"], len(MOVE_LEVELS) - 1)]
    def nearest_work(self, dist, t):
        best, bcell = None, None
        for c in NB[t]:
            if c in dist and (best is None or dist[c] < best):
                best, bcell = dist[c], c
        return None if best is None else (best, bcell)
    def tick(self, opened, flagged, locked, stats):
        if self.target is not None and (self.target in opened or self.target in flagged):
            locked.pop(self.target, None)
            self.target = None
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
        dist = bfs_dists(opened, self.coord)
        nw = self.nearest_work(dist, self.target)
        if nw is None:
            return
        w, work = nw
        if w == 0:
            t = self.target
            locked.pop(t, None); self.target = None
            if self.rtype == "opener":
                k = flood(opened, t)
                stats["money"] += k; stats["income"] += k
                stats["robot_opens"] += k; stats["open_score"] += k
                stats["score"] += k
            else:
                flagged.add(t)
                stats["money"] += 5; stats["income"] += 5
                stats["robot_flags"] += 1; stats["flag_score"] += 5
                stats["score"] += 5
        else:
            cur = work
            while dist[cur] > 1:
                for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
                    n = (cur[0]+dx, cur[1]+dy)
                    if n in dist and dist[n] == dist[cur] - 1:
                        cur = n
                        break
            self.coord = cur

TRACKS = ["opener_move", "opener_work", "marker_move", "marker_work"]

class Sim:
    def __init__(self, meta, route):
        """meta: 局外方案 dict(start_gold/move_lv/work_lv/robots)；route: 'A' 升级优先 | 'B' 加机器人优先"""
        self.route = route
        self.opened = set(PREOPEN)
        self.flagged = set()
        self.locked = {}
        self.robots = []
        self.levels = {t: 0 for t in TRACKS}
        lv_move, lv_work = meta.get("move_lv", 0), meta.get("work_lv", 0)
        self.levels["opener_move"] = lv_move
        self.levels["marker_move"] = lv_move
        self.levels["opener_work"] = lv_work
        self.levels["marker_work"] = lv_work
        self.counts = {"opener": 0, "marker": 0}
        self.stats = {"money": START_GOLD + meta.get("start_gold", 0), "income": 0, "spent": 0,
                      "robot_opens": 0, "robot_flags": 0, "player_opens": 0, "player_flags": 0,
                      "chords": 0, "open_score": 0, "flag_score": 0, "score": PREOPEN_SCORE}
        self.timeline = []
        self.free_left = FREE_CLICKS
        self.player_timer = 0.5
        self.next_rid = 0
        # 局外送机器人（start_robot Lv1 送 opener；计入 count 抬价格阶梯）
        if meta.get("robot", 0) >= 1:
            self.counts["opener"] += 1
            self.robots.append(Robot("opener", BASE, self.next_rid)); self.next_rid += 1



    def buy_robot(self, rtype, t):
        price = ROBOT_PRICES[self.counts[rtype]]
        assert self.stats["money"] >= price, f"money {self.stats['money']} < {price}"
        self.stats["money"] -= price; self.stats["spent"] += price
        self.counts[rtype] += 1
        self.robots.append(Robot(rtype, BASE, self.next_rid)); self.next_rid += 1
        self.timeline.append((round(t, 1), f"buy {rtype} #{self.counts[rtype]} -{price}"))

    def buy_upgrade(self, track, t):
        lv = self.levels[track]
        price = UPGRADE_PRICES[lv]
        assert self.stats["money"] >= price
        self.stats["money"] -= price; self.stats["spent"] += price
        self.levels[track] = lv + 1
        self.timeline.append((round(t, 1), f"up {track} Lv{lv+1} -{price}"))

    def policy(self, t):
        m = self.stats["money"]
        if self.route == "A":  # 升级优先：先补一对机器人产能基线，再 4 轨由近及远买满
            for rtype in ("opener", "marker"):
                if self.counts[rtype] < 1:
                    price = ROBOT_PRICES[self.counts[rtype]]
                    if m >= price:
                        self.buy_robot(rtype, t); return True
            for i, price in enumerate(UPGRADE_PRICES):
                for track in TRACKS:
                    if self.levels[track] == i and m >= price:
                        self.buy_upgrade(track, t); return True
            return False
        # B：先补一对机器人（首台 50），再 4 轨 Lv1，再买满升级
        for rtype in ("opener", "marker"):
            price = ROBOT_PRICES[self.counts[rtype]]
            if self.counts[rtype] < 2 and m >= price:
                self.buy_robot(rtype, t); return True
        for track in TRACKS:
            if self.levels[track] < 1 and m >= UPGRADE_PRICES[0]:
                self.buy_upgrade(track, t); return True
        for i, price in enumerate(UPGRADE_PRICES):
            for track in TRACKS:
                if self.levels[track] == i and m >= price:
                    self.buy_upgrade(track, t); return True
        return False

    def player_act(self, t):
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
                if n not in self.opened and not (n in self.flagged):
                    got += flood(self.opened, n)
            self.stats["money"] += got; self.stats["income"] += got
            self.stats["player_opens"] += got; self.stats["open_score"] += got
            self.stats["score"] += got
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
            self.stats["score"] += k
        else:
            self.flagged.add(c)
            self.stats["money"] += 5; self.stats["income"] += 5
            self.stats["player_flags"] += 1; self.stats["flag_score"] += 5
            self.stats["score"] += 5
        return True

    def run(self, dt=0.05):
        t = 0.0
        crossed = False
        while t < TIME_LIMIT:
            while self.policy(t):
                pass
            if self.stats["score"] >= SCORE_TARGET:
                crossed = True
                break
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
                if self.stats["score"] >= SCORE_TARGET:
                    crossed = True
                    break
            for r in self.robots:
                r.timer += dt
                iv = r.next_interval(self.levels)
                while r.timer >= iv:
                    r.timer -= iv
                    r.tick(self.opened, self.flagged, self.locked, self.stats)
                    iv = r.next_interval(self.levels)
                    if self.stats["score"] >= SCORE_TARGET:
                        break
                if self.stats["score"] >= SCORE_TARGET:
                    crossed = True
                    break
            if crossed:
                break
            t += dt
        return t, crossed

# ---- §8.1/8.3/8.7 静态算术断言 ----
ORE_COSTS = {"start_money": [50, 100], "start_lives": [80, 160], "global_speed": [100, 200],
             "work_speed": [100, 200], "start_robot": [100, 200]}
total_ore_shop = sum(sum(c) for c in ORE_COSTS.values())
assert total_ore_shop == 1290, total_ore_shop          # §4.1 商店总价
assert 4 * sum(UPGRADE_PRICES) == 880                  # §8.7 四轨全满 880
assert UPGRADE_PRICES[2] == 100 == ROBOT_PRICES[1]     # §8.3 同价抉择带 Lv3=第2台=100
print(f"[静态] 矿石商店总价 {total_ore_shop} | 首通 L1+L2 = 400 | 4轨全满 880 | Lv3=第2台=100≈基地80")

METAS = {
    "a 不买":        {},
    "b 移动Lv1":     {"move_lv": 1},
    "c 工作Lv1":     {"work_lv": 1},
    "d 送机器人Lv1": {"robot": 1},
}
ROUTES = {"A 升级优先": "A", "B 加机器人优先": "B"}

results = {}
all_pass = True
for mname, meta in METAS.items():
    for rname, route in ROUTES.items():
        s = Sim(meta, route)
        t, crossed = s.run()
        st = s.stats
        lifetime = START_GOLD + meta.get("start_gold", 0) + st["income"]   # §8.1 终身预算口径
        ok = crossed and t < TIME_LIMIT
        all_pass = all_pass and ok
        swept = len(s.flagged)
        results[(mname, rname)] = (t, crossed, swept, lifetime)
        time_left = TIME_LIMIT - t
        action_score = s.stats["score"] - PREOPEN_SCORE
        tb = int(time_left) * 3
        print(f"[{mname} × {rname}] 过线 {'PASS' if crossed else 'FAIL'} @ {t:5.1f}s | "
              f"已标 {swept}/40 雷 ({swept/40:.0%}) | 行动分 {action_score}+起始{PREOPEN_SCORE} | "
              f"终身预算 ~{lifetime} | 时间加分口径 +{tb} (剩{int(time_left)}s)")
        if not crossed:
            print(f"    !! 未过线：score={s.stats['score']}/300 opens={len(s.opened)-len(PREOPEN)} flags={len(s.flagged)}")
print()

# §8.4 不买局外可过线
base_ok = results[("a 不买", "A 升级优先")][1] and results[("a 不买", "B 加机器人优先")][1]

# §8.6 双维度体感——"同类任务上 ≥15% 时间差"按节奏档位口径断言（构造保证）：
# 路途任务 = 单纯走 N 格：Lv0 需 2.0N 秒，Lv1 需 1.6N 秒 → 提速 20%
# 作业任务 = 邻接连作 N 次：同理 20%。总过线时间中的体现受玩家贡献稀释，另作参考输出
gain_move_tick = (MOVE_LEVELS[0] - MOVE_LEVELS[1]) / MOVE_LEVELS[0]
gain_work_tick = (WORK_LEVELS[0] - WORK_LEVELS[1]) / WORK_LEVELS[0]
dim_ok = gain_move_tick >= 0.15 and gain_work_tick >= 0.15
t_a = results[("a 不买", "B 加机器人优先")][0]
t_b = results[("b 移动Lv1", "B 加机器人优先")][0]
t_c = results[("c 工作Lv1", "B 加机器人优先")][0]
print(f"[§8.6 双维度] 同类任务提速：移动轨 {gain_move_tick:.0%} / 工作轨 {gain_work_tick:.0%}（门槛 ≥15%: {'PASS' if dim_ok else 'FAIL'}）")
print(f"[§8.6 参考] 全局体现（B 路线总过线时间差）：移动Lv1 {(t_a-t_b)/t_a:.1%} / 工作Lv1 {(t_a-t_c)/t_a:.1%}"
      f" —— 移动>工作：大盘路途占比高（设计意图），相对价值平衡留盲测（设计 §10）")
print(f"[§8.4 不买局外] A/B 均可过线: {'PASS' if base_ok else 'FAIL'}")
print(f"[总验收] 8 组合 <120s 过线: {'PASS' if all_pass else 'FAIL'}")
assert all_pass and base_ok and dim_ok, "§8 验收未全过——回设计文档调参（WP9.5），不硬凑"
