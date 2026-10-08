extends PanelContainer
## 右侧分项得分：让玩家看出"扫雷是目标，其余是分项"；零值行收起

@onready var open_label: Label = $Margin/VBox/OpenScoreLabel
@onready var flag_label: Label = $Margin/VBox/FlagScoreLabel
@onready var mine_label: Label = $Margin/VBox/MineScoreLabel
@onready var preopen_label: Label = $Margin/VBox/PreopenScoreLabel
@onready var detector_label: Label = $Margin/VBox/DetectorScoreLabel
@onready var combat_label: Label = $Margin/VBox/CombatScoreLabel


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
	var mine: int = int(s.get("mine_score", 0))
	mine_label.text = "采矿 %d" % mine
	# 采矿分项零值收起（矿工非常驻：仅未来矿工机制关会 >0，届时自然显示）
	mine_label.visible = mine > 0
	# P2-01 新来源行：零值收起（探测/战斗只在 L4/L5 出现；预开格只在 L3 有值）
	var preopen: int = int(s.get("preopen_score", 0))
	preopen_label.text = "预开格 %d" % preopen
	preopen_label.visible = preopen > 0
	var detector: int = int(s.get("detector_score", 0))
	detector_label.text = "探测 %d" % detector
	detector_label.visible = detector > 0
	var combat: int = int(s.get("combat_score", 0))
	combat_label.text = "战斗/清障 %d" % combat
	combat_label.visible = combat > 0
	# 引导/面板压暗层都在本栏之上（Main.tscn 侧栏置底），无需让路隐藏
	visible = GameState.game_active
