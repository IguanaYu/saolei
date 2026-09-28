extends PanelContainer
## 右侧分项得分：让玩家看出"采矿是加分，扫雷是目标"

@onready var open_label: Label = $Margin/VBox/OpenScoreLabel
@onready var flag_label: Label = $Margin/VBox/FlagScoreLabel
@onready var mine_label: Label = $Margin/VBox/MineScoreLabel


func _ready() -> void:
	hide()
	mouse_filter = MOUSE_FILTER_IGNORE
	GameState.score_changed.connect(func(_v): _refresh())
	GameState.money_changed.connect(func(_v): _refresh())   # 卸货同时加钱加分
	var t := Timer.new()   # game_active 翻转无信号，低频轮询兜底显隐
	t.name = "RefreshTimer"
	t.wait_time = 0.5
	t.timeout.connect(_refresh)
	add_child(t)
	t.start()
	_refresh()


func _refresh() -> void:
	var s: Dictionary = GameState.result_stats
	open_label.text = "开格 %d" % int(s["open_score"])
	flag_label.text = "标雷 %d" % int(s["flag_score"])
	mine_label.text = "采矿 %d" % int(s.get("mine_score", 0))
	visible = GameState.game_active
