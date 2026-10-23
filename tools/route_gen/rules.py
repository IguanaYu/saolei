# -*- coding: utf-8 -*-
"""路径驱动地图生成器 · 忠实规则模拟器 v1（设计文档 §3 规则核对表的 Python 对应物）

对齐的真实代码（2026-10-23 逐条核对，行号为当日版本）：
  scripts/grid.gd       open_cell（1331 行文件：削层/开格/洪水/胜利）、_flood_open(1147)、
                        toggle_flag(882)/chord(904)/player_territory(957)、apply_fixed_board(654)
  scripts/cell.gd       open(352)/toggle_flag(390)/confirm_mine(509)/damage_wall(529)/锁与化石语义
  scripts/solver.gd     两条确定性规则（1: 旗数==数字→余格安全；2: 未开数+旗数==数字→全雷）
  scripts/main.gd       _on_cell_opened 奖励(1530: +1 金 +1 分/格)、_on_cell_flagged(1549:
                        正确首次 +5 金 +5 分、错旗无惩罚)、_trigger_probe(1883: 3×3 确认雷)
  autoload/game_state.gd PROBE_PRICE=100

口径声明（v1 边界，实施进展文档同步记录）：
  * 覆盖 ch01 普通关规则：开/标/和弦/洪水/锁/多层墙/化石/探针/奖励验真/领土。
    激光、精灵、敌人、覆盖墙、购买商店不入模拟（§12 开发顺序第 5 步）。
  * 机器人不物理模拟：v1 把「基础 Solver 的两条规则」当作免费推理动作（同
    tmp/ch02_s1_board_finder.py 的"机器人双规则免费"口径）；站位可达性单独检查（§3 表格）。
  * 总雷数视为公开信息（HUD 口径，设计文档 §5.2 快照字段）。
"""

from __future__ import annotations

from dataclasses import dataclass, field, replace

# 与 MapGenerator.NEIGHBOR_OFFSETS 完全一致（8 邻域）
NB8 = [(dx, dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if (dx, dy) != (0, 0)]

PROBE_PRICE = 100  # game_state.gd:47


def neighbors(c, W, H):
    x, y = c
    for dx, dy in NB8:
        nx, ny = x + dx, y + dy
        if 0 <= nx < W and 0 <= ny < H:
            yield (nx, ny)


@dataclass
class Board:
    """静态盘面真值（进入游玩后不变：设计 §13「雷位数字固定」）"""
    W: int
    H: int
    mines: set                      # {(x,y)}
    numbers: dict                   # {(x,y): 0-8}，由雷位 8 邻计数（map_generator 口径）
    fossils: set = field(default_factory=set)   # 2×2 展开后的格子集合
    walls: set = field(default_factory=set)     # 加固墙格（wall_hp=3），其余未开格=1
    locked: set = field(default_factory=set)    # 初始锁格
    base: tuple = None              # 预置基地；(None) = 玩家自放（v1 需给定）

    @staticmethod
    def build(W, H, mines, fossils_origins=(), walls=(), locked=(), base=None):
        mines = set(mines)
        fossils = set()
        for o in fossils_origins:           # apply_fixed_board: 化石 2×2 从左上原点展开
            ox, oy = o
            for dy in (0, 1):
                for dx in (0, 1):
                    if 0 <= ox + dx < W and 0 <= oy + dy < H:
                        fossils.add((ox + dx, oy + dy))
        assert not (mines & fossils), "化石与雷重叠=盘面数据错误（apply_fixed_board 拒铺并警告）"
        numbers = {}
        for y in range(H):
            for x in range(W):
                c = (x, y)
                if c in mines:
                    continue
                numbers[c] = sum(1 for n in neighbors(c, W, H) if n in mines)
        return Board(W, H, mines, numbers, fossils, set(walls), set(locked), base)


@dataclass
class SimState:
    """动态局面（可复制回滚）"""
    opened: set = field(default_factory=set)
    flagged: set = field(default_factory=set)
    collapsed: set = field(default_factory=set)   # 踩雷坍塌（视为已开、等价旗）
    confirmed: set = field(default_factory=set)   # 探针确认雷（公开可见）
    rewarded_flags: set = field(default_factory=set)  # 首次正确旗（grid.rewarded_flags 口径）
    verified: dict = field(default_factory=dict)  # {coord: reward_fired}——插旗即时反馈（验真通道）；
    # 仅 first_time 旗有信息量：非首次正确旗不再给奖（防刷），无新信息
    probe_results: list = field(default_factory=list)  # [(center, found_coords)]——探针公开结果
    money: int = 0
    score: int = 0
    probes_used: int = 0
    player_ops: int = 0                 # 有效玩家动作数（开/标/和弦/清锁/削层各 1）
    # 事件日志（对拍与报告用）：每次动作 append dict
    log: list = field(default_factory=list)

    def clone(self):
        return replace(self,
                       opened=set(self.opened), flagged=set(self.flagged),
                       collapsed=set(self.collapsed), confirmed=set(self.confirmed),
                       rewarded_flags=set(self.rewarded_flags),
                       verified=dict(self.verified),
                       probe_results=list(self.probe_results),
                       log=list(self.log))


class GameSim:
    """在真实规则下执行动作。动作语义逐条对齐 grid.gd / cell.gd / main.gd。"""

    def __init__(self, board: Board, start_money: int = 0):
        self.b = board
        self.st = SimState(money=start_money)
        self.wall_hp = {c: (3 if c in board.walls else 1) for c in self._all_cells()}

    def _all_cells(self):
        for y in range(self.b.H):
            for x in range(self.b.W):
                yield (x, y)

    # ---- 洪水（grid._flood_open:1147 逐条对齐：0 数字 8 邻扩散；旗/锁/多层墙/化石/雷停）----
    def _flood_open(self, start, out_opened, events):
        # 调用方（open_cell）保证 start 是刚开的安全 0 格；不做 opened/flagged 复查
        stack = [start]
        while stack:
            c = stack.pop()
            for n in neighbors(c, self.b.W, self.b.H):
                if n in out_opened:
                    continue
                if n in self.st.opened or n in self.st.flagged:
                    continue          # 旗格保持关闭（grid.gd:1162）
                if self.wall_hp.get(n, 1) > 1:
                    continue          # 多层墙停洪水（grid.gd:1164）
                if n in self.b.locked:
                    continue          # 锁格 open 失败（cell.gd:357）
                if n in self.b.fossils:
                    continue          # 化石 open 失败（cell.gd:355）
                if n in self.b.mines:
                    continue          # 雷不开
                self.st.opened.add(n)
                out_opened.add(n)
                self.st.money += 1    # 每格 +1 金（main.gd:1532）
                self.st.score += 1
                events.append({"type": "open", "coord": n, "flood": True})
                if self.b.numbers.get(n, 0) == 0:
                    stack.append(n)

    # ---- 开格（grid.open_cell:833 对齐：先削墙后判锁——damage_wall 不检查锁；
    #      >1 层先削不开格；踩雷坍塌；0 触发洪水）----
    def open_cell(self, coord, actor="player"):
        """返回 (status, opened_cells)；status: 'opened'|'peeled'|'mine'|'blocked'|'noop'"""
        if not (0 <= coord[0] < self.b.W and 0 <= coord[1] < self.b.H):
            return "noop", []
        if coord in self.st.opened or coord in self.st.collapsed:
            return "noop", []
        if coord in self.st.flagged:
            return "noop", []         # 旗格 open 直接 return（grid.gd:837 未旗判定）
        if self.wall_hp.get(coord, 1) > 1 and coord not in self.b.fossils and coord != self.b.base:
            # damage_wall：未开未旗未塌未化石未基地可削；hp=maxi(1,hp-1)（cell.gd:529）
            self.wall_hp[coord] = max(1, self.wall_hp[coord] - 1)
            self.st.player_ops += 1
            self.st.log.append({"type": "peel", "coord": coord, "actor": actor,
                                "hp_left": self.wall_hp[coord]})
            return "peeled", []
        if coord in self.b.fossils:
            return "blocked", []      # 化石谁都开不了（cell.gd:355）
        if coord in self.b.locked:
            return "blocked", []      # 锁拦开（cell.gd:357）
        if coord == self.b.base:
            return "noop", []         # 基地格不可开（cell.gd:361）
        if coord in self.b.mines:
            # collapse：视为已开、等价旗（cell.gd:516）
            self.st.collapsed.add(coord)
            self.st.opened.add(coord)
            self.st.player_ops += 1
            self.st.log.append({"type": "mine_stepped", "coord": coord, "actor": actor})
            return "mine", [coord]
        events = []
        opened = {coord}
        self.st.opened.add(coord)
        self.st.money += 1            # player/robot 开格统一 +1 金 +1 分（main.gd:1532）
        self.st.score += 1
        if actor == "player":
            self.st.player_ops += 1
        events.append({"type": "open", "coord": coord, "flood": False})
        if self.b.numbers.get(coord, 0) == 0:
            self._flood_open(coord, opened, events)
        self.st.log.append({"type": "action", "kind": "open", "coord": coord,
                            "actor": actor, "opened": sorted(opened)})
        return "opened", sorted(opened)

    # ---- 插旗（grid.toggle_flag:882 + main._on_cell_flagged:1549 对齐）----
    def toggle_flag(self, coord, actor="player"):
        """返回 'flagged'|'unflagged'|'noop'；正确首次旗奖励可观察（验真通道）"""
        if coord in self.b.fossils or coord in self.b.locked:
            return "noop"             # 化石不可标（cell.gd:392）；锁拦标与撤（cell.gd:394）
        if coord in self.st.opened or coord in self.st.collapsed:
            return "noop"
        first_time = coord not in self.st.rewarded_flags
        if coord in self.st.flagged:
            self.st.flagged.discard(coord)
            self.st.log.append({"type": "action", "kind": "unflag", "coord": coord, "actor": actor})
            return "unflagged"
        self.st.flagged.add(coord)
        reward_fired = False
        if coord in self.b.mines and first_time:
            # +5 金 +5 分仅首次（main.gd:1555）；撤旗重插不再给（rewarded_flags 防刷）
            self.st.money += 5
            self.st.score += 5
            self.st.rewarded_flags.add(coord)
            reward_fired = True
        self.st.player_ops += 1
        if first_time:
            self.st.verified[coord] = reward_fired  # 反馈即时公开（钱数变化可观察）
        self.st.log.append({"type": "action", "kind": "flag", "coord": coord, "actor": actor,
                            "correct": coord in self.b.mines, "reward_fired": reward_fired,
                            "first_time": first_time})
        return "flagged"

    # ---- 和弦（grid.chord:904 对齐：已处理雷计入数字；逐邻 open_cell；踩雷会坍塌）----
    def chord(self, coord, actor="player"):
        if coord not in self.st.opened or self.b.numbers.get(coord, 0) == 0:
            return "noop"
        flagged_count = 0
        for n in neighbors(coord, self.b.W, self.b.H):
            if (n in self.st.flagged or n in self.st.collapsed or n in self.st.confirmed
                    or self._is_vein(n)):
                flagged_count += 1
        if flagged_count != self.b.numbers[coord]:
            return "noop"
        opened_total = []
        for n in sorted(neighbors(coord, self.b.W, self.b.H)):
            if n in self.st.opened or n in self.st.flagged or n in self.st.confirmed:
                continue
            if n in self.st.collapsed:
                continue
            status, opened = self.open_cell(n, actor)
            opened_total += opened
        self.st.log.append({"type": "action", "kind": "chord", "coord": coord,
                            "actor": actor, "opened": opened_total})
        return "chord"

    def _is_vein(self, _c):
        return False            # v1 无矿脉机制

    # ---- 探针（main._trigger_probe:1883 对齐：3×3 全部确认雷；零命中=全安全公开）----
    def probe(self, center, actor="player"):
        if self.st.money < PROBE_PRICE:
            return None
        self.st.money -= PROBE_PRICE
        self.st.probes_used += 1
        self.st.player_ops += 1
        found = []
        cx, cy = center
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                c = (cx + dx, cy + dy)
                if not (0 <= c[0] < self.b.W and 0 <= c[1] < self.b.H):
                    continue
                if c in self.b.mines and c not in self.st.confirmed:
                    self.st.confirmed.add(c)
                    found.append(c)
        self.st.probe_results.append((center, list(found)))
        self.st.log.append({"type": "action", "kind": "probe", "coord": center,
                            "actor": actor, "found": found})
        return found

    # ---- 清锁（grid._on_cell_right_clicked:1254：一次操作清锁）----
    def clear_lock(self, coord, actor="player"):
        if coord not in self.b.locked:
            return False
        self.b.locked.discard(coord)
        self.st.player_ops += 1
        self.st.log.append({"type": "action", "kind": "clear_lock", "coord": coord, "actor": actor})
        return True

    # ---- 领土（grid.player_territory:957：基地沿已开格 8 连通）----
    def territory(self):
        terr = set()
        if self.b.base is None:
            return terr
        if self.b.base not in self.st.opened:
            return terr
        queue = [self.b.base]
        terr.add(self.b.base)
        while queue:
            c = queue.pop()
            for n in neighbors(c, self.b.W, self.b.H):
                if n not in terr and n in self.st.opened:
                    terr.add(n)
                    queue.append(n)
        return terr

    def safe_remaining(self):
        return sum(1 for c in self.b.numbers
                   if c not in self.st.opened and c not in self.b.fossils)


# ---------------------------------------------------------------------------
# 公开知识 + 两条确定性规则（solver.gd 口径）+ 确定安全闭包
# ---------------------------------------------------------------------------

@dataclass
class Knowledge:
    """玩家有权观察的信息（不含真雷位）"""
    numbers: dict = field(default_factory=dict)   # 已开数字格 → 数字（网/炸弹遮罩 v1 无）
    known_mines: set = field(default_factory=set)   # 确认的雷：正确旗奖励+探针确认+坍塌
    known_safe: set = field(default_factory=set)    # 已证安全：探针零命中覆盖/验旗未中/已开
    total_mines: int = 0
    probed_zero: list = field(default_factory=list)  # 探针零命中中心（3×3 全安全）

    def clone(self):
        return Knowledge(dict(self.numbers), set(self.known_mines), set(self.known_safe),
                         self.total_mines, list(self.probed_zero))


def observe(sim: GameSim, k: Knowledge):
    """从局面提取公开知识（插旗反馈与探针结果都在 SimState 里已记录）"""
    b = sim.b
    for c in sim.st.opened:
        if c in sim.st.collapsed:
            continue
        if c not in k.numbers:
            k.numbers[c] = b.numbers[c]
    # 正确旗奖励是公开反馈（钱数变化）：rewarded_flags ⊆ known_mines
    k.known_mines |= set(sim.st.rewarded_flags)
    k.known_mines |= set(sim.st.confirmed)
    k.known_mines |= set(sim.st.collapsed)
    # 验真通道：首次插旗未中奖励 = 非雷（§3「玩家可根据奖励变化验雷」）
    for c, fired in sim.st.verified.items():
        if fired:
            k.known_mines.add(c)
        else:
            k.known_safe.add(c)
    # 探针公开结果：3×3 内 found=雷，覆盖内其余格全部安全（含零命中=9 格全安全）
    for center, found in sim.st.probe_results:
        cx, cy = center
        found_set = set(found)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                c = (cx + dx, cy + dy)
                if not (0 <= c[0] < b.W and 0 <= c[1] < b.H):
                    continue
                if c in found_set:
                    k.known_mines.add(c)
                elif c not in sim.st.opened:
                    k.known_safe.add(c)


def solver_rule_targets(k: Knowledge, closed_cells, nb_fn):
    """solver.gd 两条规则，只吃公开知识。返回 (to_flag, to_open)。
    口径：旗=known_mines ∪ 当前已标旗（策略只在确证时留旗，见 simulate 模块）；
    化石不参与计数与动作（solver.gd:30）。锁格参与计数、不产生动作（solver.gd:36）。"""
    to_flag, to_open = set(), set()
    flags = k.known_mines
    for c in k.numbers:
        num = k.numbers[c]
        if num == 0:
            continue
        fl, un = 0, []
        for n in nb_fn(c):
            if n in flags:
                fl += 1
            elif n in k.numbers or n in k.known_safe:
                continue             # 已开或已知安全
            elif n in closed_cells:
                un.append(n)
        if not un:
            continue
        if fl == num:
            to_open.update(un)
        if fl + len(un) == num:
            to_flag.update(un)
    to_flag -= flags
    to_open -= k.known_safe
    return to_flag, to_open


def deterministic_closure(sim: GameSim, k: Knowledge, max_rounds=64, record=None):
    """确定安全闭包（设计 §5.2）：反复从公开信息求确定动作，执行合法动作与真实洪水，
    直到无新增。返回每轮推进记录。闭包只做"免费"动作：开确定安全格、标确定雷。
    探针/验旗是有成本动作，由策略层显式调用（不混入免费闭包，§5.3 成本分开记）。
    record: 可选回调 fn(kind, coord)，把闭包实际执行的原始动作报给外层（对拍回放用）。"""
    b = sim.b
    rounds = []
    for _ in range(max_rounds):
        before_open = len(sim.st.opened)
        before_flag = len(sim.st.flagged) + len(k.known_mines)
        observe(sim, k)
        to_flag, to_open = solver_rule_targets(k, _closed_universe(b, sim), lambda c: neighbors(c, b.W, b.H))
        # 已知安全的格直接开（探针零命中覆盖内/验旗未中）
        to_open |= (k.known_safe & _closed_universe(b, sim)) - set()
        progressed = False
        for c in sorted(to_open):
            if c in sim.st.opened or c in sim.st.flagged:
                continue
            if c in b.locked:
                continue            # 锁格不产生动作（solver.gd:36）
            sim.open_cell(c, "solver")
            if record:
                record("open", c)
            progressed = True
        for c in sorted(to_flag):
            if c in sim.st.flagged or c in k.known_mines or c in sim.st.opened:
                continue
            if c in b.locked:
                continue
            sim.toggle_flag(c, "solver")
            if record:
                record("flag", c)
            progressed = True
        observe(sim, k)
        rounds.append({"opened_delta": len(sim.st.opened) - before_open,
                       "flags_delta": len(sim.st.flagged) + len(k.known_mines) - before_flag})
        if not progressed:
            break
    return rounds


def _closed_universe(b: Board, sim: GameSim):
    return {c for c in b.numbers
            if c not in sim.st.opened and c not in b.fossils}
