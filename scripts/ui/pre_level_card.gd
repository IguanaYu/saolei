extends Control
## 关前卡片：只显示当前关配置出的真实数字（布局计划 §2.2，不重复维护硬编码文案）

signal start_confirmed(level_id: String)

var _level_id := ""

@onready var title_label: Label = $Center/Panel/Margin/VBox/TitleLabel
@onready var goal_label: Label = $Center/Panel/Margin/VBox/GoalLabel
@onready var robots_label: Label = $Center/Panel/Margin/VBox/RobotsLabel
@onready var time_label: Label = $Center/Panel/Margin/VBox/TimeLabel
@onready var skip_check: CheckBox = $Center/Panel/Margin/VBox/SkipCheck
@onready var start_button: Button = $Center/Panel/Margin/VBox/StartButton


func _ready() -> void:
	hide()
	start_button.pressed.connect(_on_start)


func open(lvl: LevelData) -> void:
	_level_id = lvl.id
	var sname := lvl.short_name if lvl.short_name != "" else lvl.display_name
	title_label.text = "第 %s 关 · %s" % [lvl.display_name.substr(2), sname]
	var obj: ObjectiveData = lvl.objectives[0] if not lvl.objectives.is_empty() else null
	goal_label.text = "目标：%s" % (obj.short_label() if obj != null else "清空安全格")
	robots_label.text = "本关要素：%s" % ("、".join(lvl.mechanic_tags) \
			if not lvl.mechanic_tags.is_empty() else "基础机器人")
	time_label.text = _time_line(lvl)
	skip_check.visible = SaveSystem.is_level_cleared(lvl.id)   # 首次必看
	skip_check.button_pressed = bool(GameSettings.get_value("skip_pre_level"))
	show()
	start_button.grab_focus()


func _time_line(lvl: LevelData) -> String:
	if lvl.time_limit_sec <= 0:
		return "本关不限时"
	return "限时 %d 秒\n到点正常结算收益，未达标可重玩" % int(lvl.time_limit_sec)


func _on_start() -> void:
	if skip_check.visible:
		GameSettings.set_value("skip_pre_level", skip_check.button_pressed)
	start_confirmed.emit(_level_id)
	hide()
