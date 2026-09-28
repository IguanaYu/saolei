extends Node
## 调试自动化：延迟截图 / 模拟点击（验收工具，仅 debug build + 显式传参时生效）
## 用法（加在 Godot 启动参数后，用 "--" 分隔的用户参数区）：
##   -- --shot=2.5:user://shot1.png --shot=4:res://tmp/shot2.png
##   -- --click=1.2:/root/Main/UILayer/MainMenu/.../ContinueButton
##   -- --quit=6   （到点自动退出）
## release 导出（OS.is_debug_build()==false）直接跳过，零副作用。

var _actions: Array = []   # [{delay, kind, arg}]
var _elapsed: float = 0.0
var _done: bool = true


func _ready() -> void:
	if not OS.is_debug_build():
		return
	# 参数经环境变量传入（AUTOSHOT="shot=3.0:res://tmp/a.png;click=1.2:/root/...;quit=6"），
	# 避免命令行路径被 shell 转换
	var spec: String = OS.get_environment("AUTOSHOT")
	if spec == "":
		return
	for item in spec.split(";"):
		if item.begins_with("shot="):
			var body := item.substr(5).split(":", true, 1)
			_actions.append({"delay": float(body[0]), "kind": "shot", "arg": body[1]})
		elif item.begins_with("click="):
			var body := item.substr(6).split(":", true, 1)
			_actions.append({"delay": float(body[0]), "kind": "click", "arg": body[1]})
		elif item.begins_with("quit="):
			_actions.append({"delay": float(item.substr(5)), "kind": "quit", "arg": ""})
	if not _actions.is_empty():
		_done = false
		_actions.sort_custom(func(a, b): return a.delay < b.delay)


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	while not _actions.is_empty() and _elapsed >= _actions[0].delay:
		var act: Dictionary = _actions.pop_front()
		match act.kind:
			"shot":
				var img := get_viewport().get_texture().get_image()
				var path: String = act.arg
				if path.begins_with("user://") or path.begins_with("res://tmp/"):
					img.save_png(path)
					print("[AutoShot] saved ", path)
				else:
					push_warning("[AutoShot] path must be user:// or res://tmp/: " + path)
			"click":
				var node := get_node_or_null(act.arg)
				if node is Button:
					node.pressed.emit()
					print("[AutoShot] clicked ", act.arg)
				else:
					push_warning("[AutoShot] not a Button: " + act.arg)
			"quit":
				print("[AutoShot] quit")
				get_tree().quit()
	if _actions.is_empty():
		_done = true
