extends SceneTree
## 机器人出生演出（出厂反馈 A+B）GUI 实测 harness（2026-10-08）
## 真实路径：BootLoading → 主菜单 → 选关 → L4 → 放基地；
## 购买走 main._buy_and_spawn_robot 全链（扣钱/事件/演出），赠送走 _gift_start_robots。
## 断言：飞行期本体隐藏+RobotFly 存在 → 落地后可见+飞图清理 → 连买错开 → 重开清场无残留。
## 用法：Godot_console.exe --path . -s res://tmp/auto_spawn_fx_test.gd

const EVIDENCE := "E:/godot/扫雷/tmp/spawn_fx_evidence/"

var step_no := 0
var fails: Array = []
var notes: Array = []
var GS: Node


func _initialize() -> void:
	print("[SpawnFx] USER_DATA=", OS.get_user_data_dir())
	DisplayServer.window_set_position(Vector2i(-3000, 0))
	var vw: int = int(ProjectSettings.get_setting("display/window/size/viewport_width", 1024))
	var vh: int = int(ProjectSettings.get_setting("display/window/size/viewport_height", 768))
	DisplayServer.window_set_size(Vector2i(vw, vh))
	DisplayServer.window_set_title("出生演出实测 harness")
	DirAccess.make_dir_recursive_absolute(EVIDENCE)
	change_scene_to_file("res://scenes/ui/BootLoading.tscn")
	call_deferred("_run")


# ---------- 基础设施（抄 auto_playtest_territory.gd） ----------

func check(cond: bool, label: String) -> void:
	step_no += 1
	if cond:
		print("  [PASS] #%d %s" % [step_no, label])
	else:
		fails.append(label)
		print("  [FAIL] #%d %s" % [step_no, label])
	notes.append({"n": step_no, "ok": cond, "label": label})


func _sec(t: float) -> void:
	await create_timer(t, true).timeout


func _await_button(text_part: String, timeout_sec: float) -> Button:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var b := _find_button(text_part)
		if b != null:
			return b
		await _sec(0.1)
	return null


func _find_button(text_part: String) -> Button:
	for n in _walk(root, []):
		if n is Button and n.is_visible_in_tree() and text_part in n.text:
			return n
	return null


func _walk(node: Node, acc: Array) -> Array:
	acc.append(node)
	for c in node.get_children():
		_walk(c, acc)
	return acc


func _inject_click(screen_pos: Vector2) -> void:
	var pos: Vector2 = root.get_final_transform() * screen_pos
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	Input.parse_input_event(motion)
	await process_frame
	var ev := InputEventMouseButton.new()
	ev.position = pos
	ev.global_position = pos
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	var rel := ev.duplicate()
	rel.pressed = false
	Input.parse_input_event(rel)
	await process_frame


func _click_button(text_part: String) -> bool:
	var b := _find_button(text_part)
	if b == null:
		print("  [WARN] 找不到按钮：", text_part)
		return false
	var rect: Rect2 = b.get_global_rect()
	await _inject_click(rect.position + rect.size / 2.0)
	return true


func _shot(fname: String) -> void:
	if DisplayServer.get_name() == "headless":
		return  # 无渲染层：截图跳过（逻辑断言不受影响）
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(EVIDENCE + fname)
	print("  [SHOT] ", fname)


func _fly_count(fx: Node) -> int:
	var n := 0
	for c in fx.get_children():
		if str(c.name).begins_with("RobotFly"):
			n += 1
	return n


func _pick_base_cell(g) -> Vector2i:
	var fallback: Vector2i = Vector2i(-9, -9)
	for c in g.cells:
		var cell = g.cells[c]
		if cell.is_opened and not cell.is_webbed and not cell.is_locked:
			if fallback == Vector2i(-9, -9):
				fallback = c
			var all_in := true
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if not g.cells.has(c + o):
					all_in = false
			if all_in:
				return c
	return fallback


# ---------- 主流程 ----------

func _run() -> void:
	await _sec(1.0)
	var menu_btn = await _await_button("选择关卡", 30.0)
	check(menu_btn != null, "BootLoading 正常进主菜单")
	GS = root.get_node("/root/GameState")

	# 导航进 L4（固定盘，无教学门）
	check(await _click_button("选择关卡"), "点击「选择关卡」")
	await _sec(0.5)
	var card4 = await _await_button("04", 5.0)
	if card4 != null:
		var r4: Rect2 = card4.get_global_rect()
		await _inject_click(r4.position + r4.size / 2.0)
	check(await _click_button("本关"), "点击「开始本关」")
	await _sec(0.5)
	var prec = await _await_button("开始挖矿", 3.0)
	if prec != null:
		check(await _click_button("开始挖矿"), "点击「开始挖矿」")
	await _sec(0.8)

	var main: Node = root.get_node("Main")
	var g = main.grid if main != null else null
	var rm = main.robot_manager
	check(g != null and g.cells.size() > 0, "L4 固定盘已装载")
	if g == null:
		_finish()
		return
	var fx: Node = g.get_node_or_null("EffectsLayer")
	check(fx != null, "EffectsLayer 存在")

	# 放基地
	var base_coord := _pick_base_cell(g)
	await _inject_click(g.cells[base_coord].global_position)
	check(GS.game_active, "放基地后对局激活（base=%s）" % str(base_coord))
	# 真实存档可能有「局外赠机」在放基地瞬间落位并起飞（错开 0.18s/台），
	# 不等落定会撞进阶段 1/2 的飞行统计窗口（2026-10-08 实测 4 项假失败的根源）
	await _sec(2.5)

	# ---- 阶段 1：单买全链（扣钱→基地亮→飞图→落地弹入扬尘） ----
	GS.add_money(1000, "test")
	var money0: int = GS.money
	var robots0: int = rm.robots.size()
	check(main._buy_and_spawn_robot("opener"), "购买 opener 成功")
	await _sec(0.12)  # 飞行中段（飞行 0.30s）
	var robot1 = rm.robots[rm.robots.size() - 1]
	check(rm.robots.size() == robots0 + 1, "机器人数 +1")
	check(not robot1.visible, "飞行期本体隐藏")
	check(_fly_count(fx) >= 1, "飞行图标 RobotFly 在场（%d）" % _fly_count(fx))
	await _shot("01-mid-flight.png")
	await _sec(1.2)
	check(robot1.visible, "落地后本体可见")
	check(_fly_count(fx) == 0, "飞图已清理（%d）" % _fly_count(fx))
	check(GS.money < money0, "购买扣了钱（%d → %d）" % [money0, GS.money])
	await _shot("02-landed.png")

	# ---- 阶段 2：连买 3 台（错开/预算） ----
	var before3: int = rm.robots.size()
	var money3: int = GS.money
	for t in ["opener", "marker", "opener"]:
		check(main._buy_and_spawn_robot(t), "连买 %s 成功" % t)
	# 同帧检查（购买为同步调用，不 await）：三台 0.30s 飞行必然都在场；
	# 中途 await 会因机器负载让首台落地、统计窗抖动（2026-10-08 实测）
	var flying_mid: int = 0
	var hidden_mid: int = 0
	for r in rm.robots:
		if not r.visible:
			hidden_mid += 1
	flying_mid = _fly_count(fx)
	check(hidden_mid >= 2, "连买飞行期多台隐藏（hidden=%d）" % hidden_mid)
	check(flying_mid >= 2, "多枚飞图同屏（fly=%d）" % flying_mid)
	await _shot("03-multi-mid-flight.png")
	await _sec(3.0)
	var all_visible := true
	for r in rm.robots:
		if not r.visible:
			all_visible = false
	check(rm.robots.size() == before3 + 3, "连买后总数 +3（%d）" % rm.robots.size())
	check(all_visible, "3 秒后全部落地可见")
	check(_fly_count(fx) == 0, "飞图全部清理")

	# ---- 阶段 3：开局赠送（同格+错开退化路径） ----
	var before_g: int = rm.robots.size()
	main._gift_start_robots({"opener": 1, "marker": 1})
	await _sec(0.25)
	var gift_hidden: int = 0
	for r in rm.robots:
		if not r.visible:
			gift_hidden += 1
	check(rm.robots.size() == before_g + 2, "赠送 2 台落位")
	check(gift_hidden >= 1, "赠送错开期至少 1 台隐藏（%d）" % gift_hidden)
	await _shot("04-gift-stagger.png")
	await _sec(2.5)
	var gift_all_visible := true
	for r in rm.robots:
		if not r.visible:
			gift_all_visible = false
	check(gift_all_visible, "赠送全部落地可见")

	# ---- 阶段 3.5：进账浮字（+N 合并 / 淡出清理 / 支出不弹） ----
	rm.remove_all()  # 清掉自动干活的机器人，避免其开格收入污染合并断言
	await _sec(0.3)
	var hud_node: Control = main.hud
	GS.add_money(50, "test")
	await process_frame
	await process_frame
	var popup: Label = hud_node.get_node_or_null("MoneyGainPopup")
	if popup != null:
		print("  [DIAG] popup.position=", popup.position,
			" global_rect=", popup.get_global_rect(),
			" visible_in_tree=", popup.is_visible_in_tree(),
			" modulate=", popup.modulate,
			" money_label.global_rect=", hud_node.money_label.get_global_rect(),
			" font_size=", popup.get_theme_font_size("font_size"))
	check(popup != null and popup.text == "+50", "进账弹 +50 浮字（%s）" % (popup.text if popup else "无"))
	await _shot("06-gain-popup.png")
	GS.add_money(30, "test")
	await _sec(0.08)
	check(popup != null and is_instance_valid(popup) and popup.text == "+80",
			"窗口内连续进账合并为 +80（实际 %s）" % (popup.text if is_instance_valid(popup) else "失效"))
	await _sec(0.9)
	var popup2: Label = hud_node.get_node_or_null("MoneyGainPopup")
	check(popup2 == null, "0.55s 淡出后浮字已清理")
	GS.add_money(-60, "test")
	await _sec(0.1)
	var popup3: Label = hud_node.get_node_or_null("MoneyGainPopup")
	check(popup3 == null, "支出不弹进账浮字")

	# ---- 阶段 4：重开清场（飞行中切关，回调不得迟到触发/报错） ----
	main._buy_and_spawn_robot("opener")
	await _sec(0.05)
	check(_fly_count(fx) >= 1, "重开前一台在飞行中")
	fx.clear_all()
	rm.remove_all()
	check(rm.robots.size() == 0, "remove_all 清空机器人")
	await _sec(1.5)
	check(_fly_count(fx) == 0, "清场后无飞图残留（%d）" % _fly_count(fx))
	await _shot("05-after-clear.png")

	_finish()


func _finish() -> void:
	var total_ok := 0
	for n in notes:
		if n.ok:
			total_ok += 1
	var summary := {
		"date": "2026-10-08",
		"total": notes.size(),
		"passed": total_ok,
		"failed": fails.size(),
		"fails": fails,
		"assertions": notes,
	}
	var f := FileAccess.open(EVIDENCE + "assertions.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(summary, "  "))
	f.close()
	print("")
	print("=== 出生演出实测结果：%d/%d 通过 ===" % [total_ok, notes.size()])
	if not fails.is_empty():
		print("=== FAILED %d 项: %s ===" % [fails.size(), ", ".join(fails)])
	quit(0 if fails.is_empty() else 1)
