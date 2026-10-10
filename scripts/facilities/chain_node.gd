class_name ChainNode
extends Node2D
## 2-4 连爆节点（总纲 §6.3）：预开安全格上的可见中立建筑。
## 被激光/副束/邻爆命中即消耗，对周围 3×3 产生一次破坏——爆炸格并入 LaserManager
## 统一命中集（同轮同格至多削 1 层），本类只管状态/演出，不自己结算。
## 机器人不把它当墙拆：opener 只找未开格/覆盖墙，节点是设施实体不进 Solver，天然排除。

var coord: Vector2i = Vector2i(-9, -9)
var consumed := false

var _hidden := false  # 消耗演出放完才真正不画（收缩动画期间继续可见）


func setup(c: Vector2i, grid) -> void:
	coord = c
	z_index = 8  # 压过格子与网格线，低于虫(10)/机器人悬停角框(40)
	position = grid.coord_to_world(c)
	queue_redraw()


## 爆炸 3×3（八邻+自身，边界裁切）——快照阶段由 LaserManager 取用；逻辑瞬时无状态
func blast_cells(grid) -> Array:
	var out: Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := coord + Vector2i(dx, dy)
			if grid.cells.has(c):
				out.append(c)
	return out


## 逻辑消耗（幂等；结算已完成的时点调用）；演出由 play_consume 编排
func trigger() -> void:
	consumed = true


## 消耗演出：错峰 delay 后膨胀一拍再收缩消失（3×3 短亮框由 EffectsLayer.fx_chain_blast_at 画）
func play_consume(delay: float) -> void:
	if _hidden:
		return
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_property(self, "scale", Vector2(1.35, 1.35), 0.05)
	tw.tween_property(self, "scale", Vector2(0.05, 0.05), 0.14)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.14)
	tw.tween_callback(func():
		_hidden = true
		queue_redraw())


func _draw() -> void:
	if _hidden:
		return
	# 同心环「爆」字图腾（程序绘制占位，素材批后换贴图）：外环暖橙 / 内环亮黄 / 中心字
	draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 24, Color(1.0, 0.55, 0.20, 0.92), 2.0)
	draw_arc(Vector2.ZERO, 7.5, 0.0, TAU, 20, Color(1.0, 0.82, 0.35, 0.95), 1.5)
	draw_circle(Vector2.ZERO, 4.5, Color(1.0, 0.62, 0.25, 0.28))
	draw_string(ThemeDB.fallback_font, Vector2(-6.0, 4.0), "爆",
			HORIZONTAL_ALIGNMENT_CENTER, 12.0, 11, Color(1.0, 0.92, 0.75))
