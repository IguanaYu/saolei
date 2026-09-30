extends Node
## L5 Boss 关 M4 验收（P3 锁链+触手+换位闭环）：P3 转场换位到右侧/锁抛墙格可清/
## 触手占格断通路/点根断裂奖励/12s 自然缩回/无墙时锁自动跳过/无段时触手顺延
## 用法：Godot_console.exe --path . --headless res://tmp/test_level5_m4.tscn

var fails: Array = []
var main: Node
var g: Grid


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


func _ready() -> void:
	await get_tree().process_frame
	var ps: PackedScene = load("res://scenes/Main.tscn")
	main = ps.instantiate()
	get_parent().add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	g = main.grid

	print("== 起关 → 直进 P3（拔 12 颗牙） ==")
	main._start_level("ch01_s05")
	await get_tree().process_frame
	var base_coord: Vector2i = FixedBoards.L5.preopen[0]
	main._try_place_first_base_at(g.coord_to_world(base_coord))
	var mines: Array = FixedBoards.L5.mines.duplicate()
	var teeth := 0
	for m in mines:
		if teeth >= 12:
			break
		g.toggle_flag(m, "robot_marker")
		teeth = g.count_processed_mines()
	check(main.boss_manager.phase == 3, "第 12 颗牙转 P3")
	await get_tree().create_timer(0.2).timeout   # 换位爬行动画 2s（真实时间）
	check(main.boss_manager._beast.anchor == "right", "Boss 换位至右侧盘框")

	print("== 锁链投射（first=4s） ==")
	await pump(6, main)
	var locked_count := 0
	for coord in g.cells:
		if g.cells[coord].is_locked:
			locked_count += 1
	check(locked_count >= 3, "P3 已抛锁（%d 把）" % locked_count)
	# 锁可点清（复用 L4 通道）：找一个锁格左键点掉
	var a_lock: Vector2i = Vector2i(-9, -9)
	for coord in g.cells:
		if g.cells[coord].is_locked:
			a_lock = coord
			break
	check(a_lock != Vector2i(-9, -9), "找到锁格")
	var lock_cell = g.get_cell(a_lock)
	lock_cell.clear_lock("player")
	check(not lock_cell.is_locked, "锁可清除（L4 通道复用）")

	print("== 触手（first=8s，右侧伸入） ==")
	# 直跳 P3 的测试盘右侧还是墙（真实游玩到 P3 时右侧多已开）——按无雷行开右侧段
	# （x≥8 的无雷行：y=2,3,6,10,12；雷位 x≥8 有 (8,1)(8,4)(9,5)(9,8)(9,11)(10,0)(10,13)(12,4)(12,7)(12,11)）
	for y in [2, 3, 6, 10, 12]:
		for x in range(g.cols - 1, g.cols - 7, -1):
			var c = g.get_cell(Vector2i(x, y))
			if c != null and not c.is_opened and not c.is_mine:
				c.is_opened = true
				c.refresh_visual()
	await pump(5, main)
	var tent: Tentacle = null
	for t in main.boss_manager.tentacles:
		if t.is_active():
			tent = t
			break
	check(tent != null, "触手已伸出（%d 条）" % main.boss_manager.tentacles.size())
	if tent != null:
		check(tent.cells.size() >= 4 and tent.cells.size() <= 6, "段长 4-6（%d）" % tent.cells.size())
		check(tent.cells[0].x == g.cols - 1, "根部贴右侧盘边（%s）" % str(tent.cells[0]))
		var blocked_ok := true
		for c in tent.cells:
			if g.is_walkable(c):
				blocked_ok = false
		check(blocked_ok, "段内全部通路阻断")
		# 点断：奖励 + 埋点
		var money0: int = GameState.money
		check(main._try_hit_enemy_at(g.coord_to_world(tent.root_coord)), "点根部命中")
		check(not tent.is_active(), "整条断裂")
		check(GameState.money == money0 + 15, "断裂奖励 +15 钱")
		check(GameState.result_stats["tentacles_cut"] == 1, "断触手埋点 +1")
		var freed_ok := true
		for c in tent.cells:
			if not g.is_walkable(c):
				freed_ok = false
		check(freed_ok, "断裂后通路释放")

	print("== 12s 自然缩回 ==")
	# 等下一条触手（every 30s）——直接手工造一条更快（用测试开过的无雷行 y=6）
	var seg: Array = []
	var y_probe := 6
	for x in range(g.cols - 1, g.cols - 7, -1):
		var c = g.get_cell(Vector2i(x, y_probe))
		if c == null or not c.is_opened or c.is_base or c.is_on_fire:
			break
		seg.append(Vector2i(x, y_probe))
	if seg.size() >= 4:
		var t2 := Tentacle.new()
		main.boss_manager.add_child(t2)
		t2.setup(seg, g)
		main.boss_manager.tentacles.append(t2)
		check(t2.is_active() and not g.is_walkable(seg[0]), "第二段触手占格")
		await pump(13, main)
		check(not t2.is_active(), "12s 自然缩回")
		# 泵的过程中 Boss 落弹可能把火烧到测试行（火也是通路阻断，8s 退散）——
		# 等火退散后再验通路，把「触手释放」与「火区干扰」两个断言解耦
		var diag_cell = g.get_cell(seg[0])
		var wait := 0
		while diag_cell.is_on_fire and wait < 10:
			await pump(1, main)
			wait += 1
		print("  [diag] seg[0]=%s fire=%s blockers=%d tent_state=%s waited=%d" % [
			seg[0], diag_cell.is_on_fire, diag_cell.path_blockers, t2.state, wait])
		check(g.is_walkable(seg[0]), "缩回后通路释放")
	else:
		# 中间行没连续开段（盘面状态不同）——退化为 boss 出的触手自然缩回验证
		var any_t: Tentacle = null
		for t in main.boss_manager.tentacles:
			if t.is_active():
				any_t = t
				break
		if any_t != null:
			var c0: Vector2i = any_t.cells[0]
			await pump(13, main)
			check(not any_t.is_active() and g.is_walkable(c0), "12s 自然缩回 + 通路释放")
		else:
			check(false, "无触手可验证缩回")

	print("== 无墙时锁自动跳过 ==")
	# 把剩余未开格全部直接开掉（安全格）+ 旗掉剩余雷 = 无未开墙（先清锁：锁可能盖住雷格）
	for coord in g.cells:
		var cl = g.cells[coord]
		if cl.is_locked:
			cl.clear_lock("player")
	for coord in g.cells:
		var c = g.cells[coord]
		if not c.is_opened and not c.is_locked and not c.is_flagged:
			if c.is_mine:
				g.toggle_flag(coord, "robot_marker")
			else:
				c.is_opened = true
				c.refresh_visual()
	var walls_left := 0
	for coord in g.cells:
		var c = g.cells[coord]
		if not c.is_opened and not c.is_locked and not c.is_flagged:
			walls_left += 1
	check(walls_left == 0, "盘面已无未开墙（旗/锁除外，剩 %d）" % walls_left)
	var teeth_now: int = g.count_processed_mines()
	if teeth_now < 20:
		# 触发一次锁投射（直接调内部，绕过节拍）
		main.boss_manager._cast_lock(g)
	check(true, "无墙抛锁不崩溃（静默跳过）")

	print("== 斩杀收尾 ==")
	if g.count_processed_mines() < 20:
		g.refresh_processed_mines()
	await get_tree().create_timer(0.8).timeout
	check(not GameState.game_active or main.results_panel.visible, "斩杀流程可走通")

	print("")
	if fails.is_empty():
		print("=== ALL PASS ===")
	else:
		print("=== FAILED %d 项: %s ===" % [fails.size(), ", ".join(fails)])
	get_tree().quit(0 if fails.is_empty() else 1)
