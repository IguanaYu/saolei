extends SceneTree
## Isolated production-actor gallery: no level completion or progress writes.

var main: Node
var allies: Array = []
var enemies: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await create_timer(2.7).timeout
	main.splash.hide()
	main.main_menu.hide()
	main.sign_in_panel.hide()
	root.get_node("GameState").reset_state("ch01_s04", root.get_node("LevelSystem").get_level("ch01_s04"))
	root.get_node("GameState").game_active = false
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 960))
	await process_frame
	main.grid.configure(14, 14, 20)
	main.grid.apply_fixed_board({"mines": [], "preopen": [], "base": Vector2i(1, 1)})
	for cell in main.grid.cells.values():
		cell.is_opened = cell.coord.x < 12 and cell.coord.y < 12
		cell.adjacent_mines = 0
		cell.refresh_visual()
	main._relayout_play_area()
	main.get_node("CaveEnv").layout_env()
	main.hud.set_level_title("敌我识别 · 运行时检查")
	main.tutorial_guide.hide()
	for i in 5:
		allies.append(main.robot_manager.spawn_robot(Vector2i(2 + i * 2, 3),
			["opener", "marker", "detector", "miner", "guard"][i], main.grid))
	for i in 4:
		enemies.append(main.enemy_manager.spawn_enemy(Vector2i(2 + i * 2, 6),
			["web", "lock", "slow", "slime"][i], main.grid))
	var nest = load("res://scenes/Nest.tscn").instantiate()
	main.enemy_manager.add_child(nest)
	nest.setup(Vector2i(10, 6), 2, main.grid)
	main.enemy_manager.nests.append(nest)
	var locked = main.grid.get_cell(Vector2i(2, 9))
	locked.is_opened = false
	assert(locked.apply_lock())
	main.grid.get_cell(Vector2i(4, 9)).apply_web()
	main.grid.get_cell(Vector2i(6, 9)).apply_slime()
	var flag = main.grid.get_cell(Vector2i(8, 9))
	flag.is_opened = false
	flag.toggle_flag()
	var number = main.grid.get_cell(Vector2i(10, 9))
	number.adjacent_mines = 3
	number.refresh_visual()
	# A distant slime is still recognisably hostile when it cannot be clicked.
	var unreachable = main.enemy_manager.spawn_enemy(Vector2i(13, 13), "slime", main.grid)
	assert(not unreachable.is_clickable(main.grid))
	assert(unreachable.modulate == Color.WHITE)
	assert(unreachable.get_node("Skin").self_modulate.a < 1.0)
	assert(main.robot_manager.robots.size() == 5)
	assert(main.enemy_manager.enemies.size() == 5)
	for actor in allies + enemies + [nest, unreachable]:
		assert(actor.has_node("FactionMarker"))
		assert(actor.get_node("Skin").material is ShaderMaterial)
	assert(locked.get_node("LockedCellSeal").visible)
	assert(not locked.open("player"))
	assert(not locked.toggle_flag())
	await create_timer(0.4).timeout
	for frame in 3:
		for actor in allies + enemies:
			actor.get_node("Skin").frame = frame
		await _capture("frame%d.png" % frame)
	await _isolated_pixels()
	assert(locked.clear_lock("player"))
	assert(not locked.get_node("LockedCellSeal").visible)
	assert(locked.open("player"))
	# Restore the seal for the rules and small-window screenshots.
	locked.is_opened = false
	assert(locked.apply_lock())
	main.rules_panel.open()
	await _capture("rules.png")
	main.rules_panel.close()
	DisplayServer.window_set_size(Vector2i(640, 480))
	await create_timer(0.3).timeout
	await _capture("small.png")
	# Exercise normal hit routing and cleanup with production managers.
	var target = main.grid.get_cell(Vector2i(8, 6))
	var before: int = main.enemy_manager.enemies.size()
	root.get_node("GameState").game_active = true
	assert(main._try_hit_enemy_at(target.global_position))
	assert(main.enemy_manager.enemies.size() == before - 1)
	root.get_node("GameState").game_active = false
	main.robot_manager.remove_all()
	main.enemy_manager.clear()
	await process_frame
	assert(main.robot_manager.robots.is_empty())
	assert(main.enemy_manager.enemies.is_empty())
	print("FACTION_REVIEW_OK: five robots, four bugs, nest, unreachable slime, atlas frames, lock lifecycle, click routing, rules, 640x480")
	quit()


func _isolated_pixels() -> void:
	# Oversized transparent viewports expose overflow instead of clipping it away.
	for kind in ["ally", "enemy", "lock"]:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(56, 56)
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var actor: Node2D
		if kind == "lock":
			actor = load("res://scripts/visuals/locked_cell_seal.gd").new()
		else:
			actor = load("res://scripts/visuals/faction_marker.gd").new()
			actor.set("hostile", kind == "enemy")
		actor.position = Vector2(28, 28)
		viewport.add_child(actor)
		await process_frame
		await RenderingServer.frame_post_draw
		assert(viewport.get_texture().get_image().save_png("res://tmp/faction_" + kind + "_pixels.png") == OK)
		viewport.queue_free()
	# Render every atlas frame in isolation; compare alpha support to source PNGs.
	for actor in allies + enemies:
		var kind: String = actor.get("robot_type") if actor.get("robot_type") != null else actor.get("enemy_type")
		var viewport := SubViewport.new()
		viewport.size = Vector2i(56, 56)
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var skin: Sprite2D = actor.get_node("Skin").duplicate()
		skin.position = Vector2(28, 28)
		viewport.add_child(skin)
		for frame in 3:
			skin.frame = frame
			await process_frame
			await RenderingServer.frame_post_draw
			assert(viewport.get_texture().get_image().save_png("res://tmp/faction_%s_frame%d_pixels.png" % [kind, frame]) == OK)
		viewport.queue_free()


func _capture(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://tmp/faction_" + filename
	assert(root.get_texture().get_image().save_png(path) == OK)
	print("FACTION_SCREENSHOT ", path)
