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

signal action_performed(robot: Robot, action: String, cell_coord: Vector2i)


func _ready() -> void:
	_update_visual()


func set_initial_position(start_coord: Vector2i, grid) -> void:
	coord = start_coord
	position = grid.coord_to_world(start_coord)


func _update_visual() -> void:
	var body: ColorRect = $Body
	var lbl: Label = $IconLabel
	if robot_type == "opener":
		body.color = Color(0.20, 0.45, 0.95)
		lbl.text = "⛏"
		lbl.modulate = Color.WHITE
	else:
		body.color = Color(0.95, 0.80, 0.15)
		lbl.text = "⚑"
		lbl.modulate = Color(0.15, 0.10, 0.05)


func accumulate_and_maybe_tick(delta: float, grid, locked: Dictionary, robot_positions: Dictionary) -> void:
	tick_interval = GameState.get_speed_interval(robot_type)
	_tick_timer += delta
	if _tick_timer >= tick_interval:
		_tick_timer = 0.0
		do_tick(grid, locked, robot_positions)


func do_tick(grid, locked: Dictionary, robot_positions: Dictionary) -> void:
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
		var found := Pathfinding.find_nearest_target(grid, coord, targets, locked, robot_positions, self)
		if found.is_empty():
			_state = "idle"
			return
		_current_target = found.target
		locked[_current_target] = self

	# 3. 寻路到当前目标（自己锁的自己能用）
	var path_result := Pathfinding.find_nearest_target(
		grid, coord, [_current_target], locked, robot_positions, self)
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
	var tween := create_tween()
	tween.tween_property(self, "position", world_pos, 0.3)
