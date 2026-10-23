extends SceneTree
## 独立临时单位验收。FakeCell 故意没有 is_mine 属性，禁止把隐藏真值当候选筛选。

class PublicCell extends RefCounted:
	var coord := Vector2i.ZERO
	var is_opened := false
	var is_flagged := false
	var is_collapsed := false
	var is_webbed := false
	var bomb_masked := false
	var adjacent_mines := 0
	var is_locked := false
	var is_fossil := false
	var is_base := false
	var is_vein := false
	var is_confirmed_mine := false
	var path_blockers := 0
	var cover_wall_hp := 0
	var wall_hp := 1

class PublicGrid extends Node2D:
	var cells: Dictionary = {}
	var facility_cells: Dictionary = {}
	var cell_size := 28
	var opened: Array = []
	var hidden_layout: Dictionary = {}
	var end_on_work := false

	func populate() -> void:
		cells.clear()
		for y in 2:
			for x in 4:
				var c := PublicCell.new()
				c.coord = Vector2i(x, y)
				cells[c.coord] = c
		cells[Vector2i(0,0)].is_opened = true
		cells[Vector2i(0,0)].adjacent_mines = 1
		cells[Vector2i(1,0)].is_flagged = true

	func get_cell(coord: Vector2i):
		return cells.get(coord)

	func get_neighbors(coord: Vector2i) -> Array:
		var neighbors: Array = []
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var c: Vector2i = coord + Vector2i(dx, dy)
				if c != coord and cells.has(c):
					neighbors.append(cells[c])
		return neighbors

	func open_cell(coord: Vector2i, by_actor: String) -> void:
		var c = get_cell(coord)
		if c == null or c.is_opened or c.is_flagged or c.is_locked or c.is_fossil:
			return
		if c.wall_hp > 1:
			c.wall_hp -= 1
		else:
			c.is_opened = true
		opened.append({"coord":coord, "actor":by_actor})
		if end_on_work:
			var state = get_node("/root/GameState")
			state.game_active = false
			state.game_over.emit("win")

var manager
var grid
var gs
var failures: Array = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print("[EXPLORER] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		failures.append(label)

func fixture() -> void:
	manager.remove_all()
	grid.populate()
	grid.opened.clear()
	grid.end_on_work = false
	gs.game_active = true
	gs.current_level_id = "explorer_public_test"
	gs.locked_targets.clear()
	gs.result_stats["diamond_explorer_actions"] = 0
	gs.result_stats["diamond_explorer_wait_seconds"] = 0.0
	manager.reset_for_level()

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	var audio = root.get_node("AudioManager")
	audio.clear_sfx()
	var bgm = audio.get_node_or_null("BgmPlayer")
	if bgm != null:
		bgm.stop()
		bgm.stream = null
	gs = root.get_node("GameState")
	grid = PublicGrid.new()
	grid.name = "PublicGrid"
	root.add_child(grid)
	manager = load("res://scripts/diamond/explorer_manager.gd").new()
	manager.name = "ExplorerUnitTestManager"
	root.add_child(manager)
	manager.setup(grid)
	manager.set_process(false)
	fixture()
	var actor = manager.summon(Vector2i(1,0), {"actions":2})
	check(actor != null and grid.get_cell(Vector2i(1,0)).is_flagged,
		"spawn leaves flagged origin untouched")
	manager.tick_all(1.4)
	check(grid.opened.is_empty(), "action interval respected")
	manager.tick_all(0.2)
	check(grid.opened.size() == 1 and grid.opened[0].actor == "diamond_explorer",
		"public solver target opens with independent actor source")
	manager.tick_all(1.6)
	check(grid.opened.size() == 2 and manager.actors.is_empty() and gs.locked_targets.is_empty(),
		"configured action budget completes and releases reservations")
	fixture()
	var first = manager.summon(Vector2i(1,0), {})
	var second = manager.summon(Vector2i(1,0), {})
	check(first.target != second.target and manager.get_reserved_targets().size() == 2,
		"concurrent explorers reserve distinct public targets")
	var old_age: float = first.age
	paused = true
	manager.tick_all(5.0)
	check(first.age == old_age and grid.opened.is_empty(), "pause freezes work and lifetime")
	paused = false
	manager.tick_all(1.6)
	check(grid.opened.size() == 2, "resume processes distinct reservations once")
	fixture()
	var robot_owner := Node2D.new()
	root.add_child(robot_owner)
	gs.locked_targets[Vector2i(1,1)] = robot_owner
	actor = manager.summon(Vector2i(1,0), {})
	check(actor.target == Vector2i(0,1), "existing robot lock excluded")
	manager.remove_all()
	check(gs.locked_targets.get(Vector2i(1,1)) == robot_owner,
		"cleanup preserves another unit lock")
	robot_owner.queue_free()
	fixture()
	actor = manager.summon(Vector2i(1,0), {})
	grid.get_cell(Vector2i(1,0)).is_flagged = false
	manager.tick_all(1.6)
	check(grid.opened.is_empty(), "changed public evidence is rechecked before work")
	fixture()
	grid.hidden_layout = {Vector2i(3,1):true}
	manager.summon(Vector2i(1,0), {})
	var target_a: Array = manager.get_reserved_targets()
	manager.reset_for_level()
	grid.hidden_layout = {Vector2i(2,1):true}
	manager.summon(Vector2i(1,0), {})
	check(manager.get_reserved_targets() == target_a,
		"hidden layout never influences selection; cells expose no is_mine")
	fixture()
	grid.get_cell(Vector2i(0,0)).is_opened = false
	manager.summon(Vector2i(1,0), {"lifetime":2.0})
	manager.tick_all(1.6)
	check(grid.opened.is_empty() and gs.result_stats.diamond_explorer_wait_seconds == 1.6,
		"without certain targets wait without guessing")
	manager.tick_all(0.5)
	check(manager.actors.is_empty() and gs.locked_targets.is_empty(), "idle lifetime expiry cleans up")
	fixture()
	var summons_before: int = gs.result_stats.get("diamond_explorers_summoned",0)
	for i in 9:
		manager.summon(Vector2i(1,0), {})
	check(manager.actors.size() == 8 and manager.pending_summons.size() == 1,
		"default cap is eight while ninth independent request waits")
	check(gs.result_stats.diamond_explorers_summoned == summons_before + 8,
		"summon statistics count actual spawned actors")
	manager._remove_actor(manager.actors[0], "test_release")
	paused = true
	manager.tick_all(0.0)
	check(manager.actors.size() == 7 and manager.pending_summons.size() == 1,
		"pause also freezes pending summons")
	paused = false
	manager.tick_all(0.0)
	check(manager.actors.size() == 8 and manager.pending_summons.is_empty()
		and gs.result_stats.diamond_explorers_summoned == summons_before + 9,
		"released slot spawns queued request without dropping effect")
	manager.summon(Vector2i(1,0), {})
	manager.reset_for_level()
	manager.tick_all(5.0)
	check(manager.actors.is_empty() and manager.pending_summons.is_empty(),
		"reset removes pending requests and active actors")
	fixture()
	manager.summon(Vector2i(1,0), {})
	grid.populate()
	manager.tick_all(2.0)
	check(grid.opened.is_empty() and manager.actors.is_empty(), "board replacement cancels old generation")
	fixture()
	grid.end_on_work = true
	for i in 9:
		manager.summon(Vector2i(1,0), {})
	manager.tick_all(1.6)
	check(gs.result_stats.diamond_explorer_actions == 1 and manager.actors.is_empty()
		and manager.pending_summons.is_empty(),
		"winning last action is counted before synchronous end cleanup")
	fixture()
	manager.summon(Vector2i(1,0), {})
	manager.reset_for_level()
	manager.tick_all(5.0)
	check(grid.opened.is_empty() and gs.locked_targets.is_empty(), "reset cannot produce delayed opening")
	fixture()
	grid.get_cell(Vector2i(1,1)).is_locked = true
	grid.get_cell(Vector2i(0,1)).is_fossil = true
	actor = manager.summon(Vector2i(1,0), {})
	manager.tick_all(2.0)
	check(actor.target == null and grid.opened.is_empty(), "locks and fossils are never work targets")
	fixture()
	grid.facility_cells[Vector2i(1,1)] = true
	actor = manager.summon(Vector2i(1,0), {})
	check(actor.target == Vector2i(0,1), "public facility occupancy excluded")
	grid.facility_cells.clear()
	fixture()
	actor = manager.summon(Vector2i(1,0), {})
	var old_target: Vector2i = actor.target
	grid.get_cell(old_target).is_opened = true
	manager.tick_all(1.6)
	check(grid.opened.size() == 1 and grid.opened[0].coord != old_target,
		"target opened by someone else is replaced without duplicate work")
	fixture()
	grid.get_cell(Vector2i(1,1)).wall_hp = 3
	actor = manager.summon(Vector2i(1,0), {"actions":2, "interval":0.5})
	manager.tick_all(0.5)
	manager.tick_all(0.5)
	check(grid.get_cell(Vector2i(1,1)).wall_hp == 1 and not grid.get_cell(Vector2i(1,1)).is_opened
		and manager.actors.is_empty(), "safe multi-layer walls use base action cost and damage path")
	fixture()
	actor = manager.summon(Vector2i(1,0), {})
	manager.tick_all(0.5)
	grid.position = Vector2(130, 45)
	grid.scale = Vector2(1.5, 1.5)
	manager.reproject_all()
	var start_px: Vector2 = (Vector2(actor.flight_from) + Vector2(0.5,0.5)) * grid.cell_size
	var end_px: Vector2 = (Vector2(actor.target) + Vector2(0.5,0.5)) * grid.cell_size
	var expected: Vector2 = grid.to_global(start_px.lerp(end_px, actor.elapsed/actor.interval))
	check(actor.global_position.distance_to(expected) < 0.001,
		"moving explorer reprojects through grid position and scale")
	print("[EXPLORER] RESULT ", checks, " checks; failures=", failures)
	manager.remove_all()
	manager.queue_free()
	grid.queue_free()
	gs.game_active = false
	await process_frame
	await process_frame
	Input.set_custom_mouse_cursor(null)
	quit(0 if failures.is_empty() else 1)
