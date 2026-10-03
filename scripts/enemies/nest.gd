class_name Nest
extends Node2D
## L4 虫巢（裂缝，设计 §9.3）：盘边可见实体，HP 2，玩家点击 2 次（各吃 1 CD）摧毁；
## 巢毁则该巢后续波次取消；双巢皆毁 = 再无新虫（场上已有障碍不回收）

var coord: Vector2i = Vector2i(-1, -1)
var hp: int = 2
const NEST_FULL := preload("res://visual_v2/runtime/completion/enemies/nest_0.png")
const NEST_DAMAGED := preload("res://visual_v2/runtime/completion/enemies/nest_1.png")
const NEST_BROKEN := preload("res://visual_v2/runtime/completion/enemies/nest_2.png")

signal damaged(nest: Nest)      # 受击未毁（剧本 #2「巢被点第一下」的触发源）
signal destroyed(nest: Nest)    # 摧毁（埋点/波次联动）


func _ready() -> void:
	z_index = 9  # 低于虫、高于 Cell
	$Body.visible = false
	$IconLabel.visible = false
	$Skin.texture = NEST_FULL


func setup(start_coord: Vector2i, start_hp: int, grid) -> void:
	coord = start_coord
	hp = start_hp
	position = grid.coord_to_world(start_coord)


func is_alive() -> bool:
	return hp > 0


## 玩家点击受击：返回是否有效命中（已毁的巢不再挡点击）
func hit() -> bool:
	if hp <= 0:
		return false
	hp -= 1
	if hp <= 0:
		destroyed.emit(self)
		$Skin.texture = NEST_BROKEN
		# 摧毁动效：裂缝崩碎
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector2(1.8, 1.8), 0.12)
		tw.parallel().tween_property(self, "modulate:a", 0.0, 0.3)
		tw.tween_callback(queue_free)
	else:
		damaged.emit(self)
		$Skin.texture = NEST_DAMAGED
		# 受击动效：抖一下
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector2(1.25, 1.25), 0.06)
		tw.tween_property(self, "scale", Vector2.ONE, 0.10)
	return true
