extends SceneTree
## 幽灵青色团块查证（2026-10-11）：07-s4 截图里发现一个矿石样青色环，
## 但 2-4 关卡定义无矿石。两个假设：A=2-3 残留泄漏；B=2-4 本来就有的某实体。
## 实验设计：1) 直启 2-4 截图扫青色（无 2-3 历史）；2) 完整 2-3→2-4 路径截图扫描；
## 3) 每次截图前 dump 场上全部实体（矿石/机器人/旗/格子状态）的屏幕矩形。
## 跑法（真实窗口，屏外）：Godot_console.exe --path . -s res://tmp/auto_ghost_check.gd

const EVIDENCE := "tmp/ghost_check/"

var GS: Node
var SaveSys: Node
var main: Node
var g: Node
var FM: Node
var RM: Node
var save_bak := ""
var skip_pre_bak = null
var tut_bak = null


func _initialize() -> void:
	print("[GhostCheck] start")
	DisplayServer.window_set_position(Vector2i(-3000, 0))
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_title("幽灵青团查证（屏外）")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EVIDENCE))
	change_scene_to_file("res://scenes/ui/BootLoading.tscn")
	call_deferred("_run")


func _sec(t: float) -> void:
	await create_timer(t, true).timeout


func _shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(EVIDENCE + fname))
	print("  [SHOT] ", fname, " ", img.get_size())


func _dump_entities(tag: String) -> void:
	print("  [DUMP:", tag, "] win_size=", root.get_size(), " grid=",
			Vector2i(g.rows, g.cols), " cell=", g.cell_size,
			" grid_global=", g.global_position)
	print("    ores=", FM.ores.size())
	for o in FM.ores:
		print("      ore origin=", o.origin, " global=", o.global_position)
	for r in RM.robots:
		print("    robot ", r.robot_type, " coord=", r.coord, " global=", r.global_position)
	var flags: Array = []
	for c in g.cells.values():
		if c.is_flagged:
			flags.append(c.coord)
	print("    flagged_cells=", flags)
	# 幽灵团块中心（截图 2560 宽 / 窗口 1280 = 2 倍缩放）：(912,575)/2
	var ghost_local: Vector2 = Vector2(912, 575) / 2.0 - g.global_position
	var ghost_coord := Vector2i(int(ghost_local.x / g.cell_size), int(ghost_local.y / g.cell_size))
	print("    ghost_local=", ghost_local, " ghost_coord=", ghost_coord)
	var gc = g.cells.get(ghost_coord)
	if gc != null:
		print("      cell opened=", gc.is_opened, " num=", gc.number, " flag=", gc.is_flagged,
				" cover_hp=", gc.cover_wall_hp, " base=", gc.is_base)
		print("      facility_here=", g.facility_cells.has(ghost_coord),
				" special=", gc.get("special") if gc.get("special") != null else "-")


func _finish() -> void:
	if save_bak != "":
		var ud := OS.get_user_data_dir()
		var f := FileAccess.open(ud + "/save_data.json", FileAccess.WRITE)
		f.store_string(save_bak)
		f.close()
		print("[GhostCheck] save 恢复")
	var Settings: Node = root.get_node("/root/GameSettings")
	if skip_pre_bak != null:
		Settings.set_value("skip_pre_level", skip_pre_bak)
	if tut_bak != null:
		Settings.set_value("tutorial_done_ch02_s03", tut_bak)
	quit(0)


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
	tut_bak = Settings.get_value("tutorial_done_ch02_s03")
	Settings.set_value("skip_pre_level", true)

	# ---- 实验 A：直启 2-4（无 2-3 历史）----
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline and root.get_node_or_null("Main") == null:
		await _sec(0.2)
	main = root.get_node("Main")
	if main == null:
		print("[GhostCheck] Main 30s 未就绪，放弃")
		_finish()
		return
	main._start_level("ch02_s04")
	await _sec(1.2)
	g = main.grid
	FM = main.facility_manager
	RM = main.robot_manager
	var guide: Node = main.get_node("UILayer/TutorialGuide")
	guide.call("_finish")
	await _sec(0.5)
	_dump_entities("A直启s4")
	await _shot("A-s4-direct.png")

	# ---- 实验 B：走 2-3 打两枪 → 下一关 → 2-4 ----
	main._start_level("ch02_s03")
	await _sec(1.2)
	guide.call("_finish")
	await _sec(0.4)
	main._on_laser_fire_requested(Vector2i(13, 7))
	await _sec(0.6)
	main._on_laser_fire_requested(Vector2i(13, 7))
	await _sec(0.6)
	_dump_entities("B-s3打完两枪")
	await _shot("B-s3-after2shots.png")
	# 直达结算 → 下一关 → 2-4
	GS.add_score(300 - GS.score + 1, "other")
	await _sec(1.6)
	var next := _find_button("下一关")
	if next != null:
		next.pressed.emit()
		await _sec(0.8)
		var prec := _find_button("开始挖矿")
		if prec != null:
			prec.pressed.emit()
	else:
		main._start_level("ch02_s04")
	await _sec(1.2)
	guide.call("_finish")
	await _sec(0.5)
	_dump_entities("B-进s4后")
	await _shot("B-s4-after-transition.png")
	_finish()


func _find_button(text_part: String) -> Button:
	var acc: Array = []
	_walk(root, acc)
	for n in acc:
		if n is Button and n.is_visible_in_tree() and text_part in n.text:
			return n
	return null


func _walk(node: Node, acc: Array) -> void:
	acc.append(node)
	for c in node.get_children():
		_walk(c, acc)
