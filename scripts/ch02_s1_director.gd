extends Node
class_name Ch02S1Director
## 第二章 2-1「激光开矿」剧本控制器（设计 §4 关内流程，实施计划 WP8）
## 复用 TutorialGuide 聚光+气泡；时序动作事件驱动（不卡秒、不强迫误打）。
## 文案 3 句 + 2 条 toast：开局/首削加固墙/首次正确标记上气泡；
## 首次发射与首次误打是视觉/结算自解释事件，走 toast 不占聚光。

const COPY_INTRO := "点远处，沿线开墙。"
const COPY_WALL := "三层墙，要打三次。"
const COPY_FLAG := "钻石先标记，收益更高。"
const COPY_SHATTER := "未标记打碎，只有少量分。"
const COPY_FIRST_FIRE := "点得越远，影响的格子越多。"   # 首次发射 toast（束闪光自解释）

var _guide: Control
var _hud: Control
var _grid: Node2D
var _shatter_toasted := false
var _first_fire_toasted := false


func _ready() -> void:
	var main := get_parent()
	_guide = main.get_node("UILayer/TutorialGuide")
	_hud = main.get_node("UILayer/HUD")
	_grid = main.get_node("BoardRoot/Grid")
	main.get_node("BoardRoot/LaserManager").laser_fired.connect(_on_laser_fired)
	_grid.cell_flagged.connect(_on_cell_flagged)
	_grid.diamond_shattered.connect(_on_diamond_shattered)


func begin() -> void:
	_shatter_toasted = false
	_first_fire_toasted = false
	var board_size := Vector2(_grid.cols * _grid.cell_size, _grid.rows * _grid.cell_size)
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_callback(func() -> void:
		_guide.begin([
			{"node": _grid, "size": board_size,
				"text": COPY_INTRO, "event": "laser_fired", "tip": "right"},
			{"node": _grid, "size": board_size,
				"text": COPY_WALL, "event": "wall_damaged", "tip": "right"},
			{"node": _grid, "size": board_size,
				"text": COPY_FLAG, "event": "first_correct_flag", "tip": "right"},
		]))


func _in_level() -> bool:
	return GameState.game_active and GameState.current_level_id == "ch02_s01"


func _on_laser_fired(_target: Vector2i) -> void:
	if not _in_level() or _first_fire_toasted:
		return
	_first_fire_toasted = true
	_hud.show_toast(COPY_FIRST_FIRE, 3.0)


func _on_cell_flagged(_cell, _by_actor: String, correct: bool, first_time: bool) -> void:
	if correct and first_time:
		_guide.notify_event("first_correct_flag")


func _on_diamond_shattered(_cell, _by_actor: String) -> void:
	if not _in_level() or _shatter_toasted:
		return
	_shatter_toasted = true
	_hud.show_toast(COPY_SHATTER, 3.0)
