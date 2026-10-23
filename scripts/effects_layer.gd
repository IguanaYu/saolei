class_name EffectsLayer
extends Node2D
## 局内动效层：开格岩屑 / 收益跳字 / 插旗灰尘 / 卸货金光飞币
## 设计稿：docs/active/局内交互动效设计-v1.md
## 挂在 Grid 下（z=45，盖过格子与悬停层）；坐标与 Cell 同为 Grid 本地系
## 预算：同屏高亮跳字 ≤2 处、每处 ≤0.6s，超出并入最新一处（§频率与可读性）

const SHARD_SHEET := preload("res://visual_v2/runtime/fx/rock_shards_mask_sheet.png")
const GLINT_SHEET := preload("res://visual_v2/runtime/fx/gold_glint_sheet.png")
const FLAG_FINAL := preload("res://visual_v2/runtime/completion/tiles/special_flag.png")
const DUST_SHEET := preload("res://visual_v2/runtime/fx/flag_dust_sheet.png")
const COIN_TEX := preload("res://visual_v2/runtime/ui/icons/icon_coin.png")

const GOLD := Color(1.0, 0.753, 0.29)  # 矿金 #f0c04a

## 岩壁主题 → 岩屑色（深/中/亮；F5 切主题自动跟色）
const SHARD_COLORS := {
	"V2": [Color(0.30, 0.25, 0.20), Color(0.44, 0.37, 0.28), Color(0.58, 0.50, 0.38)],
	"V2C": [Color(0.20, 0.26, 0.32), Color(0.30, 0.40, 0.47), Color(0.44, 0.56, 0.62)],
	"V2M": [Color(0.22, 0.28, 0.20), Color(0.33, 0.42, 0.28), Color(0.47, 0.56, 0.38)],
	"V2R": [Color(0.34, 0.22, 0.17), Color(0.48, 0.32, 0.23), Color(0.62, 0.44, 0.30)],
}

var wall_style := "V2"

var _jump_texts: Array[Node2D] = []  # 活跃跳字（预算与并入用）
var _seq := 0  # 临时节点编号：同名兄弟会被 Godot 改名 @xx@2，显式唯一命名便于排查
var _visual_rng := RandomNumberGenerator.new()


func _ready() -> void:
	_visual_rng.randomize()  # 新碎屑不能改变过载巡逻或筑墙工的玩法随机序列


## 临时节点统一取名：Kind + 序号（如 JumpText007）
func _name(kind: String) -> StringName:
	_seq += 1
	return StringName("%s%04d" % [kind, _seq])


# ---- 开格（批次入口：单格/连锁由 Grid 的 cell_open_batch 驱动）----

## 单格：仅玩家 +1 跳字（岩屑已并入波纹调度 fx_reveal_wave）
func fx_open_single(cell: Cell, by_actor: String) -> void:
	if by_actor == "player":
		_fx_jump_text(cell.position + Vector2(10, -12), "+1")


## 连锁：起点汇总 +N（锚在起点；岩屑已并入波纹调度 fx_reveal_wave）
func fx_open_chain(start_cell: Cell, chain: Array) -> void:
	_fx_jump_text(start_cell.position + Vector2(10, -14),
		"+%d" % chain.size())


## 扩散波纹岩屑：全程 ≤6 处采样，各自在波前到达时刻弹出
## 玩家 3 粒 / 机器人与开局预开 1 粒（大片开疆也只点缀，避免糊屏）
func fx_reveal_wave(entries: Array, by_actor: String) -> void:
	if entries.is_empty():
		return
	var sample_step: int = maxi(1, int(ceil(entries.size() / 6.0)))
	var count: int = 3 if by_actor == "player" else 1
	for i in range(0, entries.size(), sample_step):
		var cell: Cell = entries[i]["cell"]
		var t := cell.create_tween()  # 重开时随旧格销毁，不能留下延迟回调。
		t.tween_interval(float(entries[i]["delay"]))
		t.tween_callback(func():
			if is_instance_valid(cell):
				_fx_shards(cell, count))


func on_open_batch(start_cell: Cell, by_actor: String, chain: Array) -> void:
	if chain.is_empty():
		return
	if chain.size() == 1:
		fx_open_single(chain[0], by_actor)
	else:
		fx_open_chain(start_cell, chain)


# ---- 插旗 / 撤旗 ----

## 插旗的灰尘（旗面下落+回弹动画在 Cell 自己的图标层播放）
func fx_flag_dust(cell: Cell) -> void:
	var dust := Sprite2D.new()
	dust.name = _name("FlagDust")
	dust.texture = _frame(DUST_SHEET, 0, 16, 12)
	dust.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 规格：灰尘相对格子左上角 (1,16) → 格中心本地 (-13, 2)
	dust.position = cell.position + Vector2(-13, 2)
	add_child(dust)
	var t := dust.create_tween()
	t.tween_interval(0.10)  # 等旗面落地
	for i in 3:
		t.tween_callback(func(): dust.texture = _frame(DUST_SHEET, i, 16, 12))
		t.tween_interval(0.06)
	t.tween_callback(dust.queue_free)


## 撤旗：拔出淡出（此时 Cell 图标已被 refresh 清掉，用副本动画）
func fx_flag_pull(cell: Cell) -> void:
	var s := Sprite2D.new()
	s.name = _name("FlagPull")
	s.texture = FLAG_FINAL
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.position = cell.position
	add_child(s)
	var t := s.create_tween()
	t.set_parallel(true)
	t.tween_property(s, "position:y", cell.position.y - 10.0, 0.10)
	t.tween_property(s, "modulate:a", 0.0, 0.10)
	t.chain().tween_callback(s.queue_free)


# ---- 矿工卸货 ----

## world_pos：矿工（基地旁）全局坐标；金额当帧已入账，这里只做确认动效
func fx_unload(world_pos: Vector2, amount: int) -> void:
	var local := to_local(world_pos)
	# 基地短亮
	var grid := get_parent() as Grid
	var coord := grid.world_to_coord(world_pos)
	var cell: Cell = grid.get_cell(coord)
	if cell != null:
		var t := cell.create_tween()
		t.tween_property(cell, "modulate", Color(1.5, 1.4, 1.1), 0.08)
		t.tween_property(cell, "modulate", Color.WHITE, 0.10)
	# 金光三帧
	var glint := Sprite2D.new()
	glint.name = _name("GoldGlint")
	glint.texture = _frame(GLINT_SHEET, 0, 12, 12)
	glint.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	glint.position = local + Vector2(0, -6)
	add_child(glint)
	var gt := glint.create_tween()
	for i in 3:
		gt.tween_callback(func(): glint.texture = _frame(GLINT_SHEET, i, 12, 12))
		gt.tween_interval(0.05)
	gt.tween_callback(glint.queue_free)
	# 收益跳字
	_fx_jump_text(local + Vector2(8, -20), "+%d" % amount)
	# 2-3 枚金币短弧线飞向 HUD（无 HUD 目标则跳过）
	var hud: Control = get_tree().get_first_node_in_group("hud_money")
	if hud == null:
		return
	var target := to_local(hud.get_global_rect().get_center())
	for i in 3:
		_fly_coin(local, target, 0.05 * i)


# ---- 机器人出厂（购买/开局赠送；docs/active/机器人出生反馈-方案-v1.md）----

## 基地短亮（"工厂开工"）；同 fx_unload 的基地亮语言
func fx_base_flash(cell: Cell) -> void:
	if cell == null:
		return
	var t := cell.create_tween()
	t.tween_property(cell, "modulate", Color(1.5, 1.4, 1.1), 0.08)
	t.tween_property(cell, "modulate", Color.WHITE, 0.10)


## 皮肤首帧做飞行图标：Skin 是 hframes=3 的帧表整图，截当前帧为单帧 Atlas（零新素材）
func robot_icon_texture(skin: Sprite2D) -> Texture2D:
	if skin == null or skin.texture == null or skin.hframes < 2:
		return null
	var fw: int = skin.texture.get_width() / skin.hframes
	return _frame(skin.texture, skin.frame, fw, skin.texture.get_height())


## 出厂飞行：小机器人图标从基地飞落出生格，落地回调 on_land（机器人本体显现弹入）。
## from_local/to_local 为 Grid 本地系坐标（coord_to_world 产出）。
## 无图标或同格出生（开局赠送落在基地格）时退化为等价延迟后直接落地。
## 两条路径都绑在临时节点上：clear_all 重开清场时回调随节点一起销毁，不会迟到触发。
func fx_robot_deliver(from_local: Vector2, to_local: Vector2, icon: Texture2D,
		delay_s: float, on_land: Callable) -> void:
	var spr := Sprite2D.new()
	spr.name = _name("RobotFly")
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if icon != null and from_local.distance_to(to_local) >= 1.0:
		spr.texture = icon
		spr.scale = Vector2(0.8, 0.8)
		spr.position = from_local
	else:
		spr.visible = false  # 同格/无图：只当延迟计时器用
	add_child(spr)
	var t := spr.create_tween()
	if delay_s > 0.0:
		t.tween_interval(delay_s)
	if spr.visible:
		t.tween_property(spr, "position", to_local, 0.30).set_ease(Tween.EASE_IN)
		t.parallel().tween_property(spr, "rotation", TAU * 0.9, 0.30)
	else:
		t.tween_interval(0.15)
	t.tween_callback(on_land)
	t.tween_callback(spr.queue_free)


## 出生扬尘：复用插旗灰尘帧表，格底扩散（无插旗版的前置等待）
func fx_spawn_dust(cell: Cell) -> void:
	if cell == null:
		return
	var dust := Sprite2D.new()
	dust.name = _name("SpawnDust")
	dust.texture = _frame(DUST_SHEET, 0, 16, 12)
	dust.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	dust.position = cell.position + Vector2(0, 6)
	add_child(dust)
	var t := dust.create_tween()
	for i in 3:
		t.tween_callback(func(): dust.texture = _frame(DUST_SHEET, i, 16, 12))
		t.tween_interval(0.05)
	t.tween_callback(dust.queue_free)


# ---- 第二章激光矿场（2-1 WP3/WP4；程序绘制占位，素材批后可换贴图）----

## 激光束闪光：外层粗半透明辉光 + 内层亮芯（暖橙），0.18s 淡出。
## from/to 为 Grid 本地系（coord_to_world 产出）；挂本层吃 clear_all 重开清场
func fx_laser_flash(from_local: Vector2, to_local: Vector2) -> void:
	var beam := LaserBeamFx.new()
	beam.name = _name("LaserBeam")
	beam.length_px = from_local.distance_to(to_local)
	beam.position = from_local
	beam.rotation = (to_local - from_local).angle()
	add_child(beam)


## 束本体：双层画线（辉光+亮芯），z 压过格子（随 EffectsLayer z=45）
class LaserBeamFx extends Node2D:
	var length_px := 0.0
	var age := 0.0

	func _process(delta: float) -> void:
		if not GameState.game_active:
			queue_free()
			return
		if not preload("res://scripts/visuals/micro_sprite_loop.gd").is_gameplay_running(self):
			return
		age += delta
		if age > 0.24:
			queue_free()
		else:
			queue_redraw()

	func _draw() -> void:
		var end := Vector2(length_px, 0)
		var a := 1.0 - clampf((age - 0.06) / 0.18, 0, 1)
		draw_line(Vector2.ZERO, end, Color(1.0, 0.40, 0.12, a * 0.24), 7.0)
		draw_line(Vector2.ZERO, end, Color(1.0, 0.66, 0.25, a), 3.0)
		draw_line(Vector2.ZERO, end, Color(1.0, 0.95, 0.75, a), 1.0)
		draw_circle(Vector2.ZERO, 4.0 + age * 4, Color(1.0, 0.9, 0.6, a * 0.8))


const MECHANIC_PULSE := preload("res://scripts/visuals/mechanic_pulse.gd")


func _cell_pulse(cell: Cell, mode: String, color: Color):
	var pulse := MECHANIC_PULSE.new()
	pulse.name = _name("Mechanic" + mode.capitalize())
	pulse.mode = mode
	pulse.color = color
	pulse.entries.append({"rect": Rect2(cell.position - Vector2(14, 14), Vector2(28, 28)), "delay": 0.0})
	add_child(pulse)
	return pulse


func fx_laser_impact(cell: Cell) -> void:
	_cell_pulse(cell, "hit", Color(1, 0.8, 0.4))


func fx_flag_protected(cell: Cell) -> void:
	_cell_pulse(cell, "shield", Color(0.45, 0.95, 1.0))


func fx_builder_build(cell: Cell) -> void:
	_cell_pulse(cell, "build", Color(1, 0.6, 0.3))
	_fx_shards(cell, 2)


func fx_builder_killed(local_pos: Vector2) -> void:
	var pulse := MECHANIC_PULSE.new()
	pulse.name = _name("BuilderBreak")
	pulse.mode = "death"
	pulse.color = Color(0.85, 0.55, 0.3)
	pulse.entries.append({"rect": Rect2(local_pos - Vector2(11, 11), Vector2(22, 22)), "delay": 0.0})
	add_child(pulse)


## 削层岩屑：打墙看得见（不加分不加跳字，纯命中反馈）
func fx_wall_crack(cell: Cell) -> void:
	if cell == null:
		return
	_fx_shards(cell, 2)
	var t := cell.create_tween()
	t.tween_property(cell, "modulate", Color(1.35, 1.2, 1.0, 1.0), 0.05)
	t.tween_property(cell, "modulate", Color.WHITE, 0.10)


## 碎钻：青蓝岩屑（区别于岩壁岩屑的暖色）+ 低收益 +1 跳字（+1 由 main 结算侧入账）
func fx_diamond_shatter(cell: Cell) -> void:
	if cell == null:
		return
	for i in 3:
		var s := Sprite2D.new()
		s.name = _name("DiamondShard")
		s.texture = _frame(SHARD_SHEET, i % 3, 8, 8)
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.modulate = Color(0.45, 0.85, 1.0)
		s.position = cell.position + Vector2(_visual_rng.randf_range(-3, 3), _visual_rng.randf_range(-3, 3))
		add_child(s)
		var dir := Vector2(_visual_rng.randf_range(-1, 1), _visual_rng.randf_range(-1, 1)).normalized()
		var t := s.create_tween()
		t.set_parallel(true)
		t.tween_property(s, "position", s.position + dir * _visual_rng.randf_range(5.0, 12.0), 0.16)
		t.tween_property(s, "modulate:a", 0.0, 0.16)
		t.chain().tween_callback(s.queue_free)
	_fx_jump_text(cell.position + Vector2(10, -12), "+1")


## 四类钻石的结算快照演出。金币不并入普通「+分」跳字，动画不回调玩法逻辑。
## event.rays = [{from: Vector2i, to: Vector2i, cells: Array}]；只使用已抽好的实际射线。
func fx_diamond_effect(event: Dictionary, grid) -> void:
	var effect_id := String(event.get("effect_id", ""))
	if not preload("res://scripts/diamond/diamond_icon.gd").is_supported(effect_id):
		return
	var coord: Vector2i = event.get("coord", Vector2i(-1, -1))
	var origin_cell: Cell = grid.get_cell(coord)
	if origin_cell == null:
		return
	var feedback := DiamondEffectFeedback.new()
	feedback.name = _name("Diamond" + effect_id.capitalize().replace(" ", ""))
	feedback.effect_id = effect_id
	feedback.origin = origin_cell.position
	feedback.gold_amount = int(event.get("gold_amount", 0))
	for value in event.get("cells", []):
		var hit_coord: Vector2i = value
		var cell: Cell = grid.get_cell(hit_coord)
		if cell == null or hit_coord == coord:
			continue
		feedback.entries.append({
			"rect": Rect2(cell.position - Vector2.ONE * grid.cell_size / 2.0,
				Vector2.ONE * grid.cell_size),
			"delay": minf(origin_cell.position.distance_to(cell.position) / grid.cell_size * 0.018, 0.16),
		})
	for value in event.get("rays", []):
		if not value is Dictionary:
			continue
		var ray: Dictionary = value
		var ray_from: Vector2i = ray.get("from", coord)
		var ray_to: Vector2i = ray.get("to", coord)
		# 端点来自本枪几何快照，不能在表现阶段重抽方向或搜索隐藏目标。
		var half_cell: Vector2 = Vector2.ONE * grid.cell_size / 2.0
		feedback.rays.append({"from": Vector2(ray_from) * grid.cell_size + half_cell,
			"to": Vector2(ray_to) * grid.cell_size + half_cell})
	add_child(feedback)


class DiamondEffectFeedback extends Node2D:
	const ICON := preload("res://scripts/diamond/diamond_icon.gd")
	const MICRO_ANIMATION := preload("res://scripts/visuals/micro_sprite_loop.gd")
	var effect_id: String = ""
	var origin := Vector2.ZERO
	var gold_amount: int = 0
	var entries: Array = []
	var rays: Array = []
	var age := 0.0
	var duration := 0.62
	var _icon: Node2D
	var _label: Label
	var _label_offset := Vector2.ZERO

	func _ready() -> void:
		_icon = ICON.new()
		_icon.name = "ReleaseSymbol"
		_icon.effect_id = effect_id
		_icon.position = origin
		_icon.scale = Vector2.ONE * 1.3
		_icon.z_index = 1
		add_child(_icon)
		if effect_id == "gold" or effect_id == "explorer":
			_label = Label.new()
			_label.name = "DiamondRewardText"
			_label.text = "+%d 金币" % gold_amount if effect_id == "gold" else "探索精灵 +1"
			_label.add_theme_font_size_override("font_size", 13)
			_label.add_theme_color_override("font_color", ICON.effect_color(effect_id))
			_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05, 0.95))
			_label.add_theme_constant_override("outline_size", 3)
			_label_offset = Vector2(14, -10) if effect_id == "gold" else Vector2(10, -43)
			_label.position = origin + _label_offset
			_label.z_index = 2
			_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_label)

	func _process(delta: float) -> void:
		if not GameState.game_active:
			queue_free()
			return
		if not MICRO_ANIMATION.is_gameplay_running(self):
			return
		age += delta
		if age >= duration:
			queue_free()
			return
		var progress := age / duration
		_icon.scale = Vector2.ONE * (1.3 + sin(progress * PI) * 0.45)
		_icon.modulate.a = 1.0 - clampf((progress - 0.45) / 0.55, 0.0, 1.0)
		if _label != null:
			_label.position.y = origin.y + _label_offset.y - progress * 15.0
			_label.modulate.a = 1.0 - clampf((progress - 0.55) / 0.45, 0.0, 1.0)
		queue_redraw()

	func _draw() -> void:
		var tint := ICON.effect_color(effect_id)
		var a := 1.0 - clampf(age / duration, 0.0, 1.0)
		# 源点短环使混合连锁能看出接力源；图标另以形状区分类别。
		draw_arc(origin, 7.0 + age * 19.0, 0.0, TAU, 24, Color(tint, a * 0.8), 1.5)
		for entry in entries:
			var t := age - float(entry.delay)
			if t < 0.0 or t > 0.32:
				continue
			var cell_alpha := minf(t / 0.03, 1.0) * (1.0 - t / 0.32)
			var rect: Rect2 = entry.rect
			draw_rect(rect.grow(-2), Color(tint, cell_alpha * 0.10))
			draw_rect(rect.grow(-2), Color(tint, cell_alpha * 0.85), false, 1.2)
		var ray_age := age - 0.025
		if ray_age < 0.0 or ray_age > 0.32:
			return
		var ray_alpha := 1.0 - ray_age / 0.32
		for ray in rays:
			var from: Vector2 = ray.from
			var to: Vector2 = from.lerp(ray.to, clampf(ray_age / 0.07, 0.0, 1.0))
			draw_line(from, to, Color(tint, ray_alpha * 0.22), 6.0)
			draw_line(from, to, Color(tint.lightened(0.4), ray_alpha), 2.0)


## 2-4 连爆节点消耗演出：3×3 短亮框（Grid 本地，边界内裁切）+ 节点本体错峰收缩
## （play_consume）；奖励跳字只在真实开格/拆墙/击杀时出现（设计 §5"节点自身 0 分"）
func fx_chain_blast_at(n: ChainNode, grid, delay: float) -> void:
	n.play_consume(delay)
	var frame := ChainBlastFrame.new()
	frame.name = _name("ChainBlast")
	for dy in 3:
		for dx in 3:
			var c: Vector2i = n.coord + Vector2i(dx - 1, dy - 1)
			var cell: Cell = grid.get_cell(c)
			if cell == null:
				continue
			frame.rects.append(Rect2(cell.position - Vector2(grid.cell_size / 2.0,
					grid.cell_size / 2.0), Vector2(grid.cell_size, grid.cell_size)))
	add_child(frame)
	frame.modulate.a = 0.0
	var t := frame.create_tween()
	t.tween_interval(delay)
	t.tween_property(frame, "modulate:a", 1.0, 0.03)
	t.tween_property(frame, "modulate:a", 0.0, 0.25)
	t.tween_callback(frame.queue_free)


## 连爆 3×3 亮框本体：半透明暖橙填充 + 亮边（随延迟淡入淡出，编排在上方法）；
## fill/edge 色可注入（改版矿石/过载复用同一本体，默认值=连爆原色零影响）
class ChainBlastFrame extends Node2D:
	var rects: Array = []
	var fill_color := Color(1.0, 0.45, 0.15, 0.20)
	var edge_color := Color(1.0, 0.65, 0.30, 0.65)

	func _draw() -> void:
		for r in rects:
			draw_rect(r, fill_color, true)
			draw_rect(r, edge_color, false, 1.5)


## 改版 2-3 特殊矿石爆发演出：爆发格青蓝短亮框（Grid 本地，边界内裁切）+
## 足迹心跳一拍（不可破坏=不播放消耗动画，与节点收缩消失语义区分）
func fx_ore_burst(ore: SpecialOre, cells: Array, grid, rays: Array = []) -> void:
	var frame := MECHANIC_PULSE.new()
	frame.name = _name("OreBlast")
	frame.color = Color(0.35, 0.9, 1.0)
	var center: Vector2 = ore.position - grid.position
	for c in cells:
		var cell: Cell = grid.get_cell(c)
		if cell == null or cell.is_flagged:
			continue
		frame.entries.append({"rect": Rect2(cell.position - Vector2.ONE * grid.cell_size / 2.0,
				Vector2.ONE * grid.cell_size), "delay": 0.04 + center.distance_to(cell.position) / grid.cell_size * 0.025})
	for ray in rays:
		frame.rays.append({"from": grid.get_cell(ray.from).position, "to": grid.get_cell(ray.to).position})
	add_child(frame)
	ore.play_activate()


## 改版 2-4 过载爆炸演出：13 格短亮框 + 本体脉冲一拍（爆后存活：闪不缩）
func fx_overload_blast(r: OverloadRobot, grid, snapshot_cells: Array = []) -> void:
	var frame := MECHANIC_PULSE.new()
	frame.name = _name("OverloadBlast")
	frame.color = Color(1.0, 0.55, 0.25)
	var cells: Array = r.blast_cells(grid) if snapshot_cells.is_empty() else snapshot_cells
	for c in cells:
		var cell: Cell = grid.get_cell(c)
		if cell == null or cell.is_flagged:
			continue
		var dist := maxi(absi(c.x - r.coord.x), absi(c.y - r.coord.y))
		frame.entries.append({"rect": Rect2(cell.position - Vector2.ONE * grid.cell_size / 2.0,
				Vector2.ONE * grid.cell_size), "delay": 0.025 * dist})
	add_child(frame)
	r.play_blast()


## 2-5 引光柱破碎：暖玉碎块飞散 + 「-50」暗红大跳字（扣分在 laser_manager 结算侧入账）
func fx_pillar_broken(cell: Cell) -> void:
	if cell == null:
		return
	for i in 5:
		var s := Sprite2D.new()
		s.name = _name("PillarShard")
		s.texture = _frame(SHARD_SHEET, i % 3, 8, 8)
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.modulate = Color(0.95, 0.88, 0.6)
		s.position = cell.position + Vector2(_visual_rng.randf_range(-4, 4), _visual_rng.randf_range(-8, 4))
		add_child(s)
		var dir := Vector2(_visual_rng.randf_range(-1, 1), _visual_rng.randf_range(-1.2, 0.2)).normalized()
		var t := s.create_tween()
		t.set_parallel(true)
		t.tween_property(s, "position", s.position + dir * _visual_rng.randf_range(8.0, 18.0), 0.30)
		t.tween_property(s, "modulate:a", 0.0, 0.30)
		t.chain().tween_callback(s.queue_free)
	var node := Node2D.new()
	node.name = _name("PillarPenalty")
	var lbl := Label.new()
	lbl.text = "-50"
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 3)
	node.add_child(lbl)
	node.position = cell.position + Vector2(-10, -18)
	add_child(node)
	var t2 := node.create_tween()
	t2.set_parallel(true)
	t2.tween_property(node, "position:y", node.position.y - 14.0, 0.55)
	t2.tween_property(node, "modulate:a", 0.0, 0.55)
	t2.chain().tween_callback(node.queue_free)


# ---- 清理 ----

## 重开/切关时清空全部临时动效（由 Grid.init_empty_grid 调用）
func clear_all() -> void:
	for c in get_children():
		c.queue_free()
	_jump_texts.clear()


# ---- L5 Boss 关 ----

## 拔牙跳图：16px 牙齿贴图从处理格升起。
func fx_tooth_pulled(world_pos: Vector2) -> void:
	var node := Node2D.new()
	node.name = _name("Tooth")
	var sprite := Sprite2D.new()
	sprite.name = "ToothSprite"
	sprite.texture = preload("res://visual_v2/runtime/completion/fx/tooth.png")
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.add_child(sprite)
	node.position = world_pos
	add_child(node)
	var t := node.create_tween()
	t.set_parallel(true)
	t.tween_property(node, "position:y", world_pos.y - 16.0, 0.5)
	t.tween_property(node, "modulate:a", 0.0, 0.5)
	t.chain().tween_callback(node.queue_free)


# ---- 内部 ----

func _fx_shards(cell: Cell, count: int) -> void:
	var palette: Array = SHARD_COLORS.get(wall_style, SHARD_COLORS["V2"])
	for i in count:
		var s := Sprite2D.new()
		s.name = _name("Shard")
		s.texture = _frame(SHARD_SHEET, i % 3, 8, 8)
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.modulate = palette[i % 3]
		s.position = cell.position + Vector2(_visual_rng.randf_range(-4, 4), _visual_rng.randf_range(-4, 4))
		add_child(s)
		var dir := Vector2(_visual_rng.randf_range(-1, 1), _visual_rng.randf_range(-1, 1)).normalized()
		var t := s.create_tween()
		t.set_parallel(true)
		# 位移不超过半格（14px）
		t.tween_property(s, "position",
			s.position + dir * _visual_rng.randf_range(6.0, 14.0), 0.12)
		t.tween_property(s, "modulate:a", 0.0, 0.12)
		t.chain().tween_callback(s.queue_free)


## 收益跳字：预算同屏 ≤2；超出并入最新一处重算金额（不新开）
func _fx_jump_text(pos: Vector2, text: String) -> void:
	if _jump_texts.size() >= 2:
		var last: Node2D = _jump_texts[_jump_texts.size() - 1]
		if is_instance_valid(last):
			var amount: int = int(last.get_meta("amount", 0)) + _parse_amount(text)
			last.set_meta("amount", amount)
			var lbl: Label = last.get_meta("label")
			lbl.text = "+%d" % amount
			# 重开淡出（旧 tween 绑在被并入节点上，先杀）
			last.get_meta("tween").kill()
			var t := last.create_tween()
			last.set_meta("tween", t)
			t.tween_property(last, "modulate:a", 0.0, 0.6)
			t.tween_callback(func():
				_jump_texts.erase(last)
				last.queue_free())
			return
	var node := Node2D.new()
	node.name = _name("JumpText")
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", GOLD)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.position = Vector2(6, -8)  # 金币图标右侧
	node.add_child(lbl)
	node.position = pos
	add_child(node)
	node.set_meta("amount", _parse_amount(text))
	node.set_meta("label", lbl)
	var t := node.create_tween()
	node.set_meta("tween", t)
	t.set_parallel(true)
	t.tween_property(node, "position:y", pos.y - 12.0, 0.45)
	t.tween_property(node, "modulate:a", 0.0, 0.45)
	t.chain().tween_callback(func():
		_jump_texts.erase(node)
		node.queue_free())
	_jump_texts.append(node)


## 胜利结算演出：盘面任意位置跳"+N"金色飘字（复用 _fx_jump_text 的样式与合并）
func fx_gain_text(pos: Vector2, text: String) -> void:
	_fx_jump_text(pos, text)


func _fly_coin(from: Vector2, to: Vector2, delay_s: float) -> void:
	var s := Sprite2D.new()
	s.name = _name("FlyCoin")
	s.texture = COIN_TEX
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.position = from
	add_child(s)
	var t := s.create_tween()
	t.tween_interval(delay_s)
	# 二次贝塞尔：中点抬高 24px，tween_method 逐帧取点
	var peak := (from + to) / 2.0 + Vector2(0, -24)
	t.tween_method(
		func(k: float):
			var a: Vector2 = from.lerp(peak, k)
			var b: Vector2 = peak.lerp(to, k)
			s.position = a.lerp(b, k)
			s.scale = Vector2.ONE * (1.0 - 0.35 * k),
		0.0, 1.0, 0.4)
	t.tween_callback(s.queue_free)


func _frame(sheet: Texture2D, frame: int, fw: int, fh: int) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = sheet
	at.region = Rect2(frame * fw, 0, fw, fh)
	return at


func _parse_amount(text: String) -> int:
	return int(text.trim_prefix("+"))
