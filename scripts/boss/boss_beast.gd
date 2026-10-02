class_name BossBeast
extends Node2D
## L5 盘外巨兽实体（设计 §5 / 实施计划 WP2）：趴在盘框外缘的纯视觉实体，
## 无命中盒不可点击（血量=牙数，没有"打本体"）。姿态机 + 两处位置锚点。
## 三阶段 × 七姿态的 2D 像素帧。

signal pose_finished(pose: String)

const POSES := ["idle", "claw", "inhale", "growl", "staggered", "crawl", "fall"]
const ANCHORS := ["top", "right"]

const SPRITE_ROOT := "res://visual_v2/runtime/boss/beast_p%d_%s.png"

var pose := "idle"
var anchor := "top"
var phase := 1

var _sprite: Sprite2D
var _hp_back: ColorRect
var _hp_fill: ColorRect
var _hp_ticks: Array = []
var _hp_label: Label = null  # 拔牙进度文字（P2-08：条会被误读成血条，标明语义）
var _bar_w := 0.0
var _hp_ratio := 0.0
var _pose_timer: SceneTreeTimer = null

## 血条填充色随阶段（比体色亮一档，盘框上看得清）
const HP_FILL_TINT := [
	Color(0.62, 0.42, 1.0),
	Color(1.0, 0.62, 0.28),
	Color(1.0, 0.32, 0.32),
]


func _ready() -> void:
	z_index = 15  # 高于 Cell/Robot/敌虫，低于 UI 层
	_build_visual()


func _build_visual() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "BossSprite"
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	_build_hp_bar()
	_refresh_frame()


## 血条只建一次（换姿态/换阶段只换贴图，不重建节点）：横贯下腹，
## 阶段刻度白线（P2/P3 门槛牙数处），牙数即血量唯一可见出口
func _build_hp_bar() -> void:
	_hp_back = ColorRect.new()
	_hp_back.name = "BossHpBack"
	_hp_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_back.color = Color(0.0, 0.0, 0.0, 0.62)
	add_child(_hp_back)
	_hp_fill = ColorRect.new()
	_hp_fill.name = "BossHpFill"
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_fill.color = HP_FILL_TINT[0]
	_hp_fill.anchor_top = 0.0
	_hp_fill.anchor_bottom = 1.0   # 纵向撑满背板（offset 上下留 1px 边）
	_hp_back.add_child(_hp_fill)
	for i in 2:
		var tick := ColorRect.new()
		tick.name = "BossHpTick%d" % (i + 1)
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tick.color = Color(1, 1, 1, 0.75)
		tick.anchor_top = 0.0
		tick.anchor_bottom = 1.0
		_hp_back.add_child(tick)
		_hp_ticks.append(tick)
	# 拔牙进度文字（本体子节点而非血条子节点：不随 9px 高的条挤压；fall 时手动隐藏）
	_hp_label = Label.new()
	_hp_label.name = "BossHpLabel"
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.add_theme_font_size_override("font_size", 13)
	_hp_label.add_theme_color_override("font_color", Color(1, 0.92, 0.7, 1))
	_hp_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hp_label.add_theme_constant_override("outline_size", 4)
	add_child(_hp_label)


func _refresh_frame() -> void:
	if _sprite != null:
		_sprite.texture = load(SPRITE_ROOT % [phase, pose])


## 原生帧 140×64，对齐 28px 格子的 5 格宽盘框身位。
func layout(cell_px: int) -> void:
	_sprite.scale = Vector2.ONE * float(cell_px) / 28.0
	var frame: Vector2 = _sprite.texture.get_size() if _sprite.texture != null \
			else Vector2(140.0, 64.0)
	var w: float = frame.x * _sprite.scale.x
	var h: float = frame.y * _sprite.scale.y
	_bar_w = w - 24.0
	_hp_back.offset_left = -_bar_w / 2.0
	_hp_back.offset_right = _bar_w / 2.0
	# 体内上部（脸下方留白）：贴底会与盘框金线同高混为一体
	_hp_back.offset_top = -h / 2.0 + 5.0
	_hp_back.offset_bottom = -h / 2.0 + 14.0
	_hp_fill.offset_left = 1.0
	_hp_fill.offset_top = 1.0
	_hp_fill.offset_bottom = -1.0
	if _hp_label != null:
		_hp_label.position = Vector2(-60.0, -h / 2.0 + 16.0)
		_hp_label.size = Vector2(120.0, 18.0)
	_apply_hp()


## 阶段刻度位置（由 manager 传门槛牙数，如 [5, 11] / 总牙 20）
func setup_hp_ticks(total_teeth: int, thresholds: Array) -> void:
	for i in _hp_ticks.size():
		var tick: ColorRect = _hp_ticks[i]
		if i < thresholds.size():
			var r: float = clampf(float(thresholds[i]) / float(maxi(1, total_teeth)), 0.05, 0.95)
			tick.offset_left = _bar_w * r - 1.0
			tick.offset_right = _bar_w * r + 1.0
			tick.visible = true
		else:
			tick.visible = false


func set_hp(current: int, total: int) -> void:
	_hp_ratio = clampf(float(current) / float(maxi(1, total)), 0.0, 1.0)
	if _hp_label != null:
		_hp_label.text = "拔牙 %d/%d" % [current, total]
	_apply_hp()


func _apply_hp() -> void:
	if _hp_fill == null:
		return
	_hp_fill.offset_right = 1.0 + maxf(0.0, _bar_w - 2.0) * _hp_ratio


func set_phase(p: int) -> void:
	phase = clampi(p, 1, 3)
	_refresh_frame()
	if _hp_fill != null:
		_hp_fill.color = HP_FILL_TINT[phase - 1]


func teleport_to(anchor_id: String, world_pos: Vector2) -> void:
	anchor = anchor_id
	position = world_pos
	rotation = 0.0 if anchor == "top" else -PI / 2.0  # right 锚点贴右侧竖着趴
	_keep_label_upright()


## 本体贴右侧竖趴时文字反向旋转保持水平（P2-08 标注可读）
func _keep_label_upright() -> void:
	if _hp_label != null:
		_hp_label.rotation = -rotation


## 播放姿态（pose 持续 duration 后自动回 idle 并发 pose_finished）
func play(pose_id: String, duration: float = 1.5) -> void:
	pose = pose_id
	_refresh_frame()
	match pose_id:
		"claw", "inhale", "growl":
			# 预告姿态：前倾 + 快速呼吸感（modulate 脉冲）
			var tw := create_tween().set_loops(3)
			tw.tween_property(self, "modulate",
					Color(1.3, 1.15, 1.15, 1.0), duration / 6.0)
			tw.tween_property(self, "modulate", Color.WHITE, duration / 6.0)
		"staggered":
			# 硬直：压暗 + 抖动
			modulate = Color(0.55, 0.55, 0.6, 1.0)
			var tw := create_tween()
			for i in 5:
				tw.tween_property(self, "position:x", position.x + 6.0, 0.03)
				tw.tween_property(self, "position:x", position.x - 6.0, 0.03)
			tw.tween_property(self, "position:x", position.x, 0.02)
		"crawl":
			modulate = Color.WHITE
		"fall":
			# 斩杀掉落：失足下坠 + 旋转 + 渐隐（血条与拔牙标注随本体退场）
			modulate = Color.WHITE
			_hp_back.visible = false
			if _hp_label != null:
				_hp_label.visible = false
			var tw := create_tween()
			tw.set_parallel(true)
			tw.tween_property(self, "position:y", position.y + 520.0, 2.6) \
					.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_property(self, "rotation", rotation + PI * 1.5, 2.6)
			tw.tween_property(self, "modulate:a", 0.0, 2.6)
			tw.chain().tween_callback(func(): pose_finished.emit("fall"))
			return
		"idle":
			modulate = Color.WHITE
	_pose_timer = get_tree().create_timer(duration)
	_pose_timer.timeout.connect(func():
		if pose == pose_id:
			pose = "idle"
			modulate = Color.WHITE
			_refresh_frame()
			pose_finished.emit(pose_id))


## 换位爬行（top → right）：沿盘框外缘两段位移，全程 duration 秒
func crawl_to(anchor_id: String, corner_pos: Vector2, target_pos: Vector2, duration: float) -> void:
	anchor = anchor_id
	pose = "crawl"
	_refresh_frame()
	var tw := create_tween()
	tw.tween_property(self, "position", corner_pos, duration * 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "position", target_pos, duration * 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func():
		rotation = -PI / 2.0 if anchor_id == "right" else 0.0
		_keep_label_upright()
		pose = "idle"
		_refresh_frame()
		pose_finished.emit("crawl"))
