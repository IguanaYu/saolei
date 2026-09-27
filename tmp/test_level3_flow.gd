extends Node
## 第三关（局外成长关·积分目标）全流程自动化冒烟测试（headless）
## 用法：Godot_console.exe --path . --headless res://tmp/test_level3.tscn
## 覆盖：固定盘/预开算分/进度条 → 局外消费进场即见（速度双轨+送机器人）→ 4 轨升级 →
##       同格防重复 → 过线结算（时间加分）→ 继续挑战（冻结/免命/累加不二次win）→ 离开补埋点

var fails: Array = []
var main: Node
var g: Grid
var _saved_unlocks: Dictionary = {}
var _saved_ore: int = 0


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

	# 备份局外档，测试内改内存值（不落盘恢复）
	_saved_unlocks = SaveSystem.unlocks.duplicate()
	_saved_ore = SaveSystem.ore

	print("== 起关：固定盘 + 预开算分 + 关卡参数 ==")
	for k in ["start_money", "start_lives", "global_speed", "work_speed", "start_robot"]:
		SaveSystem.unlocks[k] = 0
	main._start_level("ch01_s01")  # 先过 L1 保证解锁链（mark_level_entered）
	main._start_level("ch01_s02")
	main._start_level("ch01_s03")
	await get_tree().process_frame
	var lvl: LevelData = GameState.get_current_level()
	check(lvl != null and lvl.fixed_mines.size() == 40, "关卡数据：固定雷位 40（%d）" % (lvl.fixed_mines.size() if lvl else -1))
	check(g.rows == 16 and g.cols == 16, "盘面 16x16")
	var open_n := 0
	for c in g.cells.values():
		if c.is_opened:
			open_n += 1
	check(open_n == 101, "预开 101 格（%d）" % open_n)
	check(GameState.score == 101, "预开算分：起始分 101（%d）" % GameState.score)
	check(GameState.money == 300, "起始资金 300（不含预开金币 %d）" % GameState.money)
	check(GameState.time_limit_cfg == 120.0, "时限 120s")
	check(GameState.lives == 3, "起始 3 命")
	check(GameState.bases.has(Vector2i(3, 5)), "基地在 (3,5)")
	check(GameState.cd_phase == "free" and GameState.cd_free_clicks_left == 5, "5 次免 CD")
	check(lvl != null and lvl.allow_continue and lvl.preopen_scores and lvl.meta_progression,
			"allow_continue/preopen_scores/meta_progression 开启")
	var hud = main.get_node("UILayer/HUD")
	check(hud.objective_progress_bar.visible, "积分进度条可见")
	check(absf(hud.objective_progress_bar.value - 101.0) < 0.01
			and absf(hud.objective_progress_bar.max_value - 300.0) < 0.01,
			"进度条 101/300")
	check(SaveSystem.has_entered_level("ch01_s03"), "进关记录（间场高亮依据）")

	print("== 升级面板：4 轨动态生成 ==")
	var upanel = main.get_node("UILayer/UpgradePanel")
	upanel._rebuild_rows_if_needed()
	var rows: Array = []
	for r in upanel.rows_box.get_children():
		rows.append(r.name)
	check(rows.has("OpenerMoveRow") and rows.has("OpenerWorkRow")
			and rows.has("MarkerMoveRow") and rows.has("MarkerWorkRow"),
			"4 轨行存在: %s" % str(rows))
	check(not rows.has("DiscountRow"), "折扣轨隐藏")

	print("== 4 轨升级：工作轨独立生效 ==")
	check(absf(GameState.get_move_interval("opener") - 2.0) < 0.001
			and absf(GameState.get_work_interval("opener") - 2.0) < 0.001, "基值双轨均 2.0s")
	GameState.add_money(200)
	check(GameState.purchase_upgrade("opener_work"), "购买 opener_work Lv1")
	check(GameState.opener_work_level == 1 and GameState.opener_move_level == 0, "只升工作轨")
	check(absf(GameState.get_work_interval("opener") - 1.6) < 0.001, "工作间隔 2.0→1.6")
	check(absf(GameState.get_move_interval("opener") - 2.0) < 0.001, "移动间隔不变 2.0")

	print("== 同格防重复（撤旗再插不重发） ==")
	var flag_score0: int = int(GameState.result_stats["flag_score"])
	var score0: int = GameState.score
	var mine_coord: Vector2i = lvl.fixed_mines[0]
	g.toggle_flag(mine_coord, "player")
	var after_flag: int = GameState.score
	check(after_flag - score0 == 5, "正确旗 +5")
	g.toggle_flag(mine_coord, "player")  # 撤
	g.toggle_flag(mine_coord, "player")  # 再插
	check(GameState.score == after_flag, "撤旗再插分数不变（%d）" % GameState.score)
	check(int(GameState.result_stats["flag_score"]) == flag_score0 + 5, "标旗分只记一次")
	g.toggle_flag(mine_coord, "player")  # 清理：撤旗

	print("== 过线：即跳结算 + 时间加分 ==")
	GameState.add_score(GameState.current_objective.target_value - GameState.score)
	await get_tree().process_frame
	check(not GameState.game_active, "过线即终局")
	var results = main.get_node("UILayer/ResultsPanel")
	check(results.visible, "结算页显示")
	check(results.continue_button.visible, "继续挑战按钮可见（allow_continue）")
	var st: Dictionary = GameState.result_stats
	check(int(st["time_bonus"]) > 0, "时间加分入账（%d）" % int(st.get("time_bonus", 0)))
	check(float(st.get("crossing_elapsed", -1.0)) >= 0.0, "过线时刻埋点（%.1fs）" % float(st.get("crossing_elapsed", -1.0)))
	check(GameState.score >= 300 + int(st["time_bonus"]) - 1, "总分含时间加分（%d）" % GameState.score)

	print("== 继续挑战：冻结/免命/累加不二次win ==")
	var tl0: float = GameState.time_left
	var lives0: int = GameState.lives
	main._on_continue_challenge()
	check(GameState.continue_mode and GameState.game_active, "回盘面继续模式")
	await get_tree().create_timer(1.0, true, false, true).timeout
	check(absf(GameState.time_left - tl0) < 0.01, "倒计时冻结（%.2f→%.2f）" % [tl0, GameState.time_left])
	g.open_cell(lvl.fixed_mines[1], "player")
	check(GameState.lives == lives0, "继续中踩雷不扣命（%d）" % GameState.lives)
	GameState.add_score(50)
	await get_tree().process_frame
	check(GameState.game_active and not results.visible, "继续中涨分不二次触发结算")
	check(GameState.score >= 300 + int(st["time_bonus"]) + 50 - 1, "分数累加于结算分之上（%d）" % GameState.score)

	print("== 继续中离开：不二次发矿 + 补埋点 ==")
	var ore0: int = SaveSystem.ore
	var rec0: Dictionary = SaveSystem.stats.get("playtest", [{}])[-1]
	main._leave_after_continue()
	check(not GameState.game_active and main.get_node("UILayer/LevelSelect").visible, "回到选关页")
	check(SaveSystem.ore == ore0, "离开不二次发矿（%d）" % SaveSystem.ore)
	var rec1: Dictionary = SaveSystem.stats.get("playtest", [{}])[-1]
	check(bool(rec1.get("continued", false)), "埋点补 continued")
	check(int(rec1.get("continue_gain", -1)) >= 0, "埋点补 continue_gain（%d）" % int(rec1.get("continue_gain", -1)))
	check(rec1.has("meta_snapshot") and rec1.has("crossing_elapsed"), "meta_snapshot/crossing_elapsed 收档")
	check(int(rec1["speed_levels_final"].size()) == 4, "4 轨终值埋点（%s）" % str(rec1["speed_levels_final"]))

	print("== 局外消费：进场即见（速度双轨 + 送机器人） ==")
	SaveSystem.unlocks["global_speed"] = 1
	SaveSystem.unlocks["work_speed"] = 1
	SaveSystem.unlocks["start_robot"] = 2
	SaveSystem.ore += 400  # 供间场购买埋点口径测试（不影响关卡）
	main._start_level("ch01_s03")
	await get_tree().process_frame
	check(GameState.opener_move_level == 1 and GameState.marker_move_level == 1, "局外移动档进场即见")
	check(GameState.opener_work_level == 1 and GameState.marker_work_level == 1, "局外工作档进场即见")
	check(absf(GameState.get_move_interval("opener") - 1.6) < 0.001, "移动间隔 1.6s")
	check(absf(GameState.get_work_interval("marker") - 1.6) < 0.001, "工作间隔 1.6s")
	check(main.robot_manager.robots.size() == 2, "start_robot Lv2 送两台（%d）" % main.robot_manager.robots.size())
	check(GameState.opener_count == 1 and GameState.marker_count == 1, "赠送计入 count（Q2：抬价格阶梯）")
	check(GameState.get_robot_price("opener") == 100, "首购价已是第 2 台价 100（%d）" % GameState.get_robot_price("opener"))

	print("== L1/L2 手感回归：通用轨同步双表 ==")
	main._start_level("ch01_s02")
	await get_tree().process_frame
	check(GameState.get_upgrade_level("opener_speed") == 0, "L2 通用轨归零（meta=false 不吃局外）")
	GameState.add_money(60)
	check(GameState.purchase_upgrade("opener_speed"), "L2 购买通用轨 Lv1")
	check(GameState.opener_move_level == 1 and GameState.opener_work_level == 1, "通用轨同步双表")
	check(absf(GameState.get_move_interval("opener") - 1.6) < 0.001
			and absf(GameState.get_work_interval("opener") - 1.6) < 0.001, "L2 双轨同速（手感不变）")

	# 恢复局外档
	SaveSystem.unlocks = _saved_unlocks.duplicate()
	SaveSystem.ore = _saved_ore

	print("")
	if fails.is_empty():
		print("=== ALL PASS ===")
		get_tree().quit(0)
	else:
		print("=== FAILED %d 项: %s ===" % [fails.size(), ", ".join(PackedStringArray(fails))])
		get_tree().quit(1)
