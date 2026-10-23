extends SceneTree
## 路径驱动地图生成器 · 步骤 A 验收：ch01_s08「自动开路」试验关接线测试
## 覆盖：LevelDatabase 出 8 关（ch01 扩容）→ R1 固定盘数据完整 → Grid 真实装载
##       （同 main.gd 固定盘分支口径）→ 决定性小样动作（旗奖励/安全开/踩雷）
## 用法：Godot_console.exe --path . --headless -s res://tests/route_gen_level_test.gd
## 注意：-s 模式编译期不能引 Grid/Cell/GameState 标识符，运行期 load/get_node。

var fails: Array = []
var step_no := 0
var _flagged_correct := false   # lambda 值捕获：计数必须挂成员


func _initialize() -> void:
	call_deferred("_run")


func check(cond: bool, label: String) -> void:
	step_no += 1
	if cond:
		print("  [PASS] #%d %s" % [step_no, label])
	else:
		fails.append(label)
		print("  [FAIL] #%d %s" % [step_no, label])


func _run() -> void:
	await process_frame
	await process_frame
	var LS = root.get_node("/root/LevelSystem")

	# ---- ① 关卡数据接线 ----
	var lvl = LS.get_level("ch01_s08")
	check(lvl != null, "ch01_s08 存在于 LevelDatabase")
	if lvl == null:
		_finish()
		return
	check(lvl.chapter_id == "ch01", "chapter_id=ch01")
	check(LS.db.chapters[0].level_ids.size() == 8, "ch01 扩到 8 关")
	check(LS.db.IMPLEMENTED_CHAPTERS.has("ch01"), "ch01 在实装章白名单（选关页可见）")
	check(lvl.fixed_mines.size() == 40, "fixed_mines=40")
	check(lvl.preopen_coords.size() == 67, "preopen=67")
	check(lvl.fixed_base == Vector2i(2, 2), "预置基地 (2,2)（路线起点）")
	check(lvl.objectives.size() == 1 and lvl.objectives[0].type == ObjectiveData.Type.CLEAR_ALL_SAFE
			and lvl.objectives[0].target_value == 150, "目标 CLEAR_ALL_SAFE/150")

	# ---- ② Grid 真实装载（同 main.gd 固定盘分支字段）----
	var grid = load("res://scripts/grid.gd").new()
	grid.name = "RouteGenLevelGrid"
	root.add_child(grid)
	grid.configure(lvl.grid_size.x, lvl.grid_size.y, lvl.mine_count)
	grid.apply_fixed_board({
		"mines": lvl.fixed_mines,
		"preopen": lvl.preopen_coords,
		"base": lvl.fixed_base,
		"fossils": lvl.fixed_fossils,
		"walls": lvl.reinforced_walls,
	})
	await process_frame
	check(grid.count_safe_total() == 216, "安全格总数 216（256-40）")
	check(grid.count_safe_remaining() == 149, "待开安全格 149（216-预开67）")
	var base_cell = grid.get_cell(Vector2i(2, 2))
	check(base_cell != null and base_cell.is_base, "基地格就位")
	var preopen_all_opened := true
	var preopen_no_mine := true
	for c in lvl.preopen_coords:
		var cell = grid.get_cell(c)
		if cell == null or not cell.is_opened:
			preopen_all_opened = false
		if cell != null and cell.is_mine:
			preopen_no_mine = false
	check(preopen_all_opened, "预开区全部已开")
	check(preopen_no_mine, "预开区与雷无重叠（apply_fixed_board 拒铺口径未触发）")

	# ---- ③ 决定性小样动作（真值来自 R1）----
	_flagged_correct = false
	grid.cell_flagged.connect(func(_cell, _actor, correct: bool, _first: bool):
		if correct:
			_flagged_correct = true)
	grid.toggle_flag(Vector2i(0, 5), "player")   # R1 已知雷
	check(_flagged_correct, "已知雷 (0,5) 插旗判正确（奖励通道）")
	grid.open_cell(Vector2i(15, 3), "player")   # R1 已知安全
	check(grid.cells.has(Vector2i(15, 3)) and grid.get_cell(Vector2i(15, 3)).is_opened,
			"已知安全格 (15,3) 开格成功")
	grid.open_cell(Vector2i(15, 2), "player")   # R1 已知雷 → 坍塌
	check(grid.get_cell(Vector2i(15, 2)).is_collapsed, "踩雷 (15,2) 坍塌")
	check(grid.count_safe_total() - grid.count_safe_remaining() == 68,
			"进度 68/216（预开67+安全开1；踩塌雷不进安全分母）")
	_finish()


func _finish() -> void:
	var code := 0 if fails.is_empty() else 1
	print("[RouteGenLevel] RESULT=%s FAILS=%d" % ["OK" if fails.is_empty() else "NG", fails.size()])
	quit(code)
