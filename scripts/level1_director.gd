extends Node
class_name Level1Director
## 外部试玩版第一关剧本控制器（docs/active/试玩版内容/第一关-设计文档.md §4）
## 复用 TutorialGuide 做聚光+气泡表现层；时序由 GameState 信号驱动。
## 文案共 5 句（设计定稿 §6）：开局 1 / 耗尽 1 / 高亮商店 1 / 15s 升级 1 / 首购 1。

const COPY_INTRO := "左键开格，右键标旗。"
const COPY_EXHAUSTED := "指挥次数用完了。"
const COPY_SHOP := "雇一台常驻机器人——它不占你的次数。"
const COPY_SHOP_TIMEOUT := "机器人只要 50。"
const COPY_RECOVERED := "次数恢复：3 秒/次。"

var _guide: Control
var _hud: Control
var _shop: Control
var _grid: Node2D
var _exhausted_seen := false


func _ready() -> void:
	var main := get_parent()
	_guide = main.get_node("UILayer/TutorialGuide")
	_hud = main.get_node("UILayer/HUD")
	_shop = main.get_node("UILayer/Shop")
	_grid = main.get_node("BoardRoot/Grid")
	GameState.cd_exhausted.connect(_on_cd_exhausted)
	GameState.cd_duration_changed.connect(_on_cd_duration_changed)
	GameState.player_action_performed.connect(
		func() -> void: _guide.notify_event("player_acted"))


## 进关后启动：开局一句话，等首次有效动作推进
func begin() -> void:
	_exhausted_seen = false
	var board_size := Vector2(_grid.cols * _grid.cell_size, _grid.rows * _grid.cell_size)  # 2026-10-04 修复轴反(原rows/cols对调,方形盘无症状)
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_callback(func() -> void:
		_guide.begin([
			{"node": _grid, "size": board_size,
				"text": COPY_INTRO, "event": "board_click", "tip": "right"},
		]))


func _on_cd_exhausted() -> void:
	if not GameState.game_active or GameState.current_level_id != "ch01_s01":
		return
	_exhausted_seen = true
	var board_size := Vector2(_grid.cols * _grid.cell_size, _grid.rows * _grid.cell_size)  # 2026-10-04 修复轴反(原rows/cols对调,方形盘无症状)
	_guide.begin([
		{"node": _grid, "size": board_size,
			"text": COPY_EXHAUSTED, "event": "", "tip": "right"},
		{"node": _shop,
			"text": COPY_SHOP, "event": "robot_bought",
			"timeout_sec": 15.0, "timeout_text": COPY_SHOP_TIMEOUT,
			"tip": "below"},
	])
	# 免费阶段提前买过（robot_bought 已发生）：guide 竞态修复会用 pending 事件自动跳过商店步


func _on_cd_duration_changed(_new_duration: float) -> void:
	# 耗尽前首购不提示（CD 概念尚未揭示）
	if _exhausted_seen and GameState.game_active:
		_hud.show_toast(COPY_RECOVERED, 3.0)
