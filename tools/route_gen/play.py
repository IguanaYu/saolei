# -*- coding: utf-8 -*-
"""PlayerSimulator：三种试玩记录（设计文档 §9）。

  * run_reference  参考过程：知道设计线，证明"存在一种符合预期的推进过程"，
                    不允许强制猜雷（§13），缺信息时用每阶段预算内的探针/验旗。
  * run_normal     正常试玩：不读取路线（不 import route 对象选格），在选定策略档位下
                    靠公开线索推进；路线只用于事后评分（§9.1）。
  * 盲插验真 / 探针是有成本动作，显式计数（§5.3 成本分开记录）。

v1 边界：闭包=玩家点击+机器人双规则的合并推理能力（同 ch02 找盘脚本"双规则免费"
口径）；不模拟机器人行走耗时/购买商店/CD 计时，操作数作为成本口径单独记录。
"""
from __future__ import annotations

from dataclasses import dataclass, field

from tools.route_gen.rules import (Board, GameSim, Knowledge, PROBE_PRICE,
                                   deterministic_closure, observe,
                                   solver_rule_targets, neighbors)
from tools.route_gen.route import Acceptance, RouteAnalysis


@dataclass
class RunResult:
    ok: bool
    opened: set = field(default_factory=set)
    ops: int = 0                      # 有效动作数（开/标/和弦/清锁/削层/探针/验旗）
    money_spent_probes: int = 0
    stuck_reason: str = ""
    stuck_stage: int = 0
    frontier_cell: tuple = None       # 卡住时该阶段带内贴已开区的未开格（修补定位用）
    milestone_reached: int = 0        # 按序推进到的最高里程碑（阶段号）
    jumped: bool = False              # 向前跳段：后段里程碑在未达前一段时先被接触
    collapsed: int = 0                # 盲开踩雷数（正常策略风险口径）
    stage_contact_ops: dict = field(default_factory=dict)  # {stage: 到达时累计 ops}
    snapshots: list = field(default_factory=list)  # [(stage, SimState, Knowledge, wall_hp)] 参考过程专供绕路检查
    action_log: list = field(default_factory=list)  # 原始动作序列（Godot 重放验收用）
    rounds: int = 0


def _blind_verify(sim: GameSim, k: Knowledge, c) -> bool:
    """验真通道：插旗→看奖励反馈→未中则撤旗并记 known_safe。返回是否中雷。
    语义=main.gd 首次正确旗即时 +5 的可观察反馈（§3 表：合法信息获取方式）。"""
    sim.toggle_flag(c, "player")
    fired = sim.st.verified.get(c, False)
    if not fired:
        sim.toggle_flag(c, "player")   # 未中=非雷：撤旗，known_safe 由 observe 记录
    return fired


def _best_probe_center(sim: GameSim, k: Knowledge, prefer=None, prefer_bonus=3):
    """信息增益最大的探针中心：3×3 内未知关闭格数最多（prefer 内格加 bonus）"""
    best, best_gain = None, -1
    closed = {c for c in sim.b.numbers
              if c not in sim.st.opened and c not in sim.b.fossils
              and not sim.is_sealed(c)}
    unknown = closed - k.known_mines - k.known_safe
    for c in closed:
        gain = sum(1 for n in neighbors(c, sim.b.W, sim.b.H) if n in unknown)
        if prefer and c in prefer:
            gain += prefer_bonus
        if gain > best_gain:
            best, best_gain = c, gain
    return best if best_gain > 0 else None


def _frontier_cells(sim: GameSim):
    """工作前沿：8 邻贴已开区的关闭格（玩家/机器人的自然操作面，§3 机器人作业口径）；
    封印格不可操作，不在前沿动作面内（§7.3）"""
    b = sim.b
    out = set()
    for c in b.numbers:
        if c in sim.st.opened or c in b.fossils or sim.is_sealed(c):
            continue
        if any(n in sim.st.opened for n in neighbors(c, b.W, b.H)):
            out.add(c)
    return out


def _verify_target(sim: GameSim, k: Knowledge, core: set):
    """验旗目标：优先本阶段核心区里未知的关闭格（定向解卡），否则通用启发"""
    for c in sorted(core):
        if (c not in sim.st.opened and c not in k.known_mines
                and c not in k.known_safe and c not in sim.b.fossils
                and c not in sim.b.locked and not sim.is_sealed(c)):
            return c
    return _best_probe_center(sim, k, prefer=core)


def _frontier_verify_target(sim: GameSim, k: Knowledge):
    """正常策略验旗目标：限制在前沿（真实玩家在已开区边上作业，不隔空全图验）"""
    frontier = _frontier_cells(sim)
    unknown = frontier - k.known_mines - k.known_safe
    if unknown:
        return sorted(unknown)[0]
    return _best_probe_center(sim, k)


def run_reference(board: Board, preopen: set, ra: RouteAnalysis, acc: Acceptance,
                  start_money: int = 0, max_rounds: int = 400) -> RunResult:
    """参考过程：按阶段推进；每阶段探针/验旗预算用尽仍无进展=失败（不猜雷）"""
    sim = GameSim(board, start_money=start_money)
    sim.st.opened |= set(preopen)
    k = Knowledge(total_mines=len(board.mines))
    observe(sim, k)
    res = RunResult(ok=False)
    probes_left = {s: acc.probe_budget for s in range(1, ra.n_stages + 1)}
    verify_left = {s: acc.verify_budget for s in range(1, ra.n_stages + 1)}

    for stage in range(1, ra.n_stages + 1):
        band = ra.stage_cells.get(stage, set())
        guard = 0
        while not acc.stage_contact(ra, sim.st.opened, stage):
            guard += 1
            if guard > max_rounds:
                res.stuck_stage = stage
                res.frontier_cell = _frontier_of_stage(sim, ra, stage)
                res.stuck_reason = f"阶段{stage}超过轮次上限"
                return _finish(res, sim, k, stage)
            before = (len(sim.st.opened), len(sim.st.flagged))
            deterministic_closure(sim, k, max_rounds=8)
            res.ops += (len(sim.st.opened) - before[0]) + (len(sim.st.flagged) - before[1])
            if acc.stage_contact(ra, sim.st.opened, stage):
                break
            # 免费闭包停摆 → 预算内定向援助（探针瞄核心区边、验旗直接验核心未知格）
            if probes_left[stage] > 0 and sim.st.money >= PROBE_PRICE:
                center = _best_probe_center(sim, k, prefer=band)
                if center is not None:
                    sim.probe(center, "player")
                    probes_left[stage] -= 1
                    res.money_spent_probes += PROBE_PRICE
                    res.ops += 1
                    continue
            if verify_left[stage] > 0:
                target = _verify_target(sim, k, band)
                if target is not None and target not in k.known_mines:
                    _blind_verify(sim, k, target)
                    verify_left[stage] -= 1
                    res.ops += 2
                    continue
            deterministic_closure(sim, k, max_rounds=8)
            if not acc.stage_contact(ra, sim.st.opened, stage):
                res.stuck_stage = stage
                res.frontier_cell = _frontier_of_stage(sim, ra, stage)
                res.stuck_reason = f"阶段{stage}缺信息：闭包停摆且探针/验旗预算用尽"
                return _finish(res, sim, k, stage)
        res.stage_contact_ops[stage] = res.ops
        res.snapshots.append((stage, sim.st.clone(), k.clone(), dict(sim.wall_hp)))
        res.milestone_reached = stage
    res.ok = True
    return _finish(res, sim, k, ra.n_stages)


def run_normal(board: Board, preopen: set, ra: RouteAnalysis, acc: Acceptance,
               seed: int, style: str = "closure", start_money: int = 0,
               max_rounds: int = 400) -> RunResult:
    """正常试玩：不读路线。style: closure=纯双规则玩家 / probe=卡住买探针 /
    verify=卡住盲插验真 / frontier=卡住前沿盲开（真实扫雷玩家，赌洪水，§9.2 随机盲开口径）。
    平局择序由 seed 决定（§4.4 的 8 种子口径）。"""
    import random
    rnd = random.Random(seed)
    sim = GameSim(board, start_money=start_money)
    sim.st.opened |= set(preopen)
    k = Knowledge(total_mines=len(board.mines))
    observe(sim, k)
    res = RunResult(ok=False)
    b = sim.b

    for res.rounds in range(1, max_rounds + 1):
        before = len(sim.st.opened)
        # ---- 一轮：双规则闭包（平局择序=seed 打乱），逐动作检查里程碑顺序 ----
        while True:
            observe(sim, k)
            to_flag, to_open = solver_rule_targets(
                k, {c for c in b.numbers if c not in sim.st.opened and c not in b.fossils},
                lambda c: neighbors(c, b.W, b.H))
            to_open |= {c for c in k.known_safe
                        if c not in sim.st.opened and c not in b.fossils}
            sealed_now = sim.active_seal_cells()   # 封印格不产生动作（§7.3）
            to_open = {c for c in to_open if c not in sim.st.opened and c not in sim.st.flagged
                       and c not in sealed_now}
            to_flag = {c for c in to_flag if c not in sim.st.flagged
                       and c not in sim.st.opened and c not in k.known_mines
                       and c not in sealed_now}
            if not to_open and not to_flag:
                break
            for c in sorted(to_open, key=lambda _: rnd.random()):
                if c not in sim.st.opened and c not in sim.st.flagged and c not in b.locked:
                    sim.open_cell(c, "player")
                    res.ops += 1
            for c in sorted(to_flag, key=lambda _: rnd.random()):
                if c not in sim.st.flagged and c not in sim.st.opened and c not in b.locked:
                    sim.toggle_flag(c, "player")
                    res.ops += 1
        _track_milestones(res, ra, acc, sim.st.opened)
        if len(sim.st.opened) == before:
            # ---- 停摆：按策略档位决定是否用成本动作（探针/验旗都在前沿作业）----
            acted = False
            if style == "probe" and sim.st.money >= PROBE_PRICE:
                frontier = _frontier_cells(sim)
                center = _best_probe_center(sim, k, prefer=frontier, prefer_bonus=4)
                if center is not None:
                    sim.probe(center, "player")
                    res.money_spent_probes += PROBE_PRICE
                    res.ops += 1
                    acted = True
            elif style == "verify":
                target = _frontier_verify_target(sim, k)
                if target is not None and target not in k.known_mines:
                    _blind_verify(sim, k, target)
                    res.ops += 2
                    acted = True
            elif style == "frontier":
                # 真实玩家手感：闭包停摆就点一个前沿关闭格（可能是雷：坍塌继续）
                frontier = sorted(_frontier_cells(sim) - k.known_mines - k.known_safe)
                if frontier:
                    pick = frontier[rnd.randrange(len(frontier))]
                    st, _opened = sim.open_cell(pick, "player")
                    res.ops += 1
                    if st == "mine":
                        res.collapsed += 1
                    acted = True
            if not acted:
                remaining = sum(1 for c in b.numbers
                                if c not in sim.st.opened and c not in b.fossils)
                res.stuck_reason = f"无确定动作停摆（剩 {remaining} 格，策略={style}）"
                break
        safe_left = sum(1 for c in b.numbers
                        if c not in sim.st.opened and c not in b.fossils)
        if safe_left == 0:
            res.ok = True
            break
    return _finish(res, sim, k, res.milestone_reached)


def _track_milestones(res: RunResult, ra: RouteAnalysis, acc: Acceptance, opened: set):
    """事后评分（路线不参与选格）：按序推进到的最高里程碑 + 向前跳段检测。
    跳段 = 第 k+2 个及以后的里程碑先于 k+1 被接触（§4.4 跳过一个重要折返才算错）。"""
    while res.milestone_reached < ra.n_stages:
        nxt = res.milestone_reached + 1
        if acc.stage_contact(ra, opened, nxt):
            res.milestone_reached = nxt
        else:
            break
    for m in range(res.milestone_reached + 2, ra.n_stages + 1):
        if acc.stage_contact(ra, opened, m):
            res.jumped = True
            break


def normal_seed_pass(res: RunResult, ra: RouteAnalysis) -> bool:
    """单个正常策略种子的合格口径（v1 校准，实施文档记录）：
    没有向前跳段，且按序推进到至少一半里程碑（保守玩家停摆不算跳段，
    但要体现路线确实把信息流往前带）。"""
    return (not res.jumped) and res.milestone_reached >= max(2, ra.n_stages // 2)


def _frontier_of_stage(sim: GameSim, ra: RouteAnalysis, stage: int):
    """该阶段带内、贴着已开区的未开格（8 邻有已开格）；无则任取带内未开格"""
    band = ra.stage_cells.get(stage, set())
    adj = [c for c in band if c not in sim.st.opened
           and any(n in sim.st.opened for n in neighbors(c, sim.b.W, sim.b.H))]
    if adj:
        return sorted(adj)[0]
    alt = [c for c in band if c not in sim.st.opened]
    return sorted(alt)[0] if alt else None


def _finish(res: RunResult, sim: GameSim, k: Knowledge, stage: int) -> RunResult:
    res.opened = set(sim.st.opened)
    res.action_log = [dict(e) for e in sim.st.log
                      if e.get("type") in ("action", "peel", "mine_stepped")]
    return res
