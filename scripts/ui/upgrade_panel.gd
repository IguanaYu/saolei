extends Panel
## 局内升级面板：金钱购买的速度 + 折扣（仅当局有效）
## 价格/档位/可见性由关卡配置注入（LevelData），默认值见 GameState 常量

const DISCOUNT_LEVELS := [0, 25, 50]

@onready var opener_speed_row = $MarginContainer/VBoxContainer/OpenerSpeedRow
@onready var marker_speed_row = $MarginContainer/VBoxContainer/MarkerSpeedRow
@onready var discount_row = $MarginContainer/VBoxContainer/DiscountRow
@onready var close_button: Button = $MarginContainer/VBoxContainer/CloseButton


func _ready() -> void:
	hide()
	GameState.money_changed.connect(_on_money_changed)
	GameState.upgrade_changed.connect(func(_id, _lv): _refresh_all())
	close_button.pressed.connect(hide)
	_bind_row(opener_speed_row, "opener_speed")
	_bind_row(marker_speed_row, "marker_speed")
	_bind_row(discount_row, "discount")
	_refresh_all()


func _bind_row(row: HBoxContainer, upgrade_id: String) -> void:
	var btn: Button = row.get_node("BuyButton")
	btn.pressed.connect(func() -> void: GameState.purchase_upgrade(upgrade_id))


func _on_money_changed(_v: int) -> void:
	_refresh_all()


func _refresh_all() -> void:
	var lvl: LevelData = GameState.get_current_level()
	var hidden: Array = lvl.upgrades_hidden if lvl != null else []
	discount_row.visible = not hidden.has("discount")
	_refresh_row(opener_speed_row, "opener_speed")
	_refresh_row(marker_speed_row, "marker_speed")
	_refresh_row(discount_row, "discount")


func _refresh_row(row: HBoxContainer, upgrade_id: String) -> void:
	var lvl: int = GameState.get_upgrade_level(upgrade_id)
	var prices: Array = GameState.get_upgrade_prices(upgrade_id)
	var tiers: Array = DISCOUNT_LEVELS if upgrade_id == "discount" else GameState.get_speed_levels()
	var level_label: Label = row.get_node("LevelLabel")
	var buy_button: Button = row.get_node("BuyButton")

	if upgrade_id == "discount":
		level_label.text = "Lv%d (-%d%%)" % [lvl, tiers[mini(lvl, tiers.size() - 1)]]
	else:
		level_label.text = "Lv%d (%.1fs)" % [lvl, tiers[mini(lvl, tiers.size() - 1)]]

	if lvl >= prices.size() or lvl >= tiers.size() - 1:
		buy_button.text = "已满级"
		buy_button.disabled = true
		return
	var next_price: int = prices[lvl]
	if upgrade_id == "discount":
		buy_button.text = "→Lv%d (-%d%%) ¥%d" % [lvl + 1, tiers[lvl + 1], next_price]
	else:
		buy_button.text = "→Lv%d (%.1fs) ¥%d" % [lvl + 1, tiers[lvl + 1], next_price]
	buy_button.disabled = GameState.money < next_price
