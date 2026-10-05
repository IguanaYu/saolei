class_name Nest
extends Node2D
## L4 虫巢（裂缝，设计 §9.3）：盘边可见实体，HP 2，玩家点击 2 次（各吃 1 CD）摧毁
##（2026-10-05 起需领土接近：本体/邻 8 格连通基地才能点，不再支持开局隔空速除）；
## 巢毁则该巢后续波次取消；双巢皆毁 = 再无新虫（场上已有障碍不回收）

var coord: Vector2i = Vector2i(-1, -1)
var hp: int = 2
const NEST_FULL := preload("res://visual_v2/runtime/completion/enemies/nest_0.png")
const NEST_DAMAGED := preload("res://visual_v2/runtime/completion/enemies/nest_1.png")
const NEST_BROKEN := preload("res://visual_v2/runtime/completion/enemies/nest_2.png")
const FACTION_MARKER := preload("res://scripts/visuals/faction_marker.gd")

signal damaged(nest: Nest)      # 受击未毁（剧本 #2「巢被点第一下」的触发源）
signal destroyed(nest: Nest)    # 摧毁（埋点/波次联动）


func _ready() -> void:
	z_index = 9  # 低于虫、高于 Cell
	$Body.visible = false
	$IconLabel.visible = false
	$Skin.texture = NEST_FULL
	FACTION_MARKER.attach(self, $Skin, true)


func setup(start_coord: Vector2i, start_hp: int, grid) -> void:
	coord = start_coord
	hp = start_hp
	position = grid.coord_to_world(start_coord)
	refresh_clickable_visual(grid)


func is_alive() -> bool:
	return hp > 0


## 可点击条件（与敌虫同套，2026-10-05）：本体格或邻 8 格属于玩家领土
## （基地沿已开格连通）——开局盘边裂缝不能隔空点掉，要拆格扩散过去
func is_clickable(grid) -> bool:
	return is_clickable_in(grid.player_territory())


func is_clickable_in(territory: Dictionary) -> bool:
	if territory.has(coord):
		return true
	for o in MapGenerator.NEIGHBOR_OFFSETS:
		if territory.has(coord + o):
			return true
	return false


## 不可点时压暗本体（放基地阶段无领土 → 开局即暗，敌军标记仍清晰）
func refresh_clickable_visual(grid, territory: Dictionary = {}) -> void:
	var t: Dictionary = territory if not territory.is_empty() else grid.player_territory()
	$Skin.self_modulate = Color.WHITE if is_clickable_in(t) else Color(0.55, 0.55, 0.55, 0.65)


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
