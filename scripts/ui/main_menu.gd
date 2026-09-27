extends Panel
## 主菜单：局外成长 hub，每局经过
## 矿石商店已抽成共享面板 OreShop（选关页间场共用同一数据源），此处只留入口按钮

signal start_requested
signal stats_requested
signal daily_requested
signal signin_requested
signal settings_requested
signal powerup_requested

@onready var ore_label: Label = $MarginContainer/CenterContainer/VBoxContainer/OreLabel
@onready var start_button: Button = $MarginContainer/CenterContainer/VBoxContainer/StartButton
@onready var powerup_button: Button = $MarginContainer/CenterContainer/VBoxContainer/PowerUpButton


func _ready() -> void:
	SaveSystem.ore_changed.connect(func(_v): _refresh_ore())
	SaveSystem.unlock_changed.connect(func(_k): _refresh_ore())
	start_button.pressed.connect(func(): start_requested.emit())
	powerup_button.pressed.connect(func(): powerup_requested.emit())
	var menu_row: HBoxContainer = $MarginContainer/CenterContainer/VBoxContainer/MenuRow
	menu_row.get_node("StatsButton").pressed.connect(func(): stats_requested.emit())
	menu_row.get_node("DailyButton").pressed.connect(func(): daily_requested.emit())
	menu_row.get_node("SignInButton").pressed.connect(func(): signin_requested.emit())
	menu_row.get_node("SettingsButton").pressed.connect(func(): settings_requested.emit())
	_refresh_ore()


func _refresh_ore() -> void:
	ore_label.text = "总矿石: %d" % SaveSystem.ore
