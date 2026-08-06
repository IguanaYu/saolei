extends Panel
## 主菜单：局外成长 hub，每局经过
## 显示矿石余额 + 局外升级树 + 开始游戏按钮

# int 类型升级：[level0→1 cost, level1→2 cost]
const ORE_INT_COSTS := {
	"start_money": [50, 100],
	"start_lives": [80, 160],
	"global_speed": [100, 200],
	"expand_zone": [100, 200],
}
# bool 类型解锁（一次性）
const ORE_BOOL_COSTS := {
	"detector": 150,
	"miner": 120,
}

const ORE_DISPLAY_NAMES := {
	"start_money": "起始金币",
	"start_lives": "起始生命",
	"global_speed": "全局速度",
	"expand_zone": "安全区扩大",
	"detector": "解锁检测型",
	"miner": "解锁矿工型",
}

signal start_requested

@onready var ore_label: Label = $MarginContainer/CenterContainer/VBoxContainer/OreLabel
@onready var start_money_row = $MarginContainer/CenterContainer/VBoxContainer/StartMoneyRow
@onready var start_lives_row = $MarginContainer/CenterContainer/VBoxContainer/StartLivesRow
@onready var global_speed_row = $MarginContainer/CenterContainer/VBoxContainer/GlobalSpeedRow
@onready var expand_zone_row = $MarginContainer/CenterContainer/VBoxContainer/ExpandZoneRow
@onready var unlock_detector_row = $MarginContainer/CenterContainer/VBoxContainer/UnlockDetectorRow
@onready var unlock_miner_row = $MarginContainer/CenterContainer/VBoxContainer/UnlockMinerRow
@onready var start_button: Button = $MarginContainer/CenterContainer/VBoxContainer/StartButton


func _ready() -> void:
	SaveSystem.ore_changed.connect(func(_v): _refresh_all())
	SaveSystem.unlock_changed.connect(func(_k): _refresh_all())
	_bind_ore_row(start_money_row, "start_money")
	_bind_ore_row(start_lives_row, "start_lives")
	_bind_ore_row(global_speed_row, "global_speed")
	_bind_ore_row(expand_zone_row, "expand_zone")
	_bind_ore_row(unlock_detector_row, "detector")
	_bind_ore_row(unlock_miner_row, "miner")
	start_button.pressed.connect(func(): start_requested.emit())
	_refresh_all()


func _bind_ore_row(row: HBoxContainer, key: String) -> void:
	var btn: Button = row.get_node("BuyButton")
	btn.pressed.connect(func() -> void: _try_buy_ore(key))


func _try_buy_ore(key: String) -> void:
	var cost: int = _get_ore_cost(key)
	if cost < 0:
		return
	SaveSystem.purchase_unlock(key, cost)


func _get_ore_cost(key: String) -> int:
	if ORE_INT_COSTS.has(key):
		var lvl: int = int(SaveSystem.unlocks.get(key, 0))
		if lvl >= 2:
			return -1
		return ORE_INT_COSTS[key][lvl]
	if ORE_BOOL_COSTS.has(key):
		if bool(SaveSystem.unlocks.get(key, false)):
			return -1
		return ORE_BOOL_COSTS[key]
	return -1


func _refresh_all() -> void:
	ore_label.text = "矿石: %d" % SaveSystem.ore
	_refresh_ore_row(start_money_row, "start_money")
	_refresh_ore_row(start_lives_row, "start_lives")
	_refresh_ore_row(global_speed_row, "global_speed")
	_refresh_ore_row(expand_zone_row, "expand_zone")
	_refresh_ore_row(unlock_detector_row, "detector")
	_refresh_ore_row(unlock_miner_row, "miner")


func _refresh_ore_row(row: HBoxContainer, key: String) -> void:
	var name_label: Label = row.get_node("NameLabel")
	var level_label: Label = row.get_node("LevelLabel")
	var buy_button: Button = row.get_node("BuyButton")

	name_label.text = ORE_DISPLAY_NAMES[key]

	if ORE_INT_COSTS.has(key):
		var lvl: int = int(SaveSystem.unlocks.get(key, 0))
		match key:
			"start_money":
				level_label.text = "Lv%d (+%d金币)" % [lvl, lvl * 50]
			"start_lives":
				level_label.text = "Lv%d (+%d命)" % [lvl, lvl]
			_:
				level_label.text = "Lv%d" % lvl
		if lvl >= 2:
			buy_button.text = "已满级"
			buy_button.disabled = true
		else:
			var cost: int = ORE_INT_COSTS[key][lvl]
			buy_button.text = "→Lv%d %d矿" % [lvl + 1, cost]
			buy_button.disabled = SaveSystem.ore < cost
	else:
		var unlocked: bool = bool(SaveSystem.unlocks.get(key, false))
		if unlocked:
			level_label.text = "已解锁"
			buy_button.text = "已拥有"
			buy_button.disabled = true
		else:
			level_label.text = "未解锁"
			var cost: int = ORE_BOOL_COSTS[key]
			buy_button.text = "解锁 %d矿" % cost
			buy_button.disabled = SaveSystem.ore < cost