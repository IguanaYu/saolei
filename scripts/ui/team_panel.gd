extends PanelContainer
## 队伍概况（左栏）：让玩家判断投资是否有效（"开墙 2 台 · 1 台空闲"→ 指向空闲原因）

const NAMES := {"opener": "开墙", "marker": "标雷", "detector": "检测", "miner": "矿工",
	"guard": "保安"}
const IDLE_REASON := {
	"opener": "暂无可推理目标", "marker": "暂无可推理目标",
	"detector": "暂无可检测旗位", "miner": "暂无可采矿脉",
}

@onready var _rows := {
	"opener": $Margin/VBox/OpenerRow, "marker": $Margin/VBox/MarkerRow,
	"detector": $Margin/VBox/DetectorRow, "miner": $Margin/VBox/MinerRow,
	"guard": $Margin/VBox/GuardRow,
}


func _ready() -> void:
	hide()
	mouse_filter = MOUSE_FILTER_IGNORE
	var rm := get_node("/root/Main/RobotManager")
	GameState.robot_spawned.connect(func(_t): _refresh())
	rm.robot_removed.connect(func(_r, _reason): _refresh())
	var t := Timer.new()          # 状态随时变（idle↔moving），低频轮询即可
	t.name = "RefreshTimer"
	t.wait_time = 0.5
	t.timeout.connect(_refresh)
	add_child(t)
	t.start()


func _refresh() -> void:
	var rm := get_node("/root/Main/RobotManager")
	var counts := {}
	var idle := {}
	for r in rm.robots:
		counts[r.robot_type] = counts.get(r.robot_type, 0) + 1
		if r.is_idle():
			idle[r.robot_type] = idle.get(r.robot_type, 0) + 1
	# 行文字保持单行短句（勿加长文案：autowrap 在主题 FontVariation 下 min size 按逐字断行算，会撑爆面板）
	var idle_reason := ""
	for type in NAMES:
		var n: int = counts.get(type, 0)
		var line := "%s %d 台" % [NAMES[type], n]
		if type == "guard":
			# 保安无"空闲"概念（is_idle 恒 false）：按有无目标显示交战/执勤（P2-02）
			var engaged := 0
			for r in rm.robots:
				if r.robot_type == "guard" and r.is_engaged():
					engaged += 1
			line += " · %s" % ("交战中" if engaged > 0 else "执勤中")
			_rows[type].text = line
			_rows[type].visible = n > 0 or _guard_in_shop()
			continue
		if idle.get(type, 0) > 0:
			line += " · %d 空闲" % idle[type]
			if idle[type] == n and idle_reason == "":
				idle_reason = IDLE_REASON[type]
		_rows[type].text = line
		_rows[type].visible = n > 0 or _type_in_shop(type)   # 没买过的类型：本关可买才显示
	$Margin/VBox/EventHintLabel.text = "空闲原因：%s" % idle_reason if idle_reason != "" else ""
	# 引导/面板压暗层都在本栏之上（Main.tscn 侧栏置底），无需让路隐藏
	visible = GameState.game_active


func _type_in_shop(type: String) -> bool:
	var lvl: LevelData = GameState.get_current_level()
	return lvl != null and not lvl.shop_hidden.has(type)


## 保安的可见性口径与商店一致（shop.gd：extra 反向开闸，L4/L5 声明才出现）——
## 不能用 _type_in_shop（guard 不在 L1-L3 的 shop_hidden 里，会误显示）
func _guard_in_shop() -> bool:
	var lvl: LevelData = GameState.get_current_level()
	return lvl != null and lvl.shop_extra.has("guard") and not lvl.shop_hidden.has("guard")
