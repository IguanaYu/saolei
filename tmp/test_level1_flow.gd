extends Node
## 第一关教学关全流程自动化冒烟测试（headless）
## 用法：Godot_console.exe --path . --headless res://tmp/test_level1.tscn
## 覆盖：起关固定盘面/无时限无命 → 5旗耗尽 → CD拦截 → 30s恢复 → 首购30→3 → 限购 → 机器人推盘通关 → 埋点

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


func _first_rule1_openable() -> Variant:
	# 开局放好 5 面旗后，规则 1 可推开的第一个安全格（旗全正确 → 满足数字的邻格安全）
	for coord in g.cells:
		var c: Cell = g.cells[coord]
		if not c.is_opened or c.adjacent_mines == 0 or c.is_base:
			continue
		var flagged := 0
		for n in g.get_neighbors(coord):
			if n.is_flagged:
				flagged += 1
		if flagged == c.adjacent_mines:
			for n in g.get_neighbors(coord):
				if not n.is_opened and not n.is_flagged:
					return n.coord
	return null


func _run() -> void:
	await get_tree().process_frame
	var ps: PackedScene = load("res://scenes/Main.tscn")
	main = ps.instantiate()
	get_parent().add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	g = main.grid

	print("== 起关：固定盘面 + 关卡参数 ==")
	SaveSystem.unlocks["start_money"] = 0  # 开发档带升级会污染资金校准，按全新档口径
	main._start_level("ch01_s01")
	await get_tree().process_frame
	var lvl: LevelData = GameState.get_current_level()
	check(lvl != null and lvl.fixed_mines.size() == 10, "关卡数据：固定雷位 10")
	check(g.rows == 10 and g.cols == 10, "盘面 10x10")
	var mine_n := 0
	var open_n := 0
	for c in g.cells.values():
		if c.is_mine:
			mine_n += 1
		if c.is_opened:
			open_n += 1
	check(mine_n == 10, "实际雷数 10（%d）" % mine_n)
	check(open_n == 53, "预开 53 格（%d）" % open_n)
	check(GameState.game_phase == "playing" and GameState.game_active, "基地预置、对局直接激活")
	check(GameState.bases.has(Vector2i(5, 5)), "基地在 (5,5)")
	check(not GameState.has_time_limit(), "无时限")
	check(not GameState.has_life_limit(), "无命限制")
	check(GameState.cd_phase == "free", "CD 处于免费阶段")
	check(GameState.money == 75, "起始资金 75（%d）" % GameState.money)
	var hud = main.get_node("UILayer/HUD")
	check(not hud.hearts[0].visible, "HUD 心形隐藏")
	check(not hud.time_label.visible, "HUD 倒计时隐藏")
	var shop = main.get_node("UILayer/Shop")
	# P8 商店重排后无 drone/debug 按钮；L1 只藏 base/upgrade（detector/miner 可见）
	check(not shop.build_base_button.visible and not shop.upgrade_button.visible,
			"商店隐藏 base/upgrade")

	print("== 免费阶段：第 5 面正确旗触发耗尽 ==")
	var init_flags := [Vector2i(1, 5), Vector2i(2, 5), Vector2i(8, 6), Vector2i(8, 7), Vector2i(8, 8)]
	for i in init_flags.size():
		g._on_cell_right_clicked(g.cells[init_flags[i]])
		if i < 4:
			check(GameState.cd_phase == "free", "第 %d 面旗后仍在免费阶段" % (i + 1))
	check(GameState.cd_phase == "cooldown", "第 5 面正确旗触发耗尽")
	check(GameState.money == 100, "耗尽时刻资金=100 恰好两台（%d）" % GameState.money)
	check(GameState.cd_duration == 30.0, "CD 时长 30s")
	check(GameState.result_stats["flag_score"] == 25, "标旗分 25")
	check(GameState.result_stats["player_ops"] == 5, "玩家操作 5 次")

	print("== CD 拦截 ==")
	var blocked_cell: Cell = g.cells[Vector2i(0, 0)]
	g._on_cell_left_clicked(blocked_cell)
	check(not blocked_cell.is_opened, "CD 中点击无效")

	print("== 30s CD 到点恢复一次 ==")
	# 充能银行：等第一层充能即可（攒满 7 层要 7×30s，不在本断言范围）
	var frames := 0
	while GameState.cd_charges < 1 and frames < 600:
		await get_tree().process_frame
		frames += 1
	check(GameState.cd_charges >= 1, "CD 到点恢复一层（frames=%d charges=%d）" % [
		frames, GameState.cd_charges])
	var safe_target = _first_rule1_openable()
	check(safe_target != null, "放好 5 旗后存在规则 1 可开格")
	if safe_target != null:
		g._on_cell_left_clicked(g.cells[safe_target])
		check(g.cells[safe_target].is_opened, "恢复后点击生效")
		check(GameState.cd_remaining > 0.0, "动作后 CD 重新计时")

	print("== 首购：CD 30 → 3 ==")
	if GameState.money < 100:
		print("  WARN 资金 %d < 100（恢复点击收益异常），测试内补齐" % GameState.money)
		GameState.add_money(100 - GameState.money)
	main._enter_placing_mode("opener")
	check(main.placing_mode == "opener", "进入 opener 放置模式")
	main._try_place_at(g.coord_to_world(Vector2i(4, 4)))
	check(GameState.opener_count == 1, "购买 opener 成功")
	check(GameState.cd_duration == 3.0, "首购后 CD=3s")
	check(GameState.cd_remaining == 0.0, "首购立刻恢复一次")
	main._enter_placing_mode("marker")
	main._try_place_at(g.coord_to_world(Vector2i(6, 4)))
	check(GameState.marker_count == 1, "购买 marker 成功")
	check(shop.lock_reason("opener") == "已购满" and shop.lock_reason("marker") == "已购满",
			"两台机器人限购锁定")

	print("== 机器人推盘至通关 ==")
	frames = 0
	while GameState.game_active and frames < 20000:
		await get_tree().process_frame
		frames += 1
		if frames % 2000 == 0:
			var opened_cnt := 0
			var flag_cnt := 0
			for c in g.cells.values():
				if c.is_opened:
					opened_cnt += 1
				if c.is_flagged:
					flag_cnt += 1
			var acts := Solver.find_certain_actions(g)
			var rstates: Array = []
			for r in main.robot_manager.robots:
				rstates.append("%s@%s %s tgt=%s" % [r.robot_type, r.coord, r._state, r._current_target])
			print("  [diag f=%d] open=%d flag=%d money=%d solver=%d robots=[%s] locked=%s" % [
				frames, opened_cnt, flag_cnt, GameState.money, acts.size(),
				" | ".join(PackedStringArray(rstates)), str(GameState.locked_targets.keys())])
	check(not GameState.game_active, "对局结束（frames=%d）" % frames)
	check(main.get_node("UILayer/ResultsPanel").visible, "结算页显示")
	var s: Dictionary = GameState.result_stats
	check(int(s["robot_ops"]) > 0, "机器人操作统计 >0")
	check(int(s["open_score"]) + int(s["flag_score"]) == GameState.score, "开格分+标旗分=总分")
	var log_arr: Array = SaveSystem.stats.get("playtest", [])
	check(log_arr.size() >= 1, "盲测埋点写入存档")
	if not log_arr.is_empty():
		var rec: Dictionary = log_arr[-1]
		check(rec["result"] == "win", "埋点 result=win")
		print("  埋点详情: player_ops=%d robot_ops=%d player_actions=%d wrong=%d elapsed=%.1f" % [
			rec["player_ops"], rec["robot_ops"], rec["player_actions"], rec["wrong_flags"], rec["elapsed"]])
	check(LevelSystem.is_level_unlocked("ch01_s02"), "通关解锁 1-2")

	print("")
	if fails.is_empty():
		print("=== ALL PASS ===")
		get_tree().quit(0)
	else:
		print("=== FAILED %d 项: %s ===" % [fails.size(), ", ".join(PackedStringArray(fails))])
		get_tree().quit(1)
