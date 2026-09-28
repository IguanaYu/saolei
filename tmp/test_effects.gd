extends Node
## 冒烟：③修复（锁格不发 cell_opened / 撤旗事件）+ ④动效层（岩屑/跳字/预算/旗/卸货飞币）

var main
var g: Grid
var fx: EffectsLayer
var failures := 0
var unflag_count := 0  # 成员变量：lambda 里改局部 int 是改副本（按值捕获）


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		push_error("FAIL: " + msg)
		failures += 1


func _count_children(name_prefix: String) -> int:
	var n := 0
	for c in fx.get_children():
		if String(c.name).begins_with(name_prefix):
			n += 1
	return n


func _ready() -> void:
	await get_tree().process_frame
	var ps: PackedScene = load("res://scenes/Main.tscn")
	main = ps.instantiate()
	get_parent().add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	main.get_node("UILayer/SplashScreen").hide()
	main.get_node("UILayer/PreLevelCard").hide()
	g = main.grid
	fx = g._fx
	check(fx != null and fx is EffectsLayer, "EffectsLayer 已挂载")

	# 起一关：放基地（随机盘）
	main._start_level("ch02_s01")
	await get_tree().process_frame
	main._try_place_first_base_at(g.coord_to_world(Vector2i(5, 5)))
	check(GameState.game_active, "对局激活")

	print("== ③a 锁格不发 cell_opened ==")
	# 找一个未开 0 邻格 A，其未开邻格 B 上锁；开 A 触发连锁 → B 应被跳过
	var a_coord: Vector2i = Vector2i(-1, -1)
	var b_coord: Vector2i = Vector2i(-1, -1)
	for c in g.cells:
		var cell: Cell = g.cells[c]
		if cell.is_opened or cell.is_mine or cell.adjacent_mines != 0 or cell.is_locked:
			continue
		for n2 in g.get_neighbors(c):
			if not n2.is_opened and not n2.is_flagged:
				a_coord = c
				b_coord = n2.coord
				break
		if a_coord.x >= 0:
			break
	check(a_coord.x >= 0, "找到 0 邻格与未开邻格（A=%s B=%s）" % [a_coord, b_coord])
	g.cells[b_coord].is_locked = true
	var emitted: Array = []
	g.cell_opened.connect(func(c, _a): emitted.append(c))
	var money0: int = GameState.money
	g.open_cell(a_coord, "player")
	await get_tree().process_frame
	check(not g.cells[b_coord].is_opened, "锁格 B 未被开")
	var all_really_opened := true
	for c in emitted:
		if not c.is_opened:
			all_really_opened = false
	check(all_really_opened, "所有 cell_opened 事件对应真实已开格（%d 个事件）" % emitted.size())
	check(GameState.money == money0 + emitted.size(), "收益=真实开格数（+%d）" % (GameState.money - money0))

	print("== ④b 连锁汇总跳字 + 岩屑 ==")
	# 上一开的连锁已触发批次；跳字要么还在屏要么已过期，重新造一次稳定的单格
	var jump0 := _count_children("JumpText")
	check(jump0 >= 1 or emitted.size() == 1, "连锁产生了跳字（或单格场景）")
	await get_tree().create_timer(0.8).timeout
	check(_count_children("JumpText") == 0, "跳字 0.6s 内自动消散")
	check(_count_children("Shard") == 0, "岩屑自动消散")

	print("== ④b 单格开格：岩屑 + 跳字 ==")
	var closed_one: Vector2i = Vector2i(-1, -1)
	for c in g.cells:
		var cell: Cell = g.cells[c]
		if not cell.is_opened and not cell.is_mine and cell.adjacent_mines > 0 and not cell.is_locked:
			closed_one = c  # 数字格：开了不会连锁，正好单格
			break
	check(closed_one.x >= 0, "找到未开数字格")
	g.open_cell(closed_one, "player")
	await get_tree().process_frame
	check(_count_children("Shard") == 3, "玩家单格开格 3 粒岩屑")
	check(_count_children("JumpText") == 1, "单格 +1 跳字")
	var jt: Node2D = null
	for c in fx.get_children():
		if String(c.name).begins_with("JumpText"):
			jt = c
	if jt != null and jt.has_meta("label"):
		check(jt.get_meta("label").text == "+1", "跳字内容 +1")
	else:
		check(false, "跳字内容 +1（节点缺失）")
	await get_tree().create_timer(0.8).timeout

	print("== 跳字预算：第 3 处并入最新 ==")
	fx._fx_jump_text(Vector2(100, 100), "+2")
	fx._fx_jump_text(Vector2(200, 100), "+3")
	fx._fx_jump_text(Vector2(300, 100), "+4")
	var dbg := "children=["
	for c in fx.get_children():
		if String(c.name).begins_with("JumpText"):
			dbg += "%s:%s," % [c.name, c.get_meta("label").text if c.has_meta("label") else "?"]
	print("DEBUG 跳字 %s] list=%d" % [dbg, fx._jump_texts.size()])
	check(_count_children("JumpText") == 2, "同屏跳字 ≤2")
	var last_lbl: Label = null
	for c in fx.get_children():
		if String(c.name).begins_with("JumpText") and c.has_meta("label"):
			last_lbl = c.get_meta("label")
	check(last_lbl != null and last_lbl.text == "+7", "第 3 处并入最新（+3+4=+7）")
	await get_tree().create_timer(0.8).timeout

	print("== ④c 插旗落地/撤旗拔出 ==")
	var flag_coord: Vector2i = Vector2i(-1, -1)
	for c in g.cells:
		var cell: Cell = g.cells[c]
		if not cell.is_opened and not cell.is_mine and not cell.is_locked:
			flag_coord = c
			break
	check(flag_coord.x >= 0, "找到可插旗格")
	var icon: TextureRect = g.cells[flag_coord].get_node("SpecialIcon")
	var y0: float = icon.position.y
	g.cell_unflagged.connect(func(_c, _a): unflag_count += 1)
	print("DEBUG flag前 cell: locked=%s opened=%s forbidden=%s" % [
		g.cells[flag_coord].is_locked, g.cells[flag_coord].is_opened,
		GameState.is_action_forbidden("flag")])
	g.toggle_flag(flag_coord, "player")
	print("DEBUG flag后 flagged=%s" % g.cells[flag_coord].is_flagged)
	check(icon.position.y < y0 - 6.0, "插旗瞬间旗面在上方（下落起点）")
	check(_count_children("FlagDust") == 1, "插旗灰尘已生成")
	await get_tree().create_timer(0.3).timeout
	check(absf(icon.position.y - y0) < 0.01 and icon.scale == Vector2.ONE,
		"落地动画结束：位置/缩放精确复原")
	g.toggle_flag(flag_coord, "player")  # 撤旗
	check(unflag_count == 1, "撤旗发了 cell_unflagged 事件")
	check(_count_children("FlagPull") == 1, "撤旗拔出副本已生成")
	await get_tree().create_timer(0.3).timeout
	check(_count_children("FlagPull") == 0, "拔出副本消散")

	print("== ④d 卸货：跳字 + 飞币 + 金光 ==")
	g.cargo_unloaded.emit(g.coord_to_world(flag_coord), 20)
	await get_tree().process_frame
	print("DEBUG 卸货: glint=%d coin=%d hud_money组=%d" % [
		_count_children("GoldGlint"), _count_children("FlyCoin"),
		get_tree().get_nodes_in_group("hud_money").size()])
	check(_count_children("GoldGlint") == 1, "卸货金光生成")
	check(_count_children("FlyCoin") == 3, "3 枚飞币起飞（HUD 落点）")
	var found20 := false
	for c in fx.get_children():
		if String(c.name).begins_with("JumpText") and c.has_meta("label") \
				and c.get_meta("label").text == "+20":
			found20 = true
	check(found20, "卸货跳字 +20")
	await get_tree().create_timer(0.8).timeout
	check(_count_children("FlyCoin") == 0 and _count_children("GoldGlint") == 0,
		"飞币/金光消散")

	print("== 清理：重开新盘动效全清 ==")
	g.cargo_unloaded.emit(g.coord_to_world(flag_coord), 5)
	await get_tree().process_frame
	g.init_empty_grid()
	await get_tree().process_frame
	check(fx.get_child_count() == 0, "init_empty_grid 清空动效层")

	print("RESULT: %s" % ("ALL_PASS" if failures == 0 else "HAS_FAIL x%d" % failures))
	get_tree().quit(0 if failures == 0 else 1)
