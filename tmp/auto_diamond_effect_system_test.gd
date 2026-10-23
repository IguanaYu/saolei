extends SceneTree
## 隔离存档的工程盘：Godot --headless --path . -s res://tmp/auto_diamond_effect_system_test.gd
## 实测空间/奖励/一次性/旧设施/独立随机与预览；不改用户存档或正式关卡。

var checks := 0
var failures: Array[String] = []
var board: Node2D
var g: Node
var lm: Node
var dm: Node
var fm: Node
var rm: Node
var explorers: Node
var em: Node
var gs: Node
var events: Array = []
var last_result: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	print("[Diamond] %s %02d %s" % ["PASS" if ok else "FAIL", checks, label])
	if not ok:
		failures.append(label)


func fixture(defs: Array, seed_value := 42) -> LevelData:
	if is_instance_valid(board):
		board.free()
	var level := LevelData.new()
	level.meta_progression = false
	level.start_gold = 0
	level.laser_mode = true
	level.diamond_effect_seed = seed_value
	level.diamond_effects.assign(defs)
	gs.reset_state("diamond_core_test", level)
	gs.game_active = true
	gs.bases.clear()
	gs.bases.append(Vector2i(0, 4))
	board = Node2D.new()
	board.name = "DiamondTestBoard"
	root.add_child(board)
	g = load("res://scripts/grid.gd").new()
	g.rows = 9
	g.cols = 9
	g.name = "Grid"
	g.laser_mode = true
	board.add_child(g)
	# 非零公开数字避免本测试不相关的洪水吞掉整个盘；矿位数字保留测试另行赋值。
	for cell in g.cells.values():
		cell.adjacent_mines = 1
	for definition in defs:
		g.get_cell(definition.coord).is_mine = true
		g.get_cell(definition.coord).is_flagged = true
	fm = load("res://scripts/facilities/facility_manager.gd").new()
	fm.name = "FacilityManager"
	board.add_child(fm)
	rm = load("res://scripts/robot_manager.gd").new()
	rm.name = "RobotManager"
	board.add_child(rm)
	em = load("res://scripts/enemies/enemy_manager.gd").new()
	em.name = "EnemyManager"
	board.add_child(em)
	explorers = load("res://scripts/diamond/explorer_manager.gd").new()
	explorers.name = "DiamondExplorerManager"
	board.add_child(explorers)
	explorers.setup(g)
	lm = load("res://scripts/laser/laser_manager.gd").new()
	lm.name = "LaserManager"
	board.add_child(lm)
	lm.setup(g, em)
	dm = load("res://scripts/diamond/diamond_effect_manager.gd").new()
	dm.name = "DiamondEffectManager"
	board.add_child(dm)
	dm.setup_for_level(level, g)
	events.clear()
	dm.effect_released.connect(func(event: Dictionary): events.append(event))
	return level


func definition(c: Vector2i, id: String, params := {}) -> Dictionary:
	return {"coord": c, "effect_id": id, "params": params}


func fire(target := Vector2i(8, 4)) -> void:
	lm.fire(Vector2i(0, 4), target)


func robot_at(c: Vector2i, type: String):
	var scene_path: String = {"opener": "res://scenes/Robot.tscn", "overload": "res://scenes/OverloadRobot.tscn",
		"refractor_wide": "res://scenes/RefractorRobot.tscn"}[type]
	var robot = load(scene_path).instantiate()
	robot.robot_type = type
	# dummy renderer 不支持旧描边 shader 的 texture 内建；机制盘只省去阵营装饰。
	var marker := Node2D.new()
	marker.name = "FactionMarker"
	robot.add_child(marker)
	rm.add_child(robot)
	robot.set_initial_position(c, g)
	rm.robots.append(robot)
	return robot


func _run() -> void:
	gs = root.get_node("GameState")
	# 先清理自动加载的循环BGM/音效池，机制测试静音并避免Dummy音频退出时的Ogg残留。
	root.get_node("AudioManager")._exit_tree()
	# --script 的入口脚本不预加载游戏类，等自动加载单例完成后检查依赖能否实例化。
	for path in ["res://scripts/effects_layer.gd", "res://scripts/grid.gd",
			"res://scripts/laser/laser_manager.gd", "res://scripts/diamond/diamond_effect_manager.gd"]:
		var script = load(path)
		if script == null or not script.can_instantiate():
			print("[Diamond] COMPILE FAILED: ", path)
			quit(2)
			return
	_gold_and_reset()
	_area_and_mixed_chain()
	_random_and_preview()
	_old_facilities()
	_source_and_flags()
	_disabled()
	board.free()
	await process_frame
	await process_frame
	print("[Diamond] RESULT checks=%d failures=%d %s" % [checks, failures.size(), str(failures)])
	quit(0 if failures.is_empty() else 1)


func _gold_and_reset() -> void:
	var c := Vector2i(3, 4)
	var level := fixture([definition(c, "gold", {"gold_amount": 17})])
	var score_before: int = gs.score
	var neighbors_before: int = g.get_cell(Vector2i(3, 3)).adjacent_mines
	fire()
	check(gs.money == 17 and gs.money_breakdown.get("diamond_effect_gold", 0) == 17,
		"正确旗被主束激活，17金币独立入账")
	check(gs.score == score_before, "金币效果不增加目标分")
	check(g.get_cell(c).is_mine and g.get_cell(c).is_flagged and not g.get_cell(c).is_opened,
		"释放后保留雷位、旗和未开状态")
	check(g.get_cell(Vector2i(3, 3)).adjacent_mines == neighbors_before, "释放不改变相邻数字")
	fire()
	g.toggle_flag(c, "player")
	g.toggle_flag(c, "player")
	fire()
	check(gs.money == 17 and events.size() == 1, "重复射击和撤旗重插不刷新一次性效果")
	check(not lm.resolving_shot and dm.states[c] == "consumed", "整枪结束提交消耗并释放胜负锁")
	dm.setup_for_level(level, g)
	fire()
	check(gs.money == 34 and events.size() == 2, "重建本局状态可重新激活，资源未写入消耗")
	check(not level.diamond_effects[0].has("consumed"), "静态关卡资源保持只读")
	fixture([definition(Vector2i(2, 4), "gold", {"gold_amount": 7}),
		definition(Vector2i(5, 4), "gold", {"gold_amount": 17})])
	fire()
	check(gs.money == 24 and events.size() == 2, "同枪多颗金币独立发放，各金额正确合计")


func _area_and_mixed_chain() -> void:
	fixture([definition(Vector2i(3, 4), "area_3x3"),
		definition(Vector2i(4, 4), "area_3x3"),
		definition(Vector2i(4, 5), "gold", {"gold_amount": 13}),
		definition(Vector2i(3, 5), "explorer", {"actions": 2}),
		definition(Vector2i(2, 3), "gold", {"gold_amount": 99})])
	g.get_cell(Vector2i(2, 3)).is_flagged = false
	g.get_cell(Vector2i(2, 5)).is_flagged = true  # 错旗没有效果。
	var wall = g.get_cell(Vector2i(4, 3))
	wall.wall_hp = 3
	var cover = g.get_cell(Vector2i(3, 3))
	cover.is_opened = true
	cover.cover_wall_hp = 3
	g.get_cell(Vector2i(5, 4)).is_opened = true
	var robot = robot_at(Vector2i(5, 4), "opener")
	var builder = load("res://scenes/Builder.tscn").instantiate()
	var faction := Node2D.new()
	faction.name = "FactionMarker"
	builder.add_child(faction)
	em.add_child(builder)
	builder.coord = cover.coord
	em.builders.append(builder)
	fire()
	check(events.size() == 4 and gs.money == 13, "两颗范围回环收敛，金币和召唤各执行一次")
	check(wall.wall_hp == 2 and not wall.is_opened, "重叠范围对多层墙整枪只削一层")
	check(cover.cover_wall_hp == 2 and robot.beam_energy == 60.0, "重叠范围覆盖墙只削一层、机器人只充能一次")
	check(builder.hp == 1, "重叠范围和原束对同一筑墙工整枪只造成一次伤害")
	check(g.get_cell(Vector2i(2, 3)).is_collapsed and dm.states[Vector2i(2, 3)] == "ready",
		"范围命中未标钻石沿碎钻规则，不免费激活")
	check(g.get_cell(Vector2i(2, 5)).is_flagged and not g.get_cell(Vector2i(2, 5)).is_opened,
		"普通错旗继续保护，不获得能力")
	check(explorers.actors.size() == 1 and explorers.actors[0].actions_left == 2,
		"精灵独立召唤并透传作业次数，不进入机器人数组")
	check(rm.robots.size() == 1, "精灵不计入机器人数量")
	fixture([definition(Vector2i(0, 0), "area_3x3")])
	var geo: Dictionary = lm.compute_shot_geometry(Vector2i(0, 4), Vector2i(0, 0))
	geo = dm.prepare_shot(geo, lm)
	check(geo.diamond_context.events[0].cells.size() == 4, "角落3×3仅保留实际存在四格")


func _random_and_preview() -> void:
	var def := definition(Vector2i(4, 4), "split_two", {"ray_range": 3})
	fixture([def], 772)
	var rng_before: int = dm.effect_rng.state
	var geo: Dictionary = lm.compute_shot_geometry(Vector2i(0, 4), Vector2i(8, 4), false)
	for i in 30:
		dm.preview_shot(geo)
	check(dm.effect_rng.state == rng_before, "反复悬停不推进实际随机流")
	fire()
	var first: Array = events[0].rays.duplicate(true)
	check(first.size() == 2 and first[0].direction != first[1].direction, "双射线实抽两个互异八向")
	var valid := true
	for ray in first:
		for c in ray.cells:
			valid = valid and g.cells.has(c)
	check(valid, "随机射线裁掉盘外/洞区，表现与逻辑共用实际格集")
	fixture([def], 772)
	fire()
	check(events[0].rays == first, "固定局面与种子复现实际方向和命中")
	var covered: Dictionary = {}
	for seed_value in 30:
		fixture([def], seed_value)
		fire()
		for ray in events[0].rays:
			covered[ray.direction] = true
	check(covered.size() == 8, "多个固定种子的抽样可覆盖八个候选方向")
	fixture([definition(Vector2i(2, 4), "split_two", {"directions": [Vector2i(1, 0), Vector2i(0, -1)]}),
		definition(Vector2i(2, 2), "area_3x3"), definition(Vector2i(3, 2), "gold")])
	fire()
	check(events.size() == 3 and gs.money == 10, "双射线→范围→金币混合接力")


func _old_facilities() -> void:
	# 原主束与两条新射线都覆盖同一2×2矿石；仍只爆发一轮。
	fixture([definition(Vector2i(1, 4), "split_two", {"ray_range": 7,
		"directions": [Vector2i(1, 0), Vector2i(1, -1)]})])
	fm.setup_ores(g, [{"origin": Vector2i(4, 3)}])
	fire()
	check(gs.result_stats.ore_bursts == 1, "主束/新双射线共享矿石触发账本，整枪至多一次")
	fire()
	check(gs.result_stats.ore_bursts == 2, "下一枪矿石仍按旧规则重新释放，没有跨枪去重")
	fixture([definition(Vector2i(3, 4), "area_3x3")])
	fm.setup_chain_nodes(g, [Vector2i(3, 3)])
	fm.setup_ores(g, [{"origin": Vector2i(4, 2)}])
	fire()
	check(not fm.chain_nodes[0].consumed and gs.result_stats.ore_bursts == 0,
		"新3×3范围不新增旧节点/旧矿石级联")
	fixture([definition(Vector2i(2, 4), "split_two", {"ray_range": 7,
		"directions": [Vector2i(1, 0), Vector2i(1, -1)]})])
	fm.setup_chain_nodes(g, [Vector2i(4, 4), Vector2i(5, 4)])
	fire()
	check(gs.result_stats.get("shots_fired", 0) == 1 and fm.chain_nodes[0].consumed and fm.chain_nodes[1].consumed,
		"新射线沿用旧节点BFS，但不重复整枪动作")
	fixture([definition(Vector2i(2, 4), "split_two", {"ray_range": 7,
		"directions": [Vector2i(1, 0), Vector2i(1, -1)]})])
	g.get_cell(Vector2i(4, 4)).is_opened = true
	robot_at(Vector2i(4, 4), "overload")
	fire()
	check(gs.result_stats.overload_blasts == 1, "主束与新射线共享过载触发账本，整枪至多一次")
	fire()
	check(gs.result_stats.overload_blasts == 2, "下一枪过载存活并可再次释放")
	fixture([definition(Vector2i(2, 4), "split_two", {"ray_range": 7,
		"directions": [Vector2i(1, 0), Vector2i(0, -1)]}),
		definition(Vector2i(5, 3), "gold", {"gold_amount": 11})])
	g.get_cell(Vector2i(3, 4)).is_opened = true
	robot_at(Vector2i(3, 4), "refractor_wide")
	fm.setup_pillar(g, Vector2i(8, 4))
	var refracted: Array = []
	lm.refractor_activated.connect(func(r): refracted.append(r))
	fire()
	check(gs.money == 11, "折光副束可激活正确标记钻石")
	check(refracted.size() == 1, "原主束/新射线命中同一折光仅释放一次")
	check(fm.pillar.hp == 5 and gs.result_stats.pillar_hits == 1,
		"原束/新束/折光多源覆盖引光柱整枪只扣一耐久")


func _source_and_flags() -> void:
	fixture([definition(Vector2i(4, 3), "gold", {"gold_amount": 23})])
	g.get_cell(Vector2i(4, 4)).is_opened = true
	robot_at(Vector2i(4, 4), "overload")
	fire()
	check(gs.money == 0 and dm.states[Vector2i(4, 3)] == "ready",
		"旧过载爆炸波及正确钻石旗不触发新效果（D10）")
	fixture([definition(Vector2i(3, 4), "gold", {"gold_amount": 19})])
	g.get_cell(Vector2i(3, 4)).is_flagged = false
	var geo: Dictionary = lm.compute_shot_geometry(Vector2i(0, 4), Vector2i(8, 4))
	geo = dm.prepare_shot(geo, lm)
	g.get_cell(Vector2i(3, 4)).is_flagged = true
	dm.commit_shot(geo)
	check(gs.money == 0, "射击开始未标者，中途变为旗也不追认资格")
	check(dm.public_info(Vector2i(3, 4)).effect_id == "gold", "正确旗公开效果类型")
	g.get_cell(Vector2i(3, 4)).is_flagged = false
	check(dm.public_info(Vector2i(3, 4)).is_empty(), "未标格不公开效果类型")


func _disabled() -> void:
	fixture([])
	var before: int = gs.money
	fire()
	check(not dm.is_enabled() and events.is_empty() and gs.money == before,
		"空配置只走原激光，无新增奖励/召唤")
