extends Node2D
## 钻石公开效果角标。只画外观，显示权限由 Cell 判定；不读取雷位、不抽玩法随机数。
## 四类以九宫格 / 分叉箭头 / 钱币 / 双翼区别；消耗后加缺角与斜杠，原旗保持可见。

const COLORS := {
	"area_3x3": Color(0.40, 0.90, 1.0),
	"split_two": Color(0.91, 0.57, 1.0),
	"gold": Color(1.0, 0.79, 0.28),
	"explorer": Color(0.49, 1.0, 0.69),
}

var effect_id: String = ""
var consumed: bool = false


static func effect_color(id: String) -> Color:
	return COLORS.get(id, Color.WHITE)


static func is_supported(id: String) -> bool:
	return COLORS.has(id)


func _draw() -> void:
	if not is_supported(effect_id):
		return
	var tint := effect_color(effect_id)
	if consumed:
		tint = tint.lerp(Color(0.57, 0.61, 0.65), 0.55)
	var back := Color(0.05, 0.07, 0.10, 0.96)
	draw_rect(Rect2(-6, -6, 12, 12), back)
	if consumed:
		# 缺角边框和贯穿斜杠，缩小时仍有形状差别；不将钻石画成空地。
		draw_polyline(PackedVector2Array([
			Vector2(-6, 6), Vector2(-6, -6), Vector2(2, -6),
			Vector2(6, -2), Vector2(6, 6), Vector2(-6, 6),
		]), tint, 1.0)
	else:
		draw_rect(Rect2(-6, -6, 12, 12), tint, false, 1.0)
	match effect_id:
		"area_3x3":
			for y in 3:
				for x in 3:
					draw_rect(Rect2(Vector2(x * 3 - 4, y * 3 - 4), Vector2(2, 2)), tint)
		"split_two":
			draw_polyline(PackedVector2Array([
				Vector2(-4, -2), Vector2(-4, -4), Vector2(-2, -4),
			]), tint, 1.0)
			draw_polyline(PackedVector2Array([
				Vector2(2, -4), Vector2(4, -4), Vector2(4, -2),
			]), tint, 1.0)
			draw_line(Vector2(-4, -4), Vector2(0, 0), tint, 1.5)
			draw_line(Vector2(4, -4), Vector2(0, 0), tint, 1.5)
			draw_line(Vector2(0, 0), Vector2(0, 4), tint, 1.5)
		"gold":
			draw_circle(Vector2.ZERO, 4.0, tint)
			draw_rect(Rect2(-1, -3, 2, 6), back)
			draw_line(Vector2(-3, 0), Vector2(3, 0), back, 1.0)
		"explorer":
			draw_colored_polygon(PackedVector2Array([
				Vector2(0, -4), Vector2(2, 0), Vector2(0, 4), Vector2(-2, 0),
			]), tint)
			draw_polyline(PackedVector2Array([
				Vector2(-2, 1), Vector2(-5, -2), Vector2(-4, 2), Vector2(-2, 3),
			]), tint, 1.0)
			draw_polyline(PackedVector2Array([
				Vector2(2, 1), Vector2(5, -2), Vector2(4, 2), Vector2(2, 3),
			]), tint, 1.0)
	if consumed:
		draw_line(Vector2(-5, 5), Vector2(5, -5), back, 3.0)
		draw_line(Vector2(-5, 5), Vector2(5, -5), Color(0.87, 0.90, 0.94), 1.0)
