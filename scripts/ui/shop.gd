extends Control
## 底部商店（封闭试玩版两行）：四设备卡（价格/差额/台数/禁买原因）+ 建基地/局内升级/操作说明

signal upgrade_open_requested  # 局内升级按钮 → main 统一开浮层（不再硬路径取面板）

@onready var buy_opener_button: Button = $MarginContainer/VBoxContainer/DeviceFlow/BuyOpenerButton
@onready var buy_marker_button: Button = $MarginContainer/VBoxContainer/DeviceFlow/BuyMarkerButton
@onready var buy_detector_button: Button = $MarginContainer/VBoxContainer/DeviceFlow/BuyDetectorButton
@onready var buy_miner_button: Button = $MarginContainer/VBoxContainer/DeviceFlow/BuyMinerButton
@onready var buy_guard_button: Button = $MarginContainer/VBoxContainer/DeviceFlow/BuyGuardButton
@onready var buy_probe_button: Button = $MarginContainer/VBoxContainer/DeviceFlow/BuyProbeButton
@onready var buy_refractor_wide_button: Button = $MarginContainer/VBoxContainer/DeviceFlow/BuyRefractorWideButton
@onready var buy_refractor_scatter_button: Button = $MarginContainer/VBoxContainer/DeviceFlow/BuyRefractorScatterButton
@onready var buy_overload_button: Button = $MarginContainer/VBoxContainer/DeviceFlow/BuyOverloadButton
@onready var upgrade_button: Button = $MarginContainer/VBoxContainer/BuildRow/UpgradeButton
@onready var build_base_button: Button = $MarginContainer/VBoxContainer/BuildRow/BuildBaseButton
@onready var rules_button: Button = $MarginContainer/VBoxContainer/BuildRow/RulesButton
@onready var hint_label: Label = $MarginContainer/VBoxContainer/HintLabel
@onready var key_hint_bar: HBoxContainer = $MarginContainer/VBoxContainer/KeyHintBar


const BUTTON_ICONS := {
	"opener": preload("res://visual_v2/runtime/ui/icons/icon_robot_opener.png"),
	"marker": preload("res://visual_v2/runtime/ui/icons/icon_robot_marker.png"),
	"detector": preload("res://visual_v2/runtime/ui/icons/icon_robot_detector.png"),
	"miner": preload("res://visual_v2/runtime/ui/icons/icon_robot_miner.png"),
	"guard": preload("res://visual_v2/runtime/completion/ui/icons/icon_robot_guard.png"),
	"probe": preload("res://visual_v2/runtime/completion/ui/icons/icon_probe.png"),
	"base": preload("res://visual_v2/runtime/completion/ui/icons/icon_base.png"),
	"upgrade": preload("res://visual_v2/runtime/ui/icons/icon_upgrade.png"),
}

## 提示行：放置模式显示放置提示（P2-03 费用/落点文案），平时显示常驻快捷键行；text 非空则更新文案
func set_placing_hint(show: bool, text := "") -> void:
	if text != "":
		hint_label.text = text
	hint_label.visible = show
	key_hint_bar.visible = not show


func _ready() -> void:
	buy_opener_button.icon = BUTTON_ICONS.opener
	buy_marker_button.icon = BUTTON_ICONS.marker
	buy_detector_button.icon = BUTTON_ICONS.detector
	buy_miner_button.icon = BUTTON_ICONS.miner
	buy_guard_button.icon = BUTTON_ICONS.guard
	buy_probe_button.icon = BUTTON_ICONS.probe
	upgrade_button.icon = BUTTON_ICONS.upgrade
	buy_refractor_wide_button.icon = BUTTON_ICONS.guard  # 程序占位：暂借保安图标
	buy_refractor_scatter_button.icon = BUTTON_ICONS.guard
	buy_overload_button.icon = BUTTON_ICONS.guard  # 改版 2-4：程序占位，素材批后换
	build_base_button.icon = BUTTON_ICONS.base
	buy_opener_button.pressed.connect(_on_buy_opener)
	buy_marker_button.pressed.connect(_on_buy_marker)
	buy_detector_button.pressed.connect(_on_buy_detector)
	buy_miner_button.pressed.connect(_on_buy_miner)
	buy_guard_button.pressed.connect(_on_buy_guard)
	buy_probe_button.pressed.connect(_on_buy_probe)
	buy_refractor_wide_button.pressed.connect(func(): _buy_refractor("refractor_wide"))
	buy_refractor_scatter_button.pressed.connect(func(): _buy_refractor("refractor_scatter"))
	# 改版 2-4 过载机器人：直购直出基地出厂（不走放置流，拍板 #10）
	buy_overload_button.pressed.connect(func(): _buy("overload"))
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


func _on_buy_guard() -> void:
	_buy("guard")


## 2-3 折光机器人：购买=进放置模式选驻点（已开安全格），确认落位才扣钱
func _buy_refractor(robot_type: String) -> void:
	if lock_reason(robot_type) != "":
		return
	if GameState.money < GameState.get_robot_price(robot_type):
		return
	var main := get_node("/root/Main")
	main.call("_enter_placing_mode", robot_type)


## 探测不是实体机器人：不进 purchase_robot 价格阶梯，直接进放置模式（瞬发 100/次）
func _on_buy_probe() -> void:
	if GameState.money < GameState.PROBE_PRICE:
		return
	var main := get_node("/root/Main")
	main.call("_enter_placing_mode", "probe")


func _buy(robot_type: String) -> void:
	try_buy(robot_type)


## 购买入口（按钮/快捷键共用）：直购直出，成功=机器人已在基地旁出生
func try_buy(robot_type: String) -> bool:
	if not can_buy(robot_type):
		return false
	var main := get_node("/root/Main")
	return main.call("_buy_and_spawn_robot", robot_type)


func can_buy(robot_type: String) -> bool:
	if lock_reason(robot_type) != "":
		return false
	if GameState.money < GameState.get_robot_price(robot_type):
		return false
	return true


## 返回未解锁/禁用原因，"" 表示可购买
func lock_reason(robot_type: String) -> String:
	var lvl: LevelData = GameState.get_current_level()
	if lvl != null and lvl.shop_hidden.has(robot_type):
		return "本关未开放"  # 按数字键快购也不能绕过关卡隐藏（如某关隐藏检测型）
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
	# 关卡限购（LevelData.shop_limits，空 = 不限；现用：L4/L5 保安限购 1）
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
	upgrade_open_requested.emit()


func _on_money_changed(_v: int) -> void:
	_refresh_prices()


func _refresh_prices() -> void:
	_apply_level_shop_config()
	_refresh_one(buy_opener_button, "opener", "开墙型")
	_refresh_one(buy_marker_button, "marker", "标雷型")
	_refresh_one(buy_detector_button, "detector", "检测型")
	_refresh_one(buy_miner_button, "miner", "矿工型")
	_refresh_one(buy_guard_button, "guard", "保安")
	if buy_probe_button.visible:
		buy_probe_button.disabled = GameState.money < GameState.PROBE_PRICE
	_refresh_one(buy_refractor_wide_button, "refractor_wide", "折光·宽束")
	_refresh_one(buy_refractor_scatter_button, "refractor_scatter", "折光·散射")
	_refresh_one(buy_overload_button, "overload", "过载")
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


## 关卡级商店配置：隐藏本关不出现的按钮（教学关只留 opener/marker，钱不可能花错）；
## shop_extra 反向开闸：guard/probe 默认隐藏，L4/L5 声明后可见（level_data.gd 口径）
func _apply_level_shop_config() -> void:
	var lvl: LevelData = GameState.get_current_level()
	var hidden: Array = lvl.shop_hidden if lvl != null else []
	var extra: Array = lvl.shop_extra if lvl != null else []
	build_base_button.visible = not hidden.has("base")
	upgrade_button.visible = not hidden.has("upgrade")
	buy_detector_button.visible = not hidden.has("detector")
	buy_miner_button.visible = not hidden.has("miner")
	buy_guard_button.visible = extra.has("guard") and not hidden.has("guard")
	buy_probe_button.visible = extra.has("probe") and not hidden.has("probe")
	buy_refractor_wide_button.visible = extra.has("refractor_wide") and not hidden.has("refractor_wide")
	buy_refractor_scatter_button.visible = extra.has("refractor_scatter") and not hidden.has("refractor_scatter")
	buy_overload_button.visible = extra.has("overload") and not hidden.has("overload")
