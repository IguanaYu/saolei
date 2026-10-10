extends Node
class_name Ch02S3Director
## 第二章 2-3「特殊矿石」剧本控制器（改版 2026-10-10 重写，折光版随关卡重摆归档）
## 一句聚光：开局展示矿石（等首次爆发推进）；二次触发时 toast「可反复触发」——
## 无限次是矿石与一切一次性设施的核心差异，值得一句轻提示（散射 toast 先例）。

const COPY_INTRO := "射中特殊矿石，向三面爆发。"
const COPY_REPEAT := "这块矿石可以反复触发。"
var _guide: Control
var _grid: Node2D
var _repeat_toasted := false


func _ready() -> void:
	var main := get_parent()
	_guide = main.get_node("UILayer/TutorialGuide")
	_grid = main.get_node("BoardRoot/Grid")
	main.get_node("BoardRoot/LaserManager").ore_burst.connect(_on_ore_burst)


func begin() -> void:
	_repeat_toasted = false
	var board_size := Vector2(_grid.cols * _grid.cell_size, _grid.rows * _grid.cell_size)
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_callback(func() -> void:
		_guide.begin([
			{"node": _grid, "size": board_size,
				"text": COPY_INTRO, "event": "ore_burst", "tip": "right"},
		]))


## 无限次轻提示：第二次爆发时机（首爆已由聚光句+亮框自解释）
func _on_ore_burst(_ore, _cells: Array) -> void:
	if not GameState.game_active or GameState.current_level_id != "ch02_s03":
		return
	if _repeat_toasted:
		return
	# 第一次爆发只推进聚光；第二次才提示可反复触发
	var stats_bursts: int = int(GameState.result_stats.get("ore_bursts", 0))
	if stats_bursts >= 2:
		_repeat_toasted = true
		var hud: Control = get_parent().get_node("UILayer/HUD")
		hud.show_toast(COPY_REPEAT, 3.0)
