extends SceneTree
## 3-1 蓄能光束冒烟测试（2026-10-17 持续激光改版垂直切片）
## 覆盖：关卡数据层（3-1/ch03 白名单）→ 点击分流（免CD不耗动作/双击兜底/空管拦截）
## → 束头逐格啃墙 → 机器人照射暂停+充电+计时冻结 → 筑墙工持续掉血 → 能量耗尽自动断束。
## 驱动方式：BeamLaser.set_process(false) 后同步直调 _tick_fire(0.25)——完全确定性，
## 不依赖真实鼠标（真光标/窗口焦点全不影响；与 hover 测试同套路）。
## 用法：Godot_console.exe --path . -s res://tmp/auto_beam_s1_test.gd（headless 可跑）

var step_no := 0
var fails: Array = []
var GS: Node
var main: Node
var g: Node
var bl: Node
var save_bak := ""


func _initialize() -> void:
	print("[BeamS1] USER_DATA=", OS.get_user_data_dir())
	change_scene_to_file("res://scenes/ui/BootLoading.tscn")
	call_deferred("_run")


func check(cond: bool, label: String) -> void:
	step_no += 1
	if cond:
		print("  [PASS] #%d %s" % [step_no, label])
	else:
		fails.append(label)
		print("  [FAIL] #%d %s" % [step_no, label])


func _sec(t: float) -> void:
	await create_timer(t, true).timeout


func _finish() -> void:
	var ud := OS.get_user_data_dir()
	if save_bak != "":
		var f := FileAccess.open(ud + "/save_data.json", FileAccess.WRITE)
		f.store_string(save_bak)
		f.close()
		print("[BeamS1] 存档已还原")
	var code := 0 if fails.is_empty() else 1
	print("[BeamS1] RESULT=%s FAILS=%d %s" % ["OK" if fails.is_empty() else "NG",
			fails.size(), str(fails)])
	quit(code)


func _run() -> void:
	await _sec(1.0)
	GS = root.get_node("/root/GameState")
	var LS = root.get_node("/root/LevelSystem")
	var ud := OS.get_user_data_dir()
	if FileAccess.file_exists(ud + "/save_data.json"):
		var f := FileAccess.open(ud + "/save_data.json", FileAccess.READ)
		save_bak = f.get_as_text()
		f.close()

	# ---- ① 关卡数据层 ----
	var lvl = LS.get_level("ch03_s01")
	check(lvl != null, "3-1 关卡存在")
	if lvl == null:
		_finish()
		return
	check(lvl.laser_beam_mode, "laser_beam_mode=true")
	check(lvl.laser_mode, "laser_mode=true（音乐/洞窟/碎钻口径复用）")
	check(lvl.fixed_base == LS.get_level("ch02_s02").fixed_base, "盘面=2-2 复制（同基地）")
	var ids: Array = []
	for ch in LS.get_implemented_chapters():
		ids.append(ch.id)
	check(ids.has("ch03"), "ch03 进实装白名单")

	# ---- ② 进关 ----
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline \
			and (root.get_node_or_null("Main") == null
				or root.get_node("Main").get_node_or_null("UILayer/TutorialGuide") == null):
		await _sec(0.1)
	main = root.get_node_or_null("Main")
	check(main != null, "Main 场景就绪")
	if main == null:
		_finish()
		return
	await _sec(0.5)
	main._start_level("ch03_s01")
	deadline = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		if GS.current_level_id == "ch03_s01" and main.grid != null \
				and main.grid.cells.size() > 0 and GS.game_active:
			break
		await _sec(0.2)
	g = main.grid
	bl = main.beam_laser
	if g == null or GS.current_level_id != "ch03_s01":
		check(false, "3-1 盘装载（id=%s）" % GS.current_level_id)
		_finish()
		return
	check(GS.game_active, "进局且 game_active")
	check(g.laser_beam_mode, "grid.laser_beam_mode=true")
	check(bl != null, "BeamLaser 就绪")
	if bl == null:
		_finish()
		return
	bl.set_process(false)  # 挂起真实帧驱动，全同步直调

	# ---- ③ 选向：ray[0] 已开（瞬间通过）、后方 ≥2 层未开墙（有得啃）----
	var base: Vector2i = GS.bases[0]
	var dir := Vector2i.ZERO
	var ray: Array = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		var r: Array = []
		for c in LaserGeometry.beam_cells(base, base + d * 128):
			if not g.cells.has(c):
				break
			r.append(c)
		if r.is_empty():
			continue
		var solid := 0
		for c in r:
			if not g.cells[c].is_opened:
				solid += 1
		if solid >= 2 and not g.cells[r[0]].is_opened:
			continue  # ray[0] 要是已开格（机器人站位兼瞬间通过验证）
		if solid >= 2:
			dir = d
			ray = r
			break
	check(dir != Vector2i.ZERO, "找到可用射线 dir=%s 长=%d" % [dir, ray.size()])
	if dir == Vector2i.ZERO:
		_finish()
		return
	var first_wall := Vector2i(-9, -9)
	for c in ray:
		if not g.cells[c].is_opened:
			first_wall = c
			break
	check(first_wall.x >= 0, "射线首面墙 %s" % first_wall)
	var target: Vector2i = ray[ray.size() - 1]

	# ---- ④ 点击分流：起束不吃动作；点射预览不被 laser_manager 画 ----
	var actions_before: int = GS.player_actions_used
	g._on_cell_left_clicked(g.cells[target])
	check(bl.firing, "点击分流起束")
	check(GS.player_actions_used == actions_before, "起束不耗动作")
	check(bl.ray.size() == ray.size() and bl.ray[0] == ray[0], "射线逐格一致")
	check(bl.head_idx == 0, "束头从基地邻格起")
	g._update_hover(Vector2(ray[2].x * g.cell_size + 14.0, ray[2].y * g.cell_size + 14.0))
	check(bl._hover_cell != null, "BeamLaser 收到悬停")
	check(not g._laser_preview.visible, "点射束预览被门控（不双画）")
	bl._release()
	check(not bl.firing, "松手断束")

	# ---- ④b 非八向斜线（指哪打哪）：基地+(4,2) 这类格必须真的在束线上 ----
	# （八向吸附回归：旧逻辑会把 (4,2) 吸附成水平，束永远到不了那一行）
	var knight := Vector2i(-9, -9)
	for off in [Vector2i(4, 2), Vector2i(-4, 2), Vector2i(4, -2), Vector2i(-4, -2),
			Vector2i(2, 4), Vector2i(-2, 4), Vector2i(2, -4), Vector2i(-2, -4),
			Vector2i(3, 1), Vector2i(-3, 1), Vector2i(3, -1), Vector2i(-3, -1)]:
		var kc: Vector2i = base + off
		if g.cells.has(kc):
			knight = kc
			break
	check(knight.x >= 0, "④b 找到非八向目标格 %s" % knight)
	if knight.x >= 0:
		g._on_cell_left_clicked(g.cells[knight])
		check(bl.firing, "④b 斜线起束")
		check(bl.ray.has(knight), "束线经过斜向目标格（不吸附八向）")
		bl._release()

	# ---- ⑤ CD 拦截态与双击兜底 ----
	for i in range(12):
		GS.consume_player_action()  # 5 免费 + 7 囤层全花光 → 拦截态
	check(GS.is_player_blocked(), "动作 CD 已进拦截态")
	g._on_cell_left_clicked(g.cells[target])
	check(bl.firing, "拦截态仍起束（能量才是唯一约束）")
	bl._release()
	g._on_cell_double_clicked(g.cells[target])
	check(bl.firing, "快速连点走双击路径也兜底起束")
	bl._release()
	bl.energy = 0.0
	g._on_cell_left_clicked(g.cells[target])
	check(not bl.firing, "空管不起束")
	bl.energy = bl.ENERGY_MAX

	# ---- ⑥ 束头逐格啃墙 ----
	g._on_cell_left_clicked(g.cells[target])
	check(bl.firing, "⑥ 起束啃墙")
	var iter := 0
	while iter < 40 and bl.firing and not g.cells[first_wall].is_opened:
		bl._tick_fire(0.25)
		iter += 1
	check(g.cells[first_wall].is_opened, "束头啃开首面墙（0.5s/层，迭代%d）" % iter)
	var opened_count := 0
	for c in ray:
		if g.cells[c].is_opened and c != base:
			opened_count += 1
	check(opened_count >= 2, "光路开格数≥2（含洪水连锁；%d）" % opened_count)
	bl._release()

	# ---- ⑦ 机器人照射：暂停 + 能量池（80 上限，0.5s 一记 +20，双速工作耗 10/s）----
	var rm = main.robot_manager
	var spot: Vector2i = ray[0]
	var r = rm.spawn_robot(spot, "opener", g, base)
	check(r != null, "光路口 spawn opener")
	if r == null:
		_finish()
		return
	r.coord = spot
	r.position = g.coord_to_world(spot)
	check(absf(r.beam_energy) < 0.001, "初始能量池为空")
	bl._robot_pip.clear()
	bl.energy = bl.ENERGY_MAX
	g._on_cell_left_clicked(g.cells[target])
	check(bl.firing, "照机器人起束")
	for i in range(5):  # 1.25s：两记整 pip（+40）+ 0.25s 零头
		if not bl.firing:
			break
		bl._tick_fire(0.25)
		r.coord = spot
		r.position = g.coord_to_world(spot)
	check(r.beam_charging, "照射中暂停标志置位")
	check(r.is_charged(), "充能后进入双速状态")
	check(absf(r.beam_energy - 40.0) < 0.001, "两记 pip +40（实际 %.0f）" % r.beam_energy)
	var acc: float = float(bl._robot_pip.get(r, -1.0))
	check(acc >= 0.0 and acc <= 0.26, "pip 账本余量 %.2fs（<0.26s）" % acc)
	var timer_before: float = r._tick_timer
	rm.tick_all(0.5, g)
	check(absf(r._tick_timer - timer_before) < 0.0001, "照住时作业计时冻结")
	bl._release()
	check(not r.beam_charging, "断束清除暂停标志")
	# 耗能：非照住状态每秒 -10（同步段无真实帧经过，手动驱动 _process 确定性成立）
	var e0: float = r.beam_energy
	r._process(1.0)
	check(absf(r.beam_energy - (e0 - 10.0)) < 0.001, "双速工作每秒耗 10 点")
	# 满池封顶：照 2s（4 记 +80）顶到上限，继续照不溢出
	bl.energy = bl.ENERGY_MAX
	g._on_cell_left_clicked(g.cells[target])
	for i in range(12):  # 3s：6 记 ×20 = 120 → 封顶 80
		if not bl.firing:
			break
		bl._tick_fire(0.25)
		r.coord = spot
		r.position = g.coord_to_world(spot)
	bl._release()
	check(absf(r.beam_energy - 80.0) < 0.001, "灌能封顶 80 不溢出（实际 %.0f）" % r.beam_energy)
	rm.remove_robot(r, "test_cleanup")

	# ---- ⑧ 筑墙工持续掉血（stub 注入，不依赖 12s 自然出怪）----
	# 自备射线：⑥⑦已把东路烧穿（束到盘缘秒断），另挑一条 ≥4 层未开墙的方向
	var dir2 := Vector2i.ZERO
	var ray2: Array = []
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 1),
			Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		var r2: Array = []
		for c in LaserGeometry.beam_cells(base, base + d * 128):
			if not g.cells.has(c):
				break
			r2.append(c)
		var solid2 := 0
		for c in r2:
			if not g.cells[c].is_opened:
				solid2 += 1
		if solid2 >= 4:
			dir2 = d
			ray2 = r2
			break
	check(dir2 != Vector2i.ZERO, "⑧ 备用射线 dir=%s 长=%d" % [dir2, ray2.size()])
	var real_em = bl.em
	var sb = StubBuilder.new()
	sb.coord = ray2[0] if not ray2.is_empty() else base
	bl.em = {"builders": [sb]}
	bl.energy = bl.ENERGY_MAX
	g._on_cell_left_clicked(g.cells[ray2[ray2.size() - 1]])
	for i in range(10):  # 2.5s → 每 0.5s 一伤 = 5 伤
		if not bl.firing:
			break
		bl._tick_fire(0.25)
	bl._release()
	check(sb.hits >= 4, "光路内筑墙工 2.5s 挨≥4伤（实际%d）" % sb.hits)
	bl.em = real_em

	# ---- ⑨ 能量耗尽自动断束 ----
	bl.energy = 12.0
	g._on_cell_left_clicked(g.cells[target])
	check(bl.firing, "低管（≥一层）可起束")
	for i in range(40):
		if not bl.firing:
			break
		bl._tick_fire(0.25)
	check(not bl.firing, "持续照射到能量耗尽自动断束")
	_finish()


## 鸭子类型桩：只实现 _irradiate 用到的面（is_alive/take_hit/coord）
class StubBuilder:
	var coord := Vector2i.ZERO
	var hits := 0

	func is_alive() -> bool:
		return true

	func take_hit(_by: String) -> void:
		hits += 1
