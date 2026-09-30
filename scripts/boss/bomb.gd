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
const BOMB_SHADOW := preload("res://visual_v2/runtime/boss/bomb_shadow.png")
const BOMB_FUSE_0 := preload("res://visual_v2/runtime/boss/bomb_fuse_0.png")
const BOMB_FUSE_1 := preload("res://visual_v2/runtime/boss/bomb_fuse_1.png")
const BOMB_DEFLECT := preload("res://visual_v2/runtime/boss/bomb_deflect.png")
const BOMB_EXPLOSION := [
	preload("res://visual_v2/runtime/boss/bomb_explosion0.png"),
	preload("res://visual_v2/runtime/boss/bomb_explosion1.png"),
	preload("res://visual_v2/runtime/boss/bomb_explosion2.png"),
	preload("res://visual_v2/runtime/boss/bomb_explosion3.png"),
]
var _sprite: Sprite2D


func _ready() -> void:
	z_index = 12  # 高于 Cell 与 Robot，低于史莱姆/虫（同层压格）
	_build_visual()


func _build_visual() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "BombSprite"
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)


func setup(at: Vector2i, grid) -> void:
	coord = at
	_grid = grid
	position = grid.coord_to_world(at)
	_apply_shadow_visual()


func _apply_shadow_visual() -> void:
	# 阴影预告：定制落点图从大缩小。
	_sprite.texture = BOMB_SHADOW
	scale = Vector2(1.6, 1.6)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(0.9, 0.9), SHADOW_SEC)


func _apply_fuse_visual(grid) -> void:
	_sprite.texture = BOMB_FUSE_0
	var cell = grid.get_cell(coord)
	if cell != null:
		cell.set_bomb_masked(true)  # 数字被挡（口径同网，机器人同盲）
	# 引信双帧在 tick 中按游戏时间切换，暂停时同步停住。


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
			_sprite.texture = BOMB_FUSE_0 if int(_timer * 8.0) % 2 == 0 else BOMB_FUSE_1
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
	_sprite.texture = BOMB_DEFLECT
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
	# 爆炸动效：定制火光帧放大 + 渐隐
	_sprite.texture = BOMB_EXPLOSION[0]
	var scale_tween := create_tween()
	scale_tween.tween_property(self, "scale", Vector2(2.2, 2.2), 0.24)
	scale_tween.parallel().tween_property(self, "modulate:a", 0.0, 0.26)
	var frames := create_tween()
	frames.tween_interval(0.065)
	frames.tween_callback(func(): _sprite.texture = BOMB_EXPLOSION[1])
	frames.tween_interval(0.065)
	frames.tween_callback(func(): _sprite.texture = BOMB_EXPLOSION[2])
	frames.tween_interval(0.065)
	frames.tween_callback(func(): _sprite.texture = BOMB_EXPLOSION[3])
	frames.tween_interval(0.07)
	frames.tween_callback(queue_free)
