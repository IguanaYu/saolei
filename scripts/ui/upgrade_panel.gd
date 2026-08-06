extends Panel
## 局内升级面板：金钱购买的速度 + 折扣（仅当局有效）

const SPEED_LEVELS := [2.0, 1.5, 1.0]
const SPEED_PRICES := [100, 200, -1]  # -1 表示已满级
const DISCOUNT_LEVELS := [0, 25, 50]
const DISCOUNT_PRICES := [200, 500, -1]

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
	btn.pressed.connect(func() -> void: _try_buy(upgrade_id))


func _try_buy(upgrade_id: String) -> void:
	var current_level: int = _get_level(upgrade_id)
	var prices: Array = _get_prices(upgrade_id)
	if current_level >= prices.size() - 1:
		return
	var price: int = prices[current_level]
	if price < 0:
		return
	if GameState.money < price:
		return
	GameState.add_money(-price)
	_set_level(upgrade_id, current_level + 1)
	GameState.upgrade_changed.emit(upgrade_id, current_level + 1)
	_refresh_all()


func _get_level(upgrade_id: String) -> int:
	match upgrade_id:
		"opener_speed": return GameState.opener_speed_level
		"marker_speed": return GameState.marker_speed_level
		"discount": return GameState.discount_level
	return 0


func _set_level(upgrade_id: String, lvl: int) -> void:
	match upgrade_id:
		"opener_speed": GameState.opener_speed_level = lvl
		"marker_speed": GameState.marker_speed_level = lvl
		"discount": GameState.discount_level = lvl


func _get_prices(upgrade_id: String) -> Array:
	match upgrade_id:
		"opener_speed", "marker_speed": return SPEED_PRICES
		"discount": return DISCOUNT_PRICES
	return []


func _on_money_changed(_v: int) -> void:
	_refresh_all()


func _refresh_all() -> void:
	_refresh_row(opener_speed_row, "opener_speed")
	_refresh_row(marker_speed_row, "marker_speed")
	_refresh_row(discount_row, "discount")


func _refresh_row(row: HBoxContainer, upgrade_id: String) -> void:
	var lvl: int = _get_level(upgrade_id)
	var prices: Array = _get_prices(upgrade_id)
	var level_label: Label = row.get_node("LevelLabel")
	var buy_button: Button = row.get_node("BuyButton")

	if upgrade_id == "discount":
		level_label.text = "Lv%d (-%d%%)" % [lvl, DISCOUNT_LEVELS[lvl]]
	else:
		level_label.text = "Lv%d (%.1fs)" % [lvl, SPEED_LEVELS[lvl]]

	if lvl >= 2:
		buy_button.text = "已满级"
		buy_button.disabled = true
	else:
		var next_price: int = prices[lvl]
		if upgrade_id == "discount":
			buy_button.text = "→Lv%d (-%d%%) ¥%d" % [lvl + 1, DISCOUNT_LEVELS[lvl + 1], next_price]
		else:
			buy_button.text = "→Lv%d (%.1fs) ¥%d" % [lvl + 1, SPEED_LEVELS[lvl + 1], next_price]
		buy_button.disabled = GameState.money < next_price