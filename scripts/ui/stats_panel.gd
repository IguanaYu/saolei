extends Control
## 挖矿档案：总局数/胜率/最佳通关/最高连胜 + 12 章星数总览

signal close_requested

const ICON_STAR := preload("res://visual_v2/runtime/ui/icons/icon_star.png")

@onready var subtitle_label: Label = $Center/Panel/VBox/SubtitleLabel
@onready var cards_row: HBoxContainer = $Center/Panel/VBox/CardsRow
@onready var chapters_grid: GridContainer = $Center/Panel/VBox/ChaptersGrid
@onready var total_label: Label = $Center/Panel/VBox/TotalsRow/TotalValueLabel
@onready var perfect_label: Label = $Center/Panel/VBox/TotalsRow/PerfectLabel


func _ready() -> void:
	hide()
	$Center/Panel/VBox/CloseButton.pressed.connect(func(): close_requested.emit())


func open() -> void:
	_refresh()
	show()


func _refresh() -> void:
	var st: Dictionary = SaveSystem.stats
	var played := int(st.total_games)
	var wins := int(st.wins)
	var win_rate := 0 if played == 0 else wins * 100 / played
	var best_time := "—" if float(st.best_time) < 0 else SaveSystem.format_duration(float(st.best_time))
	subtitle_label.text = "总游戏时长 %s · 开挖于 %s" % [
		SaveSystem.format_duration(float(st.total_play_sec)), SaveSystem.today_key()]
	_set_card(0, str(played), "总局数")
	_set_card(1, "%d%%" % win_rate, "胜率")
	_set_card(2, best_time, "最佳通关")
	_set_card(3, str(int(st.max_streak)), "最高连胜")
	_refresh_chapters()


func _set_card(idx: int, value: String, name: String) -> void:
	var card: PanelContainer = cards_row.get_child(idx)
	card.get_node("VBox/ValueLabel").text = value
	card.get_node("VBox/NameLabel").text = name


func _refresh_chapters() -> void:
	for c in chapters_grid.get_children():
		c.queue_free()
	var total_stars := 0
	var perfect := 0
	var max_stars := 0
	for ch in LevelSystem.get_all_chapters():
		var stars := 0
		for lid in ch.level_ids:
			var s := SaveSystem.get_level_stars(lid)
			stars += s
			if s >= 3:
				perfect += 1
		total_stars += stars
		max_stars += ch.level_ids.size() * 3
		chapters_grid.add_child(_build_chapter_card(ch, stars, ch.level_ids.size() * 3))
	total_label.text = "%d / %d" % [total_stars, max_stars]
	perfect_label.text = "完美通关（3★）%d 关" % perfect


func _build_chapter_card(ch: ChapterData, stars: int, max_stars: int) -> PanelContainer:
	var locked := not SaveSystem.is_chapter_unlocked(ch.id)
	var card := PanelContainer.new()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	var name_label := Label.new()
	name_label.text = ch.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 14)
	var stars_label := Label.new()
	stars_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stars_label.add_theme_font_size_override("font_size", 15)
	stars_label.add_theme_color_override("font_color",
			Color(1, 0.82, 0.4) if not locked else Color(0.43, 0.39, 0.34))
	if locked:
		name_label.add_theme_color_override("font_color", Color(0.43, 0.39, 0.34))
		stars_label.text = "未解锁"
	else:
		stars_label.text = "★%d/%d" % [stars, max_stars]
	vbox.add_child(name_label)
	vbox.add_child(stars_label)
	# 进度条（暗底 + 金色填充）
	var bar_bg := ColorRect.new()
	bar_bg.custom_minimum_size = Vector2(88, 8)
	bar_bg.color = Color(0.12, 0.09, 0.06)
	var bar_fill := ColorRect.new()
	bar_fill.color = Color(1, 0.82, 0.4)
	bar_bg.add_child(bar_fill)
	if not locked and max_stars > 0:
		bar_fill.size = Vector2(88.0 * stars / max_stars, 8)
	vbox.add_child(bar_bg)
	card.add_child(vbox)
	if locked:
		card.modulate = Color(0.7, 0.7, 0.7)
	return card


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()
