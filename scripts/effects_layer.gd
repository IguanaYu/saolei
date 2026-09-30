class_name EffectsLayer
extends Node2D
## 局内动效层：开格岩屑 / 收益跳字 / 插旗灰尘 / 卸货金光飞币
## 设计稿：docs/active/局内交互动效设计-v1.md
## 挂在 Grid 下（z=45，盖过格子与悬停层）；坐标与 Cell 同为 Grid 本地系
## 预算：同屏高亮跳字 ≤2 处、每处 ≤0.6s，超出并入最新一处（§频率与可读性）

const SHARD_SHEET := preload("res://visual_v2/runtime/fx/rock_shards_mask_sheet.png")
const GLINT_SHEET := preload("res://visual_v2/runtime/fx/gold_glint_sheet.png")
const FLAG_FINAL := preload("res://visual_v2/runtime/tiles/special_flag.png")
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


## 临时节点统一取名：Kind + 序号（如 JumpText007）
func _name(kind: String) -> StringName:
	_seq += 1
	return StringName("%s%04d" % [kind, _seq])


# ---- 开格（批次入口：单格/连锁由 Grid 的 cell_open_batch 驱动）----

## 单格：岩屑 +（仅玩家）+1 跳字；机器人只留轻岩屑；无人机全免
func fx_open_single(cell: Cell, by_actor: String) -> void:
	_fx_shards(cell, 3 if by_actor == "player" else 2)
	if by_actor == "player":
		_fx_jump_text(cell.position + Vector2(10, -12), "+1")


## 连锁：≤4 处轻岩屑 + 起点汇总 +N（锚在起点；无人机不发）
func fx_open_chain(start_cell: Cell, chain: Array) -> void:
	var picked: Array = []
	var step: int = maxi(1, chain.size() / 4)
	for i in range(0, chain.size(), step):
		picked.append(chain[i])
		if picked.size() >= 4:
			break
	for c in picked:
		_fx_shards(c, 2)
	_fx_jump_text(start_cell.position + Vector2(10, -14),
		"+%d" % chain.size())


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


# ---- 清理 ----

## 重开/切关时清空全部临时动效（由 Grid.init_empty_grid 调用）
func clear_all() -> void:
	for c in get_children():
		c.queue_free()
	_jump_texts.clear()


# ---- L5 Boss 关 ----

## 拔牙跳字：🦷 从处理格升起（牙数上涨的持续正反馈，设计 §5.3「进度感始终可见」）
func fx_tooth_pulled(world_pos: Vector2) -> void:
	var node := Node2D.new()
	node.name = _name("Tooth")
	var lbl := Label.new()
	lbl.text = "🦷"
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.position = Vector2(-9, -10)
	node.add_child(lbl)
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
		s.position = cell.position + Vector2(randf_range(-4, 4), randf_range(-4, 4))
		add_child(s)
		var dir := Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
		var t := s.create_tween()
		t.set_parallel(true)
		# 位移不超过半格（14px）
		t.tween_property(s, "position",
			s.position + dir * randf_range(6.0, 14.0), 0.12)
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
