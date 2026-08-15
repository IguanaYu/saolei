extends Node
## 输入命中测试：完整 Main 场景下，向按钮坐标注入鼠标点击，
## 用 button.pressed 信号是否触发作为判据（比 hover 更接近真相）

func _ready() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	# 跳过闪屏，直接亮主菜单
	main.get_node("UILayer/SplashScreen").hide()
	var menu: Control = main.get_node("UILayer/MainMenu")
	menu.show()
	await get_tree().process_frame

	var vp := get_viewport()
	var buttons := [
		["StartButton(开始冒险)", "MarginContainer/CenterContainer/VBoxContainer/StartButton", "UILayer/ChapterSelect"],
		["StatsButton(挖矿档案)", "MarginContainer/CenterContainer/VBoxContainer/MenuRow/StatsButton", "UILayer/StatsPanel"],
		["DailyButton(每日挑战)", "MarginContainer/CenterContainer/VBoxContainer/MenuRow/DailyButton", "UILayer/DailyPanel"],
		["SignInButton(矿工签到)", "MarginContainer/CenterContainer/VBoxContainer/MenuRow/SignInButton", "UILayer/SignInPanel"],
		["SettingsButton(设置)", "MarginContainer/CenterContainer/VBoxContainer/MenuRow/SettingsButton", "UILayer/SettingsPanel"],
	]
	var failures := 0
	for entry in buttons:
		var label: String = entry[0]
		var btn: Button = menu.get_node(entry[1])
		var target_panel: Control = main.get_node(entry[2])
		var fired := {"pressed": false, "panel": false}
		btn.pressed.connect(func(): fired.pressed = true)
		target_panel.hide()
		var rect := btn.get_global_rect()
		var center := rect.get_center()
		_click(vp, center)
		await get_tree().process_frame
		fired.panel = target_panel.visible
		var ok: bool = fired.pressed or fired.panel
		if not ok:
			failures += 1
		print("%-24s rect=%s 坐标=%s 信号触发=%s 面板打开=%s -> %s" % [
			label, rect, center, fired.pressed, fired.panel,
			"OK" if ok else "FAIL(点击丢失)"])
		target_panel.hide()

	# 面板内部按钮也测一个：签到页领取按钮
	var si: Control = main.get_node("UILayer/SignInPanel")
	si.open()
	await get_tree().process_frame
	var claim: Button = si.get_node("Center/Panel/VBox/ClaimButton")
	var claim_fired := false
	claim.pressed.connect(func(): claim_fired = true)
	_click(vp, claim.get_global_rect().get_center())
	await get_tree().process_frame
	print("%-24s disabled=%s 信号触发=%s -> %s" % ["SignInClaim(领取)", claim.disabled,
			claim_fired, "OK" if claim_fired or claim.disabled else "FAIL"])
	if not claim_fired and not claim.disabled:
		failures += 1

	print("=== failures=", failures, " ===")
	get_tree().quit()


func _click(vp: Viewport, pos: Vector2) -> void:
	# 真实窗口下 warp 会产生移动事件（更新 mouse_focus），再补手动注入兜底
	Input.warp_mouse(pos)
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	vp.push_input(motion)
	await get_tree().process_frame
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = pos
	ev.global_position = pos
	ev.pressed = true
	vp.push_input(ev)
	ev = ev.duplicate()
	ev.pressed = false
	vp.push_input(ev)
