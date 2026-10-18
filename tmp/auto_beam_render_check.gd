extends SceneTree
## 3-1 蓄能光束·渲染取证 harness（2026-10-18 表现层修复验证）
## 背景：首版光束/预览/能量条被压在 0 层被格子贴图盖住，无头逻辑测试全绿但玩家什么
## 都看不见——本 harness 用真窗渲染 + 像素扫描堵死"画了但看不见"这类 bug。
## 流程：进 3-1 → 截基线 A → 合成悬停截预览 B（帧差分断言）→ 直调出束截束体 C
## → 沿束线走廊扫描 亮橙/白热 像素、基地上方扫描能量条青蓝像素 → 存证 tmp/beam_render_evidence/。
## 用法：Godot_console.exe --path . --audio-driver Dummy -s res://tmp/auto_beam_render_check.gd
## （真窗运行约 20s，窗口会出现在屏幕中央——备份/恢复存档，逻辑零写入）

const EVIDENCE := "tmp/beam_render_evidence/"

var step_no := 0
var fails: Array = []
var GS: Node
var main: Node
var g: Node
var bl: Node
var save_bak := ""


func _initialize() -> void:
	print("[BeamRender] USER_DATA=", OS.get_user_data_dir())
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


func _settle() -> void:
	# 挂起 _process 逐帧驱动后手动 queue_redraw，等一帧真正画完再截
	bl.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw


func _shot(fname: String) -> Image:
	var img: Image = root.get_texture().get_image()
	img.save_png(EVIDENCE + fname)
	print("  [SHOT] ", fname, " ", img.get_size())
	return img


## 画布坐标 → 帧缓冲像素（工程开了拉伸，须换算；同 auto_laser_s1_test._shot_cell 口径）
func _to_img_px(world_local: Vector2, img: Image) -> Vector2:
	var canvas_sz := root.get_visible_rect().size
	var sc := Vector2(img.get_width(), img.get_height()) / canvas_sz
	var t: Transform2D = g.get_global_transform_with_canvas()
	return (t * world_local) * sc


func _count_in_rect(img: Image, rect: Rect2i, pred: Callable) -> int:
	var n := 0
	var clipped := rect.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	for y in range(clipped.position.y, clipped.end.y):
		for x in range(clipped.position.x, clipped.end.x):
			if pred.call(img.get_pixel(x, y)):
				n += 1
	return n


## 沿线段走廊（每步查 5×5 邻域）统计命中谓词的步数占比
func _corridor_hit_ratio(img: Image, a: Vector2, b: Vector2, pred: Callable) -> float:
	var len_px := a.distance_to(b)
	if len_px < 1.0:
		return 0.0
	var steps := int(len_px / 2.0)
	var hits := 0
	for i in range(steps + 1):
		var p := a.lerp(b, float(i) / float(steps))
		var hit := false
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var x := int(p.x) + dx
				var y := int(p.y) + dy
				if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
					continue
				if pred.call(img.get_pixel(x, y)):
					hit = true
					break
			if hit:
				break
		if hit:
			hits += 1
	return float(hits) / float(maxi(steps, 1))


static func is_orange(c: Color) -> bool:
	return c.r > 0.7 and c.g > 0.3 and c.g < 0.85 and c.b < 0.4


static func is_white_hot(c: Color) -> bool:
	return c.r > 0.85 and c.g > 0.8 and c.b > 0.6


static func is_cyan(c: Color) -> bool:
	return c.r < 0.7 and c.g > 0.75 and c.b > 0.8


static func diff_count(a: Image, b: Image) -> int:
	if a.get_width() != b.get_width() or a.get_height() != b.get_height():
		return -1
	var n := 0
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.25:
				n += 1
	return n


func _finish() -> void:
	var ud := OS.get_user_data_dir()
	if save_bak != "":
		var f := FileAccess.open(ud + "/save_data.json", FileAccess.WRITE)
		f.store_string(save_bak)
		f.close()
		print("[BeamRender] 存档已还原")
	var code := 0 if fails.is_empty() else 1
	print("[BeamRender] RESULT=%s FAILS=%d %s" % ["OK" if fails.is_empty() else "NG",
			fails.size(), str(fails)])
	quit(code)


func _run() -> void:
	await _sec(1.0)
	GS = root.get_node("/root/GameState")
	var ud := OS.get_user_data_dir()
	if FileAccess.file_exists(ud + "/save_data.json"):
		var f := FileAccess.open(ud + "/save_data.json", FileAccess.READ)
		save_bak = f.get_as_text()
		f.close()
	DirAccess.make_dir_recursive_absolute(EVIDENCE)

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
		check(false, "3-1 盘装载")
		_finish()
		return
	check(true, "进 3-1 且 game_active")
	# 挂起两处 _process（悬停采样+光束驱动），全合成驱动防真光标窜入
	g.set_process(false)
	bl.set_process(false)

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
		var solid := 0
		for c in r:
			if not g.cells[c].is_opened:
				solid += 1
		if solid >= 2 and (not r.is_empty()) and not g.cells[r[0]].is_opened:
			continue
		if solid >= 2:
			dir = d
			ray = r
			break
	check(dir != Vector2i.ZERO, "选向 dir=%s 长=%d" % [dir, ray.size()])
	if dir == Vector2i.ZERO:
		_finish()
		return
	var target: Vector2i = ray[ray.size() - 1]

	# ---- A：基线（仅能量条常驻）----
	await _settle()
	var img_a := _shot("a_idle.png")
	var cs: float = g.cell_size
	var bar_rect := Rect2i()
	var bar_center := _to_img_px(Vector2(base.x * cs + cs / 2.0, base.y * cs - cs * 0.6), img_a)
	bar_rect = Rect2i(int(bar_center.x) - cs, int(bar_center.y) - 10,
			int(cs * 2.0), 22)
	var cyan_n := _count_in_rect(img_a, bar_rect, is_cyan)
	check(cyan_n >= 15, "A 基线能量条可见（青蓝像素 %d）" % cyan_n)

	# ---- B：悬停预览 ----
	g._update_hover(Vector2(target.x * cs + 14.0, target.y * cs + 14.0))
	await _settle()
	var img_b := _shot("b_preview.png")
	var diff_ba := diff_count(img_a, img_b)
	check(diff_ba >= 150, "B 预览较基线变化像素 %d（≥150）" % diff_ba)

	# ---- C：出束 ----
	bl.request_start(target)
	check(bl.firing, "出束状态置位")
	for i in 20:
		if not bl.firing:
			break
		bl._tick_fire(1.0 / 60.0)
		await _settle()
	var img_c := _shot("c_firing.png")
	var diff_cb := diff_count(img_b, img_c)
	check(diff_cb >= 150, "C 束体较预览变化像素 %d（≥150）" % diff_cb)

	# ---- 束线走廊扫描：亮橙/白热沿束分布 ----
	var last: int = mini(bl.head_idx, bl.ray.size() - 1)
	var from_px := _to_img_px(Vector2(base.x * cs + cs / 2.0, base.y * cs + cs / 2.0), img_c)
	var head_c: Vector2i = bl.ray[last]
	var to_px := _to_img_px(Vector2(head_c.x * cs + cs / 2.0, head_c.y * cs + cs / 2.0), img_c)
	var orange_ratio := _corridor_hit_ratio(img_c, from_px, to_px, is_orange)
	var white_ratio := _corridor_hit_ratio(img_c, from_px, to_px, is_white_hot)
	check(orange_ratio >= 0.5, "束线走廊亮橙覆盖 %.0f%%（≥50%%）" % (orange_ratio * 100.0))
	check(white_ratio >= 0.15, "束线走廊白热芯覆盖 %.0f%%（≥15%%）" % (white_ratio * 100.0))
	var white_n := _count_in_rect(img_c,
			Rect2i(int(to_px.x) - 12, int(to_px.y) - 12, 24, 24), is_white_hot)
	check(white_n >= 5, "束头白热点可见（%d px）" % white_n)
	_finish()
