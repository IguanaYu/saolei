class_name BuilderEnemy
extends Enemy
## 2-2 筑墙工（总纲 §7）：耐久 2 的造墙敌人——在已开地面造覆盖墙，可管理不失控。
## 出现前裂隙预警 2s；每 6s 施工一块（优先玩家激光最近拆过的地面）；
## 每只保有 ≤4 块、全场 ≤8 块、不封死基地唯一出口；被激光两次/护卫两枪击破。
## 只造墙：不改数字、不偷分、不扣命、不攻击基地与机器人（底线在 EnemyManager 调度侧）

const HP_MAX := 2
const MOVE_SEC := 2.2          # 已开区内游走步速
const BUILD_INTERVAL := 6.0    # 每 6s 尝试施工一块
const BUILD_RANGE := 2         # 自身周围 2 格（切比雪夫）内选地面
const OWN_WALL_CAP := 4        # 每只保有上限

var hp: int = HP_MAX
var _build_timer := 0.0  # _move_timer 沿用父类 Enemy 的字段（不重复声明）
var _rift: Node2D = null       # 出现前裂隙（预警 2s）
var _wall_sequence: Array = []  # 新墙耐久序列（2-2 [1]；2-3 起 [1,1,3]）
var _wall_seq_idx := 0
var _my_walls: Array = []      # 本只造的墙坐标（保有上限口径；被拆/被覆盖不回收坐标，计数实时查）

signal builder_spawned(b: BuilderEnemy)
signal builder_damaged(b: BuilderEnemy)


func _ready() -> void:
	z_index = 10
	_update_visual()
	FACTION_MARKER.attach(self, $Skin, true)


func _update_visual() -> void:
	$Body.visible = false
	$IconLabel.visible = false
	if MICRO_ANIMATION.has_animation("web"):
		_micro_loop.configure($Skin, "web")  # 程序占位：借织网虫皮肤表；素材批后换筑墙工表
	$Skin.modulate = Color(1.0, 0.62, 0.45)  # 暖橙染色与三虫区分


## 出场编排：先裂隙闪烁 2s（无碰撞无交互），再落地弹入
func spawn_with_rift(start_coord: Vector2i, grid, sequence: Array) -> void:
	_wall_sequence = sequence if not sequence.is_empty() else [1]
	coord = start_coord
	position = grid.coord_to_world(start_coord)
	visible = false
	_rift = _make_rift(grid)
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_callback(func():
		if not is_instance_valid(self):
			return
		if is_instance_valid(_rift):
			_rift.queue_free()
			_rift = null
		visible = true
		builder_spawned.emit(self)
		var pop := create_tween()
		pop.tween_property(self, "scale", Vector2(1.25, 1.25), 0.12).set_ease(Tween.EASE_OUT)
		pop.tween_property(self, "scale", Vector2.ONE, 0.10))


func _make_rift(grid) -> Node2D:
	var rift := Node2D.new()
	rift.name = "BuilderRift"
	rift.z_index = 9
	var rect := ColorRect.new()
	rect.name = "RiftCore"
	rect.color = Color(1.0, 0.45, 0.2, 0.55)
	rect.position = Vector2(-10, -10)
	rect.size = Vector2(20, 20)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rift.add_child(rect)
	get_parent().add_child(rift)
	rift.position = grid.coord_to_world(coord)
	var tw := rift.create_tween().set_loops(6)
	tw.tween_property(rect, "color:a", 0.15, 0.16)
	tw.tween_property(rect, "color:a", 0.7, 0.16)
	return rift


## Enemy.tick 覆写：不奔袭基地不施害——游走 + 施工（EnemyManager 驱动）
func tick(delta: float, grid, _target_base: Vector2i) -> void:
	if not _alive or not visible:
		return
	_move_timer += delta
	_build_timer += delta
	if _move_timer >= MOVE_SEC:
		_move_timer = 0.0
		_wander_step(grid)
	if _build_timer >= BUILD_INTERVAL:
		_build_timer = 0.0
		_try_build(grid)


## 已开区内 4 邻随机游走（不出已开区；覆盖墙格不可站）
func _wander_step(grid) -> void:
	var options: Array = []
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = coord + o
		var c: Cell = grid.get_cell(n)
		if c != null and c.is_opened and c.cover_wall_hp <= 0 and not c.is_base:
			options.append(n)
	if options.is_empty():
		return
	options.shuffle()
	coord = options[0]
	var tw := create_tween()
	tw.tween_property(self, "position", grid.coord_to_world(coord), 0.3)


## 施工（设计 §7 逐条）：优先最近 10s 被玩家激光拆过的地面；排除与上限；出口保活
func _try_build(grid, laser_manager = null) -> void:
	if _alive_walls(grid) >= OWN_WALL_CAP or grid.count_cover_walls() >= 8:
		return
	var lm = laser_manager if laser_manager != null \
			else get_node_or_null("/root/Main/BoardRoot/LaserManager")
	var candidates: Array = []
	var recent: Array = []
	for dy in range(-BUILD_RANGE, BUILD_RANGE + 1):
		for dx in range(-BUILD_RANGE, BUILD_RANGE + 1):
			var c: Vector2i = coord + Vector2i(dx, dy)
			var cell: Cell = grid.get_cell(c)
			if cell == null or not cell.is_opened or cell.cover_wall_hp > 0:
				continue
			if cell.is_base or cell.is_vein or cell.is_flagged or cell.is_collapsed:
				continue  # 不占基地/已转化资源/旗格/坍塌
			if _robot_at(c):
				continue  # 不推挤机器人
			if lm != null and lm.was_recently_lasered(c):
				recent.append(c)
			else:
				candidates.append(c)
	var pool: Array = recent if not recent.is_empty() else candidates
	if pool.is_empty():
		return
	pool.shuffle()
	for c in pool:
		if not grid.base_can_reach_frontier(c):
			continue  # 会封死基地唯一出口 → 换下一个候选
		var hp_next: int = int(_wall_sequence[_wall_seq_idx % _wall_sequence.size()])
		_wall_seq_idx += 1
		if grid.get_cell(c).place_cover_wall(hp_next):
			_my_walls.append(c)
			_play_build_fx(grid, c)
			return


func _robot_at(c: Vector2i) -> bool:
	var rm = get_node_or_null("/root/Main/BoardRoot/RobotManager")
	return rm != null and rm.get_robot_positions().has(c)


func _alive_walls(grid) -> int:
	var n := 0
	for c in _my_walls:
		var cell: Cell = grid.get_cell(c)
		if cell != null and cell.cover_wall_hp > 0:
			n += 1
	return n


func _play_build_fx(grid, c: Vector2i) -> void:
	var cell: Cell = grid.get_cell(c)
	if cell != null:
		var tw := cell.create_tween()
		tw.tween_property(cell, "modulate", Color(1.4, 1.1, 0.9), 0.08)
		tw.tween_property(cell, "modulate", Color.WHITE, 0.12)


## 受击（激光每轮 ≤1 / 护卫一枪 1 伤）：归零走 Enemy.die（结算在 EnemyManager）
func take_hit(by_actor: String) -> void:
	if not _alive:
		return
	hp -= 1
	builder_damaged.emit(self)
	var tw := create_tween()
	tw.tween_property($Skin, "modulate", Color(1.0, 0.3, 0.2), 0.06)
	tw.tween_property($Skin, "modulate", Color(1.0, 0.62, 0.45), 0.12)
	if hp <= 0:
		die(by_actor)


func die(by_actor: String) -> void:
	if _rift != null and is_instance_valid(_rift):
		_rift.queue_free()
	super.die(by_actor)
