# -*- coding: utf-8 -*-
"""CLI：python -m tools.route_gen.cli --stroke tools/route_gen/strokes/s16.json [--out 目录]

笔画 JSON 格式：{"points": [[x, y], ...], "name": "S16x16"}
关卡配置 JSON（可选 --config）：对齐 GenConfig 字段；缺省用 16×16/40 雷。
产出（--out 目录，默认 tools/route_gen/out/）：
  board_fixed.json        固定盘数据（与 apply_fixed_board 同构）
  board_fixed.gd.snippet  FixedBoards 格式 GDScript 片段
  report.md               生成报告（阶段/锚点/走廊/试玩/反例/验收清单）
  preview.txt             ASCII 预览
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from tools.route_gen.generate import GenConfig, generate
from tools.route_gen.export_gd import gdscript_block, ascii_board, to_fixed_board_dict
from tools.route_gen.route import Acceptance


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stroke", required=True)
    ap.add_argument("--config", default="")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--out", default="")
    args = ap.parse_args()

    with open(args.stroke, encoding="utf-8") as f:
        stroke = json.load(f)
    pts = [tuple(p) for p in stroke["points"]]
    name = stroke.get("name", "ROUTE")

    cfg = GenConfig()
    if args.config:
        with open(args.config, encoding="utf-8") as f:
            c = json.load(f)
        for k, v in c.items():
            if k == "acc":
                cfg.acc = Acceptance(**v)
            elif hasattr(cfg, k):
                setattr(cfg, k, v)
    # 手放雷（§2 摆雷模式）：笔画 JSON 里 "fixed_mines": [[x,y],...] 作为必放硬约束
    if stroke.get("fixed_mines"):
        cfg.fixed_mines = tuple(tuple(p) for p in stroke["fixed_mines"])

    t0 = time.time()
    ra, cand, conflicts = generate(pts, cfg, seed=args.seed)
    dt = time.time() - t0

    out = args.out or os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
    os.makedirs(out, exist_ok=True)

    if cand is None:
        print("生成失败：无候选")
        sys.exit(1)

    # ---- Godot 规则重放验收（§12：正式候选最终由 Godot 规则重放）----
    from tools.route_gen.play import run_reference
    from tools.route_gen import parity as parity_mod
    board_obj = cand.board(cfg)
    ref = run_reference(board_obj, cand.preopen, ra, cfg.acc, start_money=cfg.start_money)
    actions = []
    for entry in ref.action_log:
        kind = entry.get("kind") or entry.get("type")
        if entry.get("type") == "action" and kind in ("open", "flag", "unflag",
                                                      "chord", "probe", "clear_lock"):
            actions.append({"kind": "flag" if kind == "unflag" else kind,
                            "coord": list(entry["coord"])})
        elif entry.get("type") in ("peel", "mine_stepped"):
            actions.append({"kind": "open", "coord": list(entry["coord"])})

    board_dict = to_fixed_board_dict(cand, cfg, ra)
    seals_json = [{"id": s["id"], "cells": [list(c) for c in s["cells"]],
                   "trigger": list(s["trigger"])} for s in board_dict["seals"]]
    godot_ok, godot_diffs = parity_mod.verify_board_scenario(
        {"w": cfg.W, "h": cfg.H,
         "mines": [list(m) for m in board_dict["mines"]],
         "preopen": [list(p) for p in board_dict["preopen"]],
         "base": list(board_dict["base"]),
         "fossils": [list(o) for o in board_dict["fossils"]],
         "walls": [list(x) for x in board_dict["walls"]],
         "locked": [list(x) for x in board_dict["locked"]],
         "seals": seals_json},
        actions, cfg.start_money)
    print(f"[Godot重放] {'PASS' if godot_ok else 'FAIL'}（{len(actions)} 条动作）")
    for d in godot_diffs[:5]:
        print("   -", d)
    with open(os.path.join(out, "board_fixed.json"), "w", encoding="utf-8") as f:
        json.dump({"name": name, "config": {
            "w": cfg.W, "h": cfg.H, "mine_count": cfg.mine_count,
            "start_money": cfg.start_money,
        }, "board": {
            "w": cfg.W, "h": cfg.H,
            "mines": [list(m) for m in board_dict["mines"]],
            "preopen": [list(p) for p in board_dict["preopen"]],
            "base": list(board_dict["base"]),
            "fossils": [list(o) for o in board_dict["fossils"]],
            "walls": [list(x) for x in board_dict["walls"]],
            "locked": [list(x) for x in board_dict["locked"]],
            "seals": seals_json,
        }}, f, ensure_ascii=False, indent=1)
    with open(os.path.join(out, "board_fixed.gd.snippet"), "w", encoding="utf-8") as f:
        f.write(gdscript_block(name.upper(), cand, cfg, ra, note=(
            f"路径驱动生成器 v1 烘焙（seed={args.seed}，笔画 {name}）："
            f"阶段 {ra.n_stages}、走廊提名 {len(ra.corridors)}、"
            f"正常策略 {cand.normal_pass}/{cfg.acc.normal_pass}、"
            f"加固墙 {len(cand.walls)}、锁 {len(cand.locked)}")))
    with open(os.path.join(out, "preview.txt"), "w", encoding="utf-8") as f:
        f.write(ascii_board(cand, cfg, ra) + "\n")
    with open(os.path.join(out, "report.md"), "w", encoding="utf-8") as f:
        f.write(build_report(name, cfg, ra, cand, conflicts, dt, args.seed,
                             godot_ok, len(actions), ref.ops))

    print(f"[完成] {dt:.1f}s → {out}")
    print(ascii_board(cand, cfg, ra))


def build_report(name, cfg, ra, cand, conflicts, dt, seed,
                 godot_ok=None, n_actions=0, ref_ops=0) -> str:
    L = []
    L.append(f"# 路径驱动地图生成器 · 生成报告（{name}）\n")
    L.append(f"- 日期：2026-10-23；seed={seed}；耗时 {dt:.1f}s")
    L.append(f"- 棋盘：{cfg.W}×{cfg.H}，雷数 {cfg.mine_count}，起始资金 {cfg.start_money}"
             + (f"，**手放雷 {len(cfg.fixed_mines)} 颗（硬约束，重生成保留）**" if cfg.fixed_mines else ""))
    L.append(f"- 阶段：{ra.n_stages}（锚点 {len(ra.anchors)} 个，里程碑 {len(ra.milestones)} 个）")
    L.append(f"- 几何走廊提名：{len(ra.corridors)} 条（§5.1）")
    L.append(f"- 探索带：{len(ra.band)} 格（半径 {cfg.band_radius}）；带外保持开放（§1 取舍 2）")
    L.append(f"- 加固墙 {len(cand.walls)} / 锁 {len(cand.locked)} / 化石 {len(cfg.fossil_origins)} 组\n")
    L.append("## 验收结果（§8 筛选口径）\n")
    L.append(f"- 参考过程：{'通过（无强制猜雷）' if cand.ref_ok else '未通过：' + cand.stuck}"
             f"（{ref_ops} 有效动作）")
    L.append(f"- 正常策略（不读线，{cfg.acc.normal_seeds} 种子）："
             f"{cand.normal_pass}/{cfg.acc.normal_pass} 按里程碑顺序推进")
    L.append(f"- 反例类型：{sorted({v.kind for v in cand.violations}) or '无'}")
    if godot_ok is not None:
        L.append(f"- **Godot 规则重放验收（§12）：{'通过' if godot_ok else '未通过'}"
                 f"（{n_actions} 条动作在真实 Grid 上重放，终态+奖励序列逐项比对）**")
    if conflicts:
        L.append(f"- **未找到全合格解**，冲突类型：{conflicts}（§7.4：不静默加机关/不裁地图）\n")
    L.append("## 反例明细\n")
    for v in cand.violations[:20]:
        L.append(f"- `{v.label()}` {v.detail}（涉及 {len(v.cells)} 格）")
    if not cand.violations:
        L.append("- 无")
    L.append("\n## 边界声明（§13：未实测不写成已达到）\n")
    L.append("- 本报告的\"正常策略\"为闭包+探针/验真档位的模拟玩家，未含机器人行走/购买/CD 计时；")
    L.append("- 激光、精灵、敌人、覆盖墙未入模拟（§12 开发顺序第 5 步，明确未验证）；")
    L.append("- 成功率为本次单张搜索结果，不代表方法总体成功率；")
    L.append("- 正式候选仍需 Godot 规则重放验收（tests/route_gen_parity.gd 对拍已过，"
             "但该验收针对本盘的完整试玩重放待接）。")
    return "\n".join(L)


if __name__ == "__main__":
    main()
