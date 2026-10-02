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
	super()  # 皮肤逻辑在基类（按 robot_type 取帧）


func do_tick(grid, locked: Dictionary) -> void:
	match miner_state:
		"to_mine":
			_tick_to_mine(grid, locked)
		"mining":
			_tick_mining(grid)
		"to_base":
			_tick_to_base(grid, locked)
		"unloading":
			_tick_unloading(grid)


func _tick_to_mine(grid, locked: Dictionary) -> void:
	# 如果当前矿脉无效，找新矿脉
	if _current_vein_coord == null:
		var success := _find_new_vein(grid, locked)
		if not success:
			_state = "idle"
			return

	# 检查矿脉是否还有资源（无效则释放占用，重新找脉）
	var v = grid.get_cell(_current_vein_coord)
	if v == null or v.vein_resources <= 0 or not v.is_vein:
		locked.erase(_current_vein_coord)
		_current_vein_coord = null
		_state = "idle"
		return

	# 矿工路径寻路不吃目标锁（脉已被自己占用）
	var reached: bool = _move_step(grid, [_current_vein_coord], {})
	if reached:
		miner_state = "mining"
		_state = "working"
		_play_action_pulse()


func _tick_mining(grid) -> void:
	var v = grid.get_cell(_current_vein_coord)
	if v == null or v.vein_resources <= 0 or not v.is_vein:
		# 矿脉耗尽（释放占用，其他矿工可改挑这条脉的路过位）
		if v != null and v.is_vein:
			v.deplete_vein()
			grid.vein_depleted.emit(v.coord)
		GameState.locked_targets.erase(_current_vein_coord)
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


func _tick_to_base(grid, locked: Dictionary) -> void:
	if GameState.bases.is_empty():
		_state = "idle"
		return

	var nearest = GameState.get_nearest_base(coord)
	if nearest == null:
		_state = "idle"
		return

	var reached: bool = _move_step(grid, [nearest], {})
	if reached:
		miner_state = "unloading"
		_state = "working"
		_play_action_pulse()


func _tick_unloading(grid) -> void:
	AudioManager.play_sfx("coin")
	grid.cargo_unloaded.emit(global_position, cargo)  # 确认动效（金光/跳字/飞币）
	GameState.add_money(cargo)
	GameState.add_score(cargo, "mine")  # 采矿分明细键（mine_score）由得分账本写入
	cargo = 0
	miner_state = "to_mine"
	_state = "working"
	_play_action_pulse()


## 一脉一工（2026-10-02 防抱团）：优先挑没有其他矿工占用的脉，占用跨往返保留
## （采矿→回基地→返回同一条脉）；脉全被占时回退共享最近脉，采完自然散开
func _find_new_vein(grid, locked: Dictionary) -> bool:
	var veins: Array = grid.get_all_veins()
	if veins.is_empty():
		return false
	var free: Array = []
	for v in veins:
		var holder: Variant = locked.get(v, null)
		if holder == null or holder == self:
			free.append(v)
	var pool: Array = free if not free.is_empty() else veins
	# 找最近的矿脉
	var nearest = pool[0]
	var best_dist: int = abs(coord.x - nearest.x) + abs(coord.y - nearest.y)
	for v in pool:
		var d: int = abs(coord.x - v.x) + abs(coord.y - v.y)
		if d < best_dist:
			best_dist = d
			nearest = v
	_current_vein_coord = nearest
	locked[nearest] = self
	return true


func is_idle() -> bool:
	return _current_vein_coord == null and miner_state == "to_mine"