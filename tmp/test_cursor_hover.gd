extends Node
## 冒烟：像素光标注册素材可载 + can_place_at/can_place_first_base 判定 + 悬停覆盖层状态机

var main
var g: Grid
var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		push_error("FAIL: " + msg)
		failures += 1


func _ready() -> void:
	await get_tree().process_frame
	var ps: PackedScene = load("res://scenes/Main.tscn")
	main = ps.instantiate()
	get_parent().add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	# splash 由自身计时器隐藏，测试直接关掉（否则 _in_game() 恒 false）
	main.get_node("UILayer/SplashScreen").hide()
	main.get_node("UILayer/PreLevelCard").hide()
	g = main.grid

	print("== 光标素材（main._ready 已注册，无报错即链路通） ==")
	check(load("res://visual_v2/runtime/fx/cursor_arrow.png") != null, "cursor_arrow 可加载")
	check(load("res://visual_v2/runtime/fx/cursor_placing.png") != null, "cursor_placing 可加载")

	print("== 首基地悬停（随机盘 ch02_s01） ==")
	main._start_level("ch02_s01")
	await get_tree().process_frame
	check(GameState.game_phase == "placing_base", "ch02_s01 放基地阶段")
	var c0: Vector2i = Vector2i(5, 5)
	check(g.can_place_first_base(c0), "随机盘首基地：关闭格可放")
	check(not g.can_place_first_base(Vector2i(-1, -1)), "越界格不可放")
	main._on_grid_cell_hovered(g.cells[c0])
	check(g._hover_overlay.visible and g._hover_overlay.texture == g._hover_tex["valid"],
		"首基地悬停显示合法角框")
	main._on_grid_cell_unhovered(g.cells[c0])
	check(not g._hover_overlay.visible, "移出后隐藏")

	print("== 放基地进入对局，can_place_at 判定 ==")
	check(main._try_place_first_base_at(g.coord_to_world(c0)), "放置首个基地")
	check(GameState.game_active, "对局激活")

	GameState.add_money(2000)
	var free_opened: Vector2i = Vector2i(-1, -1)
	var occupied_opened: Vector2i = Vector2i(-1, -1)
	var closed: Vector2i = Vector2i(-1, -1)
	for c in g.cells:
		var cell: Cell = g.cells[c]
		if not cell.is_opened and closed.x < 0:
			closed = c
		elif cell.is_opened and not cell.is_base:
			if free_opened.x < 0:
				free_opened = c
			elif occupied_opened.x < 0:
				occupied_opened = c
	check(free_opened.x >= 0 and occupied_opened.x >= 0, "安全区至少两个已开空格")
	main.robot_manager.spawn_robot(occupied_opened, "opener", g)

	main.placing_mode = "opener"
	check(main.can_place_at(free_opened), "opener：已开空格合法")
	check(not main.can_place_at(occupied_opened), "一格一机：占用格非法")
	check(not main.can_place_at(closed), "未开岩壁非法（is_walkable）")
	GameState.money = 1
	check(not main.can_place_at(free_opened), "钱不够非法（与 purchase_robot 口径一致）")
	GameState.add_money(2000)

	main.placing_mode = "base"
	check(main.can_place_at(free_opened), "基地：已开非基地格合法")
	main.placing_mode = "probe"
	check(main.can_place_at(closed), "L4 探测：未开格也合法（仅排除已确认雷）")
	main.placing_mode = ""

	print("== 悬停处理器状态机 ==")
	main.placing_mode = "opener"
	main._on_grid_cell_hovered(g.cells[closed])
	check(g._hover_overlay.texture == g._hover_tex["invalid"], "放置悬停未开格→红叉")
	main._on_grid_cell_hovered(g.cells[free_opened])
	check(g._hover_overlay.texture == g._hover_tex["valid"], "放置悬停空格→绿框")
	main.placing_mode = ""
	main._on_grid_cell_hovered(g.cells[closed])
	check(g._hover_overlay.texture == g._hover_tex["normal"], "普通悬停未开岩壁→低亮四角")
	main._on_grid_cell_hovered(g.cells[free_opened])
	check(not g._hover_overlay.visible, "普通悬停已开格→不显示（读数字不加干扰）")

	print("== 暂停/恢复清预览 ==")
	main._on_grid_cell_hovered(g.cells[closed])
	main._open_pause()
	check(not g._hover_overlay.visible and get_tree().paused, "暂停时清预览")
	main._resume()
	check(not g._hover_overlay.visible, "恢复后无残影")

	print("== 真实点击链路走 can_place_at ==")
	GameState.add_money(2000)
	main.placing_mode = "opener"
	check(main._try_place_at(g.coord_to_world(free_opened)), "点击空格放置成功")
	check(main.placing_mode == "", "放置后退出放置模式")
	check(not g._hover_overlay.visible, "退出放置模式清预览")

	print("RESULT: %s" % ("ALL_PASS" if failures == 0 else "HAS_FAIL x%d" % failures))
	get_tree().quit(0 if failures == 0 else 1)
