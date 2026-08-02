class_name Grid
extends Node2D
## 16×16 扫雷网格：生成地图、管理 Cell、处理玩家点击、连锁展开、胜利检测

@export var rows: int = 16
@export var cols: int = 16
@export var mine_count: int = 40
@export var cell_size: int = 28
@export var safe_zone_radius: int = 1  # 中心 3×3

var cells: Dictionary = {}  # {Vector2i: Cell}
var safe_zone: Rect2i

const CELL_SCENE := preload("res://scenes/Cell.tscn")

signal cell_opened(cell, by_actor: String)
signal cell_flagged(cell, by_actor: String, correct: bool)
signal mine_stepped(cell, by_actor: String)
signal all_safe_opened()


func _ready() -> void:
	var grid_pixel: int = rows * cell_size
	var viewport: Vector2 = get_viewport_rect().size
	position = (viewport - Vector2(grid_pixel, grid_pixel)) / 2.0
	generate_map()


func generate_map() -> void:
	for c in cells.values():
		c.queue_free()
	cells.clear()

	safe_zone = MapGenerator.make_center_safe_zone(rows, cols, safe_zone_radius)
	var data: Dictionary = MapGenerator.generate(rows, cols, mine_count, safe_zone)
	var mine_set: Dictionary = data.mine_set
	var numbers: Dictionary = data.numbers

	for y in rows:
		for x in cols:
			var coord := Vector2i(x, y)
			var cell: Cell = CELL_SCENE.instantiate()
			add_child(cell)
			cell.coord = coord
			cell.position = Vector2(x * cell_size + cell_size / 2.0, y * cell_size + cell_size / 2.0)
			cell.is_mine = mine_set.has(coord)
			cell.adjacent_mines = int(numbers.get(coord, 0))
			cell.cell_left_clicked.connect(_on_cell_left_clicked)
			cell.cell_right_clicked.connect(_on_cell_right_clicked)
			cell.cell_double_clicked.connect(_on_cell_double_clicked)
			cells[coord] = cell

			# 预开安全区
			if MapGenerator._in_safe_zone(coord, safe_zone):
				cell.is_opened = true
				cell.refresh_visual()


func get_cell(coord: Vector2i) -> Cell:
	return cells.get(coord)


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
