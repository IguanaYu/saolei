extends Control
## 闪屏/加载页：LOGO + 木质进度条 + 版本号；播完发 finished（主控切到主菜单）

signal finished

const DURATION := 1.4

@onready var bar_fill: ColorRect = $Center/VBox/BarPanel/BarFill
@onready var loading_label: Label = $Center/VBox/LoadingLabel
@onready var bar_panel: Panel = $Center/VBox/BarPanel


func _ready() -> void:
	var target_w := bar_panel.custom_minimum_size.x - 12.0
	bar_fill.size = Vector2(0, bar_panel.custom_minimum_size.y - 12.0)
	var tw := create_tween()
	tw.tween_method(
		func(v: float) -> void:
			bar_fill.size.x = v
			loading_label.text = "正在加载矿洞… %d%%" % int(round(v / target_w * 100.0)),
		0.0, target_w, DURATION)
	tw.tween_interval(0.3)
	tw.tween_property(self, "modulate:a", 0.0, 0.35)
	tw.tween_callback(
		func() -> void:
			hide()
			finished.emit())
