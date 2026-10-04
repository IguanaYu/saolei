class_name CaveEnv
extends Control
## 地图外围洞窟环境：cave_bg 平铺背景 + 岩体边框环抱地图 + 外围矿洞道具散布
## main.gd 在 grid.configure() 之后调用 layout_env() 重排

const CAVE_BG := preload("res://visual_v2/runtime/backgrounds/mine_cutaway.png")
const FRAME_T := preload("res://visual_v2/runtime/tiles/frame_T.png")
const FRAME_B := preload("res://visual_v2/runtime/tiles/frame_B.png")
const FRAME_L := preload("res://visual_v2/runtime/tiles/frame_L.png")
const FRAME_R := preload("res://visual_v2/runtime/tiles/frame_R.png")
const FRAME_THICK := 20
const OUTER_PROPS := preload("res://visual_v2/runtime/tiles/deco_outer_sheet.png")
const PROP_GRID := 4   # sheet 4x2，每件 28px
const PROP_PX := 28

var _bg_rect: TextureRect
var _frame_layer: Control
var _props_layer: Control
var _relayout_queued := false   # 拖拽窗口时 size_changed 高频触发，防抖合并


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_static()
	# Grid 的居中定位在它自己的 _ready 里，晚于本节点 → deferred 等布局完成后重排
	layout_env.call_deferred()
	# keep_height 拉伸下视口宽度随窗口变化（切全屏/调分辨率），重排边框与道具
	get_viewport().size_changed.connect(_queue_relayout)


func _queue_relayout() -> void:
	if _relayout_queued:
		return
	_relayout_queued = true
	_do_relayout.call_deferred()


func _do_relayout() -> void:
	_relayout_queued = false
	layout_env()


func _build_static() -> void:
	_bg_rect = TextureRect.new()
	_bg_rect.name = "CaveBgRect"
	_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_rect.texture = CAVE_BG
	_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_rect.modulate = Color(0.72, 0.72, 0.72)
	_bg_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_rect)

	_frame_layer = Control.new()
	_frame_layer.name = "FrameLayer"
	_frame_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame_layer)

	_props_layer = Control.new()
	_props_layer.name = "PropsLayer"
	_props_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_props_layer)


## 按 Grid 当前位置/尺寸重排边框与道具（configure 后调用；幂等）
func layout_env() -> void:
	for c in _frame_layer.get_children():
		c.queue_free()
	for c in _props_layer.get_children():
		c.queue_free()

	var grid := _find_grid()
	if grid == null:
		return
	# 岩框挂进 Grid（2026-10-04 高塔地图）：网格本地坐标（原点=盘左上），z=-1 压在格子下，
	# 随 BoardRoot 缩放与视口滚动一起动；旧实现的 global 坐标+屏幕层在 BoardRoot 恒等时等价
	var size := Vector2i(grid.cols * grid.cell_size, grid.rows * grid.cell_size)
	var rect := Rect2(-FRAME_THICK, -FRAME_THICK,
			size.x + FRAME_THICK * 2.0, size.y + FRAME_THICK * 2.0)

	# 四边（tile 拉伸自适应长度）
	_add_frame_piece("FrameTop", FRAME_T, Vector2(0.0, rect.position.y), Vector2(size.x, FRAME_THICK), true, grid)
	_add_frame_piece("FrameBottom", FRAME_B, Vector2(0.0, size.y), Vector2(size.x, FRAME_THICK), true, grid)
	_add_frame_piece("FrameLeft", FRAME_L, Vector2(rect.position.x, 0.0), Vector2(FRAME_THICK, size.y), false, grid)
	_add_frame_piece("FrameRight", FRAME_R, Vector2(size.x, 0.0), Vector2(FRAME_THICK, size.y), false, grid)
	# 四角
	for piece_name in ["FrameCornerTL", "FrameCornerTR", "FrameCornerBL", "FrameCornerBR"]:
		var tex := load("res://visual_v2/runtime/tiles/frame_%s.png" % piece_name.substr("FrameCorner".length()))
		var pos: Vector2
		if piece_name.ends_with("TL"):
			pos = rect.position
		elif piece_name.ends_with("TR"):
			pos = Vector2(rect.end.x - FRAME_THICK, rect.position.y)
		elif piece_name.ends_with("BL"):
			pos = Vector2(rect.position.x, rect.end.y - FRAME_THICK)
		else:
			pos = Vector2(rect.end.x - FRAME_THICK, rect.end.y - FRAME_THICK)
		var tr := TextureRect.new()
		tr.name = piece_name
		tr.position = pos
		tr.size = Vector2(FRAME_THICK, FRAME_THICK)
		tr.texture = tex
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.z_index = -1
		grid.add_child(tr)

	# V2 背景已经绘有完整的轨道、矿车和灯具；不再叠加随机漂浮道具。


func _find_grid() -> Grid:
	# Grid 在 BoardRoot 容器下（2026-10-04 高塔地图结构调整）：显式路径优先，递归一层兜底
	var parent := get_parent()
	var direct: Node = parent.get_node_or_null("BoardRoot/Grid")
	if direct is Grid:
		return direct
	for child in parent.get_children():
		if child is Grid:
			return child
		for grandchild in child.get_children():
			if grandchild is Grid:
				return grandchild
	return null


func _add_frame_piece(piece_name: String, tex: Texture2D, pos: Vector2, sz: Vector2,
		horizontal: bool, board_layer: Node) -> void:
	var tr := TextureRect.new()
	tr.name = piece_name
	tr.position = pos
	tr.size = sz
	tr.texture = tex
	tr.stretch_mode = TextureRect.STRETCH_TILE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.z_index = -1
	board_layer.add_child(tr)


## 外围随机撒矿洞道具（避开地图+边框区域，数量随可用面积）
func _scatter_props(map_rect: Rect2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("cave_env") # 固定种子：同一关重排不闪变
	var screen := get_viewport_rect().size
	var margin := Rect2(map_rect.position - Vector2(24, 24), map_rect.size + Vector2(48, 48))
	var slots: Array[Vector2] = []
	var step := 56.0
	var y := 8.0
	while y < screen.y - PROP_PX:
		var x := 8.0
		while x < screen.x - PROP_PX:
			var p := Vector2(x, y)
			if not margin.has_point(p) and not margin.has_point(p + Vector2(PROP_PX, PROP_PX)):
				slots.append(p)
			x += step
		y += step
	if slots.is_empty():
		return
	var count := maxi(4, int(slots.size() * 0.14))
	for i in count:
		var slot: Vector2 = slots[rng.randi_range(0, slots.size() - 1)]
		slots.erase(slot)
		var idx := rng.randi_range(0, 7)
		var atlas := AtlasTexture.new()
		atlas.atlas = OUTER_PROPS
		atlas.region = Rect2((idx % PROP_GRID) * PROP_PX, (idx / PROP_GRID) * PROP_PX, PROP_PX, PROP_PX)
		atlas.filter_clip = true
		var tr := TextureRect.new()
		tr.name = "OuterProp%d" % i
		tr.position = slot
		tr.size = Vector2(PROP_PX, PROP_PX)
		tr.texture = atlas
		tr.expand_mode = 1
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_props_layer.add_child(tr)
