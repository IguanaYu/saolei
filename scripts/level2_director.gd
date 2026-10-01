extends Node
class_name Level2Director
## 外部试玩版第二关剧本控制器（docs/active/试玩版内容/第二关-设计文档.md §4/§6）
## 复用 TutorialGuide 做聚光+气泡表现层；时序由 GameState 信号驱动。
## 文案共 4 句（设计定稿 §6）：开局规则 / 高亮升级 / 首次升级 / 30s 未升级兜底。

const COPY_INTRO := "120 秒，3 条命，清空安全格。"
const COPY_UPGRADE := "机器人可以更快。"
const COPY_FASTER := "更快了。"
const COPY_LATE := "升级：所有机器人提速。"
const LATE_HINT_SEC := 30.0
const LEVEL_ID := "ch01_s02"

var _guide: Control
var _hud: Control
var _shop: Control
var _grid: Node2D
var _upgraded := false
var _tweens: Array = []


func _ready() -> void:
	var main := get_parent()
	_guide = main.get_node("UILayer/TutorialGuide")
	_hud = main.get_node("UILayer/HUD")
	_shop = main.get_node("UILayer/Shop")
	_grid = main.get_node("Grid")
	GameState.upgrade_changed.connect(_on_upgrade_changed)
	GameState.player_action_performed.connect(
		func() -> void: _guide.notify_event("player_acted"))


## 进关后启动：开局一句话 → 首次动作后高亮商店升级行，等首次升级
func begin() -> void:
	_upgraded = false
	for tw in _tweens:
		tw.kill()
	_tweens.clear()
	var board_size := Vector2(_grid.rows * _grid.cell_size, _grid.cols * _grid.cell_size)
	var tw := create_tween()
	_tweens.append(tw)
	tw.tween_interval(0.5)
	tw.tween_callback(func() -> void:
		_guide.begin([
			{"node": _grid, "size": board_size,
				"text": COPY_INTRO, "event": "board_click", "tip": "right"},
			# 点开升级面板即收引导（面板在引导压暗层下会发黑，弹出时要全亮）
			{"node": _shop.get_node("MarginContainer/VBoxContainer/BuildRow/UpgradeButton"),
				"text": COPY_UPGRADE, "event": "upgrade_panel_opened", "tip": "below"},
		]))
	# 30s 仍未买任何升级 → 兜底提示（设计 §6 第 4 句）
	var late := create_tween()
	_tweens.append(late)
	late.tween_interval(LATE_HINT_SEC)
	late.tween_callback(func() -> void:
		if _active() and not _upgraded:
			_hud.show_toast(COPY_LATE, 3.0))


func _active() -> bool:
	return GameState.game_active and GameState.current_level_id == LEVEL_ID


func _on_upgrade_changed(_upgrade_id: String, _new_level: int) -> void:
	if not _active():
		return
	_guide.notify_event("upgraded")
	if not _upgraded:
		_upgraded = true
		_hud.show_toast(COPY_FASTER, 2.0)
