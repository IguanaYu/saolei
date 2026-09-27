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
