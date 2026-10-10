extends SceneTree
## 章节页复活 + 放基地阶段 UI 点击修复 实测（2026-10-11 后端测试）
## 断言组：
##   章节流：选关→章节页（仅 2 个实装章卡，模板桩章不出现）→点第二章→关卡列表
##           （_current_chapter_id 同步）→返回回章节页→返回回主菜单
##   主按钮：直进进度关停在实装章节内（不落模板桩章）
##   暂停修复：ch01_s04 放基地阶段点 HUD 暂停键 → 暂停面板打开且未误放基地；
##           恢复后点盘面中心 → 基地正常落位进入 playing
## 用法：Godot_console.exe --path . --headless -s res://tmp/auto_chapter_flow_test.gd

const EVIDENCE := "tmp/chapter_flow_evidence/"

var step_no := 0
var fails: Array = []
var notes: Array = []
var GS: Node
var SaveSys: Node
var main: Node
var g: Node
var save_bak := ""


func _initialize() -> void:
	print("[ChFlow] USER_DATA=", OS.get_user_data_dir())
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
	Settings.set_value("skip_pre_level", true)  # 主按钮直进断言用（测后恢复原值）

	await _phase1_chapter_page()
	await _phase2_pause_fix()
	_finish()


# ---- 阶段 1：章节页流 ----
func _phase1_chapter_page() -> void:
	print("[Phase1] 章节页流")
	var menu_btn = await _await_btn("选择关卡", 30.0)
	check(menu_btn != null, "BootLoading 正常进主菜单")
	check(await _click_button("选择关卡"), "点「选择关卡」")
	await _sec(0.8)
	main = root.get_node("Main")
	var cs: Node = main.get_node("UILayer/ChapterSelect")
	check(cs.visible, "章节页显示（复活）")
	var cards: Array = []
	for n in cs.get_node("MarginContainer/VBoxContainer/GridContainer").get_children():
		if n is Button:
			cards.append(n.text)
	var card_names: Array = []
	for t in cards:
		card_names.append(t.substr(0, 12))
	check(cards.size() == 2, "仅 2 张章卡（%d）：%s" % [cards.size(),
			" | ".join(card_names)])
	var no_stub := true
	for t in cards:
		if "产业链" in t or "充能塔" in t:
			no_stub = false
	check(no_stub, "模板桩章（产业链/充能塔…）不出现")
	check(await _click_button("激光矿场"), "点「第二章·激光矿场」")
	await _sec(0.6)
	check(not cs.visible and main.get_node("UILayer/LevelSelect").visible,
			"进第二章关卡列表（章节页收起）")
	check(main._current_chapter_id == "ch02", "_current_chapter_id 同步 ch02")
	var card21 := _find_button("01")
	check(card21 != null, "2-1 关卡卡可见")
	# 返回链：关卡列表 → 章节页 → 主菜单
	check(await _click_button("返回"), "关卡列表「返回」")
	await _sec(0.5)
	check(cs.visible, "返回回章节页（非主菜单）")
	check(await _click_button("返回"), "章节页「返回」")
	await _sec(0.5)
	check(main.get_node("UILayer/MainMenu").visible, "章节页返回回主菜单")
	# 主按钮：进度关停在实装章（ch01_s06 未清 → 应直进 1-6 而非任何 ch03+ 桩）
	main._on_continue_play()
	await _sec(0.8)
	var pre: Node = main.get_node("UILayer/PreLevelCard")
	check(pre.visible, "主按钮弹关前卡")
	check(GS.current_level_id == "" or GS.current_level_id.begins_with("ch0"),
			"进度关在实装章内（id=%s）" % GS.current_level_id)
	check(not GS.current_level_id.begins_with("ch03"), "不落模板桩章")


# ---- 阶段 2：放基地阶段暂停修复 ----
func _phase2_pause_fix() -> void:
	print("[Phase2] 放基地暂停修复")
	root.get_node("/root/GameSettings").set_value("tutorial_done_ch01_s04", true)
	main._start_level("ch01_s04")
	await _sec(1.0)
	g = main.grid
	check(GS.game_phase == "placing_base", "ch01_s04 玩家放基地阶段")
	var pause_btn: Button = main.get_node("UILayer/HUD/MarginContainer/VBoxContainer" \
			+ "/TopRow/RightPanel/RightBox/PauseButton")
	check(pause_btn != null and pause_btn.is_visible_in_tree(), "HUD 暂停键可见")
	var rect: Rect2 = pause_btn.get_global_rect()
	var got_sig: Array = [false]
	main.hud.pause_requested.connect(func(): got_sig[0] = true, CONNECT_ONE_SHOT)
	await _inject_click(rect.position + rect.size / 2.0)
	await _sec(0.3)
	check(main.get_node("UILayer/PausePanel").visible, "放基地阶段点暂停键 → 暂停面板打开（修复）")
	check(GS.bases.is_empty(), "点暂停键未误放基地")
	check(await _click_button("继续"), "暂停面板「继续」恢复")
	await _sec(0.3)
	check(not main.get_node("UILayer/PausePanel").visible, "暂停面板关闭")
	check(GS.game_phase == "placing_base", "仍在放基地阶段")
	# 盘面中心点击 → 正常放基地
	var gr: Rect2 = g.get_global_rect()
	await _inject_click(gr.position + gr.size / 2.0)
	await _sec(0.5)
	check(GS.bases.size() == 1, "盘面点击正常放基地（守卫不影响落位）")
	check(GS.game_phase == "playing", "进 playing 阶段")


func _finish() -> void:
	if save_bak != "":
		var ud := OS.get_user_data_dir()
		var f := FileAccess.open(ud + "/save_data.json", FileAccess.WRITE)
		f.store_string(save_bak)
		f.close()
		print("[ChFlow] save_data.json 已恢复备份")
	root.get_node("/root/GameSettings").set_value("skip_pre_level", false)
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
	print("=== 章节页+暂停修复实测结果：%d/%d 通过 ===" % [total_ok, notes.size()])
	if not fails.is_empty():
		print("=== FAILED %d 项: %s ===" % [fails.size(), ", ".join(fails)])
	quit(0 if fails.is_empty() else 1)
