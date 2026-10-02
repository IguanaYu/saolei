extends Node
## 冒烟：开区扩散波纹（逻辑瞬时 / 视觉延迟）
## ① 固定盘预开（ch01_s01，大片 preopen）② 随机盘放基地安全区（ch02_s01）
## ③ 玩家连锁 open_cell + 波纹岩屑
## 每条路径验：当帧逻辑已开且视觉保持岩壁 → 波纹后翻成洞底、scale 复位

var main
var g: Grid
var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		push_error("FAIL: " + msg)
		failures += 1


func _wall_on(cell) -> bool:
	return cell.get_node("WallTex").visible


func _floor_on(cell) -> bool:
	return cell.get_node("FloorTex").visible


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

	# ---- ① 固定盘预开波纹 ----
	print("== ① 固定盘 ch01_s01 预开 ==")
	main._start_level("ch01_s01")
	await get_tree().process_frame
	main.get_node("UILayer/PreLevelCard").hide()
	var opened_a: Array = []
	for c in g.cells:
		var cell: Cell = g.cells[c]
		if cell.is_opened and not cell.is_base:
			opened_a.append(cell)
	check(opened_a.size() > 30, "固定盘预开区非空: %d 格" % opened_a.size())
	var pending_n := 0
	var wall_ok := true
	for cell in opened_a:
		if cell._reveal_pending:
			pending_n += 1
			if not _wall_on(cell):
				wall_ok = false
	check(pending_n > opened_a.size() * 0.5, "过半预开格处于波纹待翻态: %d/%d" % [pending_n, opened_a.size()])
	check(wall_ok, "待翻格视觉保持岩壁")
	await get_tree().create_timer(1.6).timeout
	var revealed_n := 0
	var scale_ok := true
	for cell in opened_a:
		if not cell._reveal_pending and _floor_on(cell) and not _wall_on(cell):
			revealed_n += 1
		if not cell.scale.is_equal_approx(Vector2.ONE):
			scale_ok = false
	check(revealed_n == opened_a.size(), "波纹结束：预开格全部翻成洞底: %d/%d" % [revealed_n, opened_a.size()])
	check(scale_ok, "波纹结束：scale 全部复位")

	# ---- ② 随机盘放基地安全区波纹 ----
	print("== ② 随机盘 ch02_s01 放基地安全区 ==")
	main._start_level("ch02_s01")
	await get_tree().process_frame
	main._try_place_first_base_at(g.coord_to_world(Vector2i(5, 5)))
	var safe_n := 0
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, -1)]:
		var cell: Cell = g.get_cell(Vector2i(5, 5) + d)
		if cell != null and cell.is_opened:
			safe_n += 1
	check(safe_n == 5, "安全区逻辑瞬时已开: 5/5 (实际 %d)" % safe_n)
	var base_cell: Cell = g.get_cell(Vector2i(5, 5))
	check(base_cell.is_base and _floor_on(base_cell), "基地立即显示（波纹中心）")
	var ring_pending := 0
	for d in [Vector2i(2, 0), Vector2i(0, 2), Vector2i(1, 1)]:
		var cell: Cell = g.get_cell(Vector2i(5, 5) + d)
		if cell != null and cell._reveal_pending:
			ring_pending += 1
	check(ring_pending > 0, "外围格波纹待翻: %d" % ring_pending)
	await get_tree().create_timer(0.8).timeout
	var safe_revealed := 0
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var cell: Cell = g.get_cell(Vector2i(5 + dx, 5 + dy))
			if cell != null and cell.is_opened and not cell.is_base and not cell._reveal_pending:
				safe_revealed += 1
	check(safe_revealed >= 8, "安全区波纹全部翻完: %d 格" % safe_revealed)

	# ---- ③ 玩家连锁波纹 ----
	print("== ③ 玩家连锁 open_cell ==")
	var zero: Vector2i = Vector2i(-1, -1)
	for c in g.cells:
		var cell: Cell = g.cells[c]
		if not cell.is_opened and not cell.is_flagged and not cell.is_mine \
				and cell.adjacent_mines == 0 and not cell.is_locked:
			zero = c
			break
	check(zero.x >= 0, "找到未开零格 %s" % zero)
	var before := g.count_safe_remaining()
	var batch: Array = []
	# lambda 按值捕获局部变量：必须改数组内容（append），不能重新赋值绑定
	var batch_fn := func(_s, _a, chain): batch.append_array(chain)
	g.cell_open_batch.connect(batch_fn)
	g.open_cell(zero, "player")
	g.cell_open_batch.disconnect(batch_fn)
	var after := g.count_safe_remaining()
	check(after < before, "连锁逻辑当帧结算（安全余格 %d→%d）" % [before, after])
	check(batch.size() > 1, "连锁批次格数: %d" % batch.size())
	var chain_pending := 0
	for cb in batch:
		if cb._reveal_pending:
			chain_pending += 1
	check(chain_pending > batch.size() * 0.3, "连锁格波纹待翻: %d/%d" % [chain_pending, batch.size()])
	# 波前推进中：中段时刻岩屑已随波弹出
	await get_tree().create_timer(0.2).timeout
	var shard_n := 0
	for c in g._fx.get_children():
		if String(c.name).begins_with("Shard"):
			shard_n += 1
	check(shard_n > 0, "波纹岩屑随波前弹出: %d 粒" % shard_n)
	await get_tree().create_timer(1.4).timeout
	var chain_done := 0
	for cb in batch:
		if is_instance_valid(cb) and not cb._reveal_pending and _floor_on(cb):
			chain_done += 1
	check(chain_done == batch.size(), "连锁波纹全部翻完: %d/%d" % [chain_done, batch.size()])

	print("")
	print("== ALL PASS ==" if failures == 0 else "== FAILURES: %d ==" % failures)
	get_tree().quit(failures)
