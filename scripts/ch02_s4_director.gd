extends Node
class_name Ch02S4Director
## 第二章 2-4「过载机器人」剧本控制器（改版 2026-10-10 重写，连爆版随关卡重摆归档）
## 一句聚光：开局展示过载机（等首次爆炸推进）；购入时 toast 解释巡逻偏好
## （走位即提示：AI 偏好低数字×靠墙格，正是玩家最想开墙的位置）；
## 爆破收益由 13 格亮框+束闪光自解释，不占聚光步。

const COPY_INTRO := "射中过载机器人，原地爆发。"
const COPY_PATROL := "它自己会走到低数字的墙边。"

var _guide: Control
var _grid: Node2D
var _patrol_toasted := false


func _ready() -> void:
	var main := get_parent()
	_guide = main.get_node("UILayer/TutorialGuide")
	_grid = main.get_node("BoardRoot/Grid")
	GameState.robot_spawned.connect(_on_robot_spawned)


func begin() -> void:
	_patrol_toasted = false
	var board_size := Vector2(_grid.cols * _grid.cell_size, _grid.rows * _grid.cell_size)
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_callback(func() -> void:
		_guide.begin([
			{"node": _grid, "size": board_size,
				"text": COPY_INTRO, "event": "overload_blast", "tip": "right"},
		]))


## 购入轻提示：解释「等它走到位」的读秒玩法（s3 散射 toast 先例，不强制不占聚光）
func _on_robot_spawned(robot_type: String) -> void:
	if _patrol_toasted or not GameState.game_active \
			or GameState.current_level_id != "ch02_s04":
		return
	if robot_type == "overload":
		_patrol_toasted = true
		var hud: Control = get_parent().get_node("UILayer/HUD")
		hud.show_toast(COPY_PATROL, 3.0)
