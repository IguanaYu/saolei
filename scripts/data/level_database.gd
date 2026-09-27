class_name LevelDatabase
extends RefCounted
## 代码生成 12 章 × 5 关 = 60 个 LevelData（不用 .tres，数值迭代改一行即可）

const CELLS := 16 * 16
const MAX_DENSITY := 0.16  # 雷密度上限，超过会变成猜雷（体验崩坏）

const CHAPTER_DENSITY := [0.10, 0.125, 0.13, 0.135, 0.14, 0.145, 0.15, 0.155, 0.16, 0.16, 0.16, 0.16]
const CHAPTER_MODULE := ["opener_marker", "detector", "miner", "tower", "drone", "", "", "", "", "", "", ""]
const CHAPTER_NAMES := ["新手村", "矿脉谷", "产业链", "充能塔", "硬关峰", "综合境", "进阶域", "深度区", "深渊层", "永恒殿", "终末境", "赛季终"]
# 章内 5 关"舒适度"乘子（spike-valley 模板）：越高越简单
# 关1 爽 → 关2 顺 → 关3 Spike 卡关 → 关4 Valley 碾压 → 关5 Boss 难度尖峰
const WITHIN_EASE := [1.20, 1.00, 0.85, 1.05, 0.65]

const CHAPTER_COLORS := [
	Color(0.40, 0.62, 0.40),
	Color(0.55, 0.55, 0.75),
	Color(0.72, 0.60, 0.38),
	Color(0.40, 0.65, 0.70),
	Color(0.75, 0.42, 0.42),
	Color(0.60, 0.45, 0.72),
	Color(0.45, 0.72, 0.60),
	Color(0.70, 0.55, 0.35),
	Color(0.45, 0.45, 0.72),
	Color(0.72, 0.72, 0.40),
	Color(0.55, 0.40, 0.60),
	Color(0.75, 0.55, 0.30),
]

var chapters: Array = []      # Array[ChapterData]
var levels: Dictionary = {}   # id -> LevelData


func _init() -> void:
	_build()


func _build() -> void:
	for ch_idx in range(CHAPTER_NAMES.size()):
		var ch := ChapterData.new()
		ch.id = "ch%02d" % (ch_idx + 1)
		ch.display_name = CHAPTER_NAMES[ch_idx]
		ch.unlock_module = CHAPTER_MODULE[ch_idx]
		ch.theme_color = CHAPTER_COLORS[ch_idx]
		for s_idx in range(5):
			var lvl := _make_level(ch_idx, s_idx)
			if ch_idx == 0 and s_idx == 0:
				_apply_playtest_level1(lvl)
			elif ch_idx == 0 and s_idx == 1:
				_apply_playtest_level2(lvl)
			elif ch_idx == 0 and s_idx == 2:
				_apply_playtest_level3(lvl)
			ch.level_ids.append(lvl.id)
			levels[lvl.id] = lvl
		chapters.append(ch)


## 外部试玩版第一关（教学关）：固定地图 + 无时限无命 + 全局 CD + 商店限购
## 设计文档：docs/active/试玩版内容/第一关-设计文档.md
func _apply_playtest_level1(lvl: LevelData) -> void:
	lvl.grid_size = Vector2i(10, 10)
	lvl.mine_count = 10
	lvl.time_limit_sec = -1.0   # 无时限
	lvl.start_gold = 75         # 原则：免费阶段收入 + 75，耗尽时刻恰好够买 opener+marker（100）
	lvl.start_lives = 0         # 无命限制
	lvl.free_clicks = 8         # 免费阶段：第 8 次有效动作耗尽
	lvl.free_correct_flags = 5  # 或第 5 面正确旗耗尽（先到为准）
	lvl.cooldown_sec = 30.0
	lvl.cooldown_after_purchase = 3.0
	lvl.shop_limits = {"opener": 1, "marker": 1}
	lvl.shop_hidden = ["base", "drone", "upgrade", "debug"]
	lvl.no_stars = true
	lvl.is_playtest = true
	lvl.fixed_mines.assign(FixedBoards.L1.mines)
	lvl.fixed_base = FixedBoards.L1.base
	lvl.preopen_coords.assign(FixedBoards.L1.preopen)


## 外部试玩版第二关（升级关）：时限/命/升级考题首登场
## 设计文档：docs/active/试玩版内容/第二关-设计文档.md（v1.2）
func _apply_playtest_level2(lvl: LevelData) -> void:
	lvl.grid_size = Vector2i(14, 14)
	lvl.mine_count = 24
	var obj := ObjectiveData.new()  # s_idx==1 默认生成 FLAG_N_MINES，必须覆写回清空
	obj.type = ObjectiveData.Type.CLEAR_ALL_SAFE
	lvl.objectives = [obj]
	lvl.time_limit_sec = 90.0
	lvl.start_gold = 100        # = 双轨 Lv1（50+50）；一对机器人开局赠送（升级引导优先）
	lvl.start_lives = 3
	lvl.start_robots = {"opener": 1, "marker": 1}
	lvl.free_clicks = 5         # 开局 5 次免 CD（纯次数口径，不按旗计）
	lvl.free_correct_flags = 0
	lvl.cooldown_sec = 3.0
	lvl.cooldown_after_purchase = -1.0  # 无"首购恢复"概念，开局即 3s
	lvl.shop_limits = {}
	lvl.shop_hidden = ["base", "detector", "miner", "drone", "debug"]
	lvl.upgrades_hidden = ["discount"]
	lvl.upgrade_speed_prices = [50, 70, 100]
	lvl.upgrade_speed_levels = [2.0, 1.6, 1.3, 1.0]
	lvl.base_price_flat = 80    # 预设 1 基地后第 2 个仍 80（设计 §3），不走翻倍
	lvl.time_bonus_per_sec = 3
	lvl.allowed_modules = ["opener", "marker"]
	lvl.no_stars = true
	lvl.is_playtest = true
	lvl.meta_progression = false  # 盲测冷启动确定，不吃局外加成
	lvl.fixed_mines.assign(FixedBoards.L2.mines)
	lvl.fixed_base = FixedBoards.L2.base
	lvl.preopen_coords.assign(FixedBoards.L2.preopen)


## 外部试玩版第三关（局外成长关·积分目标）：大盘 + 过线即胜 + 继续挑战 + 局外效果进场即见
## 设计文档：docs/active/试玩版内容/第三关-设计文档.md（v1.2）
func _apply_playtest_level3(lvl: LevelData) -> void:
	lvl.grid_size = Vector2i(16, 16)
	lvl.mine_count = 40
	var obj := ObjectiveData.new()  # s_idx==2 默认生成 REACH_SCORE target=40，必须覆写为 300
	obj.type = ObjectiveData.Type.REACH_SCORE
	obj.target_value = 300
	lvl.objectives = [obj]
	lvl.time_limit_sec = 120.0
	lvl.start_gold = 300        # 再叠局外起始金币（meta_progression=true）
	lvl.start_lives = 3
	lvl.free_clicks = 5         # 同 L2：开局 5 次免 CD，用完 3s/次
	lvl.free_correct_flags = 0
	lvl.cooldown_sec = 3.0
	lvl.cooldown_after_purchase = -1.0
	lvl.shop_limits = {}
	lvl.shop_hidden = ["detector", "miner", "drone", "debug"]  # 基地可买（80 平价）
	lvl.upgrades_hidden = ["discount"]                          # 折扣轨砍出试玩版
	lvl.upgrade_speed_prices = [50, 70, 100]
	lvl.upgrade_speed_levels = [2.0, 1.6, 1.3, 1.0]
	lvl.upgrade_work_levels = [2.0, 1.6, 1.3, 1.0]
	lvl.upgrade_tracks = ["opener_move", "opener_work", "marker_move", "marker_work"]
	lvl.base_price_flat = 80
	lvl.time_bonus_per_sec = 3
	lvl.meta_progression = true   # 本关吃全部局外加成（教学：矿石变强进场即见）
	lvl.preopen_scores = true     # 预开格进关即 +1 分/格（只计分不计钱，设计 v1.2）
	lvl.allow_continue = true     # 过线结算后可「继续挑战」（倒计时冻结/免命/分数累加）
	lvl.first_clear_reward = RewardData.new()
	lvl.first_clear_reward.ore = 200
	lvl.repeat_reward = RewardData.new()
	lvl.repeat_reward.ore = 50
	lvl.allowed_modules = ["opener", "marker"]
	lvl.no_stars = true
	lvl.is_playtest = true
	lvl.fixed_mines.assign(FixedBoards.L3.mines)
	lvl.fixed_base = FixedBoards.L3.base
	lvl.preopen_coords.assign(FixedBoards.L3.preopen)


func _make_level(ch_idx: int, s_idx: int) -> LevelData:
	var lvl := LevelData.new()
	var ch_id := "ch%02d" % (ch_idx + 1)
	lvl.id = "%s_s%02d" % [ch_id, s_idx + 1]
	lvl.chapter_id = ch_id
	lvl.display_name = "%d-%d" % [ch_idx + 1, s_idx + 1]

	var density: float = CHAPTER_DENSITY[ch_idx]
	lvl.density = density
	lvl.ease_mult = WITHIN_EASE[s_idx]
	lvl.mine_count = clampi(
		int(round(CELLS * density / WITHIN_EASE[s_idx])),
		1, int(CELLS * MAX_DENSITY))

	var is_boss := s_idx == 4
	var obj := ObjectiveData.new()
	match s_idx:
		0:
			obj.type = ObjectiveData.Type.CLEAR_ALL_SAFE
		1:
			obj.type = ObjectiveData.Type.FLAG_N_MINES
			obj.target_value = max(1, int(round(lvl.mine_count * 0.2)))
		2:
			obj.type = ObjectiveData.Type.REACH_SCORE
			obj.target_value = 40 + ch_idx * 35
		3:
			obj.type = ObjectiveData.Type.CLEAR_ALL_SAFE
		4:
			obj.type = ObjectiveData.Type.SURVIVE_TIME
			obj.target_value = 60 + ch_idx * 5
	lvl.objectives = [obj]

	if is_boss:
		lvl.forbidden_actions = ["flag"]  # 禁标雷
		lvl.time_limit_sec = float(obj.target_value)
	else:
		lvl.time_limit_sec = 90.0

	# 第 1 章教学：只用基础机器人
	if ch_idx == 0:
		lvl.allowed_modules = ["opener", "marker"]
		lvl.start_gold = 150
		lvl.start_lives = 4

	lvl.first_clear_reward = RewardData.new()
	lvl.first_clear_reward.ore = 200
	lvl.repeat_reward = RewardData.new()
	lvl.repeat_reward.ore = 30
	return lvl


func get_level(id: String) -> LevelData:
	return levels.get(id)


func get_chapter(id: String) -> ChapterData:
	for ch in chapters:
		if ch.id == id:
			return ch
	return null


func all_chapters() -> Array:
	return chapters
