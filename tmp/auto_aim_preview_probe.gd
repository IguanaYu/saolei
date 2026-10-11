extends SceneTree
## 瞄准预览稳定性探针（2026-10-11）：用户报 2-1 激光预览"不是稳定显示"。
## 真窗口（屏外）进 2-1，逐帧采样 LaserPreview.visible 记录所有跳变，
## 关联悬停事件/机器人位置/冷却状态/鼠标位置。纯诊断，不判成败。
## 跑法：Godot_console.exe --path . -s res://tmp/auto_aim_preview_probe.gd （勿加 --headless）

var main: Node
var grid: Node
var GS: Node
var RM: Node
var _last_vis := false
var _log: Array = []
var _t0 := 0
var save_bak := ""
var skip_pre_bak = null
var tut01_bak = null


func _initialize() -> void:
	DisplayServer.window_set_position(Vector2i(-3000, 0))
	DisplayServer.window_set_size(Vector2i(1280, 800))
	DisplayServer.window_set_title("瞄准预览稳定性探针（屏外）")
	change_scene_to_file("res://scenes/ui/BootLoading.tscn")
	call_deferred("_run")


func _now() -> int:
	return Time.get_ticks_msec() - _t0


func _say(msg: String) -> void:
	var line := "[%5d] %s" % [_now(), msg]
	print(line)
	_log.append(line)


func _log_hover(cell) -> void:
	_say("HOVER %s opened=%s" % [str(cell.coord), str(cell.is_opened)])


func _log_unhover(_cell) -> void:
	_say("UNHOVER")


func _on_frame() -> void:
	if grid == null or not is_instance_valid(grid):
		return
	var lp = grid.get_node_or_null("LaserPreview")
	if lp == null:
		return
	if lp.visible != _last_vis:
		_last_vis = lp.visible
		var rob: Array = []
		for r in RM.robots:
			rob.append("%s@%s" % [r.robot_type, str(r.coord)])
		_say("%s vis=%s cd=%s rem=%.1f mouse=%s robots=%s" % [
			"SHOW" if _last_vis else "HIDE", str(_last_vis),
			str(GS.cd_phase), float(GS.cd_remaining),
			str(root.get_mouse_position()), " ".join(rob)])


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


func _inject_move(window_pos: Vector2) -> void:
	var pos: Vector2 = window_pos
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	Input.parse_input_event(motion)
	await process_frame
	await process_frame


func _cell_window_pos(coord: Vector2i) -> Vector2:
	var cell = grid.get_cell(coord)
	if cell == null:
		return Vector2(-9999, -9999)
	var canvas: Vector2 = cell.global_position
	return root.get_final_transform() * canvas


func _hover_cell(coord: Vector2i, offset := Vector2.ZERO) -> void:
	var wp := _cell_window_pos(coord) + offset
	if wp.x < -9000:
		_say("HOVER_SKIP %s 不在盘内" % str(coord))
		return
	await _inject_move(wp)
	await _sec(0.12)


func _run() -> void:
	await _sec(1.5)
	GS = root.get_node("/root/GameState")
	var Settings: Node = root.get_node("/root/GameSettings")
	var SaveSys: Node = root.get_node("/root/SaveSystem")
	var ud := OS.get_user_data_dir()
	if FileAccess.file_exists(ud + "/save_data.json"):
		var f := FileAccess.open(ud + "/save_data.json", FileAccess.READ)
		save_bak = f.get_as_text()
		f.close()
	skip_pre_bak = Settings.get_value("skip_pre_level")
	tut01_bak = Settings.get_value("tutorial_done_ch02_s01")
	Settings.set_value("skip_pre_level", false)
	Settings.set_value("tutorial_done_ch02_s01", false)
	SaveSys.cleared_levels.erase("ch02_s01")

	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline and root.get_node_or_null("Main") == null:
		await _sec(0.2)
	main = root.get_node("Main")

	# 导航：主菜单 → 章节页 → 激光矿场 → 01 → 开始挖矿
	await _click_through("选择关卡")
	await _sec(0.8)
	await _click_through("激光矿场")
	await _sec(0.6)
	var card = await _await_btn("01", 5.0)
	if card != null:
		var r: Rect2 = card.get_global_rect()
		await _inject_click(r.position + r.size / 2.0)
	await _click_through("本关")
	await _sec(0.8)
	await _click_through("开始挖矿")
	await _sec(1.0)
	grid = main.grid
	RM = main.robot_manager
	if GS.current_level_id != "ch02_s01":
		_say("FATAL 未进 2-1（id=%s）" % GS.current_level_id)
		_finish()
		return
	var guide: Node = main.get_node("UILayer/TutorialGuide")
	if guide.visible:
		guide.call("_finish")
	await _sec(0.5)
	_say("关卡就绪 base=%s" % str(GS.bases[0]))

	# 挂探针
	grid.cell_hovered.connect(_log_hover)
	grid.cell_unhovered.connect(_log_unhover)
	RenderingServer.frame_post_draw.connect(_on_frame)
	_last_vis = grid.get_node("LaserPreview").visible
	_t0 = Time.get_ticks_msec()

	var rockA: Vector2i = Vector2i(1, 1)   # 基地同排西端，长横束
	var rockB: Vector2i = Vector2i(4, 1)   # 第二块岩壁

	# T1 静停
	await _hover_cell(rockA)
	_say("T1 静停于 %s 3.5s" % str(rockA))
	await _sec(3.5)

	# T2 原地微抖（不出格）
	_say("T2 微抖 12 次 × 0.25s")
	for i in 12:
		await _hover_cell(rockA, Vector2(2 if i % 2 == 0 else -2, 1))
		await _sec(0.25)

	# T3 相邻已开格往返
	_say("T3 移到已开格 (1,2) 再回 %s" % str(rockA))
	await _hover_cell(Vector2i(1, 2))
	await _sec(1.0)
	await _hover_cell(rockA)
	await _sec(1.0)

	# T4 射一枪 → 冷却中移到第二块岩壁
	_say("T4 射 %s 后冷却中移 %s" % [str(rockA), str(rockB)])
	main._on_laser_fire_requested(rockA)
	await _sec(1.0)
	await _hover_cell(rockB)
	await _sec(2.5)

	# T5 静停 6s 等机器人路过束路径
	_say("T5 静停于 %s 6s（机器人游走中）" % str(rockB))
	await _sec(6.0)

	# T6 射第二枪后光标不动
	main._on_laser_fire_requested(rockB)
	_say("T6 射 %s 光标不动 2.5s" % str(rockB))
	await _sec(2.5)

	# T7 悬停基地格（设计=隐藏预览）再回岩壁
	_say("T7 悬停基地 (1,6) 再回 %s" % str(rockA))
	await _hover_cell(Vector2i(1, 6))
	await _sec(0.8)
	await _hover_cell(rockA)
	await _sec(1.0)

	_finish()


func _click_through(text_part: String) -> void:
	var b = await _await_btn(text_part, 8.0)
	if b == null:
		_say("WARN 找不到按钮 %s" % text_part)
		return
	var r: Rect2 = b.get_global_rect()
	await _inject_click(r.position + r.size / 2.0)


func _inject_click(window_pos: Vector2) -> void:
	var pos: Vector2 = window_pos
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


func _finish() -> void:
	RenderingServer.frame_post_draw.disconnect(_on_frame)
	var ud := OS.get_user_data_dir()
	if save_bak != "":
		var f := FileAccess.open(ud + "/save_data.json", FileAccess.WRITE)
		f.store_string(save_bak)
		f.close()
	var Settings: Node = root.get_node("/root/GameSettings")
	if skip_pre_bak != null:
		Settings.set_value("skip_pre_level", skip_pre_bak)
	if tut01_bak != null:
		Settings.set_value("tutorial_done_ch02_s01", tut01_bak)
	var f2 := FileAccess.open("res://tmp/aim_preview_probe.log", FileAccess.WRITE)
	f2.store_string("\n".join(_log))
	f2.close()
	print("[Probe] 完成，日志 %d 行 → tmp/aim_preview_probe.log" % _log.size())
	quit(0)
