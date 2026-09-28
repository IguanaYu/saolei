extends Control
## 闪屏：LOGO + 版本号；无实际加载 → 不放假进度条，短暂停留后进主菜单

signal finished

const DURATION := 0.8


func _ready() -> void:
	var tw := create_tween()
	tw.tween_interval(DURATION)
	tw.tween_property(self, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func() -> void:
		hide()
		finished.emit())
