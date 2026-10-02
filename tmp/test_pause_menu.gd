extends Node
## 暂停菜单新按钮冒烟测试（headless）：返回主菜单 / 退出游戏（2026-10-02 UI 优化）
## 用法：Godot_console.exe --path . --headless res://tmp/test_pause_menu.tscn
## 覆盖：按钮存在且可见 → 返回主菜单（确认→放弃结算→主菜单显示）→
##       退出游戏（弹确认、pending 正确；不接受，避免退出进程）
## 存档：record_game_result 会落盘，测试前备份 user://save_data.json，结束还原

var fails: Array = []
var main: Node
var _saved_json: String = ""
var _had_save: bool = false


func _ready() -> void:
	_run()


func check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  " + label)
	else:
		fails.append(label)
		print("  FAIL  " + label)


func _run() -> void:
	await get_tree().process_frame
	# 备份存档（abandon 结算会写盘）
	if FileAccess.file_exists("user://save_data.json"):
		_had_save = true
		_saved_json = FileAccess.open("user://save_data.json", FileAccess.READ).get_as_text()
	var ps: PackedScene = load("res://scenes/Main.tscn")
	main = ps.instantiate()
	get_parent().add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	print("== 暂停菜单：返回主菜单 / 退出游戏 ==")
	main._start_level("ch01_s01")
	await get_tree().process_frame
	main.pause_panel.open("测试矿区 · 第 1 关", "目标 test")
	var menu_btn: Button = main.pause_panel.get_node("Center/Panel/VBox/MenuButton")
	var exit_btn: Button = main.pause_panel.get_node("Center/Panel/VBox/ExitButton")
	var quit_btn: Button = main.pause_panel.get_node("Center/Panel/VBox/QuitButton")
	check(menu_btn is Button and menu_btn.visible, "「返回主菜单」按钮存在且可见")
	check(exit_btn is Button and exit_btn.visible, "「退出游戏」按钮存在且可见")
	check(quit_btn.visible, "「返回选关」仍在（未误删）")

	# ---- 返回主菜单：确认 → 放弃结算 → 主菜单 ----
	var active_before: bool = GameState.game_active
	check(active_before, "局内 game_active=true（有局面可放弃）")
	main._ask_quit_to_menu()
	check(main.confirm_dialog.visible, "返回主菜单弹确认框")
	main.confirm_dialog.confirmed.emit()
	await get_tree().process_frame
	check(main.main_menu.visible, "确认后主菜单显示")
	check(not main.pause_panel.visible, "暂停面板已收起")
	check(not GameState.game_active, "局面已结束（放弃结算）")
	check(not main.level_select.visible, "终点是主菜单而非选关页")

	# ---- 退出游戏：弹确认 + pending 正确；取消不动作 ----
	main._start_level("ch01_s01")
	await get_tree().process_frame
	GameState.game_active = true
	main._ask_exit_game()
	check(main.confirm_dialog.visible and main._pending_confirm == "exit_game",
			"退出游戏弹确认框且 pending=exit_game")
	main.confirm_dialog.cancelled.emit()
	check(GameState.game_active, "取消退出后局面仍进行")

	_finish()


func _finish() -> void:
	# 还原存档
	if _had_save:
		var f: FileAccess = FileAccess.open("user://save_data.json", FileAccess.WRITE)
		f.store_string(_saved_json)
		f.close()
	else:
		DirAccess.remove_absolute("user://save_data.json")
	print("")
	if fails.is_empty():
		print("=== 暂停菜单测试全部通过 ===")
	else:
		print("=== FAIL %d 项 ===" % fails.size())
		for f in fails:
			print("  - " + f)
	get_tree().quit(0 if fails.is_empty() else 1)
