extends SceneTree
## 改版结算行实测（WP6a，2026-10-10 headless）：s3 矿石行 / s4 过载行真实数据流验证。
## 流程：进 s3 → 跳教学 → 真打两枪矿石 → 触发结算 → 断言「特殊矿石 触发爆发 2 次」行；
##       切 s4 → 买过载 → 真打一枪引爆 → 结算 → 断言「过载机器人 引爆 1 次」行。
## （真窗截图版 winflow 见 tmp/auto_laser_s45_winflow.gd，随 s4 重摆待用户空闲后重跑）
## 用法：Godot_console.exe --path . --headless -s res://tmp/auto_settlement_rows_test.gd

const EVIDENCE := "tmp/settlement_rows_evidence/"

var step_no := 0
var fails: Array = []
var notes: Array = []
var GS: Node
var SaveSys: Node
var main: Node
var g: Node
var LM: Node
var RM: Node
var FM: Node
var save_bak := ""


func _initialize() -> void:
	print("[Rows] USER_DATA=", OS.get_user_data_dir())
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


func _find_label_text(part: String) -> String:
	for n in _walk(root, []):
		if n is Label and part in n.text:
			return n.text
	return ""


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
	SaveSys.cleared_levels.erase("ch02_s04")

	var menu_btn = await _await_btn("选择关卡", 30.0)
	check(menu_btn != null, "BootLoading 正常进主菜单")
	await _click_button("选择关卡")
	await _sec(0.8)
	root.get_node("Main")._on_chapter_selected("ch02")  # 2026-10-11 章节页复活：选关后经章节页选章
	await _sec(0.5)
	var card = await _await_btn("03", 5.0)
	check(card != null, "2-3 关卡入口可见")
	if card != null:
		var r: Rect2 = card.get_global_rect()
		await _inject_click(r.position + r.size / 2.0)
	check(await _click_button("本关"), "开始本关（s3）")
	await _sec(0.8)
	var prec = await _await_btn("开始挖矿", 5.0)
	if prec != null:
		check(await _click_button("开始挖矿"), "开始挖矿")
	await _sec(1.0)

	main = root.get_node("Main")
	g = main.grid
	LM = main.laser_manager
	RM = main.robot_manager
	FM = main.facility_manager
	if g == null or GS.current_level_id != "ch02_s03":
		check(false, "ch02_s03 装载（id=%s）" % GS.current_level_id)
		_finish()
		return

	# ---- s3：真打两枪矿石 → 结算行 ----
	RM.remove_all()
	main._on_laser_fire_requested(Vector2i(13, 7))   # 第 7 行束截停于矿石 A
	main._on_laser_fire_requested(Vector2i(13, 7))
	check(int(GS.result_stats["ore_bursts"]) == 2, "两枪矿石（埋点=%d）"
			% int(GS.result_stats["ore_bursts"]))
	GS.game_over.emit("win")
	await _sec(1.2)
	var ore_txt := _find_label_text("特殊矿石")
	check(ore_txt != "" and "2 次" in _find_label_text("触发爆发"),
			"结算行「特殊矿石 触发爆发 2 次」（%s）" % ore_txt)

	# ---- s4：买过载 → 真引爆 → 结算行 ----
	main._start_level("ch02_s04")
	await _sec(1.0)
	check(GS.current_level_id == "ch02_s04", "切至 s4")
	RM.remove_all()
	check(main._buy_and_spawn_robot("overload"), "购入过载")
	var ov = null
	for r in RM.robots:
		if r.robot_type == "overload":
			ov = r
			break
	check(ov != null, "过载在场")
	if ov != null:
		if ov.coord == GS.bases[0]:
			ov.snap_to(GS.bases[0] + Vector2i(2, 0), g)  # 出生在基地格=束长0拒射，挪开
		main._on_laser_fire_requested(ov.coord)   # 束命中过载 → 引爆
		check(int(GS.result_stats["overload_blasts"]) == 1, "一枪引爆（埋点=1）")
	GS.game_over.emit("win")
	await _sec(1.2)
	var ov_txt := _find_label_text("过载机器人")
	check(ov_txt != "" and "1 次" in _find_label_text("引爆"),
			"结算行「过载机器人 引爆 1 次」（%s）" % ov_txt)
	_finish()


func _finish() -> void:
	if save_bak != "":
		var ud := OS.get_user_data_dir()
		var f := FileAccess.open(ud + "/save_data.json", FileAccess.WRITE)
		f.store_string(save_bak)
		f.close()
		print("[Rows] save_data.json 已恢复备份")
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
	print("=== 改版结算行实测结果：%d/%d 通过 ===" % [total_ok, notes.size()])
	if not fails.is_empty():
		print("=== FAILED %d 项: %s ===" % [fails.size(), ", ".join(fails)])
	quit(0 if fails.is_empty() else 1)
