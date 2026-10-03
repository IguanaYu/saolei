extends Control
## 矿工签到：7 天奖励递增 · 连签计数 · 断签重置

signal close_requested

const ICON_ORE := preload("res://visual_v2/runtime/completion/ui/icons/icon_ore.png")
const ICON_STAR := preload("res://visual_v2/runtime/ui/icons/icon_star.png")

@onready var streak_label: Label = $Center/Panel/VBox/TitleRow/StreakLabel
@onready var days_row: HBoxContainer = $Center/Panel/VBox/DaysRow
@onready var claim_button: Button = $Center/Panel/VBox/ClaimButton
@onready var result_label: Label = $Center/Panel/VBox/ResultLabel


func _ready() -> void:
	hide()
	claim_button.pressed.connect(_on_claim)
	$Center/Panel/VBox/CloseButton.pressed.connect(func(): close_requested.emit())


func open() -> void:
	_refresh()
	show()


func _refresh() -> void:
	var state: Dictionary = SaveSystem.signin_state()
	streak_label.text = "已连签 %d 天" % int(state.streak)
	result_label.visible = false
	for c in days_row.get_children():
		c.queue_free()
	var day_today := int(state.day_today)
	var claimed := int(state.claimed_in_cycle)
	var claimed_today := bool(state.claimed_today)
	for i in 7:
		var day := i + 1
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(84, 150)
		var vbox := VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_theme_constant_override("separation", 4)
		var day_label := Label.new()
		day_label.text = "第%d天" % day
		day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		day_label.add_theme_font_size_override("font_size", 13)
		var icon := TextureRect.new()
		icon.texture = ICON_STAR if day == 7 else ICON_ORE
		icon.custom_minimum_size = Vector2(30, 30)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		var reward := Label.new()
		reward.text = "×%d矿" % SaveSystem.SIGN_DAY_ORE[i]
		reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reward.add_theme_font_size_override("font_size", 14)
		var status := Label.new()
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status.add_theme_font_size_override("font_size", 13)
		if day <= claimed:
			status.text = "已领取"
			status.add_theme_color_override("font_color", Color(0.43, 0.39, 0.34))
			card.modulate = Color(0.72, 0.72, 0.72)
		elif day == day_today and not claimed_today:
			status.text = "可领取"
			status.add_theme_color_override("font_color", Color(1, 0.82, 0.4))
		else:
			status.text = "未达成"
			status.add_theme_color_override("font_color", Color(0.55, 0.5, 0.42))
		vbox.add_child(day_label)
		vbox.add_child(icon)
		vbox.add_child(reward)
		vbox.add_child(status)
		card.add_child(vbox)
		days_row.add_child(card)
	if claimed_today:
		claim_button.text = "今日已领取 · 明日再来"
		claim_button.disabled = true
	else:
		claim_button.text = "领取今日奖励（+%d 矿）" % SaveSystem.SIGN_DAY_ORE[day_today - 1]
		claim_button.disabled = false


func _on_claim() -> void:
	var gained := SaveSystem.do_sign()
	if gained > 0:
		result_label.text = "+%d 矿石已入账！" % gained
		result_label.visible = true
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()
