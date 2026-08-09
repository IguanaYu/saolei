extends Control
## 章节选择：12 章卡片网格（动态生成）

signal chapter_selected(ch_id: String)
signal back_requested

@onready var grid_container: GridContainer = $MarginContainer/VBoxContainer/GridContainer
@onready var back_button: Button = $MarginContainer/VBoxContainer/BackButton


func _ready() -> void:
	back_button.pressed.connect(func(): back_requested.emit())
	hide()


func refresh() -> void:
	for child in grid_container.get_children():
		child.queue_free()
	for ch in LevelSystem.get_all_chapters():
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(190, 100)
		var unlocked: bool = LevelSystem.is_chapter_unlocked(ch.id)
		var stars: int = _chapter_stars(ch.id)
		if unlocked:
			btn.text = "%s %s\n%s\n★%d/15" % [ch.id.to_upper(), ch.display_name, _module_hint(ch.unlock_module), stars]
		else:
			btn.text = "%s %s\n🔒" % [ch.id.to_upper(), ch.display_name]
		btn.disabled = not unlocked
		btn.modulate = ch.theme_color if unlocked else Color(0.4, 0.4, 0.4)
		btn.pressed.connect(_emit_chapter_selected.bind(ch.id))
		grid_container.add_child(btn)


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
