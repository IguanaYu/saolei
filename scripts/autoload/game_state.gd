extends Node
## 全局状态单例 + 信号总线
## 所有跨模块的状态变化都通过这里中转

# ---- 公开状态 ----
var money: int = 50
var score: int = 0
var lives: int = 3
var time_left: float = 60.0
var game_active: bool = false

# 升级等级（0-2）
var opener_speed_level: int = 0
var marker_speed_level: int = 0
var discount_level: int = 0

# 已购买机器人计数（用于价格递增）
var opener_count: int = 0
var marker_count: int = 0

# 全局锁定目标集合（Vector2i → Robot 实例）
var locked_targets: Dictionary = {}

# ---- 信号总线 ----
signal money_changed(new_value: int)
signal score_changed(new_value: int)
signal lives_changed(new_value: int)
signal time_changed(new_value: float)
signal game_over(result: String)  # "win" | "lose" | "timeout"
signal upgrade_changed(upgrade_id: String, new_level: int)


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
	money = 50
	score = 0
	lives = 3
	time_left = 60.0
	game_active = false
	opener_speed_level = 0
	marker_speed_level = 0
	discount_level = 0
	opener_count = 0
	marker_count = 0
	locked_targets.clear()
	money_changed.emit(money)
	score_changed.emit(score)
	lives_changed.emit(lives)
	time_changed.emit(time_left)


func get_robot_price(robot_type: String) -> int:
	var count: int = opener_count if robot_type == "opener" else marker_count
	var base: int = 50 * (1 << count)
	var discount: float = [1.0, 0.75, 0.5][discount_level]
	return int(base * discount)


func purchase_robot(robot_type: String) -> bool:
	var price: int = get_robot_price(robot_type)
	if money < price:
		return false
	add_money(-price)
	if robot_type == "opener":
		opener_count += 1
	else:
		marker_count += 1
	return true


func get_speed_interval(robot_type: String) -> float:
	var level: int = opener_speed_level if robot_type == "opener" else marker_speed_level
	return [2.0, 1.5, 1.0][level]
