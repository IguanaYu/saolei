extends Node
class_name Ch02S5Director
## 第二章 2-5「引光与节制」剧本控制器（设计 §6 关内流程，实施计划 WP6）
## 开局聚光（定向自解释）→ 首增幅「损耗一格耐久」→ 首恢复「停火恢复」→
## 剩 2 轻提示（柱变色自解释，不占聚光）→ 破碎（若发生）「损失 50 分」。
## 柱信号每次 begin() 重连（重开重铸柱实体，旧连接随信号源销毁自动清理）。

const COPY_INTRO := "折光后的激光，会朝向引光柱。"
const COPY_HIT := "每次命中，损耗一格耐久。"
const COPY_RECOVER := "停火后，引光柱会缓慢恢复。"
const COPY_LOW := "引光柱快碎了，再打会 -50 分。"
const COPY_BROKEN := "引光柱破碎，损失 50 分。"

var _guide: Control
var _grid: Node2D
var _hud: Control
var _hit_toasted := false
var _recover_toasted := false
var _low_toasted := false
var _broken_toasted := false


func _ready() -> void:
	var main := get_parent()
	_guide = main.get_node("UILayer/TutorialGuide")
	_grid = main.get_node("BoardRoot/Grid")
	_hud = main.get_node("UILayer/HUD")


func begin() -> void:
	_hit_toasted = false
	_recover_toasted = false
	_low_toasted = false
	_broken_toasted = false
	var main := get_parent()
	var lm = main.laser_manager
	if lm != null and not lm.refractor_activated.is_connected(_on_first_amp):
		lm.refractor_activated.connect(_on_first_amp)
	if lm != null and not lm.pillar_broken.is_connected(_on_pillar_broken):
		lm.pillar_broken.connect(_on_pillar_broken)
	var fm = main.facility_manager
	if fm != null and fm.pillar != null:
		if not fm.pillar.pillar_recovered.is_connected(_on_first_recover):
			fm.pillar.pillar_recovered.connect(_on_first_recover)
		if not fm.pillar.pillar_low_warning.is_connected(_on_low_warning):
			fm.pillar.pillar_low_warning.connect(_on_low_warning)
	var board_size := Vector2(_grid.cols * _grid.cell_size, _grid.rows * _grid.cell_size)
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_callback(func() -> void:
		_guide.begin([
			{"node": _grid, "size": board_size,
				"text": COPY_INTRO, "event": "refractor_activated", "tip": "right"},
		]))


func _on_first_amp(_r) -> void:
	if _hit_toasted or not GameState.game_active or GameState.current_level_id != "ch02_s05":
		return
	_hit_toasted = true
	_hud.show_toast(COPY_HIT, 3.0)


func _on_first_recover(_p) -> void:
	if _recover_toasted or not GameState.game_active or GameState.current_level_id != "ch02_s05":
		return
	_recover_toasted = true
	_hud.show_toast(COPY_RECOVER, 3.0)


func _on_low_warning(_p) -> void:
	if _low_toasted or not GameState.game_active or GameState.current_level_id != "ch02_s05":
		return
	_low_toasted = true
	_hud.show_toast(COPY_LOW, 3.0)


func _on_pillar_broken() -> void:
	if _broken_toasted or GameState.current_level_id != "ch02_s05":
		return
	_broken_toasted = true
	_hud.show_toast(COPY_BROKEN, 4.0)
