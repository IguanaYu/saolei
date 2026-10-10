extends Node
class_name Ch02S2Director
## 第二章 2-2「充能与拆敌」剧本控制器（设计 §4 关内流程，实施计划 WP7）
## 三句聚光：开局充能 → 筑墙工预警 → 首次命中敌；充能与拆墙收益视觉自解释不占文案。

const COPY_INTRO := "扫到机器人，短时加速。"
const COPY_BUILDER := "它会在已开处补墙。"
const COPY_HIT := "激光也能击破敌人。"

var _guide: Control
var _grid: Node2D


func _ready() -> void:
	var main := get_parent()
	_guide = main.get_node("UILayer/TutorialGuide")
	_grid = main.get_node("BoardRoot/Grid")


func begin() -> void:
	var board_size := Vector2(_grid.cols * _grid.cell_size, _grid.rows * _grid.cell_size)
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_callback(func() -> void:
		_guide.begin([
			{"node": _grid, "size": board_size,
				"text": COPY_INTRO, "event": "robots_charged", "tip": "right"},
			{"node": _grid, "size": board_size,
				"text": COPY_BUILDER, "event": "builder_spawned", "tip": "right"},
			{"node": _grid, "size": board_size,
				"text": COPY_HIT, "event": "builder_damaged", "tip": "right"},
		]))
