extends SceneTree
## 单 Label autowrap 最小尺寸探针：验证 Godot 4.6 autowrap Label 的 min size 行为

var _frames := 0
var _lbl: Label
var _parent: PanelContainer


func _initialize() -> void:
	_parent = PanelContainer.new()
	_parent.position = Vector2(16, 128)
	_parent.size = Vector2(244, 100)
	root.add_child(_parent)
	_lbl = Label.new()
	_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var f: FontFile = load("res://assets/fonts/fusion-pixel-12px-proportional-zh_hans.ttf")
	_lbl.add_theme_font_override("font", f)
	_lbl.add_theme_font_size_override("font_size", 16)
	_lbl.text = "开墙 1 台 · 1 空闲（暂无可推理目标）"
	_parent.add_child(_lbl)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames >= 3:
		print("PROBE label min_size=", _lbl.get_minimum_size(), " actual_size=", _lbl.size)
		print("PROBE parent size=", _parent.size)
		quit()
		return true
	return false
