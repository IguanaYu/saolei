extends Control
## A 版关卡信息栏：目标、时间、生命、设置；金币锚点移到小队商店。

const HEART_FULL := preload("res://visual_v2/runtime/ui/icons/icon_heart.png")
const HEART_EMPTY := preload("res://visual_v2/runtime/ui/icons/icon_heart_empty.png")
const MAX_HEARTS := 3
const GOLD := Color(1.0, 0.753, 0.29)  # 矿金 #f0c04a，与盘面跳字同色

signal pause_requested
signal settings_requested
const UI := preload("res://scripts/ui/game_ui_style.gd")
var _objective_text := ""
var _goal_total: Label
var manual_readout: HBoxContainer
var _manual_label: Label
var _pips: Array[ColorRect] = []
var _readout_elapsed := 0.0
var _idle_warning := false

@onready var money_label: Label = $MarginContainer/VBoxContainer/TopRow/MoneyPanel/ResBox/MoneyLabel
@onready var level_title_label: Label = $MarginContainer/VBoxContainer/TopRow/MiddleBox/LevelTitleLabel
@onready var score_label: Label = $MarginContainer/VBoxContainer/TopRow/RightPanel/RightBox/ScoreLabel
@onready var time_label: Label = $MarginContainer/VBoxContainer/TopRow/RightPanel/RightBox/TimeLabel
@onready var hearts: Array = [
	$MarginContainer/VBoxContainer/TopRow/RightPanel/RightBox/Heart1,
	$MarginContainer/VBoxContainer/TopRow/RightPanel/RightBox/Heart2,
	$MarginContainer/VBoxContainer/TopRow/RightPanel/RightBox/Heart3,
]
@onready var objective_label: Label = $MarginContainer/VBoxContainer/TopRow/MiddleBox/ObjectiveRow/ObjectiveLabel
@onready var objective_tooth_icon: TextureRect = $MarginContainer/VBoxContainer/TopRow/MiddleBox/ObjectiveRow/ObjectiveToothIcon
@onready var objective_progress_bar: ProgressBar = $MarginContainer/VBoxContainer/TopRow/MiddleBox/ObjectiveProgressBar
@onready var idle_hint_label: Label = $MarginContainer/VBoxContainer/IdleHintLabel
@onready var phase_hint_label: Label = $MarginContainer/VBoxContainer/PhaseHintLabel
@onready var toast_panel: PanelContainer = $ToastPanel
@onready var toast_label: Label = $ToastPanel/ToastLabel

var _last_money: int = -1
var _gain_popup: Label = null
var _gain_tween: Tween = null
var _score_fx_tween: Tween = null  # 总分脉冲专用（连续拍重叠时先杀旧防抖动）
var _toast_tween: Tween


func _ready() -> void:
	_build_compact_ui()
	money_label.add_to_group("hud_money")  # 卸货飞币动效的落点（EffectsLayer 查组取位置）
	GameState.money_changed.connect(_on_money_changed)
	GameState.score_changed.connect(_on_score_changed)
	GameState.lives_changed.connect(_on_lives_changed)
	GameState.time_changed.connect(_on_time_changed)
	GameState.game_phase_changed.connect(_on_game_phase_changed)
	GameState.objective_progress_updated.connect(_on_objective_progress_updated)
	_refresh_all()
	_on_game_phase_changed(GameState.game_phase)


func _build_compact_ui() -> void:
	$MarginContainer.hide()
	var surface := PanelContainer.new()
	surface.name = "MissionSurface"
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.add_theme_stylebox_override("panel", UI.panel())
	add_child(surface)
	var row := HBoxContainer.new()
	row.name = "MissionRow"
	row.add_theme_constant_override("separation", 22)
	surface.add_child(row)
	level_title_label.reparent(row)
	level_title_label.custom_minimum_size.x = 174
	level_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	level_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level_title_label.add_theme_font_size_override("font_size", 18)
	level_title_label.add_theme_color_override("font_color", UI.INK)
	var goal := VBoxContainer.new()
	goal.name = "MissionGoal"
	goal.size_flags_horizontal = SIZE_EXPAND_FILL
	goal.alignment = BoxContainer.ALIGNMENT_CENTER
	goal.add_theme_constant_override("separation", 7)
	row.add_child(goal)
	var caption: HBoxContainer = objective_label.get_parent()
	caption.reparent(goal)
	caption.alignment = BoxContainer.ALIGNMENT_BEGIN
	objective_label.size_flags_horizontal = SIZE_EXPAND_FILL
	objective_label.clip_text = true
	objective_label.add_theme_font_size_override("font_size", 13)
	objective_label.add_theme_color_override("font_color", UI.SOFT)
	score_label.reparent(caption)
	score_label.add_theme_font_size_override("font_size", 16)
	_goal_total = UI.label("", "GoalTotal", 12, UI.SOFT)
	caption.add_child(_goal_total)
	objective_progress_bar.reparent(goal)
	objective_progress_bar.custom_minimum_size.y = 5
	var track := StyleBoxFlat.new()
	track.bg_color = UI.LINE
	objective_progress_bar.add_theme_stylebox_override("background", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UI.SIGNAL
	objective_progress_bar.add_theme_stylebox_override("fill", fill)
	var status := HBoxContainer.new()
	status.name = "Survival"
	status.add_theme_constant_override("separation", 8)
	row.add_child(status)
	var clock: TextureRect = time_label.get_parent().get_node("ClockIcon")
	clock.reparent(status)
	clock.custom_minimum_size = Vector2(16, 16)
	clock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	time_label.reparent(status)
	time_label.add_theme_font_size_override("font_size", 20)
	for h in hearts:
		h.reparent(status)
		h.custom_minimum_size = Vector2(17, 17)
		h.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var settings := Button.new()
	settings.name = "SettingsButton"
	settings.text = "⚙"
	settings.tooltip_text = "设置"
	settings.custom_minimum_size = Vector2(36, 36)
	UI.button(settings, 20)
	settings.add_theme_font_override("font", ThemeDB.fallback_font)
	status.add_child(settings)
	settings.pressed.connect(func(): settings_requested.emit())
	manual_readout = HBoxContainer.new()
	manual_readout.name = "ManualReadout"
	manual_readout.mouse_filter = MOUSE_FILTER_PASS
	add_child(manual_readout)
	_manual_label = UI.label("", "ManualCharges", 12, UI.SOFT)
	manual_readout.add_child(_manual_label)
	for i in 7:
		var pip := ColorRect.new()
		pip.name = "ChargePip%d" % i
		pip.custom_minimum_size = Vector2(10, 4)
		pip.size_flags_vertical = SIZE_SHRINK_CENTER
		pip.mouse_filter = MOUSE_FILTER_IGNORE
		manual_readout.add_child(pip)
		_pips.append(pip)
	_refresh_manual()


func bind_money_label(target: Label) -> void:
	money_label.remove_from_group("hud_money")
	money_label = target
	money_label.add_to_group("hud_money")
	_on_money_changed(GameState.money)


func _process(delta: float) -> void:
	_readout_elapsed += delta
	if _readout_elapsed >= 0.1:
		_readout_elapsed = 0
		_refresh_manual()


func _refresh_manual() -> void:
	var count: int = GameState.cd_free_clicks_left if GameState.cd_phase == "free" else GameState.cd_charges
	_manual_label.text = "手动 ∞" if GameState.cd_phase == "off" else (
		"手动 %d 次" % count if GameState.cd_phase == "free" else "手动 %d/%d" % [count, GameState.cd_max_charges])
	manual_readout.tooltip_text = "机器人无可执行操作，可手动破局" if _idle_warning else "每 %.1f 秒恢复一次" % GameState.cd_duration
	for i in _pips.size():
		_pips[i].visible = GameState.cd_phase == "cooldown"
		_pips[i].color = UI.SIGNAL if i < count else UI.LINE


## 局内关名（"第 1 关 · 自动扫雷"）；空串隐藏
func set_level_title(text: String) -> void:
	level_title_label.text = text
	level_title_label.visible = text != ""


func set_idle_warning(show: bool) -> void:
	# 战报仍记录空闲状态；提醒按需悬停查看，不增加常驻信息行。
	_idle_warning = show
	_refresh_manual()


## 暂停面板头部目标行的来源（P5 重排后路径变，接口不变）
func get_objective_text() -> String:
	return _objective_text


func _on_game_phase_changed(phase: String) -> void:
	# 基地阶段提示挪到商店提示行（main._on_game_phase_changed 接管）：HUD 顶栏下沿
	# 与 L5 Boss 趴框位置重叠，开局提示会盖住 Boss（回归 2026-10-01 P2）
	match phase:
		"placing_base":
			phase_hint_label.visible = false
		"playing":
			phase_hint_label.visible = false


func _refresh_all() -> void:
	_on_money_changed(GameState.money)
	_on_score_changed(GameState.score)
	_on_lives_changed(GameState.lives)
	_on_time_changed(GameState.time_left)


func _on_money_changed(v: int) -> void:
	money_label.text = str(v)
	# 挣钱脉冲（教学关"标旗在挣钱"的可见性：数字放大+金色闪一下）
	if _last_money >= 0 and v > _last_money:
		_show_gain_popup(v - _last_money)
		money_label.modulate = Color(1.0, 0.85, 0.3)
		money_label.pivot_offset = money_label.size / 2.0
		var t := create_tween()
		t.tween_property(money_label, "scale", Vector2(1.35, 1.35), 0.08)
		t.parallel().tween_property(money_label, "modulate", Color.WHITE, 0.35)
		t.tween_property(money_label, "scale", Vector2.ONE, 0.15)
	elif _last_money >= 0 and v < _last_money:
		# 支出脉冲（购机/探针等扣费"钱出去了"可见；暗红短缩，与收入金放区分）
		money_label.modulate = Color(1.0, 0.5, 0.4)
		money_label.pivot_offset = money_label.size / 2.0
		var t := create_tween()
		t.tween_property(money_label, "scale", Vector2(0.88, 0.88), 0.06)
		t.parallel().tween_property(money_label, "modulate", Color.WHITE, 0.30)
		t.tween_property(money_label, "scale", Vector2.ONE, 0.12)
	_last_money = v


## 进账浮字：金币数字右侧弹「+N」上浮淡出（与盘面跳字同语言）；
## 窗口期内连续进账合并累计并重挂淡出，不逐笔刷屏。挂余额标签而非容器，
## 避免参与容器布局，同时保持在商店面板上方。
func _show_gain_popup(amount: int) -> void:
	var anchor := Vector2(money_label.size.x + 5.0, -2.0)
	if _gain_popup == null or not is_instance_valid(_gain_popup):
		_gain_popup = Label.new()
		_gain_popup.name = "MoneyGainPopup"  # 显式命名，避免遍历误匹配
		_gain_popup.add_theme_font_size_override("font_size", 13)
		_gain_popup.add_theme_color_override("font_color", GOLD)
		_gain_popup.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_gain_popup.add_theme_constant_override("outline_size", 3)
		_gain_popup.set_meta("amount", 0)
		money_label.add_child(_gain_popup)
	elif _gain_tween != null and _gain_tween.is_valid():
		_gain_tween.kill()
	_gain_popup.position = anchor
	_gain_popup.set_meta("amount", int(_gain_popup.get_meta("amount", 0)) + amount)
	_gain_popup.text = "+%d" % int(_gain_popup.get_meta("amount"))
	_gain_popup.modulate.a = 1.0
	_gain_tween = _gain_popup.create_tween()
	_gain_tween.tween_property(_gain_popup, "position:y", anchor.y - 10.0, 0.55)
	_gain_tween.parallel().tween_property(_gain_popup, "modulate:a", 0.0, 0.55)
	_gain_tween.tween_callback(func():
		_gain_popup.queue_free()
		_gain_popup = null)


func _on_score_changed(v: int) -> void:
	score_label.text = str(v)


# ---- 胜利结算演出动效（VictoryTally 驱动；与金币脉冲/进账浮字同视觉语言）----

## 总分数字脉冲回应：金色一闪 + 短促放大（strength 收尾大脉冲可给 1.4）
func fx_score_pulse(strength := 1.25) -> void:
	if _score_fx_tween != null and _score_fx_tween.is_valid():
		_score_fx_tween.kill()
		score_label.scale = Vector2.ONE
		score_label.modulate = Color.WHITE
	score_label.pivot_offset = score_label.size / 2.0
	score_label.modulate = Color(1.0, 0.85, 0.3)
	_score_fx_tween = score_label.create_tween()
	_score_fx_tween.tween_property(score_label, "scale", Vector2(strength, strength), 0.07)
	_score_fx_tween.parallel().tween_property(score_label, "modulate", Color.WHITE, 0.3)
	_score_fx_tween.tween_property(score_label, "scale", Vector2.ONE, 0.12)


## 红心弹跳（第 i 颗；胜利结算逐颗加分用）
func fx_heart_pop(i: int) -> void:
	if i < 0 or i >= hearts.size():
		return
	var h: TextureRect = hearts[i]
	h.pivot_offset = h.size / 2.0
	var t := h.create_tween()
	t.tween_property(h, "scale", Vector2(1.45, 1.45), 0.08)
	t.tween_property(h, "scale", Vector2.ONE, 0.16)


## 心旁"+N"飘字（与金钱进账浮字同款样式）
func fx_heart_gain(i: int, text: String) -> void:
	if i < 0 or i >= hearts.size():
		return
	var h: TextureRect = hearts[i]
	var lbl := Label.new()
	lbl.name = "HeartGainPopup%d" % i  # 显式命名，避免遍历误匹配
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", GOLD)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 3)
	var anchor: Vector2 = get_global_transform().affine_inverse() \
			* h.get_global_rect().end + Vector2(4.0, -2.0)
	lbl.position = anchor
	add_child(lbl)
	var t := lbl.create_tween()
	t.tween_property(lbl, "position:y", anchor.y - 12.0, 0.5)
	t.parallel().tween_property(lbl, "modulate:a", 0.0, 0.5)
	t.tween_callback(lbl.queue_free)


## 时钟演出态显示（马里奥倒计时换分；只动显示，不碰真实 time_left）
func fx_time_show(secs_left: int) -> void:
	if not GameState.has_time_limit():
		return
	time_label.text = "%d:%02d" % [secs_left / 60, secs_left % 60]
	time_label.modulate = Color(1, 0.35, 0.3) if secs_left <= 30 else Color.WHITE


func _on_lives_changed(v: int) -> void:
	var show_hearts: bool = GameState.has_life_limit()
	for i in MAX_HEARTS:
		hearts[i].visible = show_hearts
		hearts[i].texture = HEART_FULL if i < v else HEART_EMPTY


func _on_time_changed(t: float) -> void:
	if not GameState.has_time_limit():
		time_label.visible = false
		return
	time_label.visible = true
	var secs := int(ceil(t))
	time_label.text = "%d:%02d" % [secs / 60, secs % 60]
	# 后 30 秒变红预警
	time_label.modulate = Color(1, 0.35, 0.3) if secs <= 30 else Color.WHITE


func _on_objective_progress_updated(text: String, current: int, total: int) -> void:
	_objective_text = text
	var obj: ObjectiveData = GameState.current_objective
	var score_goal: bool = obj != null and obj.type == ObjectiveData.Type.REACH_SCORE
	objective_label.text = "目标积分" if score_goal else text
	score_label.visible = score_goal
	_goal_total.visible = score_goal
	_goal_total.text = "/ %d" % total
	objective_label.visible = text != ""
	# L5 拔牙关目标文字配牙图标（FIND_ALL_MINES；其他目标类型不显示）
	objective_tooth_icon.visible = text != "" and _objective_is_teeth()
	# total>0 的目标类型画细进度条（过线后满格置金）
	objective_progress_bar.visible = total > 0
	if total > 0:
		objective_progress_bar.max_value = total
		objective_progress_bar.value = mini(current, total)
		var crossed: bool = current >= total
		objective_progress_bar.modulate = Color(1.0, 0.82, 0.35) if crossed else Color.WHITE


func _objective_is_teeth() -> bool:
	var lvl: LevelData = GameState.get_current_level()
	return lvl != null and not lvl.objectives.is_empty() \
			and lvl.objectives[0].type == ObjectiveData.Type.FIND_ALL_MINES


func show_toast(text: String, duration: float = 3.0) -> void:
	clear_toast()
	toast_label.text = text
	toast_panel.visible = true
	toast_panel.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(duration)
	_toast_tween.tween_property(toast_panel, "modulate:a", 0.0, 0.5)
	_toast_tween.tween_callback(func(): toast_panel.visible = false)


func clear_toast() -> void:
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	toast_panel.hide()
