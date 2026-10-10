extends SceneTree
## 第二章 2-3「特殊矿石」改版 E2E 实测（2026-10-10 后端测试）
## 断言组：盘装载（矿石 2 处足迹占格/折光退场）/ 商店（guard only，折光隐藏）/
## 教学线（基地第 7 行直射矿石 A 截停触发）/ 爆发结算（seed 决定论对拍：开墙+旗格免疫）/
## 爆发充能（拍板 #8）/ 无限次触发 / 矿石 B 第二触发位 / 埋点 ore_bursts。
## 用法：Godot_console.exe --path . --headless -s res://tmp/auto_ore_s3_test.gd

const EVIDENCE := "tmp/ore_s3_evidence/"

var step_no := 0
var fails: Array = []
var notes: Array = []
var GS: Node
var SaveSys: Node
var main: Node
var g: Node
var LM: Node
var EM: Node
var RM: Node
var FM: Node
var save_bak := ""


func _initialize() -> void:
	print("[OreS3] USER_DATA=", OS.get_user_data_dir())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EVIDENCE))
	change_scene_to_file("res://scenes/ui/BootLoading.tscn")
	call_deferred("_run")


func check(cond: bool, label: String) -> void:
	step_no += 1
	if cond:
		print("  [PASS] #%d %s" % [step_no, label])
	else:
		fails.append(label)
		print("  [FAIL] #%d %s" % [step_no, label])
	notes.append({"n": step_no, "ok": cond, "label": label})


func _sec(t: float) -> void:
	await create_timer(t, true).timeout


func _walk(node: Node, acc: Array) -> Array:
	acc.append(node)
	for c in node.get_children():
		_walk(c, acc)
	return acc


func _find_button(text_part: String) -> Button:
	for n in _walk(root, []):
		if n is Button and n.is_visible_in_tree() and text_part in n.text:
			return n
	return null


func _click_button(text_part: String) -> bool:
	var b := _find_button(text_part)
	if b == null:
		print("  [WARN] 找不到按钮：", text_part)
		return false
	var rect: Rect2 = b.get_global_rect()
	await _inject_click(rect.position + rect.size / 2.0)
	return true


func _inject_click(screen_pos: Vector2) -> void:
	var pos: Vector2 = root.get_final_transform() * screen_pos
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	Input.parse_input_event(motion)
	await process_frame
	var ev := InputEventMouseButton.new()
	ev.position = pos
	ev.global_position = pos
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	var rel := ev.duplicate()
	rel.pressed = false
	Input.parse_input_event(rel)
	await process_frame


func _await_btn(text_part: String, timeout_sec: float) -> Button:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var b := _find_button(text_part)
		if b != null:
			return b
		await _sec(0.1)
	return null


func _fire(target: Vector2i) -> void:
	main._on_laser_fire_requested(target)


func _run() -> void:
	await _sec(1.0)
	GS = root.get_node("/root/GameState")
	SaveSys = root.get_node("/root/SaveSystem")
	var Settings: Node = root.get_node("/root/GameSettings")
	var ud := OS.get_user_data_dir()
	if FileAccess.file_exists(ud + "/save_data.json"):
		var f := FileAccess.open(ud + "/save_data.json", FileAccess.READ)
		save_bak = f.get_as_text()
		f.close()
	Settings.set_value("tutorial_done_ch02_s03", false)
	Settings.set_value("skip_pre_level", false)
	SaveSys.cleared_levels.erase("ch02_s03")

	var menu_btn = await _await_btn("选择关卡", 30.0)
	check(menu_btn != null, "BootLoading 正常进主菜单")
	await _click_button("选择关卡")
	await _sec(0.8)
	root.get_node("Main/UILayer/LevelSelect").set_chapter("ch02")
	await _sec(0.5)
	var card = await _await_btn("03", 5.0)
	check(card != null, "2-3 关卡入口可见")
	if card != null:
		var r: Rect2 = card.get_global_rect()
		await _inject_click(r.position + r.size / 2.0)
	check(await _click_button("本关"), "开始本关")
	await _sec(0.8)
	var prec = await _await_btn("开始挖矿", 5.0)
	if prec != null:
		check(await _click_button("开始挖矿"), "开始挖矿")
	await _sec(1.0)

	main = root.get_node("Main")
	g = main.grid
	LM = main.laser_manager
	EM = main.enemy_manager
	RM = main.robot_manager
	FM = main.facility_manager
	if g == null or g.cells.size() == 0 or GS.current_level_id != "ch02_s03":
		check(false, "ch02_s03 固定盘装载（id=%s）" % GS.current_level_id)
		_finish()
		return
	await _phase1_board()
	await _phase2_ore_a_teach()
	await _phase3_ore_rules()
	await _phase4_ore_b()
	_finish()


# ---- 阶段 1：盘装载（矿石两处 / 折光退场） ----
func _phase1_board() -> void:
	print("[Phase1] 盘装载")
	check(g.cells.size() == 196, "14×14=196 格（%d）" % g.cells.size())
	var opened := 0
	for c in g.cells:
		if g.cells[c].is_opened:
			opened += 1
	check(opened == 64, "预开 64 格（%d）" % opened)
	check(GS.bases[0] == Vector2i(1, 7), "固定基地 (1,7)")
	check(FM.ores.size() == 2, "矿石 2 处（%d）" % FM.ores.size())
	var foot_a: Array = [Vector2i(7, 6), Vector2i(8, 6), Vector2i(7, 7), Vector2i(8, 7)]
	var foot_b: Array = [Vector2i(3, 4), Vector2i(4, 4), Vector2i(3, 5), Vector2i(4, 5)]
	var fa: Array = FM.ores[0].footprint() if FM.ores.size() >= 1 else []
	var fb: Array = FM.ores[1].footprint() if FM.ores.size() >= 2 else []
	check(fa == foot_a, "矿石 A 足迹 (7,6) 2×2")
	check(fb == foot_b, "矿石 B 足迹 (3,4) 2×2")
	var occupied := true
	for c in foot_a + foot_b:
		if not g.facility_cells.has(c) or g.is_walkable(c):
			occupied = false
	check(occupied, "两处足迹占格生效（不可走）")
	check(FM.chain_nodes.is_empty() and FM.pillar == null, "无节点/无柱（s3 单机制）")
	var refractor_gifts := 0
	for r in RM.robots:
		if r.robot_type.begins_with("refractor"):
			refractor_gifts += 1
	check(refractor_gifts == 0, "折光赠送退场（D5）")
	var types: Array = RM.robots.map(func(r): return r.robot_type)
	check(types.has("opener") and types.has("marker") and types.size() == 2,
			"开局赠机 opener+marker（%s）" % str(types))
	check(not main.shop.buy_refractor_wide_button.visible
			and not main.shop.buy_refractor_scatter_button.visible,
			"折光两键隐藏")
	check(not main.shop.buy_overload_button.visible, "过载按钮隐藏（s3 未开放）")
	check(main.shop.buy_guard_button.visible, "guard 开放（s3 沿用）")
	check(EM.builders_enabled and EM.builder_wall_sequence == [1, 1, 3],
			"筑墙工序列 [1,1,3]（矿石克筑墙工的设计前提）")


# ---- 阶段 2：教学线（第 7 行直射矿石 A 截停触发） ----
func _phase2_ore_a_teach() -> void:
	print("[Phase2] 教学线")
	RM.remove_all()  # 确定性隔离
	var geo: Dictionary = LM.compute_shot_geometry(Vector2i(1, 7), Vector2i(13, 7))
	check(geo.main[geo.main.size() - 1] == Vector2i(7, 7), "束沿第 7 行截停于 (7,7)")
	check(geo.ores.size() == 1 and geo.ores[0] == FM.ores[0], "矿石 A 入触发集")
	check(geo.ore_marks.size() == 4, "预览描边数据=足迹 4 格")


# ---- 阶段 3：爆发规则（seed 对拍：开墙/旗格/充能/无限次） ----
func _phase3_ore_rules() -> void:
	print("[Phase3] 爆发规则")
	var ore = FM.ores[0]
	var seed_used := 0
	var expected: Array = []
	var wall_cell := Vector2i(-9, -9)   # 将插旗的未开非雷格
	var open_cell := Vector2i(-9, -9)   # 期望被开的未开非雷格（不插旗）
	while seed_used < 5000:
		seed_used += 1
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_used
		expected = ore.burst_cells(g, rng)
		var walls: Array = []
		for c in expected:
			var cc = g.cells[c]
			if not cc.is_opened and not cc.is_mine:
				walls.append(c)
		if walls.size() >= 2:
			wall_cell = walls[0]
			open_cell = walls[1]
			break
	check(wall_cell != Vector2i(-9, -9), "找到含 ≥2 未开墙的 seed=%d" % seed_used)
	if wall_cell == Vector2i(-9, -9):
		return
	var opener = RM.spawn_robot(Vector2i(5, 6), "opener", g)  # 束格充能对照组（第 7 行束不经过）
	g.toggle_flag(wall_cell, "test")
	var open_hp0: int = g.cells[open_cell].wall_hp
	LM.burst_rng.seed = seed_used
	var bursts0: int = int(GS.result_stats["ore_bursts"])
	_fire(Vector2i(13, 7))
	check(int(GS.result_stats["ore_bursts"]) == bursts0 + 1, "ore_bursts 埋点 +1")
	check(g.cells[wall_cell].is_flagged and not g.cells[wall_cell].is_opened,
			"旗格免疫（%s 不结算）" % str(wall_cell))
	check(g.cells[open_cell].is_opened or g.cells[open_cell].wall_hp < open_hp0,
			"对照格 %s 被结算（开格或削层）" % str(open_cell))
	# 无限次：换 seed 再打
	LM.burst_rng.seed = seed_used + 100
	_fire(Vector2i(13, 7))
	check(int(GS.result_stats["ore_bursts"]) == bursts0 + 2, "二次触发照常（无限次）")
	check(FM.ores.size() == 2 and is_instance_valid(FM.ores[0]), "矿石 A 仍存活")
	g.toggle_flag(wall_cell, "test")
	RM.remove_all()


# ---- 阶段 4：矿石 B 第二触发位（北区） ----
func _phase4_ore_b() -> void:
	print("[Phase4] 矿石 B")
	var geo: Dictionary = LM.compute_shot_geometry(Vector2i(1, 7), Vector2i(3, 3))
	check(geo.main[geo.main.size() - 1] == Vector2i(3, 4),
			"东北向束截停于矿石 B 足迹 (3,4)")
	check(geo.ores.size() == 1 and geo.ores[0] == FM.ores[1], "矿石 B 入触发集")
	var bursts0: int = int(GS.result_stats["ore_bursts"])
	_fire(Vector2i(3, 3))
	check(int(GS.result_stats["ore_bursts"]) == bursts0 + 1, "矿石 B 触发埋点 +1")
	check(FM.ores.size() == 2, "两块矿石均存活（常驻设施）")


func _finish() -> void:
	if save_bak != "":
		var ud := OS.get_user_data_dir()
		var f := FileAccess.open(ud + "/save_data.json", FileAccess.WRITE)
		f.store_string(save_bak)
		f.close()
		print("[OreS3] save_data.json 已恢复备份")
	var total_ok := 0
	for n in notes:
		if n.ok:
			total_ok += 1
	var summary := {
		"date": "2026-10-10",
		"total": notes.size(),
		"passed": total_ok,
		"failed": fails.size(),
		"fails": fails,
		"assertions": notes,
	}
	var f2 := FileAccess.open(ProjectSettings.globalize_path(EVIDENCE + "assertions.json"),
			FileAccess.WRITE)
	f2.store_string(JSON.stringify(summary, "  "))
	f2.close()
	print("")
	print("=== 2-3 特殊矿石实测结果：%d/%d 通过 ===" % [total_ok, notes.size()])
	if not fails.is_empty():
		print("=== FAILED %d 项: %s ===" % [fails.size(), ", ".join(fails)])
	quit(0 if fails.is_empty() else 1)
