extends Control
## 新手引导：全屏压暗 + 聚光框只亮目标区域 + 指引气泡 + 步骤计数 + 跳过
## steps 由 main.gd 注入：[{node: Node, size: Vector2(Node2D用), text: String,
##                          event: String(""=下一步按钮推进), tip: "left"/"right"/"below"}]

signal finished

const GOLD := Color(1.0, 0.82, 0.4)

var steps: Array = []
var _step_idx := 0
# 竞态修复：提前到达的事件缓存（原实现只匹配当前步骤，早到事件被静默丢弃→卡死）
var _pending_events: Dictionary = {}
# 步骤代数：防旧步骤的 await/timer 回调污染新步骤
var _step_gen := 0
# 本局已放行教学的关卡：每关教学只播一轮，但同一局内信号驱动的后续段
# （如 L1 耗尽→商店）不因首段结束置了标记而被拦
var _run_level := ""

@onready var dim_top: ColorRect = $DimTop
@onready var dim_bottom: ColorRect = $DimBottom
@onready var dim_left: ColorRect = $DimLeft
@onready var dim_right: ColorRect = $DimRight
@onready var border_top: ColorRect = $BorderTop
@onready var border_bottom: ColorRect = $BorderBottom
@onready var border_left: ColorRect = $BorderLeft
@onready var border_right: ColorRect = $BorderRight
@onready var tip_panel: PanelContainer = $TipPanel
@onready var step_label: Label = $TipPanel/VBox/StepLabel
@onready var text_label: Label = $TipPanel/VBox/TextLabel
@onready var next_button: Button = $TipPanel/VBox/NextButton
@onready var skip_button: Button = $TopRight/SkipButton


func _ready() -> void:
	hide()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	next_button.pressed.connect(_advance)
	skip_button.pressed.connect(_finish)
	# 窗口变化的聚光重摆由 main._relayout_play_area 在棋盘重定位之后统一调用
	# （本层若自订阅会先于 main 读到旧棋盘 transform，聚光洞错位一帧）


## 视口尺寸变化时仅重排几何（不动文案与超时计时，避免重置升级提示）
func _relayout_current() -> void:
	if not visible or _step_idx >= steps.size():
		return
	var step: Dictionary = steps[_step_idx]
	var r := _spot_rect(step).grow(8.0)
	_lay_spotlight(r)
	_lay_tip(r, step.get("tip", "left"), _step_gen)


## 每关教学只播一轮：该关看过一次（标记已置）则整段剧本不再启动；
## 同局内首段已放行后，后续段直接放行（否则首段结束置标记会拦掉 L1 的耗尽段）
func begin(step_defs: Array) -> void:
	if step_defs.is_empty():
		return
	var lvl := String(GameState.current_level_id)
	if _run_level != lvl:
		if bool(GameSettings.get_value("tutorial_done_" + lvl)):
			return
		_run_level = lvl
	steps = step_defs
	_step_idx = 0
	_step_gen += 1
	_pending_events.clear()
	show()
	_apply_step()


## 外部事件推进（base_placed / robot_spawned 等，经 main 转发）
func notify_event(event: String) -> void:
	if _step_idx >= steps.size():
		return
	var step: Dictionary = steps[_step_idx]
	if step.get("event", "") == event:
		_advance()
	else:
		_pending_events[event] = true  # 早到事件缓存，推进到等待它的步骤时补领


## 点击是否落在教学自身控件上（气泡/跳过）——main._input 据此放行，
## 避免放置模式把「跳过」按钮的左键吞掉（回归 2026-10-01 P1）
func is_point_on_chrome(p: Vector2) -> bool:
	return tip_panel.get_global_rect().has_point(p) \
			or skip_button.get_global_rect().has_point(p)


func _advance() -> void:
	_step_idx += 1
	_step_gen += 1
	_apply_step()


func _apply_step() -> void:
	if _step_idx >= steps.size():
		_finish()
		return
	var gen := _step_gen
	var step: Dictionary = steps[_step_idx]
	var r := _spot_rect(step).grow(8.0)
	_lay_spotlight(r)
	step_label.text = "引导 %d / %d" % [_step_idx + 1, steps.size()]
	text_label.text = step.text
	next_button.visible = step.get("event", "") == ""
	_lay_tip(r, step.get("tip", "left"), gen)
	_start_step_timeout(step, gen)
	# 本步骤等待的事件若早已到达，立即推进
	var ev: String = step.get("event", "")
	if ev != "" and _pending_events.has(ev):
		_pending_events.erase(ev)
		_advance.call_deferred()


## 超时升级提示步骤：timeout_sec 秒后把气泡文案换成 timeout_text（只换字，不推进）
func _start_step_timeout(step: Dictionary, gen: int) -> void:
	if not step.has("timeout_sec"):
		return
	var t := get_tree().create_timer(step.timeout_sec)
	t.timeout.connect(func() -> void:
		if visible and gen == _step_gen and _step_idx < steps.size():
			text_label.text = step.get("timeout_text", step.text))


func _spot_rect(step: Dictionary) -> Rect2:
	var node: Node = step.node
	if node is Control:
		return (node as Control).get_global_rect()
	# Node2D（如棋盘 Grid）：用 transform 原点 + 指定尺寸
	var t: Transform2D = (node as Node2D).get_global_transform_with_canvas()
	return Rect2(t.origin, step.get("size", Vector2(448, 448)))


## 四块暗幕拼出聚光洞 + 金色虚框（用 4 条细矩形近似）
func _lay_spotlight(r: Rect2) -> void:
	var vp := get_viewport_rect().size
	dim_top.position = Vector2.ZERO
	dim_top.size = Vector2(vp.x, max(0.0, r.position.y))
	dim_bottom.position = Vector2(0, r.end.y)
	dim_bottom.size = Vector2(vp.x, max(0.0, vp.y - r.end.y))
	dim_left.position = Vector2(0, r.position.y)
	dim_left.size = Vector2(max(0.0, r.position.x), r.size.y)
	dim_right.position = Vector2(r.end.x, r.position.y)
	dim_right.size = Vector2(max(0.0, vp.x - r.end.x), r.size.y)
	var t := 3.0
	border_top.position = r.position - Vector2(t, t)
	border_top.size = Vector2(r.size.x + t * 2, t)
	border_bottom.position = Vector2(r.position.x - t, r.end.y)
	border_bottom.size = Vector2(r.size.x + t * 2, t)
	border_left.position = r.position - Vector2(t, t)
	border_left.size = Vector2(t, r.size.y + t * 2)
	border_right.position = Vector2(r.end.x, r.position.y - t)
	border_right.size = Vector2(t, r.size.y + t * 2)


func _lay_tip(r: Rect2, side: String, gen: int = -1) -> void:
	await get_tree().process_frame  # 等文本排版完成再取尺寸
	if not visible or _step_idx >= steps.size() or gen != _step_gen:
		return
	var tip_size := tip_panel.get_combined_minimum_size()
	var vp := get_viewport_rect().size
	var pos := Vector2.ZERO
	match side:
		"right":
			pos = Vector2(r.end.x + 18, clampf(r.get_center().y - tip_size.y / 2, 8, vp.y - tip_size.y - 8))
			if pos.x + tip_size.x > vp.x - 8:
				pos.x = max(8.0, r.position.x - tip_size.x - 18)
		"below":
			pos = Vector2(clampf(r.get_center().x - tip_size.x / 2, 8, vp.x - tip_size.x - 8),
					r.end.y + 18)
			if pos.y + tip_size.y > vp.y - 8:
				pos.y = max(8.0, r.position.y - tip_size.y - 18)
		_:  # left
			pos = Vector2(r.position.x - tip_size.x - 18, clampf(r.get_center().y - tip_size.y / 2, 8, vp.y - tip_size.y - 8))
			if pos.x < 8:
				pos.x = min(r.end.x + 18, vp.x - tip_size.x - 8)
	tip_panel.position = pos


## 新一局进关时由 main 调用：清局内放行，让"看过"判定重新按关卡标记来
func reset_run() -> void:
	_run_level = ""


func _finish() -> void:
	_step_gen += 1
	_pending_events.clear()
	GameSettings.set_value("tutorial_done_" + GameState.current_level_id, true)
	GameSettings.set_value("tutorial_done", true)  # 旧全局标记，兼容存档
	hide()
	finished.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_finish()
		get_viewport().set_input_as_handled()
