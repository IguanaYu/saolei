extends Node
class_name ShopGuideDirector
## 局外商店引导（L2 通关 → 引导玩家退出关卡、进升级页、买一件强化）
## 复用 TutorialGuide 聚光表现层；与关卡 director 不同，本流程横跨
## 结算页/选关页/主菜单/矿石商店多个屏幕，采用「每换一屏重注入该屏步骤」的
## 自愈式驱动：换屏 begin 同一 flag key 走 guide 的 _run_level 直通，
## 玩家中途逛去别的菜单也能把聚光重新摆到当前屏的正确按钮上。
##
## 触发窗口 = 通了 ch01_s02 且没进过 ch01_s03（与选关页金色高亮同口径）：
## 玩家点「下一关」直进 L3 后窗口永久关闭；看过一遍（走完/跳过/ESC）永不重播。

const L2_ID := "ch01_s02"
const L3_ID := "ch01_s03"
const FLAG_KEY := "shop_guide"          # guide 侧拼成 tutorial_done_shop_guide
const FLAG_DONE := "tutorial_done_shop_guide"

const COPY_EXIT := "矿石攒下了。点「返回选关」，去花掉它。"
const COPY_EXIT_LATE := "左下角：返回选关。"
const COPY_UPGRADE := "新解锁的「升级」：花矿石，永久变强。"
const COPY_UPGRADE_LATE := "点金色的「升级」按钮。"
const COPY_BUY := "买一件强化。起始金币最便宜。"
const COPY_BUY_LATE := "点任一「升级」按钮。"

var _guide: Control
var _results: Control
var _back_button: Button
var _level_select: Control
var _select_powerup: Button
var _main_menu: Control
var _menu_powerup: Button
var _ore_shop: Control
# 当前注入的购买步骤字典：矿石商店打开后把 node 从 RowsBox 占位改写成
# 第一个可买的 BuyButton（行节点在商店首次 open 时才创建，不能提前引用）
var _buy_step: Dictionary = {}
var _delay_tween: Tween = null


func _ready() -> void:
	var main := get_parent()
	_guide = main.get_node("UILayer/TutorialGuide")
	_results = main.get_node("UILayer/ResultsPanel")
	_back_button = main.get_node(
			"UILayer/ResultsPanel/Center/Panel/VBox/ButtonsRow/BackButton")
	_level_select = main.get_node("UILayer/LevelSelect")
	_select_powerup = main.get_node(
			"UILayer/LevelSelect/MarginContainer/VBoxContainer/TopBar/OreRow/PowerUpButton")
	_main_menu = main.get_node("UILayer/MainMenu")
	_menu_powerup = main.get_node("UILayer/MainMenu/OreTag/PowerUpButton")
	_ore_shop = main.get_node("UILayer/OreShop")

	GameState.game_over.connect(_on_game_over)
	_level_select.visibility_changed.connect(_on_level_select_visibility)
	_main_menu.visibility_changed.connect(_on_main_menu_visibility)
	_ore_shop.visibility_changed.connect(_on_ore_shop_visibility)
	SaveSystem.unlock_changed.connect(_on_unlock_changed)


## 触发窗口：L2 已通、L3 未进、本引导没看过（每日/失败路径天然不满足关卡对）
func _window_open() -> bool:
	return SaveSystem.is_level_cleared(L2_ID) \
			and not SaveSystem.has_entered_level(L3_ID) \
			and not bool(GameSettings.get_value(FLAG_DONE))


# ---- 入口一：L2 胜利结算页（主流程起点）----

func _on_game_over(result: String) -> void:
	if result != "win" or GameState.current_level_id != L2_ID:
		return
	if not _window_open():
		return
	if _delay_tween != null:
		_delay_tween.kill()
	# 结算行还在入场，压 0.8s 再亮聚光；期间玩家已点走则作罢（换屏入口会接手）
	_delay_tween = create_tween()
	_delay_tween.tween_interval(0.8)
	_delay_tween.tween_callback(func() -> void:
		if _results.visible and not _guide.visible:
			_guide.begin([_exit_step()], FLAG_KEY))


# ---- 入口二/三：选关页 / 主菜单（回归玩家与中途换屏自愈）----

func _on_level_select_visibility() -> void:
	if not _level_select.visible:
		return
	await get_tree().process_frame  # 等容器布局，聚光 rect 才准
	if not _level_select.visible:
		return
	_enter_screen(_select_steps())


func _on_main_menu_visibility() -> void:
	if not _main_menu.visible:
		return
	await get_tree().process_frame
	if not _main_menu.visible:
		return
	_enter_screen(_menu_steps())


## 换屏即重注入：局中（guide 可见）无条件重摆聚光；局外则只在窗口期放行
func _enter_screen(steps: Array) -> void:
	if _guide.visible or _window_open():
		_guide.begin(steps, FLAG_KEY)


# ---- 商店开合：推进到购买步骤 / 没买关掉则退回当前屏 ----

func _on_ore_shop_visibility() -> void:
	if _ore_shop.visible:
		await get_tree().process_frame  # 行在 open() 内先建好，再等一帧布局
		if not _ore_shop.visible or not _guide.visible:
			return
		_buy_step["node"] = _first_buy_target()
		_guide.notify_event("ore_shop_opened")
	else:
		# 关掉没买：购买步骤的目标按钮已消失，退回底层屏（选关/主菜单）重新等开商店
		if not _guide.visible or not _window_open():
			return
		if _level_select.visible:
			_guide.begin(_select_steps(), FLAG_KEY)
		elif _main_menu.visible:
			_guide.begin(_menu_steps(), FLAG_KEY)


func _on_unlock_changed(key: String) -> void:
	# 买成任意一件 = 「去升级」达成；"reset" 是清档广播，不算购买
	if key != "reset" and _guide.visible:
		_guide.notify_event("meta_upgraded")


# ---- 步骤构建（每次 fresh dict，_buy_step 记最新引用供开商店时改写）----

func _exit_step() -> Dictionary:
	return {"node": _back_button,
			"text": COPY_EXIT, "event": "level_select_opened",
			"timeout_sec": 12.0, "timeout_text": COPY_EXIT_LATE,
			"tip": "below"}


func _select_steps() -> Array:
	return [_upgrade_step(_select_powerup), _buy_steps()]


func _menu_steps() -> Array:
	return [_upgrade_step(_menu_powerup), _buy_steps()]


func _upgrade_step(button: Button) -> Dictionary:
	return {"node": button,
			"text": COPY_UPGRADE, "event": "ore_shop_opened",
			"timeout_sec": 15.0, "timeout_text": COPY_UPGRADE_LATE,
			"tip": "below"}


func _buy_steps() -> Dictionary:
	_buy_step = {"node": _ore_shop.rows_box,
			"text": COPY_BUY, "event": "meta_upgraded",
			"timeout_sec": 20.0, "timeout_text": COPY_BUY_LATE,
			"tip": "below"}
	return _buy_step


## 购买聚光目标：第一个可买的 BuyButton（TRACKS 顺序=价格从低到高，
## 首位即起始金币 50 矿；全不可买/满级时退化为整个行区）
func _first_buy_target() -> Control:
	for row in _ore_shop.rows_box.get_children():
		var buy := row.get_node("BuyButton") as Button
		if buy != null and not buy.disabled:
			return buy
	return _ore_shop.rows_box
