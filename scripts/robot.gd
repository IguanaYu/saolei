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

# 皮肤帧（4 型 × 待机/移动；与商店/HUD 图标同设计语言）
const SKINS := {
	"opener": [preload("res://visual_v2/runtime/robots/robot_opener_idle.png"), preload("res://visual_v2/runtime/robots/robot_opener_move.png")],
	"marker": [preload("res://visual_v2/runtime/robots/robot_marker_idle.png"), preload("res://visual_v2/runtime/robots/robot_marker_move.png")],
	"detector": [preload("res://visual_v2/runtime/robots/robot_detector_idle.png"), preload("res://visual_v2/runtime/robots/robot_detector_move.png")],
	"miner": [preload("res://visual_v2/runtime/robots/robot_miner_idle.png"), preload("res://visual_v2/runtime/robots/robot_miner_move.png")],
}
const SKIN_FRAME_INTERVAL := 0.18  # 移动时帧交替间隔

var _anim_timer := 0.0
var _anim_frame := 0

signal action_performed(robot: Robot, action: String, cell_coord: Vector2i)


func _ready() -> void:
	_update_visual()


func _process(delta: float) -> void:
	# 移动中：待机/移动帧交替（履带滚动+弹跳）；静止回待机帧
	if not SKINS.has(robot_type):
		return
	if _state == "moving":
		_anim_timer += delta
		if _anim_timer >= SKIN_FRAME_INTERVAL:
			_anim_timer = 0.0
			_anim_frame = 1 - _anim_frame
			$Skin.texture = SKINS[robot_type][_anim_frame]
	elif _anim_frame != 0:
		_anim_frame = 0
		_anim_timer = 0.0
		$Skin.texture = SKINS[robot_type][0]


func set_initial_position(start_coord: Vector2i, grid) -> void:
	coord = start_coord
	position = grid.coord_to_world(start_coord)


func _update_visual() -> void:
	var body: ColorRect = $Body
	var lbl: Label = $IconLabel
	if SKINS.has(robot_type):
		# 像素皮肤：隐藏旧色块/emoji，显示皮肤待机帧
		body.visible = false
		lbl.visible = false
		var skin: Sprite2D = $Skin
		skin.texture = SKINS[robot_type][0]
		skin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_anim_frame = 0
		_anim_timer = 0.0
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
		var found := Pathfinding.find_nearest_target(grid, coord, targets, locked, self)
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
