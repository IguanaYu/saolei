# -*- coding: utf-8 -*-
"""RouteAnalyzer：把一条笔画变成探索约束（设计文档 §4）。

口径（§4.3 明确一条线能表达的范围）：
  * 笔画吸附到网格、合并手抖小折点，保留主要转弯与折返；
  * 阶段 = 相邻锚点之间的路段（内部分析标记，不在地图上加锁）；
  * 格子进度归属 = 最近路径格的所属阶段（贴近两段折返时保留多候选并报告）；
  * 验收口径在分析后即固定（§4.4），搜索阶段不得回头改。
"""
from __future__ import annotations

from dataclasses import dataclass, field


def cheb(a, b):
    return max(abs(a[0] - b[0]), abs(a[1] - b[1]))


def bresenham_line(p, q):
    """两格间超覆盖直线（含端点），用于笔画吸附"""
    x0, y0 = p
    x1, y1 = q
    cells = []
    dx, dy = abs(x1 - x0), abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx - dy
    x, y = x0, y0
    while True:
        cells.append((x, y))
        if x == x1 and y == y1:
            break
        e2 = 2 * err
        if e2 > -dy:
            err -= dy
            x += sx
        if e2 < dx:
            err += dx
            y += sy
    return cells


@dataclass
class RouteAnalysis:
    W: int
    H: int
    path: list = field(default_factory=list)          # 吸附后的有序路径格（去连续重复）
    anchors: list = field(default_factory=list)       # [(path_index, coord, kind)] kind: start/end/turn/reversal
    milestones: list = field(default_factory=list)    # 关键里程碑锚点索引（折返+终点，§4.4）
    corridors: list = field(default_factory=list)     # 几何跨段提名 [(i_idx, j_idx, dist_i, dist_j, cheb)]
    stage_of_path: list = field(default_factory=list) # 每个路径格所属阶段号（1..n_stage）
    label: dict = field(default_factory=dict)         # {(x,y): stage}（band 内；线外无标签）
    multi_label: dict = field(default_factory=dict)   # {(x,y): [stage,...]} 贴近两段的候选
    band: set = field(default_factory=set)            # 探索带（band_radius 内的格子）
    stage_cells: dict = field(default_factory=dict)   # {stage: set(带内格子)}
    start: tuple = None
    end: tuple = None
    n_stages: int = 0


def analyze(stroke_pts, W, H, band_radius=2, turn_angle_deg=60.0,
            reversal_gap=4, stage_gap=10, anchor_spacing=14) -> RouteAnalysis:
    """stroke_pts: 有方向的笔画点序列（格坐标，浮点可）。返回探索约束与固定验收口径。"""
    # ---- 1. 吸附：逐点取整 + 相邻点连线采样 + 去连续重复（§4.1 合并手抖）----
    path: list = []
    pts = [(int(round(p[0])), int(round(p[1]))) for p in stroke_pts]
    pts = [p for p in pts if 0 <= p[0] < W and 0 <= p[1] < H]
    assert len(pts) >= 2, "笔画至少两个点"
    for i in range(len(pts) - 1):
        seg = bresenham_line(pts[i], pts[i + 1])
        if i > 0:
            seg = seg[1:]
        for c in seg:
            if not path or c != path[-1]:
                path.append(c)
    # 折返同格：二次经过不解释成二次揭格——路径允许重复格（真实回访），进度照记（§4.3）

    # ---- 2. 锚点：起点/终点/明显转弯/折返/过长路段中间节点 ----
    anchors = [(0, path[0], "start"), (len(path) - 1, path[-1], "end")]
    for i in range(1, len(path) - 1):
        d1 = (path[i][0] - path[i - 1][0], path[i][1] - path[i - 1][1])
        d2 = (path[i + 1][0] - path[i][0], path[i + 1][1] - path[i][1])
        if d1 == d2:
            continue
        ang = _angle_between(d1, d2)
        if ang >= turn_angle_deg:
            anchors.append((i, path[i], "turn"))
    # 过长路段补中间锚点
    anchors.sort(key=lambda a: a[0])
    filled = []
    for (i1, c1, k1), (i2, c2, k2) in zip(anchors, anchors[1:]):
        filled.append((i1, c1, k1))
        step = i2 - i1
        if step > anchor_spacing:
            n_mid = step // anchor_spacing
            for m in range(1, n_mid + 1):
                mi = i1 + m * step // (n_mid + 1)
                filled.append((mi, path[mi], "mid"))
    filled.append(anchors[-1])
    anchors = filled

    # ---- 3. 折返/跨段提名：进度差大、空间近（§5.1 几何筛查）----
    # 非极大值抑制：同一条折返附近只保留一条提名，避免每个贴邻点对都立锚（阶段碎片化）
    corridors = []
    n = len(path)
    for i in range(0, n, 2):
        for j in range(i + stage_gap, n, 2):
            d = cheb(path[i], path[j])
            if d <= reversal_gap:
                corridors.append((i, j, i, j - i, d))
    corridors.sort(key=lambda t: (t[4], -t[3]))
    kept = []
    for cor in corridors:
        i, j = cor[0], cor[1]
        if all(min(abs(i - ki), abs(j - kj)) > 6 for (ki, kj, _, _, _) in kept):
            kept.append(cor)
    corridors = kept
    # 注意：走廊端点不立阶段锚（§4.1 阶段来自转弯/折返角/过长路段中点；走廊只是
    # 跨段威胁，由 verify 的走廊成本与快照反例检查处理）——立锚会把直路切成
    # 人工小阶段，接触判定碎片化。里程碑=转弯角+终点（真正的折返处）。

    # ---- 4. 阶段与进度归属 ----
    n_stages = len(anchors) - 1
    stage_of_path = [0] * n
    for k, (i, _, _) in enumerate(anchors):
        # 阶段 k+1 = [锚点k, 锚点k+1)；最后一个锚点不新开阶段，归入末段（阶段号钳到 n_stages）
        stage_id = min(k + 1, n_stages)
        nxt = anchors[k + 1][0] if k + 1 < len(anchors) else n
        for t in range(i, nxt):
            stage_of_path[t] = stage_id
    # 格子标签：最近路径格的阶段；带内才算；贴两段保留候选（§4.2）
    label, multi, band, stage_cells = {}, {}, set(), {k: set() for k in range(1, n_stages + 1)}
    for y in range(H):
        for x in range(W):
            c = (x, y)
            best = None
            cands = []
            for t, pc in enumerate(path):
                d = cheb(c, pc)
                if d <= band_radius:
                    cands.append((d, stage_of_path[t]))
                if best is None or d < best[0]:
                    best = (d, stage_of_path[t])
            if not cands:
                continue
            if cands:
                nearest_d = min(d for d, _ in cands)
                near_stages = sorted({s for d, s in cands if d <= nearest_d + 1})
                # 归属取近邻中最早阶段（保守：早阶段归属对"提前展开"更宽容）
                label[c] = near_stages[0]
                if len(near_stages) > 1:
                    multi[c] = near_stages
                band.add(c)
                # 接触核心区 = 路线两侧 1 格（§4.4"核心区"；半径 2 的 band 是探索带）
                if nearest_d <= 1:
                    stage_cells[label[c]].add(c)

    ra = RouteAnalysis(W=W, H=H, path=path, anchors=anchors,
                       milestones=[i for i, c, kind in anchors if kind in ("turn", "end")],
                       corridors=corridors, stage_of_path=stage_of_path, label=label,
                       multi_label=multi, band=band, stage_cells=stage_cells,
                       start=path[0], end=path[-1], n_stages=n_stages)
    return ra


def _angle_between(d1, d2):
    import math
    n1 = (d1[0] ** 2 + d1[1] ** 2) ** 0.5
    n2 = (d2[0] ** 2 + d2[1] ** 2) ** 0.5
    if n1 == 0 or n2 == 0:
        return 0.0
    cos = (d1[0] * d2[0] + d1[1] * d2[1]) / (n1 * n2)
    cos = max(-1.0, min(1.0, cos))
    return math.degrees(math.acos(cos))


# ---- §4.4 验收口径（分析后固定，搜索不得回头改）----

@dataclass
class Acceptance:
    """生成前固定的验收口径"""
    core_frac: float = 0.5          # 阶段接触条件：锚点揭开 或 核心区≥此比例揭开
    normal_seeds: int = 8           # 正常策略平局择序种子数
    normal_pass: int = 6            # 至少多少条按关键里程碑顺序推进
    corridor_rel: float = 0.75      # 走廊成本 < 此比例×路线段参考成本 = 低成本跨段（§8 相对口径）
    route_op_overhead: float = 1.2  # 路线段每格动作开销（推理/和弦/旗等摊销）
    probe_budget: int = 4           # 参考过程每阶段探针预算（个）
    verify_budget: int = 8          # 参考过程每阶段验旗预算（次）
    preopen_leak_max: int = 6       # 预开揭开阶段≥2 的带内格容差（零星渗出不算泄漏）

    def stage_contact(self, ra: RouteAnalysis, opened: set, stage: int) -> bool:
        """阶段接触判定：锚点揭开 或 核心区至少 core_frac 揭开"""
        for i, c, _kind in ra.anchors:
            if ra.stage_of_path[i] == stage and c in opened:
                return True
        cells = ra.stage_cells.get(stage, set())
        if not cells:
            return True
        touched = sum(1 for c in cells if c in opened)
        return touched >= self.core_frac * len(cells)


def milestone_order_ok(ra: RouteAnalysis, acc: Acceptance, opened: set) -> tuple:
    """返回 (是否按序推进到最后一个里程碑, 完成的最高里程碑序号)；无接触=0"""
    last = 0
    for m_idx in sorted(ra.milestones):
        stage = ra.stage_of_path[m_idx]
        if acc.stage_contact(ra, opened, stage):
            last = stage
        else:
            break
    return (last == ra.n_stages, last)
