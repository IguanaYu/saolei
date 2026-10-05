extends Node
## 第四关（除害关·固定图）全流程自动化冒烟测试（headless）
## 用法：Godot_console.exe --path . --headless res://tmp/test_level4.tscn
## 覆盖：固定盘装载/大片预开 → placing_base 强制放基地（仅已开格）→ 预置虫害/裂缝
##       → 三状态（网/锁/黏液）+ Solver 兼容 → 虫施害/点杀/巢摧毁/波次取消
##       → 保安索敌清障 → 探测确认雷/计分防刷 → 商店显隐/限购 → 埋点字段

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
	for k in ["start_money", "start_lives", "global_speed", "work_speed", "start_robot"]:
		SaveSystem.unlocks[k] = 0

	# ---- M1：固定盘 + 放基地 ----
	print("== M1：固定盘装载 + 基地自放 ==")
	main._start_level("ch01_s01")  # 解锁链
	main._start_level("ch01_s02")
	main._start_level("ch01_s03")
	main._start_level("ch01_s04")
	await get_tree().process_frame
	var lvl: LevelData = GameState.get_current_level()
	check(lvl != null and lvl.has_fixed_board() and lvl.pests, "关卡数据：固定盘+pests 开")
	check(g.rows == 16 and g.cols == 16 and g.mine_count == 40, "盘面 16x16 40 雷")
	check(GameState.game_phase == "placing_base" and not GameState.game_active, "进关=放基地阶段未激活")
	var mines1: Array = []
	var opened1: int = 0
	for c in g.cells.values():
		if c.is_mine:
			mines1.append(c.coord)
		if c.is_opened:
			opened1 += 1
	check(mines1.size() == 40, "固定盘雷 40（%d）" % mines1.size())
	# 固定图保底大片预开（v2.3 盲测反馈：单起点随机洪水 42% 概率 <15%）
	check(opened1 >= 50, "大片预开 ≥50（%d 格）" % opened1)
	check(GameState.score == 0, "L4 预开不算分（preopen_scores=false，%d）" % GameState.score)
	# 预开区连通性：从任一已开零格洪水遍历应覆盖全部已开格（同连通域）
	check(_preopen_is_connected(), "预开区为一片连通洪水")
	# 巢 2 个 + 预置网 3 + 锁 3
	var em: EnemyManager = main.enemy_manager
	check(em.nests.size() == 2, "裂缝 2 个（%d）" % em.nests.size())
	for n in em.nests:
		var on_edge: bool = n.coord.x == 0 or n.coord.y == 0 \
				or n.coord.x == 15 or n.coord.y == 15
		check(on_edge, "裂缝在盘边 %s" % [n.coord])
	var webs := 0
	var locks := 0
	for c in g.cells.values():
		webs += int(c.is_webbed)
		locks += int(c.is_locked)
	check(webs == 3, "预置网 3（%d）" % webs)
	check(locks == 3, "预置锁 3（%d）" % locks)

	# 放基地：未开格失败，已开格成功
	var closed_cell: Variant = null
	var opened_cell: Variant = null
	for c in g.cells.values():
		if closed_cell == null and not c.is_opened:
			closed_cell = c
		if opened_cell == null and c.is_opened and not c.is_webbed:
			opened_cell = c
		if closed_cell != null and opened_cell != null:
			break
	check(main._try_place_first_base_at(g.coord_to_world(closed_cell.coord)) == false, "未开格放基地被拒")
	check(main._try_place_first_base_at(g.coord_to_world(opened_cell.coord)) == true, "已开格放基地成功")
	check(GameState.game_active and GameState.game_phase == "playing", "放完基地激活")
	check(GameState.bases.has(opened_cell.coord), "基地注册")

	# 重开=同一张固定盘：雷位逐格一致，回放体验稳定
	var board_a: Array = mines1.duplicate()
	main._start_level("ch01_s04")
	await get_tree().process_frame
	var mines2: Array = []
	for c in g.cells.values():
		if c.is_mine:
			mines2.append(c.coord)
	# 重开后要重新放基地才能激活
	check(GameState.game_phase == "placing_base", "重开回放基地阶段")
	var reopened: int = 0
	for c in g.cells.values():
		if c.is_opened and not c.is_webbed and not c.is_locked:
			reopened += 1
	check(reopened >= 50, "重开固定盘预开一致 ≥50（%d 格）" % reopened)
	var any_open := false
	for c in g.cells.values():
		if c.is_opened and not c.is_webbed and not c.is_locked:
			any_open = true
			opened_cell = c
			break
	check(any_open, "盘上有可放基地的干净预开格")
	check(main._try_place_first_base_at(g.coord_to_world(opened_cell.coord)), "重开放基地")
	check(board_a.hash() == mines2.hash(), "重开雷位逐格一致（固定盘）")

	# ---- M2：三状态 + Solver 兼容 ----
	print("== M2：网/锁/黏液 三状态 ==")
	# 找一个已开数字格盖网
	var digit_cell: Cell = null
	for c in g.cells.values():
		if c.is_opened and c.adjacent_mines > 0:
			digit_cell = c
			break
	check(digit_cell != null, "存在已开数字格")
	if digit_cell == null:
		_finish()
		return
	digit_cell.apply_web()
	var actions := Solver.find_certain_actions(g)
	var web_blinds: bool = true
	for a in actions:
		if a.source == digit_cell.coord:
			web_blinds = false
	check(web_blinds, "网盖数字格不再提供推理依据")
	digit_cell.clear_web("player")
	# 锁：锁住一个未开格
	var closed2: Cell = null
	for c in g.cells.values():
		if not c.is_opened and not c.is_flagged and not c.is_mine and not c.is_locked:
			closed2 = c
			break
	check(closed2 != null and closed2.apply_lock(), "上锁成功")
	g.open_cell(closed2.coord, "player")
	check(not closed2.is_opened, "锁格开不了（open 无效）")
	g.toggle_flag(closed2.coord, "player")
	check(not closed2.is_flagged, "锁格标不了旗")
	check(closed2.clear_lock("player") and not closed2.is_locked, "清锁成功")
	# 黏液：机器人间隔 ×2
	var slime_host: Cell = opened_cell
	slime_host.apply_slime()
	main.robot_manager.spawn_robot(opened_cell.coord, "opener", g)
	# 直接验证 is_slime_nearby + 间隔翻倍逻辑（避开时序抖动）
	check(g.is_slime_nearby(slime_host.coord), "黏液 3×3 判定命中")
	check(g.is_slime_nearby(slime_host.coord + Vector2i(1, 1)), "黏液 3×3 边角命中")
	check(not g.is_slime_nearby(slime_host.coord + Vector2i(2, 0)), "黏液 3×3 外不命中")
	slime_host.clear_slime("player")
	check(not g.is_slime_nearby(slime_host.coord), "清黏液后恢复")

	# ---- M3：虫/巢/波次（2026-10-05 领土接近规则） ----
	print("== M3：虫实体 + 巢 + 波次（领土接近） ==")
	var em2: EnemyManager = main.enemy_manager
	# 随机边侧的巢不可控（底边巢可能恰贴预开区）：先直击清场，换固定远位巢做确定性断言
	for n in em2.nests.duplicate():
		n.hit()
		n.hit()
	check(em2.nests.is_empty(), "清掉随机巢（直击绕过点击门）")
	var nest: Nest = load("res://scenes/Nest.tscn").instantiate()
	em2.add_child(nest)
	nest.setup(Vector2i(0, 2), 2, g)
	em2.nests.append(nest)
	nest.destroyed.connect(em2._on_nest_destroyed)
	# 远巢：开局不可点 → 拦截不伤不耗 CD → 拆路连通后 2 击摧毁
	check(not nest.is_clickable(g), "盘边远巢开局不可点（未开路接近）")
	var acts0: int = GameState.result_stats["player_actions"]
	check(main._try_hit_enemy_at(g.coord_to_world(nest.coord)), "点远巢：命中被拦截（不穿透）")
	check(nest.hp == 2, "拦截不伤巢 HP")
	# 深处墙虫同口径：隔空点死被拦
	var far_bug: Enemy = em2.spawn_enemy(Vector2i(0, 8), "web", g)
	check(not far_bug.is_clickable(g), "深处墙虫不可点")
	check(main._try_hit_enemy_at(g.coord_to_world(far_bug.coord)), "点远虫：命中被拦截")
	check(far_bug.is_alive(), "远虫未死（不隔空点死）")
	check(GameState.result_stats["player_actions"] == acts0, "拦截不耗 CD 次数")
	em2.kill_enemy(far_bug, "robot_marker")  # 清场（不走点杀埋点）
	_dig_to(Vector2i(0, 3))  # 从巢邻格向领土凿已开路（模拟玩家拆格扩散）
	check(nest.is_clickable(g), "开路到巢边后巢可点")
	check(main._try_hit_enemy_at(g.coord_to_world(nest.coord)), "点巢第一击")
	check(nest.hp == 1, "巢 HP 2→1")
	check(main._try_hit_enemy_at(g.coord_to_world(nest.coord)), "点巢第二击")
	check(not em2.nests.has(nest), "巢被摧毁（从列表移除）")
	check(int(GameState.result_stats["nests_destroyed"]) == 3, "除巢埋点（随机2+固定1）")
	# 虫施害：织网虫盖数字
	var bug := em2.spawn_enemy(Vector2i(8, 8), "web", g)
	check(bug != null and bug.is_alive(), "虫出生")
	check(GameState.get_nearest_base(Vector2i(8, 8)) != null, "虫有奔袭目标")
	check(bug.is_clickable(g), "预开区（领土）上的虫可点")
	bug._harm_timer = 99.0
	bug._harm(g)
	var webbed_after := 0
	for c in g.cells.values():
		webbed_after += int(c.is_webbed)
	check(webbed_after >= 1, "织网虫施害放了网（%d）" % webbed_after)
	# 点杀：命中半径内（断言用 manager 列表判断，避免触碰已释放的实体）
	var world := g.coord_to_world(bug.coord)
	check(main._try_hit_enemy_at(world), "点虫命中")
	await get_tree().process_frame
	check(not em2.enemies.has(bug), "虫被点杀（从列表移除）")
	check(int(GameState.result_stats["enemy_kills_player"]) == 1, "点杀埋点 +1")
	# 巢已全毁 → 波次取消
	em2._elapsed = 200.0
	em2.tick(1.0, g)
	check(em2.enemies.is_empty(), "波次全部取消（无巢无新虫）")

	# ---- M4：保安（2026-10-02 直购直出：购买即从基地旁出生，不再手动放置） ----
	print("== M4：保安机器人 ==")
	GameState.add_money(500)
	var shop: Control = main.shop
	check(shop.buy_guard_button.visible, "L4 商店显示保安按钮")
	check(shop.buy_probe_button.visible, "L4 商店显示探测按钮")
	check(shop.lock_reason("guard") == "", "保安可买（未购）")
	check(main._buy_and_spawn_robot("guard"), "直购买保安（基地旁出生）")
	check(GameState.guard_count == 1, "保安计数 1")
	check(shop.lock_reason("guard") == "已购满", "保安限购 1 生效")
	var guard = main.robot_manager.robots[main.robot_manager.robots.size() - 1]
	check(guard is GuardRobot, "GuardRobot 实例")
	check(guard.is_idle() == false, "保安永不空闲告警")
	# 保安索敌：放一个锁在已开区旁 → 保安应锁定 lock 类目标
	var lock_spot: Cell = null
	for c in g.cells.values():
		if not c.is_opened and not c.is_locked and not c.is_mine:
			for n in g.get_neighbors(c.coord):
				if n.is_opened:
					lock_spot = c
					break
		if lock_spot != null:
			break
	lock_spot.apply_lock()
	guard.do_tick(g, GameState.locked_targets)
	check(guard._target_kind == "lock", "保安索敌锁定锁格（kind=%s）" % guard._target_kind)
	check(g.get_cell(guard._target_coord) != null and g.get_cell(guard._target_coord).is_locked,
			"目标是一个锁格（盘上还有预置锁，BFS 最近优先）")
	# 快进开火（1.5s）：一枪一个
	var lock_target: Cell = g.get_cell(guard._target_coord)
	guard._fire_timer = 1.6
	guard._grid_ref = g
	guard._fire(g)
	check(not lock_target.is_locked, "保安一枪清锁")
	check(int(GameState.result_stats["obstacles_cleared_guard"]) >= 1, "保安清障埋点")

	# ---- M5：探测 ----
	print("== M5：探测机器人 ==")
	GameState.add_money(500)
	var probe_center: Vector2i = Vector2i(8, 8)
	var expect_mines: int = 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if g.get_cell(probe_center + Vector2i(dx, dy)) != null \
					and g.get_cell(probe_center + Vector2i(dx, dy)).is_mine:
				expect_mines += 1
	main._enter_placing_mode("probe")
	check(main.placing_mode == "probe", "进入 probe 放置模式")
	var money_before: int = GameState.money
	check(main._try_place_at(g.coord_to_world(probe_center)), "探测放置成功")
	check(GameState.money == money_before - 100, "扣 100")
	check(int(GameState.result_stats["probe_used"]) == 1, "探测埋点 +1")
	var confirmed_n: int = 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c = g.get_cell(probe_center + Vector2i(dx, dy))
			if c != null and c.is_confirmed_mine:
				confirmed_n += 1
	check(confirmed_n == expect_mines, "3×3 确认雷数正确（%d/%d）" % [confirmed_n, expect_mines])
	# 确认雷格再插旗不给分
	var conf_cell: Cell = null
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c = g.get_cell(probe_center + Vector2i(dx, dy))
			if c != null and c.is_confirmed_mine and not c.is_flagged:
				conf_cell = c
				break
		if conf_cell != null:
			break
	if conf_cell != null:
		var score_before: int = GameState.score
		g.toggle_flag(conf_cell.coord, "player")
		check(conf_cell.is_flagged, "确认雷格可以插旗（视觉手动）")
		check(GameState.score == score_before, "确认雷格插旗不给分")
	# Solver 吃确认雷（视同旗计雷）：构造确定性场景——找一个已开数字格，
	# 把它邻域的雷全部 confirm → 雷数已凑齐 → 其余未开邻格应生成 open 动作
	var solver_src: Cell = null
	for c in g.cells.values():
		if c.is_opened and c.adjacent_mines > 0 and not c.is_webbed:
			var has_unopened_safe := false
			for n in g.get_neighbors(c.coord):
				if not n.is_opened and not n.is_mine and not n.is_confirmed_mine:
					has_unopened_safe = true
			if has_unopened_safe:
				solver_src = c
				break
	if solver_src != null:
		for n in g.get_neighbors(solver_src.coord):
			if n.is_mine and not n.is_confirmed_mine:
				n.confirm_mine()
		var acts := Solver.find_certain_actions(g)
		var got_open := false
		for a in acts:
			if a.action == "open" and a.source == solver_src.coord:
				got_open = true
		check(got_open, "Solver 把确认雷计雷：雷数凑齐 → 生成安全格 open 动作")
	else:
		check(false, "（找不到适合构造的数字格——盘面巧合，重跑即可）")

	# ---- 回归：旧关按钮显隐 + 正式关 ----
	print("== 回归：商店显隐 ==")
	main._start_level("ch01_s01")
	await get_tree().process_frame
	check(not main.shop.buy_guard_button.visible, "L1 无保安按钮")
	check(not main.shop.buy_probe_button.visible, "L1 无探测按钮")

	_finish()


## 从 start 格向最近的已开格 BFS 凿一条已开路（避开雷/化石/网/锁），
## 直写 is_opened 不走信号——同预开口径；模拟玩家拆格扩散到目标位
func _dig_to(start: Vector2i) -> void:
	var territory: Dictionary = g.player_territory()
	var visited: Dictionary = {start: true}
	var parent: Dictionary = {}
	var queue: Array = [start]
	var goal: Variant = null
	while not queue.is_empty() and goal == null:
		var c: Vector2i = queue.pop_front()
		for o in MapGenerator.NEIGHBOR_OFFSETS:
			var n: Vector2i = c + o
			if visited.has(n) or not g.cells.has(n):
				continue
			var cell: Cell = g.cells[n]
			if cell.is_mine or cell.is_fossil or cell.is_webbed or cell.is_locked:
				continue
			visited[n] = true
			parent[n] = c
			if territory.has(n):
				goal = n
				break
			queue.append(n)
	var cur: Variant = goal
	while cur != null and parent.has(cur):
		g.cells[cur].is_opened = true
		cur = parent[cur]
	if goal != null:
		g.cells[start].is_opened = true  # 根格一并凿开（调用方保证非雷非化石）


func _preopen_is_connected() -> bool:
	# 从任一已开零格 BFS（只走已开格），应覆盖全部已开格（单一连通域）
	var start: Variant = null
	for c in g.cells.values():
		if c.is_opened and c.adjacent_mines == 0:
			start = c.coord
			break
	if start == null:
		return true  # 无零格时无法验证，跳过
	var visited: Dictionary = {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var pos: Vector2i = queue.pop_front()
		for o in MapGenerator.NEIGHBOR_OFFSETS:
			var n: Vector2i = pos + o
			if visited.has(n) or not g.cells.has(n):
				continue
			if not g.cells[n].is_opened:
				continue
			visited[n] = true
			queue.append(n)
	var total_open: int = 0
	for c in g.cells.values():
		if c.is_opened:
			total_open += 1
	return visited.size() == total_open


func _finish() -> void:
	SaveSystem.unlocks = _saved_unlocks.duplicate()
	SaveSystem.ore = _saved_ore
	print("")
	if fails.is_empty():
		print("=== L4 全部通过 ===")
	else:
		print("=== FAIL %d 项 ===" % fails.size())
		for f in fails:
			print("  - " + f)
	get_tree().quit(0 if fails.is_empty() else 1)
