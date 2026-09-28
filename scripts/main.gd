extends Node
## 主场景控制器：负责游戏主循环、玩家输入路由、模块协调、关卡流程
## 以及全套页面串联（闪屏/暂停/设置/档案/每日/签到/引导/结算）

@onready var grid: Grid = $Grid
@onready var robot_manager: RobotManager = $RobotManager
@onready var enemy_manager: EnemyManager = $EnemyManager
@onready var hud = $UILayer/HUD
@onready var shop = $UILayer/Shop
@onready var main_menu = $UILayer/MainMenu
@onready var chapter_select = $UILayer/ChapterSelect
@onready var level_select = $UILayer/LevelSelect
@onready var results_panel = $UILayer/ResultsPanel
@onready var tutorial_guide = $UILayer/TutorialGuide
@onready var pause_panel = $UILayer/PausePanel
@onready var settings_panel = $UILayer/SettingsPanel
@onready var stats_panel = $UILayer/StatsPanel
@onready var daily_panel = $UILayer/DailyPanel
@onready var sign_in_panel = $UILayer/SignInPanel
@onready var confirm_dialog = $UILayer/ConfirmDialog
@onready var splash = $UILayer/SplashScreen
@onready var pre_level_card = $UILayer/PreLevelCard
@onready var rules_panel = $UILayer/RulesPanel
@onready var playtest_done = $UILayer/PlaytestDonePanel
@onready var upgrade_panel = $UILayer/UpgradePanel
@onready var ore_shop = $UILayer/OreShop

# 当前放置模式（商店点击购买/建造后置为 "opener"/"marker"/"base"/"...")
var placing_mode: String = ""

# 试玩版第一/二/三/四关剧本控制器（_ready 时创建）
var level1_director: Level1Director = null
var level2_director: Level2Director = null
var level3_director: Level3Director = null
var level4_director: Level4Director = null

# 当前所在章节（"返回关卡选择"时用）
var _current_chapter_id: String = "ch01"
# FLAG_N_MINES 目标计数
var _flag_count: int = 0

# 确认框待执行动作
var _pending_confirm: String = ""

# L4 pregen 关的开局赠机（放完基地后在基地旁落位）
var _pending_gifts: Dictionary = {}

const CHAPTER_WALL_STYLES := ["V2", "V2C", "V2M", "V2R"]


func _ready() -> void:
	# 不立即 reset，等玩家选关进入
	_register_custom_cursors()
	grid.all_safe_opened.connect(_on_all_safe_opened)
	grid.cell_opened.connect(_on_cell_opened)
	grid.cell_flagged.connect(_on_cell_flagged)
	grid.mine_stepped.connect(_on_mine_stepped)
	grid.obstacle_cleared.connect(_on_obstacle_cleared)
	grid.cell_hovered.connect(_on_grid_cell_hovered)
	grid.cell_unhovered.connect(_on_grid_cell_unhovered)
	robot_manager.idle_warning_changed.connect(_on_idle_warning_changed)
	robot_manager.robot_removed.connect(_on_robot_removed)
	main_menu.continue_requested.connect(_on_continue_play)
	main_menu.select_level_requested.connect(_on_select_level)
	main_menu.settings_requested.connect(func(): settings_panel.open())
	main_menu.powerup_requested.connect(func(): ore_shop.open())
	main_menu.quit_requested.connect(_ask_quit)
	main_menu.rules_requested.connect(func(): rules_panel.open())
	level_select.powerup_requested.connect(func(): ore_shop.open())
	chapter_select.chapter_selected.connect(_on_chapter_selected)
	chapter_select.back_requested.connect(_on_chapter_select_back)
	level_select.start_requested.connect(_open_pre_level)
	level_select.back_requested.connect(_on_level_select_back)
	pre_level_card.start_confirmed.connect(_start_level)
	results_panel.restart_requested.connect(_on_restart_requested)
	results_panel.back_to_level_select_requested.connect(_on_back_to_level_select)
	results_panel.back_to_menu_requested.connect(_show_main_menu)
	results_panel.next_level_requested.connect(_on_next_level)
	results_panel.playtest_done_requested.connect(_open_playtest_done)
	playtest_done.done_back_requested.connect(_on_back_to_level_select)
	playtest_done.done_menu_requested.connect(_show_main_menu)
	GameState.score_changed.connect(_on_score_changed)
	GameState.time_changed.connect(_on_time_changed)
	GameState.base_placed.connect(func(_c): tutorial_guide.notify_event("base_placed"))
	GameState.robot_spawned.connect(func(_t): tutorial_guide.notify_event("robot_bought"))
	grid.board_clicked.connect(func(): tutorial_guide.notify_event("board_click"))
	upgrade_panel.visibility_changed.connect(func():
		if upgrade_panel.visible:
			tutorial_guide.notify_event("upgrade_panel_opened"))
	# 闪屏 → 主菜单（+ 每日首启签到弹窗）
	splash.finished.connect(_on_splash_finished)
	main_menu.hide()  # 闪屏期间藏住主菜单
	# 暂停
	hud.pause_requested.connect(_toggle_pause)
	pause_panel.resume_requested.connect(_resume)
	pause_panel.rules_requested.connect(func(): rules_panel.open())
	pause_panel.settings_requested.connect(func(): settings_panel.open())
	pause_panel.restart_requested.connect(_ask_restart_run)
	pause_panel.quit_requested.connect(_ask_quit_to_select)
	# 设置
	settings_panel.close_requested.connect(func(): settings_panel.hide())
	settings_panel.clear_save_requested.connect(_ask_clear_save)
	settings_panel.tutorial_rewatch_requested.connect(_on_tutorial_rewatch)
	# 各面板返回
	stats_panel.close_requested.connect(func(): stats_panel.hide())
	daily_panel.close_requested.connect(func(): daily_panel.hide())
	sign_in_panel.close_requested.connect(func(): sign_in_panel.hide())
	# 每日挑战开打
	daily_panel.start_requested.connect(_start_daily)
	# 确认框
	confirm_dialog.confirmed.connect(_on_confirm_confirmed)
	# 光标恢复环（CD 期间跟随鼠标）
	var cd_ring := CDRing.new()
	cd_ring.name = "CDRing"
	$UILayer.add_child(cd_ring)
	# 试玩版第一/二/三/四关剧本控制器
	level1_director = Level1Director.new()
	level1_director.name = "Level1Director"
	add_child(level1_director)
	level2_director = Level2Director.new()
	level2_director.name = "Level2Director"
	add_child(level2_director)
	level3_director = Level3Director.new()
	level3_director.name = "Level3Director"
	add_child(level3_director)
	level4_director = Level4Director.new()
	level4_director.name = "Level4Director"
	add_child(level4_director)
	# 音频连接器（旁听信号→AudioManager）
	var audio_connector := AudioConnector.new()
	audio_connector.name = "AudioConnector"
	add_child(audio_connector)


# ---- 闪屏 / 主菜单 ----

func _on_splash_finished() -> void:
	main_menu.show()
	main_menu.refresh()


func _show_main_menu() -> void:
	results_panel.hide()
	pause_panel.hide()
	main_menu.show()
	main_menu.refresh()


# ---- 关卡流程 ----

func _on_continue_play() -> void:
	# 主按钮直进当前进度关：弹关前卡（首关教学在局内，见 director）
	main_menu.hide()
	var idx := 0
	for i in 5:
		if not SaveSystem.is_level_cleared("ch01_s%02d" % (i + 1)):
			idx = i
			break
	_open_pre_level("ch01_s%02d" % (idx + 1))


func _on_select_level() -> void:
	main_menu.hide()
	level_select.set_chapter("ch01")   # 绕过章节页；ChapterSelect 场景保留不用
	level_select.show()


func _ask_quit() -> void:
	_pending_confirm = "quit_game"
	confirm_dialog.ask("退出游戏？", "", "退出", "取消", false)


func _on_chapter_selected(ch_id: String) -> void:
	_current_chapter_id = ch_id
	level_select.set_chapter(ch_id)
	chapter_select.hide()
	level_select.show()


func _on_chapter_select_back() -> void:
	chapter_select.hide()
	main_menu.show()


func _on_level_select_back() -> void:
	level_select.hide()
	main_menu.show()
	main_menu.refresh()


func _on_start_game(level_id: String) -> void:
	_start_level(level_id)


## 关前卡片入口：重玩且玩家勾了跳过 → 直进；否则弹卡片（数字全部读关卡真实配置）
func _open_pre_level(level_id: String) -> void:
	var lvl := LevelSystem.get_level(level_id)
	if lvl == null:
		return
	if SaveSystem.is_level_cleared(level_id) \
			and bool(GameSettings.get_value("skip_pre_level")):
		level_select.hide()
		main_menu.hide()
		_start_level(level_id)
		return
	level_select.hide()
	main_menu.hide()
	pre_level_card.open(lvl)


func _on_restart_requested() -> void:
	if GameState.daily_mode:
		_start_daily()
	else:
		_start_level(GameState.current_level_id)


## 结算「下一关」：经关前卡进下一关（首次必弹卡片）
func _on_next_level() -> void:
	results_panel.hide()
	var n: int = GameState.current_level_id.substr(-1).to_int() + 1
	_open_pre_level("ch01_s%02d" % n)


## 试玩完成页（s05 达标经结算 BackButton 进入）
func _open_playtest_done() -> void:
	results_panel.hide()
	playtest_done.open()


func _on_back_to_level_select() -> void:
	results_panel.hide()
	level_select.set_chapter(_current_chapter_id)
	level_select.show()


func _start_level(level_id: String) -> void:
	GameState.daily_mode = false
	var lvl: LevelData = LevelSystem.get_level(level_id) if level_id != "" else null
	_start_level_with(lvl, "")


func _start_daily() -> void:
	daily_panel.hide()
	main_menu.hide()
	GameState.daily_mode = true
	_start_level_with(daily_panel.today_level(), daily_panel.today_wall_style())


func _start_level_with(lvl: LevelData, wall_style: String) -> void:
	main_menu.hide()
	chapter_select.hide()
	level_select.hide()
	results_panel.hide()
	pause_panel.hide()
	tutorial_guide.hide()  # 中断上一局的引导
	get_tree().paused = false
	var id := lvl.id if lvl != null else ""
	SaveSystem.mark_level_entered(id)  # 间场「变强」高亮依据（进关即记）
	GameState.reset_state(id, lvl)
	_flag_count = 0
	robot_manager.remove_all()
	enemy_manager.clear()  # 上一局的虫/巢/波次全部清空（重开新盘；须在 setup_board 之前）
	if lvl != null:
		var chapter_number := int(lvl.chapter_id.trim_prefix("ch"))
		var chapter_style: String = CHAPTER_WALL_STYLES[clampi(int((chapter_number - 1) / 3.0), 0, 3)]
		grid.wall_style = wall_style if wall_style != "" else chapter_style
		grid.configure(lvl.grid_size.x, lvl.grid_size.y, lvl.mine_count)
		$CaveEnv.layout_env()  # 地图尺寸变化后重排洞窟边框/道具
		# 固定盘面：直接装载雷位/预开区/预置基地，跳过放基地阶段
		if lvl.has_fixed_board():
			grid.apply_fixed_board({
				"mines": lvl.fixed_mines,
				"preopen": lvl.preopen_coords,
				"base": lvl.fixed_base,
			})
			GameState.game_active = true
			# 预开算分（设计 v1.2）：只计分不计钱；300 > 预开上限 115，不会开局误判过线
			if lvl.preopen_scores:
				GameState.add_score(lvl.preopen_coords.size())
		# 随机盘（L4 除害关）：进关预生成雷+洪水预开，不设 game_active——
		# 放完基地才激活（波次计时随之从放基地起算，elapsed 只在 active 后累计）
		elif lvl.pregen_random:
			grid.apply_random_board()
			enemy_manager.setup_board(grid)
	# 开局赠送机器人 = 关卡自带 + 局外 start_robot 购买（meta 关才吃局外，Q2：计入 count）
	var gifts: Dictionary = lvl.start_robots.duplicate() if lvl != null else {}
	if lvl != null and lvl.meta_progression:
		var sr: int = int(SaveSystem.unlocks.get("start_robot", 0))
		if sr >= 1:
			gifts["opener"] = int(gifts.get("opener", 0)) + 1
		if sr >= 2:
			gifts["marker"] = int(gifts.get("marker", 0)) + 1
	if not gifts.is_empty() and lvl != null and lvl.has_fixed_board():
		_gift_start_robots(gifts)
	elif not gifts.is_empty() and lvl != null and lvl.pregen_random:
		_pending_gifts = gifts  # L4：放完基地后在基地旁落位（此时还没有基地）
	# HUD 关名（试玩关「第 N 关 · 短名」；短名未配置回退 display_name）
	if lvl != null:
		var n: int = lvl.display_name.substr(2).to_int() if lvl.display_name.length() > 2 else 1
		hud.set_level_title("第 %d 关 · %s" % [n,
				lvl.short_name if lvl.short_name != "" else lvl.display_name])
	else:
		hud.set_level_title("")
	_update_objective_progress()
	_maybe_start_tutorial()


# ---- 新手引导 ----

func _maybe_start_tutorial() -> void:
	if GameState.daily_mode:
		return
	# 试玩版剧本教学每次进关都触发（不看 tutorial_done，盲测者每遍都要看到）
	if GameState.current_level_id == "ch01_s01" and level1_director != null:
		level1_director.begin()
	elif GameState.current_level_id == "ch01_s02" and level2_director != null:
		level2_director.begin()
	elif GameState.current_level_id == "ch01_s03" and level3_director != null:
		level3_director.begin()
	elif GameState.current_level_id == "ch01_s04" and level4_director != null:
		level4_director.begin()


# ---- 暂停 / 放弃 ----

func _toggle_pause() -> void:
	if pause_panel.visible:
		_resume()
	elif _in_game():
		_open_pause()


## 是否处于"局内可操作"状态（无任何全屏覆盖层）
func _in_game() -> bool:
	return not (splash.visible or main_menu.visible or chapter_select.visible
			or level_select.visible or results_panel.visible or pause_panel.visible
			or settings_panel.visible or stats_panel.visible or daily_panel.visible
			or sign_in_panel.visible or confirm_dialog.visible or ore_shop.visible
			or pre_level_card.visible or rules_panel.visible or playtest_done.visible)


func _open_pause() -> void:
	_exit_placing_mode()  # 暂停时取消放置，避免恢复后状态混乱
	grid.set_hover_overlay(Vector2i.ZERO, "hide")
	pause_panel.open(_pause_context(), hud.get_objective_text())
	get_tree().paused = true


func _pause_context() -> String:
	if GameState.daily_mode:
		return "每日挑战 · %s" % SaveSystem.today_key()
	var lvl := GameState.get_current_level()
	if lvl == null:
		return ""
	if lvl.is_playtest:
		return "试玩矿区 · 第 %s 关" % lvl.display_name.substr(2)
	var ch := LevelSystem.get_chapter(lvl.chapter_id)
	return "%s · %s" % [ch.display_name if ch != null else "", lvl.display_name]


func _resume() -> void:
	get_tree().paused = false
	pause_panel.hide()
	grid.set_hover_overlay(Vector2i.ZERO, "hide")  # 暂停前悬停的残影清掉


## 重开本关（确认框）：本局作废，已入账矿石不受影响
func _ask_restart_run() -> void:
	_pending_confirm = "restart_run"
	confirm_dialog.ask("重新开始本关？",
		"本局进度与已得积分将作废\n已结算入账的矿石不受影响",
		"确认重开", "继续挖矿", true)


func _do_restart_run() -> void:
	get_tree().paused = false
	pause_panel.hide()
	tutorial_guide.hide()
	_on_restart_requested()


## 返回选关（确认框，半矿放弃口径——拍板 2026-09-28）
func _ask_quit_to_select() -> void:
	if GameState.continue_mode:
		# 继续挑战中离开：不走放弃流程（胜利结算已入账），文案单独一套
		_pending_confirm = "leave_continue"
		confirm_dialog.ask("离开本局？",
			"胜利结算已入账\n继续挑战的分数将计入最高分",
			"确认离开", "继续挖掘", true)
		return
	_pending_confirm = "quit_to_select"
	var keep_ore: int = GameState.score / 20
	confirm_dialog.ask("返回选关？",
		"本局按放弃结算：积分清零，矿石按一半保留（+%d 矿）" % keep_ore,
		"确认返回", "继续挖矿", true)


## 放弃结算：半矿入账 + 局面清理（终点由调用方决定）
func _abandon_settle() -> void:
	get_tree().paused = false
	pause_panel.hide()
	tutorial_guide.hide()
	var lvl := GameState.get_current_level()
	var total: float = lvl.time_limit_sec if lvl != null else 90.0
	var duration: float = GameState.elapsed if not GameState.has_time_limit() \
			else max(0.0, total - GameState.time_left)
	SaveSystem.record_game_result("abandon", duration, GameState.score, false)
	var keep_ore: int = GameState.score / 20
	if keep_ore > 0:
		SaveSystem.add_ore(keep_ore)
	GameState.game_active = false
	robot_manager.remove_all()
	enemy_manager.clear()


func _do_quit_to_select() -> void:
	_abandon_settle()
	if GameState.daily_mode:
		_show_main_menu()
		return
	level_select.set_chapter(_current_chapter_id)
	level_select.show()


# ---- 设置 / 清档 ----

func _on_tutorial_rewatch() -> void:
	hud.show_toast("第一关开场自带教学，进 1-1 即可", 3.0)


func _ask_clear_save() -> void:
	_pending_confirm = "clear_save"
	confirm_dialog.ask("清除全部存档？",
		"矿石与试玩进度将全部清零\n（设置项保留）",
		"确认清除", "取消", true)


func _on_confirm_confirmed() -> void:
	match _pending_confirm:
		"restart_run":
			_do_restart_run()
		"quit_to_select":
			_do_quit_to_select()
		"leave_continue":
			_leave_after_continue()
		"clear_save":
			SaveSystem.reset_all()
			get_tree().paused = false
			get_tree().reload_current_scene()
		"quit_game":
			get_tree().quit()
	_pending_confirm = ""


# ---- 继续挑战（目标型胜利：过线结算后可回盘面，设计 §3/§5）----

## 继续挑战中离开（Q3/Q4）：不走放弃流程、不二次发矿、不记 abandon；
## 仅当累计分更高时刷新 best_score，并给最后一条盲测记录补 continued/continue_gain
func _leave_after_continue() -> void:
	get_tree().paused = false
	pause_panel.hide()
	tutorial_guide.hide()
	GameState.game_active = false
	var win_score: int = int(GameState.result_stats.get("win_score", 0))
	SaveSystem.refresh_best_score(GameState.score)
	SaveSystem.amend_last_playtest({
		"continued": true,
		"continue_gain": GameState.score - win_score,
		"final_score": GameState.score,
	})
	robot_manager.remove_all()
	_on_back_to_level_select()


func _on_idle_warning_changed(show: bool) -> void:
	hud.set_idle_warning(show)


func _on_robot_removed(_robot, reason: String) -> void:
	if reason == "detect_failed":
		hud.show_toast("检测失败！机器人自爆了", 3.0)


func _process(delta: float) -> void:
	if not GameState.game_active:
		return
	GameState.elapsed += delta
	GameState.tick_cd(delta)
	if GameState.continue_mode:
		# 继续挑战：倒计时冻结（CD 照计，乱插旗刷分自限依赖此）
		robot_manager.tick_all(delta, grid)
		return
	if GameState.has_time_limit():
		GameState.time_left -= delta
		GameState.time_changed.emit(GameState.time_left)
		if GameState.time_left <= 0:
			var obj := GameState.current_objective
			if obj != null and obj.type == ObjectiveData.Type.SURVIVE_TIME:
				_end_game("win")  # 生存目标：熬到时间到即胜利
			else:
				_end_game("timeout")
			return
	robot_manager.tick_all(delta, grid)
	enemy_manager.tick(delta, grid)  # L4 敌虫：与机器人同点驱动，pause/结算天然停摆


# ---- 初始基地放置阶段 ----

# 在 placing_base 阶段拦截所有点击，避免传到 Cell 触发开/标
func _input(event: InputEvent) -> void:
	# ESC：设置/暂停/引导等各层优先
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		_handle_escape()
		return
	# 任一菜单覆盖层显示时不处理游戏输入
	if not _in_game():
		return
	# 数字键 1-4 快捷放置机器人
	if event is InputEventKey and event.pressed and not event.echo:
		if _try_robot_shortcut(event.keycode):
			get_viewport().set_input_as_handled()
			return
	if GameState.game_phase == "placing_base":
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			_try_place_first_base_at(event.position)
			get_viewport().set_input_as_handled()
		return
	# L4 敌害实体命中优先于格子（设计 §9.9）：Godot 重叠 Area2D 全收到 input_event
	# 且 set_input_as_handled 不阻断传播（godot#29825）→ 改 _input 几何命中拦截。
	# 仅 game_active 时（放基地阶段点虫无效，回归清单 §5.5）；放置模式下放置优先
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and placing_mode == "":
		if _try_hit_enemy_at(event.position):
			get_viewport().set_input_as_handled()
			return
	if placing_mode == "":
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_try_place_at(event.position)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_exit_placing_mode()
			get_viewport().set_input_as_handled()


## ESC 分层：确认框/闪屏→吞掉 / 设置→关 / 暂停→恢复 / 引导→交给引导层 /
## 其他覆盖层→面板自行处理 / 局内→取消放置或开暂停
func _handle_escape() -> void:
	if splash.visible or confirm_dialog.visible:
		return
	if settings_panel.visible:
		settings_panel.hide()
		return
	if rules_panel.visible:
		rules_panel.close()
		return   # 露出下层：暂停或主菜单（只退一层）
	if playtest_done.visible:
		playtest_done.hide()
		return   # 露出下层：结算面板（只退一层）
	if pause_panel.visible:
		_resume()
		return
	if pre_level_card.visible:
		pre_level_card.hide()
		level_select.show()   # ESC 只退一层：回选关
		return
	if tutorial_guide.visible:
		return  # 引导层自行处理（跳过）
	if not _in_game():
		return
	if placing_mode != "":
		_exit_placing_mode()
	elif GameState.game_phase == "placing_base" or GameState.game_active:
		_open_pause()


## 数字键 1-4 快捷放置机器人；返回 true 表示按键已处理
func _try_robot_shortcut(keycode: Key) -> bool:
	if GameState.game_phase == "placing_base":
		return false  # 先放第一个基地
	var type := ""
	match keycode:
		KEY_1: type = "opener"
		KEY_2: type = "marker"
		KEY_3: type = "detector"
		KEY_4: type = "miner"
	if type == "":
		return false
	var reason: String = shop.lock_reason(type)
	if reason != "":
		hud.show_toast(reason, 2.0)
		return true
	if GameState.money < GameState.get_robot_price(type):
		hud.show_toast("金币不足", 2.0)
		return true
	return shop.try_buy(type)


func _try_place_first_base_at(world_pos: Vector2) -> bool:
	var coord := grid.world_to_coord(world_pos)
	if not _in_bounds(coord):
		return false
	if not grid.place_first_base(coord):
		return false
	# 基地放完，激活游戏开始倒计时
	GameState.game_active = true
	# L4 pregen 关：局外赠机此时落位（基地格旁，同固定盘口径）
	if not _pending_gifts.is_empty():
		_gift_start_robots(_pending_gifts)
		_pending_gifts = {}
	return true


## L4 敌害实体点击命中（几何测试：距实体中心 < 0.6 格即命中，Q9 初值）：
## 虫 = 点杀（吃 1 CD），巢 = 受击（吃 1 CD）；CD 检查与格子点击同口径
func _try_hit_enemy_at(world_pos: Vector2) -> bool:
	if not GameState.game_active:
		return false
	var hit_radius: float = grid.cell_size * 0.6
	# 先虫后巢（虫 z_index 更高、会压在巢上）
	for e in enemy_manager.enemies:
		if e.is_alive() and e.global_position.distance_to(world_pos) < hit_radius:
			if GameState.is_player_blocked():
				GameState.cd_blocked.emit()
				return true
			enemy_manager.kill_enemy(e, "player")
			GameState.consume_player_action()
			return true
	for n in enemy_manager.nests:
		if n.is_alive() and n.global_position.distance_to(world_pos) < hit_radius:
			if GameState.is_player_blocked():
				GameState.cd_blocked.emit()
				return true
			n.hit()  # HP-1 + 受击/摧毁动效（埋点在 destroyed 信号里）
			GameState.consume_player_action()
			return true
	return false


# ---- 放置模式（商店购买后）----

func _enter_placing_mode(mode: String) -> void:
	# mode: "opener"/"marker"/"detector"/"miner"/"guard"/"base"/"probe"/"charge_tower"/...
	# 价格检查留给实际放置时做（基地价格递增、机器人价格递增）
	if mode in ["opener", "marker", "detector", "miner", "guard"] \
			and GameState.money < GameState.get_robot_price(mode):
		return
	if mode == "base" and GameState.money < GameState.get_base_price():
		return
	if mode == "probe" and GameState.money < 100:  # L4 探测：100/次一次性瞬发
		return
	placing_mode = mode
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	shop.set_placing_hint(true)


func _exit_placing_mode() -> void:
	placing_mode = ""
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	grid.set_hover_overlay(Vector2i.ZERO, "hide")
	shop.set_placing_hint(false)


## 无副作用的放置判定：悬停预览与 _try_place_at 共用同一套规则（盘点 v1 §约束 2：
## 禁止另写近似规则）。钱判定与 purchase_robot / get_base_price 的实际扣费口径一致。
func can_place_at(coord: Vector2i) -> bool:
	if not _in_bounds(coord):
		return false
	var cell = grid.get_cell(coord)

	if placing_mode == "base":
		# 后续基地：必须在已开格上、不是基地/坍塌格
		return cell != null and cell.is_opened and not cell.is_base \
			and not cell.is_collapsed and GameState.money >= GameState.get_base_price()

	# L4 探测机器人：目标格任意（开/关均可，已确认格除外）
	if placing_mode == "probe":
		return cell != null and not cell.is_confirmed_mine and GameState.money >= 100

	# 机器人放置（opener / marker / detector / miner / guard 等）：可走格 + 一格一机 + 买得起
	if not grid.is_walkable(coord):
		return false
	if robot_manager.get_robot_positions().has(coord):
		return false
	return GameState.money >= GameState.get_robot_price(placing_mode)


func _try_place_at(world_pos: Vector2) -> bool:
	var coord := grid.world_to_coord(world_pos)
	if not can_place_at(coord):
		return false

	if placing_mode == "base":
		var price: int = GameState.get_base_price()
		_exit_placing_mode()
		GameState.add_money(-price)
		grid.place_base(coord)
		return true

	# L4 探测机器人：一次性瞬发；3×3 雷位标「确认雷」（机器人视同旗/不计分/穿锁）；
	# 不吃 CD（Q3：放置类口径）
	if placing_mode == "probe":
		_exit_placing_mode()
		GameState.add_money(-100)
		_trigger_probe(coord)
		return true

	var type := placing_mode
	_exit_placing_mode()

	if not GameState.purchase_robot(type):
		return false

	robot_manager.spawn_robot(coord, type, grid)
	GameState.robot_spawned.emit(type)
	# L4 埋点：保安购买时点（-1=未买）
	if type == "guard" and float(GameState.result_stats.get("guard_bought_elapsed", -1.0)) < 0.0:
		GameState.result_stats["guard_bought_elapsed"] = snappedf(GameState.elapsed, 0.1)
	return true


func _in_bounds(coord: Vector2i) -> bool:
	return coord.x >= 0 and coord.x < grid.rows and coord.y >= 0 and coord.y < grid.cols


# ---- 像素光标与悬停预览（素材：visual_v2/runtime/fx/，规格见盘点 v1）----

## 按形状注册像素光标；形状切换仍走 set_default_cursor_shape（放置=POINTING_HAND）。
## 热点按盘点 v1：arrow (1,1)、placing (1,1)。cursor_board 留作"准星 vs 箭头"实机 A/B 后启用。
func _register_custom_cursors() -> void:
	var arrow_tex: Texture2D = load("res://visual_v2/runtime/fx/cursor_arrow.png")
	if arrow_tex != null:
		Input.set_custom_mouse_cursor(arrow_tex, Input.CURSOR_ARROW, Vector2(1, 1))
	var placing_tex: Texture2D = load("res://visual_v2/runtime/fx/cursor_placing.png")
	if placing_tex != null:
		Input.set_custom_mouse_cursor(placing_tex, Input.CURSOR_POINTING_HAND, Vector2(1, 1))


## 退出前清掉自定光标：Input 单例活得比渲染服务器久，不清会在关窗时报
## RID 泄漏与 RenderingServer null 噪音（不影响游戏内，只影响退出日志）
func _exit_tree() -> void:
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_POINTING_HAND)


## 悬停状态机：首基地阶段/放置模式给合法性与真实判定同源的角框；
## 普通模式只在未开岩壁上给低亮四角（已开格读数字，不加干扰）；覆盖层打开时清预览
func _on_grid_cell_hovered(cell: Cell) -> void:
	if GameState.game_phase == "placing_base":
		grid.set_hover_overlay(cell.coord,
			"valid" if grid.can_place_first_base(cell.coord) else "invalid")
		return
	if not _in_game():
		grid.set_hover_overlay(cell.coord, "hide")
		return
	if placing_mode != "":
		grid.set_hover_overlay(cell.coord,
			"valid" if can_place_at(cell.coord) else "invalid")
	elif not cell.is_opened:
		grid.set_hover_overlay(cell.coord, "normal")
	else:
		grid.set_hover_overlay(cell.coord, "hide")


func _on_grid_cell_unhovered(_cell: Cell) -> void:
	grid.set_hover_overlay(Vector2i.ZERO, "hide")


## 开局赠送机器人：基地格 + 周围已开邻格依次落位（一格一机）。gifts: {"opener":1,...}
func _gift_start_robots(gifts: Dictionary) -> void:
	var base_coord: Vector2i = GameState.bases[0] if not GameState.bases.is_empty() \
			else Vector2i(grid.rows / 2, grid.cols / 2)
	var spots: Array = [base_coord]
	for n in grid.get_neighbors(base_coord):
		if n.is_opened and not n.is_base:
			spots.append(n.coord)
			if spots.size() >= 4:
				break
	for robot_type in gifts:
		for i in int(gifts[robot_type]):
			if spots.is_empty():
				return
			var coord: Vector2i = spots.pop_front()
			GameState.gift_robot(robot_type)
			robot_manager.spawn_robot(coord, robot_type, grid)
			GameState.robot_spawned.emit(robot_type)


# ---- 奖励逻辑（玩家和机器人走同一条通道）----

func _on_cell_opened(_cell, by_actor: String) -> void:
	if by_actor == "drone":
		return  # 无人机开的格子不给奖励
	GameState.add_money(1)
	GameState.add_score(1)
	GameState.result_stats["open_score"] += 1
	if by_actor == "player":
		GameState.result_stats["player_ops"] += 1
	elif by_actor.begins_with("robot_"):
		GameState.result_stats["robot_ops"] += 1


func _on_cell_flagged(_cell, by_actor: String, correct: bool, first_time: bool) -> void:
	if correct and not first_time:
		return  # 撤旗重插：无奖励无惩罚，也不计操作数（WP7 防刷）
	if correct and _cell.is_confirmed_mine:
		return  # L4 探测「确认雷」格再插旗不重复给分（设计 §5 同格首次原则）
	if correct:
		GameState.add_money(5)
		GameState.add_score(5)
		GameState.result_stats["flag_score"] += 5
		if by_actor == "player":
			GameState.result_stats["player_ops"] += 1
			GameState.notify_player_correct_flag()  # 免费阶段第 N 面正确旗触发耗尽
		elif by_actor.begins_with("robot_"):
			GameState.result_stats["robot_ops"] += 1
		var obj := GameState.current_objective
		if obj != null and obj.type == ObjectiveData.Type.FLAG_N_MINES:
			_flag_count += 1
			_update_objective_progress()
			if _flag_count >= obj.target_value:
				_end_game("win")
	else:
		# 设计 v1.1：标错旗无奖励无惩罚（原 -3 分废除），仅保留埋点统计
		GameState.result_stats["wrong_flags"] += 1


## L4 障碍清除埋点：玩家点清与保安清障分列（设计 §9.10 分工口径）
func _on_obstacle_cleared(_cell, _kind: String, by_actor: String) -> void:
	if by_actor == "player":
		GameState.result_stats["obstacles_cleared_player"] += 1
	elif by_actor == "robot_guard":
		GameState.result_stats["obstacles_cleared_guard"] += 1


func _on_mine_stepped(_cell, _by_actor: String) -> void:
	# 继续挑战中踩雷不扣命（防"胜利后又失败"坏状态，设计 §5）；格子坍塌照常浪费动作
	if GameState.continue_mode:
		return
	# 无命限制关：踩雷仅该格坍塌（坍塌已在 grid 层完成），无失败状态
	if not GameState.has_life_limit():
		return
	GameState.lose_life()
	if GameState.lives <= 0:
		_end_game("lose")


func _on_all_safe_opened() -> void:
	# 清空全部安全格即胜利（目标为 CLEAR_ALL_SAFE 或自由模式）
	var obj := GameState.current_objective
	if obj == null or obj.type == ObjectiveData.Type.CLEAR_ALL_SAFE:
		_end_game("win")


func _end_game(result: String) -> void:
	if not GameState.game_active:
		return
	GameState.game_active = false
	tutorial_guide.hide()  # 局末收起引导（未完成则下次 1-1 重来）
	if result == "win":
		var obj := GameState.current_objective
		if obj != null and obj.type == ObjectiveData.Type.REACH_SCORE:
			# 过线时刻埋点（时间加分入账前的行动分轨迹，盲测校准 §10）
			GameState.result_stats["crossing_elapsed"] = snappedf(GameState.elapsed, 0.1)
		_apply_time_bonus()
		# 结算分快照（继续挑战的增量口径，见 _leave_after_continue）
		GameState.result_stats["win_score"] = GameState.score
	# 局末目标快照（结算面板状态行「目标达成/未达成 + X/Y」）
	GameState.result_stats["obj_final_text"] = _update_objective_progress()
	GameState.game_over.emit(result)


## 胜利时间加分：剩余秒 × 关卡系数，计入总分与最高分口径（设计 §3，Q4 已定）
func _apply_time_bonus() -> void:
	var lvl := GameState.get_current_level()
	if lvl == null or lvl.time_bonus_per_sec <= 0 or not GameState.has_time_limit():
		return
	var secs := int(max(0.0, floor(GameState.time_left)))
	var bonus: int = secs * lvl.time_bonus_per_sec
	if bonus <= 0:
		return
	GameState.result_stats["time_bonus"] = bonus
	GameState.result_stats["time_bonus_secs"] = secs
	GameState.add_score(bonus)
	# 积分目标关的过线瞬间提示（设计 §4.2：过线即跳结算 + toast）
	var obj := GameState.current_objective
	if obj != null and obj.type == ObjectiveData.Type.REACH_SCORE:
		hud.show_toast("过线！+%d 分" % bonus, 3.0)


# ---- 目标进度 ----

func _on_score_changed(_v: int) -> void:
	_update_objective_progress()
	var obj := GameState.current_objective
	# 继续挑战中分数只累加，不再二次触发胜利（发奖/解锁/埋点只发生一次）
	if obj != null and obj.type == ObjectiveData.Type.REACH_SCORE \
			and GameState.score >= obj.target_value and not GameState.continue_mode:
		_end_game("win")


func _on_time_changed(_v: float) -> void:
	_update_objective_progress()


## 刷新 HUD 目标进度；返回进度文本（局末存 result_stats.obj_final_text 供结算显示）
func _update_objective_progress() -> String:
	var obj := GameState.current_objective
	if obj == null:
		GameState.objective_progress_updated.emit("", 0, 0)
		return ""
	var current: int = 0
	var total: int = 0   # 页面画细进度条的分母；0 = 该目标类型隐藏条
	match obj.type:
		ObjectiveData.Type.CLEAR_ALL_SAFE:
			total = grid.count_safe_total()
			current = total - grid.count_safe_remaining()   # 已完成数，不是剩余
		ObjectiveData.Type.REACH_SCORE:
			current = GameState.score
			total = obj.target_value
		ObjectiveData.Type.FLAG_N_MINES:
			current = _flag_count
		ObjectiveData.Type.SURVIVE_TIME:
			current = int(ceil(GameState.time_left))
		ObjectiveData.Type.ACTIVATE_N_TOWER:
			current = 0
	var text: String = obj.build_progress_text(current, total)
	GameState.objective_progress_updated.emit(text, current, total)
	return text


## L4 探测机器人：3×3 强制探雷（设计 §9.5）——雷位标「确认雷」
## 机器人视同旗（Solver 计雷）、不计标旗分、情报穿锁（锁只拦交互）；零分零钱纯情报
func _trigger_probe(center: Vector2i) -> void:
	var confirmed: int = 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c = grid.get_cell(center + Vector2i(dx, dy))
			if c != null and c.is_mine and not c.is_confirmed_mine:
				c.confirm_mine()
				confirmed += 1
	GameState.result_stats["probe_used"] += 1
	var coords: String = GameState.result_stats["probe_coords"]
	GameState.result_stats["probe_coords"] = (coords + ";" if coords != "" else "") \
			+ "%d,%d" % [center.x, center.y]
	grid.play_player_action_visual(center, Grid.FLY_ICON_OPEN)
	hud.show_toast("探测完成：%d 格确认雷" % confirmed, 2.5)
