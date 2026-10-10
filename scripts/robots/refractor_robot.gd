class_name RefractorRobot
extends Robot
## 2-3 折光机器人（总纲 §6.2）：驻点增幅单位——主束到达即终止，出射宽束/散射替代后段。
## 一个脚本两种配置：robot_type "refractor_wide" / "refractor_scatter"（各 100 金限购 1）
## 不移动、不作业、不参与扫雷解答——只提供输出形状（放置位置=玩家的决策空间）

## 本台配置："wide" 宽束（3 宽×6 长） | "scatter" 散射（±45° 三束各 6 长）
var config := "wide"


## 驻点：无 tick 行为（速度/充能/黏液对它无意义）；占用格由放置规则保证唯一
func accumulate_and_maybe_tick(_delta: float, _grid, _locked: Dictionary) -> void:
	pass


func do_tick(_grid, _locked: Dictionary) -> void:
	_state = "idle"


## 永不算空闲（同 GuardRobot 先例：不触发全场停摆误报）
func is_idle() -> bool:
	return false


## 出射格集（放置预览/结算共用；dir8 = 入射方向）
func outgoing_cells(dir8: Vector2i) -> Array:
	if config == "scatter":
		return LaserGeometry.scatter_cells(coord, dir8)
	return LaserGeometry.corridor_cells(coord, dir8)
