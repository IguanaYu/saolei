extends Robot
## 矿工机器人（橙色 ⛏）：四态状态机驱动
##
## 状态机：
##   to_mine  → 找矿脉，走过去
##   mining   → 到达矿脉，每 tick 采 5 资源
##   to_base  → 货满 20，回最近基地
##   unloading → 到达基地，卸货换钱+分

const CARGO_CAPACITY: int = 20
const MINE_PER_TICK: int = 5

var cargo: int = 0
var miner_state: String = "to_mine"  # to_mine | mining | to_base | unloading
var _current_vein_coord: Variant = null


func _ready() -> void:
	super()
	robot_type = "miner"
	_update_visual()


func _update_visual() -> void:
	var body: ColorRect = $Body
	var lbl: Label = $IconLabel
	body.color = Color(0.95, 0.55, 0.05)
	lbl.text = "⛏"
	lbl.modulate = Color.WHITE


func do_tick(grid, locked: Dictionary, robot_positions: Dictionary) -> void:
	match miner_state:
		"to_mine":
			_tick_to_mine(grid, locked, robot_positions)
		"mining":
			_tick_mining(grid)
		"to_base":
			_tick_to_base(grid, locked, robot_positions)
		"unloading":
			_tick_unloading()


func _tick_to_mine(grid, locked: Dictionary, robot_positions: Dictionary) -> void:
	# 如果当前矿脉无效，找新矿脉
	if _current_vein_coord == null:
		var success := _find_new_vein(grid)
		if not success:
			_state = "idle"
			return

	# 检查矿脉是否还有资源
	var v = grid.get_cell(_current_vein_coord)
	if v == null or v.vein_resources <= 0 or not v.is_vein:
		_current_vein_coord = null
		_state = "idle"
		return

	# 矿工不用 locked_targets，传空字典
	var reached: bool = _move_step(grid, [_current_vein_coord], {}, robot_positions)
	if reached:
		miner_state = "mining"
		_state = "working"
		_play_action_pulse()


func _tick_mining(grid) -> void:
	var v = grid.get_cell(_current_vein_coord)
	if v == null or v.vein_resources <= 0 or not v.is_vein:
		# 矿脉耗尽
		if v != null and v.is_vein:
			v.deplete_vein()
			grid.vein_depleted.emit(v.coord)
		_current_vein_coord = null
		miner_state = "to_mine"
		_state = "idle"
		return

	cargo += MINE_PER_TICK
	v.vein_resources -= MINE_PER_TICK
	_play_action_pulse()

	if cargo >= CARGO_CAPACITY:
		miner_state = "to_base"
		_state = "working"


func _tick_to_base(grid, locked: Dictionary, robot_positions: Dictionary) -> void:
	if GameState.bases.is_empty():
		_state = "idle"
		return

	var nearest = GameState.get_nearest_base(coord)
	if nearest == null:
		_state = "idle"
		return

	var reached: bool = _move_step(grid, [nearest], {}, robot_positions)
	if reached:
		miner_state = "unloading"
		_state = "working"
		_play_action_pulse()


func _tick_unloading() -> void:
	GameState.add_money(cargo)
	GameState.add_score(cargo)
	cargo = 0
	miner_state = "to_mine"
	_state = "working"
	_play_action_pulse()


func _find_new_vein(grid) -> bool:
	var veins: Array = grid.get_all_veins()
	if veins.is_empty():
		return false
	# 找最近的矿脉
	var nearest = veins[0]
	var best_dist: int = abs(coord.x - nearest.x) + abs(coord.y - nearest.y)
	for v in veins:
		var d: int = abs(coord.x - v.x) + abs(coord.y - v.y)
		if d < best_dist:
			best_dist = d
			nearest = v
	_current_vein_coord = nearest
	return true


func is_idle() -> bool:
	return _current_vein_coord == null and miner_state == "to_mine"