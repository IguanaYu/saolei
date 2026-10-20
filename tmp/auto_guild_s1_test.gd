extends SceneTree
## 冒险者工会 WP1 骨架冒烟测试（2026-10-20 ch04_s01「工会开张日」）
## 覆盖：关卡数据层（ch04_s01/白名单/无时限无命）→ 进关（营业面板/商店隐藏/闸门挂接）
## → 手动开格扣工时（真实点击管线，同帧洪水只扣一次）→ 插旗扣工时/撤旗免费
## → 工时耗尽拦截（真实闸门路径）→ 三批发布推进（结转口径/占位结算/营业日结束=胜利）
## → 非工会关回归（ch02_s01 不受闸门/面板影响）。
## 驱动方式：headless 直调点击分流 _on_cell_left_clicked/_on_cell_right_clicked——
## 完全确定性，不依赖真实鼠标；全程弱类型无 class_name 标注（-s 编译期限制）。
## 用法：Godot_console.exe --path . -s res://tmp/auto_guild_s1_test.gd（headless 可跑）

var step_no := 0
var fails: Array = []
var GS: Node
var main: Node
var g: Node
var gm: Node
var save_bak := ""


func _initialize() -> void:
	print("[GuildS1] USER_DATA=", OS.get_user_data_dir())
	change_scene_to_file("res://scenes/ui/BootLoading.tscn")
	call_deferred("_run")


func check(cond: bool, label: String) -> void:
	step_no += 1
	if cond:
		print("  [PASS] #%d %s" % [step_no, label])
	else:
		fails.append(label)
		print("  [FAIL] #%d %s" % [step_no, label])


func _sec(t: float) -> void:
	await create_timer(t, true).timeout


func _finish() -> void:
	var ud := OS.get_user_data_dir()
	if save_bak != "":
		var f := FileAccess.open(ud + "/save_data.json", FileAccess.WRITE)
		f.store_string(save_bak)
		f.close()
		print("[GuildS1] 存档已还原")
	var code := 0 if fails.is_empty() else 1
	print("[GuildS1] RESULT=%s FAILS=%d %s" % ["OK" if fails.is_empty() else "NG",
			fails.size(), str(fails)])
	quit(code)


## 找一个可交互的未开格：非雷/非基地/未开/未插旗（读真值是测试特权）
func _pick_closed_cell(need_two := false) -> Array:
	var found: Array = []
	for coord in g.cells.keys():
		var c = g.cells[coord]
		if (not c.is_opened) and (not c.is_mine) and (not c.is_flagged) and (not c.is_base):
			found.append(coord)
			if found.size() >= (2 if need_two else 1):
				break
	return found


func _run() -> void:
	await _sec(1.0)
	GS = root.get_node("/root/GameState")
	var LS = root.get_node("/root/LevelSystem")
	var ud := OS.get_user_data_dir()
	if FileAccess.file_exists(ud + "/save_data.json"):
		var f := FileAccess.open(ud + "/save_data.json", FileAccess.READ)
		save_bak = f.get_as_text()
		f.close()

	# ---- ① 关卡数据层 ----
	var lvl = LS.get_level("ch04_s01")
	check(lvl != null, "4-1 关卡存在")
	if lvl == null:
		_finish()
		return
	check(lvl.guild_mode, "guild_mode=true")
	check(lvl.time_limit_sec == 0.0, "无倒计时（营业日不锁现实时间）")
	check(lvl.start_lives == 0, "无命（无失败状态）")
	check(lvl.start_gold == 0, "零开局资金（无商店经济）")
	check(lvl.fixed_base == LS.get_level("ch02_s02").fixed_base, "盘面=2-2 复制（同基地）")
	var ids: Array = []
	for ch in LS.get_implemented_chapters():
		ids.append(ch.id)
	check(ids.has("ch04"), "ch04 进实装白名单")

	# ---- ② 进关 ----
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline \
			and (root.get_node_or_null("Main") == null
				or root.get_node("Main").get_node_or_null("UILayer/TutorialGuide") == null):
		await _sec(0.1)
	main = root.get_node_or_null("Main")
	check(main != null, "Main 场景就绪")
	if main == null:
		_finish()
		return
	await _sec(0.5)
	main._start_level("ch04_s01")
	deadline = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		if GS.current_level_id == "ch04_s01" and main.grid != null \
				and main.grid.cells.size() > 0 and GS.game_active:
			break
		await _sec(0.2)
	g = main.grid
	gm = main.guild_day_manager
	if g == null or gm == null or GS.current_level_id != "ch04_s01":
		check(false, "4-1 盘装载（id=%s）" % GS.current_level_id)
		_finish()
		return
	check(GS.game_active, "进局且 game_active（预置基地直开）")
	check(gm.active, "营业日管理器激活")
	check(gm.batch_index == 0 and gm.phase == "prepare", "第 1 批准备阶段")
	check(gm.hours_granted == 100 and gm.hours_left == 100, "首批开放 100 工时")
	check(g.action_gate.is_valid(), "grid 动作闸门已挂接")
	check(main.guild_panel.visible, "营业面板显示")
	check(not main.shop.visible, "商店隐藏（工会关无购买）")
	check(not main.guild_panel._publish_btn.disabled, "发布按钮可用")

	# ---- ③ 手动开格扣工时（真实点击管线）----
	var picks := _pick_closed_cell(true)
	check(picks.size() >= 2, "可交互未开格充足")
	if picks.size() < 2:
		_finish()
		return
	var c1 = g.cells[picks[0]]
	var before: int = gm.hours_left
	g._on_cell_left_clicked(c1)
	check(gm.hours_left == before - 1, "开格一次扣 1 工时（同帧洪水合并计费）")
	check(c1.is_opened, "格子真的开了（闸门放行）")

	# ---- ④ 插旗扣工时 / 撤旗免费 ----
	var c2 = g.cells[picks[1]]
	before = gm.hours_left
	g._on_cell_right_clicked(c2)
	check(gm.hours_left == before - 1, "插旗扣 1 工时")
	check(c2.is_flagged, "旗插上了")
	g._on_cell_right_clicked(c2)
	check(gm.hours_left == before - 1, "撤旗免费（不重复扣）")
	check(not c2.is_flagged, "旗撤掉了")

	# ---- ⑤ 工时耗尽拦截（真实闸门路径）----
	gm.hours_spent = gm.hours_granted  # 直写账本模拟耗尽（spend() 有封顶不适合注入）
	check(not gm.can_player_act(), "闸门拒绝：工时耗尽")
	var picks2 := _pick_closed_cell(true)
	var c3 = g.cells[picks2[0]]
	g._on_cell_left_clicked(c3)
	check(not c3.is_opened, "拦截生效：格子没被打开")
	g._on_cell_right_clicked(c3)
	check(not c3.is_flagged, "拦截生效：旗没插上")
	gm.hours_spent = 0
	check(gm.can_player_act(), "工时恢复后闸门放行")

	# ---- ⑥ 三批发布推进（结转口径 + 营业日结束=胜利）----
	gm.publish_batch()
	check(gm.batch_index == 1 and gm.phase == "prepare", "第 2 批进入准备")
	check(gm.hours_granted == 200 and gm.hours_left == gm.hours_granted - gm.hours_spent,
			"结转口径：新批 +100 开放，余量=开放-消耗")
	check(GS.result_stats["guild_batches_published"] == 1, "发布计数埋点=1")
	check(not main.guild_panel._publish_btn.disabled, "面板回到可发布态")
	gm.publish_batch()
	check(gm.batch_index == 2, "第 3 批进入准备")
	gm.publish_batch()
	check(gm.phase == "done", "第三批发布后营业日结束")
	check(GS.result_stats["guild_batches_published"] == 3, "发布计数埋点=3")
	check(not gm.can_player_act(), "结束后闸门拒绝")
	deadline = Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		if not GS.game_active and main.results_panel.visible:
			break
		await _sec(0.2)
	check(not GS.game_active, "营业日结束→胜利结算启动（game_active=false）")
	check(main.results_panel.visible, "结算面板弹出")

	# ---- ⑦ 非工会关回归（2-1 不受闸门/面板影响）----
	main._start_level("ch02_s01")
	deadline = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		if GS.current_level_id == "ch02_s01" and main.grid != null \
				and main.grid.cells.size() > 0 and GS.game_active:
			break
		await _sec(0.2)
	g = main.grid
	if GS.current_level_id != "ch02_s01":
		check(false, "2-1 重进（id=%s）" % GS.current_level_id)
		_finish()
		return
	check(not gm.active, "非工会关管理器休眠")
	check(not main.guild_panel.visible, "营业面板隐藏")
	check(main.shop.visible, "商店恢复显示")
	check(not g.action_gate.is_valid(), "闸门清残留（非工会关不拦截）")

	_finish()
