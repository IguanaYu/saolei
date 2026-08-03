extends Node
## 全局状态单例 + 信号总线
## 所有跨模块的状态变化都通过这里中转

# ---- 公开状态 ----
var money: int = 100
var score: int = 0
var lives: int = 3
var time_left: float = 90.0
var game_active: bool = false

# 游戏阶段：placing_base=等玩家放第一个基地 / playing=正常游戏
var game_phase: String = "placing_base"

# 升级等级（0-2）
var opener_speed_level: int = 0
var marker_speed_level: int = 0
var detector_speed_level: int = 0
var miner_speed_level: int = 0
var discount_level: int = 0

# 已购买机器人计数（用于价格递增）
var opener_count: int = 0
var marker_count: int = 0
var detector_count: int = 0
var miner_count: int = 0

# 建筑状态
var bases: Array[Vector2i] = []
var base_count: int = 0

# 全局锁定目标集合（Vector2i → Robot 实例）
var locked_targets: Dictionary = {}

# ---- 信号总线 ----
signal money_changed(new_value: int)
signal score_changed(new_value: int)
signal lives_changed(new_value: int)
signal time_changed(new_value: float)
signal game_over(result: String)  # "win" | "lose" | "timeout"
signal upgrade_changed(upgrade_id: String, new_level: int)
signal base_placed(coord: Vector2i)
signal game_phase_changed(phase: String)


func add_money(amount: int) -> void:
	money = max(0, money + amount)
	money_changed.emit(money)


func add_score(amount: int) -> void:
	score = max(0, score + amount)
	score_changed.emit(score)


func lose_life() -> void:
	lives = max(0, lives - 1)
	lives_changed.emit(lives)


func reset_state() -> void:
	money = 100
	score = 0
	lives = 3
	time_left = 90.0
	game_active = false
	game_phase = "placing_base"
	opener_speed_level = 0
	marker_speed_level = 0
	detector_speed_level = 0
	discount_level = 0
	opener_count = 0
	marker_count = 0
	detector_count = 0
	bases.clear()
	base_count = 0
	locked_targets.clear()
	money_changed.emit(money)
	score_changed.emit(score)
	lives_changed.emit(lives)
	time_changed.emit(time_left)
	game_phase_changed.emit(game_phase)


# ---- 基地 ----

func get_base_price() -> int:
	# 第 1 个 80，第 2 个 160，第 3 个 320...（base × 2^N）
	return 80 * (1 << base_count)


func purchase_base() -> bool:
	var price: int = get_base_price()
	if money < price:
		return false
	add_money(-price)
	return true


func register_base(coord: Vector2i) -> void:
	if bases.has(coord):
		return
	bases.append(coord)
	base_count += 1
	base_placed.emit(coord)


## 返回离指定坐标最近的基地，没有则返回 null
func get_nearest_base(coord: Vector2i):
	if bases.is_empty():
		return null
	var nearest = bases[0]
	var best_dist: int = abs(coord.x - nearest.x) + abs(coord.y - nearest.y)
	for b in bases:
		var d: int = abs(coord.x - b.x) + abs(coord.y - b.y)
		if d < best_dist:
			best_dist = d
			nearest = b
	return nearest


func set_game_phase(phase: String) -> void:
	if game_phase == phase:
		return
	game_phase = phase
	game_phase_changed.emit(phase)


func get_robot_price(robot_type: String) -> int:
	var count: int = 0
	var base: int = 50
	match robot_type:
		"opener": count = opener_count; base = 50
		"marker": count = marker_count; base = 50
		"detector": count = detector_count; base = 80
		"miner": count = miner_count; base = 60
	base *= 1 << count
	var discount: float = [1.0, 0.75, 0.5][discount_level]
	return int(base * discount)


func purchase_robot(robot_type: String) -> bool:
	var price: int = get_robot_price(robot_type)
	if money < price:
		return false
	add_money(-price)
	match robot_type:
		"opener": opener_count += 1
		"marker": marker_count += 1
		"detector": detector_count += 1
		"miner": miner_count += 1
	return true


func get_speed_interval(robot_type: String) -> float:
	var level: int = 0
	match robot_type:
		"opener": level = opener_speed_level
		"marker": level = marker_speed_level
		"detector": level = detector_speed_level
		"miner": level = miner_speed_level
	return [2.0, 1.5, 1.0][level]
