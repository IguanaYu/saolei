extends Control
## 章节选择：12 章卡片网格（动态生成）

signal chapter_selected(ch_id: String)
signal back_requested
const CH02_PRESENTATION := preload("res://scripts/ui/ch02_presentation.gd")

@onready var grid_container: GridContainer = $MarginContainer/VBoxContainer/GridContainer
@onready var back_button: Button = $MarginContainer/VBoxContainer/BackButton


func _ready() -> void:
	back_button.pressed.connect(func(): back_requested.emit())
	hide()


func refresh() -> void:
	for child in grid_container.get_children():
		child.queue_free()
	# 只列实装章节（2026-10-11 复活本页配套）：老路线图模板桩章节不出现
	for ch in LevelSystem.get_implemented_chapters():
		var btn := Button.new()
		btn.name = "ChapterCard_" + ch.id
		btn.custom_minimum_size = Vector2(240, 118)
		var unlocked: bool = LevelSystem.is_chapter_unlocked(ch.id)
		if unlocked:
			var subtitle := "激光 · 晶簇 · 过载" if ch.id == "ch02" else _module_hint(ch.unlock_module)
			if ch.id == "ch03":
				subtitle = "蓄能 · 持续光束（试验）"  # 3-1 改版试验章；正式实装时换回模块提示
			elif ch.id == "ch04":
				subtitle = "营业日 · 三批冒险者（试验）"  # 4-1 工会试验章占位（2026-10-20）；原「充能塔」回归时改回
			btn.text = "%s %s\n%s\n%s" % [ch.id.to_upper(), ch.display_name,
					subtitle,
					_chapter_progress(ch)]
		else:
			btn.text = "%s %s\n🔒" % [ch.id.to_upper(), ch.display_name]
		btn.disabled = not unlocked
		btn.modulate = ch.theme_color if unlocked else Color(0.4, 0.4, 0.4)
		if ch.id == "ch02":
			btn.icon = CH02_PRESENTATION.icon("chapter")
			btn.add_theme_constant_override("icon_max_width", 32)
		btn.pressed.connect(_emit_chapter_selected.bind(ch.id))
		grid_container.add_child(btn)


func _chapter_progress(ch) -> String:
	var cleared := 0
	var star_slots := 0
	var stars := 0
	for id in ch.level_ids:
		if SaveSystem.is_level_cleared(id):
			cleared += 1
		var lvl: LevelData = LevelSystem.get_level(id)
		if lvl != null and not lvl.no_stars:
			star_slots += 3
			stars += SaveSystem.get_level_stars(id)
	return "已通关 %d/%d" % [cleared, ch.level_ids.size()] if star_slots == 0 \
			else "★%d/%d · 已通关 %d/%d" % [stars, star_slots, cleared, ch.level_ids.size()]


func _emit_chapter_selected(ch_id: String) -> void:
	chapter_selected.emit(ch_id)


func _chapter_stars(ch_id: String) -> int:
	var ch := LevelSystem.get_chapter(ch_id)
	if ch == null:
		return 0
	var total: int = 0
	for lvl_id in ch.level_ids:
		total += SaveSystem.get_level_stars(lvl_id)
	return total


func _module_hint(module: String) -> String:
	match module:
		"opener_marker": return "解锁: 基础机器人"
		"detector": return "解锁: 检测型"
		"miner": return "解锁: 矿工型"
		"tower": return "解锁: 充能塔"
		"drone": return "解锁: 无人机"
		_: return ""
