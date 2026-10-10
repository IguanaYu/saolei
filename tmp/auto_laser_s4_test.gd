extends SceneTree
## 第二章 2-4「连爆节点」逻辑实测 harness（2026-10-10，后端测试）
## 断言组：盘装载+节点占格 / 链结算（快照BFS/同格单层/同轮一次/旗格保护/碎钻/覆盖墙/
## 充能例外——爆炸格不充能束格照充）/ 折光走廊引爆 B 组 / 预览整链 / 边角裁切 /
## 节点耗尽后可玩与无设施等价 / 重开清场。
## 用法：Godot_console.exe --path . -s res://tmp/auto_laser_s4_test.gd（headless 可跑，截图自动跳过）

const EVIDENCE := "tmp/laser_s4_evidence/"

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
	print("[LaserS4] USER_DATA=", OS.get_user_data_dir())
	DisplayServer.window_set_position(Vector2i(-3000, 0))
	DisplayServer.window_set_size(Vector2i(1024, 768))
	DisplayServer.window_set_title("2-4 连爆节点逻辑实测")
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
	Settings.set_value("tutorial_done_ch02_s04", false)
	Settings.set_value("skip_pre_level", false)
	SaveSys.cleared_levels.erase("ch02_s04")

	var menu_btn = await _await_btn("选择关卡", 30.0)
	check(menu_btn != null, "BootLoading 正常进主菜单")
	await _click_button("选择关卡")
	await _sec(0.8)
	root.get_node("Main")._on_chapter_selected("ch02")  # 2026-10-11 章节页复活：选关后经章节页选章
	await _sec(0.5)
	var card = await _await_btn("04", 5.0)
	check(card != null, "2-4 关卡入口可见")
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
	if g == null or g.cells.size() == 0 or GS.current_level_id != "ch02_s04":
		check(false, "ch02_s04 固定盘装载（id=%s cells=%d）" % [GS.current_level_id,
				0 if g == null else g.cells.size()])
		_finish()
		return
	await _phase1_board()
	await _phase2_chain_rules()
	await _phase3_b_group()
	await _phase4_edges_and_playable()
	await _phase5_restart()
	_finish()


# ---- 阶段 1：盘装载 + 节点占格 ----
func _phase1_board() -> void:
	print("[Phase1] 盘装载与占格")
	check(g.cells.size() == 256, "16×16=256 格（%d）" % g.cells.size())
	var opened := 0
	for c in g.cells:
		if g.cells[c].is_opened:
			opened += 1
	check(opened == 80, "预开 80 格（%d）" % opened)
	check(GS.bases[0] == Vector2i(1, 7), "固定基地 (1,7)")
	check(FM.chain_nodes.size() == 6, "连爆节点 6 座（%d）" % FM.chain_nodes.size())
	var nodes_on_preopen := true
	for n in FM.chain_nodes:
		if not g.cells[n.coord].is_opened or g.facility_cells.has(n.coord) != true:
			nodes_on_preopen = false
	check(nodes_on_preopen, "节点全在预开安全格且占格生效")
	var refractors := []
	for r in RM.robots:
		if r.robot_type.begins_with("refractor"):
			refractors.append(r)
	check(refractors.size() == 1 and refractors[0].coord == Vector2i(7, 7),
			"预设宽束折光落 (7,7)")
	check(EM.builders_enabled and EM.builder_wall_sequence == [1, 1, 3], "筑墙工序列 [1,1,3]")
	# 占格门：不可走 / 折光不可放 / 开局赠机不站节点格
	check(not g.is_walkable(Vector2i(5, 3)), "节点格不可走（is_walkable 门）")
	main.placing_mode = "refractor_scatter"
	check(main.place_block_reason(Vector2i(5, 3)) != "", "折光不可放节点格")
	main.placing_mode = ""
	check(g.is_walkable(Vector2i(4, 6)), "普通预开格照常可走")
	await _shot("01-board.png")


# ---- 阶段 2：A 组教学链（快照 BFS / 同格单层 / 同轮一次 / 覆盖墙 / 充能例外） ----
func _phase2_chain_rules() -> void:
	print("[Phase2] A 组教学链")
	RM.remove_all()   # 确定性隔离（opener/marker 撤场；折光保留在预设驻点）
	# 覆盖墙样本：(4,3) 在 A 组爆炸盒内、不在束上
	g.get_cell(Vector2i(4, 3)).place_cover_wall(1)
	# 充能例外样本：opener 站束格 (3,6)；opener2 站纯爆炸格 (4,2)（同枪被炸开，逻辑测试用）
	var opener = RM.spawn_robot(Vector2i(3, 6), "opener", g)
	var opener2 = RM.spawn_robot(Vector2i(4, 2), "opener", g)
	# 快照断言：束命中 (5,3) → 链展开三座 A 节点；B 组不入链
	var geo: Dictionary = LM.compute_shot_geometry(Vector2i(1, 7), Vector2i(5, 3))
	var chain_set: Dictionary = {}
	for n in geo.chain_nodes:
		chain_set[n.coord] = true
	check(chain_set.has(Vector2i(5, 3)) and chain_set.has(Vector2i(6, 3)) and chain_set.has(Vector2i(6, 4)),
			"A 组三座同轮全触发（快照 BFS）")
	check(not chain_set.has(Vector2i(8, 6)) and not chain_set.has(Vector2i(8, 8)) and not chain_set.has(Vector2i(7, 10)),
			"B 组不被 A 组无预览引爆（两组隔离）")
	check(geo.cells.has(Vector2i(4, 2)) and geo.cells.has(Vector2i(7, 3)),
			"总命中集含爆炸盒格（束 ∪ 整链）")
	check(not geo.main.has(Vector2i(4, 2)), "束格与爆炸格分字段（(4,2) 非束格）")
	# 预览整链（悬停喂线：预览格集=geo.cells、节点格描边）
	g.cell_hovered.emit(g.get_cell(Vector2i(5, 3)))
	await _sec(0.1)
	check(g._laser_preview.visible and g._laser_preview.cells.has(Vector2i(4, 2)),
			"预览含整条链范围（=结算同源）")
	var mark_ok: bool = g._laser_preview.marks.size() == 3
	for m in g._laser_preview.marks:
		if not chain_set.has(m):
			mark_ok = false
	check(mark_ok, "预览节点格专属描边（3 座 A 节点）")
	g.cell_unhovered.emit(g.get_cell(Vector2i(5, 3)))
	# 发射：教学盒 5 面 1 层普通墙全开（+5 分）；覆盖墙 1 层归零（+1 分 +1 金）
	var score0: int = GS.score
	var money0: int = GS.money
	var cover0: int = int(GS.result_stats["cover_walls_destroyed"])
	main._on_laser_fire_requested(Vector2i(5, 3))
	await _sec(0.1)
	var a_box := [Vector2i(4, 2), Vector2i(5, 2), Vector2i(6, 2), Vector2i(7, 2), Vector2i(7, 3)]
	var all_open := true
	for c in a_box:
		if not g.cells[c].is_opened:
			all_open = false
	check(all_open, "教学爆炸盒 5 面普通墙全开")
	check(GS.score == score0 + 26 and GS.money == money0 + 26,
			"开格 +5 + 零连开洪水 +20 + 覆盖墙 +1（分/金各 +26，实 %d/%d）" % [GS.score - score0, GS.money - money0])
	check(int(GS.result_stats["cover_walls_destroyed"]) == cover0 + 1, "爆炸削覆盖墙归零照发")
	# 节点消耗与占格解除（Q2：消耗后空格恢复普通）
	var consumed_a := true
	for n in FM.chain_nodes:
		if n.coord in [Vector2i(5, 3), Vector2i(6, 3), Vector2i(6, 4)] and not n.consumed:
			consumed_a = false
	check(consumed_a, "A 组三座全部消耗")
	check(g.is_walkable(Vector2i(5, 3)), "消耗后格恢复可走")
	# 充能例外：束格 opener 充能、纯爆炸格 opener 不充能（总纲 §6.3）
	check(opener.is_charged() and not opener2.is_charged(),
			"充能只认束格（爆炸格不充能）")
	# 同轮一次：同目标再射 → 空链、无重复收益
	var score1: int = GS.score
	var geo2: Dictionary = LM.compute_shot_geometry(Vector2i(1, 7), Vector2i(5, 3))
	check(geo2.chain_nodes.is_empty(), "已消耗节点不再触发（销毁态幂等）")
	main._on_laser_fire_requested(Vector2i(5, 3))
	await _sec(0.1)
	check(GS.score == score1, "二次同射零新增收益")
	await _shot("02-groupA.png")


# ---- 阶段 3：折光走廊引爆 B 组（重叠去重 / 旗格保护 / 碎钻） ----
func _phase3_b_group() -> void:
	print("[Phase3] B 组与折光走廊")
	# 预设折光重放（Phase2 开头 remove_all 撤场过；走廊射击需要它在 (7,7)）
	RM.spawn_robot(Vector2i(7, 7), "refractor_wide", g)
	# 旗保护样本：(8,9) 是 B 组爆炸盒内的钻石（雷位）——先标记
	g.toggle_flag(Vector2i(8, 9), "robot_marker")
	check(g.cells[Vector2i(8, 9)].is_flagged, "样本钻石 (8,9) 已插旗")
	# 走廊射击：基地→(13,7) 过折光 (7,7)，宽束走廊含 (8,6)(8,8) 两座 B 节点
	var geo: Dictionary = LM.compute_shot_geometry(Vector2i(1, 7), Vector2i(13, 7))
	var b_set: Dictionary = {}
	for n in geo.chain_nodes:
		b_set[n.coord] = true
	check(b_set.has(Vector2i(8, 6)) and b_set.has(Vector2i(8, 8)) and not b_set.has(Vector2i(7, 10)),
			"折光走廊点燃 B 组两座（(7,10) 不在走廊内）")
	var peel0: int = int(GS.result_stats["layers_peeled"])
	main._on_laser_fire_requested(Vector2i(13, 7))
	await _sec(0.1)
	# 重叠去重：(9,7) 同轮被走廊束 + (8,6) 爆炸 + (8,8) 爆炸覆盖 → 只削 1 层（3→2）
	check(int(g.cells[Vector2i(9, 7)].wall_hp) == 2,
			"束+双爆炸重叠同格只削 1 层（3→2，实 %d）" % int(g.cells[Vector2i(9, 7)].wall_hp))
	check(int(GS.result_stats["layers_peeled"]) == peel0 + 15,
			"走廊 13 面加固+双爆炸补 (9,5)(9,9) 共削 15 面（去重后，实 +%d）" % (int(GS.result_stats["layers_peeled"]) - peel0))
	check(g.cells[Vector2i(8, 9)].is_flagged and not g.cells[Vector2i(8, 9)].is_collapsed,
			"旗格钻石在爆炸中受保护（不碎不开）")
	await _shot("03-corridor.png")
	# 第三座 (7,10)：直射引爆——(8,10)(8,11) 未标钻石碎（+1×2 不扣命），(7,11) 开格
	var score0: int = GS.score
	var shatter0: int = int(GS.result_stats["diamonds_shattered"])
	main._on_laser_fire_requested(Vector2i(7, 10))
	await _sec(0.1)
	check(g.cells[Vector2i(8, 10)].is_collapsed and g.cells[Vector2i(8, 11)].is_collapsed,
			"未标钻石被爆炸误打碎（低收益坍塌）")
	check(int(GS.result_stats["diamonds_shattered"]) == shatter0 + 2, "碎钻埋点 +2")
	check(GS.score == score0 + 3, "(7,11) 开格 +1 与碎钻 +2（实 +%d）" % (GS.score - score0))
	check(GS.lives == 0, "碎钻不扣命（无命关口径）")


# ---- 阶段 4：边角裁切 / 节点耗尽后可玩 / 无设施等价 ----
func _phase4_edges_and_playable() -> void:
	print("[Phase4] 边角与收尾")
	# 临时边角节点 (0,10)：3×3 出界裁切
	FM.setup_chain_nodes(g, [Vector2i(0, 10)])
	check(FM.node_at(Vector2i(0, 10)) != null, "临时边角节点就位")
	var geo: Dictionary = LM.compute_shot_geometry(Vector2i(1, 7), Vector2i(0, 10))
	var in_bounds := true
	for c in geo.chain_cells:
		if c.x < 0 or c.y < 0:
			in_bounds = false
	check(in_bounds and geo.chain_cells.has(Vector2i(1, 11)),
			"边角爆炸盒出界裁切（含 (1,11)，无负坐标）")
	main._on_laser_fire_requested(Vector2i(0, 10))
	await _sec(0.1)
	check(FM.node_at(Vector2i(0, 10)) == null, "边角节点正常消耗")
	# 节点耗尽后普通流程继续可玩（不软锁）
	var shots0: int = int(GS.result_stats["shots_fired"])
	main._on_laser_fire_requested(Vector2i(3, 5))
	await _sec(0.1)
	check(int(GS.result_stats["shots_fired"]) == shots0 + 1, "节点耗尽后普通发射照常")
	check(GS.game_active, "局面继续活跃（无软锁）")
	# 无设施等价：清空设施后 chain 恒空（ch01/2-1~2-3 行为不变的结构保证）
	FM.clear()
	var geo3: Dictionary = LM.compute_shot_geometry(Vector2i(1, 7), Vector2i(5, 3))
	check(geo3.chain_nodes.is_empty() and geo3.chain_cells.is_empty(),
			"无设施关 ShotGeometry 链字段恒空（等价性）")


# ---- 阶段 5：重开清场 ----
func _phase5_restart() -> void:
	print("[Phase5] 重开")
	main._on_restart_requested()
	await _sec(1.2)
	check(GS.score == 0 and GS.game_active, "重开新局")
	check(FM.chain_nodes.size() == 6, "节点重置 6 座（临时边角节点已清）")
	var all_alive := true
	for n in FM.chain_nodes:
		if n.consumed:
			all_alive = false
	check(all_alive, "重开后全部未消耗")
	check(g.facility_cells.size() == 6, "占格表重建（6 格）")
	check(int(g.cells[Vector2i(9, 7)].wall_hp) == 3, "东墙带复位 3 层")
	var refractors := 0
	for r in RM.robots:
		if r.robot_type.begins_with("refractor"):
			refractors += 1
	check(refractors == 1, "预设折光重放")
	await _shot("04-restarted.png")


func _finish() -> void:
	if save_bak != "":
		var ud := OS.get_user_data_dir()
		var f := FileAccess.open(ud + "/save_data.json", FileAccess.WRITE)
		f.store_string(save_bak)
		f.close()
		print("[LaserS4] save_data.json 已恢复备份")
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
	print("=== 2-4 连爆节点实测结果：%d/%d 通过 ===" % [total_ok, notes.size()])
	if not fails.is_empty():
		print("=== FAILED %d 项: %s ===" % [fails.size(), ", ".join(fails)])
	quit(0 if fails.is_empty() else 1)
