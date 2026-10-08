extends SceneTree
## 矿工文案收口验证：score_panel.gd 可编译；RulesPanel C 节已无「采矿」

func _init() -> void:
	var failures := 0
	var sp := load("res://scripts/ui/score_panel.gd")
	if sp == null:
		push_error("score_panel.gd 加载失败")
		failures += 1
	else:
		print("PARSE_OK score_panel.gd")

	var ps: PackedScene = load("res://scenes/ui/RulesPanel.tscn")
	if ps == null:
		push_error("RulesPanel.tscn 加载失败")
		failures += 1
	else:
		var panel := ps.instantiate()
		var body: Label = panel.get_node("Center/Panel/Margin/VBox/RulesScroll/RulesList/SectionCBody")
		var txt: String = body.text
		if txt.contains("采矿"):
			push_error("C 节仍含「采矿」: " + txt)
			failures += 1
		else:
			print("RULES_OK C节无采矿 -> " + txt)
		panel.free()

	var sp2 := load("res://scripts/ui/results_panel.gd")
	if sp2 == null:
		push_error("results_panel.gd 加载失败")
		failures += 1
	else:
		print("PARSE_OK results_panel.gd")
	if failures == 0:
		print("ALL_OK")
	else:
		print("FAILURES=%d" % failures)
	quit(1 if failures > 0 else 0)
