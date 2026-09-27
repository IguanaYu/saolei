extends Control
## 关卡选择：某章的 5 关（动态生成）+ 间场矿石商店入口（L3 教学时机）

signal start_requested(level_id: String)
signal back_requested
signal powerup_requested

const L3_ID := "ch01_s03"
const COPY_INTERMISSION := "矿石能变强。"  # 间场教学句（设计 §6-1，全关 ≤3 句之一）

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var grid_container: GridContainer = $MarginContainer/VBoxContainer/GridContainer
@onready var back_button: Button = $MarginContainer/VBoxContainer/BackButton
@onready var ore_label: Label = $MarginContainer/VBoxContainer/OreRow/OreLabel
@onready var powerup_button: Button = $MarginContainer/VBoxContainer/OreRow/PowerUpButton
@onready var hint_label: Label = $MarginContainer/VBoxContainer/OreRow/HintLabel

var _chapter_id: String = ""


func _ready() -> void:
	back_button.pressed.connect(func(): back_requested.emit())
	powerup_button.pressed.connect(func(): powerup_requested.emit())
	SaveSystem.ore_changed.connect(func(_v): _refresh_ore_row())
	SaveSystem.unlock_changed.connect(func(_k): _refresh_ore_row())
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
		var name_line: String = lvl.display_name + (" [BOSS]" if is_boss else "")
		# 试玩关未通关带「新」角标（设计 §4.1：L3 格子带新标）
		if lvl.is_playtest and not SaveSystem.is_level_cleared(lvl_id):
			name_line += " [新]"
		var lines: Array = [name_line]
		lines.append("★".repeat(stars) if stars > 0 else ("🔒" if not unlocked else ""))
		lines.append(obj_label)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(160, 90)
		btn.text = "\n".join(lines)
		btn.disabled = not unlocked
		btn.pressed.connect(_emit_start_requested.bind(lvl_id))
		grid_container.add_child(btn)
	_refresh_ore_row()


## 间场高亮（设计 §4.1）：L3 已解锁且从未进过 L3 → 「变强」按钮高亮 + 教学句
func _refresh_ore_row() -> void:
	ore_label.text = "总矿石: %d" % SaveSystem.ore
	var highlight: bool = LevelSystem.is_level_unlocked(L3_ID) \
			and not SaveSystem.has_entered_level(L3_ID)
	hint_label.visible = highlight
	powerup_button.modulate = Color(1.0, 0.85, 0.35) if highlight else Color.WHITE


func _emit_start_requested(level_id: String) -> void:
	start_requested.emit(level_id)
