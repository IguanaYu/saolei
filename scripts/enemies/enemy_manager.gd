class_name EnemyManager
extends Node2D
## L4 敌虫系统总控（设计 §9.1/§9.3/§9.8 前半）：波次调度 + 巢/虫生命周期 + 预置虫害放置
## 由 main._process 在 game_active 时驱动（pause/结算天然停摆）；
## 波次计时用自身累计（只被 game_active 驱动 → 天然从放基地起算）

# 场景路径 + 用时 load：本节点常驻主场景，preload 会把虫/巢贴图链拉进开机加载
const ENEMY_SCENE_PATH := "res://scenes/Enemy.tscn"
const NEST_SCENE_PATH := "res://scenes/Nest.tscn"

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
const CLICK_REFRESH_SEC := 0.5  # 可达性视觉刷新节流（领土随开格变化 ≤0.5s 反应）

# ---- 2-2 筑墙工（总纲 §7；与 L4 三虫波次表独立调度）----
const BUILDER_SCENE_PATH := "res://scenes/Builder.tscn"
const BUILDER_FIRST_AT := 12.0   # 有效游玩 12s 首只
const BUILDER_INTERVAL := 25.0   # 此后每 25s 尝试补 1 只
const BUILDER_MAX_ALIVE := 2
const BUILDER_WALL_SEQUENCE := [1]  # 2-2 新墙恒 1 层（2-3 起按关覆写 [1,1,3]）

signal enemy_spawned(enemy: Enemy)   # 剧本 #3「首虫出场后」的触发源
signal nest_damaged(nest: Nest)      # 剧本 #2「巢被点第一下」的触发源
signal nest_destroyed(nest: Nest)    # 结算「除巢数」
signal enemy_killed(enemy: Enemy, by_actor: String)  # 击杀埋点（点杀/保安分列）
signal builder_now(b)        # 2-2：筑墙工开始出场（裂隙亮起时；director 预警句挂点）
signal builder_hurt(b)       # 2-2：筑墙工首次受击（director「激光也能击破敌人」挂点）

var enemies: Array = []   # Array[Enemy]
var nests: Array = []     # Array[Nest]

## 波次开关：L4 true（三虫波次表）；L5 Boss 关 false——史莱姆由 BossManager 调度
## spawn_enemy 出虫，不走波次表（实施计划 §1.2 缺口：WAVES 是 L4 专属常量）
var waves_enabled := true

var _wave_idx := 0
var _elapsed := 0.0
var _click_refresh_timer := 0.0
var builders_enabled := false      # LevelData.builders（ch02 s02+ 开）
var builder_wall_sequence: Array = []  # 空取 BUILDER_WALL_SEQUENCE 默认
var _builder_spawned := 0
var builders: Array = []           # Array[BuilderEnemy]（enemies 数组之外单独跟踪）


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
	# 2-2 筑墙工调度：12s 首只 → 每 25s 补 → 场上 ≤2；裂隙预警在 Builder 内部编排
	if builders_enabled:
		var interval_seq: Array = builder_wall_sequence if not builder_wall_sequence.is_empty() 				else BUILDER_WALL_SEQUENCE
		if _elapsed >= BUILDER_FIRST_AT 				and _builder_spawned == 0:
			_spawn_builder(grid, interval_seq)
		elif _builder_spawned > 0 				and _elapsed >= BUILDER_FIRST_AT + BUILDER_INTERVAL * _builder_spawned:
			if _alive_builders() < BUILDER_MAX_ALIVE:
				_spawn_builder(grid, interval_seq)
			else:
				_builder_spawned += 1  # 满员也推进序号，避免每帧重试
		for b in builders.duplicate():
			if is_instance_valid(b):
				b.tick(delta, grid, Vector2i.ZERO)
	# 虫推进（每 tick 重算最近基地：玩家中途放新基地可改变虫的奔袭目标）
	for e in enemies.duplicate():
		var target = GameState.get_nearest_base(e.coord)
		if target == null:
			continue
		e.tick(delta, grid, target)
	# 可达性视觉节流刷新（领土随开格/放基地变化；点击判定走 is_clickable 实时算，不受节流影响）
	_click_refresh_timer += delta
	if _click_refresh_timer >= CLICK_REFRESH_SEC:
		_click_refresh_timer = 0.0
		refresh_click_visuals(grid)


## 统一刷新虫/巢的「开路接近」压暗视觉：领土集合只洪泛一次，全体共享
func refresh_click_visuals(grid) -> void:
	var territory: Dictionary = grid.player_territory()
	for e in enemies:
		if is_instance_valid(e):
			e.refresh_clickable_visual(grid, territory)
	for n in nests:
		if is_instance_valid(n):
			n.refresh_clickable_visual(grid, territory)


func spawn_enemy(start_coord: Vector2i, type: String, grid) -> Enemy:
	var e: Enemy = load(ENEMY_SCENE_PATH).instantiate()
	add_child(e)
	e.setup(start_coord, type, grid)
	enemies.append(e)
	e.died.connect(_on_enemy_died)
	enemy_spawned.emit(e)
	return e


## L5 史莱姆出厂（BossManager 调度；走统一 spawn 通道，保安/点杀链自动兼容）
func spawn_slime(at: Vector2i, grid) -> Enemy:
	return spawn_enemy(at, "slime", grid)


## 2-2 筑墙工出厂：已开区边缘随机位 + 裂隙预警 2s；不进 enemies（三虫波次/点杀链不认它）
func _spawn_builder(grid, sequence: Array) -> void:
	_builder_spawned += 1
	var edge: Vector2i = _builder_edge_coord(grid)
	var b: BuilderEnemy = load(BUILDER_SCENE_PATH).instantiate()
	add_child(b)
	b.coord = edge
	b.position = grid.coord_to_world(edge)
	b.spawn_with_rift(edge, grid, sequence)
	builders.append(b)
	b.died.connect(_on_builder_died)
	b.builder_damaged.connect(func(_bb): builder_hurt.emit(_bb))
	builder_now.emit(b)


func _builder_edge_coord(grid) -> Vector2i:
	# 已开区边缘：随机挑一个「邻接未开格」的已开格（靠近玩家生产区，设计 §3）
	var edges: Array = []
	for c in grid.cells:
		var cell: Cell = grid.cells[c]
		if not cell.is_opened or cell.is_base or cell.cover_wall_hp > 0:
			continue
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + o
			if grid.cells.has(n) and not grid.cells[n].is_opened:
				edges.append(c)
				break
	if edges.is_empty():
		return GameState.bases[0] if not GameState.bases.is_empty() else Vector2i.ZERO
	edges.shuffle()
	return edges[0]


func _alive_builders() -> int:
	var n := 0
	for b in builders:
		if is_instance_valid(b) and b.is_alive():
			n += 1
	return n


## 统一伤害入口（玩家激光/护卫共用）：普通虫 1 血即死；筑墙工 2 血走 take_hit
func damage_enemy(e: Enemy, by_actor: String, dmg: int = 1) -> void:
	if e is BuilderEnemy:
		(e as BuilderEnemy).take_hit(by_actor)
		return
	e.die(by_actor)  # kill_enemy 兼容别名保留给旧调用


func _on_builder_died(b: BuilderEnemy, by_actor: String) -> void:
	builders.erase(b)
	# 击破奖励（设计 §8.1：+10 分 +5 金；玩家/护卫同酬）
	GameState.add_score(10, "combat")
	GameState.add_money(5, "guard_combat" if by_actor == "robot_guard" else "player_combat")
	if by_actor == "player_laser":
		GameState.result_stats["enemy_kills_player"] += 1
	elif by_actor == "robot_guard":
		GameState.result_stats["enemy_kills_guard"] += 1
	GameState.result_stats["builders_killed"] += 1
	GameState.game_event_logged.emit("击破 筑墙工 +10分", "player", "good")


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
	for b in builders:
		if is_instance_valid(b):
			b.queue_free()
	builders.clear()
	_wave_idx = 0
	_elapsed = 0.0
	_click_refresh_timer = 0.0
	_builder_spawned = 0
	builders_enabled = false
	builder_wall_sequence = []
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
		GameState.add_money(10, "guard_combat" if by_actor == "robot_guard" else "player_combat")
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
		# 化石不落在盘边是数据约束，这里仍兜底重摇（巢长在化石上=视觉穿模）
		for _attempt in 10:
			if grid.cells.has(coord) and not grid.cells[coord].is_fossil:
				break
			coord = _random_edge_coord(sides[i], grid)
		var nest: Nest = load(NEST_SCENE_PATH).instantiate()
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
				if not n.is_opened and not n.is_flagged and not n.is_mine \
						and not n.is_fossil:  # 化石格叠锁永远清不掉，不发锁
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
