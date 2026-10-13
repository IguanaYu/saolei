extends SceneTree
## 正常渲染运行：Godot_console --path . --position -3000,0 -s res://scripts/tests/ch02_presentation_test.gd
## 真实节点、几何快照、UI 点击、暂停/重开与截图；备份并恢复存档。
const OUT := "res://tmp/ch02_presentation_evidence/"
var main: Node
var gs: Node
var audio: Node
var failures: Array = []
var checks := 0
var save_backup := ""
var save_path := ""
var settings_before: Dictionary = {}
var _finished := false


func _initialize() -> void:
	DisplayServer.window_set_position(Vector2i(-3000, 0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	change_scene_to_file("res://scenes/ui/BootLoading.tscn")
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	print("[Ch02Visual] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		failures.append(label)


func wait_sec(seconds: float) -> void:
	await create_timer(seconds, true).timeout


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + name + ".png"))
	print("[Ch02Visual] screenshot ", name)


func start(id: String) -> void:
	root.get_node("GameSettings").values["tutorial_done_" + id] = true  # 仅内存，避免延迟教学影响测量
	main._start_level(id)
	main.set_process(false)  # 固定场景供验证；不靠帧率等待随机巡逻位置
	main.tutorial_guide.hide()
	await wait_sec(0.4)


func click(button: Button) -> void:
	var center := button.get_global_rect().get_center()
	var pos := root.get_final_transform() * center
	var move := InputEventMouseMotion.new()
	move.position = pos
	move.global_position = pos
	Input.parse_input_event(move)
	await process_frame
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.position = pos
		ev.global_position = pos
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await process_frame


func fx_with(prefix: String) -> Array:
	return main.grid.get_node("EffectsLayer").get_children().filter(func(n):
		return String(n.name).begins_with(prefix) and not n.is_queued_for_deletion())


func _run() -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while root.get_node_or_null("Main") == null and Time.get_ticks_msec() < deadline:
		await wait_sec(0.1)
	main = root.get_node_or_null("Main")
	if main == null:
		check(false, "BootLoading enters Main")
		quit(1)
		return
	gs = root.get_node("GameState")
	audio = root.get_node("AudioManager")
	settings_before = root.get_node("GameSettings").values.duplicate(true)
	save_path = OS.get_user_data_dir() + "/save_data.json"
	if FileAccess.file_exists(save_path):
		save_backup = FileAccess.get_file_as_string(save_path)
		var backup := FileAccess.open(OUT + "save_data.backup.json", FileAccess.WRITE)
		backup.store_string(save_backup)
		backup.close()
	create_timer(60, true).timeout.connect(func():
		if not _finished:
			check(false, "test timed out; save restored")
			_finish())

	await start("ch02_s01")
	var g: Node = main.grid
	check(main.shop.key_hint_bar.get_node("L1").text == "发射激光", "laser controls are contextual")
	var walls: Array = g.cells.values().filter(func(c): return not c.is_mine and c.wall_hp == 3)
	check(not walls.is_empty(), "reinforced wall sample exists")
	var wall: Node = walls[0]
	check(wall.get_node("ReinforcedWallOverlay").layers == 3, "three-layer reinforcement visible")
	g.open_cell(wall.coord, "player_laser")
	check(wall.wall_hp == 2 and wall.get_node("ReinforcedWallOverlay").layers == 2, "chip updates wall state")
	g.open_cell(wall.coord, "player_laser")
	check(wall.wall_hp == 1 and wall.get_node("ReinforcedWallOverlay").visible, "last layer retains cracks")
	g.open_cell(wall.coord, "player_laser")
	check(wall.is_opened and not wall.get_node("ReinforcedWallOverlay").visible, "opening removes reinforcement")
	await shot("01-wall-states")

	await start("ch02_s02")
	g = main.grid
	var cancelled_robot: Node = main.robot_manager.spawn_robot(gs.bases[0], "opener", g,
		gs.bases[0], 1.0)
	main.robot_manager.remove_robot(cancelled_robot, "test_cancel_before_landing")
	await wait_sec(1.25)
	check(not is_instance_valid(cancelled_robot) and fx_with("RobotFly").is_empty(),
		"removing a robot before landing cancels safely and clears delivery effects")
	main.enemy_manager._spawn_builder(g, [3])
	var builder: Node = main.enemy_manager.builders.back()
	await wait_sec(0.15)
	var spawn_left: float = builder._spawn_left
	var rift_age: float = builder._rift.age
	paused = true
	await wait_sec(0.2)
	check(is_equal_approx(builder._spawn_left, spawn_left) and is_equal_approx(builder._rift.age, rift_age), "rift and spawn countdown freeze on pause")
	paused = false
	await wait_sec(2.05)
	check(builder.visible and builder.get_node("Skin").texture.resource_path.contains("ch02_v1/enemies/builder_sheet"), "builder has its own sprite after warning")
	check(not is_instance_valid(builder._rift), "warning removed after spawn")
	var covers_before: int = g.count_cover_walls()
	builder._try_build(g)
	check(g.count_cover_walls() == covers_before + 1, "successful construction creates a cover wall")
	var cover_coord: Vector2i = builder._my_walls.back()
	var cover: Node = g.get_cell(cover_coord)
	check(cover.get_node("CoverWallOverlay").constructed and cover.cover_wall_hp == 3, "cover wall uses masonry state")
	builder.take_hit("player_laser")
	check(builder.hp == 1 and builder.is_alive(), "first hit preserves wounded builder")
	var worker: Node = main.robot_manager.spawn_robot(gs.bases[0], "opener", g)
	await wait_sec(0.7)
	worker.apply_charge()
	await wait_sec(0.12)
	var ring: Node = worker.get_node("ChargeRing")
	check(ring.is_visible_in_tree() and worker.is_charged(), "charge entry and remaining ring visible")
	var charge_clock: float = ring._pulse
	paused = true
	await wait_sec(0.18)
	check(is_equal_approx(ring._pulse, charge_clock), "charge animation freezes on pause")
	paused = false
	await shot("02-builder-cover-charge")
	main.rules_panel.open()
	await wait_sec(0.1)
	check(main.rules_panel.legend_box.has_node("OverloadRangeExample"), "rules include the 13/17-cell diagram")
	await shot("03-rules-top")
	main.rules_panel.get_node("Center/Panel/Margin/VBox/RulesScroll").scroll_vertical = 430
	await wait_sec(0.1)
	await shot("04-rules-range")
	main.rules_panel.close()
	builder.take_hit("player_laser")
	check(not builder.is_alive() and cover.cover_wall_hp == 3, "builder death preserves its walls")
	gs.elapsed += 6.1
	await wait_sec(0.3)
	check(not worker.is_charged() and not ring.visible, "charge expires and returns to normal")
	g.damage_cover_wall_at(cover_coord, 1)
	check(cover.cover_wall_hp == 2 and cover.get_node("CoverWallOverlay").layers == 2, "cover wall chip updates state")
	g.damage_cover_wall_at(cover_coord, 2)
	check(cover.is_opened and not cover.get_node("CoverWallOverlay").visible, "demolition restores open ground")

	await start("ch02_s03")
	g = main.grid
	var lm: Node = main.laser_manager
	var base: Vector2i = gs.bases[0]
	var target := Vector2i(g.cols - 1, base.y)
	var rng_before = lm.burst_rng.state
	for i in 5:
		lm._on_cell_hovered(g.get_cell(target))
	check(lm.burst_rng.state == rng_before, "preview leaves ore RNG untouched")
	var geo: Dictionary = lm.compute_shot_geometry(base, target, false)
	var endpoint: Vector2i = geo.main.back()
	check(endpoint != target and main.grid._laser_preview.to_px == g.get_cell(endpoint).position, "preview line stops at the actual blocker")
	var ore: Node = geo.ores[0]
	var sprite: Sprite2D = ore.get_node("OreSkin")
	check(sprite.texture.get_size() == Vector2(144, 48) and sprite.hframes == 3, "ore uses a three-frame sheet")
	check(sprite.get_rect().size * sprite.scale == Vector2.ONE * (g.cell_size * 2 - 6), "ore sprite fits inside the 2x2 footprint")
	await shot("05-ore-preview")
	g.hide_laser_preview()
	lm.burst_rng.seed = 12
	var state_before = lm.burst_rng.state
	var expected: Dictionary = lm.compute_shot_geometry(base, target)
	lm.burst_rng.state = state_before
	lm.fire(base, target)
	var beam: Node = fx_with("LaserBeam").back()
	check(is_equal_approx(beam.length_px, g.get_cell(endpoint).position.distance_to(g.get_cell(base).position)), "emitted beam uses the stopped endpoint")
	var ore_fx: Node = fx_with("OreBlast").back()
	check(ore_fx.rays.size() == expected.ore_details[0].rays.size(), "ore effects carry the sampled rays")
	await wait_sec(0.10)
	await shot("06-ore-burst")
	await wait_sec(0.6)
	check(is_instance_valid(ore) and fx_with("OreBlast").is_empty(), "ore resets and temporary rays are removed")

	await start("ch02_s04")
	g = main.grid
	lm = main.laser_manager
	gs.add_money(500)
	await wait_sec(0.2)
	var viewport_bottom: float = main.get_viewport().get_visible_rect().end.y
	check(main.shop.buy_overload_range_button.get_global_rect().end.y <= viewport_bottom and main.shop.key_hint_bar.get_global_rect().end.y <= viewport_bottom, "expanded shop and key hints remain inside viewport")
	await click(main.shop.buy_overload_button)
	await wait_sec(0.85)
	check(gs.get_robot_purchased_count("overload") == 1, "real shop click buys overload")
	var overload: Node = main.robot_manager.robots.filter(func(r): return r.robot_type == "overload")[0]
	check(overload.get_node("Skin").texture.resource_path.contains("ch02_v1/robots/overload_sheet"), "overload never inherits opener skin")
	check(not overload.get_node("Body").visible and not overload.get_node("IconLabel").visible, "sprite presentation hides fallback shapes")
	overload.set_initial_position(Vector2i(8, 7), g)
	var blast13: Array = overload.blast_cells(g)
	check(blast13.size() == 13, "default blast has 13 cells")
	var flag_coord: Vector2i = overload.coord + Vector2i(2, 0)
	g.toggle_flag(flag_coord, "test")
	var flag_cell: Node = g.get_cell(flag_coord)
	var flag_hp: int = flag_cell.wall_hp
	lm.fire(gs.bases[0], overload.coord)
	var blast_fx: Node = fx_with("OverloadBlast").back()
	check(blast_fx.entries.size() == 12 and flag_cell.is_flagged and flag_cell.wall_hp == flag_hp, "flag is protected and excluded from impact tiles")
	check(not fx_with("MechanicShield").is_empty(), "flag protection has separate feedback")
	await wait_sec(0.10)
	check(overload.position.is_equal_approx(g.coord_to_world(overload.coord)), "overload body and blast share the same grid position")
	await shot("07-overload-13")
	await click(main.shop.buy_overload_range_button)
	check(gs.overload_range_level == 1, "real shop click purchases range upgrade")
	var blast17: Array = overload.blast_cells(g)
	check(blast17.size() == 17 and not blast17.has(overload.coord + Vector2i(2, 2)), "upgrade extends only cardinal arms")
	g.get_node("EffectsLayer").clear_all()
	await process_frame
	lm.fire(gs.bases[0], overload.coord)
	blast_fx = fx_with("OverloadBlast").back()
	check(blast_fx.entries.size() == 16, "expanded effect reflects the actual 17-cell snapshot minus flag")
	await wait_sec(0.10)
	await shot("08-overload-17")
	var blast_age: float = blast_fx.age
	paused = true
	await wait_sec(0.2)
	check(is_equal_approx(blast_fx.age, blast_age), "blast freezes on pause")
	paused = false
	await wait_sec(0.6)
	check(is_instance_valid(overload) and overload.scale == Vector2.ONE and fx_with("OverloadBlast").is_empty(), "overload survives and restores reusable appearance")
	var sound_names := ["laser", "wall_chip", "wall_break", "charge", "ore_burst", "overload", "builder_rift", "builder_build", "builder_break"]
	check(sound_names.all(func(key): return audio._streams.has(key)), "all nine mechanism sounds are loaded")
	audio.clear_sfx()
	audio.play_sfx("laser", 1.0, 0.15)
	audio.clear_sfx()
	await wait_sec(0.2)
	check(audio._players.all(func(player): return not player.playing), "cleared delayed sounds cannot return")
	check(audio._bgm.stream.resource_path.ends_with("bgm_ch02_v1.wav") and audio._bgm.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "chapter music loops")

	await start("ch02_s03")
	check(fx_with("OreBlast").is_empty() and fx_with("OverloadBlast").is_empty(), "restart removes old mechanic effects")
	await start("ch01_s01")
	check(main.shop.key_hint_bar.get_node("L1").text == "开格" and not main.get_node("CaveEnv/LaserMineAccent").visible, "first chapter restores its controls and ambience")
	var fallback: Node = main.robot_manager.spawn_robot(gs.bases[0], "refractor_wide", main.grid)
	check(fallback.get_node("Skin").texture == null and fallback.get_node("Body").visible, "unsupported robot switches cleanly to fallback")
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	root.get_node("GameSettings").values = settings_before
	if save_backup != "":
		var file := FileAccess.open(save_path, FileAccess.WRITE)
		file.store_string(save_backup)
		file.close()
	var report := FileAccess.open(OUT + "report.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks": checks, "failures": failures}, "\t"))
	print("[Ch02Visual] ", checks - failures.size(), "/", checks, " checks passed")
	quit(0 if failures.is_empty() else 1)
