class_name FactionMarker
extends Node2D
## 阵营识别共用层：友军青蓝底标，敌军橙红三角；不参与输入、寻路或实体计数。

const OUTLINE := preload("res://scripts/visuals/faction_outline.gdshader")
const ALLY_COLOR := Color(0.18, 0.85, 0.94)
const ENEMY_COLOR := Color(1.0, 0.36, 0.25)
const BACKING := Color(0.04, 0.05, 0.07, 0.95)

var hostile := false


static func attach(actor: Node2D, skin: Sprite2D, is_hostile: bool) -> void:
	if actor.has_node("FactionMarker"):
		return
	var marker := FactionMarker.new()
	marker.name = "FactionMarker"
	marker.hostile = is_hostile
	marker.z_index = 1
	actor.add_child(marker)
	var outline := ShaderMaterial.new()
	outline.shader = OUTLINE
	outline.set_shader_parameter("faction_color", ENEMY_COLOR if is_hostile else ALLY_COLOR)
	outline.set_shader_parameter("frame_count", Vector2(skin.hframes, skin.vframes))
	skin.material = outline


func _draw() -> void:
	if hostile:
		# 实心三角固定在单位右上角；和格子数字、锁格边角使用不同形状。
		draw_colored_polygon(PackedVector2Array([
			Vector2(4, -13), Vector2(12, -13), Vector2(8, -6)]), BACKING)
		draw_colored_polygon(PackedVector2Array([
			Vector2(5, -12), Vector2(11, -12), Vector2(8, -7)]), ENEMY_COLOR)
	else:
		# 平底 U 形标记：始终贴脚下，移动时跟随，避免占用数字的位置。
		draw_rect(Rect2(-9, 10, 18, 4), BACKING)
		draw_rect(Rect2(-7, 11, 14, 2), ALLY_COLOR)
		draw_rect(Rect2(-9, 9, 2, 4), ALLY_COLOR)
		draw_rect(Rect2(7, 9, 2, 4), ALLY_COLOR)
