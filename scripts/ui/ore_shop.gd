extends Panel
## 局外矿石商店（共享面板）：主菜单与选关页（间场）都能打开
## 轨道数据源在此统一维护（替换原 main_menu 硬编码），购买即埋点（设计 §4.1）
## 安全区扩大（expand_zone）不进表：固定预开地图下无用，行隐藏

# 每轨 costs 长度 = 可购档数（int 类升级封顶 2 级由 SaveSystem.purchase_unlock 兜底）
const TRACKS := [
	{"key": "start_money", "name": "起始金币", "costs": [50, 100], "desc": "每级 +50 起始资金"},
	{"key": "start_lives", "name": "起始生命", "costs": [80, 160], "desc": "每级 +1 命"},
	{"key": "global_speed", "name": "移动速度", "costs": [100, 200], "desc": "开局送同级移动档（1 级 1.6s / 2 级 1.3s）"},
	{"key": "work_speed", "name": "工作速度", "costs": [100, 200], "desc": "开局送同级工作档（开格/标记连作）"},
	{"key": "start_robot", "name": "开局送机器人", "costs": [100, 200], "desc": "Lv1 送开墙型，Lv2 再送标雷型"},
]

@onready var ore_label: Label = $MarginContainer/VBoxContainer/OreLabel
@onready var rows_box: VBoxContainer = $MarginContainer/VBoxContainer/RowsBox
@onready var close_button: Button = $MarginContainer/VBoxContainer/CloseButton

var _built := false


func _ready() -> void:
	hide()
	close_button.pressed.connect(hide)
	SaveSystem.ore_changed.connect(func(_v): _refresh_all())
	SaveSystem.unlock_changed.connect(func(_k): _refresh_all())


func open() -> void:
	_build_rows()
	_refresh_all()
	show()


func _build_rows() -> void:
	if _built:
		return
	_built = true
	for t in TRACKS:
		var row := HBoxContainer.new()
		# 行节点显式命名（StartMoneyRow 等），避免 get_children() 遍历误匹配
		row.name = String(t["key"]).to_pascal_case() + "Row"
		row.add_theme_constant_override("separation", 10)
		var name_label := Label.new()
		name_label.name = "NameLabel"
		name_label.custom_minimum_size = Vector2(110, 0)
		name_label.text = t["name"]
		var desc_label := Label.new()
		desc_label.name = "DescLabel"
		desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_label.add_theme_font_size_override("font_size", 12)
		desc_label.add_theme_color_override("font_color", Color(0.62, 0.58, 0.52))
		desc_label.text = t["desc"]
		var level_label := Label.new()
		level_label.name = "LevelLabel"
		level_label.custom_minimum_size = Vector2(95, 0)
		var buy_button := Button.new()
		buy_button.name = "BuyButton"
		buy_button.custom_minimum_size = Vector2(120, 0)
		var key := String(t["key"])
		buy_button.pressed.connect(func() -> void: _try_buy(key))
		row.add_child(name_label)
		row.add_child(desc_label)
		row.add_child(level_label)
		row.add_child(buy_button)
		rows_box.add_child(row)


func _try_buy(key: String) -> void:
	var costs: Array = _track_costs(key)
	var lvl: int = int(SaveSystem.unlocks.get(key, 0))
	if lvl >= costs.size():
		return
	var cost: int = costs[lvl]
	if SaveSystem.purchase_unlock(key, cost):
		SaveSystem.record_meta_purchase(key, lvl + 1)  # 购买组合埋点（含顺序）


func _track_costs(key: String) -> Array:
	for t in TRACKS:
		if t["key"] == key:
			return t["costs"]
	return []


func _refresh_all() -> void:
	ore_label.text = "总矿石: %d" % SaveSystem.ore
	for row in rows_box.get_children():
		var key: String = String(row.name).trim_suffix("Row").to_snake_case()
		var lvl: int = int(SaveSystem.unlocks.get(key, 0))
		var costs: Array = _track_costs(key)
		var level_label: Label = row.get_node("LevelLabel")
		var buy_button: Button = row.get_node("BuyButton")
		match key:
			"start_money":
				level_label.text = "Lv%d (+%d金币)" % [lvl, lvl * 50]
			"start_lives":
				level_label.text = "Lv%d (+%d命)" % [lvl, lvl]
			_:
				level_label.text = "Lv%d" % lvl
		if lvl >= costs.size():
			buy_button.text = "已满级"
			buy_button.disabled = true
		else:
			var cost: int = costs[lvl]
			buy_button.text = "→Lv%d %d矿" % [lvl + 1, cost]
			buy_button.disabled = SaveSystem.ore < cost
