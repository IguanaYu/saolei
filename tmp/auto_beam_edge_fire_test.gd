extends SceneTree
## 3-1 蓄能光束·盘缘起束回归（2026-10-18 用户复报「指到边缘位置左键没法释放」）
## 根因两条：
##   ① 点击全靠逐格 Area2D 拾取，鼠标滑出盘缘没有任何格子接事件 → 起束请求整个丢失
##      （修复：Grid._unhandled_input 盘外坐标兜底发 laser_beam_pressed）
##   ② 射线沿途全已开（无墙体）时，束头一帧内走完直接出盘 → 旧代码静默 _release，
##      玩家看到的就是点了没反应（修复：束头到盘缘钉住继续照，不自动断束）
## 驱动方式：BeamLaser.set_process(false) 后同步直调；盘外事件直接调 _unhandled_input，
## 事件坐标用 get_canvas_transform() 正向换算（与处理函数互逆，headless 全确定性）。
## 用法：Godot_console.exe --path . -s res://tmp/auto_beam_edge_fire_test.gd（headless 可跑）

var step_no := 0
var fails: Array = []
var GS: Node
var main: Node
var g: Node
var bl: Node
var save_bak := ""
var emit_count := 0


func _initialize() -> void:
	print("[BeamEdge] USER_DATA=", OS.get_user_data_dir())
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
		print("[BeamEdge] 存档已还原")
	var code := 0 if fails.is_empty() else 1
	print("[BeamEdge] RESULT=%s FAILS=%d %s" % ["OK" if fails.is_empty() else "NG",
			fails.size(), str(fails)])
	quit(code)


func _on_beam_pressed(_c) -> void:
	emit_count += 1


## 盘上坐标 → 视口像素（与 Grid._unhandled_input 的换算互逆：同用 get_canvas_transform）
func _viewport_pos_of(coord: Vector2i) -> Vector2:
	var local := Vector2(coord.x * g.cell_size + g.cell_size / 2.0,
			coord.y * g.cell_size + g.cell_size / 2.0)
	return g.get_canvas_transform() * g.to_global(local)


func _left_press(pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	ev.position = pos
	return ev


## 复刻 request_start 的射线展开（盘内前缀），用于对照
func _expected_ray(base: Vector2i, target: Vector2i) -> Array:
	var delta := target - base
	var span := maxi(g.rows, g.cols)
	var k := int(ceil(float(span) / maxi(1, mini(absi(delta.x), absi(delta.y))))) + 1
	var out: Array = []
	for c in LaserGeometry.beam_cells(base, base + delta * k):
		if not g.cells.has(c):
			break
		out.append(c)
	return out


func _run() -> void:
	await _sec(1.0)
	GS = root.get_node("/root/GameState")
	var ud := OS.get_user_data_dir()
	if FileAccess.file_exists(ud + "/save_data.json"):
		var f := FileAccess.open(ud + "/save_data.json", FileAccess.READ)
		save_bak = f.get_as_text()
		f.close()

	# ---- 进关 ----
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
	if g == null or bl == null or GS.current_level_id != "ch03_s01":
		check(false, "3-1 盘装载（id=%s）" % GS.current_level_id)
		_finish()
		return
	check(GS.game_active and g.laser_beam_mode, "进局且光束模式")
	bl.set_process(false)  # 挂起真实帧驱动，全同步直调
	var base: Vector2i = GS.bases[0]
	var span := maxi(g.rows, g.cols)
	g.laser_beam_pressed.connect(_on_beam_pressed)

	# ---- ① 盘外点击兜底：鼠标滑出盘缘也能起束（同方向、盘缘截断）----
	var dir := Vector2i(1, 0)
	for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1),
			Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		if not _expected_ray(base, base + d * (span + 3)).is_empty():
			dir = d
			break
	var off_target: Vector2i = base + dir * (span + 3)  # 必在盘外
	var expected: Array = _expected_ray(base, off_target)
	check(expected.size() >= 2, "① 方向 %s 盘内前缀 %d 格" % [dir, expected.size()])
	check(not g.cells.has(off_target), "① 目标 %s 确在盘外" % off_target)
	g._unhandled_input(_left_press(_viewport_pos_of(off_target)))
	check(bl.firing, "① 盘外点击起束")
	check(bl.ray == expected, "① 射线=基地→盘外点截断前缀（%d 格）" % bl.ray.size())
	check(emit_count == 1, "① 请求只发一次（计数 %d）" % emit_count)
	bl._release()

	# ---- ② 盘内点击不双发：格子路径负责，_unhandled_input 早退 ----
	var in_board: Vector2i = expected[expected.size() / 2]
	g._unhandled_input(_left_press(_viewport_pos_of(in_board)))
	check(emit_count == 1, "② 盘内坐标不重复发（计数 %d）" % emit_count)
	g._on_cell_left_clicked(g.cells[in_board])  # 对照组：格子路径本身照常
	check(bl.firing, "② 盘内格子点击照常起束")
	bl._release()

	# ---- ③ 真实管线啃穿边缘墙后：束钉在盘缘，不静默断束 ----
	var dir3 := Vector2i.ZERO
	var ray3: Array = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		var r: Array = _expected_ray(base, base + d * (span + 3))
		if r.size() < 2:
			continue
		var last: Vector2i = r[r.size() - 1]
		if g.cells[last].is_opened:
			continue  # 边缘格要是未开墙（啃穿后仍出束才有意义）
		var layers := 0
		for c in r:
			var cell = g.cells[c]  # 无类型访问：-s 脚本编译期不拉 cell.gd→grid.gd 依赖链
			layers += cell.cover_wall_hp if cell.is_opened else cell.wall_hp
		if layers == 0 or layers > 7:  # 满管 100 能量≈10 层，留余量
			continue
		dir3 = d
		ray3 = r
		break
	check(dir3 != Vector2i.ZERO, "③ 找到边缘带墙射线 dir=%s 长=%d" % [dir3, ray3.size()])
	if dir3 != Vector2i.ZERO:
		var last3: Vector2i = ray3[ray3.size() - 1]
		bl.energy = bl.ENERGY_MAX
		g._on_cell_left_clicked(g.cells[last3])
		var iter := 0
		while iter < 80 and bl.firing and not g.cells[last3].is_opened:
			bl._tick_fire(0.25)
			iter += 1
		check(g.cells[last3].is_opened, "③ 边缘墙被啃穿（迭代%d）" % iter)
		check(bl.firing, "③ 啃穿后束不静默断（旧代码此处已 _release）")
		check(bl.head_idx >= bl.ray.size(), "③ 束头钉在盘缘（head=%d/%d）"
				% [bl.head_idx, bl.ray.size()])
		var e_before: float = bl.energy
		bl._tick_fire(0.25)
		check(bl.firing, "③ 盘缘续照一拍仍出束")
		check(bl.energy < e_before, "③ 盘缘续照能量照扣（%.1f→%.1f）" % [e_before, bl.energy])
		bl._release()
		check(not bl.firing, "③ 松手才断束")

	# ---- ④ 全通走廊冷起束（用户假设场景「无墙体了」）：点击即出束、束到盘缘保持 ----
	# 直接置场（不走 open_cell 信号面，避免洪水/计分干扰机械断言），放最后跑防污染
	var ray4: Array = _expected_ray(base, off_target)
	for c in ray4:
		var cell = g.cells[c]  # 无类型访问，同上
		if not cell.is_flagged and not cell.is_fossil:
			cell.is_opened = true
			cell.cover_wall_hp = 0
	bl.energy = bl.ENERGY_MAX
	g._on_cell_left_clicked(g.cells[ray4[ray4.size() - 1]])
	check(bl.firing, "④ 全通走廊起束")
	bl._tick_fire(0.25)
	bl._tick_fire(0.25)
	check(bl.firing, "④ 束头过尽直通格后仍出束（旧代码秒断）")
	check(bl.head_idx >= bl.ray.size(), "④ 束头停在盘缘（head=%d/%d）"
			% [bl.head_idx, bl.ray.size()])
	check(bl.energy < bl.ENERGY_MAX, "④ 照射能量照扣")
	bl._release()

	_finish()
