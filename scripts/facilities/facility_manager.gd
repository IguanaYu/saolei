class_name FacilityManager
extends Node2D
## 第二章中立设施总控（2-4 连爆节点 + 2-5 引光柱 + 2-3 特殊矿石；总纲 §6.3/§6.4）。
## 阵营归中立不挂 EnemyManager；三链接线照 robot/enemy/boss 管理器惯例（2-4 实施计划 WP1）：
## 清理链 clear（main._start_level_with） / 窗口重排 reproject_all（main._relayout_play_area）/
## 高塔滚动 on_grid_relaid（main._on_grid_view_changed）。
## 占格：存活设施格进 grid.facility_cells（is_walkable 门；消耗后解除=格恢复普通）。
## 矿石例外：不可破坏（consumed 概念不适用），足迹恒占格；结算跳过由 LaserManager 负责。

var chain_nodes: Array = []   # Array[ChainNode]
var pillar: LightPillar = null   # 2-5 引光柱（唯一；无则 null）
var ores: Array = []             # Array[SpecialOre]（2-3；不可破坏恒存活）
var _grid = null


func clear() -> void:
	for n in chain_nodes:
		if is_instance_valid(n):
			n.queue_free()
	chain_nodes.clear()
	if pillar != null:
		if is_instance_valid(pillar):
			pillar.queue_free()
		pillar = null
	for o in ores:
		if is_instance_valid(o):
			o.queue_free()
	ores.clear()
	if _grid != null and is_instance_valid(_grid):
		_grid.facility_cells.clear()


func reproject_all(grid) -> void:
	for n in chain_nodes:
		if is_instance_valid(n):
			n.position = grid.coord_to_world(n.coord)
	if pillar != null and is_instance_valid(pillar):
		pillar.position = grid.coord_to_world(pillar.coord)
	for o in ores:
		if is_instance_valid(o):
			o.position = grid.coord_to_world(o.origin) + Vector2(grid.cell_size / 2.0,
					grid.cell_size / 2.0)


## 高塔滚动/窗口变化同源：设施是驻点实体，按缓存 coord 重写世界坐标即可
func on_grid_relaid(grid) -> void:
	reproject_all(grid)


## 2-5 引光柱恢复计时（main._process 驱动；三重门冻结时不会进来，2-4 无柱=no-op）
func tick(delta: float, _grid) -> void:
	if pillar != null and is_instance_valid(pillar):
		pillar.tick(delta)


## 进关装载（main._start_level_with 盘面分支后调用；coords 须全在预开安全格）
func setup_chain_nodes(grid, coords: Array) -> void:
	_grid = grid
	for c in coords:
		if not grid.cells.has(c):
			push_warning("连爆节点 %s 不在盘内，跳过（检查盘面数据）" % str(c))
			continue
		var node := ChainNode.new()
		node.name = "ChainNode%02d" % (chain_nodes.size() + 1)  # 显式命名防遍历误匹配
		add_child(node)
		node.setup(c, grid)
		chain_nodes.append(node)
	_sync_occupancy()


## 未消耗节点查询（占格/链展开共用；null=无或已消耗）
func node_at(coord: Vector2i) -> ChainNode:
	for n in chain_nodes:
		if is_instance_valid(n) and not n.consumed and n.coord == coord:
			return n
	return null


## 连爆消耗（laser_manager.fire 结算末调用，nodes 为快照 BFS 序）：
## 逻辑即时置 consumed（同轮幂等，销毁动画期不重复爆），演出按序错峰——
## 长链总时长封顶 0.4s（Q3），超出压缩步长并发闪光
func consume_chain(nodes: Array, grid) -> void:
	if nodes.is_empty():
		return
	var fx: EffectsLayer = grid.get_node_or_null("EffectsLayer") as EffectsLayer
	var step: float = minf(0.06, 0.4 / float(maxi(1, nodes.size() - 1)))
	for i in nodes.size():
		var n: ChainNode = nodes[i]
		if n == null or not is_instance_valid(n):
			continue
		n.trigger()
		if fx != null:
			fx.fx_chain_blast_at(n, grid, i * step)
		else:
			n.play_consume(0.0)  # 无特效层兜底：直接消失
	_sync_occupancy()


## 2-5 引光柱装载（main._start_level_with 盘面分支后调用）
func setup_pillar(grid, coord: Vector2i) -> void:
	_grid = grid
	if not grid.cells.has(coord):
		push_warning("引光柱 %s 不在盘内，跳过（检查盘面数据）" % str(coord))
		return
	pillar = LightPillar.new()
	pillar.name = "LightPillar"  # 显式命名防遍历误匹配
	add_child(pillar)
	pillar.setup(coord, grid)
	_sync_occupancy()


## 存活柱格查询（几何改写/受击判定用；null=无或已碎）
func pillar_coord_alive() -> Vector2i:
	if pillar != null and is_instance_valid(pillar) and pillar.is_alive:
		return pillar.coord
	return Vector2i(-9, -9)


## 柱破碎收尾（laser_manager 结算序调用）：演出 + 占格解除（柱格恢复通行）
func on_pillar_broken(grid) -> void:
	if pillar == null or not is_instance_valid(pillar):
		return
	pillar.play_break(grid)
	pillar = null
	_sync_occupancy()


## 2-3 特殊矿石装载（main._start_level_with 盘面分支后调用；defs = [{"origin": Vector2i}]，
## 足迹须全在预开安全格——finder 烘焙保证，越界格整块警告跳过）
func setup_ores(grid, defs: Array) -> void:
	_grid = grid
	for d in defs:
		var o_coord: Vector2i = d.get("origin", Vector2i(-9, -9))
		var ok := true
		for dy in SpecialOre.SIZE:
			for dx in SpecialOre.SIZE:
				if not grid.cells.has(o_coord + Vector2i(dx, dy)):
					ok = false
					break
		if not ok:
			push_warning("特殊矿石 %s 足迹越界，整块跳过（检查盘面数据）" % str(o_coord))
			continue
		var ore := SpecialOre.new()
		ore.name = "SpecialOre%02d" % (ores.size() + 1)  # 显式命名防遍历误匹配
		add_child(ore)
		ore.setup(o_coord, grid)
		ores.append(ore)
	_sync_occupancy()


## 足迹命中查询（束截停/结算跳过/触发判定共用；null=无矿石）
func ore_at(coord: Vector2i) -> SpecialOre:
	for o in ores:
		if is_instance_valid(o) and coord.x >= o.origin.x \
				and coord.x < o.origin.x + o.SIZE \
				and coord.y >= o.origin.y and coord.y < o.origin.y + o.SIZE:
			return o
	return null


## 存活设施占格表重建（grid.is_walkable 门的数据源；clear/setup/consume 后同步）
func _sync_occupancy() -> void:
	if _grid == null or not is_instance_valid(_grid):
		return
	_grid.facility_cells.clear()
	for n in chain_nodes:
		if is_instance_valid(n) and not n.consumed:
			_grid.facility_cells[n.coord] = true
	if pillar != null and is_instance_valid(pillar) and pillar.is_alive:
		_grid.facility_cells[pillar.coord] = true
	for o in ores:
		if is_instance_valid(o):
			for c in o.footprint():
				_grid.facility_cells[c] = true
