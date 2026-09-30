extends Node
## L5 Boss 关 M2 验收（P1 史莱姆闭环）：调度出场/墙爬染黏液/接近才可点杀/
## 不可点拦截不耗 CD/击杀奖励+Boss硬直/补位/转场后停补
## 用法：Godot_console.exe --path . --headless res://tmp/test_level5_m2.tscn

var fails: Array = []
var main: Node
var g: Grid


func _ready() -> void:
	_run()


## 手动推进游戏时钟（headless 下 time_scale 加速不稳定，改直接泵 main._process）
func pump(seconds: int, main: Node) -> void:
	for i in seconds:
		main._process(1.0)
		await get_tree().process_frame


func check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  " + label)
	else:
		fails.append(label)
		print("  FAIL  " + label)


func _run() -> void:
	await get_tree().process_frame
	var ps: PackedScene = load("res://scenes/Main.tscn")
	main = ps.instantiate()
	get_parent().add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	g = main.grid

	print("== 起关 + 放基地 ==")
	main._start_level("ch01_s05")
	await get_tree().process_frame
	var base_coord: Vector2i = FixedBoards.L5.preopen[0]
	main._try_place_first_base_at(g.coord_to_world(base_coord))
	check(GameState.game_active, "对局激活")

	print("== P1 调度：t=15/+3s 双史莱姆出场 ==")
	await pump(20, main)
	await get_tree().create_timer(0.1).timeout
	var n_slimes: int = main.enemy_manager.count_alive_type("slime")
	check(n_slimes == 2, "两只史莱姆已出场（%d）" % n_slimes)
	await pump(9, main)   # 再走 9s 游戏时间，史莱姆至少各走 3 步
	var any_slimed := false
	for coord in g.cells:
		if g.cells[coord].is_slimed:
			any_slimed = true
			break
	check(any_slimed, "史莱姆沿途已染黏液")

	print("== 接近才可点杀（设计 §5.1） ==")
	# 手工放一只贴近预开区的史莱姆（frontier 墙格）
	var frontier_wall: Vector2i = Vector2i(-9, -9)
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c = g.get_cell(base_coord + o)
		if c != null and not c.is_opened:
			frontier_wall = base_coord + o
			break
	check(frontier_wall != Vector2i(-9, -9), "找到 frontier 墙格")
	var s_near: Enemy = main.enemy_manager.spawn_slime(frontier_wall, g)
	check(s_near.is_clickable(g), "贴开区史莱姆可点")
	# 远处墙格一只（右下角，远离预开区）
	var far_wall: Vector2i = Vector2i(13, 13)
	if g.get_cell(far_wall) != null and g.get_cell(far_wall).is_opened:
		far_wall = Vector2i(13, 12)
	var s_far: Enemy = main.enemy_manager.spawn_slime(far_wall, g)
	check(not s_far.is_clickable(g), "深处墙史莱姆不可点（隔墙点不死）")
	var acts0: int = GameState.result_stats["player_actions"]
	check(main._try_hit_enemy_at(g.coord_to_world(far_wall)), "点远处史莱姆：命中被拦截（不穿透）")
	check(s_far.is_alive(), "远处史莱姆未死")
	check(GameState.result_stats["player_actions"] == acts0, "拦截不耗 CD 次数")
	# 击杀近处：钱分 + 埋点 + Boss 硬直
	var money0: int = GameState.money
	var stagger_fired := {"v": false}
	main.boss_manager.boss_staggered.connect(func(_d): stagger_fired["v"] = true, CONNECT_ONE_SHOT)
	check(main._try_hit_enemy_at(g.coord_to_world(frontier_wall)), "点击近处史莱姆命中")
	check(not s_near.is_alive(), "近处史莱姆被点杀")
	check(GameState.money == money0 + 10, "击杀 +10 钱")
	check(GameState.result_stats["slime_kills"] == 1, "击杀埋点 slime_kills=1")
	check(stagger_fired["v"], "Boss 硬直信号已发")

	print("== 补位：杀到 <2 后 30s 补 ==")
	for e in main.enemy_manager.enemies.duplicate():
		main.enemy_manager.kill_enemy(e, "player")
	check(main.enemy_manager.count_alive_type("slime") == 0, "清空史莱姆")
	await pump(33, main)   # 游戏时间 ~33s > 30s 补位周期
	await get_tree().create_timer(0.1).timeout
	check(main.enemy_manager.count_alive_type("slime") >= 1, "30s 补位至场上（%d 只）"
			% main.enemy_manager.count_alive_type("slime"))

	print("== 转 P2 后不再补 ==")
	var mines: Array = FixedBoards.L5.mines.duplicate()
	var teeth := 0
	for m in mines:
		if teeth > 5:
			break
		var c = g.get_cell(m)
		if c == null or c.is_opened:
			continue
		g.toggle_flag(m, "robot_marker")
		teeth = g.count_processed_mines()
	check(main.boss_manager.phase == 2, "第 6 颗牙转 P2")
	for e in main.enemy_manager.enemies.duplicate():
		main.enemy_manager.kill_enemy(e, "player")
	await pump(36, main)   # 游戏时间 ~36s > 30s 补位周期
	check(main.enemy_manager.count_alive_type("slime") == 0, "P2 不再补史莱姆")

	print("")
	if fails.is_empty():
		print("=== ALL PASS ===")
	else:
		print("=== FAILED %d 项: %s ===" % [fails.size(), ", ".join(fails)])
	get_tree().quit(0 if fails.is_empty() else 1)
