extends Control
## A 版右侧商店：购置/升级/按需日志共享内容区，快捷购机始终可见。

signal upgrade_open_requested  # 局内升级按钮 → main 打开商店内容区的升级页
const UI := preload("res://scripts/ui/game_ui_style.gd")
var money_label: Label
var content: Control
var purchase_scroll: ScrollContainer
var records_button: Button
var player_log_button: Button
var robot_log_button: Button
var auto_button: Button
var buy_tab: Button
var _quick_buttons: Dictionary = {}
var _upgrades: Control
var _player_log: Control
var _robot_log: Control
var view := "buy"
var log_view := "player"
var robots_working := true
var _cancel_placement: Button

@onready var buy_opener_button: Button = $MarginContainer/VBoxContainer/DeviceFlow/BuyOpenerButton
@onready var buy_marker_button: Button = $MarginContainer/VBoxContainer/DeviceFlow/BuyMarkerButton
@onready var buy_detector_button: Button = $MarginContainer/VBoxContainer/DeviceFlow/BuyDetectorButton
@onready var buy_miner_button: Button = $MarginContainer/VBoxContainer/DeviceFlow/BuyMinerButton
@onready var buy_guard_button: Button = $MarginContainer/VBoxContainer/DeviceFlow/BuyGuardButton
@onready var buy_probe_button: Button = $MarginContainer/VBoxContainer/DeviceFlow/BuyProbeButton
@onready var buy_refractor_wide_button: Button = $MarginContainer/VBoxContainer/DeviceFlow/BuyRefractorWideButton
@onready var buy_refractor_scatter_button: Button = $MarginContainer/VBoxContainer/DeviceFlow/BuyRefractorScatterButton
@onready var buy_overload_button: Button = $MarginContainer/VBoxContainer/DeviceFlow/BuyOverloadButton
@onready var buy_overload_range_button: Button = $MarginContainer/VBoxContainer/DeviceFlow/BuyOverloadRangeButton
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
	"overload": preload("res://visual_v2/runtime/ch02_v1/ui/icon_overload.png"),
	"overload_range": preload("res://visual_v2/runtime/ch02_v1/ui/icon_overload_range.png"),
}

## 提示行只在放置期间显示；text 非空则更新费用/落点文案。
func set_placing_hint(show: bool, text := "") -> void:
	if text != "":
		hint_label.text = text
	hint_label.visible = show
	_cancel_placement.visible = show and get_parent().get_parent().placing_mode != ""
	_refresh_prices()
	# 快捷入口不随放置提示消失；说明行仅在正在放置时出现。


func _ready() -> void:
	_build_compact_ui()
	buy_opener_button.icon = BUTTON_ICONS.opener
	buy_marker_button.icon = BUTTON_ICONS.marker
	buy_detector_button.icon = BUTTON_ICONS.detector
	buy_miner_button.icon = BUTTON_ICONS.miner
	buy_guard_button.icon = BUTTON_ICONS.guard
	buy_probe_button.icon = BUTTON_ICONS.probe
	buy_refractor_wide_button.icon = BUTTON_ICONS.guard  # 程序占位：暂借保安图标
	buy_refractor_scatter_button.icon = BUTTON_ICONS.guard
	buy_overload_button.icon = BUTTON_ICONS.overload
	buy_overload_range_button.icon = BUTTON_ICONS.overload_range
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
	# 追加拍板 #11：过载「扩爆」一次性升级（爆炸四正各再伸 1 格；先有机器人才可买）
	buy_overload_range_button.pressed.connect(func():
		get_node("/root/Main").call("_buy_overload_range"))
	upgrade_button.pressed.connect(_on_upgrade)
	build_base_button.pressed.connect(_on_build_base)
	rules_button.pressed.connect(func():
		get_node("/root/Main/UILayer/RulesPanel").open())
	GameState.money_changed.connect(_on_money_changed)
	GameState.upgrade_changed.connect(func(_id, _lv): _refresh_prices())
	GameState.base_placed.connect(func(_c): _refresh_prices())
	GameState.robot_spawned.connect(func(_t): _refresh_prices())  # 赠送/购买都会抬价格阶梯
	GameState.game_phase_changed.connect(func(_p): _refresh_prices())
	SaveSystem.unlock_changed.connect(func(_k): _refresh_prices())
	_refresh_prices()


func _build_compact_ui() -> void:
	# 保留已绑定的按钮对象和购买逻辑，只迁移视觉树。
	$MarginContainer.hide()
	var surface := PanelContainer.new()
	surface.name = "SquadSurface"
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.add_theme_stylebox_override("panel", UI.panel())
	add_child(surface)
	var body := VBoxContainer.new()
	body.name = "SquadBody"
	body.add_theme_constant_override("separation", 12)
	surface.add_child(body)
	var heading := HBoxContainer.new()
	heading.name = "ShopHeading"
	body.add_child(heading)
	var title := UI.label("小队商店", "Title")
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	heading.add_child(title)
	heading.add_child(UI.icon(preload("res://visual_v2/runtime/ui/icons/icon_coin.png"), "Coin"))
	money_label = UI.label(str(GameState.money), "Balance", 22, UI.GOLD)
	heading.add_child(money_label)
	var tabs := HBoxContainer.new()
	tabs.name = "ShopTabs"
	body.add_child(tabs)
	buy_tab = _tab("购置", "BuyTab", tabs)
	buy_tab.pressed.connect(func(): select_view("buy"))
	upgrade_button.reparent(tabs)
	upgrade_button.text = "升级"
	upgrade_button.custom_minimum_size = Vector2(54, 34)
	UI.button(upgrade_button, 13)
	var spacer := Control.new()
	spacer.name = "TabSpacer"
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	spacer.mouse_filter = MOUSE_FILTER_IGNORE
	tabs.add_child(spacer)
	records_button = _tab("记录", "RecordsToggle", tabs)
	records_button.pressed.connect(func(): select_view("buy" if view == "logs" else "logs"))
	content = Control.new()
	content.name = "ShopContent"
	content.size_flags_vertical = SIZE_EXPAND_FILL
	content.mouse_filter = MOUSE_FILTER_IGNORE
	body.add_child(content)
	purchase_scroll = ScrollContainer.new()
	purchase_scroll.name = "PurchaseScroll"
	purchase_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	purchase_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(purchase_scroll)
	var devices := VBoxContainer.new()
	devices.name = "Purchases"
	devices.size_flags_horizontal = SIZE_EXPAND_FILL
	devices.add_theme_constant_override("separation", 8)
	purchase_scroll.add_child(devices)
	for b in [buy_opener_button, buy_marker_button, buy_detector_button, buy_miner_button,
			buy_guard_button, buy_probe_button, buy_refractor_wide_button,
			buy_refractor_scatter_button, buy_overload_button, buy_overload_range_button, build_base_button]:
		b.reparent(devices)
		b.custom_minimum_size = Vector2(0, 68)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.expand_icon = true
		UI.button(b, 13)
		var badge: Node = b.get_node_or_null("KeyBadge")
		if badge != null:
			badge.hide()  # 键位统一由下方常驻入口承载。
	var filters := HBoxContainer.new()
	filters.name = "LogFilters"
	filters.visible = false
	content.add_child(filters)
	player_log_button = _tab("你的行动", "PlayerLogTab", filters)
	robot_log_button = _tab("机器人作业", "RobotLogTab", filters)
	player_log_button.pressed.connect(func(): log_view = "player"; _refresh_view())
	robot_log_button.pressed.connect(func(): log_view = "robot"; _refresh_view())
	hint_label.reparent(body)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hint_label.add_theme_font_size_override("font_size", 12)
	_cancel_placement = _tab("取消放置", "CancelPlacement", body)
	_cancel_placement.hide()
	_cancel_placement.pressed.connect(func(): get_parent().get_parent()._exit_placing_mode())
	var quick := HBoxContainer.new()
	quick.name = "RobotShortcuts"
	quick.add_theme_constant_override("separation", 5)
	body.add_child(quick)
	var types := ["opener", "marker", "detector", "miner"]
	for i in types.size():
		var type: String = types[i]
		var b := Button.new()
		b.name = type.to_pascal_case() + "Shortcut"
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 68)
		UI.button(b, 11)
		quick.add_child(b)
		var box := VBoxContainer.new()
		box.name = "ShortcutFace"
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.offset_left = 3
		box.offset_right = -3
		box.offset_top = 6
		box.mouse_filter = MOUSE_FILTER_IGNORE
		b.add_child(box)
		var row := HBoxContainer.new()
		row.name = "KeyRow"
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.mouse_filter = MOUSE_FILTER_IGNORE
		box.add_child(row)
		row.add_child(UI.icon(BUTTON_ICONS[type], "RobotIcon", 20))
		row.add_child(UI.label(str(i + 1), "Key", 12, UI.SIGNAL))
		var caption := UI.label("", "Caption", 10)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.clip_text = true
		box.add_child(caption)
		_quick_buttons[type] = b
		b.pressed.connect(func(): try_buy(type))
	auto_button = _tab("暂停自动作业", "AutoWorkToggle", body)
	auto_button.pressed.connect(func():
		robots_working = not robots_working
		auto_button.text = "暂停自动作业" if robots_working else "启动自动作业"
		GameState.game_event_logged.emit("启动自动作业" if robots_working else "暂停自动作业", "player", "dim"))
	_refresh_view()


func _tab(text: String, node_name: String, parent: Node) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size = Vector2(0, 34)
	UI.button(b, 13)
	parent.add_child(b)
	return b


## 面板保持 UILayer 下的原路径，由商店统一分配内容矩形。
func attach_panels(upgrades: Control, player_log: Control, robot_log: Control) -> void:
	_upgrades = upgrades
	_player_log = player_log
	_robot_log = robot_log
	# 日志原先在 UILayer 最底部；移到商店之后，避免被商店底板盖住。
	get_parent().move_child(_player_log, get_index() + 1)
	get_parent().move_child(_robot_log, _player_log.get_index() + 1)
	_upgrades.visibility_changed.connect(func():
		if _upgrades.visible:
			view = "upgrade"
		elif view == "upgrade":
			view = "buy"
		_refresh_view())
	content.resized.connect(layout_panels)
	for p in [_player_log, _robot_log]:
		p.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		p.get_node("Margin/VBox/TitleLabel").hide()
		var margin: MarginContainer = p.get_node("Margin")
		for side in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 0)
		p.get_node("Margin/VBox/LogText").add_theme_font_size_override("normal_font_size", 13)
	_refresh_view()


func select_view(next: String) -> void:
	if next == "upgrade":
		upgrade_open_requested.emit()
		return
	if _upgrades != null:
		_upgrades.close()
	view = next
	_refresh_view()


func reset_view() -> void:
	select_view("buy")
	robots_working = true
	auto_button.text = "暂停自动作业"


func _refresh_view() -> void:
	if content == null:
		return
	purchase_scroll.visible = view == "buy"
	content.get_node("LogFilters").visible = view == "logs"
	for pair in [[buy_tab, "buy"], [upgrade_button, "upgrade"], [records_button, "logs"]]:
		pair[0].modulate = UI.SIGNAL if view == pair[1] else Color.WHITE
	player_log_button.modulate = UI.SIGNAL if log_view == "player" else Color.WHITE
	robot_log_button.modulate = UI.SIGNAL if log_view == "robot" else Color.WHITE
	if _player_log != null:
		_player_log.visible = view == "logs" and log_view == "player"
		_robot_log.visible = view == "logs" and log_view == "robot"
	layout_panels()


func layout_panels() -> void:
	if _upgrades == null:
		return
	var r := content.get_global_rect()
	for p in [_upgrades, _player_log, _robot_log]:
		p.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		p.position = r.position + Vector2(0, 40 if p != _upgrades else 0)
		p.size = Vector2(r.size.x, maxf(0, r.size.y - (40 if p != _upgrades else 0)))


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
	if get_parent().get_parent().placing_mode != "":
		get_parent().get_parent().hud.show_toast("请先完成或取消放置", 2)
		return false
	if not can_buy(robot_type):
		return false
	var main := get_node("/root/Main")
	return main.call("_buy_and_spawn_robot", robot_type)


func can_buy(robot_type: String) -> bool:
	if GameState.game_phase == "placing_base":
		return false
	var main := get_node_or_null("/root/Main")
	if main != null and main.placing_mode != "":
		return false
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
	select_view("buy" if view == "upgrade" else "upgrade")


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
	_refresh_overload_range()
	# 基地价格递增：第 1 个 80，第 2 个 160 ...
	var base_price: int = GameState.get_base_price()
	build_base_button.text = "新建基地  %d +\n已建 %d 座" % [base_price, GameState.base_count]
	build_base_button.disabled = GameState.game_phase == "placing_base" or GameState.money < base_price
	money_label.text = str(GameState.money)
	var names := {"opener": "开墙", "marker": "标雷", "detector": "检测", "miner": "矿工"}
	for type in _quick_buttons:
		var b: Button = _quick_buttons[type]
		var reason := lock_reason(type)
		var price: int = GameState.get_robot_price(type)
		b.disabled = not can_buy(type)
		b.modulate = Color(1, 1, 1, 0.45) if b.disabled else Color.WHITE
		b.tooltip_text = "%s · %s" % [names[type], reason if reason != "" else "%d 金币 · 已有 %d 台" % [price, GameState.get_robot_purchased_count(type)]]
		b.get_node("ShortcutFace/Caption").text = "%s\n%s" % [names[type], "未开放" if reason != "" else str(price)]


## 设备卡：锁原因 / 价格+差额+已有台数（买不起写明差多少）
func _refresh_one(btn: Button, robot_type: String, display_name: String) -> void:
	var reason := lock_reason(robot_type)
	if reason != "":
		btn.text = "%s\n%s" % [display_name, reason]
		btn.tooltip_text = reason
		btn.disabled = true
		return
	var price: int = GameState.get_robot_price(robot_type)
	var owned: int = GameState.get_robot_purchased_count(robot_type)
	if GameState.money < price:
		btn.text = "%s ×%d    %d +\n还差 %d 金币" % [display_name, owned, price, price - GameState.money]
	else:
		btn.text = "%s ×%d    %d +" % [display_name, owned, price]
	btn.tooltip_text = "%s：%d 金币，已有 %d 台" % [display_name, price, owned]
	btn.disabled = not can_buy(robot_type)


## 追加拍板 #11：「扩爆」卡——三态：未购机器人（锁）/ 可购（含差价）/ 已升级（锁）
func _refresh_overload_range() -> void:
	if not buy_overload_range_button.visible:
		return
	if GameState.overload_range_level >= 1:
		buy_overload_range_button.text = "🔒 扩爆·已升级\n17 格形态"
		buy_overload_range_button.disabled = true
		return
	if GameState.get_robot_purchased_count("overload") < 1:
		buy_overload_range_button.text = "🔒 扩爆 ¥%d\n需先购过载机器人" \
				% GameState.OVERLOAD_RANGE_PRICE
		buy_overload_range_button.disabled = true
		return
	var price: int = GameState.OVERLOAD_RANGE_PRICE
	if GameState.money < price:
		buy_overload_range_button.text = "扩爆 ¥%d\n差 ¥%d · 爆炸+1 格射程" \
				% [price, price - GameState.money]
	else:
		buy_overload_range_button.text = "扩爆 ¥%d\n爆炸+1 格射程" % price
	buy_overload_range_button.disabled = GameState.money < price


## 关卡级商店配置：隐藏本关不出现的按钮（教学关只留 opener/marker，钱不可能花错）；
## shop_extra 反向开闸：guard/probe 默认隐藏，L4/L5 声明后可见（level_data.gd 口径）
func _apply_level_shop_config() -> void:
	var lvl: LevelData = GameState.get_current_level()
	var hidden: Array = lvl.shop_hidden if lvl != null else []
	var extra: Array = lvl.shop_extra if lvl != null else []
	buy_opener_button.visible = not hidden.has("opener")
	buy_marker_button.visible = not hidden.has("marker")
	build_base_button.visible = not hidden.has("base")
	upgrade_button.visible = not hidden.has("upgrade")
	buy_detector_button.visible = not hidden.has("detector")
	buy_miner_button.visible = not hidden.has("miner")
	buy_guard_button.visible = extra.has("guard") and not hidden.has("guard")
	buy_probe_button.visible = extra.has("probe") and not hidden.has("probe")
	buy_refractor_wide_button.visible = extra.has("refractor_wide") and not hidden.has("refractor_wide")
	buy_refractor_scatter_button.visible = extra.has("refractor_scatter") and not hidden.has("refractor_scatter")
	buy_overload_button.visible = extra.has("overload") and not hidden.has("overload")
	buy_overload_range_button.visible = extra.has("overload_range") \
			and not hidden.has("overload_range")
