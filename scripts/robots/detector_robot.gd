extends Robot
## 检测型机器人（紫色 🔍）：找旗子→移动→3 秒检测→成功变矿脉/失败自爆
##
## 移动阶段复用基类 tick 机制，到达旗子邻接格后进入检测阶段
## 检测阶段由 _process(delta) 计时，满 3 秒后判定

enum DetectorState { IDLE, MOVING, DETECTING }

var _detector_state: int = DetectorState.IDLE
var _detecting_timer: float = 0.0
var _detecting_target: Variant = null  # 正在检测的旗子坐标
var _grid_ref = null  # 保存 grid 引用供 _process 使用


func _ready() -> void:
	super()
	robot_type = "detector"
	_update_visual()


func _update_visual() -> void:
	var body: ColorRect = $Body
	var lbl: Label = $IconLabel
	body.color = Color(0.6, 0.2, 0.8)
	lbl.text = "🔍"
	lbl.modulate = Color.WHITE


func _process(delta: float) -> void:
	if _detector_state != DetectorState.DETECTING:
		return
	_detecting_timer += delta
	if _detecting_timer >= GameState.get_speed_interval("detector"):
		_resolve_detection()


func do_tick(grid, locked: Dictionary, robot_positions: Dictionary) -> void:
	# 检测阶段不处理 tick（由 _process 管理）
	if _detector_state == DetectorState.DETECTING:
		return

	_grid_ref = grid
	_detector_state = DetectorState.MOVING

	# 清理失效目标（旗子被取消 / 已变矿脉 / 已被其他检测器锁定）
	if _current_target != null:
		var c = grid.get_cell(_current_target)
		if c == null or not c.is_flagged or c.is_vein:
			locked.erase(_current_target)
			_current_target = null

	# 无目标时扫描旗子
	if _current_target == null:
		var flagged: Array = grid.get_all_flagged_cells()
		var available: Array = []
		for f in flagged:
			if not locked.has(f) or locked.get(f) == self:
				available.append(f)
		if available.is_empty():
			_state = "idle"
			_detector_state = DetectorState.IDLE
			return
		var found := Pathfinding.find_nearest_target(
			grid, coord, available, locked, robot_positions, self)
		if found.is_empty():
			_state = "idle"
			_detector_state = DetectorState.IDLE
			return
		_current_target = found.target
		locked[_current_target] = self

	# 寻路到目标
	var path_result := Pathfinding.find_nearest_target(
		grid, coord, [_current_target], locked, robot_positions, self)
	if path_result.is_empty():
		_state = "idle"
		_detector_state = DetectorState.IDLE
		return

	if path_result.work_pos == coord:
		# 已邻接旗子 → 进入检测阶段
		_detector_state = DetectorState.DETECTING
		_detecting_target = _current_target
		_detecting_timer = 0.0
		_state = "working"
		_play_action_pulse()
	else:
		# 走一格
		var next: Vector2i = path_result.path[0]
		_move_to(next, grid)
		coord = next
		_state = "moving"


func _resolve_detection() -> void:
	var grid = _grid_ref
	if grid == null:
		return

	var cell = grid.get_cell(_detecting_target)
	if cell == null or not cell.is_flagged:
		# 旗子被取消了，没事
		_detector_state = DetectorState.IDLE
		_detecting_target = null
		_current_target = null
		_state = "idle"
		return

	if cell.is_mine:
		# 正确！旗子变矿脉
		GameState.add_score(10)
		cell.become_vein(100)
		var locked: Dictionary = GameState.locked_targets
		locked.erase(_detecting_target)
		grid.vein_created.emit(cell.coord)
		action_performed.emit(self, "detect_vein", cell.coord)
		_detector_state = DetectorState.IDLE
		_detecting_target = null
		_current_target = null
		_state = "idle"
	else:
		# 错误！自爆
		var locked: Dictionary = GameState.locked_targets
		locked.erase(_detecting_target)
		# 通过 RobotManager 移除自己
		var main = get_node("/root/Main")
		if main and main.robot_manager:
			main.robot_manager.remove_robot(self, "detect_failed")