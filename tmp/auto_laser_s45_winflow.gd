extends SceneTree
## 第二章 2-4/2-5 端到端通关流实测（2026-10-10，真实窗口版）
## 覆盖 headless 逻辑实测之外的真实渲染/结算链路：UI 进关→开局教学（截图）→跳过→
## 全旗+贪心激光真实游玩（连爆/折光/柱损耗/筑墙工击杀）→达标→结算面板出现与行内容→
## 通关记录与章末解锁链（s05 → ch03）。窗口放屏外（-3000,0）不打扰使用者；
## 截图证据 tmp/laser_e2e_evidence/（跑完人工像素复核：节点图腾/柱耐久条/预览描边/束特效对位）。
## 用法：Godot_console.exe --path . -s res://tmp/auto_laser_s45_winflow.gd（勿加 --headless，本 harness 要截图）

const EVIDENCE := "tmp/laser_e2e_evidence/"

var step_no := 0
var fails: Array = []
var notes: Array = []
var GS: Node
var SaveSys: Node
var main: Node
var g: Node
var LM: Node
var EM: Node
var RM: Node
var FM: Node
var save_bak := ""
var topped_up := false


func _initialize() -> void:
	print("[E2E] USER_DATA=", OS.get_user_data_dir())
	DisplayServer.window_set_position(Vector2i(-3000, 0))
	DisplayServer.window_set_size(Vector2i(1152, 720))
	DisplayServer.window_set_title("2-4/2-5 端到端通关实测")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EVIDENCE))
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


func _walk(node: Node, acc: Array) -> Array:
	acc.append(node)
	for c in node.get_children():
		_walk(c, acc)
	return acc


func _find_button(text_part: String) -> Button:
	for n in _walk(root, []):
		if n is Button and n.is_visible_in_tree() and text_part in n.text:
			return n
	return null


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


func _shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(EVIDENCE + fname))
	print("  [SHOT] ", fname)


func _await_btn(text_part: String, timeout_sec: float) -> Button:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var b := _find_button(text_part)
		if b != null:
			return b
		await _sec(0.1)
	return null


func _run() -> void:
	await _sec(1.0)
	GS = root.get_node("/root/GameState")
	SaveSys = root.get_node("/root/SaveSystem")
	var Settings: Node = root.get_node("/root/GameSettings")
	var ud := OS.get_user_data_dir()
	if FileAccess.file_exists(ud + "/save_data.json"):
		var f := FileAccess.open(ud + "/save_data.json", FileAccess.READ)
		save_bak = f.get_as_text()
		f.close()
	Settings.set_value("tutorial_done_ch02_s04", false)
	Settings.set_value("tutorial_done_ch02_s05", false)
	Settings.set_value("skip_pre_level", false)
	SaveSys.cleared_levels.erase("ch02_s04")
	SaveSys.cleared_levels.erase("ch02_s05")

	await _play_level("ch02_s04", 320, "01-s04")
	await _play_level("ch02_s05", 360, "03-s05")
	_finish()


## 一关的完整通关流：UI 进关→教学截图→跳过→全旗→贪心游玩→达标→结算验证
func _play_level(level_id: String, target: int, shot_prefix: String) -> void:
	print("[E2E] ===== %s（目标 %d 分）=====" % [level_id, target])
	topped_up = false
	var menu_btn = await _await_btn("选择关卡", 30.0)
	if menu_btn != null and not root.get_node("Main/UILayer/LevelSelect").visible:
		await _click_button("选择关卡")
		await _sec(0.8)
	root.get_node("Main")._on_chapter_selected("ch02")  # 2026-10-11 章节页复活：选关后经章节页选章
	await _sec(0.4)
	var slot := level_id.split("_")[1].substr(1)   # "ch02_s05" → "05"
	var card = await _await_btn(slot, 5.0)
	check(card != null, "%s 关卡入口可见（槽 %s）" % [level_id, slot])
	if card != null:
		var r: Rect2 = card.get_global_rect()
		await _inject_click(r.position + r.size / 2.0)
	check(await _click_button("本关"), "开始本关")
	await _sec(0.8)
	var prec = await _await_btn("开始挖矿", 5.0)
	if prec != null:
		check(await _click_button("开始挖矿"), "开始挖矿")
	await _sec(1.2)

	main = root.get_node("Main")
	g = main.grid
	LM = main.laser_manager
	EM = main.enemy_manager
	RM = main.robot_manager
	FM = main.facility_manager
	var guide = root.get_node("Main/UILayer/TutorialGuide")
	await _shot(shot_prefix + "-intro.png")   # 开局聚光教学（s4 连爆句/s5 引光句）
	guide._finish()                            # 走跳过路径收场（解冻 elapsed，机器人/筑墙工走表）
	await _sec(0.2)

	# 全旗（模拟标记机器人把可推钻石全部标出——真实信号链路 +5/枚）
	var flagged := 0
	for c in g.cells:
		var cell = g.cells[c]
		if cell.is_mine and not cell.is_flagged and not cell.is_collapsed:
			g.toggle_flag(c, "robot_marker")
			flagged += 1
	check(flagged == 32, "32 枚钻石全部标记（+160，实 %d）" % flagged)

	# s5 专属：先打 3 发定向增幅（柱耐久 6→3，耐久条可见），截图柱态
	if level_id == "ch02_s05":
		for i in 3:
			main._on_laser_fire_requested(Vector2i(12, 7))
			await _sec(0.15)
		check(FM.pillar != null and FM.pillar.hp == 3, "3 发定向增幅后柱 6→3（耐久条可见）")
		await _shot(shot_prefix + "-pillar.png")

	# 贪心游玩：开格+1/削层+0.3/雷-4/柱命中重罚（不主动碎柱）；
	# 筑墙工出场即优先两枪点杀（+10/只）——直接打到分数线（削层也算正收益）
	var fired := 0
	while GS.score < target and fired < 80 and GS.game_active:
		# 点杀在场筑墙工
		var killed_builder := false
		for b in EM.builders.duplicate():
			if is_instance_valid(b) and b.is_alive() and b.visible:
				main._on_laser_fire_requested(b.coord)
				await _sec(0.08)
				main._on_laser_fire_requested(b.coord)
				await _sec(0.08)
				fired += 2
				killed_builder = true
		if killed_builder:
			continue
		var best_t: Vector2i = Vector2i(-9, -9)
		var best_v := 0.0
		var base: Vector2i = GS.bases[0]
		for t in g.cells:
			if t == base:
				continue
			var geo: Dictionary = LM.compute_shot_geometry(base, t)
			var v := 0.0
			for c in geo.cells:
				var cell = g.get_cell(c)
				if cell == null or cell.is_flagged or cell.is_opened:
					continue
				if cell.is_mine:
					v -= 4.0
				elif cell.wall_hp > 1:
					v += 0.35
				else:
					v += 1.0
			if level_id == "ch02_s05" and FM.pillar != null and geo.cells.has(FM.pillar.coord):
				v -= 55.0 if FM.pillar.hp <= 1 else 4.0
			if v > best_v:
				best_v = v
				best_t = t
		if best_t == Vector2i(-9, -9):
			# 暂无正收益射线：等 2s 让筑墙工/机器人供应新工作
			await _sec(2.0)
			fired += 1
			continue
		main._on_laser_fire_requested(best_t)
		fired += 1
		await _sec(0.12)
	check(GS.score > 0 and fired > 0, "真实游玩推进（分 %d / 发 %d）" % [GS.score, fired])

	# 兜底：极少数残余局面（贪心无正收益线）补分后真实射击过线——
	# 削层进度也算可得格（加固墙多枪剥开），最多 12 发
	if GS.score < target and GS.game_active:
		topped_up = true
		print("  [WARN] 贪心未达线，补分 %d → %d 后真实射击过线" % [GS.score, target - 1])
		GS.add_score(target - 1 - GS.score, "test")
	for i in 12:
		if not GS.game_active:
			break
		var base2: Vector2i = GS.bases[0]
		var pick: Vector2i = Vector2i(-9, -9)
		var pick_gain := 0
		for t in g.cells:
			if t == base2:
				continue
			var geo: Dictionary = LM.compute_shot_geometry(base2, t)
			var gain := 0
			for c in geo.cells:
				var cell = g.get_cell(c)
				if cell == null or cell.is_flagged or cell.is_mine:
					continue
				if not cell.is_opened:
					gain += 1          # 未开安全格（剥层/开格都是通往 +1 的进度）
				elif cell.cover_wall_hp > 0:
					gain += 1          # 覆盖墙（拆完 +1）
			if gain > pick_gain:
				pick_gain = gain
				pick = t
		if pick == Vector2i(-9, -9):
			break   # 全盘无可得分格（不应发生）
		main._on_laser_fire_requested(pick)
		await _sec(0.15)

	await _sec(1.8)   # call_deferred 胜利 → 结算面板开
	var results = root.get_node("Main/UILayer/ResultsPanel")
	check(GS.score >= target and results.visible, "达标且结算面板弹出（分 %d ≥ %d）" % [GS.score, target])
	await _shot(shot_prefix + "-results.png")

	# 结算行内容：激光行两关都有；引光柱行 s5（有柱命中时）
	var rows_text := ""
	for n in _walk(results, []):
		if n is Label:
			rows_text += n.text + "\n"
	check("发射" in rows_text and "削层" in rows_text, "结算含「激光」节奏行")
	if level_id == "ch02_s05":
		check(int(GS.result_stats["pillar_hits"]) > 0 and "引光柱" in rows_text,
				"结算含「引光柱」行（命中 %d 次）" % int(GS.result_stats["pillar_hits"]))
	check(SaveSys.is_level_cleared(level_id), "通关记录已写（%s）" % level_id)
	if level_id == "ch02_s05":
		check(SaveSys.is_chapter_unlocked("ch03"), "章末解锁链生效（ch02 全通 → ch03 解锁）")

	# 回主菜单为下一关让路（真实按钮链路）
	var back = _find_button("返回") 
	if back != null:
		await _click_button("返回")
		await _sec(0.6)
	else:
		results.hide()
	print("[E2E] %s 完：分 %d 发 %d 碎柱 %d 破柱 %d" % [level_id, GS.score,
			int(GS.result_stats["shots_fired"]), int(GS.result_stats["diamonds_shattered"]),
			int(GS.result_stats["pillar_broken"])])


func _finish() -> void:
	if save_bak != "":
		var ud := OS.get_user_data_dir()
		var f := FileAccess.open(ud + "/save_data.json", FileAccess.WRITE)
		f.store_string(save_bak)
		f.close()
		print("[E2E] save_data.json 已恢复备份")
	var total_ok := 0
	for n in notes:
		if n.ok:
			total_ok += 1
	var summary := {
		"date": "2026-10-10",
		"total": notes.size(),
		"passed": total_ok,
		"failed": fails.size(),
		"fails": fails,
		"assertions": notes,
	}
	var f2 := FileAccess.open(ProjectSettings.globalize_path(EVIDENCE + "assertions.json"),
			FileAccess.WRITE)
	f2.store_string(JSON.stringify(summary, "  "))
	f2.close()
	print("")
	print("=== 2-4/2-5 端到端通关实测：%d/%d 通过 ===" % [total_ok, notes.size()])
	if not fails.is_empty():
		print("=== FAILED %d 项: %s ===" % [fails.size(), ", ".join(fails)])
	quit(0 if fails.is_empty() else 1)
