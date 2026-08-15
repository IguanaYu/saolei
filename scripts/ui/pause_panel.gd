extends Control
## 暂停面板：局内 ESC / HUD 暂停按钮呼出；继续 / 重开 / 设置 / 放弃

signal resume_requested
signal restart_requested
signal settings_requested
signal abandon_requested

@onready var context_label: Label = $Center/Panel/VBox/ContextLabel
@onready var run_stats_label: Label = $Center/Panel/VBox/RunStatsLabel
@onready var resume_button: Button = $Center/Panel/VBox/ResumeButton


func _ready() -> void:
	hide()
	resume_button.pressed.connect(func(): resume_requested.emit())
	$Center/Panel/VBox/RestartButton.pressed.connect(func(): restart_requested.emit())
	$Center/Panel/VBox/SettingsButton.pressed.connect(func(): settings_requested.emit())
	$Center/Panel/VBox/AbandonButton.pressed.connect(func(): abandon_requested.emit())


## context: "第 2 章 · 1-3 · 水晶洞窟" 或 "每日挑战 · 8月15日"
func open(context_text: String) -> void:
	context_label.text = context_text
	_refresh()
	show()
	resume_button.grab_focus()


func _refresh() -> void:
	var hearts := "♥".repeat(clamp(GameState.lives, 0, 3)) \
			+ "♡".repeat(clamp(3 - GameState.lives, 0, 3))
	var secs := int(ceil(max(0.0, GameState.time_left)))
	run_stats_label.text = "金币 %d · 积分 %d · 命 %s · 剩余 %d:%02d" % [
		GameState.money, GameState.score, hearts, secs / 60, secs % 60]
