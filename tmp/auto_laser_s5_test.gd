extends SceneTree
## 第二章 2-5「引光与节制」逻辑实测 harness（2026-10-10，后端测试）
## 断言组：盘装载+柱占格 / 强制定向（双入射角同指向/宽散两形/轴含柱格/普通直射不被吸）/
## 多源同轮柱只扣 1 / 恢复计时（6s 等待 + 3s 步进 + 重复命中重置）/ 预览柱预警（hp=1）/
## 破柱结算序（355+9-50=314 过线又跌破不判胜；-50 钳 0）/ 破柱后入射方向恢复 /
## 章内五关连跑装载 / 重开清场。
## 用法：Godot_console.exe --path . -s res://tmp/auto_laser_s5_test.gd（headless 可跑，截图自动跳过）

const EVIDENCE := "tmp/laser_s5_evidence/"

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
	print("[LaserS5] USER_DATA=", OS.get_user_data_dir())
	DisplayServer.window_set_position(Vector2i(-3000, 0))
	DisplayServer.window_set_size(Vector2i(1024, 768))
	DisplayServer.window_set_title("2-5 引光与节制逻辑实测")
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


func _shot(fname: String) -> void:
	if DisplayServer.get_name() == "headless":
		return  # 无渲染层：截图跳过（逻辑断言不受影响）
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(EVIDENCE + fname))
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
	Settings.set_value("tutorial_done_ch02_s05", false)
	Settings.set_value("skip_pre_level", false)
	SaveSys.cleared_levels.erase("ch02_s05")

	var menu_btn = await _await_btn("选择关卡", 30.0)
	check(menu_btn != null, "BootLoading 正常进主菜单")
	await _click_button("选择关卡")
	await _sec(0.8)
	root.get_node("Main/UILayer/LevelSelect").set_chapter("ch02")
	await _sec(0.5)
	var card = await _await_btn("05", 5.0)
	check(card != null, "2-5 关卡入口可见")
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
	if g == null or g.cells.size() == 0 or GS.current_level_id != "ch02_s05":
		check(false, "ch02_s05 固定盘装载（id=%s cells=%d）" % [GS.current_level_id,
				0 if g == null else g.cells.size()])
		_finish()
		return
	await _phase1_board()
	await _phase2_directed()
	await _phase3_scatter_directed()
	await _phase4_multisource()
	await _phase5_recovery()
	await _phase6_preview()
	await _phase7_break_and_order()
	await _phase8_direction_restored()
	await _phase7b_crossing_no_win()
	await _phase9_chapter_chain()
	_finish()


# ---- 阶段 1：盘装载 + 柱占格 ----
func _phase1_board() -> void:
	print("[Phase1] 盘装载与占格")
	check(g.cells.size() == 256, "16×16=256 格（%d）" % g.cells.size())
	var opened := 0
	for c in g.cells:
		if g.cells[c].is_opened:
			opened += 1
	check(opened == 84, "预开 84 格（%d）" % opened)
	check(GS.bases[0] == Vector2i(1, 7), "固定基地 (1,7)")
	check(FM.pillar != null and FM.pillar.coord == Vector2i(11, 3) and FM.pillar.hp == 6,
			"引光柱就位 (11,3) 耐久 6")
	check(FM.chain_nodes.size() == 3, "连爆节点 3 座")
	check(not g.is_walkable(Vector2i(11, 3)), "柱格不可走（占格门）")
	main.placing_mode = "refractor_scatter"
	check(main.place_block_reason(Vector2i(11, 3)) != "", "折光不可放柱格")
	main.placing_mode = ""
	g.toggle_flag(Vector2i(11, 3), "player")
	check(not g.cells[Vector2i(11, 3)].is_flagged, "柱格右键不可标（免伤对象不存在）")
	var refractors := []
	for r in RM.robots:
		if r.robot_type.begins_with("refractor"):
			refractors.append(r)
	check(refractors.size() == 1 and refractors[0].coord == Vector2i(7, 7),
			"预设宽束折光落 (7,7)")
	check(EM.builders_enabled and EM.builder_wall_sequence == [1, 1, 3], "筑墙工序列 [1,1,3]")
	RM.remove_all()   # 确定性隔离（重放折光；opener/marker 撤场防中途改分）
	RM.spawn_robot(Vector2i(7, 7), "refractor_wide", g)
	await _shot("01-board.png")


# ---- 阶段 2：强制定向（宽束） ----
func _phase2_directed() -> void:
	print("[Phase2] 强制定向")
	var hits0: int = int(GS.result_stats["pillar_hits"])
	# 入射角 A：正东瞄 (12,7)
	var geo: Dictionary = LM.compute_shot_geometry(Vector2i(1, 7), Vector2i(12, 7))
	check(geo.refractor != null and geo.refractor.coord == Vector2i(7, 7), "束过折光（东向入射）")
	var sub_set: Dictionary = {}
	for c in geo.sub:
		sub_set[c] = true
	check(sub_set.has(Vector2i(8, 6)) and sub_set.has(Vector2i(9, 5)) and sub_set.has(Vector2i(10, 4)),
			"定向主轴=折光→柱对角带（(8,6)(9,5)(10,4)）")
	check(geo.cells.has(Vector2i(11, 3)), "柱格必在命中集（轴到柱终止）")
	main._on_laser_fire_requested(Vector2i(12, 7))
	await _sec(0.1)
	check(FM.pillar.hp == 5 and int(GS.result_stats["pillar_hits"]) == hits0 + 1,
			"增幅实际扣柱耐久（6→5）")
	await _shot("02-directed.png")
	# 入射角 B：瞄 (13,6)（入射线斜向下，量化入射仍东）——主轴同样指向柱
	var geo2: Dictionary = LM.compute_shot_geometry(Vector2i(1, 7), Vector2i(13, 6))
	check(geo2.refractor != null and geo2.cells.has(Vector2i(11, 3)),
			"第二入射角主轴仍指向柱（不由点击终点决定）")
	main._on_laser_fire_requested(Vector2i(13, 6))
	await _sec(0.1)
	check(FM.pillar.hp == 4, "再次增幅扣耐久（5→4）")
	# 普通直射不被吸：瞄 (3,4) 不碰折光与柱
	var geo3: Dictionary = LM.compute_shot_geometry(Vector2i(1, 7), Vector2i(3, 4))
	check(geo3.refractor == null and not geo3.cells.has(Vector2i(11, 3)), "普通直射不被柱吸引")
	var hits1: int = int(GS.result_stats["pillar_hits"])
	main._on_laser_fire_requested(Vector2i(3, 4))
	await _sec(0.1)
	check(int(GS.result_stats["pillar_hits"]) == hits1 and FM.pillar.hp == 4,
			"未触折光的直射不扣柱（等待期有事可做）")


# ---- 阶段 3：散射定向 ----
func _phase3_scatter_directed() -> void:
	print("[Phase3] 散射定向")
	var rf = null
	for r in RM.robots:
		if r.robot_type.begins_with("refractor"):
			rf = r
	RM.remove_robot(rf, "test")
	RM.spawn_robot(Vector2i(7, 7), "refractor_scatter", g)
	var geo: Dictionary = LM.compute_shot_geometry(Vector2i(1, 7), Vector2i(12, 7))
	var sub_set: Dictionary = {}
	for c in geo.sub:
		sub_set[c] = true
	check(sub_set.has(Vector2i(9, 5)) and sub_set.has(Vector2i(11, 3)),
			"散射中束连接至柱（含柱格）")
	check(sub_set.has(Vector2i(13, 7)) and sub_set.has(Vector2i(7, 1)),
			"散射侧束=柱轴 ±45° 各长 6（(13,7)(7,1)）")
	main._on_laser_fire_requested(Vector2i(12, 7))
	await _sec(0.1)
	check(FM.pillar.hp == 3, "散射增幅同扣柱（4→3）")
	# 换回宽束（后续阶段确定性）
	var rf2 = null
	for r in RM.robots:
		if r.robot_type.begins_with("refractor"):
			rf2 = r
	RM.remove_robot(rf2, "test")
	RM.spawn_robot(Vector2i(7, 7), "refractor_wide", g)
	await _shot("03-scatter.png")


# ---- 阶段 4：多源同轮合计扣 1 ----
func _phase4_multisource() -> void:
	print("[Phase4] 多源去重")
	# 临时节点 (10,4)：在定向轴上（袋内已开格）——轴命中 + 节点爆炸波及柱，同轮只扣 1
	FM.setup_chain_nodes(g, [Vector2i(10, 4)])
	check(FM.node_at(Vector2i(10, 4)) != null, "临时轴上节点就位")
	var geo: Dictionary = LM.compute_shot_geometry(Vector2i(1, 7), Vector2i(12, 7))
	var node_hit := false
	for n in geo.chain_nodes:
		if n.coord == Vector2i(10, 4):
			node_hit = true
	check(node_hit and geo.cells.has(Vector2i(11, 3)), "同轮轴命中+爆炸波及柱（多源）")
	var hits0: int = int(GS.result_stats["pillar_hits"])
	main._on_laser_fire_requested(Vector2i(12, 7))
	await _sec(0.1)
	check(int(GS.result_stats["pillar_hits"]) == hits0 + 1 and FM.pillar.hp == 2,
			"多束+爆炸同轮柱只扣 1（3→2）")
	check(FM.node_at(Vector2i(10, 4)) == null, "临时节点已消耗")


# ---- 阶段 5：恢复计时（6s 等待 + 3s 步进 + 重复命中重置） ----
func _phase5_recovery() -> void:
	print("[Phase5] 恢复计时")
	var hp0: int = FM.pillar.hp   # 2
	GS.elapsed += 5.0
	FM.tick(3.0, g)
	check(FM.pillar.hp == hp0, "停火 5s 未满等待期（不恢复）")
	GS.elapsed += 1.5            # 距末次受击 6.5s：进入恢复期
	FM.tick(2.9)
	check(FM.pillar.hp == hp0, "恢复期步进未满 3s（不恢复）")
	FM.tick(0.2)
	check(FM.pillar.hp == hp0 + 1, "末次受击后第 9s 首次恢复（+1，实 %d）" % FM.pillar.hp)
	# 重复命中重置等待
	FM.pillar.take_hit()
	check(FM.pillar.hp == hp0, "受击扣 1（恢复被打断回退）")
	GS.elapsed += 5.0
	FM.tick(3.0)
	check(FM.pillar.hp == hp0, "受击重置 6s 等待（5s 不恢复）")


# ---- 阶段 6：预览柱预警 ----
func _phase6_preview() -> void:
	print("[Phase6] 预览预警")
	# 柱压到 hp=1（直接 poke；发射路径已知正确）
	FM.pillar.take_hit()
	check(FM.pillar.hp == 1, "柱压至 hp=1")
	g.cell_hovered.emit(g.get_cell(Vector2i(12, 7)))
	await _sec(0.1)
	var pinfo: Dictionary = g._laser_preview.pillar
	check(not pinfo.is_empty() and pinfo.get("coord") == Vector2i(11, 3) and int(pinfo.get("hp")) == 1,
			"预览携带柱命中预警（coord+hp=1：束段暗红+将破碎文案的数据源）")
	g.cell_unhovered.emit(g.get_cell(Vector2i(12, 7)))


# ---- 阶段 7：破柱结算序（无过线版） ----
func _phase7_break_and_order() -> void:
	print("[Phase7] 破柱结算")
	GS.add_score(200 - GS.score, "test")
	var score0: int = GS.score
	var open0: int = int(GS.result_stats["open_score"]) + int(GS.result_stats["shatter_score"]) \
			+ int(GS.result_stats["cover_wall_score"]) + int(GS.result_stats["flag_score"]) \
			+ int(GS.result_stats["combat_score"])
	main._on_laser_fire_requested(Vector2i(12, 7))
	await _sec(0.1)
	var open1: int = int(GS.result_stats["open_score"]) + int(GS.result_stats["shatter_score"]) \
			+ int(GS.result_stats["cover_wall_score"]) + int(GS.result_stats["flag_score"]) \
			+ int(GS.result_stats["combat_score"])
	var gain: int = open1 - open0
	check(GS.score == score0 + gain - 50, "破柱轮=全部奖励后 -50（实 %d = %d +%d -50）" % [
			GS.score, score0, gain])
	check(int(GS.result_stats["pillar_broken"]) == 1 and FM.pillar == null,
			"柱破碎埋点+管理器收尾")
	check(g.is_walkable(Vector2i(11, 3)), "破碎后柱格恢复通行")
	check(int(GS.score_breakdown.get("pillar", 0)) == -50, "-50 入得分账本（pillar 键）")
	check(GS.game_active, "破柱不结束游戏（继续可玩）")


# ---- 阶段 8：破柱后入射方向恢复 ----
func _phase8_direction_restored() -> void:
	print("[Phase8] 方向恢复")
	var geo: Dictionary = LM.compute_shot_geometry(Vector2i(1, 7), Vector2i(12, 7))
	check(geo.pillar == Vector2i(-9, -9), "碎柱不再定向（快照固化：破碎从下轮生效）")
	var sub_set: Dictionary = {}
	for c in geo.sub:
		sub_set[c] = true
	check(sub_set.has(Vector2i(13, 7)), "折光恢复沿入射方向出射（东向走廊 (13,7)）")
	check(not sub_set.has(Vector2i(11, 3)), "柱格不再入命中集")
	var shots0: int = int(GS.result_stats["shots_fired"])
	main._on_laser_fire_requested(Vector2i(12, 7))
	await _sec(0.1)
	check(int(GS.result_stats["shots_fired"]) == shots0 + 1, "破柱后普通发射照常")


# ---- 阶段 7B：过线又跌破不判胜（355+9-50=314） ----
func _phase7b_crossing_no_win() -> void:
	print("[Phase7B] 破柱结算序·过线版")
	main._on_restart_requested()
	await _sec(1.2)
	RM.remove_all()
	RM.spawn_robot(Vector2i(7, 7), "refractor_wide", g)
	check(FM.pillar != null and FM.pillar.hp == 6, "重开后柱满耐久")
	# 5 发定向增幅把柱压到 1（每发轴必中柱）
	for i in 5:
		main._on_laser_fire_requested(Vector2i(12, 7))
		await _sec(0.05)
	check(FM.pillar.hp == 1, "5 发增幅后柱 hp=1")
	GS.add_score(355 - GS.score, "test")
	check(GS.score == 355, "局分调至 355（过线前 5 分）")
	# 链爆枪：aim (11,2) 直达节点链，爆炸波及柱 → 盘面收益 +n（开格/碎钻合计，含铺垫枪
	# 后的残余格，实测 +8）→ 峰值 355+n ≥360 触发延迟胜利 → -50 跌破 → 分数线复核拦下
	var gain0: int = int(GS.result_stats["open_score"]) + int(GS.result_stats["shatter_score"]) \
			+ int(GS.result_stats["cover_wall_score"]) + int(GS.result_stats["flag_score"]) \
			+ int(GS.result_stats["combat_score"])
	main._on_laser_fire_requested(Vector2i(11, 2))
	await _sec(0.1)
	var gain1: int = int(GS.result_stats["open_score"]) + int(GS.result_stats["shatter_score"]) \
			+ int(GS.result_stats["cover_wall_score"]) + int(GS.result_stats["flag_score"]) \
			+ int(GS.result_stats["combat_score"])
	var n_gain: int = gain1 - gain0
	check(n_gain >= 5 and GS.score == 355 + n_gain - 50 and GS.score < 360,
			"355+%d-50=%d：峰值过线后跌破（同枪扣分完整入账）" % [n_gain, GS.score])
	await _sec(0.3)   # 让 call_deferred 的陈旧胜利跑完
	check(GS.game_active, "过线又跌破不判胜（延迟胜利被分数线复核拦下）")
	check(int(GS.result_stats["pillar_broken"]) == 1, "破柱埋点（新局）")
	await _shot("04-crossing.png")


# ---- 阶段 9：章内五关连跑 + 重开清场 ----
func _phase9_chapter_chain() -> void:
	print("[Phase9] 全章装载")
	var expect := {
		"ch02_s01": [144, 40, 0, false],
		"ch02_s02": [196, 60, 0, false],
		"ch02_s03": [196, 64, 0, false],
		"ch02_s04": [256, 80, 0, false],  # 改版 2026-10-10：连爆节点退场，过载兵种关
		"ch02_s05": [256, 84, 3, true],
	}
	for id in ["ch02_s01", "ch02_s02", "ch02_s03", "ch02_s04", "ch02_s05"]:
		main._start_level(id)
		await _sec(0.6)
		var e: Array = expect[id]
		var opened := 0
		for c in g.cells:
			if g.cells[c].is_opened:
				opened += 1
		check(GS.current_level_id == id and g.cells.size() == e[0] and opened == e[1] \
				and FM.chain_nodes.size() == e[2] and (FM.pillar != null) == e[3],
				"%s 装载（格 %d 预开 %d 节点 %d 柱 %s）" % [id, g.cells.size(), opened,
						FM.chain_nodes.size(), FM.pillar != null])
	# 收尾：s5 重开清场复核
	main._start_level("ch02_s05")
	await _sec(0.8)
	check(FM.pillar != null and FM.pillar.hp == 6 and FM.pillar.is_alive,
			"最终局柱满状态（清场零残留）")
	check(g.facility_cells.size() == 4, "占格表=柱+3 节点（4 格）")
	await _shot("05-final.png")


func _finish() -> void:
	if save_bak != "":
		var ud := OS.get_user_data_dir()
		var f := FileAccess.open(ud + "/save_data.json", FileAccess.WRITE)
		f.store_string(save_bak)
		f.close()
		print("[LaserS5] save_data.json 已恢复备份")
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
	print("=== 2-5 引光与节制实测结果：%d/%d 通过 ===" % [total_ok, notes.size()])
	if not fails.is_empty():
		print("=== FAILED %d 项: %s ===" % [fails.size(), ", ".join(fails)])
	quit(0 if fails.is_empty() else 1)
