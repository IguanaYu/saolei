# -*- coding: utf-8 -*-
"""ShortcutFinder：系统自己找近路（设计文档 §5）+ 候选验收。

三类检查（§5.1→5.3，v1 覆盖前两类半）：
  1. 几何跨段提名（§5.1）——route.analyze 已产出 corridors，这里只按当前墙/锁算穿越成本；
  2. 信息与连开泄漏（§5.2）——参考过程阶段快照上做反事实闭包：禁开下一阶段核心区，
     若更后段被揭开 = 跳段反例；一次洪水揭开多段单独记为连开泄漏；
  3. 盲插验真可行性（§3 预检）——走廊穿越成本 = 3 操作/格 + 2/加固墙 + 1/锁，
     低于预算 = "换雷无法恢复信息屏障"型反例，只能靠操作成本或封印处理。
"""
from __future__ import annotations

from dataclasses import dataclass, field

from tools.route_gen.rules import (GameSim, Knowledge, observe,
                                   solver_rule_targets, neighbors)
from tools.route_gen.route import Acceptance, RouteAnalysis, bresenham_line


@dataclass
class Violation:
    kind: str            # skip / flood_leak / corridor / preopen_leak
    stage: int = 0       # 从哪个阶段快照发现
    cells: list = field(default_factory=list)   # 涉及格（修补定位用）
    detail: str = ""

    def label(self) -> str:
        return f"{self.kind}@S{self.stage}"


def closure_forbidden(sim: GameSim, k: Knowledge, forbidden: set, max_rounds=32):
    """确定安全闭包，但禁止开/标 forbidden 内的格（反事实：不走下一检查区）。
    返回本次闭包新开的格集合。"""
    b = sim.b
    opened_now = set()
    for _ in range(max_rounds):
        progressed = False
        observe(sim, k)
        to_flag, to_open = solver_rule_targets(
            k, {c for c in b.numbers if c not in sim.st.opened and c not in b.fossils},
            lambda c: neighbors(c, b.W, b.H))
        to_open |= {c for c in k.known_safe
                    if c not in sim.st.opened and c not in b.fossils}
        to_open = {c for c in to_open
                   if c not in sim.st.opened and c not in sim.st.flagged and c not in forbidden}
        to_flag = {c for c in to_flag
                   if c not in sim.st.flagged and c not in sim.st.opened and c not in forbidden}
        for c in sorted(to_open):
            if c in b.locked:
                continue
            if c in sim.st.opened:
                continue
            sim.open_cell(c, "solver")
            opened_now.add(c)
            progressed = True
        for c in sorted(to_flag):
            if c in b.locked or c in sim.st.flagged or c in k.known_mines:
                continue
            sim.toggle_flag(c, "solver")
            progressed = True
        if not progressed:
            break
    return opened_now


def corridor_cost(board, ra: RouteAnalysis, corridor) -> tuple:
    """走廊穿越成本：两端点间在膨胀带内走最短路的代价（§8 与参考过程动作数比）。
    每格成本 = 验真 2 + 开 1，加固墙 +2、锁 +1（盲插验真视角，§3 预检口径）。
    用 Dijkstra 而非全带总成本——真实穿越走最短路，全带总成本会高估 3 倍
    导致反例永不触发。返回 (cost, corridor_cells)。"""
    import heapq
    (i, j, _, _, _) = corridor
    p, q = ra.path[i], ra.path[j]
    cells = set(bresenham_line(p, q))
    for c in list(cells):
        for n in neighbors(c, board.W, board.H):
            cells.add(n)      # 膨胀：贴线格也能验真开进

    def cell_cost(c):
        if c in board.fossils:
            return None       # 化石不可通行
        w = 3
        if c in board.walls:
            w += 2
        if c in board.locked:
            w += 1
        return w

    start_cost = cell_cost(p)
    if start_cost is None:
        start_cost = 0        # 起点若为化石则从邻格算起（粗略）
    dist = {p: start_cost}
    prev = {}
    pq = [(start_cost, p)]
    while pq:
        d, c = heapq.heappop(pq)
        if d > dist.get(c, 10 ** 9):
            continue
        if c == q:
            break
        for n in neighbors(c, board.W, board.H):
            if n not in cells:
                continue
            cn = cell_cost(n)
            if cn is None:
                continue
            nd = d + cn
            if nd < dist.get(n, 10 ** 9):
                dist[n] = nd
                prev[n] = c
                heapq.heappush(pq, (nd, n))
    cost = dist.get(q, 10 ** 9)
    # 回溯最短穿越路径（repair 堵路径用）
    path = []
    if q in dist:
        c = q
        while c != p:
            path.append(c)
            c = prev.get(c, p)
        path.append(p)
        path.reverse()
    return cost, sorted(cells), path


def find_violations(board, ra: RouteAnalysis, acc: Acceptance, preopen: set,
                    reference, start_money: int = 0) -> list:
    """对一张候选盘做完整绕路检查。reference: play.run_reference 的结果（含快照）。
    若 reference.ok 为 False，只做几何走廊检查（主线都不通，跳段检查无意义）。"""
    vs: list[Violation] = []

    # ---- 0. 预开泄漏：烘焙预开揭开了"跳过整阶段"的带内格（§4.3 只查跳过重要折返，
    #      不把任何偏离都认定错误；溢进相邻下一阶段=正常探索溢出）----
    zone_stage = ra.label.get(ra.start, 1)
    leaked = [c for c in preopen
              if ra.label.get(c) is not None and ra.label[c] >= zone_stage + 2]
    if len(leaked) > acc.preopen_leak_max:
        leaked.sort(key=lambda c: ra.label[c])
        vs.append(Violation("preopen_leak", 1, leaked,
                            f"预开洪水跳阶段揭开 S{zone_stage+2}+ 的带内格 "
                            f"{len(leaked)} 格（容差 {acc.preopen_leak_max}）"))

    # ---- 1. 几何走廊成本（含在位墙/锁；§3 预检：盲插验真换雷无效）----
    # 相对口径（§8）：穿越成本 与 沿主线的参考动作数比较，不走线者须更贵
    for corridor in ra.corridors:
        cost, cells, _path = corridor_cost(board, ra, corridor)
        span_ops = (corridor[3]) * acc.route_op_overhead   # 沿主线 i→j 的参考动作数
        bar = acc.corridor_rel * span_ops
        if cost < bar:
            si = ra.stage_of_path[corridor[0]]
            sj = ra.stage_of_path[corridor[2]]
            vs.append(Violation("corridor", si, cells,
                                f"走廊 S{si}→S{sj} 穿越成本 {cost} < 主线参考 {bar:.0f}"
                                f"（跨段更便宜=低成本近路；信息屏障无效，需付费墙/锁或封印）"))

    if not reference.ok:
        return vs

    # ---- 2. 阶段快照上的反事实闭包（§5.2）----
    for (stage, st, k, wall_hp_snap) in reference.snapshots:
        sim2 = GameSim(board)
        sim2.st = st.clone()
        sim2.wall_hp = dict(wall_hp_snap)
        k2 = k.clone()
        next_stage = stage + 1
        forbidden = {c for c in ra.stage_cells.get(next_stage, set())}
        opened_now = closure_forbidden(sim2, k2, forbidden)
        # 更后段被揭开 = 跳过下一阶段的确定性绕路
        later = {c for c in opened_now
                 if ra.label.get(c) is not None and ra.label[c] >= next_stage + 1}
        if later:
            vs.append(Violation("skip", stage, sorted(later),
                                f"禁开 S{next_stage} 核心区后，闭包仍揭开 S{next_stage+1}+ 的 "
                                f"{len(later)} 格（确定性绕路）"))
        # 连开泄漏：单次洪水揭开 ≥3 个更后段格（§5.2 单独记录）
        for entry in sim2.st.log:
            if entry.get("kind") != "open":
                continue
            fl = [c for c in entry.get("opened", [])
                  if ra.label.get(c) is not None and ra.label[c] >= next_stage + 1]
            if len(fl) >= 3:
                vs.append(Violation("flood_leak", stage, sorted(fl),
                                    f"一次连开揭开 {len(fl)} 个后段格"))
                break

    # ---- 3. 远点开格：快照下确定安全的后段格（§13 测试项）----
    # 已被 2 的闭包覆盖（known_safe 会直接被开）；这里单独把"锚点级"后段接触点提出来便于修补定位
    return vs


def summarize(vs: list) -> dict:
    by_kind = {}
    for v in vs:
        by_kind.setdefault(v.kind, []).append(v)
    return {k: len(lst) for k, lst in by_kind.items()}
