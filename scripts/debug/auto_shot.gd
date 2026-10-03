extends Node
## 调试自动化：延迟截图 / 模拟点击（验收工具，仅 debug build + 显式传参时生效）
## 用法（加在 Godot 启动参数后，用 "--" 分隔的用户参数区）：
##   -- --shot=2.5:user://shot1.png --shot=4:res://tmp/shot2.png
##   -- --click=1.2:/root/Main/UILayer/MainMenu/.../ContinueButton
##   -- --call=3:/root/GameSettings:set_value:["fullscreen",true]  (args 为 JSON 数组，可省略)
##   -- --quit=6   （到点自动退出）
## release 导出（OS.is_debug_build()==false）直接跳过，零副作用。

var _actions: Array = []   # [{delay, kind, arg}]
var _elapsed: float = 0.0
var _done: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # 验收要在暂停状态截图/退出
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
		elif item.begins_with("call="):
			# call=delay:node_path:method:json_args（json_args 可省略；打印返回值）
			var parts: PackedStringArray = item.substr(5).split(":", true, 3)
			_actions.append({"delay": float(parts[0]), "kind": "call",
					"arg": [parts[1], parts[2], parts.get(3) if parts.size() > 3 else ""]})
		elif item.begins_with("quit="):
			_actions.append({"delay": float(item.substr(5)), "kind": "quit", "arg": ""})
		elif item.begins_with("sig="):
			# sig=delay:node_path:signal_name:arg(可省)  例 sig=4:/root/GameState:game_over:timeout
			var parts: PackedStringArray = item.substr(4).split(":")
			_actions.append({"delay": float(parts[0]), "kind": "sig",
					"arg": parts.slice(1)})
		elif item.begins_with("get="):
			# get=delay:node_path:property  例 get=4.9:/root/Main/UILayer/PlayerLogPanel:visible
			var parts: PackedStringArray = item.substr(4).split(":", true, 1)
			var kv: PackedStringArray = parts[1].split(":")
			_actions.append({"delay": float(parts[0]), "kind": "get", "arg": kv})
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
			"call":
				var p: PackedStringArray = act.arg
				var c_node := get_node_or_null(p[0])
				if c_node == null:
					push_warning("[AutoShot] call node not found: " + p[0])
				elif not c_node.has_method(p[1]):
					push_warning("[AutoShot] call method not found: " + p[0] + ":" + p[1])
				else:
					var args: Array = []
					if p.size() > 2 and p[2] != "":
						var parsed: Variant = JSON.parse_string(p[2])
						if typeof(parsed) == TYPE_ARRAY:
							args = parsed
					print("[AutoShot] call ", p[0], ":", p[1], "(", args, ") = ", c_node.callv(p[1], args))
			"sig":
				var p: PackedStringArray = act.arg
				var sig_node := get_node_or_null(p[0])
				if sig_node != null:
					if p.size() >= 3:
						sig_node.emit_signal(p[1], p[2])
					else:
						sig_node.emit_signal(p[1])
					print("[AutoShot] signal ", p[1], " on ", p[0])
				else:
					push_warning("[AutoShot] node not found: " + p[0])
			"get":
				var p: PackedStringArray = act.arg
				var g_node := get_node_or_null(p[0])
				if g_node != null and p.size() >= 2:
					print("[AutoShot] ", p[0], ":", p[1], " = ", g_node.get(p[1]))
				else:
					push_warning("[AutoShot] get target invalid")
			"quit":
				print("[AutoShot] quit")
				get_tree().quit()
	if _actions.is_empty():
		_done = true
