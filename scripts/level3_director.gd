extends Node
class_name Level3Director
## 外部试玩版第三关剧本控制器（docs/active/试玩版内容/第三关-设计文档.md §4.2/§6）
## 剧本极薄：全关 ≤3 句——间场句在选关页（level_select），过线 toast 在 main._apply_time_bonus，
## 本 director 只负责进关一句。局外效果不用文字解释，进场即见。

const COPY_INTRO := "积分 300，不用扫完。"
const LEVEL_ID := "ch01_s03"

var _guide: Control
var _grid: Node2D
var _tweens: Array = []


func _ready() -> void:
	var main := get_parent()
	_guide = main.get_node("UILayer/TutorialGuide")
	_grid = main.get_node("Grid")


## 进关后启动：0.5s 后盘面聚光气泡（目标型玩法首见——"不用扫完"的核心认知）
func begin() -> void:
	for tw in _tweens:
		tw.kill()
	_tweens.clear()
	var board_size := Vector2(_grid.rows * _grid.cell_size, _grid.cols * _grid.cell_size)
	var tw := create_tween()
	_tweens.append(tw)
	tw.tween_interval(0.5)
	tw.tween_callback(func() -> void:
		if _active():
			_guide.begin([
				{"node": _grid, "size": board_size,
					"text": COPY_INTRO, "event": "board_click", "tip": "right"},
			]))


func _active() -> bool:
	return GameState.game_active and GameState.current_level_id == LEVEL_ID
