extends Control
## 规则页：三节固定文案 + 棋盘符号图例（图标+名词+短解释+鼠标动作，P3-01）
## 入口三处：主菜单 / 暂停 / 商店第二行「操作说明」（布局计划 §2.3）
## 从局内（商店）打开时暂停游戏，关闭恢复打开前状态（暂停面板打开中则保持暂停）

signal close_requested

const FACTION_MARKER := preload("res://scripts/visuals/faction_marker.gd")
const LOCKED_CELL_SEAL := preload("res://scripts/visuals/locked_cell_seal.gd")

@onready var close_button: Button = $Center/Panel/Margin/VBox/CloseButton
@onready var legend_box: VBoxContainer = $Center/Panel/Margin/VBox/RulesScroll/RulesList/LegendBox

var _was_paused := false
var _legend_built := false   # 图例含 load() 贴图，推迟到首次打开再建（不占启动链）

## 图例表：icon 为 null 的条目用文字代替（数字无贴图——格子上就是 Label）
## 贴图与 cell.gd 运行时同源（visual_v2/runtime），不复制文件
const LEGEND := [
	{"symbol": "ally", "name": "友军",
		"desc": "青蓝轮廓 + 脚下底标", "act": "自动工作"},
	{"symbol": "enemy", "name": "敌军",
		"desc": "橙红轮廓 + 三角标记", "act": "点击虫子 / 虫巢除害"},
	{"icon": "res://visual_v2/runtime/completion/tiles/special_flag.png", "name": "旗",
		"desc": "标记怀疑的雷", "act": "右键插 / 撤"},
	{"icon": null, "num": "3", "name": "数字",
		"desc": "周围 8 格的雷数", "act": "左键开格"},
	{"icon": "res://visual_v2/runtime/completion/tiles/overlays/confirmed.png", "name": "确认雷",
		"desc": "探测确认的雷位", "act": "不可再交互"},
	{"icon": "res://visual_v2/runtime/completion/tiles/overlays/web.png", "name": "蛛网",
		"desc": "盖住数字，挡机器人推理", "act": "点击清除"},
	{"symbol": "lock", "name": "锁格",
		"desc": "锁死格子，无法开 / 标", "act": "点击清除"},
	{"icon": "res://visual_v2/runtime/completion/tiles/overlays/fossil_tl.png", "name": "化石",
		"desc": "嵌在岩层里的菊石，永久挡住 2×2", "act": "清不掉，绕过去"},
	{"icon": "res://visual_v2/runtime/completion/tiles/overlays/slime_floor.png", "name": "黏液",
		"desc": "机器人经过减速", "act": "点击清除"},
	{"icon": "res://visual_v2/runtime/completion/tiles/overlays/fire_0.png", "name": "火焰",
		"desc": "阻断通路，会蔓延熄灭", "act": "点击整片熄灭 +5 分"},
	{"icon": "res://visual_v2/runtime/completion/boss/tentacle_root.png", "name": "触手",
		"desc": "占格挡路（第 5 关）", "act": "点根部断整条 +15 分"},
]


func _ready() -> void:
	hide()
	close_button.pressed.connect(close)


func _build_legend() -> void:
	for item in LEGEND:
		var row := HBoxContainer.new()
		row.name = "Legend" + String(item["name"])
		row.add_theme_constant_override("separation", 10)
		var icon: Variant = item.get("icon")
		if item.has("symbol"):
			var holder := Control.new()
			holder.name = "SymbolIcon"
			holder.custom_minimum_size = Vector2(28, 28)
			holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var symbol: Node2D
			if item["symbol"] == "lock":
				symbol = LOCKED_CELL_SEAL.new()
			else:
				symbol = FACTION_MARKER.new()
				symbol.set("hostile", item["symbol"] == "enemy")
			symbol.name = "LegendSymbol"
			symbol.position = Vector2(14, 14)
			holder.add_child(symbol)
			row.add_child(holder)
		elif icon != null and String(icon).contains("res://"):
			var icon_rect := TextureRect.new()
			icon_rect.name = "IconRect"
			icon_rect.texture = load(icon)
			icon_rect.custom_minimum_size = Vector2(24, 24)
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			row.add_child(icon_rect)
		else:
			# 数字条目：样式化数字 Label 代替贴图（格子上本来就是文字）
			var num_label := Label.new()
			num_label.name = "NumLabel"
			num_label.text = String(item.get("num", "?"))
			num_label.custom_minimum_size = Vector2(24, 24)
			num_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			num_label.add_theme_font_size_override("font_size", 17)
			num_label.add_theme_color_override("font_color", Color(0.55, 0.8, 1.0, 1))
			row.add_child(num_label)
		var name_label := Label.new()
		name_label.name = "NameLabel"
		name_label.text = String(item["name"])
		name_label.custom_minimum_size = Vector2(64, 0)
		name_label.add_theme_font_size_override("font_size", 16)
		name_label.add_theme_color_override("font_color", Color(0.92, 0.86, 0.72, 1))
		var desc_label := Label.new()
		desc_label.name = "DescLabel"
		desc_label.text = String(item["desc"])
		desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_label.add_theme_font_size_override("font_size", 14)
		desc_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.65, 1))
		var act_label := Label.new()
		act_label.name = "ActLabel"
		act_label.text = String(item["act"])
		act_label.add_theme_font_size_override("font_size", 14)
		act_label.add_theme_color_override("font_color", Color(1, 0.82, 0.4, 1))
		row.add_child(name_label)
		row.add_child(desc_label)
		row.add_child(act_label)
		legend_box.add_child(row)


func open() -> void:
	if not _legend_built:
		_build_legend()
		_legend_built = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	show()
	close_button.grab_focus()


func close() -> void:
	hide()
	get_tree().paused = _was_paused
