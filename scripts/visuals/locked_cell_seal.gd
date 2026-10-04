extends Node2D
## 固定格子障碍：交叉链条 + 挂锁。与有阵营三角的锁匠虫使用不同轮廓。
## 坐标限定在原生 28×28 格内；同一绘制也供操作说明使用。

const DARK := Color(0.10, 0.07, 0.05)
const METAL := Color(0.92, 0.52, 0.18)
const LIGHT := Color(1.0, 0.77, 0.37)


func _draw() -> void:
	# 四角锚点表示整格被封锁；链节从角延伸到中央挂锁。
	for x in [-12, 8]:
		for y in [-12, 8]:
			draw_rect(Rect2(x, y, 4, 4), DARK)
			draw_rect(Rect2(x + 1, y + 1, 2, 2), LIGHT)
	for offset in range(-10, 11, 4):
		for direction in [-1, 1]:
			var point := Vector2(offset, offset * direction)
			draw_rect(Rect2(point - Vector2(2, 2), Vector2(5, 5)), DARK)
			draw_rect(Rect2(point - Vector2.ONE, Vector2(3, 3)), METAL)
			draw_rect(Rect2(point, Vector2.ONE), DARK)
	# 顶部锁环与下方方形锁体，避免像带眼睛的生物。
	draw_rect(Rect2(-5, -8, 10, 9), DARK)
	draw_rect(Rect2(-4, -7, 8, 8), LIGHT)
	draw_rect(Rect2(-2, -5, 4, 5), DARK)
	draw_rect(Rect2(-7, -1, 14, 11), DARK)
	draw_rect(Rect2(-6, 0, 12, 9), METAL)
	draw_rect(Rect2(-5, 0, 10, 2), LIGHT)
	draw_rect(Rect2(-2, 3, 4, 3), DARK)
	draw_rect(Rect2(-1, 5, 2, 3), DARK)
