extends SceneTree
## 预瞄准渲染验证（2026-10-11 终版）：不碰真实鼠标（用户在用电脑，真实光标会污染
## -3000,0 处的测试窗）。直接 emit cell_hovered 信号驱动预览，同帧截图，离线像素
## 比对基线，量化：束格高亮是否画出、对比度多强。顺带打印显示器布局。
## 跑法：Godot_console.exe --path . -s res://tmp/auto_aim_render_check.gd （勿加 --headless）

const SHOT := "tmp/aim_render/"

var main: Node
var grid: Node
var GS: Node
var save_bak := ""
var skip_pre_bak = null
var tut_bak = null


func _initialize() -> void:
	DisplayServer.window_set_position(Vector2i(-3000, 0))
	DisplayServer.window_set_size(Vector2i(1280, 800))
	DisplayServer.window_set_title("预瞄准渲染验证（屏外）")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT))
	change_scene_to_file("res://scenes/ui/BootLoading.tscn")
	call_deferred("_run")


func _sec(t: float) -> void:
	await create_timer(t, true).timeout


func _walk(node: Node, acc: Array) -> Array:
	acc.append(node)
	for c in node.get_children():
		_walk(c, acc)
	return acc


func _await_btn(text_part: String, timeout_sec: float) -> Button:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		for n in _walk(root, []):
			if n is Button and n.is_visible_in_tree() and text_part in n.text:
				return n
		await _sec(0.1)
	return null


func _click_signal(text_part: String) -> void:
	var b = await _await_btn(text_part, 8.0)
	if b != null:
		b.pressed.emit()
		await process_frame


func _shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(SHOT + fname))
	print("  [SHOT] ", fname)


func _dump_pv(tag: String) -> void:
	var lp = grid.get_node_or_null("LaserPreview")
	print("  [PV:", tag, "] visible=", lp.visible, " cells=", lp.cells.size(),
			" line=", lp.has_line)


func _run() -> void:
	await _sec(1.5)
	# 显示器布局（确认 -3000,0 是否落在用户真实显示器上）
	for i in DisplayServer.get_screen_count():
		print("[SCREEN %d] usable=", DisplayServer.screen_get_usable_rect(i),
				" win_pos=", DisplayServer.window_get_position())
	GS = root.get_node("/root/GameState")
	var Settings: Node = root.get_node("/root/GameSettings")
	var SaveSys: Node = root.get_node("/root/SaveSystem")
	var ud := OS.get_user_data_dir()
	if FileAccess.file_exists(ud + "/save_data.json"):
		var f := FileAccess.open(ud + "/save_data.json", FileAccess.READ)
		save_bak = f.get_as_text()
		f.close()
	skip_pre_bak = Settings.get_value("skip_pre_level")
	tut_bak = Settings.get_value("tutorial_done_ch02_s01")
	Settings.set_value("skip_pre_level", false)
	Settings.set_value("tutorial_done_ch02_s01", true)   # 跳过教学，只测渲染
	SaveSys.cleared_levels.erase("ch02_s01")

	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline and root.get_node_or_null("Main") == null:
		await _sec(0.2)
	main = root.get_node("Main")

	await _click_signal("选择关卡")
	await _sec(0.8)
	await _click_signal("激光矿场")
	await _sec(0.6)
	var card = await _await_btn("01", 5.0)
	if card != null:
		card.pressed.emit()
		await process_frame
	await _click_signal("本关")
	await _sec(0.8)
	await _click_signal("开始挖矿")
	await _sec(1.0)
	grid = main.grid
	if GS.current_level_id != "ch02_s01":
		print("[FATAL] ", GS.current_level_id)
		_finish()
		return
	var guide: Node = main.get_node("UILayer/TutorialGuide")
	if guide.visible:
		guide.call("_finish")
		await _sec(0.3)

	# 基线（无悬停）
	await _sec(0.3)
	_dump_pv("基线")
	await _shot("0-baseline.png")

	# 直接信号驱动：悬停 (1,1) 岩壁（近束）→ 立即截图（同帧渲染，不受真实鼠标影响）
	grid.cell_hovered.emit(grid.get_cell(Vector2i(1, 1)))
	await _dump_pv("emit(1,1)")
	await _shot("1-sig-near.png")
	grid.cell_unhovered.emit(grid.get_cell(Vector2i(1, 1)))
	await _sec(0.2)

	# 直接信号驱动：悬停 (6,6) 加固墙（长束穿已开区）
	grid.cell_hovered.emit(grid.get_cell(Vector2i(6, 6)))
	_dump_pv("emit(6,6)")
	await _shot("2-sig-far.png")
	grid.cell_unhovered.emit(grid.get_cell(Vector2i(6, 6)))
	await _sec(0.2)

	# 直接信号驱动：悬停 (9,1) 远处岩壁（超长斜束，覆盖最多已开格）
	grid.cell_hovered.emit(grid.get_cell(Vector2i(9, 1)))
	_dump_pv("emit(9,1)")
	await _shot("3-sig-diag.png")
	grid.cell_unhovered.emit(grid.get_cell(Vector2i(9, 1)))

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
	Settings.set_value("tutorial_done_ch02_s01", false)   # 复位：用户要亲自体验
	print("[Done]")
	quit(0)
