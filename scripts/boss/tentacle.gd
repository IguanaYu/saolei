class_name Tentacle
extends Node2D
## L5 挡路触手（设计 §5.3 / 实施计划 WP5）：从 Boss 所在盘边沿一行/一列
## 伸入 4-6 格连续已开格段——机器人不可经过（path_blockers），玩家棋盘操作不受影响。
## 点根部（靠盘边那端）= 整条断裂（1 CD + 奖励）；12s 不处理自然缩回。
## 计时由 BossManager.tick 驱动（冻结时同步暂停）。

const LIFETIME_SEC := 12.0

var cells: Array = []      # Vector2i 段内格子（cells[0] = 根部，靠盘边）
var root_coord: Vector2i = Vector2i(-9, -9)
var state := "alive"       # alive | broken | retracted
var remaining := LIFETIME_SEC
var _grid = null
var _segments: Array = []  # 占位色块（显式命名防误匹配）


func _ready() -> void:
	z_index = 11  # 高于 Cell，低于炸弹/史莱姆


## 段格子（已由 BossManager 选好，均为可占用的已开格）；占格即阻断通路
func setup(segment: Array, grid) -> void:
	cells = segment.duplicate()
	root_coord = cells[0]
	_grid = grid
	_build_visual()
	for c in cells:
		var cell = grid.get_cell(c)
		if cell != null:
			cell.path_blockers += 1


func _build_visual() -> void:
	# 占位：从根到梢一串渐细的暗紫节肢 + 根部亮标记（正式分段贴图列美术需求，WP8）
	# 本体锚在根部世界坐标：缩回动画的缩放自然朝根（盘边）收
	var root_pos: Vector2 = _grid.coord_to_world(root_coord)
	position = root_pos
	for i in cells.size():
		var seg := ColorRect.new()
		seg.name = "TentacleSeg%d" % i
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w := 20.0 - float(i) * 2.0
		seg.color = Color(0.32, 0.18, 0.40) if i > 0 else Color(0.55, 0.30, 0.62)
		var rel: Vector2 = _grid.coord_to_world(cells[i]) - root_pos
		seg.offset_left = rel.x - w / 2.0
		seg.offset_top = rel.y - w / 2.0
		seg.offset_right = rel.x + w / 2.0
		seg.offset_bottom = rel.y + w / 2.0
		add_child(seg)
		_segments.append(seg)
	# 摆动动画（占位：整组透明度呼吸）
	var tw := create_tween().set_loops()
	tw.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 0.8), 0.7)
	tw.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.7)


func is_active() -> bool:
	return state == "alive"


## BossManager.tick 驱动（game_active=false 冻结时不调用）
func tick(delta: float) -> void:
	if state != "alive":
		return
	remaining -= delta
	if remaining <= 0.0:
		release("retracted")


## 释放通路占用（断裂/缩回共用）；mode 仅用于动效区分
func release(mode: String) -> void:
	if state != "alive":
		return
	state = mode
	if _grid != null:
		for c in cells:
			var cell = _grid.get_cell(c)
			if cell != null:
				cell.path_blockers -= 1
	if mode == "broken":
		# 断裂动效：节肢两段弹开 + 渐隐
		var tw := create_tween()
		for i in _segments.size():
			var seg: ColorRect = _segments[i]
			var dir := 1.0 if i % 2 == 0 else -1.0
			tw.parallel().tween_property(seg, "position:y",
					seg.position.y + dir * 26.0, 0.25)
		tw.tween_property(self, "modulate:a", 0.0, 0.30)
		tw.tween_callback(queue_free)
	else:
		# 缩回：整条缩向根部 + 渐隐
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector2(0.1, 0.1), 0.35)
		tw.parallel().tween_property(self, "modulate:a", 0.0, 0.35)
		tw.tween_callback(queue_free)


## 玩家点断（main 几何命中链转发，根部命中判定在 BossManager.hit_tentacle_root_at）
func cut_by_player() -> void:
	if state != "alive":
		return
	release("broken")
