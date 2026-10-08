extends Node
## 主场景控制器：负责游戏主循环、玩家输入路由、模块协调、关卡流程
## 以及全套页面串联（闪屏/暂停/设置/档案/每日/签到/引导/结算）

@onready var grid: Grid = $BoardRoot/Grid
@onready var robot_manager: RobotManager = $BoardRoot/RobotManager
@onready var enemy_manager: EnemyManager = $BoardRoot/EnemyManager
@onready var boss_manager: BossManager = $BoardRoot/BossManager
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
@onready var event_log_connector = $UILayer/EventLogConnector
@onready var escape_router = $UILayer/EscapeRouter

# 当前放置模式（"base"=建基地 / "probe"=探针；机器人已改直购直出，不走放置）
var placing_mode: String = ""

# ---- 高塔地图视口滚动（2026-10-04，docs/active/高塔地图-实施计划-v1.md §1.2）----
var _scroll_up_btn: Button = null
var _scroll_down_btn: Button = null
var _play_area_rect: Rect2 = Rect2()

# 试玩版第一/二/三/四关剧本控制器（_ready 时创建）
var level1_director: Level1Director = null
var level2_director: Level2Director = null
var level3_director: Level3Director = null
var level4_director: Level4Director = null
var level5_director: Level5Director = null
# 局外商店引导（L2 通关 → 结算/选关/主菜单聚光带去矿石商店买强化）
var shop_guide_director: ShopGuideDirector = null

# 当前所在章节（"返回关卡选择"时用）
var _current_chapter_id: String = "ch01"
# FLAG_N_MINES 目标计数
var _flag_count: int = 0

# 确认框待执行动作
var _pending_confirm: String = ""

# L4 pregen 关的开局赠机（放完基地后在基地旁落位）
var _pending_gifts: Dictionary = {}

# 踩雷全屏反馈（屏震+闪光）：世界层四节点同源震动用
var _shake_tween: Tween = null
var _shake_bases: Array[Vector2] = []
var _blast_flash: ColorRect = null

const CHAPTER_WALL_STYLES := ["V2", "V2C", "V2M", "V2R"]


func _ready() -> void:
	# 不立即 reset，等玩家选关进入
	_register_custom_cursors()
	# Esc 走 UILayer 下的 ALWAYS 路由器转发：暂停/规则等置 paused=true 的树里
	# main._input（可暂停）已停摆，"按 ESC 继续"不能只靠它（2026-10-03 盲测 F01）
	escape_router.escape_requested.connect(_handle_escape)
	grid.all_safe_opened.connect(_on_all_safe_opened)
	grid.cell_opened.connect(_on_cell_opened)
	grid.cell_flagged.connect(_on_cell_flagged)
	grid.mine_stepped.connect(_on_mine_stepped)
	grid.obstacle_cleared.connect(_on_obstacle_cleared)
	grid.processed_mines_changed.connect(_on_processed_mines_changed)
	grid.fire_extinguish_requested.connect(_on_fire_extinguish_requested)
	enemy_manager.enemy_killed.connect(_on_enemy_killed_forward)
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
	shop.upgrade_open_requested.connect(func(): upgrade_panel.open())
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
	# 近失激励（P0.4）：结算页「变强商店」按钮直达矿石商店（与主菜单/选关页同口径）
	results_panel.powerup_requested.connect(func(): ore_shop.open())
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
	# 教学出现时取消放置模式（回归 2026-10-01 P1：教学×放置重叠，跳过按钮被放置左键吞掉）
	tutorial_guide.visibility_changed.connect(func():
		if tutorial_guide.visible and placing_mode != "":
			_exit_placing_mode())
	# 基地阶段提示走商店提示行（回归 2026-10-01 P2：HUD 顶栏提示盖住 L5 Boss）
	GameState.game_phase_changed.connect(_on_game_phase_changed)
	# 窗口/F11 变化：统一重算棋盘可用区并联动重排（P1-04，本节点最后连接 =
	# grid/cave_env/tutorial 的即时处理器之后运行，读到的是最新 UI 边界）
	get_viewport().size_changed.connect(_relayout_play_area)
	# 高塔地图（2026-10-04）：视口滚动时逐帧重投影实体 + 刷新箭头按钮
	grid.view_changed.connect(_on_grid_view_changed)
	_scroll_up_btn = _make_scroll_button("▲")
	_scroll_down_btn = _make_scroll_button("▼")
	_scroll_up_btn.pressed.connect(func() -> void: grid.scroll_view(-1))
	_scroll_down_btn.pressed.connect(func() -> void: grid.scroll_view(1))
	# 闪屏 → 主菜单（+ 每日首启签到弹窗）
	splash.finished.connect(_on_splash_finished)
	main_menu.hide()  # 闪屏期间藏住主菜单
	# 经 BootLoading 加载页进入：闪屏职责已被加载页吸收，直接亮主菜单
	# （直接运行 Main.tscn 调试时标志为假，原闪屏照播，调试路径不受影响；
	# 只 hide 不 free——_in_game() 等处常驻访问 splash.visible，free 后会刷
	# "previously freed" 报错；残留的 finished 回调是幂等的 show+refresh，无害）
	if GameState.boot_splash_played:
		splash.hide()
		_on_splash_finished()
	# 暂停
	hud.pause_requested.connect(_toggle_pause)
	pause_panel.resume_requested.connect(_resume)
	pause_panel.rules_requested.connect(func(): rules_panel.open())
	pause_panel.settings_requested.connect(func(): settings_panel.open())
	pause_panel.restart_requested.connect(_ask_restart_run)
	pause_panel.quit_requested.connect(_ask_quit_to_select)
	pause_panel.menu_requested.connect(_ask_quit_to_menu)
	pause_panel.exit_requested.connect(_ask_exit_game)
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
	level5_director = Level5Director.new()
	level5_director.name = "Level5Director"
	add_child(level5_director)
	# 局外商店引导（横跨结算/选关/主菜单/商店的换屏自愈流程）
	shop_guide_director = ShopGuideDirector.new()
	shop_guide_director.name = "ShopGuideDirector"
	add_child(shop_guide_director)
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
	playtest_done.hide()  # 完成页按钮只发信号不自隐藏，接收端统一收起
	main_menu.show()
	main_menu.refresh()


# ---- 关卡流程 ----

func _on_continue_play() -> void:
	# 主按钮直进当前进度关：弹关前卡（首关教学在局内，见 director）
	# 首个未通关关由 LevelSystem 统一给出（全通 → 末关，与菜单"第 5 关"文案一致）
	main_menu.hide()
	_open_pre_level(LevelSystem.get_first_uncleared_level_id(_current_chapter_id))


func _on_select_level() -> void:
	main_menu.hide()
	_show_level_select()   # 绕过章节页；ChapterSelect 场景保留不用


## 统一选关页入口：先设章节并刷新再显示（P1-07：不初始化会露出空列表/陈旧详情）
func _show_level_select() -> void:
	level_select.set_chapter(_current_chapter_id)
	level_select.show()


func _ask_quit() -> void:
	_pending_confirm = "quit_game"
	confirm_dialog.ask("退出游戏？", "", "退出", "取消", false)


func _on_chapter_selected(ch_id: String) -> void:
	_current_chapter_id = ch_id
	chapter_select.hide()
	_show_level_select()


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
	# 章节顺序表找后继（P1-06：substr(-1).to_int() 对 "ch01_s01" 恒得 0，任何关都会跳回第 1 关）
	var next_id := LevelSystem.get_next_level_id(GameState.current_level_id)
	if next_id == "":
		return  # 章末无后继（按钮本已隐藏，防御性返回）
	_open_pre_level(next_id)


## 试玩完成页（s05 达标经结算 BackButton 进入）
func _open_playtest_done() -> void:
	results_panel.hide()
	playtest_done.open()


func _on_back_to_level_select() -> void:
	results_panel.hide()
	playtest_done.hide()  # 完成页返回路径同 _show_main_menu：面板不残留
	_show_level_select()


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
	_close_level_overlays()  # 上一局的升级面板/放置预览/光标不带到新关（P1-03）
	get_tree().paused = false
	var id := lvl.id if lvl != null else ""
	SaveSystem.mark_level_entered(id)  # 间场「变强」高亮依据（进关即记）
	GameState.reset_state(id, lvl)
	event_log_connector.clear_logs()  # 侧栏事件流随新局清空（重开/换关同口径）
	if GameState.assist_active:
		GameState.game_event_logged.emit("挑战援助生效：本关 +1 命", "player", "good")
	_flag_count = 0
	robot_manager.remove_all()
	enemy_manager.clear()  # 上一局的虫/巢/波次全部清空（重开新盘；须在 setup_board 之前）
	boss_manager.clear()   # 上一局的 Boss 实体/阶段状态清空（非 Boss 关为空操作）
	if lvl != null:
		var chapter_number := int(lvl.chapter_id.trim_prefix("ch"))
		var chapter_style: String = CHAPTER_WALL_STYLES[clampi(int((chapter_number - 1) / 3.0), 0, 3)]
		grid.wall_style = wall_style if wall_style != "" else chapter_style
		grid.shape_rows = lvl.shape_mask.duplicate()  # 形状掩码（空=矩形，普通关不受影响）
		grid.configure(lvl.grid_size.x, lvl.grid_size.y, lvl.mine_count)
		_relayout_play_area()  # 棋盘在扣除 HUD/商店后的可用区内居中（P1-04）
		$CaveEnv.layout_env()  # 地图尺寸变化后重排洞窟边框/道具（读的是已更新的棋盘位）
		# 固定盘面：直接装载雷位/预开区/预置基地，跳过放基地阶段
		if lvl.has_fixed_board():
			grid.apply_fixed_board({
				"mines": lvl.fixed_mines,
				"preopen": lvl.preopen_coords,
				"base": lvl.fixed_base,
				"fossils": lvl.fixed_fossils,
			})
			# L4/L5 Boss 关（fixed_base=(-1,-1) 玩家自放）：保持 placing_base 阶段，
			# 放完基地才 game_active（同 L4 口径，倒计时从放基地起算）
			if lvl.fixed_base != Vector2i(-1, -1):
				GameState.game_active = true
			# L4 除害关（pests）：固定盘装载后布置裂缝+预置虫害（同原随机盘口径，
			# 放基地前即可见，剧本 #0）
			if lvl.pests:
				enemy_manager.setup_board(grid)
			# 预开算分（设计 v1.2）：只计分不计钱；300 > 预开上限 115，不会开局误判过线
			if lvl.preopen_scores:
				GameState.add_score(lvl.preopen_coords.size(), "preopen")
		# 随机盘（L4 除害关）：进关预生成雷+洪水预开，不设 game_active——
		# 放完基地才激活（波次计时随之从放基地起算，elapsed 只在 active 后累计）
		elif lvl.pregen_random:
			grid.apply_random_board()
			enemy_manager.setup_board(grid)
		# L5 Boss 关（FIND_ALL_MINES 目标 = 有 Boss 的关）：实体+阶段机就位（安静 Boss 关
		# 的招式表在 M2-M4 逐阶段填实；盘外锚点定位不依赖基地摆放）
		var obj0 = lvl.objectives[0] if not lvl.objectives.is_empty() else null
		if obj0 != null and obj0.type == ObjectiveData.Type.FIND_ALL_MINES:
			boss_manager.setup(grid, lvl.mine_count)
			enemy_manager.waves_enabled = false  # L5 不放 L4 三虫波次（实施计划 §1.2 缺口）
	# 开局赠送机器人 = 关卡自带 + 局外 start_robot 购买（meta 关才吃局外，Q2：计入 count）
	var gifts: Dictionary = lvl.start_robots.duplicate() if lvl != null else {}
	if lvl != null and lvl.meta_progression:
		var sr: int = int(SaveSystem.unlocks.get("start_robot", 0))
		if sr >= 1:
			gifts["opener"] = int(gifts.get("opener", 0)) + 1
		if sr >= 2:
			gifts["marker"] = int(gifts.get("marker", 0)) + 1
	# 基地玩家自放（L4/L5）：赠机压到放完基地后落位（此时还没有基地）；
	# 预置基地的关立即落位。pregen_random 为裸随机遗留路径，口径相同
	var player_places_base: bool = lvl != null and (lvl.pregen_random \
			or (lvl.has_fixed_board() and lvl.fixed_base == Vector2i(-1, -1)))
	if not gifts.is_empty() and lvl != null and not player_places_base:
		_gift_start_robots(gifts)
	elif not gifts.is_empty() and lvl != null:
		_pending_gifts = gifts
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
	tutorial_guide.reset_run()
	# 每关教学单独记次：看过一次（含跳过）整段不再播；重看入口=设置里重置标记
	# 2026-10-04 修复：新关卡（如 ch01_s06）的标志键从未写入时 get_value 返回 null，
	# bool(null) 在 4.x 是非法构造会报 SCRIPT ERROR——null 视同"未播过"，正常走教学判断
	var tutorial_done: Variant = GameSettings.get_value(
		"tutorial_done_" + GameState.current_level_id)
	if tutorial_done == null or tutorial_done:
		return
	if GameState.current_level_id == "ch01_s01" and level1_director != null:
		level1_director.begin()
	elif GameState.current_level_id == "ch01_s02" and level2_director != null:
		level2_director.begin()
	elif GameState.current_level_id == "ch01_s03" and level3_director != null:
		level3_director.begin()
	elif GameState.current_level_id == "ch01_s04" and level4_director != null:
		level4_director.begin()
	elif GameState.current_level_id == "ch01_s05" and level5_director != null:
		level5_director.begin()


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


## 收起局内浮层与放置预览（幂等）：结算/退出/重玩/新局开始统一调用，
## 顺带复位光标形状与商店提示行（_exit_placing_mode 全覆盖这三件）
func _close_level_overlays() -> void:
	upgrade_panel.close()
	_exit_placing_mode()


## 基地阶段提示：走商店提示行（底部固定区），不放 HUD 顶栏——顶栏下沿与
## L4/L5 Boss 趴框重叠（回归 2026-10-01 P2）。两个自放基地的关（L4 随机盘/L5 固定盘）
## 都只允许已开格，文案按此口径
func _on_game_phase_changed(phase: String) -> void:
	match phase:
		"placing_base":
			shop.set_placing_hint(true, "请放置第一个基地（点击已开格）")
		"playing":
			if placing_mode == "":
				shop.set_placing_hint(false)


## 棋盘可用区域 = 视口 − HUD 顶栏 − 底部商店（P1-04：棋盘/洞窟框/教学高亮不再压商店）。
## 进关与窗口变化时重算；联动 grid 居中 → 场上实体按缓存 coord 重投影 → 教学聚光重摆。
## CaveEnv 自订阅 viewport 变化（deferred），此时读到的已是更新后的 grid 位置
func _relayout_play_area() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var top: float = hud.get_global_rect().end.y
	var shop_top: float = shop.get_global_rect().position.y
	_play_area_rect = Rect2(0.0, top, vp.x, maxf(0.0, shop_top - top))
	grid.set_play_area(_play_area_rect)
	robot_manager.reproject_all(grid)
	enemy_manager.reproject_all(grid)
	boss_manager.on_grid_relaid(grid)
	_update_scroll_buttons()
	if tutorial_guide.visible:
		tutorial_guide._relayout_current()


## 高塔地图：滚动箭头按钮（半透明覆盖在棋盘可视窗顶/底中央，仅可滚方向显示）
func _make_scroll_button(label_text: String) -> Button:
	var b := Button.new()
	b.text = label_text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(96.0, 30.0)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		var alpha := 0.45 if state == "normal" else (0.75 if state == "hover" else 0.6)
		style.bg_color = Color(0.07, 0.08, 0.11, alpha)
		style.border_color = Color(0.85, 0.72, 0.45, 0.8)
		style.set_border_width_all(1)
		style.set_corner_radius_all(6)
		if state == "pressed":
			style.bg_color = Color(0.2, 0.16, 0.09, 0.85)
		b.add_theme_stylebox_override(state, style)
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", Color(0.92, 0.85, 0.66))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.8))
	$UILayer.add_child(b)
	b.visible = false
	return b


func _on_grid_view_changed(_view_top_px: float) -> void:
	# 滚动补间逐帧回调：实体重投影（管理器现成接口）+ 按钮态刷新
	robot_manager.reproject_all(grid)
	enemy_manager.reproject_all(grid)
	boss_manager.on_grid_relaid(grid)
	_update_scroll_buttons()


func _update_scroll_buttons() -> void:
	if _scroll_up_btn == null:
		return
	var scrollable: bool = grid != null and is_instance_valid(grid) and grid.view_range_px() > 0.0
	var in_game: bool = GameState.game_active or GameState.game_phase == "placing_base"
	var show_any: bool = scrollable and in_game and not get_tree().paused
	var center_x: float = _play_area_rect.get_center().x - 48.0 if _play_area_rect.size.x > 0.0 \
			else get_viewport().get_visible_rect().size.x / 2.0 - 48.0
	_scroll_up_btn.visible = show_any and grid.can_scroll_up()
	_scroll_down_btn.visible = show_any and grid.can_scroll_down()
	_scroll_up_btn.position = Vector2(center_x, _play_area_rect.position.y + 4.0)
	_scroll_down_btn.position = Vector2(center_x, _play_area_rect.end.y - 34.0)


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


## 返回主菜单（确认框）：结算口径同返回选关，终点为主菜单
func _ask_quit_to_menu() -> void:
	if GameState.continue_mode:
		_pending_confirm = "leave_continue_menu"
		confirm_dialog.ask("离开本局？",
			"胜利结算已入账\n继续挑战的分数将计入最高分",
			"确认离开", "继续挖掘", true)
		return
	_pending_confirm = "quit_to_menu"
	var keep_ore: int = GameState.score / 20
	confirm_dialog.ask("返回主菜单？",
		"本局按放弃结算：积分清零，矿石按一半保留（+%d 矿）" % keep_ore,
		"确认返回", "继续挖矿", true)


## 退出游戏（确认框）：先按放弃口径结算入档，再关进程（免得局内退出绕过账本）
func _ask_exit_game() -> void:
	if GameState.continue_mode:
		_pending_confirm = "exit_game"
		confirm_dialog.ask("退出游戏？",
			"胜利结算已入账\n继续挑战的分数将计入最高分",
			"退出", "取消", true)
		return
	_pending_confirm = "exit_game"
	var keep_ore: int = GameState.score / 20
	confirm_dialog.ask("退出游戏？",
		"本局按放弃结算：积分清零，矿石按一半保留（+%d 矿）" % keep_ore,
		"退出", "取消", true)


## 放弃结算：半矿入账 + 局面清理（终点由调用方决定）
func _abandon_settle() -> void:
	get_tree().paused = false
	pause_panel.hide()
	tutorial_guide.hide()
	_close_level_overlays()  # 放弃离开：放置预览/光标/提示行一并复位
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
	_show_level_select()


# ---- 设置 / 清档 ----

func _on_tutorial_rewatch() -> void:
	for i in range(1, 6):
		GameSettings.set_value("tutorial_done_ch01_s0%d" % i, false)
	GameSettings.set_value("tutorial_done_shop_guide", false)  # 局外商店引导一并重置（重置后仍需处于窗口期才会重播）
	hud.show_toast("各关教学已重置，重新进关即可重看", 3.0)


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
		"quit_to_menu":
			_abandon_settle()
			_show_main_menu()
		"leave_continue":
			_leave_after_continue(false)
		"leave_continue_menu":
			_leave_after_continue(true)
		"exit_game":
			if GameState.continue_mode:
				# 继续挑战中退出：与离开同口径——不记 abandon，仅刷新最高分
				SaveSystem.refresh_best_score(GameState.score)
			else:
				_abandon_settle()
			get_tree().quit()
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
## to_menu=true 终点为主菜单（暂停面板"返回主菜单"），否则回选关页
func _leave_after_continue(to_menu: bool = false) -> void:
	get_tree().paused = false
	pause_panel.hide()
	tutorial_guide.hide()
	_close_level_overlays()  # 离开路径与放弃同口径：浮层/预览不残留
	GameState.game_active = false
	var win_score: int = int(GameState.result_stats.get("win_score", 0))
	SaveSystem.refresh_best_score(GameState.score)
	SaveSystem.amend_last_playtest({
		"continued": true,
		"continue_gain": GameState.score - win_score,
		"final_score": GameState.score,
	})
	robot_manager.remove_all()
	if to_menu:
		_show_main_menu()
	else:
		_on_back_to_level_select()


func _on_idle_warning_changed(show: bool) -> void:
	hud.set_idle_warning(show)


func _on_robot_removed(_robot, reason: String) -> void:
	if reason == "detect_failed":
		hud.show_toast("检测失败！机器人自爆了", 3.0)


func _process(delta: float) -> void:
	if not GameState.game_active:
		_update_scroll_buttons()  # 高塔：结算/退出局面收起箭头（game_active 翻转的那一帧）
		return
	# 引导=教学停摆：计时/CD/机器人/敌虫全冻结（todo 卡点三）。剧本步骤等的是玩家
	# 输入事件（board_click 等，不经 _process），早退不影响推进；后续剧本若新增
	# 「等机器人干活」类事件，需回来放开 robot_manager.tick
	if tutorial_guide.visible:
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
	boss_manager.tick(delta, grid)   # L5 Boss：阶段机/出招计时（非 Boss 关 tick 内部短路）


# ---- 初始基地放置阶段 ----

# 在 placing_base 阶段拦截所有点击，避免传到 Cell 触发开/标
func _input(event: InputEvent) -> void:
	# Esc 已移交流程见 _ready：EscapeRouter（UILayer/ALWAYS）转发到 _handle_escape，
	# 暂停树里本函数已停摆，不能再承担 Esc 分层（2026-10-03 盲测 F01）
	# 教学可见时，落在教学控件（气泡/跳过）上的点击放行给它们，不走局内输入
	# （放置模式会 set_input_as_handled 把「跳过」的左键吞掉，回归 2026-10-01 P1）
	if tutorial_guide.visible and event is InputEventMouseButton \
			and tutorial_guide.is_point_on_chrome(event.position):
		return
	# 任一菜单覆盖层显示时不处理游戏输入
	if not _in_game():
		return
	# 数字键 1-4 快捷放置机器人
	if event is InputEventKey and event.pressed and not event.echo:
		if _try_robot_shortcut(event.keycode):
			get_viewport().set_input_as_handled()
			return
	# 高塔地图：滚轮滚动视口（与箭头按钮同一步长/补间；不可滚时是空操作）
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			grid.scroll_view(-1)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			grid.scroll_view(1)
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
		_on_back_to_level_select()  # 完成页 ESC 与返回按钮同路径（P1-07/N10：裸 hide 会露出未清理棋盘）
		return
	if pause_panel.visible:
		_resume()
		return
	if pre_level_card.visible:
		pre_level_card.hide()
		_show_level_select()   # ESC 只退一层：回选关（统一入口，先设章节再显示，P1-07）
		return
	if tutorial_guide.visible:
		return  # 引导层自行处理（跳过）
	if upgrade_panel.visible:
		upgrade_panel.close()
		return  # 局内升级浮层：ESC 先收它，再按原规则开暂停
	if ore_shop.visible:
		ore_shop.hide()
		return  # 矿石商店浮层（主菜单/选关/结算页均可开）：ESC 只退一层先收它
	if not _in_game():
		return
	if placing_mode != "":
		_exit_placing_mode()
	elif GameState.game_phase == "placing_base" or GameState.game_active:
		_open_pause()


## 数字键 1-4 快捷放置机器人；返回 true 表示按键已处理
## 键位映射与商店角标（Shop.tscn 各按钮 KeyBadge"按1-按4"）同源，改键位需两处同步
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
	# 高塔地图：基地落在当前视口外时平滑滚过去（防"基地在屏外"）
	grid.snap_view_to_coord(coord)
	# L4 pregen 关：局外赠机此时落位（基地格旁，同固定盘口径）
	if not _pending_gifts.is_empty():
		_gift_start_robots(_pending_gifts)
		_pending_gifts = {}
	return true


## L4/L5 敌害实体点击命中（几何测试：距实体中心 < 0.6 格即命中，Q9 初值）：
## 炸弹 > 虫/史莱姆 > 巢（设计 §7 点击优先级链；全部吃 1 CD，CD 检查与格子点击同口径）
## 可点条件（全虫种+巢统一，2026-10-05）：本体格或邻 8 格属玩家领土（基地沿已开格连通，
## 设计 §5.1 开路接近）——隔空点杀被拦截、不耗 CD（压暗态自解释）
func _try_hit_enemy_at(world_pos: Vector2) -> bool:
	if not GameState.game_active:
		return false
	var hit_radius: float = grid.cell_size * 0.7
	# L5 落弹最优先（引信期才可点：阴影期未落地、爆炸期已结束）
	if boss_manager.active:
		var bomb := boss_manager.hit_bomb_at(world_pos, hit_radius)
		if bomb != null:
			if GameState.is_player_blocked():
				GameState.cd_blocked.emit()
				return true
			bomb.deflect(boss_manager)  # 奖励/硬直/顺延在 on_bomb_deflected
			GameState.consume_player_action()
			return true
		# L5 触手根部次之（点根 = 整条断裂；Q10 半径稍大）
		var tentacle := boss_manager.hit_tentacle_root_at(world_pos, grid.cell_size * 0.8)
		if tentacle != null:
			if GameState.is_player_blocked():
				GameState.cd_blocked.emit()
				return true
			tentacle.cut_by_player()
			GameState.add_money(15, "player_combat")
			GameState.add_score(15, "combat")
			GameState.game_event_logged.emit("你 斩断触手 +15金", "player", "player")
			GameState.result_stats["tentacles_cut"] += 1
			GameState.consume_player_action()
			return true
	hit_radius = grid.cell_size * 0.6
	# 先虫后巢（虫 z_index 更高、会压在巢上）
	for e in enemy_manager.enemies:
		if e.is_alive() and e.global_position.distance_to(world_pos) < hit_radius:
			if not e.is_clickable(grid):
				return true  # 命中但未开路接近：拦截穿透、不耗 CD（Q2 压暗态自解释）
			if GameState.is_player_blocked():
				GameState.cd_blocked.emit()
				return true
			enemy_manager.kill_enemy(e, "player")
			GameState.consume_player_action()
			return true
	for n in enemy_manager.nests:
		if n.is_alive() and n.global_position.distance_to(world_pos) < hit_radius:
			if not n.is_clickable(grid):
				return true  # 巢同口径：拆格扩散到盘边才能点（拦截穿透、不耗 CD）
			if GameState.is_player_blocked():
				GameState.cd_blocked.emit()
				return true
			n.hit()  # HP-1 + 受击/摧毁动效（埋点在 destroyed 信号里）
			GameState.consume_player_action()
			return true
	return false


# ---- 放置模式（商店购买后）----

func _enter_placing_mode(mode: String) -> void:
	# mode: "base"=建基地 / "probe"=探针（价格检查留给实际放置时做，基地价递增）
	if mode == "base" and GameState.money < GameState.get_base_price():
		return
	if mode == "probe" and GameState.money < GameState.PROBE_PRICE:
		return
	placing_mode = mode
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	shop.set_placing_hint(true, _placing_hint_text(mode))


func _exit_placing_mode() -> void:
	placing_mode = ""
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	grid.set_hover_overlay(Vector2i.ZERO, "hide")
	grid.set_probe_preview(false)
	shop.set_placing_hint(false)


## 放置提示按对象类型给出费用与落点规则（P2-03：不再全部共用"点击地图放置机器人"）
func _placing_hint_text(mode: String) -> String:
	match mode:
		"base":
			return "建基地 ¥%d：点已开格（不能是基地/坍塌格）· 右键/ESC 取消" \
					% GameState.get_base_price()
		"probe":
			return "探测 ¥%d：点目标格，确认其周围 3×3 的雷 · 右键/ESC 取消" % GameState.PROBE_PRICE
		_:
			return ""


## 非法落点短原因（P2-03）：""=可放置；can_place_at 与 _try_place_at 共用同一套规则
func place_block_reason(coord: Vector2i) -> String:
	if not _in_bounds(coord):
		return "盘外"
	var cell = grid.get_cell(coord)

	if placing_mode == "base":
		if cell == null or not cell.is_opened:
			return "基地要放在已开格"
		if cell.is_base:
			return "这里已是基地"
		if cell.is_collapsed:
			return "坍塌格不能建基地"
		if GameState.money < GameState.get_base_price():
			return "金币不够"
		return ""

	# L4 探测：目标格任意（开/关均可，已确认格除外）
	if placing_mode == "probe":
		if cell == null:
			return "盘外"
		if cell.is_fossil:
			return "化石下不会有雷"
		if cell.is_confirmed_mine:
			return "这格已是确认雷"
		if GameState.money < GameState.PROBE_PRICE:
			return "金币不够"
		return ""

	return ""


## 无副作用的放置判定：悬停预览与 _try_place_at 共用同一套规则（盘点 v1 §约束 2：
## 禁止另写近似规则）。钱判定与 purchase_robot / get_base_price 的实际扣费口径一致。
func can_place_at(coord: Vector2i) -> bool:
	return place_block_reason(coord) == ""


func _try_place_at(world_pos: Vector2) -> bool:
	var coord := grid.world_to_coord(world_pos)
	if not can_place_at(coord):
		# 非法落点给短原因（P2-03：不再只有红角框静默失败）
		hud.show_toast(place_block_reason(coord), 1.5)
		return false

	if placing_mode == "base":
		var price: int = GameState.get_base_price()
		_exit_placing_mode()
		GameState.add_money(-price)
		GameState.game_event_logged.emit("建造基地 −%d金" % price, "player", "player")
		grid.place_base(coord)
		return true

	# L4 探测机器人：一次性瞬发；3×3 雷位标「确认雷」（机器人视同旗/不计分/穿锁）；
	# 不吃 CD（Q3：放置类口径）
	if placing_mode == "probe":
		_exit_placing_mode()
		GameState.add_money(-GameState.PROBE_PRICE)
		GameState.game_event_logged.emit("放置探针 −%d金" % GameState.PROBE_PRICE, "player", "player")
		_trigger_probe(coord)
		return true

	return true


## 直购直出（2026-10-02 优化）：机器人不再手动放置，购买后自动从最新基地旁出生。
## 找不到空位时直接拒单不扣钱。锁定/余额检查在调用方（shop.can_buy / 快捷键）
func _buy_and_spawn_robot(robot_type: String) -> bool:
	var spot := _find_spawn_spot_near_base()
	if spot == Vector2i(-1, -1):
		hud.show_toast("基地周围没有空位", 2.0)
		return false
	var robot_price: int = GameState.get_robot_price(robot_type)  # 购前取价（阶梯在购买后抬升）
	if not GameState.purchase_robot(robot_type):
		return false
	# 出生演出从最新基地出发（与 _find_spawn_spot_near_base 的 BFS 起点同源）
	robot_manager.spawn_robot(spot, robot_type, grid, GameState.bases.back())
	GameState.game_event_logged.emit("购入 %s −%d金" % [
		{"opener": "开墙", "marker": "标雷", "detector": "检测", "miner": "矿工",
			"guard": "保安"}.get(robot_type, robot_type), robot_price], "player", "player")
	GameState.robot_spawned.emit(robot_type)
	# L4 埋点：保安购买时点（-1=未买）
	if robot_type == "guard" and float(GameState.result_stats.get("guard_bought_elapsed", -1.0)) < 0.0:
		GameState.result_stats["guard_bought_elapsed"] = snappedf(GameState.elapsed, 0.1)
	return true


## 最新基地旁 BFS 找最近可站格（已开+无阻断+一格一机，基地格自身可站——同开局赠机口径）；
## 全场无空位返回 (-1,-1)
func _find_spawn_spot_near_base() -> Vector2i:
	if GameState.bases.is_empty():
		return Vector2i(-1, -1)
	var occupied: Dictionary = robot_manager.get_robot_positions()
	var queue: Array = [GameState.bases.back()]
	var visited: Dictionary = {queue[0]: true}
	while not queue.is_empty():
		var pos: Vector2i = queue.pop_front()
		if grid.is_walkable(pos) and not occupied.has(pos):
			return pos
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = pos + o
			if not visited.has(n) and grid.cells.has(n):
				visited[n] = true
				queue.append(n)
	return Vector2i(-1, -1)


func _in_bounds(coord: Vector2i) -> bool:
	# 2026-10-04 修复：原实现把 rows/cols 写反（coord.x < grid.rows），方形盘无症状，
	# 每日挑战非方形盘（cols>rows）右侧列放不了首基地。改为按实际存在格判断，
	# 同时天然支持未来任意形状地图（调研 §6.1）。
	return grid.cells.has(coord)


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
		grid.set_probe_preview(placing_mode == "probe", cell.coord)
	elif not cell.is_opened:
		grid.set_hover_overlay(cell.coord, "normal")
	else:
		grid.set_hover_overlay(cell.coord, "hide")


func _on_grid_cell_unhovered(_cell: Cell) -> void:
	grid.set_hover_overlay(Vector2i.ZERO, "hide")
	grid.set_probe_preview(false)


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
	var gifted := []
	var delay := 0.0  # 出生演出错开：开局连赠多台不叠成特效弹幕
	for robot_type in gifts:
		for i in int(gifts[robot_type]):
			if spots.is_empty():
				break
			var coord: Vector2i = spots.pop_front()
			GameState.gift_robot(robot_type)
			robot_manager.spawn_robot(coord, robot_type, grid, base_coord, delay)
			GameState.robot_spawned.emit(robot_type)
			gifted.append(robot_type)
			delay += 0.18
	if not gifted.is_empty():
		var counts := {}
		for t in gifted:
			counts[t] = counts.get(t, 0) + 1
		var parts := []
		for t in counts:
			parts.append("%s×%d" % [{"opener": "开墙", "marker": "标雷", "detector": "检测",
				"miner": "矿工", "guard": "保安"}.get(t, t), counts[t]])
		GameState.game_event_logged.emit("开局赠送 " + " ".join(parts), "player", "good")


# ---- 奖励逻辑（玩家和机器人走同一条通道）----

func _on_cell_opened(_cell, by_actor: String) -> void:
	if by_actor == "drone":
		return  # 无人机开的格子不给奖励
	GameState.add_money(1, "player_open" if by_actor == "player"
			else "robot_open" if by_actor.begins_with("robot_") else "")
	GameState.add_score(1, "open")
	if by_actor == "player":
		GameState.result_stats["player_ops"] += 1
	elif by_actor.begins_with("robot_"):
		GameState.result_stats["robot_ops"] += 1
	# 打折的清空目标（L4 开 N 格）：每次开格后判达标（口径 = 已开安全格，含预开）
	var obj := GameState.current_objective
	if obj != null and obj.type == ObjectiveData.Type.CLEAR_ALL_SAFE and obj.target_value > 0:
		var opened_count: int = grid.count_safe_total() - grid.count_safe_remaining()
		_update_objective_progress()
		if opened_count >= obj.target_value and GameState.game_active:
			_end_game("win")


func _on_cell_flagged(_cell, by_actor: String, correct: bool, first_time: bool) -> void:
	if correct and not first_time:
		return  # 撤旗重插：无奖励无惩罚，也不计操作数（WP7 防刷）
	if correct and _cell.is_confirmed_mine:
		return  # L4 探测「确认雷」格再插旗不重复给分（设计 §5 同格首次原则）
	if correct:
		GameState.add_money(5, "player_flag" if by_actor == "player" else "robot_flag")
		GameState.add_score(5, "flag")
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
	_play_mine_blast_fx()  # 屏震+闪光：坍塌即爆炸，先于继续挑战/无命关的早退分支
	# 继续挑战中踩雷不扣命（防"胜利后又失败"坏状态，设计 §5）；格子坍塌照常浪费动作
	if GameState.continue_mode:
		return
	# 无命限制关：踩雷仅该格坍塌（坍塌已在 grid 层完成），无失败状态
	if not GameState.has_life_limit():
		return
	GameState.lose_life()
	if GameState.lives <= 0:
		_end_game("lose")


## 踩雷全屏反馈：世界层同源屏震（0.25s 平方衰减）+ UILayer 顶层暖白闪光（0.35s）
## Grid/Robot/Enemy/Boss 四节点共用同一偏移——只摇棋盘会让机器人"钉在原地"穿帮
func _play_mine_blast_fx() -> void:
	var world_nodes: Array[Node2D] = [grid, robot_manager, enemy_manager, boss_manager]
	# 震动开始才采基点：棋盘位置随 _relayout_play_area 变化，不能在 _ready 采
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
		_restore_world_positions(world_nodes)
	_shake_bases.clear()
	for n in world_nodes:
		_shake_bases.append(n.position)
	const AMP := 6.0
	_shake_tween = create_tween()
	_shake_tween.tween_method(
		func(k: float):
			var decay: float = (1.0 - k) * (1.0 - k)
			var offset := Vector2(randf_range(-AMP, AMP), randf_range(-AMP, AMP)) * decay
			for i in world_nodes.size():
				world_nodes[i].position = _shake_bases[i] + offset,
		0.0, 1.0, 0.25)
	_shake_tween.finished.connect(func(): _restore_world_positions(world_nodes))
	# 闪光：全屏暖白不挡鼠标；连炸时旧闪先离树再释放（queue_free 拖到帧末，
	# 同帧新建会撞名被改名 @2，违反显式命名规矩）
	if _blast_flash != null and is_instance_valid(_blast_flash):
		_blast_flash.get_parent().remove_child(_blast_flash)
		_blast_flash.queue_free()
	_blast_flash = ColorRect.new()
	_blast_flash.name = "MineBlastFlash"
	_blast_flash.color = Color(1.0, 0.96, 0.86, 0.0)
	_blast_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blast_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	$UILayer.add_child(_blast_flash)
	var ft := _blast_flash.create_tween()
	ft.tween_property(_blast_flash, "color:a", 0.30, 0.05)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ft.tween_property(_blast_flash, "color:a", 0.0, 0.30)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	ft.tween_callback(_blast_flash.queue_free)


func _restore_world_positions(world_nodes: Array[Node2D]) -> void:
	for i in mini(world_nodes.size(), _shake_bases.size()):
		if is_instance_valid(world_nodes[i]):
			world_nodes[i].position = _shake_bases[i]


func _on_all_safe_opened() -> void:
	# 清空全部安全格即胜利（目标为 CLEAR_ALL_SAFE 或自由模式）
	var obj := GameState.current_objective
	if obj == null or obj.type == ObjectiveData.Type.CLEAR_ALL_SAFE:
		_end_game("win")


## L5 敌害击杀转发：史莱姆死 → Boss 硬直 3s（奖励钱分在 enemy_manager 内发）
func _on_enemy_killed_forward(e, _by_actor: String) -> void:
	if boss_manager.active and e.enemy_type == "slime":
		boss_manager.stagger(3.0)


## L5 灭火（设计 §5.2）：点任一火格 → 连通组整片熄灭，吃 1 CD + 奖励
func _on_fire_extinguish_requested(coord: Vector2i) -> void:
	if not boss_manager.active:
		return
	if boss_manager.extinguish_fire_group(coord):
		GameState.consume_player_action()
		grid.play_player_action_visual(coord, Grid.FLY_ICON_OPEN)


## L5 牙数变化（旗/确认雷/坍塌任一来源）：刷新进度；拔完最后一颗牙 = 斩杀胜利
func _on_processed_mines_changed(current: int) -> void:
	_update_objective_progress()
	var obj := GameState.current_objective
	if obj == null or obj.type != ObjectiveData.Type.FIND_ALL_MINES:
		return
	if boss_manager.active:
		boss_manager.on_teeth_changed(current)  # 阶段门槛判定（5/11）
	if current >= obj.target_value and GameState.game_active:
		if boss_manager.active:
			_start_boss_kill_sequence()
		else:
			_end_game("win")


## 斩杀演出（设计 §5.4）：冻结全场（时钟停=Q6 时间加分锁定在拔牙瞬间）→
## Boss 掉落 3s → 走标准胜利结算。game_active 短暂置回以通过 _end_game 入口守卫。
func _start_boss_kill_sequence() -> void:
	GameState.game_active = false
	hud.show_toast("最后一颗牙。", 4.0)  # 斩杀大字（设计 §8-6，掉落演出期间压屏）
	boss_manager.kill_sequence_done.connect(_on_boss_kill_done, CONNECT_ONE_SHOT)
	boss_manager.begin_kill_sequence()


func _on_boss_kill_done() -> void:
	GameState.game_active = true
	_end_game("win")


func _end_game(result: String) -> void:
	if not GameState.game_active:
		return
	GameState.game_active = false
	tutorial_guide.hide()  # 局末收起引导（未完成则下次 1-1 重来）
	_close_level_overlays()  # 结算收起升级面板/放置预览（P1-03：旧面板不再盖关前卡）
	if result == "win":
		var obj := GameState.current_objective
		if obj != null and obj.type == ObjectiveData.Type.REACH_SCORE:
			# 过线时刻埋点（时间加分入账前的行动分轨迹，盲测校准 §10）
			GameState.result_stats["crossing_elapsed"] = snappedf(GameState.elapsed, 0.1)
		_apply_time_bonus()
		# 结算分快照（继续挑战的增量口径，见 _leave_after_continue）
		GameState.result_stats["win_score"] = GameState.score
	# 局末目标快照（结算面板状态行「目标达成/未达成 + X/Y」+ 近失判定的数值口径，P0.4）
	GameState.result_stats["obj_final_text"] = _update_objective_progress()
	var pv := _objective_progress_values()
	GameState.result_stats["obj_final_current"] = pv.x
	GameState.result_stats["obj_final_total"] = pv.y
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
	GameState.result_stats["time_bonus_secs"] = secs
	GameState.add_score(bonus, "time_bonus")  # 明细键 time_bonus 由账本写入
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
	var v := _objective_progress_values()
	var text: String = obj.build_progress_text(v.x, v.y)
	GameState.objective_progress_updated.emit(text, v.x, v.y)
	return text


## 目标进度数值（current=已完成数，total=分母，0=该目标类型隐藏条）；
## HUD 文本与局末近失快照（obj_final_current/total）共用一份口径
func _objective_progress_values() -> Vector2i:
	var obj := GameState.current_objective
	if obj == null:
		return Vector2i.ZERO
	var current: int = 0
	var total: int = 0   # 页面画细进度条的分母；0 = 该目标类型隐藏条
	match obj.type:
		ObjectiveData.Type.CLEAR_ALL_SAFE:
			total = grid.count_safe_total()
			current = total - grid.count_safe_remaining()   # 已完成数，不是剩余
			if obj.target_value > 0:
				total = obj.target_value   # 打折目标（L4）：已开口径不变，胜利线换成 target_value
		ObjectiveData.Type.REACH_SCORE:
			current = GameState.score
			total = obj.target_value
		ObjectiveData.Type.FLAG_N_MINES:
			current = _flag_count
		ObjectiveData.Type.SURVIVE_TIME:
			current = int(ceil(GameState.time_left))
		ObjectiveData.Type.ACTIVATE_N_TOWER:
			current = 0
		ObjectiveData.Type.FIND_ALL_MINES:
			total = grid.mine_count
			current = grid.count_processed_mines()
	return Vector2i(current, total)


## L4 探测机器人：3×3 强制探雷（设计 §9.5）——雷位标「确认雷」
## 机器人视同旗（Solver 计雷）、不计标旗分、情报穿锁（锁只拦交互）；零分零钱纯情报
func _trigger_probe(center: Vector2i) -> void:
	var confirmed: int = 0
	var new_teeth: Array = []  # 本次探测新处理的牙（已旗/已塌的不重复跳字）
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c = grid.get_cell(center + Vector2i(dx, dy))
			if c != null and c.is_mine and not c.is_confirmed_mine:
				c.confirm_mine()
				confirmed += 1
				if not c.is_collapsed and not grid.rewarded_flags.has(center + Vector2i(dx, dy)):
					new_teeth.append(center + Vector2i(dx, dy))
	GameState.result_stats["probe_used"] += 1
	var coords: String = GameState.result_stats["probe_coords"]
	GameState.result_stats["probe_coords"] = (coords + ";" if coords != "" else "") \
			+ "%d,%d" % [center.x, center.y]
	grid.refresh_processed_mines()  # L5 牙数：确认雷也是拔牙（探测 3×3 内可能有多颗）
	for t_coord in new_teeth:
		grid.fx_tooth_at(t_coord)
	grid.play_player_action_visual(center, Grid.FLY_ICON_OPEN)
	hud.show_toast("探测完成：%d 格确认雷" % confirmed, 2.5)
