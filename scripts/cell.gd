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
var is_base: bool = false        # 基地建筑
var is_vein: bool = false        # 矿脉
var vein_resources: int = 0      # 矿脉剩余资源

# ---- L4 虫害三状态（独立状态位，不碰雷位数字真值，设计 §5「⑥ 合规」）----
var is_webbed: bool = false     # 网=显示遮罩：盖住已开数字（玩家与机器人同盲，Q7）
var is_locked: bool = false     # 锁=交互阻断：谁都开不了也标不了（旗不可撤直到清锁，Q6）
var is_slimed: bool = false     # 黏液=速度修正：3×3 内机器人间隔 ×2，不阻断开/标
var is_confirmed_mine: bool = false  # 探测「确认雷」：机器人视同旗、不计分、穿锁

# ---- L5 Boss 关状态（设计 §5.2 / 实施计划 WP4，仍不碰真值）----
var is_on_fire: bool = false    # 火=通路阻断：机器人禁入，8s 退散，点击整片熄灭
var bomb_masked: bool = false   # 炸弹压格=显示遮罩：数字被挡（口径同网，玩家与机器人同盲）
var path_blockers: int = 0      # 通路阻断计数（火/触手 +1/-1）：is_walkable 判定，0=不阻断

# ---- 化石（2×2 永久多格障碍；调研 §4 定调：纯难度件，不可清除，透明口径不改数字）----
var is_fossil: bool = false                 # 永久占位：不可开/不可标/机器人虫子皆不可入
var fossil_origin: Vector2i = Vector2i(-9, -9)  # 所属 2×2 化石左上原点（贴图取象限用）

# 信号
signal cell_left_clicked(cell: Cell)
signal cell_right_clicked(cell: Cell)
signal cell_double_clicked(cell: Cell)
signal cell_state_changed(cell: Cell)
## 障碍被清除（玩家点清/保安射清）：kind = "web"/"lock"/"slime"，埋点用
signal cell_obstacle_cleared(cell: Cell, kind: String, by_actor: String)

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

# ---- 视觉素材 ----
# 岩壁（未开格）：无缝纹理 336px = 12 格周期；相邻格按坐标定位切块 → 整片连续
# 风格 8 种：A1-A4 连体岩壁 / B1-B4 碎石泥土（Grid.wall_style 配置，章节可换）
var wall_style: String = "V2"
const WALL_GRID := 12
const WALL_TILE_PX := 28

# 洞底（已开格）：默认暗沙；有配套 floor_<风格> 时自动跟随（如 D 系主题套）
const FLOOR_DEFAULT := preload("res://visual_v2/runtime/tiles/floor_V2.png")
const FLOOR_GRID := 12
const FLOOR_TILE_PX := 28

# 挖开边缘碎裂条（中性色，配所有岩壁风格）
const EDGE_T := preload("res://visual_v2/runtime/tiles/wall_edge_T.png")
const EDGE_B := preload("res://visual_v2/runtime/tiles/wall_edge_B.png")
const EDGE_L := preload("res://visual_v2/runtime/tiles/wall_edge_L.png")
const EDGE_R := preload("res://visual_v2/runtime/tiles/wall_edge_R.png")
const SPECIAL_BASE := preload("res://visual_v2/runtime/completion/tiles/special_base.png")
const SPECIAL_FLAG := preload("res://visual_v2/runtime/completion/tiles/special_flag.png")
const SPECIAL_VEIN := preload("res://visual_v2/runtime/completion/tiles/special_vein.png")
const SPECIAL_COLLAPSE := preload("res://visual_v2/runtime/completion/tiles/special_collapse.png")
const OVERLAY_LOCK := preload("res://visual_v2/runtime/completion/tiles/overlays/lock.png")
const OVERLAY_WEB := preload("res://visual_v2/runtime/completion/tiles/overlays/web.png")
const OVERLAY_SLIME_WALL := preload("res://visual_v2/runtime/completion/tiles/overlays/slime_wall.png")
const OVERLAY_SLIME_FLOOR := preload("res://visual_v2/runtime/completion/tiles/overlays/slime_floor.png")
const OVERLAY_CONFIRMED := preload("res://visual_v2/runtime/completion/tiles/overlays/confirmed.png")
const OVERLAY_FIRE := preload("res://visual_v2/runtime/completion/tiles/overlays/fire_0.png")
const OVERLAY_FIRE_1 := preload("res://visual_v2/runtime/completion/tiles/overlays/fire_1.png")
const OVERLAY_FIRE_LOW := preload("res://visual_v2/runtime/completion/tiles/overlays/fire_low.png")
# 化石 2×2 整图四象限（tmp/make_fossil.py 生成；序=行*2+列，配 _fossil_texture()）
const OVERLAY_FOSSIL := [
	preload("res://visual_v2/runtime/completion/tiles/overlays/fossil_tl.png"),
	preload("res://visual_v2/runtime/completion/tiles/overlays/fossil_tr.png"),
	preload("res://visual_v2/runtime/completion/tiles/overlays/fossil_bl.png"),
	preload("res://visual_v2/runtime/completion/tiles/overlays/fossil_br.png"),
]

# 洞壁生态装饰（E 系主题套）：有 deco_<风格>_sheet 的风格在未开岩壁随机点缀
const DECO_GRID := 4          # sheet 4x2
const DECO_TILE_PX := 28
const DECO_DENSITY := 0.10

var _floor_atlas: AtlasTexture
var _deco_tex: TextureRect = null
var _obstacle_mark: TextureRect = null
var _slime_overlay: TextureRect = null
var _fire_frame := 0

# 双击检测
var _last_click_time: float = 0.0
const DOUBLE_CLICK_THRESHOLD := 0.35

# 左右键同按（和弦手势）：第二键落下时并成一次和弦触发，本击不再走单键分支
var _gesture_open_stamp: float = -1.0  # 本次按持中左键刚掀开此格的时刻（同手势防连吃 2 CD）
var _chord_shake_pending := false      # 和弦震波标记：波前到达翻开的瞬间横震一下
var _shake_tween: Tween = null

# 扩散波纹动画：逻辑已开（is_opened=true）但视觉保持岩壁，波前到达才翻开
# 窗口期内寻路/计分/胜负判定全部读逻辑状态，不受视觉延迟影响
var _reveal_pending := false
var _wall_open_fx: Control = null
var _wall_open_tween: Tween = null


func _ready() -> void:
	_setup_wall()
	_setup_floor()
	_setup_deco()
	_setup_obstacle_mark()
	refresh_visual()
	refresh_wall_edges()
	# 本格状态变化后，刷新周围格子的岩壁边缘描边
	cell_state_changed.connect(_on_state_changed_refresh_edges)
	input_event.connect(_on_input_event)


## L4/L5 障碍覆盖层：28px 透明贴片，与棋盘原生格像素对齐。
func _setup_obstacle_mark() -> void:
	_slime_overlay = TextureRect.new()
	_slime_overlay.name = "SlimeOverlay"
	_configure_overlay(_slime_overlay)
	_obstacle_mark = TextureRect.new()
	_obstacle_mark.name = "ObstacleMark"
	_configure_overlay(_obstacle_mark)


func _configure_overlay(node: TextureRect) -> void:
	node.offset_left = -14
	node.offset_top = -14
	node.offset_right = 14
	node.offset_bottom = 14
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(node)


func set_fire_frame(frame: int) -> void:
	if not is_on_fire or _fire_frame == frame:
		return
	_fire_frame = frame
	if _obstacle_mark != null:
		_obstacle_mark.texture = _fire_texture()


func _fire_texture() -> Texture2D:
	return OVERLAY_FIRE_LOW if _fire_frame == 2 else (OVERLAY_FIRE_1 if _fire_frame == 1 else OVERLAY_FIRE)


## 化石象限贴图：按本格在 2×2 中的位置取四分之一（行*2+列）
func _fossil_texture() -> Texture2D:
	var dx: int = clampi(coord.x - fossil_origin.x, 0, 1)
	var dy: int = clampi(coord.y - fossil_origin.y, 0, 1)
	return OVERLAY_FOSSIL[dy * 2 + dx]


func _setup_wall() -> void:
	# 按坐标确定性取块（非随机）：相邻格取相邻区块 → 岩壁跨格连成一体
	var sheet: Texture2D = load("res://visual_v2/runtime/tiles/wall_%s.png" % wall_style)
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(
		(coord.x % WALL_GRID) * WALL_TILE_PX,
		(coord.y % WALL_GRID) * WALL_TILE_PX,
		WALL_TILE_PX, WALL_TILE_PX)
	atlas.filter_clip = true
	var wall: TextureRect = $WallTex
	wall.texture = atlas
	wall.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	$WallEdgeTop.texture = EDGE_T
	$WallEdgeBottom.texture = EDGE_B
	$WallEdgeLeft.texture = EDGE_L
	$WallEdgeRight.texture = EDGE_R
	for edge in [$WallEdgeTop, $WallEdgeBottom, $WallEdgeLeft, $WallEdgeRight]:
		edge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		edge.visible = false


func _setup_floor() -> void:
	# 每个格子创建时随机锁定一块洞底，翻开后显示（避免每次刷新跳动）
	# 风格配套：优先 floor_<wall_style>（D 系主题套），否则用默认暗沙
	# exists() 先探测：load() 对不存在路径会刷 ERROR 日志
	var sheet: Texture2D = null
	var path := "res://visual_v2/runtime/tiles/floor_%s.png" % wall_style
	if ResourceLoader.exists(path):
		sheet = load(path)
	if sheet == null:
		sheet = FLOOR_DEFAULT
	_floor_atlas = AtlasTexture.new()
	_floor_atlas.atlas = sheet
	var col := randi() % FLOOR_GRID
	var row := randi() % FLOOR_GRID
	_floor_atlas.region = Rect2(col * FLOOR_TILE_PX, row * FLOOR_TILE_PX, FLOOR_TILE_PX, FLOOR_TILE_PX)
	_floor_atlas.filter_clip = true
	var floor_tex: TextureRect = $FloorTex
	floor_tex.texture = _floor_atlas
	floor_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	floor_tex.visible = false


## 主题生态装饰：仅当风格配了 deco_<风格>_sheet（E 系）才散布；
## A-D 系无专属表 → 保持原视觉不变
func _setup_deco() -> void:
	var path := "res://visual_v2/runtime/tiles/deco_%s_sheet.png" % wall_style
	if not ResourceLoader.exists(path):
		return
	if randf() > DECO_DENSITY:
		return
	var atlas := AtlasTexture.new()
	atlas.atlas = load(path)
	var idx := randi() % (DECO_GRID * 2)
	atlas.region = Rect2(
		(idx % DECO_GRID) * DECO_TILE_PX,
		(idx / DECO_GRID) * DECO_TILE_PX,
		DECO_TILE_PX, DECO_TILE_PX)
	atlas.filter_clip = true
	_deco_tex = TextureRect.new()
	_deco_tex.name = "WallDeco"  # 明确命名：避免 get_children 遍历误匹配
	_deco_tex.texture = atlas
	_deco_tex.expand_mode = 1  # AtlasTexture 必须显式（默认 KEEP_SIZE 会把控件撑到纹理尺寸）
	_deco_tex.position = Vector2(-14, -14)
	_deco_tex.size = Vector2(DECO_TILE_PX, DECO_TILE_PX)
	_deco_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deco_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_deco_tex)


## 原地切换岩壁风格（调试键/章节主题用）：重建墙/洞底/装饰，不动局面
func apply_wall_style(style: String) -> void:
	wall_style = style
	_setup_wall()
	_setup_floor()
	if _deco_tex != null:
		_deco_tex.queue_free()
		_deco_tex = null
	_setup_deco()
	refresh_visual()


func _on_state_changed_refresh_edges(_cell: Cell) -> void:
	var g := get_parent()
	if g is Grid:
		g.refresh_edges_around(coord)


## 岩壁边缘：只在与"开侧"（已开格或地图外）交界的边显示碎裂描边
func refresh_wall_edges() -> void:
	if is_opened:
		$WallEdgeTop.visible = false
		$WallEdgeBottom.visible = false
		$WallEdgeLeft.visible = false
		$WallEdgeRight.visible = false
		return
	var g := get_parent()
	$WallEdgeTop.visible = _side_is_open_side(g, Vector2i(0, -1))
	$WallEdgeBottom.visible = _side_is_open_side(g, Vector2i(0, 1))
	$WallEdgeLeft.visible = _side_is_open_side(g, Vector2i(-1, 0))
	$WallEdgeRight.visible = _side_is_open_side(g, Vector2i(1, 0))


func _side_is_open_side(g: Node, dir: Vector2i) -> bool:
	if g is Grid:
		var n: Cell = g.get_cell(coord + dir)
		if n == null:
			return true  # 地图边界：也算洞壁外缘
		return n.is_opened  # 坍塌/基地/矿脉都置 is_opened，天然算开侧
	return false


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	# 左右键同按（和弦手势）：另一键已按住时本击是补齐的第二键，并成一次和弦，
	# 不再走左键开格/右键插旗的单键分支（防同一手势误触副动作）
	if (event.button_index == MOUSE_BUTTON_LEFT
			or event.button_index == MOUSE_BUTTON_RIGHT) \
			and _is_chord_gesture(event as InputEventMouseButton):
		_try_chord_gesture()
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		var was_open := is_opened
		var now: float = Time.get_ticks_msec() / 1000.0
		if now - _last_click_time < DOUBLE_CLICK_THRESHOLD:
			cell_double_clicked.emit(self)
			_last_click_time = 0.0
		else:
			cell_left_clicked.emit(self)
			_last_click_time = now
		# 左键在本按持里刚掀开此格：短时间内补右键不算和弦（同一手势防双吃 CD）
		if not was_open and is_opened:
			_gesture_open_stamp = now
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		cell_right_clicked.emit(self)


## 双键判定：本击落下时另一键也按住（button_mask 已含本击；再兜底查全局键态）
func _is_chord_gesture(event: InputEventMouseButton) -> bool:
	if event.button_mask & MOUSE_BUTTON_MASK_LEFT \
			and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		return true
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
		and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)


## 和弦手势入口：复用双击和弦管线（CD/预判门槛全同），落空由 Grid 摇头反馈
func _try_chord_gesture() -> void:
	# 同一手势里左键刚把此格从关闭掀开 → 不立刻续和弦（想吃连招请松键再来一次）
	if Time.get_ticks_msec() / 1000.0 - _gesture_open_stamp < 0.4:
		return
	_last_click_time = 0.0  # 不给后续双击检测留尾巴（防手势+双击接连双触发）
	cell_double_clicked.emit(self)


func open(by_actor: String) -> bool:
	# 返回 true 表示状态真的改变了
	if is_fossil:
		return false  # 化石=永久障碍：谁都开不了（无清除交互，纯难度件）
	if is_locked:
		return false  # 锁=交互阻断：谁都不能开（玩家/机器人/无人机一律拦）
	if is_opened or is_collapsed or is_flagged:
		return false
	if is_base:
		return false  # 基地格不可被开
	is_opened = true
	refresh_visual()
	return true


func become_base() -> void:
	is_base = true
	is_opened = true  # 基地视为已开（机器人可走）
	refresh_visual()


func become_vein(resources: int) -> void:
	is_vein = true
	vein_resources = resources
	is_opened = true  # 矿脉视为已开（机器人可走）
	is_flagged = false  # 取消旗子状态
	refresh_visual()


func deplete_vein() -> void:
	is_vein = false
	vein_resources = 0
	refresh_visual()


func toggle_flag() -> bool:
	if is_fossil:
		return false  # 化石上不能插旗（它也不是雷，标了必错）
	if is_locked:
		return false  # 锁同时拦插旗与撤旗（Q6：已插旗格被锁，旗不可撤直到清锁）
	if is_opened or is_collapsed:
		return false
	is_flagged = not is_flagged
	refresh_visual()
	if is_flagged:
		play_flag_plant()  # 旗面落地动画（灰尘由 Grid→EffectsLayer 出）
	return true


## 插旗落地：图标层下落约 8px + 小幅回弹（约 170ms），不动整格岩壁（设计稿 §3）
func play_flag_plant() -> void:
	var icon: TextureRect = $SpecialIcon
	var base_y: float = icon.position.y
	icon.pivot_offset = icon.size / 2.0
	icon.position.y = base_y - 8.0
	icon.scale = Vector2(1.0, 0.82)  # 压缩形态（sheet 帧序：压缩→回弹→静止）
	var t := icon.create_tween()
	t.tween_property(icon, "position:y", base_y, 0.10)
	t.tween_property(icon, "scale", Vector2(1.0, 1.1), 0.04)
	t.tween_property(icon, "scale", Vector2.ONE, 0.03)


# ---- L4 虫害障碍：apply 幂等（已有同类状态返回 false），clear 是玩家/保安共用入口 ----

func apply_web() -> bool:
	if is_webbed or not is_opened or is_base or is_vein or is_collapsed:
		return false  # 网只盖已开数字格（基地/矿脉/坍塌无数字可盖）
	is_webbed = true
	refresh_visual()
	return true


func apply_lock() -> bool:
	if is_locked or is_opened or is_base or is_vein or is_collapsed or is_fossil:
		return false  # 锁只锁关闭格；化石永久占位不可叠锁（叠了永远清不掉，纯视觉噪音）
	is_locked = true
	refresh_visual()
	return true


func apply_slime() -> bool:
	if is_slimed:
		return false
	is_slimed = true
	refresh_visual()
	return true


func clear_web(by_actor: String) -> bool:
	if not is_webbed:
		return false
	is_webbed = false
	refresh_visual()
	cell_obstacle_cleared.emit(self, "web", by_actor)
	return true


func clear_lock(by_actor: String) -> bool:
	if not is_locked:
		return false
	is_locked = false
	refresh_visual()
	cell_obstacle_cleared.emit(self, "lock", by_actor)
	return true


func clear_slime(by_actor: String) -> bool:
	if not is_slimed:
		return false
	is_slimed = false
	refresh_visual()
	cell_obstacle_cleared.emit(self, "slime", by_actor)
	return true


## 点击分流用：本格是否叠着可清除的障碍（锁未开/网已开/黏液任意）
func has_obstacle() -> bool:
	if is_locked and not is_opened:
		return true
	if is_webbed and is_opened:
		return true
	return is_slimed


## 火区点燃（计时/连通组在 BossManager；格子只管状态+视觉+通路计数）
## 点燃顺带烧掉本格黏液（「火清黏液」组合，设计 §5）
func ignite_fire() -> void:
	if is_on_fire:
		return
	is_on_fire = true
	_fire_frame = 0
	path_blockers += 1
	if is_slimed:
		clear_slime("fire")
	refresh_visual()


func fire_out() -> void:
	if not is_on_fire:
		return
	is_on_fire = false
	path_blockers -= 1
	refresh_visual()


## 炸弹压格遮罩（Bomb 实体落格 set / 离格或爆炸 clear）
func set_bomb_masked(v: bool) -> void:
	if bomb_masked == v:
		return
	bomb_masked = v
	refresh_visual()


## 探测「确认雷」：不 open 不 flag、绕过锁（锁只拦交互，情报可穿透，设计 §5）
func confirm_mine() -> void:
	if is_confirmed_mine:
		return
	is_confirmed_mine = true
	refresh_visual()


func collapse() -> void:
	is_collapsed = true
	is_opened = true  # 视为已开，机器人可走
	refresh_visual()
	_play_collapse_flicker()


# ---- 动效 ----

# ---- 扩散波纹翻开（Grid._schedule_reveal_wave 统一调度）----

## 视觉延迟翻开：保持岩壁 delay 秒后碎落；delay<=0 立即翻
func defer_visual_reveal(delay: float) -> void:
	if delay <= 0.0:
		play_reveal()
		return
	_reveal_pending = true
	refresh_visual()  # 走 pending 分支：切回岩壁视觉（同帧内完成，无闪烁）
	var t := create_tween()
	t.tween_interval(delay)
	t.tween_callback(_on_reveal_reached)


func _on_reveal_reached() -> void:
	_reveal_pending = false
	refresh_visual()
	# 期间被基地/矿脉/坍塌接管的格不再碎落（它们有自己的表现）
	if not (is_base or is_vein or is_collapsed):
		_play_wall_open()
		_play_chord_shake_if_pending()


## 立即翻开 + 岩壁碎落（波纹中心格 / 无延迟路径）
func play_reveal() -> void:
	_reveal_pending = false
	refresh_visual()
	_play_wall_open()
	_play_chord_shake_if_pending()


## 原墙纹理分成四块，轻落淡出；只动覆盖层，数字与碰撞区留在原位。
func _play_wall_open() -> void:
	if not is_opened or is_base or is_vein or is_collapsed:
		return
	_clear_wall_open_fx()
	var wall: TextureRect = $WallTex
	var fx := Control.new()
	fx.name = "WallOpenFx"
	fx.position = wall.position
	fx.size = wall.size
	fx.clip_contents = true  # 碎块限制在本格，不能压到邻格数字。
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fx.z_index = 1
	add_child(fx)
	_wall_open_fx = fx
	var source: Texture2D = wall.texture
	var region := Rect2(Vector2.ZERO, source.get_size())
	if source is AtlasTexture:
		region = source.region
		source = source.atlas
	var half := region.size / 2.0
	_wall_open_tween = fx.create_tween().set_parallel(true)
	for i in 4:
		var quadrant := Vector2(i % 2, int(i / 2))
		var texture := AtlasTexture.new()
		texture.atlas = source
		texture.region = Rect2(region.position + quadrant * half, half)
		texture.filter_clip = true
		var piece := Sprite2D.new()
		piece.name = "WallQuarter%d" % i
		piece.texture = texture
		piece.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		piece.scale = wall.size / region.size
		var start := (quadrant + Vector2(0.5, 0.5)) * fx.size / 2.0
		piece.position = start
		fx.add_child(piece)
		var fall := Vector2(-2 if i % 2 == 0 else 2, 1 if i < 2 else 3)
		_wall_open_tween.tween_method(func(k: float):
			piece.position = start + (fall * k).round()
			piece.self_modulate.a = 1.0 - k,
			0.0, 1.0, 0.22)
	if _deco_tex != null:
		var deco := Sprite2D.new()
		deco.name = "WallDecoCover"
		deco.texture = _deco_tex.texture
		deco.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		deco.position = _deco_tex.position - wall.position + _deco_tex.size / 2.0
		fx.add_child(deco)
		_wall_open_tween.tween_property(deco, "self_modulate:a", 0.0, 0.22)
	_wall_open_tween.chain().tween_callback(func():
		if _wall_open_fx == fx:
			_wall_open_fx = null
		fx.queue_free())


func _clear_wall_open_fx() -> void:
	if _wall_open_tween != null and _wall_open_tween.is_valid():
		_wall_open_tween.kill()
	_wall_open_tween = null
	if is_instance_valid(_wall_open_fx):
		_wall_open_fx.queue_free()
	_wall_open_fx = null


# ---- 和弦震波（左右键同按/双击和弦触发；Grid.chord 排错峰次序）----

## 被和弦波前掀到的格：翻开瞬间横震一下（标记由 Grid 设置，翻开时消费）
func mark_chord_shake() -> void:
	_chord_shake_pending = true


## 开格失败（锁拦截/踩雷坍塌）：撤回震波标记，防悬空标记日后误震
func clear_chord_shake() -> void:
	_chord_shake_pending = false


func _play_chord_shake_if_pending() -> void:
	if _chord_shake_pending:
		_chord_shake_pending = false
		play_chord_shake()


## 命中的邻格横震：衰减正弦、round 到整像素（±2→±1px），贴图不糊
func play_chord_shake() -> void:
	_run_shake(2.5, 0.22, 1.9)


## 和弦落空：中心格摇头（不生效反馈，不吃 CD）
func play_chord_deny() -> void:
	_run_shake(2.0, 0.26, 2.2)


func _home_position() -> Vector2:
	return Vector2(
		coord.x * cell_size + cell_size / 2.0,
		coord.y * cell_size + cell_size / 2.0)


func _run_shake(cycles: float, dur: float, amp: float) -> void:
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	var home := _home_position()
	position = home  # 重放先归位，保证像素对齐
	var step := func(t: float) -> void:
		position = home + Vector2(round(sin(t * cycles * TAU) * amp * (1.0 - t)), 0.0)
	_shake_tween = create_tween()
	_shake_tween.tween_method(step, 0.0, 1.0, dur)


## 和弦命中：中心数字格短促弹胀（触发源锚点，给视线一个落点）
func play_chord_pulse() -> void:
	var t := create_tween()
	t.tween_property(self, "scale", Vector2(1.12, 1.12), 0.07)
	t.tween_property(self, "scale", Vector2.ONE, 0.10)


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
	if is_base or is_vein or is_collapsed:
		_clear_wall_open_fx()
	var bg: ColorRect = $Background
	var lbl: Label = $Label
	var special: TextureRect = $SpecialIcon
	var show_wall := false
	var show_floor := false
	special.texture = null
	if _reveal_pending and is_opened and not is_base and not is_vein and not is_collapsed:
		# 扩散波纹窗口：逻辑已开但波前未到——视觉保持岩壁，由 Grid 的延迟调度翻开
		show_wall = true
		bg.color = Color(0.20, 0.21, 0.25)
		lbl.text = ""
	elif is_base:
		show_floor = true
		bg.color = Color(0.17, 0.16, 0.15)
		lbl.text = ""
		special.texture = SPECIAL_BASE
	elif is_vein:
		show_floor = true
		bg.color = Color(0.22, 0.18, 0.10)
		lbl.text = ""
		special.texture = SPECIAL_VEIN
	elif is_collapsed:
		show_floor = true
		bg.color = Color(0.22, 0.07, 0.07)
		lbl.text = ""
		special.texture = SPECIAL_COLLAPSE
	elif is_flagged:
		# 旗格仍是未开岩壁：岩壁上插旗
		show_wall = true
		bg.color = Color(0.20, 0.21, 0.25)
		lbl.text = ""
		special.texture = SPECIAL_FLAG
	elif is_opened:
		# 已开格：铺暗色洞底，数字叠在上面
		show_floor = true
		bg.color = Color(0.17, 0.14, 0.12)
		if adjacent_mines == 0:
			lbl.text = ""
		else:
			lbl.text = str(adjacent_mines)
			lbl.modulate = NUMBER_COLORS[adjacent_mines]
	else:
		# 未开格：连体岩壁
		show_wall = true
		bg.color = Color(0.20, 0.21, 0.25)
		lbl.text = ""
	$WallTex.visible = show_wall
	if _deco_tex != null:
		_deco_tex.visible = show_wall  # 装饰长在岩壁上，跟墙同步显隐
	$FloorTex.visible = show_floor
	special.visible = special.texture != null
	if not show_wall:
		refresh_wall_edges()  # 开侧格不显示描边，直接清掉
	# ---- L4 障碍覆盖（叠在基础视觉之上，黏液只染色不改表现）----
	if is_webbed or bomb_masked:
		# 网/炸弹盖数字：数字对玩家同样不可见（Q7「玩家与机器人同盲」）
		lbl.text = ""
	if _obstacle_mark != null:
		if is_fossil:
			# 化石置顶：与其他障碍互斥（不可叠锁/不预开/不web——铺设侧已保证）
			_obstacle_mark.texture = _fossil_texture()
		elif is_locked:
			_obstacle_mark.texture = OVERLAY_LOCK
		elif is_on_fire:
			_obstacle_mark.texture = _fire_texture()
		elif is_webbed:
			_obstacle_mark.texture = OVERLAY_WEB
		elif is_confirmed_mine and not is_opened:
			_obstacle_mark.texture = OVERLAY_CONFIRMED
		else:
			_obstacle_mark.texture = null
	if is_slimed:
		_slime_overlay.texture = OVERLAY_SLIME_FLOOR if is_opened else OVERLAY_SLIME_WALL
	else:
		_slime_overlay.texture = null
	if is_on_fire:
		bg.color = bg.color.lerp(Color(0.85, 0.30, 0.10), 0.55)  # 火：橙红炙烤
	cell_state_changed.emit(self)
