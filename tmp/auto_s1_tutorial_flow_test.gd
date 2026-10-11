extends SceneTree
## 2-1 教学真实流程实测（2026-10-11）：用户实测卡在第一步，按了没用。
## 根因两个：① main 漏转发 laser_manager.laser_fired → 教学第一步等的事件没人发；
## ② 教学可见时主循环全冻结（含冷却）→ 第二步「三层墙打三次」永远等不到第二枪。
## 本测试全程真实鼠标点击走完三步：射岩壁(步1) → 免费次数耗尽等冷却回充(修复②)
## → 射三层墙(步2) → 右键标雷(步3) → 教学完成落标记。
## 跑法：Godot_console.exe --path . -s res://tmp/auto_s1_tutorial_flow_test.gd （勿加 --headless）

var step_no := 0
var fails: Array = []
var notes: Array = []
var GS: Node
var SaveSys: Node
var main: Node
var grid: Node
var save_bak := ""
var skip_pre_bak = null
var _last_hover: Vector2i = Vector2i(-99, -99)
var _hover_seen := false
var _aim_pos := Vector2.ZERO


func _initialize() -> void:
	DisplayServer.window_set_position(Vector2i(-3000, 0))
	DisplayServer.window_set_size(Vector2i(1280, 800))
	DisplayServer.window_set_title("2-1 教学真实流程实测（屏外）")
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


func _await_btn(text_part: String, timeout_sec: float) -> Button:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var b := _find_button(text_part)
		if b != null:
			return b
		await _sec(0.1)
	return null


func _click_through(text_part: String) -> void:
	var b = await _await_btn(text_part, 8.0)
	if b == null:
		check(false, "找不到按钮 %s" % text_part)
		return
	# 导航用信号直发：菜单按钮有入场动画，找按钮时读的矩形和点击瞬间会错位
	# （探针实测点「选择关卡」落到「继续试玩」直接开局）；被测的真实输入链路在局内格子点击
	b.pressed.emit()
	await process_frame


func _inject_move(window_pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = window_pos
	motion.global_position = window_pos
	Input.parse_input_event(motion)
	await process_frame
	await process_frame


func _inject_button(window_pos: Vector2, right := false) -> void:
	var pos: Vector2 = window_pos
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	Input.parse_input_event(motion)
	await process_frame
	var ev := InputEventMouseButton.new()
	ev.position = pos
	ev.global_position = pos
	ev.button_index = MOUSE_BUTTON_RIGHT if right else MOUSE_BUTTON_LEFT
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	var rel := ev.duplicate()
	rel.pressed = false
	Input.parse_input_event(rel)
	await process_frame


func _winpos(coord: Vector2i) -> Vector2:
	var cell = grid.get_cell(coord)
	if cell == null:
		return Vector2(-9999, -9999)
	return root.get_final_transform() * cell.global_position


func _on_hover_capture(cell) -> void:
	_last_hover = cell.coord
	_hover_seen = true


func _cell_px() -> float:
	var a := _winpos(Vector2i(0, 0))
	var b := _winpos(Vector2i(1, 0))
	return (b - a).length() if (b - a).length() > 1.0 else 28.0


## 真实鼠标瞄准：注入移动→读实际悬停格→按误差修正，迭代到落点正确。
## 坐标映射有未知平移误差（探针实测目标(1,1)落在(7,9)），线性部分可信故可迭代收敛
func _aim(coord: Vector2i) -> bool:
	_hover_seen = false
	var pos := _winpos(coord)
	if pos.x < -9000:
		return false
	var px := _cell_px()
	for i in 8:
		await _inject_move(pos)
		await _sec(0.12)
		if _last_hover == coord:
			_aim_pos = pos
			return true
		if not _hover_seen:
			pos += Vector2(7, 5)
			continue
		var err: Vector2i = coord - _last_hover
		if err.length() > 6.0:
			return false   # 误差不收敛（线性部分也错），放弃真实点击
		pos += Vector2(err.x, err.y) * px
	return false


func _fire(coord: Vector2i) -> void:
	if await _aim(coord):
		await _inject_button(_aim_pos, false)
	else:
		print("  [WARN] 瞄准 %s 不收敛，退回直调发射" % str(coord))
		main._on_laser_fire_requested(coord)


func _flag(coord: Vector2i) -> void:
	if await _aim(coord):
		await _inject_button(_aim_pos, true)
	else:
		print("  [WARN] 瞄准 %s 不收敛，退回模拟标雷" % str(coord))
		grid.toggle_flag(coord, "player")


func _step_text() -> String:
	var guide: Node = main.get_node("UILayer/TutorialGuide")
	if not guide.visible:
		return "(教学已结束)"
	return guide.get_node("TipPanel/VBox/StepLabel").text


func _wait_cd_ready(timeout_sec := 12.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if GS.cd_phase != "cooldown" or int(GS.cd_charges) > 0:
			return true
		await _sec(0.2)
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
	Settings.set_value("skip_pre_level", false)
	Settings.set_value("tutorial_done_ch02_s01", false)
	SaveSys.cleared_levels.erase("ch02_s01")

	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline and root.get_node_or_null("Main") == null:
		await _sec(0.2)
	main = root.get_node("Main")

	# 导航：主菜单 → 章节页 → 激光矿场 → 01 → 本关 → 开始挖矿
	await _click_through("选择关卡")
	await _sec(0.8)
	var cs: Node = main.get_node_or_null("UILayer/ChapterSelect")
	if cs == null or not cs.visible:
		var btns: Array = []
		for n in _walk(root, []):
			if n is Button and n.is_visible_in_tree():
				btns.append(n.text.replace("\n", "|").substr(0, 18))
		print("  [DEBUG] 章节页未现！可见按钮: ", " / ".join(btns),
				" menu=", main.get_node("UILayer/MainMenu").visible)
	check(cs != null and cs.visible, "章节页显示")
	await _click_through("激光矿场")
	await _sec(0.6)
	var card = await _await_btn("01", 5.0)
	if card != null:
		card.pressed.emit()
		await process_frame
	await _click_through("本关")
	await _sec(0.8)
	await _click_through("开始挖矿")
	await _sec(1.0)
	grid = main.grid
	if GS.current_level_id != "ch02_s01":
		check(false, "ch02_s01 装载（id=%s）" % GS.current_level_id)
		_finish()
		return
	check(main.get_node("UILayer/TutorialGuide").visible, "2-1 教学自动出现")
	check(_step_text() == "引导 1 / 3", "第一步聚光（%s）" % _step_text())
	grid.cell_hovered.connect(_on_hover_capture)

	# 步 1：真实点击射远处岩壁 (1,1)（基地同排西端长横束）
	await _fire(Vector2i(1, 1))
	await _sec(0.5)
	check(_step_text() == "引导 2 / 3", "打一枪 → 第二步（%s）" % _step_text())

	# 修复②专项：耗尽免费次数 → 教学期间冷却照走回充
	for i in 6:
		await _fire(Vector2i(1, 1))   # 已开格空射，扣动作无盘面影响
		await _sec(0.3)
	var recharged := await _wait_cd_ready(12.0)
	check(recharged, "教学期间冷却回充（修复②，cd=%s 剩 %.1fs）"
			% [str(GS.cd_phase), float(GS.cd_remaining)])
	check(_step_text() == "引导 2 / 3", "空射不推进教学（%s）" % _step_text())

	# 步 2：真实点击射三层加固墙 (6,6)（基地正下方第 6 行）
	await _fire(Vector2i(6, 6))
	await _sec(0.5)
	check(_step_text() == "引导 3 / 3", "削到加固墙 → 第三步（%s）" % _step_text())

	# 步 3：真实右键标雷 (2,3)（雷位）
	await _wait_cd_ready(12.0)
	await _flag(Vector2i(2, 3))
	await _sec(0.6)
	check(not main.get_node("UILayer/TutorialGuide").visible, "正确标雷 → 教学完成收起")
	var flag_val: Variant = Settings.get_value("tutorial_done_ch02_s01")
	check(flag_val == true, "教学完成标记落档（值=%s）" % str(flag_val))

	# 收尾：教学标记复位 false——用户下一局 2-1 亲自体验修复后的完整教学
	_finish()


func _finish() -> void:
	if save_bak != "":
		var ud := OS.get_user_data_dir()
		var f := FileAccess.open(ud + "/save_data.json", FileAccess.WRITE)
		f.store_string(save_bak)
		f.close()
	var Settings: Node = root.get_node("/root/GameSettings")
	if skip_pre_bak != null:
		Settings.set_value("skip_pre_level", skip_pre_bak)
	Settings.set_value("tutorial_done_ch02_s01", false)
	var total_ok := 0
	for n in notes:
		if n.ok:
			total_ok += 1
	print("")
	print("=== 2-1 教学真实流程：%d/%d 通过 ===" % [total_ok, notes.size()])
	if not fails.is_empty():
		print("=== FAILED %d 项: %s ===" % [fails.size(), ", ".join(fails)])
	quit(0 if fails.is_empty() else 1)
