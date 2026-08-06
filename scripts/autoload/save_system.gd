extends Node
## 存档系统 autoload 单例：矿石 + 解锁状态持久化
## JSON 存档路径 user://save_data.json

const SAVE_PATH := "user://save_data.json"

var ore: int = 0

# 局外升级等级（int）或解锁状态（bool）
var unlocks: Dictionary = {
	"start_money": 0,    # 起始金币加成，每级 +50，max 2
	"start_lives": 0,    # 起始额外生命，每级 +1，max 2
	"global_speed": 0,   # 全局速度加成，每级提速，max 2
	"expand_zone": 0,    # 安全区扩大，每级 +1 半径，max 2
	"start_robot": 0,    # 开局送机器人，每级 +1，max 2
	"detector": false,   # 解锁检测型
	"miner": false,      # 解锁矿工型
}

signal ore_changed(new_ore: int)
signal unlock_changed(key: String)


func _ready() -> void:
	load_game()


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("存档损坏，使用默认值")
		return
	ore = int(data.get("ore", 0))
	var saved: Dictionary = data.get("unlocks", {})
	# 逐字段合并，兼容旧存档
	for key in unlocks:
		if saved.has(key):
			unlocks[key] = saved[key]
	ore_changed.emit(ore)


func save_game() -> void:
	var data = {"version": 2, "ore": ore, "unlocks": unlocks}
	var f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("无法写入存档")
		return
	f.store_string(JSON.stringify(data, "  "))


func add_ore(amount: int) -> void:
	ore += amount
	ore_changed.emit(ore)
	save_game()


func spend_ore(amount: int) -> bool:
	if ore < amount:
		return false
	ore -= amount
	ore_changed.emit(ore)
	save_game()
	return true


## 购买局外升级，返回是否成功
func purchase_unlock(key: String, cost: int) -> bool:
	if not unlocks.has(key):
		return false
	var current = unlocks[key]
	if typeof(current) == TYPE_BOOL:
		if current:
			return false  # 已解锁
		if not spend_ore(cost):
			return false
		unlocks[key] = true
		unlock_changed.emit(key)
		save_game()
		return true
	else:
		# int 类型，最高 2 级
		if current >= 2:
			return false
		if not spend_ore(cost):
			return false
		unlocks[key] = current + 1
		unlock_changed.emit(key)
		save_game()
		return true
