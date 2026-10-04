class_name Robot
extends Node2D
## 机器人实体：根据类型自动找活、走过去、作业
##
## 开墙型（蓝色 ⛏）：打开确定安全的墙
## 标雷型（黄色 ⚑）：标记确定是雷的墙

@export var robot_type: String = "opener"  # "opener" | "marker"

var coord: Vector2i = Vector2i(-1, -1)
var tick_interval: float = 2.0
var _tick_timer: float = 0.0
var _current_target: Variant = null  # Vector2i 或 null
var _state: String = "idle"  # "idle" | "moving" | "working"
var _move_tween: Tween = null  # 当前移动动画（snap_to 震退时取消）

const MICRO_ANIMATION := preload("res://scripts/visuals/micro_sprite_loop.gd")
const FACTION_MARKER := preload("res://scripts/visuals/faction_marker.gd")
const FOOT_SHADOW_TEXTURE := preload("res://visual_v2/runtime/robots/shadow_blob.png")

var _micro_loop := MICRO_ANIMATION.new()

signal action_performed(robot: Robot, action: String, cell_coord: Vector2i)


func _ready() -> void:
	_update_visual()
	_add_foot_shadow()
	FACTION_MARKER.attach(self, $Skin, false)


## 脚下接触影（两级羽化 blob，调研文档：docs/active/美术生产/调研-2D游戏脚下阴影-2026-10-02.md）
## 独立节点而非烘进皮肤帧：皮肤局部微动，影子继续贴地
func _add_foot_shadow() -> void:
	var shadow := Sprite2D.new()
	shadow.name = "FootShadow"
	shadow.texture = FOOT_SHADOW_TEXTURE
	shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shadow.z_index = -1  # 压到 Skin 之下；随 Robot z=5 仍高于格子
	shadow.position = Vector2(0, 9)  # 皮肤 bbox 底 ≈ +10，露下缘月牙
	add_child(shadow)


func _process(delta: float) -> void:
	# 钻头、旗、探头、灯各自轻循环，不按移动/作业切换动作。
	if MICRO_ANIMATION.is_gameplay_running(self):
		_micro_loop.advance(delta)


func set_initial_position(start_coord: Vector2i, grid) -> void:
	coord = start_coord
	position = grid.coord_to_world(start_coord)


func _update_visual() -> void:
	var body: ColorRect = $Body
	var lbl: Label = $IconLabel
	if MICRO_ANIMATION.has_animation(robot_type):
		# 像素皮肤：只更新已有 Skin，不添加可被遍历误认的实体节点。
		body.visible = false
		lbl.visible = false
		_micro_loop.configure($Skin, robot_type)
		return
	# 无皮肤类型兜底：旧色块样式
	if robot_type == "opener":
		body.color = Color(0.20, 0.45, 0.95)
		lbl.text = "⛏"
		lbl.modulate = Color.WHITE
	elif robot_type == "guard":
		body.color = Color(0.25, 0.55, 0.60)
		lbl.text = "🛡"
		lbl.modulate = Color.WHITE
	else:
		body.color = Color(0.95, 0.80, 0.15)
		lbl.text = "⚑"
		lbl.modulate = Color(0.15, 0.10, 0.05)


func accumulate_and_maybe_tick(delta: float, grid, locked: Dictionary) -> void:
	# 节奏分离（设计 §9.4）：opener/marker 的移动/工作间隔独立计时；
	# detector/miner 单间隔不变（走 get_speed_interval 兼容口径）
	if robot_type == "opener" or robot_type == "marker":
		tick_interval = GameState.get_work_interval(robot_type) \
				if _next_tick_is_work() else GameState.get_move_interval(robot_type)
	else:
		tick_interval = GameState.get_speed_interval(robot_type)
	# L4 黏液减速：对"下一 tick 将做什么"的间隔统一 ×2（含移动/工作双轨；布尔判定不叠乘）
	if grid.is_slime_nearby(coord):
		tick_interval *= 2.0
		GameState.result_stats["slowed_seconds"] += delta
	_tick_timer += delta
	if _tick_timer >= tick_interval:
		_tick_timer = 0.0
		do_tick(grid, locked)


## 下一 tick 将做什么：已有目标且与目标相邻（切比雪夫距离 ≤1）→ 作业；否则 → 移动
func _next_tick_is_work() -> bool:
	return _current_target != null \
			and maxi(abs(coord.x - _current_target.x), abs(coord.y - _current_target.y)) <= 1


func do_tick(grid, locked: Dictionary) -> void:
	# 1. 清理失效目标
	if _current_target != null:
		var c = grid.get_cell(_current_target)
		if c == null or c.is_opened or c.is_flagged or c.is_collapsed:
			locked.erase(_current_target)
			_current_target = null

	# 2. 无目标时扫描 + 锁定
	if _current_target == null:
		var actions := Solver.find_certain_actions(grid)
		var want: String = "open" if robot_type == "opener" else "flag"
		var my_actions := actions.filter(func(a): return a.action == want)
		var targets: Array = my_actions.map(func(a): return a.coord)
		if targets.is_empty():
			_state = "idle"
			return
		# 同型防抱团：优先选离其他同型已锁目标 ≥radius+1 格的候选；
		# 候选全被挤占/不可达时回退全场最近（现状口径，不停工）
		var found := {}
		var spaced: Array = Pathfinding.spaced_targets(targets, locked, robot_type, self)
		if not spaced.is_empty():
			found = Pathfinding.find_nearest_target(grid, coord, spaced, locked, self)
		if found.is_empty():
			found = Pathfinding.find_nearest_target(grid, coord, targets, locked, self)
		if found.is_empty():
			_state = "idle"
			return
		_current_target = found.target
		locked[_current_target] = self

	# 3. 寻路到当前目标（自己锁的自己能用）
	var path_result := Pathfinding.find_nearest_target(
		grid, coord, [_current_target], locked, self)
	if path_result.is_empty():
		_state = "idle"
		return

	if path_result.work_pos == coord:
		# 邻接 → 直接作业
		var action: String = "open" if robot_type == "opener" else "flag"
		if robot_type == "opener":
			grid.open_cell(_current_target, "robot_opener")
		else:
			grid.toggle_flag(_current_target, "robot_marker")
		action_performed.emit(self, action, _current_target)
		locked.erase(_current_target)
		_current_target = null
		_state = "working"
		_play_action_pulse()
	else:
		# 走一格
		var next: Vector2i = path_result.path[0]
		_move_to(next, grid)
		coord = next
		_state = "moving"


# 状态查询
func is_idle() -> bool:
	return _current_target == null


# ---- 动效 ----

func _play_action_pulse() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.3, 1.3), 0.08)
	tween.tween_property(self, "scale", Vector2.ONE, 0.14)


func _move_to(target_coord: Vector2i, grid) -> void:
	var world_pos: Vector2 = grid.coord_to_world(target_coord)
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = create_tween()
	_move_tween.tween_property(self, "position", world_pos, 0.3)


## L5 火区震退（WP4）：瞬移到安全格并重置作业状态（爆炸冲击语义，不走移动步）
func snap_to(target_coord: Vector2i, grid) -> void:
	coord = target_coord
	position = grid.coord_to_world(target_coord)
	_state = "idle"
	_play_action_pulse()


## 寻路并移动一步，返回 true 表示已到达目标邻接格（可作业）
## 子类（MinerRobot）可复用此方法
func _move_step(grid, targets: Array, locked: Dictionary) -> bool:
	var path_result := Pathfinding.find_nearest_target(
		grid, coord, targets, locked, self)
	if path_result.is_empty():
		return false
	if path_result.work_pos == coord:
		return true
	var next: Vector2i = path_result.path[0]
	_move_to(next, grid)
	coord = next
	_state = "moving"
	return false
