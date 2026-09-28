extends Node
## 充能银行验证：囤 7 层 / 花存款不打断回充 / 满仓闲置 / 拦截口径 / CDRing 三态

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		push_error("FAIL: " + msg)
		failures += 1


func _ready() -> void:
	GameState.cd_phase = "free"
	GameState.cd_free_clicks_left = 2
	GameState.cd_flag_limit = 0
	GameState.cd_sec = 10.0
	GameState.cd_after_purchase = -1.0
	GameState.cd_max_charges = 7
	GameState.cd_charges = 0
	GameState.cd_duration = 0.0
	GameState.cd_remaining = 0.0
	GameState.cd_purchase_boosted = false

	print("== 免费阶段 → 耗尽 ==")
	check(not GameState.is_player_blocked(), "免费阶段不拦")
	GameState.consume_player_action()
	GameState.consume_player_action()
	check(GameState.cd_phase == "cooldown", "免费用尽转 cooldown")
	check(GameState.cd_charges == 0 and absf(GameState.cd_remaining - 10.0) < 0.001,
		"耗尽后 0 层，首层计时 10s")
	check(GameState.is_player_blocked(), "0 层被拦")

	print("== 回充与囤层 ==")
	GameState.tick_cd(10.0)
	check(GameState.cd_charges == 1, "10s 后囤到第 1 层")
	check(not GameState.is_player_blocked(), "有存款可花")
	check(absf(GameState.cd_remaining - 10.0) < 0.001, "囤到后立即攒下一层")

	print("== 花存款不打断回充 ==")
	GameState.tick_cd(4.0)   # 下一层还剩 6s
	GameState.consume_player_action()  # 花 1 层
	check(GameState.cd_charges == 0, "花掉 1 层")
	check(absf(GameState.cd_remaining - 6.0) < 0.001, "花存款不打断回充（仍剩 6s）")
	GameState.tick_cd(6.0)
	check(GameState.cd_charges == 1, "原计时走完补回 1 层")

	print("== 囤满 7 层封顶 ==")
	for i in 12:
		GameState.tick_cd(10.0)
	check(GameState.cd_charges == 7, "囤满 7 层封顶")
	check(GameState.cd_remaining <= 0.0, "满仓闲置不再计时")
	GameState.tick_cd(100.0)
	check(GameState.cd_charges == 7, "满仓后 tick 不加层")

	print("== 满仓花层与花空 ==")
	GameState.consume_player_action()
	check(GameState.cd_charges == 6, "满仓花 1 层剩 6")
	check(absf(GameState.cd_remaining - 10.0) < 0.001, "满仓消耗后重新开攒")
	for i in 6:
		GameState.consume_player_action()
	check(GameState.cd_charges == 0 and GameState.is_player_blocked(), "花空被拦")

	print("== 首购 boost 立刻恢复一次 ==")
	GameState.cd_duration = 3.0
	GameState.cd_remaining = 0.0   # boost 置零
	GameState.tick_cd(0.016)
	check(GameState.cd_charges == 1, "boost 置零后立即恢复 1 次")

	print("== CDRing 三态 ==")
	var ring := CDRing.new()
	add_child(ring)
	GameState.game_active = true
	GameState.cd_phase = "cooldown"
	GameState.cd_charges = 7
	GameState.cd_remaining = 0.0
	await get_tree().process_frame
	check(not ring.visible, "满仓环隐藏")
	GameState.cd_charges = 3
	GameState.cd_remaining = 4.0
	await get_tree().process_frame
	check(ring.visible, "囤层中环显示（×3+进度弧）")
	GameState.cd_charges = 0
	await get_tree().process_frame
	check(ring.visible, "0 层环显示（倒计时）")
	GameState.game_active = false

	print("RESULT: %s" % ("ALL_PASS" if failures == 0 else "HAS_FAIL x%d" % failures))
	get_tree().quit(0 if failures == 0 else 1)
