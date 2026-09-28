extends Control
class_name CDRing
## 光标恢复环：跟随鼠标显示玩家操作充能状态
## 三态：0 层=倒计时（被拦）/ 有存款=下一层进度弧+层数 / 满仓=隐藏
## 纯代码控件，由 main.gd 挂到 UILayer；显隐由每帧读取 GameState 驱动

const RADIUS := 15.0
const RING_COLOR := Color(1.0, 0.82, 0.3)
const READY_COLOR := Color(0.45, 0.9, 0.5)
const WARN_COLOR := Color(1.0, 0.35, 0.3)

var _shake_tween: Tween = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _ready() -> void:
	GameState.cd_blocked.connect(_shake)
	z_index = 100


func _process(_delta: float) -> void:
	# 满仓无事可报 → 隐藏；其余冷却态都显示（被拦倒计时 / 囤层进度）
	if not GameState.game_active or GameState.cd_phase != "cooldown" \
			or GameState.cd_charges >= GameState.cd_max_charges:
		visible = false
		return
	visible = true
	position = get_global_mouse_position() + Vector2(22, 22)
	queue_redraw()


func _draw() -> void:
	var dur: float = GameState.cd_duration
	var rem: float = GameState.cd_remaining
	var charges: int = GameState.cd_charges
	draw_circle(Vector2.ZERO, RADIUS + 5, Color(0, 0, 0, 0.5))
	draw_arc(Vector2.ZERO, RADIUS, 0, TAU, 40, Color(1, 1, 1, 0.25), 4.0)
	var font := ThemeDB.fallback_font
	var ratio: float = 1.0 - (rem / dur) if dur > 0.0 else 1.0
	if charges <= 0:
		# 0 层被拦：倒计时秒数（临近完成转红感更弱、剩余久金色）
		var col := WARN_COLOR if rem <= 3.0 else RING_COLOR
		draw_arc(Vector2.ZERO, RADIUS, -PI / 2, -PI / 2 + TAU * ratio, 40, col, 4.0)
		var txt := str(int(ceil(rem)))
		var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
		draw_string(font, Vector2(-ts.x / 2.0, 4.5), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	else:
		# 有存款：可花层数为主体 + 下一层进度弧（细一档，不抢读数）
		draw_arc(Vector2.ZERO, RADIUS, -PI / 2, -PI / 2 + TAU * ratio, 40, READY_COLOR, 2.0)
		var label := "×%d" % charges
		var ls := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		draw_string(font, Vector2(-ls.x / 2.0, 4.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, READY_COLOR)


## CD 中点击：环抖一下，告知"点了但没次数"
func _shake() -> void:
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	scale = Vector2.ONE
	_shake_tween = create_tween()
	_shake_tween.tween_property(self, "scale", Vector2(1.25, 1.25), 0.05)
	_shake_tween.tween_property(self, "scale", Vector2.ONE, 0.12)
