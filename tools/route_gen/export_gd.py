# -*- coding: utf-8 -*-
"""ReportExporter：固定盘导出（FixedBoards GDScript 格式）+ ASCII 预览 + JSON。"""
from __future__ import annotations

from tools.route_gen.generate import Candidate, GenConfig
from tools.route_gen.route import RouteAnalysis


def to_fixed_board_dict(cand: Candidate, cfg: GenConfig, ra: RouteAnalysis) -> dict:
    """与 scripts/data/fixed_boards.gd 的 data 结构同构（apply_fixed_board 可直接吃）"""
    return {
        "mines": sorted(cand.mines),
        "preopen": sorted(cand.preopen),
        "base": ra.start,
        "fossils": sorted(list(cfg.fossil_origins) + sorted(cand.fossils)),
        "walls": sorted(cand.walls),
        "locked": sorted(cand.locked),
    }


def gdscript_block(name: str, cand: Candidate, cfg: GenConfig, ra: RouteAnalysis,
                   note: str = "") -> str:
    d = to_fixed_board_dict(cand, cfg, ra)

    def vlist(items):
        return ", ".join(f"Vector2i({x}, {y})" for (x, y) in items)

    lines = [
        f"const {name} := {{",
        f'\t"mines": [{vlist(d["mines"])}],',
        f'\t"preopen": [{vlist(d["preopen"])}],',
        f'\t"base": Vector2i({d["base"][0]}, {d["base"][1]}),',
    ]
    if d["fossils"]:
        lines.append(f'\t"fossils": [{vlist(d["fossils"])}],')
    if d["walls"]:
        lines.append(f'\t"walls": [{vlist(d["walls"])}],')
    if d["locked"]:
        lines.append(f'\t"locked": [{vlist(d["locked"])}],')
    lines.append("}")
    if note:
        lines.insert(0, "## " + note.replace("\n", "\n## "))
    return "\n".join(lines)


def ascii_board(cand: Candidate, cfg: GenConfig, ra: RouteAnalysis) -> str:
    """字符画：# 未开墙 M 雷 W 加固墙 L 锁 F 化石 . 已开/预开 @ 基地 * 路线（未开段）"""
    d = {(x, y): "." for y in range(cfg.H) for x in range(cfg.W)}
    route = set(ra.path)
    for c in cand.preopen:
        d[c] = "."
    for c in cand.mines:
        if c not in cand.preopen:
            d[c] = "M"
    for c in cand.walls:
        if c not in cand.preopen and c not in cand.mines:
            d[c] = "W"
    for c in cand.locked:
        if c not in cand.preopen:
            d[c] = "L"
    for o in list(cfg.fossil_origins) + sorted(cand.fossils):
        for dy in (0, 1):
            for dx in (0, 1):
                c = (o[0] + dx, o[1] + dy)
                if c in d:
                    d[c] = "F"
    for c in route:
        if c not in cand.preopen:
            if d[c] in "MWL":
                continue          # 真值优先显示
            d[c] = "*"
    d[ra.start] = "@"
    rows = []
    for y in range(cfg.H):
        rows.append("".join(d[(x, y)] for x in range(cfg.W)))
    return "\n".join(rows)
