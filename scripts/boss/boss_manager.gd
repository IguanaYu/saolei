class_name BossManager
extends Node2D
## L5 Boss 总控（设计 §3/§5 / 实施计划 WP2）：牙数=血量驱动三阶段状态机，
## 出招时点表调度（M2-M4 逐阶段填实），硬直/转场出招暂停，斩杀演出流程。
## 由 main._process 驱动 tick——game_active=false（暂停/结算/斩杀冻结）时天然停摆。

signal phase_changed(phase: int)      # 转场完成（演出+暂停结束后）
signal kill_sequence_done             # 斩杀掉落演出完毕 → main 走胜利结算
signal boss_staggered(duration: float)

## 阶段门槛（牙数，设计 §3）：拔到第 6 颗进 P2、第 12 颗进 P3
const PHASE_TEETH := [5, 11]
const TRANSITION_PAUSE_SEC := 3.0     # 转场后出招暂停（设计 §3）
const KILL_FALL_SEC := 3.0            # 斩杀掉落演出时长（设计 §5.4）

## 出招时点表（M2-M4 填实；tick 里按 kind 分发到对应 WP 的实现）
## 每条：{"kind": String, "every": sec, "cap": int 同场上限, "first": sec 首次时点, "next": 运行态}
## 注意：不能是 const——Godot 4 的 const 容器深只读，next 计时需要运行时可写
static func _build_attacks() -> Dictionary:
	return {
		1: [
			# P1 史莱姆不走通用表（首对 t=15/+3s + 每 30s 补位，tick 内专门调度）
		],
		2: [
			# M3/WP4：定时落弹
			{"kind": "bomb", "every": 18.0, "cap": 2, "first": 5.0, "next": 0.0},
		],
		3: [
			# M4/WP5：锁链 + 触手 + 降频落弹
			{"kind": "lock", "every": 25.0, "cap": -1, "first": 4.0, "next": 0.0},
			{"kind": "tentacle", "every": 30.0, "cap": 2, "first": 8.0, "next": 0.0},
			{"kind": "bomb", "every": 35.0, "cap": 1, "first": 14.0, "next": 0.0},
		],
	}

var _attacks := _build_attacks()

## P1 史莱姆调度（设计 §5.1，初值盲测校准）：t=15 首只、+3s 第二只；此后每 30s 若场上 <2 补至 2
const SLIME_FIRST_AT := 15.0
const SLIME_SECOND_GAP := 3.0
const SLIME_REFILL_EVERY := 30.0
const SLIME_CAP := 2
var _slime_timer := SLIME_FIRST_AT
var _slimes_spawned := 0

## L5 P2 落弹/火区（设计 §5.2，初值盲测校准）
const FIRE_SEC := 8.0            # 火区持续
const BOMB_NUMBER_PREF := 0.7    # 落点 70% 优先数字格（§9.5 升级件）
const BOMB_MIN_OPENED := 8       # 已开格不足顺延（设计 §7 边界）
const BOMB_DEFER_SEC := 10.0     # 顺延时长

## L5 P3 锁链/触手（设计 §5.3，初值盲测校准）
const LOCK_COUNT := [3, 5]       # 每次抛锁 3-5 把
const TENTACLE_LEN := [4, 6]     # 触手段长 4-6 格
const TENTACLE_DEFER_SEC := 10.0 # 无合格段顺延
const CHAIN_LINK_TEX := preload("res://visual_v2/runtime/fx/chain_link.png")

var bombs: Array = []                    # Array[Bomb]（active 的）
var fire_cells: Dictionary = {}          # Vector2i -> 剩余秒
var tentacles: Array = []                # Array[Tentacle]（active 的）

var phase := 1
var active := false                  # 是否处于 Boss 局（FIND_ALL_MINES 目标关）
var _teeth := 0
var _total_teeth := 20
var _elapsed := 0.0                  # Boss 自己的局内钟（转场/硬直会冻结出招但不重置）
var _staggered_until := -1.0
var _pause_until := 0.0              # 转场出招暂停
var _beast: BossBeast
var _grid = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE  # 场景暂停（面板）时随主场景停


## 进关 setup（main 在 FIND_ALL_MINES 关调用）：盘外锚点定位 + 姿态初值
func setup(grid, total_teeth: int) -> void:
	clear()
	active = true
	_grid = grid
	_total_teeth = max(1, total_teeth)
	_teeth = 0
	phase = 1
	_elapsed = 0.0
	_staggered_until = -1.0
	_pause_until = 0.0
	_slime_timer = SLIME_FIRST_AT
	_slimes_spawned = 0
	_beast = BossBeast.new()
	_beast.name = "BossBeast"  # 显式命名防遍历误匹配
	add_child(_beast)
	_beast.layout(grid.cell_size)
	_beast.teleport_to("top", top_anchor_pos(grid))
	_beast.setup_hp_ticks(_total_teeth, PHASE_TEETH)
	_beast.set_hp(0, _total_teeth)
	_beast.play("claw", 1.5)  # 入场亮爪（与放基地并行的开场演出）
	_grid_home = grid.position


func top_anchor_pos(grid) -> Vector2:
	# 上侧盘框中段：第一行中点向外偏 1.6 格（巨兽趴框上，爪子伸进上边缘）
	var mid := Vector2i(grid.cols / 2, 0)
	return grid.coord_to_world(mid) + Vector2(0, -grid.cell_size * 1.6)


func right_anchor_pos(grid) -> Vector2:
	var mid := Vector2i(grid.cols - 1, grid.rows / 2)
	return grid.coord_to_world(mid) + Vector2(grid.cell_size * 1.6, 0)


## 由 main 转发 grid.processed_mines_changed（牙数即血量）
func on_teeth_changed(current: int) -> void:
	_teeth = current
	if _beast != null:
		_beast.set_hp(current, _total_teeth)
	var target := 1
	if _total_teeth >= 12:
		target = 3 if current > PHASE_TEETH[1] else (2 if current > PHASE_TEETH[0] else 1)
	else:
		target = 2 if current > _total_teeth / 2 else 1
	if target > phase and active:
		_transition_to(target)


func _transition_to(target: int) -> void:
	phase = target
	_beast.set_phase(target)
	_staggered_until = _elapsed + 1.0   # 转场硬直感
	_pause_until = _elapsed + TRANSITION_PAUSE_SEC
	shake_board(0.35)  # 转场震屏（WP8 占位震感）
	for atk in _attacks.get(target, []):
		atk["next"] = _elapsed + float(atk["first"])
	if target == 3:
		# 换位：上侧 → 右侧（设计 §5.3），沿盘框外缘爬过去
		var corner: Vector2 = _grid.coord_to_world(Vector2i(_grid.cols - 1, 0)) \
				+ Vector2(_grid.cell_size * 1.6, -_grid.cell_size * 1.6)
		_beast.crawl_to("right", corner, right_anchor_pos(_grid), 2.0)
	# 转场埋点（阶段时长分布的盲测数据源，设计 §10.3）
	GameState.result_stats["phase_reached"] = maxi(int(GameState.result_stats["phase_reached"]), target)
	var t_key := "phase2_elapsed" if target == 2 else "phase3_elapsed"
	if float(GameState.result_stats.get(t_key, -1.0)) < 0.0:
		GameState.result_stats[t_key] = snappedf(GameState.elapsed, 0.1)
	phase_changed.emit(target)


## 硬直（点杀史莱姆/反弹炸弹等触发）：出招计时冻结 + 姿态反馈
func stagger(sec: float) -> void:
	_staggered_until = max(_staggered_until, _elapsed + sec)
	if _beast != null:
		_beast.play("staggered", sec)
	boss_staggered.emit(sec)


## 出招顺延（反弹奖励：下次该类招式 +7s，设计 §5.2）
func delay_attack(kind: String, sec: float) -> void:
	for atk in _attacks.get(phase, []):
		if atk["kind"] == kind:
			atk["next"] += sec


## main._process 驱动（game_active=false 时不会被调用 = 全场冻结）
func tick(delta: float, grid) -> void:
	if not active:
		return
	_elapsed += delta
	# 引信/火区/触手倒计时：不吃出招暂停/硬直（已在场上的威胁照常走；斩杀冻结由 game_active 兜底）
	for b in bombs.duplicate():
		if is_instance_valid(b):
			b.tick(delta, grid, self)
	bombs = bombs.filter(func(b): return is_instance_valid(b) and b.is_active())
	for t in tentacles.duplicate():
		if is_instance_valid(t):
			t.tick(delta)
	tentacles = tentacles.filter(func(t): return is_instance_valid(t) and t.is_active())
	var expired: Array = []
	for coord in fire_cells:
		fire_cells[coord] = float(fire_cells[coord]) - delta
		var burning_cell = grid.get_cell(coord)
		if burning_cell != null:
			var remaining: float = float(fire_cells[coord])
			burning_cell.set_fire_frame(2 if remaining < 2.0 else int(remaining * 4.0) % 2)
		if float(fire_cells[coord]) <= 0.0:
			expired.append(coord)
	for coord in expired:
		fire_cells.erase(coord)
		var c = grid.get_cell(coord)
		if c != null:
			c.fire_out()
	var frozen := _elapsed < _pause_until or _elapsed < _staggered_until
	if not frozen:
		if phase == 1:
			_slime_schedule(grid)
		for atk in _attacks.get(phase, []):
			if atk["every"] <= 0.0:
				continue  # 一次性/专门调度的招式不走通用表
			if _elapsed >= float(atk["next"]):
				atk["next"] = _elapsed + float(atk["every"])
				_try_cast_attack(atk, grid)


## P1 史莱姆调度：首对入场 + 阶段内补位（转场后不再补充，残兵自然带入 P2/P3）
func _slime_schedule(grid) -> void:
	if _elapsed < _slime_timer:
		return
	if _slimes_spawned < 2:
		_cast_slime(grid)
		_slimes_spawned += 1
		_slime_timer = _elapsed + (SLIME_SECOND_GAP if _slimes_spawned == 1 else SLIME_REFILL_EVERY)
	else:
		if _alive_slimes() < SLIME_CAP:
			_cast_slime(grid)
		_slime_timer = _elapsed + SLIME_REFILL_EVERY


## 出一只史莱姆：Boss 所在侧（P1=上）盘边随机墙格入场；亮爪预告同帧（正式预告演出 WP8）
func _cast_slime(grid) -> void:
	var edge_walls: Array = []
	for x in range(grid.cols):
		var c = grid.get_cell(Vector2i(x, 0))
		if c != null and not c.is_opened:
			edge_walls.append(Vector2i(x, 0))
	if edge_walls.is_empty():
		for y in range(grid.rows):  # 上边缘全开光的兜底：左边缘找墙
			var c = grid.get_cell(Vector2i(0, y))
			if c != null and not c.is_opened:
				edge_walls.append(Vector2i(0, y))
	if edge_walls.is_empty():
		return  # 无墙可入：本次跳过（补位计时照常推进）
	if _beast != null:
		_beast.play("claw", 1.5)
	edge_walls.shuffle()
	get_parent().enemy_manager.spawn_slime(edge_walls[0], grid)


func _alive_slimes() -> int:
	return get_parent().enemy_manager.count_alive_type("slime")


## 单次出招分发（M2-M4 实现各 kind；未知 kind 静默跳过=安静 Boss 关可玩）
func _try_cast_attack(atk: Dictionary, grid) -> void:
	match atk["kind"]:
		"bomb":
			if not _cast_bomb(atk, grid):
				# 落点不足（已开格 <8 等）：本次顺延 10s（设计 §7 边界——永有招可出）
				for a in _attacks.get(phase, []):
					if a["kind"] == "bomb":
						a["next"] = _elapsed + BOMB_DEFER_SEC
		"lock":
			_cast_lock(grid)
		"tentacle":
			if not _cast_tentacle(atk, grid):
				# 无 4-6 格连续已开段：顺延 10s（Q4 兜底）
				for a in _attacks.get(phase, []):
					if a["kind"] == "tentacle":
						a["next"] = _elapsed + TENTACLE_DEFER_SEC


## 锁链投射（设计 §5.3，复用 L4 锁状态）：向剩余未开墙随机抛 3-5 把，
## 避开已锁/已旗/已确认格（L4 Q4 口径：不锁玩家已确认的成果）。
## 无未开墙时静默跳过（残局墙清光，设计 §7——触手/落弹承接 P3）。
func _cast_lock(grid) -> void:
	var candidates: Array = []
	for coord in grid.cells:
		var c: Cell = grid.cells[coord]
		if not c.is_opened and not c.is_locked and not c.is_flagged \
				and not c.is_confirmed_mine and not c.is_base:
			candidates.append(coord)
	if candidates.is_empty():
		return
	candidates.shuffle()
	var count: int = mini(randi_range(LOCK_COUNT[0], LOCK_COUNT[1]), candidates.size())
	var locked := 0
	for coord in candidates:
		if locked >= count:
			break
		if grid.cells[coord].apply_lock():
			locked += 1
			_fx_lock_cast(grid.coord_to_world(coord))
	if _beast != null and locked > 0:
		_beast.play("growl", 1.5)


func _fx_lock_cast(target_pos: Vector2) -> void:
	if _beast == null:
		return
	var link := Sprite2D.new()
	link.name = "LockCastLink"
	link.texture = CHAIN_LINK_TEX
	link.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	link.z_index = 14
	link.position = _beast.position
	add_child(link)
	var tw := link.create_tween()
	tw.tween_property(link, "position", target_pos, 0.24) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(link, "modulate:a", 0.0, 0.28)
	tw.tween_callback(link.queue_free)


## 触手（设计 §5.3）：从 Boss 当前所在盘边沿一行/一列取 4-6 格连续已开段伸入。
## 段内排除火区（互斥）/基地格（出生点不阻断）。返回 false = 无合格段
func _cast_tentacle(atk: Dictionary, grid) -> bool:
	var alive := tentacles.filter(func(t): return is_instance_valid(t)).size()
	if alive >= int(atk["cap"]):
		return true  # 到场上上限：正常周期等下一轮
	var side := "right" if (_beast == null or _beast.anchor == "right") else "top"
	var want_len: int = randi_range(TENTACLE_LEN[0], TENTACLE_LEN[1])
	var best: Array = []
	# 候选行/列：right 侧从最右列向内；top 侧从第一行向下
	if side == "right":
		for y in range(1, grid.rows - 1):
			var run: Array = []
			for x in range(grid.cols - 1, -1, -1):
				if not _tentacle_ok(grid, Vector2i(x, y)):
					break
				run.append(Vector2i(x, y))
				if run.size() >= want_len:
					break
			if run.size() >= TENTACLE_LEN[0] and run.size() > best.size():
				best = run
	else:
		for x in range(1, grid.cols - 1):
			var run: Array = []
			for y in range(0, grid.rows):
				if not _tentacle_ok(grid, Vector2i(x, y)):
					break
				run.append(Vector2i(x, y))
				if run.size() >= want_len:
					break
			if run.size() >= TENTACLE_LEN[0] and run.size() > best.size():
				best = run
	if best.is_empty():
		return false
	# 只取需要的长度（best 可能长于 want_len——同 run 内截断靠边一段）
	var segment: Array = best.slice(0, mini(want_len, best.size()))
	if _beast != null:
		_beast.play("growl", 1.5)
	var t := Tentacle.new()
	t.name = "BossTentacle"  # 显式命名防遍历误匹配
	add_child(t)
	t.setup(segment, grid)
	tentacles.append(t)
	return true


func _tentacle_ok(grid, c: Vector2i) -> bool:
	var cell = grid.get_cell(c)
	return cell != null and cell.is_opened and not cell.is_base \
			and not cell.is_on_fire and cell.path_blockers == 0


## 玩家点断触手（main 几何命中链转发）：根部命中判定 + 断裂结算（吃 1 CD 在 main 侧）
func hit_tentacle_root_at(world_pos: Vector2, radius: float) -> Tentacle:
	for t in tentacles:
		if is_instance_valid(t) and t.is_active() \
				and grid_root_world_pos(t).distance_to(world_pos) < radius:
			return t
	return null


func grid_root_world_pos(t: Tentacle) -> Vector2:
	return t.global_position


## 落弹（设计 §5.2）：落点选择器 + 出弹。false = 本次顺延
func _cast_bomb(atk: Dictionary, grid) -> bool:
	var on_field := bombs.filter(func(b): return is_instance_valid(b)).size()
	if on_field >= int(atk["cap"]):
		return true  # 到场上限：不算失败，按正常周期等下一轮
	var opened: Array = []
	for coord in grid.cells:
		var c: Cell = grid.cells[coord]
		if c.is_opened and not c.is_base and not c.is_on_fire and not c.bomb_masked:
			opened.append(coord)
	if opened.size() < BOMB_MIN_OPENED:
		return false
	var robot_coords: Dictionary = {}
	for r in get_parent().robot_manager.robots:
		robot_coords[r.coord] = true
	var pool: Array = opened.filter(func(c): return not robot_coords.has(c))
	if pool.is_empty():
		return false
	# 70% 优先数字格（§9.5：数字被压 = 信息剥夺压力，同网口径）
	var target: Vector2i
	var digits: Array = pool.filter(func(c): return grid.cells[c].adjacent_mines > 0)
	if not digits.is_empty() and randf() < BOMB_NUMBER_PREF:
		target = digits.pick_random()
	else:
		target = pool.pick_random()
	if _beast != null:
		_beast.play("inhale", 1.5)  # 吸气预告（阴影预告随弹体自带）
	var bomb := Bomb.new()
	bomb.name = "BossBomb"  # 显式命名防遍历误匹配
	add_child(bomb)
	bomb.setup(target, grid)
	bombs.append(bomb)
	return true


## 反弹结算（Bomb.deflect 飞抵后回调）：奖励 + 硬直 + 下次落弹顺延（设计 §5.2）
func on_bomb_deflected() -> void:
	GameState.add_money(15)
	GameState.add_score(15)
	GameState.result_stats["bombs_deflected"] += 1
	stagger(2.0)
	delay_attack("bomb", 7.0)


## 爆炸点火：以落点为中心十字 5 格（只烧已开格、不烧基地格——机器人出生点不阻断；
## 越界裁剪；烧掉覆盖黏液——cell.ignite_fire 内）
func ignite_fire_cross(center: Vector2i) -> void:
	if _grid == null:
		return
	shake_board(0.4)
	var ignited: Array = []
	for o in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c: Vector2i = center + o
		var cell = _grid.get_cell(c)
		if cell == null or not cell.is_opened or cell.is_base or cell.is_on_fire:
			continue
		cell.ignite_fire()
		fire_cells[c] = FIRE_SEC
		ignited.append(c)
	if not ignited.is_empty():
		get_parent().robot_manager.displace_robots_in(ignited, _grid)


## 灭火（grid.fire_extinguish_requested → main 转发）：点击格所在 4 向连通组整片熄灭
## 成功 = 有火被灭（吃 CD 与奖励在 main 侧）
func extinguish_fire_group(coord: Vector2i) -> bool:
	if not fire_cells.has(coord):
		return false
	var group: Array = [coord]
	var seen: Dictionary = {coord: true}
	var i := 0
	while i < group.size():
		var c: Vector2i = group[i]
		i += 1
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + o
			if not seen.has(n) and fire_cells.has(n):
				seen[n] = true
				group.append(n)
	for c in group:
		fire_cells.erase(c)
		var cell = _grid.get_cell(c) if _grid != null else null
		if cell != null:
			cell.fire_out()
	GameState.add_money(5)
	GameState.add_score(5)
	GameState.result_stats["fires_extinguished"] += 1
	return true


## 反弹飞行目标（Boss 本体当前位置；无实体时回退上侧锚点）
func beast_world_pos() -> Vector2:
	if _beast != null and is_instance_valid(_beast):
		return _beast.global_position
	return top_anchor_pos(_grid) if _grid != null else Vector2.ZERO


## 玩家点击命中炸弹？（main 几何命中链最优先调用）
func hit_bomb_at(world_pos: Vector2, radius: float) -> Bomb:
	for b in bombs:
		if is_instance_valid(b) and b.state == "fuse" \
				and b.global_position.distance_to(world_pos) < radius:
			return b
	return null


## 斩杀流程（main 在第 20 颗牙时调用；调用前 main 已置 game_active=false 冻结全场）
func begin_kill_sequence() -> void:
	shake_board(0.5)
	if _beast == null:
		kill_sequence_done.emit()
		return
	_beast.pose_finished.connect(
			func(_p): kill_sequence_done.emit(), CONNECT_ONE_SHOT)
	_beast.play("fall", KILL_FALL_SEC)


## 震屏（WP8 占位震感）：棋盘短促抖动；以 setup 时的原位为锚，重复调用先杀旧 tween 防漂移
var _grid_home: Vector2 = Vector2.ZERO
var _shake_tween: Tween = null

func shake_board(strength_sec: float) -> void:
	if _grid == null:
		return
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
		_grid.position = _grid_home
	var amp: float = _grid.cell_size * 0.18
	_shake_tween = create_tween()
	for i in 4:
		var off := Vector2(randf_range(-amp, amp), randf_range(-amp, amp)) \
				if i < 3 else Vector2.ZERO
		_shake_tween.tween_property(_grid, "position", _grid_home + off, strength_sec / 4.0)
	_shake_tween.tween_property(_grid, "position", _grid_home, 0.05)


## 局末/重开清理（main._start_level_with 与结算路径调用）
func clear() -> void:
	active = false
	phase = 1
	_teeth = 0
	_elapsed = 0.0
	_staggered_until = -1.0
	_pause_until = 0.0
	_slime_timer = SLIME_FIRST_AT
	_slimes_spawned = 0
	_grid = null
	for b in bombs:
		if is_instance_valid(b):
			b.queue_free()
	bombs.clear()
	for t in tentacles:
		if is_instance_valid(t):
			t.state = "retracted"  # 直接释放，不播断裂动效（清场景路径）
			if t._grid != null:
				for c in t.cells:
					var cell = t._grid.get_cell(c)
					if cell != null:
						cell.path_blockers -= 1
			t.queue_free()
	tentacles.clear()
	# 火区状态残留由重开新盘覆盖（cells 重建），这里只清登记表
	fire_cells.clear()
	if _beast != null:
		_beast.queue_free()
		_beast = null
	for phase_key in _attacks:
		for atk in _attacks[phase_key]:
			atk["next"] = 0.0
