extends SceneTree
## 改版机制层 scratch 实测（WP2 特殊矿石 + WP4 过载机器人，2026-10-10 后端测试）
## 载体盘：ch02_s02（激光关·无矿石/过载/折光/节点——机制全部手工布置，隔离验证）。
## 断言组：
##   矿石：装载+足迹占格 / 束止于足迹（不穿透）/ 触发判定只认束格 /
##         爆发形状（3 互异八向 ×≤3 步，剔足迹，边界内）/ seed 决定论对拍 /
##         爆发格开墙 + 旗格免疫 + 爆发格充能 opener（拍板 #8）/
##         无限次触发（连打两轮仍存活）/ 埋点 ore_bursts
##   过载：注册链（价格 100 / s2 商店隐藏 / 基地出厂直购）/ 13 格精确形状（盘边裁切）/
##         束止于机器人 + 爆炸开墙 + 碎钻 + 覆盖墙削层 + 旗格免疫 /
##         爆炸格充能 opener（拍板 #8）/ 爆后存活 / 埋点 overload_blasts /
##         无级联（爆炸格盖矿石足迹不触发矿石，D3）
##   巡逻：手动 tick 30 拍全在已开空格（含足迹/基地排除）
## 用法：Godot_console.exe --path . --headless -s res://tmp/auto_ore_overload_mech_test.gd

const EVIDENCE := "tmp/ore_overload_mech_evidence/"

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


func _initialize() -> void:
	print("[Mech] USER_DATA=", OS.get_user_data_dir())
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


func _await_btn(text_part: String, timeout_sec: float) -> Button:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var b := _find_button(text_part)
		if b != null:
			return b
		await _sec(0.1)
	return null


func _fire(target: Vector2i) -> void:
	main._on_laser_fire_requested(target)


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
	Settings.set_value("tutorial_done_ch02_s02", false)
	Settings.set_value("skip_pre_level", false)
	SaveSys.cleared_levels.erase("ch02_s02")

	var menu_btn = await _await_btn("选择关卡", 30.0)
	check(menu_btn != null, "BootLoading 正常进主菜单")
	await _click_button("选择关卡")
	await _sec(0.8)
	root.get_node("Main")._on_chapter_selected("ch02")  # 2026-10-11 章节页复活：选关后经章节页选章
	await _sec(0.5)
	var card = await _await_btn("02", 5.0)
	check(card != null, "2-2 关卡入口可见")
	if card != null:
		var r: Rect2 = card.get_global_rect()
		await _inject_click(r.position + r.size / 2.0)
	check(await _click_button("本关"), "开始本关")
	await _sec(0.8)
	var prec = await _await_btn("开始挖矿", 5.0)
	if prec != null:
		check(await _click_button("开始挖矿"), "开始挖矿")
	await _sec(1.0)

	main = root.get_node("Main")
	g = main.grid
	LM = main.laser_manager
	EM = main.enemy_manager
	RM = main.robot_manager
	FM = main.facility_manager
	if g == null or g.cells.size() == 0 or GS.current_level_id != "ch02_s02":
		check(false, "ch02_s02 固定盘装载（id=%s）" % GS.current_level_id)
		_finish()
		return
	RM.remove_all()  # 确定性隔离：撤开局赠机（opener/marker 走位会污染束/爆发格）
	await _phase1_ore_geometry()
	await _phase2_ore_resolution()
	await _phase3_overload()
	await _phase4_cascade_guard()
	await _phase5_patrol()
	_finish()


# ---- 阶段 1：矿石装载 / 束止 / 触发判定 / 爆发形状 ----
func _phase1_ore_geometry() -> void:
	print("[Phase1] 矿石几何")
	var base: Vector2i = GS.bases[0]
	check(base == Vector2i(1, 7), "固定基地 (1,7)")
	FM.setup_ores(g, [{"origin": Vector2i(6, 6)}])
	check(FM.ores.size() == 1, "矿石装载 1 块")
	var foot: Array = FM.ores[0].footprint()
	check(foot == [Vector2i(6, 6), Vector2i(7, 6), Vector2i(6, 7), Vector2i(7, 7)],
			"足迹 2×2（%s）" % str(foot))
	var occupied := true
	for c in foot:
		if not g.facility_cells.has(c) or g.is_walkable(c):
			occupied = false
	check(occupied, "足迹占格生效（不可走）")
	check(FM.ore_at(Vector2i(7, 7)) == FM.ores[0] and FM.ore_at(Vector2i(5, 5)) == null,
			"ore_at 足迹命中查询")
	# 束止：沿第 7 行向东，束应在首个足迹格 (6,7) 截停，(7,7) 不在束集
	var geo: Dictionary = LM.compute_shot_geometry(base, Vector2i(10, 7))
	check(geo.main[geo.main.size() - 1] == Vector2i(6, 7), "束止于首个足迹格 (6,7)")
	check(not geo.main.has(Vector2i(7, 7)), "束不穿透矿石")
	check(geo.ores.size() == 1, "束踩足迹 → 矿石入触发集")
	var marks_ok: bool = geo.ore_marks.size() == 4
	for c in foot:
		if not geo.ore_marks.has(c):
			marks_ok = false
	check(marks_ok, "ore_marks = 完整足迹（预览描边数据源）")
	# 未踩足迹不触发：第 1 列向上打
	var geo2: Dictionary = LM.compute_shot_geometry(base, Vector2i(1, 3))
	check(geo2.ores.is_empty() and geo2.ore_cells.is_empty(), "束不踩足迹 → 不触发")
	# 爆发形状：3 互异八向（互异=两两 ≥45°>30°），每向 ≤3 步；剔足迹；界内
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261010
	var shape_ok := true
	var dist_ok := true
	for i in 5:
		var cells: Array = FM.ores[0].burst_cells(g, rng)
		if cells.size() < 3 or cells.size() > 18:
			shape_ok = false
		for c in cells:
			if foot.has(c) or not g.cells.has(c):
				shape_ok = false
			if maxi(absi(c.x - 6), absi(c.y - 6)) > 4:
				dist_ok = false
	check(shape_ok, "爆发形状界内/剔足迹/格数 3~18（5 轮抽样）")
	check(dist_ok, "爆发格距足迹原点切比雪夫 ≤4（≤3 步出射）")
	# 方向互异验证：同 seed 两次调用结果一致（rng 决定论 → 结算对拍的前提）
	var r1 := RandomNumberGenerator.new()
	r1.seed = 777
	var r2 := RandomNumberGenerator.new()
	r2.seed = 777
	check(FM.ores[0].burst_cells(g, r1) == FM.ores[0].burst_cells(g, r2),
			"同 seed 爆发格集一致（决定论）")


# ---- 阶段 2：矿石结算（决定论对拍：开墙/旗格/充能/无限次/埋点） ----
func _phase2_ore_resolution() -> void:
	print("[Phase2] 矿石结算")
	var ore = FM.ores[0]
	# 选 seed：期望集含 ≥1 已开格（充能样本）+ ≥2 未开非雷格（旗格/开墙样本）
	var seed_used := 0
	var expected: Array = []
	var opened_cell := Vector2i(-9, -9)
	var wall_a := Vector2i(-9, -9)  # 将插旗
	var wall_b := Vector2i(-9, -9)  # 期望被开
	while seed_used < 5000:
		seed_used += 1
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_used
		expected = ore.burst_cells(g, rng)
		opened_cell = Vector2i(-9, -9)
		wall_a = Vector2i(-9, -9)
		wall_b = Vector2i(-9, -9)
		for c in expected:
			var cc = g.cells[c]
			if cc.is_mine or cc.is_flagged:
				continue
			if cc.is_opened and opened_cell == Vector2i(-9, -9):
				opened_cell = c
			elif not cc.is_opened:
				if wall_a == Vector2i(-9, -9):
					wall_a = c
				elif wall_b == Vector2i(-9, -9):
					wall_b = c
		if opened_cell != Vector2i(-9, -9) and wall_a != Vector2i(-9, -9) \
				and wall_b != Vector2i(-9, -9):
			break
	check(opened_cell != Vector2i(-9, -9) and wall_a != Vector2i(-9, -9),
			"找到可用 seed=%d（含已开/未开样本）" % seed_used)
	if opened_cell == Vector2i(-9, -9) or wall_a == Vector2i(-9, -9):
		return
	var wall_b_in_set: bool = wall_b != Vector2i(-9, -9)
	# 充能样本：opener 站爆发格内的已开格（不在束行 y=7 上——充能必来自爆发格）
	var opener = null
	if opened_cell.y != 7:
		opener = RM.spawn_robot(opened_cell, "opener", g)
	g.toggle_flag(wall_a, "test")
	var bursts0: int = int(GS.result_stats["ore_bursts"])
	LM.burst_rng.seed = seed_used  # 与期望集同源 → 结算对拍
	_fire(Vector2i(10, 7))
	check(int(GS.result_stats["ore_bursts"]) == bursts0 + 1, "ore_bursts 埋点 +1")
	check(g.cells[wall_a].is_flagged and not g.cells[wall_a].is_opened,
			"旗格免疫：爆发向旗格不结算（%s）" % str(wall_a))
	if wall_b_in_set:
		check(g.cells[wall_b].is_opened, "爆发格开墙（%s）" % str(wall_b))
	if opener != null and is_instance_valid(opener):
		check(opener.is_charged(), "爆发格充能 opener（拍板 #8）")
	# 无限次：换 seed 再打一轮，矿石仍存活
	LM.burst_rng.seed = seed_used + 1000
	_fire(Vector2i(10, 7))
	check(int(GS.result_stats["ore_bursts"]) == bursts0 + 2, "二次触发照常结算")
	check(FM.ores.size() == 1 and is_instance_valid(FM.ores[0]) \
			and FM.ore_at(Vector2i(6, 6)) != null, "矿石不可破坏仍存活（无限次）")
	g.toggle_flag(wall_a, "test")  # 收尾撤旗（若已被开则 toggle 自然无效）
	RM.remove_all()


# ---- 阶段 3：过载注册 / 形状 / 爆炸结算 / 存活 ----
func _phase3_overload() -> void:
	print("[Phase3] 过载机器人")
	check(GS.get_robot_price("overload") == 100, "价格 100（拍板 #9）")
	check(not main.shop.buy_overload_button.visible, "s2 商店不开放过载（extra 未开闸）")
	GS.add_money(200)
	var bought: bool = main._buy_and_spawn_robot("overload")
	check(bought, "直购直出（基地出厂，拍板 #10）")
	var bought_list: Array = RM.robots.filter(func(r): return r.robot_type == "overload")
	check(bought_list.size() == 1, "出厂 1 台 OverloadRobot")
	check(GS.overload_count == 1, "计数入册（限购阶梯数据源）")
	RM.remove_all()
	# 13 格精确形状（盘心无裁切）：手工布置 (4,5)
	var r3 = RM.spawn_robot(Vector2i(4, 5), "overload", g)
	var expect: Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			expect.append(Vector2i(4 + dx, 5 + dy))
	for e in [Vector2i(6, 5), Vector2i(2, 5), Vector2i(4, 3), Vector2i(4, 7)]:
		expect.append(e)
	var got: Array = r3.blast_cells(g)
	expect.sort()
	got.sort()
	check(got == expect and got.size() == 13, "爆炸 13 格 = 3×3+四正各 1（拍板 #6）")
	# 盘边裁切：x=1 时西向延伸出盘 → 12 格
	var r4 = RM.spawn_robot(Vector2i(1, 4), "overload", g)
	check(r4.blast_cells(g).size() == 12, "盘边裁切（西向延伸格剔除）")
	RM.remove_all()
	# 爆炸结算：过载站 (1,3)，束沿第 1 列北上截停；3×3+延伸覆盖顶部墙带
	var r5 = RM.spawn_robot(Vector2i(1, 3), "overload", g)
	g.get_cell(Vector2i(3, 3)).place_cover_wall(2)  # 覆盖墙样本（延伸格内·已开地面）
	g.toggle_flag(Vector2i(1, 2), "test")           # 旗格样本（3×3 内未开墙）
	var opener2 = RM.spawn_robot(Vector2i(2, 3), "opener", g)  # 爆炸格充能样本（不在束列）
	var blasts0: int = int(GS.result_stats["overload_blasts"])
	var shatter0: int = int(GS.result_stats["diamonds_shattered"])
	var geo: Dictionary = LM.compute_shot_geometry(Vector2i(1, 7), Vector2i(1, 1))
	check(geo.main[geo.main.size() - 1] == Vector2i(1, 3), "束止于过载机器人")
	var blast5: Array = r5.blast_cells(g)
	var overlap5 := 0
	for b in blast5:
		if geo.main.has(b):
			overlap5 += 1
	check(geo.overloads.size() == 1
			and geo.overload_cells.size() == blast5.size() - overlap5,
			"过载入触发集 + 爆炸格=blast去束重叠（%d-%d）" % [blast5.size(), overlap5])
	_fire(Vector2i(1, 1))
	check(int(GS.result_stats["overload_blasts"]) == blasts0 + 1, "overload_blasts 埋点 +1")
	check(g.cells[Vector2i(0, 2)].is_opened and g.cells[Vector2i(1, 1)].is_opened,
			"爆炸开墙（(0,2)(1,1) 单层墙）")
	check(g.cells[Vector2i(2, 2)].is_collapsed, "爆炸碎钻（(2,2) 雷 → 坍塌）")
	check(int(GS.result_stats["diamonds_shattered"]) == shatter0 + 1, "碎钻埋点 +1")
	check(g.get_cell(Vector2i(3, 3)).cover_wall_hp == 1, "爆炸削覆盖墙 1 层（连爆语义）")
	check(g.cells[Vector2i(1, 2)].is_flagged and not g.cells[Vector2i(1, 2)].is_opened,
			"旗格免疫：爆炸向旗格不结算")
	if opener2 != null and is_instance_valid(opener2):
		check(opener2.is_charged(), "爆炸格充能 opener（拍板 #8）")
	check(is_instance_valid(r5) and RM.robots.has(r5), "爆后存活（拍板 #7 非一次性）")
	RM.remove_all()


# ---- 阶段 4：无级联（爆炸格盖矿石足迹 ≠ 触发，D3） ----
func _phase4_cascade_guard() -> void:
	print("[Phase4] 无级联")
	var r = RM.spawn_robot(Vector2i(5, 5), "overload", g)  # 3×3 盖住矿石足迹 (6,6)
	var geo: Dictionary = LM.compute_shot_geometry(Vector2i(1, 7), Vector2i(5, 5))
	check(geo.overloads.size() == 1, "束命中过载 → 爆炸展开")
	check(geo.ores.is_empty() and geo.ore_cells.is_empty(),
			"爆炸格盖足迹不触发矿石（无级联，D3）")
	var bursts0: int = int(GS.result_stats["ore_bursts"])
	_fire(Vector2i(5, 5))
	check(int(GS.result_stats["ore_bursts"]) == bursts0, "结算后矿石未被波及触发")
	RM.remove_all()


# ---- 阶段 5：巡逻域合法性（手动 tick，绕开 2.2s 计时） ----
func _phase5_patrol() -> void:
	print("[Phase5] 巡逻")
	var r = RM.spawn_robot(Vector2i(4, 5), "overload", g)
	var visited: Dictionary = {Vector2i(4, 5): true}
	var legal := true
	for i in 30:
		r.do_tick(g, {})
		visited[r.coord] = true
		var cc = g.cells.get(r.coord)
		if cc == null or not cc.is_opened or cc.is_base or g.facility_cells.has(r.coord):
			legal = false
	check(legal, "30 拍全在已开空格（剔基地/设施/未开）")
	check(visited.size() > 1, "确有移动（%d 个不同格）" % visited.size())
	check(not r.is_idle(), "永不算空闲（不触发停摆误报）")


func _finish() -> void:
	if save_bak != "":
		var ud := OS.get_user_data_dir()
		var f := FileAccess.open(ud + "/save_data.json", FileAccess.WRITE)
		f.store_string(save_bak)
		f.close()
		print("[Mech] save_data.json 已恢复备份")
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
	print("=== 改版机制层实测结果：%d/%d 通过 ===" % [total_ok, notes.size()])
	if not fails.is_empty():
		print("=== FAILED %d 项: %s ===" % [fails.size(), ", ".join(fails)])
	quit(0 if fails.is_empty() else 1)
