extends SceneTree
## 一次性布局探针：塞最长文案，量 TeamPanel/ScorePanel 实际 size（headless 可跑）

var _frames := 0
var _team
var _score


func _initialize() -> void:
	# 显式用项目主题同款字体（headless 下 root 窗口不一定带项目 theme）
	var f: FontFile = load("res://assets/fonts/fusion-pixel-12px-proportional-zh_hans.ttf")
	_team = load("res://scenes/ui/TeamPanel.tscn").instantiate()
	root.add_child(_team)
	_team.show()
	# 最长单行文案 + EventHint 原因行
	for row in ["OpenerRow", "MarkerRow", "DetectorRow", "MinerRow"]:
		var lbl: Label = _team.get_node("Margin/VBox/" + row)
		lbl.add_theme_font_override("font", f)
		lbl.add_theme_font_size_override("font_size", 16)
	_team.get_node("Margin/VBox/OpenerRow").text = "开墙 1 台 · 1 空闲"
	_team.get_node("Margin/VBox/MarkerRow").text = "标雷 1 台 · 1 空闲"
	_team.get_node("Margin/VBox/DetectorRow").text = "检测 1 台 · 1 空闲"
	_team.get_node("Margin/VBox/MinerRow").text = "矿工 1 台 · 1 空闲"
	_team.get_node("Margin/VBox/EventHintLabel").text = "空闲原因：暂无可推理目标"
	_score = load("res://scenes/ui/ScorePanel.tscn").instantiate()
	root.add_child(_score)
	_score.show()
	_score.get_node("Margin/VBox/OpenScoreLabel").text = "开格 999"


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames >= 3:
		print("PROBE team size=", _team.size, " expected max width 244")
		var vbox: VBoxContainer = _team.get_node("Margin/VBox")
		print("PROBE vbox min=", vbox.get_minimum_size(), " size=", vbox.size)
		for c in vbox.get_children():
			print("PROBE child ", c.name, " min=", c.get_minimum_size(), " size=", c.size)
		print("PROBE score size=", _score.size, " expected max width 244")
		quit()
		return true
	return false
