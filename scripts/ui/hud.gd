extends Control
## 顶部 HUD：钱、积分、命、时间 + 机器人空闲提示 + 阶段提示

@onready var money_label: Label = $MarginContainer/VBoxContainer/HBoxContainer/MoneyLabel
@onready var score_label: Label = $MarginContainer/VBoxContainer/HBoxContainer/ScoreLabel
@onready var lives_label: Label = $MarginContainer/VBoxContainer/HBoxContainer/LivesLabel
@onready var time_label: Label = $MarginContainer/VBoxContainer/HBoxContainer/TimeLabel
@onready var idle_hint_label: Label = $MarginContainer/VBoxContainer/IdleHintLabel
@onready var phase_hint_label: Label = $MarginContainer/VBoxContainer/PhaseHintLabel
@onready var toast_label: Label = $MarginContainer/VBoxContainer/ToastLabel


func _ready() -> void:
	GameState.money_changed.connect(_on_money_changed)
	GameState.score_changed.connect(_on_score_changed)
	GameState.lives_changed.connect(_on_lives_changed)
	GameState.time_changed.connect(_on_time_changed)
	GameState.game_phase_changed.connect(_on_game_phase_changed)
	_refresh_all()
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
	money_label.text = "钱: %d" % v


func _on_score_changed(v: int) -> void:
	score_label.text = "积分: %d" % v


func _on_lives_changed(v: int) -> void:
	lives_label.text = "命: %d/3" % v


func _on_time_changed(t: float) -> void:
	time_label.text = "时间: 0:%02d" % int(ceil(t))


func show_toast(text: String, duration: float = 3.0) -> void:
	toast_label.text = text
	toast_label.visible = true
	toast_label.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(duration)
	t.tween_property(toast_label, "modulate:a", 0.0, 0.5)
	t.tween_callback(func(): toast_label.visible = false)
