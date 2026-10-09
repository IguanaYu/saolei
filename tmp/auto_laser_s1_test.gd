extends SceneTree
## 第二章 2-1「激光开矿」逻辑实测 harness（2026-10-09，后端测试）
## 真实路径：BootLoading → 主菜单 → 选关（切 ch02）→ 关前卡 → 进 ch02_s01。
## 走 main._on_laser_fire_requested 全链（CD 消耗+发射+结算+埋点）。
## 断言组：盘装载 / 标记防刷 / 直射开格 / 三层墙三枪 / 旗格保护穿射 /
##          碎钻不扣命 / 空射扣动作 / 基地格不发射 / CD 拦截与回充 / 达标延迟结算 / 重开清场。
## 用法：Godot_console.exe --path . -s res://tmp/auto_laser_s1_test.gd

const EVIDENCE := "E:/godot/扫雷/tmp/laser_s1_evidence/"

var step_no := 0
var fails: Array = []
var notes: Array = []
var GS: Node
var SaveSys: Node
var Settings: Node
var main: Node
var g: Node
var LM: Node
var save_bak := ""


func _initialize() -> void:
	print("[LaserS1] USER_DATA=", OS.get_user_data_dir())
	DisplayServer.window_set_position(Vector2i(-3000, 0))
	DisplayServer.window_set_size(Vector2i(1024, 768))
	DisplayServer.window_set_title("2-1 激光关逻辑实测")
	DirAccess.make_dir_recursive_absolute(EVIDENCE)
	change_scene_to_file("res://scenes/ui/BootLoading.tscn")
	call_deferred("_run")


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


func _click_button(text_part: String) -> bool:
	var b := _find_button(text_part)
	if b == null:
		print("  [WARN] 找不到按钮：", text_part)
		return false
	var rect: Rect2 = b.get_global_rect()
	await _inject_click(rect.position + rect.size / 2.0)
	return true


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


func FixedBoards_preopen() -> Array:
	var fb = load("res://scripts/data/fixed_boards.gd")
	return fb.CH2_S1.preopen


func _shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(EVIDENCE + fname)
	print("  [SHOT] ", fname)


## 格中心裁剪 ×6 放大（像素验证用：角标/裂纹等小元素）
func _shot_cell(coord: Vector2i, fname: String) -> void:
	await RenderingServer.frame_post_draw
	var cell = g.cells.get(coord)
	if cell == null:
		return
	var c_pos: Vector2 = cell.global_position
	var img := root.get_texture().get_image()
	# 画布坐标 → 帧缓冲像素（工程开了拉伸：canvas 1365 宽 vs 窗口 1024，须换算）
	var sc: Vector2 = Vector2(img.get_width(), img.get_height()) / root.get_visible_rect().size
	var rect := Rect2i(int(c_pos.x * sc.x) - 24, int(c_pos.y * sc.y) - 24, 48, 48)
	rect = rect.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	var crop := img.get_region(rect)
	crop.resize(crop.get_width() * 6, crop.get_height() * 6, Image.INTERPOLATE_NEAREST)
	crop.save_png(EVIDENCE + fname)
	print("  [SHOT] ", fname, " cell ", coord)


# ---------- 主流程 ----------

func _run() -> void:
	await _sec(1.0)
	GS = root.get_node("/root/GameState")
	SaveSys = root.get_node("/root/SaveSystem")
	Settings = root.get_node("/root/GameSettings")
	# user:// 存档备份（测试轮协议：跑前备份/跑后恢复，避免污染真实进度）
	var ud := OS.get_user_data_dir()
	if FileAccess.file_exists(ud + "/save_data.json"):
		var f := FileAccess.open(ud + "/save_data.json", FileAccess.READ)
		save_bak = f.get_as_text()
		f.close()
	Settings.set_value("tutorial_done_ch02_s01", false)

	var menu_btn = await _await_button("选择关卡", 30.0)
	check(menu_btn != null, "BootLoading 正常进主菜单")
	check(await _click_button("选择关卡"), "点击「选择关卡」")
	await _sec(0.8)
	# 现场转储：可见按钮清单（导航断位排查用）
	var btn_texts: Array = []
	for n in _walk(root, []):
		if n is Button and n.is_visible_in_tree():
			btn_texts.append(n.text.substr(0, 14).replace("
", "|"))
	print("  [DEBUG] 可见按钮: ", " / ".join(btn_texts))
	# 切第二章（逻辑直调 set_chapter，章节切换 UI 不在本次断言范围）
	var level_select: Node = root.get_node("Main/UILayer/LevelSelect")
	check(level_select != null, "选关页存在")
	level_select.set_chapter("ch02")
	await _sec(0.5)
	var btn2: Array = []
	for n in _walk(root, []):
		if n is Button and n.is_visible_in_tree():
			btn2.append(n.text.substr(0, 12).replace("
", "|"))
	print("  [DEBUG] ch02 后可见按钮: ", " / ".join(btn2))
	var card1 = await _await_button("2-1", 5.0)
	if card1 == null:
		card1 = await _await_button("01", 3.0)
	check(card1 != null, "第二章 2-1 关卡入口可见")
	if card1 != null:
		var r: Rect2 = card1.get_global_rect()
		await _inject_click(r.position + r.size / 2.0)
	check(await _click_button("本关"), "点击「开始本关」")
	await _sec(0.5)
	var prec = await _await_button("开始挖矿", 3.0)
	if prec != null:
		check(await _click_button("开始挖矿"), "点击「开始挖矿」")
	await _sec(1.0)

	main = root.get_node("Main")
	g = main.grid
	LM = main.laser_manager
	if g == null or g.cells.size() == 0:
		check(false, "ch02_s01 固定盘已装载")
		_finish()
		return
	await _phase1_board()
	await _phase2_shooting()
	await _phase3_cd_and_win()
	await _phase4_restart()
	_finish()


# ---- 阶段 1：盘装载与引导 ----
func _phase1_board() -> void:
	print("[Phase1] 盘装载")
	# 确定性隔离：移除赠送机器人（教学播完后机器人会下场开格/插旗，搅动后续断言；
	# opener 削层与激光同走 open_cell 入口，多层墙语义已由三枪断言覆盖）
	main.robot_manager.remove_all()
	check(g.cells.size() == 144, "12×12=144 格（%d）" % g.cells.size())
	check(g.laser_mode, "laser_mode 已启用")
	check(GS.current_level_id == "ch02_s01", "关卡 id=ch02_s01")
	var mines := 0
	for c in g.cells:
		if g.cells[c].is_mine:
			mines += 1
	check(mines == 18, "18 枚钻石（%d）" % mines)
	var opened := 0
	var opened_list: Array = []
	for c in g.cells:
		if g.cells[c].is_opened:
			opened += 1
			opened_list.append(c)
	check(opened == 40, "预开 40 格（%d）" % opened)
	if opened != 40:
		var preopen_set: Dictionary = {}
		for c in FixedBoards_preopen():
			preopen_set[c] = true
		var extras: Array = []
		for c in opened_list:
			if not preopen_set.has(c):
				extras.append(c)
		print("  [DEBUG] 多开的格: ", extras)
	check(GS.bases.size() == 1 and GS.bases[0] == Vector2i(1, 6), "固定基地 (1,6)")
	check(int(g.cells[Vector2i(6, 6)].wall_hp) == 3, "加固墙 (6,6) hp=3")
	check(int(g.cells[Vector2i(7, 6)].wall_hp) == 1, "普通未开墙 (7,6) hp=1")
	print("  [DEBUG] hp(6,6)=", g.cells[Vector2i(6, 6)].wall_hp,
			" hp(7,6)=", g.cells[Vector2i(7, 6)].wall_hp,
			" opened(6,6)=", g.cells[Vector2i(6, 6)].is_opened,
			" opened(7,6)=", g.cells[Vector2i(7, 6)].is_opened,
			" walls#=", main._walls_applied_count() if main.has_method("_walls_applied_count") else "n/a")
	check(int(g.cells[Vector2i(2, 6)].wall_hp) == 0, "预开格 wall_hp=0")
	check(GS.lives == 0 and not GS.has_life_limit(), "无命关（HUD 心形应隐藏）")
	check(LM != null and LM.is_laser_level(), "LaserManager 就位")
	check(root.get_node("Main/Ch02S1Director") != null, "2-1 剧本控制器在场")
	check(root.get_node("Main/UILayer/TutorialGuide").visible, "教学首播（开局聚光）")
	# 标记链照旧 + 防刷（远离射线的钻石 (2,3)）
	g.toggle_flag(Vector2i(2, 3), "player")
	check(g.cells[Vector2i(2, 3)].is_flagged, "右键标记照旧（插旗成功）")
	check(g.rewarded_flags.has(Vector2i(2, 3)), "正确旗入防刷表（+5 已发）")
	check(int(GS.score_breakdown.get("flag", 0)) == 5, "正确标记 +5 分")
	g.toggle_flag(Vector2i(2, 3), "player")   # 撤
	g.toggle_flag(Vector2i(2, 3), "player")   # 重插
	check(int(GS.score_breakdown.get("flag", 0)) == 5, "撤旗重插不刷分（仍 5）")
	g.toggle_flag(Vector2i(2, 3), "player")   # 收尾撤掉，别挡后续射线
	await _shot("01-board.png")
	print("  [DEBUG] (6,6) global=", g.cells[Vector2i(6, 6)].global_position,
			" (2,6) global=", g.cells[Vector2i(2, 6)].global_position,
			" viewport=", root.get_visible_rect().size)
	await _shot_cell(Vector2i(6, 6), "01b-wall-badge.png")   # 加固墙角标像素验证
	await _shot_cell(Vector2i(2, 6), "01c-preopen-cell.png")  # 对照：预开格应亮


# ---- 阶段 2：射击语义 ----
func _phase2_shooting() -> void:
	print("[Phase2] 射击语义")
	# A: 直射开安全格（45° 教学线，线上无钻石）
	var score0 := int(GS.score)
	main._on_laser_fire_requested(Vector2i(4, 3))
	check(g.cells[Vector2i(4, 3)].is_opened, "直射打开安全格 (4,3)")
	check(int(GS.score) > score0, "开格加分（%d → %d）" % [score0, GS.score])
	check(int(GS.result_stats["shots_fired"]) == 1, "shots_fired=1")
	# B: 三层墙三枪（干净行 y=6 至 (6,6)：线上全是预开格+墙）
	main._on_laser_fire_requested(Vector2i(6, 6))
	check(int(g.cells[Vector2i(6, 6)].wall_hp) == 2, "第一枪 3→2（不露内容）")
	check(not g.cells[Vector2i(6, 6)].is_opened, "削层后仍未开")
	main._on_laser_fire_requested(Vector2i(6, 6))
	check(int(g.cells[Vector2i(6, 6)].wall_hp) == 1, "第二枪 2→1")
	main._on_laser_fire_requested(Vector2i(6, 6))
	check(g.cells[Vector2i(6, 6)].is_opened, "第三枪破墙开格")
	check(int(GS.result_stats["layers_peeled"]) == 2, "layers_peeled=2")
	await _shot("02-wall-3shots.png")
	# C: 旗格保护 + 光束穿续（标 (7,6) 钻石后，穿它射线打开后方）
	g.toggle_flag(Vector2i(7, 6), "player")
	var wall76_flagged: bool = g.cells[Vector2i(7, 6)].is_flagged
	main._on_laser_fire_requested(Vector2i(8, 6))
	check(wall76_flagged and g.cells[Vector2i(7, 6)].is_flagged \
			and not g.cells[Vector2i(7, 6)].is_collapsed, "旗格被激光保护（未碎）")
	check(g.cells[Vector2i(8, 6)].is_opened, "光束穿过旗格打开后方 (8,6)")
	# D: 碎钻（未标钻石 (10,6) 被打碎：+1 分 0 金不扣命不结束）
	var shatter0: int = int(GS.result_stats["diamonds_shattered"])
	var score_d := int(GS.score)
	main._on_laser_fire_requested(Vector2i(10, 6))
	check(g.cells[Vector2i(10, 6)].is_collapsed, "未标钻石被打碎（坍塌=已处理）")
	check(int(GS.result_stats["diamonds_shattered"]) == shatter0 + 1, "碎钻计数 +1")
	check(int(GS.score_breakdown.get("shatter", 0)) == 1, "碎钻来源账目 =1 分")
	check(int(GS.score) == score_d + 2, "碎钻束总收益 +2（碎钻 1 + 同束开格 1，实际 +%d）" % (int(GS.score) - score_d))
	check(GS.game_active and GS.lives == 0, "碎钻不扣命不结束（无命关仍活）")
	check(int(GS.result_stats["shots_fired"]) == 6, "shots_fired=6（累计）")
	await _shot("03-shatter.png")
	# E: 空射扣动作（点已开格）
	var used0: int = GS.player_actions_used
	var s_e := int(GS.score)
	main._on_laser_fire_requested(Vector2i(2, 6))
	check(GS.player_actions_used == used0 + 1, "空射照扣 1 动作")
	check(int(GS.score) == s_e, "空射不加分")
	# F: 基地格自身不发射
	var used_f: int = GS.player_actions_used
	var shots_f: int = int(GS.result_stats["shots_fired"])
	main._on_laser_fire_requested(Vector2i(1, 6))
	check(GS.player_actions_used == used_f and int(GS.result_stats["shots_fired"]) == shots_f,
			"点基地格不发射不扣动作")


# ---- 阶段 3：CD 拦截 / 回充 / 达标延迟结算 ----
func _phase3_cd_and_win() -> void:
	print("[Phase3] CD 与达标")
	# 已用动作：5 免费（A/B×3/C/D/E）→ 已进 cooldown；阶段 2 末共 7 消耗（含 F 前的 6+空射 1）
	check(GS.cd_phase == "cooldown", "免费 5 次耗尽进入 cooldown（%s）" % GS.cd_phase)
	check(GS.is_player_blocked(), "囤层空时发射被拦")
	var shots_before: int = int(GS.result_stats["shots_fired"])
	g._on_cell_left_clicked(g.cells[Vector2i(11, 6)])
	check(int(GS.result_stats["shots_fired"]) == shots_before, "被拦时不发射")
	check(GS.cd_charges == 0, "囤层 0")
	GS.tick_cd(3.0)
	check(GS.cd_charges == 1, "3s 回充 1 层")
	check(not GS.is_player_blocked(), "有囤层可发射")
	g._on_cell_left_clicked(g.cells[Vector2i(11, 6)])   # 真实点击路径（含 CD 消耗）
	check(g.cells[Vector2i(11, 6)].is_opened, "点击路径发射成功（(11,6) 已开）")
	# 达标延迟：把分推到 140 线上一次性跨越（走真实 add_score + 射击收尾）
	GS.add_score(140 - int(GS.score) - 2, "open")   # 留 2 分给最后一枪的开格
	check(GS.game_active, "未达线不结算")
	main._on_laser_fire_requested(Vector2i(11, 7))
	check(int(GS.score) >= 140, "跨线（%d 分）" % int(GS.score))
	check(GS.game_active, "射击同帧不结算（deferred 等整轮完成）")
	await _sec(0.3)   # 过一帧让 call_deferred 落地
	check(not GS.game_active, "整轮完成后达标结算（win）")
	check(root.get_node("Main/UILayer/ResultsPanel").visible, "结算面板弹出")
	check(float(GS.result_stats["crossing_elapsed"]) > -0.5, "过线时点已埋点（非 -1 默认）")
	await _shot("04-results.png")


# ---- 阶段 4：重开清场 ----
func _phase4_restart() -> void:
	print("[Phase4] 重开")
	var results: Node = root.get_node("Main/UILayer/ResultsPanel")
	var restart_btn: Button = _find_button("再来一次")
	if restart_btn == null:
		restart_btn = _find_button("重玩")
	if restart_btn != null:
		var r: Rect2 = restart_btn.get_global_rect()
		await _inject_click(r.position + r.size / 2.0)
	else:
		main._on_restart_requested()
	await _sec(1.2)
	check(GS.score == 0 and GS.game_active, "重开后新局激活清分")
	check(g.cells.size() == 144 and int(g.cells[Vector2i(6, 6)].wall_hp) == 3,
			"盘面重建：加固墙回 3 层")
	check(not g.cells[Vector2i(4, 3)].is_opened, "已开格复位")
	check(g.rewarded_flags.is_empty(), "防刷表清空")
	var fx: Node = g.get_node_or_null("EffectsLayer")
	var leftovers := 0
	for c in fx.get_children():
		if str(c.name).begins_with("LaserBeam"):
			leftovers += 1
	check(leftovers == 0, "光束视觉无残留（%d）" % leftovers)
	check(not g.get_node("LaserPreview").visible, "激光预览隐藏")
	check(int(GS.result_stats["shots_fired"]) == 0, "埋点清零")
	await _shot("05-restarted.png")


func _finish() -> void:
	# 存档恢复（测试轮协议）
	if save_bak != "":
		var ud := OS.get_user_data_dir()
		var f := FileAccess.open(ud + "/save_data.json", FileAccess.WRITE)
		f.store_string(save_bak)
		f.close()
		print("[LaserS1] save_data.json 已恢复备份")
	var total_ok := 0
	for n in notes:
		if n.ok:
			total_ok += 1
	var summary := {
		"date": "2026-10-09",
		"total": notes.size(),
		"passed": total_ok,
		"failed": fails.size(),
		"fails": fails,
		"assertions": notes,
	}
	var f2 := FileAccess.open(EVIDENCE + "assertions.json", FileAccess.WRITE)
	f2.store_string(JSON.stringify(summary, "  "))
	f2.close()
	print("")
	print("=== 2-1 激光关实测结果：%d/%d 通过 ===" % [total_ok, notes.size()])
	if not fails.is_empty():
		print("=== FAILED %d 项: %s ===" % [fails.size(), ", ".join(fails)])
	quit(0 if fails.is_empty() else 1)
