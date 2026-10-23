class_name DiamondExplorerManager
extends Node2D
## 钻石召唤的临时飞行单位。只消费公开推理结果，不参与机器人购买/升级/数量。
## 所有作业都在同步 tick 中完成；飞行表现不持有能在下一局触发的回调。

const DEFAULT_ACTIONS := 3
const DEFAULT_INTERVAL := 1.5
const DEFAULT_LIFETIME := 20.0
const DEFAULT_MAX_ACTIVE := 8

signal explorer_summoned(explorer)
signal explorer_worked(explorer, coord: Vector2i)
signal explorer_removed(explorer, reason: String)

class ExplorerActor extends Node2D:
	var robot_type := "diamond_explorer"  # 共享目标锁读取的单位类别；不会加入 robots 数组。
	var actor_id := 0
	var generation := 0
	var coord := Vector2i.ZERO
	var flight_from := Vector2i.ZERO
	var target: Variant = null
	var actions_left := DEFAULT_ACTIONS
	var interval := DEFAULT_INTERVAL
	var lifetime := DEFAULT_LIFETIME
	var age := 0.0
	var elapsed := 0.0
	var state := "waiting"
	var visual_phase := 0.0
	var work_flash := 0.0

	func _draw() -> void:
		# 翅膀、菱形核心与剩余次数点；在 28px 格距下仍可区分机器人和钻石。
		var bob := Vector2(0.0, -7.0 + sin(visual_phase * 4.0) * 1.5)
		var flap := 2.0 + sin(visual_phase * 15.0) * 2.0
		draw_circle(Vector2(0, 3), 5.0, Color(0.05, 0.10, 0.15, 0.18))
		draw_colored_polygon(PackedVector2Array([
			bob + Vector2(-2, 0), bob + Vector2(-11, -flap - 2),
			bob + Vector2(-9, 4), bob + Vector2(-3, 3)]), Color(0.68, 1.0, 0.91, 0.8))
		draw_colored_polygon(PackedVector2Array([
			bob + Vector2(2, 0), bob + Vector2(11, -flap - 2),
			bob + Vector2(9, 4), bob + Vector2(3, 3)]), Color(0.68, 1.0, 0.91, 0.8))
		draw_circle(bob, 6.0 + work_flash * 4.0, Color(0.3, 1.0, 0.74, 0.14 + work_flash * 0.2))
		draw_colored_polygon(PackedVector2Array([
			bob + Vector2(0, -5), bob + Vector2(4, 0),
			bob + Vector2(0, 6), bob + Vector2(-4, 0)]), Color(0.17, 0.9, 0.58))
		draw_line(bob + Vector2(0, -4), bob + Vector2(0, 3), Color(0.94, 1.0, 0.8), 2.0)
		for i in mini(actions_left, 8):
			draw_circle(Vector2((float(i) - float(mini(actions_left, 8) - 1) * 0.5) * 3.0, 7),
				1.0, Color(0.8, 1.0, 0.74))


var actors: Array = []  # ExplorerActor；可查询 coord/target/actions_left/age/state。
var pending_summons: Array = []  # 满员只排队，本局的独立钻石召唤不会因为并存上限丢失。
var max_active := DEFAULT_MAX_ACTIVE
var _grid = null
var _generation := 0
var _next_actor_id := 0
var _reservations: Dictionary = {}
var _level_id := ""
var _board_anchor: WeakRef = null
var _board_anchor_coord := Vector2i.ZERO


func setup(grid) -> void:
	remove_all()
	_grid = grid
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if not GameState.game_over.is_connected(_on_game_over):
		GameState.game_over.connect(_on_game_over)


func reset_for_level() -> void:
	remove_all()
	max_active = DEFAULT_MAX_ACTIVE
	_level_id = GameState.current_level_id


func remove_all() -> void:
	_generation += 1
	pending_summons.clear()
	for actor in actors.duplicate():
		_remove_actor(actor, "reset")
	actors.clear()
	_reservations.clear()
	_board_anchor = null


func _exit_tree() -> void:
	remove_all()


func _on_game_over(_result: String) -> void:
	remove_all()


func summon(coord: Vector2i, params: Dictionary = {}) -> ExplorerActor:
	if not is_instance_valid(_grid) or not GameState.game_active or _grid.get_cell(coord) == null:
		return null
	if (not actors.is_empty() or not pending_summons.is_empty()) and not _board_matches():
		remove_all()
	if actors.is_empty() and pending_summons.is_empty():
		_level_id = GameState.current_level_id
		_board_anchor_coord = coord
		_board_anchor = weakref(_grid.get_cell(coord))
	_drain_pending()
	var limit := clampi(int(params.get("max_active", max_active)), 1, 32)
	if actors.size() >= limit or not pending_summons.is_empty():
		# 每颗钻石每局最多提交一次，合法队列不可能超过棋盘格数。
		if pending_summons.size() >= _grid.cells.size():
			push_error("DiamondExplorerManager: 召唤队列超过棋盘格数，请检查重复提交")
			return null
		pending_summons.append({"coord":coord, "params":params.duplicate(true),
			"generation":_generation})
		return null
	return _spawn_actor(coord, params)


func _spawn_actor(coord: Vector2i, params: Dictionary) -> ExplorerActor:
	var actor := ExplorerActor.new()
	_next_actor_id += 1
	actor.actor_id = _next_actor_id
	actor.name = "DiamondExplorer_%d" % actor.actor_id
	actor.generation = _generation
	actor.coord = coord
	actor.flight_from = coord
	actor.actions_left = clampi(int(params.get("actions", DEFAULT_ACTIONS)), 1, 32)
	actor.interval = clampf(float(params.get("interval", DEFAULT_INTERVAL)), 0.1, 30.0)
	actor.lifetime = clampf(float(params.get("lifetime", DEFAULT_LIFETIME)), 0.1, 300.0)
	actor.visual_phase = float(actor.actor_id) * 1.7
	actor.z_index = 12
	add_child(actor)
	actors.append(actor)
	_stat("diamond_explorers_summoned", 1)
	_assign_target(actor)
	_reproject(actor)
	explorer_summoned.emit(actor)
	return actor


func _process(delta: float) -> void:
	tick_all(delta)


## 测试可直接推进这个同步入口；实际游戏由 _process 调用，主场景无需再 tick。
func tick_all(delta: float) -> void:
	if actors.is_empty() and pending_summons.is_empty():
		return
	if not GameState.game_active or not _board_matches():
		remove_all()
		return
	if is_inside_tree() and get_tree().paused:
		return
	var guide := get_node_or_null("/root/Main/UILayer/TutorialGuide") as CanvasItem
	if guide != null and guide.visible:
		return
	_drain_pending()
	var step := maxf(delta, 0.0)
	var current_generation := _generation
	for actor in actors.duplicate():
		if _generation != current_generation or not GameState.game_active:
			break
		if not is_instance_valid(actor) or actor.generation != _generation:
			continue
		actor.age += step
		if actor.age >= actor.lifetime:
			_stat("diamond_explorers_expired", 1)
			_remove_actor(actor, "expired")
			continue
		actor.visual_phase += step
		actor.work_flash = maxf(0.0, actor.work_flash - step * 3.0)
		if actor.target != null and not _target_available(actor.target, actor):
			_release_target(actor)
			actor.elapsed = 0.0
			actor.state = "waiting"
		if actor.target == null:
			_assign_target(actor)
		if actor.target == null:
			_stat("diamond_explorer_wait_seconds", step)
			_reproject(actor)
			continue
		actor.elapsed += step
		# 单帧最多做一次，卡顿不会越过目标检验连续开格。
		if actor.elapsed >= actor.interval:
			_perform_work(actor)
		if _generation == current_generation and is_instance_valid(actor) and actors.has(actor):
			_reproject(actor)
	if _generation == current_generation and GameState.game_active:
		_drain_pending()


func _drain_pending() -> void:
	if not GameState.game_active or not _board_matches():
		return
	while not pending_summons.is_empty():
		var request: Dictionary = pending_summons[0]
		if int(request.generation) != _generation:
			pending_summons.pop_front()
			continue
		var limit := clampi(int(request.params.get("max_active", max_active)), 1, 32)
		if actors.size() >= limit:
			break
		pending_summons.pop_front()
		if _grid.get_cell(request.coord) == null:
			push_error("DiamondExplorerManager: 本局待召唤钻石坐标失效")
			continue
		_spawn_actor(request.coord, request.params)


func get_reserved_targets() -> Array:
	var coords: Array = _reservations.keys()
	coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x)
	return coords


func reproject_all(_new_grid = null) -> void:
	if not is_instance_valid(_grid):
		return
	for actor in actors:
		if is_instance_valid(actor):
			_reproject(actor)


func _board_matches() -> bool:
	return is_instance_valid(_grid) and _level_id == GameState.current_level_id \
		and _board_anchor != null and is_instance_valid(_board_anchor.get_ref()) \
		and _grid.get_cell(_board_anchor_coord) == _board_anchor.get_ref()


func _assign_target(actor: ExplorerActor) -> void:
	var choices: Array = []
	for action in Solver.find_certain_actions(_grid):
		if action.get("action", "") != "open":
			continue
		var candidate: Vector2i = action.coord
		if _target_available(candidate, actor):
			choices.append(candidate)
	# 距离相同按行列排，选择不依赖隐藏雷位、字典插入顺序或视觉随机源。
	choices.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := actor.coord.distance_squared_to(a)
		var db := actor.coord.distance_squared_to(b)
		if da != db:
			return da < db
		return a.y < b.y if a.y != b.y else a.x < b.x)
	if choices.is_empty():
		actor.state = "waiting"
		return
	actor.target = choices[0]
	actor.flight_from = actor.coord
	actor.elapsed = 0.0
	actor.state = "flying"
	_reservations[actor.target] = actor
	# 与机器人同用一张锁表，机器人也会避开精灵已预留的目标。
	GameState.locked_targets[actor.target] = actor


func _target_available(coord: Vector2i, actor: ExplorerActor) -> bool:
	var cell = _grid.get_cell(coord)
	if cell == null or cell.is_opened or cell.is_flagged or cell.is_collapsed \
		or cell.is_locked or cell.is_fossil or cell.is_base or cell.is_vein \
		or cell.is_confirmed_mine or cell.path_blockers > 0 or cell.cover_wall_hp > 0:
		return false
	if _grid.facility_cells.has(coord):
		return false
	if _reservations.has(coord) and _reservations[coord] != actor:
		return false
	if GameState.locked_targets.has(coord) and GameState.locked_targets[coord] != actor:
		return false
	return true


func _perform_work(actor: ExplorerActor) -> void:
	var target_coord: Vector2i = actor.target
	if not _target_available(target_coord, actor):
		_release_target(actor)
		actor.elapsed = 0.0
		return
	# 飞行途中旗/数字可能改变；作业前重新从公开信息核验推理仍成立。
	var still_certain := false
	for action in Solver.find_certain_actions(_grid):
		if action.get("action", "") == "open" and action.coord == target_coord:
			still_certain = true
			break
	if not still_certain:
		_release_target(actor)
		actor.elapsed = 0.0
		return
	var cell = _grid.get_cell(target_coord)
	var old_wall_hp: int = cell.wall_hp
	var current_generation := _generation
	actor.coord = target_coord
	# 基础开格会同步发胜负信号，先记本次作业，末次行动也进入最终统计。
	actor.actions_left -= 1
	_stat("diamond_explorer_actions", 1)
	_grid.open_cell(target_coord, "diamond_explorer")
	# 开格可同步触发胜负/换关并移除全部单位，不在其后补做旧局作业。
	if _generation != current_generation or not is_instance_valid(actor) or not actors.has(actor):
		return
	var worked: bool = cell.is_opened or cell.wall_hp < old_wall_hp
	_release_target(actor)
	actor.elapsed = 0.0
	if worked:
		actor.work_flash = 1.0
		explorer_worked.emit(actor, target_coord)
	else:
		actor.actions_left += 1
		_stat("diamond_explorer_actions", -1)
	if actor.actions_left <= 0:
		_remove_actor(actor, "completed")
	else:
		_assign_target(actor)


func _release_target(actor: ExplorerActor) -> void:
	if actor.target != null:
		if _reservations.get(actor.target) == actor:
			_reservations.erase(actor.target)
		if GameState.locked_targets.get(actor.target) == actor:
			GameState.locked_targets.erase(actor.target)
	actor.target = null
	actor.state = "waiting"


func _remove_actor(actor: ExplorerActor, reason: String) -> void:
	if not is_instance_valid(actor):
		actors.erase(actor)
		return
	_release_target(actor)
	actors.erase(actor)
	actor.state = "removed"
	actor.visible = false
	actor.queue_free()
	explorer_removed.emit(actor, reason)


func _reproject(actor: ExplorerActor) -> void:
	var coord_px: Vector2 = (Vector2(actor.coord) + Vector2(0.5, 0.5)) * float(_grid.cell_size)
	if actor.target != null:
		var from_px: Vector2 = (Vector2(actor.flight_from) + Vector2(0.5, 0.5)) * float(_grid.cell_size)
		var target_px: Vector2 = (Vector2(actor.target) + Vector2(0.5, 0.5)) * float(_grid.cell_size)
		coord_px = from_px.lerp(target_px, clampf(actor.elapsed / actor.interval, 0.0, 1.0))
	actor.position = to_local(_grid.to_global(coord_px))
	actor.scale = Vector2.ONE * float(_grid.cell_size) / 28.0
	actor.queue_redraw()


func _stat(key: String, amount: Variant) -> void:
	GameState.result_stats[key] = GameState.result_stats.get(key, 0) + amount
