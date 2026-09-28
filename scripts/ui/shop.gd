extends Control
## 底部商店（封闭试玩版两行）：四设备卡（价格/差额/台数/禁买原因）+ 建基地/局内升级/操作说明

@onready var buy_opener_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/BuyOpenerButton
@onready var buy_marker_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/BuyMarkerButton
@onready var buy_detector_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/BuyDetectorButton
@onready var buy_miner_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/BuyMinerButton
@onready var upgrade_button: Button = $MarginContainer/VBoxContainer/BuildRow/UpgradeButton
@onready var build_base_button: Button = $MarginContainer/VBoxContainer/BuildRow/BuildBaseButton
@onready var rules_button: Button = $MarginContainer/VBoxContainer/BuildRow/RulesButton
@onready var hint_label: Label = $MarginContainer/VBoxContainer/HintLabel


const BUTTON_ICONS := {
	"opener": preload("res://visual_v2/runtime/ui/icons/icon_robot_opener.png"),
	"marker": preload("res://visual_v2/runtime/ui/icons/icon_robot_marker.png"),
	"detector": preload("res://visual_v2/runtime/ui/icons/icon_robot_detector.png"),
	"miner": preload("res://visual_v2/runtime/ui/icons/icon_robot_miner.png"),
	"base": preload("res://visual_v2/runtime/ui/icons/icon_base.png"),
	"upgrade": preload("res://visual_v2/runtime/ui/icons/icon_upgrade.png"),
}


func set_placing_hint(show: bool) -> void:
	hint_label.visible = show


func _ready() -> void:
	buy_opener_button.icon = BUTTON_ICONS.opener
	buy_marker_button.icon = BUTTON_ICONS.marker
	buy_detector_button.icon = BUTTON_ICONS.detector
	buy_miner_button.icon = BUTTON_ICONS.miner
	upgrade_button.icon = BUTTON_ICONS.upgrade
	build_base_button.icon = BUTTON_ICONS.base
	buy_opener_button.pressed.connect(_on_buy_opener)
	buy_marker_button.pressed.connect(_on_buy_marker)
	buy_detector_button.pressed.connect(_on_buy_detector)
	buy_miner_button.pressed.connect(_on_buy_miner)
	upgrade_button.pressed.connect(_on_upgrade)
	build_base_button.pressed.connect(_on_build_base)
	rules_button.pressed.connect(func():
		get_node("/root/Main/UILayer/RulesPanel").open())
	GameState.money_changed.connect(_on_money_changed)
	GameState.upgrade_changed.connect(func(_id, _lv): _refresh_prices())
	GameState.base_placed.connect(func(_c): _refresh_prices())
	GameState.robot_spawned.connect(func(_t): _refresh_prices())  # 赠送/购买都会抬价格阶梯
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
	# 关卡限购（教学关：opener/marker 各 1 台）
	var lvl: LevelData = GameState.get_current_level()
	if lvl != null and lvl.shop_limits.has(robot_type):
		if GameState.get_robot_purchased_count(robot_type) >= int(lvl.shop_limits[robot_type]):
			return "已购满"
	return ""


func _on_build_base() -> void:
	if GameState.money < GameState.get_base_price():
		return
	var main := get_node("/root/Main")
	main.call("_enter_placing_mode", "base")


func _on_upgrade() -> void:
	var panel = get_node("/root/Main/UILayer/UpgradePanel")
	panel.show()


func _on_money_changed(_v: int) -> void:
	_refresh_prices()


func _refresh_prices() -> void:
	_apply_level_shop_config()
	_refresh_one(buy_opener_button, "opener", "开墙型")
	_refresh_one(buy_marker_button, "marker", "标雷型")
	_refresh_one(buy_detector_button, "detector", "检测型")
	_refresh_one(buy_miner_button, "miner", "矿工型")
	# 基地价格递增：第 1 个 80，第 2 个 160 ...
	var base_price: int = GameState.get_base_price()
	build_base_button.text = "建基地 ¥%d" % base_price
	build_base_button.disabled = GameState.money < base_price


## 设备卡：锁原因 / 价格+差额+已有台数（买不起写明差多少）
func _refresh_one(btn: Button, robot_type: String, display_name: String) -> void:
	var reason := lock_reason(robot_type)
	if reason != "":
		btn.text = "🔒 %s\n%s" % [display_name, reason]
		btn.disabled = true
		return
	var price: int = GameState.get_robot_price(robot_type)
	var owned: int = GameState.get_robot_purchased_count(robot_type)
	if GameState.money < price:
		btn.text = "%s ¥%d\n差 ¥%d · 已有 %d 台" % [display_name, price, price - GameState.money, owned]
	else:
		btn.text = "%s ¥%d\n已有 %d 台" % [display_name, price, owned]
	btn.disabled = GameState.money < price


## 关卡级商店配置：隐藏本关不出现的按钮（教学关只留 opener/marker，钱不可能花错）
func _apply_level_shop_config() -> void:
	var lvl: LevelData = GameState.get_current_level()
	var hidden: Array = lvl.shop_hidden if lvl != null else []
	build_base_button.visible = not hidden.has("base")
	upgrade_button.visible = not hidden.has("upgrade")
	buy_detector_button.visible = not hidden.has("detector")
	buy_miner_button.visible = not hidden.has("miner")
