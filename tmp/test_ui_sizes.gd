extends Node
## 面板尺寸自检：验证各全屏面板的 Panel 高度是否为 0（0 = 按钮点不了）

const PANELS := [
	"res://scenes/ui/ConfirmDialog.tscn",
	"res://scenes/ui/PausePanel.tscn",
	"res://scenes/ui/SettingsPanel.tscn",
	"res://scenes/ui/StatsPanel.tscn",
	"res://scenes/ui/DailyPanel.tscn",
	"res://scenes/ui/SignInPanel.tscn",
	"res://scenes/ui/ResultsPanel.tscn",
	"res://scenes/ui/TutorialGuide.tscn",
]


func _ready() -> void:
	var insts: Array = []
	for p in PANELS:
		var sc: PackedScene = load(p)
		var inst = sc.instantiate()
		add_child(inst)
		insts.append(inst)
		if inst.has_method("open"):
			if inst.name == "PausePanel":
				inst.call("open", "测试上下文")
			else:
				inst.call("open")
	await get_tree().process_frame
	await get_tree().process_frame
	var bad := 0
	for inst in insts:
		var panel: Control = inst.get_node_or_null("Center/Panel")
		if panel == null:
			panel = inst.get_node_or_null("TipPanel")
		var verdict := "OK"
		if panel == null or panel.size.y < 10.0:
			verdict = "BAD(高度0,按钮点不了)"
			bad += 1
		print("%-16s %-22s size=%s" % [inst.name, verdict,
				panel.size if panel != null else Vector2.ZERO])
	print("=== bad=", bad, " ===")
	get_tree().quit()
