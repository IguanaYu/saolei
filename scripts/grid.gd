class_name Grid
extends Node2D
## 16×16 扫雷网格：生成地图、管理 Cell、处理玩家点击、连锁展开、胜利检测

@export var rows: int = 16
@export var cols: int = 16
@export var mine_count: int = 32
@export var cell_size: int = 28

var cells: Dictionary = {}  # {Vector2i: Cell}

const CELL_SCENE := preload("res://scenes/Cell.tscn")

signal cell_opened(cell, by_actor: String)
signal cell_flagged(cell, by_actor: String, correct: bool)
signal mine_stepped(cell, by_actor: String)
signal all_safe_opened()
signal vein_created(coord: Vector2i)
signal vein_depleted(coord: Vector2i)


func _ready() -> void:
	var grid_pixel: int = rows * cell_size
	var viewport: Vector2 = get_viewport_rect().size
	position = (viewport - Vector2(grid_pixel, grid_pixel)) / 2.0
	init_empty_grid()


## 创建空网格（全关闭），等待玩家放置第一个基地触发雷生成
func init_empty_grid() -> void:
	for c in cells.values():
		c.queue_free()
	cells.clear()
	for y in rows:
		for x in cols:
			var coord := Vector2i(x, y)
			var cell: Cell = CELL_SCENE.instantiate()
			add_child(cell)
			cell.coord = coord
			cell.position = Vector2(x * cell_size + cell_size / 2.0, y * cell_size + cell_size / 2.0)
			cell.cell_left_clicked.connect(_on_cell_left_clicked)
			cell.cell_right_clicked.connect(_on_cell_right_clicked)
			cell.cell_double_clicked.connect(_on_cell_double_clicked)
			cells[coord] = cell


## 玩家放置第一个基地：触发雷生成 + 预开安全区 + 标记基地
## 任意关闭格都可放置（特例：不需要先开格）
func place_first_base(coord: Vector2i) -> bool:
	if not cells.has(coord):
		return false
	# 安全区半径：基础 1 + 局外升级
	var radius: int = 1 + int(SaveSystem.unlocks.get("expand_zone", 0))
	var safe_coords: Array = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var sc := coord + Vector2i(dx, dy)
			if cells.has(sc):
				safe_coords.append(sc)
	# 在安全区外生成雷
	var data: Dictionary = MapGenerator.generate_excluding(rows, cols, mine_count, safe_coords)
	var mine_set: Dictionary = data.mine_set
	var numbers: Dictionary = data.numbers
	for c in cells:
		cells[c].is_mine = mine_set.has(c)
		cells[c].adjacent_mines = int(numbers.get(c, 0))
	# 预开安全区（直接设字段，不触发 cell_opened 信号，避免给奖励）
	for sc in safe_coords:
		cells[sc].is_opened = true
		cells[sc].refresh_visual()
	# 标记基地
	cells[coord].become_base()
	GameState.register_base(coord)
	GameState.set_game_phase("playing")
	return true


## 玩家放置后续基地（必须在已开格上）
func place_base(coord: Vector2i) -> bool:
	if not cells.has(coord):
		return false
	var cell: Cell = cells[coord]
	if not cell.is_opened or cell.is_collapsed or cell.is_base:
		return false
	cell.become_base()
	GameState.register_base(coord)
	return true


func get_cell(coord: Vector2i) -> Cell:
	return cells.get(coord)


## 获取所有被标记旗子的格子坐标
func get_all_flagged_cells() -> Array:
	var result: Array = []
	for coord in cells:
		var c: Cell = cells[coord]
		if c.is_flagged and not c.is_vein:
			result.append(coord)
	return result


## 获取所有有资源的矿脉坐标
func get_all_veins() -> Array:
	var result: Array = []
	for coord in cells:
		var c: Cell = cells[coord]
		if c.is_vein and c.vein_resources > 0:
			result.append(coord)
	return result


## 获取离基地最远的 n 个关闭格（无人机用）
func get_farthest_closed_cells(n: int, base_coord: Vector2i) -> Array:
	var candidates: Array = []
	for coord in cells:
		var c: Cell = cells[coord]
		if c.is_opened or c.is_flagged or c.is_mine:
			continue
		if c.is_base or c.is_vein:
			continue
		var dist: int = abs(coord.x - base_coord.x) + abs(coord.y - base_coord.y)
		candidates.append({"coord": coord, "dist": dist})
	candidates.sort_custom(func(a, b): return a.dist > b.dist)
	var result: Array = []
	for i in range(min(n, candidates.size())):
		result.append(candidates[i].coord)
	return result


func get_neighbors(coord: Vector2i) -> Array:
	var result: Array = []
	for o in MapGenerator.NEIGHBOR_OFFSETS:
		var n: Vector2i = coord + o
		if cells.has(n):
			result.append(cells[n])
	return result


func open_cell(coord: Vector2i, by_actor: String) -> void:
	if not cells.has(coord):
		return
	var cell: Cell = cells[coord]
	if not cell.open(by_actor):
		return

	if cell.is_mine:
		cell.collapse()
		mine_stepped.emit(cell, by_actor)
		return

	cell_opened.emit(cell, by_actor)

	if cell.adjacent_mines == 0:
		_flood_open(coord, by_actor)

	# 胜利检测：在所有连锁展开之后
	if count_safe_remaining() == 0:
		all_safe_opened.emit()


func toggle_flag(coord: Vector2i, by_actor: String) -> void:
	if not cells.has(coord):
		return
	var cell: Cell = cells[coord]
	var was_flagged: bool = cell.is_flagged
	if not cell.toggle_flag():
		return
	if not was_flagged and cell.is_flagged:
		cell_flagged.emit(cell, by_actor, cell.is_mine)


func chord(coord: Vector2i, by_actor: String) -> void:
	if not cells.has(coord):
		return
	var cell: Cell = cells[coord]
	if not cell.is_opened or cell.adjacent_mines == 0:
		return
	var neighbors: Array = get_neighbors(coord)
	var flagged_count: int = 0
	for n in neighbors:
		if n.is_flagged:
			flagged_count += 1
	if flagged_count != cell.adjacent_mines:
		return
	for n in neighbors:
		if not n.is_opened and not n.is_flagged:
			open_cell(n.coord, by_actor)


func is_walkable(coord: Vector2i) -> bool:
	if not cells.has(coord):
		return false
	return cells[coord].is_opened  # 坍塌格视为已开


func count_safe_remaining() -> int:
	var count: int = 0
	for cell in cells.values():
		if not cell.is_mine and not cell.is_opened:
			count += 1
	return count


func coord_to_world(coord: Vector2i) -> Vector2:
	return global_position + Vector2(
		coord.x * cell_size + cell_size / 2.0,
		coord.y * cell_size + cell_size / 2.0)


func world_to_coord(world_pos: Vector2) -> Vector2i:
	var local: Vector2 = world_pos - global_position
	return Vector2i(int(local.x / cell_size), int(local.y / cell_size))


func _flood_open(start: Vector2i, by_actor: String) -> void:
	var start_cell: Cell = cells.get(start)
	if start_cell == null or start_cell.adjacent_mines != 0:
		return
	var queue: Array[Vector2i] = [start]
	var visited: Dictionary = {start: true}
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for o in MapGenerator.NEIGHBOR_OFFSETS:
			var n: Vector2i = c + o
			if visited.has(n) or not cells.has(n):
				continue
			visited[n] = true
			var n_cell: Cell = cells[n]
			if n_cell.is_opened or n_cell.is_flagged:
				continue
			n_cell.open(by_actor)
			cell_opened.emit(n_cell, by_actor)
			if n_cell.adjacent_mines == 0 and not n_cell.is_mine:
				queue.append(n)


func _on_cell_left_clicked(cell: Cell) -> void:
	if GameState.game_active:
		open_cell(cell.coord, "player")


func _on_cell_right_clicked(cell: Cell) -> void:
	if GameState.game_active:
		toggle_flag(cell.coord, "player")


func _on_cell_double_clicked(cell: Cell) -> void:
	if GameState.game_active:
		chord(cell.coord, "player")
