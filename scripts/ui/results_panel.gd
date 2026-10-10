extends Control
## 结算面板 V2：暗化背景 + 大星级弹出动画 + 新纪录角标 + 分项奖励图标化
## 兼容三种模式：关卡(首通/重刷) / 每日挑战 / 旧自由模式

signal restart_requested
signal next_level_requested          # 试玩关 win → 经关前卡进下一关
signal playtest_done_requested       # s05 达标 → 试玩完成页（P11）
signal powerup_requested             # 近失激励 → 「变强商店」直达矿石商店（P0.4）
signal back_to_level_select_requested
signal back_to_menu_requested

const ICON_COIN := preload("res://visual_v2/runtime/ui/icons/icon_coin.png")
const ICON_ORE := preload("res://visual_v2/runtime/completion/ui/icons/icon_ore.png")
const ICON_CLOCK := preload("res://visual_v2/runtime/ui/icons/icon_clock.png")
const ICON_HEART := preload("res://visual_v2/runtime/ui/icons/icon_heart.png")
const ICON_STAR := preload("res://visual_v2/runtime/ui/icons/icon_star.png")

const STAR_GRAY := Color(0.38, 0.35, 0.3)
const DAILY_ORE := 30
# 到点/命尽（强行停止）的矿石口径：积分折算（Q1 待定，改这一个常量即可）
const FORCED_STOP_ORE_DIVISOR := 10
# 连续未达标援助（P0.4）：第 ASSIST_STREAK 次起每次 +ASSIST_ORE 矿，并给下局一次性 +1 命
const ASSIST_STREAK := 3
const ASSIST_ORE := 50
# 升级建议可指轨（名称/上限与 ore_shop.TRACKS 同源；P0.2 科技树改造时同步改这里）
const SUGGEST_TRACKS := {
	"start_lives": {"name": "起始生命", "max": 2},
	"start_money": {"name": "起始金币", "max": 2},
	"start_robot": {"name": "开局送机器人", "max": 2},
	"global_speed": {"name": "移动速度", "max": 2},
	"work_speed": {"name": "工作速度", "max": 2},
}

@onready var title_label: Label = $Center/Panel/VBox/TitleLabel
@onready var objective_status_label: Label = $Center/Panel/VBox/ObjectiveStatusLabel
@onready var record_badge: PanelContainer = $Center/Panel/VBox/RecordBadge
@onready var stars_row: HBoxContainer = $Center/Panel/VBox/StarsRow
@onready var star_hint_label: Label = $Center/Panel/VBox/StarHintLabel
@onready var rewards_box: VBoxContainer = $Center/Panel/VBox/RewardsScroll/RewardsBox
@onready var final_score_label: Label = $Center/Panel/VBox/ScoreRow/FinalScoreLabel
@onready var next_button: Button = $Center/Panel/VBox/ButtonsRow/NextLevelButton
@onready var restart_button: Button = $Center/Panel/VBox/ButtonsRow/RestartButton
@onready var powerup_button: Button = $Center/Panel/VBox/ButtonsRow/PowerupButton
@onready var back_button: Button = $Center/Panel/VBox/ButtonsRow/BackButton


func _ready() -> void:
	hide()
	GameState.game_over.connect(_on_game_over)
	restart_button.pressed.connect(func(): restart_requested.emit())
	next_button.pressed.connect(func(): next_level_requested.emit())
	powerup_button.pressed.connect(func(): powerup_requested.emit())
	back_button.pressed.connect(_on_back)


func _on_back() -> void:
	# s05（试玩末关）达标 → 查看试玩总结；每日/自由模式回主菜单；其余回选关
	var lvl := GameState.get_current_level()
	if lvl != null and lvl.is_playtest and GameState.current_level_id == "ch01_s05" \
			and _last_result == "win":
		playtest_done_requested.emit()
	elif GameState.daily_mode or GameState.current_level_id == "":
		back_to_menu_requested.emit()
	else:
		back_to_level_select_requested.emit()


var _last_result: String = ""
# 近失判定与连败计数（P0.4）：_on_game_over 顶部一次算好，埋点与非达标分支共用
var _last_near_miss: bool = false
var _fail_streak: int = 0


func _on_game_over(result: String) -> void:
	show()
	_last_result = result
	record_badge.visible = false
	restart_button.text = "重玩本关"
	powerup_button.visible = false
	# 试玩关达标 → 「下一关」直达（末关 s05 走完成页，BackButton 文案切换）
	var lvl := GameState.get_current_level()
	var is_last: bool = GameState.current_level_id == "ch01_s05"
	next_button.visible = result == "win" and lvl != null and lvl.is_playtest and not is_last
	if result == "win" and lvl != null and lvl.is_playtest and is_last:
		back_button.text = "查看试玩总结"
	else:
		back_button.text = "返回选关" if GameState.current_level_id != "" and not GameState.daily_mode \
				else "返回主菜单"
	# 近失/连败计数（P0.4）：先于埋点结算，record 里带上本局后的累计值；每日/自由模式不参与
	_last_near_miss = false
	_fail_streak = 0
	if GameState.current_level_id != "" and not GameState.daily_mode:
		_fail_streak = SaveSystem.record_level_fail_streak(GameState.current_level_id, result)
		if result != "win":
			var obj := GameState.current_objective
			if obj != null:
				_last_near_miss = ObjectiveData.is_near_miss(obj.type,
						int(GameState.result_stats.get("obj_final_current", 0)),
						int(GameState.result_stats.get("obj_final_total", 0)),
						obj.target_value)
	# 每日挑战计入总局数/连胜，但不挤占关卡最佳时间/最高积分
	var is_record := _record_stats(result, not GameState.daily_mode)
	if lvl != null and lvl.is_playtest:
		_record_playtest(result)
	if GameState.daily_mode:
		_handle_daily(result)
	elif GameState.current_level_id == "":
		_handle_free_mode(result)
	else:
		_handle_level_mode(result, is_record)


func _time_used() -> float:
	if not GameState.has_time_limit():
		return GameState.elapsed
	var lvl := GameState.get_current_level()
	var total: float = lvl.time_limit_sec if lvl != null else 90.0
	return max(0.0, total - GameState.time_left)


## 盲测埋点：每局一条记录进存档（外部试玩收档解析用）
func _record_playtest(result: String) -> void:
	var s: Dictionary = GameState.result_stats
	SaveSystem.record_playtest({
		"level": GameState.current_level_id,
		"result": result,
		"near_miss": _last_near_miss,   # 差一点就达标（P0.4，仅 timeout/lose）
		"fail_streak": _fail_streak,    # 本局后该关连续未达标累计（win 清零）
		"elapsed": snappedf(GameState.elapsed, 0.1),
		"score": GameState.score,
		"money_left": GameState.money,
		"open_score": s["open_score"],
		"flag_score": s["flag_score"],
		"wrong_flags": s["wrong_flags"],
		"player_ops": s["player_ops"],
		"robot_ops": s["robot_ops"],
		"player_actions": s["player_actions"],
		"time_bonus": s.get("time_bonus", 0),
		"preopen_score": s.get("preopen_score", 0),
		"detector_score": s.get("detector_score", 0),
		"combat_score": s.get("combat_score", 0),
		"crossing_elapsed": s.get("crossing_elapsed", -1.0),  # 过线时刻（L3 目标型玩法）
		"first_upgrade_elapsed": s.get("first_upgrade_elapsed", -1.0),
		# 4 轨终值 [开墙移动, 开墙工作, 标雷移动, 标雷工作]（L1/L2 无工作轨=与移动同步）
		"speed_levels_final": [GameState.opener_move_level, GameState.opener_work_level,
				GameState.marker_move_level, GameState.marker_work_level],
		"robots_final": [GameState.opener_count, GameState.marker_count],
		# L4 除害关（设计 §9.10）
		"nest_cleared_elapsed": s.get("nest_cleared_elapsed", -1.0),
		"nests_destroyed": s.get("nests_destroyed", 0),
		"guard_bought_elapsed": s.get("guard_bought_elapsed", -1.0),
		"probe_used": s.get("probe_used", 0),
		"probe_coords": s.get("probe_coords", ""),
		"enemy_kills": [s.get("enemy_kills_player", 0), s.get("enemy_kills_guard", 0)],
		"obstacles_cleared": [s.get("obstacles_cleared_player", 0), s.get("obstacles_cleared_guard", 0)],
		"stall_seconds": snappedf(float(s.get("stall_seconds", 0.0)), 0.1),
		"slowed_seconds": snappedf(float(s.get("slowed_seconds", 0.0)), 0.1),
		# 本局开局时的局外解锁快照（L3 起玩家数值分化的分组依据，设计 §4.1）
		"meta_snapshot": {
			"start_money": int(SaveSystem.unlocks.get("start_money", 0)),
			"start_lives": int(SaveSystem.unlocks.get("start_lives", 0)),
			"global_speed": int(SaveSystem.unlocks.get("global_speed", 0)),
			"work_speed": int(SaveSystem.unlocks.get("work_speed", 0)),
			"start_robot": int(SaveSystem.unlocks.get("start_robot", 0)),
		},
	})


## 统计埋点；返回本局是否刷新最高积分
func _record_stats(result: String, track_best := true) -> bool:
	var is_record: bool = track_best and result == "win" \
			and GameState.score > int(SaveSystem.stats.best_score)
	SaveSystem.record_game_result(result, _time_used(), GameState.score, track_best)
	return is_record


# ---------------- 模式分支 ----------------

func _handle_free_mode(result: String) -> void:
	title_label.text = {"win": "胜利！", "lose": "失败", "timeout": "时间到"}.get(result, "结束")
	back_button.text = "返回主菜单"
	_clear_rewards()
	var ore_earned: int = GameState.score / 10
	SaveSystem.add_ore(ore_earned)
	_add_row(ICON_CLOCK, "本局用时", SaveSystem.format_duration(_time_used()))
	_add_row(ICON_ORE, "矿石结算", "+%d" % ore_earned)
	stars_row.visible = false
	star_hint_label.visible = false
	_add_money_rows()  # 金钱来源放在各模式奖励列表末尾（谁挣了多少钱）
	final_score_label.text = str(GameState.score)


func _handle_level_mode(result: String, is_record: bool) -> void:
	record_badge.visible = is_record
	_clear_rewards()
	_add_row(ICON_CLOCK, "本局用时", SaveSystem.format_duration(_time_used()))
	objective_status_label.text = String(GameState.result_stats.get("obj_final_text", ""))
	var lvl := GameState.get_current_level()
	if result != "win":
		# 到点/命尽 = 强行停止并结算（非失败态，设计 v1.2）：正常给矿、不算过关、可重玩
		# P2-05：结束原因写明（不再让玩家从 0:00 反推）；L5 Boss 关到点专属文案（设计 §4）
		var reason := "生命耗尽" if result == "lose" else "时间到"
		title_label.text = "它退回了黑暗里 · 牙没拔完" \
				if GameState.current_level_id == "ch01_s05" else "%s · 目标未达成" % reason
		stars_row.visible = false
		star_hint_label.visible = false
		# ---- 差一点激励（P0.4，非失败框架内）：距离行 + 等额矿石 + 连败援助 + 升级建议 ----
		if _last_near_miss:
			var obj := GameState.current_objective
			_add_row(ICON_STAR, ObjectiveData.near_miss_gap_text(obj.type,
					int(GameState.result_stats.get("obj_final_current", 0)),
					int(GameState.result_stats.get("obj_final_total", 0)),
					obj.target_value), "")
		var ore_earned: int = GameState.score / FORCED_STOP_ORE_DIVISOR
		var bonus_ore := 0
		if _last_near_miss:
			bonus_ore += ore_earned  # 差一点：再给一份等额矿石（合计双倍）
		var assist_granted := _fail_streak >= ASSIST_STREAK
		if assist_granted:
			bonus_ore += ASSIST_ORE
			SaveSystem.grant_assist(GameState.current_level_id, "extra_life")
		if ore_earned > 0:
			SaveSystem.add_ore(ore_earned)
		if bonus_ore > 0:
			SaveSystem.add_ore(bonus_ore)
		if ore_earned > 0:
			_add_row(ICON_ORE, "结算矿石", "+%d" % ore_earned)
		if _last_near_miss:
			_add_row(ICON_ORE, "差一点激励", "+%d" % ore_earned)
		if assist_granted:
			_add_row(ICON_ORE, "挑战援助", "+%d · 下局本关 +1 命" % ASSIST_ORE)
		# 升级建议 + 直达商店（仅 meta 关：L1/L2 不吃局外加成，指了是误导）
		var suggest: Dictionary = _upgrade_suggestion(result) if _last_near_miss else {}
		if not suggest.is_empty() and lvl != null and lvl.meta_progression:
			_add_row(ICON_STAR, "建议：再升 1 次「%s」就稳了" % suggest["name"], "")
			powerup_button.visible = true
		_add_row(ICON_HEART, "剩余生命", "%d" % GameState.lives)
		if lvl != null and lvl.is_playtest:
			_add_playtest_rows(false)
		_add_money_rows()  # 金钱来源放在各模式奖励列表末尾（谁挣了多少钱）
		final_score_label.text = str(GameState.score)
		return
	title_label.text = "目标达成"
	var stars := 0 if (lvl != null and lvl.no_stars) else _calculate_stars()
	var is_first: bool = not SaveSystem.is_first_clear_claimed(GameState.current_level_id)
	if is_first:
		var r := LevelSystem.claim_first_clear(GameState.current_level_id)
		_add_row(ICON_ORE, "首通奖励", "+%d 矿" % (r.ore if r != null else 0))
	else:
		var ore: int = lvl.repeat_reward.ore if lvl != null else 0
		SaveSystem.add_ore(ore)
		_add_row(ICON_ORE, "重刷奖励", "+%d 矿" % ore)
	LevelSystem.mark_cleared(GameState.current_level_id, stars)
	for line in _unlock_feedback(GameState.current_level_id):
		_add_row(ICON_STAR, line, "")
	# L2 通关 = 变强商店揭示时刻（布局计划 §2.5）；去向由局外商店引导聚光带路
	if lvl != null and lvl.is_playtest and GameState.current_level_id == "ch01_s02":
		_add_row(ICON_STAR, "新功能解锁：升级商店", "")
	if lvl != null and lvl.no_stars:
		# 试玩版教学关：无星级，账单分项行（开格/标雷/采矿/时间/操作占比）
		stars_row.visible = false
		star_hint_label.visible = false
		_add_playtest_rows()
	else:
		_animate_stars(stars)
		star_hint_label.visible = true
		star_hint_label.text = _star_hint(stars)
	_add_money_rows()  # 金钱来源放在各模式奖励列表末尾（谁挣了多少钱）
	final_score_label.text = str(GameState.score)


## 固定账单：开格/标雷/采矿/预开/探测/战斗/时间加分/操作占比（P2-01：总分=各行之和；
## 零值来源行收起；时间加分 0 也显示——让玩家知道有这项）
func _add_playtest_rows(include_time_bonus := true) -> void:
	var s: Dictionary = GameState.result_stats
	_add_row(ICON_COIN, "开格分", str(s["open_score"]))
	_add_row(ICON_COIN, "标旗分", str(s["flag_score"]))
	_add_row(ICON_COIN, "采矿分", str(int(s.get("mine_score", 0))))
	if int(s.get("preopen_score", 0)) > 0:
		_add_row(ICON_COIN, "预开格分", str(int(s.get("preopen_score", 0))))
	if int(s.get("detector_score", 0)) > 0:
		_add_row(ICON_COIN, "探测分", str(int(s.get("detector_score", 0))))
	if int(s.get("combat_score", 0)) > 0:
		_add_row(ICON_COIN, "战斗/清障分", str(int(s.get("combat_score", 0))))
	if int(s.get("shatter_score", 0)) > 0:
		_add_row(ICON_COIN, "碎钻分", str(int(s.get("shatter_score", 0))))
	var total_ops: int = int(s["player_ops"]) + int(s["robot_ops"])
	var pct: int = int(round(float(s["player_ops"]) / total_ops * 100.0)) if total_ops > 0 else 0
	_add_row(ICON_STAR, "你的扫雷操作",
		"%d 次 · 机器人 %d 次（你占 %d%%）" % [s["player_ops"], s["robot_ops"], pct])
	if include_time_bonus:
		_add_row(ICON_CLOCK, "时间加分",
			"剩余 %d 秒 +%d 分" % [int(s.get("time_bonus_secs", 0)), int(s.get("time_bonus", 0))])
	# L4 除害关：敌人数据行 + 探测次数（设计 §3 结算；到点/命尽分支也显示）
	if GameState.current_level_id == "ch01_s04":
		_add_row(ICON_STAR, "除害",
			"除巢 %d · 击杀 %d · 清障 %d" % [
				int(s.get("nests_destroyed", 0)),
				int(s.get("enemy_kills_player", 0)) + int(s.get("enemy_kills_guard", 0)),
				int(s.get("obstacles_cleared_player", 0)) + int(s.get("obstacles_cleared_guard", 0))])
		_add_row(ICON_STAR, "探测", "%d 次" % int(s.get("probe_used", 0)))
	# 第二章激光关：节奏观察行（总纲 §11——发射数/削层/碎钻/均束长）
	if GameState.current_level_id.begins_with("ch02"):
		var fired: int = int(s.get("shots_fired", 0))
		var avg_beam: float = float(s.get("beam_cells_total", 0)) / float(fired) if fired > 0 else 0.0
		_add_row(ICON_STAR, "激光",
			"发射 %d 次 · 削层 %d · 碎钻 %d · 均束 %.1f 格" % [
				fired, int(s.get("layers_peeled", 0)),
				int(s.get("diamonds_shattered", 0)), avg_beam])
		if int(s.get("builders_killed", 0)) > 0 or int(s.get("cover_walls_destroyed", 0)) > 0:
			_add_row(ICON_STAR, "拆敌",
				"击破筑墙工 %d · 拆覆盖墙 %d" % [
					int(s.get("builders_killed", 0)),
					int(s.get("cover_walls_destroyed", 0))])
	# L5 Boss 关：互动数据行（设计 §4 结算；到点/命尽分支也显示——打没打完都给看战果）
	if GameState.current_level_id == "ch01_s05":
		_add_row(ICON_STAR, "Boss战",
			"史莱姆 %d · 反弹 %d · 灭火 %d · 断触手 %d" % [
				int(s.get("slime_kills", 0)),
				int(s.get("bombs_deflected", 0)),
				int(s.get("fires_extinguished", 0)),
				int(s.get("tentacles_cut", 0))])


## 金钱来源（2026-10-02 侧栏改造收尾："谁挣了多少钱"，只在结算末尾展示）：
## 按挣钱方分组读 money_breakdown；零值组收起；两组以上才给合计行
func _add_money_rows() -> void:
	var b: Dictionary = GameState.money_breakdown
	var groups := [
		["你的扫雷", ["player_open", "player_flag"]],
		["你的战斗", ["player_combat"]],
		["开墙机开格", ["robot_open"]],
		["标雷机标旗", ["robot_flag"]],
		["矿工采矿", ["mine"]],
		["保安击退", ["guard_combat"]],
	]
	var total := 0
	var shown := 0
	for g in groups:
		var sum := 0
		for src in g[1]:
			sum += int(b.get(src, 0))
		total += sum
		if sum > 0:
			_add_row(ICON_COIN, "收入 · " + g[0], "+%d金" % sum)
			shown += 1
	if shown > 1:
		_add_row(ICON_COIN, "收入合计", "+%d金" % total)


func _handle_daily(result: String) -> void:
	title_label.text = "挑战完成！" if result == "win" else ("挑战失败" if result == "lose" else "时间到")
	back_button.text = "返回主菜单"
	_clear_rewards()
	_add_row(ICON_CLOCK, "本局用时", SaveSystem.format_duration(_time_used()))
	stars_row.visible = false
	star_hint_label.visible = false
	if result == "win":
		var info: Dictionary = SaveSystem.complete_daily(_time_used())
		SaveSystem.add_ore(DAILY_ORE)
		_add_row(ICON_ORE, "挑战奖励", "+%d 矿" % DAILY_ORE)
		if bool(info.new_best):
			_add_row(ICON_STAR, "今日新纪录！", "")
		if bool(info.badge_added):
			_add_row(ICON_STAR, "本周徽章 +1（%d/5）" % SaveSystem.get_daily_badges().size(), "")
		if int(info.chest_ore) > 0:
			SaveSystem.add_ore(int(info.chest_ore))
			_add_row(ICON_ORE, "本周宝箱", "+%d 矿" % int(info.chest_ore))
	_add_money_rows()  # 金钱来源放在各模式奖励列表末尾（谁挣了多少钱）
	final_score_label.text = str(GameState.score)


# ---------------- 视觉 ----------------

func _clear_rewards() -> void:
	for c in rewards_box.get_children():
		c.queue_free()


func _add_row(icon: Texture2D, left_text: String, right_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var icon_rect := TextureRect.new()
	icon_rect.texture = icon
	icon_rect.custom_minimum_size = Vector2(20, 20)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	var left := Label.new()
	left.text = left_text
	left.add_theme_font_size_override("font_size", 15)
	left.add_theme_color_override("font_color", Color(0.85, 0.78, 0.64))
	if right_text == "":
		var fill := Control.new()
		fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(icon_rect)
		row.add_child(left)
		row.add_child(fill)
		left.add_theme_color_override("font_color", Color(1, 0.82, 0.4))
		rewards_box.add_child(row)
		return
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right := Label.new()
	right.text = right_text
	right.add_theme_font_size_override("font_size", 15)
	row.add_child(icon_rect)
	row.add_child(left)
	row.add_child(spacer)
	row.add_child(right)
	rewards_box.add_child(row)


func _animate_stars(count: int) -> void:
	stars_row.visible = true
	var star_nodes: Array = [stars_row.get_node("Star1"), stars_row.get_node("Star2"), stars_row.get_node("Star3")]
	for i in 3:
		var tr: TextureRect = star_nodes[i]
		tr.pivot_offset = tr.size / 2.0
		tr.modulate = Color.WHITE if i < count else STAR_GRAY
		tr.scale = Vector2.ONE
	for i in count:
		var tr: TextureRect = star_nodes[i]
		tr.scale = Vector2.ZERO
		var tw := create_tween()
		tw.tween_interval(0.18 * i)
		tw.tween_property(tr, "scale", Vector2.ONE, 0.28) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _star_hint(stars: int) -> String:
	var parts := ["★ 完成目标"]
	if GameState.lives >= 2:
		parts.append("★ 剩余 %d 命" % GameState.lives)
	else:
		parts.append("☆ 剩余命不足")
	var obj := GameState.current_objective
	if obj == null or obj.type != ObjectiveData.Type.SURVIVE_TIME:
		var lvl := GameState.get_current_level()
		if lvl != null and GameState.time_left >= lvl.time_limit_sec * 0.5:
			parts.append("★ 速度加成")
		else:
			parts.append("☆ 速度不足")
	return " · ".join(parts)


## 章末通关后，追加"新章节 / 新功能解锁"提示
## 试玩版关卡不显示（拍板 2026-09-28：s05 通关不解锁/不提示第 2 章，达标走完成页）
func _unlock_feedback(level_id: String) -> Array:
	var lvl := LevelSystem.get_level(level_id)
	if lvl == null or lvl.is_playtest:
		return []
	var ch := LevelSystem.get_chapter(lvl.chapter_id)
	if ch == null or ch.level_ids[-1] != level_id:
		return []
	var lines: Array = []
	var ch_idx: int = ch.id.substr(2).to_int()
	var next_id := "ch%02d" % (ch_idx + 1)
	if next_id != "ch13" and LevelSystem.is_chapter_unlocked(next_id):
		var next_ch := LevelSystem.get_chapter(next_id)
		if next_ch != null:
			lines.append("🎉 新章节解锁: %s" % next_ch.display_name)
	if ch.unlock_module != "" and ch.unlock_module != "opener_marker":
		lines.append("🎉 新功能解锁: %s" % _module_name(ch.unlock_module))
	return lines


func _module_name(module: String) -> String:
	match module:
		"detector": return "检测型机器人"
		"miner": return "矿工机器人"
		"tower": return "充能塔"
		"drone": return "无人机"
	return module


## 1 星保底；命 ≥ 2 +1 星；快速通关（剩余 ≥ 50%）+1 星（生存关不加）
func _calculate_stars() -> int:
	var stars := 1
	if GameState.lives >= 2:
		stars += 1
	var obj := GameState.current_objective
	if obj == null or obj.type != ObjectiveData.Type.SURVIVE_TIME:
		var lvl := GameState.get_current_level()
		if lvl != null and GameState.time_left >= lvl.time_limit_sec * 0.5:
			stars += 1
	return stars


## 近失升级建议（P0.4）：按结束方式/目标类型指向最可能有感的矿石商店轨；
## 建议轨已满级返回空字典（退化为只给距离行与矿石，不显示建议/商店按钮）
func _upgrade_suggestion(result: String) -> Dictionary:
	var key := ""
	if result == "lose":
		key = "start_lives"
	else:
		var obj := GameState.current_objective
		if obj != null:
			match obj.type:
				ObjectiveData.Type.REACH_SCORE:
					# 攒分类：工作/移动档里挑等级更低的（更便宜，提速攒分）
					key = "work_speed" if int(SaveSystem.unlocks.get("work_speed", 0)) \
							<= int(SaveSystem.unlocks.get("global_speed", 0)) else "global_speed"
				ObjectiveData.Type.FIND_ALL_MINES:
					key = "start_robot"  # Lv2 起开局送标雷型，拔牙提速
				_:
					key = "start_money"  # 清图/其他：开局钱多早买机早铺开
	var t: Dictionary = SUGGEST_TRACKS.get(key, {})
	if t.is_empty() or int(SaveSystem.unlocks.get(key, 0)) >= int(t["max"]):
		return {}
	return {"key": key, "name": t["name"]}
