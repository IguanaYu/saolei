extends Node
## 存档系统 autoload 单例：矿石 + 解锁状态持久化
## JSON 存档路径 user://save_data.json

const SAVE_PATH := "user://save_data.json"

var ore: int = 0

# 局外升级等级（int）或解锁状态（bool）
var unlocks: Dictionary = {
	"start_money": 0,    # 起始金币加成，每级 +50，max 2
	"start_lives": 0,    # 起始额外生命，每级 +1，max 2
	"global_speed": 0,   # 全局速度加成，每级提速，max 2
	"expand_zone": 0,    # 安全区扩大，每级 +1 半径，max 2
	"start_robot": 0,    # 开局送机器人，每级 +1，max 2
	"detector": false,   # 解锁检测型（章 2 通关解锁）
	"miner": false,      # 解锁矿工型（章 3 通关解锁）
	"tower": false,      # 解锁充能塔（章 4 通关解锁，功能未实现）
	"drone": false,      # 解锁无人机（章 5 通关解锁）
}

# ---- 关卡章节进度（v3）----
var cleared_levels: Dictionary = {}        # {"ch01_s01": true}
var level_stars: Dictionary = {}           # {"ch01_s01": 3}
var first_clear_claimed: Dictionary = {}   # {"ch01_s01": true}
var unlocked_chapters: Array = ["ch01"]

# ---- 统计 / 每日挑战 / 签到（v4）----
var stats := {
	"total_games": 0, "wins": 0, "best_time": -1.0, "best_score": 0,
	"cur_streak": 0, "max_streak": 0, "total_play_sec": 0.0,
}
var daily := {
	"today_key": "", "today_best": -1.0,   # 今日挑战最佳用时
	"all_best": -1.0,                       # 每日挑战历史最佳
	"badges": {},                           # {周一日期串: [星期几]}（1=周一..7=周日）
	"chest_weeks": [],                      # 已领周宝箱的周一日期串
}
var signin := {"last_claim_date": "", "streak": 0}

const SIGN_DAY_ORE := [5, 8, 10, 15, 20, 30, 60]

signal ore_changed(new_ore: int)
signal unlock_changed(key: String)


func _ready() -> void:
	load_game()


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("存档损坏，使用默认值")
		return
	ore = int(data.get("ore", 0))
	var saved: Dictionary = data.get("unlocks", {})
	# 逐字段合并，兼容旧存档
	for key in unlocks:
		if saved.has(key):
			unlocks[key] = saved[key]
	cleared_levels = data.get("cleared_levels", {})
	level_stars = data.get("level_stars", {})
	first_clear_claimed = data.get("first_clear_claimed", {})
	var saved_chapters: Variant = data.get("unlocked_chapters", ["ch01"])
	if typeof(saved_chapters) == TYPE_ARRAY and not saved_chapters.is_empty():
		unlocked_chapters = saved_chapters
	else:
		unlocked_chapters = ["ch01"]
	_merge_dict(stats, data.get("stats", {}))
	_merge_dict(daily, data.get("daily", {}))
	_merge_dict(signin, data.get("signin", {}))
	ore_changed.emit(ore)


func _merge_dict(target: Dictionary, src: Dictionary) -> void:
	for key in target:
		if src.has(key):
			target[key] = src[key]


func save_game() -> void:
	var data = {
		"version": 4, "ore": ore, "unlocks": unlocks,
		"cleared_levels": cleared_levels, "level_stars": level_stars,
		"first_clear_claimed": first_clear_claimed,
		"unlocked_chapters": unlocked_chapters,
		"stats": stats, "daily": daily, "signin": signin,
	}
	var f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("无法写入存档")
		return
	f.store_string(JSON.stringify(data, "  "))


func add_ore(amount: int) -> void:
	ore += amount
	ore_changed.emit(ore)
	save_game()


func spend_ore(amount: int) -> bool:
	if ore < amount:
		return false
	ore -= amount
	ore_changed.emit(ore)
	save_game()
	return true


## 购买局外升级，返回是否成功
func purchase_unlock(key: String, cost: int) -> bool:
	if not unlocks.has(key):
		return false
	var current = unlocks[key]
	if typeof(current) == TYPE_BOOL:
		if current:
			return false  # 已解锁
		if not spend_ore(cost):
			return false
		unlocks[key] = true
		unlock_changed.emit(key)
		save_game()
		return true
	else:
		# int 类型，最高 2 级
		if current >= 2:
			return false
		if not spend_ore(cost):
			return false
		unlocks[key] = current + 1
		unlock_changed.emit(key)
		save_game()
		return true


# ---- 关卡章节进度（v3）----

func is_level_cleared(id: String) -> bool:
	return bool(cleared_levels.get(id, false))


func get_level_stars(id: String) -> int:
	return int(level_stars.get(id, 0))


func set_level_cleared(id: String, stars: int) -> void:
	cleared_levels[id] = true
	level_stars[id] = max(get_level_stars(id), stars)
	save_game()


func is_first_clear_claimed(id: String) -> bool:
	return first_clear_claimed.has(id)


func claim_first_clear(id: String) -> void:
	first_clear_claimed[id] = true
	save_game()


func is_chapter_unlocked(ch_id: String) -> bool:
	return unlocked_chapters.has(ch_id)


func unlock_chapter(ch_id: String) -> void:
	if unlocked_chapters.has(ch_id):
		return
	unlocked_chapters.append(ch_id)
	save_game()


# ==================== 日期工具（本地时区） ====================

func _local_unix() -> int:
	return int(Time.get_unix_time_from_system() + Time.get_time_zone_from_system().get("bias", 0) * 60)


func _date_key_from_unix(u: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(u)
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


func today_key() -> String:
	return _date_key_from_unix(_local_unix())


func yesterday_key() -> String:
	return _date_key_from_unix(_local_unix() - 86400)


## 周一=1 ... 周日=7
func today_weekday() -> int:
	var wd: int = Time.get_date_dict_from_system().weekday  # 引擎定义 0=周日
	return ((wd + 6) % 7) + 1


## 本周周一的日期串（徽章周 key）
func monday_key() -> String:
	return _date_key_from_unix(_local_unix() - (today_weekday() - 1) * 86400)


## 今天是年内第几天（每日挑战期号用）
func day_of_year() -> int:
	var now := Time.get_date_dict_from_system()
	var jan1 := Time.get_unix_time_from_datetime_dict(
		{"year": now.year, "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0})
	return int((_local_unix() - int(jan1)) / 86400.0) + 1


# ==================== 统计（挖矿档案） ====================

## 每局结束埋点。result: "win"/"lose"/"timeout"/"abandon"
## track_best=false 时（每日挑战）不计入最佳时间/最高积分
func record_game_result(result: String, time_used: float, score: int, track_best := true) -> void:
	stats.total_games = int(stats.total_games) + 1
	stats.total_play_sec = float(stats.total_play_sec) + max(0.0, time_used)
	if result == "win":
		stats.wins = int(stats.wins) + 1
		stats.cur_streak = int(stats.cur_streak) + 1
		stats.max_streak = max(int(stats.max_streak), int(stats.cur_streak))
		if track_best:
			if float(stats.best_time) < 0 or time_used < float(stats.best_time):
				stats.best_time = time_used
			stats.best_score = max(int(stats.best_score), score)
	else:
		stats.cur_streak = 0
	save_game()


func format_duration(sec: float) -> String:
	var s := int(round(sec))
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]


## 外部试玩盲测埋点：每局一条记录，收档时直接从存档 JSON 解析
func record_playtest(entry: Dictionary) -> void:
	entry["ts"] = Time.get_unix_time_from_system()
	var arr: Array = stats.get("playtest", [])
	arr.append(entry)
	if arr.size() > 200:
		arr = arr.slice(arr.size() - 200)  # 封顶防膨胀
	stats["playtest"] = arr
	save_game()


# ==================== 每日挑战 ====================

func get_daily_badges() -> Array:
	return daily.badges.get(monday_key(), [])


## 完成今日挑战（每天只记一枚徽章）。返回 {new_best, badge_added, chest_ore}
func complete_daily(time_used: float) -> Dictionary:
	var out := {"new_best": false, "badge_added": false, "chest_ore": 0}
	if daily.today_key != today_key():
		daily.today_key = today_key()
		daily.today_best = -1.0
	if float(daily.today_best) < 0 or time_used < float(daily.today_best):
		daily.today_best = time_used
		out.new_best = true
	if float(daily.all_best) < 0 or time_used < float(daily.all_best):
		daily.all_best = time_used
	var mk := monday_key()
	var arr: Array = daily.badges.get(mk, [])
	var wd := today_weekday()
	if not arr.has(wd):
		arr.append(wd)
		daily.badges[mk] = arr
		out.badge_added = true
		if arr.size() >= 5 and not daily.chest_weeks.has(mk):
			daily.chest_weeks.append(mk)
			out.chest_ore = 50
	save_game()
	return out


# ==================== 签到 ====================

func can_sign_today() -> bool:
	return signin.last_claim_date != today_key()


func _signin_alive() -> bool:
	return signin.last_claim_date == yesterday_key()


## 签到状态：claimed_today 今天是否已领；day_today 今天(应)领的第几天(1-7)；
## claimed_in_cycle 本周期已领天数；streak 生效连签天数（断签视为 0）
func signin_state() -> Dictionary:
	var claimed_today: bool = signin.last_claim_date == today_key()
	var alive := _signin_alive() or claimed_today
	var streak: int = int(signin.streak) if alive else 0
	var day_today: int = (int(streak) % 7) + 1
	var claimed_in_cycle: int = ((int(streak) - 1) % 7) + 1 if claimed_today and streak > 0 else streak % 7
	return {"claimed_today": claimed_today, "day_today": day_today,
			"claimed_in_cycle": claimed_in_cycle, "streak": streak}


## 领今日奖励，返回矿石数；不可领返回 -1
func do_sign() -> int:
	if not can_sign_today():
		return -1
	if not _signin_alive():
		signin.streak = 0
	signin.streak = int(signin.streak) + 1
	signin.last_claim_date = today_key()
	var day := ((int(signin.streak) - 1) % 7) + 1
	var ore_reward: int = SIGN_DAY_ORE[day - 1]
	add_ore(ore_reward)
	return ore_reward


# ==================== 清档 ====================

func reset_all() -> void:
	## 清空游戏存档（GameSettings 里的设置保留）
	ore = 0
	unlocks = {
		"start_money": 0, "start_lives": 0, "global_speed": 0, "expand_zone": 0,
		"start_robot": 0, "detector": false, "miner": false, "tower": false, "drone": false,
	}
	cleared_levels = {}
	level_stars = {}
	first_clear_claimed = {}
	unlocked_chapters = ["ch01"]
	stats = {"total_games": 0, "wins": 0, "best_time": -1.0, "best_score": 0,
			"cur_streak": 0, "max_streak": 0, "total_play_sec": 0.0}
	daily = {"today_key": "", "today_best": -1.0, "all_best": -1.0, "badges": {}, "chest_weeks": []}
	signin = {"last_claim_date": "", "streak": 0}
	save_game()
	ore_changed.emit(ore)
	unlock_changed.emit("reset")
