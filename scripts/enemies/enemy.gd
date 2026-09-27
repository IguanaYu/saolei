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

# 占位视觉（Q5：代码色块+emoji，正式素材列美术生产需求）
const TYPE_VISUALS := {
	"web": {"color": Color(0.72, 0.72, 0.78), "icon": "🕸"},
	"lock": {"color": Color(0.85, 0.68, 0.22), "icon": "🔒"},
	"slow": {"color": Color(0.42, 0.68, 0.34), "icon": "🐌"},
}

signal died(enemy: Enemy, by_actor: String)


func _ready() -> void:
	z_index = 10  # 高于 Cell 与 Robot，虫压在盘面上
	_update_visual()
	# 出场动效：从巢里爬出来
	scale = Vector2(0.1, 0.1)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _update_visual() -> void:
	var cfg: Dictionary = TYPE_VISUALS.get(enemy_type, TYPE_VISUALS["web"])
	$Body.color = cfg.color
	$IconLabel.text = cfg.icon


func setup(start_coord: Vector2i, type: String, grid) -> void:
	coord = start_coord
	enemy_type = type
	position = grid.coord_to_world(start_coord)
	_update_visual()


func is_alive() -> bool:
	return _alive


## 每 tick 推进（EnemyManager 驱动，pause/结算时天然停摆）
func tick(delta: float, grid, target_base: Vector2i) -> void:
	if not _alive:
		return
	_move_timer += delta
	_harm_timer += delta
	if _move_timer >= EnemyManager.ENEMY_MOVE_SEC:
		_move_timer = 0.0
		_step(grid, target_base)
	if _harm_timer >= EnemyManager.HARM_INTERVAL:
		_harm_timer = 0.0
		_harm(grid)


func _step(grid, target_base: Vector2i) -> void:
	var next_coord: Vector2i = coord
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
