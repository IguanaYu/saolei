class_name MenuStage
extends Node2D
## 主菜单"剖面剧场"：矿井剖面背景上的常驻循环演出，让菜单第一眼是活的。
## 演出四层（自下而上）：光斑呼吸(提灯/水晶) → 岗位机器人(敲矿/凿岩+特效)
##   → 巡逻机器人(轨道/平台往返) → 偶发落石；尘埃粒子全程漂浮。
## 全部复用对局资产（micro sheets / fx sheets / shadow_blob），不读玩法状态；
## 坐标一律用 mine_cutaway 纹理像素系（1448×1086），_sync_transform 对齐背景
## KEEP_ASPECT_COVERED 的实际显示，背景裁切时演员随图同裁不露馅。
## 落位依据背景像素分析（暖光簇/红矿簇锚点），调演出只动顶部常量表。

const TEX_SIZE := Vector2(1448, 1086)  # mine_cutaway.png 实际尺寸

const SHADOW_TEX := preload("res://visual_v2/runtime/robots/shadow_blob.png")
const GLINT_SHEET := preload("res://visual_v2/runtime/fx/gold_glint_sheet.png")
const SHARD_SHEET := preload("res://visual_v2/runtime/fx/rock_shards_mask_sheet.png")
const MICRO_LOOP := preload("res://scripts/visuals/micro_sprite_loop.gd")

const ACTOR_SCALE := 1.6       # 菜单远景剧场里比局内略大，保存在感
const ACTOR_NAMES := {         # 演出节点命名（MenuActor 前缀，防 get_children 误匹配）
	"miner": "MenuActorMiner", "opener": "MenuActorOpener", "guard": "MenuActorGuard",
	"detector": "MenuActorDetector", "marker": "MenuActorMarker",
}

## 岗位演员：原位作业 + 周期特效（pos 为脚底落点，纹理像素）
const STATION_ACTORS := [
	{"kind": "miner", "pos": Vector2(330, 704), "scale": 1.7,
		"fx": "glint", "period": 2.8, "fx_offset": Vector2(-16, -12)},
	{"kind": "opener", "pos": Vector2(1200, 880), "scale": 1.7,
		"fx": "shards", "period": 3.6, "fx_offset": Vector2(-14, -8)},
]
## 巡逻演员：waypoints 往返 + 端点停顿。巡逻线只放两层可见岩架上——
## 16:9 窗口(keep_height)下背景上下各裁 ~136 纹理px，可见纹理 y∈[136,950]，
## 最底轨道桥(y≈958)会裁出屏，勿用（首版实测：演员贴屏底被切半身）。
const PATROL_ACTORS := [
	{"kind": "guard", "points": [Vector2(180, 868), Vector2(560, 868)],
		"speed": 34.0, "pause": 2.2, "phase": 0.0},
	{"kind": "detector", "points": [Vector2(950, 712), Vector2(1170, 712)],
		"speed": 26.0, "pause": 1.8, "phase": 0.45},
	{"kind": "marker", "points": [Vector2(1150, 516), Vector2(1300, 516)],
		"speed": 16.0, "pause": 3.0, "phase": 0.7},
]
## 提灯呼吸光斑（纹理坐标 = 背景暖光簇锚点）；红水晶慢脉动
const LAMP_GLOWS := [
	Vector2(216, 456), Vector2(216, 744), Vector2(1224, 264),
	Vector2(1128, 888), Vector2(984, 936), Vector2(360, 408),
]
const CRYSTAL_GLOWS := [Vector2(1272, 792), Vector2(1368, 504)]
const LAMP_COLOR := Color(1.0, 0.72, 0.35, 1.0)
const CRYSTAL_COLOR := Color(1.0, 0.22, 0.14, 1.0)
const SHARD_COLORS := [Color(0.44, 0.37, 0.28), Color(0.58, 0.50, 0.38)]

var _loops: Array = []        # [{loop}] 所有微动画循环统一推进
var _patrols: Array = []      # [{node, points, idx, dir, wait, pause, speed}]
var _station_fx: Array = []   # [{t, period, fx, pos}] 岗位特效倒计时
var _glows: Array = []        # [{sprite, base, amp, speed, phase}]
var _pebble_wait := 7.0       # 落石倒计时（先等一会儿再开始掉）
var _rng := RandomNumberGenerator.new()  # 菜单演出独立随机源
var _bg: TextureRect = null
var _glow_tex: ImageTexture = null
var _dot_tex: ImageTexture = null


func _ready() -> void:
	_rng.randomize()
	_bg = get_parent().get_node("MineBackground") as TextureRect
	_sync_transform()
	_bg.item_rect_changed.connect(_sync_transform)
	_glow_tex = _make_radial_texture(48)
	_dot_tex = _make_dot_texture(2)
	_build_glow_breathers(LAMP_GLOWS, LAMP_COLOR, 0.13, 0.05, 0.9)
	_build_glow_breathers(CRYSTAL_GLOWS, CRYSTAL_COLOR, 0.16, 0.06, 0.45)
	for cfg in STATION_ACTORS:
		_spawn_station_actor(cfg)
	for cfg in PATROL_ACTORS:
		_spawn_patrol_actor(cfg)
	_build_dust_particles()


func _process(delta: float) -> void:
	for entry in _loops:
		entry.loop.advance(delta)
	_advance_patrols(delta)
	_advance_station_fx(delta)
	_advance_glow_breathers(delta)
	_advance_pebbles(delta)


# ---- 与背景对齐（COVERED 换算） ----

## 让本层坐标系 == mine_cutaway 纹理像素系：背景怎么裁切缩放，演员就跟着贴哪
func _sync_transform() -> void:
	if _bg == null or _bg.texture == null:
		return
	var tex := _bg.texture.get_size()
	var rect := _bg.size
	var s := maxf(rect.x / tex.x, rect.y / tex.y)
	scale = Vector2(s, s)
	position = (rect - tex * s) * 0.5


# ---- 演员 ----

func _spawn_actor_node(kind: String, pos: Vector2, scl: float) -> Dictionary:
	var node := Node2D.new()
	node.name = ACTOR_NAMES.get(kind, "MenuActor")
	node.position = pos
	node.scale = Vector2(scl, scl)
	var shadow := Sprite2D.new()
	shadow.name = "FootShadow"
	shadow.texture = SHADOW_TEX
	shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shadow.z_index = -1
	shadow.position = Vector2(0, 9)  # 与局内一致：露皮肤下缘月牙
	node.add_child(shadow)
	var skin := Sprite2D.new()
	skin.name = "Skin"
	skin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.add_child(skin)
	add_child(node)
	var loop := MICRO_LOOP.new()
	loop.configure(skin, kind)
	_loops.append({"loop": loop})
	return {"node": node, "skin": skin}


func _spawn_station_actor(cfg: Dictionary) -> void:
	var actor := _spawn_actor_node(cfg.kind, cfg.pos, float(cfg.get("scale", ACTOR_SCALE)))
	_station_fx.append({
		"t": _rng.randf() * float(cfg.period),
		"period": float(cfg.period),
		"fx": cfg.fx,
		"pos": actor.node.position + Vector2(cfg.fx_offset),
	})


func _spawn_patrol_actor(cfg: Dictionary) -> void:
	var points: Array = cfg.points
	var start_i := 0
	var start_pos: Vector2 = points[0]
	# phase ∈ [0,1)：沿线段长度比例直接落位，开场即分散
	var leg: Vector2 = points[1] - points[0]
	var k := float(cfg.get("phase", 0.0))
	start_pos = points[0] + leg * k
	var actor := _spawn_actor_node(cfg.kind, start_pos, ACTOR_SCALE)
	_patrols.append({
		"node": actor.node,
		"skin": actor.skin,
		"points": points,
		"idx": 0,
		"dir": 1,
		"wait": 0.0,
		"pause": float(cfg.pause),
		"speed": float(cfg.speed),
	})


func _advance_patrols(delta: float) -> void:
	for p in _patrols:
		var node: Node2D = p.node
		if not is_instance_valid(node):
			continue
		if p.wait > 0.0:
			p.wait -= delta
			continue
		var target: Vector2 = p.points[p.idx + 1] if p.dir > 0 else p.points[p.idx]
		var to_target: Vector2 = target - node.position
		var step := float(p.speed) * delta
		if to_target.length() <= step:
			node.position = target
			p.idx += p.dir
			if p.idx >= p.points.size() - 1 or p.idx < 0:
				p.dir *= -1
				p.idx = clampi(p.idx, 0, p.points.size() - 1)
			p.wait = float(p.pause) * _rng.randf_range(0.7, 1.3)
		else:
			node.position += to_target.normalized() * step
			p.skin.flip_h = to_target.x < 0


# ---- 岗位特效（金光 / 岩屑，复用局内 sheet 与帧手法） ----

func _advance_station_fx(delta: float) -> void:
	for e in _station_fx:
		e.t -= delta
		if e.t > 0.0:
			continue
		e.t += e.period * _rng.randf_range(0.85, 1.15)
		if e.fx == "glint":
			_play_glint(e.pos)
		else:
			_play_shards(e.pos)


func _play_glint(pos: Vector2) -> void:
	var s := Sprite2D.new()
	s.name = "MenuFxGlint"
	s.texture = _frame(GLINT_SHEET, 0, 12, 12)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.position = pos
	add_child(s)
	var t := s.create_tween()
	for i in 3:
		t.tween_callback(func(): s.texture = _frame(GLINT_SHEET, i, 12, 12))
		t.tween_interval(0.05)
	t.tween_callback(s.queue_free)


func _play_shards(pos: Vector2) -> void:
	for i in 2:
		var s := Sprite2D.new()
		s.name = "MenuFxShard"
		s.texture = _frame(SHARD_SHEET, i % 3, 8, 8)
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.modulate = SHARD_COLORS[i % 2]
		s.position = pos + Vector2(_rng.randf_range(-3, 3), _rng.randf_range(-3, 3))
		add_child(s)
		var dir := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, -0.2)).normalized()
		var t := s.create_tween()
		t.set_parallel(true)
		t.tween_property(s, "position", s.position + dir * _rng.randf_range(6.0, 12.0), 0.14)
		t.tween_property(s, "modulate:a", 0.0, 0.14)
		t.chain().tween_callback(s.queue_free)


func _frame(sheet: Texture2D, frame: int, fw: int, fh: int) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = sheet
	at.region = Rect2(frame * fw, 0, fw, fh)
	return at


# ---- 光斑呼吸 ----

func _build_glow_breathers(positions: Array, color: Color, base: float, amp: float, speed: float) -> void:
	for pos in positions:
		var sprite := Sprite2D.new()
		sprite.name = "MenuGlow"
		sprite.texture = _glow_tex
		sprite.modulate = color
		sprite.scale = Vector2(3.5, 3.5)  # 48px 贴图 → ~168 纹理px 光域（暗区实测偏大已收敛）
		sprite.material = _make_additive_material()
		sprite.position = pos
		add_child(sprite)
		_glows.append({
			"sprite": sprite,
			"base": base,
			"amp": amp,
			"speed": speed,
			"phase": _rng.randf() * TAU,
		})


func _advance_glow_breathers(delta: float) -> void:
	for g in _glows:
		g.phase = fmod(g.phase + delta * float(g.speed), TAU)
		g.sprite.modulate.a = float(g.base) + float(g.amp) * sin(g.phase)


func _make_additive_material() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


# ---- 尘埃（洞内微粒反光，缓慢上浮） ----

func _build_dust_particles() -> void:
	var dust := CPUParticles2D.new()
	dust.name = "MenuDust"
	dust.texture = _dot_tex
	dust.amount = 36
	dust.lifetime = 7.0
	dust.preprocess = 6.0  # 进菜单即满场，不用等飘起来
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = TEX_SIZE * 0.5 - Vector2(20, 20)
	dust.direction = Vector2(0, -1)
	dust.spread = 12.0
	dust.gravity = Vector2(0, 2)  # 微弱下沉抗一下初速，成漂浮感
	dust.initial_velocity_min = 5.0
	dust.initial_velocity_max = 14.0
	dust.scale_amount_min = 0.5
	dust.scale_amount_max = 1.3
	dust.color = Color(1.0, 0.9, 0.72, 0.35)
	dust.fixed_fps = 20  # 像素风步进感
	add_child(dust)


# ---- 偶发落石（洞顶钟乳石掉小碎石，两侧避开中央 UI） ----

func _advance_pebbles(delta: float) -> void:
	_pebble_wait -= delta
	if _pebble_wait > 0.0:
		return
	_pebble_wait = _rng.randf_range(9.0, 20.0)
	var side := _rng.randf() < 0.5
	var x := _rng.randf_range(90.0, 480.0) if side else _rng.randf_range(980.0, 1370.0)
	var from := Vector2(x, _rng.randf_range(120.0, 190.0))
	var to := Vector2(x + _rng.randf_range(-16.0, 16.0), _rng.randf_range(300.0, 430.0))
	var s := Sprite2D.new()
	s.name = "MenuPebble"
	s.texture = _frame(SHARD_SHEET, _rng.randi() % 3, 8, 8)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.modulate = SHARD_COLORS[_rng.randi() % 2]
	s.position = from
	s.z_index = 3
	add_child(s)
	var t := s.create_tween()
	t.tween_property(s, "position", to, 0.55).set_ease(Tween.EASE_IN)
	# 落地弹一下再淡出
	t.tween_property(s, "position:y", to.y - 7.0, 0.16).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(s, "modulate:a", 0.0, 0.30)
	t.tween_callback(s.queue_free)


# ---- 生成的贴图 ----

func _make_radial_texture(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := float(size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c + 0.5, y - c + 0.5).length() / c
			var a := clampf(1.0 - d * d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _make_dot_texture(px: int) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)
