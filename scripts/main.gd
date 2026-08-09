extends Node
## 主场景控制器：负责游戏主循环、玩家输入路由、模块协调、关卡流程

@onready var grid: Grid = $Grid
@onready var robot_manager: RobotManager = $RobotManager
@onready var hud = $UILayer/HUD
@onready var shop = $UILayer/Shop
@onready var main_menu = $UILayer/MainMenu
@onready var chapter_select = $UILayer/ChapterSelect
@onready var level_select = $UILayer/LevelSelect
@onready var results_panel = $UILayer/ResultsPanel

# 当前放置模式（商店点击购买/建造后置为 "opener"/"marker"/"base"/...）
var placing_mode: String = ""

# 当前所在章节（"返回关卡选择"时用）
var _current_chapter_id: String = "ch01"
# FLAG_N_MINES 目标计数
var _flag_count: int = 0


func _ready() -> void:
	# 不立即 reset，等玩家选关进入
	grid.all_safe_opened.connect(_on_all_safe_opened)
	grid.cell_opened.connect(_on_cell_opened)
	grid.cell_flagged.connect(_on_cell_flagged)
	grid.mine_stepped.connect(_on_mine_stepped)
	robot_manager.idle_warning_changed.connect(_on_idle_warning_changed)
	robot_manager.robot_removed.connect(_on_robot_removed)
	main_menu.start_requested.connect(_on_start_adventure)
	chapter_select.chapter_selected.connect(_on_chapter_selected)
	chapter_select.back_requested.connect(_on_chapter_select_back)
	level_select.start_requested.connect(_on_start_game)
	level_select.back_requested.connect(_on_level_select_back)
	results_panel.restart_requested.connect(_on_restart_requested)
	results_panel.back_to_level_select_requested.connect(_on_back_to_level_select)
	GameState.score_changed.connect(_on_score_changed)
	GameState.time_changed.connect(_on_time_changed)


# ---- 关卡流程 ----

func _on_start_adventure() -> void:
	main_menu.hide()
	chapter_select.show()
	chapter_select.refresh()


func _on_chapter_selected(ch_id: String) -> void:
	_current_chapter_id = ch_id
	level_select.set_chapter(ch_id)
	chapter_select.hide()
	level_select.show()


func _on_chapter_select_back() -> void:
	chapter_select.hide()
	main_menu.show()


func _on_level_select_back() -> void:
	level_select.hide()
	chapter_select.show()
	chapter_select.refresh()


func _on_start_game(level_id: String) -> void:
	_start_level(level_id)


func _on_restart_requested() -> void:
	_start_level(GameState.current_level_id)


func _on_back_to_level_select() -> void:
	results_panel.hide()
	level_select.set_chapter(_current_chapter_id)
	level_select.show()


func _start_level(level_id: String) -> void:
	main_menu.hide()
	chapter_select.hide()
	level_select.hide()
	results_panel.hide()
	GameState.reset_state(level_id)
	_flag_count = 0
	var lvl: LevelData = LevelSystem.get_level(level_id) if level_id != "" else null
	if lvl != null:
		grid.configure(lvl.grid_size.x, lvl.grid_size.y, lvl.mine_count)
	robot_manager.remove_all()
	_update_objective_progress()


func _on_idle_warning_changed(show: bool) -> void:
	hud.set_idle_warning(show)


func _on_robot_removed(_robot, reason: String) -> void:
	if reason == "detect_failed":
		hud.show_toast("检测失败！机器人自爆了", 3.0)


func _process(delta: float) -> void:
	if not GameState.game_active:
		return
	GameState.time_left -= delta
	GameState.time_changed.emit(GameState.time_left)
	if GameState.time_left <= 0:
		var obj := GameState.current_objective
		if obj != null and obj.type == ObjectiveData.Type.SURVIVE_TIME:
			_end_game("win")  # 生存目标：熬到时间到即胜利
		else:
			_end_game("timeout")
		return
	robot_manager.tick_all(delta, grid)


# ---- 初始基地放置阶段 ----

# 在 placing_base 阶段拦截所有点击，避免传到 Cell 触发开/标
func _input(event: InputEvent) -> void:
	# 任一菜单覆盖层显示时不处理游戏输入
	if main_menu.visible or chapter_select.visible or level_select.visible:
		return
	# 数字键 1-4 快捷放置机器人
	if event is InputEventKey and event.pressed and not event.echo:
		if _try_robot_shortcut(event.keycode):
			get_viewport().set_input_as_handled()
			return
	if GameState.game_phase == "placing_base":
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			_try_place_first_base_at(event.position)
			get_viewport().set_input_as_handled()
		return
	if placing_mode == "":
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_try_place_at(event.position)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_exit_placing_mode()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_exit_placing_mode()
		get_viewport().set_input_as_handled()


## 数字键 1-4 快捷放置机器人；返回 true 表示按键已处理
func _try_robot_shortcut(keycode: Key) -> bool:
	if GameState.game_phase == "placing_base":
		return false  # 先放第一个基地
	var type := ""
	match keycode:
		KEY_1: type = "opener"
		KEY_2: type = "marker"
		KEY_3: type = "detector"
		KEY_4: type = "miner"
	if type == "":
		return false
	var reason: String = shop.lock_reason(type)
	if reason != "":
		hud.show_toast(reason, 2.0)
		return true
	if GameState.money < GameState.get_robot_price(type):
		hud.show_toast("金币不足", 2.0)
		return true
	return shop.try_buy(type)


func _try_place_first_base_at(world_pos: Vector2) -> bool:
	var coord := grid.world_to_coord(world_pos)
	if not _in_bounds(coord):
		return false
	if not grid.place_first_base(coord):
		return false
	# 基地放完，激活游戏开始倒计时
	GameState.game_active = true
	return true


# ---- 放置模式（商店购买后）----

func _enter_placing_mode(mode: String) -> void:
	# mode: "opener"/"marker"/"detector"/"miner"/"base"/"charge_tower"/...
	# 价格检查留给实际放置时做（基地价格递增、机器人价格递增）
	if mode in ["opener", "marker", "detector", "miner"] and GameState.money < GameState.get_robot_price(mode):
		return
	if mode == "base" and GameState.money < GameState.get_base_price():
		return
	placing_mode = mode
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	shop.set_placing_hint(true)


func _exit_placing_mode() -> void:
	placing_mode = ""
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	shop.set_placing_hint(false)


func _try_place_at(world_pos: Vector2) -> bool:
	var coord := grid.world_to_coord(world_pos)
	if not _in_bounds(coord):
		return false

	if placing_mode == "base":
		# 后续基地：必须在已开格上、不是基地
		var cell = grid.get_cell(coord)
		if cell == null or not cell.is_opened or cell.is_base or cell.is_collapsed:
			return false
		var price: int = GameState.get_base_price()
		if GameState.money < price:
			return false
		_exit_placing_mode()
		GameState.add_money(-price)
		grid.place_base(coord)
		return true

	# 机器人放置（opener / marker / detector / miner）
	if not grid.is_walkable(coord):
		return false
	if robot_manager.get_robot_positions().has(coord):
		return false  # 一格一机

	var type := placing_mode
	_exit_placing_mode()

	if not GameState.purchase_robot(type):
		return false

	robot_manager.spawn_robot(coord, type, grid)
	return true


func _in_bounds(coord: Vector2i) -> bool:
	return coord.x >= 0 and coord.x < grid.rows and coord.y >= 0 and coord.y < grid.cols


# ---- 奖励逻辑（玩家和机器人走同一条通道）----

func _on_cell_opened(_cell, by_actor: String) -> void:
	if by_actor == "drone":
		return  # 无人机开的格子不给奖励
	GameState.add_money(1)
	GameState.add_score(1)


func _on_cell_flagged(_cell, _by_actor: String, correct: bool) -> void:
	if correct:
		GameState.add_money(5)
		GameState.add_score(5)
		var obj := GameState.current_objective
		if obj != null and obj.type == ObjectiveData.Type.FLAG_N_MINES:
			_flag_count += 1
			_update_objective_progress()
			if _flag_count >= obj.target_value:
				_end_game("win")
	else:
		GameState.add_score(-3)


func _on_mine_stepped(_cell, _by_actor: String) -> void:
	GameState.lose_life()
	if GameState.lives <= 0:
		_end_game("lose")


func _on_all_safe_opened() -> void:
	# 清空全部安全格即胜利（目标为 CLEAR_ALL_SAFE 或自由模式）
	var obj := GameState.current_objective
	if obj == null or obj.type == ObjectiveData.Type.CLEAR_ALL_SAFE:
		_end_game("win")


func _end_game(result: String) -> void:
	if not GameState.game_active:
		return
	GameState.game_active = false
	GameState.game_over.emit(result)


# ---- 目标进度 ----

func _on_score_changed(_v: int) -> void:
	_update_objective_progress()
	var obj := GameState.current_objective
	if obj != null and obj.type == ObjectiveData.Type.REACH_SCORE and GameState.score >= obj.target_value:
		_end_game("win")


func _on_time_changed(_v: float) -> void:
	_update_objective_progress()


func _update_objective_progress() -> void:
	var obj := GameState.current_objective
	if obj == null:
		GameState.objective_progress_updated.emit("")
		return
	var current: int = 0
	match obj.type:
		ObjectiveData.Type.CLEAR_ALL_SAFE:
			current = grid.count_safe_remaining()
		ObjectiveData.Type.REACH_SCORE:
			current = GameState.score
		ObjectiveData.Type.FLAG_N_MINES:
			current = _flag_count
		ObjectiveData.Type.SURVIVE_TIME:
			current = int(ceil(GameState.time_left))
		ObjectiveData.Type.ACTIVATE_N_TOWER:
			current = 0
	GameState.objective_progress_updated.emit(obj.build_progress_text(current))


## 无人机技能：打开 3 个最远关闭格
func _trigger_drone() -> void:
	if GameState.money < 100:
		return
	GameState.add_money(-100)
	var base_coord: Vector2i = GameState.bases[0] if not GameState.bases.is_empty() else Vector2i(8, 8)
	var coords: Array = grid.get_farthest_closed_cells(3, base_coord)
	for coord in coords:
		grid.open_cell(coord, "drone")
