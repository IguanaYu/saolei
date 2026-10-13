extends Node2D
## 高塔地图的世界层遮罩：格子和实体只画在棋盘可视窗内。
## 普通地图不用遮罩，保留 Boss 趴在棋盘上沿的演出。
var _mask := Rect2()

func set_clip_rect(area: Rect2, enabled: bool) -> void:
	clip_children = CanvasItem.CLIP_CHILDREN_ONLY if enabled else CanvasItem.CLIP_CHILDREN_DISABLED
	_mask = Rect2(area.position / scale, area.size / scale)
	queue_redraw()

func _draw() -> void:
	if clip_children == CanvasItem.CLIP_CHILDREN_ONLY:
		draw_rect(_mask, Color.WHITE)
