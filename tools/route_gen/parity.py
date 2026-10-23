# -*- coding: utf-8 -*-
"""对拍驱动：生成随机场景 → Python 模拟预期 → 调 Godot 真实 Grid 执行 → 逐项比对。

用法（仓库根目录）：
    python tools/route_gen/parity.py            # 生成+执行+比对 5 个种子
    python tools/route_gen/parity.py --seeds 1 2 3

覆盖机制：开格/洪水/正确旗奖励/验旗撤旗/和弦/多层墙削层/锁/化石/探针/踩雷坍塌。
场景与结果文件在 tools/route_gen/out/（.gitignore 外，运行产物）。
"""
from __future__ import annotations

import json
import os
import random
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from tools.route_gen.rules import Board, GameSim, Knowledge, deterministic_closure, observe, \
    solver_rule_targets, neighbors, PROBE_PRICE

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(REPO, "tools", "route_gen", "out")
GODOT = r"E:\godot\Godot_v4.6.1-stable_win64_console.exe"


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


def make_scenario(seed: int, w=16, h=16, n_mines=30, n_actions=90):
    rnd = random.Random(seed)
    base = (rnd.randint(3, w - 4), rnd.randint(3, h - 4))
    for _ in range(200):  # 找一个预开后不至于全开的雷阵
        zone = {(x, y) for x in range(base[0] - 1, base[0] + 2)
                for y in range(base[1] - 1, base[1] + 2)}
        cells = [(x, y) for y in range(h) for x in range(w)]
        rest = [c for c in cells if c not in zone]
        mines = set(rnd.sample(rest, n_mines))
        board = Board.build(w, h, mines, base=base)
        pre = bake_preopen(board, zone)
        if len(pre) <= w * h * 0.45:
            break
    else:
        raise RuntimeError("200 次都找不到合适雷阵")
    # 化石 2×2：不与雷/预开/基地重叠（apply_fixed_board 拒铺口径）
    fossils = []
    used = set(pre) | mines | {base}
    tries = 0
    while len(fossils) < 2 and tries < 400:
        tries += 1
        o = (rnd.randint(0, w - 2), rnd.randint(0, h - 2))
        block = {(o[0] + dx, o[1] + dy) for dx in (0, 1) for dy in (0, 1)}
        if block & used:
            continue
        fossils.append(o)
        used |= block

    board = Board.build(w, h, mines, fossils_origins=fossils, base=base)
    preopen = bake_preopen(board, zone)
    # 重算数字后化石格确定非雷；洪水重算
    used = set(preopen) | mines | {base} | {c for o in fossils for c in
                                            [(o[0] + dx, o[1] + dy) for dx in (0, 1) for dy in (0, 1)]}
    # 加固墙：6 个未开格（可在雷上——外壳不泄漏真值）
    wall_candidates = [c for c in board.numbers if c not in used]
    walls = set(rnd.sample(wall_candidates, min(6, len(wall_candidates))))
    used |= walls
    # 锁：2 个未开非化石格
    lock_candidates = [c for c in board.numbers
                       if c not in used and c not in board.fossils]
    locked = set(rnd.sample(lock_candidates, min(2, len(lock_candidates))))
    # 区域封印（§7.3 对拍覆盖）：雷周围 3×3 作封印区（含雷），触发锚=贴预开前沿的安全关闭格
    seals = {}
    seal_cells = set()
    mine0 = sorted(mines)[0]
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            c = (mine0[0] + dx, mine0[1] + dy)
            if 0 <= c[0] < w and 0 <= c[1] < h and c not in preopen \
                    and c not in fossils and c != base:
                seal_cells.add(c)
    if len(seal_cells) >= 5:
        frontier = [c for c in board.numbers
                    if c not in preopen and c not in mines and c not in seal_cells
                    and c not in walls and c not in locked
                    and any(n in preopen for n in neighbors(c, w, h))]
        if frontier:
            trigger = sorted(frontier)[0]
            seals["s1"] = {"cells": sorted(seal_cells), "trigger": trigger}
    board = Board.build(w, h, mines, fossils_origins=fossils, walls=walls,
                        locked=locked, seals=seals, base=base)
    preopen = bake_preopen(board, zone)

    # ---- 动作脚本：封印对拍前缀 + 闭包驱动 + 随机探索 + 全机制抽样 ----
    actions = []

    def add(kind, coord):
        actions.append({"kind": kind, "coord": list(coord)})

    sim = GameSim(board, start_money=300)
    sim.st.opened |= set(preopen)
    k = Knowledge(total_mines=len(mines))
    observe(sim, k)
    if seals:
        # 前缀（确定性）：封印格开/标被拦 → 开触发锚 → 组解封 → 解封区动作恢复
        s_cell = sorted(seals["s1"]["cells"])[0]
        add("open", s_cell)
        sim.open_cell(s_cell, "player")
        add("flag", s_cell)
        sim.toggle_flag(s_cell, "player")
        add("open", tuple(seals["s1"]["trigger"]))
        sim.open_cell(tuple(seals["s1"]["trigger"]), "player")
    guard = 0
    while len(actions) < n_actions and guard < n_actions * 6:
        guard += 1
        r = rnd.random()
        if r < 0.35:
            # 闭包一步（确定性动作，最能暴露规则漂移）；闭包内部动作必须记入脚本
            recorder = lambda kind, coord: add(kind, coord)
            before = len(sim.st.opened)
            deterministic_closure(sim, k, max_rounds=1, record=recorder)
            if len(sim.st.opened) > before:
                continue
        closed = [c for c in board.numbers if c not in sim.st.opened]
        if not closed:
            break
        c = rnd.choice(closed)
        r2 = rnd.random()
        if r2 < 0.30:
            add("open", c)
            sim.open_cell(c, "player")
        elif r2 < 0.50:
            # 插旗 + 观察反馈 + 可能撤旗（验真通道）
            add("flag", c)
            sim.toggle_flag(c, "player")
            if rnd.random() < 0.5 and c in sim.st.flagged:
                add("flag", c)
                sim.toggle_flag(c, "player")
        elif r2 < 0.62:
            # 和弦：找个已开数字格（可能落空，也是行为覆盖）
            opened_nums = [c2 for c2 in sim.st.opened
                           if board.numbers.get(c2, 0) > 0 and c2 not in sim.st.collapsed]
            if opened_nums:
                cc = rnd.choice(opened_nums)
                add("chord", cc)
                sim.chord(cc, "player")
        elif r2 < 0.72 and sim.st.money >= PROBE_PRICE:
            add("probe", c)
            sim.probe(c, "player")
        elif r2 < 0.82 and c in locked and c not in sim.st.opened:
            add("clear_lock", c)
            sim.clear_lock(c, "player")
        elif r2 < 0.92:
            # 削墙（连打三下破墙）
            if c in walls and c not in sim.st.opened:
                add("open", c)
                add("open", c)
                add("open", c)
                sim.open_cell(c, "player")
                sim.open_cell(c, "player")
                sim.open_cell(c, "player")
            else:
                add("open", c)
                sim.open_cell(c, "player")
        else:
            # 踩雷测试：随机开一个雷（坍塌路径覆盖）
            mine_cells = [m for m in mines if m not in sim.st.opened]
            if mine_cells:
                m = rnd.choice(mine_cells)
                add("open", m)
                sim.open_cell(m, "player")

    observe(sim, k)
    return {
        "board": {
            "w": w, "h": h,
            "mines": [list(m) for m in sorted(mines)],
            "preopen": [list(p) for p in sorted(preopen)],
            "base": list(base),
            "fossils": [list(o) for o in fossils],
            "walls": [list(x) for x in sorted(walls)],
            "locked": [list(x) for x in sorted(locked)],
            "seals": [{"id": sid, "cells": [list(c) for c in sorted(g["cells"])],
                       "trigger": list(g["trigger"])} for sid, g in sorted(seals.items())],
        },
        "start_money": 300,
        "actions": actions,
    }


def expected_from_scenario(scen):
    """Python 侧预期结果（与 parity.gd 汇总口径一致）"""
    seals = {s["id"]: {"cells": {tuple(c) for c in s["cells"]},
                       "trigger": tuple(s["trigger"])}
             for s in scen["board"].get("seals", [])}
    b = Board.build(
        scen["board"]["w"], scen["board"]["h"],
        mines={tuple(m) for m in scen["board"]["mines"]},
        fossils_origins=[tuple(o) for o in scen["board"]["fossils"]],
        walls={tuple(x) for x in scen["board"]["walls"]},
        locked={tuple(x) for x in scen["board"]["locked"]},
        seals=seals,
        base=tuple(scen["board"]["base"]),
    )
    sim = GameSim(b, start_money=scen["start_money"])
    sim.st.opened |= {tuple(p) for p in scen["board"]["preopen"]}
    wall_hp = {c: (3 if c in b.walls else 1) for c in b.numbers}
    flag_rewards = []
    for act in scen["actions"]:
        kind, coord = act["kind"], tuple(act["coord"])
        if kind == "open":
            sim.open_cell(coord, "player")
        elif kind == "flag":
            was = coord in sim.st.flagged
            first_time = coord not in sim.st.rewarded_flags
            sim.toggle_flag(coord, "player")
            if not was and coord in sim.st.flagged:
                fired = coord in b.mines and first_time and coord not in sim.st.confirmed
                flag_rewards.append({"coord": list(coord), "reward_fired": fired})
        elif kind == "chord":
            sim.chord(coord, "player")
        elif kind == "clear_lock":
            sim.clear_lock(coord, "player")
        elif kind == "probe":
            # 用 GameSim.probe 本体（封印中心拒部署/封印格未扫描的口径同源）
            sim.probe(coord, "player")
    # 旗奖励复核：Python 侧 toggle_flag 的 verified 顺序应与 fired 序列一致
    return {
        "opened": sorted([list(c) for c in sim.st.opened]),
        "flagged": sorted([list(c) for c in sim.st.flagged]),
        "collapsed": sorted([list(c) for c in sim.st.collapsed]),
        "confirmed": sorted([list(c) for c in sim.st.confirmed]),
        "locked": sorted([list(c) for c in b.locked]),
        "wall_hp": sorted([{"coord": list(c), "hp": sim.wall_hp[c]}
                           for c in sim.wall_hp if sim.wall_hp[c] != 1 and c not in sim.st.opened],
                          key=lambda d: d["coord"]),
        "money": sim.st.money,
        "score": sim.st.score,
        "flag_rewards": flag_rewards,
    }


def compare(expected, got):
    diffs = []
    for key in ("opened", "flagged", "collapsed", "confirmed", "locked"):
        e = {tuple(c) for c in expected[key]}
        g = {tuple(c) for c in got[key]}
        if e != g:
            diffs.append(f"{key}: python-only={sorted(e - g)[:6]} godot-only={sorted(g - e)[:6]}")
    if expected["money"] != got["money"]:
        diffs.append(f"money: python={expected['money']} godot={got['money']}")
    if expected["score"] != got["score"]:
        diffs.append(f"score: python={expected['score']} godot={got['score']}")
    ew = sorted(expected["wall_hp"], key=lambda d: d["coord"])
    gw = sorted(got["wall_hp"], key=lambda d: d["coord"])
    if ew != gw:
        diffs.append(f"wall_hp: python={ew[:6]} godot={gw[:6]}")
    ef = [(tuple(r["coord"]), r["reward_fired"]) for r in expected["flag_rewards"]]
    gf = [(tuple(r["coord"]), r["reward_fired"]) for r in got["flag_rewards"]]
    if ef != gf:
        diffs.append(f"flag_rewards: python={ef[:8]} godot={gf[:8]}")
    return diffs


def run_seed(seed: int, keep_going=False) -> bool:
    scen = make_scenario(seed)
    exp = expected_from_scenario(scen)
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "parity_scenario.json"), "w", encoding="utf-8") as fp:
        json.dump(scen, fp, ensure_ascii=False)
    if os.path.exists(os.path.join(OUT, "parity_result.json")):
        os.remove(os.path.join(OUT, "parity_result.json"))
    proc = subprocess.run(
        [GODOT, "--path", REPO, "--headless", "-s", "res://tests/route_gen_parity.gd"],
        capture_output=True, text=True, timeout=180, encoding="utf-8", errors="replace")
    rpath = os.path.join(OUT, "parity_result.json")
    if not os.path.exists(rpath):
        print(f"seed {seed}: FAIL — Godot 未产出结果（exit={proc.returncode}）")
        print(proc.stdout[-2000:])
        print(proc.stderr[-2000:])
        return False
    with open(rpath, encoding="utf-8") as fp:
        got = json.load(fp)
    diffs = compare(exp, got)
    n_actions = len(scen["actions"])
    if diffs:
        print(f"seed {seed}: FAIL（{n_actions} 条动作，{len(diffs)} 处差异）")
        for d in diffs:
            print("   -", d)
        with open(os.path.join(OUT, f"parity_fail_{seed}.json"), "w", encoding="utf-8") as fp:
            json.dump({"scenario": scen, "expected": exp, "got": got}, fp, ensure_ascii=False, indent=1)
        return False
    print(f"seed {seed}: PASS（{n_actions} 条动作，opened={len(exp['opened'])} "
          f"flag={len(exp['flagged'])} collapse={len(exp['collapsed'])} "
          f"confirmed={len(exp['confirmed'])} money={exp['money']}）")
    return True


def verify_board_scenario(board_dict: dict, actions: list, start_money: int,
                          keep_files: bool = True) -> tuple:
    """外部入口：给定固定盘 dict（与 cli 导出同构）+ 动作序列，跑 Godot 重放并比对。
    返回 (ok, diffs)。设计文档 §12：正式候选最终由 Godot 规则重放验收。"""
    scen = {"board": board_dict, "start_money": start_money, "actions": actions}
    exp = expected_from_scenario(scen)
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "parity_scenario.json"), "w", encoding="utf-8") as fp:
        json.dump(scen, fp, ensure_ascii=False)
    rpath = os.path.join(OUT, "parity_result.json")
    if os.path.exists(rpath):
        os.remove(rpath)
    proc = subprocess.run(
        [GODOT, "--path", REPO, "--headless", "-s", "res://tests/route_gen_parity.gd"],
        capture_output=True, text=True, timeout=180, encoding="utf-8", errors="replace")
    if not os.path.exists(rpath):
        return False, [f"Godot 未产出结果（exit={proc.returncode}）"]
    with open(rpath, encoding="utf-8") as fp:
        got = json.load(fp)
    diffs = compare(exp, got)
    if not keep_files:
        os.remove(os.path.join(OUT, "parity_scenario.json"))
    return (not diffs), diffs


def main():
    seeds = [1, 2, 3, 4, 5]
    if "--seeds" in sys.argv:
        seeds = [int(s) for s in sys.argv[sys.argv.index("--seeds") + 1:]]
    ok = all(run_seed(s) for s in seeds)
    print("PARITY", "ALL PASS" if ok else "HAS FAILURES")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
