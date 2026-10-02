class_name EnemyManager
extends Node2D
## L4 敌虫系统总控（设计 §9.1/§9.3/§9.8 前半）：波次调度 + 巢/虫生命周期 + 预置虫害放置
## 由 main._process 在 game_active 时驱动（pause/结算天然停摆）；
## 波次计时用自身累计（只被 game_active 驱动 → 天然从放基地起算）

const ENEMY_SCENE := preload("res://scenes/Enemy.tscn")
const NEST_SCENE := preload("res://scenes/Nest.tscn")

# 波次常量（初值，盲测校准项，设计 §10）
const WAVES := [
	{"t": 35.0, "type": "web"},    # 织网虫
	{"t": 75.0, "type": "lock"},   # 锁匠虫
	{"t": 110.0, "type": "slow"},  # 减速虫
]
const ENEMY_MOVE_SEC := 2.0   # 虫速 ~2s/格
const HARM_INTERVAL := 8.0    # 途中每 ~8s 施害 1 次
const NEST_HP := 2            # 巢 HP：玩家点击 2 次（各吃 1 CD）摧毁
const PRESET_WEBS := 3        # 预置网：盖已开数字（保安开局即有活）
const PRESET_LOCKS := 3       # 预置锁：锁 frontier 关闭格

signal enemy_spawned(enemy: Enemy)   # 剧本 #3「首虫出场后」的触发源
signal nest_damaged(nest: Nest)      # 剧本 #2「巢被点第一下」的触发源
signal nest_destroyed(nest: Nest)    # 结算「除巢数」
signal enemy_killed(enemy: Enemy, by_actor: String)  # 击杀埋点（点杀/保安分列）

var enemies: Array = []   # Array[Enemy]
var nests: Array = []     # Array[Nest]

## 波次开关：L4 true（三虫波次表）；L5 Boss 关 false——史莱姆由 BossManager 调度
## spawn_enemy 出虫，不走波次表（实施计划 §1.2 缺口：WAVES 是 L4 专属常量）
var waves_enabled := true

var _wave_idx := 0
var _elapsed := 0.0


## 进关时调用（放基地前即可见，剧本 #0）：裂缝×2 + 预置网×3 + 预置锁×3
func setup_board(grid) -> void:
	if not waves_enabled:
		return  # L5：无巢无预置虫害，纯 Boss 招式驱动
	_spawn_nests(grid)
	_place_preset_hazards(grid)


## 波次与虫/巢计时推进（main._process 驱动，game_active 才调用）
func tick(delta: float, grid) -> void:
	_elapsed += delta
	# 波次到点 → 从随机存活巢出虫；巢已全毁 → 该波取消（index 照常推进）
	if waves_enabled:
		while _wave_idx < WAVES.size() and _elapsed >= float(WAVES[_wave_idx].t):
			var wave: Dictionary = WAVES[_wave_idx]
			_wave_idx += 1
			var alive := _alive_nests()
			if alive.is_empty():
				continue  # 双巢皆除 = 再无新虫（设计 §5）
			alive.shuffle()
			spawn_enemy(alive[0].coord, String(wave.type), grid)
	# 虫推进（每 tick 重算最近基地：玩家中途放新基地可改变虫的奔袭目标）
	for e in enemies.duplicate():
		var target = GameState.get_nearest_base(e.coord)
		if target == null:
			continue
		e.tick(delta, grid, target)


func spawn_enemy(start_coord: Vector2i, type: String, grid) -> Enemy:
	var e: Enemy = ENEMY_SCENE.instantiate()
	add_child(e)
	e.setup(start_coord, type, grid)
	enemies.append(e)
	e.died.connect(_on_enemy_died)
	enemy_spawned.emit(e)
	return e


## L5 史莱姆出厂（BossManager 调度；走统一 spawn 通道，保安/点杀链自动兼容）
func spawn_slime(at: Vector2i, grid) -> Enemy:
	return spawn_enemy(at, "slime", grid)


func count_alive_type(type: String) -> int:
	var n := 0
	for e in enemies:
		if e.is_alive() and e.enemy_type == type:
			n += 1
	return n


## 玩家点杀 / 保安击杀入口：由 main._try_hit_enemy_at 与 GuardRobot 调用
func kill_enemy(e: Enemy, by_actor: String) -> void:
	e.die(by_actor)


func clear() -> void:
	for e in enemies:
		e.queue_free()
	enemies.clear()
	for n in nests:
		n.queue_free()
	nests.clear()
	_wave_idx = 0
	_elapsed = 0.0
	waves_enabled = true  # 恢复默认（L4）；L5 进关时再关（实施计划 §5-2 回归点）


## 棋盘重排（F11/改分辨率，P1-04 配套）后按缓存 coord 重写虫/巢世界坐标；
## 移动途中的 tween 由下一次 tick 校正
func reproject_all(grid) -> void:
	for e in enemies:
		if is_instance_valid(e):
			e.position = grid.coord_to_world(e.coord)
	for n in nests:
		if is_instance_valid(n):
			n.position = grid.coord_to_world(n.coord)


func _on_enemy_died(e: Enemy, by_actor: String) -> void:
	enemies.erase(e)
	if by_actor == "player":
		GameState.result_stats["enemy_kills_player"] += 1
	elif by_actor == "robot_guard":
		GameState.result_stats["enemy_kills_guard"] += 1
	if e.enemy_type == "slime":
		# L5 史莱姆击杀奖励（设计 §5.1，点杀/保安同酬）；Boss 硬直由 main 接 enemy_killed 转发
		GameState.add_money(10)
		GameState.add_score(10, "combat")
		GameState.result_stats["slime_kills"] += 1
	enemy_killed.emit(e, by_actor)


# ---- 布置 ----

## 盘边随机两条不同边各放 1 巢（避开盘角；裂缝开局可见）
func _spawn_nests(grid) -> void:
	var sides := ["top", "bottom", "left", "right"]
	sides.shuffle()
	for i in range(2):
		var coord := _random_edge_coord(sides[i], grid)
		var nest: Nest = NEST_SCENE.instantiate()
		add_child(nest)
		nest.setup(coord, NEST_HP, grid)
		nests.append(nest)
		nest.damaged.connect(func(n): nest_damaged.emit(n))
		nest.destroyed.connect(_on_nest_destroyed)


func _random_edge_coord(side: String, grid) -> Vector2i:
	# 避开盘角（角上巢到两条边的基地都太近）：取边上去掉两端的一格
	match side:
		"top":
			return Vector2i(randi_range(1, grid.cols - 2), 0)
		"bottom":
			return Vector2i(randi_range(1, grid.cols - 2), grid.rows - 1)
		"left":
			return Vector2i(0, randi_range(1, grid.rows - 2))
		_:
			return Vector2i(grid.cols - 1, randi_range(1, grid.rows - 2))


## 预置虫害：网盖随机已开数字格；锁随机 frontier 关闭格（预开区 8 邻中的未开格）
func _place_preset_hazards(grid) -> void:
	var opened_digits: Array = []
	var frontier_closed: Array = []
	for coord in grid.cells:
		var c = grid.cells[coord]
		if c.is_opened and c.adjacent_mines > 0 and not c.is_base:
			opened_digits.append(c)
	for coord in grid.cells:
		var c = grid.cells[coord]
		if c.is_opened:
			for n in grid.get_neighbors(coord):
				if not n.is_opened and not n.is_flagged and not n.is_mine:
					frontier_closed.append(n)
					break  # 每个已开格至多贡献一个 frontier 格，分散分布
	# 打乱后逐个放置（apply 幂等失败自动顺延到下一个候选）
	opened_digits.shuffle()
	var webs := 0
	for c in opened_digits:
		if webs >= PRESET_WEBS:
			break
		if c.apply_web():
			webs += 1
	frontier_closed.shuffle()
	var locks := 0
	for c in frontier_closed:
		if locks >= PRESET_LOCKS:
			break
		if c.apply_lock():
			locks += 1


func _on_nest_destroyed(nest: Nest) -> void:
	nests.erase(nest)
	nest_destroyed.emit(nest)
	GameState.result_stats["nests_destroyed"] += 1
	if float(GameState.result_stats.get("nest_cleared_elapsed", -1.0)) < 0.0:
		GameState.result_stats["nest_cleared_elapsed"] = snappedf(GameState.elapsed, 0.1)


func _alive_nests() -> Array:
	var result: Array = []
	for n in nests:
		if n.is_alive():
			result.append(n)
	return result
