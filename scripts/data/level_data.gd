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

# ---- 固定盘面（空 = 随机生成，走原 place_first_base 流程）----
var fixed_mines: Array[Vector2i] = []       # 雷位
var fixed_base: Vector2i = Vector2i(-1, -1)  # 预置基地；(-1,-1) = 玩家自放
var preopen_coords: Array[Vector2i] = []    # 预开区（含洪水结果，直接烘焙）

# ---- 教学规则参数（零值 = 该机制不启用）----
var free_clicks: int = 0            # >0：第 N 次有效玩家动作触发 CD 耗尽
var free_correct_flags: int = 0     # >0：第 N 面正确旗触发耗尽（与上条先到为准）
var cooldown_sec: float = 0.0       # 耗尽后单次 CD 时长；0 = 本关无 CD
var cooldown_after_purchase: float = -1.0  # >=0：首台机器人购买后 CD 改为此值

# ---- 商店限制 ----
var shop_limits: Dictionary = {}    # 如 {"opener":1, "marker":1}；空 = 不限购
var shop_hidden: Array = []         # 本关隐藏的商店按钮 type："base"/"drone"/"upgrade"/"debug"

# ---- 结算表现 ----
var no_stars: bool = false          # true = 结算不显示星级
var is_playtest: bool = false       # true = 试玩版关卡（结算写入盲测埋点）


func has_fixed_board() -> bool:
	return not fixed_mines.is_empty()


func get_effective_mine_count() -> int:
	return mine_count
