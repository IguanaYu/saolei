extends Node
## L5 Boss 关 M1 验收（安静 Boss 关）：FIND_ALL_MINES 目标通道 + 固定盘玩家自放基地 +
## 牙数三来源计数 + 阶段门槛 5/11 + 斩杀演出→胜利结算 + L4/L1 回归不受影响
## 用法：Godot_console.exe --path . --headless res://tmp/test_level5_m1.tscn

var fails: Array = []
var main: Node
var g: Grid


func _ready() -> void:
	Engine.time_scale = 30.0
	_run()


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

	print("== L5 起关：目标/固定盘/Boss 就位 ==")
	main._start_level("ch01_s05")
	await get_tree().process_frame
	var obj = GameState.current_objective
	check(obj != null and obj.type == ObjectiveData.Type.FIND_ALL_MINES, "目标类型 FIND_ALL_MINES")
	check(obj.target_value == 20, "牙数目标 20")
	check(g.mine_count == 20 and g.rows == 14 and g.cols == 14, "盘面 14x14/20 雷")
	check(GameState.game_phase == "placing_base", "玩家自放基地阶段（固定盘+无预置基地）")
	check(not GameState.game_active, "放基地前未激活")
	check(main.boss_manager.active, "BossManager 已就位")
	check(main.enemy_manager.waves_enabled == false, "L4 三虫波次在 L5 关闭")
	check(g.count_processed_mines() == 0, "开局牙数 0")
	var live_txt: String = main._update_objective_progress()
	check(live_txt.contains("拔牙 (0/20)"), "HUD 目标行「拔牙 (0/20)」(%s)" % live_txt)

	# 放基地：挑预开区内一格
	var base_coord: Vector2i = FixedBoards.L5.preopen[0]
	check(main._try_place_first_base_at(g.coord_to_world(base_coord)), "预开区放基地成功")
	check(GameState.game_active, "放完基地对局激活")
	check(GameState.get_nearest_base(base_coord) != null, "基地已注册")

	print("== 牙数三来源：正确旗/探测确认/踩塌 ==")
	var mines: Array = FixedBoards.L5.mines.duplicate()
	# 1) 正确旗（玩家）
	g.toggle_flag(mines[0], "player")
	check(g.count_processed_mines() == 1, "正确旗 = 拔 1 颗牙")
	# 撤旗不回退（rewarded_flags 首次口径）
	g.toggle_flag(mines[0], "player")
	check(not g.get_cell(mines[0]).is_flagged, "旗已撤")
	check(g.count_processed_mines() == 1, "撤旗后牙数不回退")
	g.toggle_flag(mines[0], "player")
	# 2) 探测确认雷（换一颗雷，3x3 中心取其邻格）
	var probe_center: Vector2i = mines[1] + Vector2i(1, 1)
	main._trigger_probe(probe_center)
	var confirmed: int = 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c = g.get_cell(probe_center + Vector2i(dx, dy))
			if c != null and c.is_confirmed_mine:
				confirmed += 1
	check(confirmed > 0, "探测确认到雷（%d 颗）" % confirmed)
	check(g.count_processed_mines() >= 2, "确认雷计入牙数（%d）" % g.count_processed_mines())
	# 3) 踩塌（坍塌格也计）
	var lives0: int = GameState.lives
	g.open_cell(mines[2], "player")
	check(g.get_cell(mines[2]).is_collapsed, "踩雷坍塌")
	check(GameState.lives == lives0 - 1, "踩雷 -1 命")
	check(g.count_processed_mines() >= 3, "坍塌计入牙数（%d）" % g.count_processed_mines())

	print("== 阶段门槛 5/11（牙数=血量驱动） ==")
	var teeth_now: int = g.count_processed_mines()
	var flag_idx := 3
	while teeth_now <= 5:
		var m: Vector2i = mines[flag_idx]
		flag_idx += 1
		if g.get_cell(m).is_confirmed_mine or g.get_cell(m).is_collapsed \
				or g.rewarded_flags.has(m):
			continue  # 已处理过的跳过
		g.toggle_flag(m, "player")
		teeth_now = g.count_processed_mines()
	check(teeth_now == 6, "拔到第 6 颗（当前 %d）" % teeth_now)
	check(main.boss_manager.phase == 2, "第 6 颗牙 → P2")
	while teeth_now <= 11:
		var m: Vector2i = mines[flag_idx]
		flag_idx += 1
		if g.get_cell(m).is_confirmed_mine or g.get_cell(m).is_collapsed \
				or g.rewarded_flags.has(m):
			continue
		g.toggle_flag(m, "player")
		teeth_now = g.count_processed_mines()
	check(teeth_now == 12, "拔到第 12 颗（当前 %d）" % teeth_now)
	check(main.boss_manager.phase == 3, "第 12 颗牙 → P3")

	print("== 斩杀：第 20 颗牙 → 掉落演出 → 胜利结算 ==")
	var win_fired := {"v": false}
	GameState.game_over.connect(func(result): win_fired["v"] = (result == "win"), CONNECT_ONE_SHOT)
	while teeth_now < 20:
		var m: Vector2i = mines[flag_idx]
		flag_idx += 1
		if g.get_cell(m).is_confirmed_mine or g.get_cell(m).is_collapsed \
				or g.rewarded_flags.has(m):
			continue
		g.toggle_flag(m, "player")
		teeth_now = g.count_processed_mines()
	check(teeth_now == 20, "全部 20 颗牙（当前 %d）" % teeth_now)
	check(not GameState.game_active, "斩杀瞬间全场冻结（game_active=false）")
	# 等掉落演出走完（time_scale=30 → 3s 演出约 6 帧后）
	for i in 40:
		await get_tree().process_frame
	check(win_fired["v"], "斩杀演出后 game_over(win)")
	check(main.results_panel.visible, "结算面板已出")

	print("== 回归：L4 波次恢复 / L1 目标行不受影响 ==")
	main._start_level("ch01_s04")
	await get_tree().process_frame
	check(main.enemy_manager.waves_enabled, "L4 波次开关恢复")
	check(not main.boss_manager.active, "L4 无 Boss")
	check(GameState.game_phase == "placing_base", "L4 随机盘放基地阶段")
	main._start_level("ch01_s01")
	await get_tree().process_frame
	var l1_txt: String = main._update_objective_progress()
	check(l1_txt.contains("清空安全格"), "L1 目标行不变（%s）" % l1_txt)
	check(main.boss_manager.active == false, "L1 无 Boss")

	print("")
	if fails.is_empty():
		print("=== ALL PASS ===")
	else:
		print("=== FAILED %d 项: %s ===" % [fails.size(), ", ".join(fails)])
	get_tree().quit(0 if fails.is_empty() else 1)
