class_name LevelData
extends Resource
## 单关数据：目标 / 地图参数 / 规则 / 奖励

var id: String = ""              # "ch01_s01"
var chapter_id: String = ""      # "ch01"
var display_name: String = ""    # "1-1"
var grid_size: Vector2i = Vector2i(16, 16)
var mine_count: int = 32
var density: float = 0.125       # 章节基础雷密度（调试/展示用）
var ease_mult: float = 1.0       # 章内舒适度乘子（越高越简单）
var time_limit_sec: float = 90.0
var start_gold: int = 100
var start_lives: int = 3
var objectives: Array = []       # Array[ObjectiveData]，通常 1 个
var forbidden_actions: Array = []  # 如 ["flag"]（禁标雷）
var allowed_modules: Array = []  # 允许使用的机器人类型；空 = 全部允许
var first_clear_reward: RewardData
var repeat_reward: RewardData


func get_effective_mine_count() -> int:
	return mine_count
