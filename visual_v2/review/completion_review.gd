extends SceneTree
## Reconstructs review boards without entering levels or writing player progress.

var main: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	# Wait for splash's completion signal before hiding the menu it opens.
	await create_timer(2.6).timeout
	main.splash.hide()
	main.main_menu.hide()
	main.sign_in_panel.hide()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 960))
	await process_frame
	for level_index in range(1, 6):
		await _board(level_index)
		await create_timer(0.4).timeout
		await _capture("level%d.png" % level_index)
	# Explicit art-state gallery on L5's board; actors continue to use production scripts.
	await _state_gallery()
	await create_timer(0.3).timeout
	await _capture("states.png")
	main.rules_panel.open()
	await create_timer(0.3).timeout
	await _capture("rules.png")
	main.rules_panel.close()
	print("COMPLETION_REVIEW_OK five boards, state gallery, rules")
	quit()

func _board(number: int) -> void:
	main.main_menu.hide()
	main.splash.hide()
	main.sign_in_panel.hide()
	main.robot_manager.remove_all()
	main.enemy_manager.clear()
	main.boss_manager.clear()
	await process_frame
	var level = root.get_node("LevelSystem").get_level("ch01_s%02d" % number)
	root.get_node("GameState").reset_state(level.id, level)
	main.grid.configure(level.grid_size.x, level.grid_size.y, level.mine_count)
	if level.has_fixed_board():
		main.grid.apply_fixed_board({"mines": level.fixed_mines,
			"preopen": level.preopen_coords, "base": level.fixed_base})
	else:
		main.grid.apply_random_board()
		main.enemy_manager.setup_board(main.grid)
	if number >= 4:
		for cell in main.grid.cells.values():
			if cell.is_opened and not cell.is_base:
				assert(main.grid.place_first_base(cell.coord))
				break
	if number == 5:
		main.boss_manager.setup(main.grid, level.mine_count)
	# Gameplay frozen: screenshots do not earn rewards or settle runs.
	root.get_node("GameState").game_active = false
	main._relayout_play_area()
	main.get_node("CaveEnv").layout_env()
	main.hud.set_level_title("第 %d 关 · 素材验收" % number)
	main.tutorial_guide.hide()
	if number == 3:
		main.grid.get_cell(Vector2i(3, 3)).become_vein(20)
	if number == 4:
		for i in 3:
			var bug = load("res://scenes/Enemy.tscn").instantiate()
			main.enemy_manager.add_child(bug)
			bug.setup(Vector2i(6 + i, 6), ["web", "lock", "slow"][i], main.grid)
		var guard = load("res://scenes/GuardRobot.tscn").instantiate()
		main.robot_manager.add_child(guard)
		guard.set_initial_position(Vector2i(6, 7), main.grid)
	await process_frame

func _state_gallery() -> void:
	var cells: Array = []
	for x in range(2, 12):
		var c = main.grid.get_cell(Vector2i(x, 5))
		c.is_mine = false
		c.is_opened = true
		c.is_base = false
		c.adjacent_mines = 3
		c.refresh_visual()
		cells.append(c)
	cells[0].become_base()
	cells[1].become_vein(20)
	cells[2].collapse()
	cells[3].is_opened = false
	cells[3].toggle_flag()
	cells[4].apply_web()
	cells[5].is_opened = false
	cells[5].apply_lock()
	cells[6].apply_slime()
	cells[7].ignite_fire()
	cells[8].is_opened = false
	cells[8].confirm_mine()
	# Validate cell textures fit the existing one-cell control bounds.
	for c in cells:
		var special: TextureRect = c.get_node("SpecialIcon")
		assert(special.size == Vector2(28, 28))
		assert(special.expand_mode == TextureRect.EXPAND_IGNORE_SIZE)
	# Root hit releases every occupied tile, regardless of the new tentacle artwork.
	var segment: Array = [Vector2i(3, 8), Vector2i(4, 8), Vector2i(5, 8)]
	var tentacle = load("res://scripts/boss/tentacle.gd").new()
	main.boss_manager.add_child(tentacle)
	var before := int(main.grid.get_cell(segment[0]).path_blockers)
	tentacle.setup(segment, main.grid)
	assert(main.grid.get_cell(segment[0]).path_blockers == before + 1)
	tentacle.release("broken")
	assert(main.grid.get_cell(segment[0]).path_blockers == before)
	var display_tentacle = load("res://scripts/boss/tentacle.gd").new()
	main.boss_manager.add_child(display_tentacle)
	display_tentacle.setup([Vector2i(3, 9), Vector2i(4, 9), Vector2i(5, 9)], main.grid)
	var bomb = load("res://scripts/boss/bomb.gd").new()
	main.boss_manager.add_child(bomb)
	bomb.setup(Vector2i(10, 9), main.grid)
	bomb.tick(bomb.SHADOW_SEC + 0.01, main.grid, main.boss_manager)
	assert(bomb.state == "fuse")
	assert(main.grid.get_cell(Vector2i(10, 9)).bomb_masked)
	# Every boss phase and pose is loaded by the actual production frame selector.
	var beast = main.boss_manager.get_node("BossBeast")
	for phase in range(1, 4):
		beast.set_phase(phase)
		for pose in beast.POSES:
			beast.pose = pose
			beast._refresh_frame()
			assert(beast.get_node("BossSprite").texture.get_size() == Vector2(140, 64))
	beast.pose = "idle"
	beast.set_phase(1)

func _capture(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://visual_v2/review/completion_20261002/" + filename
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	assert(root.get_texture().get_image().save_png(path) == OK)
	print("COMPLETION_SCREENSHOT ", path)
