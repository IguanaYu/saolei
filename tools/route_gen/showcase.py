# -*- coding: utf-8 -*-
"""地形可能性总览数据导出：8 种笔画形状逐案例跑真实 analyze + generate，
导出 showcase.json 供交互式总览页（对话内可视化）展示。
只读使用现有管线，不改任何现有模块；产物在 out/（gitignore 外）。

用法：python tools/route_gen/showcase.py
"""
from __future__ import annotations

import io
import json
import os
import sys
import time
import contextlib

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from tools.route_gen.route import analyze, cheb
from tools.route_gen.generate import GenConfig, generate

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")

# 8 案例：名称 / 笔画 / 每案例配置 / 定位标签
CASES = [
    ("S三横", [[2, 2], [13, 2], [13, 8], [2, 8], [2, 14], [13, 14]],
     {}, "基准形状 gap6", "可行"),
    ("近距S", [[2, 2], [13, 2], [13, 7], [2, 7], [2, 12], [13, 12]],
     {}, "折返间距 5——封印机制的代表场景", "可行·用封印"),
    ("L形", [[2, 2], [13, 2], [13, 13]],
     {}, "单折返直角", "可行"),
    ("U形", [[2, 2], [2, 13], [13, 13], [13, 2]],
     {}, "两侧折返", "可行"),
    ("环形", [[2, 2], [13, 2], [13, 13], [2, 13], [2, 2]],
     {}, "闭合回路（终点=起点）", "可行"),
    ("对角折线", [[1, 1], [5, 4], [9, 1], [13, 4], [9, 8], [5, 11], [1, 8], [1, 13]],
     {}, "斜向推进", "弱引导边界"),
    ("螺旋", [[2, 2], [13, 2], [13, 13], [2, 13], [2, 5], [10, 5], [10, 10], [5, 10], [5, 7], [8, 7]],
     {}, "多走廊密集路线——超过 2 组封印预算", "冲突边界"),
    ("直线", [[2, 2], [13, 13]],
     {}, "无折返=单阶段，没有可引导的结构", "弱引导边界"),
]


def export_case(name, pts, cfg_over, note, tag, seed=1):
    t0 = time.time()
    pts_t = [tuple(p) for p in pts]
    cfg = GenConfig(**cfg_over)
    ra = analyze(pts_t, cfg.W, cfg.H, band_radius=cfg.band_radius)

    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        cand, conflicts = None, []
        try:
            ra2, cand, conflicts = generate(pts_t, cfg, seed=seed)
        except Exception as e:   # 雷数放不下等构造错误也如实记录
            conflicts = [{"kind": "error", "detail": str(e)}]

    # 几何跨段提名 + 段间距过近点对（§4.3 预警）
    gaps = []
    n = len(ra.path)
    for i in range(0, n, 2):
        for j in range(i + 10, n, 2):
            d = cheb(ra.path[i], ra.path[j])
            if d <= 4:
                gaps.append([i, j, d])
                if len(gaps) >= 6:
                    break
        if len(gaps) >= 6:
            break

    case = {
        "name": name, "note": note, "tag": tag,
        "stroke": pts, "seed": seed,
        "gen_seconds": round(time.time() - t0, 1),
        "analysis": {
            "path": [list(c) for c in ra.path],
            "anchors": [[i, list(c), kind, ra.stage_of_path[i]] for i, c, kind in ra.anchors],
            "corridors": [[ra.path[i][0], ra.path[i][1], ra.path[j][0], ra.path[j][1],
                           ra.stage_of_path[i], ra.stage_of_path[j]]
                          for (i, j, si, gap, d) in ra.corridors],
            "n_stages": ra.n_stages,
            "band_count": len(ra.band),
            "gap_warnings": gaps,
        },
        "gen": None,
    }
    if cand is not None:
        board = cand.board(cfg)
        case["gen"] = {
            "mines": [list(m) for m in sorted(cand.mines)],
            "preopen": [list(p) for p in sorted(cand.preopen)],
            "walls": [list(w) for w in sorted(cand.walls)],
            "locked": [list(l) for l in sorted(cand.locked)],
            "fossils": [list(o) for o in sorted(list(cfg.fossil_origins) + sorted(cand.fossils))],
            "seals": [{"id": sid, "cells": [list(c) for c in sorted(g["cells"])],
                       "trigger": list(g["trigger"])} for sid, g in sorted(cand.seals.items())],
            "base": list(ra.start),
            "ref_ok": cand.ref_ok,
            "normal_pass": cand.normal_pass,
            "conflicts": sorted({v.kind for v in cand.violations}) if cand.violations else [],
            "stuck": cand.stuck,
        }
    return case


def main():
    cases = []
    for (name, pts, cfg_over, note, tag) in CASES:
        print(f"[showcase] {name} …", flush=True)
        cases.append(export_case(name, pts, cfg_over, note, tag))
        print(f"  {cases[-1]['gen_seconds']}s tag={tag} "
              f"conflicts={cases[-1]['gen']['conflicts'] if cases[-1]['gen'] else 'ERR'}", flush=True)
    data = {"board": {"w": 16, "h": 16, "mine_count": 40}, "cases": cases}
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "showcase.json"), "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
    size = os.path.getsize(os.path.join(OUT, "showcase.json"))
    print(f"OK → out/showcase.json（{size // 1024} KB，{len(cases)} 案例）")


if __name__ == "__main__":
    main()
