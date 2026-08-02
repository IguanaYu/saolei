extends Control
## 顶部 HUD：钱、积分、命、时间 + 机器人空闲提示

@onready var money_label: Label = $MarginContainer/VBoxContainer/HBoxContainer/MoneyLabel
@onready var score_label: Label = $MarginContainer/VBoxContainer/HBoxContainer/ScoreLabel
@onready var lives_label: Label = $MarginContainer/VBoxContainer/HBoxContainer/LivesLabel
@onready var time_label: Label = $MarginContainer/VBoxContainer/HBoxContainer/TimeLabel
@onready var idle_hint_label: Label = $MarginContainer/VBoxContainer/IdleHintLabel


func _ready() -> void:
	GameState.money_changed.connect(_on_money_changed)
	GameState.score_changed.connect(_on_score_changed)
	GameState.lives_changed.connect(_on_lives_changed)
	GameState.time_changed.connect(_on_time_changed)
	_refresh_all()


func set_idle_warning(show: bool) -> void:
	idle_hint_label.visible = show


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
