extends Panel
## 主菜单（封闭试玩版）：主按钮直进当前进度关，两层内见棋盘
## 矿石/变强入口 L2 通关后揭示（is_level_cleared("ch01_s02")），揭示后带"新"直到进过 L3

signal continue_requested        # 直接进当前进度关（经关前卡）
signal select_level_requested
signal rules_requested
signal settings_requested
signal powerup_requested
signal feedback_requested        # 拍板暂不连接：反馈渠道未定，按钮隐藏；渠道确定后接线启用
signal quit_requested

const PLAYTEST_IDS := ["ch01_s01", "ch01_s02", "ch01_s03", "ch01_s04", "ch01_s05"]

@onready var continue_button: Button = $MarginContainer/CenterContainer/VBoxContainer/ContinueButton
@onready var ore_tag: HBoxContainer = $OreTag
@onready var ore_label: Label = $OreTag/OreLabel
@onready var powerup_button: Button = $OreTag/PowerUpButton


func _ready() -> void:
	SaveSystem.ore_changed.connect(func(_v): _refresh_ore())
	SaveSystem.unlock_changed.connect(func(_k): _refresh_ore())
	continue_button.pressed.connect(func(): continue_requested.emit())
	$MarginContainer/CenterContainer/VBoxContainer/SelectLevelButton.pressed.connect(
		func(): select_level_requested.emit())
	$MarginContainer/CenterContainer/VBoxContainer/MenuRow/RulesButton.pressed.connect(
		func(): rules_requested.emit())
	$MarginContainer/CenterContainer/VBoxContainer/MenuRow/SettingsButton.pressed.connect(
		func(): settings_requested.emit())
	powerup_button.pressed.connect(func(): powerup_requested.emit())
	$MarginContainer/CenterContainer/VBoxContainer/BottomRow/QuitButton.pressed.connect(
		func(): quit_requested.emit())
	_refresh_ore()


## 每次显示后由 main 调：按钮文字从存档推导，不能出现"继续"却回第一关
func refresh() -> void:
	# 矿石行一并兜底刷：首通 L2 时 add_ore(ore_changed) 先于 mark_cleared 到达
	# 且后者不发信号，不在这里补刷的话「升级」按钮会一直隐藏到下次矿石变动
	_refresh_ore()
	var idx := _current_index()
	continue_button.text = "开始试玩" if idx == 0 and not SaveSystem.is_level_cleared(PLAYTEST_IDS[0]) \
			else "继续试玩 · 第 %d 关" % (idx + 1)


func _current_index() -> int:
	for i in PLAYTEST_IDS.size():
		if not SaveSystem.is_level_cleared(PLAYTEST_IDS[i]):
			return i
	return PLAYTEST_IDS.size() - 1   # 全通关 → 第 5 关（拍板：重玩最后一关）


func _refresh_ore() -> void:
	# L2 通关后揭示（拍板口径）：is_level_unlocked 在试玩期恒真（全关解锁覆写），
	# 必须用通关记录判断，否则新档开局就能看到矿石/变强入口
	var show_ore: bool = SaveSystem.is_level_cleared("ch01_s02")
	ore_tag.visible = show_ore
	ore_label.text = "总矿石 %d" % SaveSystem.ore
	# 揭示时刻高亮：从没进过 L3（=刚通 L2 回到菜单）时"变强"带"新"
	powerup_button.text = "升级 · 新" if show_ore and not SaveSystem.has_entered_level("ch01_s03") \
			else "升级"
