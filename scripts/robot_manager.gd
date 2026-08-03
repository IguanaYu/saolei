class_name RobotManager
extends Node2D
## 管理所有机器人；串行调度避免 race

const ROBOT_SCENE := preload("res://scenes/Robot.tscn")
const DETECTOR_ROBOT_SCENE := preload("res://scenes/DetectorRobot.tscn")
const MINER_ROBOT_SCENE := preload("res://scenes/MinerRobot.tscn")
const IDLE_WARNING_THRESHOLD := 3.0  # 所有机器人连续 idle 超过这个秒数就报警

signal idle_warning_changed(show: bool)
signal robot_removed(robot, reason: String)

var robots: Array = []

var _all_idle_seconds: float = 0.0
var _idle_warning_on: bool = false


func spawn_robot(start_coord: Vector2i, robot_type: String, grid) -> Robot:
	var robot: Robot
	match robot_type:
		"detector": robot = DETECTOR_ROBOT_SCENE.instantiate()
		"miner": robot = MINER_ROBOT_SCENE.instantiate()
		_: robot = ROBOT_SCENE.instantiate()
	add_child(robot)
	robot.robot_type = robot_type
	robot._update_visual()
	robot.set_initial_position(start_coord, grid)
	robots.append(robot)
	# 新机器人入场，清除空闲警告
	_reset_idle_warning()
	return robot


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


func get_robot_positions() -> Dictionary:
	var positions: Dictionary = {}
	for r in robots:
		positions[r.coord] = r
	return positions


func tick_all(delta: float, grid) -> void:
	var locked: Dictionary = GameState.locked_targets
	var positions: Dictionary = get_robot_positions()
	var any_busy: bool = false
	for robot in robots:
		positions[robot.coord] = robot  # 动态更新，避免两机器人挤一格
		robot.accumulate_and_maybe_tick(delta, grid, locked, positions)
		if not robot.is_idle():
			any_busy = true

	if robots.is_empty():
		_reset_idle_warning()
		return

	if any_busy:
		_reset_idle_warning()
	else:
		_all_idle_seconds += delta
		if _all_idle_seconds >= IDLE_WARNING_THRESHOLD and not _idle_warning_on:
			_idle_warning_on = true
			idle_warning_changed.emit(true)


func _reset_idle_warning() -> void:
	_all_idle_seconds = 0.0
	if _idle_warning_on:
		_idle_warning_on = false
		idle_warning_changed.emit(false)
