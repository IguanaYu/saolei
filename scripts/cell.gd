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

# 已开地砖 sprite sheet（12x12 块，每块源 80x80；暖色像素矿洞风，AI 抠块拼接）
const BRICK_SHEET := preload("res://assets/tiles/floor_bricks_sheet.png")
const BRICK_GRID := 12
const BRICK_TILE_PX := 80
var _brick_atlas: AtlasTexture

# 双击检测
var _last_click_time: float = 0.0
const DOUBLE_CLICK_THRESHOLD := 0.35


func _ready() -> void:
	_setup_brick()
	refresh_visual()
	input_event.connect(_on_input_event)


func _setup_brick() -> void:
	# 每个格子创建时随机锁定一块地砖，翻开后显示（避免每次刷新跳动）
	_brick_atlas = AtlasTexture.new()
	_brick_atlas.atlas = BRICK_SHEET
	var col := randi() % BRICK_GRID
	var row := randi() % BRICK_GRID
	_brick_atlas.region = Rect2(col * BRICK_TILE_PX, row * BRICK_TILE_PX, BRICK_TILE_PX, BRICK_TILE_PX)
	_brick_atlas.filter_clip = true  # 防止 atlas 块边缘像素渗透到相邻格
	var brick: TextureRect = $Brick
	brick.texture = _brick_atlas
	brick.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	brick.visible = false


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
	var show_brick := false
	if is_base:
		bg.color = Color(0.15, 0.35, 0.75)
		lbl.text = "B"
		lbl.modulate = Color.WHITE
	elif is_vein:
		bg.color = Color(0.7, 0.55, 0.1)
		lbl.text = "◆"
		lbl.modulate = Color(1.0, 0.85, 0.3)
	elif is_collapsed:
		bg.color = Color(0.4, 0.05, 0.05)
		lbl.text = "✸"
		lbl.modulate = Color.WHITE
	elif is_flagged:
		bg.color = Color(0.3, 0.3, 0.35)
		lbl.text = "⚑"
		lbl.modulate = Color(1.0, 0.8, 0.2)
	elif is_opened:
		# 已开数字格：铺一块随机地砖，数字叠在上面
		show_brick = true
		bg.color = Color(0.85, 0.75, 0.55)
		if adjacent_mines == 0:
			lbl.text = ""
		else:
			lbl.text = str(adjacent_mines)
			lbl.modulate = NUMBER_COLORS[adjacent_mines]
	else:
		bg.color = Color(0.25, 0.18, 0.12)
		lbl.text = ""
	$Brick.visible = show_brick
	cell_state_changed.emit(self)
