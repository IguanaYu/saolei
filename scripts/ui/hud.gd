extends Control
## 顶部 HUD：图标化资源条（钱/矿石/积分）+ 命数心形 + 倒计时 + 暂停按钮 + 提示

const HEART_FULL := preload("res://visual_v2/runtime/ui/icons/icon_heart.png")
const HEART_EMPTY := preload("res://visual_v2/runtime/ui/icons/icon_heart_empty.png")
const MAX_HEARTS := 3

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
@onready var objective_label: Label = $MarginContainer/VBoxContainer/TopRow/MiddleBox/ObjectiveLabel
@onready var objective_progress_bar: ProgressBar = $MarginContainer/VBoxContainer/TopRow/MiddleBox/ObjectiveProgressBar
@onready var idle_hint_label: Label = $MarginContainer/VBoxContainer/IdleHintLabel
@onready var phase_hint_label: Label = $MarginContainer/VBoxContainer/PhaseHintLabel
@onready var toast_panel: PanelContainer = $ToastPanel
@onready var toast_label: Label = $ToastPanel/ToastLabel

var _last_money: int = -1


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
	match phase:
		"placing_base":
			phase_hint_label.text = "请放置第一个基地（点击任意格子）"
			phase_hint_label.visible = true
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
		money_label.modulate = Color(1.0, 0.85, 0.3)
		money_label.pivot_offset = money_label.size / 2.0
		var t := create_tween()
		t.tween_property(money_label, "scale", Vector2(1.35, 1.35), 0.08)
		t.parallel().tween_property(money_label, "modulate", Color.WHITE, 0.35)
		t.tween_property(money_label, "scale", Vector2.ONE, 0.15)
	_last_money = v


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
	# total>0 的目标类型画细进度条（过线后满格置金）
	objective_progress_bar.visible = total > 0
	if total > 0:
		objective_progress_bar.max_value = total
		objective_progress_bar.value = mini(current, total)
		var crossed: bool = current >= total
		objective_progress_bar.modulate = Color(1.0, 0.82, 0.35) if crossed else Color.WHITE


func show_toast(text: String, duration: float = 3.0) -> void:
	toast_label.text = text
	toast_panel.visible = true
	toast_panel.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(duration)
	t.tween_property(toast_panel, "modulate:a", 0.0, 0.5)
	t.tween_callback(func(): toast_panel.visible = false)
