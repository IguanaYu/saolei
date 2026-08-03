extends Node
## 主场景控制器：负责游戏主循环、玩家输入路由、模块协调

@onready var grid: Grid = $Grid
@onready var robot_manager: RobotManager = $RobotManager
@onready var hud = $UILayer/HUD
@onready var shop = $UILayer/Shop

# 当前放置模式（商店点击购买/建造后置为 "opener"/"marker"/"base"/...）
var placing_mode: String = ""


func _ready() -> void:
	GameState.reset_state()
	# game_active 在玩家放完第一个基地后才置为 true
	grid.all_safe_opened.connect(_on_all_safe_opened)
	grid.cell_opened.connect(_on_cell_opened)
	grid.cell_flagged.connect(_on_cell_flagged)
	grid.mine_stepped.connect(_on_mine_stepped)
	robot_manager.idle_warning_changed.connect(_on_idle_warning_changed)
	robot_manager.robot_removed.connect(_on_robot_removed)


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
		_end_game("timeout")
		return
	robot_manager.tick_all(delta, grid)


# ---- 初始基地放置阶段 ----

# 在 placing_base 阶段拦截所有点击，避免传到 Cell 触发开/标
func _input(event: InputEvent) -> void:
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
	# mode: "opener"/"marker"/"detector"/"base"/"charge_tower"/...
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

func _on_cell_opened(_cell, _by_actor: String) -> void:
	GameState.add_money(1)
	GameState.add_score(1)


func _on_cell_flagged(_cell, _by_actor: String, correct: bool) -> void:
	if correct:
		GameState.add_money(5)
		GameState.add_score(5)
	else:
		GameState.add_score(-3)


func _on_mine_stepped(_cell, _by_actor: String) -> void:
	GameState.lose_life()
	if GameState.lives <= 0:
		_end_game("lose")


func _on_all_safe_opened() -> void:
	_end_game("win")


func _end_game(result: String) -> void:
	if not GameState.game_active:
		return
	GameState.game_active = false
	GameState.game_over.emit(result)
