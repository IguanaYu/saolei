extends Node
## 退出游戏按钮全路径复现：确认 → _abandon_settle → quit()，验证进程退出码
## 用法：Godot_console.exe --path . --headless res://tmp/test_exit_game.tscn
## 期望：退出码 0（若为 1 = 关停路径有崩溃）

var _saved_json: String = ""
var _had_save: bool = false


func _ready() -> void:
	await get_tree().process_frame
	if FileAccess.file_exists("user://save_data.json"):
		_had_save = true
		_saved_json = FileAccess.open("user://save_data.json", FileAccess.READ).get_as_text()
	var ps: PackedScene = load("res://scenes/Main.tscn")
	var main: Node = ps.instantiate()
	get_parent().add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	main._start_level("ch01_s01")
	await get_tree().process_frame
	print("局面激活=%s，走退出路径..." % GameState.game_active)
	main._ask_exit_game()
	print("确认框可见=%s pending=%s" % [main.confirm_dialog.visible, main._pending_confirm])
	# 真实路径：暂停面板开着 → 树处于 paused 状态下确认退出
	get_tree().paused = true
	main.confirm_dialog.confirmed.emit()
	print("confirmed 已发，下一帧进程应自行退出")
	await get_tree().process_frame
	# 若 quit 未生效（异常中断），1s 后强退并报非零
	await get_tree().create_timer(1.0).timeout
	# 还原存档（若进程还活着说明 quit 没执行到）
	if _had_save:
		var f: FileAccess = FileAccess.open("user://save_data.json", FileAccess.WRITE)
		f.store_string(_saved_json)
		f.close()
	print("!!! quit() 未生效，异常退出")
	get_tree().quit(3)
