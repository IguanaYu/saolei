extends SceneTree
## 第二章 2-4「过载机器人」改版 E2E 实测（2026-10-10 后端测试）
## 断言组：盘装载（新盘 seed=1697，无节点/折光残留）/ 商店接线（过载开闸·折光隐藏·
## 限购 1）/ 购买出厂（直购直出基地）/ 巡逻域 / 首爆收益（东墙带削层+充能）/
## 无限使用（连打三枪削穿 3 层墙）/ 埋点。
## 用法：Godot_console.exe --path . --headless -s res://tmp/auto_overload_s4_test.gd

const EVIDENCE := "tmp/overload_s4_evidence/"

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
	print("[OverloadS4] USER_DATA=", OS.get_user_data_dir())
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
	Settings.set_value("tutorial_done_ch02_s04", false)
	Settings.set_value("skip_pre_level", false)
	SaveSys.cleared_levels.erase("ch02_s04")

	var menu_btn = await _await_btn("选择关卡", 30.0)
	check(menu_btn != null, "BootLoading 正常进主菜单")
	await _click_button("选择关卡")
	await _sec(0.8)
	root.get_node("Main/UILayer/LevelSelect").set_chapter("ch02")
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
	# 教学停摆门（main._process 见 tutorial_guide.visible 早退）：模拟玩家点跳过，
	# 否则巡逻/CD 计时全冻结（聚光在等 overload_blast 事件）
	main.get_node("UILayer/TutorialGuide").call("_finish")
	await _sec(0.3)
	if g == null or g.cells.size() == 0 or GS.current_level_id != "ch02_s04":
		check(false, "ch02_s04 固定盘装载（id=%s）" % GS.current_level_id)
		_finish()
		return
	await _phase1_board()
	await _phase2_buy_patrol()
	await _phase3_blast_economy()
	_finish()


# ---- 阶段 1：盘装载（新盘：无节点/折光残留）----
func _phase1_board() -> void:
	print("[Phase1] 盘装载")
	check(g.cells.size() == 256, "16×16=256 格（%d）" % g.cells.size())
	var opened := 0
	for c in g.cells:
		if g.cells[c].is_opened:
			opened += 1
	check(opened == 80, "预开 80 格（%d）" % opened)
	check(GS.bases[0] == Vector2i(1, 7), "固定基地 (1,7)")
	check(FM.chain_nodes.is_empty(), "连爆节点退场（空列表）")
	check(FM.ores.is_empty() and FM.pillar == null, "无矿石/无柱（s4 单机制）")
	var refractor_gifts := 0
	for r in RM.robots:
		if r.robot_type.begins_with("refractor"):
			refractor_gifts += 1
	check(refractor_gifts == 0, "折光赠送退场")
	var types: Array = RM.robots.map(func(r): return r.robot_type)
	check(types.has("opener") and types.has("marker") and types.size() == 2,
			"开局赠机 opener+marker（%s）" % str(types))
	check(EM.builders_enabled and EM.builder_wall_sequence == [1, 1, 3], "筑墙工序列 [1,1,3] 沿用")
	# 商店：过载开闸、折光隐藏、价格 100
	check(main.shop.buy_overload_button.visible, "过载按钮可见（extra 开闸）")
	check(not main.shop.buy_refractor_wide_button.visible
			and not main.shop.buy_refractor_scatter_button.visible, "折光两键隐藏")
	check(GS.get_robot_price("overload") == 100, "过载价格 100（拍板 #9）")
	check(GS.is_module_allowed("overload") and not GS.is_module_allowed("refractor_wide"),
			"模块白名单：过载 in / 折光 out")
	check("过载" in main.shop.buy_overload_button.text, "按钮文案含「过载」")


# ---- 阶段 2：购买出厂 + 巡逻域 ----
func _phase2_buy_patrol() -> void:
	print("[Phase2] 购买与巡逻")
	var gold0: int = GS.money
	check(gold0 == 180, "起始金 180（保 100 购入+80 周转）")
	var bought: bool = await _click_button("过载")
	var robots: Array = RM.robots.filter(func(r): return r.robot_type == "overload")
	check(bought and robots.size() == 1, "点「过载」购买 → 出厂 1 台")
	check(GS.money == gold0 - 100, "扣 100 金（余 %d）" % GS.money)
	var ov = robots[0] if robots.size() == 1 else null
	if ov == null:
		return
	var dist_ok: bool = maxi(absi(ov.coord.x - 1), absi(ov.coord.y - 7)) <= 3
	check(dist_ok, "基地旁出厂（coord=%s）" % str(ov.coord))
	# 限购 1：按钮转锁定
	check(GS.get_robot_purchased_count("overload") == 1, "已购计数 1")
	check(main.shop.lock_reason("overload") == "已购满", "限购 1 → 已购满")
	check(main.shop.buy_overload_button.disabled, "购买按钮禁用")
	# 巡逻域：跑 ~8 秒，全程已开空格
	var legal := true
	var moved := false
	var start_coord: Vector2i = ov.coord
	for i in 16:
		await _sec(0.5)
		if not is_instance_valid(ov):
			legal = false
			break
		var cc = g.cells.get(ov.coord)
		if cc == null or not cc.is_opened or cc.is_base or g.facility_cells.has(ov.coord):
			legal = false
		if ov.coord != start_coord:
			moved = true
	check(legal, "巡逻 8s 全在已开空格")
	check(moved, "确有巡逻移动")


# ---- 阶段 3：首爆收益 + 无限使用（东墙带 3 层削穿） ----
func _phase3_blast_economy() -> void:
	print("[Phase3] 爆破经济")
	RM.remove_all()  # 确定性隔离：撤巡逻中的过载与工人，手工摆位
	var ov = RM.spawn_robot(Vector2i(8, 7), "overload", g)  # 预开东缘，3×3 盖 (9,6..8) 东墙带
	var opener = RM.spawn_robot(Vector2i(8, 6), "opener", g)  # 爆炸格充能样本（不在束行）
	var hp970: int = g.get_cell(Vector2i(9, 7)).wall_hp
	check(hp970 == 3, "东墙带 (9,7) 3 层（%d）" % hp970)
	_fire(Vector2i(8, 7))  # 束沿第 7 行截停于过载
	check(g.get_cell(Vector2i(9, 7)).wall_hp == 2 and g.get_cell(Vector2i(9, 6)).wall_hp == 2,
			"首爆削 3×3 内加固墙一层")
	check(g.get_cell(Vector2i(10, 7)).wall_hp == 2, "四正延伸格同削（(10,7) 3→2）")
	if opener != null and is_instance_valid(opener):
		check(opener.is_charged(), "爆炸格充能 opener（拍板 #8）")
	check(is_instance_valid(ov) and RM.robots.has(ov), "爆后存活（拍板 #7）")
	_fire(Vector2i(8, 7))
	check(g.get_cell(Vector2i(9, 7)).wall_hp == 1, "二次引爆续削（无限使用）")
	_fire(Vector2i(8, 7))
	check(g.get_cell(Vector2i(9, 7)).is_opened, "三次引爆削穿开格（3 层→开）")
	check(int(GS.result_stats["overload_blasts"]) == 3, "overload_blasts 埋点 =3")
	check(is_instance_valid(ov), "三连爆后仍存活（常驻移动炮台）")


func _finish() -> void:
	if save_bak != "":
		var ud := OS.get_user_data_dir()
		var f := FileAccess.open(ud + "/save_data.json", FileAccess.WRITE)
		f.store_string(save_bak)
		f.close()
		print("[OverloadS4] save_data.json 已恢复备份")
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
	print("=== 2-4 过载机器人实测结果：%d/%d 通过 ===" % [total_ok, notes.size()])
	if not fails.is_empty():
		print("=== FAILED %d 项: %s ===" % [fails.size(), ", ".join(fails)])
	quit(0 if fails.is_empty() else 1)
