extends Node2D
## 原生墙的加固/裂纹，以及施工墙的砌砖边框。中央留出数字窗口。
var layers := 1
var constructed := false


func _draw() -> void:
	if constructed:
		var mortar := Color(0.13, 0.10, 0.09, 0.95)
		var brick := Color(0.50, 0.33, 0.20, 0.95)
		draw_rect(Rect2(-13, -13, 26, 26), mortar, false, 3)
		for y in [-12, 9]:
			for x in [-12, -4, 4]:
				draw_rect(Rect2(x, y, 7, 3), brick)
		for x in [-12, 9]:
			for y in [-8, -1, 6]:
				draw_rect(Rect2(x, y, 3, 6), brick)
		# 不压中央数字；厚度以两侧金属压条与角标共同表达。
		for i in range(layers - 1):
			draw_line(Vector2(-10 + i * 2, -9), Vector2(-10 + i * 2, 8), Color(0.82, 0.64, 0.35), 1)
			draw_line(Vector2(10 - i * 2, -9), Vector2(10 - i * 2, 8), Color(0.82, 0.64, 0.35), 1)
		return
	var steel := Color(0.36, 0.47, 0.5, 0.95)
	var shine := Color(0.68, 0.77, 0.7, 0.95)
	if layers >= 2:
		for x in ([-10, 9] if layers >= 3 else [-10]):
			draw_rect(Rect2(x, -11, 3, 22), Color(0.10, 0.14, 0.17))
			draw_rect(Rect2(x + 1, -10, 1, 20), steel)
			for y in [-10, 8]:
				draw_rect(Rect2(x, y, 3, 2), shine)
	if layers <= 2:
		var crack := PackedVector2Array([Vector2(4, -10), Vector2(1, -4), Vector2(5, 1), Vector2(0, 7), Vector2(2, 12)])
		draw_polyline(crack, Color(0.10, 0.08, 0.07, 0.9), 2)
		if layers == 1:
			draw_polyline(PackedVector2Array([Vector2(5, 1), Vector2(9, 4), Vector2(11, 3)]), Color(0.12, 0.08, 0.05), 1)
