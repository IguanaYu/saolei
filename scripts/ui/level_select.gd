extends Control
## 关卡选择：某章的 5 关（动态生成）

signal start_requested(level_id: String)
signal back_requested

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var grid_container: GridContainer = $MarginContainer/VBoxContainer/GridContainer
@onready var back_button: Button = $MarginContainer/VBoxContainer/BackButton

var _chapter_id: String = ""


func _ready() -> void:
	back_button.pressed.connect(func(): back_requested.emit())
	hide()


func set_chapter(ch_id: String) -> void:
	_chapter_id = ch_id
	refresh()


func refresh() -> void:
	for child in grid_container.get_children():
		child.queue_free()
	var ch := LevelSystem.get_chapter(_chapter_id)
	if ch == null:
		return
	title_label.text = "%s · %s" % [ch.id.to_upper(), ch.display_name]
	for lvl_id in ch.level_ids:
		var lvl := LevelSystem.get_level(lvl_id)
		var unlocked: bool = LevelSystem.is_level_unlocked(lvl_id)
		var is_boss: bool = ch.level_ids[-1] == lvl_id
		var stars: int = SaveSystem.get_level_stars(lvl_id)
		var obj: ObjectiveData = lvl.objectives[0] if not lvl.objectives.is_empty() else null
		var obj_label: String = obj.short_label() if obj != null else ""
		var lines: Array = [lvl.display_name + (" [BOSS]" if is_boss else "")]
		lines.append("★".repeat(stars) if stars > 0 else ("🔒" if not unlocked else ""))
		lines.append(obj_label)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(160, 90)
		btn.text = "\n".join(lines)
		btn.disabled = not unlocked
		btn.pressed.connect(_emit_start_requested.bind(lvl_id))
		grid_container.add_child(btn)


func _emit_start_requested(level_id: String) -> void:
	start_requested.emit(level_id)
