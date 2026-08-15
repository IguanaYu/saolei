extends Node
## 最终验证：四个主菜单入口按钮，逐个点击→面板打开→关闭→下一个

func _ready() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	main.get_node("UILayer/SplashScreen").hide()
	main.get_node("UILayer/MainMenu").show()
	await get_tree().process_frame

	var vp := get_viewport()
	var cases := [
		["StatsButton(挖矿档案)", "UILayer/MainMenu/MarginContainer/CenterContainer/VBoxContainer/MenuRow/StatsButton", "UILayer/StatsPanel"],
		["DailyButton(每日挑战)", "UILayer/MainMenu/MarginContainer/CenterContainer/VBoxContainer/MenuRow/DailyButton", "UILayer/DailyPanel"],
		["SignInButton(矿工签到)", "UILayer/MainMenu/MarginContainer/CenterContainer/VBoxContainer/MenuRow/SignInButton", "UILayer/SignInPanel"],
		["SettingsButton(设置)", "UILayer/MainMenu/MarginContainer/CenterContainer/VBoxContainer/MenuRow/SettingsButton", "UILayer/SettingsPanel"],
	]
	var failures := 0
	for entry in cases:
		var label: String = entry[0]
		var btn: Button = main.get_node(entry[1])
		var panel: Control = main.get_node(entry[2])
		var fired := false
		btn.pressed.connect(func(): fired = true)
		panel.hide()
		_click(vp, btn.get_global_rect().get_center())
		await get_tree().process_frame
		var ok: bool = fired and panel.visible
		if not ok:
			failures += 1
		print("%-24s 信号=%s 面板打开=%s -> %s" % [label, fired, panel.visible,
				"OK" if ok else "FAIL"])
		panel.hide()  # 关面板，让下一个按钮可点
		await get_tree().process_frame
	print("=== failures=", failures, " ===")
	get_tree().quit()


func _click(vp: Viewport, pos: Vector2) -> void:
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
