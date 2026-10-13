extends Node2D
## 一轮几何快照的临时演出；格集、旗保护、光线均由调用方提供。
const MICRO_ANIMATION := preload("res://scripts/visuals/micro_sprite_loop.gd")
var entries: Array = []  # {rect, delay}
var rays: Array = []     # {from, to}，像素坐标
var color := Color(1.0, 0.65, 0.25)
var age := 0.0
var duration := 0.55
var mode := "hit"       # hit / shield / build / death


func _process(delta: float) -> void:
	if not GameState.game_active:
		queue_free()
		return
	if not MICRO_ANIMATION.is_gameplay_running(self):
		return
	age += delta
	if age >= duration:
		queue_free()
	else:
		queue_redraw()


func _draw() -> void:
	for entry in entries:
		var t: float = age - float(entry.delay)
		if t < 0 or t > 0.32:
			continue
		var a := minf(t / 0.035, 1.0) * (1.0 - t / 0.32)
		var rect: Rect2 = entry.rect
		var tint := Color(color, a)
		if mode == "shield":
			draw_rect(rect.grow(-2), tint, false, 2)
			var p := rect.position + Vector2(4, 6)
			draw_polyline(PackedVector2Array([p, p + Vector2(3, 3), p + Vector2(8, -3)]), tint, 2)
		elif mode == "build":
			# 分三排落砖，中央留窗：演出与覆盖墙的数字可读性一致。
			for row in 3:
				var row_a := clampf((t - row * 0.025) * 12, 0, 1) * a
				draw_rect(Rect2(rect.position + Vector2(2, row * 7 + 2), Vector2(rect.size.x - 4, 4)), Color(color, row_a * 0.7))
		elif mode == "death":
			for i in 6:
				var d := Vector2.from_angle(i * TAU / 6.0)
				var p := rect.get_center() + d * (3.0 + t * 32.0)
				draw_rect(Rect2(p - Vector2.ONE, Vector2(3, 3)), tint)
		else:
			draw_rect(rect.grow(-2), Color(color, a * 0.12))
			draw_rect(rect.grow(-2), tint, false, 1.5)
			for i in 4:
				var p := rect.get_center() + Vector2.from_angle(i * PI / 2.0) * (3.0 + t * 20.0)
				draw_rect(Rect2(p - Vector2.ONE, Vector2(2, 2)), tint)
	var ray_t := age - 0.04
	if ray_t < 0 or ray_t > 0.28:
		return
	var ray_alpha := 1.0 - ray_t / 0.28
	for ray in rays:
		var from: Vector2 = ray.from
		var to: Vector2 = from.lerp(ray.to, clampf(ray_t / 0.07, 0, 1))
		draw_line(from, to, Color(color, ray_alpha * 0.25), 5)
		draw_line(from, to, Color(color.lightened(0.5), ray_alpha), 1.5)
