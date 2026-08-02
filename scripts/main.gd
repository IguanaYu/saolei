extends Node
## 主场景控制器：负责游戏主循环、玩家输入路由、模块协调

@onready var grid: Grid = $Grid
@onready var robot_manager: RobotManager = $RobotManager
@onready var hud = $UILayer/HUD
@onready var shop = $UILayer/Shop

# 放置机器人模式（商店点击购买后置为 "opener" / "marker"）
var placing_robot_type: String = ""


func _ready() -> void:
	GameState.reset_state()
	GameState.game_active = true
	grid.all_safe_opened.connect(_on_all_safe_opened)
	grid.cell_opened.connect(_on_cell_opened)
	grid.cell_flagged.connect(_on_cell_flagged)
	grid.mine_stepped.connect(_on_mine_stepped)
	robot_manager.idle_warning_changed.connect(_on_idle_warning_changed)


func _on_idle_warning_changed(show: bool) -> void:
	hud.set_idle_warning(show)


func _process(delta: float) -> void:
	if not GameState.game_active:
		return
	GameState.time_left -= delta
	GameState.time_changed.emit(GameState.time_left)
	if GameState.time_left <= 0:
		_end_game("timeout")
		return
	robot_manager.tick_all(delta, grid)


# ---- 放置模式（商店购买后）----

func _enter_placing_mode(robot_type: String) -> void:
	if GameState.money < GameState.get_robot_price(robot_type):
		return
	placing_robot_type = robot_type
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	shop.set_placing_hint(true)


func _exit_placing_mode() -> void:
	placing_robot_type = ""
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	shop.set_placing_hint(false)


# 放置模式下用 _input 拦截，否则 Cell 会先收到点击
func _input(event: InputEvent) -> void:
	if placing_robot_type == "":
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_try_place_robot_at(event.position)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_exit_placing_mode()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_exit_placing_mode()
		get_viewport().set_input_as_handled()


func _try_place_robot_at(world_pos: Vector2) -> bool:
	var coord := grid.world_to_coord(world_pos)
	if not _in_bounds(coord) or not grid.is_walkable(coord):
		return false
	if robot_manager.get_robot_positions().has(coord):
		return false  # 一格一机

	var type := placing_robot_type
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
