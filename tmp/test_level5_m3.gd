extends Node
## L5 Boss 关 M3 验收（P2 炸弹+火区闭环）：转场后落弹调度/引信遮罩/点击反弹/
## 漏接爆炸成十字火/机器人禁入+震退/火烧黏液/灭火整片/自然退散
## 用法：Godot_console.exe --path . --headless res://tmp/test_level5_m3.tscn

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


func _run() -> void:
	await get_tree().process_frame
	var ps: PackedScene = load("res://scenes/Main.tscn")
	main = ps.instantiate()
	get_parent().add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	g = main.grid

	print("== 起关 → 直进 P2（拔 6 颗牙） ==")
	main._start_level("ch01_s05")
	await get_tree().process_frame
	var base_coord: Vector2i = FixedBoards.L5.preopen[0]
	main._try_place_first_base_at(g.coord_to_world(base_coord))
	var mines: Array = FixedBoards.L5.mines.duplicate()
	var teeth := 0
	for m in mines:
		if teeth >= 6:
			break
		g.toggle_flag(m, "robot_marker")
		teeth = g.count_processed_mines()
	check(main.boss_manager.phase == 2, "第 6 颗牙转 P2")

	print("== 落弹调度 + 遮罩 ==")
	await pump(8, main)   # 转场暂停 3s + first 5s → 首弹已落（阴影→引信）
	var bombs_now: Array = main.boss_manager.bombs
	check(bombs_now.size() >= 1, "首颗落弹在场（%d）" % bombs_now.size())
	var bomb = bombs_now[0]
	check(bomb.state == "fuse", "已过阴影期进入引信")
	var bcell = g.get_cell(bomb.coord)
	check(bcell != null and bcell.bomb_masked, "落格已遮罩（bomb_masked）")

	print("== 点击反弹（设计 §5.2） ==")
	var money0: int = GameState.money
	check(main._try_hit_enemy_at(g.coord_to_world(bomb.coord)), "点击炸弹命中")
	await get_tree().create_timer(0.8).timeout   # 反弹飞行 0.5s 落 Boss（奖励/埋点在落点结算）
	check(GameState.result_stats["bombs_deflected"] == 1, "反弹埋点 +1")
	check(GameState.money == money0 + 15, "反弹奖励 +15 钱")
	var next_bomb_at: float = 0.0
	for a in main.boss_manager._attacks.get(2, []):
		if a["kind"] == "bomb":
			next_bomb_at = float(a["next"])
	check(next_bomb_at > main.boss_manager._elapsed + 6.0, "下次落弹顺延 ≥7s（%.1f > %.1f+6）"
			% [next_bomb_at, main.boss_manager._elapsed])
	check(bcell.bomb_masked == false, "反弹后遮罩解除")

	print("== 漏接爆炸 → 十字火区 ==")
	# 直接构造一台机器人 + 一格黏液在火区里，验证震退/烧黏液（确定性优于等随机落点）
	var p: Vector2i = FixedBoards.L5.preopen[10]
	var robot = main.robot_manager.spawn_robot(p, "opener", g)
	var q: Vector2i = p + Vector2i(1, 0) if g.get_cell(p + Vector2i(1, 0)) != null \
			and g.get_cell(p + Vector2i(1, 0)).is_opened else p
	if q != p:
		check(g.get_cell(q).apply_slime(), "预置黏液")
	main.boss_manager.ignite_fire_cross(p)
	check(g.get_cell(p).is_on_fire, "中心格着火")
	check(not g.is_walkable(p), "火区机器人禁入（is_walkable=false）")
	check(robot.coord != p, "区内机器人被震退（%s）" % str(robot.coord))
	if q != p:
		check(not g.get_cell(q).is_slimed, "火清黏液（覆盖格黏液被烧）")

	print("== 灭火：点一格整片熄灭 ==")
	var money1: int = GameState.money
	main._on_fire_extinguish_requested(p)
	check(not g.get_cell(p).is_on_fire, "点击火格整片熄灭")
	check(g.get_cell(p).path_blockers == 0, "通路恢复（path_blockers=0）")
	check(GameState.money == money1 + 5, "灭火奖励 +5 钱")
	check(GameState.result_stats["fires_extinguished"] == 1, "灭火埋点 +1")

	print("== 自然退散（8s） ==")
	var r: Vector2i = FixedBoards.L5.preopen[20]
	main.boss_manager.ignite_fire_cross(r)
	check(g.get_cell(r).is_on_fire, "第二片火点燃")
	await pump(9, main)
	check(main.boss_manager.fire_cells.is_empty(), "8s 自然退散（登记表空）")
	check(not g.get_cell(r).is_on_fire, "格子火状态清除")

	print("== 引信走完自动爆炸（真实链路） ==")
	# 快进到下一颗弹（顺延后的 next），放任引信走完（shadow 1.2 + fuse 5）
	var waited := 0
	while main.boss_manager.fire_cells.is_empty() and waited < 40:
		await pump(2, main)
		waited += 2
	check(main.boss_manager.fire_cells.size() > 0, "漏接炸弹爆炸成火区（火 %d 格）"
			% main.boss_manager.fire_cells.size())

	print("")
	if fails.is_empty():
		print("=== ALL PASS ===")
	else:
		print("=== FAILED %d 项: %s ===" % [fails.size(), ", ".join(fails)])
	get_tree().quit(0 if fails.is_empty() else 1)


func _ready() -> void:
	_run()
