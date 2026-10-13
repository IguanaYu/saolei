extends Control
## 固定公开规则示例；不模拟未发射的随机矿石方向。


func _ready() -> void:
	custom_minimum_size = Vector2(550, 94)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	for expanded in [false, true]:
		var center := Vector2(55 if not expanded else 220, 37)
		for y in range(-3, 4):
			for x in range(-3, 4):
				var hit := (absi(x) <= 1 and absi(y) <= 1) or \
						((x == 0 or y == 0) and maxi(absi(x), absi(y)) <= (3 if expanded else 2))
				if not hit:
					continue
				var rect := Rect2(center + Vector2(x * 9, y * 9) - Vector2(4, 4), Vector2(8, 8))
				draw_rect(rect, Color(0.70, 0.35, 0.13))
				draw_rect(rect, Color(1, 0.7, 0.35), false, 1)
		draw_string(get_theme_default_font(), center + Vector2(-42, 50),
				"默认 13 格" if not expanded else "扩爆 17 格", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.85, 0.5))
	draw_string(get_theme_default_font(), Vector2(302, 33), "斜向范围保持一格", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.8, 0.7))
	draw_string(get_theme_default_font(), Vector2(302, 57), "旗格免疫 · 本体可反复引爆", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 0.9, 0.95))
