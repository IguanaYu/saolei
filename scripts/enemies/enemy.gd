class_name Enemy
extends Node2D
## L4 敌虫实体（设计 §9.1）：从巢出生 → 直奔最近基地（爬岩壁不受 walkable 限制）
## → 途中每 HARM_INTERVAL 施害一次 → 到基地后原地徘徊继续施害（不攻击基地，Q1）
## 点杀（玩家 1 CD）/ 保安击杀；虫死不回收已施放的障碍

var enemy_type: String = "web"  # "web"织网(盖数字) | "lock"锁匠(锁格) | "slow"减速(留黏液)
var coord: Vector2i = Vector2i(-1, -1)

var _state := "to_base"  # to_base | lurk（围绕基地 3×3 徘徊）
var _move_timer := 0.0
var _harm_timer := 0.0
var _alive := true

const MICRO_ANIMATION := preload("res://scripts/visuals/micro_sprite_loop.gd")
var _micro_loop := MICRO_ANIMATION.new()

const SLIME_MOVE_SEC := 2.5  # 史莱姆步速（设计 §5.1，初值）

signal died(enemy: Enemy, by_actor: String)


func _ready() -> void:
	z_index = 10  # 高于 Cell 与 Robot，虫压在盘面上
	_update_visual()
	# 出场动效：从巢里爬出来
	scale = Vector2(0.1, 0.1)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if not _alive or not MICRO_ANIMATION.is_gameplay_running(self):
		return
	_micro_loop.advance(delta)


func _update_visual() -> void:
	$Body.visible = false
	$IconLabel.visible = false
	_micro_loop.configure($Skin, enemy_type if MICRO_ANIMATION.has_animation(enemy_type) else "web")


func setup(start_coord: Vector2i, type: String, grid) -> void:
	coord = start_coord
	enemy_type = type
	position = grid.coord_to_world(start_coord)
	_update_visual()
	_refresh_clickable_visual(grid)


func is_alive() -> bool:
	return _alive


## 每 tick 推进（EnemyManager 驱动，pause/结算时天然停摆）
func tick(delta: float, grid, target_base: Vector2i) -> void:
	if not _alive:
		return
	_move_timer += delta
	_harm_timer += delta
	var move_sec: float = SLIME_MOVE_SEC if enemy_type == "slime" else EnemyManager.ENEMY_MOVE_SEC
	if _move_timer >= move_sec:
		_move_timer = 0.0
		_step(grid, target_base)
	if _harm_timer >= EnemyManager.HARM_INTERVAL:
		_harm_timer = 0.0
		_harm(grid)


func _step(grid, target_base: Vector2i) -> void:
	var next_coord: Vector2i = coord
	if enemy_type == "slime":
		_slime_step(grid)
		return
	if _state == "to_base":
		var next := Pathfinding.find_path_free_step(grid, coord, target_base)
		if next == Vector2i(-9, -9):
			_state = "lurk"  # 兜底（理论不可达）
			return
		next_coord = next
		if next_coord == target_base:
			_state = "lurk"  # 走进基地格 → 转徘徊
	else:
		# lurk：围绕基地 3×3 随机徘徊（含未开格——虫爬岩壁）
		var candidates: Array = []
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var c: Vector2i = target_base + Vector2i(dx, dy)
				if grid.cells.has(c) and c != coord:
					candidates.append(c)
		if not candidates.is_empty():
			candidates.shuffle()
			next_coord = candidates[0]
	coord = next_coord
	var tw := create_tween()
	tw.tween_property(self, "position", grid.coord_to_world(coord), 0.3)


## 施害（Q4 初值：当前位置 8 邻+自身中第一个合格格，找不到则本次跳过）
func _harm(grid) -> void:
	match enemy_type:
		"web":
			for c in [coord] + _neighbor_coords():
				var cell = grid.get_cell(c)
				if cell != null and cell.apply_web():
					return
		"lock":
			for c in [coord] + _neighbor_coords():
				var cell = grid.get_cell(c)
				# 优先未开未旗未确认格（Q4：不锁玩家已确认的成果/已标的旗）
				if cell != null and not cell.is_flagged and not cell.is_confirmed_mine \
						and cell.apply_lock():
					return
		"slow":
			var here = grid.get_cell(coord)
			if here != null:
				here.apply_slime()  # 当前格直接留黏液


## L5 史莱姆移动（设计 §5.1 / 实施计划 WP3.1）：沿未开墙随机爬、70% 偏向
## frontier（邻 8 格含已开格的墙）；离格时当前格染黏液（Q1：每步一染，墙/开地通吃）
func _slime_step(grid) -> void:
	var here = grid.get_cell(coord)
	if here != null:
		here.apply_slime()  # Q1：每步离格时染黏液（墙/开地通吃）
	var wall_candidates: Array = []   # 未开格（墙）
	var ground_candidates: Array = [] # 已开格（没墙可爬时落地面继续糊）
	for o in MapGenerator.NEIGHBOR_OFFSETS:
		var c: Vector2i = coord + o
		if not grid.cells.has(c) or c == coord:
			continue
		if not grid.cells[c].is_opened:
			wall_candidates.append(c)
		else:
			ground_candidates.append(c)
	var pick_pool: Array = wall_candidates if not wall_candidates.is_empty() else ground_candidates
	if pick_pool.is_empty():
		return  # 死角：原地
	# frontier 偏好：墙候选中「邻 8 格含已开格」的优先 70%（把黏液糊到推进前沿）
	var frontier_walls: Array = wall_candidates.filter(func(c): return _near_opened(c, grid))
	if not frontier_walls.is_empty() and randf() < 0.7:
		pick_pool = frontier_walls
	pick_pool.shuffle()
	coord = pick_pool[0]
	var tw := create_tween()
	tw.tween_property(self, "position", grid.coord_to_world(coord), 0.3)
	_refresh_clickable_visual(grid)


func _near_opened(c: Vector2i, grid) -> bool:
	for o in MapGenerator.NEIGHBOR_OFFSETS:
		var n: Vector2i = c + o
		if grid.cells.has(n) and grid.cells[n].is_opened:
			return true
	return false


## 史莱姆可点击条件（设计 §5.1）：本体格或邻 8 格含已开格——必须开路接近，不能隔墙点死
func is_clickable(grid) -> bool:
	return _near_opened(coord, grid)


## 可点=常态 / 不可点=半透明压暗（Q2：纯视觉自解释，不占文案预算）
func _refresh_clickable_visual(grid) -> void:
	if enemy_type != "slime":
		return
	modulate = Color.WHITE if is_clickable(grid) else Color(0.55, 0.55, 0.55, 0.65)


func _neighbor_coords() -> Array:
	var result: Array = []
	for o in MapGenerator.NEIGHBOR_OFFSETS:
		result.append(coord + o)
	return result


## 被击杀（by_actor = "player" 点杀 / "robot_guard" 保安）：死亡动效后自毁
## 已施放的障碍不回收（设计 §3——虫死了网/锁/黏液仍在，需单独清）
func die(by_actor: String) -> void:
	if not _alive:
		return
	_alive = false
	died.emit(self, by_actor)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.6, 1.6), 0.10)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_callback(queue_free)
