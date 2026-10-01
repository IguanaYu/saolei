extends Control
## 选关页（封闭试玩版两栏）：左列 5 关列表 + 右侧详情（目标/最佳/解锁条件）
## 矿石/变强行 L2 通关后揭示（与主菜单同口径），揭示后带间场教学高亮

signal start_requested(level_id: String)
signal back_requested
signal powerup_requested

const L2_ID := "ch01_s02"
const L3_ID := "ch01_s03"
const COPY_INTERMISSION := "矿石能升级。"  # 间场教学句（设计 §6-1，全关 ≤3 句之一）

@onready var back_button: Button = $MarginContainer/VBoxContainer/TopBar/BackButton
@onready var title_label: Label = $MarginContainer/VBoxContainer/TopBar/TitleLabel
@onready var ore_row: HBoxContainer = $MarginContainer/VBoxContainer/TopBar/OreRow
@onready var ore_label: Label = $MarginContainer/VBoxContainer/TopBar/OreRow/OreLabel
@onready var powerup_button: Button = $MarginContainer/VBoxContainer/TopBar/OreRow/PowerUpButton
@onready var hint_label: Label = $MarginContainer/VBoxContainer/TopBar/OreRow/HintLabel
@onready var left_list: VBoxContainer = $MarginContainer/VBoxContainer/Body/LeftList
@onready var detail_title: Label = $MarginContainer/VBoxContainer/Body/DetailPanel/DetailMargin/DetailVBox/DetailTitleLabel
@onready var detail_intro: Label = $MarginContainer/VBoxContainer/Body/DetailPanel/DetailMargin/DetailVBox/DetailIntroLabel
@onready var detail_goal: Label = $MarginContainer/VBoxContainer/Body/DetailPanel/DetailMargin/DetailVBox/DetailGoalLabel
@onready var detail_new: Label = $MarginContainer/VBoxContainer/Body/DetailPanel/DetailMargin/DetailVBox/DetailNewLabel
@onready var detail_best: Label = $MarginContainer/VBoxContainer/Body/DetailPanel/DetailMargin/DetailVBox/DetailBestLabel
@onready var lock_hint: Label = $MarginContainer/VBoxContainer/Body/DetailPanel/DetailMargin/DetailVBox/LockHintLabel
@onready var start_button: Button = $MarginContainer/VBoxContainer/Body/DetailPanel/DetailMargin/DetailVBox/StartButton

var _chapter_id: String = ""
var _selected: int = 0
var _row_buttons: Array = []


func _ready() -> void:
	back_button.pressed.connect(func(): back_requested.emit())
	powerup_button.pressed.connect(func(): powerup_requested.emit())
	start_button.pressed.connect(_on_start_pressed)
	SaveSystem.ore_changed.connect(func(_v): _refresh_ore_row())
	SaveSystem.unlock_changed.connect(func(_k): _refresh_ore_row())
	hide()


func set_chapter(ch_id: String) -> void:
	_chapter_id = ch_id
	refresh()


func refresh() -> void:
	for child in left_list.get_children():
		child.queue_free()
	_row_buttons.clear()
	var ch := LevelSystem.get_chapter(_chapter_id)
	if ch == null:
		return
	var cleared := 0
	for id in ch.level_ids:
		if SaveSystem.is_level_cleared(id):
			cleared += 1
	title_label.text = "试玩矿区 · 进度 %d/%d" % [cleared, ch.level_ids.size()]
	for i in ch.level_ids.size():
		var lvl: LevelData = LevelSystem.get_level(ch.level_ids[i])
		var btn := Button.new()
		btn.name = "LevelRow%02d" % (i + 1)   # 显式命名，防 get_children 遍历误匹配
		btn.custom_minimum_size = Vector2(314, 90)
		var state := "✓" if SaveSystem.is_level_cleared(lvl.id) \
				else ("" if LevelSystem.is_level_unlocked(lvl.id) else "🔒")
		var sname := lvl.short_name if lvl.short_name != "" else "第 %d 关" % (i + 1)
		btn.text = "%02d %s  %s\n%s" % [i + 1, sname, state,
				lvl.intro_line if lvl.intro_line != "" else " "]
		var idx := i
		btn.pressed.connect(func(): _select(idx))   # 锁行也可点，只读详情
		left_list.add_child(btn)
		_row_buttons.append(btn)
	_select(clampi(_selected, 0, ch.level_ids.size() - 1))
	_refresh_ore_row()


func _select(idx: int) -> void:
	_selected = idx
	var lvl: LevelData = LevelSystem.get_level(_chapter_level_id(idx))
	if lvl == null:
		return
	detail_title.text = "%02d %s" % [idx + 1,
			lvl.short_name if lvl.short_name != "" else lvl.display_name]
	detail_intro.text = lvl.intro_line
	detail_goal.text = "目标：%s" % _goal_line(lvl)
	detail_new.text = _new_tags_line(idx, lvl)
	var unlocked: bool = LevelSystem.is_level_unlocked(lvl.id)
	lock_hint.visible = not unlocked
	lock_hint.text = "通关第 %d 关解锁" % idx
	start_button.disabled = not unlocked
	var best: Dictionary = _best_for(lvl.id)
	detail_best.text = "最佳得分 %d · 最佳用时 %s" % [best.score, best.time] \
			if not best.is_empty() else "尚无记录"
	start_button.text = "重玩本关" if SaveSystem.is_level_cleared(lvl.id) else "开始本关"
	for i in _row_buttons.size():
		_row_buttons[i].modulate = Color(1.0, 0.85, 0.35) if i == idx else Color.WHITE


func _chapter_level_id(idx: int) -> String:
	var ch := LevelSystem.get_chapter(_chapter_id)
	if ch == null or idx >= ch.level_ids.size():
		return ""
	return ch.level_ids[idx]


func _goal_line(lvl: LevelData) -> String:
	var obj: ObjectiveData = lvl.objectives[0] if not lvl.objectives.is_empty() else null
	return obj.short_label() if obj != null else "清空安全格"


## 本关新增（mechanic_tags 对本章之前所有关并集的差集）：首关=全部算新增；
## 空差集/无标签=空串不占行。按前一并集而非相邻前关——tags 是"本关焦点"非累积，
## 相邻差集会把早出现过又缺席的旧标签（如 L5 的开墙/标雷 vs L4）误判成新增
func _new_tags_line(idx: int, lvl: LevelData) -> String:
	if lvl.mechanic_tags.is_empty():
		return ""
	var prev_tags: Array = []
	for i in idx:
		var prev: LevelData = LevelSystem.get_level(_chapter_level_id(i))
		if prev != null:
			for tag in prev.mechanic_tags:
				if not prev_tags.has(tag):
					prev_tags.append(tag)
	var diff: Array = []
	for tag in lvl.mechanic_tags:
		if not prev_tags.has(tag):
			diff.append(tag)
	if diff.is_empty():
		return ""
	return "本关新增：%s" % "、".join(diff)


## 每关最佳成绩：从盲测记录（stats.playtest，仅 win）聚合最高分与最快用时
func _best_for(level_id: String) -> Dictionary:
	var best_score := -1
	var best_time := 1e9
	for r in SaveSystem.stats.get("playtest", []):
		if r.get("level") == level_id and r.get("result") == "win":
			best_score = maxi(best_score, int(r.get("score", 0)))
			best_time = minf(best_time, float(r.get("elapsed", 1e9)))
	if best_score < 0:
		return {}
	return {"score": best_score, "time": SaveSystem.format_duration(best_time)}


func _on_start_pressed() -> void:
	var id := _chapter_level_id(_selected)
	if id != "":
		start_requested.emit(id)


## 间场高亮（设计 §4.1）：L2 通关且从未进过 L3 → 「变强」按钮高亮 + 教学句
## （揭示门控用通关记录：is_level_unlocked 试玩期恒真，见 main_menu 同口径注释）
func _refresh_ore_row() -> void:
	var revealed: bool = SaveSystem.is_level_cleared(L2_ID)   # L2 通关前整行不可见
	ore_row.visible = revealed
	ore_label.text = "总矿石: %d" % SaveSystem.ore
	var highlight: bool = revealed and not SaveSystem.has_entered_level(L3_ID)
	hint_label.visible = highlight
	hint_label.text = COPY_INTERMISSION
	powerup_button.modulate = Color(1.0, 0.85, 0.35) if highlight else Color.WHITE
