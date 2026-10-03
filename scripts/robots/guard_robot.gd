class_name GuardRobot
extends Robot
## L4 保安机器人（设计 §9.4）：商店 80 限购 1，花钱买断的清道夫
## 仅在已开区移动（BFS walkable）；索敌优先级 虫>锁>网>黏液，同类取 BFS 最近；
## 射程 4 格（切比雪夫）、1.5s/发；一次只处理一个目标；一枪一个
## 速度固定 2.0s/格（Q2：不吃升级轨，便于盲测归因）；受黏液减速（统一口径）

const FIRE_INTERVAL := 1.5   # 开火间隔（_process 计时，不走移动 tick）
const FIRE_RANGE := 4        # 射程：切比雪夫距离

var _target_kind := ""       # "" / "enemy" / "lock" / "web" / "slime"
var _target_coord: Vector2i = Vector2i(-1, -1)
var _target_enemy: Enemy = null
var _fire_timer := 0.0
var _grid_ref = null


func _ready() -> void:
	super()
	robot_type = "guard"
	_update_visual()


## 保安永不报空闲（is_idle 恒 false）：避免触发停摆文案误报（计划 WP4.1）
func is_idle() -> bool:
	return false


## 是否有目标（索敌/交战中）——队伍栏状态文案用（P2-02：交战中/执勤中）
func is_engaged() -> bool:
	return _target_kind != ""


func _process(delta: float) -> void:
	if not MICRO_ANIMATION.is_gameplay_running(self):
		return
	super(delta)  # 基类局部微动画
	# 交战计时：目标在射程内站定开火（与移动 tick 分离，参照 detector 的 _process 模式）
	if _target_kind != "" and _grid_ref != null \
			and _chebyshev(_target_coord) <= FIRE_RANGE:
		_fire_timer += delta
		if _fire_timer >= FIRE_INTERVAL:
			_fire_timer = 0.0
			_fire(_grid_ref)


func do_tick(grid, locked: Dictionary) -> void:
	_grid_ref = grid
	_validate_target(grid)
	if _target_kind == "":
		_acquire_target(grid)
	if _target_kind == "":
		_patrol(grid)
		return
	if _chebyshev(_target_coord) <= FIRE_RANGE:
		_state = "working"  # 站定，开火由 _process 推进
		return
	# 射程外：BFS（限已开区）走一步；不可达（如未开区深处的障碍）→ 弃目标重新索敌
	var path := Pathfinding.find_nearest_target(grid, coord, [_target_coord], {}, self)
	if path.is_empty():
		_target_kind = ""
		_state = "idle"
		return
	if path.work_pos == coord:
		_state = "working"  # 已 8 邻接（必在射程内，理论到不了这里）
		return
	var next: Vector2i = path.path[0]
	_move_to(next, grid)
	coord = next
	_state = "moving"


func _chebyshev(target: Vector2i) -> int:
	return maxi(abs(coord.x - target.x), abs(coord.y - target.y))


## 目标失效检查（玩家先清了/虫被打死/格子状态变化）
func _validate_target(grid) -> void:
	if _target_kind == "enemy":
		if _target_enemy == null or not _target_enemy.is_alive():
			_clear_target()
	elif _target_kind != "":
		var cell = grid.get_cell(_target_coord)
		if cell == null \
				or (_target_kind == "lock" and not cell.is_locked) \
				or (_target_kind == "web" and not cell.is_webbed) \
				or (_target_kind == "slime" and not cell.is_slimed):
			_clear_target()


## 索敌：四类按优先级扫描，同类取 BFS 最近（walkable BFS 天然过滤未开区深处的障碍）
func _acquire_target(grid) -> void:
	var em: EnemyManager = get_node("/root/Main/EnemyManager")
	var enemy_coords: Array = []
	for e in em.enemies:
		if e.is_alive():
			var c = grid.get_cell(e.coord)
			if c != null and c.is_opened:  # 虫进已开区才可被保安射杀（设计 §5）
				enemy_coords.append(e.coord)
	var locks: Array = []
	var webs: Array = []
	var slimes: Array = []
	for coord in grid.cells:
		var c = grid.cells[coord]
		if c.is_locked:
			locks.append(coord)
		if c.is_webbed:
			webs.append(coord)
		if c.is_slimed:
			slimes.append(coord)
	for group in [["enemy", enemy_coords], ["lock", locks], ["web", webs], ["slime", slimes]]:
		if group[1].is_empty():
			continue
		var found := Pathfinding.find_nearest_target(grid, coord, group[1], {}, self)
		if found.is_empty():
			continue  # 该类无可达目标 → 降级下一优先级
		_target_kind = group[0]
		_target_coord = found.target
		if group[0] == "enemy":
			for e in em.enemies:
				if e.is_alive() and e.coord == found.target:
					_target_enemy = e
					break
		_fire_timer = 0.0
		return


## 巡逻：无任何目标时随机走相邻已开格（不触发空闲警告）
func _patrol(grid) -> void:
	var options: Array = []
	for o in Pathfinding.MOVE_OFFSETS:
		var n: Vector2i = coord + o
		if grid.is_walkable(n):
			options.append(n)
	if options.is_empty():
		return
	options.shuffle()
	_move_to(options[0], grid)
	coord = options[0]
	_state = "moving"


## 开火：一枪一个 → 虫 die("robot_guard") / 障碍 clear_*（by_actor="robot_guard" 埋点口径）
func _fire(grid) -> void:
	if _target_kind == "enemy":
		if _target_enemy != null and _target_enemy.is_alive():
			var em: EnemyManager = get_node("/root/Main/EnemyManager")
			em.kill_enemy(_target_enemy, "robot_guard")
	else:
		var cell = grid.get_cell(_target_coord)
		if cell != null:
			if _target_kind == "lock":
				cell.clear_lock("robot_guard")
			elif _target_kind == "web":
				cell.clear_web("robot_guard")
			elif _target_kind == "slime":
				cell.clear_slime("robot_guard")
	_play_action_pulse()
	_clear_target()


func _clear_target() -> void:
	_target_kind = ""
	_target_coord = Vector2i(-1, -1)
	_target_enemy = null
	_fire_timer = 0.0
