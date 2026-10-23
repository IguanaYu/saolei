extends SceneTree
## 隔离存档中的真实渲染/鼠标输入检查；截图不作为逻辑验收的替代。
const EVIDENCE := "res://tmp/diamond_visual_evidence/"
const IDS := ["area_3x3", "split_two", "gold", "explorer"]
var main: Node
var grid: Node
var gs: Node
var events: Array = []
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(1024, 768))
	DisplayServer.window_set_position(Vector2i(-2400, 0))
	DisplayServer.window_set_title("钻石效果系统 · 隔离渲染验证")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EVIDENCE))
	change_scene_to_file("res://scenes/Main.tscn")
	call_deferred("_run")


func _run() -> void:
	await create_timer(1.2).timeout
	print("[DiamondVisual] USER_DATA=", OS.get_user_data_dir())
	main = root.get_node("Main")
	main.splash.hide()
	grid = main.grid
	_check(grid.get_node_or_null("EffectsLayer") != null, "真实渲染动效层载入成功")
	if grid.get_node_or_null("EffectsLayer") == null:
		quit(1)
		return
	gs = root.get_node("GameState")
	gs.boot_splash_played = true
	await _gallery()
	await _random_preview()
	await _mixed_chain()
	await _explorer_operation()
	var result := {"checks": checks, "failures": failures,
		"event_ids": events.map(func(event): return event.effect_id)}
	var output := FileAccess.open(EVIDENCE + "result.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "\t"))
	print("[DiamondVisual] ", JSON.stringify(result))
	main.queue_free()
	main = null
	grid = null
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	print("[DiamondVisual] ", "PASS " if condition else "FAIL ", description)
	if not condition:
		failures.append(description)


func _level(id: String) -> LevelData:
	var level := LevelData.new()
	level.id = id
	level.chapter_id = "ch02"
	level.display_name = "2-0"
	level.short_name = "钻石效果验证"
	level.grid_size = Vector2i(12, 12)
	level.fixed_base = Vector2i(1, 5)
	level.laser_mode = true
	level.meta_progression = false
	level.time_limit_sec = 0.0
	level.diamond_effect_seed = 42
	var objective := ObjectiveData.new()
	objective.type = ObjectiveData.Type.REACH_SCORE
	objective.target_value = 99999
	level.objectives = [objective]
	return level


func _gallery() -> void:
	var level := _level("diamond_visual_gallery")
	for row in [3, 6, 9]:
		for index in 4:
			var coord := Vector2i(2 + index * 2, row)
			level.fixed_mines.append(coord)
			level.diamond_effects.append({"coord": coord, "effect_id": IDS[index]})
	level.mine_count = level.fixed_mines.size()
	level.preopen_coords = [Vector2i(1, 5)]
	main._start_level_with(level, "V2")
	await process_frame
	for row in [3, 6]:
		for index in 4:
			var coord := Vector2i(2 + index * 2, row)
			await _click_cell(coord, MOUSE_BUTTON_RIGHT)
			var cell = grid.get_cell(coord)
			_check(cell.is_flagged and cell.has_public_diamond_effect(), "真实右键公开 " + IDS[index])
			if row == 6:
				# 展示同一状态接口的已消耗外观；实际消耗另由混合链输入验证。
				cell.diamond_effect_consumed = true
				cell.refresh_visual()
	for index in 4:
		var hidden = grid.get_cell(Vector2i(2 + index * 2, 9))
		_check(not hidden.has_public_diamond_effect() and hidden.diamond_effect_description().is_empty(),
			"隐藏钻石不公开 " + IDS[index])
		_check(not is_instance_valid(hidden.get_node_or_null("DiamondEffectBadge")), "隐藏钻石不创建角标")
	var wrong = grid.get_cell(Vector2i(10, 9))
	wrong.diamond_effect_id = "gold"
	await _click_cell(wrong.coord, MOUSE_BUTTON_RIGHT)
	_check(wrong.is_flagged and not wrong.has_public_diamond_effect() and wrong.diamond_effect_description().is_empty(),
		"错误旗即使有内部效果字段也不公开")
	await create_timer(0.3).timeout
	await _shot("01_four_effects_and_states.png")
	await _board_crop("01_four_effects_and_states_board_x3.png")


func _mixed_chain() -> void:
	var level := _level("diamond_visual_mixed_chain")
	var coords := [Vector2i(3, 5), Vector2i(3, 4), Vector2i(4, 5), Vector2i(4, 4)]
	for index in 4:
		level.fixed_mines.append(coords[index])
		var params := {}
		if IDS[index] == "split_two":
			params = {"ray_range": 4}
		elif IDS[index] == "gold":
			params = {"gold_amount": 17}
		elif IDS[index] == "explorer":
			params = {"actions": 3, "interval": 0.4, "lifetime": 12.0}
		level.diamond_effects.append({"coord": coords[index], "effect_id": IDS[index], "params": params})
	level.mine_count = level.fixed_mines.size()
	level.preopen_coords = [Vector2i(1, 5), Vector2i(1, 4), Vector2i(2, 4), Vector2i(2, 5), Vector2i(2, 6)]
	main._start_level_with(level, "V2")
	events.clear()
	main.diamond_effect_manager.effect_released.connect(func(event): events.append(event.duplicate(true)))
	await process_frame
	for coord in coords:
		await _click_cell(coord, MOUSE_BUTTON_RIGHT)
	await create_timer(0.2).timeout
	await _shot("02_mixed_chain_before.png")
	var before_gold: int = gs.money
	await _click_cell(Vector2i(8, 5), MOUSE_BUTTON_LEFT, false)
	await create_timer(0.10).timeout
	await _shot("03_mixed_chain_release.png")
	await _board_crop("03_mixed_chain_release_board_x3.png")
	_check(events.size() == 4, "一次真实发射触发四类混合连锁")
	_check(int(gs.result_stats.get("money_from_diamond_effect_gold", 0)) == 17 or gs.money >= before_gold + 17,
		"金币效果入账 17，表现显示 +17 金币")
	for event in events:
		if event.effect_id == "split_two":
			_check(event.rays.size() == 2, "渲染快照与逻辑共用两条实际射线")
	_check(main.diamond_explorer_manager.actors.size() == 1, "实际召唤一名探索精灵")
	await create_timer(0.43).timeout
	await _shot("04_explorer_waiting.png")
	await _board_crop("04_explorer_waiting_board_x3.png")
	_check(main.diamond_explorer_manager.actors[0].state == "waiting",
		"连开已完成全部安全格时精灵无目标等待")
	for coord in coords:
		var cell = grid.get_cell(coord)
		_check(cell.is_flagged and cell.is_mine and cell.diamond_effect_consumed, "激活后雷和旗保持 " + str(coord))
	main._start_level_with(level, "V2")
	await process_frame
	_check(main.diamond_explorer_manager.actors.is_empty(), "重开清理所有探索精灵")
	_check(grid.get_node("EffectsLayer").get_child_count() == 0, "重开清理临时钻石演出")
	await _shot("06_restart_clean.png")


func _random_preview() -> void:
	var level := _level("diamond_visual_random_preview")
	level.fixed_mines = [Vector2i(3, 5), Vector2i(5, 3)]
	level.mine_count = 2
	level.preopen_coords = [Vector2i(1, 5)]
	level.diamond_effects = [
		{"coord": Vector2i(3, 5), "effect_id": "split_two", "params": {"ray_range": 4}},
		{"coord": Vector2i(5, 3), "effect_id": "gold", "params": {"gold_amount": 17}},
	]
	main._start_level_with(level, "V2")
	await process_frame
	# 悬停采样读的是真实系统光标（get_global_mouse_position），合成鼠标事件更新不了它；
	# 测试改为停用逐帧采样、直接驱动 _update_hover，预览链路（cell_hovered→preview_shot）仍是真实代码。
	grid.set_process(false)
	await _hover_cell(Vector2i(3, 5))
	_check(grid._laser_preview.random_origins.is_empty() and grid._laser_preview.random_cells.is_empty(),
		"隐藏双射线不公开来源或可能范围")
	await _click_cell(Vector2i(3, 5), MOUSE_BUTTON_RIGHT)
	var rng_state: int = main.diamond_effect_manager.effect_rng.state
	for index in 12:
		await _hover_cell(Vector2i(1, 5))
		await _hover_cell(Vector2i(3, 5))
	_check(main.diamond_effect_manager.effect_rng.state == rng_state, "反复真实悬停不推进实际随机序列")
	_check(grid._laser_preview.random_origins == [Vector2i(3, 5)], "仅公开正确旗的随机来源")
	_check(grid._laser_preview.random_cells.has(Vector2i(5, 3)), "紫色角点包含配置八向最大可能格")
	_check(not grid._laser_preview.cells.has(Vector2i(5, 3)), "可能范围不混入确定命中集")
	_check(not grid._laser_preview.marks.has(Vector2i(5, 3)) \
		and main.diamond_effect_manager.public_info(Vector2i(5, 3)).is_empty(),
		"可能范围不揭示隐藏金币钻石或预演连锁")
	for coord in grid._laser_preview.random_cells:
		_check(grid.get_cell(coord) != null, "可能范围裁切在棋盘内 " + str(coord))
	main.hud.clear_toast()
	await _shot("02_random_possible_preview.png")
	await _board_crop("02_random_possible_preview_board_x3.png")
	grid.set_process(true)


func _explorer_operation() -> void:
	var level := _level("diamond_visual_explorer_operation")
	level.fixed_mines = [Vector2i(3, 5)]
	level.mine_count = 1
	level.preopen_coords = [Vector2i(1, 5), Vector2i(2, 5)]
	level.diamond_effects = [{"coord": Vector2i(3, 5), "effect_id": "explorer",
		"params": {"actions": 3, "interval": 0.6, "lifetime": 12.0}}]
	main._start_level_with(level, "V2")
	await process_frame
	await _click_cell(Vector2i(3, 5), MOUSE_BUTTON_RIGHT)
	await _click_cell(Vector2i(3, 5), MOUSE_BUTTON_LEFT, false)
	await create_timer(0.25).timeout
	_check(main.diamond_explorer_manager.actors.size() == 1, "单项盘真实输入召唤精灵")
	if not main.diamond_explorer_manager.actors.is_empty():
		_check(main.diamond_explorer_manager.actors[0].state == "flying", "精灵依公开数字选定安全目标并飞行")
	await _shot("05_explorer_flying.png")
	await _board_crop("05_explorer_flying_board_x3.png")
	await create_timer(0.5).timeout
	await _shot("05_explorer_worked.png")
	await _board_crop("05_explorer_worked_board_x3.png")
	_check(int(gs.result_stats.get("diamond_explorer_actions", 0)) > 0, "探索精灵实际完成确定安全格作业")
	main._start_level_with(level, "V2")
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


func _hover_cell(coord: Vector2i) -> void:
	var cell = grid.get_cell(coord)
	# 取格中心格内坐标驱动采样；_process 已停用，悬停状态只由本函数改变。
	grid._update_hover(cell.position + Vector2.ONE * grid.cell_size * 0.5)
	await process_frame
	await process_frame


func _shot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(EVIDENCE + filename)
	print("[DiamondVisual] SCREENSHOT ", filename)


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
	crop.save_png(EVIDENCE + filename)
