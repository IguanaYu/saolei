extends Control
## 每日挑战：全球同图（日期种子生成盘面）· 周徽章 · 刷新倒计时
## 盘面规格随星期几爬难度：周一最小，周日最大

signal start_requested
signal close_requested

const DAILY_ORE := 30
const STYLE_POOL := ["A1", "C1", "E1", "E2", "E3", "E4", "E5", "E6"]

@onready var date_label: Label = $Center/Panel/VBox/DateLabel
@onready var map_name_label: Label = $Center/Panel/VBox/MapCard/VBox/MapNameLabel
@onready var map_desc_label: Label = $Center/Panel/VBox/MapCard/VBox/MapDescLabel
@onready var today_best_label: Label = $Center/Panel/VBox/RecordsRow/TodayCard/VBox/ValueLabel
@onready var all_best_label: Label = $Center/Panel/VBox/RecordsRow/AllCard/VBox/ValueLabel
@onready var badges_row: HBoxContainer = $Center/Panel/VBox/BadgesRow
@onready var chest_label: Label = $Center/Panel/VBox/ChestLabel
@onready var countdown_label: Label = $Center/Panel/VBox/CountdownLabel


func _ready() -> void:
	hide()
	$Center/Panel/VBox/StartButton.pressed.connect(func(): start_requested.emit())
	$Center/Panel/VBox/CloseButton.pressed.connect(func(): close_requested.emit())


func open() -> void:
	_refresh()
	show()


func _process(_delta: float) -> void:
	if not visible:
		return
	var t := Time.get_time_dict_from_system()
	var left: int = 86400 - (int(t.hour) * 3600 + int(t.minute) * 60 + int(t.second))
	countdown_label.text = "距离明日刷新 %02d:%02d:%02d" % [
		left / 3600, (left % 3600) / 60, left % 60]


func _refresh() -> void:
	var d := Time.get_date_dict_from_system()
	date_label.text = "%d 月 %d 日 · 全球同图" % [d.month, d.day]
	var lvl := today_level()
	map_name_label.text = "今日矿场 · 第 %d 期" % SaveSystem.day_of_year()
	map_desc_label.text = "%d × %d · %d 雷 · 清空全部安全格" % [
		lvl.grid_size.x, lvl.grid_size.y, lvl.mine_count]
	# 个人记录
	var st: Dictionary = SaveSystem.daily
	today_best_label.text = SaveSystem.format_duration(float(st.today_best)) \
			if st.today_key == SaveSystem.today_key() and float(st.today_best) >= 0 else "—"
	all_best_label.text = SaveSystem.format_duration(float(st.all_best)) \
			if float(st.all_best) >= 0 else "—"
	_refresh_badges()


func _refresh_badges() -> void:
	for c in badges_row.get_children():
		c.queue_free()
	var earned: Array = SaveSystem.get_daily_badges()
	var wd := SaveSystem.today_weekday()
	var week_names := ["一", "二", "三", "四", "五", "六", "日"]
	for i in 7:
		var day := i + 1
		var slot := PanelContainer.new()
		var vbox := VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_theme_constant_override("separation", 0)
		var badge := Label.new()
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.add_theme_font_size_override("font_size", 22)
		var week := Label.new()
		week.text = "周" + week_names[i]
		week.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		week.add_theme_font_size_override("font_size", 12)
		if earned.has(day):
			badge.text = "◆"
			badge.add_theme_color_override("font_color", Color(1, 0.82, 0.4))
		elif day == wd:
			badge.text = "◇"
			badge.add_theme_color_override("font_color", Color(1, 0.9, 0.6))
		else:
			badge.text = "◇"
			badge.add_theme_color_override("font_color", Color(0.35, 0.32, 0.28))
		vbox.add_child(badge)
		vbox.add_child(week)
		slot.add_child(vbox)
		slot.custom_minimum_size = Vector2(58, 66)
		if day == wd:
			slot.modulate = Color(1.05, 1.0, 0.9)
		badges_row.add_child(slot)
	chest_label.text = "本周徽章 %d / 5 · 集齐 5 枚领矿石宝箱（+50）" % earned.size()


## 日期种子 → 今日盘面（同一天所有玩家同一张图）
func today_level() -> LevelData:
	var key := SaveSystem.today_key()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var wd := SaveSystem.today_weekday()  # 1=周一..7=周日
	var rows := 10 + int((wd - 1) / 2.0)  # 10..13
	var cols := 12 + (wd - 1)             # 12..18
	var lvl := LevelData.new()
	lvl.id = "daily_" + key
	lvl.display_name = "每日挑战"
	lvl.grid_size = Vector2i(rows, cols)
	lvl.mine_count = int(rows * cols * 0.11)
	lvl.time_limit_sec = 240.0
	lvl.start_gold = 150
	lvl.start_lives = 3
	var obj := ObjectiveData.new()
	obj.type = ObjectiveData.Type.CLEAR_ALL_SAFE
	lvl.objectives = [obj]
	return lvl


## 今日岩壁风格（同图同风格）
func today_wall_style() -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(SaveSystem.today_key() + "style")
	return STYLE_POOL[rng.randi() % STYLE_POOL.size()]


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()
