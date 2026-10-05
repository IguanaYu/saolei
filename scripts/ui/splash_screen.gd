extends Control
## 闪屏：LOGO + 版本号；无实际加载 → 不放假进度条，短暂停留后进主菜单

signal finished

const DURATION := 0.8


func _ready() -> void:
	var tw := create_tween()
	tw.tween_interval(DURATION)
	tw.tween_property(self, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func() -> void:
		# 经 BootLoading 进入时本页已被预隐藏（职责被加载页吸收）：
		# 补间不会因 hide 停止，迟到的 finished 会把主菜单 show 回来——
		# 若玩家此时已切进选关/设置等界面，菜单会在其下方重新 visible（2026-10-04 实测）。
		# 没播过就不补发。
		if not visible:
			return
		hide()
		finished.emit())
