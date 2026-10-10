extends Node
class_name Ch02S3Director
## 第二章 2-3「折光机器人」剧本控制器（设计 §5 关内流程，实施计划 WP7）
## 两句聚光：开局展示预设宽束（等首次增幅推进）→ 散射轻提示（放散射配置时 toast）；
## 首次增幅由束宽对比自解释（设计「用前后宽度直接展示效果」），不占聚光步。

const COPY_INTRO := "射中折光机器人，激光变宽。"
const COPY_SCATTER := "散射适合分开的目标。"

var _guide: Control
var _grid: Node2D
var _scatter_toasted := false


func _ready() -> void:
	var main := get_parent()
	_guide = main.get_node("UILayer/TutorialGuide")
	_grid = main.get_node("BoardRoot/Grid")
	GameState.robot_spawned.connect(_on_robot_spawned)


func begin() -> void:
	_scatter_toasted = false
	var board_size := Vector2(_grid.cols * _grid.cell_size, _grid.rows * _grid.cell_size)
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_callback(func() -> void:
		_guide.begin([
			{"node": _grid, "size": board_size,
				"text": COPY_INTRO, "event": "refractor_activated", "tip": "right"},
		]))


## 散射轻提示：玩家部署散射配置时一次性 toast（不强制购买，设计 §5）
func _on_robot_spawned(robot_type: String) -> void:
	if not GameState.game_active or GameState.current_level_id != "ch02_s03":
		return
	if robot_type == "refractor_scatter" and not _scatter_toasted:
		_scatter_toasted = true
		var hud: Control = get_parent().get_node("UILayer/HUD")
		hud.show_toast(COPY_SCATTER, 3.0)
