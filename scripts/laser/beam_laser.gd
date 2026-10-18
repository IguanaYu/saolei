class_name BeamLaser
extends Node2D
## 3-1 蓄能光束（持续激光改版·垂直切片，2026-10-17）
## 设计拍板（会话 2026-10-17）：方向锁死（按下瞬间定八向）、悬停预览保留（能量投影）、
## 未满可放（边攒边用）、爆发类设施 0.5s +25% 充 2s 爆一次（后续关迁移时用，本关无）。
##
## 机制：
##   长按左键 = 从基地沿「按下瞬间基地→点击格」的精确直线（超覆盖，指哪打哪）
##   放出持续光束，束头逐格啃墙（每层 0.5s）；按住期间方向锁死，不随鼠标转向；
##   已开无墙/旗/化石格瞬间通过（不花时间）；松手 / 能量耗尽 / 出盘 = 断束。
##   能量 100：按住 -20/s，松手 +20/s（满管 ≈5s ≈ 10 层墙）；能量 <10 不起束（啃不动一层）。
##   照住 opener/marker：暂停作业 + 灌能（0.5s 一记 +20；池上限 80、双速工作耗
##   10/s——充能条与续航合一，照 2s 满 = 8s 双速，进度保留）。
##   照住筑墙工：每 0.5s 挨 1 伤（会走就会离开光路）。
##   激光不再消耗动作额度（插旗照旧吃）；胜负仍走 REACH_SCORE（开格信号原管线）。
##
## 结构：Grid 子节点（吃 Grid 本地系，同 LaserPreview/EffectsLayer 口径）。
## 点击/双击分流（grid.laser_beam_pressed）→ main（放置期拦截）→ request_start。

const ENERGY_MAX := 100.0
const DRAIN_PER_SEC := 20.0
const REGEN_PER_SEC := 20.0
const SEC_PER_HIT := 0.5                      # 每削一层墙/覆盖墙的照射时长
const HIT_ENERGY := DRAIN_PER_SEC * SEC_PER_HIT  # 10：预览口径 能量÷10=还能啃几层
const ROBOT_PIP_SEC := 0.5                    # 照住机器人每 0.5s 灌一记
const ROBOT_PIP_ENERGY := 20.0                # 一记 +20（池上限 80 → 照 2s 充满 = 8s 双速）
const BUILDER_HIT_SEC := 0.5                  # 光路上筑墙工每 0.5s 挨 1 伤

var grid: Grid = null
var rm = null              # RobotManager（.robots）
var em = null              # EnemyManager（.builders）
var laser_manager = null   # 借 recent_laser_opened 口径（筑墙工施工优先级）

var energy := ENERGY_MAX
var firing := false
var ray: Array = []            # Vector2i 八向射线（不含基地；盘内截断）
var head_idx := -1             # 正在啃的格下标
var cell_progress := 0.0       # 当前格已照时长（断束不清零=物理余温，续照续算）
var _builder_acc: Dictionary = {}   # BuilderEnemy → 已照时长
var _robot_pip: Dictionary = {}     # Robot → 距下一记灌能的已照时长（松束保留）
var _opened_pending: Array = []     # 本帧啃出状态变化的格（回填 recent_laser_opened）
var _hover_cell: Cell = null
var _hum: AudioStreamPlayer = null


func _ready() -> void:
	# 44：格子/机器人(≤10)与悬停框(40)之上、点射瞬态特效(45)之下——
	# 破墙岩屑/跳字仍压在持续束上方；缺省 0 层会被格子贴图整个盖住（2026-10-18 用户复报）
	z_index = 44


func setup(g: Grid, robot_manager, enemy_manager, laser_mgr) -> void:
	grid = g
	rm = robot_manager
	em = enemy_manager
	laser_manager = laser_mgr
	g.cell_hovered.connect(_on_cell_hovered)
	g.cell_unhovered.connect(_on_cell_unhovered)
	_hum = AudioStreamPlayer.new()
	_hum.name = "BeamHum"  # 显式命名，避免遍历误匹配
	# duplicate：AudioManager 池里同名流是单发口径，直接改 loop 会污染 2-1~2-5 的点射音
	var stream := load("res://assets/audio/sfx/ch02_laser.wav").duplicate()
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	_hum.stream = stream
	_hum.volume_db = -6.0
	_hum.bus = &"SFX"
	add_child(_hum)


## 每关重置（main._start_level_with 调用；非光束关也调=清演出残留）
func reset_for_level() -> void:
	_release()
	energy = ENERGY_MAX
	_builder_acc.clear()
	_robot_pip.clear()
	_opened_pending.clear()
	_hover_cell = null
	queue_redraw()


## 左键按下（grid 分流 → main 转发）：方向在按下瞬间锁死
func request_start(target: Vector2i) -> void:
	if grid == null or firing or not GameState.game_active:
		return
	if energy < HIT_ENERGY:
		return  # 空管：啃不动一层就不出束（能量条红色即反馈）
	var base: Vector2i = GameState.bases[0] if not GameState.bases.is_empty() \
			else Vector2i(-1, -1)
	if base.x < 0 or target == base:
		return
	# 方向 = 按下瞬间 基地→目标格 的精确直线（沿用点射超覆盖几何，指哪打哪——
	# 八向量化会把斜向全吸附成正交，2026-10-18 用户复报"只能朝上下左右射"），
	# 向盘外等比延伸到出界；按住期间锁死，不随鼠标转向
	var delta := target - base
	var span := maxi(grid.rows, grid.cols)
	var k := int(ceil(float(span) / maxi(1, mini(absi(delta.x), absi(delta.y))))) + 1
	ray.clear()
	for c in LaserGeometry.beam_cells(base, base + delta * k):
		if not grid.cells.has(c):
			break  # 出盘截断
		ray.append(c)
	if ray.is_empty():
		return
	firing = true
	head_idx = 0
	cell_progress = 0.0
	_hum.play()
	GameState.result_stats["shots_fired"] += 1


func _process(delta: float) -> void:
	if grid == null or not grid.laser_beam_mode:
		if firing:
			_release()
		return
	if firing:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
				or not GameState.game_active:
			_release()
		else:
			_tick_fire(delta)
	elif GameState.game_active:
		energy = minf(ENERGY_MAX, energy + REGEN_PER_SEC * delta)
	queue_redraw()


# ---- 束推进 ----

func _tick_fire(delta: float) -> void:
	energy = maxf(0.0, energy - DRAIN_PER_SEC * delta)
	var work := delta
	while work > 0.0001 and firing:
		if head_idx >= ray.size():
			_release()  # 出盘：束停在盘缘（能量按持按时长照扣）
			break
		var c: Vector2i = ray[head_idx]
		var cell: Cell = grid.get_cell(c)
		if cell == null:
			_release()
			break
		if _passes_through(cell):
			head_idx += 1
			cell_progress = 0.0
			continue
		var need := SEC_PER_HIT - cell_progress
		if work >= need:
			work -= need
			cell_progress = 0.0
			_apply_hit(c, cell)
			if firing and _passes_through(cell):
				head_idx += 1  # 破穿了才前进；多层墙原地续啃
		else:
			cell_progress += work
			work = 0.0
	if firing and energy <= 0.0:
		_release()
	if not firing:
		return  # 断束帧到此为止：_release 已清机器人照住标志，不能再让 _irradiate 填回
	if not _opened_pending.is_empty() and laser_manager != null:
		laser_manager.note_beam_opened(_opened_pending)
		_opened_pending.clear()
	_irradiate(delta)


## 光照直通格：不花时间不结算（旗/化石挡不住光）
func _passes_through(cell: Cell) -> bool:
	return cell.is_flagged or cell.is_fossil \
			or (cell.is_opened and cell.cover_wall_hp <= 0)


func _apply_hit(c: Vector2i, cell: Cell) -> void:
	if cell.is_opened:
		grid.damage_cover_wall_at(c, 1)
		_opened_pending.append(c)  # 覆盖墙被拆也算「被激光拆过」
	else:
		var was_opened := cell.is_opened
		grid.open_cell(c, "player_laser")  # 多层墙=削一层；钻石头格=碎钻；余同点射管线
		if cell.is_opened and not was_opened:
			_opened_pending.append(c)
			GameState.result_stats["beam_cells_total"] += 1


## 照射侧效：机器人暂停+充电 / 筑墙工持续掉血（光路=基地到束头的前缀）
func _irradiate(delta: float) -> void:
	var lit := {}
	var last: int = mini(head_idx, ray.size() - 1)
	for i in range(0, last + 1):
		lit[ray[i]] = true
	if rm != null:
		for r in rm.robots:
			if not is_instance_valid(r):
				continue
			var workable: bool = r.robot_type == "opener" or r.robot_type == "marker"
			var illuminated: bool = workable and lit.has(r.coord)
			r.beam_charging = illuminated
			if illuminated:
				var acc: float = float(_robot_pip.get(r, 0.0)) + delta
				while acc >= ROBOT_PIP_SEC:
					acc -= ROBOT_PIP_SEC
					r.grant_beam_energy(ROBOT_PIP_ENERGY)  # +20/记；池满 80 溢出即弃
					AudioManager.play_sfx("charge")
				_robot_pip[r] = acc
	if em != null:
		for b in em.builders:
			if not is_instance_valid(b) or not b.is_alive():
				_builder_acc.erase(b)
				continue
			if lit.has(b.coord):
				var acc: float = float(_builder_acc.get(b, 0.0)) + delta
				while acc >= BUILDER_HIT_SEC and b.is_alive():
					acc -= BUILDER_HIT_SEC
					b.take_hit("player_laser")
				if b.is_alive():
					_builder_acc[b] = acc
				else:
					_builder_acc.erase(b)


func _release() -> void:
	if not firing:
		return
	firing = false
	head_idx = -1
	cell_progress = 0.0
	if _hum != null and _hum.playing:
		_hum.stop()
	if rm != null:
		for r in rm.robots:
			if is_instance_valid(r):
				r.beam_charging = false
	queue_redraw()


# ---- 悬停 ----

func _on_cell_hovered(cell: Cell) -> void:
	_hover_cell = cell


func _on_cell_unhovered(_cell: Cell) -> void:
	_hover_cell = null


# ---- 绘制（Grid 本地系）----

func _draw() -> void:
	if grid == null or not grid.laser_beam_mode:
		return
	if GameState.bases.is_empty():
		return
	var base: Vector2i = GameState.bases[0]
	var cs: float = grid.cell_size
	_draw_energy_bar(base, cs)
	if firing and head_idx >= 0 and not ray.is_empty():
		_draw_beam(base, cs)
	elif _hover_cell != null and GameState.game_active:
		_draw_preview(base, cs)


func _cell_center(c: Vector2i, cs: float) -> Vector2:
	return Vector2(c.x * cs + cs / 2.0, c.y * cs + cs / 2.0)


func _draw_energy_bar(base: Vector2i, cs: float) -> void:
	var center := _cell_center(base, cs)
	var size := Vector2(cs * 2.4, 8.0)
	var pos := center + Vector2(-size.x / 2.0, -cs * 1.05)
	var frac := energy / ENERGY_MAX
	var col: Color
	if energy < HIT_ENERGY:
		# 空管：红色呼吸闪烁——按了也不出束的唯一状态
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 120.0)
		col = Color(0.95, 0.2, 0.12, 0.45 + 0.55 * pulse)
	else:
		col = Color(0.9, 0.25, 0.16).lerp(Color(0.45, 0.95, 1.0),
				clampf(frac * 1.4, 0.0, 1.0))
	draw_rect(Rect2(pos - Vector2(2, 2), size + Vector2(4, 4)), Color(0.07, 0.06, 0.05, 0.95))
	draw_rect(Rect2(pos, Vector2(maxf(size.x * frac, 1.5), size.y)), col)
	if firing:
		# 出束中：白描边=正在消耗
		draw_rect(Rect2(pos - Vector2(2, 2), size + Vector2(4, 4)),
				Color(1.0, 0.95, 0.85, 0.95), false, 2.0)


func _draw_beam(base: Vector2i, cs: float) -> void:
	var last: int = mini(head_idx, ray.size() - 1)
	var head_c: Vector2i = ray[last]
	var from := _cell_center(base, cs)
	var to := _cell_center(head_c, cs)
	# 光路前缀地面微光（照住的地皮；robots 充能环/筑墙工掉血各自有反馈）
	var warm := Color(1.0, 0.55, 0.2, 0.16)
	for i in range(0, last + 1):
		var c: Vector2i = ray[i]
		draw_rect(Rect2(Vector2(c.x * cs + 1.0, c.y * cs + 1.0), Vector2(cs - 2.0, cs - 2.0)),
				warm)
	# 正在啃的格白闪（呼吸节奏）
	var chew: Cell = grid.get_cell(head_c)
	if chew != null and not chew.is_opened:
		var flash := 0.12 + 0.10 * sin(Time.get_ticks_msec() / 40.0)
		draw_rect(Rect2(Vector2(head_c.x * cs + 1.0, head_c.y * cs + 1.0),
				Vector2(cs - 2.0, cs - 2.0)), Color(1, 1, 1, flash))
	# 闪电折线：8 段、每帧小幅随机垂偏（外辉光/中层/白热芯三层叠画）
	var segs := 8
	var normal := (to - from).orthogonal().normalized()
	if normal == Vector2.ZERO:
		normal = Vector2(0, 1)
	var pts := PackedVector2Array()
	for i in range(segs + 1):
		var p := from.lerp(to, float(i) / float(segs))
		if i > 0 and i < segs:
			p += normal * randf_range(-3.0, 3.0)
		pts.append(p)
	draw_polyline(pts, Color(1.0, 0.5, 0.15, 0.35), 9.0)
	draw_polyline(pts, Color(1.0, 0.62, 0.2, 0.75), 5.0)
	draw_polyline(pts, Color(1.0, 0.95, 0.85, 0.95), 2.0)
	# 束头：白热点 + 六向乱窜火花
	draw_circle(to, 4.0, Color(1.0, 0.97, 0.9))
	for i in 6:
		var p := to + Vector2.from_angle(randf_range(0.0, TAU)) * randf_range(6.0, 14.0)
		draw_line(to, p, Color(1.0, 0.72, 0.3, randf_range(0.5, 0.9)), 1.5)
	# 照射中的机器人头顶小弧=距下一记灌能（+20）的进度；能量余量看机器人充能环
	if rm != null:
		for r in rm.robots:
			if is_instance_valid(r) and r.beam_charging:
				var acc: float = float(_robot_pip.get(r, 0.0))
				var p := grid.to_local(r.global_position) + Vector2(0, -17)
				draw_arc(p, 6.0, -PI / 2.0,
						-PI / 2.0 + TAU * clampf(acc / ROBOT_PIP_SEC, 0.0, 1.0),
						16, Color(0.5, 0.98, 1.0, 0.95), 2.0)


## 悬停预览：整条射线 + 能量投影（够到的段亮、够不到的段暗；随回能实时前移）
## 射线 = 基地→悬停格 精确直线超覆盖、向盘外延伸（与 request_start 同构，预览=结算同源）
func _draw_preview(base: Vector2i, cs: float) -> void:
	var target: Vector2i = _hover_cell.coord
	if target == base:
		return
	var delta := target - base
	var span := maxi(grid.rows, grid.cols)
	var k := int(ceil(float(span) / maxi(1, mini(absi(delta.x), absi(delta.y))))) + 1
	var cum := 0.0
	var entries: Array = []   # [coord, cum_cost, pass_through]
	for c in LaserGeometry.beam_cells(base, base + delta * k):
		if not grid.cells.has(c):
			break
		var cell: Cell = grid.get_cell(c)
		if cell == null:
			break
		var pass_through := _passes_through(cell)
		if not pass_through:
			var layers: int = cell.cover_wall_hp if cell.is_opened else cell.wall_hp
			cum += layers * HIT_ENERGY
		entries.append([c, cum, pass_through])
	if entries.is_empty():
		return
	var hot_fill := Color(1.0, 0.42, 0.15, 0.38)
	var hot_border := Color(1.0, 0.6, 0.3, 1.0)
	var dim_fill := Color(1.0, 0.42, 0.15, 0.12)
	var dim_border := Color(1.0, 0.55, 0.25, 0.45)
	var pass_border := Color(0.6, 0.9, 1.0, 0.7)
	var end_center := Vector2.ZERO
	var affordable_n := 0
	for e in entries:
		var c: Vector2i = e[0]
		var affordable: bool = float(e[1]) <= energy
		if affordable:
			affordable_n += 1
		var r := Rect2(Vector2(c.x * cs + 2.0, c.y * cs + 2.0), Vector2(cs - 4.0, cs - 4.0))
		if affordable:
			if not e[2]:
				draw_rect(r, hot_fill, true)
				draw_rect(r, hot_border, false, 2.0)
			else:
				draw_rect(r, pass_border, false, 1.5)
		else:
			draw_rect(r, dim_fill, true)
			draw_rect(r, dim_border, false, 1.0)
		end_center = _cell_center(c, cs)
	draw_line(_cell_center(base, cs), end_center, Color(1.0, 0.78, 0.45, 0.5), 2.0)
	# 能量截断线：最后一块啃得穿的格与第一块超管格之间（回能时肉眼可见地前移）
	if affordable_n < entries.size():
		var inner := _cell_center(base, cs) if affordable_n == 0 \
				else _cell_center(entries[affordable_n - 1][0], cs)
		var outer := _cell_center(entries[affordable_n][0], cs)
		var mid := (inner + outer) / 2.0
		var perp := (outer - inner).orthogonal().normalized() * (cs * 0.55)
		draw_line(mid - perp, mid + perp, Color(1.0, 0.85, 0.5, 0.95), 2.5)
		draw_circle(mid, 2.0, Color(1.0, 0.9, 0.6, 1.0))
