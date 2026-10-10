extends SceneTree
## 第二章 2-3 矿石 / 2-4 过载 真实画面走查（2026-10-11 重写，替代旧连爆版 winflow 的 s4 部分）
## 不开 --headless：真实渲染 + 截图，跑完人工看图验收画面表现（特效位置/实体样子/结算行）。
## 流程：主菜单→章节页(两卡)→激光矿场→2-3 打两枪矿石+暂停面板→结算；
##       →2-4 买过载→巡逻→引爆→买扩爆→再引爆→结算。
## 窗口放屏外 (-3000,0) 不打扰使用者（项目既有惯例）。跑法：
## Godot_console.exe --path . -s res://tmp/auto_s3_s4_window_test.gd （勿加 --headless）

const EVIDENCE := "tmp/s3_s4_window_evidence/"

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
var skip_pre_bak = null
var tut03_bak = null
var tut04_bak = null


func _initialize() -> void:
	print("[WindowWalk] USER_DATA=", OS.get_user_data_dir())
	DisplayServer.window_set_position(Vector2i(-3000, 0))
	DisplayServer.window_set_size(Vector2i(1280, 800))
	DisplayServer.window_set_title("2-3/2-4 真实画面走查（屏外）")
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


func _shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(EVIDENCE + fname))
	print("  [SHOT] ", fname)


func _find_label(part: String) -> bool:
	for n in _walk(root, []):
		if n is Label and part in n.text:
			return true
	return false


func _run() -> void:
	await _sec(1.5)
	GS = root.get_node("/root/GameState")
	SaveSys = root.get_node("/root/SaveSystem")
	var Settings: Node = root.get_node("/root/GameSettings")
	var ud := OS.get_user_data_dir()
	if FileAccess.file_exists(ud + "/save_data.json"):
		var f := FileAccess.open(ud + "/save_data.json", FileAccess.READ)
		save_bak = f.get_as_text()
		f.close()
	skip_pre_bak = Settings.get_value("skip_pre_level")
	tut03_bak = Settings.get_value("tutorial_done_ch02_s03")
	tut04_bak = Settings.get_value("tutorial_done_ch02_s04")
	Settings.set_value("skip_pre_level", false)
	Settings.set_value("tutorial_done_ch02_s03", false)
	Settings.set_value("tutorial_done_ch02_s04", false)
	SaveSys.cleared_levels.erase("ch02_s03")
	SaveSys.cleared_levels.erase("ch02_s04")

	# ---- 导航：主菜单 → 章节页 → 激光矿场 → 2-3 ----
	var menu_btn = await _await_btn("选择关卡", 30.0)
	check(menu_btn != null, "进主菜单")
	await _shot("00-menu.png")
	check(await _click_button("选择关卡"), "点「选择关卡」")
	await _sec(0.8)
	main = root.get_node("Main")
	var cs: Node = main.get_node("UILayer/ChapterSelect")
	check(cs.visible, "章节页显示")
	await _shot("01-chapters.png")
	var cards: Array = []
	for n in cs.get_node("MarginContainer/VBoxContainer/GridContainer").get_children():
		if n is Button:
			cards.append(n.text.substr(0, 10))
	check(cards.size() == 2, "两张章卡：%s" % " | ".join(cards))
	check(await _click_button("激光矿场"), "选「激光矿场」")
	await _sec(0.6)
	var card = await _await_btn("03", 5.0)
	check(card != null, "2-3 入口可见")
	if card != null:
		var r: Rect2 = card.get_global_rect()
		await _inject_click(r.position + r.size / 2.0)
	check(await _click_button("本关"), "开始本关")
	await _sec(0.8)
	var prec = await _await_btn("开始挖矿", 5.0)
	if prec != null:
		check(await _click_button("开始挖矿"), "开始挖矿")
	await _sec(1.0)
	g = main.grid
	LM = main.laser_manager
	RM = main.robot_manager
	FM = main.facility_manager
	if GS.current_level_id != "ch02_s03":
		check(false, "ch02_s03 装载（id=%s）" % GS.current_level_id)
		_finish()
		return

	# ---- 2-3：教学 → 矿石两枪 → 暂停面板 → 结算 ----
	var guide: Node = main.get_node("UILayer/TutorialGuide")
	await _shot("02-s3-tutorial.png")
	check(guide.visible, "开局聚光教学可见")
	guide.call("_finish")
	await _sec(0.4)
	main._on_laser_fire_requested(Vector2i(13, 7))   # 第 7 行直射矿石 A
	await _shot("03-s3-ore1.png")
	main._on_laser_fire_requested(Vector2i(13, 7))
	await _shot("04-s3-ore2.png")
	check(int(GS.result_stats["ore_bursts"]) >= 2, "矿石触发 ≥2 次（%d）"
			% int(GS.result_stats["ore_bursts"]))
	# 暂停面板（放基地修复同类路径：普通局内点暂停键）
	var pause_btn: Button = main.get_node("UILayer/HUD/MarginContainer/VBoxContainer" \
			+ "/TopRow/RightPanel/RightBox/PauseButton")
	var pr: Rect2 = pause_btn.get_global_rect()
	await _inject_click(pr.position + pr.size / 2.0)
	await _sec(0.4)
	check(main.get_node("UILayer/PausePanel").visible, "点暂停键 → 面板开")
	await _shot("05-s3-pause.png")
	check(await _click_button("继续"), "继续游戏")
	await _sec(0.4)
	# 直达结算：补分到目标线（真实结算链路，来源 other 不入明细账）
	GS.add_score(300 - GS.score + 1, "other")
	await _sec(1.6)
	await _shot("06-s3-results.png")
	check(_find_label("特殊矿石"), "结算含「特殊矿石」行")
	check(_find_label("触发爆发"), "结算行有次数文案")

	# ---- 2-4：下一关进入 → 买过载 → 巡逻 → 引爆 → 扩爆 → 再引爆 → 结算 ----
	var next_btn = await _await_btn("下一关", 6.0)
	if next_btn != null:
		check(await _click_button("下一关"), "结算「下一关」进 2-4")
		var prec4 = await _await_btn("开始挖矿", 6.0)
		if prec4 != null:
			check(await _click_button("开始挖矿"), "2-4 开始挖矿")
	else:
		root.get_node("Main")._start_level("ch02_s04")
	await _sec(1.2)
	check(GS.current_level_id == "ch02_s04", "ch02_s04 装载")
	guide.call("_finish")
	await _sec(0.5)
	await _shot("07-s4-tutorial-board.png")
	GS.add_money(200)
	check(await _click_button("过载"), "商店购「过载」")
	await _sec(3.5)   # 巡逻走几步
	await _shot("08-s4-patrol.png")
	var ov = null
	for r2 in RM.robots:
		if r2.robot_type == "overload":
			ov = r2
	check(ov != null, "过载机器人在场")
	if ov != null and ov.coord == GS.bases[0]:
		ov.snap_to(GS.bases[0] + Vector2i(2, 0), g)
	await _sec(0.2)
	main._on_laser_fire_requested(ov.coord)
	await _shot("09-s4-blast.png")
	check(int(GS.result_stats["overload_blasts"]) >= 1, "过载引爆 ≥1 次")
	check(await _click_button("扩爆"), "商店购「扩爆」")
	await _sec(0.6)
	main._on_laser_fire_requested(ov.coord)
	await _shot("10-s4-blast17.png")
	check(int(GS.result_stats["overload_blasts"]) >= 2, "扩爆后引爆照常（%d）"
			% int(GS.result_stats["overload_blasts"]))
	GS.add_score(325 - GS.score + 1, "other")
	await _sec(1.6)
	await _shot("11-s4-results.png")
	check(_find_label("过载机器人"), "结算含「过载机器人」行")
	_finish()


func _finish() -> void:
	if save_bak != "":
		var ud := OS.get_user_data_dir()
		var f := FileAccess.open(ud + "/save_data.json", FileAccess.WRITE)
		f.store_string(save_bak)
		f.close()
		print("[WindowWalk] save_data.json 已恢复备份")
	var Settings: Node = root.get_node("/root/GameSettings")
	if skip_pre_bak != null:
		Settings.set_value("skip_pre_level", skip_pre_bak)
	if tut03_bak != null:
		Settings.set_value("tutorial_done_ch02_s03", tut03_bak)
	if tut04_bak != null:
		Settings.set_value("tutorial_done_ch02_s04", tut04_bak)
	var total_ok := 0
	for n in notes:
		if n.ok:
			total_ok += 1
	var summary := {
		"date": "2026-10-11",
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
	print("=== 2-3/2-4 真实画面走查：%d/%d 通过，截图 %d 张（%s）==="
			% [total_ok, notes.size(), 12, EVIDENCE])
	if not fails.is_empty():
		print("=== FAILED %d 项: %s ===" % [fails.size(), ", ".join(fails)])
	quit(0 if fails.is_empty() else 1)
