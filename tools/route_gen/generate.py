# -*- coding: utf-8 -*-
"""MineSearch + RepairLoop：布雷候选生成、按反例最小修补、验收筛选（设计文档 §6/§8）。

流程（§8）：
  读取关卡规则与笔画 → 分析（route.analyze，验收口径即固定）→ 生成候选
  → 参考过程 + 正常策略试玩 + 绕路反例搜索 → 按反例选最小修补（守恒换雷/加墙/加锁）
  → 从开局复验 → 合格烘焙 / 预算耗尽返回冲突与最佳候选。

修补杠杆优先级（§8 修补优先级 + §7 只用现有机制）：
  主线卡住→修线索(换雷)；零区泄漏→修零区边缘换雷；走廊低成本→加墙/加锁（成本件）
  →仍不行→报告"当前机制预算下未找到合格方案"（§7.4 不静默加机关、不裁地图）。
"""
from __future__ import annotations

import random
from dataclasses import dataclass, field, replace

from tools.route_gen.rules import Board, GameSim, neighbors
from tools.route_gen.route import Acceptance, RouteAnalysis, analyze, cheb
from tools.route_gen.play import run_reference, run_normal, normal_seed_pass
from tools.route_gen.verify import find_violations, corridor_cost, Violation


@dataclass
class GenConfig:
    W: int = 16
    H: int = 16
    mine_count: int = 40
    start_money: int = 100
    band_radius: int = 2
    walls_max: int = 24          # 加固墙上限（CH2 固定盘用 18-30 块，此处取保守值）
    locks_max: int = 6
    fossil_origins: tuple = ()   # 2×2 左上原点（可选）
    max_candidates: int = 24
    max_repairs: int = 18
    acc: Acceptance = field(default_factory=Acceptance)


@dataclass
class Candidate:
    mines: set
    walls: set
    locked: set
    preopen: set
    score: float = -1e9
    violations: list = field(default_factory=list)
    ref_ok: bool = False
    normal_pass: int = 0
    stuck: str = ""

    def board(self, cfg: GenConfig) -> Board:
        return Board.build(cfg.W, cfg.H, self.mines, cfg.fossil_origins,
                           self.walls, self.locked, self.base)

    base: tuple = None


def bake_preopen(board: Board, zone: set) -> set:
    """grid._preopen_cascade 口径：区域内 0 格起洪水的烘焙预开"""
    opened = set(zone)
    queue = [c for c in zone if c not in board.mines and board.numbers.get(c) == 0]
    visited = set(queue)
    while queue:
        c = queue.pop(0)
        for n in neighbors(c, board.W, board.H):
            if n in visited:
                continue
            visited.add(n)
            if n in opened or n in board.mines:
                continue
            opened.add(n)
            if board.numbers.get(n) == 0:
                queue.append(n)
    return opened


def hard_constraint_cells(cfg: GenConfig, ra: RouteAnalysis) -> set:
    """不许放雷的格：锚点（安全锚保证 §4.4）、化石、基地安全区（place_first_base
    半径 1 口径——真实流程雷生成排除安全区，预开种子区必须无雷）"""
    no_mine = {c for _, c, _ in ra.anchors}
    for o in cfg.fossil_origins:
        for dy in (0, 1):
            for dx in (0, 1):
                no_mine.add((o[0] + dx, o[1] + dy))
    x, y = ra.start
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if 0 <= x + dx < cfg.W and 0 <= y + dy < cfg.H:
                no_mine.add((x + dx, y + dy))
    return no_mine


def initial_zone(cfg: GenConfig, ra: RouteAnalysis) -> set:
    """开局安全区：基地=路线起点，半径 1（place_first_base 半径口径）"""
    x, y = ra.start
    return {(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)
            if 0 <= x + dx < cfg.W and 0 <= y + dy < cfg.H}


def evaluate(cand: Candidate, cfg: GenConfig, ra: RouteAnalysis, acc: Acceptance,
             with_normal: bool = True) -> Candidate:
    """完整验收（§8 筛选 1-4）：真值正确 → 主线完成 → 无低成本跨段 → 正常策略贴线 → 省机关"""
    board = cand.board(cfg)
    preopen = bake_preopen(board, initial_zone(cfg, ra))
    cand.preopen = preopen
    vs = [v for v in cand.violations]
    ref = run_reference(board, preopen, ra, acc, start_money=cfg.start_money)
    cand.ref_ok = ref.ok
    cand.stuck = ref.stuck_reason
    if not ref.ok:
        cand.violations = [Violation("main_stuck", ref.stuck_stage,
                                     [ref.frontier_cell] if ref.frontier_cell else [],
                                     cand.stuck)] + \
                          [v for v in vs if v.kind == "corridor"]
        cand.score = -1000 - len(cand.violations)
        return cand
    vs = find_violations(board, ra, acc, preopen, ref, cfg.start_money)
    cand.violations = vs
    npass = 0
    if with_normal and not vs:
        # 无已知反例才跑 8 种子正常策略（§4.4：至少 6 条按关键里程碑顺序推进）
        styles = ["closure", "frontier", "frontier", "probe",
                  "frontier", "verify", "frontier", "probe"]
        for seed in range(acc.normal_seeds):
            r = run_normal(board, preopen, ra, acc, seed=seed,
                           style=styles[seed % len(styles)],
                           start_money=cfg.start_money)
            if normal_seed_pass(r, ra):
                npass += 1
    cand.normal_pass = npass
    hard_vs = sum(1 for v in vs if v.kind in ("skip", "flood_leak", "preopen_leak"))
    corridor_vs = sum(1 for v in vs if v.kind == "corridor")
    cand.score = (
        - 1000 * hard_vs                     # 跳段反例一票否决级
        - 100 * (0 if ref.ok else 1)
        - 10 * corridor_vs
        - 5 * max(0, acc.normal_pass - npass)
        - 1 * (len(cand.walls) + len(cand.locked))   # 省机关（§8 筛选 4）
    )
    return cand


def repair(cand: Candidate, cfg: GenConfig, ra: RouteAnalysis, rnd: random.Random) -> Candidate:
    """按反例选最小修补（§8）。返回修补后的新候选（原候选不动）。"""
    no_mine = hard_constraint_cells(cfg, ra)
    board = cand.board(cfg)
    mines = set(cand.mines)
    walls = set(cand.walls)
    locked = set(cand.locked)
    allowed_new_mine = {c for c in board.numbers
                        if c not in no_mine and c not in cand.preopen and c not in mines}
    action = None

    for v in cand.violations:
        if v.kind in ("preopen_leak", "flood_leak"):
            # 零区泄漏：先批量围堵预开（换雷+局部加固墙，§8"修零区边缘或放局部加固墙"）；
            # 中途洪水泄漏换雷贴近泄漏区
            if v.kind == "preopen_leak":
                fm, fw = contain_flood(cand.mines, cfg, ra, no_mine, rnd,
                                       max_swaps=8, walls=cand.walls)
                if fm != cand.mines or fw != cand.walls:
                    return replace(cand, mines=fm, walls=fw, score=-1e9,
                                   violations=[], ref_ok=False, normal_pass=0)
            targets = (v.cells[:3] if v.cells else [None])
            action = [("swap_near", t) for t in targets]
            break
        if v.kind == "main_stuck":
            # 主线卡住：优先搬出卡点阶段核心区里的雷（核心区雷多过半=接触条件不可满足），
            # 再搬卡点附近的雷到带外（带内减密→信息流恢复，§8"修可用线索"）
            ops = []
            core = ra.stage_cells.get(v.stage, set())
            core_mines = [m for m in sorted(mines) if m in core and m not in no_mine
                          and m not in cand.preopen]
            far_pool = [c for c in allowed_new_mine if c not in ra.band]
            if core_mines and far_pool and \
                    len(core_mines) > (1 - acc_stage_safe_frac()) * len(core):
                ops.append(("relocate", (rnd.choice(core_mines), rnd.choice(far_pool))))
            center = v.cells[0] if v.cells else None
            if center is not None:
                near_mines = [m for m in sorted(mines) if m in _radius(center, 3, cfg.W, cfg.H)
                              and m not in no_mine and m not in cand.preopen]
                if near_mines and far_pool:
                    ops.append(("relocate", (rnd.choice(near_mines), rnd.choice(far_pool))))
            if not ops:
                ops = [("swap_global", None)]
            action = ops
            break
        if v.kind == "corridor":
            # 走廊太便宜：墙优先落在当前最短穿越路径上（堵最便宜走法逼改道），
            # 路径格没落脚点再退回整条带；再加锁（+1/格），都满则换雷
            cost, cells, path_cells = corridor_cost(board, ra, _corridor_of(ra, v))
            anchors_set = {a for _, a, _ in ra.anchors}
            if len(walls) < cfg.walls_max:
                spot = [c for c in path_cells if c not in cand.preopen
                        and c not in anchors_set
                        and c not in board.fossils and c != ra.start]
                if not spot:
                    spot = [c for c in cells if c not in cand.preopen
                            and c not in anchors_set
                            and c not in board.fossils and c != ra.start]
                if spot:
                    action = [("wall", rnd.choice(spot))]
                    break
            if len(locked) < cfg.locks_max:
                spot = [c for c in cells if c not in cand.preopen
                        and c not in walls and c not in board.fossils]
                if spot:
                    action = [("lock", rnd.choice(spot))]
                    break
            action = [("swap_near", rnd.choice(cells))]
            break
    if action is None:
        action = [("swap_near", None)]   # 无定位信息：全局扰动

    for op in action:
        if op[0] == "wall":
            walls.add(op[1])
        elif op[0] == "lock":
            locked.add(op[1])
        elif op[0] == "relocate":
            m, n = op[1]
            mines.discard(m)
            mines.add(n)
        else:
            # 守恒换雷：m→n，雷数不变、数字重算（§6"对局部雷位做守恒交换"）
            center = op[1] if op[0] == "swap_near" else None
            if center is not None:
                near_new = [c for c in allowed_new_mine
                            if c in _radius(center, 2, cfg.W, cfg.H)]
            else:
                near_new = sorted(allowed_new_mine)
            pool_old = sorted(mines)
            if not near_new or not pool_old:
                continue
            n = rnd.choice(near_new)
            m = rnd.choice(pool_old)
            mines.discard(m)
            mines.add(n)
    return replace(cand, mines=mines, walls=walls, locked=locked,
                   score=-1e9, violations=[], ref_ok=False, normal_pass=0)


def _corridor_of(ra: RouteAnalysis, v: Violation):
    """从反例 cells 反查走廊编号：取端点阶段匹配的第一条"""
    for corridor in ra.corridors:
        _, cells, _p = corridor_cost(_dummy_board(ra), ra, corridor)
        if set(cells) & set(v.cells):
            return corridor
    return ra.corridors[0] if ra.corridors else (0, 1, 0, 1, 1)


def _dummy_board(ra):
    from tools.route_gen.rules import Board as B
    return B.build(ra.W, ra.H, set(), base=ra.start)


def _radius(c, r, W, H):
    return {(c[0] + dx, c[1] + dy) for dx in range(-r, r + 1) for dy in range(-r, r + 1)
            if 0 <= c[0] + dx < W and 0 <= c[1] + dy < H}


def acc_stage_safe_frac() -> float:
    """阶段核心区安全格占比下限（接触条件 50% 可满足的裕度）"""
    return 0.6


def _leak_of(mines, walls, cfg, ra):
    """泄漏 = 预开跳过整阶段揭开的带内格（与 verify.find_violations 同口径）"""
    board = Board.build(cfg.W, cfg.H, mines, cfg.fossil_origins, walls=walls, base=ra.start)
    preopen = bake_preopen(board, initial_zone(cfg, ra))
    zone_stage = ra.label.get(ra.start, 1)
    leaked = [c for c in preopen
              if ra.label.get(c) is not None and ra.label[c] >= zone_stage + 2]
    return board, preopen, leaked


def contain_flood(mines: set, cfg: GenConfig, ra: RouteAnalysis, no_mine: set,
                  rnd: random.Random, max_swaps: int = 30, walls: set = None) -> tuple:
    """洪水围堵（贪心闸门版，§8"修零区边缘或放局部加固墙"）：
    每轮对预开区里的 0 格逐个试算"加墙后泄漏降幅"，选降幅最大者落墙/落雷——
    直接命中零格链咽喉，避免贴着泄漏格打的无穷改道。
    返回 (mines, walls)。"""
    mines = set(mines)
    walls = set(walls) if walls else set()
    zone = initial_zone(cfg, ra)
    for _ in range(max_swaps):
        board, preopen, leaked = _leak_of(mines, walls, cfg, ra)
        if len(leaked) <= cfg.acc.preopen_leak_max:
            return mines, walls
        # 候选闸门：预开区内的 0 格（非安全区/锚点/基地）
        gates = [c for c in preopen
                 if board.numbers.get(c) == 0 and c not in no_mine and c != ra.start]
        best = None
        for z in gates:
            _, _, l2 = _leak_of(mines, walls | {z}, cfg, ra)
            score = len(l2) + (0.5 if z in {c for cells in ra.stage_cells.values() for c in cells} else 0.0)
            if best is None or score < best[0]:
                best = (score, z, len(l2))
        if best is None or best[2] >= len(leaked):
            return mines, walls   # 无单点可降：交给上层换雷/报告冲突
        if len(walls) < cfg.walls_max:
            walls.add(best[1])
        else:
            pool_out = [m for m in mines if m not in no_mine and m not in zone]
            if not pool_out:
                return mines, walls
            m = rnd.choice(pool_out)
            mines.discard(m)
            mines.add(best[1])
    return mines, walls


def generate(stroke_pts, cfg: GenConfig, seed: int = 7, log=print):
    """主入口：笔画 → 合格固定盘（或最佳候选+冲突报告）。"""
    rnd = random.Random(seed)
    ra = analyze(stroke_pts, cfg.W, cfg.H, band_radius=cfg.band_radius)
    acc = cfg.acc
    no_mine = hard_constraint_cells(cfg, ra)
    allowed = {c for c in [(x, y) for y in range(cfg.H) for x in range(cfg.W)]
               if c not in no_mine}
    if len(allowed) < cfg.mine_count:
        raise ValueError(f"硬约束排除后放不下 {cfg.mine_count} 颗雷（只剩 {len(allowed)} 格）")

    log(f"[分析] 阶段={ra.n_stages} 锚点={len(ra.anchors)} 里程碑={len(ra.milestones)} "
        f"走廊提名={len(ra.corridors)} 带内格={len(ra.band)}")
    for (i, c, kind) in ra.anchors:
        log(f"   锚点#{i} {c} {kind} 阶段{ra.stage_of_path[i]}")

    best = None
    tried = 0
    while tried < cfg.max_candidates:
        tried += 1
        # 初始布雷：带内减密（band_ratio 份额），富矿沉到线外（§1 取舍 2/§6 主线方向信息流）
        band_allowed = sorted(c for c in allowed if c in ra.band)
        out_allowed = sorted(c for c in allowed if c not in ra.band)
        n_band = min(len(band_allowed), round(cfg.mine_count * 0.5))
        mines = set(rnd.sample(band_allowed, n_band)) | \
            set(rnd.sample(out_allowed, min(cfg.mine_count - n_band, len(out_allowed))))
        while len(mines) < cfg.mine_count:
            rest = [c for c in out_allowed if c not in mines]
            if not rest:
                rest = [c for c in band_allowed if c not in mines]
            if not rest:
                break
            mines.add(rnd.choice(rest))
        cand = Candidate(mines=mines, walls=set(), locked=set(),
                         preopen=set(), base=ra.start)
        # 初始洪水围堵（带内减密后洪水易直通全图，先构造性切链/落墙）
        cand.mines, cand.walls = contain_flood(cand.mines, cfg, ra, no_mine, rnd,
                                               walls=cand.walls)
        stale = 0
        last_eval = None
        while stale < cfg.max_repairs:
            cand = evaluate(cand, cfg, ra, acc, with_normal=(stale == 0 or not cand.violations))
            last_eval = cand
            hard = [v for v in cand.violations if v.kind != "corridor"]
            if cand.ref_ok and not hard:
                # 全绿：跑正常策略确认（evaluate 内 with_normal 已跑）；接受
                if cand.normal_pass >= acc.normal_pass:
                    log(f"[候选{tried}] 修补{stale}轮后合格：score={cand.score:.0f} "
                        f"正常策略{cand.normal_pass}/{acc.normal_pass} "
                        f"墙={len(cand.walls)} 锁={len(cand.locked)}")
                    return ra, cand, []
                # 正常策略不过线也算软失败：换雷扰动
                if best is None or cand.score > best.score:
                    best = cand
                break
            if best is None or cand.score > best.score:
                best = cand
            fixed = repair(cand, cfg, ra, rnd)
            if fixed is None:
                break
            cand = fixed
            stale += 1
        ev = last_eval if last_eval is not None else cand
        stuck_at = next((v.stage for v in ev.violations if v.kind == "main_stuck"), "?")
        kinds = {}
        for v in ev.violations:
            kinds[v.kind] = kinds.get(v.kind, 0) + 1
        log(f"[候选{tried}] 放弃（修补{stale}轮："
            f"{'主线卡住@S' + str(stuck_at) if not ev.ref_ok else '剩' + str(len(ev.violations)) + '反例 ' + str(kinds)}）")

    conflicts = sorted({v.kind for v in best.violations}) if best else ["unknown"]
    log(f"[结束] {tried} 个候选未出全合格解；最佳 score={best.score:.0f} 反例类型={conflicts}")
    return ra, best, best.violations if best else []
