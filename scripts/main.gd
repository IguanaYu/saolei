extends Node
## 主场景控制器：负责游戏主循环、玩家输入路由、模块协调、关卡流程
## 以及全套页面串联（闪屏/暂停/设置/档案/每日/签到/引导/结算）

@onready var grid: Grid = $Grid
@onready var robot_manager: RobotManager = $RobotManager
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

# 当前放置模式（商店点击购买/建造后置为 "opener"/"marker"/"base"/...）
var placing_mode: String = ""

# 试玩版第一关剧本控制器（_ready 时创建）
var level1_director: Level1Director = null

# 当前所在章节（"返回关卡选择"时用）
var _current_chapter_id: String = "ch01"
# FLAG_N_MINES 目标计数
var _flag_count: int = 0

# 确认框待执行动作
var _pending_confirm: String = ""

# 岩壁风格循环（F5 调试切换）：默认 A1 + 已拍板的 E 系 4 套
const WALL_STYLE_CYCLE := ["A1", "E1", "E2", "E3", "E4"]
const WALL_STYLE_NAMES := {
	"A1": "连体岩壁（默认）",
	"E1": "沙岩层窟",
	"E2": "冰晶裂谷",
	"E3": "苔藓菌窟",
	"E4": "遗迹砖窟",
}


func _ready() -> void:
	# 不立即 reset，等玩家选关进入
	grid.all_safe_opened.connect(_on_all_safe_opened)
	grid.cell_opened.connect(_on_cell_opened)
	grid.cell_flagged.connect(_on_cell_flagged)
	grid.mine_stepped.connect(_on_mine_stepped)
	robot_manager.idle_warning_changed.connect(_on_idle_warning_changed)
	robot_manager.robot_removed.connect(_on_robot_removed)
	main_menu.start_requested.connect(_on_start_adventure)
	main_menu.stats_requested.connect(func(): stats_panel.open())
	main_menu.daily_requested.connect(func(): daily_panel.open())
	main_menu.signin_requested.connect(func(): sign_in_panel.open())
	main_menu.settings_requested.connect(func(): settings_panel.open())
	chapter_select.chapter_selected.connect(_on_chapter_selected)
	chapter_select.back_requested.connect(_on_chapter_select_back)
	level_select.start_requested.connect(_on_start_game)
	level_select.back_requested.connect(_on_level_select_back)
	results_panel.restart_requested.connect(_on_restart_requested)
	results_panel.back_to_level_select_requested.connect(_on_back_to_level_select)
	results_panel.back_to_menu_requested.connect(_show_main_menu)
	results_panel.share_requested.connect(
		func(): hud.show_toast("分享功能开发中，先截个图吧！", 3.0))
	GameState.score_changed.connect(_on_score_changed)
	GameState.time_changed.connect(_on_time_changed)
	GameState.base_placed.connect(func(_c): tutorial_guide.notify_event("base_placed"))
	GameState.robot_spawned.connect(func(_t): tutorial_guide.notify_event("robot_bought"))
	# 闪屏 → 主菜单（+ 每日首启签到弹窗）
	splash.finished.connect(_on_splash_finished)
	main_menu.hide()  # 闪屏期间藏住主菜单
	# 暂停
	hud.pause_requested.connect(_toggle_pause)
	pause_panel.resume_requested.connect(_resume)
	pause_panel.restart_requested.connect(_on_pause_restart)
	pause_panel.settings_requested.connect(func(): settings_panel.open())
	pause_panel.abandon_requested.connect(_ask_abandon)
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
	# 试玩版第一关剧本控制器
	level1_director = Level1Director.new()
	level1_director.name = "Level1Director"
	add_child(level1_director)


# ---- 闪屏 / 主菜单 ----

func _on_splash_finished() -> void:
	main_menu.show()
	if not SaveSystem.can_sign_today():
		return
	var tw := create_tween()
	tw.tween_interval(0.3)
	tw.tween_callback(func(): sign_in_panel.open())


func _show_main_menu() -> void:
	results_panel.hide()
	pause_panel.hide()
	main_menu.show()


# ---- 关卡流程 ----

func _on_start_adventure() -> void:
	main_menu.hide()
	chapter_select.show()
	chapter_select.refresh()


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
	chapter_select.show()
	chapter_select.refresh()


func _on_start_game(level_id: String) -> void:
	_start_level(level_id)


func _on_restart_requested() -> void:
	if GameState.daily_mode:
		_start_daily()
	else:
		_start_level(GameState.current_level_id)


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
	GameState.reset_state(id, lvl)
	_flag_count = 0
	if lvl != null:
		if wall_style != "":
			grid.wall_style = wall_style
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
	robot_manager.remove_all()
	_update_objective_progress()
	_maybe_start_tutorial()


# ---- 新手引导 ----

func _maybe_start_tutorial() -> void:
	if GameState.daily_mode:
		return
	# 试玩版第一关：剧本教学每次进关都触发（不看 tutorial_done，盲测者每遍都要看到）
	if GameState.current_level_id == "ch01_s01" and level1_director != null:
		level1_director.begin()


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
			or sign_in_panel.visible or confirm_dialog.visible)


func _open_pause() -> void:
	_exit_placing_mode()  # 暂停时取消放置，避免恢复后状态混乱
	pause_panel.open(_pause_context())
	get_tree().paused = true


func _pause_context() -> String:
	if GameState.daily_mode:
		return "每日挑战 · %s" % SaveSystem.today_key()
	var lvl := GameState.get_current_level()
	if lvl == null:
		return ""
	var ch := LevelSystem.get_chapter(lvl.chapter_id)
	return "%s · %s" % [ch.display_name if ch != null else "", lvl.display_name]


func _resume() -> void:
	get_tree().paused = false
	pause_panel.hide()


func _on_pause_restart() -> void:
	_resume()
	_on_restart_requested()


func _ask_abandon() -> void:
	_pending_confirm = "abandon"
	var keep_ore: int = GameState.score / 20
	confirm_dialog.ask("放弃本局？",
		"本局积分与进度将清零\n已采集矿石按一半结算保留（+%d 矿）" % keep_ore,
		"确认放弃", "继续挖掘", true)


func _do_abandon() -> void:
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
	_show_main_menu()


# ---- 设置 / 清档 ----

func _on_tutorial_rewatch() -> void:
	hud.show_toast("第一关开场自带教学，进 1-1 即可", 3.0)


func _ask_clear_save() -> void:
	_pending_confirm = "clear_save"
	confirm_dialog.ask("清除全部存档？",
		"矿石、关卡进度、升级、统计与签到记录将全部清零\n（设置项保留）",
		"确认清除", "取消", true)


func _on_confirm_confirmed() -> void:
	match _pending_confirm:
		"abandon":
			_do_abandon()
		"clear_save":
			SaveSystem.reset_all()
			get_tree().paused = false
			get_tree().reload_current_scene()
	_pending_confirm = ""


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
		# F5 循环切换岩壁风格（A1 → E1-E4）：原地换肤不重置局面
		if event.keycode == KEY_F5:
			_cycle_wall_style()
			get_viewport().set_input_as_handled()
			return
	if GameState.game_phase == "placing_base":
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			_try_place_first_base_at(event.position)
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
	if pause_panel.visible:
		_resume()
		return
	if tutorial_guide.visible:
		return  # 引导层自行处理（跳过）
	if not _in_game():
		return
	if placing_mode != "":
		_exit_placing_mode()
	elif GameState.game_phase == "placing_base" or GameState.game_active:
		_open_pause()


## F5 循环切换岩壁风格：A1 → E1-E4 → A1
func _cycle_wall_style() -> void:
	var idx := WALL_STYLE_CYCLE.find(grid.wall_style)
	var next: String = WALL_STYLE_CYCLE[(idx + 1) % WALL_STYLE_CYCLE.size()]
	grid.set_wall_style(next)
	hud.show_toast("岩壁风格：%s" % WALL_STYLE_NAMES.get(next, next), 2.0)


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
	return true


# ---- 放置模式（商店购买后）----

func _enter_placing_mode(mode: String) -> void:
	# mode: "opener"/"marker"/"detector"/"miner"/"base"/"charge_tower"/...
	# 价格检查留给实际放置时做（基地价格递增、机器人价格递增）
	if mode in ["opener", "marker", "detector", "miner"] and GameState.money < GameState.get_robot_price(mode):
		return
	if mode == "base" and GameState.money < GameState.get_base_price():
		return
	placing_mode = mode
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	shop.set_placing_hint(true)


func _exit_placing_mode() -> void:
	placing_mode = ""
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	shop.set_placing_hint(false)


func _try_place_at(world_pos: Vector2) -> bool:
	var coord := grid.world_to_coord(world_pos)
	if not _in_bounds(coord):
		return false

	if placing_mode == "base":
		# 后续基地：必须在已开格上、不是基地
		var cell = grid.get_cell(coord)
		if cell == null or not cell.is_opened or cell.is_base or cell.is_collapsed:
			return false
		var price: int = GameState.get_base_price()
		if GameState.money < price:
			return false
		_exit_placing_mode()
		GameState.add_money(-price)
		grid.place_base(coord)
		return true

	# 机器人放置（opener / marker / detector / miner）
	if not grid.is_walkable(coord):
		return false
	if robot_manager.get_robot_positions().has(coord):
		return false  # 一格一机

	var type := placing_mode
	_exit_placing_mode()

	if not GameState.purchase_robot(type):
		return false

	robot_manager.spawn_robot(coord, type, grid)
	GameState.robot_spawned.emit(type)
	return true


func _in_bounds(coord: Vector2i) -> bool:
	return coord.x >= 0 and coord.x < grid.rows and coord.y >= 0 and coord.y < grid.cols


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


func _on_cell_flagged(_cell, by_actor: String, correct: bool) -> void:
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


func _on_mine_stepped(_cell, _by_actor: String) -> void:
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
	GameState.game_over.emit(result)


# ---- 目标进度 ----

func _on_score_changed(_v: int) -> void:
	_update_objective_progress()
	var obj := GameState.current_objective
	if obj != null and obj.type == ObjectiveData.Type.REACH_SCORE and GameState.score >= obj.target_value:
		_end_game("win")


func _on_time_changed(_v: float) -> void:
	_update_objective_progress()


func _update_objective_progress() -> void:
	var obj := GameState.current_objective
	if obj == null:
		GameState.objective_progress_updated.emit("")
		return
	var current: int = 0
	match obj.type:
		ObjectiveData.Type.CLEAR_ALL_SAFE:
			current = grid.count_safe_remaining()
		ObjectiveData.Type.REACH_SCORE:
			current = GameState.score
		ObjectiveData.Type.FLAG_N_MINES:
			current = _flag_count
		ObjectiveData.Type.SURVIVE_TIME:
			current = int(ceil(GameState.time_left))
		ObjectiveData.Type.ACTIVATE_N_TOWER:
			current = 0
	GameState.objective_progress_updated.emit(obj.build_progress_text(current))


## 无人机技能：打开 3 个最远关闭格
func _trigger_drone() -> void:
	if GameState.money < 100:
		return
	GameState.add_money(-100)
	var base_coord: Vector2i = GameState.bases[0] if not GameState.bases.is_empty() else Vector2i(8, 8)
	var coords: Array = grid.get_farthest_closed_cells(3, base_coord)
	for coord in coords:
		grid.open_cell(coord, "drone")
