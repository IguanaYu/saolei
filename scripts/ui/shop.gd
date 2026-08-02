extends Control
## 底部商店：买机器人 + 打开升级面板

@onready var buy_opener_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/BuyOpenerButton
@onready var buy_marker_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/BuyMarkerButton
@onready var upgrade_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/UpgradeButton
@onready var hint_label: Label = $MarginContainer/VBoxContainer/HintLabel


func set_placing_hint(show: bool) -> void:
	hint_label.visible = show


func _ready() -> void:
	buy_opener_button.pressed.connect(_on_buy_opener)
	buy_marker_button.pressed.connect(_on_buy_marker)
	upgrade_button.pressed.connect(_on_upgrade)
	GameState.money_changed.connect(_on_money_changed)
	GameState.upgrade_changed.connect(_on_money_changed)
	_refresh_prices()


func _on_buy_opener() -> void:
	_buy("opener")


func _on_buy_marker() -> void:
	_buy("marker")


func _buy(robot_type: String) -> void:
	if GameState.money < GameState.get_robot_price(robot_type):
		return
	var main := get_node("/root/Main")
	main.call("_enter_placing_mode", robot_type)


func _on_upgrade() -> void:
	var panel = get_node("/root/Main/UILayer/UpgradePanel")
	panel.show()


func _on_money_changed(_v: int) -> void:
	_refresh_prices()


func _refresh_prices() -> void:
	_refresh_one(buy_opener_button, "opener", "开墙型")
	_refresh_one(buy_marker_button, "marker", "标雷型")


func _refresh_one(btn: Button, robot_type: String, display_name: String) -> void:
	var price := GameState.get_robot_price(robot_type)
	btn.text = "%s ¥%d" % [display_name, price]
	btn.disabled = GameState.money < price
