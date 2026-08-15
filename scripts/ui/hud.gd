extends Control
## 顶部 HUD：图标化资源条（钱/矿石/积分）+ 命数心形 + 倒计时 + 提示

const HEART_FULL := preload("res://assets/ui/icons/icon_heart.png")
const HEART_EMPTY := preload("res://assets/ui/icons/icon_heart_empty.png")
const MAX_HEARTS := 3

@onready var money_label: Label = $MarginContainer/VBoxContainer/TopRow/ResPanel/ResBox/MoneyLabel
@onready var score_label: Label = $MarginContainer/VBoxContainer/TopRow/ResPanel/ResBox/ScoreLabel
@onready var time_label: Label = $MarginContainer/VBoxContainer/TopRow/RightPanel/RightBox/TimeLabel
@onready var ore_label: Label = $MarginContainer/VBoxContainer/TopRow/ResPanel/ResBox/OreLabel
@onready var hearts: Array = [
	$MarginContainer/VBoxContainer/TopRow/RightPanel/RightBox/Heart1,
	$MarginContainer/VBoxContainer/TopRow/RightPanel/RightBox/Heart2,
	$MarginContainer/VBoxContainer/TopRow/RightPanel/RightBox/Heart3,
]
@onready var objective_label: Label = $MarginContainer/VBoxContainer/ObjectiveLabel
@onready var idle_hint_label: Label = $MarginContainer/VBoxContainer/IdleHintLabel
@onready var phase_hint_label: Label = $MarginContainer/VBoxContainer/PhaseHintLabel
@onready var toast_label: Label = $MarginContainer/VBoxContainer/ToastLabel


func _ready() -> void:
	GameState.money_changed.connect(_on_money_changed)
	GameState.score_changed.connect(_on_score_changed)
	GameState.lives_changed.connect(_on_lives_changed)
	GameState.time_changed.connect(_on_time_changed)
	GameState.game_phase_changed.connect(_on_game_phase_changed)
	GameState.objective_progress_updated.connect(_on_objective_progress_updated)
	SaveSystem.ore_changed.connect(_on_ore_changed)
	_refresh_all()
	_on_ore_changed(SaveSystem.ore)
	_on_game_phase_changed(GameState.game_phase)


func set_idle_warning(show: bool) -> void:
	idle_hint_label.visible = show


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


func _on_score_changed(v: int) -> void:
	score_label.text = str(v)


func _on_lives_changed(v: int) -> void:
	for i in MAX_HEARTS:
		hearts[i].texture = HEART_FULL if i < v else HEART_EMPTY


func _on_time_changed(t: float) -> void:
	var secs := int(ceil(t))
	time_label.text = "%d:%02d" % [secs / 60, secs % 60]
	# 后 30 秒变红预警
	time_label.modulate = Color(1, 0.35, 0.3) if secs <= 30 else Color.WHITE


func _on_objective_progress_updated(text: String) -> void:
	objective_label.text = text
	objective_label.visible = text != ""


func show_toast(text: String, duration: float = 3.0) -> void:
	toast_label.text = text
	toast_label.visible = true
	toast_label.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(duration)
	t.tween_property(toast_label, "modulate:a", 0.0, 0.5)
	t.tween_callback(func(): toast_label.visible = false)


func _on_ore_changed(v: int) -> void:
	ore_label.text = str(v)
