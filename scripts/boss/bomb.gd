class_name Bomb
extends Node2D
## L5 定时落弹实体（设计 §5.2 / 实施计划 WP4）：
## 阴影预告 1.2s → 落弹压格（数字被遮，同网口径）→ 引信 5s：
##   玩家点击 = 反弹飞回 Boss（硬直 2s + 下次出招顺延 +7s + 奖励）
##   引信走完 = 爆炸，落点为中心十字 5 格火区（机器人禁入/震退/烧黏液/8s 退散）
## 与棋盘地雷强区分：黑铁壳 + 燃烧引信 + 阴影落点（不进格子层真值）
## 计时由 BossManager.tick 驱动（game_active=false 冻结时引信同步暂停）。

const SHADOW_SEC := 1.2
const FUSE_SEC := 5.0
const DEFLECT_FLY_SEC := 0.5

var coord: Vector2i = Vector2i(-1, -1)
var state := "shadow"  # shadow | fuse | deflect | exploding
var _timer := 0.0
var _grid = null
var _body: ColorRect
var _icon: Label


func _ready() -> void:
	z_index = 12  # 高于 Cell 与 Robot，低于史莱姆/虫（同层压格）
	_build_visual()


func _build_visual() -> void:
	_body = ColorRect.new()
	_body.name = "BombBody"
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.color = Color(0.12, 0.12, 0.14)
	_body.offset_left = -11
	_body.offset_top = -11
	_body.offset_right = 11
	_body.offset_bottom = 11
	add_child(_body)
	_icon = Label.new()
	_icon.name = "BombIconLabel"
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_icon.offset_left = -14
	_icon.offset_top = -16
	_icon.offset_right = 14
	_icon.offset_bottom = 12
	add_child(_icon)


func setup(at: Vector2i, grid) -> void:
	coord = at
	_grid = grid
	position = grid.coord_to_world(at)
	_apply_shadow_visual()


func _apply_shadow_visual() -> void:
	# 阴影预告：半透明灰圈放大逼近 + ⬇ 提示
	_body.color = Color(0.05, 0.05, 0.06, 0.55)
	_icon.text = "⬇"
	scale = Vector2(1.6, 1.6)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(0.9, 0.9), SHADOW_SEC)


func _apply_fuse_visual(grid) -> void:
	_body.color = Color(0.12, 0.12, 0.14)
	_icon.text = "💣"
	var cell = grid.get_cell(coord)
	if cell != null:
		cell.set_bomb_masked(true)  # 数字被挡（口径同网，机器人同盲）
	# 引信闪烁：红白交替加速紧张感
	var tw := create_tween().set_loops(int(FUSE_SEC / 0.25))
	tw.tween_property(_body, "color", Color(0.45, 0.10, 0.10), 0.125)
	tw.tween_property(_body, "color", Color(0.12, 0.12, 0.14), 0.125)


func is_active() -> bool:
	return state == "shadow" or state == "fuse"


## BossManager.tick 驱动（冻结时不调用）；落弹/引爆时回调 boss 侧
func tick(delta: float, grid, boss: BossManager) -> void:
	_timer += delta
	match state:
		"shadow":
			if _timer >= SHADOW_SEC:
				_timer = 0.0
				state = "fuse"
				_apply_fuse_visual(grid)
		"fuse":
			if _timer >= FUSE_SEC:
				state = "exploding"
				_explode(grid, boss)


## 玩家点击（main 几何命中链转发）：反弹飞回 Boss
func deflect(boss: BossManager) -> void:
	if state != "fuse":
		return  # 阴影期点不到（还没落地），爆炸期已结束
	state = "deflect"
	if _grid != null:
		var cell = _grid.get_cell(coord)
		if cell != null:
			cell.set_bomb_masked(false)
	_icon.text = "💥"
	_icon.modulate = Color(1.0, 0.85, 0.3)
	var target: Vector2 = boss.beast_world_pos()
	var tw := create_tween()
	tw.tween_property(self, "position", target, DEFLECT_FLY_SEC) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "scale", Vector2(0.4, 0.4), DEFLECT_FLY_SEC)
	tw.tween_callback(func():
		boss.on_bomb_deflected()
		queue_free())


## 引爆炸火区：十字 5 格（只点已开格，不烧未开墙——设计 §7 边界）
func _explode(grid, boss: BossManager) -> void:
	var cell = grid.get_cell(coord)
	if cell != null:
		cell.set_bomb_masked(false)
	boss.ignite_fire_cross(coord)
	# 爆炸动效：白闪放大 + 渐隐
	_body.color = Color(1.0, 0.75, 0.3)
	_icon.text = "💥"
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(2.2, 2.2), 0.15)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.30)
	tw.tween_callback(queue_free)
