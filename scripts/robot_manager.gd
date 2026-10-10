class_name RobotManager
extends Node2D
## 管理所有机器人；串行调度避免 race

# 场景路径 + spawn 时 load：本节点常驻主场景，preload 会把四套机器人
# 皮肤/动画拉进开机加载（进关买机器人才需要；ResourceCache 后续命中零开销）
const ROBOT_SCENE_PATH := "res://scenes/Robot.tscn"
const DETECTOR_ROBOT_SCENE_PATH := "res://scenes/DetectorRobot.tscn"
const MINER_ROBOT_SCENE_PATH := "res://scenes/MinerRobot.tscn"
const GUARD_ROBOT_SCENE_PATH := "res://scenes/GuardRobot.tscn"
const REFRACTOR_SCENE_PATH := "res://scenes/RefractorRobot.tscn"
const OVERLOAD_SCENE_PATH := "res://scenes/OverloadRobot.tscn"
const IDLE_WARNING_THRESHOLD := 3.0  # 所有机器人连续 idle 超过这个秒数就报警

signal idle_warning_changed(show: bool)
signal robot_removed(robot, reason: String)

var robots: Array = []

var _all_idle_seconds: float = 0.0
var _idle_warning_on: bool = false


## 机器人出生：from_coord 传来源基地格时播出厂演出（基地亮→飞图→落地弹入扬尘，
## docs/active/机器人出生反馈-方案-v1.md）；delay_s 用于开局赠送多台错开。
## 演出纯叠加：机器人逻辑立即生效，只有可见性被演出接管到落地时点
func spawn_robot(start_coord: Vector2i, robot_type: String, grid,
		from_coord := Vector2i(-1, -1), delay_s := 0.0) -> Robot:
	var robot: Robot
	match robot_type:
		"detector": robot = load(DETECTOR_ROBOT_SCENE_PATH).instantiate()
		"miner": robot = load(MINER_ROBOT_SCENE_PATH).instantiate()
		"guard": robot = load(GUARD_ROBOT_SCENE_PATH).instantiate()
		"refractor_wide", "refractor_scatter":
			robot = load(REFRACTOR_SCENE_PATH).instantiate()
			robot.config = "wide" if robot_type == "refractor_wide" else "scatter"
		"overload":
			robot = load(OVERLOAD_SCENE_PATH).instantiate()
		_: robot = load(ROBOT_SCENE_PATH).instantiate()
	add_child(robot)
	robot.robot_type = robot_type
	robot._update_visual()
	robot.set_initial_position(start_coord, grid)
	robots.append(robot)
	# 新机器人入场，清除空闲警告
	_reset_idle_warning()
	_play_spawn_presentation(robot, grid, start_coord, from_coord, delay_s)
	return robot


## 出生演出编排；EffectsLayer 缺失（异常兜底）时不隐藏本体，直接可见
func _play_spawn_presentation(robot: Robot, grid, spot: Vector2i,
		from_coord: Vector2i, delay_s: float) -> void:
	var fx: EffectsLayer = grid.get_node_or_null("EffectsLayer") as EffectsLayer
	if fx == null:
		return
	robot.visible = false
	var origin: Vector2i = from_coord if from_coord != Vector2i(-1, -1) else spot
	if from_coord != Vector2i(-1, -1) and delay_s == 0.0:
		fx.fx_base_flash(grid.get_cell(from_coord))  # 连续赠送只在首台闪基地
	var icon: Texture2D = fx.robot_icon_texture(robot.get_node_or_null("Skin"))
	fx.fx_robot_deliver(grid.coord_to_world(origin), grid.coord_to_world(spot),
		icon, delay_s,
		func():
			if not is_instance_valid(robot):
				return
			robot.visible = true
			robot.play_spawn_drop()
			fx.fx_spawn_dust(grid.get_cell(spot))
			AudioManager.play_sfx("flag", 1.1))


## 移除机器人（detector 自爆时调用）
func remove_robot(robot: Robot, reason: String) -> void:
	robots.erase(robot)
	robot.queue_free()
	robot_removed.emit(robot, reason)
	_reset_idle_warning()


func remove_all() -> void:
	for r in robots:
		r.queue_free()
	robots.clear()
	_reset_idle_warning()


## 棋盘重排（F11/改分辨率，P1-04 配套）后按缓存 coord 重写世界坐标；
## 移动途中的 tween 目标是旧坐标，由下一次移动 tick 自然校正（亚秒级视觉差，可接受）
func reproject_all(grid) -> void:
	for r in robots:
		if is_instance_valid(r):
			r.position = grid.coord_to_world(r.coord)


## L5 火区点燃震退（WP4）：区内机器人瞬移到 BFS 最近的无阻断已开格（Q3：不做飞行轨迹，
## 靠爆炸动效顺序读「被震退」）
func displace_robots_in(coords: Array, grid) -> void:
	if coords.is_empty() or grid == null:
		return
	var hot: Dictionary = {}
	for c in coords:
		hot[c] = true
	for r in robots:
		if not hot.has(r.coord):
			continue
		var dest := _nearest_free_cell(r.coord, grid, hot)
		if dest != r.coord:
			r.snap_to(dest, grid)


func _nearest_free_cell(from: Vector2i, grid, hot: Dictionary) -> Vector2i:
	# BFS：起点自身被阻断时从 4 邻展开，找最近的 is_walkable 格
	var queue: Array = [from]
	var visited: Dictionary = {from: true}
	while not queue.is_empty():
		var pos: Vector2i = queue.pop_front()
		if pos != from and grid.is_walkable(pos) and not hot.has(pos):
			return pos
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = pos + o
			if not visited.has(n) and grid.cells.has(n):
				visited[n] = true
				queue.append(n)
	return from  # 全场阻断的极端兜底：原地（火必退，不永久死锁）


func get_robot_positions() -> Dictionary:
	var positions: Dictionary = {}
	for r in robots:
		positions[r.coord] = r
	return positions


func tick_all(delta: float, grid) -> void:
	var locked: Dictionary = GameState.locked_targets
	var any_busy: bool = false
	for robot in robots:
		robot.accumulate_and_maybe_tick(delta, grid, locked)
		if not robot.is_idle():
			any_busy = true

	if robots.is_empty():
		_reset_idle_warning()
		return

	if any_busy:
		_reset_idle_warning()
	else:
		_all_idle_seconds += delta
		GameState.result_stats["stall_seconds"] += delta  # L4 埋点：全场停摆累计时长
		if _all_idle_seconds >= IDLE_WARNING_THRESHOLD and not _idle_warning_on:
			_idle_warning_on = true
			idle_warning_changed.emit(true)


func _reset_idle_warning() -> void:
	_all_idle_seconds = 0.0
	if _idle_warning_on:
		_idle_warning_on = false
		idle_warning_changed.emit(false)
