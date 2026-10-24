extends SceneTree
## 四类钻石效果实机截图脚本（2026-10-24）。
## 输出：docs/active/玩法设计/第二章-激光矿场/钻石效果实机截图-2026-10-24/
## 运行（APPDATA 重定向隔离存档——use_custom_user_dir 在 4.6.1 实测无效）：
##   APPDATA=<沙盒目录> Godot_console.exe --path . --audio-driver Dummy -s res://tmp/diamond_effect_screenshots.gd
const OUT := "res://docs/active/玩法设计/第二章-激光矿场/钻石效果实机截图-2026-10-24/"

var main: Node
var grid: Node
var gs: Node

func _initialize() -> void:
	DisplayServer.window_set_position(Vector2i(-2400, 0))
	DisplayServer.window_set_size(Vector2i(1024, 768))
	DisplayServer.window_set_title("钻石效果实机截图")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	change_scene_to_file("res://scenes/Main.tscn")
	call_deferred("_run")


func _run() -> void:
	await create_timer(1.2).timeout
	main = root.get_node("Main")
	main.splash.hide()
	grid = main.grid
	gs = root.get_node("GameState")
	gs.boot_splash_played = true
	await _gold()
	await _area()
	await _split()
	await _explorer()
	print("[Shot] DONE")
	main.queue_free()
	main = null
	grid = null
	await process_frame
	await process_frame
	quit(0)


func _level(id: String, mines: Array, effects: Array, preopen: Array) -> LevelData:
	var level := LevelData.new()
	level.id = id
	level.chapter_id = "ch02"
	level.display_name = "2-0"
	level.short_name = "效果截图"
	level.grid_size = Vector2i(12, 12)
	level.fixed_base = Vector2i(1, 5)
	level.laser_mode = true
	level.meta_progression = false
	level.time_limit_sec = 0.0
	level.diamond_effect_seed = 42
	level.mine_count = mines.size()
	level.fixed_mines.assign(mines)
	level.preopen_coords.assign(preopen)
	level.diamond_effects.assign(effects)
	var objective := ObjectiveData.new()
	objective.type = ObjectiveData.Type.REACH_SCORE
	objective.target_value = 99999
	level.objectives = [objective]
	return level


func _gold() -> void:
	main._start_level_with(_level("shot_gold", [Vector2i(3, 5)],
		[{"coord": Vector2i(3, 5), "effect_id": "gold", "params": {"gold_amount": 10}}],
		[Vector2i(1, 5), Vector2i(2, 5)]), "V2")
	await process_frame
	# 悬停采样读真实系统光标，截图脚本改为手动驱动（与视觉验证同口径）
	grid.set_process(false)
	await create_timer(0.3).timeout
	await _click_cell(Vector2i(3, 5), MOUSE_BUTTON_RIGHT)
	await _fresh_hover(Vector2i(3, 5))
	await _shot("01-金币-正确标记与悬停说明.png")
	await _board_crop("01-金币-正确标记与悬停_盘面x3.png")
	main.hud.clear_toast()
	await _click_cell(Vector2i(3, 5), MOUSE_BUTTON_LEFT, false)
	await create_timer(0.15).timeout
	await _shot("02-金币-激光领取+10金币.png")
	await _board_crop("02-金币-激光领取+10金币_盘面x3.png")
	await create_timer(1.0).timeout


func _area() -> void:
	main._start_level_with(_level("shot_area", [Vector2i(3, 5), Vector2i(4, 4)],
		[{"coord": Vector2i(3, 5), "effect_id": "area_3x3", "params": {}},
			{"coord": Vector2i(4, 4), "effect_id": "gold", "params": {"gold_amount": 10}}],
		[Vector2i(1, 5), Vector2i(2, 5)]), "V2")
	await process_frame
	await create_timer(0.3).timeout
	await _click_cell(Vector2i(3, 5), MOUSE_BUTTON_RIGHT)
	await _click_cell(Vector2i(4, 4), MOUSE_BUTTON_RIGHT)
	await _fresh_hover(Vector2i(3, 5))
	await _shot("03-范围-悬停显示3x3预览.png")
	await _board_crop("03-范围-悬停显示3x3预览_盘面x3.png")
	main.hud.clear_toast()
	await _click_cell(Vector2i(3, 5), MOUSE_BUTTON_LEFT, false)
	await create_timer(0.15).timeout
	await _shot("04-范围-开3x3并接力金币.png")
	await _board_crop("04-范围-开3x3并接力金币_盘面x3.png")
	await create_timer(1.0).timeout


func _split() -> void:
	# 远端雷防止射线连开清盘触发胜利（胜利变暗会盖住射线表现）；
	# 均在八向射程 (3,5)±4 之外，不会被射线击碎。
	var mines: Array = [Vector2i(3, 5), Vector2i(9, 2), Vector2i(10, 6), Vector2i(8, 10),
		Vector2i(11, 11), Vector2i(5, 11), Vector2i(0, 10)]
	main._start_level_with(_level("shot_split", mines,
		[{"coord": Vector2i(3, 5), "effect_id": "split_two", "params": {"ray_range": 4}}],
		[Vector2i(1, 5), Vector2i(2, 5)]), "V2")
	await process_frame
	await create_timer(0.3).timeout
	await _click_cell(Vector2i(3, 5), MOUSE_BUTTON_RIGHT)
	await _fresh_hover(Vector2i(3, 5))
	await _shot("05-双射线-悬停显示随机可能范围.png")
	await _board_crop("05-双射线-悬停显示随机可能范围_盘面x3.png")
	main.hud.clear_toast()
	await _click_cell(Vector2i(3, 5), MOUSE_BUTTON_LEFT, false)
	await create_timer(0.15).timeout
	await _shot("06-双射线-随机两向发射瞬间.png")
	await _board_crop("06-双射线-随机两向发射瞬间_盘面x3.png")
	await create_timer(0.9).timeout
	await _shot("07-双射线-射线开格结果.png")
	await _board_crop("07-双射线-射线开格结果_盘面x3.png")


func _explorer() -> void:
	main._start_level_with(_level("shot_explorer", [Vector2i(3, 5)],
		[{"coord": Vector2i(3, 5), "effect_id": "explorer",
			"params": {"actions": 3, "interval": 1.2, "lifetime": 20.0}}],
		[Vector2i(1, 5), Vector2i(2, 5), Vector2i(2, 6)]), "V2")
	await process_frame
	await create_timer(0.3).timeout
	await _click_cell(Vector2i(3, 5), MOUSE_BUTTON_RIGHT)
	await _click_cell(Vector2i(3, 5), MOUSE_BUTTON_LEFT, false)
	await create_timer(0.35).timeout
	await _shot("08-精灵-召唤飞行.png")
	await _board_crop("08-精灵-召唤飞行_盘面x3.png")
	# 第一次作业（开 0 区连带）完成后、第二次作业（清盘触发胜利）前抓拍
	await create_timer(1.45).timeout
	await _shot("09-精灵-自动开确定安全格.png")
	await _board_crop("09-精灵-自动开确定安全格_盘面x3.png")


## 先移开再悬停，确保浮字是本效果的说明而不是插旗提示
func _fresh_hover(coord: Vector2i) -> void:
	await _hover(Vector2i(1, 5))
	main.hud.clear_toast()
	await _hover(coord)


func _hover(coord: Vector2i) -> void:
	var cell = grid.get_cell(coord)
	grid._update_hover(cell.position + Vector2.ONE * grid.cell_size * 0.5)
	await process_frame
	await process_frame


func _click_cell(coord: Vector2i, button: MouseButton, wait_after := true) -> void:
	var cell = grid.get_cell(coord)
	var screen: Vector2 = root.get_final_transform() * cell.get_global_transform_with_canvas().origin
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	Input.parse_input_event(motion)
	await process_frame
	var down := InputEventMouseButton.new()
	down.button_index = button
	down.position = screen
	down.global_position = screen
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	var up := down.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame
	if wait_after:
		await create_timer(0.06).timeout


func _shot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT) + filename)
	print("[Shot] ", filename)


func _board_crop(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var transform: Transform2D = grid.get_global_transform_with_canvas()
	var canvas_rect := Rect2(transform * Vector2.ZERO,
		Vector2(grid.cols, grid.rows) * grid.cell_size * transform.get_scale())
	var frame_scale := Vector2(image.get_size()) / root.get_visible_rect().size
	var pixel_rect := Rect2i(canvas_rect.position * frame_scale, canvas_rect.size * frame_scale)
	pixel_rect = pixel_rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var crop := image.get_region(pixel_rect)
	crop.resize(crop.get_width() * 3, crop.get_height() * 3, Image.INTERPOLATE_NEAREST)
	crop.save_png(ProjectSettings.globalize_path(OUT) + filename)
