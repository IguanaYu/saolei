extends Control
## 底部商店：买机器人 + 建造 + 打开升级面板

@onready var buy_opener_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/BuyOpenerButton
@onready var buy_marker_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/BuyMarkerButton
@onready var buy_detector_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/BuyDetectorButton
@onready var buy_miner_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/BuyMinerButton
@onready var upgrade_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/UpgradeButton
@onready var build_base_button: Button = $MarginContainer/VBoxContainer/BuildRow/BuildBaseButton
@onready var drone_button: Button = $MarginContainer/VBoxContainer/BuildRow/DroneButton
@onready var hint_label: Label = $MarginContainer/VBoxContainer/HintLabel
@onready var debug_button: Button = $MarginContainer/VBoxContainer/DebugButton


func set_placing_hint(show: bool) -> void:
	hint_label.visible = show


func _ready() -> void:
	buy_opener_button.pressed.connect(_on_buy_opener)
	buy_marker_button.pressed.connect(_on_buy_marker)
	buy_detector_button.pressed.connect(_on_buy_detector)
	buy_miner_button.pressed.connect(_on_buy_miner)
	upgrade_button.pressed.connect(_on_upgrade)
	build_base_button.pressed.connect(_on_build_base)
	drone_button.pressed.connect(_on_trigger_drone)
	debug_button.pressed.connect(_on_debug_button)
	GameState.money_changed.connect(_on_money_changed)
	GameState.upgrade_changed.connect(func(_id, _lv): _refresh_prices())
	GameState.base_placed.connect(func(_c): _refresh_prices())
	SaveSystem.unlock_changed.connect(func(_k): _refresh_prices())
	_refresh_prices()


func _on_buy_opener() -> void:
	_buy("opener")


func _on_buy_marker() -> void:
	_buy("marker")


func _on_buy_detector() -> void:
	_buy("detector")


func _on_buy_miner() -> void:
	_buy("miner")


func _on_debug_button() -> void:
	GameState.add_money(200)


func _buy(robot_type: String) -> void:
	try_buy(robot_type)


## 快捷按键入口：成功进入放置模式返回 true
func try_buy(robot_type: String) -> bool:
	if not can_buy(robot_type):
		return false
	var main := get_node("/root/Main")
	main.call("_enter_placing_mode", robot_type)
	return true


func can_buy(robot_type: String) -> bool:
	if lock_reason(robot_type) != "":
		return false
	if GameState.money < GameState.get_robot_price(robot_type):
		return false
	return true


## 返回未解锁/禁用原因，"" 表示可购买
func lock_reason(robot_type: String) -> String:
	if robot_type == "detector":
		if not bool(SaveSystem.unlocks.get("detector", false)):
			return "检测型未解锁（通 2-5）"
		if not GameState.is_module_allowed("detector"):
			return "本关禁用检测型"
	if robot_type == "miner":
		if not bool(SaveSystem.unlocks.get("miner", false)):
			return "矿工未解锁（通 3-5）"
		if not GameState.is_module_allowed("miner"):
			return "本关禁用矿工型"
	return ""


func _on_build_base() -> void:
	if GameState.money < GameState.get_base_price():
		return
	var main := get_node("/root/Main")
	main.call("_enter_placing_mode", "base")


func _on_trigger_drone() -> void:
	if GameState.money < 100:
		return
	var main := get_node("/root/Main")
	main.call("_trigger_drone")


func _on_upgrade() -> void:
	var panel = get_node("/root/Main/UILayer/UpgradePanel")
	panel.show()


func _on_money_changed(_v: int) -> void:
	_refresh_prices()


func _refresh_prices() -> void:
	_refresh_one(buy_opener_button, "opener", "开墙型")
	_refresh_one(buy_marker_button, "marker", "标雷型")
	_refresh_one(buy_detector_button, "detector", "检测型")
	_refresh_one(buy_miner_button, "miner", "矿工型")
	# 基地价格递增：第 1 个 80，第 2 个 160 ...
	var base_price: int = GameState.get_base_price()
	build_base_button.text = "建基地 ¥%d" % base_price
	build_base_button.disabled = GameState.money < base_price
	var drone_unlocked: bool = bool(SaveSystem.unlocks.get("drone", false))
	drone_button.text = "🔒 无人机" if not drone_unlocked else "无人机 ¥100"
	drone_button.disabled = not drone_unlocked or GameState.money < 100


func _refresh_one(btn: Button, robot_type: String, display_name: String) -> void:
	if lock_reason(robot_type) != "":
		btn.text = "🔒 %s" % display_name
		btn.disabled = true
		return
	var price: int = GameState.get_robot_price(robot_type)
	btn.text = "%s ¥%d" % [display_name, price]
	btn.disabled = GameState.money < price
