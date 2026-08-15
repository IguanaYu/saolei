class_name CaveEnv
extends Control
## 地图外围洞窟环境：cave_bg 平铺背景 + 岩体边框环抱地图 + 外围矿洞道具散布
## main.gd 在 grid.configure() 之后调用 layout_env() 重排

const CAVE_BG := preload("res://assets/tiles/cave_bg.png")
const FRAME_T := preload("res://assets/tiles/frame_T.png")
const FRAME_B := preload("res://assets/tiles/frame_B.png")
const FRAME_L := preload("res://assets/tiles/frame_L.png")
const FRAME_R := preload("res://assets/tiles/frame_R.png")
const FRAME_THICK := 20
const OUTER_PROPS := preload("res://assets/tiles/deco_outer_sheet.png")
const PROP_GRID := 4   # sheet 4x2，每件 28px
const PROP_PX := 28

var _bg_rect: TextureRect
var _frame_layer: Control
var _props_layer: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_static()
	# Grid 的居中定位在它自己的 _ready 里，晚于本节点 → deferred 等布局完成后重排
	layout_env.call_deferred()


func _build_static() -> void:
	_bg_rect = TextureRect.new()
	_bg_rect.name = "CaveBgRect"
	_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_rect.texture = CAVE_BG
	_bg_rect.stretch_mode = TextureRect.STRETCH_TILE
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
	var origin: Vector2 = grid.global_position
	var size := Vector2i(grid.cols * grid.cell_size, grid.rows * grid.cell_size)
	var rect := Rect2(origin.x - FRAME_THICK, origin.y - FRAME_THICK,
			size.x + FRAME_THICK * 2.0, size.y + FRAME_THICK * 2.0)

	# 四边（tile 拉伸自适应长度）
	_add_frame_piece("FrameTop", FRAME_T, Vector2(origin.x, rect.position.y), Vector2(size.x, FRAME_THICK), true)
	_add_frame_piece("FrameBottom", FRAME_B, Vector2(origin.x, origin.y + size.y), Vector2(size.x, FRAME_THICK), true)
	_add_frame_piece("FrameLeft", FRAME_L, Vector2(rect.position.x, origin.y), Vector2(FRAME_THICK, size.y), false)
	_add_frame_piece("FrameRight", FRAME_R, Vector2(origin.x + size.x, origin.y), Vector2(FRAME_THICK, size.y), false)
	# 四角
	for piece_name in ["FrameCornerTL", "FrameCornerTR", "FrameCornerBL", "FrameCornerBR"]:
		var tex := load("res://assets/tiles/frame_%s.png" % piece_name.substr("FrameCorner".length()))
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
		_frame_layer.add_child(tr)

	_scatter_props(rect)


func _find_grid() -> Grid:
	var parent := get_parent()
	for child in parent.get_children():
		if child is Grid:
			return child
	return null


func _add_frame_piece(piece_name: String, tex: Texture2D, pos: Vector2, sz: Vector2, horizontal: bool) -> void:
	var tr := TextureRect.new()
	tr.name = piece_name
	tr.position = pos
	tr.size = sz
	tr.texture = tex
	tr.stretch_mode = TextureRect.STRETCH_TILE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_layer.add_child(tr)


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
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_props_layer.add_child(tr)
