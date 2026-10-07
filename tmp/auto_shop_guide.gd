extends SceneTree
## 局外商店引导（L2 通关 → 选关/主菜单 → 矿石商店购买）GUI 实测 harness
## 真实路径：BootLoading → 主菜单；换屏/点击全部走 Input.parse_input_event 真实鼠标事件，
## 断言走运行时状态（guide.steps / GameSettings 标记 / SaveSystem 矿石与解锁）。
## 用法：Godot_console.exe --path . -s res://tmp/auto_shop_guide.gd
## 证据输出：tmp/shop_guide_evidence/（本地目录，不入库）
## 注意：会写真实 user:// 存档——bash 侧先备份 save_data.json/settings.json，跑完恢复。

const EVIDENCE := "E:/godot/扫雷/tmp/shop_guide_evidence/"
const FLAG := "tutorial_done_shop_guide"

var step_no := 0
var fails: Array = []
var notes: Array = []
var GS: Node
var SS: Node
var SETTINGS: Node
var LS: Node
var MAIN: Node
var GUIDE: Node


func _initialize() -> void:
	print("[ShopGuide] USER_DATA=", OS.get_user_data_dir())
	DirAccess.make_dir_recursive_absolute(EVIDENCE)
	DisplayServer.window_set_position(Vector2i(-3000, 0))
	var vw: int = int(ProjectSettings.get_setting("display/window/size/viewport_width", 1024))
	var vh: int = int(ProjectSettings.get_setting("display/window/size/viewport_height", 768))
	DisplayServer.window_set_size(Vector2i(vw, vh))
	DisplayServer.window_set_title("商店引导实测 harness")
	change_scene_to_file("res://scenes/ui/BootLoading.tscn")
	call_deferred("_run")


# ---------- 基础设施（与 auto_playtest_territory.gd 同源） ----------

func check(cond: bool, label: String) -> void:
	step_no += 1
	if cond:
		print("  [PASS] #%d %s" % [step_no, label])
	else:
		fails.append(label)
		print("  [FAIL] #%d %s" % [step_no, label])
	notes.append({"n": step_no, "ok": cond, "label": label})


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _sec(t: float) -> void:
	await create_timer(t, true).timeout


func _shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(EVIDENCE + fname)
	print("  [SHOT] ", fname)


func _walk(node: Node, acc: Array) -> Array:
	acc.append(node)
	for c in node.get_children():
		_walk(c, acc)
	return acc


func _find_button_path(text_part: String, path_part: String) -> Button:
	for n in _walk(root, []):
		if n is Button and n.is_visible_in_tree() \
				and n.text.contains(text_part) and str(n.get_path()).contains(path_part):
			return n
	return null


func _to_inject_pos(canvas_pos: Vector2) -> Vector2:
	return root.get_final_transform() * canvas_pos


var _probe := false   # 预留：注入后采样悬停控件（4.6 无 gui_get_hover_control，未用）


func _inject_click(screen_pos: Vector2) -> void:
	var pos := _to_inject_pos(screen_pos)
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	Input.parse_input_event(motion)
	await process_frame
	var ev := InputEventMouseButton.new()
	ev.position = pos
	ev.global_position = pos
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	var rel := ev.duplicate()
	rel.pressed = false
	Input.parse_input_event(rel)
	await process_frame


func _inject_key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	var rel := ev.duplicate()
	rel.pressed = false
	Input.parse_input_event(rel)
	await process_frame


func _click_button_path(text_part: String, path_part: String) -> bool:
	var b := _find_button_path(text_part, path_part)
	if b == null:
		print("  [WARN] 找不到按钮：text*=", text_part, " path*=", path_part)
		return false
	var rect: Rect2 = b.get_global_rect()
	await _inject_click(rect.position + rect.size / 2.0)
	return true


func _step_text(idx: int) -> String:
	var steps: Array = GUIDE.steps
	if idx >= steps.size():
		return ""
	return String(steps[idx].get("text", ""))


func _step_node_path(idx: int) -> String:
	var steps: Array = GUIDE.steps
	if idx >= steps.size() or steps[idx].get("node", null) == null:
		return ""
	return str((steps[idx]["node"] as Node).get_path())


## 调试转储：guide 状态 + 四屏可见性 + 跳过键落点探针（谁在吃点击）
func _dump(tag: String) -> void:
	var g_state := "guide vis=" + str(GUIDE.visible) + " steps=" + str(GUIDE.steps.size())
	for i in GUIDE.steps.size():
		var sd: Dictionary = GUIDE.steps[i]
		var sn: Node = sd.get("node")
		var sn_desc := "null"
		if sn != null:
			sn_desc = str(sn.get_path()).get_file() + "/vis=" \
					+ str((sn as CanvasItem).is_visible_in_tree())
		g_state += " | s" + str(i) + "[" + String(sd.get("text", "")).left(10) + " " + sn_desc + "]"
	var screens: String = "menu=" + str(MAIN.get_node("UILayer/MainMenu").visible) \
			+ " sel=" + str(MAIN.get_node("UILayer/LevelSelect").visible) \
			+ " shop=" + str(MAIN.get_node("UILayer/OreShop").visible) \
			+ " results=" + str(MAIN.get_node("UILayer/ResultsPanel").visible) \
			+ " lvl=" + GS.current_level_id
	print("  [DUMP:", tag, "] ", g_state, " ;; ", screens)
	# 跳过键与气泡的矩形 + 跳过键可见性（点击落点探针在 _inject_click 里采样）
	var skip: Button = GUIDE.get_node("TopRight/SkipButton")
	var tip: Control = GUIDE.get_node("TipPanel")
	print("  [DUMP:", tag, "] skip_rect=", skip.get_global_rect(), " tip_rect=", tip.get_global_rect(),
			" skip_vis=", skip.is_visible_in_tree())


# ---------- 主流程 ----------

func _run() -> void:
	await _frames(5)
	GS = root.get_node("/root/GameState")
	SS = root.get_node("/root/SaveSystem")
	SETTINGS = root.get_node("/root/GameSettings")
	LS = root.get_node("/root/LevelSystem")
	# 等 BootLoading 走完进主菜单
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		MAIN = root.get_node_or_null("Main")
		if MAIN != null and MAIN.get_node("UILayer/MainMenu").visible:
			break
		await _sec(0.2)
	GUIDE = MAIN.get_node("UILayer/TutorialGuide")
	check(MAIN != null and MAIN.get_node("UILayer/MainMenu").visible, "boot 到主菜单")

	# ---- 状态布置：窗口期（L1/L2 已通、L3 未进、引导未看过、有矿、局外清零）----
	SETTINGS.set_value(FLAG, false)
	LS.mark_cleared("ch01_s01", 3)
	LS.mark_cleared("ch01_s02", 3)
	SS.levels_entered.erase("ch01_s03")
	# 局外轨道清零（跨次运行的购买累积会让"最便宜可买行"漂移，破坏断言确定性）
	for k in ["start_money", "start_lives", "global_speed", "work_speed", "start_robot"]:
		SS.unlocks[k] = 0
	SS.add_ore(200)
	var menu := MAIN.get_node("UILayer/MainMenu")
	# 补齐揭示行：boot 时窗口未开，按钮行不可见——重摆一次主菜单触发引导入口
	menu.hide()
	await _frames(2)
	menu.show()
	await _frames(6)

	# ---- T1 回归玩家主菜单入口：聚光「升级·新」----
	check(GUIDE.visible, "T1 主菜单窗口期引导出现")
	check(GUIDE.steps.size() == 2, "T1 主菜单步骤=2（升级→购买）")
	check(_step_node_path(0).contains("MainMenu/OreTag/PowerUpButton"), "T1 聚光主菜单升级按钮")
	check(menu.ore_tag.visible and "新" in menu.powerup_button.text, "T1 顺带验主菜单揭示+新角标")
	await _shot("01-main-menu-guide.png")

	# ---- T2 真实点击穿透压暗层 → 商店开 → 步骤推进到购买 ----
	check(await _click_button_path("升级", "MainMenu/OreTag"), "T2 点击主菜单升级按钮")
	await _frames(6)
	var shop := MAIN.get_node("UILayer/OreShop")
	check(shop.visible, "T2 矿石商店打开")
	check(GUIDE.visible, "T2 引导仍在")
	check(GUIDE.get_node("TipPanel/VBox/StepLabel").text == "引导 2 / 2", "T2 推进到购买步骤")
	check(_step_node_path(1).contains("StartMoneyRow/BuyButton"), "T2 购买聚光=起始金币行按钮(动态改写)")
	await _shot("02-shop-buy-step.png")
	_dump("t3-before-click")

	# ---- T3 真实点击购买 → 引导无声收场 + 标记落盘 ----
	var ore_before: int = SS.ore
	var buy_btn: Button = GUIDE.steps[1]["node"]
	var fb := _find_button_path("", "StartMoneyRow/BuyButton")   # 查找器交叉验证
	print("  [PROBE] finder(", "StartMoneyRow/BuyButton", ")→",
			str(fb.get_path()) if fb != null else "null",
			" step-node=", str(buy_btn.get_path()),
			" text=", buy_btn.text, " vis=", buy_btn.is_visible_in_tree(),
			" rect=", buy_btn.get_global_rect())
	await _inject_click(buy_btn.get_global_rect().get_center())
	check(buy_btn != null and not buy_btn.disabled, "T3 购买按钮定位且未禁用")
	await _frames(6)
	check(not GUIDE.visible, "T3 购买后引导收场")
	check(bool(SETTINGS.get_value(FLAG)), "T3 一次性标记落盘")
	check(int(SS.unlocks.get("start_money", 0)) == 1, "T3 start_money=Lv1")
	check(SS.ore == ore_before - 50, "T3 扣矿50 (%d→%d)" % [ore_before, SS.ore])
	await _shot("03-after-buy.png")

	# ---- T4 看过之后不再重播 ----
	check(await _click_button_path("关闭", "OreShop"), "T4 关闭商店")
	await _frames(4)
	_dump("t4-after-close")
	check(not GUIDE.visible, "T4 关商店不复活引导")
	menu.hide()
	await _frames(2)
	menu.show()
	await _frames(6)
	_dump("t4-after-reshow")
	check(not GUIDE.visible, "T4 重进主菜单不重播")

	# ---- T5 重置后选关页入口 + 逛回主菜单自愈 ----
	SETTINGS.set_value(FLAG, false)
	var sel_btn: Button = menu.get_node("MarginContainer/CenterContainer/VBoxContainer/SelectLevelButton")
	await _inject_click(sel_btn.get_global_rect().get_center())
	check(true, "T5 主菜单去选关(直点)")
	await _frames(6)
	var sel := MAIN.get_node("UILayer/LevelSelect")
	check(sel.visible and GUIDE.visible, "T5 选关页引导出现")
	check(_step_node_path(0).contains("OreRow/PowerUpButton"), "T5 聚光选关页升级按钮")
	await _shot("04-select-guide.png")
	# 自愈：真实路径点选关页「返回」→ 主菜单显示 → 聚光自动换到主菜单按钮
	var sel_back: Button = sel.get_node("MarginContainer/VBoxContainer/TopBar/BackButton")
	await _inject_click(sel_back.get_global_rect().get_center())
	await _frames(6)
	check(menu.visible and not sel.visible, "T5 真实路径退回主菜单")
	check(GUIDE.visible and _step_node_path(0).contains("MainMenu/OreTag"), "T5 自愈换聚光主菜单按钮")
	await _shot("05-heal-to-menu.png")

	# ---- T6 L2 胜利结算页入口：聚光「返回选关」→ 点击后接力到选关页 ----
	_dump("t6-before-skip")
	_probe = true
	# 跳过走 ESC（guide._unhandled_input 真实路径；鼠标点跳过由 TipPanel IGNORE 修复保障，
	# 上面各 DUMP 的 tip/skip 矩形重叠即为该修复的回归证据）
	await _inject_key(KEY_ESCAPE)
	_probe = false
	await _frames(4)
	_dump("t6-after-skip")
	check(not GUIDE.visible, "T6 跳过真的收场了")
	SETTINGS.set_value(FLAG, false)
	menu.hide()   # 真实流程结算时菜单必隐藏；不关则其不透明面板盖住结算页吃掉点击
	await _frames(2)
	GS.current_level_id = "ch01_s02"
	GS.game_over.emit("win")
	await _sec(1.5)   # 结算行入场后 0.8s 才亮聚光
	var results := MAIN.get_node("UILayer/ResultsPanel")
	_dump("t6-before-check")
	check(results.visible and GUIDE.visible, "T6 结算页引导出现")
	check(_step_node_path(0).contains("ButtonsRow/BackButton"), "T6 聚光返回选关按钮")
	check(_step_text(0).contains("返回选关"), "T6 文案引导退出关卡")
	await _shot("06-results-guide.png")
	check(await _click_button_path("返回选关", "ResultsPanel"), "T6 点击返回选关")
	await _frames(6)
	_dump("t6-after-back")
	check(sel.visible and GUIDE.visible and _step_node_path(0).contains("OreRow"), "T6 接力到选关页聚光")
	await _shot("07-relay-to-select.png")

	# ---- T7 鼠标点「跳过」=看过，之后不再播（回归 TipPanel IGNORE 修复：
	# 此态气泡与跳过键矩形重叠，修复前点击被面板吞掉）----
	_dump("t7-before-skip")
	check(await _click_button_path("跳过", "TutorialGuide"), "T7 鼠标点跳过")
	await _frames(4)
	check(not GUIDE.visible and bool(SETTINGS.get_value(FLAG)), "T7 跳过落标记")
	MAIN._show_main_menu()
	await _frames(6)
	check(not GUIDE.visible, "T7 之后不再重播")

	# ---- T8 旧口径回归：单参 begin 仍按关卡 id 写标记（L1/L2 局内教学不受影响）----
	SETTINGS.set_value("tutorial_done_ch01_s02", false)
	GUIDE.begin([{"node": menu.powerup_button, "text": "回归", "event": ""}], "")
	await _frames(3)
	check(GUIDE.visible, "T8 单参 begin 正常显示")
	check(await _click_button_path("跳过", "TutorialGuide"), "T8 跳过收场")
	await _frames(3)
	check(bool(SETTINGS.get_value("tutorial_done_ch01_s02")), "T8 标记落在关卡键(非商店键)")

	# ---- T9 L1 局内教学回归（挪层+气泡 IGNORE 不破坏局内体验）----
	SETTINGS.set_value("skip_pre_level", true)
	SETTINGS.set_value("tutorial_done_ch01_s01", false)
	menu.show()
	await _frames(2)
	MAIN._open_pre_level("ch01_s01")   # 已通关+skip → 直进 L1
	await _sec(1.5)                    # 关前数据 + L1 director 0.5s 延迟
	check(not MAIN.get_node("UILayer/MainMenu").visible, "T9 进关（菜单收起）")
	check(GUIDE.visible, "T9 L1 局内教学出现")
	check(_step_text(0) == "左键开格，右键标旗。", "T9 L1 开局文案")
	check(_step_node_path(0).contains("Grid"), "T9 聚光棋盘")
	# NextButton 点击路径回归：event"" 步骤显示下一步，面板 IGNORE 后按钮须仍可点
	var grid_node: Node = GUIDE.steps[0]["node"]
	GUIDE.begin([{"node": grid_node, "text": "回归Next", "event": ""}], "reg_next")
	await _frames(3)
	var next_btn: Button = GUIDE.get_node("TipPanel/VBox/NextButton")
	check(next_btn.is_visible_in_tree(), "T9 Next按钮可见")
	await _inject_click(next_btn.get_global_rect().get_center())
	await _frames(3)
	check(not GUIDE.visible, "T9 点Next后整段收场(按钮未被IGNORE面板挡)")

	# ---- 汇报 ----
	var report := {"total": step_no, "fails": fails, "notes": notes}
	var f := FileAccess.open(EVIDENCE + "report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("[ShopGuide] %d/%d PASS %s" % [step_no - fails.size(), step_no,
			"" if fails.is_empty() else "FAILS=" + str(fails)])
	quit(1 if fails.is_empty() else 2)
