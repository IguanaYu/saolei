extends Control
## 规则页：三节固定文案 + 棋盘符号图例（图标+名词+短解释+鼠标动作，P3-01）
## 入口三处：主菜单 / 暂停 / 商店第二行「操作说明」（布局计划 §2.3）
## 从局内（商店）打开时暂停游戏，关闭恢复打开前状态（暂停面板打开中则保持暂停）

signal close_requested

const FACTION_MARKER := preload("res://scripts/visuals/faction_marker.gd")
const LOCKED_CELL_SEAL := preload("res://scripts/visuals/locked_cell_seal.gd")
const CH02_RULES_DIAGRAM := preload("res://scripts/ui/ch02_rules_diagram.gd")
const CH02_ICON_DIR := "res://visual_v2/runtime/ch02_v1/ui/"

@onready var close_button: Button = $Center/Panel/Margin/VBox/CloseButton
@onready var legend_box: VBoxContainer = $Center/Panel/Margin/VBox/RulesScroll/RulesList/LegendBox

var _was_paused := false
var _legend_built := false   # 图例含 load() 贴图，推迟到首次打开再建（不占启动链）
var _legend_laser := false

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
const CH02_LEGEND := [
	{"icon": CH02_ICON_DIR + "icon_laser.png", "name": "激光 / 厚墙", "desc": "基地发射，墙每次削一层", "act": "左键发射"},
	{"icon": "res://visual_v2/runtime/ui/icons/icon_robot_opener.png", "name": "充能", "desc": "开墙与标雷机提速 6 秒", "act": "光束 / 爆发命中"},
	{"icon": CH02_ICON_DIR + "icon_builder.png", "name": "筑墙工", "desc": "两点耐久，会在地面砌墙", "act": "激光 / 保安击破"},
	{"icon": CH02_ICON_DIR + "icon_builder.png", "name": "覆盖墙", "desc": "砖框围着旧数字；拆完恢复地面", "act": "每次拆一层"},
	{"icon": CH02_ICON_DIR + "icon_special_ore.png", "name": "特殊矿石", "desc": "2×2 足迹挡光；随机三向各射程 3", "act": "反复命中激活"},
	{"icon": CH02_ICON_DIR + "icon_overload.png", "name": "过载机", "desc": "自动巡逻，停靠墙边；爆后存活", "act": "激光引爆 13 格"},
	{"icon": CH02_ICON_DIR + "icon_overload_range.png", "name": "扩爆升级", "desc": "四条直臂各延长一格，斜向不变", "act": "升级后 17 格"},
]


func _ready() -> void:
	hide()
	close_button.pressed.connect(close)


func _build_legend(laser := false) -> void:
	for child in legend_box.get_children():
		legend_box.remove_child(child)
		child.queue_free()
	var entries: Array = LEGEND.duplicate(true)
	if laser:
		entries = [LEGEND[0], LEGEND[2].duplicate(), LEGEND[3].duplicate(), LEGEND[7]]
		entries[1].desc = "标记钻石，旗格免疫激光与爆发"
		entries[2].act = "周围 8 格的钻石数"
		entries.append_array(CH02_LEGEND)
	for item in entries:
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
		name_label.custom_minimum_size = Vector2(92, 0)
		name_label.add_theme_font_size_override("font_size", 15)
		name_label.add_theme_color_override("font_color", Color(0.92, 0.86, 0.72, 1))
		var desc_label := Label.new()
		desc_label.name = "DescLabel"
		desc_label.text = String(item["desc"])
		desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	if laser:
		var diagram := CH02_RULES_DIAGRAM.new()
		diagram.name = "OverloadRangeExample"
		legend_box.add_child(diagram)


func open() -> void:
	var lvl: LevelData = GameState.get_current_level()
	var laser := GameState.game_active and lvl != null and lvl.laser_mode
	if not _legend_built or _legend_laser != laser:
		_build_legend(laser)
		_legend_built = true
		_legend_laser = laser
	var list := $Center/Panel/Margin/VBox/RulesScroll/RulesList
	list.get_node("SectionATitle").text = "第二章 · 激光矿场" if laser else "怎么扫雷"
	list.get_node("SectionABody").text = \
			"左键从基地发射激光，右键插旗/撤旗；左右同按仍为和弦。数字是周围 8 格的钻石数，数字与钻石位置不变。墙从 ×3 → ×2 → 1 层 → 打开；旗格只被光束穿过，不会削层或碎钻。" if laser else \
			"左键开格、右键插旗/撤旗；数字 = 周围雷数；已揭示数字与雷位永不变动。"
	list.get_node("SectionBBody").text = \
			"开墙与标雷机器人自动工作，激光或爆发命中后提速 6 秒，青色刻度显示剩余时间。矿石每轮抽取三条方向，射前只提示足迹；过载的十字范围可提前预览。筑墙工死后，已砌的覆盖墙仍需拆除。" if laser else \
			"开墙机器人开安全格、标雷机器人插旗，它们自动寻找最近的目标，购买后从最新基地旁自动出场；只有建基地和探测需要手动选位置。第 4 关起可用「探测」按钮确认可疑格、雇「保安」除虫护场。"
	list.get_node("SectionCBody").text = \
			"金币用于买设备，积分达到本关目标即可过关。先标记钻石保留完整收益；激光打碎钻石只有少量积分。削厚墙的前几层不会获得开格奖励。" if laser else \
			"资金买设备（不扣积分）；扫雷进度是过关目标；积分来自开格/标雷/剩余时间，只用于成绩。"
	_was_paused = get_tree().paused
	get_tree().paused = true
	show()
	close_button.grab_focus()


func close() -> void:
	hide()
	get_tree().paused = _was_paused
