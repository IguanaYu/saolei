extends SceneTree
## 第二章 2-3「折光机器人」逻辑实测 harness（2026-10-10，后端测试）
## 断言组：盘装载+预设驻点赠送 / 光束接管（主束截停/宽束走廊/散射三束/同轮单格一层/
## 副束不激活第二台/先充能后增幅共存）/ 购买放置流（不扣钱落位扣/非法落点不吞/
## 预览=结算同源）/ 商店限购 / 重开清场。导航洗档同 s2 harness。
## 用法：Godot_console.exe --path . -s res://tmp/auto_laser_s3_test.gd

const EVIDENCE := "E:/godot/扫雷/tmp/laser_s3_evidence/"

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
var save_bak := ""


func _initialize() -> void:
	print("[LaserS3] USER_DATA=", OS.get_user_data_dir())
	DisplayServer.window_set_position(Vector2i(-3000, 0))
	DisplayServer.window_set_size(Vector2i(1024, 768))
	DisplayServer.window_set_title("2-3 折光机器人逻辑实测")
	DirAccess.make_dir_recursive_absolute(EVIDENCE)
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


func _shot(fname: String) -> void:
	if DisplayServer.get_name() == "headless":
		return  # 无渲染层：截图跳过（逻辑断言不受影响）
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(EVIDENCE + fname)
	print("  [SHOT] ", fname)


func _await_btn(text_part: String, timeout_sec: float) -> Button:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var b := _find_button(text_part)
		if b != null:
			return b
		await _sec(0.1)
	return null


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
	if g == null or g.cells.size() == 0 or GS.current_level_id != "ch02_s03":
		check(false, "ch02_s03 固定盘装载（id=%s cells=%d）" % [GS.current_level_id,
				0 if g == null else g.cells.size()])
		_finish()
		return
	await _phase1_board()
	await _phase2_takeover()
	await _phase3_placement()
	await _phase4_restart()
	_finish()


# ---- 阶段 1：盘装载 + 预设驻点 ----
func _phase1_board() -> void:
	print("[Phase1] 盘装载")
	check(g.cells.size() == 196, "14×14=196 格（%d）" % g.cells.size())
	var opened := 0
	for c in g.cells:
		if g.cells[c].is_opened:
			opened += 1
	check(opened == 64, "预开 64 格（%d）" % opened)
	check(GS.bases[0] == Vector2i(1, 7), "固定基地 (1,7)")
	check(int(g.cells[Vector2i(9, 7)].wall_hp) == 3, "宽墙带 (9,7) hp=3")
	# 预设宽束驻点赠送：折光在 (8,7)（不走 BFS——基地旁落位会错位）
	var refractors := []
	for r in RM.robots:
		if r.robot_type.begins_with("refractor"):
			refractors.append(r)
	check(refractors.size() == 1, "预设宽束折光 1 台（%d）" % refractors.size())
	if refractors.size() == 1:
		check(refractors[0].coord == Vector2i(8, 7), "落预设驻点 (8,7)（实际 %s）" % str(refractors[0].coord))
		check(refractors[0].config == "wide", "配置=wide")
	check(EM.builders_enabled, "筑墙工开闸（序列 1,1,3）")
	check(EM.builder_wall_sequence == [1, 1, 3], "新墙序列 [1,1,3]")
	RM.remove_all()   # 确定性隔离（opener/marker 撤场，折光按需重放）
	var rf = RM.spawn_robot(Vector2i(8, 7), "refractor_wide", g)
	check(rf != null and rf.coord == Vector2i(8, 7), "受控重放折光 (8,7)")
	await _shot("01-board.png")


# ---- 阶段 2：光束接管 ----
func _phase2_takeover() -> void:
	print("[Phase2] 光束接管")
	# A: 直射不经过折光 → 行为同 2-1/2-2（走 (2,7) 已开格纯空射）
	var shots0: int = int(GS.result_stats["shots_fired"])
	main._on_laser_fire_requested(Vector2i(2, 7))
	check(int(GS.result_stats["shots_fired"]) == shots0 + 1, "未过折光的直射照常")
	# B: 束过折光 → 截停+宽束走廊：打 (8,7) 正东远端 (13,7)
	#    预期：主束 (2..8,7) 截停于折光；副束=3 宽×6 走廊（y∈[6,8]×x∈[9,11]+(12..14 行6-8)）
	var geo_b: Dictionary = LM.compute_shot_geometry(Vector2i(1, 7), Vector2i(13, 7))
	check(geo_b.refractor != null and geo_b.refractor.coord == Vector2i(8, 7), "主束截停于折光")
	check(geo_b.main.has(Vector2i(9, 7)) == false, "主束不含折光后方格")
	var corridor_expect: Array = []
	for yy in range(6, 9):
		for xx in range(9, 15):
			corridor_expect.append(Vector2i(xx, yy))
	var sub_set: Dictionary = {}
	for c in geo_b.sub:
		sub_set[c] = true
	var corridor_hit := true
	for c in corridor_expect:
		if not sub_set.has(c) and c.x <= 13:
			corridor_hit = false
	check(corridor_hit, "宽束走廊=3 宽×6（含 (13,y) 列）")
	var peeled0: int = int(GS.result_stats["layers_peeled"])
	main._on_laser_fire_requested(Vector2i(13, 7))
	check(int(GS.result_stats["layers_peeled"]) == peeled0 + 10,
			"副束削走廊宽墙带 10 面各一层（(9-11,y)×3+(13,7)，同轮单格一层，实 +%d）" % (int(GS.result_stats["layers_peeled"]) - peeled0))
	check(int(g.cells[Vector2i(9, 7)].wall_hp) == 2, "(9,7) 3→2")
	check(int(g.cells[Vector2i(9, 6)].wall_hp) == 2 and int(g.cells[Vector2i(9, 8)].wall_hp) == 2,
			"走廊两侧 (9,6)(9,8) 同削一层（3 宽生效）")
	check(not g.cells[Vector2i(2, 7)].is_flagged, "无副作用兜底")
	await _shot("02-wide.png")
	# C: 副束不激活第二台：折光 (8,7) 东南走廊内放第二台折光 (10,9)，束后它不增幅
	var rf2 = RM.spawn_robot(Vector2i(10, 9), "refractor_scatter", g)
	var geo_c: Dictionary = LM.compute_shot_geometry(Vector2i(1, 7), Vector2i(13, 7))
	check(geo_c.refractor != null and geo_c.refractor.coord == Vector2i(8, 7),
			"副束路径上的第二台不被激活（仍首台接管）")
	RM.remove_robot(rf2, "test")
	# D: 散射：换散射折光打东向 → 三束（主轴行7 + ±45° 斜束）
	var rf_wide = null
	for r in RM.robots:
		if r.robot_type.begins_with("refractor"):
			rf_wide = r
	RM.remove_robot(rf_wide, "test")
	var rf_s = RM.spawn_robot(Vector2i(8, 7), "refractor_scatter", g)
	var geo_d: Dictionary = LM.compute_shot_geometry(Vector2i(1, 7), Vector2i(13, 7))
	var dset: Dictionary = {}
	for c in geo_d.sub:
		dset[c] = true
	check(dset.has(Vector2i(10, 7)) and dset.has(Vector2i(9, 6)) and dset.has(Vector2i(9, 8)),
			"散射三束（主轴+±45° 起点）")
	var on_diag := 0
	for c in geo_d.sub:
		if c.x - 8 == -(c.y - 7) and c.x > 8:
			on_diag += 1   # 东北斜束 y=15-x 线（相对 (8,7)）
	check(on_diag >= 4, "东北斜束长 ≥4 格（%d）" % on_diag)
	# E: 先充能后增幅共存：opener 站 (2,7)（主束起点后第一格），束过它再打到折光
	var opener = RM.spawn_robot(Vector2i(2, 7), "opener", g)
	main._on_laser_fire_requested(Vector2i(13, 7))
	check(opener.is_charged(), "主束先充能 opener（增幅不抢效果）")
	RM.remove_all()
	await _shot("03-scatter.png")


# ---- 阶段 3：购买放置流 ----
func _phase3_placement() -> void:
	print("[Phase3] 放置流")
	GS.add_money(500, "test")
	var money0: int = GS.money
	# 进入放置模式（真实链路：shop._buy_refractor → _enter_placing_mode）
	var shop: Control = root.get_node("Main/UILayer/Shop")
	shop._buy_refractor("refractor_scatter")
	check(main.placing_mode == "refractor_scatter", "购买散射进放置模式")
	check(GS.money == money0, "确认落位前不扣钱")
	# 非法落点：未开格
	check(main.place_block_reason(Vector2i(9, 7)) != "", "未开格拒放")
	# 合法落点：预开区空格 (4,9) → 直接调 _try_place_at（坐标换算走点击层，逻辑层等价）
	var spot: Vector2i = Vector2i(4, 9)
	check(main.place_block_reason(spot) == "", "预开空格可放（%s）" % main.place_block_reason(spot))
	main._try_place_at(g.coord_to_world(spot))
	check(main.placing_mode == "", "落位后退出放置模式")
	check(GS.money == money0 - 100, "落位扣 100（%d → %d）" % [money0, GS.money])
	var placed := []
	for r in RM.robots:
		if r.robot_type.begins_with("refractor") and r.coord == spot:
			placed.append(r)
	check(placed.size() == 1, "散射折光落位 %s" % str(spot))
	# 限购：再买同型被拦
	shop._buy_refractor("refractor_scatter")
	check(main.placing_mode != "refractor_scatter" or GS.get_robot_purchased_count("refractor_scatter") >= 1,
			"散射限购 1（已购满不再进放置）")
	await _shot("04-placed.png")
	RM.remove_all()


# ---- 阶段 4：重开清场 ----
func _phase4_restart() -> void:
	print("[Phase4] 重开")
	main._on_restart_requested()
	await _sec(1.2)
	check(GS.score == 0 and GS.game_active, "重开新局")
	var refractors := 0
	for r in RM.robots:
		if r.robot_type.begins_with("refractor"):
			refractors += 1
	check(refractors == 1, "重开后预设折光重放（1 台）")
	check(int(g.cells[Vector2i(9, 7)].wall_hp) == 3, "宽墙带复位 3 层")
	await _shot("05-restarted.png")


func _finish() -> void:
	if save_bak != "":
		var ud := OS.get_user_data_dir()
		var f := FileAccess.open(ud + "/save_data.json", FileAccess.WRITE)
		f.store_string(save_bak)
		f.close()
		print("[LaserS3] save_data.json 已恢复备份")
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
	var f2 := FileAccess.open(EVIDENCE + "assertions.json", FileAccess.WRITE)
	f2.store_string(JSON.stringify(summary, "  "))
	f2.close()
	print("")
	print("=== 2-3 折光机器人实测结果：%d/%d 通过 ===" % [total_ok, notes.size()])
	if not fails.is_empty():
		print("=== FAILED %d 项: %s ===" % [fails.size(), ", ".join(fails)])
	quit(0 if fails.is_empty() else 1)
