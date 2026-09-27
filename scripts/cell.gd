class_name Cell
extends Area2D
## 单格逻辑：状态机 + 视觉刷新 + 鼠标输入路由
## 玩家和机器人都通过 Grid 调用 open()/toggle_flag()/collapse() 来修改状态

@export var coord: Vector2i = Vector2i(-1, -1)
@export var cell_size: int = 28

# 状态
var is_mine: bool = false
var is_opened: bool = false
var is_flagged: bool = false
var is_collapsed: bool = false  # 踩雷坍塌
var adjacent_mines: int = 0      # 0-8
var is_base: bool = false        # 基地建筑
var is_vein: bool = false        # 矿脉
var vein_resources: int = 0      # 矿脉剩余资源

# 信号
signal cell_left_clicked(cell: Cell)
signal cell_right_clicked(cell: Cell)
signal cell_double_clicked(cell: Cell)
signal cell_state_changed(cell: Cell)

# 数字配色（索引 0 不用）
const NUMBER_COLORS := [
	Color.TRANSPARENT,
	Color(0.2, 0.4, 1.0),       # 1 蓝
	Color(0.0, 0.6, 0.2),       # 2 绿
	Color(0.9, 0.1, 0.1),       # 3 红
	Color(0.4, 0.1, 0.6),       # 4 深紫
	Color(0.5, 0.3, 0.1),       # 5 棕
	Color(0.0, 0.6, 0.7),       # 6 青
	Color(0.05, 0.05, 0.05),    # 7 黑
	Color(0.4, 0.4, 0.4),       # 8 灰
]

# ---- 视觉素材 ----
# 岩壁（未开格）：无缝纹理 336px = 12 格周期；相邻格按坐标定位切块 → 整片连续
# 风格 8 种：A1-A4 连体岩壁 / B1-B4 碎石泥土（Grid.wall_style 配置，章节可换）
var wall_style: String = "V2"
const WALL_GRID := 12
const WALL_TILE_PX := 28

# 洞底（已开格）：默认暗沙；有配套 floor_<风格> 时自动跟随（如 D 系主题套）
const FLOOR_DEFAULT := preload("res://visual_v2/runtime/tiles/floor_V2.png")
const FLOOR_GRID := 12
const FLOOR_TILE_PX := 28

# 挖开边缘碎裂条（中性色，配所有岩壁风格）
const EDGE_T := preload("res://visual_v2/runtime/tiles/wall_edge_T.png")
const EDGE_B := preload("res://visual_v2/runtime/tiles/wall_edge_B.png")
const EDGE_L := preload("res://visual_v2/runtime/tiles/wall_edge_L.png")
const EDGE_R := preload("res://visual_v2/runtime/tiles/wall_edge_R.png")
const SPECIAL_BASE := preload("res://visual_v2/runtime/tiles/special_base.png")
const SPECIAL_FLAG := preload("res://visual_v2/runtime/tiles/special_flag.png")
const SPECIAL_VEIN := preload("res://visual_v2/runtime/tiles/special_vein.png")
const SPECIAL_COLLAPSE := preload("res://visual_v2/runtime/tiles/special_collapse.png")

# 洞壁生态装饰（E 系主题套）：有 deco_<风格>_sheet 的风格在未开岩壁随机点缀
const DECO_GRID := 4          # sheet 4x2
const DECO_TILE_PX := 28
const DECO_DENSITY := 0.10

var _floor_atlas: AtlasTexture
var _deco_tex: TextureRect = null

# 双击检测
var _last_click_time: float = 0.0
const DOUBLE_CLICK_THRESHOLD := 0.35


func _ready() -> void:
	_setup_wall()
	_setup_floor()
	_setup_deco()
	refresh_visual()
	refresh_wall_edges()
	# 本格状态变化后，刷新周围格子的岩壁边缘描边
	cell_state_changed.connect(_on_state_changed_refresh_edges)
	input_event.connect(_on_input_event)


func _setup_wall() -> void:
	# 按坐标确定性取块（非随机）：相邻格取相邻区块 → 岩壁跨格连成一体
	var sheet: Texture2D = load("res://visual_v2/runtime/tiles/wall_%s.png" % wall_style)
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(
		(coord.x % WALL_GRID) * WALL_TILE_PX,
		(coord.y % WALL_GRID) * WALL_TILE_PX,
		WALL_TILE_PX, WALL_TILE_PX)
	atlas.filter_clip = true
	var wall: TextureRect = $WallTex
	wall.texture = atlas
	wall.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	$WallEdgeTop.texture = EDGE_T
	$WallEdgeBottom.texture = EDGE_B
	$WallEdgeLeft.texture = EDGE_L
	$WallEdgeRight.texture = EDGE_R
	for edge in [$WallEdgeTop, $WallEdgeBottom, $WallEdgeLeft, $WallEdgeRight]:
		edge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		edge.visible = false


func _setup_floor() -> void:
	# 每个格子创建时随机锁定一块洞底，翻开后显示（避免每次刷新跳动）
	# 风格配套：优先 floor_<wall_style>（D 系主题套），否则用默认暗沙
	# exists() 先探测：load() 对不存在路径会刷 ERROR 日志
	var sheet: Texture2D = null
	var path := "res://visual_v2/runtime/tiles/floor_%s.png" % wall_style
	if ResourceLoader.exists(path):
		sheet = load(path)
	if sheet == null:
		sheet = FLOOR_DEFAULT
	_floor_atlas = AtlasTexture.new()
	_floor_atlas.atlas = sheet
	var col := randi() % FLOOR_GRID
	var row := randi() % FLOOR_GRID
	_floor_atlas.region = Rect2(col * FLOOR_TILE_PX, row * FLOOR_TILE_PX, FLOOR_TILE_PX, FLOOR_TILE_PX)
	_floor_atlas.filter_clip = true
	var floor_tex: TextureRect = $FloorTex
	floor_tex.texture = _floor_atlas
	floor_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	floor_tex.visible = false


## 主题生态装饰：仅当风格配了 deco_<风格>_sheet（E 系）才散布；
## A-D 系无专属表 → 保持原视觉不变
func _setup_deco() -> void:
	var path := "res://visual_v2/runtime/tiles/deco_%s_sheet.png" % wall_style
	if not ResourceLoader.exists(path):
		return
	if randf() > DECO_DENSITY:
		return
	var atlas := AtlasTexture.new()
	atlas.atlas = load(path)
	var idx := randi() % (DECO_GRID * 2)
	atlas.region = Rect2(
		(idx % DECO_GRID) * DECO_TILE_PX,
		(idx / DECO_GRID) * DECO_TILE_PX,
		DECO_TILE_PX, DECO_TILE_PX)
	atlas.filter_clip = true
	_deco_tex = TextureRect.new()
	_deco_tex.name = "WallDeco"  # 明确命名：避免 get_children 遍历误匹配
	_deco_tex.texture = atlas
	_deco_tex.expand_mode = 1  # AtlasTexture 必须显式（默认 KEEP_SIZE 会把控件撑到纹理尺寸）
	_deco_tex.position = Vector2(-14, -14)
	_deco_tex.size = Vector2(DECO_TILE_PX, DECO_TILE_PX)
	_deco_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deco_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_deco_tex)


## 原地切换岩壁风格（调试键/章节主题用）：重建墙/洞底/装饰，不动局面
func apply_wall_style(style: String) -> void:
	wall_style = style
	_setup_wall()
	_setup_floor()
	if _deco_tex != null:
		_deco_tex.queue_free()
		_deco_tex = null
	_setup_deco()
	refresh_visual()


func _on_state_changed_refresh_edges(_cell: Cell) -> void:
	var g := get_parent()
	if g is Grid:
		g.refresh_edges_around(coord)


## 岩壁边缘：只在与"开侧"（已开格或地图外）交界的边显示碎裂描边
func refresh_wall_edges() -> void:
	if is_opened:
		$WallEdgeTop.visible = false
		$WallEdgeBottom.visible = false
		$WallEdgeLeft.visible = false
		$WallEdgeRight.visible = false
		return
	var g := get_parent()
	$WallEdgeTop.visible = _side_is_open_side(g, Vector2i(0, -1))
	$WallEdgeBottom.visible = _side_is_open_side(g, Vector2i(0, 1))
	$WallEdgeLeft.visible = _side_is_open_side(g, Vector2i(-1, 0))
	$WallEdgeRight.visible = _side_is_open_side(g, Vector2i(1, 0))


func _side_is_open_side(g: Node, dir: Vector2i) -> bool:
	if g is Grid:
		var n: Cell = g.get_cell(coord + dir)
		if n == null:
			return true  # 地图边界：也算洞壁外缘
		return n.is_opened  # 坍塌/基地/矿脉都置 is_opened，天然算开侧
	return false


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		var now: float = Time.get_ticks_msec() / 1000.0
		if now - _last_click_time < DOUBLE_CLICK_THRESHOLD:
			cell_double_clicked.emit(self)
			_last_click_time = 0.0
		else:
			cell_left_clicked.emit(self)
			_last_click_time = now
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		cell_right_clicked.emit(self)


func open(by_actor: String) -> bool:
	# 返回 true 表示状态真的改变了
	if is_opened or is_collapsed or is_flagged:
		return false
	if is_base:
		return false  # 基地格不可被开
	is_opened = true
	refresh_visual()
	_play_open_pulse()
	return true


func become_base() -> void:
	is_base = true
	is_opened = true  # 基地视为已开（机器人可走）
	refresh_visual()


func become_vein(resources: int) -> void:
	is_vein = true
	vein_resources = resources
	is_opened = true  # 矿脉视为已开（机器人可走）
	is_flagged = false  # 取消旗子状态
	refresh_visual()


func deplete_vein() -> void:
	is_vein = false
	vein_resources = 0
	refresh_visual()


func toggle_flag() -> bool:
	if is_opened or is_collapsed:
		return false
	is_flagged = not is_flagged
	refresh_visual()
	if is_flagged:
		_play_open_pulse()
	return true


func collapse() -> void:
	is_collapsed = true
	is_opened = true  # 视为已开，机器人可走
	refresh_visual()
	_play_collapse_flicker()


# ---- 动效 ----

func _play_open_pulse() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.18, 1.18), 0.08)
	tween.tween_property(self, "scale", Vector2.ONE, 0.10)


func _play_collapse_flicker() -> void:
	var bg: ColorRect = $Background
	var tween := create_tween()
	tween.tween_property(bg, "color", Color(1.0, 0.5, 0.5), 0.08)
	tween.tween_property(bg, "color", Color(0.4, 0.05, 0.05), 0.20)
	# 同时整格放大一下，强调事故
	var s_tween := create_tween()
	s_tween.tween_property(self, "scale", Vector2(1.3, 1.3), 0.1)
	s_tween.tween_property(self, "scale", Vector2.ONE, 0.18)


func refresh_visual() -> void:
	var bg: ColorRect = $Background
	var lbl: Label = $Label
	var special: TextureRect = $SpecialIcon
	var show_wall := false
	var show_floor := false
	special.texture = null
	if is_base:
		show_floor = true
		bg.color = Color(0.17, 0.16, 0.15)
		lbl.text = ""
		special.texture = SPECIAL_BASE
	elif is_vein:
		show_floor = true
		bg.color = Color(0.22, 0.18, 0.10)
		lbl.text = ""
		special.texture = SPECIAL_VEIN
	elif is_collapsed:
		show_floor = true
		bg.color = Color(0.22, 0.07, 0.07)
		lbl.text = ""
		special.texture = SPECIAL_COLLAPSE
	elif is_flagged:
		# 旗格仍是未开岩壁：岩壁上插旗
		show_wall = true
		bg.color = Color(0.20, 0.21, 0.25)
		lbl.text = ""
		special.texture = SPECIAL_FLAG
	elif is_opened:
		# 已开格：铺暗色洞底，数字叠在上面
		show_floor = true
		bg.color = Color(0.17, 0.14, 0.12)
		if adjacent_mines == 0:
			lbl.text = ""
		else:
			lbl.text = str(adjacent_mines)
			lbl.modulate = NUMBER_COLORS[adjacent_mines]
	else:
		# 未开格：连体岩壁
		show_wall = true
		bg.color = Color(0.20, 0.21, 0.25)
		lbl.text = ""
	$WallTex.visible = show_wall
	if _deco_tex != null:
		_deco_tex.visible = show_wall  # 装饰长在岩壁上，跟墙同步显隐
	$FloorTex.visible = show_floor
	special.visible = special.texture != null
	if not show_wall:
		refresh_wall_edges()  # 开侧格不显示描边，直接清掉
	cell_state_changed.emit(self)
