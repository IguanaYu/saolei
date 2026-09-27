extends Node
class_name Level4Director
## 外部试玩版第四关剧本控制器（docs/active/试玩版内容/第四关-设计文档.md §4/§6）
## 四句文案（设计定稿）：放基地 / 首波前虫害 / 保安推销 / 探测兜底。
## 时序由信号 + elapsed 轮询驱动；三种虫害的效果不用文字解释（图标/停摆自证）。

const COPY_BASE := "选个位置，放下基地。"
const COPY_WORM := "裂缝里有虫。"
const COPY_GUARD := "雇个保安？"
const COPY_PROBE := "卡住了？探测，三格见雷。"
const LEVEL_ID := "ch01_s04"
const WORM_HINT_SEC := 20.0        # 首波（35s）前提早提示（elapsed 从放基地起算）
const GUARD_DELAY_SEC := 10.0      # 首虫出场后再等 10s
const STALL_AFTER_WARN_SEC := 2.0  # 停摆警告（3s 阈值）后再计 2s ≈ 5s 口径

var _guide: Control
var _hud: Control
var _grid: Node2D
var _enemy_manager: EnemyManager
var _robot_manager: Node2D

var _worm_shown := false
var _guard_shown := false
var _probe_shown := false
var _first_enemy_time := -1.0
var _idle_warn_time := -1.0
var _breath_tween: Tween = null
var _tweens: Array = []


func _ready() -> void:
	var main := get_parent()
	_guide = main.get_node("UILayer/TutorialGuide")
	_hud = main.get_node("UILayer/HUD")
	_grid = main.get_node("Grid")
	_enemy_manager = main.get_node("EnemyManager")
	_robot_manager = main.get_node("RobotManager")
	GameState.base_placed.connect(_on_base_placed)
	_enemy_manager.nest_damaged.connect(func(_n): _try_show_worm_hint())
	_enemy_manager.enemy_spawned.connect(_on_enemy_spawned)
	_robot_manager.idle_warning_changed.connect(_on_idle_warning)


## 进关后启动：0.5s 聚光盘面 + 气泡（等待放基地），已开区呼吸高亮
func begin() -> void:
	_worm_shown = false
	_guard_shown = false
	_probe_shown = false
	_first_enemy_time = -1.0
	_idle_warn_time = -1.0
	for tw in _tweens:
		tw.kill()
	_tweens.clear()
	_start_breath_highlight()
	var board_size := Vector2(_grid.rows * _grid.cell_size, _grid.cols * _grid.cell_size)
	var tw := create_tween()
	_tweens.append(tw)
	tw.tween_interval(0.5)
	tw.tween_callback(func() -> void:
		if _in_level():
			_guide.begin([
				{"node": _grid, "size": board_size,
					"text": COPY_BASE, "event": "base_placed", "tip": "right"},
			]))


func _process(_delta: float) -> void:
	if not _in_level():
		return
	var elapsed: float = GameState.elapsed
	# #2 首波前：elapsed ≥ 20s（巢被点第一下的信号路径在 _try_show_worm_hint）
	if not _worm_shown and elapsed >= WORM_HINT_SEC:
		_show_worm_hint()
	# #3 保安推销：首虫出场后 10s 或钱 ≥80（先到），未买过保安才出现
	if not _guard_shown and GameState.guard_count == 0 \
			and ((_first_enemy_time >= 0.0 and elapsed - _first_enemy_time >= GUARD_DELAY_SEC)
				or GameState.money >= 80):
		_guard_shown = true
		_hud.show_toast(COPY_GUARD, 3.0)
	# #4 探测兜底：首次停摆 ≥5s（警告后再计 2s）且未买过探测
	if not _probe_shown and int(GameState.result_stats.get("probe_used", 0)) == 0 \
			and _idle_warn_time >= 0.0 and elapsed - _idle_warn_time >= STALL_AFTER_WARN_SEC:
		_probe_shown = true
		_hud.show_toast(COPY_PROBE, 3.0)


## 本关内（placing_base 引导阶段也算——进关即生效）
func _in_level() -> bool:
	return GameState.current_level_id == LEVEL_ID \
			and (GameState.game_active or GameState.game_phase == "placing_base")


func _on_base_placed(_coord: Vector2i) -> void:
	if not _in_level():
		return
	_stop_breath_highlight()


func _on_enemy_spawned(_e) -> void:
	if _first_enemy_time < 0.0:
		_first_enemy_time = GameState.elapsed


func _on_idle_warning(show: bool) -> void:
	if show and _idle_warn_time < 0.0:
		_idle_warn_time = GameState.elapsed


func _try_show_worm_hint() -> void:
	if not _worm_shown and _in_level() and GameState.game_active:
		_show_worm_hint()


func _show_worm_hint() -> void:
	_worm_shown = true
	_hud.show_toast(COPY_WORM, 3.0)


## 放基地阶段：已开区呼吸高亮（剧本 #0「已开区高亮，两处裂缝同时可见」）
func _start_breath_highlight() -> void:
	_stop_breath_highlight()
	var cells: Array = []
	for coord in _grid.cells:
		var c = _grid.cells[coord]
		if c.is_opened:
			cells.append(c)
	if cells.is_empty():
		return
	_breath_tween = create_tween().set_loops()
	_breath_tween.tween_method(
		func(v: float) -> void:
			for c in cells:
				if is_instance_valid(c):
					c.modulate = Color(1.0 + v * 0.25, 1.0 + v * 0.25, 1.0 + v * 0.15, 1.0),
		0.0, 1.0, 0.7).set_ease(Tween.EASE_IN_OUT)
	_breath_tween.tween_method(
		func(v: float) -> void:
			for c in cells:
				if is_instance_valid(c):
					c.modulate = Color(1.0 + v * 0.25, 1.0 + v * 0.25, 1.0 + v * 0.15, 1.0),
		1.0, 0.0, 0.7).set_ease(Tween.EASE_IN_OUT)


func _stop_breath_highlight() -> void:
	if _breath_tween != null:
		_breath_tween.kill()
		_breath_tween = null
		for coord in _grid.cells:
			_grid.cells[coord].modulate = Color.WHITE
