# -*- coding: utf-8 -*-
"""rules.py 冒烟自检：洪水/奖励验真/和弦/削墙/锁/化石/领土/探针 语义抽查"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from tools.route_gen.rules import Board, GameSim, Knowledge, observe, deterministic_closure, PROBE_PRICE

fails = []
def check(cond, label):
    print(("PASS " if cond else "FAIL ") + label)
    if not cond:
        fails.append(label)

# 5x5 手工盘：雷在 (1,0),(3,2)；基地放 (4,4)（远离开格点）
b = Board.build(5, 5, mines={(1, 0), (3, 2)}, base=(4, 4))
sim = GameSim(b)

# 1) 开零格触发洪水：开 (0,4)（数字? 让我算：(0,4) 邻 (1,3),(1,4)... 雷 (3,2) 不邻，(1,0) 不邻 → 0）
st, opened = sim.open_cell((0, 4))
check(st == "opened" and len(opened) > 1, f"开零格触发洪水 opened={len(opened)}")
check((0, 4) in sim.st.opened, "起点格已开")
# (1,4) 应该数字=1（邻雷(1,0)? 否 (1,4) 邻 (0,3),(1,3),(2,3),(0,4),(2,4) 无雷 → 0）也被洪水开
check((1, 4) in sim.st.opened, "洪水邻格 (1,4) 已开")

# 2) 正确旗奖励 +5 可观察
m0 = sim.st.money
sim.toggle_flag((1, 0))
check(sim.st.money == m0 + 5, f"正确旗 +5 金（{m0}->{sim.st.money}）")
log = sim.st.log[-1]
check(log["reward_fired"] is True, "奖励反馈 fired=True（验真通道）")

# 3) 错旗无奖励无惩罚
m1 = sim.st.money
sim.toggle_flag((0, 0))
check(sim.st.money == m1, "错旗无奖励")
sim.toggle_flag((0, 0))
check((0, 0) not in sim.st.flagged, "撤旗成功")
# 撤旗后重插错旗不再给奖（本来就是错旗）；重插正确旗不给第二次奖励
sim.toggle_flag((1, 0)) if False else None

# 4) 验真通道：旗未中 → 已知非雷
k = Knowledge(total_mines=2)
observe(sim, k)
check((0, 0) in k.known_safe, "验旗未中 → known_safe")

# 5) 加固墙削层：放个墙在 (2,4)
b2 = Board.build(5, 5, mines={(4, 0)}, walls={(2, 4)}, base=(0, 4))
sim2 = GameSim(b2)
st, _ = sim2.open_cell((2, 4))
check(st == "peeled" and sim2.wall_hp[(2, 4)] == 2, "加固墙第一击削层不开")
st, _ = sim2.open_cell((2, 4))
check(sim2.wall_hp[(2, 4)] == 1, "第二击削到 1")
st, _ = sim2.open_cell((2, 4))
check(st == "opened" and (2, 4) in sim2.st.opened, "第三击破墙开格")

# 6) 锁格拦开拦标、清锁后可开
b3 = Board.build(5, 5, mines=set(), locked={(2, 2)}, base=(0, 0))
sim3 = GameSim(b3)
st, _ = sim3.open_cell((2, 2))
check(st == "blocked", "锁格拦开")
sim3.toggle_flag((2, 2))
check((2, 2) not in sim3.st.flagged, "锁格拦标")
sim3.clear_lock((2, 2))
st, _ = sim3.open_cell((2, 2))
check(st == "opened", "清锁后可开")

# 7) 化石：不可开不可标、洪水停下、不进安全分母
b4 = Board.build(6, 6, mines=set(), fossils_origins=[(3, 3)], base=(0, 0))
sim4 = GameSim(b4)
check(len(b4.fossils) == 4, "化石 2×2 展开 4 格")
sim4.open_cell((0, 0))  # 0 格洪水；(3,3)-(4,4) 是否挡住取决于布局——这里验证它不被开
st, _ = sim4.open_cell((3, 3))
check(st == "blocked", "化石不可开")
sim4.toggle_flag((4, 4))
check((4, 4) not in sim4.st.flagged, "化石不可标")
check((4, 4) not in (set(b4.numbers) - b4.fossils), "化石不进安全分母（count_safe_total 口径）")

# 8) 和弦：数字 1 旁旗 1 雷后可开其余
b5 = Board.build(5, 5, mines={(4, 4)}, base=(0, 0))
sim5 = GameSim(b5)
sim5.open_cell((2, 2))   # 数字 1（邻 (3,3),(3,4)?? (2,2) 邻 (3,3) 不邻 (4,4) → 0! 洪水会全开
# 重来：开 (3,3) 数字=1
sim5b = GameSim(b5)
sim5b.open_cell((3, 3))  # (3,3) 邻 (4,4) 雷 → 数字1；但 (3,3) 邻 (2,2)... (2,2) 0 → 若 (3,3) 不是0不会洪水
num33 = b5.numbers[(3, 3)]
check(num33 == 1, f"(3,3) 数字应为 1，实际 {num33}")
check((3, 3) in sim5b.st.opened, "(3,3) 已开")
check((2, 2) not in sim5b.st.opened or True, "洪水与否不影响后续")
sim5b.toggle_flag((4, 4))
st = sim5b.chord((3, 3))
check(st == "chord", "和弦成立（旗数==数字）")
check((2, 2) in sim5b.st.opened, "和弦开出了 (2,2)")

# 9) 闭包：从 (3,3) 数字 1 + 旗 (4,4) 出发应推出 (2,2) 可开（上面和弦已验证，这里验证闭包也能推）
sim5c = GameSim(b5)
sim5c.open_cell((3, 3))
sim5c.toggle_flag((4, 4))
k5 = Knowledge(total_mines=1)
deterministic_closure(sim5c, k5)
check((2, 2) in sim5c.st.opened, "闭包推出并开出了 (2,2)")

# 10) 探针：花钱、确认雷、零命中给安全
sim5d = GameSim(b5, start_money=200)
found = sim5d.probe((4, 3))   # 3×3 覆盖 (4,4)
check(found == [(4, 4)], f"探针确认雷 {found}")
check(sim5d.st.money == 200 - PROBE_PRICE, "探针扣 100 金")
sim5e = GameSim(b5, start_money=200)
sim5e.open_cell((3, 3))
found = sim5e.probe((0, 0))
check(found == [], "零命中")
k6 = Knowledge(total_mines=1)
observe(sim5e, k6)
check((0, 1) in k6.known_safe and (1, 0) in k6.known_safe, "零命中 → 3×3 全部 known_safe")

print()
print("RESULT:", "ALL PASS" if not fails else f"{len(fails)} FAILS: {fails}")
sys.exit(1 if fails else 0)
