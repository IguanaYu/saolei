class_name BossBeast
extends Node2D
## L5 盘外巨兽实体（设计 §5 / 实施计划 WP2）：趴在盘框外缘的纯视觉实体，
## 无命中盒不可点击（血量=牙数，没有"打本体"）。姿态机 + 两处位置锚点。
## 占位视觉（WP8 换正式素材）：深色巨兽色块 + emoji + 三阶段损伤色调

signal pose_finished(pose: String)

const POSES := ["idle", "claw", "inhale", "growl", "staggered", "crawl", "fall"]
const ANCHORS := ["top", "right"]

## 三阶段损伤色调（占位）：P1 完整深紫 / P2 裂纹褪色 / P3 泛红狂暴
const PHASE_TINT := [
	Color(0.36, 0.22, 0.48),
	Color(0.48, 0.30, 0.38),
	Color(0.58, 0.24, 0.24),
]

var pose := "idle"
var anchor := "top"
var phase := 1

var _body: ColorRect
var _icon: Label
var _pose_timer: SceneTreeTimer = null


func _ready() -> void:
	z_index = 15  # 高于 Cell/Robot/敌虫，低于 UI 层
	_build_placeholder_visual()


func _build_placeholder_visual() -> void:
	# 显式命名，避免 get_children() 遍历误匹配（AGENTS.md 守则）
	_body = ColorRect.new()
	_body.name = "BossBody"
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.color = PHASE_TINT[0]
	_body.z_index = 0
	add_child(_body)
	_icon = Label.new()
	_icon.name = "BossIconLabel"
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_icon.text = "👹"
	_icon.add_theme_font_size_override("font_size", 44)
	add_child(_icon)


## 占位身位：约 5 格宽 × 2.2 格高（贴盘框外缘；正方向随锚点旋转）
func layout(cell_px: int) -> void:
	var w := cell_px * 5.0
	var h := cell_px * 2.2
	_body.offset_left = -w / 2.0
	_body.offset_right = w / 2.0
	_body.offset_top = -h / 2.0
	_body.offset_bottom = h / 2.0
	_icon.offset_left = -w / 2.0
	_icon.offset_right = w / 2.0
	_icon.offset_top = -h / 2.0
	_icon.offset_bottom = h / 2.0


func set_phase(p: int) -> void:
	phase = clampi(p, 1, 3)
	_body.color = PHASE_TINT[phase - 1]


func teleport_to(anchor_id: String, world_pos: Vector2) -> void:
	anchor = anchor_id
	position = world_pos
	rotation = 0.0 if anchor == "top" else -PI / 2.0  # right 锚点贴右侧竖着趴


## 播放姿态（pose 持续 duration 后自动回 idle 并发 pose_finished）
func play(pose_id: String, duration: float = 1.5) -> void:
	pose = pose_id
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
			# 斩杀掉落：失足下坠 + 旋转 + 渐隐
			modulate = Color.WHITE
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
			pose_finished.emit(pose_id))


## 换位爬行（top → right）：沿盘框外缘两段位移，全程 duration 秒
func crawl_to(anchor_id: String, corner_pos: Vector2, target_pos: Vector2, duration: float) -> void:
	anchor = anchor_id
	pose = "crawl"
	var tw := create_tween()
	tw.tween_property(self, "position", corner_pos, duration * 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "position", target_pos, duration * 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func():
		rotation = -PI / 2.0 if anchor_id == "right" else 0.0
		pose = "idle"
		pose_finished.emit("crawl"))
