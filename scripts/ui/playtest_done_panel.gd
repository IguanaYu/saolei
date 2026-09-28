extends Control
## 试玩完成页：5/5 关达标后的总结（总用时/最高分，读盲测记录聚合）
## 不显示第 2 章 /「完整版即将解锁」类入口（布局计划 §2.5）

signal done_back_requested
signal done_menu_requested

@onready var time_label: Label = $Center/Panel/Margin/VBox/TimeLabel
@onready var best_label: Label = $Center/Panel/Margin/VBox/BestLabel
@onready var feedback_button: Button = $Center/Panel/Margin/VBox/FeedbackButton


func _ready() -> void:
	hide()
	$Center/Panel/Margin/VBox/ButtonsRow/BackButton.pressed.connect(
		func(): done_back_requested.emit())
	$Center/Panel/Margin/VBox/ButtonsRow/MenuButton.pressed.connect(
		func(): done_menu_requested.emit())


func open() -> void:
	var total := 0.0
	var best := 0
	for r in SaveSystem.stats.get("playtest", []):
		if r.get("result") == "win":
			total += float(r.get("elapsed", 0.0))
			best = maxi(best, int(r.get("score", 0)))
	time_label.text = "试玩总用时 %s" % SaveSystem.format_duration(total)
	best_label.text = "最高分 %d" % best
	feedback_button.visible = str(GameSettings.get_value("feedback_url")) != ""
	show()
