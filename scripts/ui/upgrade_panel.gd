extends Panel
## 局内升级面板：金钱购买的速度 + 折扣（仅当局有效）
## 价格/档位/可见性由关卡配置注入（LevelData），默认值见 GameState 常量
## 行按当前关 upgrade_tracks 动态生成（L1/L2 两条通用速度轨；L3 四轨：开墙/标雷 × 移动/工作）

const DISCOUNT_LEVELS := [0, 25, 50]

# 轨 id → 显示名（通用轨 = 单表时代的"速度"，升级时移动/工作同步）
const TRACK_NAMES := {
	"opener_speed": "开墙型速度",
	"marker_speed": "标雷型速度",
	"opener_move": "开墙·移动",
	"opener_work": "开墙·工作",
	"marker_move": "标雷·移动",
	"marker_work": "标雷·工作",
	"recharge": "点击恢复",
	"discount": "购买折扣",
}

@onready var rows_box: VBoxContainer = $MarginContainer/VBoxContainer/RowsBox
@onready var close_button: Button = $MarginContainer/VBoxContainer/CloseButton

var _built_tracks: Array = []  # 已建行的轨 id 签名（tracks 变化时重建）
var _row_ids: Dictionary = {}  # row 节点 → 轨 id（queue_free 中的行由 id 表驱动刷新）


func _ready() -> void:
	hide()
	GameState.money_changed.connect(_on_money_changed)
	GameState.upgrade_changed.connect(func(_id, _lv): _refresh_all())
	close_button.pressed.connect(hide)
	_rebuild_rows_if_needed()
	_refresh_all()


## 当前关应显示的轨列表（upgrade_tracks + 点击恢复 + 折扣尾行，hidden 过滤）
func _visible_tracks() -> Array:
	var lvl: LevelData = GameState.get_current_level()
	var hidden: Array = lvl.upgrades_hidden if lvl != null else []
	var tracks: Array = lvl.upgrade_tracks if lvl != null and not lvl.upgrade_tracks.is_empty() \
			else ["opener_speed", "marker_speed"]
	var out: Array = []
	for t in tracks:
		if not hidden.has(t):
			out.append(t)
	# 有玩家操作 CD 的关追加点击恢复轨（无 CD 的关买了无效，不显示）
	if lvl != null and lvl.cooldown_sec > 0.0 and not hidden.has("recharge"):
		out.append("recharge")
	if not hidden.has("discount"):
		out.append("discount")
	return out


func _rebuild_rows_if_needed() -> void:
	var tracks := _visible_tracks()
	if tracks == _built_tracks:
		return
	_built_tracks = tracks
	_row_ids.clear()
	for c in rows_box.get_children():
		c.queue_free()
	for t in tracks:
		var row := _make_row(t)
		rows_box.add_child(row)
		_row_ids[row] = t


## 行节点显式命名（如 OpenerMoveRow），避免 get_children() 遍历误匹配
func _make_row(upgrade_id: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = upgrade_id.to_pascal_case() + "Row"
	row.add_theme_constant_override("separation", 12)
	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.custom_minimum_size = Vector2(110, 0)
	name_label.text = TRACK_NAMES.get(upgrade_id, upgrade_id)
	var level_label := Label.new()
	level_label.name = "LevelLabel"
	level_label.custom_minimum_size = Vector2(110, 0)
	var buy_button := Button.new()
	buy_button.name = "BuyButton"
	buy_button.custom_minimum_size = Vector2(170, 0)
	buy_button.pressed.connect(func() -> void: GameState.purchase_upgrade(upgrade_id))
	row.add_child(name_label)
	row.add_child(level_label)
	row.add_child(buy_button)
	return row


func _on_money_changed(_v: int) -> void:
	_refresh_all()


func _refresh_all() -> void:
	_rebuild_rows_if_needed()
	for row in _row_ids:
		if is_instance_valid(row) and not row.is_queued_for_deletion():
			_refresh_row(row, _row_ids[row])


func _refresh_row(row: HBoxContainer, upgrade_id: String) -> void:
	var lvl: int = GameState.get_upgrade_level(upgrade_id)
	var prices: Array = GameState.get_upgrade_prices(upgrade_id)
	var tiers: Array
	if upgrade_id == "discount":
		tiers = DISCOUNT_LEVELS
	elif upgrade_id == "recharge":
		tiers = GameState.RECHARGE_LEVELS  # 乘数表；显示层换算成实际回充秒数
	else:
		tiers = GameState.get_upgrade_levels_table(upgrade_id)
	var level_label: Label = row.get_node("LevelLabel")
	var buy_button: Button = row.get_node("BuyButton")

	if upgrade_id == "discount":
		level_label.text = "Lv%d (-%d%%)" % [lvl, tiers[mini(lvl, tiers.size() - 1)]]
	elif upgrade_id == "recharge":
		var base_dur: float = GameState.get_base_cd_duration()
		level_label.text = "Lv%d (%.1fs)" % [lvl, base_dur * tiers[mini(lvl, tiers.size() - 1)]]
	else:
		level_label.text = "Lv%d (%.1fs)" % [lvl, tiers[mini(lvl, tiers.size() - 1)]]

	if lvl >= prices.size() or lvl >= tiers.size() - 1:
		buy_button.text = "已满级"
		buy_button.disabled = true
		return
	var next_price: int = prices[lvl]
	if upgrade_id == "discount":
		buy_button.text = "→Lv%d (-%d%%) ¥%d" % [lvl + 1, tiers[lvl + 1], next_price]
	elif upgrade_id == "recharge":
		var base_dur: float = GameState.get_base_cd_duration()
		buy_button.text = "→Lv%d (%.1fs) ¥%d" % [lvl + 1, base_dur * tiers[lvl + 1], next_price]
	else:
		buy_button.text = "→Lv%d (%.1fs) ¥%d" % [lvl + 1, tiers[lvl + 1], next_price]
	buy_button.disabled = GameState.money < next_price
