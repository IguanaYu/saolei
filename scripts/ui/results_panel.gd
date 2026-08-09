extends Control
## 结算面板：游戏结束时显示；区分首通 / 重刷奖励

signal restart_requested
signal back_to_level_select_requested

@onready var result_title_label: Label = $VBoxContainer/ResultTitleLabel
@onready var final_score_label: Label = $VBoxContainer/FinalScoreLabel
@onready var stats_label: Label = $VBoxContainer/StatsLabel
@onready var restart_button: Button = $VBoxContainer/RestartButton
@onready var back_button: Button = $VBoxContainer/BackButton


func _ready() -> void:
	hide()
	GameState.game_over.connect(_on_game_over)
	restart_button.pressed.connect(func(): restart_requested.emit())
	back_button.pressed.connect(func(): back_to_level_select_requested.emit())


func _on_game_over(result: String) -> void:
	show()
	final_score_label.text = "最终积分: %d" % GameState.score
	if GameState.current_level_id == "":
		_handle_free_mode(result)
	else:
		_handle_level_mode(result)


## 旧自由模式（无关卡）：积分/10 换矿石
func _handle_free_mode(result: String) -> void:
	var title_map := {"win": "胜利！", "lose": "失败", "timeout": "时间到"}
	result_title_label.text = title_map.get(result, "结束")
	var time_used: float = 90.0 - GameState.time_left
	var ore_earned: int = GameState.score / 10
	SaveSystem.add_ore(ore_earned)
	stats_label.text = "用时: %.1f 秒\n获得矿石: +%d" % [max(0.0, time_used), ore_earned]


func _handle_level_mode(result: String) -> void:
	if result != "win":
		result_title_label.text = "失败"
		stats_label.text = "再接再厉"
		return
	var stars := _calculate_stars()
	var is_first: bool = not SaveSystem.is_first_clear_claimed(GameState.current_level_id)
	var lines := ["星数: %d/3" % stars]
	if is_first:
		var r := LevelSystem.claim_first_clear(GameState.current_level_id)
		lines.append("首通奖励: +%d 矿" % (r.ore if r != null else 0))
	else:
		var lvl := LevelSystem.get_level(GameState.current_level_id)
		var ore: int = lvl.repeat_reward.ore if lvl != null else 0
		SaveSystem.add_ore(ore)
		lines.append("重刷奖励: +%d 矿" % ore)
	LevelSystem.mark_cleared(GameState.current_level_id, stars)
	result_title_label.text = "首通胜利" if is_first else "重刷胜利"
	stats_label.text = "\n".join(lines)


## 1 星保底；命 ≥ 2 +1 星；快速通关（剩余 ≥ 50%）+1 星（生存关不加）
func _calculate_stars() -> int:
	var stars := 1
	if GameState.lives >= 2:
		stars += 1
	var obj := GameState.current_objective
	if obj == null or obj.type != ObjectiveData.Type.SURVIVE_TIME:
		var lvl := GameState.get_current_level()
		if lvl != null and GameState.time_left >= lvl.time_limit_sec * 0.5:
			stars += 1
	return stars
