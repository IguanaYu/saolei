extends Node
class_name Level5Director
## 外部试玩版第五关剧本控制器（docs/active/试玩版内容/第五关-设计文档.md §6/§8）
## 六句文案（设计定稿）：开场拔牙题眼 / 史莱姆 / P2 反弹 / P3 收尾 / 探测兜底 / 斩杀大字。
## 时序由信号驱动（Boss 阶段信号/敌害出场/停摆警告）；招式效果不用文字解释（L4 视觉语言自证）。

const COPY_OPEN := "它的牙埋在墙里，拔完它就走。"
const COPY_SLIME := "开路过去，点死它们。"
const COPY_BOMB := "点炸弹，把它弹回去。"
const COPY_P3 := "拆锁，断触手，收尾。"
const COPY_PROBE := "卡住了？探测，三格见雷。"
const COPY_KILL := "最后一颗牙。"
const LEVEL_ID := "ch01_s05"
const STALL_AFTER_WARN_SEC := 2.0  # 停摆警告（3s 阈值）后再计 2s ≈ 5s 口径（同 L4）

var _guide: Control
var _hud: Control
var _grid: Node2D
var _boss_manager: BossManager
var _enemy_manager: EnemyManager
var _robot_manager: Node2D

var _slime_shown := false
var _probe_shown := false
var _idle_warn_time := -1.0


func _ready() -> void:
	var main := get_parent()
	_guide = main.get_node("UILayer/TutorialGuide")
	_hud = main.get_node("UILayer/HUD")
	_grid = main.get_node("BoardRoot/Grid")
	_boss_manager = main.get_node("BoardRoot/BossManager")
	_enemy_manager = main.get_node("BoardRoot/EnemyManager")
	_robot_manager = main.get_node("BoardRoot/RobotManager")
	GameState.base_placed.connect(_on_base_placed)
	_enemy_manager.enemy_spawned.connect(_on_enemy_spawned)
	_robot_manager.idle_warning_changed.connect(_on_idle_warning)
	_boss_manager.phase_changed.connect(_on_phase_changed)


## 进关后启动：0.5s 聚光盘面 + 气泡（等待放基地，Boss 入场演出并行）
func begin() -> void:
	_slime_shown = false
	_probe_shown = false
	_idle_warn_time = -1.0
	var board_size := Vector2(_grid.rows * _grid.cell_size, _grid.cols * _grid.cell_size)
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_callback(func() -> void:
		if _in_level():
			_guide.begin([
				{"node": _grid, "size": board_size,
					"text": COPY_OPEN, "event": "base_placed", "tip": "right"},
			]))


func _process(_delta: float) -> void:
	if not _in_level():
		return
	# #5 探测兜底（复用 L4 口径）：首次停摆 ≥5s 且未买过探测
	if not _probe_shown and int(GameState.result_stats.get("probe_used", 0)) == 0 \
			and _idle_warn_time >= 0.0 \
			and GameState.elapsed - _idle_warn_time >= STALL_AFTER_WARN_SEC:
		_probe_shown = true
		_hud.show_toast(COPY_PROBE, 3.0)


func _in_level() -> bool:
	return GameState.current_level_id == LEVEL_ID \
			and (GameState.game_active or GameState.game_phase == "placing_base")


func _on_base_placed(_coord: Vector2i) -> void:
	pass  # 气泡事件由 TutorialGuide 自行结束


func _on_enemy_spawned(e) -> void:
	# #2 首只史莱姆出场
	if not _slime_shown and _in_level() and e.enemy_type == "slime":
		_slime_shown = true
		_hud.show_toast(COPY_SLIME, 3.0)


func _on_phase_changed(phase: int) -> void:
	if not _in_level():
		return
	# #3 P2 转场完成 / #4 P3 转场完成（转场演出+出招暂停后）
	match phase:
		2:
			_hud.show_toast(COPY_BOMB, 3.0)
		3:
			_hud.show_toast(COPY_P3, 3.0)


func _on_idle_warning(show: bool) -> void:
	if show and _idle_warn_time < 0.0:
		_idle_warn_time = GameState.elapsed
