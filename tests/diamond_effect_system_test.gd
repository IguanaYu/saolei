extends SceneTree
## Isolated end-to-end tests. Run with the project copied to an isolated user-data directory.
var main
var g
var lm
var dm
var em
var gs
var failures: Array = []
var checks := 0

func _initialize() -> void:
	root.get_node("GameState").boot_splash_played = true
	change_scene_to_file("res://scenes/Main.tscn")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print("[DIAMOND] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		failures.append(label)

func fixture(defs: Array, mines: Array = [Vector2i(2,3), Vector2i(3,3), Vector2i(3,2), Vector2i(5,5)]):
	var lvl := LevelData.new()
	lvl.id = "diamond_validation"
	lvl.chapter_id = "ch02"
	lvl.display_name = "验证盘"
	lvl.grid_size = Vector2i(7,7)
	lvl.fixed_mines.assign(mines)
	lvl.mine_count = mines.size()
	lvl.fixed_base = Vector2i(0,3)
	lvl.preopen_coords.assign([Vector2i(0,3),Vector2i(1,3)])
	lvl.laser_mode = true
	lvl.meta_progression = false
	lvl.start_gold = 100
	lvl.start_lives = 0
	lvl.time_limit_sec = 0
	lvl.time_bonus_per_sec = 0
	lvl.diamond_effect_seed = 42
	lvl.diamond_effects.assign(defs)
	var obj := ObjectiveData.new()
	obj.type = ObjectiveData.Type.REACH_SCORE
	obj.target_value = 99999
	lvl.objectives = [obj]
	main._start_level_with(lvl, "")
	main.splash.hide()
	main.tutorial_guide.hide()
	return lvl

func d(c: Vector2i, id: String, p: Dictionary = {}) -> Dictionary:
	return {"coord": c, "effect_id": id, "params": p}

func flag(c: Vector2i) -> void:
	g.toggle_flag(c, "player")

func fire(c: Vector2i) -> void:
	main._on_laser_fire_requested(c)

func click(c: Vector2i, button: int) -> void:
	var cell = g.get_cell(c)
	var pos: Vector2 = root.get_final_transform() * cell.global_position
	var move := InputEventMouseMotion.new()
	move.position = pos
	move.global_position = pos
	Input.parse_input_event(move)
	await physics_frame
	await process_frame
	var event := InputEventMouseButton.new()
	event.position = pos
	event.global_position = pos
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await physics_frame
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await physics_frame
	await process_frame

func run() -> void:
	await process_frame
	await process_frame
	main = root.get_node("Main")
	g = main.grid
	lm = main.laser_manager
	dm = main.diamond_effect_manager
	em = main.diamond_explorer_manager
	gs = root.get_node("GameState")
	print("[DIAMOND] isolated data: ", OS.get_user_data_dir())
	await test_gold()
	await test_chains()
	await test_random()
	await test_explorer()
	test_validation()
	await test_compatibility()
	print("[DIAMOND] RESULT ", checks, " checks; failures=", failures)
	gs.game_active = false
	main.queue_free()
	await process_frame
	await process_frame
	Input.set_custom_mouse_cursor(null)
	quit(0 if failures.is_empty() else 1)

func test_gold() -> void:
	var at := Vector2i(2,3)
	var lvl = fixture([d(at,"gold",{"gold_amount":17})])
	check(dm.public_info(at).is_empty(), "hidden effects reveal no public info")
	var number: int = g.get_cell(Vector2i(1,3)).adjacent_mines
	flag(at)
	var score: int = gs.score
	var money: int = gs.money
	fire(at)
	check(gs.money == money+17 and gs.score == score, "gold grants only configured coins, no score")
	check(gs.money_breakdown.get("diamond_effect_gold",0)==17, "gold has independent ledger")
	check(g.get_cell(at).is_mine and g.get_cell(at).is_flagged and not g.get_cell(at).is_opened, "consumed diamond retains mine and flag")
	check(g.get_cell(Vector2i(1,3)).adjacent_mines==number, "mine numbers remain unchanged")
	fire(at)
	flag(at)
	flag(at)
	fire(at)
	check(gs.money==money+17, "repeat shots and reflag cannot farm coins")
	check(gs.player_actions_used==3, "effects add no player action cost")
	main._start_level_with(lvl, "")
	check(gs.money==100 and dm.public_info(at).is_empty(), "restart resets state and balances")
	flag(at)
	fire(at)
	check(gs.money_breakdown.get("diamond_effect_gold",0)==17, "restart restores effect availability")
	# Wrong flag and unflagged effect diamond follow ordinary laser rules.
	fixture([d(at,"gold",{"gold_amount":17})])
	flag(Vector2i(1,2))
	fire(at)
	check(g.get_cell(at).is_collapsed and gs.money_breakdown.get("diamond_effect_gold",0)==0, "unflagged diamond shatters without effect")
	check(dm.public_info(Vector2i(1,2)).is_empty(), "wrong flag has no effect ability or identity")
	# Actual mouse dispatch, not a direct handler call.
	fixture([d(at,"gold",{"gold_amount":17})])
	await process_frame
	await click(at,MOUSE_BUTTON_RIGHT)
	check(g.get_cell(at).is_flagged, "real right-click flags diamond")
	await click(at,MOUSE_BUTTON_LEFT)
	check(gs.money_breakdown.get("diamond_effect_gold",0)==17, "real left-click laser activates flagged diamond")

func test_chains() -> void:
	var a := Vector2i(2,3)
	var b := Vector2i(3,3)
	var gold := Vector2i(3,2)
	fixture([d(a,"area_3x3"),d(b,"area_3x3"),d(gold,"gold",{"gold_amount":11})])
	for c in [a,b,gold]: flag(c)
	var wall = g.get_cell(Vector2i(2,2))
	wall.wall_hp = 3
	fire(a)
	check(wall.wall_hp==2, "overlapping 3x3 peels a wall only once per shot")
	check(gs.money_breakdown.get("diamond_effect_gold",0)==11, "area chain activates gold")
	check(g.get_cell(a).diamond_effect_consumed and g.get_cell(b).diamond_effect_consumed, "mutual area cycle consumes each diamond once")
	check(gs.result_stats.get("diamond_effects_triggered",0)==3, "mixed chain has three activations")
	fixture([d(Vector2i(0,0),"area_3x3")],[Vector2i(0,0),Vector2i(5,5)])
	flag(Vector2i(0,0))
	fire(Vector2i(0,0))
	check(g.get_cell(Vector2i(0,0)).diamond_effect_consumed, "corner area clips to existing cells")
	# A synchronous clear-all win must not bypass later effect commits.
	var lvl = fixture([d(a,"area_3x3"),d(gold,"gold",{"gold_amount":13})])
	flag(a)
	flag(gold)
	gs.current_objective.type = ObjectiveData.Type.CLEAR_ALL_SAFE
	for c in g.cells.values():
		if not c.is_mine and c.coord != Vector2i(2,2):
			c.is_opened = true
	gs.current_objective.target_value=0
	fire(a)
	check(gs.money_breakdown.get("diamond_effect_gold",0)==13, "complete effect ledger commits before synchronous win")
	await process_frame
	check(not gs.game_active, "win is evaluated after full shot")
	if main.victory_tally.is_active():
		main.victory_tally._skip()
	await process_frame

func test_random() -> void:
	var at := Vector2i(2,3)
	var lvl = fixture([d(at,"split_two",{"ray_range":3})])
	flag(at)
	var observed: Array = []
	dm.effect_released.connect(func(event): observed.append(event.duplicate(true)))
	for i in 25: lm.compute_shot_geometry(Vector2i(0,3),at,false)
	fire(at)
	var first: Array = observed.duplicate(true)
	check(first.size()==1 and first[0].rays.size()==2, "split produces exactly two saved rays")
	if not first.is_empty():
		check(first[0].rays[0].to != first[0].rays[1].to, "split directions are distinct")
	main._start_level_with(lvl, "")
	flag(at)
	observed.clear()
	fire(at)
	check(observed==first, "fixed seed and hover count preserve actual random result")
	var dirs: Dictionary = {}
	for seed_value in 24:
		lvl.diamond_effect_seed=seed_value
		main._start_level_with(lvl, "")
		flag(at)
		observed.clear()
		fire(at)
		if not observed.is_empty():
			for ray in observed[0].rays: dirs[LaserGeometry.octant_dir(ray.from,ray.to)]=true
	check(dirs.size()==8, "random samples cover eight candidate directions")

func test_explorer() -> void:
	var at := Vector2i(2,3)
	fixture([d(at,"explorer",{"actions":3,"interval":1.5,"lifetime":20})])
	flag(at)
	fire(at)
	check(em.actors.size()==1 and g.get_cell(at).is_flagged, "explorer summons above intact flagged diamond")
	var count: int = main.robot_manager.robots.size()
	var money: int = gs.money
	em.tick_all(1.6)
	check(gs.result_stats.get("diamond_explorer_actions",0)>0, "explorer opens public-information safe target")
	check(main.robot_manager.robots.size()==count and gs.money_breakdown.get("diamond_explorer",0)>0, "explorer rewards separate from robot economy")
	var actions: int = gs.result_stats.get("diamond_explorer_actions",0)
	paused=true
	em.tick_all(3.0)
	check(gs.result_stats.get("diamond_explorer_actions",0)==actions, "pause freezes explorer actions")
	paused=false
	em.summon(at,{"actions":3,"interval":1.5,"lifetime":20})
	em.tick_all(0.1)
	check(em.get_reserved_targets().size() <= em.actors.size(), "explorers share unique target reservations")
	main._start_level_with(fixture([]), "")
	check(em.actors.is_empty() and gs.result_stats.get("diamond_explorer_actions",0)==0, "restart clears explorers, locks and statistics")
	# Identical public input, different hidden mine layout: same target.
	fixture([], [Vector2i(2,3),Vector2i(5,5)])
	flag(at)
	em.summon(at,{})
	em.tick_all(0.01)
	var targets_a: Array = em.get_reserved_targets()
	em.reset_for_level()
	g.get_cell(Vector2i(5,5)).is_mine=false
	g.get_cell(Vector2i(6,5)).is_mine=true
	em.summon(at,{})
	em.tick_all(0.01)
	check(em.get_reserved_targets()==targets_a, "hidden mine changes do not influence explorer selection")
	em.reset_for_level()
	# No public number evidence: wait and expire without guessing.
	for c in g.cells.values(): c.is_opened=false
	em.summon(at,{"lifetime":2.0})
	em.tick_all(1.6)
	check(gs.result_stats.get("diamond_explorer_actions",0)==0, "no certain target never guesses")
	em.tick_all(2.0)
	check(em.actors.is_empty(), "idle explorer expires and releases locks")

func test_validation() -> void:
	var lvl = fixture([])
	# Load the subclass after autoloads exist; a top-level extends eagerly compiles GameState users.
	var probe_script := GDScript.new()
	probe_script.source_code = "extends \"res://scripts/diamond/diamond_effect_manager.gd\"\nfunc _report(message: String) -> void:\n\tvalidation_errors.append(message)\n"
	check(probe_script.reload() == OK, "invalid-input diagnostic probe loads after autoloads")
	var probe = probe_script.new()
	main.get_node("BoardRoot").add_child(probe)
	for entry in [d(Vector2i(99,99),"gold"), d(Vector2i(1,2),"gold"),
		d(Vector2i(2,3),"unknown"), d(Vector2i(2,3),"gold",{"gold_amount":-1}),
		d(Vector2i(2,3),"split_two",{"ray_range":0}),
		d(Vector2i(2,3),"explorer",{"interval":-1}),
		d(Vector2i(2,3),"explorer",{"actions":1.5}),
		d(Vector2i(2,3),"gold",{"typo_amount":5})]:
		lvl.diamond_effects.assign([entry])
		probe.setup_for_level(lvl,g)
		check(not probe.validation_errors.is_empty() and probe.definitions.is_empty(),
			"invalid definition reports instead of substituting "+str(entry))
	probe.reset_for_level()
	probe.queue_free()

func test_compatibility() -> void:
	fixture([])
	fire(Vector2i(2,3))
	check(g.get_cell(Vector2i(2,3)).is_collapsed, "empty configuration preserves old shatter semantics")
	for id in ["ch01_s01","ch02_s01","ch02_s02","ch02_s03","ch02_s04","ch02_s05","ch03_s01","ch04_s01"]:
		main._start_level(id)
		await process_frame
		check(gs.game_active or gs.game_phase=="placing_base", "enter "+id)
		em.summon(Vector2i(0,0),{})
		main._start_level(id)
		check(em.actors.is_empty(), "restart clears temporary units "+id)
		if not id.begins_with("ch02"):
			check(dm.public_info(Vector2i(0,0)).is_empty(), "other chapter has no diamond effects "+id)
			check(dm.definitions.is_empty(), "other chapter configuration stays disabled "+id)
		else:
			check(dm.validation_errors.is_empty() and not dm.definitions.is_empty(), "explicit chapter two coordinates validate "+id)
		main._abandon_settle()
		check(em.actors.is_empty(), "exit clears temporary units "+id)
