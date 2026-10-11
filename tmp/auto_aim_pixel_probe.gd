extends SceneTree
## 预瞄准像素探针（2026-10-11）：用户两次报"预览不显示/不稳定"。
## 上次探针只验证了 visible 标志位翻转，没验证画面上真画出了东西——补上：
## 进 2-1（真实状态：教学键已从设置消失=用户现状，顺带验证教学修复），
## 基线/悬停岩壁/悬停远墙/悬停已开格四张截图 + 预览节点内部 dump，离线像素差分。
## 跑法：Godot_console.exe --path . -s res://tmp/auto_aim_pixel_probe.gd （勿加 --headless）

const SHOT := "tmp/aim_pixel/"

var main: Node
var grid: Node
var GS: Node
var save_bak := ""
var skip_pre_bak = null
var _last_hover: Vector2i = Vector2i(-99, -99)
var _hover_seen := false
var _aim_pos := Vector2.ZERO


func _initialize() -> void:
	DisplayServer.window_set_position(Vector2i(-3000, 0))
	DisplayServer.window_set_size(Vector2i(1280, 800))
	DisplayServer.window_set_title("预瞄准像素探针（屏外）")
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
	else:
		print("[WARN] 无按钮 ", text_part)


func _inject_move(window_pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = window_pos
	motion.global_position = window_pos
	Input.parse_input_event(motion)
	await process_frame
	await process_frame


func _winpos(coord: Vector2i) -> Vector2:
	var cell = grid.get_cell(coord)
	if cell == null:
		return Vector2(-9999, -9999)
	return root.get_final_transform() * cell.global_position


func _on_hover_capture(cell) -> void:
	_last_hover = cell.coord
	_hover_seen = true


func _aim(coord: Vector2i) -> bool:
	_hover_seen = false
	var pos := _winpos(coord)
	if pos.x < -9000:
		return false
	var a := _winpos(Vector2i(0, 0))
	var b := _winpos(Vector2i(1, 0))
	var px := (b - a).length()
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
			return false
		pos += Vector2(err.x, err.y) * px
	return false


func _shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(SHOT + fname))
	print("  [SHOT] ", fname)


var _t0 := 0
var _watching := false


func _now_ms() -> int:
	return Time.get_ticks_msec() - _t0


func _on_hover_watch(cell) -> void:
	if _watching:
		var rob: Array = []
		for r in main.robot_manager.robots:
			rob.append("%s@%s" % [r.robot_type, str(r.coord)])
		print("  [EV +%d] HOVER %s robots=%s mouse=%s" % [_now_ms(), str(cell.coord),
				" ".join(rob), str(root.get_mouse_position())])


func _on_unhover_watch(cell) -> void:
	if _watching:
		var rob: Array = []
		for r in main.robot_manager.robots:
			rob.append("%s@%s" % [r.robot_type, str(r.coord)])
		print("  [EV +%d] UNHOVER %s robots=%s mouse=%s" % [_now_ms(), str(cell.coord),
				" ".join(rob), str(root.get_mouse_position())])


func _watch_still(tag: String, seconds: float) -> void:
	_watching = true
	_t0 = Time.get_ticks_msec()
	print("  [WATCH %s] 静止监测 %.1fs 开始" % [tag, seconds])
	await _sec(seconds)
	_watching = false
	print("  [WATCH %s] 结束" % tag)


func _dump_preview(tag: String) -> void:
	var lp = grid.get_node_or_null("LaserPreview")
	if lp == null:
		print("  [PV:", tag, "] 节点不存在!")
		return
	print("  [PV:", tag, "] visible=", lp.visible, " cells=", lp.cells.size(),
			" line=", lp.has_line,
			" from=", lp.from_px, " to=", lp.to_px,
			" gpos=", lp.global_position, " z=", lp.z_index,
			" mod=", lp.modulate, " cell_px=", lp.cell_px)
	if lp.cells.size() > 0:
		var cs: Array = []
		for i in mini(6, lp.cells.size()):
			cs.append(str(lp.cells[i]))
		print("    首格=", " ".join(cs), str(lp.cells[lp.cells.size() - 1]) if lp.cells.size() > 6 else "")


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
	Settings.set_value("skip_pre_level", false)
	# 注意：不动 tutorial_done_ch02_s01——保持用户真实状态（键不存在），
	# 顺带验证 DEFAULTS 补注册后 get_value 的返回
	print("[STATE] tutorial_done_ch02_s01 读取值=",
			str(Settings.get_value("tutorial_done_ch02_s01")))
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
		print("[FATAL] 未进 2-1: ", GS.current_level_id)
		_finish()
		return
	var guide: Node = main.get_node("UILayer/TutorialGuide")
	await _sec(1.2)   # 教学有 0.5s 延迟起播
	print("[TUT] 修复后教学出现=", guide.visible,
			"（true=DEFAULTS补注册+空值修正生效）")
	if guide.visible:
		guide.call("_finish")   # 清场做预览测量
		await _sec(0.4)

	grid.cell_hovered.connect(_on_hover_capture)
	grid.cell_hovered.connect(_on_hover_watch)
	grid.cell_unhovered.connect(_on_unhover_watch)
	await _inject_move(Vector2(-500, -500))   # 鼠标挪出棋盘做基线
	await _sec(0.3)
	_dump_preview("基线")
	await _shot("0-baseline.png")

	# 悬停点1：近处岩壁 (1,1)（基地 (1,6) 同列，短束）+ 静止监测
	if await _aim(Vector2i(1, 1)):
		print("[AIM] 命中 (1,1) pos=", str(_aim_pos),
				" cell_center=", str(_winpos(Vector2i(1, 1))))
		await _watch_still("(1,1)", 3.0)
		_dump_preview("悬停(1,1)")
		await _shot("1-hover-wall-near.png")
	else:
		print("[AIM] (1,1) 不收敛")

	# 悬停点2：远处加固墙 (6,6)（长束穿已开区）
	if await _aim(Vector2i(6, 6)):
		print("[AIM] 命中 (6,6) pos=", str(_aim_pos),
				" cell_center=", str(_winpos(Vector2i(6, 6))))
		await _watch_still("(6,6)", 3.0)
		_dump_preview("悬停(6,6)")
		await _shot("2-hover-wall-far.png")
	else:
		print("[AIM] (6,6) 不收敛")

	# 悬停点3：已开地面 (3,6)（束上无墙）
	if await _aim(Vector2i(3, 6)):
		print("[AIM] 命中 (3,6)")
		await _sec(0.4)
		_dump_preview("悬停(3,6)")
		await _shot("3-hover-open-ground.png")
	else:
		print("[AIM] (3,6) 不收敛")

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
	print("[Done] 截图在 ", SHOT)
	quit(0)
