extends Control
## 顶部 HUD：图标化资源条（钱/矿石/积分）+ 命数心形 + 倒计时 + 暂停按钮 + 提示

const HEART_FULL := preload("res://visual_v2/runtime/ui/icons/icon_heart.png")
const HEART_EMPTY := preload("res://visual_v2/runtime/ui/icons/icon_heart_empty.png")
const MAX_HEARTS := 3
const GOLD := Color(1.0, 0.753, 0.29)  # 矿金 #f0c04a，与盘面跳字同色

signal pause_requested

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


func _ready() -> void:
	money_label.add_to_group("hud_money")  # 卸货飞币动效的落点（EffectsLayer 查组取位置）
	GameState.money_changed.connect(_on_money_changed)
	GameState.score_changed.connect(_on_score_changed)
	GameState.lives_changed.connect(_on_lives_changed)
	GameState.time_changed.connect(_on_time_changed)
	GameState.game_phase_changed.connect(_on_game_phase_changed)
	GameState.objective_progress_updated.connect(_on_objective_progress_updated)
	$MarginContainer/VBoxContainer/TopRow/RightPanel/RightBox/PauseButton.pressed.connect(
		func(): pause_requested.emit())
	_refresh_all()
	_on_game_phase_changed(GameState.game_phase)


## 局内关名（"第 1 关 · 自动扫雷"）；空串隐藏
func set_level_title(text: String) -> void:
	level_title_label.text = text
	level_title_label.visible = text != ""


func set_idle_warning(show: bool) -> void:
	idle_hint_label.visible = show


## 暂停面板头部目标行的来源（P5 重排后路径变，接口不变）
func get_objective_text() -> String:
	return objective_label.text


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
## 窗口期内连续进账合并累计并重挂淡出，不逐笔刷屏。挂 HUD 根节点而非
## ResBox/MoneyPanel——容器会自动重排子节点，会顶乱现有资源条布局
func _show_gain_popup(amount: int) -> void:
	var anchor: Vector2 = get_global_transform().affine_inverse() \
			* money_label.get_global_rect().end + Vector2(5.0, -2.0)
	if _gain_popup == null or not is_instance_valid(_gain_popup):
		_gain_popup = Label.new()
		_gain_popup.name = "MoneyGainPopup"  # 显式命名，避免遍历误匹配
		_gain_popup.add_theme_font_size_override("font_size", 13)
		_gain_popup.add_theme_color_override("font_color", GOLD)
		_gain_popup.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_gain_popup.add_theme_constant_override("outline_size", 3)
		_gain_popup.set_meta("amount", 0)
		add_child(_gain_popup)
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
	objective_label.text = text
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
	toast_label.text = text
	toast_panel.visible = true
	toast_panel.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(duration)
	t.tween_property(toast_panel, "modulate:a", 0.0, 0.5)
	t.tween_callback(func(): toast_panel.visible = false)
