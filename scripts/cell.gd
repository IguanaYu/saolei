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

# 双击检测
var _last_click_time: float = 0.0
const DOUBLE_CLICK_THRESHOLD := 0.35


func _ready() -> void:
	refresh_visual()
	input_event.connect(_on_input_event)


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
	is_opened = true
	refresh_visual()
	_play_open_pulse()
	return true


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
	if is_collapsed:
		bg.color = Color(0.4, 0.05, 0.05)
		lbl.text = "✸"
		lbl.modulate = Color.WHITE
	elif is_flagged:
		bg.color = Color(0.3, 0.3, 0.35)
		lbl.text = "⚑"
		lbl.modulate = Color(1.0, 0.8, 0.2)
	elif is_opened:
		bg.color = Color(0.85, 0.75, 0.55)
		if adjacent_mines == 0:
			lbl.text = ""
		else:
			lbl.text = str(adjacent_mines)
			lbl.modulate = NUMBER_COLORS[adjacent_mines]
	else:
		bg.color = Color(0.25, 0.18, 0.12)
		lbl.text = ""
	cell_state_changed.emit(self)
