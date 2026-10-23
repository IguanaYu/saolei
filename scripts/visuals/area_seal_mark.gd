extends Node2D
## 区域封印标记（§7.3 机关解除区域封印）：青色符环 + 中央菱形，与锁格挂锁区分。
## 占位程序绘制，素材批换时替换本文件即可。

const RING := Color(0.45, 0.95, 1.0, 0.9)
const RING_DIM := Color(0.45, 0.95, 1.0, 0.35)
const CORE := Color(0.15, 0.45, 0.6, 0.85)


func _draw() -> void:
	# 外环四段弧感（用短矩形近似，避免 arc 采样开销）；四角刻点读作「区域被框住」
	for x in [-12, 8]:
		for y in [-12, 8]:
			draw_rect(Rect2(x, y, 4, 4), RING_DIM)
			draw_rect(Rect2(x + 1, y + 1, 2, 2), RING)
	# 中央菱形封印核心
	var pts := PackedVector2Array([
		Vector2(0, -9), Vector2(9, 0), Vector2(0, 9), Vector2(-9, 0),
	])
	draw_colored_polygon(pts, CORE)
	draw_polyline(pts + PackedVector2Array([Vector2(0, -9)]), RING, 1.5)
	# 内十字刻线
	draw_line(Vector2(-4, 0), Vector2(4, 0), RING_DIM, 1.0)
	draw_line(Vector2(0, -4), Vector2(0, 4), RING_DIM, 1.0)
