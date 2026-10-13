extends Node
## Run with --path . res://visual_v2/review/ui_a_layout_review.tscn.
## Real GUI clicks, numeric keys, gameplay integration and measured layout bounds.
## Writes review images to tmp/ui_a_*.png. Back up user:// before running.
var main: Node
var failures: Array[String] = []
@onready var root: Window = get_tree().root
@onready var process_frame: Signal = get_tree().process_frame
var paused: bool:
	get:
		return get_tree().paused

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok:
		failures.append(message)

func settle() -> void:
	for i in 4:
		await process_frame

func click(b: Button) -> void:
	check(b.is_visible_in_tree() and not b.disabled, "clickable " + str(b.name))
	await click_point(b.get_global_rect().get_center())

func click_point(p: Vector2, mouse_button := MOUSE_BUTTON_LEFT) -> void:
	var vp := root
	var motion := InputEventMouseMotion.new()
	motion.position = p
	motion.global_position = p
	vp.push_input(motion)
	await get_tree().create_timer(0.06).timeout
	var e := InputEventMouseButton.new()
	e.button_index = mouse_button
	e.position = p
	e.global_position = p
	e.pressed = true
	vp.push_input(e)
	e = e.duplicate()
	e.pressed = false
	vp.push_input(e)
	await settle()

func key(code: Key, repeat := false, ctrl := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	e.echo = repeat
	e.ctrl_pressed = ctrl
	root.push_input(e)
	e = e.duplicate()
	e.pressed = false
	root.push_input(e)
	await settle()

func board_rect() -> Rect2:
	var g: Grid = main.grid
	var s: Vector2 = main.get_node("BoardRoot").scale
	return Rect2(g.global_position + Vector2(0, g._view_top_px) * s, Vector2(g.cols * g.cell_size, g.view_window_px()) * s)

func screenshot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/ui_a_" + name + ".png")

func _run() -> void:
	GameState.boot_splash_played = true
	GameSettings.values["fullscreen"] = false
	GameSettings.values["window_size"] = "1024x768"
	GameSettings._apply_fullscreen()
	DisplayServer.window_set_size(Vector2i(1024, 768))
	for id in ["ch01_s01", "ch01_s02", "ch01_s03", "ch01_s04", "ch01_s05", "ch01_s06", "ch01_s07", "ch02_s01", "ch02_s02", "ch02_s03", "ch02_s04", "ch02_s05"]:
		GameSettings.values["tutorial_done_" + id] = true
	for k in ["start_money", "start_lives", "global_speed", "work_speed", "start_robot"]:
		SaveSystem.unlocks[k] = 0
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await settle()
	if "--mask-only" in OS.get_cmdline_user_args():
		await _verify_tower_pixels()
		get_tree().quit()
		return
	main._start_level("ch01_s03")
	await settle()
	main.shop.robots_working = false
	await get_tree().create_timer(0.65).timeout
	var base_rect := board_rect()
	check(main.grid.cols == 16 and main.grid.rows == 16, "level dimensions preserved")
	check(GameState.money == 300 and GameState.score == 101, "real level initial money and score")
	check(not main.upgrade_panel.visible and main.shop.view == "buy", "purchase view by default")
	check(not main.get_node("UILayer/PlayerLogPanel").visible and not main.get_node("UILayer/RobotLogPanel").visible, "logs start closed")
	check(main.get_node("UILayer/PlayerLogPanel").get_index() > main.shop.get_index(), "records draw above shop background")
	check(main.shop._quick_buttons.size() == 4, "four constant shortcut entries")
	check(main.shop._quick_buttons.detector.disabled and main.shop._quick_buttons.miner.disabled, "unavailable robot types stay locked")
	check(main.hud.money_label == main.shop.money_label and get_tree().get_first_node_in_group("hud_money") == main.shop.money_label, "money effects use visible shop balance")
	await screenshot("purchase_1024")
	await click(main.shop.upgrade_button)
	check(main.upgrade_panel.visible and main.shop.view == "upgrade", "upgrade tab opens real panel")
	check(board_rect().is_equal_approx(base_rect), "opening upgrade does not move board")
	check(not main.upgrade_panel.get_global_rect().intersects(base_rect), "upgrades never overlap board")
	await screenshot("upgrade_1024")
	await key(KEY_1)
	check(GameState.money == 250 and GameState.opener_count == 1, "key 1 purchases during upgrades")
	await click(main.upgrade_panel.rows_box.get_node("OpenerMoveRow/BuyButton"))
	check(GameState.money == 200 and GameState.get_upgrade_level("opener_move") == 1, "real upgrade purchased")
	await click(main.shop.records_button)
	check(main.shop.view == "logs" and main.get_node("UILayer/PlayerLogPanel").visible, "records toggle shows player stream")
	await key(KEY_2)
	check(GameState.money == 150 and GameState.marker_count == 1, "key 2 purchases while reading records")
	check(main.get_node("UILayer/PlayerLogPanel")._log.get_parsed_text().contains("购入"), "purchase recorded in real stream")
	await click(main.shop.robot_log_button)
	check(main.get_node("UILayer/RobotLogPanel").visible and not main.get_node("UILayer/PlayerLogPanel").visible, "robot log tab switches stream")
	await screenshot("records_1024")
	await click(main.shop.records_button)
	await get_tree().create_timer(0.65).timeout
	check(main.shop.view == "buy" and not main.get_node("UILayer/RobotLogPanel").visible, "records close without losing entries")
	var before: int = GameState.money
	await key(KEY_3)
	await key(KEY_4)
	await key(KEY_1, true)
	await key(KEY_1, false, true)
	check(GameState.money == before, "locked, held and modified keys do not purchase")
	var p: Button = main.shop._quick_buttons.opener
	await click(p)
	check(GameState.money == 50 and GameState.opener_count == 2, "shortcut button shares purchase and doubled price")
	check(main.shop._quick_buttons.opener.disabled and main.shop._quick_buttons.marker.disabled, "unaffordable shortcuts are disabled")
	# Logged events continue while records are closed.
	GameState.game_event_logged.emit("Review event while hidden", "player", "dim")
	await click(main.shop.records_button)
	await click(main.shop.player_log_button)
	check(main.get_node("UILayer/PlayerLogPanel")._log.get_parsed_text().contains("Review event while hidden"), "closed logs continue recording")
	await key(KEY_ESCAPE)
	check(main.shop.view == "buy" and not main.pause_panel.visible, "escape closes logs first")
	await click(main.hud.get_node("MissionSurface/MissionRow/Survival/SettingsButton"))
	check(main.settings_panel.visible and paused, "settings pause real game")
	before = GameState.money
	await key(KEY_1)
	check(GameState.money == before, "settings block numeric purchases")
	await key(KEY_ESCAPE)
	check(not main.settings_panel.visible and main.pause_panel.visible, "settings escape reveals pause")
	await key(KEY_ESCAPE)
	check(not paused and not main.pause_panel.visible, "second escape resumes")
	await click(main.shop.auto_button)
	check(main.shop.robots_working, "automatic work resumes")
	await click(main.shop.auto_button)
	check(not main.shop.robots_working and GameState.game_active, "stopping robots keeps manual gameplay active")
	# Different real maps, including extra shop entries and the scrolling tower.
	for level_id in ["ch01_s01", "ch01_s02", "ch01_s04", "ch01_s05", "ch01_s06", "ch02_s01", "ch02_s03", "ch02_s04", "ch02_s05"]:
		main._start_level(level_id)
		await settle()
		main.tutorial_guide.hide()
		main.shop.robots_working = false
		check(not main.shop.get_global_rect().intersects(board_rect()), level_id + " board and shop separate")
		check(main.shop.view == "buy", level_id + " resets shop view")
		check(main.shop._quick_buttons.opener.is_visible_in_tree(), level_id + " keeps shortcut entry")
		if level_id in ["ch01_s01", "ch01_s04", "ch01_s05", "ch01_s06", "ch02_s04"]:
			await screenshot(level_id)
		if main.grid.view_range_px() > 0:
			check(main.get_node("BoardRoot").clip_children == CanvasItem.CLIP_CHILDREN_ONLY, "tower rendering is clipped to board area")
			main.grid.scroll_view(1, false)
			await settle()
			check(not main.shop.get_global_rect().intersects(board_rect()), "tower scroll preserves bounds")
			await click(main.shop.upgrade_button)
			check(main.upgrade_panel.visible, "tower shop remains clickable after scrolling")
			await click(main.shop.records_button)
			check(main.shop.view == "logs", "tower records remain clickable")
			var spotlight: Rect2 = main.tutorial_guide._spot_rect({"node": main.grid})
			check(spotlight.is_equal_approx(board_rect()), "tower spotlight matches visible board")
	# Viewport sizes are measured in actual canvas coordinates after stretch.
	main._start_level("ch01_s03")
	await settle()
	for window_size in [Vector2i(1024, 768), Vector2i(1280, 900), Vector2i(800, 768), Vector2i(640, 480)]:
		DisplayServer.window_set_size(window_size)
		await get_tree().create_timer(0.15).timeout
		await settle()
		main._relayout_play_area()
		await settle()
		var vp := root.get_visible_rect()
		var shop_rect: Rect2 = main.shop.get_global_rect()
		var r := board_rect()
		check(vp.encloses(shop_rect) and vp.encloses(r) and not shop_rect.intersects(r), "viewport fits " + str(window_size))
		check(main.shop._quick_buttons.opener.get_global_rect().end.y < shop_rect.end.y, "shortcut stays in shop " + str(window_size))
		check(main.hud.manual_readout.get_global_rect().end.y < vp.end.y, "manual charges visible " + str(window_size))
		print("BOUNDS ", window_size, " viewport=", vp, " board=", r, " shop=", shop_rect, " tile=", main.grid.cell_size * main.get_node("BoardRoot").scale.x)
		await screenshot("size_%dx%d" % [window_size.x, window_size.y])
	DisplayServer.window_set_size(Vector2i(1024, 768))
	await get_tree().create_timer(0.15).timeout
	main._start_level("ch01_s03")
	await settle()
	main.shop.robots_working = false
	await click(main.shop.upgrade_button)
	var time_before: float = GameState.time_left
	await get_tree().create_timer(0.2).timeout
	check(GameState.time_left < time_before and not paused, "upgrades do not pause countdown")
	var mine: Vector2i = GameState.get_current_level().fixed_mines[0]
	await click_point(main.grid.global_transform * (Vector2(mine) * main.grid.cell_size + Vector2.ONE * main.grid.cell_size / 2.0), MOUSE_BUTTON_RIGHT)
	check(main.grid.get_cell(mine).is_flagged, "right click flags while upgrades remain open")
	var safe_coord := Vector2i(-1, -1)
	for coord in main.grid.cells:
		var c: Cell = main.grid.cells[coord]
		if not c.is_opened and not c.is_mine and c.adjacent_mines > 0:
			safe_coord = coord
			break
	check(safe_coord.x >= 0, "safe unopened test cell exists")
	await click_point(main.grid.global_transform * (Vector2(safe_coord) * main.grid.cell_size + Vector2.ONE * main.grid.cell_size / 2.0))
	check(main.grid.get_cell(safe_coord).is_opened, "left click opens actual board while upgrades remain open")
	await click(main.shop.buy_tab)
	await click(main.shop.build_base_button)
	check(main.placing_mode == "base", "base purchase enters placement")
	before = GameState.money
	check(not main.shop.try_buy("opener") and GameState.money == before, "placement blocks quick purchases")
	var site := Vector2i(-1, -1)
	for coord in main.grid.cells:
		var c: Cell = main.grid.cells[coord]
		if c.is_opened and not c.is_mine and not GameState.bases.has(coord):
			site = coord
			break
	var base_price: int = GameState.get_base_price()
	await click_point(main.grid.global_transform * (Vector2(site) * main.grid.cell_size + Vector2.ONE * main.grid.cell_size / 2.0))
	check(main.placing_mode == "" and GameState.bases.has(site) and GameState.money == before - base_price, "placing base deducts actual price at confirmation")
	await click(main.shop.build_base_button)
	await click(main.shop._cancel_placement)
	check(main.placing_mode == "" and not main.shop.hint_label.visible, "cancel placement restores shop")
	await click(main.shop.records_button)
	await click(main.shop.player_log_button)
	await screenshot("player_records_1024")
	var log_panel = main.get_node("UILayer/PlayerLogPanel")
	for i in 150:
		GameState.game_event_logged.emit("Review history %d" % i, "player", "dim")
	await settle()
	check(log_panel._entries.size() == 120, "log retains bounded history")
	var scroll: VScrollBar = log_panel._log.get_v_scroll_bar()
	scroll.value = 0
	GameState.game_event_logged.emit("New event while reading older history", "player", "dim")
	await settle()
	check(scroll.value < 2, "new log entries do not jump during history review")
	await click(main.shop.records_button)
	await click(main.shop.records_button)
	await settle()
	check(scroll.value + scroll.page >= scroll.max_value - 2, "reopening records shows latest entries")
	# Actual second-level guide: board action -> relocated upgrade button -> full upgrade page.
	GameSettings.values["tutorial_done_ch01_s02"] = false
	main._start_level("ch01_s02")
	await get_tree().create_timer(0.7).timeout
	await settle()
	check(main.tutorial_guide.visible and main.tutorial_guide._step_idx == 0, "level 2 tutorial starts")
	var spot: Rect2 = main.tutorial_guide._spot_rect(main.tutorial_guide.steps[0])
	check(spot.is_equal_approx(board_rect()), "tutorial spotlight follows enlarged board")
	main.tutorial_guide.notify_event("board_click")
	await settle()
	check(main.tutorial_guide._step_idx == 1 and main.tutorial_guide.steps[1].node == main.shop.upgrade_button, "tutorial targets relocated upgrade tab")
	await screenshot("tutorial_upgrade_1024")
	await click(main.shop.upgrade_button)
	check(main.upgrade_panel.visible and not main.tutorial_guide.visible, "tutorial finishes when actual upgrade tab opens")
	GameState.add_money(10)
	await settle()
	check(main.hud._gain_popup != null and main.hud._gain_popup.get_parent() == main.shop.money_label, "money feedback follows visible shop balance")
	main._start_level("ch01_s03")
	await settle()
	main.shop.select_view("buy")
	main.hud.clear_toast()
	await get_tree().create_timer(1.5).timeout
	await screenshot("final_1024")
	print("UI A REVIEW FAILURES: ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)


## Frozen reference images let PIL measure clipping independently of visual inspection.
func _verify_tower_pixels() -> void:
	main._start_level("ch01_s06")
	await settle()
	main.tutorial_guide.hide()
	main.hud.clear_toast()
	await get_tree().create_timer(1.5).timeout
	main.grid.scroll_view(1, false)
	await settle()
	get_tree().paused = true
	await screenshot("mask_enabled")
	var world: Node2D = main.get_node("BoardRoot")
	world.set_clip_rect(main._play_area_rect, false)
	await screenshot("mask_disabled")
	world.set_clip_rect(main._play_area_rect, true)
	world.hide()
	await screenshot("mask_background")
	var area: Rect2 = main._play_area_rect
	var vp: Rect2 = root.get_visible_rect()
	var im: Image = root.get_texture().get_image()
	var f := FileAccess.open("res://tmp/ui_a_mask_bounds.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"area": [area.position.x, area.position.y, area.end.x, area.end.y], "viewport": [vp.size.x, vp.size.y], "image": [im.get_width(), im.get_height()]}))
	get_tree().paused = false
