extends Node
## 冒烟：局内暂停 → 点"声音与设置" → 设置面板叠加打开 → 暂停中调音量总线即时变 → 关设置回暂停

func _ready() -> void:
	var failures := 0
	var main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var pause: Control = main.get_node("UILayer/PausePanel")
	var settings: Control = main.get_node("UILayer/SettingsPanel")
	var btn: Button = main.get_node("UILayer/PausePanel/Center/Panel/VBox/SettingsButton")

	# 1) 打开暂停（等效局内 ESC）
	main._open_pause()
	await get_tree().process_frame
	if not (pause.visible and get_tree().paused):
		push_error("FAIL: 暂停面板未打开/树未暂停")
		failures += 1
	else:
		print("PASS: 暂停打开，tree.paused=true")

	# 2) 触发"声音与设置"按钮 → 设置面板应叠加打开（暂停面板仍在）
	# （headless 下 warp_mouse 模拟点击不可靠，改 pressed.emit() 验证接线链路；
	#   暂停态可点击由 UILayer process_mode=ALWAYS 保证，与 P9 规则按钮同机制）
	btn.pressed.emit()
	await get_tree().process_frame
	if not settings.visible:
		push_error("FAIL: 设置面板未从暂停面板打开")
		failures += 1
	elif not pause.visible:
		push_error("FAIL: 设置打开后暂停面板被意外隐藏")
		failures += 1
	else:
		print("PASS: 设置面板叠加在暂停面板之上打开")

	# 3) 暂停中拖音量滑条 -> Music 总线 dB 应立即变化
	var music_idx := AudioServer.get_bus_index("Music")
	var db_before := AudioServer.get_bus_volume_db(music_idx)
	var slider: HSlider = main.get_node(
		"UILayer/SettingsPanel/Center/Panel/VBox/RowVolume/HBox/VolumeSlider")
	slider.set_value_no_signal(0.2)  # 直接改值不触发；用 GameSettings 走真实链路
	GameSettings.set_value("music_volume", 0.2)
	await get_tree().process_frame
	var db_after := AudioServer.get_bus_volume_db(music_idx)
	print("INFO: 暂停中 music_volume 0.7->0.2, Music bus %.1f -> %.1f dB" % [db_before, db_after])
	if absf(db_after - db_before) < 0.5:
		push_error("FAIL: 暂停中调节音量未生效")
		failures += 1
	else:
		print("PASS: 暂停中音量调节即时生效")

	# 4) 关闭设置 → 应回到暂停面板（仍是暂停态）
	settings.hide()
	await get_tree().process_frame
	if not (pause.visible and get_tree().paused):
		push_error("FAIL: 关设置后未回到暂停面板")
		failures += 1
	else:
		print("PASS: 关设置回到暂停面板，仍为暂停态")

	# 5) ESC 语义模拟：main._handle_escape() 关设置时只退一层（上面已验证 hide 后暂停仍在）
	# 还原默认音量，避免污染存档
	GameSettings.set_value("music_volume", 0.7)
	main._resume()
	await get_tree().process_frame
	print("RESULT: %s" % ("ALL_PASS" if failures == 0 else "HAS_FAIL x%d" % failures))
	get_tree().quit(0 if failures == 0 else 1)


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
