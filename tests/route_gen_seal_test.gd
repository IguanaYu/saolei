extends SceneTree
## §7.3 区域封印机制 · 游戏侧冒烟：装载/四类拦截/洪水不穿/领土触发解封/解封后恢复
## 用法：Godot_console.exe --path . --headless -s res://tests/route_gen_seal_test.gd
## 盘面：8×8，雷 (5,5)；预开=左上 6 格手工烘焙；封印组 s1 = 雷区 3×3（含雷），
##       触发机关 = (2,2)（数字 0 关闭格，贴预开前沿）。

var fails: Array = []
var step_no := 0
var _released: Array = []


func _initialize() -> void:
	call_deferred("_run")


func check(cond: bool, label: String) -> void:
	step_no += 1
	if cond:
		print("  [PASS] #%d %s" % [step_no, label])
	else:
		fails.append(label)
		print("  [FAIL] #%d %s" % [step_no, label])


func _v(x: int, y: int) -> Vector2i:
	return Vector2i(x, y)


func _run() -> void:
	await process_frame
	await process_frame
	var mines: Array = [_v(5, 5)]
	var preopen: Array = [_v(0, 0), _v(1, 0), _v(0, 1), _v(1, 1), _v(2, 0), _v(0, 2)]
	var seal_cells: Array = []
	for dy in range(4, 7):
		for dx in range(4, 7):
			seal_cells.append(_v(dx, dy))   # 3×3 含雷 (5,5)
	var data := {
		"mines": mines,
		"preopen": preopen,
		"base": _v(0, 0),
		"seals": [{"id": "s1", "cells": seal_cells, "trigger": _v(2, 2)}],
	}
	var grid = load("res://scripts/grid.gd").new()
	grid.name = "SealTestGrid"
	root.add_child(grid)
	grid.configure(8, 8, 1)
	grid.apply_fixed_board(data)
	grid.seal_released.connect(func(id: String): _released.append(id))
	await process_frame

	# ---- ① 装载 ----
	check(grid.seal_groups.has("s1") and grid.seal_groups["s1"]["cells"].size() == 9,
			"封印组 s1 装载 9 格")
	check(grid.get_cell(_v(5, 5)).is_sealed and grid.get_cell(_v(5, 5)).seal_id == "s1",
			"雷格处于封印态")
	check(not grid.get_cell(_v(5, 5)).is_opened, "封印格未被预开（烘焙侧不入预开的防御）")
	check(_released.is_empty(), "装载期未误触发")

	# ---- ② 拦截：开/标/削层 ----
	print("  [DBG] seal_groups=", grid.seal_groups)
	grid.open_cell(_v(4, 4), "player")
	check(not grid.get_cell(_v(4, 4)).is_opened and grid.get_cell(_v(4, 4)).wall_hp == 1,
			"封印格不可开（普通墙格连削层都拦）")
	grid.toggle_flag(_v(4, 5), "player")
	check(not grid.get_cell(_v(4, 5)).is_flagged, "封印格不可标")

	# ---- ③ 洪水不穿封印 ----
	grid.open_cell(_v(2, 1), "player")   # 0 格洪水向右下铺开
	check(grid.get_cell(_v(3, 3)).is_opened, "洪水铺到封印区外沿 (3,3)")
	check(not grid.get_cell(_v(4, 4)).is_opened, "洪水停在封印格前 (4,4)")
	check(grid.get_cell(_v(3, 4)).is_opened, "封印区外沿 (3,4) 正常铺开")

	# ---- ④ 触发：机关格 (2,2) 开出 + 领土连通 → 整组解封 ----
	grid.open_cell(_v(2, 2), "player")
	await process_frame
	check(_released.has("s1"), "机关接通发出 seal_released(s1)")
	check(grid.seal_groups["s1"]["released"], "组状态 released=true")
	var all_unsealed := true
	for c in seal_cells:
		if grid.get_cell(c).is_sealed:
			all_unsealed = false
	check(all_unsealed, "整组解封（9 格 is_sealed 全清）")

	# ---- ⑤ 解封后恢复正常规则 ----
	grid.open_cell(_v(4, 4), "player")
	check(grid.get_cell(_v(4, 4)).is_opened, "解封后可开")
	grid.open_cell(_v(5, 5), "player")
	check(grid.get_cell(_v(5, 5)).is_collapsed, "解封后踩雷正常坍塌")
	grid.open_cell(_v(4, 5), "player")   # 贴雷数字 1 格：非洪水路径的开格
	check(grid.get_cell(_v(4, 5)).is_opened, "解封区普通开格正常")
	_finish()


func _finish() -> void:
	var code := 0 if fails.is_empty() else 1
	print("[RouteGenSeal] RESULT=%s FAILS=%d" % ["OK" if fails.is_empty() else "NG", fails.size()])
	quit(code)
