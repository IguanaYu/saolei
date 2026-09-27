extends Node
## 全局状态单例 + 信号总线
## 所有跨模块的状态变化都通过这里中转

# ---- 公开状态 ----
var money: int = 100
var score: int = 0
var lives: int = 3
var time_left: float = 90.0
var game_active: bool = false
var elapsed: float = 0.0            # 本局实际用时（无时限关的用时口径）
var time_limit_cfg: float = 90.0    # 关卡配置原始值（<=0 = 无时限）
var lives_cfg: int = 3              # 关卡配置原始值（<=0 = 无命限制）

# 游戏阶段：placing_base=等玩家放第一个基地 / playing=正常游戏
var game_phase: String = "placing_base"

# 升级等级（opener/marker 双轨：移动+工作；detector/miner 单间隔；折扣轨 0-2）
var opener_move_level: int = 0
var opener_work_level: int = 0
var marker_move_level: int = 0
var marker_work_level: int = 0
var detector_speed_level: int = 0
var miner_speed_level: int = 0
var discount_level: int = 0

# 继续挑战模式（胜利结算后回盘面：倒计时冻结/加分锁定/免命/分数累加）
var continue_mode: bool = false

# 升级轨默认配置（关卡可用 LevelData 覆盖速度轨；折扣轨砍出试玩版，仅余价格）
const DEFAULT_SPEED_PRICES := [50, 70, 100]
const DEFAULT_SPEED_LEVELS := [2.0, 1.6, 1.3, 1.0]
const DISCOUNT_PRICES := [200, 500]

# 已购买机器人计数（用于价格递增）
var opener_count: int = 0
var marker_count: int = 0
var detector_count: int = 0
var miner_count: int = 0
var guard_count: int = 0

# 建筑状态
var bases: Array[Vector2i] = []
var base_count: int = 0

# 全局锁定目标集合（Vector2i → Robot 实例）
var locked_targets: Dictionary = {}

# ---- 关卡模式（P13）----
var current_level_id: String = ""           # "" = 自由/兼容模式
var current_objective: ObjectiveData = null
var current_level_override: LevelData = null  # 每日挑战等动态关卡（不走 LevelSystem）
var daily_mode: bool = false                  # 本局是每日挑战

# ---- 玩家操作 CD（教学关：玩家点击=一次性机器人，次数有限）----
var cd_phase: String = "off"        # off / free(免费阶段) / cooldown(次数耗尽)
var cd_free_clicks_left: int = 0    # 免费动作余量
var cd_flag_limit: int = 0          # 免费阶段正确旗上限（0 = 不按旗计）
var cd_correct_flags: int = 0       # 免费阶段已插正确旗数
var cd_sec: float = 0.0             # 耗尽后单次 CD 时长
var cd_after_purchase: float = -1.0 # >=0：首台机器人购买后 CD 改为此值
var cd_duration: float = 0.0        # 当前生效的单次 CD（首购后变短）
var cd_remaining: float = 0.0       # 距下次可用
var cd_purchase_boosted: bool = false
var player_actions_used: int = 0    # 本局玩家有效动作总数（埋点口径，动作级）

# ---- 结算统计（开格分/标旗分/人机操作占比，reset_state 清零）----
var result_stats := {
	"open_score": 0, "flag_score": 0, "wrong_flags": 0,
	"player_ops": 0, "robot_ops": 0, "player_actions": 0,
	"time_bonus": 0, "time_bonus_secs": 0, "first_upgrade_elapsed": -1.0,
	# L4 除害关（敌人/探测，设计 §9.10）
	"nest_cleared_elapsed": -1.0,   # 首巢摧毁时点（-1=未除）
	"nests_destroyed": 0,           # 结算行「除巢数」
	"guard_bought_elapsed": -1.0,   # 保安购买时点（-1=未买）
	"probe_used": 0,                # 探测使用次数
	"probe_coords": "",             # 探测坐标串 "x,y;x,y"（埋点分析用）
	"enemy_kills_player": 0,        # 玩家点杀虫数
	"enemy_kills_guard": 0,         # 保安击杀虫数
	"obstacles_cleared_player": 0,  # 玩家清障数（锁/网/黏液）
	"obstacles_cleared_guard": 0,   # 保安清障数
	"stall_seconds": 0.0,           # 全场机器人停摆累计时长
	"slowed_seconds": 0.0,          # 机器人在黏液 3×3 内的累计时长
}

# 速度档位缓存（reset_state 时从关卡配置读入；机器人每 tick 热路径用）
var _move_levels_cache: Array = DEFAULT_SPEED_LEVELS.duplicate()
var _work_levels_cache: Array = []  # 空 = 本关无工作轨，工作间隔取移动表（L1/L2 手感不变）

# ---- 信号总线 ----
signal money_changed(new_value: int)
signal score_changed(new_value: int)
signal lives_changed(new_value: int)
signal time_changed(new_value: float)
signal game_over(result: String)  # "win" | "lose" | "timeout"
signal upgrade_changed(upgrade_id: String, new_level: int)
signal base_placed(coord: Vector2i)
signal game_phase_changed(phase: String)
signal tower_activated  # 预留：充能塔功能落地后 emit
signal objective_progress_updated(text: String)
signal robot_spawned(robot_type: String)
signal cd_exhausted()                          # 免费阶段 → 耗尽瞬间
signal cd_blocked()                            # CD 中点击被拦（UI 反馈）
signal cd_tick(remaining: float, duration: float)
signal cd_duration_changed(new_duration: float)  # 首购后 CD 变短
signal player_action_performed                 # 每次有效玩家动作（剧本推进用）


func has_time_limit() -> bool:
	return time_limit_cfg > 0.0


func has_life_limit() -> bool:
	return lives_cfg > 0


func add_money(amount: int) -> void:
	money = max(0, money + amount)
	money_changed.emit(money)


func add_score(amount: int) -> void:
	score = max(0, score + amount)
	score_changed.emit(score)


func lose_life() -> void:
	lives = max(0, lives - 1)
	lives_changed.emit(lives)


# ---- 玩家操作 CD ----

## CD 中点击是否被拦（免费阶段/off 永远放行）
func is_player_blocked() -> bool:
	return cd_phase == "cooldown" and cd_remaining > 0.0


## 有效玩家动作执行后计数（开格/翻旗/和弦/踩雷各 1 次，洪水整片算 1）
func consume_player_action() -> void:
	player_actions_used += 1
	result_stats["player_actions"] = player_actions_used
	player_action_performed.emit()
	if cd_phase == "free":
		cd_free_clicks_left -= 1
		if cd_free_clicks_left <= 0:
			_enter_cooldown()
	elif cd_phase == "cooldown":
		# 恢复好的次数被本次动作用掉，重新计时
		cd_remaining = cd_duration
		cd_tick.emit(cd_remaining, cd_duration)


## 免费阶段的正确旗计数（第 N 面正确旗触发耗尽，与点击数先到为准）
func notify_player_correct_flag() -> void:
	if cd_phase == "free" and cd_flag_limit > 0:
		cd_correct_flags += 1
		if cd_correct_flags >= cd_flag_limit:
			_enter_cooldown()


func _enter_cooldown() -> void:
	cd_phase = "cooldown"
	# 免费阶段就已首购过 → 耗尽后直接用短 CD（boost 不能被 30s 覆盖）
	if cd_purchase_boosted and cd_after_purchase >= 0.0:
		cd_duration = cd_after_purchase
	else:
		cd_duration = cd_sec
	cd_remaining = cd_duration
	cd_exhausted.emit()


## 每帧推进 CD（main._process 调用；暂停时由 get_tree().paused 天然停摆）
func tick_cd(delta: float) -> void:
	if cd_phase == "cooldown" and cd_remaining > 0.0:
		cd_remaining = maxf(0.0, cd_remaining - delta)
		cd_tick.emit(cd_remaining, cd_duration)


## 重置本局状态。level_id 为空串时走旧自由模式（兼容旧调用）
## override 用于动态生成的关卡（每日挑战）
func reset_state(level_id: String = "", override: LevelData = null) -> void:
	# 从存档读取起始加成
	var su = SaveSystem
	current_level_id = level_id
	current_objective = null
	current_level_override = override
	var lvl: LevelData = override if override != null \
			else (LevelSystem.get_level(level_id) if level_id != "" else null)
	if lvl != null:
		current_objective = lvl.objectives[0] if not lvl.objectives.is_empty() else null
		# meta_progression=false 的关（试玩 L1/L2）不吃局外加成，保证盲测冷启动确定
		var meta: bool = lvl.meta_progression
		money = lvl.start_gold + (50 * int(su.unlocks.get("start_money", 0)) if meta else 0)
		# 无命限制关（start_lives<=0）不吃局外加命，保持"无失败状态"承诺
		lives = 0 if lvl.start_lives <= 0 else lvl.start_lives + (int(su.unlocks.get("start_lives", 0)) if meta else 0)
		time_left = lvl.time_limit_sec
		time_limit_cfg = lvl.time_limit_sec
		lives_cfg = lvl.start_lives
	else:
		money = 100 + 50 * int(su.unlocks.get("start_money", 0))
		lives = 3 + int(su.unlocks.get("start_lives", 0))
		time_left = 90.0
		time_limit_cfg = 90.0
		lives_cfg = 3
	score = 0
	elapsed = 0.0
	game_active = false
	continue_mode = false
	game_phase = "placing_base"
	# 玩家操作 CD 初始化（cooldown_sec>0 才启用；免费阶段无 CD 概念）
	cd_phase = "free" if lvl != null and lvl.cooldown_sec > 0.0 else "off"
	cd_free_clicks_left = lvl.free_clicks if lvl != null else 0
	cd_flag_limit = lvl.free_correct_flags if lvl != null else 0
	cd_correct_flags = 0
	cd_sec = lvl.cooldown_sec if lvl != null else 0.0
	cd_after_purchase = lvl.cooldown_after_purchase if lvl != null else -1.0
	cd_duration = 0.0
	cd_remaining = 0.0
	cd_purchase_boosted = false
	player_actions_used = 0
	result_stats = {
		"open_score": 0, "flag_score": 0, "wrong_flags": 0,
		"player_ops": 0, "robot_ops": 0, "player_actions": 0,
		"time_bonus": 0, "time_bonus_secs": 0, "first_upgrade_elapsed": -1.0,
		"nest_cleared_elapsed": -1.0, "nests_destroyed": 0,
		"guard_bought_elapsed": -1.0, "probe_used": 0, "probe_coords": "",
		"enemy_kills_player": 0, "enemy_kills_guard": 0,
		"obstacles_cleared_player": 0, "obstacles_cleared_guard": 0,
		"stall_seconds": 0.0, "slowed_seconds": 0.0,
	}
	# 速度档位缓存（关卡可覆盖；买档越界时 get_move_interval 钳制）
	_move_levels_cache = (lvl.upgrade_speed_levels if lvl != null and not lvl.upgrade_speed_levels.is_empty()
			else DEFAULT_SPEED_LEVELS).duplicate()
	_work_levels_cache = (lvl.upgrade_work_levels.duplicate()
			if lvl != null and not lvl.upgrade_work_levels.is_empty() else [])
	# 局外速度加成：移动/工作分轨直送（meta=false 关跳过，盲测冷启动确定）
	var meta_spd: bool = lvl == null or lvl.meta_progression
	var gs_move: int = int(su.unlocks.get("global_speed", 0)) if meta_spd else 0
	var gs_work: int = int(su.unlocks.get("work_speed", 0)) if meta_spd else 0
	opener_move_level = gs_move
	marker_move_level = gs_move
	opener_work_level = gs_work
	marker_work_level = gs_work
	detector_speed_level = gs_move
	miner_speed_level = gs_move
	discount_level = 0
	opener_count = 0
	marker_count = 0
	detector_count = 0
	miner_count = 0
	guard_count = 0
	bases.clear()
	base_count = 0
	locked_targets.clear()
	money_changed.emit(money)
	score_changed.emit(score)
	lives_changed.emit(lives)
	time_changed.emit(time_left)
	game_phase_changed.emit(game_phase)


## 当前关是否允许使用某机器人（allowed_modules 为空 = 全部允许）
func is_module_allowed(robot_type: String) -> bool:
	if current_level_id == "":
		return true
	var lvl: LevelData = LevelSystem.get_level(current_level_id)
	if lvl == null or lvl.allowed_modules.is_empty():
		return true
	return lvl.allowed_modules.has(robot_type)


## 当前关是否禁用某操作（如 "flag" 禁标雷）
func is_action_forbidden(action: String) -> bool:
	if current_level_id == "":
		return false
	var lvl: LevelData = LevelSystem.get_level(current_level_id)
	if lvl == null:
		return false
	return lvl.forbidden_actions.has(action)


func get_current_level() -> LevelData:
	if current_level_override != null:
		return current_level_override
	return LevelSystem.get_level(current_level_id) if current_level_id != "" else null


# ---- 基地 ----

func get_base_price() -> int:
	# 关卡平价（base_price_flat>0）优先；否则第 1 个 80，第 2 个 160...（base × 2^N）
	var lvl := get_current_level()
	if lvl != null and lvl.base_price_flat > 0:
		return lvl.base_price_flat
	return 80 * (1 << base_count)


func purchase_base() -> bool:
	var price: int = get_base_price()
	if money < price:
		return false
	add_money(-price)
	return true


func register_base(coord: Vector2i) -> void:
	if bases.has(coord):
		return
	bases.append(coord)
	base_count += 1
	base_placed.emit(coord)


## 返回离指定坐标最近的基地，没有则返回 null
func get_nearest_base(coord: Vector2i):
	if bases.is_empty():
		return null
	var nearest = bases[0]
	var best_dist: int = abs(coord.x - nearest.x) + abs(coord.y - nearest.y)
	for b in bases:
		var d: int = abs(coord.x - b.x) + abs(coord.y - b.y)
		if d < best_dist:
			best_dist = d
			nearest = b
	return nearest


func set_game_phase(phase: String) -> void:
	if game_phase == phase:
		return
	game_phase = phase
	game_phase_changed.emit(phase)


func get_robot_price(robot_type: String) -> int:
	var count: int = 0
	var base: int = 50
	match robot_type:
		"opener": count = opener_count; base = 50
		"marker": count = marker_count; base = 50
		"detector": count = detector_count; base = 80
		"miner": count = miner_count; base = 60
		"guard": count = guard_count; base = 80  # L4 保安：限购 1 下无翻倍问题
	base *= 1 << count
	var discount: float = [1.0, 0.75, 0.5][discount_level]
	return int(base * discount)


func get_robot_purchased_count(robot_type: String) -> int:
	match robot_type:
		"opener": return opener_count
		"marker": return marker_count
		"detector": return detector_count
		"miner": return miner_count
		"guard": return guard_count
	return 0


func purchase_robot(robot_type: String) -> bool:
	var price: int = get_robot_price(robot_type)
	if money < price:
		return false
	add_money(-price)
	match robot_type:
		"opener": opener_count += 1
		"marker": marker_count += 1
		"detector": detector_count += 1
		"miner": miner_count += 1
		"guard": guard_count += 1
	# 首购恢复 CD（教学关：30s → 3s，立刻恢复一次次数）
	if cd_phase != "off" and cd_after_purchase >= 0.0 and not cd_purchase_boosted:
		cd_purchase_boosted = true
		cd_duration = cd_after_purchase
		cd_remaining = 0.0
		cd_duration_changed.emit(cd_duration)
	return true


## 开局赠送机器人：计数+1 抬升价格阶梯，但不扣钱、不触发首购 CD 恢复
func gift_robot(robot_type: String) -> void:
	match robot_type:
		"opener": opener_count += 1
		"marker": marker_count += 1
		"detector": detector_count += 1
		"miner": miner_count += 1
		"guard": guard_count += 1


## 移动间隔（opener/marker 走移动轨等级；detector/miner 单间隔同表）
func get_move_interval(robot_type: String) -> float:
	var level: int = 0
	match robot_type:
		"opener": level = opener_move_level
		"marker": level = marker_move_level
		"detector": level = detector_speed_level
		"miner": level = miner_speed_level
	level = mini(level, _move_levels_cache.size() - 1)
	return float(_move_levels_cache[level])


## 工作间隔（邻接连作节奏）。工作表为空 = 本关无工作轨 → 取移动表（L1/L2 手感不变）
func get_work_interval(robot_type: String) -> float:
	if _work_levels_cache.is_empty() or not (robot_type == "opener" or robot_type == "marker"):
		return get_move_interval(robot_type)
	var level: int = opener_work_level if robot_type == "opener" else marker_work_level
	level = mini(level, _work_levels_cache.size() - 1)
	return float(_work_levels_cache[level])


## 兼容旧口径（detector/miner 单间隔）
func get_speed_interval(robot_type: String) -> float:
	return get_move_interval(robot_type)


# ---- 局内升级 ----

func get_speed_levels() -> Array:
	var lvl := get_current_level()
	if lvl != null and not lvl.upgrade_speed_levels.is_empty():
		return lvl.upgrade_speed_levels
	return DEFAULT_SPEED_LEVELS


func get_work_levels() -> Array:
	var lvl := get_current_level()
	if lvl != null and not lvl.upgrade_work_levels.is_empty():
		return lvl.upgrade_work_levels
	return get_speed_levels()  # 无工作轨的关，展示层用移动表兜底


## 面板显示用档位表（工作轨显示工作表）
func get_upgrade_levels_table(upgrade_id: String) -> Array:
	if upgrade_id.ends_with("_work"):
		return get_work_levels()
	return get_speed_levels()


func get_speed_prices() -> Array:
	var lvl := get_current_level()
	if lvl != null and not lvl.upgrade_speed_prices.is_empty():
		return lvl.upgrade_speed_prices
	return DEFAULT_SPEED_PRICES


func get_upgrade_prices(upgrade_id: String) -> Array:
	if upgrade_id == "discount":
		return DISCOUNT_PRICES
	return get_speed_prices()


func get_upgrade_level(upgrade_id: String) -> int:
	match upgrade_id:
		"opener_speed": return opener_move_level
		"opener_move": return opener_move_level
		"opener_work": return opener_work_level
		"marker_speed": return marker_move_level
		"marker_move": return marker_move_level
		"marker_work": return marker_work_level
		"discount": return discount_level
	return 0


func set_upgrade_level(upgrade_id: String, lvl: int) -> void:
	match upgrade_id:
		# 通用速度轨（L1/L2）：移动+工作同步——单 tick 时代的手感完全保留
		"opener_speed":
			opener_move_level = lvl
			opener_work_level = lvl
		"marker_speed":
			marker_move_level = lvl
			marker_work_level = lvl
		"opener_move": opener_move_level = lvl
		"opener_work": opener_work_level = lvl
		"marker_move": marker_move_level = lvl
		"marker_work": marker_work_level = lvl
		"discount": discount_level = lvl


## 购买一档升级（面板只调用此入口；价格/满级由关卡配置决定）
func purchase_upgrade(upgrade_id: String) -> bool:
	var cur: int = get_upgrade_level(upgrade_id)
	var prices: Array = get_upgrade_prices(upgrade_id)
	if cur >= prices.size():
		return false
	var price: int = prices[cur]
	if price < 0 or money < price:
		return false
	add_money(-price)
	set_upgrade_level(upgrade_id, cur + 1)
	if float(result_stats.get("first_upgrade_elapsed", -1.0)) < 0.0:
		result_stats["first_upgrade_elapsed"] = snappedf(elapsed, 0.1)
	upgrade_changed.emit(upgrade_id, cur + 1)
	return true
