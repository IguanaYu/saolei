extends Control
## 结算面板：游戏结束时显示

@onready var result_title_label: Label = $VBoxContainer/ResultTitleLabel
@onready var final_score_label: Label = $VBoxContainer/FinalScoreLabel
@onready var stats_label: Label = $VBoxContainer/StatsLabel
@onready var restart_button: Button = $VBoxContainer/RestartButton


func _ready() -> void:
	hide()
	GameState.game_over.connect(_on_game_over)
	restart_button.pressed.connect(_on_restart)


func _on_game_over(result: String) -> void:
	show()
	var title_map := {"win": "胜利！", "lose": "失败", "timeout": "时间到"}
	result_title_label.text = title_map.get(result, "结束")
	final_score_label.text = "最终积分: %d" % GameState.score
	var time_used := 60.0 - GameState.time_left
	stats_label.text = "用时: %.1f 秒" % max(0.0, time_used)


func _on_restart() -> void:
	GameState.reset_state()
	get_tree().reload_current_scene()
