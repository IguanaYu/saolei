class_name DiamondEffectManager
extends Node
## 第二章的一次性钻石能力。静态关卡资源只读；排队/消耗和随机结果均为本局状态。
## 新范围不激活旧设施；新射线借用 LaserManager 的旧规则并共享整枪对象账本。

signal effect_released(event: Dictionary)
signal diamond_state_changed(coord: Vector2i)

const EFFECT_IDS := ["area_3x3", "split_two", "gold", "explorer"]
const DIRECTIONS := [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1),
	Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]
const INVALID_COORD := Vector2i(-9999, -9999)

var grid: Grid = null
var definitions: Dictionary = {}  # coord -> {effect_id, params}，不写回 LevelData
var states: Dictionary = {}       # coord -> ready / queued / consumed
var validation_errors: Array[String] = []
var effect_rng := RandomNumberGenerator.new()
var level_serial := 0
var shot_serial := 0
var handlers: Dictionary = {}


func _init() -> void:
	handlers = {"area_3x3": _handle_area, "split_two": _handle_split,
		"gold": _handle_gold, "explorer": _handle_explorer}


func setup_for_level(level, board: Grid) -> void:
	reset_for_level()
	grid = board
	if level == null or grid == null or not grid.laser_mode or grid.laser_beam_mode:
		return
	effect_rng.seed = int(level.diamond_effect_seed)
	for raw in level.diamond_effects:
		if not raw is Dictionary:
			_report("配置必须是 Dictionary")
			continue
		var coord_value = raw.get("coord", INVALID_COORD)
		if not coord_value is Vector2i:
			_report("coord 必须是 Vector2i")
			continue
		var coord: Vector2i = coord_value
		var cell: Cell = grid.get_cell(coord)
		var effect_id := str(raw.get("effect_id", raw.get("id", "")))
		if cell == null or not cell.is_mine or cell.is_fossil or cell.is_opened:
			_report("%s 必须是盘内未打开的钻石格" % str(coord))
			continue
		if definitions.has(coord):
			_report("%s 重复配置" % str(coord))
			continue
		if not EFFECT_IDS.has(effect_id):
			_report("%s 未知效果 %s" % [str(coord), effect_id])
			continue
		var params_value = raw.get("params", {})
		if not params_value is Dictionary:
			_report("%s params 必须是 Dictionary" % str(coord))
			continue
		var params: Dictionary = params_value.duplicate(true)
		# 同时支持便于固定盘编写的顶层参数。
		for key in ["gold_amount", "ray_range", "directions", "actions", "interval",
				"lifetime", "max_active"]:
			if raw.has(key):
				params[key] = raw[key]
		if not _validate_params(effect_id, params, coord):
			continue
		definitions[coord] = {"effect_id": effect_id, "params": params}
		states[coord] = "ready"
		cell.diamond_effect_id = effect_id
		cell.diamond_effect_consumed = false
		cell.refresh_visual()


func reset_for_level() -> void:
	level_serial += 1
	shot_serial = 0
	if grid != null and is_instance_valid(grid):
		for coord in definitions:
			var cell: Cell = grid.get_cell(coord)
			if cell != null:
				cell.diamond_effect_id = ""
				cell.diamond_effect_consumed = false
				cell.refresh_visual()
	definitions.clear()
	states.clear()
	validation_errors.clear()
	grid = null


func is_enabled() -> bool:
	return grid != null and not definitions.is_empty()


## 信息边界：只向表现层公开当前正确标记的钻石，不通过预览泄露隐藏位置和类型。
func public_info(coord: Vector2i) -> Dictionary:
	if not definitions.has(coord) or grid == null:
		return {}
	var cell: Cell = grid.get_cell(coord)
	if cell == null or not cell.is_flagged or not cell.is_mine or cell.is_opened:
		return {}
	var result: Dictionary = definitions[coord].duplicate(true)
	result["consumed"] = states.get(coord, "ready") != "ready"
	return result


func _report(message: String) -> void:
	validation_errors.append(message)
	push_error("DiamondEffectManager: " + message)


func _validate_params(effect_id: String, params: Dictionary, coord: Vector2i) -> bool:
	var allowed: Dictionary = {"area_3x3": [], "split_two": ["ray_range", "directions"],
		"gold": ["gold_amount"], "explorer": ["actions", "interval", "lifetime", "max_active"]}
	for key in params:
		if not allowed[effect_id].has(key):
			_report("%s %s 不支持参数 %s" % [str(coord), effect_id, str(key)])
			return false
	if effect_id == "gold":
		var amount = params.get("gold_amount", 10)
		if not _number_in_range(amount, 1.0, 1000000.0) or float(amount) != int(amount):
			_report("%s gold_amount 必须是 1..1000000 的整数" % str(coord))
			return false
		params["gold_amount"] = int(amount)
	elif effect_id == "split_two":
		var length = params.get("ray_range", 3)
		if not _number_in_range(length, 1.0, 128.0) or float(length) != int(length):
			_report("%s ray_range 必须是 1..128 的整数" % str(coord))
			return false
		params["ray_range"] = int(length)
		var candidates = params.get("directions", DIRECTIONS.duplicate())
		if not candidates is Array or candidates.size() < 2:
			_report("%s directions 至少包含两个互异八向" % str(coord))
			return false
		var seen: Dictionary = {}
		for direction in candidates:
			if not DIRECTIONS.has(direction) or seen.has(direction):
				_report("%s directions 含非法或重复方向" % str(coord))
				return false
			seen[direction] = true
		params["directions"] = candidates.duplicate()
	elif effect_id == "explorer":
		for key in ["actions", "max_active"]:
			if params.has(key) and (not _number_in_range(params[key], 1.0, 32.0) or float(params[key]) != int(params[key])):
				_report("%s %s 必须是 1..32 的整数" % [str(coord), key])
				return false
		for key in ["interval", "lifetime"]:
			var upper := 30.0 if key == "interval" else 300.0
			if params.has(key) and not _number_in_range(params[key], 0.1, upper):
				_report("%s %s 必须是 0.1..%s 的数值" % [str(coord), key, str(upper)])
				return false
	return true


func _number_in_range(value, lower: float, upper: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) \
		and float(value) >= lower and float(value) <= upper


## 在任何开格/自动展开之前创建旗快照，迭代队列收敛后才执行空间结算。
## 返回的 geo 保持原字段并扩展 diamond_context；旧爆炸格只参与破坏，不进钻石队列。
func prepare_shot(geo: Dictionary, laser_manager) -> Dictionary:
	if not is_enabled():
		return geo
	shot_serial += 1
	var ctx := {"level_serial": level_serial, "shot_serial": shot_serial,
		"eligible": {}, "queued": {}, "queue": [], "events": [], "gold": 0,
		"explorers": [], "charge_cells": [], "ray_geometries": [],
		"new_cells": [], "committed": false, "ledger": laser_manager.trigger_ledger_from(geo)}
	for coord in definitions:
		var cell: Cell = grid.get_cell(coord)
		if cell != null and cell.is_flagged and cell.is_mine and not cell.is_opened and not cell.is_fossil:
			ctx.eligible[coord] = true
	_enqueue_cells(_beam_cells(geo), ctx)
	var cursor := 0
	while cursor < ctx.queue.size():
		if cursor >= definitions.size():
			_report("队列超过本局钻石数；请检查重复入队，当前 shot=%d" % shot_serial)
			break
		var coord: Vector2i = ctx.queue[cursor]
		cursor += 1
		var definition: Dictionary = definitions[coord]
		var params: Dictionary = definition.params
		var event := {"coord": coord, "effect_id": definition.effect_id,
			"params": params.duplicate(true), "cells": [], "rays": [], "gold_amount": 0}
		handlers[str(definition.effect_id)].call(event, ctx, geo, laser_manager)
		ctx.events.append(event)
	geo["diamond_context"] = ctx
	return geo


func _handle_area(event: Dictionary, ctx: Dictionary, geo: Dictionary, _laser_manager) -> void:
	event.cells = _area_cells(event.coord)
	_merge_cells(geo.cells, event.cells)
	_merge_cells(ctx.new_cells, event.cells)
	_merge_cells(ctx.charge_cells, event.cells)
	_enqueue_cells(event.cells, ctx)


func _handle_split(event: Dictionary, ctx: Dictionary, geo: Dictionary, laser_manager) -> void:
	var directions: Array = event.params.directions.duplicate()
	for index in range(2):
		var selected := effect_rng.randi_range(index, directions.size() - 1)
		var swap = directions[index]
		directions[index] = directions[selected]
		directions[selected] = swap
		var end: Vector2i = event.coord + directions[index] * int(event.params.ray_range)
		var ray_geo: Dictionary = laser_manager.compute_shot_geometry(event.coord, end, true, ctx.ledger)
		var ray_cells: Array = _beam_cells(ray_geo)
		_merge_cells(event.cells, ray_cells)
		event.rays.append({"from": event.coord, "to": laser_manager.main_endpoint(ray_geo, end),
			"cells": ray_geo.main.duplicate(), "direction": directions[index]})
		_merge_geometry(geo, ray_geo)
		_merge_cells(ctx.new_cells, ray_geo.cells)
		_merge_cells(ctx.charge_cells, ray_cells)
		ctx.ray_geometries.append({"from": event.coord, "target": end, "geo": ray_geo})
		_enqueue_cells(ray_cells, ctx)


func _handle_gold(event: Dictionary, ctx: Dictionary, _geo: Dictionary, _laser_manager) -> void:
	event.gold_amount = int(event.params.gold_amount)
	ctx.gold += event.gold_amount


func _handle_explorer(event: Dictionary, ctx: Dictionary, _geo: Dictionary, _laser_manager) -> void:
	ctx.explorers.append({"coord": event.coord, "params": event.params.duplicate(true)})


func _enqueue_cells(cells: Array, ctx: Dictionary) -> void:
	for coord in cells:
		if not ctx.eligible.has(coord) or ctx.queued.has(coord) or states.get(coord, "") != "ready":
			continue
		ctx.queued[coord] = true
		ctx.queue.append(coord)
		states[coord] = "queued"  # 逻辑即时锁定，动画未结束也不能再次触发。


## 由 LaserManager 在本枪所有破坏/充能/柱受击后调用；同步完成奖励和召唤，再允许判胜。
func commit_shot(geo: Dictionary) -> void:
	var ctx: Dictionary = geo.get("diamond_context", {})
	if ctx.is_empty() or ctx.get("committed", false) or int(ctx.level_serial) != level_serial:
		return
	ctx.committed = true
	for coord in ctx.queue:
		states[coord] = "consumed"
		var cell: Cell = grid.get_cell(coord)
		if cell != null:
			cell.diamond_effect_consumed = true
			cell.refresh_visual()
		diamond_state_changed.emit(coord)
	if int(ctx.gold) > 0:
		GameState.add_money(int(ctx.gold), "diamond_effect_gold")
	var explorers = get_node_or_null("../DiamondExplorerManager")
	for request in ctx.explorers:
		if explorers != null:
			explorers.summon(request.coord, request.params)
		else:
			push_error("DiamondEffectManager: 缺少 DiamondExplorerManager，不能提交召唤")
	_inc_stat("diamond_effects_triggered", ctx.events.size())
	_inc_stat("diamond_chain_max", maxi(0, ctx.events.size() - int(GameState.result_stats.get("diamond_chain_max", 0))))
	_inc_stat("diamond_effect_cells", ctx.new_cells.size())
	for event in ctx.events:
		_inc_stat("diamond_" + str(event.effect_id) + "_triggered", 1)
		effect_released.emit(event)


func _inc_stat(key: String, amount: int) -> void:
	GameState.result_stats[key] = int(GameState.result_stats.get(key, 0)) + amount


## 确定的 3×3 才加入实际预览；随机射线只返回已公开的来源标识，绝不抽签。
func preview_shot(geo: Dictionary) -> Dictionary:
	var result := {"cells": [], "marks": [], "random_origins": [], "possible_cells": []}
	if not is_enabled():
		return result
	var pending: Array = _beam_cells(geo)
	var seen: Dictionary = {}
	var cursor := 0
	while cursor < pending.size():
		var coord: Vector2i = pending[cursor]
		cursor += 1
		if seen.has(coord):
			continue
		seen[coord] = true
		var info := public_info(coord)
		if info.is_empty() or info.consumed:
			continue
		result.marks.append(coord)
		if info.effect_id == "area_3x3":
			var area := _area_cells(coord)
			_merge_cells(result.cells, area)
			_merge_cells(pending, area)
		elif info.effect_id == "split_two":
			result.random_origins.append(coord)
			# 只展示已公开来源的最大候选几何；不抽签、不触发设施或预演新钻石。
			for direction in info.params.directions:
				var end: Vector2i = coord + direction * int(info.params.ray_range)
				for possible in LaserGeometry.beam_cells(coord, end):
					if grid.cells.has(possible) and not result.possible_cells.has(possible):
						result.possible_cells.append(possible)
	return result


func _area_cells(origin: Vector2i) -> Array:
	var out: Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var coord := origin + Vector2i(dx, dy)
			if grid.cells.has(coord):
				out.append(coord)
	return out


func _beam_cells(geo: Dictionary) -> Array:
	var out: Array = geo.get("main", []).duplicate()
	_merge_cells(out, geo.get("sub", []))
	return out


func _merge_cells(into: Array, additions: Array) -> void:
	for coord in additions:
		if not into.has(coord):
			into.append(coord)


func _merge_geometry(into: Dictionary, extra: Dictionary) -> void:
	for key in ["cells", "chain_nodes", "chain_cells", "ores", "ore_cells", "ore_marks",
			"overloads", "overload_cells", "refractors"]:
		if not into.has(key):
			into[key] = []
		_merge_cells(into[key], extra.get(key, []))
	for key in ["ore_details", "overload_details"]:
		into[key].append_array(extra.get(key, []))
